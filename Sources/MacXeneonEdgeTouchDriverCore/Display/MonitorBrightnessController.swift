import AppKit
import Foundation

/// Brightness I/O never shares the HID/gesture queue or blocks AppKit.
final class MonitorBrightnessController {
    private let queue = DispatchQueue(label: "wch.monitor-brightness", qos: .utility)
    private let native = NativeMonitorBrightness()
    private let displayLink: DisplayLinkMonitorBrightness
    private let vendor: UInt32?
    private let model: UInt32?
    private let url: URL
    private var policy: MonitorBrightnessPolicy
    private var persisted: MonitorBrightnessPreferences
    private var loadError: String?
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var stopped = false
    private var lastPoll: TimeInterval = -10
    private var sourceLevel: Double?
    private var candidateSource: Double?
    private var sourceChangedAt: TimeInterval = 0
    private var sourceStartedAt: TimeInterval = 0
    private var nativeEndpoints: [NativeMonitorBrightness.Endpoint] = []
    private var displayLinkEndpoints: [DisplayLinkMonitorBrightness.Endpoint] = []
    private var samples: [MonitorBrightnessSample] = []
    private var writeStatus: [MonitorBrightnessIdentity: String] = [:]
    private var pending: [MonitorBrightnessIdentity: (Double, TimeInterval)] = [:]

