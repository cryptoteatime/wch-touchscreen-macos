import Foundation

enum MonitorBrightnessTransport: String, Codable { case native, displayLink }

struct MonitorBrightnessIdentity: Codable, Hashable {
    var transport: MonitorBrightnessTransport
    var key: String
    var name: String
    var vendor: UInt32
    var model: UInt32

    var isValid: Bool { !key.isEmpty && key.count <= 512 && !name.isEmpty && name.count <= 128 && vendor != 0 && model != 0 }
}

struct MonitorBrightnessTarget: Codable, Equatable {
    var identity: MonitorBrightnessIdentity
    var level: Double
}

struct MonitorBrightnessPreferences: Codable, Equatable {
    var version = 1
    var enabled = false
    var followBuiltIn = false
    var targets: [MonitorBrightnessTarget] = []

    var isValid: Bool {
        version == 1 && targets.count <= 16 && Set(targets.map(\.identity)).count == targets.count &&
        targets.allSatisfy { $0.identity.isValid && $0.level.isFinite && (0...1).contains($0.level) }
    }
}

struct MonitorBrightnessSample {
    var identity: MonitorBrightnessIdentity
    var connection: String
    var level: Double?
}

struct MonitorBrightnessWrite: Equatable {
    var identity: MonitorBrightnessIdentity
    var level: Double
}

/// Pure policy: connection defaults can never become remembered native brightness.
/// DisplayLink reports cached values, so its physical-button overrides are left to
/// the monitor's own memory. Only an explicit Mac brightness change writes to it.
struct MonitorBrightnessPolicy {
    private struct Connection {
        var token: String
        var began: TimeInterval
        var nextAttempt: TimeInterval
        var attempts = 0
        var ready = false
        var failed = false
        var protectUntil: TimeInterval = 0
        var candidate: Double?
        var candidateAt: TimeInterval = 0
    }
    var preferences: MonitorBrightnessPreferences
    private var connections: [MonitorBrightnessIdentity: Connection] = [:]
    private var sourceBaseline: Double?

    init(preferences: MonitorBrightnessPreferences) { self.preferences = preferences }

    mutating func resetConnections() { connections.removeAll(); sourceBaseline = nil }

    mutating func remember(_ samples: [MonitorBrightnessSample]) {
        for sample in unique(samples) {
            guard let level = valid(sample.level), sample.identity.isValid else { continue }
            // Never silently replace a saved HDMI value with its possibly stale cache.
            if sample.identity.transport == .displayLink && target(for: sample.identity) != nil { continue }
            save(sample.identity, level)
        }
        preferences.enabled = true
    }

    mutating func synchronize(_ level: Double, samples: [MonitorBrightnessSample], now: TimeInterval,
                              including identities: Set<MonitorBrightnessIdentity>? = nil) -> [MonitorBrightnessWrite] {
        guard let level = valid(level) else { return [] }
        let samples = samples.filter { identities == nil || identities!.contains($0.identity) }
        sourceBaseline = level
        remember(samples)
        // An intentional Mac adjustment also updates remembered disconnected screens.
        for index in preferences.targets.indices where identities == nil || identities!.contains(preferences.targets[index].identity) {
            preferences.targets[index].level = level
        }
        var writes: [MonitorBrightnessWrite] = []
        for sample in unique(samples) where target(for: sample.identity) != nil {
            var state = connections[sample.identity] ?? Connection(token: sample.connection, began: now, nextAttempt: now + 2)
            state.candidate = nil
            state.protectUntil = now + 6
            if sample.identity.transport == .native {
                state.ready = false; state.failed = false; state.attempts = 0
                state.began = now - 10; state.nextAttempt = now + 2
            }
            connections[sample.identity] = state
            writes.append(MonitorBrightnessWrite(identity: sample.identity, level: level))
        }
        return writes
    }

