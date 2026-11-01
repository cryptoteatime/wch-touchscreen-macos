import CoreGraphics
import Darwin
import Foundation
import IOKit

/// Optional Apple Silicon DDC transport. Match each proxy to its framebuffer by
/// port name; registry iteration order and CG display numbers are not identities.
/// IOAV declarations/protocol researched in MonitorControl (see notices).
final class NativeMonitorBrightness {
    struct Endpoint {
        var identity: MonitorBrightnessIdentity
        var connection: String
        var displayID: UInt32 = 0
        fileprivate var service: CFTypeRef?
        var intel: IntelMonitorBrightness? = nil
    }
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private let kit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private var maximumByConnection: [String: UInt16] = [:]
    private var create: Create? { symbol("IOAVServiceCreateWithService", in: kit, as: Create.self) }
    private var read: Transfer? { symbol("IOAVServiceReadI2C", in: kit, as: Transfer.self) }
    private var write: Transfer? { symbol("IOAVServiceWriteI2C", in: kit, as: Transfer.self) }

    deinit { if let kit { dlclose(kit) }; if let displayServices { dlclose(displayServices) } }

    static var backend: String {
        #if arch(x86_64)
        return "Intel framebuffer DDC/CI"
        #else
        return "Apple Silicon IOAV DDC/CI"
        #endif
    }

    /// Called only by this instance's serial hardware worker.
    func resetConnection() { maximumByConnection.removeAll() }

    func builtInLevel() -> Double? {
        guard let get = symbol("DisplayServicesGetBrightness", in: displayServices, as: GetBrightness.self) else { return nil }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count <= 16 else { return nil }
        var ids = [UInt32](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        let builtIn = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0 }
        guard builtIn.count == 1 else { return nil }
        var value: Float = 0
        guard get(builtIn[0], &value) == 0, value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }

    func endpoints(vendor: UInt32? = nil, model: UInt32? = nil) -> [Endpoint] {
        #if arch(x86_64)
        return IntelMonitorBrightness.discover(vendor: vendor, model: model).map {
            Endpoint(identity: $0.identity, connection: $0.connection, displayID: $0.displayID, service: nil, intel: $0.link)
        }
        #else
        guard let create, read != nil, write != nil else { return [] }
        var frames: [String: [MonitorBrightnessIdentity]] = [:]
        for kind in ["IOMobileFramebufferShim", "AppleCLCD2"] {
            eachService(kind) { frame in
                guard let port = self.parentName(frame),
                      let uuid = self.property(frame, "EDID UUID") as? String,
                      let attrs = self.property(frame, "DisplayAttributes") as? [String: Any],
                      let product = attrs["ProductAttributes"] as? [String: Any],
                      let name = product["ProductName"] as? String,
                      let foundVendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
                      let foundModel = (product["ProductID"] as? NSNumber)?.uint32Value,
                      vendor == nil || foundVendor == vendor,
                      model == nil || foundModel == model else { return }
                let identity = MonitorBrightnessIdentity(transport: .native,
                    key: "native:\(uuid.lowercased()):\(foundVendor):\(foundModel):\(name)", name: name, vendor: foundVendor, model: foundModel)
                guard identity.isValid else { return }
                frames[port, default: []].append(identity)
            }
        }
        var result: [Endpoint] = []
        eachService("DCPAVServiceProxy") { entry in
            guard self.property(entry, "Location") as? String == "External",
                  let parent = self.parentName(entry), let colon = parent.firstIndex(of: ":"),
                  let matches = frames[String(parent[..<colon])], matches.count == 1,
                  let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { return }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &registryID) == KERN_SUCCESS else { return }
            result.append(Endpoint(identity: matches[0], connection: String(registryID), service: service))
        }
        // Identical panels with no distinguishing EDID must not be guessed.
        let groups = Dictionary(grouping: result, by: \.identity)
        let unique = result.filter { groups[$0.identity]?.count == 1 }
        let online = Set(unique.map(\.connection))
        maximumByConnection = maximumByConnection.filter { online.contains($0.key) }
        let displays = DisplayResolver.activeDisplaySnapshots().filter { !$0.builtIn }
        return unique.map { endpoint in
            var endpoint = endpoint
            let matching = displays.filter { display in
                display.vendorNumber == endpoint.identity.vendor && display.modelNumber == endpoint.identity.model &&
                    endpoint.identity.key.hasPrefix("native:\(display.uuid.lowercased()):")
            }
            if matching.count == 1 { endpoint.displayID = matching[0].displayID }
            return endpoint
        }
        #endif
    }

    func level(_ endpoint: Endpoint) -> Double? {
        guard let value = reading(endpoint) else { return nil }
        return Double(value.current) / Double(value.maximum)
    }

    func set(_ endpoint: Endpoint, level: Double, mayWrite: () -> Bool = { true }) -> Bool {
        // The range is stable for this live IORegistry connection and was read
        // during discovery/polling. Avoid a 70 ms DDC query before every write.
        // A new connection or failed read must establish a valid range again.
        guard level.isFinite, (0...1).contains(level), mayWrite(),
              let maximum = maximumByConnection[endpoint.connection] ?? reading(endpoint)?.maximum else { return false }
        let value = UInt16((level * Double(maximum)).rounded())
        guard mayWrite() else { return false }
        if let intel = endpoint.intel {
            guard intel.write(value, mayWrite: mayWrite) else { return false }
        } else {
            guard let write, let service = endpoint.service else { return false }
            var packet = MonitorBrightnessDDC.set(value)
            let code = packet.withUnsafeMutableBytes { write(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            guard code == 0 else { return false }
        }
        usleep(100_000)
        guard let actual = reading(endpoint) else { return false }
        return actual.maximum == maximum && actual.current == value
    }

    private func reading(_ endpoint: Endpoint) -> (current: UInt16, maximum: UInt16)? {
        var validRead = false
        defer { if !validRead { maximumByConnection.removeValue(forKey: endpoint.connection) } }
        if let intel = endpoint.intel {
            guard let value = intel.reading() else { return nil }
            if maximumByConnection.count > 32 { maximumByConnection.removeAll() }
            maximumByConnection[endpoint.connection] = value.maximum; validRead = true
            return value
        }
        guard let read, let write, let service = endpoint.service else { return nil }
        var query = MonitorBrightnessDDC.query
        for _ in 0..<2 {
            let code = query.withUnsafeMutableBytes { write(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            guard code == 0 else { return nil }
            usleep(10_000)
        }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 11)
        let code = reply.withUnsafeMutableBytes { read(service, 0x37, 0, $0.baseAddress!, UInt32($0.count)) }
        guard code == 0, let value = MonitorBrightnessDDC.reading(reply) else { return nil }
        if maximumByConnection.count > 32 { maximumByConnection.removeAll() }
        maximumByConnection[endpoint.connection] = value.maximum
        validRead = true
        return value
    }

    private func eachService(_ kind: String, visit: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kind), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            visit(entry); IOObjectRelease(entry)
        }
    }
    private func property(_ entry: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    private func parentName(_ entry: io_service_t) -> String? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(parent, &name) == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }
    private func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}
