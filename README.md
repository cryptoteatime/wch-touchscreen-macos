# WCH Touch Driver for macOS — portrait and desktop memory fork

A native Swift menu-bar touchscreen driver for compatible **wch.cn `27C0:0859`** controllers, with portrait touch mapping, persistent connections, right-click gestures, and desktop restoration.

This is a fork of **[mrnocreativity/xeneon-wch-touchscreen-driver-macos](https://github.com/mrnocreativity/xeneon-wch-touchscreen-driver-macos)** at `707106e828d178db004a7ec1b3d8eee9447b03b9`, which builds on **[ajvwhite/MacXeneonEdgeTouchDriver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver)**. Their driver architecture, HID handling, multi-display pairing, validation and basic gestures are inherited. See [credits](THIRD_PARTY_NOTICES.md), the retained Git history, and [MIT license](LICENSE). Fork additions were developed by cryptoteatime with OpenAI Codex assistance.

This is an independent community project, not software supplied or endorsed by WCH, Corsair, Synaptics, or the monitor seller. DisplayLink handles video where required; this app handles touch and optional desktop placement.

## Added in this fork

- Touch coordinates follow 0°, 90°, 180° and 270° display rotation, including screen-edge handling.
- The pointer stays visible and remains on the touched screen. Returning focus to the previous app is optional and off by default.
- Opt-in USB-connection memory avoids repeated pairing when the same ports, cables and distinct display descriptors return.
- Stationary long-press right-click and double-click dragging, with configurable gesture timing.
- **WCH → Touch Settings…**, **Gesture Cheat Sheet…**, and desktop Save / Restore / Status controls.
- Desktop memory saves external display rotations, available modes/scaling, arrangement, and ordinary window geometry. The built-in display's current resolution is preserved.
- Reopened windows can be recognized after login using app identity and locally salted window fingerprints. See the reboot behavior below.

True multi-contact gestures are not supported by this controller's current input mode. Existing single-finger scrolling and dragging are retained.

## Compatibility and verified scope

The local hardware test used two portable touchscreen panels whose displays identify as **Type-c** and **HDMI**, with EDID vendor/model `4A8B:2200` and WCH USB controllers `27C0:0859`. Both ran at 1050 × 1680, rotated 90° / 270°, on an Apple Silicon MacBook Pro with macOS 26.6.2. The exact marketed monitor model has not been independently verified; the USB/display identifiers are more useful than an Amazon listing variant.

Physical reconnect testing restored nine open windows to exactly their saved positions and sizes and restored both touch mappings. Portrait touch, click/focus behavior, long-press right-click and dragging were also physically tested. Reboot matching has automated coverage for changed process/window identities, delayed windows and ambiguous windows. A live integration simulation changed all saved process/window IDs and restored all nine placements, then recaptured the real identities. A complete cold-boot verification of this release is still pending. Do not interpret that coverage as verification of every app's macOS Resume behavior.

The package targets macOS 13 or later. Other macOS versions, Intel hardware and different panels need hardware testing. A USB ID match alone does not prove compatibility. The original Xeneon profile remains available.

## Install from source

Requires Apple's Xcode or Command Line Tools, Python 3, and Git. No third-party Python packages or additional window-manager app are needed.

```sh
git clone https://github.com/cryptoteatime/wch-touchscreen-macos.git
cd wch-touchscreen-macos
./Scripts/install.sh --profile portable-dual-wch
```

For the original Corsair Xeneon defaults, use `--profile xeneon`. A profile initializes a **new** configuration only; updates preserve existing settings, pairings and layouts. Adjust the display vendor/model configuration for other hardware after inspecting it with `swift run DisplayInfo`.

The installer creates **WCH Touch Driver.app** in `~/Applications` for a new install, or updates the existing app at its current location. It uses one per-user LaunchAgent and keeps recovery copies in the existing Application Support directory. It does not use sudo, replace DisplayLink, change the built-in resolution, or install custom resolution overrides. Display memory can only restore modes already available from macOS.

Grant **Accessibility** and **Input Monitoring** to the exact installed app in System Settings → Privacy & Security. These permissions let the driver receive touchscreen reports and control the pointer/windows. Ad hoc signatures can require permissions to be refreshed after an update. A stable Developer ID identity supplied through `CODESIGN_IDENTITY` avoids changing signing identity between builds. No signing credentials belong in this repository.

Keep the same USB ports and monitor-side data ports after pairing. Exchanging identical hardware or changing hubs/ports may require **WCH → Pair Screens Again…**. Connection memory is opt-in; it is not a globally unique controller identity.

### Desktop memory and restarting

Enable **Remember monitor layout and app windows** in Touch Settings (enabled by the portable profile). Arrange your windows with all saved screens attached. WCH samples the stable desktop approximately every two seconds and freezes the snapshot while a saved display is disconnected or the Mac is shutting down.

On reconnect or login, it waits at least three seconds for display changes to settle, restores monitor geometry, then restores windows. It waits up to three minutes for saved windows to reopen. Already restored windows are not repeatedly moved while other apps launch.

When restarting, leave macOS **Reopen windows when logging back in** checked. macOS and each app reopen their windows; WCH restores the positions of matching windows. WCH does not launch apps, reopen documents, reconstruct tabs, or create Mission Control Spaces. See [Apple's explanation of reopening windows](https://support.apple.com/en-us/102318).

Window matching prefers the same running window, then unique app-provided window identity, document fingerprint, or title fingerprint. A single saved window with one current window can match by application alone. Multiple indistinguishable windows, minimized/full-screen windows, and windows that do not reopen within the grace period are skipped. Some apps restrict their minimum size or refuse Accessibility placement; status reports these failures instead of overwriting a good snapshot. A canceled logout that already sent the shutdown notification may require restarting WCH to resume capture.

Profiles are tied to the complete saved monitor set, with unique hardware fallback for a changed DisplayLink UUID. A different or ambiguous set is not guessed. Desktop memory currently requires a built-in display plus at least two compatible external touchscreens. Rotation relies on a private macOS function and may need maintenance across OS updates.

### Gestures

| Action | Result |
| --- | --- |
| Tap and lift | Left-click |
| Tap twice nearby | Double-click using macOS timing |
| Move immediately | One-finger vertical/horizontal scrolling |
| Hold 300 ms, then move | Left drag; lift to drop |
| Hold still 650 ms, then lift | Right-click without a preceding left-click |
| Tap, then hold the second contact and move | Double-click drag |

Timings and sensitivity are configurable. Responses to scrolling and double-click dragging depend on the app.

## Privacy and local files

Runtime files stay in `~/Library/Application Support/MacXeneonEdgeTouchDriver/`. The window snapshot contains app identifiers, local process/window identifiers and geometry. It contains no readable titles, document URLs or document contents. Optional title/document/window-identifier fingerprints use HMAC-SHA256 with a random local salt saved separately. The snapshot and salt are user-readable only. They are still private local metadata and are ignored by Git.

The app has no analytics or upload feature. Upstream diagnostic logs can contain local identifiers and touch coordinates. Do not include `desktop-layout.json`, `pairings.json`, `window-identity-salt`, logs, or raw diagnostics in public issues. Share a sanitized compatibility summary instead.

The original `com.ajvwhite.MacXeneonEdgeTouchDriver` bundle and LaunchAgent identity is intentionally retained so an update does not start a second HID owner. Do not run the upstream driver, Touch-Up, UPDD, or another touch driver concurrently against the same controller.

## Build, checks and removal

```sh
swift test
python3 Scripts/test-regressions.py
python3 Scripts/build-app.py
./Scripts/build-release.sh
./Scripts/uninstall.sh
```

The standalone suite covers connection persistence, gestures, display layout policy, reboot window matching and private fingerprints. CI also runs the full Swift package suite. The direct compiler build is available when the installed SwiftPM runtime itself is broken. If Apple's selected SDK and compiler are incompatible, set `WCH_SDK_PATH` to a compatible **already installed** SDK; the project does not download or modify system toolchains.

Release builds are ad hoc signed by default and **not Apple-notarized**. `CODESIGN_IDENTITY` and `NOTARIZATION_PROFILE` enable a maintainer's Developer ID signing/notarization workflow. `build-release.sh` produces an app archive for the host architecture.

Uninstall stops the LaunchAgent and moves the app/startup entry into a recoverable local backup. Settings, saved layouts and logs are retained. Remove the app's Privacy & Security entries yourself if desired.

Developer control commands use the existing user-private driver socket and do not start another HID owner:

```sh
"$HOME/Applications/WCH Touch Driver.app/Contents/MacOS/MacXeneonEdgeTouchDriver" status
"$HOME/Applications/WCH Touch Driver.app/Contents/MacOS/MacXeneonEdgeTouchDriver" layout-status
"$HOME/Applications/WCH Touch Driver.app/Contents/MacOS/MacXeneonEdgeTouchDriver" save-layout
"$HOME/Applications/WCH Touch Driver.app/Contents/MacOS/MacXeneonEdgeTouchDriver" restore-layout
```

Use the actual app path if upgrading an installation in `/Applications`. See [historical upstream documentation](docs/upstream-readme.md) for inherited implementation details; it describes the old installer and original behavior.
