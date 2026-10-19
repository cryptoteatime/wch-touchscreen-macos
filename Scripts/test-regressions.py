#!/usr/bin/env python3
"""Targeted checks for machines where the installed SwiftPM runner is broken."""
import subprocess
from build_support import ROOT, compile_binary

for name in ("VerifyRemember", "VerifyGestures", "VerifyDesktopLayout", "VerifyRestoration", "VerifyBrightness", "VerifyMonitorProfiles"):
    source = ROOT / "Scripts/Regression" / (name + ".swift")
    output = ROOT / "artifacts/regressions" / name
    extra = [ROOT / "Tests/MacXeneonEdgeTouchDriverCoreTests/DesktopRestorationScenarios.swift"] if name == "VerifyRestoration" else []
    if name == "VerifyBrightness":
        extra = [ROOT / "Tests/MacXeneonEdgeTouchDriverCoreTests/MonitorBrightnessScenarios.swift"]
    if name == "VerifyMonitorProfiles":
        extra = [ROOT / "Tests/MacXeneonEdgeTouchDriverCoreTests/MonitorProfileScenarios.swift"]
    compile_binary(source, output, extra=extra, defines=["WCH_STANDALONE"])
    subprocess.run([str(output)], check=True)
