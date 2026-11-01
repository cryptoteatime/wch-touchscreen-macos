import Foundation

/// Independent snapshots for complete active monitor sets (including clamshell).
/// Never replace the open-lid desktop with a partial disconnected snapshot.
struct DesktopLayoutLibrary: Codable {
    var version = 2
    var layouts: [DesktopLayout] = []

    var isValid: Bool {
        version == 2 && layouts.count <= 8 && layouts.allSatisfy(\.isValid) &&
        Set(layouts.map { $0.screens.map(\.uuid).sorted().joined(separator: "|") }).count == layouts.count
    }

    static func load(_ data: Data) throws -> DesktopLayoutLibrary {
        let decoder = JSONDecoder()
        if let library = try? decoder.decode(Self.self, from: data), library.isValid { return library }
        let legacy = try decoder.decode(DesktopLayout.self, from: data)
        guard legacy.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return Self(layouts: [legacy])
    }

    enum Selection: Equatable { case existing(Int), new, ambiguous }

    func permitsLearning(_ screens: [DesktopScreen], profiles: [MonitorProfile]?, vendor: UInt32?, model: UInt32?) -> Bool {
        guard screens.filter(\.builtIn).count <= 1, screens.contains(where: { !$0.builtIn }) else { return false }
        if let profiles {
            let selected = profiles.filter { $0.touchEnabled || $0.brightnessConnection != .off }
            let snapshots = screens.map { DisplaySnapshot(displayID: $0.runtimeID, vendorNumber: $0.vendor, modelNumber: $0.model,
                serialNumber: $0.serial, bounds: $0.frame, pixelsWide: $0.pixelWidth, pixelsHigh: $0.pixelHeight,
                rotationDegrees: $0.rotation, uuid: $0.uuid, builtIn: $0.builtIn) }
            let resolved = MonitorProfileRouting.resolved(profiles, displays: snapshots)
            return !selected.isEmpty && selected.allSatisfy { resolved[$0.displayUUID] != nil }
        }
        let matching = { (screens: [DesktopScreen]) in screens.filter { !$0.builtIn && $0.vendor == vendor && $0.model == model }.count }
        // A legacy two-panel snapshot must not learn one panel as a new setup
        // during a prolonged partial disconnect. New single-panel installs work.
        let required = max(1, layouts.map { matching($0.screens) }.max() ?? 0)
        return matching(screens) >= required
    }

    func selection(for screens: [DesktopScreen]) -> Selection {
        let candidates = layouts.indices.filter { layouts[$0].matches(screens) != nil }
        let exact = candidates.filter { Set(layouts[$0].screens.map(\.uuid)) == Set(screens.map(\.uuid)) }
        let preferred = exact.isEmpty ? candidates : exact
        if preferred.count == 1 { return .existing(preferred[0]) }
        return preferred.isEmpty ? .new : .ambiguous
    }

    mutating func remember(_ layout: DesktopLayout) throws {
        guard layout.isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        switch selection(for: layout.screens) {
        case .existing(let index): layouts[index] = layout
        case .new:
            guard layouts.count < 8 else { throw CocoaError(.fileWriteOutOfSpace) }
            layouts.append(layout)
        case .ambiguous: throw CocoaError(.fileWriteUnknown)
        }
    }
}
