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
| Driver | Fork version 1.2.0 |

The marketed monitor model has not been independently verified. These shared product identifiers are more reliable than assuming an Amazon listing variant. Other panels, Intel Macs, and other macOS versions need hardware testing.

The original Xeneon configuration remains available through `--profile xeneon`. Prior upstream reports are retained in the [historical upstream documentation](upstream-readme.md); they do not establish verification of this fork's new features on those products.

## Verification

- Physical tests confirmed portrait touch mapping, pointer placement, normal clicking, long-press right-click, and dragging on both panels.
- Physical unplug/reconnect testing restored both touch mappings and nine open windows to their saved positions and sizes.
- A live changed-identity simulation replaced saved process/window identities and restored all nine placements, then recaptured the real identities.
- Release 1.2.0 passed 162 Swift package tests, 87 standalone regression checks, and an app build/signature check. See the [release verification run](https://github.com/cryptoteatime/wch-touchscreen-macos/actions/runs/39203946233) and [current CI](https://github.com/cryptoteatime/wch-touchscreen-macos/actions/workflows/verify.yml).
- **A complete Mac reboot test remains pending.** Automated scenarios cover changed identities, delayed app startup, and ambiguous windows, but cannot verify every application's macOS Resume behavior.

The controller's current input mode supplies a single contact. Pinch-to-zoom and multi-finger gestures require a working multi-contact protocol and are not available through a settings toggle.

## Report your hardware

Use the [compatibility report form](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new?template=compatibility-report.yml). Include the retail model, macOS version, public product identifiers, and what worked on each screen. Omit unique serial numbers, display UUIDs, USB location IDs, and raw saved profiles.
