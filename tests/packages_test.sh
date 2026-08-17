#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

test_apply_requires_explicit_package_and_approval() {
	new_fixture
	add_package
	run_dotfiles "$FIXTURE_ROOT" apply
	assert_eq 2 "$COMMAND_STATUS" 'the removed apply route should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Usage: bin/dotfiles [--action' 'removed legacy apply route should point to the supported interface' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'invalid entry use should run no external commands'
}

test_apply_plans_simulates_links_and_validates_package() {
	new_fixture
	add_package
	make_applying_stow
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	assert_eq 0 "$COMMAND_STATUS" 'safe package apply should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: apply demo from config/demo to' 'plan should identify source and target' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Phase: verify' 'output should expose the final phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Applied and verified package: demo' 'success should mean links and validators passed' || return 1
	assert_eq "$FIXTURE_REPO/config/demo/.config/demo/config" "$(readlink -f "$FIXTURE_HOME/.config/demo/config")" \
		'apply should create the expected repository-owned link' || return 1
	local calls expected_calls
	calls=$(<"$CALL_LOG")
	expected_calls=$(printf '%s\n' \
		"version|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" \
		"stow --simulate --verbose=2 --dir $FIXTURE_REPO/config --target $FIXTURE_HOME demo" \
		"stow --verbose=2 --dir $FIXTURE_REPO/config --target $FIXTURE_HOME demo" \
		'validator --check' \
		"validator-two --check|PWD=$FIXTURE_REPO")
	assert_eq "$expected_calls" "$calls" 'simulation, mutation, audit, and every validator should run in order'
}

test_apply_requires_separate_omarchy_mismatch_confirmation() {
	new_fixture
	add_package
	make_applying_stow
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\nn\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  mismatched Omarchy should require separate confirmation\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Phase: confirm' 'mismatch rejection should identify the confirmation phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Apply Stow packages in the Dotfiles wizard' \
		'recovery should name the compatibility action' || return 1
	if [[ -e $FIXTURE_HOME/.config/demo/config ]]; then
		printf '  mismatch rejection must happen before filesystem mutation\n' >&2
		return 1
	fi

	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\ny\n' run_operation "$FIXTURE_ROOT" apply_packages demo
	assert_eq 0 "$COMMAND_STATUS" 'explicit mismatch confirmation should permit the planned apply' || return 1
}

test_apply_reports_missing_package_prerequisite_before_stow() {
	new_fixture
	add_package
	rm "$FIXTURE_BIN/test-validator"
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  missing package prerequisite should fail apply\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Missing package prerequisite for demo: test-validator' \
		'missing declared command should be named' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: plan phase failed for package demo.' \
		'prerequisites should fail in planning' || return 1
	if [[ $(<"$CALL_LOG") == *'stow '* ]]; then
		printf '  Stow must not run when a package prerequisite is missing\n' >&2
		return 1
	fi
}

test_apply_rejects_missing_validator_executable_before_simulation() {
	new_fixture
	add_package
	jq '.packages[0].validators = ["missing-validator --check"]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	assert_eq 1 "$COMMAND_STATUS" 'apply should fail planning when a validator executable is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing validator executable for demo: missing-validator --check' \
		'apply should identify the unavailable validator' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: plan phase failed for package demo.' \
		'apply should reject the validator during planning' || return 1
	if [[ $(<"$CALL_LOG") == *'stow '* || -e $FIXTURE_HOME/.config/demo/config ]]; then
		printf '  missing validator must stop apply before simulation or link mutation\n' >&2
		return 1
	fi
}

test_missing_stow_routes_to_prerequisite_action() {
	new_fixture
	add_package
	rm "$FIXTURE_BIN/stow"
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	assert_eq 1 "$COMMAND_STATUS" 'missing Stow should stop package application' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: GNU Stow is required.' \
		'missing Stow should be explained' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Prepare prerequisites in the Dotfiles wizard.' \
		'recovery should name the standalone prerequisite action' || return 1
	assert_contains "$(<"$CALL_LOG")" 'version|' 'Omarchy inspection should precede the missing-Stow result'
}

