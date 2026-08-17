#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

test_top_level_menu_starts_with_guided_setup() {
	new_fixture
	run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'an empty menu choice should safely exit' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  1. Guided setup\n  2. Package status' 'guided setup should be the first top-level action' || return 1
	assert_contains "$COMMAND_OUTPUT" '  10. Update pinned global skills' 'every retained standalone action should be listed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No action selected.' 'no action should be selected by default'
}

test_legacy_and_invalid_entry_forms_are_rejected() {
	new_fixture
	run_dotfiles "$FIXTURE_ROOT" status
	assert_eq 2 "$COMMAND_STATUS" 'a removed public route should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Usage: bin/dotfiles [--action' 'invalid entry use should explain the supported interface' || return 1
	run_dotfiles "$FIXTURE_ROOT" --arbitrary
	assert_eq 2 "$COMMAND_STATUS" 'arbitrary flags should be rejected' || return 1
	run_dotfiles "$FIXTURE_ROOT" --action unknown
	assert_eq 2 "$COMMAND_STATUS" 'an unknown preselected action should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unknown wizard action: unknown' 'unknown action output should name the invalid value'
}

test_public_action_preselection_dispatches() {
	new_fixture
	run_dotfiles "$FIXTURE_ROOT" --action status
	assert_eq 0 "$COMMAND_STATUS" 'a valid public preselection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'public preselection should dispatch to the selected operation'
}

test_status_and_check_standalone_actions() {
	new_fixture
	DOTFILES_TEST_INPUT='2\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone status should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'standalone status should reach the package engine' || return 1
	DOTFILES_TEST_INPUT='3\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone checks should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid' 'standalone checks should reach the structural engine'
}

test_bash_apply_standalone_uses_one_multiselect_and_dependency_order() {
	new_fixture
	add_package base
	add_dependent_package app base
	make_applying_stow
	DOTFILES_TEST_INPUT='4\n2\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'standalone Bash apply should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" $'Plan: apply packages in dependency order:\n  1. base (required by selection)\n  2. app (selected)' 'apply should resolve and show the complete dependency plan' || return 1
	assert_eq 1 "$(awk '/Apply this complete Stow plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" 'apply should confirm the complete plan once' || return 1
	local base_apply app_apply
	base_apply=$(awk '/^stow --verbose=2 .* base$/ { print NR; exit }' "$CALL_LOG")
	app_apply=$(awk '/^stow --verbose=2 .* app$/ { print NR; exit }' "$CALL_LOG")
	[[ -n $base_apply && -n $app_apply && $base_apply -lt $app_apply ]]
}

test_gum_apply_has_no_default_selection() {
	new_fixture
	add_package
	make_applying_stow
	local responses=$FIXTURE_ROOT/gum-responses
	printf 'Apply Stow packages\n\n' >"$responses"
	make_gum_responder
	DOTFILES_UI=gum DOTFILES_TEST_GUM_RESPONSES=$responses run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'an empty Gum package selection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No Stow packages selected; no changes made.' 'Gum should default to no Stow packages' || return 1
	assert_contains "$(<"$CALL_LOG")" 'gum choose --no-limit --header Choose Stow packages (none selected by default)' 'Gum should provide the multi-select screen'
}

test_migrate_and_remove_standalone_actions() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved\n' >"$FIXTURE_HOME/.config/demo/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " != *" --simulate "* ]]; then
	mkdir -p "$HOME/.config/demo"
	ln -s "$DOTFILES_TEST_REPO/config/demo/.config/demo/config" "$HOME/.config/demo/config"
fi'
	DOTFILES_TEST_INPUT='5\n2\n.config/demo/config\ny\ny\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone migration should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migrated and verified package: demo' 'migration should reach its internal engine' || return 1

	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " == *" --delete "* && " $* " != *" --simulate "* ]]; then rm -rf "$HOME/.config/demo"; fi'
	DOTFILES_TEST_INPUT='6\n2\ny\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone removal should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified package: demo' 'removal should reach its internal engine'
}

