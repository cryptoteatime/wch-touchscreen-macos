#!/usr/bin/env python3
"""Install one app and one user LaunchAgent, preserving settings and rollback files."""
import argparse
from datetime import datetime
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
from build_support import ROOT

def bootstrap_agent(domain, agent):
    # bootout can acknowledge before launchd finishes removing the old job.
    for attempt in range(5):
        result = subprocess.run(["launchctl", "bootstrap", domain, str(agent)], capture_output=True, text=True)
        if result.returncode == 0:
            return
        if attempt == 4:
            raise subprocess.CalledProcessError(result.returncode, result.args, output=result.stdout, stderr=result.stderr)
        time.sleep(1)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--profile", choices=["portable-dual-wch", "xeneon"], default="xeneon")
parser.add_argument("--app-dir", type=Path, help="Defaults to the current app location, or ~/Applications")
parser.add_argument("--no-build", action="store_true")
parser.add_argument("--no-start", action="store_true", help="Install, but leave stopped for local permission approval")
args = parser.parse_args()
label = "com.ajvwhite.MacXeneonEdgeTouchDriver"
support = Path.home() / "Library/Application Support/MacXeneonEdgeTouchDriver"
agent = Path.home() / "Library/LaunchAgents" / (label + ".plist")
logs = Path.home() / "Library/Logs/MacXeneonEdgeTouchDriver"
domain = "gui/" + str(os.getuid())
if not args.no_build:
    subprocess.run([sys.executable, str(ROOT / "Scripts/build-app.py")], check=True)
source = ROOT / "artifacts/WCH Touch Driver.app"
subprocess.run(["codesign", "--verify", "--strict", str(source)], check=True)
previous_agent = agent.read_bytes() if agent.exists() else None
existing = None
if previous_agent:
    program = Path(plistlib.loads(previous_agent)["ProgramArguments"][0])
    existing = next((p for p in program.parents if p.suffix == ".app" and p.exists()), None)
app_dir = args.app_dir or (existing.parent if existing else Path.home() / "Applications")
app_dir.mkdir(parents=True, exist_ok=True)
destination = app_dir / "WCH Touch Driver.app"
if existing and existing != destination:
    raise SystemExit("Update the existing app in place; use --app-dir " + str(existing.parent))
if destination.exists():
    info = plistlib.loads((destination / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != label:
        raise SystemExit("Refusing to replace an unrelated application at " + str(destination))
for directory in (support, logs, agent.parent):
    directory.mkdir(parents=True, exist_ok=True)
backup = support / "backups" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
backup.mkdir(parents=True, mode=0o700)
for name in ("config.json", "pairings.json", "desktop-layout.json", "window-identity-salt"):
    if (support / name).exists():
        shutil.copy2(support / name, backup / name)
if previous_agent:
    (backup / agent.name).write_bytes(previous_agent)
if destination.exists():
    shutil.copytree(destination, backup / destination.name)
if not (support / "config.json").exists():
    shutil.copyfile(ROOT / "Profiles" / (args.profile + ".json"), support / "config.json")
    (support / "config.json").chmod(0o600)
with tempfile.TemporaryDirectory(prefix=".wch-install-", dir=app_dir) as scratch:
    staged = Path(scratch) / destination.name
    shutil.copytree(source, staged)
    subprocess.run(["codesign", "--verify", "--strict", str(staged)], check=True)
    subprocess.run(["launchctl", "bootout", domain + "/" + label], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    old = Path(scratch) / "Previous.app"
    try:
        if destination.exists():
            destination.rename(old)
        staged.rename(destination)
        config = plistlib.loads((ROOT / "Resources" / (label + ".plist.template")).read_bytes())
        config["ProgramArguments"] = [str(destination / "Contents/MacOS/MacXeneonEdgeTouchDriver")]
        config["StandardOutPath"] = str(logs / "stdout.log")
        config["StandardErrorPath"] = str(logs / "stderr.log")
        temporary_agent = agent.with_suffix(".plist.tmp")
        temporary_agent.write_bytes(plistlib.dumps(config))
        temporary_agent.replace(agent)
        if not args.no_start:
            subprocess.run(["launchctl", "enable", domain + "/" + label], check=True)
            bootstrap_agent(domain, agent)
    except Exception:
        subprocess.run(["launchctl", "bootout", domain + "/" + label], capture_output=True)
        if destination.exists():
            shutil.rmtree(destination)
        if old.exists():
            old.rename(destination)
        if previous_agent:
            agent.write_bytes(previous_agent)
            try:
                bootstrap_agent(domain, agent)
            except subprocess.CalledProcessError:
                print("Previous files restored; restart its LaunchAgent after launchd settles. Backup:", backup, file=sys.stderr)
        elif agent.exists():
            agent.unlink()
        raise
print("Installed:", destination)
print("Settings preserved; recovery copy:", backup)
print("Grant Accessibility and Input Monitoring to this exact app in System Settings.")
print("Ad hoc builds can require these permissions to be refreshed after an update.")
if args.no_start:
    print("Start after permissions are ready: launchctl bootstrap", domain, str(agent))
