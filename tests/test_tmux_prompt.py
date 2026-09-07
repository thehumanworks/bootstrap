"""Keep the sandbox cwd fallback compatible with existing Bash prompt hooks."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parents[1] / "scripts" / "tmux-prompt.bash"


class TmuxPromptTests(unittest.TestCase):
    def run_shell(self, setup, check, *, interactive=True):
        with tempfile.TemporaryDirectory(prefix="tmux-prompt-") as tmp:
            root = Path(tmp)
            fake = root / "tmux"
            fake.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$CWD_LOG"\n')
            fake.chmod(0o755)
            result = subprocess.run(
                [
                    "/bin/bash",
                    "--noprofile",
                    "--norc",
                    "-ic" if interactive else "-c",
                    f'{setup}\nsource "$HOOK"\nsource "$HOOK"\n{check}',
                ],
                cwd=root,
                env={
                    "HOME": tmp,
                    "PATH": f"{tmp}:/usr/bin:/bin",
                    "HOOK": str(HOOK),
                    "TMUX_PANE": "%1",
                    "CWD_LOG": str(root / "cwd.log"),
                },
                capture_output=True,
                text=True,
                timeout=5,
                check=True,
            )
            log = root / "cwd.log"
            return (
                result.stdout,
                log.read_text().splitlines() if log.exists() else [],
                os.path.realpath(tmp),
            )

    def test_scalar_hook_preserves_previous_status_and_registers_once(self):
        out, calls, cwd = self.run_shell(
            'PROMPT_COMMAND=\'printf "previous=%s\\n" "$?"\'',
            'false; eval "$PROMPT_COMMAND"',
        )
        self.assertEqual(out, "previous=1\n")
        self.assertEqual(calls, ["set-option", "-p", "-t", "%1", "@shell_cwd", cwd])

    def test_array_hook_preserves_existing_entries(self):
        out, calls, _ = self.run_shell(
            'PROMPT_COMMAND=(\'printf "previous=%s\\n" "$?"\' :)',
            "[[ ${#PROMPT_COMMAND[@]} == 3 ]] || exit 1; "
            'false; eval "${PROMPT_COMMAND[0]}"; eval "${PROMPT_COMMAND[1]}"',
        )
        self.assertEqual(out, "previous=1\n")
        self.assertEqual(calls.count("set-option"), 1)

    def test_noninteractive_shell_does_not_install_a_prompt_hook(self):
        out, calls, _ = self.run_shell(
            "unset PROMPT_COMMAND",
            'printf "%s" "${PROMPT_COMMAND-unset}"',
            interactive=False,
        )
        self.assertEqual(out, "unset")
        self.assertEqual(calls, [])
