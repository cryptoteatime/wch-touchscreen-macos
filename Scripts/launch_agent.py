"""Bounded launchd shutdown shared by the app installer and uninstaller."""
import subprocess
import time


def stop_agent(domain, label, *, timeout=10, interval=0.2):
    """Return only after launchd confirms absence; unknown state aborts changes."""
    service = domain + "/" + label
    # A missing GUI domain must not be mistaken for an absent service.
    subprocess.run(["launchctl", "print", domain], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

    def is_loaded():
        result = subprocess.run(["launchctl", "print", service],
                                capture_output=True, text=True)
        if result.returncode == 0:
            return True
        if result.returncode == 113:  # launchd service not found
            return False
        raise RuntimeError(f"Cannot determine WCH LaunchAgent state (status {result.returncode}). "
                           "Cannot safely replace or remove installed files.")

    if not is_loaded():
        return
    # A service can disappear between print and bootout. Its observed absence,
    # rather than bootout's return code, authorizes replacing installed files.
    subprocess.run(["launchctl", "bootout", service], capture_output=True, text=True)
    deadline = time.monotonic() + timeout
    while is_loaded():
        if time.monotonic() >= deadline:
            raise TimeoutError("WCH LaunchAgent did not stop; installed files were left in place.")
        time.sleep(interval)
