#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

bind_thefuck_fixture() {
	local executable=$1
	local fixture_usr_bin=$FIXTURE_ROOT/bwrap-usr-bin

	mkdir -p "$fixture_usr_bin"
	cp /usr/bin/bash /usr/bin/env "$fixture_usr_bin/"
	: >"$fixture_usr_bin/thefuck"
	BWRAP_EXTRA_ARGS=(
		--ro-bind "$fixture_usr_bin" /usr/bin
		--ro-bind "$executable" /usr/bin/thefuck
	)
}

bind_tmux_fixture() {
	local executable=$1

	BWRAP_EXTRA_ARGS+=(--ro-bind "$executable" /usr/bin/tmux)
}

make_private_tmux_starter() {
	local body=$1
	local target=$FIXTURE_HOME/.local/libexec/dotfiles/tmux-starter

	mkdir -p "${target%/*}"
	make_fake tmux-starter "$body"
	mv "$FIXTURE_BIN/tmux-starter" "$target"
}

test_interactive_bash_bare_tmux_uses_private_starter_and_command_bypasses_wrapper() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' ':' >"$FIXTURE_OMARCHY/default/bash/rc"
	make_private_tmux_starter '
printf "STARTER_ARG_COUNT<%s>\n" "$#" >>"$DOTFILES_TEST_CALL_LOG"
exit 37'
	make_fake tmux '
printf "OFFICIAL_ARG_COUNT<%s>\n" "$#" >>"$DOTFILES_TEST_CALL_LOG"
exit 41'
	mv "$FIXTURE_BIN/tmux" "$FIXTURE_ROOT/official-tmux"
	bind_tmux_fixture "$FIXTURE_ROOT/official-tmux"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			tmux
			printf "STARTER_STATUS<%s>\n" "$?"
			command tmux
			printf "BYPASS_STATUS<%s>\n" "$?"
		'

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq 0 "$COMMAND_STATUS" 'interactive tmux probe should complete' || return 1
	assert_contains "$COMMAND_OUTPUT" 'STARTER_STATUS<37>' \
		'a bare tmux call should return the private starter status' || return 1
	assert_contains "$COMMAND_OUTPUT" 'BYPASS_STATUS<41>' \
		'command tmux should bypass the wrapper and return the executable status' || return 1
	assert_eq $'STARTER_ARG_COUNT<0>\nOFFICIAL_ARG_COUNT<0>' "$calls" \
		'the wrapper and explicit bypass should invoke only their exact targets'
}

test_interactive_bash_bare_tmux_reports_unavailable_private_starter() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash" "$FIXTURE_HOME/.local/libexec/dotfiles"
	printf '%s\n' ':' >"$FIXTURE_OMARCHY/default/bash/rc"
	make_fake tmux 'printf "UNEXPECTED_OFFICIAL_CALL\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 91'
	mv "$FIXTURE_BIN/tmux" "$FIXTURE_ROOT/official-tmux"
	bind_tmux_fixture "$FIXTURE_ROOT/official-tmux"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			missing_output=$(tmux 2>&1)
			missing_status=$?
			: >"$HOME/.local/libexec/dotfiles/tmux-starter"
			non_executable_output=$(tmux 2>&1)
			non_executable_status=$?
			printf "MISSING_STATUS<%s>\n" "$missing_status"
			printf "MISSING_OUTPUT<%s>\n" "$missing_output"
			printf "NON_EXECUTABLE_STATUS<%s>\n" "$non_executable_status"
			printf "NON_EXECUTABLE_OUTPUT<%s>\n" "$non_executable_output"
		'

	local calls expected_error
	calls=$(<"$CALL_LOG")
	expected_error="tmux: private starter unavailable or not executable: $FIXTURE_HOME/.local/libexec/dotfiles/tmux-starter; recovery: reapply the tmux package"
	assert_eq 0 "$COMMAND_STATUS" 'unavailable private starter probe should complete' || return 1
	assert_contains "$COMMAND_OUTPUT" 'MISSING_STATUS<127>' \
		'a missing private starter should return 127' || return 1
	assert_contains "$COMMAND_OUTPUT" "MISSING_OUTPUT<$expected_error>" \
		'a missing private starter should name its path and package recovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'NON_EXECUTABLE_STATUS<127>' \
		'a non-executable private starter should return 127' || return 1
	assert_contains "$COMMAND_OUTPUT" "NON_EXECUTABLE_OUTPUT<$expected_error>" \
		'a non-executable private starter should name its path and package recovery' || return 1
	assert_eq '' "$calls" 'an unavailable private starter must not fall back to tmux'
}

