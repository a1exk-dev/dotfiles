#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

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

set -e
run_test test_interactive_bash_reloads_shortcuts_without_reloading_omarchy \
	'interactive Bash reloads shortcuts without reloading Omarchy'
run_test test_interactive_bash_uses_neovim_for_vi_and_keeps_omarchy_defaults \
	'interactive Bash uses Neovim for vi and keeps Omarchy defaults'
run_test test_interactive_bash_ll_delegates_to_omarchy_lsa \
	'interactive Bash ll delegates to Omarchy lsa'
run_test test_interactive_bash_bare_home_delegates_to_omarchy_zd \
	'interactive Bash bare home delegates to Omarchy zd'
finish_tests
