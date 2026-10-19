import ApplicationServices
import CoreGraphics
import Foundation

/// DisplayLink Manager 17's local PublicApiHandler notification interface.
/// No client impersonation, XPC connection, extra app, or Shortcut is used.
/// This vendor interface is optional and may change in future Manager releases.
final class DisplayLinkMonitorBrightness {
    struct Endpoint {
        var identity: MonitorBrightnessIdentity
        var connection: String
        var persistentID: String
        var reportedLevel: Double?
    }
    var onUpdate: (() -> Void)?
    private let center = DistributedNotificationCenter.default()
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []
    private var list: [Endpoint] = []
    private var receivedAt: TimeInterval = 0
    private var results: [String: (Double, Int, TimeInterval)] = [:]
    private let vendor: UInt32?
    private let model: UInt32?

    init(vendor: UInt32?, model: UInt32?) { self.vendor = vendor; self.model = model }
    func start() {
        tokens.append(center.addObserver(forName: Notification.Name("com.displaylink.DisplayListUpdated"), object: nil, queue: .main) { [weak self] in self?.receiveList($0) })
        tokens.append(center.addObserver(forName: Notification.Name("com.displaylink.BrightnessUpdated"), object: nil, queue: .main) { [weak self] in self?.receiveBrightness($0) })
        refresh()
    }
    func stop() { tokens.forEach(center.removeObserver); tokens.removeAll() }
    func refresh() { center.postNotificationName(Notification.Name("com.displaylink.GetDisplays"), object: nil, userInfo: nil, deliverImmediately: true) }
    func endpoints() -> [Endpoint] {
        lock.lock(); defer { lock.unlock() }
        guard ProcessInfo.processInfo.systemUptime - receivedAt < 8 else { return [] }
        return list.filter { item in
            guard let id = UInt32(item.connection) else { return false }
            return CGDisplayIsOnline(id) != 0 && CGDisplayIsBuiltin(id) == 0
        }
    }
    func set(_ endpoint: Endpoint, level: Double) -> Bool {
        guard level.isFinite, (0...1).contains(level),
              endpoints().contains(where: { $0.identity == endpoint.identity && $0.persistentID == endpoint.persistentID && $0.connection == endpoint.connection }),
              let data = try? JSONSerialization.data(withJSONObject: ["persistentDisplayId": endpoint.persistentID, "brightness": level]),
              let object = String(data: data, encoding: .utf8) else { return false }
        center.postNotificationName(Notification.Name("com.displaylink.SetBrightness"), object: object, userInfo: nil, deliverImmediately: true)
        return true
    }
    func result(for endpoint: Endpoint, after: TimeInterval) -> (Double, Int)? {
        lock.lock(); defer { lock.unlock() }
        guard let value = results[endpoint.persistentID], value.2 >= after else { return nil }
        return (value.0, value.1)
    }

    private func receiveList(_ notification: Notification) {
        guard let data = data(notification), let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], records.count <= 16 else { return }
        let entries: [Endpoint] = records.compactMap { item -> Endpoint? in
            guard let idNumber = item["CGID"] as? NSNumber, idNumber.int64Value > 0, idNumber.uint64Value <= UInt32.max,
                  let name = item["name"] as? String, let persistent = item["persistentDisplayId"] as? String,
                  !persistent.isEmpty, persistent.count <= 512, item["isEnabled"] as? Bool == true else { return nil }
            let id = idNumber.uint32Value
            guard CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0,
                  CGDisplayVendorNumber(id) == vendor, CGDisplayModelNumber(id) == model,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            let identity = MonitorBrightnessIdentity(transport: .displayLink, key: "displaylink:" + (CFUUIDCreateString(nil, uuid) as String),
                name: name, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id))
            guard identity.isValid else { return nil }
            return Endpoint(identity: identity, connection: String(id), persistentID: persistent, reportedLevel: level(item["brightness"]))
        }
        let groups = Dictionary(grouping: entries, by: \.identity)
        lock.lock()
        list = entries.filter { groups[$0.identity]?.count == 1 }
        receivedAt = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        onUpdate?()
    }
    private func receiveBrightness(_ notification: Notification) {
        guard let data = data(notification), let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = item["persistentDisplayId"] as? String, let value = level(item["brightness"]), let code = item["statusCode"] as? Int else { return }
        lock.lock()
        if let index = list.firstIndex(where: { $0.persistentID == id }) {
            results[id] = (value, code, ProcessInfo.processInfo.systemUptime)
            if code == 0 { list[index].reportedLevel = value }
        }
        lock.unlock()
        onUpdate?()
    }
    private func data(_ notification: Notification) -> Data? {
        guard let text = notification.object as? String, text.utf8.count <= 32_768 else { return nil }
        return text.data(using: .utf8)
    }
    private func level(_ object: Any?) -> Double? {
        guard let value = (object as? NSNumber)?.doubleValue, value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }
}
