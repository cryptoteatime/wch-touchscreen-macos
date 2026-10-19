import AppKit
import Foundation

/// Per-monitor preferences use the same config and restart path as touch settings.
final class MonitorProfilesController: NSObject {
    private var window: NSWindow?
    private var profiles: [MonitorProfile] = []
    private var selected = -1
    private let monitor = NSPopUpButton()
    private let name = NSTextField(string: "")
    private let details = NSTextField(wrappingLabelWithString: "")
    private let touch = NSButton(checkboxWithTitle: "Use this monitor for WCH touch pairing", target: nil, action: nil)
    private let connection = NSPopUpButton()
    private let behavior = NSPopUpButton()
    private var nativeIdentities: [MonitorBrightnessIdentity] = []

    func show() {
        let configuration = DriverConfiguration.load().configuration
        nativeIdentities = NativeMonitorBrightness().endpoints().map(\.identity)
        profiles = MonitorProfileDiscovery.profiles(configuration: configuration, native: nativeIdentities)
        selected = -1
        if window == nil { buildWindow() }
        rebuildMenu()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "WCH Monitor Profiles"
        panel.isReleasedWhenClosed = false
        monitor.target = self; monitor.action = #selector(selectMonitor)
        connection.addItems(withTitles: ["Automatic", "Native DDC/CI", "DisplayLink", "Off"])
        behavior.addItems(withTitles: ["Use the global brightness setting", "Follow MacBook brightness changes", "Remember an independent level"])
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        func row(_ title: String, _ view: NSView) {
            let label = NSTextField(labelWithString: title)
            label.widthAnchor.constraint(equalToConstant: 145).isActive = true
            view.widthAnchor.constraint(equalToConstant: 420).isActive = true
            stack.addArrangedSubview(NSStackView(views: [label, view]))
        }
        row("Monitor", monitor); row("Profile name", name)
        details.font = .systemFont(ofSize: 11); details.textColor = .secondaryLabelColor
        details.widthAnchor.constraint(equalToConstant: 585).isActive = true
        stack.addArrangedSubview(details); stack.addArrangedSubview(touch)
        row("Brightness connection", connection); row("Brightness behavior", behavior)
        let note = NSTextField(wrappingLabelWithString: "Automatic selects a uniquely identified native connection first, then DisplayLink when available. Brightness control must also be enabled in the WCH menu.\n\nTouch pairing supports WCH 27C0:0859 controllers. Display profiles stay local and are tied to the detected video connection. Changed adapters or ports may require a new profile and pairing.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        note.widthAnchor.constraint(equalToConstant: 585).isActive = true; stack.addArrangedSubview(note)
        let save = NSButton(title: "Apply & Restart WCH", target: self, action: #selector(apply))
        let forget = NSButton(title: "Forget Selected Profile", target: self, action: #selector(forgetProfile))
        stack.addArrangedSubview(NSStackView(views: [save, forget]))
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: panel.contentView!.trailingAnchor, constant: -24)])
        panel.center(); window = panel
    }

    private func rebuildMenu() {
        monitor.removeAllItems()
        let displays = DisplayResolver.activeDisplaySnapshots()
        for profile in profiles {
            let online = displays.contains { profile.matches($0) }
            let location = displays.first { profile.matches($0) }.map { " · x=\(Int($0.bounds.minX)), y=\(Int($0.bounds.minY))" } ?? ""
            monitor.addItem(withTitle: profile.name + (online ? location : " · disconnected"))
        }
        monitor.selectItem(at: 0)
        loadSelection()
    }
    @objc private func selectMonitor() { storeSelection(); loadSelection() }
    private func storeSelection() {
        guard profiles.indices.contains(selected) else { return }
        profiles[selected].name = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles[selected].touchEnabled = touch.state == .on
        profiles[selected].brightnessConnection = MonitorProfile.BrightnessConnection.allCases[connection.indexOfSelectedItem]
        profiles[selected].brightnessBehavior = MonitorProfile.BrightnessBehavior.allCases[behavior.indexOfSelectedItem]
    }
    private func loadSelection() {
        selected = monitor.indexOfSelectedItem
        let valid = profiles.indices.contains(selected)
        for control: NSControl in [name, touch, connection, behavior] { control.isEnabled = valid }
        guard valid else { name.stringValue = ""; details.stringValue = "Connect an external display, then reopen Monitor Profiles."; return }
        let profile = profiles[selected]
        name.stringValue = profile.name; touch.state = profile.touchEnabled ? .on : .off
        connection.selectItem(at: MonitorProfile.BrightnessConnection.allCases.firstIndex(of: profile.brightnessConnection)!)
        behavior.selectItem(at: MonitorProfile.BrightnessBehavior.allCases.firstIndex(of: profile.brightnessBehavior)!)
        let native = nativeIdentities.filter { profile.accepts($0) }.count == 1
        details.stringValue = "\(profile.hardwareName) · Display hardware \(String(format: "%04X:%04X", profile.vendor, profile.model))\n" +
            (native ? "Native brightness connection detected." : "Brightness availability depends on this display's connection and driver. See Brightness Status for results.")
    }
    @objc private func forgetProfile() {
        guard profiles.indices.contains(selected) else { return }
        profiles.remove(at: selected); selected = -1; rebuildMenu()
    }
    @objc private func apply() {
        storeSelection()
        guard MonitorProfile.valid(profiles) else { showError("Use a name of 1–128 characters for each monitor. Up to 16 distinct monitors can be saved."); return }
        do {
            let url = DriverConfiguration.defaultConfigURL()
            let data = try Data(contentsOf: url)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            root["monitors"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profiles))
            let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let restart = Process(); restart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            restart.arguments = ["kickstart", "-k", "gui/\(getuid())/\(DriverLoggers.subsystem)"]
            try restart.run()
        } catch { showError("Could not apply monitor profiles: \(error.localizedDescription)") }
    }
    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "WCH Monitor Profiles"; alert.informativeText = message; alert.runModal()
    }
}
