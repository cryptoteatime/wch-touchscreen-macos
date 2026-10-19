# Privacy and security

## Permissions

WCH uses **Input Monitoring** to receive touchscreen reports and **Accessibility** to control the pointer and, when desktop memory is enabled, read window metadata and place windows. These are broad macOS permissions. The application filters touchscreen input to the configured WCH controllers.

The app has no analytics or upload feature. Its control interface is a user-private Unix socket on the same Mac, not a network service. The source release is built locally and ad hoc signed unless a Developer ID identity is supplied; no Apple-notarized binary is currently provided.

Optional brightness control reads the built-in display brightness, uses DDC/CI for compatible external panels, and exchanges local distributed notifications with DisplayLink Manager when a configured screen needs that connection. This is local inter-application communication, not a remote network connection. Only configured monitors are selected; ambiguous identities are skipped.

## Local data

Runtime files live in `~/Library/Application Support/MacXeneonEdgeTouchDriver/`. The layout snapshot stores app identifiers, local process/window identifiers, and geometry. Optional window-identifier, document, and title fingerprints use HMAC-SHA256 with a random local salt stored separately. Readable titles, document URLs, and document contents are not saved in the snapshot. The snapshot and salt have owner-only file permissions.

Brightness preferences store monitor identifiers and remembered levels in `brightness.json`, also with owner-only permissions.

Individual monitor profiles in `config.json` include display UUIDs, vendor/model identifiers, serials, local labels, and brightness routing preferences. Saving profiles uses owner-only permissions. These identifiers are used locally to select the correct display.

These files remain private metadata even when fingerprinted. Do not publish `desktop-layout.json`, `pairings.json`, `brightness.json`, `window-identity-salt`, local configuration, or backups. Diagnostic logs may contain local identifiers and touch coordinates; redact them before sharing. Uninstall retains settings and logs for recovery.

## Report a security issue

Use **Security → Report a vulnerability** on this repository to [report privately through GitHub](https://github.com/cryptoteatime/wch-touchscreen-macos/security/advisories/new). Include the affected version and a minimal reproduction, with credentials and personal data removed. Ordinary setup or hardware issues belong in [Issues](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new/choose).

Please reproduce against the latest release or current `main` when possible. This is a community project; older releases do not have a separate security maintenance schedule.
