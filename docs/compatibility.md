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
| Driver | Fork version 1.3.0 |
| Brightness | Native Apple Silicon DDC/CI; DisplayLink Manager 17.0.24 |

The marketed monitor model has not been independently verified. These shared product identifiers are more reliable than assuming an Amazon listing variant. Other panels, Intel Macs, and other macOS versions need hardware testing.

The original Xeneon configuration remains available through `--profile xeneon`. Prior upstream reports are retained in the [historical upstream documentation](upstream-readme.md); they do not establish verification of this fork's new features on those products.

## Verification

- Physical tests confirmed portrait touch mapping, pointer placement, normal clicking, long-press right-click, and dragging on both panels.
- Physical unplug/reconnect testing restored both touch mappings and nine open windows to their saved positions and sizes.
- A live changed-identity simulation replaced saved process/window identities and restored all nine placements, then recaptured the real identities.
- Release 1.2.0 passed 162 Swift package tests, 87 standalone regression checks, and an app build/signature check. See the [release verification run](https://github.com/cryptoteatime/wch-touchscreen-macos/actions/runs/39203946233) and [current CI](https://github.com/cryptoteatime/wch-touchscreen-macos/actions/workflows/verify.yml).
- The first physical Mac restart preserved display modes and touch mappings but exposed incomplete window restoration: startup restored a snapshot containing only one window. Version 1.2.1 adds protection against disappearing windows during teardown and late display geometry changes. **A repeat full restart test of that fix remains pending.** Automated scenarios cannot verify every application's macOS Resume behavior.

### Brightness in 1.3.0

- The installed WCH app sent brightness to both panels directly. Native hardware readback confirmed the target and DisplayLink acknowledged its write; no Shortcut was involved. Both touch controllers stayed active and all nine saved windows restored after the app update.
- A physical-button test set the HDMI panel to 70%, while a fresh DisplayLink query still reported 85%. WCH therefore does not automatically restore that cached level over HDMI button overrides. The user previously confirmed that this HDMI panel retained its own setting across reconnect.
- The brightness policy passed 29 standalone checks, including native startup defaults, one-percent button changes, restart persistence, duplicate identities, bounded failures, and MacBook sync. Together with the existing suite, 140 standalone checks passed locally, along with an app build and signature verification.
- Physical MacBook-key following and a reconnect/reboot of the new brightness feature still need end-to-end verification. Readback and simulation are not a substitute for these tests. See [brightness behavior and limitations](brightness.md).

The controller's current input mode supplies a single contact. Pinch-to-zoom and multi-finger gestures require a working multi-contact protocol and are not available through a settings toggle.

## Report your hardware

Use the [compatibility report form](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new?template=compatibility-report.yml). Include the retail model, macOS version, public product identifiers, and what worked on each screen. Omit unique serial numbers, display UUIDs, USB location IDs, and raw saved profiles.
