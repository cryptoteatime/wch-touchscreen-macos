#!/usr/bin/env python3
"""Exercise launchd races without touching the user's installed driver."""
import subprocess
import unittest
from unittest.mock import patch
from launch_agent import stop_agent


class LaunchAgentTests(unittest.TestCase):
    def run_scenario(self, statuses):
        results = [subprocess.CompletedProcess([], code, "", "") for code in statuses]
        return patch("launch_agent.subprocess.run", side_effect=results)

    def test_already_absent_needs_no_bootout(self):
        with self.run_scenario([0, 113]) as run:
            stop_agent("gui/123", "example.wch")
        self.assertFalse(any(call.args[0][1] == "bootout" for call in run.call_args_list))

    def test_delayed_removal_waits_before_returning(self):
        with self.run_scenario([0, 0, 0, 0, 0, 113]), patch("launch_agent.time.sleep") as sleep:
            stop_agent("gui/123", "example.wch")
        self.assertEqual(sleep.call_count, 2)

    def test_bootout_error_is_safe_only_if_absence_is_confirmed(self):
        with self.run_scenario([0, 0, 5, 113]):
            stop_agent("gui/123", "example.wch")

    def test_unknown_query_state_aborts(self):
        for statuses in ([0, 5], [0, 0, 0, 5]):
            with self.subTest(statuses=statuses), self.run_scenario(statuses):
                with self.assertRaises(RuntimeError):
                    stop_agent("gui/123", "example.wch")

    def test_loaded_service_cannot_timeout_successfully(self):
        with self.run_scenario([0, 0, 0, 0]), self.assertRaises(TimeoutError):
            stop_agent("gui/123", "example.wch", timeout=0)

    def test_inaccessible_gui_domain_aborts_before_bootout(self):
        error = subprocess.CalledProcessError(113, ["launchctl", "print", "gui/123"])
        with patch("launch_agent.subprocess.run", side_effect=error) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                stop_agent("gui/123", "example.wch")
        self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
