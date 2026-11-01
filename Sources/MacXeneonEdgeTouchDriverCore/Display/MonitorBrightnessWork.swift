import Foundation

/// One outstanding hardware operation per monitor; key repeats retain only the
/// latest unsent value. Reads from before a new target cannot become overrides.
struct MonitorBrightnessWork {
    struct Ticket: Equatable {
        var id: UInt64
        var connection: String
        var revision: UInt64
        var level: Double?
        var queuedAt: TimeInterval
    }
    private(set) var connection: String
    private(set) var revision: UInt64 = 0
    private(set) var inFlight: Ticket?
    private var nextID: UInt64 = 0
    private var write: (Double, TimeInterval)?
    private var wantsRead = false

    init(connection: String) { self.connection = connection }
    mutating func reconnect(_ connection: String) {
        self.connection = connection; revision &+= 1
        write = nil; wantsRead = false
        // Keep the old operation busy until it finishes. Its result is rejected.
    }
    mutating func requestRead() { wantsRead = true }
    mutating func requestWrite(_ level: Double, at now: TimeInterval) {
        guard level.isFinite, (0...1).contains(level) else { return }
        revision &+= 1; write = (level, now)
    }
    mutating func next(at now: TimeInterval) -> Ticket? {
        guard inFlight == nil, write != nil || wantsRead else { return nil }
        nextID &+= 1
        let ticket = Ticket(id: nextID, connection: connection, revision: revision,
                            level: write?.0, queuedAt: write?.1 ?? now)
        if write != nil { write = nil } else { wantsRead = false }
        inFlight = ticket
        return ticket
    }
    mutating func complete(_ ticket: Ticket) -> Bool {
        guard inFlight == ticket else { return false }
        inFlight = nil
        return ticket.connection == connection && ticket.revision == revision
    }
}

/// A short event-driven disconnect must invalidate work even when the next poll
/// sees the same CG display number and vendor brightness cache.
struct MonitorBrightnessConnections {
    private var versions: [UInt32: UInt64] = [:]
    private var generation: UInt64 = 0
    private var minimumGeneration: UInt64 = 0
    mutating func interrupted(_ display: UInt32) {
        generation &+= 1; versions[display] = generation
        if versions.count > 64 { minimumGeneration = generation; versions = [display: generation] }
    }
    func token(_ base: String, display: UInt32) -> String {
        "\(base):epoch:\(versions[display] ?? minimumGeneration)"
    }
}

public enum MonitorBrightnessCommand {
    public static func level(_ command: String) -> Double? {
        let prefix = "set-brightness:"
        guard command.hasPrefix(prefix) else { return nil }
        let value = command.dropFirst(prefix.count)
        guard (1...3).contains(value.count), value.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let percent = Int(value), (0...100).contains(percent) else { return nil }
        return Double(percent) / 100
    }
}

/// Locked cancellation fence checked by hardware workers before a write. State
/// policy remains on the brightness queue; no hardware call holds this lock.
final class MonitorBrightnessPermit {
    private let lock = NSLock()
    private var connection: String?
    init(_ connection: String) { self.connection = connection }
    func update(_ connection: String?) { lock.lock(); self.connection = connection; lock.unlock() }
    func accepts(_ connection: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return self.connection == connection
    }
}

/// Bounded local diagnostics contain no serials, UUIDs, USB IDs or app/window data.
struct MonitorBrightnessDiagnostics {
    private(set) var events: [[String: String]] = []
    private(set) var counters: [String: Int] = [:]
    mutating func record(_ event: String, transport: String = "all", detail: String = "", milliseconds: Int? = nil) {
        counters[event, default: 0] += 1
        var item = ["at": ISO8601DateFormatter().string(from: Date()), "event": event,
                    "transport": transport, "detail": String(detail.prefix(160))]
        if let milliseconds { item["milliseconds"] = String(max(0, milliseconds)) }
        events.append(item)
        if events.count > 64 { events.removeFirst(events.count - 64) }
    }
    var object: [String: Any] { ["counts": counters, "recent": events] }
}
