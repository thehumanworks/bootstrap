import json
import re
import tomllib
import unittest
from pathlib import Path


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

    def test_package_managers_and_json_tools_are_pinned(self) -> None:
        tools = self.parsed["tools"]
        for name in PACKAGE_MANAGER_TOOLS + JSON_TOOLS:
            self.assertIn(name, tools)
            self.assertTrue(str(tools[name]).strip())

    def test_global_claude_md_is_symlinked_from_the_checkout(self) -> None:
        self.assertRegex(
            self.config,
            re.compile(
                r'^"~/.claude/CLAUDE\.md" = '
                r'\{ source = "\.claude/CLAUDE\.md", mode = "symlink" \}$',
                re.MULTILINE,
            ),
        )
        claude_md = (REPOSITORY / ".claude" / "CLAUDE.md").read_text(encoding="utf-8")
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
                r'\{ source = "\.claude\.json", mode = "copy" \}$',
                re.MULTILINE,
            ),
        )
        with (REPOSITORY / ".claude.json").open(encoding="utf-8") as state_file:
            self.assertEqual(json.load(state_file), {"hasCompletedOnboarding": True})


if __name__ == "__main__":
    unittest.main()
