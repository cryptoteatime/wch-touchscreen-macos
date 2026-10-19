# Authors, Fork Lineage, and Research References

## Direct source ancestry

- **ajvwhite** created the original native Swift driver: [MacXeneonEdgeTouchDriver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver), MIT licensed. The underlying HID, gesture and driver architecture is inherited work.
- **Ronny Welter / mrnocreativity** developed the multi-display fork: [xeneon-wch-touchscreen-driver-macos](https://github.com/mrnocreativity/xeneon-wch-touchscreen-driver-macos). This fork starts from commit `707106e828d178db004a7ec1b3d8eee9447b03b9`; its Git history is retained, including multi-display pairing, observation and input validation work.
- **cryptoteatime**, with implementation assistance from OpenAI Codex, added portrait mapping, persistent connection preferences, direct pointer/focus behavior, long-press secondary click, double-click dragging, settings and gesture reference UI, and desktop/window restoration. This is a community fork, not an official WCH or monitor-vendor product.

The upstream copyright and MIT permission notice are retained in `LICENSE` and in built app bundles. Keeping the inherited bundle identifier preserves installation continuity; it does not imply endorsement by the original author.

## Desktop restoration research

- Apple's CoreGraphics display configuration and Accessibility window APIs underpin the implementation.
- [jakehilborn/displayplacer](https://github.com/jakehilborn/displayplacer) was consulted for macOS display-configuration constraints. Its implementation was not copied into this driver.
- Rotation uses the optional macOS `SLSSetDisplayRotation` symbol. It is a private OS interface and may change; the driver reports failure and retains the snapshot if it is unavailable.

## Brightness research and licensing

- [MonitorControl](https://github.com/MonitorControl/MonitorControl) informed the Apple Silicon IOAV/DDC declarations and protocol in `NativeMonitorBrightness.swift`. Its MIT notice is reproduced below and included in built app bundles through this file.
- DisplayLink Manager remains a separately installed Synaptics product. WCH's optional bridge uses Manager 17's local distributed-notification messages, verified against the installed application. No DisplayLink code or binary is redistributed. This vendor interface may change; its acknowledgement does not make cached brightness a live hardware-button reading.
- Reading the built-in display uses the optional private `DisplayServicesGetBrightness` symbol, which may change across macOS versions.

### MonitorControl MIT notice

MIT License

Copyright © 2017

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Upstream research acknowledgements

The public work below materially informed hardware validation and design decisions in the multi-display implementation. Each credit is scoped to the role that reference actually served.

## TouchscreenDriver

- Repository: [ymlaine/TouchscreenDriver](https://github.com/ymlaine/TouchscreenDriver)
- Author credit: Yves-Marie Lainé with Claude
- License: the repository [README](https://github.com/ymlaine/TouchscreenDriver#license) identifies the work as MIT-licensed.
- Consulted for: WCH `27C0:0859` report behavior, raw coordinate ranges, and exclusive user-space HID capture on the Xeneon Edge.

## xeneon-edge-multitouch-macos

- Repository: [Myseri/xeneon-edge-multitouch-macos](https://github.com/Myseri/xeneon-edge-multitouch-macos)
- Author credit: xeneon-touch contributors
- License: [MIT](https://github.com/Myseri/xeneon-edge-multitouch-macos/blob/main/userspace/LICENSE)
- Consulted for: hardware-verified USB interface behavior and evidence for the single-touch limitation on macOS.

## m14t-touch-macos

- Repository: [talesmousinho/m14t-touch-macos](https://github.com/talesmousinho/m14t-touch-macos)
- Author: Tales Fonseca
- License: [MIT](https://github.com/talesmousinho/m14t-touch-macos/blob/main/LICENSE)
- Consulted for: separation of HID input, display resolution, coordinate mapping, and synthetic events into small native Swift components.
