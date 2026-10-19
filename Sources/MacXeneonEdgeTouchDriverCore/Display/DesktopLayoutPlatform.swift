import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// OS operations are isolated from the reconnect state machine and touch routing.
final class DesktopLayoutPlatform {
    enum DisplayResult { case ready, changed, unavailable(String) }
    struct LiveWindow { var saved: DesktopWindow; var element: AXUIElement }

    // macOS exposes rotation reading publicly, but rotation writing still needs
    // this optional system symbol. Resolve it at runtime; never fail app startup.
    private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private let accessibility = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
    private let fingerprints = DesktopWindowFingerprint()
    private typealias Rotate = @convention(c) (UInt32, Int32) -> Int32
    private typealias WindowNumber = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32

    func screens() -> [DesktopScreen] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0, count <= 16 else { return [] }
        var ids = [UInt32](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).compactMap { id in
            guard let mode = CGDisplayCopyDisplayMode(id), let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return DesktopScreen(uuid: CFUUIDCreateString(nil, uuid) as String,
                vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id),
                builtIn: CGDisplayIsBuiltin(id) != 0, frame: CGDisplayBounds(id), rotation: Int(CGDisplayRotation(id).rounded()),
                width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate, runtimeID: id)
        }.sorted { $0.uuid < $1.uuid }
    }

    func configure(_ layout: DesktopLayout, matches: [String: DesktopScreen]) -> DisplayResult {
        // Rotation changes the mode list; resolve modes on the following settled tick.
        let rotations = layout.screens.filter { !$0.builtIn && matches[$0.uuid]?.rotation != $0.rotation }
        if !rotations.isEmpty {
            guard let skyLight, let symbol = dlsym(skyLight, "SLSSetDisplayRotation") else {
                return .unavailable("This macOS version does not expose the rotation function.")
            }
            let rotate = unsafeBitCast(symbol, to: Rotate.self)
            for screen in rotations {
                guard let live = matches[screen.uuid] else { return .unavailable("A display disconnected.") }
                let code = rotate(live.runtimeID, Int32(screen.rotation))
                guard code == 0 else { return .unavailable("Rotation returned \(code).") }
            }
            return .changed
        }

        var modes: [(UInt32, CGDisplayMode)] = []
        var origins: [(UInt32, CGPoint)] = []
        var mirrors: [UInt32] = []
        for saved in layout.screens {
            guard let live = matches[saved.uuid] else { return .unavailable("A display disconnected.") }
            // Built-in resolution and refresh rate always remain under the user's control.
            if saved.builtIn { continue }
            if live.width != saved.width || live.height != saved.height || live.pixelWidth != saved.pixelWidth ||
                live.pixelHeight != saved.pixelHeight || abs(live.refreshRate - saved.refreshRate) >= 1 {
                let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
                let all = CGDisplayCopyAllDisplayModes(live.runtimeID, options) as? [CGDisplayMode] ?? []
                let candidates = all.filter { $0.width == saved.width && $0.height == saved.height &&
                    $0.pixelWidth == saved.pixelWidth && $0.pixelHeight == saved.pixelHeight &&
                    abs($0.refreshRate - saved.refreshRate) < 1 }
                guard let mode = candidates.first else { return .unavailable("Saved resolution is not available yet for an external display.") }
                modes.append((live.runtimeID, mode))
            }
            let origin = layout.targetOrigin(for: saved, matches: matches)
            if live.frame.origin != origin { origins.append((live.runtimeID, origin)) }
            if CGDisplayMirrorsDisplay(live.runtimeID) != kCGNullDirectDisplay { mirrors.append(live.runtimeID) }
        }
        guard !modes.isEmpty || !origins.isEmpty || !mirrors.isEmpty else { return .ready }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return .unavailable("Could not begin display configuration.") }
        var code = CGError.success
        for id in mirrors where code == .success { code = CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay) }
        for (id, mode) in modes where code == .success { code = CGConfigureDisplayWithDisplayMode(config, id, mode, nil) }
        // Specify all origins so the OS does not move an otherwise unchanged screen.
        for saved in layout.screens where code == .success {
            guard let live = matches[saved.uuid] else { continue }
            let p = saved.builtIn ? live.frame.origin : layout.targetOrigin(for: saved, matches: matches)
            code = CGConfigureDisplayOrigin(config, live.runtimeID, Int32(p.x.rounded()), Int32(p.y.rounded()))
        }
        guard code == .success else { CGCancelDisplayConfiguration(config); return .unavailable("Display configuration returned \(code.rawValue).") }
        code = CGCompleteDisplayConfiguration(config, .permanently)
        return code == .success ? .changed : .unavailable("Display commit returned \(code.rawValue).")
    }

    func windows(on screens: [DesktopScreen]) -> [LiveWindow] {
        guard AXIsProcessTrusted(), let accessibility, let symbol = dlsym(accessibility, "_AXUIElementGetWindow") else { return [] }
        let number = unsafeBitCast(symbol, to: WindowNumber.self)
        var result: [LiveWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() && !app.isTerminated {
            guard let bundle = app.bundleIdentifier, let launch = app.launchDate else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.15)
            guard let list = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in list.prefix(128) {
                AXUIElementSetMessagingTimeout(window, 0.15)
                guard attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                      (attribute(window, kAXMinimizedAttribute) as? Bool) != true,
                      (attribute(window, "AXFullScreen") as? Bool) != true,
                      var frame = frame(of: window), !frame.isEmpty, frame.width.isFinite, frame.height.isFinite else { continue }
                var id: UInt32 = 0
                guard number(window, &id) == 0, id != 0 else { continue }
                let best = screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
                guard let screen = best, area(screen.frame.intersection(frame)) > 0 else { continue }
                frame.origin.x = frame.origin.x.rounded(); frame.origin.y = frame.origin.y.rounded()
                frame.size.width = frame.width.rounded(); frame.size.height = frame.height.rounded()
                var saved = DesktopWindow(bundleID: bundle, pid: app.processIdentifier,
                    launchedAt: launch.timeIntervalSince1970, windowID: id, screenUUID: screen.uuid, frame: frame)
                saved.identifierHash = fingerprints.hash(attribute(window, kAXIdentifierAttribute) as? String, kind: bundle + ":identifier")
                saved.documentHash = fingerprints.hash(attribute(window, kAXDocumentAttribute) as? String, kind: bundle + ":document")
                saved.titleHash = fingerprints.hash(attribute(window, kAXTitleAttribute) as? String, kind: bundle + ":title")
                result.append(LiveWindow(saved: saved, element: window))
                if result.count >= 512 { return result }
            }
        }
        return result.sorted { $0.saved.key < $1.saved.key }
    }

    func restoreWindows(_ layout: DesktopLayout, matches: [String: DesktopScreen], progress: inout DesktopWindowRestoreProgress) -> (restored: Int, pending: Int, failed: Int) {
        let live = windows(on: Array(matches.values))
        let plan = DesktopWindowMatcher.matches(saved: layout.windows, live: live.map(\.saved), completed: progress.bindings)
        for match in plan where !progress.failedKeys.contains(match.savedKey) {
            guard let saved = layout.windows.first(where: { $0.key == match.savedKey }),
                  let current = live.first(where: { $0.saved.key == match.liveKey }),
                  let target = layout.targetFrame(for: saved, matches: matches) else { continue }
            if near(current.saved.frame, target) { progress.bindings[saved.key] = current.saved.key; continue }
            var position = target.origin, size = target.size
            guard let sizeValue = AXValueCreate(.cgSize, &size), let positionValue = AXValueCreate(.cgPoint, &position) else {
                progress.failures[saved.key, default: 0] += 1; continue
            }
            // Position/size only: no raise, activation, clicks, or Space switching.
            _ = AXUIElementSetAttributeValue(current.element, kAXSizeAttribute as CFString, sizeValue)
            _ = AXUIElementSetAttributeValue(current.element, kAXPositionAttribute as CFString, positionValue)
            _ = AXUIElementSetAttributeValue(current.element, kAXSizeAttribute as CFString, sizeValue)
            if let actual = frame(of: current.element), near(actual, target) { progress.bindings[saved.key] = current.saved.key }
            else { progress.failures[saved.key, default: 0] += 1 }
        }
        return (progress.bindings.count, progress.waitingKeys(in: layout.windows).count, progress.failedKeys.count)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
    private func frame(of window: AXUIElement) -> CGRect? {
        guard let p = attribute(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attribute(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    private func area(_ r: CGRect) -> CGFloat { r.isNull || r.isEmpty ? 0 : r.width * r.height }
    private func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) <= 2 && abs(a.minY-b.minY) <= 2 && abs(a.width-b.width) <= 2 && abs(a.height-b.height) <= 2
    }
}
