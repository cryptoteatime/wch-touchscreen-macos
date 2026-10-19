import Foundation
#if !WCH_STANDALONE
@testable import MacXeneonEdgeTouchDriverCore
#endif

func exerciseMonitorBrightness(_ check: (Bool, String) -> Void) throws {
    let left = MonitorBrightnessIdentity(transport: .native, key: "native:fixture-left", name: "Type-c", vendor: 1, model: 2)
    let right = MonitorBrightnessIdentity(transport: .displayLink, key: "displaylink:fixture-right", name: "HDMI", vendor: 1, model: 2)
    func samples(_ level: Double?, token: String = "first", rightLevel: Double = 0.85) -> [MonitorBrightnessSample] {
        [MonitorBrightnessSample(identity: left, connection: token, level: level),
         MonitorBrightnessSample(identity: right, connection: token, level: rightLevel)]
    }
    var preferences = MonitorBrightnessPreferences(enabled: true, followBuiltIn: true,
        targets: [MonitorBrightnessTarget(identity: left, level: 0.85), MonitorBrightnessTarget(identity: right, level: 0.85)])
    check(preferences.isValid, "A pair of independent saved targets is valid")
    var duplicate = preferences; duplicate.targets.append(duplicate.targets[0])
    check(!duplicate.isValid, "Duplicate identities are rejected")
    var invalid = preferences; invalid.targets[0].level = 1.01
    check(!invalid.isValid, "Out-of-range levels are rejected")
    invalid.targets[0].level = .nan
    check(!invalid.isValid, "NaN levels are rejected")
    check(MonitorBrightnessDDC.set(85) == [0x84, 3, 0x10, 0, 85, 0xfd], "DDC Set VCP 85 uses the captured wire protocol")
    let response: [UInt8] = [0x6e, 0x88, 2, 0, 0x10, 0, 0, 100, 0, 80, 0x90]
    check(MonitorBrightnessDDC.reading(response)?.current == 80, "The captured hardware response decodes to 80")
    var corrupt = response; corrupt[10] ^= 1
    check(MonitorBrightnessDDC.reading(corrupt) == nil, "Invalid DDC checksums cannot become remembered brightness")
    corrupt = response; corrupt[3] = 1; corrupt[10] ^= 1
    check(MonitorBrightnessDDC.reading(corrupt) == nil, "Unsupported VCP responses are rejected even with a valid checksum")
    check(MonitorBrightnessDDC.reading(Array(response.prefix(10))) == nil, "Short replies are rejected")

    var policy = MonitorBrightnessPolicy(preferences: preferences)
    check(policy.step(samples(0.10), builtIn: 1, now: 0).isEmpty, "Startup waits for the connection to settle")
    check(policy.target(for: left) == 0.85, "A 10% startup default cannot overwrite the saved target")
    let initial = policy.step(samples(0.10), builtIn: 1, now: 3)
    check(initial == [MonitorBrightnessWrite(identity: left, level: 0.85)], "Only the native panel needs reconnect restoration")
    for time in [6.0, 9, 12] { _ = policy.step(samples(0.85), builtIn: 1, now: time) }
    check(!policy.restoring(left) && !policy.failed(left), "Stable hardware readback completes restoration")
    _ = policy.step(samples(0.70), builtIn: 1, now: 15)
    check(policy.target(for: left) == 0.85, "A single transient reading is not remembered")
    _ = policy.step(samples(0.70), builtIn: 1, now: 17)
    check(policy.target(for: left) == 0.70, "Stable physical-button changes are remembered without fighting the user")
    _ = policy.step(samples(0.69), builtIn: 1, now: 18)
    _ = policy.step(samples(0.69), builtIn: 1, now: 19)
    check(policy.target(for: left) == 0.69, "A one-percent button adjustment is remembered")
    let saved = try JSONDecoder().decode(MonitorBrightnessPreferences.self, from: JSONEncoder().encode(policy.preferences))
    var rebooted = MonitorBrightnessPolicy(preferences: saved)
    _ = rebooted.step(samples(0.10, token: "reboot", rightLevel: 0.20), builtIn: 1, now: 0)
    let rebootWrites = rebooted.step(samples(0.10, token: "reboot", rightLevel: 0.20), builtIn: 1, now: 3)
    check(rebootWrites == [MonitorBrightnessWrite(identity: left, level: 0.69)], "The last manual native value survives a process restart")
    check(rebootWrites.allSatisfy { $0.identity != right }, "A cached DisplayLink value is never forced over an HDMI hardware override")
    let sourceChange = policy.step(samples(0.70), builtIn: 0.50, now: 20)
    check(Set(sourceChange.map(\.identity)) == Set([left, right]) && sourceChange.allSatisfy { $0.level == 0.50 }, "The next MacBook adjustment intentionally synchronizes both panels")
    check(policy.preferences.targets.allSatisfy { $0.level == 0.50 }, "MacBook changes update remembered values")
    let same = policy.step(samples(0.50), builtIn: 0.50, now: 21)
    check(same.isEmpty, "The same Mac brightness does not continuously force the monitors")
    _ = policy.step([], builtIn: 0.50, now: 22)
    _ = policy.step([], builtIn: 0.60, now: 23)
    check(policy.preferences.targets.allSatisfy { $0.level == 0.60 }, "Intentional Mac changes also update disconnected saved targets")

    preferences.followBuiltIn = false
    var independent = MonitorBrightnessPolicy(preferences: preferences)
    _ = independent.step(samples(0.85), builtIn: 1, now: 0)
    check(independent.step(samples(0.85), builtIn: 0.4, now: 1).isEmpty, "Independent mode ignores Mac brightness changes")
    var failed = MonitorBrightnessPolicy(preferences: preferences)
    _ = failed.step(samples(nil), builtIn: 1, now: 0)
    for time in stride(from: 3.0, through: 24, by: 3) { _ = failed.step(samples(nil), builtIn: 1, now: time) }
    check(failed.failed(left), "Missing readback exhausts a bounded retry budget")
    check(failed.step(samples(0.10), builtIn: 1, now: 60).isEmpty && failed.target(for: left) == 0.85, "A failed restore cannot silently learn a reset level")
    _ = failed.step([], builtIn: 1, now: 61)
    _ = failed.step(samples(0.10, token: "new-port-session"), builtIn: 1, now: 62)
    check(failed.step(samples(0.10, token: "new-port-session"), builtIn: 1, now: 65).count == 1, "A real new connection gets a fresh bounded attempt")
    var ambiguous = MonitorBrightnessPolicy(preferences: preferences)
    let duplicated = samples(0.10) + [samples(0.10)[0]]
    _ = ambiguous.step(duplicated, builtIn: 1, now: 0)
    check(ambiguous.step(duplicated, builtIn: 1, now: 5).isEmpty, "Duplicate live identities are not guessed")
    ambiguous.remember(duplicated)
    check(ambiguous.target(for: left) == 0.85, "Remembering cannot replace an ambiguous monitor target")
    preferences.enabled = false
    var disabled = MonitorBrightnessPolicy(preferences: preferences)
    _ = disabled.step(samples(0.10), builtIn: 1, now: 0)
    check(disabled.step(samples(0.10), builtIn: 0.3, now: 60).isEmpty, "Disabled control never writes")
}
