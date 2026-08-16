#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

test_make_entry_point_delegates_to_engine() {
	new_fixture
	DOTFILES_TEST_INPUT='2\n' run_make "$FIXTURE_CACHE"

	assert_eq 0 "$COMMAND_STATUS" 'the default Make target should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'Make should expose engine output' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'Make should delegate version detection' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'Make should expose the engine empty state' || return 1

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq "version|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" "$calls" \
		'Make should delegate once to the same command engine'
}

test_fallback_wizard_has_no_default_mutation() {
	new_fixture
	add_package
	run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'an empty fallback choice should leave the wizard safely' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Dotfiles wizard' 'the no-argument command should launch the wizard' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No action selected.' 'the fallback should default to no action' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'opening and leaving the wizard should not inspect or mutate anything'
}

test_fallback_wizard_delegates_apply_to_engine() {
	new_fixture
	add_package
	make_applying_stow
	DOTFILES_TEST_INPUT='3\n2\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'fallback apply should complete through the engine' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: apply demo from config/demo' 'fallback apply should expose the engine plan before confirmation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Apply this complete plan? [y/N]' 'fallback apply should confirm after planning' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Applied and verified package: demo' 'fallback apply should expose the engine outcome' || return 1
	assert_eq 2 "$(awk '/^stow / { count++ } END { print count + 0 }' "$CALL_LOG")" 'fallback apply should delegate exactly one simulation and one mutation'
}

test_fallback_apply_conflict_stops_before_confirmation() {
	new_fixture
	add_package
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'keep me\n' >"$FIXTURE_HOME/.config/demo/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
printf "planned conflict\n" >&2
exit 1'
	DOTFILES_TEST_INPUT='3\n2\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'fallback apply conflict should fail planning' || return 1
	assert_contains "$COMMAND_OUTPUT" 'planned conflict' 'fallback should expose the simulation conflict' || return 1
	if [[ $COMMAND_OUTPUT == *'Apply this complete plan?'* ]]; then
		printf '  apply conflict must stop before the confirmation prompt\n' >&2
		return 1
	fi
	assert_eq 1 "$(awk '/^stow / { count++ } END { print count + 0 }' "$CALL_LOG")" 'apply conflict should run only the planning simulation' || return 1
	assert_eq 'keep me' "$(<"$FIXTURE_HOME/.config/demo/config")" 'apply conflict should preserve the existing target'
}

test_fallback_wizard_has_no_default_package() {
	new_fixture
	add_package
	DOTFILES_TEST_INPUT='3\n\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'an empty package choice should safely return from the wizard' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No package selected.' 'fallback package selection should default to no package' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'no package selection should invoke no engine operation or mutation command'
}

test_fallback_wizard_delegates_confirmed_stow_setup() {
	new_fixture
	mv "$FIXTURE_BIN/stow" "$FIXTURE_BIN/installed-stow"
	make_fake omarchy-pkg-add 'printf "omarchy-pkg-add %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
mv "$DOTFILES_TEST_FAKE_BIN/installed-stow" "$DOTFILES_TEST_FAKE_BIN/stow"'
	DOTFILES_TEST_INPUT='6\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'confirmed prerequisite setup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: install GNU Stow with omarchy-pkg-add stow' 'setup should display the complete delegated plan before confirmation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'GNU Stow installed and verified.' 'setup should verify the delegated result' || return 1
	assert_contains "$(<"$CALL_LOG")" 'omarchy-pkg-add stow' 'setup should delegate GNU Stow installation exactly to Omarchy' || return 1
	assert_eq 1 "$(awk '/^omarchy-pkg-add stow$/ { count++ } END { print count + 0 }' "$CALL_LOG")" 'setup should invoke the delegated installation once'
}

test_gum_wizard_delegates_apply_to_engine() {
	new_fixture
	add_package
	make_applying_stow
	local responses=$FIXTURE_ROOT/gum-responses
	printf 'Apply package\ndemo\n' >"$responses"
	make_gum_responder
	DOTFILES_UI=gum DOTFILES_TEST_GUM_RESPONSES=$responses run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'Gum apply should complete through the engine' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Applied and verified package: demo' 'Gum should expose the same engine outcome' || return 1
	assert_contains "$(<"$CALL_LOG")" 'gum confirm Apply this complete plan?' 'Gum should own only the confirmation UI' || return 1
	assert_eq 2 "$(awk '/^stow / { count++ } END { print count + 0 }' "$CALL_LOG")" 'Gum apply should delegate exactly one simulation and one mutation'
	local simulation_line confirmation_line
	simulation_line=$(awk '/^stow --simulate / { print NR; exit }' "$CALL_LOG")
	confirmation_line=$(awk '/^gum confirm Apply this complete plan[?]$/ { print NR; exit }' "$CALL_LOG")
	if [[ -z $simulation_line || -z $confirmation_line || $simulation_line -ge $confirmation_line ]]; then
		printf '  planning simulation must precede Gum confirmation\n' >&2
		return 1
	fi
}

test_gum_remove_conflict_stops_before_confirmation() {
	new_fixture
	add_package
	mkdir -p "$FIXTURE_HOME/.config"
	ln -s "$FIXTURE_REPO/config/demo/.config/demo" "$FIXTURE_HOME/.config/demo"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
printf "planned remove conflict\n" >&2
exit 1'
	local responses=$FIXTURE_ROOT/gum-responses
	printf 'Remove package\ndemo\n' >"$responses"
	make_gum_responder
	DOTFILES_UI=gum DOTFILES_TEST_GUM_RESPONSES=$responses run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'Gum remove conflict should fail planning' || return 1
	assert_contains "$COMMAND_OUTPUT" 'planned remove conflict' 'Gum should expose the remove simulation conflict' || return 1
	if [[ $(<"$CALL_LOG") == *'gum confirm '* ]]; then
		printf '  remove conflict must stop before Gum confirmation\n' >&2
		return 1
	fi
	assert_eq 1 "$(awk '/^stow / { count++ } END { print count + 0 }' "$CALL_LOG")" 'remove conflict should run only the planning simulation' || return 1
	assert_eq "$FIXTURE_REPO/config/demo/.config/demo/config" "$(readlink -f "$FIXTURE_HOME/.config/demo/config")" 'remove conflict should preserve linked package targets'
}

set -e
run_test test_make_entry_point_delegates_to_engine 'Make entry point delegates to the command engine'
run_test test_fallback_wizard_has_no_default_mutation 'fallback wizard has no default mutation'
run_test test_fallback_wizard_delegates_apply_to_engine 'fallback wizard delegates apply to the engine'
run_test test_fallback_apply_conflict_stops_before_confirmation 'fallback apply conflict stops before confirmation'
run_test test_fallback_wizard_has_no_default_package 'fallback wizard has no default package'
run_test test_fallback_wizard_delegates_confirmed_stow_setup 'fallback wizard delegates confirmed Stow setup'
run_test test_gum_wizard_delegates_apply_to_engine 'Gum wizard delegates apply to the engine'
run_test test_gum_remove_conflict_stops_before_confirmation 'Gum remove conflict stops before confirmation'
finish_tests
