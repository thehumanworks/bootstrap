# tmux workspaces

This configuration treats tmux as a persistent workspace manager for parallel coding agents:

- **session = workspace** — one repository or long-running objective;
- **window = workstream** — orchestration, agents, tests, logs, review, or a subproject;
- **pane = process/agent** — one shell, editor, agent, watcher, or service.

Copied from the workstation's `~/.config/mise` configuration, with the same
keybindings and theme, plus sandbox-compatible directory handling in the
workspace helper on macOS, Linux VMs and Modal sandboxes.
The normal interaction model is prefixless. **Hyper** (Caps Lock mapped to
`⌃⌥⇧⌘` on the workstation) controls tmux directly. The terminal must send
extended `Ctrl+Alt+Shift` keys; the keyboard remap belongs on the client machine.
The optional Linux keyboard profile below installs that remap. Over SSH the remote machine needs
the tmux files, not Raycast, Ghostty or a macOS window manager.

Terminals without Hyper can use `Ctrl-a` followed by `c` (new window), `%` / `"`
(split), arrow keys (select pane), `s` (sessions), `w` (windows), `[` (copy),
`]` (paste), `d` (detach), or `?` (this config's key reference). Run `tw` for
the workspace picker and `tw agent` / `tw grid` for agent layouts. F12 toggles
key forwarding to an inner tmux, so the same prefix works through nested SSH.

`mise bootstrap` applies `~/.config/tmux/tmux.conf` and `~/.local/bin/tw`. After
the files land, a `post-dotfiles` hook reloads any already-running tmux server
with `tmux source-file`. The hook is a no-op when tmux is missing or no server
is running, so it never starts a server and never kills sessions.

```sh
./bootstrap.sh
# Apply only tmux files to an already provisioned machine, from this checkout:
mise bootstrap dotfiles apply --yes \
  ~/.config/tmux/tmux.conf ~/.local/bin/tw \
  ~/.local/bin/agent-tmux-state ~/.local/bin/claude-tmux-state \
  ~/.local/lib/tmux/install-tmux-plugins.sh \
  ~/.local/lib/tmux/reload-tmux-config.sh ~/.local/lib/tmux/tmux-prompt.bash \
  ~/.bashrc/tmux-cwd ~/.bash_profile/tmux-cwd
```

New tmux servers load the managed configuration automatically. Later changes
can also be reloaded with `Ctrl-a r`. A configuration reload does not require
`tmux kill-server`, which would terminate every session and child process.

The selected dotfile apply also runs the plugin/reload hook. On an existing
machine, a conflicting file requires an intentional `--force` replacement.
Helpers and hooks resolve from this checkout; keep it on disk. New sandboxes
must be built from a revision containing these files, or receive and apply the
updated checkout. Existing sandbox images do not update automatically.
Run bootstrap and dotfile apply from the checkout: Mise 2026.9.0 resolves their
relative source paths beside the loaded config, even when that config is a
symlink. The installed `tw` and `mise run update-tmux-plugins` commands work
from other directories.

Use the Mise-managed tmux version declared in `mise.toml`. Minimal Linux images
also need the `tmux-256color` terminfo entry; Debian-family distributions provide it in
`ncurses-term`. Check with `infocmp tmux-256color` if attaching fails.

On Modal's restricted PTYs, tmux may not be able to query a pane's working
directory. The managed Bash prompt hook reports it at each prompt, so windows,
splits and popups still follow `cd`. Before the first prompt they use the pane's
start directory. Worktree commands read the pane process's `/proc` cwd when
needed. Other shells on such hosts need an equivalent `@shell_cwd` prompt hook;
normal macOS and Linux terminals use tmux's native directory detection.

The `agent-tmux-state` helper and its legacy `claude-tmux-state` name are
installed, but this copy does not alter agent harness hooks. A harness can call
`agent-tmux-state working`, `input`, `done`, or `clear` to update pane labels
and attention bells.

## Caps Lock on a Linux keyboard host

The optional `keyboard-linux` profile installs [keyd](https://github.com/rvaiya/keyd),
which remaps physical keyboards across Wayland, X11 and Linux consoles. Use it
on the Linux machine running your terminal, or a VM with a directly attached
keyboard. It cannot change keys already encoded by an SSH client, and does not
apply to Modal's headless sandboxes.

On Debian 13 or a compatible apt-based desktop with the `keyd` package and
systemd, run this single command from this checkout:

```sh
mise run --skip-tools keyboard:setup
```

The task installs keyd, applies the mapping and enables/starts its service in
order, stopping if a step fails. `--skip-tools` avoids installing unrelated
language runtimes for this system-package task. Mise requests sudo when needed.
Holding Caps Lock now sends Ctrl+Alt+Shift,
matching tmux's `C-M-S-` bindings; for example Caps Lock+h selects the left pane.
Super is omitted so Linux desktop Super shortcuts do not consume the chord.
Your terminal must support extended keys. A Linux virtual console cannot encode
every such combination; `Ctrl-a` remains the fallback there.

The profile manages `/etc/keyd/bootstrap-tmux.conf` and `keyd.service`. It is
not enabled by normal `./bootstrap.sh`; the existing macOS Hyper remapper stays
on the keyboard host. If you already use keyd, merge the Caps Lock mapping into
the config for your keyboard instead: keyd must not match the same device from
two configuration files.

Rerun the same setup command after editing the mapping; Mise reloads or restarts
keyd on changes. To turn remapping off, run `sudo systemctl disable --now keyd`.
keyd's emergency stop chord is Backspace+Escape+Enter.


## Start and reattach

The `tw` helper works both outside and inside tmux:

```sh
# Select an existing workspace, or create one when none exist.
tw

# Create one normal workspace rooted at the current Git repository.
tw new

# Create an orchestrator window and a four-pane agent window.
tw agent

# Explicit forms are useful in scripts.
tw new api ~/code/api
tw agent api-agents ~/code/api 6

# Inspect, attach, rename, and remove workspaces.
tw list
tw attach
tw rename
tw kill
```

Names are normalised for reliable tmux targeting. When no directory is supplied, `tw` uses the current Git repository root, falling back to the current directory.

Press `Hyper-Enter` or `Ctrl-a W` (uppercase W) to create a new Git worktree and open a window
there. It uses the active pane's checkout and committed `HEAD`, creates a unique
branch, and places the worktree beside that checkout as `<checkout>-worktree.XXXXXX`.
Uncommitted changes stay in the original checkout. Repeated presses create
separate worktrees; closing a window leaves its worktree and branch intact.
Outside Git, or if worktree creation fails (including a repo without commits),
it opens a normal window in the active pane's directory. The same action is
available inside tmux as `tw worktree`.

Worktree lifecycle actions use separate keys and ask for confirmation:

| Action | Prefix binding | Hyper binding |
|---|---|---|
| Merge into the recorded parent branch | `Ctrl-a F9` | `Hyper-F9` |
| Remove the worktree directory and invoking pane | `Ctrl-a F10` | `Hyper-F10` |

Creation records the source branch in local Git configuration as
`branch.<new-branch>.tmux-parent`. Merge requires that parent branch to be
checked out and both worktrees to be clean. It fast-forwards where possible
and otherwise creates a merge commit. Conflicts stay in the parent checkout
for manual resolution or `git merge --abort`; the helper prints its path.
Merging keeps the child worktree, branch, and pane.

Removal uses `git worktree remove` without force and keeps the branch, including
unmerged commits. It refuses the main checkout, detached HEADs, locked worktrees,
unfinished Git operations, uncommitted/untracked/ignored files, and worktrees
used by another pane on the same tmux server. After Git removes the directory,
only the invoking pane closes (and its window if it was the last pane).
`Hyper-d`, `Hyper-x`, and window-close bindings keep their existing behavior.

Worktrees created before parent tracking was added, or from detached HEAD,
have no recorded parent. To choose one explicitly, run this in the child
worktree, replacing `main` with the intended parent:

```sh
git config --local "branch.$(git branch --show-current).tmux-parent" main
```

The direct commands `tw worktree-merge` and `tw worktree-remove` perform the
same checks immediately; confirmation is supplied by the keybindings.

## Agent layout

`tw agent` creates:

```text
workspace
├── control    # one pane titled "orchestrator"
└── agents     # four tiled panes: agent-1 ... agent-4
```

The panes intentionally start as ordinary shells. This keeps the layout tool independent of Codex, Claude, Cursor Agent, Grok, or any future agent command, and avoids silently starting duplicate jobs after reattachment.

Inside an existing workspace, `Hyper-g` adds another four-pane agent window. Repeated use creates `agents`, `agents-2`, `agents-3`, and so on.

`Hyper-y` toggles tmux `synchronize-panes`, which broadcasts each keystroke to every pane in the current window. The top-right status displays **SYNC** while broadcasting. Disable it before entering agent-specific prompts or secrets.

## Attention routing

With several agents running, the question is which pane needs you. Streaming
output makes tmux's activity flag useless, so the configuration tracks
**bells** and an optional per-pane **agent state** instead.

- Every pane border shows `▶ working`, `⏳ input`, or `✔ done` next to the
  pane title when a harness publishes its state. A crashed pane stays on
  screen as `[exited N]` instead of vanishing with its last output.
- A window whose agent needs input or finished a turn rings the bell. Its tab
  turns red, the status bar shows one `!` per waiting window, and a short
  message names the window. `Hyper-f` jumps to the next such window;
  `Hyper-Tab` returns to the previous one.
- `Hyper-;` bounces between the last two panes, for the orchestrator and one
  agent.
- A bell that rings while no client is attached only sets the window flag;
  the message is shown only to attached clients. Otherwise tmux would queue
  the text as a configuration error and dump it into the active pane, in view
  mode, on the next attach.

The state comes from `~/.local/bin/agent-tmux-state`, which writes the
pane option `@agent_state` and rings the bell on the pane's tty. If the tty is
unavailable to the hook, it asks the tmux server to ring the bell. Configure
harness lifecycle hooks separately, or publish the signals directly:

```sh
agent-tmux-state input     # ⏳ needs a human, ring the bell
agent-tmux-state done      # ✔ finished a turn, ring the bell
agent-tmux-state working   # ▶ busy
agent-tmux-state clear     # remove the label
printf '\a'                 # bell only, works from any process in a pane
```

`Ctrl-a R` restarts a dead pane and clears its stale state. `Ctrl-a P` toggles
logging of one pane's output to `~/.local/state/tmux/`, which is useful when
comparing parallel agents after the fact.

## Moving agents around

`Hyper-b` breaks the current pane out into its own window when an agent grows
too chatty for a grid. To pull a pane back beside you, mark it with `Hyper-m`
in its window, move to the destination window, and press `Hyper-v`.

## Reading agent output

`Hyper-[` enters copy mode for keyboard scrolling and `Hyper-]` pastes the
tmux buffer. `Hyper-u` opens [extrakto](https://github.com/laktak/extrakto) in
a popup: a fuzzy list of paths, URLs, and tokens from the pane's scrollback.
`Enter` copies the pick, `Tab` inserts it at the shell prompt, `Ctrl-o` opens
it, `Ctrl-f` cycles the filter, `Ctrl-g` narrows the capture. Without the
plugin installed, `Hyper-u` falls back to a copy-mode search for the last
path or URL.

## Nested tmux over SSH

The intended multi-machine model is to SSH (Tailscale) into a box and attach
to the tmux server there, so each pane holds one remote tmux client. Every
Hyper chord is a root-table bind, so the local tmux would swallow it before the
remote one saw it. `Hyper-Escape` (or `F12` from a keyboard without Hyper)
hands every key, `Ctrl-a` and Hyper included, to the current pane; the same
key takes them back. While passive the status bar dims and shows **NESTED**.

The toggle is session-scoped, so it stays with the workspace that holds the
SSH pane and never affects another workspace on the same server. It works by
switching the session to the `off` key table and unsetting its prefixes,
so both ends can run this configuration and the remote tmux answers to the
same keys once it has them.

## Prefixless keys

On macOS, **Caps Lock** is Raycast's Hyper key (`⌃⌥⇧⌘`). Hold Caps Lock, then tap the letter. Hyper already includes Shift, so the old `Alt-Shift-*` actions now use their own letters instead of a second Shift.

tmux binds the chord as `C-M-S-`. Command may be present in the OS event; Ghostty is left to encode the rest.

### Workspaces

| Key | Action |
|---|---|
| `Hyper-s` | Select and switch workspace with `fzf` |
| `Hyper-a` | Attach/select workspace |
| `Hyper-n` | Create a standard workspace |
| `Hyper-e` | Create an agent workspace |
| `Hyper-q` | Select and remove a workspace |
| `Hyper-d` | Detach this client; processes continue |
| `Hyper-r` | Rename the current workspace |

Outside tmux, use the matching `tw` subcommands because tmux key tables only exist for attached clients.

### Panes

| Key | Action |
|---|---|
| `Hyper-h/j/k/l` | Move left/down/up/right |
| `Hyper-;` | Jump to the previously active pane |
| `Hyper-←/↓/↑/→` | Resize left/down/up/right by five cells |
| `Hyper--` | Horizontal split (stack panes, `-` divider) |
| `Hyper-\|` | Vertical split (side by side, `\|` divider) |
| `Hyper-x` | Remove pane immediately |
| `Hyper-z` | Toggle pane zoom |
| `Hyper-p` | Show pane numbers |
| `Hyper-t` | Rename pane title |
| `Hyper-b` | Break pane out into its own window |
| `Hyper-m` / `Hyper-v` | Mark a pane / join the marked pane beside this one |

These bindings do not consume Neovim's existing `Ctrl-h/j/k/l` window navigation.

### Windows

| Key | Action |
|---|---|
| `Hyper-c` | Create window in the current directory |
| `Hyper-Enter` | Create a worktree window; open a normal window outside Git |
| `Hyper-F9` / `Hyper-F10` | Confirm merge into parent / remove worktree and pane |
| `Hyper-w` | Open tmux's window/tree chooser |
| `Hyper-,` / `Hyper-.` | Previous / next window |
| `Hyper-Tab` | Previously active window |
| `Hyper-f` | Next window whose agent rang the bell |
| `Hyper-i` | Rename window |
| `Hyper-Backspace` | Remove window with confirmation |
| `Hyper-1` … `Hyper-9`, `Hyper-0` | Select windows 1 … 10 |

### Agent and utility controls

| Key | Action |
|---|---|
| `Hyper-g` | Add a four-pane tiled agent window |
| `Hyper-y` | Toggle broadcast input for the current window |
| `Hyper-u` | Pick a path, URL, or token from pane text (extrakto) |
| `Hyper-[` / `Hyper-]` | Copy mode / paste buffer |
| `Hyper-o` | Open a large scratch-shell popup |
| `Hyper-Escape` / `F12` | Hand all keys to a nested tmux in this pane; press again to take them back |
| `Hyper-/` | Open the key reference |
| `Ctrl-a ?` | Open the same key reference without Hyper |
| `Ctrl-a r` | Reload the tmux configuration |
| `Ctrl-a W` | Create a worktree window; open a normal window outside Git |
| `Ctrl-a F9` / `Ctrl-a F10` | Confirm merge into parent / remove worktree and pane |
| `Ctrl-a R` | Restart a dead pane and clear its agent state |
| `Ctrl-a P` | Toggle logging this pane to `~/.local/state/tmux/` |
| `Ctrl-a I` / `Ctrl-a U` | Install / update tpm plugins |

## Persistence model

A detached tmux workspace remains on the machine with its child processes running. It therefore survives:

- closing Ghostty or another terminal window;
- detaching with `Hyper-d`;
- an SSH or Tailscale SSH disconnect;
- attaching from another client later with `tw attach`.

A pane whose process exits with a non-zero status stays on screen with its
output (`remain-on-exit failed`); `Ctrl-a R` restarts it. Clean exits still
close the pane.

This is process persistence, not reboot recovery. A machine restart, sandbox
termination or explicit `tmux kill-server` ends the server and its processes.
The configuration does not restore sessions after a restart.

## Terminal behaviour

Use a UTF-8 terminal/locale for the Unicode pane labels. On a minimal Linux
image with only the `C` locale, start the client with `tmux -u` or set a supported
UTF-8 locale such as `LANG=C.UTF-8`.

The configuration uses `tmux-256color` inside panes and enables true colour,
OSC 52 clipboard integration, focus events, hyperlinks, extended keys,
synchronized updates, mouse support, alternate-screen applications, and
controlled passthrough for modern terminal applications. Scrollback is 50,000
lines per pane, which keeps a dozen agent panes affordable; agents keep their
own transcripts.

When a client creates or attaches to a session, tmux merges all of that
client's environment into the session. This keeps `PATH`, mise activation,
virtual environments, `COLORTERM`, and other shell variables available to new
windows. Variables absent from the attaching client are retained so attaching
from a less specialised shell does not erase a workspace's environment.
Transient terminal, display, and authentication-agent variables are the
exception: tmux explicitly removes those when the client no longer supplies
them, preventing stale sockets or terminal identity from leaking into new
processes.

This also means a persistent session retains exported client variables,
including secret-bearing ones, for new processes started in that session. Do
not attach from a shell containing short-lived secrets unless the workspace is
intended to inherit them. A stricter machine may replace the wildcard with an
explicit allowlist in `~/.config/tmux/local.conf`.

Reloading the configuration changes the update policy, but an existing session
receives the current client environment on its next attach. Detach and reattach
once after the first reload; no server restart is required.

For a fidelity check, run:

```sh
printf 'inside: TERM=%s COLORTERM=%s\n' "$TERM" "${COLORTERM-}"
tmux display-message -p 'outside: #{client_termname} [#{client_termfeatures}]'
```

The inside value should be `TERM=tmux-256color`; from Ghostty, the client should
normally report `xterm-ghostty` with `RGB` and `sync`. A client reporting a
minimal type such as `linux` did not advertise the capabilities of its real
terminal, so tmux cannot safely infer full colour or synchronized rendering
from it. Fix that terminal or transport's `TERM`/terminfo setup rather than
forcing unsupported capabilities in tmux.

If a transport is known to hard-code `TERM=linux` even though its terminal
really supports 256 colours, RGB, and synchronized updates, detach and reattach
with an explicit client override: `tmux -2 -T RGB,sync attach -t NAME`.

OSC 52 clipboard access and terminal passthrough cross the pane-to-host trust
boundary: programs running in a pane, including repository-controlled output,
may write to the host clipboard or emit supported terminal control sequences.
Run only trusted workloads in these sessions, or disable `set-clipboard` and
`allow-passthrough` in `~/.config/tmux/local.conf`.

```tmux
set-option -s set-clipboard off
set-window-option -g allow-passthrough off
```

The status and pane borders reuse the repository's Cutie Pro palette. Pane headers show pane number, explicit title, current command, and directory, which makes parallel agents distinguishable even when their terminal output looks similar.

## Plugins

[tpm](https://github.com/tmux-plugins/tpm) loads the plugins declared with
`@plugin` in `tmux.conf`. `scripts/install-tmux-plugins.sh` installs missing
tpm/plugin checkouts into `~/.config/tmux/plugins/` during `mise bootstrap`,
without starting a server or updating existing checkouts. Run
`mise run update-tmux-plugins` to update them and reload the running server;
`Ctrl-a I` and `Ctrl-a U` install and update interactively. Failures are reported
as errors. The configuration sources cleanly when the directory
is absent, so a fresh machine or CI never depends on the plugins.

Only extrakto is installed. It needs `python3` and `fzf`, both managed by
mise. Alternatives were rejected on purpose: tmux-fingers needs an interactive
install wizard or a per-platform binary, tmux-fzf-url downloads a helper from
GitHub on first use, tmux-logging is unmaintained and one `pipe-pane` bind
replaces it, tmux-yank duplicates OSC 52, and session-switcher plugins
duplicate `tw`.

## Verification

Run `mise run test` for contract and plugin-installer checks, and
`mise run test-tmux` for isolated runtime checks of keybindings, reloads,
workspace/worktree operations, agent-state reporting and nested key forwarding.
The runtime suite creates and removes only its own tmux servers and temporary
repositories. See [the maintainer guide](MAINTAINERS.md) for the live Modal gate.

## Local overrides

Machine-specific settings may be placed in:

```text
~/.config/tmux/local.conf
```

It is loaded after the tracked configuration and is intentionally absent from the repository.

The fixtures in `tests/keyd/*.t` exercise the Linux mapping with upstream keyd's
`test-io` engine (tested with v2.5.0). Build that engine in a separate keyd
checkout with `make test-io`, then run its `bin/test-io` against
`dotfiles/keyd/tmux.conf` and `tests/keyd/*.t`. This checks emitted key events
without input devices; actual keyboard, desktop shortcuts and systemd service
activation still need a Linux keyboard host.
