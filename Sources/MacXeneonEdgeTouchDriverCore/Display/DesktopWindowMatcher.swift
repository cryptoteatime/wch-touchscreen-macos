import Foundation

/// Resolves relaunched windows without relying on PID reuse or enumeration order.
/// A one-window app can retain its placement even if its title changes at login.
enum DesktopWindowMatcher {
    struct Match: Equatable {
        var savedKey: String
        var liveKey: String
    }

    static func matches(saved: [DesktopWindow], live: [DesktopWindow], completed: [String: String] = [:]) -> [Match] {
        var usedSaved = Set(completed.keys)
        var usedLive = Set(completed.values)
        var result: [Match] = []
        func accept(_ old: DesktopWindow, _ current: DesktopWindow) {
            usedSaved.insert(old.key); usedLive.insert(current.key)
            result.append(Match(savedKey: old.key, liveKey: current.key))
        }
        for old in saved where !usedSaved.contains(old.key) {
            let candidates = live.filter { !usedLive.contains($0.key) && $0.bundleID == old.bundleID && $0.key == old.key }
            if candidates.count == 1 { accept(old, candidates[0]) }
        }
        // App-supplied identifiers, document identity, then title. Each tier must
        // be unique on both sides; identical browser windows are never ordered.
        for field in [\DesktopWindow.identifierHash, \.documentHash, \.titleHash] {
            for old in saved where !usedSaved.contains(old.key) {
                guard let fingerprint = old[keyPath: field], !fingerprint.isEmpty else { continue }
                let sources = saved.filter { !usedSaved.contains($0.key) && $0.bundleID == old.bundleID && $0[keyPath: field] == fingerprint }
                let targets = live.filter { !usedLive.contains($0.key) && $0.bundleID == old.bundleID && $0[keyPath: field] == fingerprint }
                if sources.count == 1 && targets.count == 1 { accept(old, targets[0]) }
            }
        }
        for old in saved where !usedSaved.contains(old.key) {
            let sources = saved.filter { $0.bundleID == old.bundleID }
            let targets = live.filter { $0.bundleID == old.bundleID }
            if sources.count == 1, targets.count == 1, !usedLive.contains(targets[0].key) {
                accept(old, targets[0])
            }
        }
        return result
    }
}

/// Completed windows are not moved again while a slow application is opening.
struct DesktopWindowRestoreProgress {
    static let launchGraceSeconds: TimeInterval = 180
    var bindings: [String: String] = [:]
    var failures: [String: Int] = [:]
    var startedAt: TimeInterval?

    var failedKeys: Set<String> { Set(failures.filter { $0.value >= 3 }.map(\.key)) }
    func waitingKeys(in windows: [DesktopWindow]) -> Set<String> {
        Set(windows.map(\.key)).subtracting(bindings.keys).subtracting(failedKeys)
    }
    mutating func begin(at now: TimeInterval) { if startedAt == nil { startedAt = now } }
    func hasTimeRemaining(at now: TimeInterval) -> Bool {
        startedAt.map { now - $0 < Self.launchGraceSeconds } ?? true
    }
}
