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
}
