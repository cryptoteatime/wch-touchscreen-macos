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
    check(initial == [MonitorBrightnessWrite(identity: left, level: 0.85), MonitorBrightnessWrite(identity: right, level: 0.85)], "Both connections restore their saved levels, even when HDMI's cache matches")
    check(policy.restoring(right), "A matching DisplayLink cache cannot confirm a hardware restore")
    check(policy.acknowledge(right, connection: "first", level: 0.85, requestedAt: 3, success: true), "The current HDMI attempt accepts its acknowledgement")
    check(!policy.restoring(right), "Acknowledgement completes the HDMI restore")
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
    check(rebootWrites.contains(MonitorBrightnessWrite(identity: left, level: 0.69)), "The last manual native value survives a process restart")
    check(rebootWrites.contains(MonitorBrightnessWrite(identity: right, level: 0.85)), "A process restart restores HDMI's last saved WCH level instead of its reset default")
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
    check(independent.step(samples(0.85), builtIn: 0.4, now: 1) == [MonitorBrightnessWrite(identity: right, level: 0.85)] &&
          independent.preferences.targets.allSatisfy { $0.level == 0.85 },
          "Independent mode restores the saved HDMI level on the early schedule and ignores Mac brightness changes")
    var failed = MonitorBrightnessPolicy(preferences: preferences)
    _ = failed.step(samples(nil), builtIn: 1, now: 0)
    for time in stride(from: 3.0, through: 24, by: 3) { _ = failed.step(samples(nil), builtIn: 1, now: time) }
    check(failed.failed(left), "Missing readback exhausts a bounded retry budget")
    check(failed.step(samples(0.10), builtIn: 1, now: 60).isEmpty && failed.target(for: left) == 0.85, "A failed restore cannot silently learn a reset level")
    _ = failed.step([], builtIn: 1, now: 61)
    _ = failed.step(samples(0.10, token: "new-port-session"), builtIn: 1, now: 62)
    check(failed.step(samples(0.10, token: "new-port-session"), builtIn: 1, now: 65).count == 2, "A real new connection gets fresh bounded attempts on both transports")
    var ambiguous = MonitorBrightnessPolicy(preferences: preferences)
    let duplicated = samples(0.10) + [samples(0.10)[0]]
    _ = ambiguous.step(duplicated, builtIn: 1, now: 0)
    check(ambiguous.step(duplicated, builtIn: 1, now: 5).map(\.identity) == [right], "Duplicate live identities are skipped without suppressing another monitor")
    ambiguous.remember(duplicated)
    check(ambiguous.target(for: left) == 0.85, "Remembering cannot replace an ambiguous monitor target")

    func hdmi(_ token: String = "A", level: Double = 0.85) -> [MonitorBrightnessSample] {
        [MonitorBrightnessSample(identity: right, connection: token, level: level)]
    }
    var hdmiPolicy = MonitorBrightnessPolicy(preferences: preferences)
    _ = hdmiPolicy.step(hdmi(), builtIn: 1, now: 0)
    check(hdmiPolicy.step(hdmi(), builtIn: 1, now: 3).count == 1, "HDMI is actively restored despite a matching cached level")
    check(!hdmiPolicy.acknowledge(right, connection: "old", level: 0.85, requestedAt: 3, success: true), "An old connection cannot acknowledge the current restore")
    check(!hdmiPolicy.acknowledge(right, connection: "A", level: 0.20, requestedAt: 3, success: true), "An acknowledgement for another level cannot complete restoration")
    check(!hdmiPolicy.acknowledge(right, connection: "A", level: 0.85, requestedAt: 2, success: true), "An old write cannot acknowledge the current restore")
    check(hdmiPolicy.acknowledge(right, connection: "A", level: 0.85, requestedAt: 3, success: false) && hdmiPolicy.restoring(right), "Vendor errors remain eligible for a bounded retry")
    check(hdmiPolicy.step(hdmi(), builtIn: 1, now: 8).isEmpty, "HDMI retry waits until the acknowledgement window has elapsed")
    check(hdmiPolicy.step(hdmi(), builtIn: 1, now: 9).count == 1, "A failed HDMI restore gets another attempt")
    check(hdmiPolicy.acknowledge(right, connection: "A", level: 0.85, requestedAt: 9, success: true), "The retry can complete on acknowledgement")
    check(hdmiPolicy.step(hdmi(level: 0.10), builtIn: 1, now: 40).isEmpty && hdmiPolicy.target(for: right) == 0.85,
          "After success, cached changes neither cause repeated writes nor replace the saved HDMI level")
    _ = hdmiPolicy.step([], builtIn: 1, now: 41)
    _ = hdmiPolicy.step(hdmi(), builtIn: 1, now: 42)
    check(hdmiPolicy.step(hdmi(), builtIn: 1, now: 45).count == 1, "Reconnect restores HDMI even when macOS reuses its connection token")
    check(!hdmiPolicy.acknowledge(right, connection: "A", level: 0.85, requestedAt: 9, success: true), "A pre-disconnect acknowledgement cannot complete a new session")
    var timedOut = MonitorBrightnessPolicy(preferences: preferences)
    _ = timedOut.step(hdmi(), builtIn: 1, now: 0)
    var attempts = 0
    for time in stride(from: 3.0, through: 60, by: 3) { attempts += timedOut.step(hdmi(), builtIn: 1, now: time).count }
    check(attempts == 4 && timedOut.failed(right) && !timedOut.restoring(right), "Missing HDMI acknowledgements stop after four attempts")
    check(timedOut.target(for: right) == 0.85, "An HDMI timeout preserves the saved target")
    _ = timedOut.step(hdmi("B"), builtIn: 1, now: 61)
    check(timedOut.step(hdmi("B"), builtIn: 1, now: 64).count == 1 && !timedOut.failed(right), "A changed HDMI connection renews the bounded budget")
    _ = timedOut.synchronize(0.5, samples: hdmi("B"), now: 65)
    check(!timedOut.acknowledge(right, connection: "B", level: 0.85, requestedAt: 64, success: true), "A new Mac brightness press supersedes an in-flight restore")
    check(timedOut.acknowledge(right, connection: "B", level: 0.5, requestedAt: 65, success: true), "The latest Mac brightness write can complete restoration")

    var fast = MonitorBrightnessPolicy(preferences: preferences)
    _ = fast.step(samples(0.10, rightLevel: 0.10), builtIn: 1, now: 0)
    check(fast.stepDisplayLink(samples(0.10), now: 0.49).isEmpty, "The fast HDMI path preserves a short connection settling period")
    check(fast.stepDisplayLink(samples(0.10), now: 0.5) == [MonitorBrightnessWrite(identity: right, level: 0.85)],
          "HDMI restoration starts after half a second without a native hardware poll")
    check(fast.step(samples(0.10), builtIn: 1, now: 0.5).isEmpty, "A regular poll at the same time does not duplicate the fast write")
    check(fast.target(for: left) == 0.85 && fast.restoring(left), "Fast HDMI work preserves the native target and connection state")
    check(fast.stepDisplayLink(samples(0.10), now: 1).isEmpty, "The fast timer does not repeatedly write while awaiting acknowledgement")
    check(fast.acknowledge(right, connection: "first", level: 0.85, requestedAt: 0.5, success: true), "The early HDMI write still requires its own acknowledgement")
    check(fast.step(samples(0.10), builtIn: 1, now: 2.99).isEmpty, "Native brightness retains its original three-second settling period")
    check(fast.step(samples(0.10), builtIn: 1, now: 3) == [MonitorBrightnessWrite(identity: left, level: 0.85)],
          "The native restore proceeds on its original schedule after the fast HDMI restore")
    for time in [6.0, 9, 12] { _ = fast.step(samples(0.85), builtIn: 1, now: time) }
    _ = fast.step(samples(0.70), builtIn: 1, now: 15)
    _ = fast.stepDisplayLink(samples(0.70), now: 16.5)
    check(fast.target(for: left) == 0.85, "Fast HDMI ticks cannot treat an old native sample as a second stable button reading")
    _ = fast.step(samples(0.70), builtIn: 1, now: 17)
    check(fast.target(for: left) == 0.70, "A fresh native poll still remembers a stable hardware adjustment")

    var rapid = MonitorBrightnessPolicy(preferences: preferences)
    _ = rapid.stepDisplayLink(hdmi("A"), now: 0)
    check(rapid.stepDisplayLink([], now: 0.25).isEmpty, "A disconnect before the early deadline produces no write")
    _ = rapid.stepDisplayLink(hdmi("B"), now: 0.3)
    check(rapid.stepDisplayLink(hdmi("B"), now: 0.79).isEmpty, "A replacement HDMI connection gets its own settling period")
    check(rapid.stepDisplayLink(hdmi("B"), now: 0.8).count == 1, "A stable replacement connection can restore promptly")
    check(rapid.acknowledge(right, connection: "B", level: 0.85, requestedAt: 0.8, success: false), "An early vendor error is handled without declaring success")
    check(rapid.stepDisplayLink(hdmi("B"), now: 6.79).isEmpty, "Early errors retain the existing retry interval")
    check(rapid.stepDisplayLink(hdmi("B"), now: 6.8).count == 1, "An early failed attempt still gets the normal bounded retry")
    var fastTimeout = MonitorBrightnessPolicy(preferences: preferences)
    _ = fastTimeout.stepDisplayLink(hdmi(), now: 0)
    var fastAttempts = 0
    for index in 1...200 { fastAttempts += fastTimeout.stepDisplayLink(hdmi(), now: Double(index) / 4).count }
    check(fastAttempts == 4 && fastTimeout.failed(right), "A fast timer cannot exceed four unacknowledged attempts")
    var fastAmbiguous = MonitorBrightnessPolicy(preferences: preferences)
    _ = fastAmbiguous.stepDisplayLink(hdmi() + hdmi(), now: 0)
    check(fastAmbiguous.stepDisplayLink(hdmi() + hdmi(), now: 1).isEmpty, "The fast path skips duplicate HDMI identities")
    preferences.enabled = false
    var disabled = MonitorBrightnessPolicy(preferences: preferences)
    _ = disabled.step(samples(0.10), builtIn: 1, now: 0)
    check(disabled.step(samples(0.10), builtIn: 0.3, now: 60).isEmpty, "Disabled control never writes")
    check(disabled.stepDisplayLink(hdmi(), now: 100).isEmpty, "The fast path also respects disabled brightness control")
}

