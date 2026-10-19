import AppKit
import Foundation

/// Small local preferences UI. Applying settings restarts the per-user LaunchAgent.
final class DriverSettingsController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var window: NSWindow?
    private let hold = NSTextField(string: "")
    private let rightHold = NSTextField(string: "")
    private let sensitivity = NSTextField(string: "")
    private let movement = NSTextField(string: "")
    private let doubleTap = NSTextField(string: "")
    private let remember = NSButton(checkboxWithTitle: "Remember screens with this USB connection", target: nil, action: nil)
    private let restoreFocus = NSButton(checkboxWithTitle: "Return focus to the previously active window", target: nil, action: nil)
    private let desktop = NSButton(checkboxWithTitle: "Remember monitor layout and app windows", target: nil, action: nil)

    override init() {
        super.init()
        item.button?.title = "WCH"
        item.button?.toolTip = "WCH Touch Driver"
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Touch Settings…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let help = NSMenuItem(title: "Gesture Cheat Sheet…", action: #selector(showCheatSheet), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(.separator())
        for (title, action) in [("Save Current Desktop Layout", #selector(saveDesktop)),
                                ("Restore Saved Desktop Layout", #selector(restoreDesktop)),
                                ("Desktop Layout Status…", #selector(desktopStatus))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let pair = NSMenuItem(title: "Pair Screens Again…", action: #selector(repair), keyEquivalent: "")
        pair.target = self
        menu.addItem(pair)
        item.menu = menu
    }

    @objc private func showSettings() {
        let config = DriverConfiguration.load().configuration
        hold.stringValue = String(config.gesture.holdToDragMs)
        rightHold.stringValue = String(config.gesture.rightClickHoldMs)
        sensitivity.stringValue = String(config.gesture.scrollSensitivity)
        movement.stringValue = String(config.gesture.movementThresholdPoints)
        doubleTap.stringValue = String(config.gesture.doubleClickDistancePoints)
        remember.state = config.rememberConnections ? .on : .off
        restoreFocus.state = config.restorePreviousFocus ? .on : .off
        desktop.state = config.rememberDesktopLayout ? .on : .off
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 610),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "WCH Touch Settings"
            panel.isReleasedWhenClosed = false
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            func row(_ title: String, _ field: NSTextField) {
                let label = NSTextField(labelWithString: title)
                label.widthAnchor.constraint(equalToConstant: 290).isActive = true
                field.widthAnchor.constraint(equalToConstant: 110).isActive = true
                stack.addArrangedSubview(NSStackView(views: [label, field]))
            }
            row("Hold before dragging (100–2000 ms)", hold)
            row("Hold for right-click (300–4000 ms)", rightHold)
            row("Scroll sensitivity (0.1–10)", sensitivity)
            row("Movement before scrolling (1–100 pt)", movement)
            row("Double-tap tolerance (1–100 pt)", doubleTap)
            stack.addArrangedSubview(remember)
            stack.addArrangedSubview(restoreFocus)
            stack.addArrangedSubview(desktop)
            let note = NSTextField(wrappingLabelWithString:
                "Hold still, then lift to right-click. Hold briefly, then move to drag. Right-click hold must be at least 150 ms longer than drag hold. See WCH → Gesture Cheat Sheet for all actions.\n\nDesktop memory restores the layout after reconnect or login. Enable macOS ‘Reopen windows when logging back in’ for reboot restoration. WCH waits up to 3 minutes for reopened windows; ambiguous, minimized and full-screen windows are skipped. The MacBook’s resolution is preserved.\n\nKeep the same ports and cables to remember screens. Multi-finger gestures are unavailable in the current input mode.")
            note.font = .systemFont(ofSize: 11)
            note.textColor = .secondaryLabelColor
            note.widthAnchor.constraint(equalToConstant: 490).isActive = true
            stack.addArrangedSubview(note)
            let apply = NSButton(title: "Apply & Restart Touch Driver", target: self, action: #selector(applySettings))
            stack.addArrangedSubview(apply)
            panel.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24),
                stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 24),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: panel.contentView!.trailingAnchor, constant: -24)
            ])
            panel.center()
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func applySettings() {
        guard let holdValue = Int(hold.stringValue), (100...2000).contains(holdValue),
              let rightValue = Int(rightHold.stringValue), (300...4000).contains(rightValue), rightValue >= holdValue + 150,
              let scrollValue = Double(sensitivity.stringValue), scrollValue.isFinite, (0.1...10).contains(scrollValue),
              let movementValue = Int(movement.stringValue), (1...100).contains(movementValue),
              let doubleValue = Int(doubleTap.stringValue), (1...100).contains(doubleValue) else {
            showError("Enter numbers within the ranges shown. Right-click hold must be at least 150 ms longer than drag hold.")
            return
        }
        do {
            let url = DriverConfiguration.defaultConfigURL()
            let data = try Data(contentsOf: url)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var gesture = root["gesture"] as? [String: Any] ?? [:]
            gesture["holdToDragMs"] = holdValue
            gesture["rightClickHoldMs"] = rightValue
            gesture["scrollSensitivity"] = scrollValue
            gesture["movementThresholdPoints"] = movementValue
            gesture["doubleClickDistancePoints"] = doubleValue
            root["gesture"] = gesture
            root["rememberConnections"] = remember.state == .on
            root["restorePreviousFocus"] = restoreFocus.state == .on
            root["rememberDesktopLayout"] = desktop.state == .on
            let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: url, options: .atomic)
            let restart = Process()
            restart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            restart.arguments = ["kickstart", "-k", "gui/\(getuid())/\(DriverLoggers.subsystem)"]
            try restart.run()
        } catch { showError("Could not apply settings: \(error.localizedDescription)") }
    }

    @objc private func showCheatSheet() {
        let gesture = DriverConfiguration.load().configuration.gesture
        let alert = NSAlert()
        alert.messageText = "WCH Touch Gesture Cheat Sheet"
        alert.informativeText = """
        TAP & LIFT — Single left-click.

        DOUBLE-TAP — Double-click near the same spot, using the Mac’s double-click timing.

        MOVE IMMEDIATELY — One-finger scrolling, vertically or horizontally.

        HOLD \(gesture.holdToDragMs) ms, THEN MOVE — Left-button drag. Lift to drop. Useful for windows, sliders, files, and text selection.

        HOLD STILL \(gesture.rightClickHoldMs) ms, THEN LIFT — Right-click / context menu. No left-click is sent first.

        TAP, THEN PRESS AGAIN & MOVE — Double-click drag. Keep the second contact down; lift to finish. Text apps may select whole words while dragging.

        A thumb behaves like another single finger. Two-finger gestures and pinch are unavailable in this input mode. App responses to clicks and drags vary.
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func repair() {
        let alert = NSAlert()
        alert.messageText = "Pair both touchscreens again?"
        alert.informativeText = "This replaces the saved mappings. Touch and release the circle on each screen when prompted."
        alert.addButton(withTitle: "Pair Screens")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do { _ = try DriverControl.request("re-pair") }
            catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self?.showError(message) }
            }
        }
    }

    @objc private func saveDesktop() { desktopCommand("save-layout") }
    @objc private func restoreDesktop() { desktopCommand("restore-layout") }
    @objc private func desktopStatus() { desktopCommand("layout-status") }

    private func desktopCommand(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let message: String
            do {
                let reply = try DriverControl.request(command)
                let data = Data(reply.utf8)
                let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                message = (value["error"] as? String ?? value["status"] as? String ?? reply) +
                    "\n\nSaved displays: \(value["savedDisplays"] ?? 0)\nSaved app windows: \(value["savedWindows"] ?? 0)\n\nReopened windows are matched by app and private fingerprints. Readable window titles, document paths and contents are not saved. Enable macOS ‘Reopen windows when logging back in’ when restarting. Ambiguous, minimized and full-screen windows are skipped."
            } catch { message = error.localizedDescription }
            DispatchQueue.main.async {
                guard self != nil else { return }
                let alert = NSAlert()
                alert.messageText = "WCH Desktop Layout"
                alert.informativeText = message
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "WCH Touch Settings"
        alert.informativeText = message
        alert.runModal()
    }
}