test_stow_conflict_stops_before_mutation_and_reports_recovery() {
	new_fixture
	add_package
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'keep me\n' >"$FIXTURE_HOME/.config/demo/config"
	local before
	before=$(sha256sum "$FIXTURE_HOME/.config/demo/config")
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
printf "existing target would conflict: %s/.config/demo/config\n" "$HOME" >&2
exit 1'
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  Stow conflict should fail apply\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" "$FIXTURE_HOME/.config/demo/config" 'conflicting normal target should be reported' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Conflict: regular file:' 'conflict should identify the normal target type' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: apply phase failed for package demo.' 'conflict should identify the apply phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'resolve the reported target conflict without deleting it' \
		'recovery should preserve the target and explain retry' || return 1
	assert_eq "$before" "$(sha256sum "$FIXTURE_HOME/.config/demo/config")" 'normal target should remain unchanged' || return 1
	local stow_calls
	stow_calls=$(awk '/^stow / { count++ } END { print count + 0 }' "$CALL_LOG")
	assert_eq 1 "$stow_calls" 'failed simulation should prevent mutating Stow invocation'
}

test_migrate_requires_mutation_and_inspection_approval() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	local before_target
	before_target=$(sha256sum "$FIXTURE_HOME/.config/demo/config")

	DOTFILES_TEST_INPUT='n\n' run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --interactive
	assert_eq 0 "$COMMAND_STATUS" 'declining the migration plan should be a safe skip' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migration candidate: regular file:' 'migration should expose the candidate before approval' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migrate this complete plan?' 'migration should request mutation approval' || return 1
	assert_eq "$before_target" "$(sha256sum "$FIXTURE_HOME/.config/demo/config")" 'declined migration should preserve the target' || return 1
	if [[ -e $FIXTURE_REPO/config/demo/.config/demo/config ]]; then
		printf '  declined migration should not create package content\n' >&2
		return 1
	fi
	if [[ $(<"$CALL_LOG") == *$'stow --verbose=2 '* ]]; then
		printf '  declined migration should invoke no external mutation commands\n' >&2
		return 1
	fi
}

test_migrate_rejects_home_parent_symlink_escape() {
	new_fixture
	add_package
	local outside=$FIXTURE_ROOT/outside-home
	mkdir -p "$outside"
	printf 'outside target\n' >"$outside/config"
	ln -s "$outside" "$FIXTURE_HOME/escape"

	run_operation "$FIXTURE_ROOT" migrate_target demo escape/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'migration should reject a target resolving outside HOME' || return 1
	assert_contains "$COMMAND_OUTPUT" 'migration target resolves outside HOME' 'rejection should explain the containment failure' || return 1
	assert_eq 'outside target' "$(<"$outside/config")" 'HOME symlink escape must preserve the outside file' || return 1
	if [[ -e $FIXTURE_REPO/config/demo/escape/config || -d $FIXTURE_STATE/dotfiles/backups || -s $CALL_LOG ]]; then
		printf '  HOME containment rejection must precede simulation, backup, and repository writes\n' >&2
		return 1
	fi
}

test_migrate_rejects_package_parent_symlink_escape() {
	new_fixture
	add_package
	local outside=$FIXTURE_ROOT/outside-package
	mkdir -p "$outside" "$FIXTURE_HOME/escape"
	printf 'outside sentinel\n' >"$outside/sentinel"
	printf 'approved user content\n' >"$FIXTURE_HOME/escape/config"
	ln -s "$outside" "$FIXTURE_REPO/config/demo/escape"

	run_operation "$FIXTURE_ROOT" migrate_target demo escape/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'migration should reject a package destination resolving outside its package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'package destination resolves outside package demo' 'rejection should explain package ownership containment' || return 1
	assert_eq 'outside sentinel' "$(<"$outside/sentinel")" 'package symlink escape must preserve outside content' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/escape/config")" 'package containment rejection must preserve the migration target' || return 1
	if [[ -e $outside/config || -d $FIXTURE_STATE/dotfiles/backups || -s $CALL_LOG ]]; then
		printf '  package containment rejection must precede simulation, backup, and outside writes\n' >&2
		return 1
	fi
}

