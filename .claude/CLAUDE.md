# Sandbox

This checkout is a mise-managed agent sandbox. Tools, secrets, and Claude
settings come from the bootstrap repository. Do not rediscover that from
scratch each session.

## Layout

- Global mise config is `~/.config/mise/config.toml`, a symlink into
  `~/.local/share/mise/bootstrap-repo/mise.toml`.
- `~/.claude/settings.json` and this file are also symlinks into that
  checkout. Editing them is a git change on the bootstrap repo.
- `/workdir` starts empty and is not a git repository until you clone one.

## Secrets

`fnox` injects secrets at the shell. `claude`, `gh`, `git`, and `tny`
already run through `fnox run`. Never print, log, or persist secret
values, including `GH_TOKEN`, `OPENROUTER_API_KEY`, and `AIPROXY_API_KEY`.

## Constraints

- Claude Code is in auto mode and skips the dangerous-mode prompt.
- Sandboxes that use this bootstrap are typically 1 vCPU. Check `nproc`
  before you parallelize. Extra threads will not make builds faster.
- Prefer tools that are already installed: `jq`, `rg`, `fd`, `ps`/`pkill`,
  `ss`, `lsof`, `zip`/`unzip`, `shellcheck`, `sqlite3`, `rsync`, `pnpm`,
  `yarn`, and `corepack`. Use `corepack` when a repo pins `packageManager`.
