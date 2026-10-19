# WCH Touch Driver for macOS

[![Build and tests](https://github.com/cryptoteatime/wch-touchscreen-macos/actions/workflows/verify.yml/badge.svg)](https://github.com/cryptoteatime/wch-touchscreen-macos/actions/workflows/verify.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Use compatible WCH touchscreens on your Mac, including multiple monitors in portrait. Tap a screen to move the pointer there, scroll with one finger, and keep your monitor layout when reconnecting.

[Latest release](https://github.com/cryptoteatime/wch-touchscreen-macos/releases/latest) · [Setup guide](docs/setup.md) · [Compatibility](docs/compatibility.md) · [Report a problem](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new/choose)

## What it does

- Maps touch to the correct screen in landscape or portrait.
- Remembers paired monitors when you reconnect through the same ports.
- Adds right-click, scrolling, dragging, and adjustable gesture timing.
- Remembers external monitor rotation, resolution, arrangement, and app window positions.
- Restores matching windows after login, once macOS or the app reopens them.
- Optionally follows MacBook brightness and remembers supported monitors' brightness.
- Configures touch and brightness separately for each monitor, including mixed models and connections.

This is a free community project for compatible **wch.cn `27C0:0859`** controllers. Check the [tested hardware and limitations](docs/compatibility.md) first. DisplayLink, when needed, handles video separately. Multi-finger gestures such as pinch-to-zoom are not currently supported.

## Get started

Requires macOS 13+, Apple's Xcode or Command Line Tools, Python 3, and Git. The current release is built from source; an Apple-notarized download is not provided.

```sh
git clone https://github.com/cryptoteatime/wch-touchscreen-macos.git
cd wch-touchscreen-macos
./Scripts/install.sh --profile portable-dual-wch
```

Grant **Accessibility** and **Input Monitoring** to **WCH Touch Driver** in System Settings → Privacy & Security, then follow the touch targets to pair your screens. WCH starts automatically at login. Existing settings are preserved during updates.

Use **WCH → Monitor Profiles…** to select your monitors and their brightness behavior, and **Touch Settings…** to adjust gestures. The [setup guide](docs/setup.md) covers permissions, updates, and removal.

## Touch controls

| Gesture | Action |
| --- | --- |
| Tap and lift | Click |
| Tap twice nearby | Double-click |
| Slide immediately | Scroll vertically or horizontally |
| Hold briefly, then move | Drag; lift to drop |
| Hold still, then lift | Right-click |
| Tap, then hold the second touch and move | Double-click drag |

Default holds are 0.3 seconds for dragging and 0.65 seconds for right-click. Open **WCH → Gesture Cheat Sheet…** for a quick reference. Gesture behavior can vary by app.

## Remember your desktop

Enable **Remember monitor layout and app windows**, then arrange your desktop with all screens attached. WCH learns changes automatically and restores the saved setup when those screens return.

For restarts, leave **Reopen windows when logging back in** checked. WCH restores positions of matching windows; macOS and each app reopen them. See [desktop restoration](docs/desktop-restoration.md) for timing and limits, and [verification status](docs/compatibility.md#verification) for what has been tested.

## Monitor brightness

Choose **WCH → Monitor Brightness → Follow MacBook Brightness Changes** to adjust compatible external screens with the MacBook's brightness controls. [Monitor profiles](docs/monitor-profiles.md) let each screen follow the global setting, follow independently, or retain its own level. Automatic connection selection prefers native DDC/CI and uses DisplayLink for screens that need it. See [brightness setup and hardware limits](docs/brightness.md).

## More information

- [Privacy, permissions, and security reporting](SECURITY.md)
- [Build, test, and contribute](CONTRIBUTING.md)
- [Release history](https://github.com/cryptoteatime/wch-touchscreen-macos/releases) · [Changelog](CHANGELOG.md)

## Credits

Built on [mrnocreativity's multi-display driver](https://github.com/mrnocreativity/xeneon-wch-touchscreen-driver-macos), which builds on [ajvwhite's original driver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver). Fork additions by cryptoteatime with OpenAI Codex assistance. Original history and the [MIT license](LICENSE) are retained; see [full acknowledgements](THIRD_PARTY_NOTICES.md).

This project is independent of WCH, Corsair, Synaptics, and monitor manufacturers.
