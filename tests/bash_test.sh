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

set -e
run_test test_interactive_bash_uses_neovim_for_vi_and_keeps_omarchy_defaults \
	'interactive Bash uses Neovim for vi and keeps Omarchy defaults'
finish_tests