    init(configuration: DriverConfiguration, url: URL = defaultURL()) {
        vendor = configuration.display.vendorNumber; model = configuration.display.modelNumber
        displayLink = DisplayLinkMonitorBrightness(vendor: vendor, model: model)
        self.url = url
        var value = MonitorBrightnessPreferences()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard data.count < 65_536 else { throw CocoaError(.fileReadCorruptFile) }
                value = try JSONDecoder().decode(MonitorBrightnessPreferences.self, from: data)
                guard value.isValid else { throw CocoaError(.fileReadCorruptFile) }
            } catch {
                value = MonitorBrightnessPreferences()
                loadError = "Saved brightness could not be read. Re-enable brightness from the WCH menu to replace it."
            }
        }
        policy = MonitorBrightnessPolicy(preferences: value); persisted = value
    }

    static func defaultURL() -> URL { DriverConfiguration.defaultConfigURL().deletingLastPathComponent().appendingPathComponent("brightness.json") }

    func start() {
        displayLink.onUpdate = { [weak self] in self?.queue.async { [weak self] in self?.checkAcknowledgements() } }
        displayLink.start()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep(true) })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep(false) })
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: .milliseconds(250), leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer; timer.resume()
        }
    }
    func stop() {
        displayLink.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        queue.async { [weak self] in self?.stopped = true; self?.timer?.cancel(); self?.timer = nil }
    }
    private func sleep(_ value: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.sleeping = value
            self.policy.resetConnections(); self.lastPoll = -10
            self.sourceLevel = nil; self.candidateSource = nil; self.pending.removeAll()
            if !value { self.displayLink.refresh() }
        }
    }

    func request(_ command: String, reply: @escaping (String) -> Void) {
        displayLink.refresh()
        queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            guard let self, !self.stopped else { reply("{\"error\":\"Brightness service stopped\"}"); return }
            let now = ProcessInfo.processInfo.systemUptime
            self.poll(now)
            var error: String?
            switch command {
            case "remember-brightness", "follow-brightness":
                if self.samples.isEmpty { error = "No compatible monitors are available yet." }
                else {
                    self.loadError = nil
                    self.policy.remember(self.samples)
                    self.policy.preferences.followBuiltIn = command == "follow-brightness"
                    self.policy.resetConnections()
                    if command == "follow-brightness" {
                        if let source = self.native.builtInLevel() {
                            self.sourceLevel = source
                            self.apply(self.policy.synchronize(source, samples: self.samples, now: now), now: now)
                        } else { error = "The built-in brightness is unavailable; saved monitor levels are retained." }
                    }
                }
            case "brightness-independent": self.policy.preferences.followBuiltIn = false
            case "brightness-off": self.policy.preferences.enabled = false
            case "sync-brightness":
                if let source = self.native.builtInLevel() {
                    self.loadError = nil; self.sourceLevel = source
                    self.apply(self.policy.synchronize(source, samples: self.samples, now: now), now: now)
                } else { error = "The built-in brightness is unavailable." }
            case "restore-brightness": self.policy.resetConnections(); self.lastPoll = -10
            default: break
            }
            self.save()
            var result = self.status()
            if let error { result["error"] = error }
            let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            reply(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
        }
    }

    private func tick() {
        guard !stopped, !sleeping, loadError == nil, policy.preferences.enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let source = native.builtInLevel()
        var sourceSettled = false
        if let source {
            if sourceLevel == nil { sourceLevel = source; sourceSettled = true }
            else if abs(source - sourceLevel!) >= 0.005 {
                if candidateSource == nil { sourceStartedAt = now }
                if candidateSource == nil || abs(source - candidateSource!) >= 0.003 {
                    candidateSource = source; sourceChangedAt = now
                }
                if now - sourceChangedAt >= 0.25 || now - sourceStartedAt >= 0.8 {
                    sourceLevel = source; candidateSource = nil; sourceSettled = true
                }
            } else { candidateSource = nil }
        }
        let polled = now - lastPoll >= 2
        // Status requests may refresh samples too. They must not postpone this
        // policy cadence, or frequent diagnostics could starve override memory.
        if polled { poll(now); lastPoll = now }
        if polled || sourceSettled {
            apply(policy.step(samples, builtIn: sourceLevel, now: now), now: now)
            save()
        }
        checkAcknowledgements()
    }

    private func poll(_ now: TimeInterval) {
        displayLink.refresh()
        nativeEndpoints = native.endpoints(vendor: vendor, model: model)
        displayLinkEndpoints = displayLink.endpoints()
        samples = nativeEndpoints.map { MonitorBrightnessSample(identity: $0.identity, connection: $0.connection, level: native.level($0)) } +
            displayLinkEndpoints.map { MonitorBrightnessSample(identity: $0.identity, connection: $0.connection, level: $0.reportedLevel) }
    }

    private func apply(_ writes: [MonitorBrightnessWrite], now: TimeInterval) {
        for write in writes {
            switch write.identity.transport {
            case .native:
                guard let endpoint = nativeEndpoints.first(where: { $0.identity == write.identity }) else { continue }
                let success = native.set(endpoint, level: write.level)
                writeStatus[write.identity] = success ? "Hardware readback verified" : "Hardware write/readback failed; saved level retained"
            case .displayLink:
                guard let endpoint = displayLinkEndpoints.first(where: { $0.identity == write.identity }) else { continue }
                if displayLink.set(endpoint, level: write.level) {
                    pending[write.identity] = (write.level, now)
                    writeStatus[write.identity] = "Waiting for DisplayLink acknowledgement"
                } else { writeStatus[write.identity] = "DisplayLink unavailable; no change made" }
            }
        }
    }
    private func checkAcknowledgements() {
        let now = ProcessInfo.processInfo.systemUptime
        for (identity, request) in Array(pending) {
            if let endpoint = displayLinkEndpoints.first(where: { $0.identity == identity }),
               let result = displayLink.result(for: endpoint, after: request.1), abs(result.0 - request.0) < 0.006 {
                writeStatus[identity] = result.1 == 0 ? "DisplayLink acknowledged the setting" : "DisplayLink reported error \(result.1)"
                pending.removeValue(forKey: identity)
            } else if now - request.1 >= 5 {
                writeStatus[identity] = "DisplayLink did not acknowledge; no automatic retry"
                pending.removeValue(forKey: identity)
            }
        }
    }
    private func save() {
        guard policy.preferences != persisted, policy.preferences.isValid else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(policy.preferences).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            persisted = policy.preferences
        } catch { loadError = "Could not save monitor brightness: \(error.localizedDescription)" }
    }
    private func status() -> [String: Any] {
        let monitors: [[String: Any]] = policy.preferences.targets.map { target in
            let live = samples.first { $0.identity == target.identity }
            var item: [String: Any] = ["name": target.identity.name, "transport": target.identity.transport.rawValue,
                "rememberedPercent": Int((target.level * 100).rounded()), "connected": live != nil,
                "restoring": policy.restoring(target.identity), "restoreFailed": policy.failed(target.identity),
                "lastWrite": writeStatus[target.identity] ?? "No write this session",
                "physicalButtonsReadable": target.identity.transport == .native]
            if let level = live?.level { item["reportedPercent"] = Int((level * 100).rounded()) }
            return item
        }
        var result: [String: Any] = ["enabled": policy.preferences.enabled, "followBuiltIn": policy.preferences.followBuiltIn,
            "monitors": monitors,
            "status": loadError ?? (policy.preferences.enabled ? (policy.preferences.followBuiltIn ? "Following MacBook brightness changes" : "Remembering independent monitor brightness") : "Brightness control is off"),
            "displayLinkNote": "DisplayLink's reported level is cached. HDMI button overrides are not read live; reconnect keeps the monitor's own setting."]
        if let level = native.builtInLevel() { result["builtInPercent"] = Int((level * 100).rounded()) }
        if let loadError { result["error"] = loadError }
        return result
    }
}
