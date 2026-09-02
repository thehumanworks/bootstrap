import re
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]


class BootstrapContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = (REPOSITORY / "mise.toml").read_text(encoding="utf-8")

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


if __name__ == "__main__":
    unittest.main()
