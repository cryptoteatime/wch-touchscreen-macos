import CoreGraphics
import Foundation

@main struct VerifyRemember {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func display(_ id: UInt32, _ serial: UInt32, _ x: Int = 0) -> DisplaySnapshot {
            DisplaySnapshot(displayID: id, vendorNumber: 19083, modelNumber: 8704, serialNumber: serial,
                bounds: CGRect(x: x, y: 0, width: 1200, height: 1920), pixelsWide: 1200, pixelsHigh: 1920, rotationDegrees: 90)
        }
        let a = TouchDeviceIdentity(locationID: 100, serialNumber: "duplicate", registryEntryID: 1)
        let b = TouchDeviceIdentity(locationID: 200, serialNumber: "duplicate", registryEntryID: 2)
        let devices: Set<TouchDeviceIdentity> = [a, b]
        let screens = [display(3, 0), display(5, 26, 1200)]
        let url = root.appendingPathComponent("pairings.json")
        let initial = PairingStore(url: url, bootSessionIdentifier: "boot-one", observationSession: "one", rememberConnections: true)
        try initial.assign(device: a, to: screens[0], connectedDevices: devices, displays: screens)
        try initial.assign(device: b, to: screens[1], connectedDevices: devices, displays: screens)
        check(initial.pairings.count == 2 && initial.pairings.allSatisfy { $0.scope == .connection }, "Must save two port associations")
        try initial.invalidateAmbiguous()
        check(initial.pairings.count == 2, "Hotplug revocation must retain port associations")
        let rebooted = PairingStore(url: url, bootSessionIdentifier: "boot-two", observationSession: "two", rememberConnections: true)
        let a2 = TouchDeviceIdentity(locationID: 100, serialNumber: "duplicate", registryEntryID: 101)
        let b2 = TouchDeviceIdentity(locationID: 200, serialNumber: "duplicate", registryEntryID: 102)
        let reconnected: Set<TouchDeviceIdentity> = [b2, a2]
        let newScreens = [display(99, 26, -1200), display(98, 0, 2400)]
        check(rebooted.resolveDisplay(for: a2, connectedDevices: reconnected, displays: newScreens)?.displayID == 98, "Left survives new boot, new registry and display IDs, and geometry")
        check(rebooted.resolveDisplay(for: b2, connectedDevices: reconnected, displays: newScreens)?.displayID == 99, "Right survives new boot")
        let moved = TouchDeviceIdentity(locationID: 300, serialNumber: "duplicate", registryEntryID: 103)
        check(rebooted.resolveDisplay(for: moved, connectedDevices: [moved,b2], displays: newScreens) == nil, "Changed USB port must require pairing")
        let replacement = TouchDeviceIdentity(locationID: 100, serialNumber: "different", registryEntryID: 104)
        check(rebooted.resolveDisplay(for: replacement, connectedDevices: [replacement,b2], displays: newScreens) == nil, "Different controller descriptor must not reuse pairing")
        let ambiguous = [display(98,0), display(100,0), display(99,26)]
        check(rebooted.resolveDisplay(for: a2, connectedDevices: reconnected, displays: ambiguous) == nil, "Duplicate display descriptors must not route")
        check(rebooted.resolveDisplay(for: b2, connectedDevices: reconnected, displays: ambiguous)?.displayID == 99, "Independent valid endpoint still routes")
        let off = PairingStore(url: url, bootSessionIdentifier: "boot-two", observationSession: "two", rememberConnections: false)
        check(off.resolveDisplay(for: a2, connectedDevices: reconnected, displays: newScreens) == nil, "Feature opt-out must revoke port trust")
        try rebooted.invalidateAll()
        check(rebooted.pairings.isEmpty, "Explicit re-pair clears persistent connections")
        // Upgrade only physically verified associations whose same-boot incarnations still match.
        let legacyURL = root.appendingPathComponent("legacy.json")
        let legacy = PairingStore(url: legacyURL, bootSessionIdentifier: "boot-one", observationSession: "old")
        try legacy.assign(device: a, to: screens[0], connectedDevices: devices, displays: screens)
        try legacy.assign(device: b, to: screens[1], connectedDevices: devices, displays: screens)
        let expired = PairingStore(url: legacyURL, bootSessionIdentifier: "different-boot", observationSession: "new", rememberConnections: true)
        try expired.rememberVerifiedRuntimePairings(connectedDevices: devices, displays: screens)
        check(expired.pairings.isEmpty, "Prior-boot runtime records must not migrate")
        let migration = PairingStore(url: legacyURL, bootSessionIdentifier: "boot-one", observationSession: "new", rememberConnections: true)
        try migration.rememberVerifiedRuntimePairings(connectedDevices: reconnected, displays: screens)
        check(migration.pairings.isEmpty, "Re-enumerated devices must not migrate old runtime authority")
        try migration.rememberVerifiedRuntimePairings(connectedDevices: devices, displays: screens)
        check(migration.pairings.count == 2 && migration.pairings.allSatisfy { $0.scope == .connection }, "Verified attached pairings migrate without extra taps")
        let migratedReload = PairingStore(url: legacyURL, bootSessionIdentifier: "next-boot", observationSession: "next", rememberConnections: true)
        check(migratedReload.resolveDisplay(for: a2, connectedDevices: reconnected, displays: newScreens)?.displayID == 98, "Migrated mapping is durable")
        // A pair with identical display descriptors cannot be made persistent by location alone.
        let ambiguousStore = PairingStore(url: root.appendingPathComponent("ambiguous.json"), bootSessionIdentifier: "boot-one", rememberConnections: true)
        try ambiguousStore.assign(device: a, to: ambiguous[0], connectedDevices: devices, displays: ambiguous)
        check(ambiguousStore.pairings[0].scope == .bootSession, "Ambiguous displays keep session-only pairing")
        let configURL = root.appendingPathComponent("config.json")
        try Data("{\"rememberConnections\":true}".utf8).write(to: configURL)
        check(DriverConfiguration.load(from: configURL).configuration.rememberConnections, "Configuration opt-in loads")
        try Data("{}".utf8).write(to: configURL)
        check(!DriverConfiguration.load(from: configURL).configuration.rememberConnections, "Configuration remains opt-in")
        check(!DriverConfiguration.load(from: configURL).configuration.restorePreviousFocus, "Normal touch keeps focus on the touched window")
        try Data("{\"restorePreviousFocus\":true}".utf8).write(to: configURL)
        check(DriverConfiguration.load(from: configURL).configuration.restorePreviousFocus, "Optional previous-window focus restoration loads")
        let queue = DispatchQueue(label: "local.gesture-regression")
        let sink = CountedClicks()
        let cursor = TestCursor()
        let gesture = GestureController(mapperProvider: { CoordinateMapper(displayBounds: CGRect(x: 0, y: 0, width: 1200, height: 1920)) },
            inputSink: sink, cursorController: cursor,
            timing: GestureTiming(warpToClickDelayMs: 0, downToUpDelayMs: 20, clickToWarpBackDelayMs: 10, tapDebounceMs: 50, holdToDragMs: 30),
            schedulingQueue: queue)
        queue.sync {
            gesture.handle(TouchEvent(kind: .down, contactID: 0, rawX: 8000, rawY: 4000, timestamp: .now()))
            gesture.handle(TouchEvent(kind: .up, contactID: 0, rawX: 8000, rawY: 4000, timestamp: .now()))
        }
        Thread.sleep(forTimeInterval: 0.08)
        queue.sync { check(sink.events == ["down:1", "up:1"], "One quick tap must emit exactly one click") }
        queue.sync {
            sink.events = []
            gesture.forceCancel()
            gesture.handle(TouchEvent(kind: .down, contactID: 0, rawX: 8000, rawY: 4000, timestamp: .now()))
        }
        Thread.sleep(forTimeInterval: 0.07)
        queue.sync { gesture.handle(TouchEvent(kind: .up, contactID: 0, rawX: 8000, rawY: 4000, timestamp: .now())) }
        Thread.sleep(forTimeInterval: 0.06)
        queue.sync { check(sink.events == ["down:1", "up:1"], "One held contact must emit exactly one click") }
        print("Persistent connection and gesture regression checks passed: \(checks)")
    }
}

private final class CountedClicks: SyntheticInputSink {
    var events: [String] = []
    func postMouseDown(at: CGPoint, clickCount: Int) { events.append("down:\(clickCount)") }
    func postMouseUp(at: CGPoint, clickCount: Int) { events.append("up:\(clickCount)") }
    func postRightMouseDown(at: CGPoint) { events.append("rightDown") }
    func postRightMouseUp(at: CGPoint) { events.append("rightUp") }
    func postMouseDragged(to: CGPoint) {}
    func postScroll(deltaX: CGFloat, deltaY: CGFloat, phase: SyntheticScrollPhase) {}
}
private final class TestCursor: CursorController {
    func borrow(warpingTo: CGPoint) -> Bool { true }
    func updatePosition(_ point: CGPoint) {}
    func returnToOrigin() {}
    func forceShow() {}
}
