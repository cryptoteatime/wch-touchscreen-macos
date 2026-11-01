import Foundation

/// Keep vendor replies flowing when AppKit suspends notifications after a
/// settings window loses focus. Only these named subscriptions request immediate
/// delivery; AppKit retains control of the center's global suspension flag.
final class BrightnessNotificationObservation: NSObject {
    private let center: DistributedNotificationCenter
    private let names: [Notification.Name]
    private let handler: (Notification) -> Void

    init(names: [Notification.Name], center: DistributedNotificationCenter = .default(),
         handler: @escaping (Notification) -> Void) {
        self.names = names; self.center = center; self.handler = handler
        super.init()
        for name in names {
            center.addObserver(self, selector: #selector(receive(_:)), name: name,
                               object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func receive(_ notification: Notification) { handler(notification) }

    func stop() {
        for name in names { center.removeObserver(self, name: name, object: nil) }
    }

    deinit { stop() }
}
