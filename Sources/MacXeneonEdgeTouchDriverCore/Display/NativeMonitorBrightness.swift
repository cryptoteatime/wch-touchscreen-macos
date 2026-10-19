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
        fileprivate var service: CFTypeRef
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

    func builtInLevel() -> Double? {
        guard let get = symbol("DisplayServicesGetBrightness", in: displayServices, as: GetBrightness.self) else { return nil }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count <= 16 else { return nil }
        var ids = [UInt32](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        let builtIn = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
        guard builtIn.count == 1 else { return nil }
        var value: Float = 0
        guard get(builtIn[0], &value) == 0, value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }

    func endpoints(vendor: UInt32? = nil, model: UInt32? = nil) -> [Endpoint] {
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
        return unique
    }

    func level(_ endpoint: Endpoint) -> Double? {
        guard let value = reading(endpoint) else { return nil }
        return Double(value.current) / Double(value.maximum)
    }

    func set(_ endpoint: Endpoint, level: Double) -> Bool {
        // The range is stable for this live IORegistry connection and was read
        // during discovery/polling. Avoid a 70 ms DDC query before every write.
        // A new connection or failed read must establish a valid range again.
        guard level.isFinite, (0...1).contains(level), let write,
              let maximum = maximumByConnection[endpoint.connection] ?? reading(endpoint)?.maximum else { return false }
        let value = UInt16((level * Double(maximum)).rounded())
        var packet = MonitorBrightnessDDC.set(value)
        let code = packet.withUnsafeMutableBytes { write(endpoint.service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
        guard code == 0 else { return false }
        usleep(100_000)
        guard let actual = reading(endpoint) else { return false }
        return actual.maximum == maximum && actual.current == value
    }

    private func reading(_ endpoint: Endpoint) -> (current: UInt16, maximum: UInt16)? {
        var validRead = false
        defer { if !validRead { maximumByConnection.removeValue(forKey: endpoint.connection) } }
        guard let read, let write else { return nil }
        var query = MonitorBrightnessDDC.query
        for _ in 0..<2 {
            let code = query.withUnsafeMutableBytes { write(endpoint.service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            guard code == 0 else { return nil }
            usleep(10_000)
        }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 11)
        let code = reply.withUnsafeMutableBytes { read(endpoint.service, 0x37, 0, $0.baseAddress!, UInt32($0.count)) }
        guard code == 0, let value = MonitorBrightnessDDC.reading(reply) else { return nil }
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
