import Foundation

/// App activity fences snapshots without restarting the display settling clock.
/// The controller serializes access to these signals with its callback lock.
struct DesktopLayoutSignals {
    private(set) var revision: UInt64 = 0
    private(set) var displayRevision: UInt64 = 0
    private(set) var sleeping = false
    private var changedAt: TimeInterval
    private var displayChangedAt: TimeInterval
    private var configuring: Set<UInt32> = []

    init(now: TimeInterval) { changedAt = now; displayChangedAt = now }

    mutating func applicationChanged(at now: TimeInterval) {
        revision &+= 1; changedAt = now
    }

    mutating func displayChanged(at now: TimeInterval) {
        applicationChanged(at: now)
        displayRevision &+= 1; displayChangedAt = now
    }

    mutating func displayCallback(_ display: UInt32, beginning: Bool, at now: TimeInterval) {
        if beginning { configuring.insert(display) } else { configuring.remove(display) }
        displayChanged(at: now)
    }

    mutating func sleepChanged(_ asleep: Bool, at now: TimeInterval) {
        sleeping = asleep; configuring.removeAll(); displayChanged(at: now)
    }

    func isCurrent(_ expected: UInt64) -> Bool { revision == expected && !sleeping && configuring.isEmpty }
    func canRestore(at now: TimeInterval) -> Bool {
        !sleeping && configuring.isEmpty && now - displayChangedAt >= DesktopLayoutReadiness.confirmationSeconds
    }
    func canCapture(at now: TimeInterval) -> Bool {
        canRestore(at: now) && now - changedAt >= 3
    }
}

/// Require matching hardware and geometry observations before advancing a stage.
struct DesktopLayoutReadiness {
    static let confirmationSeconds: TimeInterval = 0.5
    private var screens: [DesktopScreen] = []
    private var revision: UInt64?
    private var observedAt: TimeInterval = 0

    mutating func observe(_ current: [DesktopScreen], displayRevision: UInt64, at now: TimeInterval) -> Bool {
        guard !current.isEmpty else { screens = []; revision = nil; return false }
        guard revision == displayRevision, Self.sameState(screens, current) else {
            screens = current; revision = displayRevision; observedAt = now
            return false
        }
        return now - observedAt >= Self.confirmationSeconds
    }

    static func sameState(_ lhs: [DesktopScreen], _ rhs: [DesktopScreen]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let a = lhs.sorted { $0.uuid < $1.uuid }, b = rhs.sorted { $0.uuid < $1.uuid }
        return zip(a, b).allSatisfy { pair in
            let (left, right) = pair
            return left.uuid == right.uuid && left.runtimeID == right.runtimeID &&
                left.sameHardware(as: right) && left.sameGeometry(as: right)
        }
    }
}

/// A new display state can advance promptly; repeated writes to the same state
/// retain the previous two-second retry cadence, including window failures.
struct DesktopLayoutAttemptPacing {
    private var screens: [DesktopScreen] = []
    private var attemptedAt: TimeInterval?

    func delay(for current: [DesktopScreen], at now: TimeInterval) -> TimeInterval {
        guard let attemptedAt, DesktopLayoutReadiness.sameState(screens, current) else { return 0 }
        return max(0, 2 - (now - attemptedAt))
    }

    mutating func attempted(_ current: [DesktopScreen], at now: TimeInterval) {
        screens = current; attemptedAt = now
    }
}
