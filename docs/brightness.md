# Monitor brightness

[Back to README](../README.md)

Brightness control is optional and starts off. Open **WCH → Monitor Brightness → Follow MacBook Brightness Changes** to enable it. Enabling immediately matches connected compatible monitors to the MacBook's current brightness; later MacBook brightness changes update them again. The menu setting survives WCH restarts and login.

Use **WCH → Monitor Profiles…** to select a connection and following preference for each screen. Automatic selection prefers a uniquely identified native route, and activates the DisplayLink integration only when a selected screen needs it and DisplayLink Manager is running. See [monitor profiles](monitor-profiles.md).

## Physical buttons and reconnecting

Monitor buttons can override a screen's brightness until the next MacBook brightness change. What can be remembered depends on the connection:

| Connection | Button changes | Reconnect or login |
| --- | --- | --- |
| Supported native DDC/CI display, such as the tested Type-c panel | WCH reads the hardware level and remembers a stable change | WCH restores the saved level after the connection settles, verifies it, and retries for a bounded period |
| DisplayLink, such as the tested HDMI panel | Buttons work, but DisplayLink's reported level stays cached | WCH restores its saved level after the connection settles and waits for DisplayLink's acknowledgement |

DisplayLink restoration uses the last level saved by WCH, even when the reported cache already matches it. WCH makes at most four attempts, then reports a failure while retaining the target. After a successful acknowledgement, it stops writing until another reconnect or a MacBook brightness change. Hardware-button changes on that connection cannot be captured for the next reconnect; the saved WCH level takes precedence then.

The first DisplayLink restore is eligible half a second after WCH detects the selected endpoint, checked on a 100 ms timer. DisplayLink discovery and monitor startup add their own time. Each write still validates the current display identity and requires an acknowledgement; retries remain six seconds apart. A video connection change, paired touchscreen USB reconnect, sleep/wake, or DisplayLink Manager restart refreshes the connection and re-arms restoration. Saved levels survive these events.

Brightness changes are sampled every 100 ms. Each native monitor has its own hardware worker and retains only the newest unsent value during rapid key presses; DisplayLink dispatch does not wait for those workers. Native write/readback timing and retry limits are retained. Slow hardware calls cannot be forcibly canceled, but results from superseded targets or connections are discarded. The panels may still respond at different speeds.

If the Type-c panel resets to a low startup default, that default does not replace its saved level. A failed restore keeps the saved target and reports the failure. Allow roughly fifteen seconds after reconnecting before adjusting its physical buttons so the initial restoration can finish.

WCH follows the brightness value, including changes made by macOS automatic brightness. Equal percentages do not guarantee equal perceived brightness across different panels. WCH changes hardware brightness; it does not use a dimming overlay, adjust contrast, or change resolutions.

## Menu controls

| Control | Behavior |
| --- | --- |
| Follow MacBook Brightness Changes | Enable syncing for profiles using the global setting; per-monitor overrides remain in effect |
| Match MacBook Brightness Now | Send the current MacBook level once and remember it |
| Remember Current Brightness | Capture readable hardware levels and turn off global following; explicit per-monitor follow preferences remain in effect |
| Set Monitor Brightness… | Choose and remember a level without requiring an active built-in display |
| Restore Saved Brightness | Refresh connections and retry the remembered levels |
| Brightness Status… | Show remembered targets, write results, and session recovery counts |
| Turn Off Brightness Control | Stop automatic reads and writes; keep saved preferences |

DisplayLink values in status are last-known values, not live readings of physical-button changes. **Remember Current Brightness** cannot capture an HDMI button override through DisplayLink. A single explicit match enables brightness memory but does not turn on continuous following when it was off.

## Closed lid and desktop Macs

When no built-in display is active, WCH keeps the external monitors' saved levels and reconnect behavior. **Set Monitor Brightness…** works without a MacBook brightness source. Readable native button changes can still be remembered. Following resumes when an active built-in brightness source becomes available; per-monitor independent settings remain independent. WCH does not intercept an external keyboard's brightness keys or invent a built-in source.

## Compatibility and implementation

Apple Silicon uses optional `IOAVService` DDC/CI symbols. Intel builds add experimental framebuffer I2C DDC/CI for a uniquely matched vendor/model/serial identity. An Intel bus is used for writes only after a valid brightness read; indistinguishable monitors and unsupported buses are skipped. Intel hardware validation remains pending. DisplayLink support uses Manager 17's local distributed-notification interface. IOAV, DisplayServices, and the vendor notification interface may change across OS or Manager updates. Individual monitor profiles support different display models; legacy configurations continue to use their display vendor/model filter.

The MacBook is read through `DisplayServicesGetBrightness`; WCH never writes its brightness. Each native monitor uses a separate hardware queue so a slow monitor does not block touch processing, other monitors, or the brightness policy timer. DisplayLink writes are checked for an acknowledgement; that acknowledgement is not an independent optical measurement or a live read of the monitor buttons. Native writes are checked by hardware readback.

Preferences and monitor identifiers are stored locally in `brightness.json` with owner-only file permissions. The installer backs this up with the other settings. Do not upload this file or raw diagnostic output to GitHub; see [privacy](../SECURITY.md).

Brightness Status includes bounded session counters and the most recent 64 recovery events, with transport, time, and write latency. This brightness event list omits device identifiers and app metadata. Other driver diagnostics can contain private identifiers. Repeated read failures, missing acknowledgements, and discarded stale results help distinguish a control failure from a reported disconnect; they do not determine its physical cause. A panel reset that produces no USB/video event and no live readback may still need **Restore Saved Brightness** or a brightness adjustment.

For local diagnostics, the installed executable accepts `set-brightness:0` through `set-brightness:100`, `brightness-status`, `follow-brightness`, `brightness-independent`, `remember-brightness`, `sync-brightness`, `restore-brightness`, and `brightness-off`. `restore-brightness` retries restoration on both supported transports. All normal operation is available from the WCH menu.
