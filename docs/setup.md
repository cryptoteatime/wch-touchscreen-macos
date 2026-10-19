# Setup and everyday use

[Back to README](../README.md)

## Install

Check [compatibility](compatibility.md) before installing. You need Apple's Xcode or Command Line Tools, Python 3, and Git.

```sh
git clone https://github.com/cryptoteatime/wch-touchscreen-macos.git
cd wch-touchscreen-macos
./Scripts/install.sh --profile portable-dual-wch
```

For the original Corsair Xeneon defaults, use `--profile xeneon`. These presets initialize a new configuration only; updates preserve existing settings, pairings, and layouts. Select other models or configure mixed monitors in **WCH → Monitor Profiles…**; see [monitor profiles](monitor-profiles.md).

The installer places **WCH Touch Driver.app** in `~/Applications` for a new install, or updates the existing app at its current location. One per-user LaunchAgent starts it at login. Recovery copies are kept in the application's existing support directory. Installation does not require sudo.

The app handles touch. Keep DisplayLink running if your monitors need it for video. Stop any other touch driver controlling the same devices, including another WCH build, Touch-Up, or UPDD.

## Permissions and pairing

In **System Settings → Privacy & Security**, enable **Accessibility** and **Input Monitoring** for the exact installed WCH app. These allow touchscreen input, pointer control, and optional window placement. See [privacy and permissions](../SECURITY.md).

Touch and release the pairing target on each physical screen. Keep the same Mac USB ports, hubs, cables, and monitor-side data ports when reconnecting. Changing that arrangement or exchanging identical panels can require pairing again.

New portable-profile installs enable connection memory. Other configurations can opt in through Touch Settings. Connection memory remembers the connection arrangement; it does not give identical controllers a unique hardware identity.

## Menu controls

| Menu item | Purpose |
| --- | --- |
| Touch Settings… | Change gesture timing, sensitivity, and memory options |
| Monitor Profiles… | Select touch displays, brightness connections, and per-monitor following preferences |
| Gesture Cheat Sheet… | See the current touch controls |
| Pair Screens Again… | Replace saved touch mappings using physical targets |
| Save Current Desktop Layout | Accept the current connected arrangement |
| Restore Saved Desktop Layout | Retry the remembered arrangement |
| Desktop Layout Status | Inspect saved displays and restoration results |
| Monitor Brightness | Follow MacBook brightness or remember independent levels; see [brightness](brightness.md) |

**Apply & Restart Touch Driver** saves preferences and restarts WCH. It does not restart the Mac.

### Return focus to the previously active window

This option comes from the upstream driver's behavior. After a touch gesture, it reactivates and raises the window that was focused before the touch. It can be useful when briefly using a secondary touch panel while continuing keyboard work in another app.

The fork makes it optional and **off by default**, so the touched window stays active. Leave it off for ordinary touchscreen use: raising the previous window can undo macOS's wallpaper desktop reveal and look like a second tap, even though it is a focus change.

## Desktop restoration

Enable **Remember monitor layout and app windows**, then arrange windows with all screens attached. For restart behavior and limitations, see [desktop restoration](desktop-restoration.md).

## Update

From a clean source checkout:

```sh
git pull --ff-only
./Scripts/install.sh --profile portable-dual-wch
```

The installer preserves your configuration and keeps recovery copies of the old app, startup entry, and local settings. Local builds are ad hoc signed unless you provide a Developer ID identity. macOS may require you to refresh the app's existing permissions after updating; using a stable signing identity helps preserve them. See [build and signing](../CONTRIBUTING.md#build-and-signing).

## Remove

```sh
./Scripts/uninstall.sh
```

This stops WCH and moves the app and startup entry into a recoverable backup. Settings, saved layouts, and logs remain local. You can remove WCH's Privacy & Security entries in System Settings afterward.

## Troubleshooting

- **Video works but touch does not:** check permissions, the monitor's data port, and that another touch driver is not running.
- **Touch goes to the wrong screen:** choose Pair Screens Again and use the physical targets.
- **Windows have not returned yet:** check Desktop Layout Status and the [restoration limits](desktop-restoration.md#limits).
- **The build reports an SDK mismatch:** see [developer instructions](../CONTRIBUTING.md#checks); a compatible SDK may already be installed.

Use [GitHub Issues](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new/choose) for reproducible problems or compatibility reports. Share a short, sanitized description rather than your saved layouts or raw logs.