test_interactive_bash_tmux_arguments_use_exact_executable() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' ':' >"$FIXTURE_OMARCHY/default/bash/rc"
	make_private_tmux_starter 'printf "UNEXPECTED_STARTER_CALL\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 92'
	make_fake tmux '
printf "OFFICIAL_ARG_COUNT<%s>\n" "$#" >>"$DOTFILES_TEST_CALL_LOG"
argument_index=0
for argument in "$@"; do
	argument_index=$((argument_index + 1))
	printf "OFFICIAL_ARG_%s<%s>\n" "$argument_index" "$argument" >>"$DOTFILES_TEST_CALL_LOG"
done
exit 23'
	mv "$FIXTURE_BIN/tmux" "$FIXTURE_ROOT/official-tmux"
	make_fake tmux 'printf "PATH_SHADOW_INVOKED\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 93'
	bind_tmux_fixture "$FIXTURE_ROOT/official-tmux"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			tmux list-sessions -F "session <#{session_name}>"
			printf "TMUX_STATUS<%s>\n" "$?"
		'

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq 0 "$COMMAND_STATUS" 'tmux argument forwarding probe should complete' || return 1
	assert_contains "$COMMAND_OUTPUT" 'TMUX_STATUS<23>' \
		'tmux arguments should return the exact executable status' || return 1
	assert_eq $'OFFICIAL_ARG_COUNT<3>\nOFFICIAL_ARG_1<list-sessions>\nOFFICIAL_ARG_2<-F>\nOFFICIAL_ARG_3<session <#{session_name}>>' "$calls" \
		'tmux arguments should preserve boundaries and reject the PATH shadow'
}

test_interactive_bash_retains_tmux_alias_and_stable_wrapper_on_reload() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' "alias t='tmux attach || tmux new -s Work'" >"$FIXTURE_OMARCHY/default/bash/rc"
	make_private_tmux_starter 'printf "UNEXPECTED_STARTER_CALL\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 92'
	make_fake tmux '
printf "OFFICIAL_ARG_COUNT<%s>\n" "$#" >>"$DOTFILES_TEST_CALL_LOG"
argument_index=0
for argument in "$@"; do
	argument_index=$((argument_index + 1))
	printf "OFFICIAL_ARG_%s<%s>\n" "$argument_index" "$argument" >>"$DOTFILES_TEST_CALL_LOG"
done
[[ ${1-} != attach ]]'
	mv "$FIXTURE_BIN/tmux" "$FIXTURE_ROOT/official-tmux"
	bind_tmux_fixture "$FIXTURE_ROOT/official-tmux"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			first_definition=$(declare -f tmux 2>/dev/null || true)
			source "$1"
			source "$1"
			second_definition=$(declare -f tmux 2>/dev/null || true)
			if [[ -n $first_definition && $first_definition == "$second_definition" ]]; then
				stable=yes
			else
				stable=no
			fi
			printf "TMUX_TYPE<%s>\n" "$(type -t tmux 2>/dev/null || true)"
			printf "TMUX_STABLE<%s>\n" "$stable"
			printf "T_ALIAS<%s>\n" "$(alias t 2>/dev/null || true)"
			t
			printf "T_STATUS<%s>\n" "$?"
		' bash "$FIXTURE_REPO/config/bash/.bashrc"

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq 0 "$COMMAND_STATUS" 'tmux alias reload probe should complete' || return 1
	assert_contains "$COMMAND_OUTPUT" 'TMUX_TYPE<function>' \
		'interactive Bash should expose tmux as a function' || return 1
	assert_contains "$COMMAND_OUTPUT" 'TMUX_STABLE<yes>' \
		'repeated sourcing should leave the same tmux function' || return 1
	assert_contains "$COMMAND_OUTPUT" "T_ALIAS<alias t='tmux attach || tmux new -s Work'>" \
		'the exact Omarchy t alias should remain unchanged' || return 1
	assert_contains "$COMMAND_OUTPUT" 'T_STATUS<0>' \
		'the Omarchy t alias should fall through from attach to new' || return 1
	assert_eq $'OFFICIAL_ARG_COUNT<1>\nOFFICIAL_ARG_1<attach>\nOFFICIAL_ARG_COUNT<3>\nOFFICIAL_ARG_1<new>\nOFFICIAL_ARG_2<-s>\nOFFICIAL_ARG_3<Work>' "$calls" \
		'the Omarchy t alias should use the wrapper argument path'
}

