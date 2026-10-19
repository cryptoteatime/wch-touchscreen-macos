import AppKit
import CoreGraphics
import Foundation

/// A saved display selection. The UUID belongs to the video connection, not the
/// USB touch controller; physical pairing still authorizes touch routing.
public struct MonitorProfile: Codable, Equatable {
    public enum BrightnessConnection: String, Codable, CaseIterable {
        case automatic, native, displayLink, off
    }
    public enum BrightnessBehavior: String, Codable, CaseIterable {
        case global, follow, independent
    }
    public var displayUUID: String
    public var name: String
    public var hardwareName: String
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var touchEnabled: Bool
    public var brightnessConnection: BrightnessConnection
    public var brightnessBehavior: BrightnessBehavior
    public var nativeBrightnessKey: String?

    public var isValid: Bool {
        UUID(uuidString: displayUUID) != nil && vendor != 0 && model != 0 &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 128 &&
        !hardwareName.isEmpty && hardwareName.count <= 128 &&
        (nativeBrightnessKey == nil || (nativeBrightnessKey!.hasPrefix("native:") && nativeBrightnessKey!.count <= 512))
    }
    public static func valid(_ profiles: [Self]) -> Bool {
        profiles.count <= 16 && profiles.allSatisfy(\.isValid) &&
        Set(profiles.map { $0.displayUUID.lowercased() }).count == profiles.count
    }
    func matches(uuid: String, vendor: UInt32, model: UInt32, serial: UInt32, builtIn: Bool = false) -> Bool {
        !builtIn && displayUUID.lowercased() == uuid.lowercased() &&
        self.vendor == vendor && self.model == model && self.serial == serial
    }
    func matches(_ display: DisplaySnapshot) -> Bool {
        matches(uuid: display.uuid, vendor: display.vendorNumber, model: display.modelNumber,
                serial: display.serialNumber, builtIn: display.builtIn)
    }
    func sameHardware(_ display: DisplaySnapshot) -> Bool {
        !display.builtIn && vendor == display.vendorNumber && model == display.modelNumber && serial == display.serialNumber
    }
    func accepts(_ identity: MonitorBrightnessIdentity) -> Bool {
        guard brightnessConnection != .off, vendor == identity.vendor, model == identity.model else { return false }
        switch identity.transport {
        case .native:
            guard brightnessConnection != .displayLink else { return false }
            if let nativeBrightnessKey { return nativeBrightnessKey == identity.key }
            return hardwareName == identity.name
        case .displayLink:
            return brightnessConnection != .native && identity.key.lowercased() == "displaylink:" + displayUUID.lowercased()
        }
    }
    func follows(global: Bool) -> Bool {
        brightnessBehavior == .follow || (brightnessBehavior == .global && global)
    }
}

/// Invalid explicit profiles fail closed without discarding unrelated settings.
struct MonitorProfileList: Decodable {
    var profiles: [MonitorProfile]
    var valid: Bool
    init(from decoder: Decoder) throws {
        let values = try? decoder.singleValueContainer().decode([MonitorProfile].self)
        valid = values.map(MonitorProfile.valid) ?? false
        profiles = valid ? values! : []
    }
}

/// Pure connection selection, shared by discovery and the brightness controller.
/// A route requires a unique profile and endpoint; list order is never evidence.
enum MonitorProfileRouting {
    /// Recreated video UUIDs may use a unique hardware fallback, but only if
    /// both the saved and live sets prove that descriptor is unambiguous.
    static func resolved(_ profiles: [MonitorProfile], displays: [DisplaySnapshot]) -> [String: DisplaySnapshot] {
        guard MonitorProfile.valid(profiles) else { return [:] }
        var proposals: [(String, DisplaySnapshot)] = []
        for profile in profiles {
            let exact = displays.filter { profile.matches($0) }
            if exact.count == 1 { proposals.append((profile.displayUUID, exact[0])); continue }
            guard exact.isEmpty else { continue }
            let hardware = displays.filter { profile.sameHardware($0) }
            let saved = profiles.filter { $0.vendor == profile.vendor && $0.model == profile.model && $0.serial == profile.serial }
            if saved.count == 1 && hardware.count == 1 { proposals.append((profile.displayUUID, hardware[0])) }
        }
        let uses = Dictionary(grouping: proposals, by: { $0.1.displayID }).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: proposals.filter { uses[$0.1.displayID] == 1 })
    }

    static func selected(_ profiles: [MonitorProfile], displays: [DisplaySnapshot],
                         native: [MonitorBrightnessIdentity], displayLink: [MonitorBrightnessIdentity]) -> [MonitorBrightnessIdentity: MonitorProfile] {
        var proposals: [(MonitorBrightnessIdentity, MonitorProfile)] = []
        let live = resolved(profiles, displays: displays)
        for profile in profiles where live[profile.displayUUID] != nil {
            let direct = native.filter { profile.accepts($0) }
            let linked = displayLink.filter { profile.accepts($0) }
            // Automatic prefers a uniquely identified native route. A native
            // ambiguity is not permission to send through a second connection.
            if direct.count == 1 { proposals.append((direct[0], profile)) }
            else if direct.isEmpty && linked.count == 1 { proposals.append((linked[0], profile)) }
        }
        let counts = Dictionary(grouping: proposals, by: { $0.0 }).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: proposals.filter { counts[$0.0] == 1 })
    }
    static func needsDisplayLink(_ profiles: [MonitorProfile], displays: [DisplaySnapshot],
                                 native: [MonitorBrightnessIdentity]) -> Bool {
        let selectedNative = selected(profiles, displays: displays, native: native, displayLink: [])
        let live = resolved(profiles, displays: displays)
        return profiles.contains { profile in
            live[profile.displayUUID] != nil &&
            (profile.brightnessConnection == .displayLink ||
             (profile.brightnessConnection == .automatic && !selectedNative.values.contains(profile)))
        }
    }
}

/// Main-thread editor discovery; obtaining endpoints does not write brightness.
enum MonitorProfileDiscovery {
    static func profiles(configuration: DriverConfiguration, native: [MonitorBrightnessIdentity]) -> [MonitorProfile] {
        var profiles = configuration.monitors ?? []
        let legacy = DisplayResolver(configuration: configuration.display).matchingDisplays()
        let resolved = MonitorProfileRouting.resolved(profiles, displays: DisplayResolver.activeDisplaySnapshots())
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = number.uint32Value
            guard CGDisplayIsBuiltin(id) == 0, let uuidRef = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
            let uuid = CFUUIDCreateString(nil, uuidRef) as String
            guard !resolved.values.contains(where: { $0.displayID == id }),
                  !profiles.contains(where: { $0.displayUUID.lowercased() == uuid.lowercased() }) else { continue }
            let managed = configuration.monitors == nil && legacy.contains { $0.displayID == id }
            let vendor = CGDisplayVendorNumber(id), model = CGDisplayModelNumber(id)
            let candidates = native.filter { $0.vendor == vendor && $0.model == model && $0.name == screen.localizedName }
            profiles.append(MonitorProfile(displayUUID: uuid, name: screen.localizedName, hardwareName: screen.localizedName,
                vendor: vendor, model: model, serial: CGDisplaySerialNumber(id), touchEnabled: managed,
                brightnessConnection: managed ? .automatic : .off, brightnessBehavior: .global,
                nativeBrightnessKey: candidates.count == 1 ? candidates[0].key : nil))
        }
        return profiles
    }
}