test_migrate_backs_up_moves_simulates_and_verifies() {
	new_fixture
	add_package
	rm -rf "$FIXTURE_REPO/config/demo/.config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
package=${!#}
if [[ " $* " != *" --simulate "* ]]; then
	mkdir -p "$HOME/.config/$package"
	ln -s "$DOTFILES_TEST_REPO/config/$package/.config/$package/config" "$HOME/.config/$package/config"
fi'

	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 0 "$COMMAND_STATUS" 'approved migration should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup created:' 'migration should expose recovery evidence before moving content' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Moved approved content into package:' 'migration should report the explicit move' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migrated and verified package: demo' 'success should include final link verification' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_REPO/config/demo/.config/demo/config")" 'approved target content should move into the package' || return 1
	assert_eq "$FIXTURE_REPO/config/demo/.config/demo/config" "$(readlink -f "$FIXTURE_HOME/.config/demo/config")" 'migration should leave the target linked to moved package content' || return 1
	local -a backups=("$FIXTURE_STATE"/dotfiles/backups/demo/[0-9]*Z/.config/demo/config)
	assert_eq 1 "${#backups[@]}" 'migration should create one timestamped backup below XDG state' || return 1
	assert_eq 'approved user content' "$(<"${backups[0]}")" 'backup should preserve the original target content' || return 1
	local calls
	calls=$(<"$CALL_LOG")
	assert_eq 2 "$(awk '/^stow --simulate / { count++ } END { print count + 0 }' "$CALL_LOG")" 'migration should simulate before and after moving content' || return 1
	if [[ $calls == *--adopt* ]]; then
		printf '  migration must never invoke Stow adoption\n' >&2
		return 1
	fi
}

test_migrate_plans_and_applies_dependencies_before_selected_package() {
	new_fixture
	add_package base
	add_dependent_package app base
	rm "$FIXTURE_REPO/config/app/.config/app/config"
	mkdir -p "$FIXTURE_HOME/.config/app"
	printf 'approved app content\n' >"$FIXTURE_HOME/.config/app/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " != *" --simulate "* ]]; then
	package=${!#}
	mkdir -p "$HOME/.config"
	if [[ $package == base ]]; then
		ln -s "$DOTFILES_TEST_REPO/config/base/.config/base" "$HOME/.config/base"
	else
		mkdir -p "$HOME/.config/app"
		ln -s "$DOTFILES_TEST_REPO/config/app/.config/app/config" "$HOME/.config/app/config"
	fi
fi'

	run_operation "$FIXTURE_ROOT" migrate_target app .config/app/config --yes --inspection-approved

	assert_eq 0 "$COMMAND_STATUS" 'migration with a dependency should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" $'Plan: migration package order:\n  1. base (required dependency; apply only)\n  2. app (selected; migrate and apply)' \
		'migration should visibly distinguish dependency apply from selected migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package base prerequisites: test-validator, test-validator-two' \
		'migration plan should include dependency prerequisites' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package base validators: test-validator --check; test-validator-two --check' \
		'migration plan should include dependency validators' || return 1
	local base_sim app_initial_sim base_apply app_post_sim app_apply
	base_sim=$(awk '/^stow --simulate .* base$/ { print NR; exit }' "$CALL_LOG")
	app_initial_sim=$(awk '/^stow --simulate .* app$/ { print NR; exit }' "$CALL_LOG")
	base_apply=$(awk '/^stow --verbose=2 .* base$/ { print NR; exit }' "$CALL_LOG")
	app_post_sim=$(awk '/^stow --simulate .* app$/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	app_apply=$(awk '/^stow --verbose=2 .* app$/ { print NR; exit }' "$CALL_LOG")
	if [[ -z $base_sim || -z $app_initial_sim || -z $base_apply || -z $app_post_sim || -z $app_apply || \
		$base_sim -ge $app_initial_sim || $app_initial_sim -ge $base_apply || $base_apply -ge $app_post_sim || $app_post_sim -ge $app_apply ]]; then
		printf '  migration should simulate the closure, apply dependencies, then re-simulate and apply the selected package\n' >&2
		return 1
	fi
	assert_eq "$FIXTURE_REPO/config/base/.config/base/config" "$(readlink -f "$FIXTURE_HOME/.config/base/config")" 'dependency should be linked first' || return 1
	assert_eq "$FIXTURE_REPO/config/app/.config/app/config" "$(readlink -f "$FIXTURE_HOME/.config/app/config")" 'selected migrated package should be linked last'
}

test_migrate_dependency_failure_preserves_target_and_earlier_success() {
	new_fixture
	add_package base
	add_dependent_package middle base
	add_dependent_package app middle
	rm "$FIXTURE_REPO/config/app/.config/app/config"
	mkdir -p "$FIXTURE_HOME/.config/app"
	printf 'approved app content\n' >"$FIXTURE_HOME/.config/app/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
package=${!#}
if [[ " $* " != *" --simulate "* && $package == middle ]]; then
	printf "middle apply failed\n" >&2
	exit 46
fi
if [[ " $* " != *" --simulate "* ]]; then
	mkdir -p "$HOME/.config"
	ln -s "$DOTFILES_TEST_REPO/config/$package/.config/$package" "$HOME/.config/$package"
fi'

	run_operation "$FIXTURE_ROOT" migrate_target app .config/app/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'dependency apply failure should stop migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package state: base: succeeded' 'earlier dependency success should be retained and reported' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package state: middle: failed' 'failed dependency should be reported' || return 1
	assert_eq "$FIXTURE_REPO/config/base/.config/base/config" "$(readlink -f "$FIXTURE_HOME/.config/base/config")" 'earlier dependency should remain linked' || return 1
	assert_eq 'approved app content' "$(<"$FIXTURE_HOME/.config/app/config")" 'selected migration target should remain untouched' || return 1
	if [[ -e $FIXTURE_REPO/config/app/.config/app/config || -d $FIXTURE_STATE/dotfiles/backups ]]; then
		printf '  dependency failure must stop before selected-package backup or move\n' >&2
		return 1
	fi
}

test_migrate_unrelated_conflict_stops_before_backup_or_move() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	printf 'tracked sibling\n' >"$FIXTURE_REPO/config/demo/.config/demo/sibling"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	printf 'unrelated conflict\n' >"$FIXTURE_HOME/.config/demo/sibling"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
printf "existing sibling target conflicts\n" >&2
exit 45'

	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'unrelated pre-move conflict should fail migration planning' || return 1
	assert_contains "$COMMAND_OUTPUT" 'existing sibling target conflicts' 'migration should expose the unrelated conflict' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery:' 'migration should provide recovery before stopping' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" 'preflight conflict should preserve the migration target' || return 1
	assert_eq 'tracked sibling' "$(<"$FIXTURE_REPO/config/demo/.config/demo/sibling")" 'preflight conflict should preserve package content' || return 1
	if [[ -e $FIXTURE_REPO/config/demo/.config/demo/config || -d $FIXTURE_STATE/dotfiles/backups ]]; then
		printf '  preflight conflict must stop before backup or move\n' >&2
		return 1
	fi
	assert_eq 1 "$(awk '/^stow --simulate / { count++ } END { print count + 0 }' "$CALL_LOG")" 'preflight conflict should run only the initial simulation'
}

test_migrate_backup_failure_preserves_target() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	local before_target
	before_target=$(sha256sum "$FIXTURE_HOME/.config/demo/config")
	make_fake cp 'printf "cp %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exit 41'
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'

	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'backup failure should fail migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: backup phase failed for package demo.' 'backup failure should identify its phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'the target remains unchanged' 'backup failure should report target recovery state' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Migrate existing target in the Dotfiles wizard' 'backup failure should name the migration action' || return 1
	assert_eq "$before_target" "$(sha256sum "$FIXTURE_HOME/.config/demo/config")" 'backup failure should preserve the target' || return 1
	if [[ -e $FIXTURE_REPO/config/demo/.config/demo/config ]]; then
		printf '  backup failure should not create package content\n' >&2
		return 1
	fi
	assert_eq 1 "$(awk '/^stow / { count++ } END { print count + 0 }' "$CALL_LOG")" 'backup failure should stop after the initial simulation'
}

