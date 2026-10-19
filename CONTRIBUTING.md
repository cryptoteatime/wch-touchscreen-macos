# Contributing

Use [Issues](https://github.com/cryptoteatime/wch-touchscreen-macos/issues/new/choose) for reproducible bugs and hardware reports, and pull requests for focused changes. Describe the user-visible behavior and how you checked it. Use [private security reporting](SECURITY.md#report-a-security-issue) for vulnerabilities.

Preserve the [MIT license](LICENSE), upstream history, and [author credits](THIRD_PARTY_NOTICES.md). The inherited bundle identifier remains `com.ajvwhite.MacXeneonEdgeTouchDriver` so upgrades replace the existing driver rather than creating a second owner of the HID device.

## Checks

```sh
swift test
python3 Scripts/test-regressions.py
python3 Scripts/build-app.py
```

[GitHub Actions](https://github.com/cryptoteatime/wch-touchscreen-macos/actions/workflows/verify.yml) runs the Swift package suite, standalone regressions, and an app build/signature check. The standalone suite covers connection persistence, gestures, display layout policy, reboot window matching, and private fingerprints.

The direct compiler build can be used when the local SwiftPM runtime is broken. If Apple's selected compiler and SDK are incompatible, set `WCH_SDK_PATH` to a compatible **already installed** SDK. The project does not download or modify toolchains.

Automated tests do not establish physical touchscreen or macOS Resume compatibility. Document which hardware and actions were actually tested; distinguish process-identity simulations from a real reboot.

## Build and signing

```sh
python3 Scripts/build-app.py
./Scripts/build-release.sh
```

The release script creates an app archive for the host architecture. Builds are ad hoc signed by default and are not Apple-notarized. Set `CODESIGN_IDENTITY` to use your Developer ID identity; `NOTARIZATION_PROFILE` enables the maintainer notarization workflow. Keep all signing credentials outside the repository.

The installer preserves recovery copies and replaces the app bundle rather than overwriting a running executable in place. Existing configuration, pairing, and layout files remain local.

## Local diagnostics

Use the existing driver's private local control socket. Do not start a second HID owner to inspect the first one.

```sh
"$HOME/Applications/WCH Touch Driver.app/Contents/MacOS/MacXeneonEdgeTouchDriver" status
"$HOME/Applications/WCH Touch Driver.app/Contents/MacOS/MacXeneonEdgeTouchDriver" layout-status
"$HOME/Applications/WCH Touch Driver.app/Contents/MacOS/MacXeneonEdgeTouchDriver" save-layout
"$HOME/Applications/WCH Touch Driver.app/Contents/MacOS/MacXeneonEdgeTouchDriver" restore-layout
```

Use `/Applications` instead of `$HOME/Applications` if that is where the existing app is installed. Runtime diagnostics can contain private machine identifiers and app metadata. Share a sanitized summary; never commit local profiles, pairings, identity salts, logs, screenshots, or credentials.

The [historical upstream README](docs/upstream-readme.md) and [design notes](docs/plans/) explain inherited implementation decisions. They describe earlier installers and behavior; current setup instructions are in the [setup guide](docs/setup.md).
