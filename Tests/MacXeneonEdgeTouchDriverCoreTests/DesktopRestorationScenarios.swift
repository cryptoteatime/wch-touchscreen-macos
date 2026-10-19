import CoreGraphics
import Foundation
#if !WCH_STANDALONE
@testable import MacXeneonEdgeTouchDriverCore
#endif

func exerciseDesktopRestoration(_ check: (Bool, String) -> Void) throws {
    func window(_ id: UInt32, _ pid: Int32, app: String = "example.editor", title: String? = nil) -> DesktopWindow {
        DesktopWindow(bundleID: app, pid: pid, launchedAt: Double(pid), windowID: id,
            screenUUID: "screen", frame: CGRect(x: 100, y: 80, width: 600, height: 800), titleHash: title)
    }
    let a = window(10, 100), rebooted = window(99, 200)
    check(DesktopWindowMatcher.matches(saved: [a], live: [rebooted]).first?.liveKey == rebooted.key,
          "A single-window app restores after both process and window IDs change")
    var renamed = rebooted; renamed.titleHash = "new-title"
    check(DesktopWindowMatcher.matches(saved: [a], live: [renamed]).count == 1, "Single-window title changes do not prevent restoration")
    let otherApp = window(10, 100, app: "example.other")
    check(DesktopWindowMatcher.matches(saved: [a], live: [otherApp]).isEmpty, "Reused process/window IDs cannot match another app")
    let b = window(11, 100)
    check(DesktopWindowMatcher.matches(saved: [a, b], live: [rebooted]).isEmpty, "A missing second window cannot make a multi-window app unambiguous")
    let second = window(98, 200)
    check(DesktopWindowMatcher.matches(saved: [a], live: [rebooted, second]).isEmpty, "An unexpected extra live window blocks bundle-only matching")
    check(DesktopWindowMatcher.matches(saved: [a, b], live: [second, rebooted]).isEmpty, "Enumeration order never decides two anonymous windows")
    var docA = a; docA.documentHash = "document-a"
    var docB = b; docB.documentHash = "document-b"
    var newA = rebooted; newA.documentHash = "document-a"
    var newB = second; newB.documentHash = "document-b"
    let documents = DesktopWindowMatcher.matches(saved: [docA, docB], live: [newB, newA])
    check(documents.first(where: { $0.savedKey == a.key })?.liveKey == newA.key, "Document identity survives reordered windows")
    check(documents.first(where: { $0.savedKey == b.key })?.liveKey == newB.key, "Second document retains its own destination")
    var titleA = a; titleA.titleHash = "one"
    var titleB = b; titleB.titleHash = "two"
    var newTitleA = rebooted; newTitleA.titleHash = "one"
    var newTitleB = second; newTitleB.titleHash = "two"
    check(DesktopWindowMatcher.matches(saved: [titleA, titleB], live: [newTitleB, newTitleA]).count == 2, "Unique titles identify multiple windows")
    titleB.titleHash = "one"; newTitleB.titleHash = "one"
    check(DesktopWindowMatcher.matches(saved: [titleA, titleB], live: [newTitleA, newTitleB]).isEmpty, "Duplicate titles stay unresolved")
    docA.identifierHash = "generic"; docB.identifierHash = "generic"
    newA.identifierHash = "generic"; newB.identifierHash = "generic"
    check(DesktopWindowMatcher.matches(saved: [docA, docB], live: [newB, newA]).count == 2, "Generic AX identifiers do not defeat unique document identity")
    var sameRuntime = docA; sameRuntime.documentHash = "renamed"
    check(DesktopWindowMatcher.matches(saved: [docA, docB], live: [sameRuntime, newB]).first?.liveKey == docA.key, "Exact runtime identity takes priority on reconnect")
    let done = [docA.key: newA.key]
    let later = DesktopWindowMatcher.matches(saved: [docA, docB], live: [newA, newB], completed: done)
    check(later.count == 1 && later[0].savedKey == docB.key, "A slow-opening second window does not move the first twice")
    var progress = DesktopWindowRestoreProgress()
    progress.begin(at: 10); progress.begin(at: 100)
    check(progress.startedAt == 10, "New app arrivals do not extend the launch deadline forever")
    check(progress.hasTimeRemaining(at: 189) && !progress.hasTimeRemaining(at: 190), "Launch grace is bounded to three minutes")
    progress.bindings[a.key] = rebooted.key
    check(progress.waitingKeys(in: [a,b]) == [b.key], "Only unmatched windows remain pending")
    progress.failures[b.key] = 3
    check(progress.waitingKeys(in: [a,b]).isEmpty && progress.failedKeys == [b.key], "Refused windows stop retrying after three failures")
    let legacy = try JSONSerialization.data(withJSONObject: ["bundleID":"example.editor", "pid":100,
        "launchedAt":100, "windowID":10, "screenUUID":"screen", "frame":[[100,80],[600,800]]])
    let decoded = try JSONDecoder().decode(DesktopWindow.self, from: legacy)
    check(decoded.titleHash == nil && decoded.identifierHash == nil, "Existing reconnect snapshots migrate without losing their windows")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let hash = DesktopWindowFingerprint(directory: directory)
    let value = hash.hash("Private document", kind: "example:title")
    check(value?.count == 64 && value != "Private document", "Fingerprints never persist readable titles")
    check(value == DesktopWindowFingerprint(directory: directory).hash("Private document", kind: "example:title"), "Fingerprint salt survives a new process")
    check(value != hash.hash("Private document", kind: "other:title"), "Fingerprint namespaces distinguish applications")
    let otherDirectory = directory.appendingPathComponent("other")
    check(value != DesktopWindowFingerprint(directory: otherDirectory).hash("Private document", kind: "example:title"), "Different installations have different fingerprints")
    check(hash.hash("  ", kind: "title") == nil, "Empty metadata is not an identity")
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("window-identity-salt").path)
    check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Local identity salt is private to the user")

    // A complete saved desk must survive apps closing before the logout notice.
    var capture = DesktopLayoutCaptureGuard(now: 0)
    check(!capture.allowsCapture(saved: [a,b], live: [a,b], at: 59), "Login does not immediately overwrite the saved layout")
    check(capture.allowsCapture(saved: [a,b], live: [a,b], at: 60), "Ordinary learning resumes after login settles")
    var moved = a; moved.frame.origin.x += 50
    check(capture.allowsCapture(saved: [a,b], live: [moved,b], at: 61), "Normal window moves are learned without a removal delay")
    check(!capture.allowsCapture(saved: [a,b], live: [a], at: 62), "The first disappearing window does not shrink the saved snapshot")
    check(capture.pendingRemovalCount == 1, "Status reports the missing saved window")
    check(!capture.allowsCapture(saved: [a,b], live: [a], at: 121), "A partial layout remains protected during teardown")
    check(capture.allowsCapture(saved: [a,b], live: [a], at: 122), "An intentional stable closure is eventually learned")
    check(capture.allowsCapture(saved: [a,b], live: [a,b], at: 123) && capture.pendingRemovalCount == 0,
          "A window returning clears the removal candidate")
    check(!capture.allowsCapture(saved: [a,b], live: [a], at: 124), "A later closure starts a fresh delay")
    check(!capture.allowsCapture(saved: [a,b], live: [], at: 130), "Closing the remaining app cannot replace the snapshot with an empty desk")
    check(!capture.allowsCapture(saved: [a,b], live: [], at: 1000), "An empty AX response never automatically erases a saved desk")
    check(!capture.allowsCapture(saved: [a,b], live: [b], at: 1001), "A changed missing-window set restarts the settling period")
    check(capture.allowsCapture(saved: [a,b], live: [a,b], at: 1002), "Transient Accessibility omissions recover normally")
    check(capture.allowsCapture(saved: [a], live: [rebooted], at: 1003), "A uniquely relaunched app is a replacement, not a lost window")
    capture.beginRecovery(at: 1010)
    check(capture.isRecovering(at: 1039) && !capture.isRecovering(at: 1040), "Reconnect protects late display changes for thirty seconds")
    check(!capture.allowsCapture(saved: [a], live: [rebooted], at: 1030), "Late display enumeration cannot be learned as a new arrangement")
    capture.beginRecovery(at: 1035)
    check(capture.isRecovering(at: 1064), "A second arriving monitor extends the reconnect protection")
    capture.acceptExplicitSave(at: 1040)
    check(!capture.isRecovering(at: 1040) && capture.pendingRemovalCount == 0,
          "An explicit save immediately accepts the user's chosen arrangement")
    var fresh = DesktopLayoutCaptureGuard(now: 0)
    fresh.beginRecovery(at: 5)
    check(fresh.isRecovering(at: 59), "An early display callback cannot shorten login protection")
}

