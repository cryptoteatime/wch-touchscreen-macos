# Compatibility and verification

[Back to README](../README.md)

The project targets macOS 13 or later and compatible **wch.cn TouchScreen USB `27C0:0859`** controllers. A matching USB identifier alone does not establish compatibility. Controller firmware, report formats, and display identity can differ between retail products.

## Tested configuration

| Component | Verified setup |
| --- | --- |
| Mac | Apple Silicon MacBook Pro |
| OS | macOS 26.6.2 |
| Touch controllers | Two WCH `27C0:0859` controllers |
| Display descriptors | Type-c and HDMI; EDID vendor/model `4A8B:2200` |
| External layout | 1050 × 1680, rotated 90° and 270° |
| Driver | Fork versions 1.2–1.4 |
| Brightness | Native Apple Silicon DDC/CI; DisplayLink Manager 17.0.24 |

The marketed monitor model has not been independently verified. These shared product identifiers are more reliable than assuming an Amazon listing variant. Other panels, Intel Macs, and other macOS versions need hardware testing.

The original Xeneon configuration remains available through `--profile xeneon`. Prior upstream reports are retained in the [historical upstream documentation](upstream-readme.md); they do not establish verification of this fork's new features on those products.

## Verification

- Physical tests confirmed portrait touch mapping, pointer placement, normal clicking, long-press right-click, and dragging on both panels.
- Physical unplug/reconnect testing in 1.4.0 retained both monitor profiles, restored the portrait display layout and both touch mappings, and returned nine open windows to their saved positions and sizes.
- Simulated process/window identity changes restored saved placements. Automated scenarios cover delayed app startup, logout closures, transient missing windows, and late display geometry changes.
- Full restart validation of the layout protection introduced in 1.2.1 remains pending. Automated checks cannot verify every application's macOS Resume behavior.
- [macOS CI](https://github.com/cryptoteatime/wch-touchscreen-macos/actions/workflows/verify.yml) runs the Swift package tests, standalone regression scenarios, and app build/signature verification.

### Brightness and monitor profiles

- MacBook brightness controls changed both panels. Native writes were verified with hardware readback; DisplayLink writes received acknowledgements.
- Physical-button testing confirmed that DisplayLink reports cached brightness rather than live button changes. The HDMI panel retained its setting on some reconnects but reset to 10% in a later test. Version 1.4.1 explicitly restores WCH's saved DisplayLink level with bounded acknowledgement retries.
- Brightness regression scenarios cover startup defaults, one-percent button changes, restart persistence, duplicate identities, bounded failures, and MacBook following.
- Profile regression scenarios cover mixed display models, native-only and mixed connections, independent following preferences, excluded monitors, and configuration migration. Other monitor models and connection combinations still require hardware testing.
- Physical reconnect testing in 1.4.1 restored both saved brightness levels, both profiles, the portrait layout, and nine windows, with touch working on both panels. The HDMI panel initially reported 10%, then acknowledged the saved 100% setting; the operator confirmed the visible brightness returned without a button press. Native brightness was confirmed by hardware readback. A brief dim interval remains while DisplayLink reconnects and restoration settles.
- Full reboot brightness testing remains pending. See [brightness behavior and limitations](brightness.md).

The controller's current input mode supplies a single contact. Pinch-to-zoom and multi-finger gestures require a working multi-contact protocol and are not available through a settings toggle.

## Report your hardware

Use the [compatibility report form](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new?template=compatibility-report.yml). Include the retail model, macOS version, public product identifiers, and what worked on each screen. Omit unique serial numbers, display UUIDs, USB location IDs, and raw saved profiles.
