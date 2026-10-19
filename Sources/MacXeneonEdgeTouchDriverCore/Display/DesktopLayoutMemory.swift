import CoreGraphics
import Foundation

struct DesktopScreen: Codable, Equatable {
    var uuid: String
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    var builtIn: Bool
    var frame: CGRect
    var rotation: Int
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
    // A runtime ID is never used as a persistent identity.
    var runtimeID: UInt32

    func sameHardware(as other: DesktopScreen) -> Bool {
        vendor == other.vendor && model == other.model && serial == other.serial && builtIn == other.builtIn
    }

    func sameGeometry(as other: DesktopScreen) -> Bool {
        frame == other.frame && rotation == other.rotation && width == other.width && height == other.height &&
        pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight && abs(refreshRate - other.refreshRate) < 1
    }
}

struct DesktopWindow: Codable, Equatable {
    var bundleID: String
    var pid: Int32
    var launchedAt: Double
    var windowID: UInt32
    var screenUUID: String
    var frame: CGRect
    // Optional for backward-compatible loading of reconnect-only snapshots.
    // Only locally salted hashes are persisted, never readable titles or URLs.
    var identifierHash: String? = nil
    var documentHash: String? = nil
    var titleHash: String? = nil
    var key: String { "\(pid):\(launchedAt):\(windowID)" }
}

struct DesktopLayout: Codable, Equatable {
    var version = 1
    var screens: [DesktopScreen]
    var windows: [DesktopWindow]

    var isValid: Bool {
        version == 1 && screens.count >= 2 && screens.count <= 16 &&
        Set(screens.map(\.uuid)).count == screens.count &&
        screens.filter(\.builtIn).count == 1 &&
        screens.allSatisfy { !$0.uuid.isEmpty && [0,90,180,270].contains($0.rotation) &&
            validFrame($0.frame) && $0.width > 0 && $0.height > 0 && $0.width <= 16384 && $0.height <= 16384 &&
            $0.pixelWidth > 0 && $0.pixelHeight > 0 && $0.pixelWidth <= 32768 && $0.pixelHeight <= 32768 &&
            $0.refreshRate.isFinite && (0...1000).contains($0.refreshRate) } &&
        windows.count <= 512 && Set(windows.map(\.key)).count == windows.count &&
        windows.allSatisfy { window in validFrame(window.frame) && window.launchedAt.isFinite && window.pid > 0 && window.windowID > 0 &&
            screens.contains(where: { $0.uuid == window.screenUUID }) &&
            [window.identifierHash, window.documentHash, window.titleHash].allSatisfy {
                $0 == nil || ($0!.count == 64 && $0!.allSatisfy { "0123456789abcdef".contains($0) })
            } }
    }

    private func validFrame(_ r: CGRect) -> Bool {
        [r.minX,r.minY,r.width,r.height].allSatisfy { $0.isFinite && abs($0) < 100_000 } && r.width > 0 && r.height > 0
    }

    /// UUID first; a unique hardware descriptor also survives a recreated DisplayLink UUID.
    /// Ambiguous or partial topologies are never guessed at or applied.
    func matches(_ live: [DesktopScreen]) -> [String: DesktopScreen]? {
        guard live.count == screens.count else { return nil }
        var result: [String: DesktopScreen] = [:]
        var used = Set<UInt32>()
        for saved in screens {
            let exact = live.filter { $0.uuid == saved.uuid && $0.sameHardware(as: saved) }
            let candidates = exact.isEmpty ? live.filter { $0.sameHardware(as: saved) } : exact
            guard candidates.count == 1, let match = candidates.first, used.insert(match.runtimeID).inserted else { return nil }
            result[saved.uuid] = match
        }
        return result
    }

    /// Preserve the MacBook's current mode. If its width changed while undocked,
    /// keep a right-hand screen attached to its new right edge.
    func targetOrigin(for saved: DesktopScreen, matches: [String: DesktopScreen]) -> CGPoint {
        guard let main = screens.first(where: \.builtIn), let currentMain = matches[main.uuid] else { return saved.frame.origin }
        var origin = saved.frame.origin
        origin.x += currentMain.frame.minX - main.frame.minX
        origin.y += currentMain.frame.minY - main.frame.minY
        if saved.frame.minX >= main.frame.maxX - 1 { origin.x += currentMain.frame.width - main.frame.width }
        return origin
    }

    func needsExternalDisplayRestore(matches: [String: DesktopScreen]) -> Bool {
        screens.contains { saved in
            guard !saved.builtIn else { return false }
            guard let live = matches[saved.uuid] else { return true }
            return live.frame.origin != targetOrigin(for: saved, matches: matches) ||
                live.rotation != saved.rotation || live.width != saved.width || live.height != saved.height ||
                live.pixelWidth != saved.pixelWidth || live.pixelHeight != saved.pixelHeight ||
                abs(live.refreshRate - saved.refreshRate) >= 1
        }
    }

    func targetFrame(for window: DesktopWindow, matches: [String: DesktopScreen]) -> CGRect? {
        guard let saved = screens.first(where: { $0.uuid == window.screenUUID }), let live = matches[saved.uuid] else { return nil }
        var result = window.frame.offsetBy(dx: live.frame.minX - saved.frame.minX, dy: live.frame.minY - saved.frame.minY)
        result.size.width = min(result.width, live.frame.width)
        result.size.height = min(result.height, live.frame.height)
        result.origin.x = max(live.frame.minX, min(result.minX, live.frame.maxX - result.width))
        result.origin.y = max(live.frame.minY, min(result.minY, live.frame.maxY - result.height))
        return result
    }
}

/// Small pure state machine: a missing/late monitor must never replace the docked snapshot.
struct DesktopLayoutPolicy {
    enum Action: Equatable { case wait, capture, restore }
    var needsRestore: Bool
    var attempts = 0
    var failed = false
    init(hasSavedLayout: Bool) { needsRestore = hasSavedLayout }
    mutating func membershipChanged() { needsRestore = true; attempts = 0; failed = false }
    mutating func action(hasLayout: Bool, completeMatch: Bool, canLearn: Bool) -> Action {
        if !hasLayout { return canLearn ? .capture : .wait }
        guard completeMatch else { needsRestore = true; return .wait }
        if failed { return .wait }
        return needsRestore ? .restore : .capture
    }
    mutating func restoreFailed() { attempts += 1; failed = attempts >= 3 }
    mutating func restored() { needsRestore = false; attempts = 0; failed = false }
}
