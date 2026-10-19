import Foundation
import CoreGraphics
#if !WCH_STANDALONE
@testable import MacXeneonEdgeTouchDriverCore
#endif

func exerciseMonitorProfiles(_ check: (Bool, String) -> Void) throws {
    let uuidA = "00000000-0000-4000-8000-000000000001"
    let uuidB = "00000000-0000-4000-8000-000000000002"
    var a = MonitorProfile(displayUUID: uuidA, name: "Left", hardwareName: "Panel A", vendor: 1, model: 2, serial: 0,
        touchEnabled: true, brightnessConnection: .automatic, brightnessBehavior: .global, nativeBrightnessKey: "native:fixture-a")
    var b = MonitorProfile(displayUUID: uuidB, name: "Right", hardwareName: "Panel B", vendor: 3, model: 4, serial: 5,
        touchEnabled: true, brightnessConnection: .automatic, brightnessBehavior: .independent, nativeBrightnessKey: "native:fixture-b")
    func display(_ p: MonitorProfile, id: UInt32, builtIn: Bool = false) -> DisplaySnapshot {
        DisplaySnapshot(displayID: id, vendorNumber: p.vendor, modelNumber: p.model, serialNumber: p.serial,
            bounds: CGRect(x: Int(id) * 100, y: -300, width: 1050, height: 1680), pixelsWide: 1050, pixelsHigh: 1680,
            rotationDegrees: 90, uuid: p.displayUUID, builtIn: builtIn)
    }
    let da = display(a, id: 2), db = display(b, id: 3)
    let na = MonitorBrightnessIdentity(transport: .native, key: "native:fixture-a", name: "Panel A", vendor: 1, model: 2)
    let nb = MonitorBrightnessIdentity(transport: .native, key: "native:fixture-b", name: "Panel B", vendor: 3, model: 4)
    let dlb = MonitorBrightnessIdentity(transport: .displayLink, key: "displaylink:" + uuidB, name: "Panel B", vendor: 3, model: 4)
    check(MonitorProfile.valid([a, b]), "Different models have independent valid profiles")
    check(!MonitorProfile.valid([a, a]), "Duplicate display profiles are rejected")
    var bad = a; bad.displayUUID = "invalid"
    check(!bad.isValid, "Malformed UUIDs cannot become display selectors")
    check(a.matches(da) && !a.matches(db), "Profiles match the complete identity")
    check(a.matches(display(a, id: 99)), "Changing runtime display IDs does not invalidate a profile")
    check(!a.matches(display(a, id: 1, builtIn: true)), "The built-in screen cannot be selected")
    bad = a; bad.vendor = 99
    check(!bad.matches(da), "A reused UUID with changed hardware cannot match")
    bad = a; bad.serial = 42
    check(!bad.matches(da), "Changed serials are not silently accepted")
    var config = DriverConfiguration.defaults; config.monitors = [a, b]
    check(DisplayResolver(configuration: config).matchingDisplays(from: [db, da]).map(\.displayID) == [2, 3], "Mixed-model portrait touch selection is independent of legacy resolution")
    config.monitors = [a]
    check(DisplayResolver(configuration: config).matchingDisplays(from: [da, db]).map(\.displayID) == [2], "Unselected models do not enter touch pairing")
    a.touchEnabled = false; config.monitors = [a, b]
    check(DisplayResolver(configuration: config).matchingDisplays(from: [da, db]).map(\.displayID) == [3], "Touch can be disabled without removing brightness selection")
    a.touchEnabled = true
    config.monitors = []
    check(DisplayResolver(configuration: config).matchingDisplays(from: [da, db]).isEmpty, "An explicit empty profile list never falls back to legacy matching")
    config.monitors = [a, b]
    check(DisplayResolver(configuration: config).matchingDisplays(from: [da, display(a, id: 88)]).isEmpty, "Duplicate live identities are not guessed")

    let direct = MonitorProfileRouting.selected([a, b], displays: [da, db], native: [na, nb], displayLink: [])
    check(Set(direct.keys) == Set([na, nb]), "Two different native monitors work without DisplayLink")
    check(!MonitorProfileRouting.needsDisplayLink([a, b], displays: [da, db], native: [na, nb]), "Native-only setups do not request the DisplayLink integration")
    check(MonitorProfileRouting.needsDisplayLink([a, b], displays: [da, db], native: [na]), "The unmatched automatic monitor can discover DisplayLink")
    let mixed = MonitorProfileRouting.selected([a, b], displays: [da, db], native: [na], displayLink: [dlb])
    check(Set(mixed.keys) == Set([na, dlb]), "Mixed native and DisplayLink connections select a route per monitor")
    let preferred = MonitorProfileRouting.selected([a, b], displays: [da, db], native: [na, nb], displayLink: [dlb])
    check(preferred[nb] == b && preferred[dlb] == nil, "Automatic emits only one route and prefers native")
    b.brightnessConnection = .displayLink
    let forced = MonitorProfileRouting.selected([a, b], displays: [da, db], native: [na, nb], displayLink: [dlb])
    check(forced[dlb] == b && forced[nb] == nil, "An explicit DisplayLink profile never writes through native too")
    b.brightnessConnection = .native
    check(!MonitorProfileRouting.needsDisplayLink([b], displays: [db], native: []), "Native-only selection never falls back to DisplayLink")
    b.brightnessConnection = .off
    check(MonitorProfileRouting.selected([a, b], displays: [da, db], native: [na, nb], displayLink: [dlb]).count == 1, "Disabled brightness leaves other monitors active")
    check(!MonitorProfileRouting.needsDisplayLink([b], displays: [db], native: []), "Disabled monitors do not activate DisplayLink")
    b.brightnessConnection = .automatic
    check(MonitorProfileRouting.selected([a, b], displays: [da], native: [na, nb], displayLink: [dlb]).count == 1, "Disconnected profiles cannot write to an endpoint")
    check(MonitorProfileRouting.selected([a], displays: [da], native: [na, na], displayLink: []).isEmpty, "Ambiguous native endpoints are skipped")
    check(MonitorProfileRouting.selected([a, a], displays: [da], native: [na], displayLink: []).isEmpty, "One endpoint cannot be assigned to two profiles")
    check(a.follows(global: true) && !a.follows(global: false) && !b.follows(global: true), "Global and independent behavior differ per monitor")
    b.brightnessBehavior = .follow
    check(b.follows(global: false), "A per-monitor follow override works when global follow is off")

    let samples = [MonitorBrightnessSample(identity: na, connection: "a", level: 0.85),
                   MonitorBrightnessSample(identity: nb, connection: "b", level: 0.65)]
    var policy = MonitorBrightnessPolicy(preferences: MonitorBrightnessPreferences(enabled: true, followBuiltIn: true,
        targets: [.init(identity: na, level: 0.85), .init(identity: nb, level: 0.65)]))
    _ = policy.step(samples, builtIn: 1, now: 0, following: [na])
    let writes = policy.step(samples, builtIn: 0.5, now: 1, following: [na])
    check(writes == [.init(identity: na, level: 0.5)] && policy.target(for: nb) == 0.65, "Following one monitor preserves the independent monitor's target")
    _ = policy.step([], builtIn: 0.4, now: 2, following: [na])
    check(policy.target(for: na) == 0.4 && policy.target(for: nb) == 0.65, "Offline follow updates remain scoped to the selected monitor")
    policy.preferences.followBuiltIn = false
    check(policy.step(samples, builtIn: 0.3, now: 3, following: [na]).map(\.identity) == [na], "Per-monitor following remains active with the global default off")
    let retained = policy.target(for: nb)
    _ = policy.synchronize(0.9, samples: samples, now: 4, including: [na])
    check(policy.target(for: nb) == retained, "Explicit scoped synchronization cannot change an excluded saved target")

    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temp) }
    let encoded = try JSONEncoder().encode(config)
    try encoded.write(to: temp)
    let loaded = DriverConfiguration.load(from: temp)
    check(loaded.configuration == config && loaded.warnings.isEmpty, "Profiles round-trip alongside existing touch and gesture settings")
    try Data("{\"monitors\":[{\"displayUUID\":\"bad\"}],\"gesture\":{\"scrollSensitivity\":2},\"rememberConnections\":true}".utf8).write(to: temp)
    let invalid = DriverConfiguration.load(from: temp)
    check(invalid.configuration.monitors == [] && invalid.configuration.rememberConnections && invalid.configuration.gesture.scrollSensitivity == 2 && invalid.warnings.count == 1, "Malformed profiles fail closed while preserving unrelated configuration")
    try Data("{\"display\":{\"vendorNumber\":1,\"modelNumber\":2}}".utf8).write(to: temp)
    let legacy = DriverConfiguration.load(from: temp)
    check(legacy.configuration.monitors == nil && legacy.configuration.display.vendorNumber == 1, "Legacy profiles retain their matching behavior without migration")
}