test_migrate_move_failure_retains_backup_and_unrelated_target() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo" "$FIXTURE_HOME/.config/unrelated"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	printf 'leave alone\n' >"$FIXTURE_HOME/.config/unrelated/config"
	make_fake mv 'printf "mv %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exit 42'
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'

	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'move failure should fail migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: migrate phase failed for package demo.' 'move failure should identify its phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup retained:' 'move failure should expose retained recovery evidence' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Migrate existing target in the Dotfiles wizard' 'move failure should name the migration action' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" 'failed move should leave the original target available' || return 1
	assert_eq 'leave alone' "$(<"$FIXTURE_HOME/.config/unrelated/config")" 'failed move should not alter unrelated targets' || return 1
	local -a backups=("$FIXTURE_STATE"/dotfiles/backups/demo/[0-9]*Z/.config/demo/config)
	assert_eq 'approved user content' "$(<"${backups[0]}")" 'failed move should retain the completed backup' || return 1
	assert_eq 1 "$(awk '/^stow / { count++ } END { print count + 0 }' "$CALL_LOG")" 'move failure should not run post-move Stow'
}

test_migrate_post_move_stow_conflict_retains_recovery_evidence() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo" "$FIXTURE_HOME/.config/unrelated"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	printf 'leave alone\n' >"$FIXTURE_HOME/.config/unrelated/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ -f $DOTFILES_TEST_REPO/config/demo/.config/demo/config ]]; then
printf "remaining unrelated Stow conflict\n" >&2
exit 43
fi'

	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'post-move Stow conflict should fail migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'remaining unrelated Stow conflict' 'post-move conflict details should remain visible' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup retained:' 'post-move conflict should identify the retained backup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'restore the original target with:' 'post-move conflict should provide restoration evidence' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Migrate existing target in the Dotfiles wizard' 'post-move conflict should name the migration action' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_REPO/config/demo/.config/demo/config")" 'moved content should remain recoverable in the package' || return 1
	assert_eq 'leave alone' "$(<"$FIXTURE_HOME/.config/unrelated/config")" 'post-move conflict should not alter unrelated targets' || return 1
	assert_eq 2 "$(awk '/^stow --simulate / { count++ } END { print count + 0 }' "$CALL_LOG")" 'post-move conflict should come from the repeated simulation'
}

