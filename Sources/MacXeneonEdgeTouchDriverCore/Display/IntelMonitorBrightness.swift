import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import IOKit.i2c

/// Optional Intel framebuffer DDC/CI. Protocol research: MonitorControl (MIT).
/// A framebuffer is used only for a unique hardware match on both sides.
/// Identical monitors without distinct hardware identities are skipped.
final class IntelMonitorBrightness {
    let framebuffer: io_service_t
    private var selectedBus: UInt32?
    private var selectedReply: UInt32?
    init(_ framebuffer: io_service_t) { self.framebuffer = framebuffer; IOObjectRetain(framebuffer) }
    deinit { IOObjectRelease(framebuffer) }

    struct Detected {
        var identity: MonitorBrightnessIdentity
        var connection: String
        var displayID: UInt32
        var link: IntelMonitorBrightness
    }
    static func discover(vendor: UInt32?, model: UInt32?) -> [Detected] {
        #if arch(x86_64)
        let displays = DisplayResolver.activeDisplaySnapshots().filter { !$0.builtIn }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOFramebuffer"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var candidates: [(io_service_t, UInt32, UInt32, UInt32, String)] = []
        defer { candidates.forEach { IOObjectRelease($0.0) } }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            guard let info = IODisplayCreateInfoDictionary(entry, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any],
                  let v = (info[kDisplayVendorID] as? NSNumber)?.uint32Value,
                  let m = (info[kDisplayProductID] as? NSNumber)?.uint32Value,
                  let names = info[kDisplayProductName] as? [String: String],
                  let name = names.sorted(by: { $0.key < $1.key }).first?.value else { IOObjectRelease(entry); continue }
            let serial = (info[kDisplaySerialNumber] as? NSNumber)?.uint32Value ?? 0
            candidates.append((entry, v, m, serial, name))
        }
        return displays.compactMap { display in
            guard vendor == nil || display.vendorNumber == vendor, model == nil || display.modelNumber == model else { return nil }
            let matches = candidates.filter { $0.1 == display.vendorNumber && $0.2 == display.modelNumber && $0.3 == display.serialNumber }
            let sameHardware = displays.filter { $0.vendorNumber == display.vendorNumber && $0.modelNumber == display.modelNumber && $0.serialNumber == display.serialNumber }
            let usable = sameHardware.count == 1 && matches.count == 1 ? matches : []
            guard usable.count == 1, let match = usable.first else { return nil }
            var count: IOItemCount = 0
            var registryID: UInt64 = 0
            guard IOFBGetI2CInterfaceCount(match.0, &count) == KERN_SUCCESS, count > 0, count <= 8,
                  IORegistryEntryGetRegistryEntryID(match.0, &registryID) == KERN_SUCCESS else { return nil }
            let identity = MonitorBrightnessIdentity(transport: .native,
                key: "native:\(display.uuid.lowercased()):\(display.vendorNumber):\(display.modelNumber):\(match.4)",
                name: match.4, vendor: display.vendorNumber, model: display.modelNumber)
            guard identity.isValid else { return nil }
            return Detected(identity: identity, connection: String(registryID), displayID: display.displayID, link: Self(match.0))
        }
        #else
        return []
        #endif
    }

    func reading() -> (current: UInt16, maximum: UInt16)? {
        var count: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &count) == KERN_SUCCESS, count > 0, count <= 8 else { return nil }
        let buses: [UInt32] = selectedBus.map { [$0] } ?? Array(0..<count)
        for bus in buses {
            var interface: io_service_t = 0
            guard IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(interface) }
            let types = (IORegistryEntryCreateCFProperty(interface, kIOI2CTransactionTypesKey as CFString, nil, 0)?.takeRetainedValue() as? NSNumber)?.uint64Value ?? 0
            let supported: [UInt32] = [UInt32(kIOI2CDDCciReplyTransactionType), UInt32(kIOI2CSimpleTransactionType)].filter { types & (UInt64(1) << $0) != 0 }
            let replies: [UInt32] = selectedReply.map { [$0] } ?? supported
            for reply in replies {
                var packet = [UInt8(0x51)] + MonitorBrightnessDDC.query
                var data = [UInt8](repeating: 0, count: 11)
                if transact(interface, packet: &packet, data: &data, reply: reply), let value = MonitorBrightnessDDC.reading(data) {
                    selectedBus = bus; selectedReply = reply; return value
                }
            }
        }
        selectedBus = nil; selectedReply = nil
        return nil
    }

    func write(_ value: UInt16, mayWrite: () -> Bool) -> Bool {
        // A validated read chooses the bus; never spray a write across buses.
        guard let bus = selectedBus, mayWrite() else { return false }
        var interface: io_service_t = 0
        guard IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(interface) }
        var packet = [UInt8(0x51)] + MonitorBrightnessDDC.set(value)
        var noReply: [UInt8] = []
        guard mayWrite() else { return false }
        return transact(interface, packet: &packet, data: &noReply, reply: UInt32(kIOI2CNoTransactionType))
    }

    private func transact(_ interface: io_service_t, packet: inout [UInt8], data: inout [UInt8], reply: UInt32) -> Bool {
        var connection: IOI2CConnectRef?
        guard IOI2CInterfaceOpen(interface, 0, &connection) == KERN_SUCCESS, let connection else { return false }
        defer { IOI2CInterfaceClose(connection, 0) }
        return packet.withUnsafeMutableBytes { outgoing in
            data.withUnsafeMutableBytes { incoming in
                var request = IOI2CRequest()
                request.sendAddress = 0x6e; request.replyAddress = 0x6f
                request.replySubAddress = 0x51
                request.sendTransactionType = UInt32(kIOI2CSimpleTransactionType)
                request.replyTransactionType = reply
                request.sendBuffer = vm_address_t(UInt(bitPattern: outgoing.baseAddress))
                request.sendBytes = UInt32(outgoing.count)
                request.replyBuffer = vm_address_t(UInt(bitPattern: incoming.baseAddress))
                request.replyBytes = UInt32(incoming.count)
                request.minReplyDelay = 50_000_000
                return IOI2CSendRequest(connection, 0, &request) == KERN_SUCCESS && request.result == KERN_SUCCESS
            }
        }
    }
}
