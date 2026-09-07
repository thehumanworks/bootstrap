"""Exercise tmux plugin bootstrap using isolated directories and a fake Git CLI."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

INSTALLER = Path(__file__).resolve().parents[1] / "scripts" / "install-tmux-plugins.sh"


class PluginBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mise-plugin-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plugins = self.root / "plugins"
        self.log = self.root / "git.log"
        config = self.root / "tmux.conf"
        config.write_text(
            "set -g @plugin 'tmux-plugins/tpm'\nset -g @plugin 'example/plugin'\n"
        )
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        git = bin_dir / "git"
        git.write_text(
            "#!/bin/sh\n"
            'printf "%s\\n" "$*" >> "$TEST_GIT_LOG"\n'
            'if [ "${TEST_GIT_FAIL:-0}" = 1 ]; then exit 1; fi\n'
            'if [ "$1" = clone ]; then\n'
            "  for target do :; done\n"
            '  mkdir -p "$target/.git"\n'
            "fi\n"
        )
        git.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:/usr/bin:/bin",
            "HOME": str(self.root),
            "TMUX_CONF": str(config),
            "TMUX_PLUGIN_MANAGER_PATH": str(self.plugins),
            "TEST_GIT_LOG": str(self.log),
            "TEST_GIT_FAIL": "0",
        }

    def run_installer(self, *args):
        return subprocess.run(
            ["/bin/sh", str(INSTALLER), *args],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def existing_plugins(self):
        for name in ("tpm", "plugin"):
            (self.plugins / name / ".git").mkdir(parents=True)

    def test_bootstrap_installs_once_without_updating_on_repeat(self):
        self.assertEqual(self.run_installer().returncode, 0)
        self.assertEqual(len(self.calls()), 2)
        self.assertTrue(all(call.startswith("clone ") for call in self.calls()))
        self.assertEqual(self.run_installer().returncode, 0)
        self.assertEqual(len(self.calls()), 2)

    def test_explicit_update_pulls_existing_plugins(self):
        self.existing_plugins()
        self.assertEqual(self.run_installer("--update").returncode, 0)
        self.assertEqual(len(self.calls()), 2)
        self.assertTrue(all(" pull --ff-only " in call for call in self.calls()))

    def test_failed_install_is_not_reported_as_success(self):
        self.env["TEST_GIT_FAIL"] = "1"
        self.assertNotEqual(self.run_installer().returncode, 0)

    def test_failed_update_is_not_reported_as_success(self):
        self.existing_plugins()
        self.env["TEST_GIT_FAIL"] = "1"
        self.assertNotEqual(self.run_installer("--update").returncode, 0)

    def test_unknown_arguments_do_not_touch_plugins(self):
        self.assertEqual(self.run_installer("--unknown").returncode, 2)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
