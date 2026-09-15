# Base and work environments

Bootstrap with the native mise environment selector:

```sh
mise -E dev bootstrap --from https://github.com/thehumanworks/bootstrap.git
mise -E work bootstrap --from https://github.com/thehumanworks/bootstrap.git
```

For Modal, use the sandboxes project's `sb image build --profile base --publish`
or `sb image build --profile lf --publish`. These publish `mise:base` and
`mise:lf`. Rebuild after pushing bootstrap changes; the image records the
resolved bootstrap commit in the build result.

The work overlay selects the work Git identity, `GH_HOST=leadforensics.ghe.com`,
ACLI, and Atlassian MCP for Claude Code and Codex. Global mise overlays keep
these settings available outside this checkout. Image metadata and login
setup retain `MISE_ENV=work`; the app's SSH helper respects that selection.

`fnox.work.toml` defines native named profiles. `work` inherits `work-github`
and `work-atlassian`, and excludes default secrets using `FNOX_NO_DEFAULTS`.
This prevents this checkout's personal `fnox.toml` from overriding work auth.
`gh` and the work Git credential helper resolve only `work-github`, with a
hard error if its credential is unavailable. The work token uses `GH_TOKEN`,
which GitHub CLI prefers to `GITHUB_TOKEN` for `*.ghe.com`. The personal token
remains available as `MISE_GITHUB_TOKEN` for public GitHub downloads.

The image contains references, tools and client configuration. The named
Modal `1password` secret supplies `OP_SERVICE_ACCOUNT_TOKEN` at runtime.
Work secrets are not attached to image builds. The build-only `github`
secret may contain `GH_TOKEN` or `GITHUB_TOKEN`.

## Work commands

```sh
gh auth status --hostname leadforensics.ghe.com
gh api --hostname leadforensics.ghe.com user --jq .login
acli jira auth status
acli jira workitem search --jql 'assignee = currentUser()' --limit 1 --json
```

ACLI resolves only the three Atlassian credentials through fnox. Its wrapper
passes the token over stdin to official `acli ... auth login`, runs the
requested Jira/Confluence command and removes the temporary credential store.
Each invocation authenticates anew, so rotation takes effect without image
rebuilds. Other ACLI product commands retain their standard authentication.

Both agent clients register `atlassian` as a stdio server backed by pinned
`mcp-remote`, connecting to Atlassian's official `https://mcp.atlassian.com/v2/mcp`.
The launcher computes Basic auth in memory from the existing email/API token;
the adapter receives a literal environment-variable header reference, never a
token in arguments or client configuration. The organization must permit API
token authentication and the token must allow the requested operations.

For a manual MCP client, use this command and arguments:

```sh
fnox run --profile work-atlassian --no-defaults --if-missing error \
  --non-interactive -- atlassian-mcp
```

## Design references

Reviewed 2026-09-15:

- [mise environments](https://mise.jdx.dev/configuration/environments.html),
  [bootstrap](https://mise.jdx.dev/bootstrap.html) and
  [command wrappers](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers)
- [fnox profiles, hierarchy and no-defaults](https://fnox.jdx.dev/reference/configuration)
- [GitHub CLI token/hostname precedence](https://cli.github.com/manual/gh_help_environment)
- [Official Atlassian MCP authentication](https://atlassian.github.io/atlassian-mcp-server/)
- [Official ACLI stdin login](https://developer.atlassian.com/cloud/acli/reference/commands/jira-auth-login/)
- [mcp-remote environment headers](https://github.com/punkpeye/mcp-remote#custom-headers)
