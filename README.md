# bootstrap

Personal development environment for disposable Linux sandboxes, managed by
[mise](https://mise.jdx.dev/bootstrap.html).

> [!WARNING]
> This configuration installs agent CLIs with unrestricted execution settings
> and can replace selected files in `$HOME`. Use it only in a trusted,
> disposable sandbox.

## Requirements

- Linux with a writable `$HOME`
- `bash`, `git`, CA certificates, and `curl` or `wget`
- mise 2026.8.15 or newer
- Authentication for the initial private GitHub clone
- `OP_SERVICE_ACCOUNT_TOKEN` injected at runtime with access only to the
  referenced 1Password items

The initial clone uses an HTTPS PAT supplied as `GH_TOKEN`. Credentials stored
behind fnox cannot help with that clone because fnox, `op`, and `gh` are
installed later.

## Fresh sandbox: clone and bootstrap together

With mise installed and a fine-grained PAT injected into `GH_TOKEN`, this
single invocation supplies a host-scoped, in-memory credential helper to the
`git clone` performed by mise and then runs bootstrap:

```bash
: "${GH_TOKEN:?inject a GitHub PAT into GH_TOKEN}"
GIT_CONFIG_COUNT=3 \
  GIT_CONFIG_KEY_0=credential.https://github.com.helper \
  GIT_CONFIG_VALUE_0= \
  GIT_CONFIG_KEY_1=credential.https://github.com.helper \
  GIT_CONFIG_VALUE_1='!f() { if [ "$1" = get ]; then printf "%s\n" "username=x-access-token" "password=$GH_TOKEN"; fi; }; f' \
  GIT_CONFIG_KEY_2=credential.interactive \
  GIT_CONFIG_VALUE_2=never \
mise -E dev bootstrap \
  --from https://github.com/thehumanworks/bootstrap.git \
  --from-dir "$HOME/.local/share/thehumanworks-bootstrap" \
  --yes \
  --force-dotfiles

unset GH_TOKEN
exec bash -l
```

`--from` performs the clone and then runs bootstrap from that checkout. Keep
`--from-dir` at a durable path: the global mise configuration links back to
the checkout so the installed tools and shell aliases work in every project.
The PAT is neither placed in the URL nor written to the checkout's
`.git/config`; the helper value contains only a reference to `GH_TOKEN`.

On a minimal sandbox, install mise first, then run the same block above:

```bash
curl -fsSL https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"
```

The force flag is intentional for disposable homes. Omit it in an existing
home and inspect the dry run first.

## Private clone authentication

Prefer a fine-grained, read-only PAT injected as `GH_TOKEN` by the sandbox's
secret manager. The quick-start's environment-only helper resets any existing
GitHub helper for that invocation and answers only Git's `get` operation. You
can alternatively use:

- the sandbox provider's GitHub checkout integration;
- a short-lived GitHub App token exposed through an equivalent
  environment-only Git credential helper; or
- a preconfigured Git Credential Manager.

Do not put a token in the clone URL. It can remain in process arguments, shell
history, and the checkout's `.git/config`. `GH_TOKEN` authenticates `gh`, but
does not by itself authenticate a plain `git clone`.

## Profiles

| Profile | Git host | Identity | fnox source |
| --- | --- | --- | --- |
| `dev` | `github.com` | Personal | `fnox.toml` |
| `work` | `leadforensics.ghe.com` | Work | `fnox.work.toml` |

Select work by replacing `-E dev` with `-E work`. The selected fnox file is
copied to the home directory and each credential is injected only into the
command profile that needs it. Codex and Claude inherit the GitHub profile so
their nested Git operations still work, but neither receives the Tailscale
credential or the 1Password service-account token.

The XDG Git config contains a host-scoped, fnox-backed credential helper. This
lets package managers and other child processes authenticate Git without
putting `GH_TOKEN` in the environment of every Git process.

## Existing checkout

`bootstrap.sh` is a compatibility wrapper for a repository that is already
checked out. It is current-directory independent and forwards bootstrap flags:

```bash
./bootstrap.sh dev --dry-run
./bootstrap.sh dev --force-dotfiles
./bootstrap.sh work --update --force-dotfiles
```

Unlike the disposable-sandbox quick start, the wrapper does not force dotfile
replacement unless the flag is explicitly supplied.

## Verify and update

```bash
BOOTSTRAP_DIR="$HOME/.local/share/thehumanworks-bootstrap"

mise -C "$BOOTSTRAP_DIR" -E dev run doctor
mise -C "$BOOTSTRAP_DIR" -E dev bootstrap status --missing
```

Re-run and fast-forward the stored checkout:

```bash
mise -E dev bootstrap \
  --from https://github.com/thehumanworks/bootstrap.git \
  --from-dir "$HOME/.local/share/thehumanworks-bootstrap" \
  --update \
  --yes \
  --force-dotfiles
```

The declarative bootstrap phases are convergent. `--update` performs a
fast-forward-only pull and refuses an existing checkout whose `origin` does not
match the requested URL.

## What is managed

- Language runtimes and development tools in `mise/conf.d/tools.toml`
- Exact Linux x64 tool versions and supported checksums in `mise/mise.lock`
- Global mise activation and aliases
- Personal or work Git identity plus a scoped credential helper
- fnox command profiles backed by 1Password
- Claude and Codex user settings

The existing tool set is preserved. This setup adds:

- `git-lfs`, which the committed Git configs already require;
- `jq`, for JSON processing alongside `yq`; and
- `shellcheck`, to validate the shell bootstrap code alongside `shfmt`.

`~/.claude.json` is deliberately not managed. Claude owns that mutable file;
it contains sign-in, machine, project, and session state. Only
`~/.claude/settings.json` is copied from this repository.

## Faster ephemeral startup

The full runtime set is intentionally broad, so a cold install is expensive.
For frequently-created sandboxes:

1. Install from the committed lockfile, and pre-bake mise plus the tool set
   into the base image when startup latency matters most.
2. Cache `$MISE_DATA_DIR` and `$MISE_CACHE_DIR` by OS, architecture, profile,
   and a hash of `mise/mise.lock`.
3. Keep the `--from-dir` checkout clean so it can be reused with `--update`.
4. Inject `OP_SERVICE_ACCOUNT_TOKEN` only when a sandbox starts; never bake
   credentials, shell history, or 1Password state into the image.
5. Consider a later base/toolchains/extras profile split after benchmarking
   which runtimes are actually needed in most sandboxes.

## References

- [mise bootstrap](https://mise.jdx.dev/bootstrap.html)
- [mise dotfiles](https://mise.jdx.dev/dotfiles.html)
- [mise configuration hierarchy](https://mise.jdx.dev/configuration.html)
- [fnox profiles and secret scope](https://fnox.jdx.dev/reference/configuration.html)
- [fnox exec](https://fnox.jdx.dev/cli/exec.html)
- [Git credential helpers](https://git-scm.com/docs/gitcredentials#_custom_helpers)
- [GitHub personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [GitHub CLI environment variables](https://cli.github.com/manual/gh_help_environment)
- [Claude Code settings](https://docs.anthropic.com/en/docs/claude-code/settings)
