import json
import re
import unittest
from pathlib import Path

import tomllib

REPOSITORY = Path(__file__).resolve().parents[1]

HOST_APT_PACKAGES = (
    "procps",
    "unzip",
    "zip",
    "zstd",
    "file",
    "tree",
    "bsdextrautils",
    "gettext-base",
    "sqlite3",
    "rsync",
    "lsof",
    "iproute2",
    "dnsutils",
    "iputils-ping",
    "ncurses-term",
)

PACKAGE_MANAGER_TOOLS = ("pnpm", "yarn", "npm:corepack")
JSON_TOOLS = ("jq", "shellcheck")


class BootstrapContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = (REPOSITORY / "mise.toml").read_text(encoding="utf-8")
        cls.parsed = tomllib.loads(cls.config)

    def test_global_mise_config_is_backed_by_the_canonical_checkout(self) -> None:
        self.assertRegex(
            self.config,
            re.compile(
                r'^"~/.config/mise/config\.toml" = '
                r'\{ source = "mise\.toml", mode = "symlink" \}$',
                re.MULTILINE,
            ),
        )
        self.assertTrue((REPOSITORY / "mise.toml").is_file())

    def test_ssh_entrypoint_tools_are_declared_in_global_config(self) -> None:
        self.assertRegex(
            self.config,
            re.compile(r'^"npm:@openai/codex"\s*=', re.MULTILINE),
        )
        self.assertRegex(self.config, re.compile(r"^neovim\s*=", re.MULTILINE))

    def test_host_utilities_are_declared_as_apt_packages(self) -> None:
        packages = self.parsed["bootstrap"]["packages"]
        for name in HOST_APT_PACKAGES:
            self.assertEqual(packages[f"apt:{name}"], "latest")

    def test_tmux_bindings_have_their_installed_helpers(self) -> None:
        dotfiles = self.parsed["dotfiles"]
        targets = {
            "~/.config/tmux/tmux.conf": "dotfiles/tmux/tmux.conf",
            "~/.local/bin/tw": "scripts/tmux-workspace",
            "~/.local/bin/agent-tmux-state": "scripts/agent-tmux-state",
            "~/.local/bin/claude-tmux-state": "scripts/agent-tmux-state",
            "~/.local/lib/tmux/install-tmux-plugins.sh": "scripts/install-tmux-plugins.sh",
            "~/.local/lib/tmux/reload-tmux-config.sh": "scripts/reload-tmux-config.sh",
            "~/.local/lib/tmux/tmux-prompt.bash": "scripts/tmux-prompt.bash",
        }
        for target, source in targets.items():
            self.assertEqual(dotfiles[target], {"source": source, "mode": "symlink"})
            self.assertTrue((REPOSITORY / source).is_file())
        for name in ("tmux", "python", "fzf"):
            self.assertIn(name, self.parsed["tools"])
        for target in ("~/.bashrc/tmux-cwd", "~/.bash_profile/tmux-cwd"):
            self.assertIn("tmux-prompt.bash", dotfiles[target]["block"])

    def test_tmux_hooks_do_not_depend_on_the_workstation_checkout(self) -> None:
        for script in (
            self.parsed["bootstrap"]["hooks"]["post-dotfiles"]["run"],
            self.parsed["tasks"]["update-tmux-plugins"]["run"],
        ):
            self.assertNotIn("$HOME/.config/mise/scripts", script)
            self.assertNotIn("{{", script)
            self.assertIn("set -eu", script)
            for name in ("install-tmux-plugins.sh", "reload-tmux-config.sh"):
                self.assertIn("$HOME/.local/lib/tmux/" + name, script)
                self.assertTrue((REPOSITORY / "scripts" / name).is_file())

    def test_all_mise_tools_select_latest(self) -> None:
        configs = [
            self.parsed,
            tomllib.loads((REPOSITORY / "mise.work.toml").read_text(encoding="utf-8")),
            tomllib.loads(
                self.parsed["dotfiles"]["~/.config/mise/conf.d/secret-tools.toml"][
                    "content"
                ]
            ),
        ]
        for config in configs:
            for name, tool in config["tools"].items():
                with self.subTest(name=name):
                    version = tool if isinstance(tool, str) else tool["version"]
                    self.assertEqual("latest", version)
        for name in PACKAGE_MANAGER_TOOLS + JSON_TOOLS:
            self.assertIn(name, self.parsed["tools"])

    def test_global_claude_md_is_symlinked_from_the_checkout(self) -> None:
        self.assertRegex(
            self.config,
            re.compile(
                r'^"~/.claude/CLAUDE\.md" = '
                r'\{ source = "dotfiles/claude/CLAUDE\.md", mode = "symlink" \}$',
                re.MULTILINE,
            ),
        )
        claude_md = (REPOSITORY / "dotfiles" / "claude" / "CLAUDE.md").read_text(
            encoding="utf-8"
        )
        for needle in ("mise", "fnox", "1 vCPU", "packageManager"):
            self.assertIn(needle, claude_md)

    def test_secret_tools_use_mise_wrappers_not_shell_aliases(self) -> None:
        self.assertNotIn("shell_alias", self.parsed)
        wrappers = self.parsed["wrappers"]
        for name in ("claude", "gh", "git", "tny"):
            wrapper = wrappers[name]
            self.assertEqual(wrapper["command"], "fnox")
            self.assertEqual(
                wrapper["args"],
                [
                    "run",
                    "--if-missing",
                    "warn",
                    "--non-interactive",
                    "--",
                    name,
                ],
            )

    def test_claude_oauth_onboarding_state_is_minimal_and_copied(self) -> None:
        self.assertRegex(
            self.config,
            re.compile(
                r'^"~/.claude\.json" = '
                r'\{ source = "dotfiles/claude/\.claude\.json", mode = "copy" \}$',
                re.MULTILINE,
            ),
        )
        with (REPOSITORY / "dotfiles" / "claude" / ".claude.json").open(
            encoding="utf-8"
        ) as state_file:
            self.assertEqual(json.load(state_file), {"hasCompletedOnboarding": True})


if __name__ == "__main__":
    unittest.main()
