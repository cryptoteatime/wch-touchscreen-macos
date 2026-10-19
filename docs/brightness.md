# Monitor brightness

[Back to README](../README.md)

Brightness control is optional and starts off. Open **WCH → Monitor Brightness → Follow MacBook Brightness Changes** to enable it. Enabling immediately matches connected compatible monitors to the MacBook's current brightness; later MacBook brightness changes update them again. The menu setting survives WCH restarts and login.

Use **WCH → Monitor Profiles…** to select a connection and following preference for each screen. Automatic selection prefers a uniquely identified native route, and activates the DisplayLink integration only when a selected screen needs it and DisplayLink Manager is running. See [monitor profiles](monitor-profiles.md).

## Physical buttons and reconnecting

Monitor buttons can override a screen's brightness until the next MacBook brightness change. What can be remembered depends on the connection:

| Connection | Button changes | Reconnect or login |
| --- | --- | --- |
| Supported native Apple Silicon display, such as the tested Type-c panel | WCH reads the hardware level and remembers a stable change | WCH restores the saved level after the connection settles, verifies it, and retries for a bounded period |
| DisplayLink, such as the tested HDMI panel | Buttons work, but DisplayLink's reported level stays cached | WCH leaves the panel's own retained setting alone; it cannot reliably restore an unreadable button override |

The tested HDMI panel retains its own setting. Other hardware may reset it. If that happens, choose **Match MacBook Brightness Now** or adjust the MacBook brightness again. WCH deliberately does not write a stale cached level over a physical-button adjustment on reconnect.

If the Type-c panel resets to a low startup default, that default does not replace its saved level. A failed restore keeps the saved target and reports the failure. Allow roughly fifteen seconds after reconnecting before adjusting its physical buttons so the initial restoration can finish.

WCH follows the brightness value, including changes made by macOS automatic brightness. Equal percentages do not guarantee equal perceived brightness across different panels. WCH changes hardware brightness; it does not use a dimming overlay, adjust contrast, or change resolutions.

## Menu controls

| Control | Behavior |
| --- | --- |
| Follow MacBook Brightness Changes | Enable syncing for profiles using the global setting; per-monitor overrides remain in effect |
| Match MacBook Brightness Now | Send the current MacBook level once and remember it |
| Remember Current Brightness | Capture readable hardware levels and turn off global following; explicit per-monitor follow preferences remain in effect |
| Brightness Status… | Show remembered targets and the last write result |
| Turn Off Brightness Control | Stop automatic reads and writes; keep saved preferences |

DisplayLink values in status are last-known values, not live readings of physical-button changes. **Remember Current Brightness** cannot capture an HDMI button override through DisplayLink. A single explicit match enables brightness memory but does not turn on continuous following when it was off.

## Compatibility and implementation

The native transport currently targets Apple Silicon DDC/CI through optional `IOAVService` symbols. DisplayLink support uses Manager 17's local distributed-notification interface. Neither interface is a stable public macOS API; changes in macOS or DisplayLink Manager may require an update. Missing or ambiguous identities are skipped. Individual monitor profiles support different display models; legacy configurations continue to use their display vendor/model filter.

The MacBook is read through `DisplayServicesGetBrightness`; WCH never writes its brightness. External hardware I/O runs on a separate utility queue so it does not block touch processing. DisplayLink writes are checked for an acknowledgement; that acknowledgement is not an independent optical measurement or a live read of the monitor buttons. Native writes are checked by hardware readback.

Preferences and monitor identifiers are stored locally in `brightness.json` with owner-only file permissions. The installer backs this up with the other settings. Do not upload this file or raw diagnostic output to GitHub; see [privacy](../SECURITY.md).

For local diagnostics, the installed executable accepts `brightness-status`, `follow-brightness`, `brightness-independent`, `remember-brightness`, `sync-brightness`, `restore-brightness`, and `brightness-off`. `restore-brightness` retries native restoration only. All normal operation is available from the WCH menu.