    mutating func step(_ samples: [MonitorBrightnessSample], builtIn: Double?, now: TimeInterval,
                       following identities: Set<MonitorBrightnessIdentity>? = nil) -> [MonitorBrightnessWrite] {
        let samples = unique(samples)
        let online = Set(samples.map(\.identity))
        connections = connections.filter { online.contains($0.key) }
        guard preferences.enabled else { sourceBaseline = valid(builtIn); return [] }
        var writes: [MonitorBrightnessWrite] = []
        if let source = valid(builtIn) {
            if (identities != nil ? !identities!.isEmpty : preferences.followBuiltIn), let baseline = sourceBaseline, abs(source - baseline) >= 0.005 {
                writes = synchronize(source, samples: samples, now: now, including: identities)
            }
            sourceBaseline = source
        }
        for sample in samples {
            guard let desired = target(for: sample.identity) else { continue }
            var state = connections[sample.identity] ?? Connection(token: sample.connection, began: now, nextAttempt: now + 3)
            if state.token != sample.connection { state = Connection(token: sample.connection, began: now, nextAttempt: now + 3) }
            defer { connections[sample.identity] = state }
            // A hardware-button override on HDMI is invisible while connected.
            // Reapplying the cache here would undo it; never do that automatically.
            if sample.identity.transport == .displayLink { state.ready = true; continue }
            guard !state.failed else { continue }
            if !state.ready {
                guard now >= state.nextAttempt else { continue }
                state.nextAttempt = now + 3
                state.attempts += 1
                if let actual = valid(sample.level), abs(actual - desired) < 0.006 {
                    if now - state.began >= 12 { state.ready = true; state.protectUntil = now + 2 }
                } else if !writes.contains(where: { $0.identity == sample.identity }) {
                    writes.append(MonitorBrightnessWrite(identity: sample.identity, level: desired))
                }
                if state.attempts >= 8 && !state.ready { state.failed = true }
                continue
            }
            guard now >= state.protectUntil, let actual = valid(sample.level) else { continue }
            if abs(actual - desired) < 0.006 { state.candidate = nil; continue }
            if let candidate = state.candidate, abs(candidate - actual) < 0.005, now - state.candidateAt >= 1 {
                save(sample.identity, actual); state.candidate = nil
            } else { state.candidate = actual; state.candidateAt = now }
        }
        return writes
    }

    func target(for identity: MonitorBrightnessIdentity) -> Double? { preferences.targets.first { $0.identity == identity }?.level }
    func failed(_ identity: MonitorBrightnessIdentity) -> Bool { connections[identity]?.failed == true }
    func restoring(_ identity: MonitorBrightnessIdentity) -> Bool { identity.transport == .native && connections[identity]?.ready == false && !failed(identity) }

    private mutating func save(_ identity: MonitorBrightnessIdentity, _ level: Double) {
        if let index = preferences.targets.firstIndex(where: { $0.identity == identity }) { preferences.targets[index].level = level }
        else if preferences.targets.count < 16 { preferences.targets.append(MonitorBrightnessTarget(identity: identity, level: level)) }
    }
    private func valid(_ value: Double?) -> Double? { guard let value, value.isFinite, (0...1).contains(value) else { return nil }; return value }
    private func unique(_ samples: [MonitorBrightnessSample]) -> [MonitorBrightnessSample] {
        let groups = Dictionary(grouping: samples, by: \.identity)
        return samples.filter { $0.identity.isValid && groups[$0.identity]?.count == 1 }
    }
}

/// DDC/CI VCP 0x10 is the monitor's backlight level, not a software overlay.
enum MonitorBrightnessDDC {
    static let query: [UInt8] = [0x82, 0x01, 0x10, 0xfd]
    static func set(_ value: UInt16) -> [UInt8] {
        var packet: [UInt8] = [0x84, 0x03, 0x10, UInt8(value >> 8), UInt8(value & 255)]
        packet.append(packet.reduce(UInt8(0x6e ^ 0x51), ^))
        return packet
    }
    static func reading(_ reply: [UInt8]) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count == 11, reply[0] == 0x6e, reply[1] == 0x88, reply[2] == 2,
              reply[3] == 0, reply[4] == 0x10, reply[5] == 0,
              reply.prefix(10).reduce(UInt8(0x50), ^) == reply[10] else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0, current <= maximum else { return nil }
        return (current, maximum)
    }
}
