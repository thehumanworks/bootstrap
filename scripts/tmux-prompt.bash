# shellcheck shell=bash
# Sourced by interactive Bash. Modal's PTY implementation may leave tmux's
# pane_current_path empty; report the shell directory without changing the keys.
if [[ $- == *i* && -n ${TMUX_PANE:-} ]]; then
	_bootstrap_tmux_cwd() {
		local previous_status=$?
		"${TMUX_BIN:-tmux}" set-option -p -t "$TMUX_PANE" @shell_cwd "$PWD" 2>/dev/null || true
		return "$previous_status"
	}
	# Preserve scalar and array PROMPT_COMMAND values and avoid duplicate hooks
	# when a login shell sources both .bash_profile and .bashrc.
	if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a '* ]]; then
		if [[ " ${PROMPT_COMMAND[*]} " != *' _bootstrap_tmux_cwd '* ]]; then
			PROMPT_COMMAND=(_bootstrap_tmux_cwd "${PROMPT_COMMAND[@]}")
		fi
	elif [[ ${PROMPT_COMMAND:-} != *'_bootstrap_tmux_cwd'* ]]; then
		# This branch is scalar; the array branch above preserves array entries.
		# shellcheck disable=SC2178,SC2128
		PROMPT_COMMAND="_bootstrap_tmux_cwd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
	fi
fi
