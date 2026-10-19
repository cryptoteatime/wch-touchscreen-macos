# Monitor profiles

[Back to README](../README.md) · [Brightness](brightness.md)

Open **WCH → Monitor Profiles…** with your screens connected. Select a monitor, choose its settings, then click **Apply & Restart WCH**. Changes to every monitor in the panel are saved together. Existing touch pairings, gestures, desktop layouts, and brightness targets are preserved.

| Setting | Purpose |
| --- | --- |
| Profile name | A local label for the monitor |
| Use this monitor for WCH touch pairing | Include this display in physical touch pairing |
| Brightness connection | Automatic, Native DDC/CI, DisplayLink, or Off |
| Brightness behavior | Use the global setting, follow MacBook changes, or remember an independent level |

The monitor picker shows its current desktop coordinates or “disconnected.” Saved profiles remain available when unplugged. **Forget Selected Profile** removes its selection when you apply; a connected screen can be added again by reopening the panel.

## Mixed monitors and connections

Profiles match individual video displays rather than requiring every screen to share one vendor/model. Different compatible WCH touchscreens can therefore be paired together. Non-touch monitors can participate in supported brightness control with touch pairing unchecked.

**Automatic** prefers a uniquely identified native brightness endpoint. If that route is unavailable, WCH checks DisplayLink only while DisplayLink Manager is running and a selected screen needs it. Each screen receives writes through one selected route. Native-only configurations do not require DisplayLink Manager.

**Native DDC/CI** and **DisplayLink** restrict a monitor to that connection. **Off** excludes it from brightness control. The chosen route must be supported by the monitor, adapter, Mac, and driver; selecting a route does not add capabilities to the hardware. Native brightness currently uses Apple Silicon IOAV DDC/CI, and DisplayLink brightness is tested with Manager 17.0.24.

Enable brightness control from **WCH → Monitor Brightness**. Per-monitor following overrides apply while brightness control is enabled. **Turn Off Brightness Control** stops all automatic following. **Match MacBook Brightness Now** is a one-time match for all enabled brightness profiles, including profiles that normally keep an independent level. Equal percentages can look different across panels.

## Identity and pairing

Profiles retain the display UUID, public vendor/model, serial, and available native brightness identity locally. If an adapter recreates a video UUID, WCH accepts a hardware fallback only when that vendor/model/serial combination is unique in both the saved and connected sets. DisplayLink brightness targets keep their original profile identity while writes use the current connection identifier. Ambiguous identities are skipped.

Matching does not depend on resolution, portrait orientation, or the current display number. A different cable path or adapter can still require selecting the newly detected display and pairing again.

USB touch pairing remains separate from video selection. This driver supports the tested single-contact WCH **27C0:0859** protocol. Adding a display profile does not implement other touch controller protocols or multi-finger gestures. Identical displays without distinguishable brightness endpoints may be unavailable for brightness control.

## Existing configurations

The older `display` vendor/model setting remains supported until you save individual monitor profiles. On first opening, currently connected monitors matching that legacy setting are selected automatically. Other detected screens start with touch and brightness off. Saving an empty profile list disables monitor selection rather than falling back to the old model filter.

With individual profiles, desktop layout learning supports one or more selected external monitors alongside a built-in display, and waits for all configured monitors with touch or brightness enabled. The entire saved desktop must be connected before automatic restoration. See [desktop restoration](desktop-restoration.md).

Profile data lives in the existing local `config.json` and is included in installer backups. Keep that file and raw diagnostic output private; see [privacy](../SECURITY.md).