func exerciseDesktopLayoutReadiness(_ check: (Bool, String) -> Void) {
    func screen(_ name: String, _ id: UInt32, builtIn: Bool = false) -> DesktopScreen {
        DesktopScreen(uuid: name, vendor: 1, model: 2, serial: id, builtIn: builtIn,
            frame: CGRect(x: builtIn ? 0 : 1500, y: 0, width: 1050, height: 1680),
            rotation: builtIn ? 0 : 90, width: 1050, height: 1680, pixelWidth: 1050,
            pixelHeight: 1680, refreshRate: 60, runtimeID: id)
    }
    let mac = screen("mac", 1, builtIn: true), external = screen("external", 2)
    let screens = [mac, external]
    var signals = DesktopLayoutSignals(now: 0)
    var ready = DesktopLayoutReadiness()
    check(!ready.observe(screens, displayRevision: signals.displayRevision, at: 0), "One display reading cannot establish readiness")
    check(!signals.canRestore(at: 0.49), "Restore retains a short display settling interval")
    check(!ready.observe(screens, displayRevision: signals.displayRevision, at: 0.49), "Stable readings must span the confirmation interval")
    check(ready.observe(Array(screens.reversed()), displayRevision: signals.displayRevision, at: 0.5) && signals.canRestore(at: 0.5),
          "Matching display readings permit prompt restoration regardless of enumeration order")
    let beforeLaunch = signals.revision, displayRevision = signals.displayRevision
    for index in 1...10 { signals.applicationChanged(at: Double(index) / 4) }
    check(signals.displayRevision == displayRevision && signals.canRestore(at: 2.5), "Continuous app launches do not reset display readiness")
    check(ready.observe(screens, displayRevision: signals.displayRevision, at: 2.5), "App events retain confirmed display geometry")
    check(!signals.isCurrent(beforeLaunch), "An app lifecycle change still invalidates an in-flight snapshot")
    check(!signals.canCapture(at: 5.49) && signals.canCapture(at: 5.5), "Saving still waits three quiet seconds after app activity")
    signals.displayCallback(1, beginning: true, at: 6)
    signals.displayCallback(2, beginning: true, at: 6)
    check(!signals.canRestore(at: 10) && !signals.isCurrent(signals.revision), "An unfinished OS configuration cannot be treated as ready after a timeout")
    signals.displayCallback(1, beginning: false, at: 10)
    check(!signals.canRestore(at: 11), "Each display must finish its configuration callback")
    signals.displayCallback(2, beginning: false, at: 11)
    check(!ready.observe(screens, displayRevision: signals.displayRevision, at: 11), "Completed configuration starts a fresh geometry confirmation")
    check(ready.observe(screens, displayRevision: signals.displayRevision, at: 11.5) && signals.canRestore(at: 11.5),
          "The final configuration callback unlocks the confirmed display state")
    check(!signals.canCapture(at: 13.99) && signals.canCapture(at: 14), "Faster restore does not shorten the display capture guard")
    var rotated = external; rotated.rotation = 270
    check(!ready.observe([mac, rotated], displayRevision: signals.displayRevision, at: 12), "A rotation change without a callback still restarts confirmation")
    check(ready.observe([mac, rotated], displayRevision: signals.displayRevision, at: 12.5), "Stable new rotation can advance to the next configuration stage")
    var relocated = rotated; relocated.frame.origin.x += 100
    check(!ready.observe([mac, relocated], displayRevision: signals.displayRevision, at: 13), "Origin changes must settle independently")
    var scaled = relocated; scaled.pixelWidth *= 2
    check(!ready.observe([mac, scaled], displayRevision: signals.displayRevision, at: 13.5), "A late scaling change prevents window placement")
    var replacement = scaled; replacement.runtimeID = 99
    check(!ready.observe([mac, replacement], displayRevision: signals.displayRevision, at: 14), "A replacement runtime endpoint must be confirmed again")
    check(!ready.observe([], displayRevision: signals.displayRevision, at: 14.25), "Empty enumeration never becomes ready")
    check(!ready.observe(screens, displayRevision: signals.displayRevision, at: 14.5), "A returning display set needs fresh observations")
    check(ready.observe(screens, displayRevision: signals.displayRevision, at: 15), "Readiness recovers after transient empty enumeration")
    let beforeSleep = signals.revision
    signals.sleepChanged(true, at: 16)
    check(!signals.canRestore(at: 20) && !signals.canCapture(at: 20) && !signals.isCurrent(beforeSleep), "Sleep fences restoration and snapshot commits")
    signals.sleepChanged(false, at: 21)
    check(!signals.canRestore(at: 21.49) && signals.canRestore(at: 21.5), "Wake starts its own display settling interval")
    check(!ready.observe(screens, displayRevision: signals.displayRevision, at: 21.5), "Wake cannot reuse pre-sleep display confirmation")
    var pacing = DesktopLayoutAttemptPacing()
    check(pacing.delay(for: screens, at: 0) == 0, "The first confirmed layout attempt has no polling delay")
    pacing.attempted(screens, at: 0)
    check(pacing.delay(for: Array(screens.reversed()), at: 0.25) == 1.75, "Fast callbacks cannot consume retry budgets more quickly")
    check(pacing.delay(for: screens, at: 2) == 0, "Unchanged-state retries retain the two-second cadence")
    check(pacing.delay(for: [mac, rotated], at: 0.5) == 0, "Actual geometry progress can advance without another retry interval")
    pacing.attempted([mac, rotated], at: 0.5)
    check(pacing.delay(for: [mac, rotated], at: 1) == 1.5, "A no-effect configuration or refused window write cannot retry on every fast probe")
    let saved = DesktopLayout(screens: screens, windows: [])
    var policy = DesktopLayoutPolicy(hasSavedLayout: true)
    check(policy.action(hasLayout: true, completeMatch: saved.matches([mac]) != nil, canLearn: false) == .wait,
          "A stable but incomplete monitor set still cannot restore")
    check(policy.action(hasLayout: true, completeMatch: saved.matches(screens) != nil, canLearn: true) == .restore,
          "Confirmed complete topology restores before learning")
    var capture = DesktopLayoutCaptureGuard(now: 0)
    check(!capture.allowsCapture(saved: [], live: [], at: 0.5), "Fast startup restoration cannot overwrite the protected snapshot")
    capture.beginRecovery(at: 100)
    check(!capture.allowsCapture(saved: [], live: [], at: 101), "Fast reconnect readiness preserves the thirty-second snapshot guard")
}
