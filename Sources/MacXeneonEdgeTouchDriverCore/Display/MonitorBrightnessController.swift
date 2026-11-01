import AppKit
import CoreGraphics
import Foundation

/// Fast policy/source sampling is independent of every monitor's hardware I/O.
final class MonitorBrightnessController {
    private final class NativeSession {
        let io = NativeMonitorBrightness()
        let queue = DispatchQueue(label: "wch.brightness-endpoint", qos: .userInitiated)
        let permit: MonitorBrightnessPermit
        var endpoint: NativeMonitorBrightness.Endpoint
        var work: MonitorBrightnessWork
        var readFailures = 0
        // Accessed only on the endpoint's hardware queue.
        var hardwareConnection: String?
        init(_ endpoint: NativeMonitorBrightness.Endpoint, connection: String) {
            self.endpoint = endpoint; work = MonitorBrightnessWork(connection: connection)
            permit = MonitorBrightnessPermit(connection)
        }
    }
    private struct VendorRequest {
        var level: Double
        var requestedAt: TimeInterval
        var sentAt: TimeInterval?
        var connection: String
    }
    private let queue = DispatchQueue(label: "wch.monitor-brightness", qos: .userInitiated)
    private let discoveryQueue = DispatchQueue(label: "wch.brightness-discovery", qos: .utility)
    private let discovery = NativeMonitorBrightness()
    private let native = NativeMonitorBrightness()
    private let displayLink: DisplayLinkMonitorBrightness
    private let vendor: UInt32?
    private let model: UInt32?
    private let profiles: [MonitorProfile]?
    private var routes: [MonitorBrightnessIdentity: MonitorProfile] = [:]
    private let url: URL
    private var policy: MonitorBrightnessPolicy
    private var persisted: MonitorBrightnessPreferences
    private var loadError: String?
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var registered = false
    private var sleeping = false
    private var stopped = false
    private var lastPoll: TimeInterval = -10
    private var lastDiscovery: TimeInterval = -10
    private var discoveryInFlight = false
    private var discoveryRevision: UInt64 = 0
    private var sourceLevel: Double?
    private var nativeCandidates: [NativeMonitorBrightness.Endpoint] = []
    private var nativeEndpoints: [NativeMonitorBrightness.Endpoint] = []
    private var displayLinkEndpoints: [DisplayLinkMonitorBrightness.Endpoint] = []
    private var samples: [MonitorBrightnessSample] = []
    private var sessions: [MonitorBrightnessIdentity: NativeSession] = [:]
    private var connections = MonitorBrightnessConnections()
    private var displayIDs: [MonitorBrightnessIdentity: UInt32] = [:]
    private var diagnostics = MonitorBrightnessDiagnostics()
    private var writeStatus: [MonitorBrightnessIdentity: String] = [:]
    private var pending: [MonitorBrightnessIdentity: VendorRequest] = [:]
    private var verifiedConnections: [MonitorBrightnessIdentity: String] = [:]

