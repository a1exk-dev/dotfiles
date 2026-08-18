#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

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

set -e
run_test test_interactive_bash_uses_neovim_for_vi_and_keeps_omarchy_defaults \
	'interactive Bash uses Neovim for vi and keeps Omarchy defaults'
run_test test_interactive_bash_ll_delegates_to_omarchy_lsa \
	'interactive Bash ll delegates to Omarchy lsa'
finish_tests
