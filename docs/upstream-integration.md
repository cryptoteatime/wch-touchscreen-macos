# Upstream integration

[Contributing](../CONTRIBUTING.md) · [Credits](../THIRD_PARTY_NOTICES.md)

This repository builds on [mrnocreativity's multi-display driver](https://github.com/mrnocreativity/xeneon-wch-touchscreen-driver-macos), descended from [ajvwhite's original driver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver). The GitHub fork relationship and original commit history are retained. A branch being ahead records this project's additions; being behind means upstream commits have not yet been integrated.

## November 16, 2026 integration

Reviewed upstream through [`69e8869`](https://github.com/mrnocreativity/xeneon-wch-touchscreen-driver-macos/commit/69e8869). The merge incorporates privacy setup guidance, read-only HID descriptor checks, automatic pairing for a lone supported screen, guided selection of unlisted touchscreens, and learned display models.

Explicit Monitor Profiles take precedence over automatic discovery, including profiles with touch disabled. Built-in and mirrored displays are excluded from pairing. Learned model recognition does not establish a physical pairing or override connection-identity checks. Portrait mapping, gestures, brightness, connection memory, and desktop/window restoration remain part of this fork.

The optional compatibility report opens a preview. Copying it and opening a GitHub issue require user actions; the app does not submit reports. Reports are directed to this repository.

### Installer differences

Upstream's portable installer installs a standalone executable. This fork continues to install **WCH Touch Driver.app** at its existing location, preserving the app identity, menu controls, settings, and recovery copies. Upstream's portable installer and its release helper are not included. Current installation instructions are in [Setup](setup.md).

The app installer adopts upstream's launchd shutdown safeguard: it waits for confirmed service removal before replacing or removing installed files. Unknown service state or a timeout stops the operation. Rollback also confirms shutdown before changing files and retains a permanent recovery copy if it cannot proceed.

### Compatibility evidence

Hardware reports are checked at their original source. The Logicom Nomad Touch entry remains unverified because the reporter's [follow-up](https://github.com/mrnocreativity/xeneon-wch-touchscreen-driver-macos/issues/1#issuecomment-6735320711) says it was not working. A matching controller alone does not establish working support. See the [monitor list](monitors.md).

## Future updates

Merge upstream on a review branch, resolve differences in favor of documented behavior, and run the checks in [Contributing](../CONTRIBUTING.md#checks). Publish only after the Apple Silicon and Intel CI jobs pass. Installing a newly merged build and physically testing it are separate steps; passing CI does not establish hardware compatibility.
