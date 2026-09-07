#!/bin/sh

# Install missing tpm/plugins from the managed tmux configuration. Existing
# checkouts are updated only with --update. Runs from bootstrap; never starts a tmux
# server and never needs one. tpm loads the plugins when a server starts or the
# configuration is reloaded, and prefix+I / prefix+U still work interactively.

set -eu

PROGRAM=${0##*/}
UPDATE=false
case ${1:-} in
--update)
	UPDATE=true
	shift
	;;
esac
if [ "$#" -ne 0 ]; then
	printf 'Usage: %s [--update]\n' "$PROGRAM" >&2
	exit 2
fi
CONF=${TMUX_CONF:-${HOME:?}/.config/tmux/tmux.conf}
PLUGIN_DIR=${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.config/tmux/plugins}
PLUGIN_DIR=${PLUGIN_DIR%/}

if ! command -v git >/dev/null 2>&1; then
	printf '%s: git is required to install tmux plugins\n' "$PROGRAM" >&2
	exit 1
fi

if [ ! -r "$CONF" ]; then
	exit 0
fi

sync_repo() {
	name=$1
	url=$2
	target="$PLUGIN_DIR/$name"
	if [ -d "$target/.git" ]; then
		if [ "$UPDATE" = false ]; then
			return 0
		fi
		if git -C "$target" pull --ff-only --quiet >/dev/null 2>&1; then
			printf '%s: updated %s\n' "$PROGRAM" "$name"
		else
			printf '%s: could not update %s (offline?)\n' "$PROGRAM" "$name" >&2
			return 1
		fi
	else
		mkdir -p "$PLUGIN_DIR"
		if git clone --depth 1 --quiet "$url" "$target" >/dev/null 2>&1; then
			printf '%s: installed %s\n' "$PROGRAM" "$name"
		else
			printf '%s: could not clone %s\n' "$PROGRAM" "$url" >&2
			return 1
		fi
	fi
}

sync_repo tpm https://github.com/tmux-plugins/tpm.git

# Same parsing rule as tpm: `set -g @plugin 'owner/repo'` (quotes optional).
sed -n "s/^[[:space:]]*set\(-option\)\{0,1\}[[:space:]]\{1,\}-g[[:space:]]\{1,\}@plugin[[:space:]]\{1,\}['\"]\{0,1\}\([^'\"[:space:]]*\)['\"]\{0,1\}.*/\2/p" "$CONF" |
	while IFS= read -r plugin; do
		[ -n "$plugin" ] || continue
		case $plugin in
		tmux-plugins/tpm) continue ;; # TPM was bootstrapped above.
		*/*) sync_repo "${plugin##*/}" "https://github.com/$plugin.git" ;;
		esac
	done