test_migrate_link_verification_failure_retains_backup() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'

	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'missing migrated link should fail verification' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: verify phase failed for package demo.' 'migration should reuse link audit failure reporting' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup retained:' 'verification failure should preserve backup evidence' || return 1
	local -a backups=("$FIXTURE_STATE"/dotfiles/backups/demo/[0-9]*Z/.config/demo/config)
	assert_eq 'approved user content' "$(<"${backups[0]}")" 'verification failure should preserve the original backup'
}

test_migrate_requires_separate_omarchy_mismatch_confirmation() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " != *" --simulate "* ]]; then
	mkdir -p "$HOME/.config/demo"
	ln -s "$DOTFILES_TEST_REPO/config/demo/.config/demo/config" "$HOME/.config/demo/config"
fi'
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\ny\nn\n' run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --interactive

	assert_eq 1 "$COMMAND_STATUS" 'migration should stop on an unapproved Omarchy mismatch' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'migration should report the supported version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'migration should report the detected version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Migrate existing target in the Dotfiles wizard' 'migration should name the distinct mismatch recovery action' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" 'mismatch rejection should precede target mutation' || return 1
	if [[ -e $FIXTURE_REPO/config/demo/.config/demo/config || -d $FIXTURE_STATE/dotfiles/backups ]]; then
		printf '  mismatch rejection should precede backup and package mutation\n' >&2
		return 1
	fi

	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved --allow-omarchy-mismatch
	assert_eq 0 "$COMMAND_STATUS" 'distinct mismatch approval should permit migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migrated and verified package: demo' 'approved mismatch should complete the same verified flow' || return 1
}

test_migrate_validates_prerequisites_before_backup() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config" "$FIXTURE_BIN/test-validator"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'missing prerequisite should fail migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing package prerequisite for demo: test-validator' 'migration should name every missing declared command' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: plan phase failed for package demo.' 'prerequisite failure should provide phase recovery output' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" 'prerequisite failure should preserve the target' || return 1
	if [[ -e $FIXTURE_REPO/config/demo/.config/demo/config || -d $FIXTURE_STATE/dotfiles/backups ]]; then
		printf '  prerequisite failure should precede backup and package mutation\n' >&2
		return 1
	fi
}

test_migrate_rejects_missing_validator_executable_before_simulation() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	jq '.packages[0].validators = ["missing-validator --check"]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"

	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'migration should fail planning when a validator executable is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing validator executable for demo: missing-validator --check' \
		'migration should identify the unavailable validator' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: plan phase failed for package demo.' \
		'migration should reject the validator during planning' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" 'missing validator should preserve the migration target' || return 1
	if [[ $(<"$CALL_LOG") == *'stow '* || -e $FIXTURE_REPO/config/demo/.config/demo/config || -d $FIXTURE_STATE/dotfiles/backups ]]; then
		printf '  missing validator must stop migration before simulation, backup, or move\n' >&2
		return 1
	fi
}

test_migrate_rejects_occupied_package_destination() {
	new_fixture
	add_package
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	local source_before
	source_before=$(sha256sum "$FIXTURE_REPO/config/demo/.config/demo/config")
	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'occupied package destination should reject migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'package destination already exists' 'rejection should identify the clobber hazard' || return 1
	assert_eq "$source_before" "$(sha256sum "$FIXTURE_REPO/config/demo/.config/demo/config")" 'occupied package content should never be overwritten' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" 'occupied destination rejection should preserve the target' || return 1
}