    init(configuration: DriverConfiguration, url: URL = defaultURL()) {
        vendor = configuration.display.vendorNumber; model = configuration.display.modelNumber
        profiles = configuration.monitors
        displayLink = DisplayLinkMonitorBrightness(profiles: configuration.monitors)
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
        displayLink.onUpdate = { [weak self] in self?.queue.async { [weak self] in
            guard let self, !self.stopped, !self.sleeping else { return }
            self.refreshRoutes(); self.checkAcknowledgements()
        } }
        registered = CGDisplayRegisterReconfigurationCallback(brightnessDisplayCallback, Unmanaged.passUnretained(self).toOpaque()) == .success
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep(true) })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep(false) })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.displaylink.DisplayLinkUserAgent" else { return }
                self?.queue.async { [weak self] in self?.vendorRestarted() }
            })
        }
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer; timer.resume()
            if !self.registered { self.event("observation-unavailable", detail: "Using periodic discovery", warning: true) }
        }
    }
    func stop() {
        if registered { CGDisplayRemoveReconfigurationCallback(brightnessDisplayCallback, Unmanaged.passUnretained(self).toOpaque()); registered = false }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true; self.timer?.cancel(); self.timer = nil; self.clearLiveState()
        }
    }
    private func clearLiveState() {
        discoveryRevision &+= 1
        sessions.values.forEach { $0.permit.update(nil) }; sessions.removeAll()
        policy.resetConnections(); pending.removeAll(); samples.removeAll()
        verifiedConnections.removeAll()
        nativeCandidates.removeAll(); nativeEndpoints.removeAll(); displayLinkEndpoints.removeAll()
        displayIDs.removeAll(); writeStatus.removeAll(); displayLink.stop()
        sourceLevel = nil; lastPoll = -10; lastDiscovery = -10
    }
    private func sleep(_ value: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.sleeping = value; self.clearLiveState()
            self.event(value ? "sleep" : "wake", detail: "Saved targets retained")
        }
    }
    /// Called both by video lifecycle callbacks and a physically paired USB loss.
    func connectionInterrupted(displayID: UInt32, reason: String) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.connections.interrupted(displayID); self.discoveryRevision &+= 1
            for (identity, id) in self.displayIDs where id == displayID {
                self.policy.invalidate(identity); self.pending.removeValue(forKey: identity)
                self.sessions[identity]?.permit.update(nil)
                self.writeStatus[identity] = "Connection changed; restoring the saved target when ready"
            }
            self.event("connection-change", detail: reason)
            self.lastDiscovery = -10
            self.displayLink.refresh(); self.refreshRoutes()
        }
    }
    fileprivate func displayChanged(_ displayID: UInt32, _ flags: CGDisplayChangeSummaryFlags) {
        guard flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) || flags.contains(.disabledFlag) else { return }
        connectionInterrupted(displayID: displayID, reason: "Display added, removed, enabled, or disabled")
    }
    private func vendorRestarted() {
        guard !stopped else { return }
        for (identity, id) in displayIDs where identity.transport == .displayLink {
            connections.interrupted(id); policy.invalidate(identity)
        }
        pending.removeAll(); displayLink.stop(); lastDiscovery = -10
        event("vendor-restart", transport: "displayLink", detail: "Refreshing endpoints and acknowledgements")
        refreshRoutes()
    }

    func request(_ command: String, reply: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { reply("{\"error\":\"Brightness service stopped\"}"); return }
            let now = ProcessInfo.processInfo.systemUptime
            var error: String?
            switch command {
            case "remember-brightness", "follow-brightness":
                self.loadError = nil
                self.policy.remember(self.samples)
                self.policy.preferences.followBuiltIn = command == "follow-brightness"
                self.policy.resetConnections()
                self.refreshRoutes()
                if command == "follow-brightness", let source = self.native.builtInLevel() {
                    self.sourceLevel = source
                    self.apply(self.policy.synchronize(source, samples: self.samples, now: now, including: self.followingIdentities()), now: now)
                }
            case "brightness-independent": self.policy.preferences.followBuiltIn = false
            case "brightness-off": self.policy.preferences.enabled = false; self.clearLiveState()
            case "sync-brightness":
                if self.samples.isEmpty { error = "No compatible monitors are available yet; wait for discovery, then try again." }
                else if let source = self.native.builtInLevel() {
                    self.loadError = nil; self.sourceLevel = source
                    self.apply(self.policy.synchronize(source, samples: self.samples, now: now, including: self.eligibleIdentities()), now: now)
                } else { error = "No active built-in brightness source. Use Set Monitor Brightness to adjust external displays." }
            case "restore-brightness": self.clearLiveState()
            default:
                if let level = MonitorBrightnessCommand.level(command) {
                    if self.samples.isEmpty { error = "No compatible monitors are available yet; wait for discovery, then try again." }
                    else {
                        self.loadError = nil
                        // An explicit WCH adjustment works without a built-in display.
                        let writes = self.policy.synchronize(level, samples: self.samples, now: now, including: self.eligibleIdentities(), trackSource: false)
                        self.refreshRoutes(); self.apply(writes, now: now)
                    }
                }
            }
            if command != "brightness-status" { self.lastDiscovery = -10; self.tick() }
            self.save()
            var result = self.status()
            if let error { result["error"] = error }
            let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            reply(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
        }
    }

    private func tick() {
        guard !stopped, !sleeping, loadError == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Discovery remains available while disabled so enabling controls can
        // identify monitors. Hardware reads/writes require the enabled preference.
        if now - lastDiscovery >= 2 { discover(now) }
        guard policy.preferences.enabled else { return }
        let source = native.builtInLevel()
        let changed = source.map { sourceLevel == nil || abs($0 - sourceLevel!) >= 0.005 } ?? false
        if changed || source == nil { sourceLevel = source }
        let polled = now - lastPoll >= 2
        if polled {
            lastPoll = now; displayLink.refresh(); refreshRoutes()
            for (identity, session) in sessions { session.work.requestRead(); pump(identity, session) }
        }
        if polled || changed {
            if changed { diagnostics.record("source-change", detail: "\(Int(((source ?? 0) * 100).rounded())) percent") }
            let unknown = samples.filter { policy.target(for: $0.identity) == nil }
            // A newly configured follower starts from the active source. Saved
            // targets still take precedence when an existing monitor reconnects.
            if let source {
                let followers = Set(unknown.filter { profile(for: $0.identity)?.follows(global: policy.preferences.followBuiltIn) ?? policy.preferences.followBuiltIn }.map(\.identity))
                if !followers.isEmpty {
                    apply(policy.synchronize(source, samples: unknown, now: now, including: followers, trackSource: false), now: now)
                }
            }
            policy.remember(unknown.filter { policy.target(for: $0.identity) == nil })
            apply(policy.step(samples, builtIn: source, now: now, following: followingIdentities()), now: now)
            save()
        } else { apply(policy.stepDisplayLink(samples, now: now), now: now) }
        checkAcknowledgements()
    }
    private func discover(_ now: TimeInterval) {
        guard !discoveryInFlight else { return }
        discoveryInFlight = true; lastDiscovery = now
        let revision = discoveryRevision
        let vendor = profiles == nil ? self.vendor : nil, model = profiles == nil ? self.model : nil
        discoveryQueue.async { [weak self] in
            guard let self else { return }
            let endpoints = self.discovery.endpoints(vendor: vendor, model: model)
            self.queue.async { [weak self] in
                guard let self else { return }
                self.discoveryInFlight = false
                guard !self.stopped, !self.sleeping, self.discoveryRevision == revision else { self.lastDiscovery = -10; return }
                self.nativeCandidates = endpoints; self.refreshRoutes(); self.displayLink.refresh()
            }
        }
    }
    private func refreshRoutes() {
        guard !stopped, !sleeping else { return }
        let displays = DisplayResolver.activeDisplaySnapshots().filter { !$0.builtIn && CGDisplayIsActive($0.displayID) != 0 }
        let resolved = MonitorProfileRouting.resolved(profiles ?? [], displays: displays)
        let needed = profiles.map { MonitorProfileRouting.needsDisplayLink($0, displays: displays, native: nativeCandidates.map(\.identity)) } ??
            (displays.filter { $0.vendorNumber == vendor && $0.modelNumber == model }.count > nativeCandidates.count)
        // Read-only discovery must also work before a DisplayLink-only setup
        // enables brightness. All writes remain gated by the enabled preference.
        displayLink.setActive(needed)
        let linked = displayLink.endpoints()
        if let profiles {
            routes = MonitorProfileRouting.selected(profiles, displays: displays, native: nativeCandidates.map(\.identity), displayLink: linked.map(\.identity))
            nativeEndpoints = nativeCandidates.filter { routes[$0.identity] != nil }
            displayLinkEndpoints = linked.filter { routes[$0.identity] != nil }
        } else {
            nativeEndpoints = nativeCandidates.filter { endpoint in displays.contains { $0.vendorNumber == endpoint.identity.vendor && $0.modelNumber == endpoint.identity.model } }
            displayLinkEndpoints = linked.filter { $0.identity.vendor == vendor && $0.identity.model == model }
        }
        var updated: [MonitorBrightnessSample] = []
        var ids: [MonitorBrightnessIdentity: UInt32] = [:]
        for endpoint in nativeEndpoints {
            let identity = endpoint.identity
            let id = routes[identity].flatMap { resolved[$0.displayUUID]?.displayID } ?? endpoint.displayID
            ids[identity] = id
            let connection = connections.token(endpoint.connection, display: id)
            let previous = samples.first { $0.identity == identity && $0.connection == connection }
            updated.append(MonitorBrightnessSample(identity: identity, connection: connection, level: previous?.level, observedAt: previous?.observedAt))
            if let session = sessions[identity] {
                if session.work.connection != connection {
                    session.endpoint = endpoint
                    session.work.reconnect(connection); session.permit.update(connection)
                    session.work.requestRead(); policy.invalidate(identity)
                    event("endpoint-connected", transport: "native", detail: "Refreshing hardware state")
                }
            } else if policy.preferences.enabled {
                let session = NativeSession(endpoint, connection: connection)
                session.work.requestRead(); sessions[identity] = session
                event("endpoint-connected", transport: "native", detail: "Refreshing hardware state")
            }
        }
        for endpoint in displayLinkEndpoints {
            let identity = endpoint.identity, id = UInt32(endpoint.connection) ?? 0
            ids[identity] = id
            let connection = connections.token(endpoint.connection + ":" + endpoint.persistentID, display: id)
            if !samples.contains(where: { $0.identity == identity && $0.connection == connection }) {
                policy.invalidate(identity); pending.removeValue(forKey: identity)
                event("endpoint-connected", transport: "displayLink", detail: "Saved target requires a fresh write")
            }
            updated.append(MonitorBrightnessSample(identity: identity, connection: connection, level: endpoint.reportedLevel))
        }
        let online = Set(updated.map(\.identity))
        for identity in Array(sessions.keys) where !online.contains(identity) {
            sessions.removeValue(forKey: identity)?.permit.update(nil); policy.invalidate(identity)
            event("endpoint-disconnected", transport: "native")
        }
        for previous in samples where !online.contains(previous.identity) {
            policy.invalidate(previous.identity); pending.removeValue(forKey: previous.identity)
            if previous.identity.transport == .displayLink { event("endpoint-disconnected", transport: "displayLink") }
        }
        pending = pending.filter { identity, request in updated.contains { $0.identity == identity && $0.connection == request.connection } }
        verifiedConnections = verifiedConnections.filter { online.contains($0.key) }
        samples = updated; displayIDs = ids
        if policy.preferences.enabled { for (identity, session) in sessions { pump(identity, session) } }
    }
    private func profile(for identity: MonitorBrightnessIdentity) -> MonitorProfile? {
        let matches = profiles?.filter { $0.accepts(identity) } ?? []
        return matches.count == 1 ? matches[0] : nil
    }
    private func eligibleIdentities() -> Set<MonitorBrightnessIdentity> {
        let known = policy.preferences.targets.map(\.identity) + samples.map(\.identity)
        return Set(known.filter { identity in
            profiles == nil ? identity.vendor == vendor && identity.model == model : profile(for: identity) != nil
        })
    }
    private func followingIdentities() -> Set<MonitorBrightnessIdentity> {
        Set(eligibleIdentities().filter { identity in
            profile(for: identity)?.follows(global: policy.preferences.followBuiltIn) ?? policy.preferences.followBuiltIn
        })
    }

    private func apply(_ writes: [MonitorBrightnessWrite], now: TimeInterval) {
        // Vendor dispatch never waits for native DDC or hardware readback.
        for write in writes {
            guard let sample = samples.first(where: { $0.identity == write.identity }) else { continue }
            switch write.identity.transport {
            case .native:
                guard let session = sessions[write.identity] else { continue }
                session.work.requestWrite(write.level, at: now); pump(write.identity, session)
            case .displayLink:
                guard let endpoint = displayLinkEndpoints.first(where: { $0.identity == write.identity }) else { continue }
                let sentAt = ProcessInfo.processInfo.systemUptime
                if displayLink.set(endpoint, level: write.level) {
                    pending[write.identity] = VendorRequest(level: write.level, requestedAt: now, sentAt: sentAt, connection: sample.connection)
                    writeStatus[write.identity] = "Waiting for DisplayLink acknowledgement"
                    diagnostics.record("write-sent", transport: "displayLink", detail: "\(Int((write.level * 100).rounded())) percent")
                } else {
                    writeStatus[write.identity] = "DisplayLink unavailable; saved target retained"
                    event("write-failed", transport: "displayLink", warning: true)
                }
            }
        }
    }
    private func pump(_ identity: MonitorBrightnessIdentity, _ session: NativeSession) {
        guard !stopped, !sleeping, policy.preferences.enabled,
              let ticket = session.work.next(at: ProcessInfo.processInfo.systemUptime) else { return }
        let endpoint = session.endpoint
        session.queue.async { [weak self, weak session] in
            guard let self, let session else { return }
            let permitted = { session.permit.accepts(ticket.connection) }
            if session.hardwareConnection != ticket.connection {
                session.io.resetConnection(); session.hardwareConnection = ticket.connection
            }
            var level: Double?
            var success = false
            if permitted() {
                if let target = ticket.level {
                    success = session.io.set(endpoint, level: target, mayWrite: permitted)
                    if success { level = target }
                } else { level = session.io.level(endpoint); success = level != nil }
            }
            let observed = level, succeeded = success, finished = ProcessInfo.processInfo.systemUptime
            self.queue.async { [weak self, weak session] in
                guard let self, let session, self.sessions[identity] === session else { return }
                let current = session.work.complete(ticket)
                if current, !self.stopped, !self.sleeping, self.policy.preferences.enabled,
                   let index = self.samples.firstIndex(where: { $0.identity == identity && $0.connection == ticket.connection }) {
                    self.samples[index].level = observed; self.samples[index].observedAt = finished
                    if ticket.level != nil {
                        self.writeStatus[identity] = succeeded ? "Hardware readback verified" : "Hardware write/readback failed; saved target retained"
                        self.event(succeeded ? "write-verified" : "write-failed", transport: "native",
                                   milliseconds: Int((finished - ticket.queuedAt) * 1000), warning: !succeeded,
                                   persistent: !succeeded || self.verifiedConnections[identity] != ticket.connection)
                        if succeeded { self.verifiedConnections[identity] = ticket.connection }
                    } else if !succeeded {
                        session.readFailures += 1
                        self.diagnostics.record("hardware-read-failed", transport: "native")
                        if session.readFailures == 3 { self.event("hardware-unresponsive", transport: "native", warning: true) }
                    } else {
                        if session.readFailures >= 3 { self.event("hardware-responsive", transport: "native") }
                        session.readFailures = 0
                    }
                } else { self.diagnostics.record("stale-result-discarded", transport: "native") }
                self.pump(identity, session)
            }
        }
    }
    private func checkAcknowledgements() {
        let now = ProcessInfo.processInfo.systemUptime
        for (identity, request) in Array(pending) {
            guard let sentAt = request.sentAt else { continue }
            if let endpoint = displayLinkEndpoints.first(where: { $0.identity == identity }),
               samples.contains(where: { $0.identity == identity && $0.connection == request.connection }),
               let result = displayLink.result(for: endpoint, after: sentAt), abs(result.0 - request.level) < 0.006 {
                if policy.acknowledge(identity, connection: request.connection, level: result.0,
                                      requestedAt: request.requestedAt, success: result.1 == 0) {
                    writeStatus[identity] = result.1 == 0 ? "DisplayLink acknowledged the setting" : "DisplayLink reported an error; saved target retained"
                    event(result.1 == 0 ? "write-acknowledged" : "write-failed", transport: "displayLink",
                          milliseconds: Int((now - request.requestedAt) * 1000), warning: result.1 != 0,
                          persistent: result.1 != 0 || verifiedConnections[identity] != request.connection)
                    if result.1 == 0 { verifiedConnections[identity] = request.connection }
                } else { diagnostics.record("stale-result-discarded", transport: "displayLink") }
                pending.removeValue(forKey: identity)
            } else if now - sentAt >= 5 {
                writeStatus[identity] = "DisplayLink did not acknowledge the setting; bounded retry pending"
                event("acknowledgement-timeout", transport: "displayLink", warning: true)
                pending.removeValue(forKey: identity)
            }
        }
    }
    private func event(_ name: String, transport: String = "all", detail: String = "", milliseconds: Int? = nil,
                       warning: Bool = false, persistent: Bool = true) {
        diagnostics.record(name, transport: transport, detail: detail, milliseconds: milliseconds)
        if persistent { DriverLoggers.log(warning ? .warning : .notice, category: .display, "Brightness \(transport): \(name). \(detail)") }
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
        let eligible = eligibleIdentities()
        let monitors: [[String: Any]] = policy.preferences.targets.filter { eligible.contains($0.identity) }.map { target in
            let live = samples.first { $0.identity == target.identity }
            var item: [String: Any] = ["name": profile(for: target.identity)?.name ?? target.identity.name, "transport": target.identity.transport.rawValue,
                "followsMacBook": followingIdentities().contains(target.identity),
                "rememberedPercent": Int((target.level * 100).rounded()), "connected": live != nil,
                "restoring": policy.restoring(target.identity), "restoreFailed": policy.failed(target.identity),
                "lastWrite": writeStatus[target.identity] ?? "No write this session",
                "physicalButtonsReadable": target.identity.transport == .native]
            if let level = live?.level { item["reportedPercent"] = Int((level * 100).rounded()) }
            if let ticket = sessions[target.identity]?.work.inFlight {
                item["hardwareBusyMilliseconds"] = Int(max(0, ProcessInfo.processInfo.systemUptime - ticket.queuedAt) * 1000)
            }
            return item
        }
        var result: [String: Any] = ["enabled": policy.preferences.enabled, "followBuiltIn": policy.preferences.followBuiltIn,
            "monitors": monitors,
            "status": loadError ?? (policy.preferences.enabled ? (followingIdentities().isEmpty ? "Remembering independent monitor brightness" : "Following MacBook brightness changes on selected monitors") : "Brightness control is off")]
        result["nativeBackend"] = NativeMonitorBrightness.backend
        result["diagnostics"] = diagnostics.object
        result["sourceAvailable"] = native.builtInLevel() != nil
        if loadError == nil, policy.preferences.enabled, native.builtInLevel() == nil {
            result["status"] = "No active built-in brightness source; remembering external monitor levels"
        }
        if !displayLinkEndpoints.isEmpty {
            result["displayLinkNote"] = "DisplayLink's reported level is cached. Reconnect restores WCH's saved level; physical-button overrides cannot be remembered."
        }
        if let level = native.builtInLevel() { result["builtInPercent"] = Int((level * 100).rounded()) }
        if let profiles {
            let displays = DisplayResolver.activeDisplaySnapshots()
            let resolved = MonitorProfileRouting.resolved(profiles, displays: displays)
            result["profiles"] = profiles.map { profile -> [String: Any] in
                ["name": profile.name, "connected": resolved[profile.displayUUID] != nil,
                 "touchEnabled": profile.touchEnabled, "brightnessConnection": profile.brightnessConnection.rawValue,
                 "brightnessBehavior": profile.brightnessBehavior.rawValue,
                 "activeTransport": routes.first { $0.value == profile }?.key.transport.rawValue ?? "unavailable"]
            }
        }
        if let loadError { result["error"] = loadError }
        return result
    }
}

private func brightnessDisplayCallback(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<MonitorBrightnessController>.fromOpaque(context).takeUnretainedValue().displayChanged(display, flags)
}