test_noninteractive_bash_does_not_define_tmux_wrapper() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' 'OMARCHY_RC_SOURCED=yes' >"$FIXTURE_OMARCHY/default/bash/rc"
	make_private_tmux_starter 'printf "UNEXPECTED_STARTER_CALL\n" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake tmux 'printf "UNEXPECTED_OFFICIAL_CALL\n" >>"$DOTFILES_TEST_CALL_LOG"'
	mv "$FIXTURE_BIN/tmux" "$FIXTURE_ROOT/official-tmux"
	bind_tmux_fixture "$FIXTURE_ROOT/official-tmux"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/bash --noprofile --norc -c '
			source "$1"
			if declare -F tmux >/dev/null; then tmux_function=present; else tmux_function=missing; fi
			printf "TMUX_FUNCTION<%s>\n" "$tmux_function"
			printf "OMARCHY_RC_SOURCED<%s>\n" "${OMARCHY_RC_SOURCED-no}"
		' bash "$FIXTURE_REPO/config/bash/.bashrc"

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq 0 "$COMMAND_STATUS" 'non-interactive tmux source should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'TMUX_FUNCTION<missing>' \
		'non-interactive Bash should not define the tmux wrapper' || return 1
	assert_contains "$COMMAND_OUTPUT" 'OMARCHY_RC_SOURCED<no>' \
		'non-interactive Bash should return before Omarchy defaults' || return 1
	assert_eq '' "$calls" 'non-interactive sourcing should not invoke tmux or its starter'
}

test_interactive_bash_reloads_shortcuts_without_reloading_omarchy() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' \
		'OMARCHY_LOAD_COUNT=$(( ${OMARCHY_LOAD_COUNT:-0} + 1 ))' \
		'starship_precmd() { :; }' \
		'__zoxide_hook() { :; }' \
		'PROMPT_COMMAND+=(starship_precmd __zoxide_hook)' \
		'n() { printf "fake Omarchy n\\n"; }' \
		>"$FIXTURE_OMARCHY/default/bash/rc"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			unalias vi ll "~"
			source "$1"
			source "$1"

			starship_hook_count=0
			zoxide_hook_count=0
			for hook in "${PROMPT_COMMAND[@]}"; do
				case $hook in
					starship_precmd) ((starship_hook_count += 1)) ;;
					__zoxide_hook) ((zoxide_hook_count += 1)) ;;
				esac
			done

			printf "OMARCHY_LOAD_COUNT<%s>\n" "$OMARCHY_LOAD_COUNT"
			printf "STARSHIP_HOOK_COUNT<%s>\n" "$starship_hook_count"
			printf "ZOXIDE_HOOK_COUNT<%s>\n" "$zoxide_hook_count"
			printf "VI_ALIAS<%s>\n" "$(alias vi 2>/dev/null || true)"
			printf "LL_ALIAS<%s>\n" "$(alias ll 2>/dev/null || true)"
			printf "TILDE_ALIAS<%s>\n" "$(alias "~" 2>/dev/null || true)"
			printf "N_TYPE<%s>\n" "$(type -t n 2>/dev/null || true)"
		' bash "$FIXTURE_REPO/config/bash/.bashrc"

	assert_eq 0 "$COMMAND_STATUS" 'interactive Bash reload should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'OMARCHY_LOAD_COUNT<1>' \
		'packaged Omarchy initialization should run exactly once' || return 1
	assert_contains "$COMMAND_OUTPUT" 'STARSHIP_HOOK_COUNT<1>' \
		'reloading should leave exactly one Starship prompt hook' || return 1
	assert_contains "$COMMAND_OUTPUT" 'ZOXIDE_HOOK_COUNT<1>' \
		'reloading should leave exactly one zoxide prompt hook' || return 1
	assert_contains "$COMMAND_OUTPUT" "VI_ALIAS<alias vi='nvim'>" \
		'reloading should reapply the exact vi alias' || return 1
	assert_contains "$COMMAND_OUTPUT" "LL_ALIAS<alias ll='lsa'>" \
		'reloading should reapply the exact ll alias' || return 1
	assert_contains "$COMMAND_OUTPUT" "TILDE_ALIAS<alias ~='cd ~'>" \
		'reloading should reapply the exact bare-home alias' || return 1
	assert_contains "$COMMAND_OUTPUT" 'N_TYPE<function>' \
		'the fake Omarchy n function should remain available'
}

