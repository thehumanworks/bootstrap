# 0001. Wrap secret-bearing tools with mise command wrappers

- Status: accepted
- Date: 2026-09-03

## Context

`claude`, `gh`, `git`, and `tny` must run through `fnox run` so 1Password
secrets are injected. That was configured as `[shell_alias]`:

```toml
[shell_alias]
claude = "fnox run -- claude"
```

The alias never applied in Modal sandboxes.

mise documents `[shell_alias]` as a directory-scoped shell alias that exists
only after `mise activate` runs `hook-env` in an interactive shell. It is not
available to tasks, scripts, or any process that is not that shell
([Shell Aliases](https://mise.jdx.dev/shell-aliases.html),
[FAQs](https://mise.jdx.dev/faq.html)).

Modal `Sandbox.exec` takes a program and argv. It does not start a login
shell ([Running commands in Sandboxes](https://modal.com/docs/guide/sandbox-spawn)).
`sb exec` splits the command with `shlex.split` and forwards that argv
(sandboxes ADR 0006). The image `PATH` already contains
`~/.local/share/mise/shims`, so `claude` is the mise shim.

`[bootstrap.mise_shell_activate] bash = true` writes `mise activate --shims`
to `~/.bash_profile` and full `mise activate` to `~/.bashrc`
([Shell Activation](https://mise.jdx.dev/bootstrap/shell.html)). Tailscale SSH
is a login shell that reads `.bash_profile`. `--shims` does not install
aliases ([Shims vs PATH](https://mise.jdx.dev/dev-tools/shims.html#shims-vs-path)).

## Decision

Replace `[shell_alias]` with mise `[wrappers]`:

```toml
[wrappers.claude]
command = "fnox"
args = ["run", "--if-missing", "warn", "--non-interactive", "--", "claude"]
```

The same shape is used for `gh`, `git`, and `tny`.

`[wrappers]` is a PATH-level intercept. Invoking the ordinary shim
(`~/.local/share/mise/shims/claude`) looks up the wrapper, rewrites argv to
`fnox run … -- claude …`, and strips mise dispatch directories from `PATH`
so the inner `claude` is the real binary
([Command wrappers](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers),
mise v2026.8.16+). That path is what `Sandbox.exec("claude")` already uses.

`--if-missing warn` lets the wrapped command still run when 1Password is not
attached. Image build runs `mise exec -- gh auth setup-git` with only the
GitHub secret; a hard error on unresolved `op://` refs would fail that step.
`--non-interactive` blocks browser auth prompts inside sandboxes.

The Modal image pins mise 2026.9.0, which includes wrappers. Local mise
2026.8.8 warns `unknown field: wrappers` and ignores the section.

## Alternatives considered

- Keep `[shell_alias]` and start Claude via `bash -ic`. Rejected: every
  `sb exec` / `Sandbox.exec` caller would have to remember a shell, and
  login SSH still would not see aliases.
- Put hand-written scripts on `PATH` via `env._.path`. Rejected: mise already
  provides wrappers that reshim, strip dispatch dirs, and work with
  `mise exec`.
- Wrap only `claude`. Rejected: `gh`, `git`, and `tny` have the same secret
  contract.

## Consequences

- `Sandbox.exec("claude")`, `sb exec … claude`, SSH, and `mise exec -- claude`
  all go through `fnox run`.
- Image builds that `mise exec -- gh` after bootstrap now invoke fnox. They
  must tolerate missing 1Password secrets (`--if-missing warn`).
- `mise reshim` refreshes `$MISE_DATA_DIR/command-wrappers/bin`. Full
  `mise activate` also prepends that directory; the regular tool shim is
  enough for Modal exec.
- Do not reintroduce `[shell_alias]` for these tools.
