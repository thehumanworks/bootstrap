#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
HELPER="$REPO_ROOT/scripts/tmux-workspace"
RELOAD="$REPO_ROOT/scripts/reload-tmux-config.sh"
CONFIG="$REPO_ROOT/dotfiles/tmux/tmux.conf"

fail() {
	printf 'test_tmux: %s\n' "$*" >&2
	exit 1
}

assert_equal() {
	local expected=$1
	local actual=$2
	local label=$3
	[[ $actual == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

assert_contains_line() {
	local expected=$1
	local input=$2
	local label=$3
	while IFS= read -r line; do
		[[ $line == "$expected" ]] && return
	done <<<"$input"
	fail "$label: missing '$expected'"
}

wait_for_format() {
	local target=$1
	local format=$2
	local expected=$3
	local label=$4
	local actual=''
	for _ in {1..100}; do
		actual=$(tmux_test display-message -p -t "$target" "$format")
		[[ $actual == "$expected" ]] && return
		sleep 0.02
	done
	fail "$label: expected '$expected', got '$actual'"
}

dump_keys() {
	local table=${1:-root}
	printf 'test_tmux: tmux %s\n' "$("$REAL_TMUX" -V)" >&2
	tmux_test list-keys -T "$table" >&2 || true
}

# Match the key field that follows the table name, so C-M-S does not collide
# with C-M-S-h and stock menu bindings mentioning "R" do not shadow prefix R.
lookup_key() {
	local table=$1
	local key=$2
	tmux_test list-keys -T "$table" |
		awk -v key="$key" -v table="$table" '
			$1 == "bind-key" {
				for (i = 2; i < NF; i++) {
					if ($i == "-T" && $(i + 1) == table && $(i + 2) == key) {
						print
						exit
					}
				}
			}
		'
}

assert_key_contains() {
	local key=$1
	local expected=$2
	local binding
	binding=$(lookup_key root "$key")
	[[ -n $binding && $binding == *"$expected"* ]] && return
	dump_keys root
	fail "root binding $key does not contain $expected"
}

assert_exact_key() {
	local key=$1
	local expected=$2
	local table=${3:-root}
	local binding
	binding=$(lookup_key "$table" "$key")
	[[ -n $binding && $binding == *"$expected"* ]] && return
	dump_keys "$table"
	fail "$table binding $key does not contain $expected"
}

# tmux < 3.5 lists Hyper letters as C-M-X instead of C-M-S-x.
assert_hyper_letter() {
	local letter=$1
	local expected=$2
	local lower=$letter
	local upper
	upper=$(printf '%s' "$letter" | tr '[:lower:]' '[:upper:]')
	local binding
	binding=$(lookup_key root "C-M-S-$lower")
	[[ -z $binding ]] && binding=$(lookup_key root "C-M-$upper")
	if [[ -n $binding && $binding == *"$expected"* ]]; then
		return
	fi
	dump_keys root
	fail "Hyper-$lower binding does not contain $expected"
}

bash -n "$HELPER"
bash -n "$RELOAD"
bash -n "$REPO_ROOT/scripts/install-tmux-plugins.sh"

if ! command -v tmux >/dev/null 2>&1; then
	printf '%s\n' 'tmux is unavailable; helper syntax passed, integration checks skipped.'
	exit 0
fi

REAL_TMUX=$(command -v tmux)
if command -v mise >/dev/null 2>&1; then
	MISE_TMUX=$(mise which tmux 2>/dev/null || true)
	if [[ -x $MISE_TMUX ]]; then
		REAL_TMUX=$MISE_TMUX
	fi
fi
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tmux-test.XXXXXX")
TMP_ROOT=$(CDPATH='' cd -- "$TMP_ROOT" && pwd -P)
SOCKET_NAME="dotfiles-test-$$"
PROJECT="$TMP_ROOT/project"
TEST_HOME="$TMP_ROOT/home"
WRAPPER="$TMP_ROOT/bin/tmux"
mkdir -p "$PROJECT" "$TEST_HOME/.config/tmux" "$TMP_ROOT/bin"
mkdir -p "$TEST_HOME/.local/bin"
ln -s "$HELPER" "$TEST_HOME/.local/bin/tw"
# Load only the prompt hook in fixture shells, never the real user's startup.
printf 'source "%s/scripts/tmux-prompt.bash"\n' "$REPO_ROOT" >"$TEST_HOME/.bashrc"
cp "$TEST_HOME/.bashrc" "$TEST_HOME/.bash_profile"

cleanup() {
	"$REAL_TMUX" -L "$SOCKET_NAME-host" kill-server >/dev/null 2>&1 || true
	"$REAL_TMUX" -L "$SOCKET_NAME" kill-server >/dev/null 2>&1 || true
	"$REAL_TMUX" -L "$SOCKET_NAME-inner" kill-server >/dev/null 2>&1 || true
	"$REAL_TMUX" -L "$SOCKET_NAME-detached-host" kill-server >/dev/null 2>&1 || true
	"$REAL_TMUX" -L "$SOCKET_NAME-detached" kill-server >/dev/null 2>&1 || true
	rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

cat >"$WRAPPER" <<EOF_WRAPPER
#!/bin/sh
exec "$REAL_TMUX" -L "$SOCKET_NAME" "\$@"
EOF_WRAPPER
chmod +x "$WRAPPER"

# All helper calls use this isolated server through the wrapper.
export TMUX_BIN="$WRAPPER"
export HOME="$TEST_HOME"
# Do not inherit Mise/Fnox command wrappers after changing HOME: their trust
# state and credentials belong to the real user, not this test fixture.
export PATH="$TMP_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export SHELL=/bin/bash

tmux_test() {
	"$WRAPPER" "$@"
}

# Bootstrap must not start a server when none exists.
unset TMUX || true
unset TMUX_PANE || true
PATH="$TMP_ROOT/bin:$PATH" TMUX_BIN="$WRAPPER" HOME="$TEST_HOME" \
	"$RELOAD"
if "$REAL_TMUX" -L "$SOCKET_NAME" list-sessions >/dev/null 2>&1; then
	fail 'reload helper started a tmux server'
fi

# A readable managed config plus a live server must reload without kill-server.
ln -s "$CONFIG" "$TEST_HOME/.config/tmux/tmux.conf"
"$REAL_TMUX" -L "$SOCKET_NAME" -f /dev/null \
	new-session -d -s bootstrap -c "$PROJECT"
assert_equal C-b "$(tmux_test show-options -gv prefix)" 'stock prefix before reload'
PATH="$TMP_ROOT/bin:$PATH" TMUX_BIN="$WRAPPER" HOME="$TEST_HOME" \
	"$RELOAD"
assert_equal C-a "$(tmux_test show-options -gv prefix)" 'managed prefix after reload'

tmux_test source-file "$CONFIG"

assert_exact_key W 'worktree' prefix
assert_exact_key C-M-S-Enter 'worktree'
assert_exact_key F9 'confirm-before' prefix
assert_exact_key F9 'worktree-merge' prefix
assert_exact_key F10 'confirm-before' prefix
assert_exact_key F10 'worktree-remove' prefix
assert_exact_key C-M-S-F9 'worktree-merge'
assert_exact_key C-M-S-F10 'worktree-remove'

# Exercise real Git worktrees and fallback windows on an isolated server.
GIT_PROJECT="$TMP_ROOT/repo with 'quotes' and \$dollars"
mkdir -p "$GIT_PROJECT/subdir"
git -C "$GIT_PROJECT" init -q
git -C "$GIT_PROJECT" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m initial
printf 'uncommitted\n' >"$GIT_PROJECT/dirty.txt"
SOURCE_PANE=$(tmux_test new-session -d -P -F '#{pane_id}' -s worktrees -c "$GIT_PROJECT/subdir" 'sleep 60')
"$HELPER" worktree "$SOURCE_PANE"
FIRST_WORKTREE=$(tmux_test display-message -p -t worktrees '#{E:@tw_cwd}')
[[ $FIRST_WORKTREE == "$GIT_PROJECT"-worktree.* ]] || fail 'worktree was not created beside the checkout'
assert_equal "$(git -C "$GIT_PROJECT" rev-parse HEAD)" "$(git -C "$FIRST_WORKTREE" rev-parse HEAD)" 'worktree starts at source HEAD'
[[ $(git -C "$FIRST_WORKTREE" branch --show-current) == worktree/* ]] || fail 'worktree does not have its own branch'
[[ ! -e $FIRST_WORKTREE/dirty.txt && -f $GIT_PROJECT/dirty.txt ]] || fail 'uncommitted files changed'
"$HELPER" worktree "$SOURCE_PANE"
SECOND_WORKTREE=$(tmux_test display-message -p -t worktrees '#{E:@tw_cwd}')
[[ $SECOND_WORKTREE != "$FIRST_WORKTREE" ]] || fail 'repeated invocation reused a worktree'
LINKED_PANE=$(tmux_test display-message -p -t worktrees '#{pane_id}')
"$HELPER" worktree "$LINKED_PANE"
THIRD_WORKTREE=$(tmux_test display-message -p -t worktrees '#{E:@tw_cwd}')
assert_equal "$(git -C "$GIT_PROJECT" rev-parse HEAD)" "$(git -C "$THIRD_WORKTREE" rev-parse HEAD)" 'creation from linked worktree'
assert_equal 4 "$(git -C "$GIT_PROJECT" worktree list --porcelain | grep -c '^worktree ')" 'three distinct worktrees registered'

for FALLBACK_KIND in plain unborn; do
	FALLBACK_DIR="$TMP_ROOT/$FALLBACK_KIND directory"
	mkdir -p "$FALLBACK_DIR"
	if [[ $FALLBACK_KIND == unborn ]]; then
		git -C "$FALLBACK_DIR" init -q
	fi
	FALLBACK_PANE=$(tmux_test new-session -d -P -F '#{pane_id}' -s "$FALLBACK_KIND" -c "$FALLBACK_DIR" 'sleep 60')
	"$HELPER" worktree "$FALLBACK_PANE"
	assert_equal 2 "$(tmux_test list-windows -t "$FALLBACK_KIND" | wc -l | tr -d ' ')" "$FALLBACK_KIND fallback creates window"
	assert_equal "$FALLBACK_DIR" "$(tmux_test display-message -p -t "$FALLBACK_KIND" '#{E:@tw_cwd}')" "$FALLBACK_KIND fallback directory"
done

# Merge/remove operate only on disposable repositories and named test panes.
expect_worktree_failure() {
	local command=$1 pane=$2 message=$3 output
	if output=$("$HELPER" "$command" "$pane" 2>&1); then
		fail "$command unexpectedly succeeded: $message"
	fi
	[[ $output == *"$message"* ]] || fail "$command returned unexpected error: $output"
}

MERGE_PROJECT="$TMP_ROOT/merge project"
mkdir -p "$MERGE_PROJECT"
git -C "$MERGE_PROJECT" init -q
git -C "$MERGE_PROJECT" config user.name Test
git -C "$MERGE_PROJECT" config user.email test@example.invalid
printf 'base\n' >"$MERGE_PROJECT/shared"
git -C "$MERGE_PROJECT" add shared
git -C "$MERGE_PROJECT" commit -qm initial
PARENT_BRANCH=$(git -C "$MERGE_PROJECT" branch --show-current)
PARENT_PANE=$(tmux_test new-session -d -P -F '#{pane_id}' -s lifecycle -c "$MERGE_PROJECT" 'sleep 300')
"$HELPER" worktree "$PARENT_PANE"
CHILD_ROOT=$(tmux_test display-message -p -t lifecycle '#{E:@tw_cwd}')
CHILD_PANE=$(tmux_test display-message -p -t lifecycle '#{pane_id}')
CHILD_BRANCH=$(git -C "$CHILD_ROOT" branch --show-current)
assert_equal "$PARENT_BRANCH" "$(git -C "$CHILD_ROOT" config --get "branch.$CHILD_BRANCH.tmux-parent")" 'recorded parent branch'
expect_worktree_failure worktree-remove "$PARENT_PANE" 'main checkout'
expect_worktree_failure worktree-merge "$PARENT_PANE" 'main checkout'
expect_worktree_failure worktree-remove "$FALLBACK_PANE" 'main checkout'
git -C "$CHILD_ROOT" config --unset "branch.$CHILD_BRANCH.tmux-parent"
expect_worktree_failure worktree-merge "$CHILD_PANE" 'no recorded parent'
git -C "$CHILD_ROOT" config "branch.$CHILD_BRANCH.tmux-parent" "$PARENT_BRANCH"
printf 'child\n' >"$CHILD_ROOT/feature"
expect_worktree_failure worktree-merge "$CHILD_PANE" 'uncommitted'
expect_worktree_failure worktree-remove "$CHILD_PANE" 'uncommitted'
git -C "$CHILD_ROOT" add feature
git -C "$CHILD_ROOT" commit -qm feature
printf 'parent dirty\n' >"$MERGE_PROJECT/untracked"
expect_worktree_failure worktree-merge "$CHILD_PANE" 'uncommitted'
rm "$MERGE_PROJECT/untracked"
"$HELPER" worktree-merge "$CHILD_PANE"
assert_equal "$(git -C "$CHILD_ROOT" rev-parse HEAD)" "$(git -C "$MERGE_PROJECT" rev-parse HEAD)" 'merge advances parent'
[[ -d $CHILD_ROOT ]] || fail 'merge removed the worktree'

# Diverged branches with independent edits merge without changing the child.
printf 'parent\n' >"$MERGE_PROJECT/parent-only"
git -C "$MERGE_PROJECT" add parent-only
git -C "$MERGE_PROJECT" commit -qm parent
printf 'child two\n' >"$CHILD_ROOT/feature"
git -C "$CHILD_ROOT" commit -qam child-two
CHILD_HEAD=$(git -C "$CHILD_ROOT" rev-parse HEAD)
"$HELPER" worktree-merge "$CHILD_PANE"
git -C "$MERGE_PROJECT" merge-base --is-ancestor "$CHILD_HEAD" HEAD || fail 'merge did not include child commits'
assert_equal "$CHILD_HEAD" "$(git -C "$CHILD_ROOT" rev-parse HEAD)" 'merge preserves child branch'

# Conflicts stay in the parent for explicit resolution; never force/reset it.
printf 'parent change\n' >"$MERGE_PROJECT/shared"
git -C "$MERGE_PROJECT" commit -qam parent-conflict
printf 'child change\n' >"$CHILD_ROOT/shared"
git -C "$CHILD_ROOT" commit -qam child-conflict
expect_worktree_failure worktree-merge "$CHILD_PANE" 'merge did not complete'
git -C "$MERGE_PROJECT" rev-parse --verify MERGE_HEAD >/dev/null || fail 'conflict did not preserve merge state'
expect_worktree_failure worktree-merge "$CHILD_PANE" 'Git operation in progress'
git -C "$MERGE_PROJECT" merge --abort

printf 'local-secret\n' >"$CHILD_ROOT/.ignored-secret"
printf '.ignored-secret\n' >>"$MERGE_PROJECT/.git/info/exclude"
expect_worktree_failure worktree-remove "$CHILD_PANE" 'protected ignored files'
rm "$CHILD_ROOT/.ignored-secret"
git -C "$MERGE_PROJECT" worktree lock "$CHILD_ROOT"
expect_worktree_failure worktree-remove "$CHILD_PANE" 'locked'
git -C "$MERGE_PROJECT" worktree unlock "$CHILD_ROOT"
OTHER_PANE=$(tmux_test new-window -d -P -F '#{pane_id}' -t '=lifecycle:' -c "$CHILD_ROOT" 'sleep 300')
expect_worktree_failure worktree-remove "$CHILD_PANE" 'another tmux pane'
tmux_test kill-pane -t "$OTHER_PANE"
"$HELPER" worktree-remove "$CHILD_PANE"
[[ ! -e $CHILD_ROOT ]] || fail 'remove left the worktree directory'
git -C "$MERGE_PROJECT" show-ref --verify --quiet "refs/heads/$CHILD_BRANCH" || fail 'remove deleted the branch'
assert_equal 1 "$(git -C "$MERGE_PROJECT" worktree list --porcelain | grep -c '^worktree ')" 'remove unregisters worktree'
assert_equal 1 "$(tmux_test list-panes -s -t lifecycle | wc -l | tr -d ' ')" 'remove closes only its pane'

assert_equal tmux-256color "$(tmux_test show-options -sv default-terminal)" 'default terminal'
assert_equal off "$(tmux_test show-options -gv destroy-unattached)" 'durable sessions'
assert_equal off "$(tmux_test show-options -sv exit-unattached)" 'durable server'
assert_equal on "$(tmux_test show-window-options -gv alternate-screen)" 'alternate screen'

TERMINAL_FEATURES=$(tmux_test show-options -sv terminal-features)
[[ $TERMINAL_FEATURES == *'xterm-ghostty:RGB:clipboard:focus:hyperlinks:extkeys:sync'* ]] ||
	fail 'Ghostty terminal features do not include RGB and synchronized updates'
assert_equal 1 "$(grep -c '^xterm-ghostty:RGB:clipboard:focus:hyperlinks:extkeys:sync$' <<<"$TERMINAL_FEATURES")" \
	'one Ghostty terminal feature entry'

# Reloading through Ctrl-a r/source-file must not append duplicate array entries.
tmux_test source-file "$CONFIG"
TERMINAL_FEATURES=$(tmux_test show-options -sv terminal-features)
assert_equal 1 "$(grep -c '^xterm-ghostty:RGB:clipboard:focus:hyperlinks:extkeys:sync$' <<<"$TERMINAL_FEATURES")" \
	'idempotent Ghostty terminal feature entry'

UPDATE_ENVIRONMENT=$(tmux_test show-options -gv update-environment)
assert_contains_line '*' "$UPDATE_ENVIRONMENT" 'environment wildcard'
assert_contains_line COLORTERM "$UPDATE_ENVIRONMENT" 'terminal colour environment refresh'
assert_contains_line TERM_PROGRAM "$UPDATE_ENVIRONMENT" 'terminal identity environment refresh'
assert_contains_line SSH_AUTH_SOCK "$UPDATE_ENVIRONMENT" 'authentication agent environment refresh'

# An arbitrary variable and terminal colour metadata from the invoking client
# must reach the new session; this is the path used on session entry/reattach.
PANE_ENVIRONMENT="$TMP_ROOT/pane-environment"
env TMUX_TEST_PRESERVED=client-value COLORTERM=truecolor TERM_PROGRAM=ghostty \
	"$WRAPPER" new-session -d -s environment -c "$PROJECT" \
	"printf '%s\\n' \"\$TMUX_TEST_PRESERVED\" \"\$COLORTERM\" \"\$TERM\" > '$PANE_ENVIRONMENT'; sleep 30"
assert_equal client-value "$(tmux_test show-environment -t '=environment' TMUX_TEST_PRESERVED | sed 's/^[^=]*=//')" \
	'arbitrary client environment'
assert_equal truecolor "$(tmux_test show-environment -t '=environment' COLORTERM | sed 's/^[^=]*=//')" \
	'terminal colour environment'
assert_equal ghostty "$(tmux_test show-environment -t '=environment' TERM_PROGRAM | sed 's/^[^=]*=//')" \
	'terminal identity environment'
for _ in {1..100}; do
	[[ -s $PANE_ENVIRONMENT ]] && break
	sleep 0.02
done
[[ -s $PANE_ENVIRONMENT ]] || fail 'pane environment capture timed out'
assert_equal client-value "$(sed -n '1p' "$PANE_ENVIRONMENT")" 'arbitrary pane environment'
assert_equal truecolor "$(sed -n '2p' "$PANE_ENVIRONMENT")" 'pane true-colour environment'
assert_equal tmux-256color "$(sed -n '3p' "$PANE_ENVIRONMENT")" 'pane terminal type'

if command -v tput >/dev/null 2>&1; then
	assert_equal 256 "$(tput -T tmux-256color colors)" 'tmux terminfo colour count'
	[[ -n $(tput -T tmux-256color smcup) ]] || fail 'tmux terminfo lacks alternate-screen entry'
	[[ -n $(tput -T tmux-256color rmcup) ]] || fail 'tmux terminfo lacks alternate-screen exit'
fi

# Exercise the actual pane parser: primary content must be hidden while the
# application is in the alternate buffer, then restored when the app exits.
ALTERNATE_PANE=$(tmux_test new-window -d -P -F '#{pane_id}' -t '=bootstrap:' -n alternate \
	"printf 'primary-screen-ok\\n'; printf '\\033[?2026h\\033[?1049halt-screen-ok\\n\\033[?2026l'; sleep 1; printf '\\033[?1049l'; sleep 30")
wait_for_format "$ALTERNATE_PANE" '#{alternate_on}' 1 'alternate-screen entry'
ALTERNATE_CONTENT=$(tmux_test capture-pane -p -t "$ALTERNATE_PANE")
[[ $ALTERNATE_CONTENT == *'alt-screen-ok'* ]] || fail 'alternate-screen content was not rendered'
[[ $ALTERNATE_CONTENT != *'primary-screen-ok'* ]] || fail 'primary content leaked into alternate screen'
wait_for_format "$ALTERNATE_PANE" '#{alternate_on}' 0 'alternate-screen exit'
PRIMARY_CONTENT=$(tmux_test capture-pane -p -t "$ALTERNATE_PANE")
[[ $PRIMARY_CONTENT == *'primary-screen-ok'* ]] || fail 'primary screen was not restored'
[[ $PRIMARY_CONTENT != *'alt-screen-ok'* ]] || fail 'alternate content leaked after exit'

"$HELPER" new --detached Demo "$PROJECT"
tmux_test has-session -t '=demo'
assert_equal "$PROJECT" "$(tmux_test show-options -qv -t 'demo:' @workspace_root)" 'standard root'
assert_equal standard "$(tmux_test show-options -qv -t 'demo:' @workspace_kind)" 'standard kind'
assert_equal main "$(tmux_test list-windows -t '=demo' -F '#{window_name}')" 'standard window'

"$HELPER" agent --detached Demo-Agents "$PROJECT" 3
tmux_test has-session -t '=demo-agents'
assert_equal agents "$(tmux_test show-options -qv -t 'demo-agents:' @workspace_kind)" 'agent kind'
assert_equal 3 "$(tmux_test show-options -qv -t 'demo-agents:' @workspace_agents)" 'agent count metadata'

WINDOWS=$(tmux_test list-windows -t '=demo-agents' -F '#{window_name}' | LC_ALL=C sort)
assert_equal $'agents\ncontrol' "$WINDOWS" 'agent workspace windows'
PANE_COUNT=$(tmux_test list-panes -t 'demo-agents:agents' -F '#{pane_id}' | wc -l | tr -d ' ')
assert_equal 3 "$PANE_COUNT" 'agent pane count'
PANE_TITLES=$(tmux_test list-panes -t 'demo-agents:agents' -F '#{pane_title}' | LC_ALL=C sort)
assert_equal $'agent-1\nagent-2\nagent-3' "$PANE_TITLES" 'agent pane titles'

# Exercise `tw grid` with a real pane context while retaining the isolated socket.
BOOTSTRAP_PANE=$(tmux_test list-panes -t '=bootstrap' -F '#{pane_id}' | head -n 1)
SOCKET_PATH=$(tmux_test display-message -p -t "$BOOTSTRAP_PANE" '#{socket_path}')
SERVER_PID=$(tmux_test display-message -p -t "$BOOTSTRAP_PANE" '#{pid}')
TMUX="$SOCKET_PATH,$SERVER_PID,0" TMUX_PANE="$BOOTSTRAP_PANE" \
	"$HELPER" grid 4 agents-test "$PROJECT"
GRID_COUNT=$(tmux_test list-panes -t 'bootstrap:agents-test' -F '#{pane_id}' | wc -l | tr -d ' ')
assert_equal 4 "$GRID_COUNT" 'grid pane count'

assert_hyper_letter h 'select-pane -L'
assert_hyper_letter s '.local/bin/tw'
assert_hyper_letter g 'grid 4'
assert_hyper_letter y 'synchronize-panes'
assert_hyper_letter e '.local/bin/tw'
assert_hyper_letter x 'kill-pane'
assert_exact_key 'C-M-S-/' '.local/bin/tw'
assert_exact_key 'C-M-S-,' 'previous-window'
assert_exact_key 'C-M-S--' 'split-window -v'
vertical_split=$(tmux_test list-keys -T root | awk '/split-window -h -c/')
[[ $vertical_split == *C-M-S-* ]] || {
	dump_keys root
	fail 'vertical Hyper split bind is missing'
}
assert_exact_key 'x' 'kill-pane' prefix
assert_exact_key '?' '.local/bin/tw' prefix

# Agent attention routing: bells flag windows, activity does not, dead panes stay.
assert_equal off "$(tmux_test show-window-options -gv monitor-activity)" 'activity monitoring off'
assert_equal on "$(tmux_test show-window-options -gv monitor-bell)" 'bell monitoring on'
assert_equal other "$(tmux_test show-options -gv bell-action)" 'bell action'
assert_equal failed "$(tmux_test show-window-options -gv remain-on-exit)" 'dead panes remain'
assert_hyper_letter f 'next-window -a'
assert_hyper_letter b 'break-pane'
assert_hyper_letter m 'select-pane -m'
assert_hyper_letter v 'join-pane'
assert_hyper_letter u 'extrakto'
assert_exact_key 'C-M-BTab' 'last-window'
assert_exact_key '"C-M-S-;"' 'last-pane'
assert_exact_key 'C-M-S-[' 'copy-mode'
assert_exact_key 'C-M-S-]' 'paste-buffer'
assert_exact_key 'R' 'respawn-pane' prefix
assert_exact_key 'P' 'pipe-pane' prefix

# The Claude Code hook publishes pane state and rings the bell on the pane tty.
STATE_HELPER="$REPO_ROOT/scripts/agent-tmux-state"
bash -n "$STATE_HELPER"
STATE_PANE=$(tmux_test new-window -d -P -F '#{pane_id}' -t '=bootstrap:' -n state 'sleep 30')
TMUX_PANE="$STATE_PANE" "$STATE_HELPER" input </dev/null
assert_equal '⏳ input' "$(tmux_test show-options -pqv -t "$STATE_PANE" @agent_state)" 'agent state set'
wait_for_format "$STATE_PANE" '#{window_bell_flag}' 1 'agent bell flag'
BORDER=$(tmux_test display-message -p -t "$STATE_PANE" '#{T:pane-border-format}')
[[ $BORDER == *'⏳ input'* ]] || fail 'pane border does not show agent state'
STATUS_RIGHT=$(tmux_test display-message -p -t "$STATE_PANE" '#{T:status-right}')
[[ $STATUS_RIGHT == *'!'* ]] || fail 'status bar does not count bell windows'
TMUX_PANE="$STATE_PANE" "$STATE_HELPER" clear </dev/null
assert_equal '' "$(tmux_test show-options -pqv -t "$STATE_PANE" @agent_state)" 'agent state cleared'
TMUX_PANE='' "$STATE_HELPER" input </dev/null || fail 'state helper must exit 0 outside tmux'
# Codex runs hooks in a sandbox that cannot open the pane tty; the helper must
# then ring the bell through the tmux server. macOS seatbelt reproduces this.
if command -v sandbox-exec >/dev/null 2>&1; then
	SANDBOX_PANE=$(tmux_test new-window -d -P -F '#{pane_id}' -t '=bootstrap:' -n sandboxed 'sleep 30')
	TMUX_PANE="$SANDBOX_PANE" sandbox-exec -p '(version 1)(allow default)(deny file-write* (regex #"^/dev/ttys"))' \
		"$STATE_HELPER" 'done' </dev/null
	assert_equal '✔ done' "$(tmux_test show-options -pqv -t "$SANDBOX_PANE" @agent_state)" 'sandboxed hook sets state'
	wait_for_format "$SANDBOX_PANE" '#{window_bell_flag}' 1 'sandboxed hook still rings the bell'
fi
# A bell while no client is attached must not leave a queued message behind:
# tmux shows queued errors in the active pane (view mode) on the next attach.
DETACHED_SOCKET="$SOCKET_NAME-detached"
"$REAL_TMUX" -L "$DETACHED_SOCKET" -f "$CONFIG" new-session -d -s main -x 100 -y 30 -c "$PROJECT" -n quiet 'sleep 30'
DETACHED_PANE=$("$REAL_TMUX" -L "$DETACHED_SOCKET" new-window -d -P -F '#{pane_id}' -t main -n agent 'sleep 30')
# Ring the bell on the pane tty directly: the state helper talks to $TMUX_BIN,
# which is the main test server, not this one.
printf '\a' >"$("$REAL_TMUX" -L "$DETACHED_SOCKET" display-message -p -t "$DETACHED_PANE" '#{pane_tty}')"
for _ in {1..100}; do
	[[ $("$REAL_TMUX" -L "$DETACHED_SOCKET" display-message -p -t "$DETACHED_PANE" '#{window_bell_flag}') == 1 ]] && break
	sleep 0.02
done
"$REAL_TMUX" -L "$DETACHED_SOCKET-host" -f /dev/null new-session -d -s host -x 100 -y 30 -c "$PROJECT" \
	"TERM=tmux-256color exec '$REAL_TMUX' -L '$DETACHED_SOCKET' attach -t main"
for _ in {1..100}; do
	[[ $("$REAL_TMUX" -L "$DETACHED_SOCKET" list-clients | grep -c .) == 1 ]] && break
	sleep 0.02
done
assert_equal 1 "$("$REAL_TMUX" -L "$DETACHED_SOCKET" list-clients | grep -c .)" 'client attached after a detached bell'
assert_equal 1 "$("$REAL_TMUX" -L "$DETACHED_SOCKET" display-message -p -t "$DETACHED_PANE" '#{window_bell_flag}')" \
	'bell flag survives a detached bell'
for _ in {1..25}; do
	[[ $("$REAL_TMUX" -L "$DETACHED_SOCKET" display-message -p -t 'main:quiet' '#{pane_in_mode}') == 0 ]] ||
		fail 'a bell while detached must not put the next attach into view mode'
	sleep 0.02
done
"$REAL_TMUX" -L "$DETACHED_SOCKET-host" kill-server >/dev/null 2>&1 || true
"$REAL_TMUX" -L "$DETACHED_SOCKET" kill-server >/dev/null 2>&1 || true

# Nested tmux: Hyper-Escape or F12 hands every key to an inner tmux and takes
# it back. Verified end to end with three stacked servers: HOST feeds keys to a
# client of the test server (outer, managed config), whose pane runs a client
# of INNER (managed config). Keys must land in the outer server while it is
# active and in the inner server while it is passive.
assert_exact_key 'C-M-S-Escape' 'key-table off'
assert_exact_key 'F12' 'key-table off'
assert_exact_key 'C-M-S-Escape' 'set-option -u key-table' off
assert_exact_key 'F12' 'set-option -u key-table' off

wait_for_option() {
	local target=$1
	local option=$2
	local expected=$3
	local label=$4
	local actual=''
	for _ in {1..100}; do
		actual=$(tmux_test show-options -qv -t "$target" "$option")
		[[ $actual == "$expected" ]] && return
		sleep 0.02
	done
	fail "$label: expected '$expected', got '$actual'"
}

window_count() {
	"$REAL_TMUX" -L "$1" list-windows -t "$2" 2>/dev/null | grep -c . || true
}

wait_for_windows() {
	local socket=$1
	local session=$2
	local expected=$3
	local label=$4
	local actual=''
	for _ in {1..100}; do
		actual=$(window_count "$socket" "$session")
		[[ $actual == "$expected" ]] && return
		sleep 0.02
	done
	fail "$label: expected $expected windows, got $actual"
}

INNER_SOCKET="$SOCKET_NAME-inner"
HOST_SOCKET="$SOCKET_NAME-host"
HOST_CONF="$TMP_ROOT/host.conf"
INNER_READY="$TMP_ROOT/inner-ready"
# The host has no real terminal, so it must encode modified keys for its pane
# unconditionally; a real terminal negotiates this with the outer client.
printf 'set-option -s extended-keys always\n' >"$HOST_CONF"
"$REAL_TMUX" -L "$INNER_SOCKET" -f "$CONFIG" new-session -d -s inner -x 100 -y 30 -c "$PROJECT" 'sleep 60'
# Mirror real use: attach to the outer tmux first, then start the inner client
# from a pane of the attached session.
tmux_test new-session -d -s nested -x 100 -y 30 -c "$PROJECT" \
	"while [ ! -e '$INNER_READY' ]; do sleep 0.05; done; TERM=tmux-256color exec '$REAL_TMUX' -L '$INNER_SOCKET' attach -t inner"
"$REAL_TMUX" -L "$HOST_SOCKET" -f "$HOST_CONF" new-session -d -s host -x 100 -y 30 -c "$PROJECT" \
	"TERM=tmux-256color exec '$REAL_TMUX' -L '$SOCKET_NAME' attach -t nested"
# The outer client asks the host pane for extended keys; wait until the host
# has switched the pane, or modified keys would still arrive in legacy form.
HOST_KEY_MODE=''
for _ in {1..100}; do
	HOST_KEY_MODE=$("$REAL_TMUX" -L "$HOST_SOCKET" display-message -p -t host '#{pane_key_mode}')
	[[ $HOST_KEY_MODE == Ext* ]] && break
	sleep 0.02
done
[[ $HOST_KEY_MODE == Ext* ]] || fail "host pane never entered extended-keys mode (got '$HOST_KEY_MODE')"
assert_equal 1 "$(tmux_test list-clients -t '=nested' | grep -c .)" 'outer tmux client attached'
touch "$INNER_READY"
OUTER_KEY_MODE=''
for _ in {1..100}; do
	OUTER_KEY_MODE=$(tmux_test display-message -p -t 'nested:1' '#{pane_key_mode}')
	[[ $OUTER_KEY_MODE == Ext* ]] && break
	sleep 0.02
done
[[ $OUTER_KEY_MODE == Ext* ]] || fail "outer pane never entered extended-keys mode (got '$OUTER_KEY_MODE')"
assert_equal 1 "$("$REAL_TMUX" -L "$INNER_SOCKET" list-clients | grep -c .)" 'inner tmux client attached'

host_keys() {
	"$REAL_TMUX" -L "$HOST_SOCKET" send-keys -t host "$@"
}

host_keys C-M-S-c
wait_for_windows "$SOCKET_NAME" nested 2 'Hyper-c reaches the active outer tmux'
assert_equal 1 "$(window_count "$INNER_SOCKET" inner)" 'active outer tmux keeps Hyper-c from the inner one'
# A passive outer tmux forwards keys to its active pane, so return to the
# window that holds the inner client before handing the keys over.
tmux_test select-window -t 'nested:1'

host_keys C-M-S-Escape
wait_for_option 'nested:' key-table off 'Hyper-Escape turns the outer tmux passive'
assert_equal None "$(tmux_test show-options -qv -t 'nested:' prefix)" 'passive outer tmux has no prefix'
OUTER_CLIENT=$(tmux_test list-clients -t '=nested' -F '#{client_tty}' | head -n 1)
NESTED_STATUS=$(tmux_test display-message -p -c "$OUTER_CLIENT" '#{T:status-left}')
[[ $NESTED_STATUS == *NESTED* ]] || fail 'status bar does not show NESTED while passive'
host_keys C-M-S-c
wait_for_windows "$INNER_SOCKET" inner 2 'Hyper-c reaches the inner tmux while the outer is passive'
host_keys C-a c
wait_for_windows "$INNER_SOCKET" inner 3 'Ctrl-a c reaches the inner tmux while the outer is passive'
assert_equal 2 "$(window_count "$SOCKET_NAME" nested)" 'passive outer tmux ignores its own keys'

host_keys F12
wait_for_option 'nested:' key-table '' 'F12 makes the outer tmux active again'
assert_equal C-a "$(tmux_test show-options -Aqv -t 'nested:' prefix)" 'active outer tmux regains the prefix'
ACTIVE_STATUS=$(tmux_test display-message -p -c "$OUTER_CLIENT" '#{T:status-left}')
[[ $ACTIVE_STATUS != *NESTED* ]] || fail 'status bar still shows NESTED after reactivation'
host_keys C-M-S-c
wait_for_windows "$SOCKET_NAME" nested 3 'Hyper-c reaches the reactivated outer tmux'
assert_equal 3 "$(window_count "$INNER_SOCKET" inner)" 'reactivated outer tmux keeps Hyper-c from the inner one'

# Send the real prefix binding through an attached tmux client in both cases.
host_keys C-a W
wait_for_windows "$SOCKET_NAME" nested 4 'Ctrl-a W opens a normal window outside Git'
assert_equal "$PROJECT" "$(tmux_test display-message -p -t nested '#{E:@tw_cwd}')" 'bound fallback preserves cwd'
tmux_test new-window -t '=nested:' -c "$GIT_PROJECT" 'sleep 60'
host_keys C-a W
wait_for_windows "$SOCKET_NAME" nested 6 'Ctrl-a W opens a Git worktree window'
BOUND_WORKTREE=$(tmux_test display-message -p -t nested '#{E:@tw_cwd}')
[[ $BOUND_WORKTREE == "$GIT_PROJECT"-worktree.* ]] || fail 'bound worktree window has the wrong directory'
assert_equal "$(git -C "$GIT_PROJECT" rev-parse HEAD)" "$(git -C "$BOUND_WORKTREE" rev-parse HEAD)" 'bound worktree HEAD'

host_keys C-M-S-Enter
wait_for_windows "$SOCKET_NAME" nested 7 'Hyper-Enter opens a Git worktree window'
HYPER_WORKTREE=$(tmux_test display-message -p -t nested '#{E:@tw_cwd}')
[[ $HYPER_WORKTREE != "$BOUND_WORKTREE" ]] || fail 'Hyper-Enter reused the source worktree'
assert_equal "$(git -C "$GIT_PROJECT" rev-parse HEAD)" "$(git -C "$HYPER_WORKTREE" rev-parse HEAD)" 'Hyper worktree HEAD'
tmux_test new-window -t '=nested:' -c "$PROJECT" 'sleep 60'
host_keys C-M-S-Enter
wait_for_windows "$SOCKET_NAME" nested 9 'Hyper-Enter opens a normal window outside Git'
assert_equal "$PROJECT" "$(tmux_test display-message -p -t nested '#{E:@tw_cwd}')" 'Hyper fallback preserves cwd'

# Verify cancellation and acceptance through the actual visible confirmation UI.
answer_confirmation() {
	local answer=$1 switch_to=${2:-} screen='' found=0
	for _ in {1..100}; do
		screen=$("$REAL_TMUX" -L "$HOST_SOCKET" capture-pane -p -t host)
		if [[ $screen == *'(y/n)'* ]]; then
			found=1
			break
		fi
		sleep 0.02
	done
	[[ $found == 1 ]] || fail 'worktree key did not show a confirmation prompt'
	if [[ -n $switch_to ]]; then
		tmux_test select-window -t "$switch_to"
	fi
	host_keys "$answer"
	for _ in {1..100}; do
		screen=$("$REAL_TMUX" -L "$HOST_SOCKET" capture-pane -p -t host)
		[[ $screen != *'(y/n)'* ]] && return
		sleep 0.02
	done
	fail 'worktree confirmation prompt did not close'
}

wait_for_parent_head() {
	local expected=$1 actual=''
	for _ in {1..100}; do
		actual=$(git -C "$MERGE_PROJECT" rev-parse HEAD)
		[[ $actual == "$expected" ]] && return
		sleep 0.02
	done
	fail "merge key did not advance parent to $expected (got $actual)"
}

KEY_PARENT_PANE=$(tmux_test new-window -P -F '#{pane_id}' -t '=nested:' -c "$MERGE_PROJECT" 'sleep 300')
"$HELPER" worktree "$KEY_PARENT_PANE"
KEY_CHILD_ROOT=$(tmux_test display-message -p -t nested '#{E:@tw_cwd}')
KEY_CHILD_PANE=$(tmux_test display-message -p -t nested '#{pane_id}')
printf 'key merge\n' >"$KEY_CHILD_ROOT/key-feature"
git -C "$KEY_CHILD_ROOT" add key-feature
git -C "$KEY_CHILD_ROOT" commit -qm key-feature
BEFORE_KEY_MERGE=$(git -C "$MERGE_PROJECT" rev-parse HEAD)
host_keys C-a F9
answer_confirmation n
assert_equal "$BEFORE_KEY_MERGE" "$(git -C "$MERGE_PROJECT" rev-parse HEAD)" 'cancelled prefix merge preserves parent'
host_keys C-a F9
answer_confirmation y "$KEY_PARENT_PANE"
wait_for_parent_head "$(git -C "$KEY_CHILD_ROOT" rev-parse HEAD)"
tmux_test select-window -t "$KEY_CHILD_PANE"
printf 'Hyper merge\n' >>"$KEY_CHILD_ROOT/key-feature"
git -C "$KEY_CHILD_ROOT" commit -qam hyper-feature
host_keys C-M-S-F9
answer_confirmation y
wait_for_parent_head "$(git -C "$KEY_CHILD_ROOT" rev-parse HEAD)"

host_keys C-a F10
answer_confirmation n
[[ -d $KEY_CHILD_ROOT ]] || fail 'cancelled prefix removal deleted worktree'
host_keys C-M-S-F10
answer_confirmation n
[[ -d $KEY_CHILD_ROOT ]] || fail 'cancelled Hyper removal deleted worktree'
host_keys C-a F10
answer_confirmation y "$KEY_PARENT_PANE"
wait_for_windows "$SOCKET_NAME" nested 10 'prefix removal closes its pane/window'
[[ ! -e $KEY_CHILD_ROOT ]] || fail 'prefix removal left worktree directory'
"$HELPER" worktree "$KEY_PARENT_PANE"
KEY_CHILD_ROOT=$(tmux_test display-message -p -t nested '#{E:@tw_cwd}')
host_keys C-M-S-F10
answer_confirmation y
wait_for_windows "$SOCKET_NAME" nested 10 'Hyper removal closes its pane/window'
[[ ! -e $KEY_CHILD_ROOT ]] || fail 'Hyper removal left worktree directory'

# Force the shell-report fallback even on macOS, then use real key events.
# This catches splits/windows incorrectly reusing the initial directory after cd.
CWD_DIR="$PROJECT/changed directory"
mkdir -p "$CWD_DIR"
CWD_PANE=$(tmux_test new-window -P -F '#{pane_id}' -t '=nested:' -c "$PROJECT")
tmux_test set-option -p -t "$CWD_PANE" @tw_cwd '#{?@shell_cwd,#{@shell_cwd},#{pane_start_path}}'
printf -v CWD_COMMAND 'cd -- %q' "$CWD_DIR"
tmux_test send-keys -t "$CWD_PANE" -l "$CWD_COMMAND"
tmux_test send-keys -t "$CWD_PANE" Enter
wait_for_format "$CWD_PANE" '#{@shell_cwd}' "$CWD_DIR" 'Bash reports cwd after cd'
host_keys C-a c
wait_for_windows "$SOCKET_NAME" nested 12 'prefix creates a window after cd'
wait_for_format nested '#{pane_start_path}' "$CWD_DIR" 'new window uses reported cwd'
tmux_test select-pane -t "$CWD_PANE"
host_keys C-a '%'
wait_for_format nested '#{pane_start_path}' "$CWD_DIR" 'split uses reported cwd'

"$REAL_TMUX" -L "$HOST_SOCKET" kill-server >/dev/null 2>&1 || true
"$REAL_TMUX" -L "$INNER_SOCKET" kill-server >/dev/null 2>&1 || true

# Plugin loading is optional: the configuration must source cleanly without tpm.
[[ -d "$TEST_HOME/.config/tmux/plugins" ]] && fail 'test home unexpectedly has tmux plugins'

"$HELPER" kill --force demo
"$HELPER" kill --force demo-agents
if tmux_test has-session -t '=demo' 2>/dev/null; then
	fail 'standard workspace survived forced removal'
fi
if tmux_test has-session -t '=demo-agents' 2>/dev/null; then
	fail 'agent workspace survived forced removal'
fi

printf '%s\n' 'tmux configuration and workspace helper integration checks passed.'