test_prerequisite_standalone_installs_stow_and_node_with_supported_flows() {
	new_fixture
	mv "$FIXTURE_BIN/stow" "$FIXTURE_BIN/installed-stow"
	mv "$FIXTURE_BIN/node" "$FIXTURE_BIN/installed-node"
	mv "$FIXTURE_BIN/npm" "$FIXTURE_BIN/installed-npm"
	mv "$FIXTURE_BIN/npx" "$FIXTURE_BIN/installed-npx"
	make_fake omarchy 'printf "%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "4.0.0-1\n"; exit 0; fi
if [[ $* == "pkg add stow" ]]; then mv "$DOTFILES_TEST_FAKE_BIN/installed-stow" "$DOTFILES_TEST_FAKE_BIN/stow"; exit 0; fi
if [[ $* == "install dev-env node" ]]; then
	mv "$DOTFILES_TEST_FAKE_BIN/installed-node" "$DOTFILES_TEST_FAKE_BIN/node"
	mv "$DOTFILES_TEST_FAKE_BIN/installed-npm" "$DOTFILES_TEST_FAKE_BIN/npm"
	mv "$DOTFILES_TEST_FAKE_BIN/installed-npx" "$DOTFILES_TEST_FAKE_BIN/npx"
	exit 0
fi
exit 64'
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='7\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'confirmed prerequisite preparation should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy pkg add stow' 'the Stow plan should name the supported Omarchy flow' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy install dev-env node' 'the Node plan should name the supported Omarchy flow' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Node.js 22.20.0' 'the existing documented Node threshold should be enforced' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Prerequisites installed and verified' 'all installed tools should be verified'
}

test_prerequisites_upgrade_old_node() {
	new_fixture
	make_fake node 'printf "v20.0.0\n"'
	make_fake updated-node 'printf "v22.20.0\n"'
	make_fake omarchy 'printf "%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "4.0.0-1\n"; exit 0; fi
if [[ $* == "install dev-env node" ]]; then mv "$DOTFILES_TEST_FAKE_BIN/updated-node" "$DOTFILES_TEST_FAKE_BIN/node"; exit 0; fi
exit 64'
	DOTFILES_TEST_INPUT='7\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'old Node.js should be upgraded and verified' || return 1
	assert_contains "$(<"$CALL_LOG")" 'install dev-env node' 'old Node.js should use the supported Omarchy installer' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Prerequisites installed and verified: GNU Stow, Node.js 22.20.0' 'the upgraded Node.js version should be verified'
}

test_prerequisites_reject_missing_core_tool() {
	new_fixture
	local restricted_bin=$FIXTURE_ROOT/restricted-bin command
	mkdir -p "$restricted_bin"
	for command in bash dirname env jq find readlink git sort head node npm npx stow omarchy; do
		if [[ -x $FIXTURE_BIN/$command ]]; then
			ln -s "$FIXTURE_BIN/$command" "$restricted_bin/$command"
		elif command -v "$command" >/dev/null 2>&1; then
			ln -s "$(command -v "$command")" "$restricted_bin/$command"
		fi
	done
	DOTFILES_TEST_PATH=$restricted_bin DOTFILES_TEST_INPUT='7\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'a missing core tool should stop prerequisite preparation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: missing core prerequisite command: diff' 'the unavailable core tool should be named' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Prepare prerequisites in the Dotfiles wizard' 'core-tool recovery should name the wizard action'
}

test_cleanup_skills_and_update_standalone_actions() {
	new_fixture
	configure_cleanup_fakes
	DOTFILES_TEST_INPUT='8\n0\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone cleanup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No cleanup items selected' 'cleanup should remain independently reachable' || return 1

	new_fixture
	configure_skill_fakes
	seed_current_global_skills
	DOTFILES_TEST_INPUT='9\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone pinned skill installation should succeed when current' || return 1
	assert_contains "$COMMAND_OUTPUT" 'All manifest-owned skills already match' 'skill installation should remain independently reachable' || return 1

	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE=true DOTFILES_TEST_INPUT='10\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone skill update should succeed when current' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No upstream skill updates are available.' 'skill update should remain independently reachable'
}

