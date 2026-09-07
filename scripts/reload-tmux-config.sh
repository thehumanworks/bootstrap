#!/bin/sh

set -eu

# Reload the managed tmux configuration into an already-running server.
# Safe for mise bootstrap: no-ops when tmux, the config, or a live server is
# missing. Never starts a server and never kills sessions.

PROGRAM=${0##*/}
CONF=${TMUX_CONF:-${HOME:?}/.config/tmux/tmux.conf}

resolve_tmux() {
	if [ -n "${TMUX_BIN:-}" ]; then
		printf '%s\n' "$TMUX_BIN"
		return 0
	fi

	resolved=$(command -v tmux 2>/dev/null || true)
	if [ -n "$resolved" ]; then
		printf '%s\n' "$resolved"
		return 0
	fi

	if command -v mise >/dev/null 2>&1; then
		resolved=$(mise which tmux 2>/dev/null || true)
		if [ -n "$resolved" ] && [ -x "$resolved" ]; then
			printf '%s\n' "$resolved"
			return 0
		fi
	fi

	for candidate in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
		if [ -x "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

tmux_bin=$(resolve_tmux || true)
if [ -z "$tmux_bin" ]; then
	exit 0
fi

if [ ! -r "$CONF" ]; then
	exit 0
fi

# `tmux source-file` starts a server when none exists. Probe first.
if ! "$tmux_bin" list-sessions >/dev/null 2>&1; then
	exit 0
fi

"$tmux_bin" source-file "$CONF"
printf '%s: sourced %s\n' "$PROGRAM" "$CONF"
