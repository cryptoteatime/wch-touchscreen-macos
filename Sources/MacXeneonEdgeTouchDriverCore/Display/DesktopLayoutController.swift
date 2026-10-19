import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Owns a docked snapshot independently of HID pairing and the gesture queue.
/// It freezes capture at display-change callbacks and while any saved screen is missing.
final class DesktopLayoutController {
    private let queue = DispatchQueue(label: "wch.desktop-layout", qos: .utility)
    private let signalLock = NSLock()
    private var revision: UInt64 = 0
    private var changedAt = ProcessInfo.processInfo.systemUptime
    private var sleeping = false
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var registered = false
    private var stopped = false
    private let platform = DesktopLayoutPlatform()
    private let enabled: Bool
    private let vendor: UInt32?
    private let model: UInt32?
    private let url: URL
    private var layout: DesktopLayout?
    private var policy: DesktopLayoutPolicy
    private var loadError: String?
    private var status = "Starting desktop layout memory"
    private var savedAt: Date?
    private var lastRestoreAt: Date?
    private var restorePasses = 0
    private var windowProgress = DesktopWindowRestoreProgress()
    private var lastWindowResult: [String: Int] = [:]

    init(configuration: DriverConfiguration, url: URL = defaultURL()) {
        enabled = configuration.rememberDesktopLayout
        vendor = configuration.display.vendorNumber
        model = configuration.display.modelNumber
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard data.count < 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                let value = try JSONDecoder().decode(DesktopLayout.self, from: data)
                guard value.isValid else { throw CocoaError(.fileReadCorruptFile) }
                layout = value
                savedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            } catch { loadError = "Saved layout could not be read; use Save Current Desktop Layout to replace it." }
        }
        policy = DesktopLayoutPolicy(hasSavedLayout: layout != nil)
    }

    static func defaultURL() -> URL { DriverConfiguration.defaultConfigURL().deletingLastPathComponent().appendingPathComponent("desktop-layout.json") }

    func start() {
        guard enabled else { status = "Desktop layout memory is off"; return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        registered = CGDisplayRegisterReconfigurationCallback(desktopLayoutDisplayCallback, context) == .success
        guard registered else { status = "Could not observe display changes; layout memory is paused"; return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleepChanged(true) })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.sleepChanged(false) })
        // Freeze before logout/restart closes windows, preserving the last desktop.
        observers.append(center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in self?.sleepChanged(true) })
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.signalLock.lock(); self.revision &+= 1; self.changedAt = ProcessInfo.processInfo.systemUptime; self.signalLock.unlock()
            })
        }
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 4, repeating: 2, leeway: .milliseconds(300))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        if registered { CGDisplayRemoveReconfigurationCallback(desktopLayoutDisplayCallback, Unmanaged.passUnretained(self).toOpaque()); registered = false }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        queue.async { [weak self] in self?.stopped = true; self?.timer?.cancel(); self?.timer = nil }
    }

    fileprivate func displayChanged(_ flags: CGDisplayChangeSummaryFlags) {
        signalLock.lock(); revision &+= 1; changedAt = ProcessInfo.processInfo.systemUptime; signalLock.unlock()
        let membership = flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) || flags.contains(.disabledFlag)
        queue.async { [weak self] in
            guard let self else { return }
            if membership {
                if !self.policy.needsRestore { self.restorePasses = 0 }
                self.windowProgress = DesktopWindowRestoreProgress()
                self.policy.membershipChanged()
            }
        }
    }

    private func sleepChanged(_ asleep: Bool) {
        signalLock.lock(); sleeping = asleep; revision &+= 1; changedAt = ProcessInfo.processInfo.systemUptime; signalLock.unlock()
        queue.async { [weak self] in
            self?.policy.membershipChanged(); self?.restorePasses = 0; self?.windowProgress = DesktopWindowRestoreProgress()
        }
    }

    private func stableRevision() -> UInt64? {
        signalLock.lock(); defer { signalLock.unlock() }
        guard !sleeping, ProcessInfo.processInfo.systemUptime - changedAt >= 3 else { return nil }
        return revision
    }

    private func stillCurrent(_ expected: UInt64) -> Bool {
        signalLock.lock(); defer { signalLock.unlock() }
        return revision == expected && !sleeping
    }

    func request(_ command: String, reply: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self else { reply("{\"error\":\"Layout service stopped\"}"); return }
            var error: String?
            if command != "layout-status" && !self.enabled { error = "Enable Remember monitor layout and app windows in Touch Settings first." }
            else if command == "save-layout" {
                if let revision = self.stableRevision() {
                    let screens = self.platform.screens()
                    if self.canLearn(screens) {
                        self.loadError = nil
                        if self.capture(screens, revision: revision) { self.policy.restored(); self.restorePasses = 0; self.windowProgress = DesktopWindowRestoreProgress() }
                        else { error = "The displays changed during capture; try again when they have settled." }
                    } else { error = "Connect both touchscreens before saving the desktop layout." }
                } else { error = "Wait a few seconds for the displays to settle, then save again." }
            } else if command == "restore-layout" {
                if self.layout != nil { self.policy.membershipChanged(); self.restorePasses = 0; self.windowProgress = DesktopWindowRestoreProgress(); self.tick() }
                else { error = "No saved desktop layout yet." }
            }
            var object = self.statusObject()
            if let error { object["error"] = error }
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            reply(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
        }
    }

    private func canLearn(_ screens: [DesktopScreen]) -> Bool {
        screens.contains(where: \.builtIn) && screens.filter { !$0.builtIn && $0.vendor == vendor && $0.model == model }.count >= 2 &&
        screens.allSatisfy { CGDisplayMirrorsDisplay($0.runtimeID) == kCGNullDirectDisplay }
    }

    private func tick() {
        guard enabled, registered, !stopped else { return }
        if let loadError { status = loadError; return }
        guard AXIsProcessTrusted() else { status = "Accessibility permission is unavailable; saved layout retained"; return }
        guard let revision = stableRevision() else { status = "Waiting for display changes to settle"; return }
        let screens = platform.screens()
        let matches = layout?.matches(screens)
        let action = policy.action(hasLayout: layout != nil, completeMatch: matches != nil, canLearn: canLearn(screens))
        switch action {
        case .wait:
            if policy.failed { return }
            status = layout == nil ? "Waiting for both touchscreens before saving" : "Saved layout retained; waiting for the same monitors"
        case .capture:
            _ = capture(screens, revision: revision)
        case .restore:
            guard let layout, let matches, stillCurrent(revision) else { return }
            guard !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  !CGEventSource.buttonState(.combinedSessionState, button: .right) else { status = "Waiting for the current drag to finish"; return }
            // Bound retries even when an OS function reports success without effect.
            if restorePasses >= 12 { policy.failed = true; status = "Restore paused: display configuration did not settle. Saved layout retained."; return }
            restorePasses += 1
            switch platform.configure(layout, matches: matches) {
            case .changed:
                status = "Restoring monitor orientation, resolution, and arrangement"
                signalLock.lock(); changedAt = ProcessInfo.processInfo.systemUptime; self.revision &+= 1; signalLock.unlock()
            case .unavailable(let reason):
                policy.restoreFailed()
                status = "\(reason) Saved layout retained\(policy.failed ? "; use Restore Saved Desktop Layout to retry." : "; will retry.")"
                log(status)
            case .ready:
                guard stillCurrent(revision) else { return }
                restorePasses = 0
                let now = ProcessInfo.processInfo.systemUptime
                windowProgress.begin(at: now)
                let result = platform.restoreWindows(layout, matches: matches, progress: &windowProgress)
                guard stillCurrent(revision) else { return }
                lastWindowResult = ["restored": result.restored, "pending": result.pending, "skipped": 0, "failed": result.failed]
                if result.pending > 0 && windowProgress.hasTimeRemaining(at: now) {
                    status = "Restored \(result.restored) windows; waiting for \(result.pending) saved windows to reopen (up to 3 minutes)"
                    return
                }
                lastWindowResult["skipped"] = result.pending
                lastWindowResult["pending"] = 0
                lastRestoreAt = Date()
                if result.failed > 0 {
                    policy.failed = true
                    status = "Monitors restored; \(result.failed) windows refused their saved size or position. Saved layout retained."
                } else {
                    policy.restored(); restorePasses = 0
                    status = "Desktop restored; tracking the connected layout"
                }
                log("\(status) Windows restored=\(result.restored), skipped=\(result.pending), failed=\(result.failed).")
            }
        }
    }

    @discardableResult private func capture(_ screens: [DesktopScreen], revision: UInt64) -> Bool {
        guard canLearn(screens), AXIsProcessTrusted() else { return false }
        let windows = platform.windows(on: screens).map(\.saved)
        guard stillCurrent(revision), screens == platform.screens() else { return false }
        let next = DesktopLayout(screens: screens, windows: windows)
        guard next.isValid else { status = "Layout capture was invalid; previous snapshot retained"; return false }
        if next == layout { status = "Remembering \(screens.count) displays and \(windows.count) app windows"; return true }
        do {
            let data = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Serialize the commit against the display callback's capture fence.
            signalLock.lock()
            defer { signalLock.unlock() }
            guard self.revision == revision && !sleeping else { return false }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            layout = next; savedAt = Date()
            status = "Remembering \(screens.count) displays and \(windows.count) app windows"
            return true
        } catch { status = "Could not save desktop layout: \(error.localizedDescription)"; log(status); return false }
    }

    private func statusObject() -> [String: Any] {
        var object: [String: Any] = ["enabled": enabled, "status": status, "savedDisplays": layout?.screens.count ?? 0,
            "savedWindows": layout?.windows.count ?? 0, "restorePending": policy.needsRestore, "pausedAfterError": policy.failed,
            "lastWindowRestore": lastWindowResult, "accessibilityGranted": AXIsProcessTrusted()]
        let formatter = ISO8601DateFormatter()
        if let savedAt { object["savedAt"] = formatter.string(from: savedAt) }
        if let lastRestoreAt { object["lastRestoreAt"] = formatter.string(from: lastRestoreAt) }
        object["screens"] = layout?.screens.map { ["builtIn": $0.builtIn, "width": $0.width, "height": $0.height,
            "rotation": $0.rotation, "x": $0.frame.minX, "y": $0.frame.minY] as [String: Any] } ?? []
        return object
    }
    private func log(_ message: String) { DriverLoggers.log(.notice, category: .display, "Desktop layout: \(message)") }
}

private func desktopLayoutDisplayCallback(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<DesktopLayoutController>.fromOpaque(context).takeUnretainedValue().displayChanged(flags)
}
