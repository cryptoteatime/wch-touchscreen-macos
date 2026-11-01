# Will my touchscreen work?

[Back to README](../README.md) · [Monitor list](monitors.md) · [Setup guide](setup.md)

## Quick answer

WCH makes supported touchscreens behave like a mouse on your Mac: tap to click, slide to scroll, and hold to right-click. It can map each screen separately, including portrait screens. It requires macOS 13 or later.

**Start with the [monitor list](monitors.md).** You can search by brand, model, or product number. Each entry says whether it was tested with this project, reported working with an earlier driver, or still needs Mac testing. A missing entry means we don't have a report yet.

You don't need to know which driver came with your monitor. The important part is the touch hardware inside it. WCH currently works with one specific family of touch controllers, so it cannot add touch support to every USB-C or HDMI monitor.

## Find your monitor

1. Look for the brand and model on the back of the screen, its box, or your order's product description. A product link is useful too; you do not need to share your order or receipt.
2. Look up that name in the [monitor list](monitors.md). Match the exact model and variant where possible.
3. If it is missing, use the optional check below or [send a hardware report](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new?template=compatibility-report.yml) with what you know. Technical fields can be left blank.

Names such as **HDMI**, **Type-c**, and **USB Display** in macOS may describe a connection rather than the retail model. Similar-looking monitors can also contain different touch hardware.

<details>
<summary>Check the touch hardware in System Information — no Terminal needed</summary>

1. Connect and power the monitor using its USB data/touch connection. HDMI alone does not carry USB touch input; some monitors need a separate USB cable.
2. Hold **Option** while opening the **Apple menu**, then choose **System Information**. [Apple's instructions](https://support.apple.com/guide/system-information/welcome/mac) also describe opening it through System Settings.
3. Select **USB** under Hardware in the sidebar. Look for **TouchScreen** or **wch.cn**, and select that device.
4. Check **Vendor ID** and **Product ID**. The controller this driver looks for is **Vendor ID `0x27c0`**, **Product ID `0x0859`**. These identify the type of hardware; they are not your device's serial number.

**Both match:** your monitor is a candidate. A physical test is still needed because its firmware and the way it sends touch input may differ.

**Different numbers:** this driver does not currently recognize that controller. Choosing another display profile does not add support for it.

**No touch device appears:** check the monitor's data port, cable, and power before deciding it is incompatible. A working picture does not prove the USB touch connection is working.

If asking for help, copy just the device name and these two IDs. Keep serial numbers, location IDs, and full system reports private.

</details>

## Picture, touch, and brightness are separate

| What you want | What it needs |
| --- | --- |
| A picture on the screen | A working video connection supported by your Mac. Keep DisplayLink if your monitor's video connection requires it; WCH does not require DisplayLink for every setup. |
| Taps on the correct screen | Compatible touch hardware, a USB data connection, WCH's permissions, and screen pairing. |
| Scrolling, dragging, and right-click | WCH's [one-finger controls](../README.md#touch-controls). Multi-finger gestures are not supported, even if the monitor advertises them for Windows. |
| Brightness controls and memory | A monitor and connection that allow software brightness control. Touch can work even when brightness control is unavailable. See [brightness](brightness.md). |
| Monitor layout and window memory | Enable the option in WCH. After a restart, macOS or each app must reopen its windows before WCH can put them back. See [desktop restoration](desktop-restoration.md). |

## Verification

| Setup or feature | Current evidence |
| --- | --- |
| Two portable touchscreens on an Apple Silicon (M-series) MacBook Pro | Physically tested: portrait touch, clicking, right-click, dragging, brightness following, and restoring layout and windows after reconnect. The retail model is still unidentified. |
| CORSAIR XENEON EDGE and Prechen HD-123 | Reports from the drivers this project builds on. See the [model entries](monitors.md#earlier-driver-reports) for the tested features and limits. |
| Intel Macs and other macOS versions | Builds and automated checks run on Apple Silicon and Intel, on macOS 15 and 26. This does not establish physical monitor compatibility; Intel brightness support is experimental. |
| Closed-lid laptops, desktop Macs, and full reboot restoration | Automated scenarios are covered. Physical validation of these configurations and the current reboot restoration changes remains pending. |

The [hardware verification details](hardware-verification.md) retain the exact versions, connection types, test observations, and remaining gaps. Model reports apply to the tested setup and features; they are not a promise that every version sold under that name behaves identically.

## Help grow the list

[Report your monitor](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new?template=compatibility-report.yml), including unsuccessful results. A product name or link, your Mac/macOS version, and a description of what you tried are enough to start. Model numbers and public product codes such as SKU, UPC/EAN, or Amazon ASIN help distinguish variants when available. Please omit order details, serial numbers, and raw saved profiles.
