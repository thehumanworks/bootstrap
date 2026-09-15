import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parents[1]


class WorkProfileTests(unittest.TestCase):
    def test_global_overlays_and_work_clients_are_installed(self):
        common = tomllib.loads((ROOT / "mise.toml").read_text())
        work = tomllib.loads((ROOT / "mise.work.toml").read_text())
        for name in ("dev", "work"):
            self.assertEqual(
                f"mise.{name}.toml",
                common["dotfiles"][f"~/.config/mise/config.{name}.toml"]["source"],
            )
        self.assertEqual("work", work["env"]["FNOX_PROFILE"])
        self.assertEqual("true", work["env"]["FNOX_NO_DEFAULTS"])
        self.assertEqual("leadforensics.ghe.com", work["env"]["GH_HOST"])
        for tool in ("acli", "npm:mcp-remote"):
            self.assertIn(tool, work["tools"])
        for entry in work["dotfiles"].values():
            self.assertTrue((ROOT / entry["source"]).exists())
        client = json.loads((ROOT / "dotfiles/claude/.claude.work.json").read_text())
        self.assertIn("work-atlassian", client["mcpServers"]["atlassian"]["args"])
        self.assertIn(
            "codex mcp add atlassian -- fnox",
            work["bootstrap"]["hooks"]["post-tools"]["run"],
        )

    def test_native_fnox_work_selection_and_missing_auth(self):
        fnox = shutil.which("fnox")
        self.assertIsNotNone(fnox, "fnox is required for native profile verification")
        work = tomllib.loads((ROOT / "mise.work.toml").read_text())
        wrapper = work["wrappers"]["gh"]
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            (base / "config").mkdir()
            (base / "bin").mkdir()
            (base / "project").mkdir()
            (base / "config/config.toml").write_text(
                (ROOT / "fnox.work.toml").read_text()
            )
            (base / "project/fnox.toml").write_text(
                '[secrets]\nGH_TOKEN = { default = "personal-project" }\nPERSONAL_ONLY = { default = "must-not-load" }\n'
            )
            (base / "project/fnox.work.toml").write_text(
                (ROOT / "fnox.work.toml").read_text()
            )
            op = base / "bin/op"
            op.write_text(
                '#!/bin/sh\ncase "$*" in *github/leadforensics/token*) [ "$FAIL_WORK_AUTH" != 1 ] || exit 1; printf work-sentinel ;; *) exit 1 ;; esac\n'
            )
            op.chmod(0o755)
            gh = base / "bin/gh"
            gh.write_text(f"""#!{sys.executable}
import os,json,sys
if sys.argv[1:] == ['auth','git-credential','get']:
 print('username=test\\npassword='+os.environ['GH_TOKEN']); sys.exit(0)
print(json.dumps({{'work':os.environ.get('GH_TOKEN')=='work-sentinel','personal':'PERSONAL_ONLY' in os.environ}}))
""")
            gh.chmod(0o755)
            env = {
                k: v
                for k, v in os.environ.items()
                if not k.startswith(("FNOX_", "OP_"))
            }
            env.update(
                PATH=str(base / "bin") + os.pathsep + env["PATH"],
                FNOX_CONFIG_DIR=str(base / "config"),
                GH_TOKEN="personal-inherited",
                OP_SERVICE_ACCOUNT_TOKEN="unit-sentinel",
                **work["env"],
            )
            for cwd in (base, base / "project"):
                run = subprocess.run(
                    [fnox, *wrapper["args"]],
                    cwd=cwd,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(0, run.returncode, run.stderr)
                self.assertEqual(
                    {"work": True, "personal": False}, json.loads(run.stdout)
                )
                failed = subprocess.run(
                    [fnox, *wrapper["args"]],
                    cwd=cwd,
                    env={**env, "FAIL_WORK_AUTH": "1"},
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(0, failed.returncode)
                self.assertEqual(
                    "", failed.stdout, "gh must not run with inherited personal auth"
                )
                for fail in ("0", "1"):
                    credentials = subprocess.run(
                        ["/usr/bin/git", "credential", "fill"],
                        input="protocol=https\nhost=leadforensics.ghe.com\n\n",
                        cwd=cwd,
                        env={
                            **env,
                            "FAIL_WORK_AUTH": fail,
                            "GIT_CONFIG_GLOBAL": str(ROOT / ".gitconfig.work"),
                            "GIT_CONFIG_NOSYSTEM": "1",
                            "GIT_TERMINAL_PROMPT": "0",
                        },
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    if fail == "0":
                        self.assertEqual(0, credentials.returncode, credentials.stderr)
                        self.assertIn("password=work-sentinel", credentials.stdout)
                    else:
                        self.assertNotEqual(0, credentials.returncode)
                        self.assertNotIn("password=", credentials.stdout)

    def test_work_git_helper_resolves_strict_auth_without_mise_dispatch(self):
        helper = subprocess.run(
            [
                "git",
                "config",
                "--file",
                str(ROOT / ".gitconfig.work"),
                "--get-all",
                "credential.https://leadforensics.ghe.com.helper",
            ],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        self.assertIn("--profile work-github", helper)
        self.assertIn("--no-defaults", helper)
        self.assertIn("--if-missing error", helper)
        self.assertIn("-- gh auth git-credential", helper)

    def test_acli_auth_uses_stdin_and_cleans_up_on_success_and_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fake = base / "acli"
            fake.write_text(f"""#!{sys.executable}
import os,sys,json,pathlib
config = pathlib.Path(os.environ['ACLI_CONFIG_DIR'])
assert config.exists()
assert 'unit-token' not in ' '.join(sys.argv)
with open(os.environ['RECORD'], 'a') as f: f.write(json.dumps({{'config':str(config),'args':sys.argv[1:]}})+'\\n')
if sys.argv[2:4] == ['auth','login']:
 assert sys.stdin.read() == 'unit-token'
 sys.exit(int(os.environ.get('LOGIN_FAIL','0')))
print('read-ok')
""")
            fake.chmod(0o755)
            for fail in ("0", "1"):
                record = base / ("record" + fail)
                env = {
                    **os.environ,
                    "PATH": str(base) + os.pathsep + os.environ["PATH"],
                    "RECORD": str(record),
                    "LOGIN_FAIL": fail,
                    "ATLASSIAN_API_TOKEN": "unit-token",
                    "ATLASSIAN_EMAIL": "test@example.com",
                    "ATLASSIAN_BASE_URL": "https://example.atlassian.net/",
                }
                run = subprocess.run(
                    [
                        sys.executable,
                        str(ROOT / "scripts/acli-work"),
                        "jira",
                        "auth",
                        "status",
                    ],
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(int(fail), run.returncode)
                calls = [json.loads(line) for line in record.read_text().splitlines()]
                self.assertEqual(2 if fail == "0" else 1, len(calls))
                self.assertFalse(Path(calls[0]["config"]).exists())
                self.assertNotIn("unit-token", run.stdout + run.stderr)

    def test_mcp_auth_is_only_in_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "mcp-remote"
            fake.write_text(f"""#!{sys.executable}
import os,sys,base64
assert os.environ['ATLASSIAN_MCP_AUTH'] == 'Basic ' + base64.b64encode(b'test@example.com:unit-token').decode()
assert 'Authorization:${{ATLASSIAN_MCP_AUTH}}' in sys.argv
assert 'https://mcp.atlassian.com/v2/mcp' in sys.argv
assert 'unit-token' not in ' '.join(sys.argv)
print('mcp-ok')
""")
            fake.chmod(0o755)
            env = {
                **os.environ,
                "PATH": tmp + os.pathsep + os.environ["PATH"],
                "ATLASSIAN_API_TOKEN": "unit-token",
                "ATLASSIAN_EMAIL": "test@example.com",
            }
            run = subprocess.run(
                [sys.executable, str(ROOT / "scripts/atlassian-mcp")],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(0, run.returncode, run.stderr)
            self.assertEqual("mcp-ok\n", run.stdout)
