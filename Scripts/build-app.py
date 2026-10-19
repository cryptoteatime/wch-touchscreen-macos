#!/usr/bin/env python3
"""Create the app bundle used by the per-user installer."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from build_support import ROOT, compile_binary

version = (ROOT / "VERSION").read_text().strip()
artifacts = ROOT / "artifacts"
artifacts.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="wch-build-", dir=artifacts) as scratch:
    stage = Path(scratch)
    main = stage / "DriverMain.swift"
    # The direct compiler route avoids a dependency on SwiftPM's own runtime.
    main.write_text((ROOT / "Sources/MacXeneonEdgeTouchDriver/main.swift").read_text()
                    .replace("import MacXeneonEdgeTouchDriverCore\n", ""))
    bundle = stage / "WCH Touch Driver.app"
    contents = bundle / "Contents"
    (contents / "Resources").mkdir(parents=True)
    compile_binary(main, contents / "MacOS/MacXeneonEdgeTouchDriver")
    info = {"CFBundleExecutable": "MacXeneonEdgeTouchDriver",
            "CFBundleIdentifier": "com.ajvwhite.MacXeneonEdgeTouchDriver",
            "CFBundleName": "WCH Touch Driver", "CFBundleDisplayName": "WCH Touch Driver",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
            "CFBundleVersion": version, "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
            "NSHighResolutionCapable": True,
            "NSHumanReadableCopyright": "MIT; original driver by ajvwhite; multi-display fork by Ronny Welter; desktop additions by cryptoteatime."}
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    for name in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
        shutil.copy2(ROOT / name, contents / "Resources" / name)
    identity = os.environ.get("CODESIGN_IDENTITY", "-")
    command = ["codesign", "--force", "--options", "runtime", "--sign", identity]
    if identity != "-":
        command += ["--timestamp"]
    subprocess.run(command + [str(bundle)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
    destination = artifacts / bundle.name
    # Fresh executable inodes avoid stale macOS code-signing cache entries.
    if destination.exists():
        shutil.rmtree(destination)
    shutil.move(str(bundle), destination)
    print(destination)
