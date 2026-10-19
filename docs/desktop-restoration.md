# Desktop restoration

[Back to README](../README.md) · [Setup](setup.md)

Desktop memory remembers external display rotations, available resolutions and scaling, screen arrangement, and ordinary app window positions and sizes. The built-in display's current resolution and refresh rate are preserved. The right external display follows the built-in screen's right edge if its logical width changes while disconnected.

Enable **Remember monitor layout and app windows** in Touch Settings. The portable profile enables it for new configurations.

## Reconnect

With all saved screens connected, WCH samples the stable desktop about every two seconds. Moving windows or changing the arrangement updates the saved layout automatically. The snapshot is frozen while a saved display is missing.

After driver startup, the saved layout is protected from automatic replacement for sixty seconds; reconnect and wake protect it for at least thirty seconds. If macOS applies a late display arrangement during this period, WCH restores the intended external geometry again. **Save Current Desktop Layout** accepts your chosen arrangement immediately if you want to override this settling period.

When every saved screen returns, WCH checks promptly after display callbacks and confirms matching hardware and geometry readings over at least half a second. It waits for macOS to finish reconfiguration, restores screen geometry, confirms the resulting state, and then moves matching windows. The two-second timer remains a fallback. Repeated attempts against unchanged geometry retain their two-second spacing and existing retry limits. A short visible settling period is expected.

App launches and quits do not restart the display settling clock. They still invalidate an in-flight snapshot, and automatic saving retains its three-second quiet period after either app or display changes. The longer startup/reconnect snapshot protections above also remain active while restoration proceeds.

## Restart or log in

Leave macOS **Reopen windows when logging back in** checked. macOS and each application reopen their windows; WCH then restores matching positions. WCH does not launch applications, reopen documents or tabs, or recreate Mission Control Spaces. [Apple explains reopening windows here](https://support.apple.com/en-us/102318).

WCH waits up to three minutes for saved windows to appear. Windows already restored are not repeatedly repositioned while other apps launch. Once the restoration period finishes, it resumes learning the connected desktop.

Disappearing windows must remain absent for sixty seconds before a smaller snapshot replaces the saved one. This protects against apps closing before the logout notification arrives, and against temporary Accessibility omissions. An empty response never automatically replaces a saved desktop. Intentional window closures are learned after the delay, or immediately through Save Current Desktop Layout.

## How windows are matched

Within one session, WCH prefers the same running window. Across sessions, it uses unique app-provided window identifiers, document fingerprints, or title fingerprints. If an app had exactly one saved window and has exactly one current window, it can match by application alone.

Fingerprints are private salted hashes stored locally. Readable titles, document URLs, and document contents are not saved. See [privacy details](../SECURITY.md#local-data).

## Limits

- Desktop memory requires a built-in display. Individual monitor profiles support one or more selected external displays; all profiles with touch or brightness enabled must be connected before learning a desktop. Legacy model-based configurations require at least two matching external screens.
- The complete saved monitor set must be present. Stable display identifiers and a unique hardware fallback accommodate changed DisplayLink IDs; ambiguous or different sets are not guessed.
- Multiple indistinguishable windows, minimized or full-screen windows, and windows that do not reopen within the waiting period are skipped.
- Apps may enforce minimum window sizes or refuse Accessibility placement. Desktop Layout Status reports failures. WCH retains the snapshot after placement errors rather than learning the failed arrangement.
- Only resolutions already available from macOS can be restored. WCH does not create custom display modes.
- Display rotation uses the optional private macOS function `SLSSetDisplayRotation`, which may change with OS updates. An unavailable or failing function pauses restoration without preventing touch startup.
- Canceling a logout after macOS has sent its shutdown notification may require restarting WCH to resume layout capture.

Use **Save Current Desktop Layout** to explicitly accept a new arrangement, or **Restore Saved Desktop Layout** to retry restoration. Desktop Layout Status distinguishes saved and live screen positions and shows whether capture is protected. [Compatibility and verification](compatibility.md#verification) distinguishes hardware tests from simulations.