test_interactive_bash_uses_neovim_for_vi_and_keeps_omarchy_defaults() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' 'n() { printf "fake Omarchy n\\n"; }' >"$FIXTURE_OMARCHY/default/bash/rc"
	make_fake nvim 'printf "fake nvim\\n"'

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			alias_before=$(alias vi 2>/dev/null || true)
			source "$1"
			alias_after=$(alias vi 2>/dev/null || true)
			printf "ALIAS_BEFORE<%s>\n" "$alias_before"
			printf "ALIAS_AFTER<%s>\n" "$alias_after"
			printf "NVIM<%s>\n" "$(command -v nvim)"
			printf "VI_TYPE<%s>\n" "$(type vi 2>/dev/null || true)"
			printf "N_TYPE<%s>\n" "$(type -t n 2>/dev/null || true)"
		' bash "$FIXTURE_REPO/config/bash/.bashrc"

	assert_eq 0 "$COMMAND_STATUS" 'interactive Bash startup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" "ALIAS_BEFORE<alias vi='nvim'>" \
		'startup should define the exact vi alias' || return 1
	assert_contains "$COMMAND_OUTPUT" "ALIAS_AFTER<alias vi='nvim'>" \
		'repeated sourcing should leave the same vi alias' || return 1
	assert_contains "$COMMAND_OUTPUT" "NVIM<$FIXTURE_BIN/nvim>" \
		'nvim should resolve from the isolated fixture' || return 1
	assert_contains "$COMMAND_OUTPUT" "VI_TYPE<vi is aliased to \`nvim'>" \
		'type should report vi as the approved alias' || return 1
	assert_contains "$COMMAND_OUTPUT" 'N_TYPE<function>' \
		'the fake Omarchy n function should remain available'
}

test_interactive_bash_ll_delegates_to_omarchy_lsa() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' \
		"alias ls='eza -lh --group-directories-first --icons=auto'" \
		"alias lsa='ls -a'" >"$FIXTURE_OMARCHY/default/bash/rc"
	make_fake eza 'printf "EZA_ARGS"; printf "<%s>" "$@"; printf "\n"'

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			alias_before=$(alias ll 2>/dev/null || true)
			source "$1"
			alias_after=$(alias ll 2>/dev/null || true)
			printf "ALIAS_BEFORE<%s>\n" "$alias_before"
			printf "ALIAS_AFTER<%s>\n" "$alias_after"
			printf "LL_TYPE<%s>\n" "$(type ll 2>/dev/null || true)"
			ll "quoted caller argument"
		' bash "$FIXTURE_REPO/config/bash/.bashrc"

	assert_eq 0 "$COMMAND_STATUS" 'interactive Bash ll startup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" "ALIAS_BEFORE<alias ll='lsa'>" \
		'startup should define the exact ll alias' || return 1
	assert_contains "$COMMAND_OUTPUT" "ALIAS_AFTER<alias ll='lsa'>" \
		'repeated sourcing should leave the same ll alias' || return 1
	assert_contains "$COMMAND_OUTPUT" "LL_TYPE<ll is aliased to \`lsa'>" \
		'type should report ll as the approved alias' || return 1
	assert_contains "$COMMAND_OUTPUT" \
		'EZA_ARGS<-lh><--group-directories-first><--icons=auto><-a><quoted caller argument>' \
		'll should preserve Omarchy listing flags and forward a quoted argument' || return 1

	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' \
		"alias ls='eza -lh --group-directories-first --icons=auto'" \
		>"$FIXTURE_OMARCHY/default/bash/rc"
	make_fake eza 'printf "unexpected eza fallback\n"'

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			ll missing-lsa-probe
			printf "LL_STATUS<%s>\n" "$?"
		'

	assert_eq 0 "$COMMAND_STATUS" 'missing-lsa probe should complete' || return 1
	assert_contains "$COMMAND_OUTPUT" 'bash: lsa: command not found' \
		'missing Omarchy lsa should fail visibly' || return 1
	assert_contains "$COMMAND_OUTPUT" 'LL_STATUS<127>' \
		'missing Omarchy lsa should return command-not-found status'
}

