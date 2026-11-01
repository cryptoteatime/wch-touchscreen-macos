# Monitor compatibility list

[Compatibility guide](compatibility.md) · [Back to README](../README.md) · [Report a monitor](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new?template=compatibility-report.yml)

Last reviewed: **November 1, 2026**.

Use **Command-F** to search for your brand, model, or product code. This list starts small and grows with sourced reports. Read the status beside a model before using it to choose a monitor.

## At a glance

| Monitor | Evidence | Product code, where verified |
| --- | --- | --- |
| [Dual-screen portable extender](#dual-screen-portable-extender--retail-model-unidentified) | Tested with this project; retail identity unknown | Unknown |
| [CORSAIR XENEON EDGE 14.5-inch](#corsair-xeneon-edge-145-inch-lcd-touchscreen) | Earlier driver report | Manufacturer SKU `CC-9011306-WW` |
| [Prechen HD-123 12.3-inch](#prechen-hd-123-123-inch-portable-touch-screen-secondary-monitor) | Earlier driver report | Reported ASIN `B0CTMNPBX3` |
| [Anmite A156W03T](#models-awaiting-mac-testing) | Needs Mac testing | Unknown |
| [LOGICOM NOMAD TOUCH](#models-awaiting-mac-testing) | Needs Mac testing | Unknown |
| [Verbatim PMT-15](#models-awaiting-mac-testing) | Needs Mac testing | Unknown |

## What the labels mean

| Label | Evidence |
| --- | --- |
| **Tested with this project** | Someone tested the listed features on physical hardware using this project. Remaining gaps are recorded. |
| **Earlier driver report** | Reported by an author of an earlier driver this project builds on. This project's added features still need testing on that model. |
| **Needs Mac testing** | A source identifies the expected touch controller, but we have no working report for this driver on that product. |

## Tested with this project

### Dual-screen portable extender — retail model unidentified

**Status: Tested with this project.** Two portrait panels, shown by macOS as **Type-c** and **HDMI**, were tested on an Apple Silicon MacBook Pro with macOS 26.6.2. One video connection is native USB-C and the other uses DisplayLink. Both touch controllers identify as `27C0:0859`.

Physical tests cover touch mapping, clicking, right-click, dragging, brightness following, and restoring layout and app windows after reconnect. Full reboot validation of the current changes remains pending. See the [dated test record](hardware-verification.md).

The brand, exact model, and physical panel size have not been verified. **Type-c and HDMI are not model numbers.** This entry records a working setup but cannot identify a product to buy. No retail listing or barcode is treated as a confirmed match.

## Earlier driver reports

### CORSAIR XENEON EDGE 14.5-inch LCD Touchscreen

**Status: Earlier driver report.** The original driver's author documents one XENEON EDGE in landscape on Apple Silicon, with tapping, double-clicking, dragging, and optional one-finger scrolling. The original driver does not support multiple touch panels or two-finger gestures. [Original driver documentation](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver/blob/1ce4828f529760723c5271b1b7e6f2022ab7e394/README.md).

- **Product identification:** 2560 × 720; CORSAIR lists SKU **CC-9011306-WW** for the black model. This identifies the manufacturer listing, not a separate test of every SKU or color. [Manufacturer product page](https://www.corsair.com/us/en/p/monitors/cc-9011306-ww/xeneon-edge-14-5-lcd-touchscreen-cc-9011306-ww).
- **Touch hardware:** `27C0:0859`, recorded as the original reference target in the [upstream compatibility table](https://github.com/mrnocreativity/xeneon-wch-touchscreen-driver-macos/blob/707106e828d178db004a7ec1b3d8eee9447b03b9/README.md#known-compatibility).
- **Still to verify with this project:** portrait, multiple panels, brightness control, and layout/window restoration on this model.

### Prechen HD-123 12.3-inch Portable Touch Screen Secondary Monitor

**Status: Earlier driver report.** The upstream maintainer reports testing two identical panels on September 2, 2026: pairing, taps, scrolling, hold-to-drag, double-clicks, reconnect handling, and recovery from malformed touch input. [Dated upstream report](https://github.com/mrnocreativity/xeneon-wch-touchscreen-driver-macos/blob/707106e828d178db004a7ec1b3d8eee9447b03b9/README.md#known-compatibility).

- **Product identification in that report:** model **HD-123**, Amazon ASIN **B0CTMNPBX3**, 1920 × 720, USB-C and HDMI.
- **Touch hardware:** `27C0:0859`.
- **Still to verify with this project:** portrait behavior, brightness control, and layout/window restoration. The report does not specify the exact Mac model or macOS version.

## Models awaiting Mac testing

**Mac testing is still needed for these models.** HARMAN's Soundcraft Ui24R beta-testing list associates the following product names with `27C0:0859`. That list concerns an audio mixer; compatibility with this Mac driver remains unverified. [HARMAN's controller list](https://help.harmanpro.com/en_US/sc-ui-series/ui24r-beta-pidvid-touchscreen-compatibility-testing), updated August 24, 2026.

| Brand | Model named by the source | Status |
| --- | --- | --- |
| Anmite | A156W03T | Needs Mac testing |
| LOGICOM | NOMAD TOUCH | Needs Mac testing |
| Verbatim | PMT-15 | Needs Mac testing |

Check your own unit using the [System Information steps](compatibility.md#find-your-monitor). The source lists other Verbatim models with different controller IDs, so a brand name alone is not enough. We have not verified UPC/EAN barcodes or additional retail variants for these entries.

## Add a model or update a result

Use the [hardware report form](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new?template=compatibility-report.yml). Unknown technical details are fine. Include what you can identify from the product label or listing, what you tested, and whether each feature worked.

For additions to this list, record:

- Brand, exact model/variant, and a public product link. Add SKU, UPC/EAN, or ASIN only when the label or a cited source supports it. These are product codes, not unique serial numbers.
- Evidence label, test date, WCH version, Mac model, macOS version, cables/docks, and power source where known. Mark missing details as unknown.
- Results for touch, rotation, gestures, brightness, reconnect, sleep/wake, and reboot separately. Leave untested features marked untested.
- A link to the original report and any limitations or conflicting results. Keep conflicting variants separate instead of silently replacing an earlier result.

A store listing, matching USB ID, or passing automated test alone is not enough for **Tested with this project**. Please keep serial numbers, order information, and private system reports out of public issues.
