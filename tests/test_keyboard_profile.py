"""Keep physical keyboard ownership out of ordinary headless bootstrap."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parents[1]


class KeyboardProfileTests(unittest.TestCase):
    def run_setup(self, *, failure="", systemd=True):
        config = tomllib.loads((ROOT / "mise.toml").read_text())
        with tempfile.TemporaryDirectory(prefix="keyboard-setup-") as tmp:
            root = Path(tmp)
            for name, body in {
                "systemctl": "exit 0\n" if systemd else "exit 1\n",
                "mise": (
                    'printf "%s\\n" "$*" >> "$SETUP_LOG"\n'
                    'case "$*" in *"${SETUP_FAILURE:-never-matches}"*) exit 7;; esac\n'
                ),
            }.items():
                path = root / name
                path.write_text("#!/bin/sh\n" + body)
                path.chmod(0o755)
            result = subprocess.run(
                ["/bin/sh", "-c", config["tasks"]["keyboard:setup"]["run"]],
                env={
                    **os.environ,
                    "PATH": f"{tmp}:/usr/bin:/bin",
                    "SETUP_LOG": str(root / "calls"),
                    "SETUP_FAILURE": failure,
                },
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            log = root / "calls"
            return result, log.read_text().splitlines() if log.exists() else []

    def test_single_command_runs_all_three_phases_in_order(self):
        result, calls = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            calls,
            [
                "-E keyboard-linux bootstrap packages apply --yes apt:keyd",
                "-E keyboard-linux bootstrap files apply --yes",
                "-E keyboard-linux bootstrap services apply --yes",
            ],
        )

    def test_setup_stops_when_a_phase_fails(self):
        for phase, count in (("packages", 1), ("files", 2), ("services", 3)):
            with self.subTest(phase=phase):
                result, calls = self.run_setup(failure=phase)
                self.assertEqual(result.returncode, 7)
                self.assertEqual(len(calls), count)

    def test_headless_host_is_rejected_before_any_changes(self):
        result, calls = self.run_setup(systemd=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires a Linux keyboard host running systemd", result.stderr)
        self.assertEqual(calls, [])

    def test_keyboard_remapping_requires_explicit_profile_selection(self):
        default = tomllib.loads((ROOT / "mise.toml").read_text())
        settings = tomllib.loads((ROOT / ".miserc.toml").read_text())
        self.assertNotIn("keyboard-linux", settings.get("env", []))
        self.assertNotIn("apt:keyd", default["bootstrap"]["packages"])
        self.assertNotIn("keyd", default["bootstrap"].get("services", {}))

    def test_keyboard_profile_uses_native_package_file_and_service_resources(self):
        config = tomllib.loads((ROOT / "mise.keyboard-linux.toml").read_text())
        resources = config["bootstrap"]
        self.assertIn("apt:keyd", resources["packages"])
        file = resources["files"]["/etc/keyd/bootstrap-tmux.conf"]
        self.assertTrue((ROOT / file["source"]).is_file())
        self.assertEqual(file["notify"], ["keyd"])
        self.assertEqual(resources["services"]["keyd"]["state"], "running")
        self.assertEqual(
            resources["services"]["keyd"]["on_change"], "reload_or_restart"
        )