test_interactive_bash_bare_home_delegates_to_omarchy_zd() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash" "$FIXTURE_ROOT/away"
	printf '%s\n' \
		"alias cd='zd'" \
		'zd() { printf "ZD_ARG<%s>\n" "$1"; builtin cd -- "$1"; }' \
		>"$FIXTURE_OMARCHY/default/bash/rc"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			alias_before=$(alias "~" 2>/dev/null || true)
			source "$1"
			alias_after=$(alias "~" 2>/dev/null || true)
			printf "ALIAS_BEFORE<%s>\n" "$alias_before"
			printf "ALIAS_AFTER<%s>\n" "$alias_after"
			builtin cd -- "$2"
			printf "START_PWD<%s>\n" "$PWD"
			~
			printf "FINAL_PWD<%s>\n" "$PWD"
			printf "TILDE_PATH<%s>\n" ~/probe
		' bash "$FIXTURE_REPO/config/bash/.bashrc" "$FIXTURE_ROOT/away"

	assert_eq 0 "$COMMAND_STATUS" 'interactive Bash bare-home startup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" "ALIAS_BEFORE<alias ~='cd ~'>" \
		'startup should define the exact bare-home alias' || return 1
	assert_contains "$COMMAND_OUTPUT" "ALIAS_AFTER<alias ~='cd ~'>" \
		'repeated sourcing should leave the same bare-home alias' || return 1
	assert_contains "$COMMAND_OUTPUT" "START_PWD<$FIXTURE_ROOT/away>" \
		'the bare-home command should start outside HOME' || return 1
	assert_contains "$COMMAND_OUTPUT" "ZD_ARG<$FIXTURE_HOME>" \
		'the bare-home command should pass expanded HOME through Omarchy zd' || return 1
	assert_contains "$COMMAND_OUTPUT" "FINAL_PWD<$FIXTURE_HOME>" \
		'the bare-home command should change to HOME' || return 1
	assert_contains "$COMMAND_OUTPUT" "TILDE_PATH<$FIXTURE_HOME/probe>" \
		'ordinary tilde paths should retain normal expansion'
}

test_interactive_bash_runs_static_thefuck_correction_workflow() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' 'n() { printf "fake Omarchy n\\n"; }' >"$FIXTURE_OMARCHY/default/bash/rc"
	make_fake thefuck '
{
	printf "ARG_COUNT<%s>\n" "$#"
	argument_index=0
	for argument in "$@"; do
		argument_index=$((argument_index + 1))
		printf "ARG_%s<%s>\n" "$argument_index" "$argument"
	done
	printf "TF_SHELL<%s>\n" "${TF_SHELL-}"
	printf "TF_ALIAS<%s>\n" "${TF_ALIAS-}"
	printf "PYTHONIOENCODING<%s>\n" "${PYTHONIOENCODING-}"
	printf "TF_SHELL_ALIASES_BEGIN\n%s\nTF_SHELL_ALIASES_END\n" "${TF_SHELL_ALIASES-}"
	printf "TF_HISTORY_BEGIN\n%s\nTF_HISTORY_END\n" "${TF_HISTORY-}"
} >>"$DOTFILES_TEST_CALL_LOG"
printf "CORRECTED_VALUE=ran_in_current_shell\n"'
	mv "$FIXTURE_BIN/thefuck" "$FIXTURE_ROOT/official-thefuck"
	make_fake thefuck '