func exerciseBrightnessWork(_ check: (Bool, String) -> Void) {
    var left = MonitorBrightnessWork(connection: "first")
    left.requestRead()
    let read = left.next(at: 0)!
    left.requestWrite(0.3, at: 0.05)
    left.requestWrite(0.6, at: 0.1)
    left.requestWrite(1, at: 0.15)
    check(left.next(at: 0.16) == nil, "A slow read does not allow overlapping native operations")
    check(!left.complete(read), "A pre-adjustment read cannot overwrite the latest target")
    let final = left.next(at: 0.2)!
    check(final.level == 1 && final.queuedAt == 0.15, "Rapid changes coalesce to the latest unsent value")
    check(left.complete(final), "The current connection and target accept verified readback")
    check(left.next(at: 0.4) == nil, "Superseded intermediate levels are not replayed")
    left.requestWrite(0.4, at: 1)
    let old = left.next(at: 1)!
    left.reconnect("second")
    left.requestWrite(0.85, at: 1.1)
    check(left.next(at: 1.2) == nil, "Reconnect waits for the old hardware operation to finish")
    check(!left.complete(old), "A late completion from the old connection is discarded")
    let replacement = left.next(at: 1.3)!
    check(replacement.connection == "second" && replacement.level == 0.85, "Reconnected hardware receives only its newest target")
    check(!left.complete(old), "A duplicate stale completion cannot clear the new in-flight operation")
    check(left.complete(replacement), "The new operation remains valid after a stale duplicate")
    var right = MonitorBrightnessWork(connection: "right")
    left.requestRead(); _ = left.next(at: 2)
    right.requestWrite(0.7, at: 2)
    check(right.next(at: 2)?.level == 0.7, "A stalled native monitor does not block a second monitor")
    var third = MonitorBrightnessWork(connection: "third")
    third.requestWrite(0.9, at: 2)
    check(third.next(at: 2)?.level == 0.9, "Three native monitors have independent work queues")
    var invalid = MonitorBrightnessWork(connection: "invalid")
    for value in [Double.nan, .infinity, -0.1, 1.1] { invalid.requestWrite(value, at: 0) }
    check(invalid.next(at: 1) == nil, "Invalid hardware levels never create work")
    var epochs = MonitorBrightnessConnections()
    let before = epochs.token("reused", display: 10)
    let other = epochs.token("other", display: 20)
    epochs.interrupted(10)
    check(epochs.token("reused", display: 10) != before, "Brief disconnect invalidates a reused display number")
    check(epochs.token("other", display: 20) == other, "A reset is scoped to the affected display")
    let second = epochs.token("reused", display: 10)
    epochs.interrupted(10)
    check(epochs.token("reused", display: 10) != second, "Repeated brownout-like events receive new generations")
    for id in UInt32(100)..<170 { epochs.interrupted(id) }
    check(epochs.token("reused", display: 10) != before, "Bounded generation history cannot revive an old zero-generation token")
    let permit = MonitorBrightnessPermit("first")
    check(permit.accepts("first"), "Worker permit starts on the authorized connection")
    permit.update(nil)
    check(!permit.accepts("first"), "Disabling control revokes queued writes")
    permit.update("second")
    check(!permit.accepts("first") && permit.accepts("second"), "Reconnection cannot reuse an old write permit")
    for percent in [0, 1, 85, 100] {
        check(MonitorBrightnessCommand.level("set-brightness:\(percent)") == Double(percent) / 100, "WCH brightness works without a built-in source")
    }
    for command in ["set-brightness:-1", "set-brightness:101", "set-brightness:nan", "set-brightness:0.5", "set-brightness: 85", "set-brightness:85\n", "other:85"] {
        check(MonitorBrightnessCommand.level(command) == nil, "Malformed brightness commands are rejected")
    }
    var diagnostics = MonitorBrightnessDiagnostics()
    for _ in 0..<100 { diagnostics.record("write-failed", transport: "native") }
    check(diagnostics.events.count == 64 && diagnostics.counters["write-failed"] == 100, "Diagnostics retain bounded events with cumulative counts")

    let native = MonitorBrightnessIdentity(transport: .native, key: "native:test", name: "Native", vendor: 1, model: 2)
    let linked = MonitorBrightnessIdentity(transport: .displayLink, key: "displaylink:test", name: "Linked", vendor: 3, model: 4)
    var policy = MonitorBrightnessPolicy(preferences: .init(enabled: true, followBuiltIn: true,
        targets: [.init(identity: native, level: 0.85), .init(identity: linked, level: 0.85)]))
    func samples(_ connection: String = "A") -> [MonitorBrightnessSample] {
        [.init(identity: native, connection: connection, level: 0.85), .init(identity: linked, connection: connection, level: 0.85)]
    }
    _ = policy.step(samples(), builtIn: 1, now: 0)
    _ = policy.stepDisplayLink(samples(), now: 0.5)
    check(policy.acknowledge(linked, connection: "A", level: 0.85, requestedAt: 0.5, success: true), "Initial vendor acknowledgement is accepted")
    policy.invalidate(linked)
    check(!policy.acknowledge(linked, connection: "A", level: 0.85, requestedAt: 0.5, success: true), "A disconnect event revokes even an identical cached acknowledgement")
    _ = policy.stepDisplayLink(samples(), now: 1)
    check(policy.stepDisplayLink(samples(), now: 1.5).map(\.identity) == [linked], "An event seen between polls re-arms vendor restoration")
    let local = policy.synchronize(0.7, samples: samples(), now: 2, trackSource: false)
    check(local.count == 2 && policy.target(for: native) == 0.7, "Explicit external level updates both saved targets")
    let unchangedMac = policy.step(samples(), builtIn: 1, now: 2.1)
    check(!unchangedMac.contains { $0.level == 1 }, "An unchanged Mac source does not undo a WCH menu adjustment")
    _ = policy.step(samples(), builtIn: nil, now: 3)
    check(policy.target(for: native) == 0.7, "No active built-in display preserves saved external levels")
    check(policy.step(samples(), builtIn: 0.5, now: 4).allSatisfy { $0.level == 0.5 }, "A later intentional Mac change resumes following")
    var new = MonitorBrightnessPolicy(preferences: .init())
    check(new.synchronize(0.85, samples: [.init(identity: native, connection: "new", level: nil)], now: 0).count == 1,
          "Enabling follow can target a known monitor before its first hardware read returns")
    var fresh = MonitorBrightnessPolicy(preferences: .init(enabled: true, targets: [.init(identity: native, level: 0.85)]))
    for time in [0.0, 3, 6, 9, 12, 15] { _ = fresh.step([.init(identity: native, connection: "N", level: 0.85, observedAt: time)], builtIn: nil, now: time) }
    _ = fresh.step([.init(identity: native, connection: "N", level: 0.7, observedAt: 16)], builtIn: nil, now: 16)
    _ = fresh.step([.init(identity: native, connection: "N", level: 0.7, observedAt: 16)], builtIn: nil, now: 20)
    check(fresh.target(for: native) == 0.85, "Re-reading a cached native sample cannot establish a manual override")
    _ = fresh.step([.init(identity: native, connection: "N", level: 0.7, observedAt: 21)], builtIn: nil, now: 21)
    check(fresh.target(for: native) == 0.7, "A second fresh hardware reading can confirm a manual override")
}
