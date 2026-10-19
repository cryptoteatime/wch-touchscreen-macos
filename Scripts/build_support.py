"""Build with Apple's installed Swift compiler; no third-party Python packages."""
import os
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parent.parent

def compiler_flags():
    sdk = os.environ.get("WCH_SDK_PATH") or subprocess.check_output(
        ["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    arch = platform.machine()
    if arch not in ("arm64", "x86_64"):
        raise SystemExit("Build this driver on an Apple Silicon or Intel Mac.")
    return ["xcrun", "swiftc", "-sdk", sdk, "-target", f"{arch}-apple-macosx13.0",
            "-O", "-whole-module-optimization", "-parse-as-library",
            "-module-name", "MacXeneonEdgeTouchDriverCore"]

def core_sources():
    return sorted((ROOT / "Sources/MacXeneonEdgeTouchDriverCore").rglob("*.swift"))

def compile_binary(main, output, extra=(), defines=()):
    output.parent.mkdir(parents=True, exist_ok=True)
    command = compiler_flags()
    for define in defines:
        command += ["-D", define]
    subprocess.run(command + [str(p) for p in core_sources()] +
                   [str(p) for p in extra] + [str(main), "-o", str(output)], check=True)