test_migrate_parent_creation_failure_retains_backup() {
	new_fixture
	add_package
	rm -rf "$FIXTURE_REPO/config/demo/.config"
	mkdir -p "$FIXTURE_HOME/.config/demo" "$FIXTURE_HOME/.config/unrelated"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	printf 'leave alone\n' >"$FIXTURE_HOME/.config/unrelated/config"
	make_fake mkdir 'if [[ " $* " == *"/relocated/dotfiles/config/demo/.config/demo"* ]]; then
	exit 44
fi
/usr/bin/mkdir "$@"'
	run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'package parent creation failure should fail migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: migrate phase failed for package demo.' 'parent creation failure should identify migration recovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup retained:' 'parent creation failure should expose its backup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Migrate existing target in the Dotfiles wizard' 'parent creation failure should name the migration action' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" 'parent creation failure should preserve the target' || return 1
	assert_eq 'leave alone' "$(<"$FIXTURE_HOME/.config/unrelated/config")" 'parent creation failure should preserve unrelated targets' || return 1
}

test_link_audit_failure_identifies_verify_phase_and_unlink_recovery() {
	new_fixture
	add_package
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  missing expected link should fail verification\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" "Expected link is missing or incorrect: $FIXTURE_HOME/.config/demo/config" \
		'audit should name the missing expected link' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: verify phase failed for package demo.' \
		'audit should identify the verify phase' || return 1
	assert_contains "$COMMAND_OUTPUT" "stow --delete --dir '$FIXTURE_REPO/config' --target '$FIXTURE_HOME' 'demo'" \
		'audit recovery should give the exact unlink command'
}

test_validator_failure_identifies_command_and_recovery() {
	new_fixture
	add_package
	make_applying_stow
	make_fake test-validator 'printf "validator %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exit 23'
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	assert_eq 1 "$COMMAND_STATUS" 'validator failure should fail apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Validator failed for demo: test-validator --check' \
		'failure should name the declared validator' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: verify phase failed for package demo.' \
		'validator should fail in verification' || return 1
	assert_contains "$COMMAND_OUTPUT" 'fix the linked configuration, validate with: test-validator --check; then choose Apply Stow packages' \
		'recovery should provide the exact validation command' || return 1
	assert_eq "$FIXTURE_REPO/config/demo/.config/demo/config" "$(readlink -f "$FIXTURE_HOME/.config/demo/config")" \
		'failed validation should leave the applied package available for scoped recovery'
}

test_apply_includes_dependencies_in_visible_topological_order() {
	new_fixture
	add_package base
	add_dependent_package app base
	make_applying_stow
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages app

	assert_eq 0 "$COMMAND_STATUS" 'dependency closure should apply successfully' || return 1
	assert_contains "$COMMAND_OUTPUT" $'Plan: apply packages in dependency order:\n  1. base (required by selection)\n  2. app (selected)' \
		'plan should visibly distinguish and order included dependencies' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package base prerequisites: test-validator, test-validator-two' \
		'apply plan should include dependency prerequisites' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package base validators: test-validator --check; test-validator-two --check' \
		'apply plan should include dependency validators' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package app prerequisites: none' 'apply plan should include selected-package prerequisites' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package app validators: none' 'apply plan should include selected-package validators' || return 1
	local calls base_simulate app_simulate base_apply app_apply
	calls=$(<"$CALL_LOG")
	assert_contains "$calls" "stow --verbose=2 --dir $FIXTURE_REPO/config --target $FIXTURE_HOME base" \
		'base should be applied' || return 1
	base_simulate=$(awk '/^stow --simulate .* base$/ { print NR; exit }' "$CALL_LOG")
	app_simulate=$(awk '/^stow --simulate .* app$/ { print NR; exit }' "$CALL_LOG")
	base_apply=$(awk '/^stow --verbose=2 .* base$/ { print NR; exit }' "$CALL_LOG")
	app_apply=$(awk '/^stow --verbose=2 .* app$/ { print NR; exit }' "$CALL_LOG")
	if [[ -z $base_simulate || -z $app_simulate || -z $base_apply || -z $app_apply || \
		$base_simulate -ge $app_simulate || $app_simulate -ge $base_apply || $base_apply -ge $app_apply ]]; then
		printf '  every dependency-order simulation should precede every dependency-order mutation\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Package state: base: succeeded' 'dependency success should be reported' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package state: app: succeeded' 'selected package success should be reported' || return 1
}