printf "PATH_SHADOW_INVOKED\n" >>"$DOTFILES_TEST_CALL_LOG"
printf "PATH_SHADOW_CORRECTION=ran\n"'
	bind_thefuck_fixture "$FIXTURE_ROOT/official-thefuck"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			if [[ -s $DOTFILES_TEST_CALL_LOG ]]; then startup_calls=invoked; else startup_calls=none; fi
			first_definition=$(declare -f fuck 2>/dev/null || true)
			printf "STARTUP_CALLS<%s>\n" "$startup_calls"
			printf "FUCK_TYPE<%s>\n" "$(type -t fuck 2>/dev/null || true)"

			source "$1"
			if [[ -s $DOTFILES_TEST_CALL_LOG ]]; then reload_calls=invoked; else reload_calls=none; fi
			second_definition=$(declare -f fuck 2>/dev/null || true)
			if [[ -n $first_definition && $first_definition == "$second_definition" ]]; then
				stable=yes
			else
				stable=no
			fi
			printf "RELOAD_CALLS<%s>\n" "$reload_calls"
			printf "FUCK_STABLE<%s>\n" "$stable"

			alias workflow_probe="printf probe"
			history -c
			history -s "git stats"
			PYTHONIOENCODING=latin-1
			fuck "first caller argument" "two words"
			printf "CORRECTED_VALUE<%s>\n" "${CORRECTED_VALUE-unset}"
			printf "TF_HISTORY_AFTER<%s>\n" "${TF_HISTORY-unset}"
			printf "PYTHONIOENCODING_AFTER<%s>\n" "$PYTHONIOENCODING"
			printf "LAST_HISTORY<%s>\n" "$(history 1)"
		' bash "$FIXTURE_REPO/config/bash/.bashrc"

	local calls path_shadow_calls
	calls=$(<"$CALL_LOG")
	if [[ $calls == *PATH_SHADOW_INVOKED* ]]; then path_shadow_calls=invoked; else path_shadow_calls=none; fi
	assert_eq 0 "$COMMAND_STATUS" 'interactive The Fuck workflow should complete' || return 1
	assert_contains "$COMMAND_OUTPUT" 'STARTUP_CALLS<none>' \
		'startup should not invoke the fake The Fuck executable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'FUCK_TYPE<function>' \
		'tool presence should define fuck as a function' || return 1
	assert_contains "$COMMAND_OUTPUT" 'RELOAD_CALLS<none>' \
		'repeated sourcing should not invoke the fake The Fuck executable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'FUCK_STABLE<yes>' \
		'repeated sourcing should leave the same static function' || return 1
	assert_contains "$COMMAND_OUTPUT" 'CORRECTED_VALUE<ran_in_current_shell>' \
		'a successful correction should execute in the current shell' || return 1
	assert_eq none "$path_shadow_calls" \
		'the correction workflow should not invoke a PATH-shadowing executable' || return 1
	assert_contains "$calls" 'ARG_COUNT<3>' \
		'the executable should receive the placeholder and both caller arguments' || return 1
	assert_contains "$calls" 'ARG_1<THEFUCK_ARGUMENT_PLACEHOLDER>' \
		'the placeholder should be the first executable argument' || return 1
	assert_contains "$calls" 'ARG_2<first caller argument>' \
		'the first caller argument should be forwarded unchanged' || return 1
	assert_contains "$calls" 'ARG_3<two words>' \
		'a quoted caller argument should be forwarded unchanged' || return 1
	assert_contains "$calls" 'TF_SHELL<bash>' \
		'the executable should receive the Bash shell identity' || return 1
	assert_contains "$calls" 'TF_ALIAS<fuck>' \
		'the executable should receive the function alias name' || return 1
	assert_contains "$calls" 'PYTHONIOENCODING<utf-8>' \
		'the executable should receive UTF-8 Python output encoding' || return 1
	assert_contains "$calls" "alias workflow_probe='printf probe'" \
		'the executable should receive current shell aliases' || return 1
	assert_contains "$calls" 'git stats' \
		'the executable should receive recent Bash history' || return 1
	assert_contains "$COMMAND_OUTPUT" 'TF_HISTORY_AFTER<unset>' \
		'TF_HISTORY should be cleaned after the correction' || return 1
	assert_contains "$COMMAND_OUTPUT" 'PYTHONIOENCODING_AFTER<latin-1>' \
		'PYTHONIOENCODING should be restored after the correction' || return 1
	assert_contains "$COMMAND_OUTPUT" 'CORRECTED_VALUE=ran_in_current_shell' \
		'the correction should be added to Bash history'
}

test_interactive_bash_does_not_evaluate_failed_thefuck_output() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' ':' >"$FIXTURE_OMARCHY/default/bash/rc"
	make_fake thefuck '