test_guided_setup_orders_and_skips_nonessential_phases() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	DOTFILES_TEST_INPUT='1\n0\n\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'guided setup should continue across empty nonessential selections' || return 1
	local prerequisites skills cleanup stow
	prerequisites=$(awk '/Guided phase 1:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	skills=$(awk '/Guided phase 2:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	cleanup=$(awk '/Guided phase 3:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	stow=$(awk '/Guided phase 4:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	if [[ -z $prerequisites || -z $skills || -z $cleanup || -z $stow || $prerequisites -ge $skills || $skills -ge $cleanup || $cleanup -ge $stow ]]; then
		printf '  guided phases did not run in the required order\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'No cleanup items selected' 'empty cleanup should continue' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No Stow packages selected' 'empty Stow selection should continue' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' 'all skipped nonessential phases should complete the guide'
}

test_guided_setup_stops_on_operational_failure_with_action_recovery() {
	new_fixture
	rm "$FIXTURE_BIN/stow"
	make_fake omarchy 'if [[ ${1-} == version ]]; then printf "4.0.0-1\n"; exit 0; fi
if [[ $* == "pkg add stow" ]]; then exit 73; fi
exit 64'
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='1\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'a prerequisite operation failure should stop guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'GNU Stow installation failed.' 'the operational failure should be visible' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Prepare prerequisites in the Dotfiles wizard.' 'recovery should name a wizard action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 2:'* ]]; then
		printf '  guided setup continued after an operational failure\n' >&2
		return 1
	fi
}

test_guided_setup_stops_when_prerequisites_are_declined() {
	new_fixture
	rm "$FIXTURE_BIN/stow"
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='1\nn\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'declining required prerequisites should stop guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'required prerequisites remain unsatisfied' 'guided setup should distinguish decline from success' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Prepare prerequisites in the Dotfiles wizard.' 'decline recovery should name the prerequisite action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 2:'* ]]; then
		printf '  guided setup continued to skills after prerequisite decline\n' >&2
		return 1
	fi
}

test_guided_bash_stow_selection_failure_reports_recovery() {
	new_fixture
	add_package
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	DOTFILES_TEST_INPUT='1\n0\n99\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'an invalid Bash Stow selection should stop guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: invalid Stow package selection: 99' 'the invalid Bash selection should be identified' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply Stow packages in the Dotfiles wizard.' 'Bash selection recovery should name the standalone action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  guided setup completed after an invalid Stow selection\n' >&2
		return 1
	fi
}

test_guided_gum_stow_cancel_reports_recovery() {
	new_fixture
	add_package
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == choose && $* == *"Choose an action"* ]]; then printf "Guided setup\n"; exit 0; fi
if [[ ${1-} == choose && $* == *"Choose Stow packages"* ]]; then exit 75; fi
if [[ ${1-} == choose ]]; then exit 0; fi
if [[ ${1-} == confirm ]]; then exit 0; fi
exit 64'
	DOTFILES_UI=gum run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'a Gum Stow cancellation should stop guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply Stow packages in the Dotfiles wizard.' 'Gum cancellation recovery should name the standalone action'
}

test_make_targets_launch_expected_wizard_actions() {
	new_fixture
	DOTFILES_TEST_INPUT='2\n' run_make "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'default Make target should open the menu' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'default Make should delegate to the selected menu action' || return 1

	configure_skill_fakes
	seed_current_global_skills
	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" make --no-print-directory -C "$FIXTURE_REPO" skills
	assert_eq 0 "$COMMAND_STATUS" 'make skills should launch its preselected action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'All manifest-owned skills already match' 'make skills should not require top-level menu selection' || return 1

	configure_skill_update_fakes
	DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE=true run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" make --no-print-directory -C "$FIXTURE_REPO" skills-update
	assert_eq 0 "$COMMAND_STATUS" 'make skills-update should launch its preselected action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No upstream skill updates are available.' 'make skills-update should not require top-level menu selection'
}

set -e
run_test test_top_level_menu_starts_with_guided_setup 'top-level menu starts with guided setup'
run_test test_legacy_and_invalid_entry_forms_are_rejected 'legacy and invalid entry forms are rejected'
run_test test_public_action_preselection_dispatches 'public action preselection dispatches'
run_test test_status_and_check_standalone_actions 'status and checks remain standalone actions'
run_test test_bash_apply_standalone_uses_one_multiselect_and_dependency_order 'Bash apply resolves a multi-selection in dependency order'
run_test test_gum_apply_has_no_default_selection 'Gum apply has no default selection'
run_test test_migrate_and_remove_standalone_actions 'migration and removal remain standalone actions'
run_test test_prerequisite_standalone_installs_stow_and_node_with_supported_flows 'prerequisites install and verify Stow and Node through Omarchy'
run_test test_prerequisites_upgrade_old_node 'prerequisites upgrade an old Node.js through Omarchy'
run_test test_prerequisites_reject_missing_core_tool 'prerequisites reject a missing core tool with wizard recovery'
run_test test_cleanup_skills_and_update_standalone_actions 'cleanup and skill operations remain standalone actions'
run_test test_guided_setup_orders_and_skips_nonessential_phases 'guided setup orders and skips nonessential phases'
run_test test_guided_setup_stops_on_operational_failure_with_action_recovery 'guided setup stops on failure with wizard recovery'
run_test test_guided_setup_stops_when_prerequisites_are_declined 'guided setup stops when required prerequisites are declined'
run_test test_guided_bash_stow_selection_failure_reports_recovery 'guided Bash Stow selection failure reports recovery'
run_test test_guided_gum_stow_cancel_reports_recovery 'guided Gum Stow cancellation reports recovery'
run_test test_make_targets_launch_expected_wizard_actions 'Make targets launch expected wizard actions'
finish_tests
