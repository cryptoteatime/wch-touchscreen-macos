#!/usr/bin/env python3
"""Stop WCH and move its installed app/agent into a recoverable local backup."""
from datetime import datetime
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

label = "com.ajvwhite.MacXeneonEdgeTouchDriver"
support = Path.home() / "Library/Application Support/MacXeneonEdgeTouchDriver"
agent = Path.home() / "Library/LaunchAgents" / (label + ".plist")
if not agent.exists():
    raise SystemExit("No WCH user LaunchAgent is installed. Settings and logs are unchanged.")
program = Path(plistlib.loads(agent.read_bytes())["ProgramArguments"][0])
app = next((p for p in program.parents if p.suffix == ".app" and p.exists()), None)
if app and plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier") != label:
    raise SystemExit("The configured app has an unexpected identity; no files were changed.")
backup = support / "backups" / ("uninstalled-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
backup.mkdir(parents=True, mode=0o700)
subprocess.run(["launchctl", "bootout", "gui/" + str(os.getuid()) + "/" + label], capture_output=True)
if app:
    shutil.move(str(app), backup / app.name)
shutil.move(str(agent), backup / agent.name)
print("WCH stopped. App and startup entry retained in:", backup)
print("Settings, pairings, desktop snapshots, identity salt, and logs were kept.")
print("You can remove WCH's permission entries manually in System Settings.")