printf "FAILED_CALL" >>"$DOTFILES_TEST_CALL_LOG"
printf "<%s>" "$@" >>"$DOTFILES_TEST_CALL_LOG"
printf "\n" >>"$DOTFILES_TEST_CALL_LOG"
printf "FAILED_CORRECTION_WAS_EVALUATED=yes\n"
exit 23'
	mv "$FIXTURE_BIN/thefuck" "$FIXTURE_ROOT/official-thefuck"
	make_fake thefuck '
printf "PATH_SHADOW_INVOKED\n" >>"$DOTFILES_TEST_CALL_LOG"
printf "FAILED_CORRECTION_WAS_EVALUATED=path_shadow\n"'
	bind_thefuck_fixture "$FIXTURE_ROOT/official-thefuck"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			PYTHONIOENCODING=original-encoding
			history -c
			history -s "broken command"
			fuck --fail
			printf "FUCK_TYPE<%s>\n" "$(type -t fuck 2>/dev/null || true)"
			printf "FAILED_CORRECTION<%s>\n" "${FAILED_CORRECTION_WAS_EVALUATED-unset}"
			printf "TF_HISTORY_AFTER<%s>\n" "${TF_HISTORY-unset}"
			printf "PYTHONIOENCODING_AFTER<%s>\n" "$PYTHONIOENCODING"
		'

	local calls path_shadow_calls
	calls=$(<"$CALL_LOG")
	if [[ $calls == *PATH_SHADOW_INVOKED* ]]; then path_shadow_calls=invoked; else path_shadow_calls=none; fi
	assert_eq 0 "$COMMAND_STATUS" 'failed The Fuck workflow probe should complete' || return 1
	assert_contains "$COMMAND_OUTPUT" 'FUCK_TYPE<function>' \
		'tool presence should define the correction function' || return 1
	assert_eq none "$path_shadow_calls" \
		'the correction workflow should not invoke a PATH-shadowing executable' || return 1
	assert_contains "$calls" 'FAILED_CALL<THEFUCK_ARGUMENT_PLACEHOLDER><--fail>' \
		'the failed executable should still receive the placeholder and caller argument' || return 1
	assert_contains "$COMMAND_OUTPUT" 'FAILED_CORRECTION<unset>' \
		'nonzero executable output must not be evaluated' || return 1
	assert_contains "$COMMAND_OUTPUT" 'TF_HISTORY_AFTER<unset>' \
		'TF_HISTORY should be cleaned after executable failure' || return 1
	assert_contains "$COMMAND_OUTPUT" 'PYTHONIOENCODING_AFTER<original-encoding>' \
		'PYTHONIOENCODING should be restored after executable failure'
}

test_interactive_bash_clears_stale_fuck_function_when_thefuck_is_missing() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' ':' >"$FIXTURE_OMARCHY/default/bash/rc"
	printf '%s\n' 'not executable' >"$FIXTURE_ROOT/non-executable-thefuck"
	chmod 0644 "$FIXTURE_ROOT/non-executable-thefuck"
	make_fake thefuck '
printf "PATH_SHADOW_INVOKED<%s>\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
printf ":\n"'
	bind_thefuck_fixture "$FIXTURE_ROOT/non-executable-thefuck"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/bash --noprofile --rcfile "$FIXTURE_REPO/config/bash/.bashrc" -i -c '
			printf "STARTUP_FUCK_TYPE<%s>\n" "$(type -t fuck 2>/dev/null || printf missing)"
			thefuck --prime-cache >/dev/null
			hashed_path=$(hash -t thefuck 2>/dev/null || true)
			: >"$DOTFILES_TEST_CALL_LOG"
			fuck() { printf "stale function ran\n"; }
			source "$1" >"$2" 2>&1
			reload_status=$?
			fuck_type=$(type -t fuck 2>/dev/null || printf missing)
			if [[ $fuck_type == function ]]; then fuck after-removal >/dev/null; fi
			printf "HASHED_PATH<%s>\n" "$hashed_path"
			printf "RELOAD_STATUS<%s>\n" "$reload_status"
			printf "FUCK_TYPE<%s>\n" "$fuck_type"
		' bash "$FIXTURE_REPO/config/bash/.bashrc" "$FIXTURE_ROOT/reload-output"

	local calls reload_output
	calls=$(<"$CALL_LOG")
	reload_output=$(<"$FIXTURE_ROOT/reload-output")
	assert_eq 0 "$COMMAND_STATUS" 'missing-tool reload probe should complete' || return 1
	assert_contains "$COMMAND_OUTPUT" 'STARTUP_FUCK_TYPE<missing>' \
		'a PATH-shadowing executable alone should not define fuck' || return 1
	assert_contains "$COMMAND_OUTPUT" "HASHED_PATH<$FIXTURE_BIN/thefuck>" \
		'the reload probe should begin with a cached PATH-shadowing executable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'RELOAD_STATUS<0>' \
		'reloading without The Fuck should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'FUCK_TYPE<missing>' \
		'reloading without The Fuck should remove a stale fuck function' || return 1
	assert_eq '' "$calls" \
		'reloading without the official executable should not invoke the PATH shadow' || return 1
	assert_eq '' "$reload_output" \
		'reloading without The Fuck should be quiet'
}

