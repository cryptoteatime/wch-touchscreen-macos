import Foundation

/// A transient logout or display-enumeration state must not become the saved desk.
struct DesktopLayoutCaptureGuard {
    static let startupSettleSeconds: TimeInterval = 60
    static let reconnectSettleSeconds: TimeInterval = 30
    static let removalSettleSeconds: TimeInterval = 60

    private(set) var recoveryUntil: TimeInterval
    private var missingKeys: Set<String> = []
    private var missingSince: TimeInterval?

    init(now: TimeInterval) { recoveryUntil = now + Self.startupSettleSeconds }

    func isRecovering(at now: TimeInterval) -> Bool { now < recoveryUntil }

    mutating func beginRecovery(at now: TimeInterval) {
        recoveryUntil = max(recoveryUntil, now + Self.reconnectSettleSeconds)
        resetRemovals()
    }

    mutating func acceptExplicitSave(at now: TimeInterval) {
        recoveryUntil = now
        resetRemovals()
    }

    var pendingRemovalCount: Int { missingKeys.count }

    mutating func allowsCapture(saved: [DesktopWindow], live: [DesktopWindow], at now: TimeInterval) -> Bool {
        guard !isRecovering(at: now) else { return false }
        let matches = DesktopWindowMatcher.matches(saved: saved, live: live)
        let missing = Set(saved.map(\.key)).subtracting(matches.map(\.savedKey))
        guard !missing.isEmpty else { resetRemovals(); return true }
        if missing != missingKeys {
            missingKeys = missing
            missingSince = now
        }
        // An empty Accessibility response is also possible during shutdown or an
        // unresponsive app/session. Only an explicit save may replace it with zero.
        guard !live.isEmpty else { return false }
        return missingSince.map { now - $0 >= Self.removalSettleSeconds } ?? false
    }

    private mutating func resetRemovals() {
        missingKeys.removeAll()
        missingSince = nil
    }
}