test_apply_stops_after_failure_and_preserves_prior_success() {
	new_fixture
	add_package base
	add_dependent_package app base
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
package=${!#}
if [[ $package == app && " $* " != *" --simulate "* ]]; then
	printf "planned app failure\n" >&2
	exit 29
fi
if [[ " $* " != *" --simulate "* ]]; then
	mkdir -p "$HOME/.config"
	ln -s "$DOTFILES_TEST_REPO/config/$package/.config/$package" "$HOME/.config/$package"
fi'
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages app

	assert_eq 1 "$COMMAND_STATUS" 'the first package failure should fail the batch' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package state: base: succeeded' 'prior verified success should be reported' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package state: app: failed' 'failed attempted package should be reported' || return 1
	assert_eq "$FIXTURE_REPO/config/base/.config/base/config" "$(readlink -f "$FIXTURE_HOME/.config/base/config")" \
		'prior successful dependency should remain linked' || return 1
	if [[ -e $FIXTURE_HOME/.config/app/config ]]; then
		printf '  failed dependent should not be linked\n' >&2
		return 1
	fi
}

test_remove_blocks_retained_linked_dependents_and_names_each() {
	new_fixture
	add_package base
	add_dependent_package app base
	add_dependent_package addon base
	mkdir -p "$FIXTURE_HOME/.config"
	ln -s "$FIXTURE_REPO/config/base/.config/base" "$FIXTURE_HOME/.config/base"
	ln -s "$FIXTURE_REPO/config/app/.config/app" "$FIXTURE_HOME/.config/app"
	ln -s "$FIXTURE_REPO/config/addon/.config/addon" "$FIXTURE_HOME/.config/addon"
	run_operation "$FIXTURE_ROOT" remove_package base --yes

	assert_eq 1 "$COMMAND_STATUS" 'retained linked dependents should block removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removal blocked: linked packages depend on base:' \
		'blocked removal should explain the dependency constraint' || return 1
	assert_contains "$COMMAND_OUTPUT" '  addon' 'every linked blocker should be named' || return 1
	assert_contains "$COMMAND_OUTPUT" '  app' 'every linked blocker should be named' || return 1
	assert_contains "$COMMAND_OUTPUT" 'remove the named dependent packages first, or retain this package; then choose Remove Stow package in the Dotfiles wizard' \
		'blocked removal should preserve dependent-package guidance and name the removal action' || return 1
	if [[ $(<"$CALL_LOG") == *'stow '* ]]; then
		printf '  blocked removal should not invoke Stow\n' >&2
		return 1
	fi
	assert_eq "$FIXTURE_REPO/config/base/.config/base/config" "$(readlink -f "$FIXTURE_HOME/.config/base/config")" \
		'blocked package should remain linked' || return 1
}

test_remove_simulates_unlinks_verifies_and_reports_retained_leftovers() {
	new_fixture
	add_package demo
	jq '.packages[0].cleanup = [
		"Generated files remain in ~/.cache/demo",
		"Application state remains in ~/.local/state/demo",
		"Backups remain in $XDG_STATE_HOME/dotfiles/backups"
	]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
	mkdir -p "$FIXTURE_HOME/.config" "$FIXTURE_HOME/.cache/demo" "$FIXTURE_HOME/.local/state/demo" "$FIXTURE_STATE/dotfiles/backups"
	ln -s "$FIXTURE_REPO/config/demo/.config/demo" "$FIXTURE_HOME/.config/demo"
	printf 'generated\n' >"$FIXTURE_HOME/.cache/demo/generated"
	printf 'state\n' >"$FIXTURE_HOME/.local/state/demo/state"
	printf 'backup\n' >"$FIXTURE_STATE/dotfiles/backups/backup"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " == *" --delete "* && " $* " != *" --simulate "* ]]; then
	package=${!#}
	rm "$HOME/.config/$package"
fi'
	run_operation "$FIXTURE_ROOT" remove_package demo --yes

	assert_eq 0 "$COMMAND_STATUS" 'approved safe removal should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: remove demo links from' 'removal plan should be visible' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified package: demo' 'success should include link verification' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Cleanup notes (not deleted):' 'leftovers should be explicitly retained' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Generated files remain in ~/.cache/demo' 'generated files should be reported' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Application state remains in ~/.local/state/demo' 'application state should be reported' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backups remain in $XDG_STATE_HOME/dotfiles/backups' 'backups should be reported' || return 1
	assert_eq $'version|HOME='"$FIXTURE_HOME"'|XDG_CONFIG_HOME='"$FIXTURE_CONFIG"'|XDG_STATE_HOME='"$FIXTURE_STATE"'|XDG_CACHE_HOME='"$FIXTURE_CACHE"$'\nstow --simulate --delete --verbose=2 --dir '"$FIXTURE_REPO"$'/config --target '"$FIXTURE_HOME"$' demo\nstow --delete --verbose=2 --dir '"$FIXTURE_REPO"$'/config --target '"$FIXTURE_HOME"' demo' \
		"$(<"$CALL_LOG")" 'removal simulation should precede deletion' || return 1
	if [[ -e $FIXTURE_HOME/.config/demo || -L $FIXTURE_HOME/.config/demo ]]; then
		printf '  managed package link should be gone\n' >&2
		return 1
	fi
	assert_eq 'generated' "$(<"$FIXTURE_HOME/.cache/demo/generated")" 'generated files should not be deleted' || return 1
	assert_eq 'state' "$(<"$FIXTURE_HOME/.local/state/demo/state")" 'application state should not be deleted' || return 1
	assert_eq 'backup' "$(<"$FIXTURE_STATE/dotfiles/backups/backup")" 'backups should not be deleted' || return 1
}

set -e
run_test test_apply_requires_explicit_package_and_approval 'apply requires explicit package and approval'
run_test test_apply_plans_simulates_links_and_validates_package 'apply plans, simulates, links, and validates a package'
run_test test_apply_requires_separate_omarchy_mismatch_confirmation 'apply requires separate Omarchy mismatch confirmation'
run_test test_apply_reports_missing_package_prerequisite_before_stow 'apply reports missing package prerequisite before Stow'
run_test test_apply_rejects_missing_validator_executable_before_simulation 'apply rejects missing validator executable before simulation'
run_test test_missing_stow_routes_to_prerequisite_action 'missing Stow routes to the prerequisite wizard action'
run_test test_stow_conflict_stops_before_mutation_and_reports_recovery 'Stow conflict stops before mutation and reports recovery'
run_test test_migrate_requires_mutation_and_inspection_approval 'migration requires mutation and inspection approval'
run_test test_migrate_rejects_home_parent_symlink_escape 'migration rejects HOME parent symlink escape'
run_test test_migrate_rejects_package_parent_symlink_escape 'migration rejects package parent symlink escape'
run_test test_migrate_backs_up_moves_simulates_and_verifies 'migration backs up, moves, simulates, and verifies'
run_test test_migrate_plans_and_applies_dependencies_before_selected_package 'migration plans and applies dependencies before selected package'
run_test test_migrate_dependency_failure_preserves_target_and_earlier_success 'migration dependency failure preserves target and earlier success'
run_test test_migrate_unrelated_conflict_stops_before_backup_or_move 'migration unrelated conflict stops before backup or move'
run_test test_migrate_backup_failure_preserves_target 'migration backup failure preserves the target'
run_test test_migrate_move_failure_retains_backup_and_unrelated_target 'migration move failure retains backup and unrelated target'
run_test test_migrate_post_move_stow_conflict_retains_recovery_evidence 'migration post-move conflict retains recovery evidence'
run_test test_migrate_link_verification_failure_retains_backup 'migration verification failure retains backup'
run_test test_migrate_requires_separate_omarchy_mismatch_confirmation 'migration requires separate Omarchy mismatch confirmation'
run_test test_migrate_validates_prerequisites_before_backup 'migration validates prerequisites before backup'
run_test test_migrate_rejects_missing_validator_executable_before_simulation 'migration rejects missing validator executable before simulation'
run_test test_migrate_rejects_occupied_package_destination 'migration rejects an occupied package destination'
run_test test_migrate_parent_creation_failure_retains_backup 'migration parent creation failure retains backup'
run_test test_link_audit_failure_identifies_verify_phase_and_unlink_recovery 'link audit failure reports verification recovery'
run_test test_validator_failure_identifies_command_and_recovery 'validator failure reports command and recovery'
run_test test_apply_includes_dependencies_in_visible_topological_order 'apply includes dependencies in visible topological order'
run_test test_apply_stops_after_failure_and_preserves_prior_success 'apply stops after failure and preserves prior success'
run_test test_remove_blocks_retained_linked_dependents_and_names_each 'remove blocks retained linked dependents and names each'
run_test test_remove_simulates_unlinks_verifies_and_reports_retained_leftovers 'remove simulates, unlinks, verifies, and reports retained leftovers'
finish_tests
