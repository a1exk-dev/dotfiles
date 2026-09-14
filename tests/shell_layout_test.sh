#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

# Stands in for Omarchy's bar command: logs the call and, like the real shell,
# rewrites shell.json with the widget first in the right section.
fake_omarchy_bar_move() {
	make_fake omarchy '
printf "omarchy %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
[[ ${1-} == bar && ${2-} == move ]] || exit 0
mkdir -p "$HOME/.config/omarchy"
printf "%s\n" "{\"bar\":{\"layout\":{\"right\":[{\"id\":\"omarchy.keyboard-layout\"},{\"id\":\"omarchy.tray\"}]}}}" >"$HOME/.config/omarchy/shell.json"
echo "Moved omarchy.keyboard-layout"'
}

test_shell_layout_moves_indicator_before_tray() {
	new_fixture
	fake_omarchy_bar_move
	DOTFILES_TEST_INPUT='y\n' run_dotfiles "$FIXTURE_ROOT" --action shell-layout

	assert_eq 0 "$COMMAND_STATUS" 'an approved Shell layout should apply' || return 1
	assert_contains "$(<"$CALL_LOG")" 'omarchy bar move omarchy.keyboard-layout --section right --index 0' \
		'the layout should go through Omarchy'"'"'s bar command' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Shell layout applied and verified.' 'the result should be verified from shell.json'
}

test_shell_layout_decline_makes_no_changes() {
	new_fixture
	fake_omarchy_bar_move
	DOTFILES_TEST_INPUT='\n' run_dotfiles "$FIXTURE_ROOT" --action shell-layout

	assert_eq 0 "$COMMAND_STATUS" 'a declined Shell layout should succeed without changes' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No changes made.' 'declining should say nothing changed' || return 1
	if [[ $(<"$CALL_LOG") == *'bar move'* ]]; then
		printf '  a declined plan must not call Omarchy\n' >&2
		return 1
	fi
}

test_shell_layout_reports_omarchy_failure() {
	new_fixture
	make_fake omarchy 'printf "omarchy %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"; [[ ${1-} == bar ]] && exit 1; exit 0'
	DOTFILES_TEST_INPUT='y\n' run_dotfiles "$FIXTURE_ROOT" --action shell-layout

	assert_eq 1 "$COMMAND_STATUS" 'a failed Omarchy move should fail the action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: make sure omarchy-shell is running' 'the failure should name a recovery'
}

run_test test_shell_layout_moves_indicator_before_tray 'Shell layout moves the language indicator before the tray'
run_test test_shell_layout_decline_makes_no_changes 'Shell layout decline makes no changes'
run_test test_shell_layout_reports_omarchy_failure 'Shell layout reports an Omarchy failure with recovery'
finish_tests