test_noninteractive_bash_does_not_define_or_invoke_thefuck() {
	new_fixture
	mkdir -p "$FIXTURE_OMARCHY/default/bash"
	printf '%s\n' 'OMARCHY_RC_SOURCED=yes' >"$FIXTURE_OMARCHY/default/bash/rc"
	make_fake thefuck 'printf "unexpected invocation\n" >>"$DOTFILES_TEST_CALL_LOG"'
	bind_thefuck_fixture "$FIXTURE_BIN/thefuck"

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/bash --noprofile --norc -c '
			source "$1"
			printf "FUCK_TYPE<%s>\n" "$(type -t fuck 2>/dev/null || printf missing)"
			printf "OMARCHY_RC_SOURCED<%s>\n" "${OMARCHY_RC_SOURCED-no}"
		' bash "$FIXTURE_REPO/config/bash/.bashrc"

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq 0 "$COMMAND_STATUS" 'non-interactive Bash source should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'FUCK_TYPE<missing>' \
		'non-interactive Bash should not define the correction function' || return 1
	assert_contains "$COMMAND_OUTPUT" 'OMARCHY_RC_SOURCED<no>' \
		'non-interactive Bash should retain its early return before Omarchy defaults' || return 1
	assert_eq '' "$calls" \
		'non-interactive Bash should not invoke The Fuck'
}

set -e
run_test test_interactive_bash_bare_tmux_uses_private_starter_and_command_bypasses_wrapper \
	'interactive Bash sends bare tmux to its private starter and retains command bypass'
run_test test_interactive_bash_bare_tmux_reports_unavailable_private_starter \
	'interactive Bash reports an unavailable private tmux starter'
run_test test_interactive_bash_tmux_arguments_use_exact_executable \
	'interactive Bash sends tmux arguments to the exact executable'
run_test test_interactive_bash_retains_tmux_alias_and_stable_wrapper_on_reload \
	'interactive Bash retains the tmux alias and stable wrapper on reload'
run_test test_noninteractive_bash_does_not_define_tmux_wrapper \
	'non-interactive Bash does not define the tmux wrapper'
run_test test_interactive_bash_reloads_shortcuts_without_reloading_omarchy \
	'interactive Bash reloads shortcuts without reloading Omarchy'
run_test test_interactive_bash_uses_neovim_for_vi_and_keeps_omarchy_defaults \
	'interactive Bash uses Neovim for vi and keeps Omarchy defaults'
run_test test_interactive_bash_ll_delegates_to_omarchy_lsa \
	'interactive Bash ll delegates to Omarchy lsa'
run_test test_interactive_bash_bare_home_delegates_to_omarchy_zd \
	'interactive Bash bare home delegates to Omarchy zd'
run_test test_interactive_bash_runs_static_thefuck_correction_workflow \
	'interactive Bash runs the static The Fuck correction workflow'
run_test test_interactive_bash_does_not_evaluate_failed_thefuck_output \
	'interactive Bash does not evaluate failed The Fuck output'
run_test test_interactive_bash_clears_stale_fuck_function_when_thefuck_is_missing \
	'interactive Bash clears a stale fuck function when The Fuck is missing'
run_test test_noninteractive_bash_does_not_define_or_invoke_thefuck \
	'non-interactive Bash does not define or invoke The Fuck'
finish_tests
