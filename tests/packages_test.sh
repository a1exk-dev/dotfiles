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
	set_package_arch_packages demo demo-runtime
	set_installed_arch_packages demo-runtime
	make_applying_stow
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	assert_eq 0 "$COMMAND_STATUS" 'safe package apply should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: apply demo from config/demo to' 'plan should identify source and target' || return 1
	assert_contains "$COMMAND_OUTPUT" 'demo-runtime (required by demo): installed' \
		'plan should identify the Arch package owner and installed status' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Phase: verify' 'output should expose the final phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Applied and verified package: demo' 'success should mean links and validators passed' || return 1
	assert_eq "$FIXTURE_REPO/config/demo/.config/demo/config" "$(readlink -f "$FIXTURE_HOME/.config/demo/config")" \
		'apply should create the expected repository-owned link' || return 1
	local calls expected_calls
	calls=$(<"$CALL_LOG")
	expected_calls=$(printf '%s\n' \
		"version|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" \
		"pkg present demo-runtime|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" \
		"stow --no-folding --simulate --verbose=2 --dir $FIXTURE_REPO/config --target $FIXTURE_HOME demo" \
		"pkg present demo-runtime|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" \
		"stow --no-folding --verbose=2 --dir $FIXTURE_REPO/config --target $FIXTURE_HOME demo" \
		'validator --check' \
		"validator-two --check|PWD=$FIXTURE_REPO")
	assert_eq "$expected_calls" "$calls" 'simulation, mutation, audit, and every validator should run in order'
}

test_apply_empty_and_requirement_free_selections_skip_arch_package_commands() {
	new_fixture
	run_operation "$FIXTURE_ROOT" apply_packages
	assert_eq 0 "$COMMAND_STATUS" 'an empty selection should remain a successful no-op' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'an empty selection should not inspect or install Arch packages' || return 1

	new_fixture
	add_package
	make_applying_stow
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo
	assert_eq 0 "$COMMAND_STATUS" 'a requirement-free package should apply normally' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg present'* || $(<"$CALL_LOG") == *'pkg add'* ]]; then
		printf '  a requirement-free selection must not call an Arch package command\n' >&2
		return 1
	fi
}

test_apply_install_failure_stops_before_stow_mutation() {
	new_fixture
	add_package
	set_package_arch_packages demo demo-runtime
	make_applying_stow
	DOTFILES_TEST_ARCH_INSTALL_FAILURE=true DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages demo

	assert_eq 1 "$COMMAND_STATUS" 'Arch package installation failure should fail apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: Arch package installation failed.' \
		'installation failure should identify the failed action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Apply Stow packages in the Dotfiles wizard' \
		'installation failure should provide apply-specific recovery' || return 1
	assert_eq 1 "$(awk '/^stow --no-folding --simulate / { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'installation failure should occur after the initial simulation only' || return 1
	if [[ $(<"$CALL_LOG") == *$'stow --no-folding --verbose=2 '* || -e $FIXTURE_HOME/.config/demo/config ]]; then
		printf '  Arch package installation failure must stop before Stow mutation\n' >&2
		return 1
	fi
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
	if [[ $(<"$CALL_LOG") == *$'stow --no-folding --verbose=2 '* ]]; then
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
	assert_eq 2 "$(awk '/^stow --no-folding --simulate / { count++ } END { print count + 0 }' "$CALL_LOG")" 'migration should simulate before and after moving content' || return 1
	if [[ $calls == *--adopt* ]]; then
		printf '  migration must never invoke Stow adoption\n' >&2
		return 1
	fi
}

test_migrate_plans_and_applies_dependencies_before_selected_package() {
	new_fixture
	add_package base
	add_dependent_package app base
	set_package_arch_packages base shared-runtime
	set_package_arch_packages app shared-runtime app-runtime
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
	assert_contains "$COMMAND_OUTPUT" 'shared-runtime (required by base, app): will install' \
		'migration plan should deduplicate a shared requirement and retain both owners' || return 1
	assert_contains "$COMMAND_OUTPUT" 'app-runtime (required by app): will install' \
		'migration plan should include selected-package requirements' || return 1
	assert_contains "$(<"$CALL_LOG")" 'pkg add shared-runtime app-runtime' \
		'migration should install missing requirements once in dependency order' || return 1
	local base_initial_sim app_initial_sim install_call base_repeat_sim app_repeat_sim shared_verify app_verify base_apply app_post_sim app_apply
	base_initial_sim=$(awk '/^stow --no-folding --simulate .* base$/ { print NR; exit }' "$CALL_LOG")
	app_initial_sim=$(awk '/^stow --no-folding --simulate .* app$/ { print NR; exit }' "$CALL_LOG")
	install_call=$(awk '/^pkg add shared-runtime app-runtime[|]/ { print NR; exit }' "$CALL_LOG")
	base_repeat_sim=$(awk '/^stow --no-folding --simulate .* base$/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	app_repeat_sim=$(awk '/^stow --no-folding --simulate .* app$/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	shared_verify=$(awk '/^pkg present shared-runtime[|]/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	app_verify=$(awk '/^pkg present app-runtime[|]/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	base_apply=$(awk '/^stow --no-folding --verbose=2 .* base$/ { print NR; exit }' "$CALL_LOG")
	app_post_sim=$(awk '/^stow --no-folding --simulate .* app$/ { count++; if (count == 3) { print NR; exit } }' "$CALL_LOG")
	app_apply=$(awk '/^stow --no-folding --verbose=2 .* app$/ { print NR; exit }' "$CALL_LOG")
	if [[ -z $base_initial_sim || -z $app_initial_sim || -z $install_call || -z $base_repeat_sim || -z $app_repeat_sim || \
		-z $shared_verify || -z $app_verify || -z $base_apply || -z $app_post_sim || -z $app_apply || $base_initial_sim -ge $app_initial_sim || \
		$app_initial_sim -ge $install_call || $install_call -ge $shared_verify || $shared_verify -ge $app_verify || \
		$app_verify -ge $base_repeat_sim || $base_repeat_sim -ge $app_repeat_sim || $app_repeat_sim -ge $base_apply || \
		$base_apply -ge $app_post_sim || $app_post_sim -ge $app_apply ]]; then
		printf '  migration should simulate, install, verify every requirement, re-simulate, then mutate in dependency order\n' >&2
		return 1
	fi
	assert_eq "$FIXTURE_REPO/config/base/.config/base/config" "$(readlink -f "$FIXTURE_HOME/.config/base/config")" 'dependency should be linked first' || return 1
	assert_eq "$FIXTURE_REPO/config/app/.config/app/config" "$(readlink -f "$FIXTURE_HOME/.config/app/config")" 'selected migrated package should be linked last'
}

test_migrate_arch_verification_failure_preserves_target_before_stow_mutation() {
	new_fixture
	add_package
	set_package_arch_packages demo demo-runtime
	set_installed_arch_packages
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	make_applying_stow

	DOTFILES_TEST_ARCH_VERIFY_FAILURE=true run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --yes --inspection-approved

	assert_eq 1 "$COMMAND_STATUS" 'failed Arch package verification should fail migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: Arch package verification failed: demo-runtime' \
		'verification failure should name the package whose identity was not confirmed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Migrate existing target in the Dotfiles wizard' \
		'verification failure should provide migration-specific recovery' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" \
		'verification failure should preserve the migration target' || return 1
	assert_eq 'demo-runtime' "$(<"$ARCH_PACKAGE_STATE")" \
		'a successfully added package may remain after verification failure' || return 1
	assert_eq 1 "$(awk '/^stow --no-folding --simulate / { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'failed Arch verification should stop before the post-install simulation' || return 1
	if [[ -e $FIXTURE_REPO/config/demo/.config/demo/config || -d $FIXTURE_STATE/dotfiles/backups || \
		$(<"$CALL_LOG") == *$'stow --no-folding --verbose=2 '* ]]; then
		printf '  Arch verification failure must precede Stow mutation, backup, and move\n' >&2
		return 1
	fi
}

test_migrate_rejects_relative_state_root_before_confirmation_or_mutation() {
	new_fixture
	add_package
	set_package_arch_packages demo demo-runtime
	set_installed_arch_packages
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved user content\n' >"$FIXTURE_HOME/.config/demo/config"
	make_applying_stow
	local absolute_state=$FIXTURE_STATE
	FIXTURE_STATE=relative-state

	DOTFILES_TEST_INPUT='y\ny\n' run_operation "$FIXTURE_ROOT" migrate_target demo .config/demo/config --interactive
	FIXTURE_STATE=$absolute_state

	assert_eq 1 "$COMMAND_STATUS" 'a relative state root should fail migration planning' || return 1
	assert_contains "$COMMAND_OUTPUT" 'set XDG_STATE_HOME to an absolute path; the target is unchanged' \
		'invalid state recovery should preserve the existing backup-root guidance' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_HOME/.config/demo/config")" \
		'invalid state root should preserve the migration target' || return 1
	if [[ $COMMAND_OUTPUT == *'Migrate this complete plan?'* || $(<"$CALL_LOG") == *'pkg add'* || \
		$(<"$CALL_LOG") == *$'stow --no-folding --verbose=2 '* || -e $FIXTURE_REPO/config/demo/.config/demo/config || \
		-d $absolute_state/dotfiles/backups ]]; then
		printf '  invalid state root must stop before confirmation, Arch install, Stow mutation, backup, or move\n' >&2
		return 1
	fi
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
	assert_eq 1 "$(awk '/^stow --no-folding --simulate / { count++ } END { print count + 0 }' "$CALL_LOG")" 'preflight conflict should run only the initial simulation'
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
	assert_contains "$COMMAND_OUTPUT" 'stow --no-folding --delete --dir' \
		'post-move recovery should preserve leaf-only Stow ownership' || return 1
	assert_contains "$COMMAND_OUTPUT" 'restore the original target with:' 'post-move conflict should provide restoration evidence' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Migrate existing target in the Dotfiles wizard' 'post-move conflict should name the migration action' || return 1
	assert_eq 'approved user content' "$(<"$FIXTURE_REPO/config/demo/.config/demo/config")" 'moved content should remain recoverable in the package' || return 1
	assert_eq 'leave alone' "$(<"$FIXTURE_HOME/.config/unrelated/config")" 'post-move conflict should not alter unrelated targets' || return 1
	assert_eq 2 "$(awk '/^stow --no-folding --simulate / { count++ } END { print count + 0 }' "$CALL_LOG")" 'post-move conflict should come from the repeated simulation'
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
	assert_contains "$COMMAND_OUTPUT" "stow --no-folding --delete --dir '$FIXTURE_REPO/config' --target '$FIXTURE_HOME' 'demo'" \
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
	set_package_arch_packages base shared-runtime base-runtime
	set_package_arch_packages app shared-runtime app-runtime
	set_installed_arch_packages base-runtime
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
	assert_contains "$COMMAND_OUTPUT" 'shared-runtime (required by base, app): will install' \
		'plan should deduplicate shared requirements and retain every owner' || return 1
	assert_contains "$COMMAND_OUTPUT" 'base-runtime (required by base): installed' \
		'plan should classify an already installed dependency requirement' || return 1
	assert_contains "$COMMAND_OUTPUT" 'app-runtime (required by app): will install' \
		'plan should classify a missing selected-package requirement' || return 1
	assert_eq 1 "$(awk '/Apply this complete Stow plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'Arch package requirements should remain inside the one Stow-plan confirmation' || return 1
	local calls base_initial_simulate app_initial_simulate install_call base_repeat_simulate app_repeat_simulate shared_verify base_verify app_verify base_apply app_apply
	calls=$(<"$CALL_LOG")
	assert_eq 1 "$(awk '/^pkg add / { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'missing requirements should use one batched installer call' || return 1
	assert_contains "$calls" 'pkg add shared-runtime app-runtime' \
		'batched installation should preserve dependency requirement order and omit installed packages' || return 1
	base_initial_simulate=$(awk '/^stow --no-folding --simulate .* base$/ { print NR; exit }' "$CALL_LOG")
	app_initial_simulate=$(awk '/^stow --no-folding --simulate .* app$/ { print NR; exit }' "$CALL_LOG")
	install_call=$(awk '/^pkg add shared-runtime app-runtime[|]/ { print NR; exit }' "$CALL_LOG")
	base_repeat_simulate=$(awk '/^stow --no-folding --simulate .* base$/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	app_repeat_simulate=$(awk '/^stow --no-folding --simulate .* app$/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	shared_verify=$(awk '/^pkg present shared-runtime[|]/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	base_verify=$(awk '/^pkg present base-runtime[|]/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	app_verify=$(awk '/^pkg present app-runtime[|]/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	base_apply=$(awk '/^stow --no-folding --verbose=2 .* base$/ { print NR; exit }' "$CALL_LOG")
	app_apply=$(awk '/^stow --no-folding --verbose=2 .* app$/ { print NR; exit }' "$CALL_LOG")
	if [[ -z $base_initial_simulate || -z $app_initial_simulate || -z $install_call || -z $base_repeat_simulate || -z $app_repeat_simulate || \
		-z $shared_verify || -z $base_verify || -z $app_verify || -z $base_apply || -z $app_apply || \
		$base_initial_simulate -ge $app_initial_simulate || $app_initial_simulate -ge $install_call || \
		$install_call -ge $shared_verify || $shared_verify -ge $base_verify || $base_verify -ge $app_verify || \
		$app_verify -ge $base_repeat_simulate || $base_repeat_simulate -ge $app_repeat_simulate || \
		$app_repeat_simulate -ge $base_apply || $base_apply -ge $app_apply ]]; then
		printf '  apply should simulate, batch-install, verify every requirement, re-simulate, then mutate in dependency order\n' >&2
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
	set_package_arch_packages demo demo-runtime
	set_installed_arch_packages demo-runtime
	jq '.packages[0].cleanup = [
		"Generated files remain in ~/.cache/demo",
		"Application state remains in ~/.local/state/demo",
		"Backups remain in $XDG_STATE_HOME/dotfiles/backups",
		"Arch package demo-runtime remains installed"
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
	assert_contains "$COMMAND_OUTPUT" 'Arch package demo-runtime remains installed' \
		'removal should display retained package state through cleanup notes' || return 1
	assert_eq $'version|HOME='"$FIXTURE_HOME"'|XDG_CONFIG_HOME='"$FIXTURE_CONFIG"'|XDG_STATE_HOME='"$FIXTURE_STATE"'|XDG_CACHE_HOME='"$FIXTURE_CACHE"$'\nstow --no-folding --simulate --delete --verbose=2 --dir '"$FIXTURE_REPO"$'/config --target '"$FIXTURE_HOME"$' demo\nstow --no-folding --delete --verbose=2 --dir '"$FIXTURE_REPO"$'/config --target '"$FIXTURE_HOME"' demo' \
		"$(<"$CALL_LOG")" 'removal simulation should precede deletion' || return 1
	if [[ -e $FIXTURE_HOME/.config/demo || -L $FIXTURE_HOME/.config/demo ]]; then
		printf '  managed package link should be gone\n' >&2
		return 1
	fi
	assert_eq 'generated' "$(<"$FIXTURE_HOME/.cache/demo/generated")" 'generated files should not be deleted' || return 1
	assert_eq 'state' "$(<"$FIXTURE_HOME/.local/state/demo/state")" 'application state should not be deleted' || return 1
	assert_eq 'backup' "$(<"$FIXTURE_STATE/dotfiles/backups/backup")" 'backups should not be deleted' || return 1
	assert_eq 'demo-runtime' "$(<"$ARCH_PACKAGE_STATE")" 'removal should leave declared Arch packages installed' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg drop'* ]]; then
		printf '  Stow package removal must not call the Arch package remover\n' >&2
		return 1
	fi
}

test_real_starship_pre_migration_lifecycle() (
	new_fixture
	set_installed_arch_packages thefuck tmux fzf less
	local source=$FIXTURE_REPO/config/starship/.config/starship.toml
	local target=$FIXTURE_HOME/.config/starship.toml
	local retained_cache=$FIXTURE_CACHE/starship/runtime-cache
	local retained_state=$FIXTURE_STATE/starship/runtime-state
	local real_command_bin=$FIXTURE_ROOT/real-starship-bin
	local real_package_path=$real_command_bin:/usr/bin:/bin
	local approved_content='add_newline = true'
	rm -- "$source"
	mkdir -p "$FIXTURE_HOME/.config" "$real_command_bin"
	printf '%s\n' "$approved_content" >"$target"
	make_fake starship '
if [[ ${1-} != print-config || $# -ne 1 ]]; then exit 64; fi
printf "starship %s|CONFIG=%s|CACHE=%s|SESSION=%s\n" "$*" "$STARSHIP_CONFIG" "$STARSHIP_CACHE" "$STARSHIP_SESSION_KEY" >>"$DOTFILES_TEST_CALL_LOG"
[[ $STARSHIP_CONFIG == "$HOME/.config/starship.toml" ]] || exit 65
[[ $STARSHIP_SESSION_KEY == dotfiles-starship-validation ]] || exit 66
[[ -d $STARSHIP_CACHE && ! -e $STARSHIP_CACHE/invoked ]] || exit 67
printf "invoked\n" >"$STARSHIP_CACHE/invoked"'
	ln -s "$FIXTURE_BIN/omarchy" "$real_command_bin/omarchy"
	ln -s "$FIXTURE_BIN/starship" "$real_command_bin/starship"
	assert_eq /usr/bin/stow "$(PATH=$real_package_path command -v stow)" \
		'the Starship lifecycle fixture should use real GNU Stow' || return 1

	DOTFILES_TEST_PATH=$real_package_path DOTFILES_TEST_INPUT='5\n.config/starship.toml\ny\ny\n' \
		run_dotfiles "$FIXTURE_ROOT" --action migrate

	assert_eq 0 "$COMMAND_STATUS" 'the isolated initial Starship migration should succeed' || {
		printf '  output: %s\n' "$COMMAND_OUTPUT" >&2
		return 1
	}
	assert_contains "$COMMAND_OUTPUT" $'Choose a package (none selected by default)\n  1. Cancel\n  2. bash\n  3. tmux\n  4. ghostty\n  5. starship' \
		'the public migration command should offer Bash and Starship as independent choices' || return 1
	assert_contains "$COMMAND_OUTPUT" $'Plan: migration package order:\n  1. starship (selected; migrate and apply)' \
		'the public migration command should plan only the selected Starship package' || return 1
	if [[ $COMMAND_OUTPUT == *'Plan simulation: apply bash'* || $COMMAND_OUTPUT == *'Package bash prerequisites:'* ]]; then
		printf '  selecting Starship must not include Bash in the migration plan\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'starship (required by starship): will install' \
		'the migration plan should identify the missing official Arch package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Arch packages installed and verified: starship' \
		'the migration should install and verify the declared Arch package' || return 1
	assert_eq 3 "$(awk '/^Plan simulation: apply starship$/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'migration should simulate initially, after installation, and after moving the source' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migrated and verified package: starship' \
		'the public migration should complete link and validator verification' || return 1
	assert_eq "$approved_content" "$(<"$source")" \
		'migration should move the approved bytes into the Starship package' || return 1
	if [[ ! -L $target ]]; then
		printf '  migration should leave the Starship target as a leaf symlink\n' >&2
		return 1
	fi
	assert_eq "$source" "$(readlink -f -- "$target")" \
		'the migrated Starship target should resolve to its exact repository source' || return 1
	if [[ ! -d $FIXTURE_HOME/.config || -L $FIXTURE_HOME/.config ]]; then
		printf '  Starship migration should leave .config as an ordinary directory\n' >&2
		return 1
	fi
	local -a backups=("$FIXTURE_STATE"/dotfiles/backups/starship/[0-9]*Z/.config/starship.toml)
	assert_eq 1 "${#backups[@]}" 'Starship migration should create one timestamped XDG-state backup' || return 1
	cmp --silent -- "$source" "${backups[0]}" || {
		printf '  Starship source and migration backup should be byte-identical\n' >&2
		return 1
	}
	if compgen -G "$FIXTURE_TMP/dotfiles-starship-validator.*" >/dev/null; then
		printf '  successful Starship validation should remove its isolated cache root\n' >&2
		return 1
	fi

	DOTFILES_TEST_PATH=$real_package_path run_dotfiles "$FIXTURE_ROOT" --action status
	assert_eq 0 "$COMMAND_STATUS" 'package status should inspect migrated Starship state' || return 1
	assert_contains "$COMMAND_OUTPUT" 'starship: linked - Complete Omarchy-based Starship prompt configuration' \
		'package status should report Starship as linked' || return 1

	mkdir -p "${retained_cache%/*}" "${retained_state%/*}"
	printf 'cache\n' >"$retained_cache"
	printf 'state\n' >"$retained_state"
	DOTFILES_TEST_PATH=$real_package_path DOTFILES_TEST_INPUT='5\ny\n' \
		run_dotfiles "$FIXTURE_ROOT" --action remove

	assert_eq 0 "$COMMAND_STATUS" 'the isolated Starship package should remove cleanly' || {
		printf '  output: %s\n' "$COMMAND_OUTPUT" >&2
		return 1
	}
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified package: starship' \
		'Starship removal should verify that its leaf target is absent' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removing this package leaves ~/.config/starship.toml absent' \
		'Starship removal should disclose the absent config' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Arch package starship remains installed' \
		'Starship removal should disclose the retained Arch package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Starship cache and state are not removed' \
		'Starship removal should disclose retained runtime data' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migration backups remain under the Dotfiles XDG state backup tree' \
		'Starship removal should disclose retained backups' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy refresh config starship.toml' \
		'Starship removal should report the optional baseline restoration command' || return 1
	if [[ -e $target || -L $target ]]; then
		printf '  Starship removal should leave the live fixture path absent\n' >&2
		return 1
	fi
	assert_eq "$approved_content" "$(<"$source")" \
		'Starship removal should retain the repository source' || return 1
	assert_eq cache "$(<"$retained_cache")" 'Starship removal should retain cache data' || return 1
	assert_eq state "$(<"$retained_state")" 'Starship removal should retain state data' || return 1
	assert_eq "$approved_content" "$(<"${backups[0]}")" \
		'Starship removal should retain migration backups' || return 1
	assert_eq $'thefuck\ntmux\nfzf\nless\nstarship' "$(<"$ARCH_PACKAGE_STATE")" \
		'Starship removal should retain every installed Arch package' || return 1
	if [[ $(<"$CALL_LOG") == *'refresh config starship.toml'* || $(<"$CALL_LOG") == *'pkg drop'* ]]; then
		printf '  Starship removal must not refresh the config or remove the Arch package\n' >&2
		return 1
	fi

	DOTFILES_TEST_PATH=$real_package_path DOTFILES_TEST_INPUT='4\ny\n' \
		run_dotfiles "$FIXTURE_ROOT" --action apply
	assert_eq 0 "$COMMAND_STATUS" 'the removed Starship package should reapply successfully' || {
		printf '  output: %s\n' "$COMMAND_OUTPUT" >&2
		return 1
	}
	assert_eq "$source" "$(readlink -f -- "$target")" \
		'reapplication should restore the exact Starship leaf link' || return 1
	assert_eq 2 "$(awk '/^starship print-config[|]/ { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'migration and reapplication should each invoke the Starship validator once' || return 1
	local cache cache_count=0
	local -A validator_caches=()
	while IFS= read -r cache; do
		cache_count=$((cache_count + 1))
		validator_caches["$cache"]=1
		if [[ $cache != "$FIXTURE_TMP"/dotfiles-starship-validator.*/cache || -e $cache ]]; then
			printf '  validator cache should be fresh, fixture-scoped, and removed: %s\n' "$cache" >&2
			return 1
		fi
	done < <(awk -F 'CACHE=|[|]SESSION=' '/^starship print-config[|]/ { print $2 }' "$CALL_LOG")
	assert_eq 2 "$cache_count" 'both lifecycle validations should report a cache' || return 1
	assert_eq 2 "${#validator_caches[@]}" 'each lifecycle validation should receive a distinct cache' || return 1
	assert_eq 2 "$(awk -F 'SESSION=' '/^starship print-config[|]/ && $2 == "dotfiles-starship-validation" { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'every lifecycle validation should use the fixed session key'
)

test_starship_validator_fails_on_nonzero_status_and_cleans_cache() (
	new_fixture
	local source=$FIXTURE_REPO/config/starship/.config/starship.toml
	local target=$FIXTURE_HOME/.config/starship.toml
	local real_command_bin=$FIXTURE_ROOT/real-starship-bin
	local real_package_path=$real_command_bin:/usr/bin:/bin
	mkdir -p "${source%/*}" "$real_command_bin"
	printf 'add_newline = true\n' >"$source"
	make_fake starship '
printf "nonzero-cache=%s|session=%s\n" "$STARSHIP_CACHE" "$STARSHIP_SESSION_KEY" >>"$DOTFILES_TEST_CALL_LOG"
printf "invoked\n" >"$STARSHIP_CACHE/invoked"
exit 23'
	ln -s "$FIXTURE_BIN/omarchy" "$real_command_bin/omarchy"
	ln -s "$FIXTURE_BIN/starship" "$real_command_bin/starship"

	DOTFILES_TEST_PATH=$real_package_path DOTFILES_TEST_INPUT='y\n' \
		run_operation "$FIXTURE_ROOT" apply_packages starship

	assert_eq 1 "$COMMAND_STATUS" 'a nonzero Starship status should fail package validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Validator failed for starship:' \
		'the public operation should identify the failed Starship validator' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: verify phase failed for package starship.' \
		'the nonzero result should fail during package verification' || return 1
	if [[ ! -L $target || $(readlink -f -- "$target") != "$source" ]]; then
		printf '  failed validation should leave the isolated Starship link available for recovery\n' >&2
		return 1
	fi
	if compgen -G "$FIXTURE_TMP/dotfiles-starship-validator.*" >/dev/null; then
		printf '  nonzero Starship validation should remove its isolated cache root\n' >&2
		return 1
	fi
	assert_contains "$(<"$CALL_LOG")" '|session=dotfiles-starship-validation' \
		'nonzero validation should still use the fixed session key'
)

test_starship_validator_rejects_repeated_status_zero_diagnostics_and_cleans_cache() (
	new_fixture
	local source=$FIXTURE_REPO/config/starship/.config/starship.toml
	local real_command_bin=$FIXTURE_ROOT/real-starship-bin
	local real_package_path=$real_command_bin:/usr/bin:/bin
	mkdir -p "${source%/*}" "$real_command_bin"
	printf 'invalid = [\n' >"$source"
	ln -s "$FIXTURE_BIN/omarchy" "$real_command_bin/omarchy"

	run_in_sandbox "$FIXTURE_ROOT" "$real_package_path" bash -c '
		set -u
		work=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-starship-raw.XXXXXX") || exit 1
		cleanup() { rm -rf -- "$work"; }
		trap cleanup EXIT
		mkdir -p -- "$work/cache"
		STARSHIP_CONFIG=$1 STARSHIP_CACHE=$work/cache STARSHIP_SESSION_KEY=dotfiles-starship-validation \
			starship print-config >/dev/null 2>"$work/stderr"
		status=$?
		cat -- "$work/stderr" >&2
		exit "$status"
	' bash "$source"
	assert_eq 0 "$COMMAND_STATUS" \
		'Starship 1.26.0 should demonstrate the status-zero diagnostic regression' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Unable to parse the config file' \
		'the raw status-zero command should emit a real parse diagnostic' || return 1
	if compgen -G "$FIXTURE_TMP/dotfiles-starship-raw.*" >/dev/null; then
		printf '  raw diagnostic proof should remove its isolated cache root\n' >&2
		return 1
	fi

	DOTFILES_TEST_PATH=$real_package_path DOTFILES_TEST_INPUT='y\n' \
		run_operation "$FIXTURE_ROOT" apply_packages starship
	local first_status=$COMMAND_STATUS first_output=$COMMAND_OUTPUT
	if compgen -G "$FIXTURE_TMP/dotfiles-starship-validator.*" >/dev/null; then
		printf '  first diagnostic validation should remove its isolated cache root\n' >&2
		return 1
	fi
	DOTFILES_TEST_PATH=$real_package_path DOTFILES_TEST_INPUT='y\n' \
		run_operation "$FIXTURE_ROOT" apply_packages starship

	assert_eq 1 "$first_status" 'the first status-zero diagnostic should fail validation' || return 1
	assert_eq 1 "$COMMAND_STATUS" 'the repeated status-zero diagnostic should also fail validation' || return 1
	assert_contains "$first_output" 'Unable to parse the config file' \
		'the first validator run should preserve the real diagnostic' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Unable to parse the config file' \
		'a fresh cache should make the fixed-session diagnostic repeat' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Validator failed for starship:' \
		'the repeated diagnostic should fail the public package validator' || return 1
	if compgen -G "$FIXTURE_TMP/dotfiles-starship-validator.*" >/dev/null; then
		printf '  repeated diagnostic validation should remove its isolated cache root\n' >&2
		return 1
	fi
)

test_real_tmux_dependency_and_leaf_only_lifecycle() (
	new_fixture
	DOTFILES_TEST_INPUT='1\nn\n' run_dotfiles "$FIXTURE_ROOT" --action apply

	assert_eq 0 "$COMMAND_STATUS" 'declining the real Bash package plan should be a safe no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" $'Plan: apply packages in dependency order:\n  1. tmux (required by selection)\n  2. bash (selected)' \
		'the real Bash plan should include tmux first' || return 1
	assert_contains "$COMMAND_OUTPUT" 'tmux (required by tmux): installed' \
		'the real plan should attribute the tmux Arch package to its Stow package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'fzf (required by tmux): installed' \
		'the real plan should attribute fzf to the tmux Stow package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'less (required by tmux): installed' \
		'the real plan should attribute less to the tmux Stow package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'thefuck (required by bash): installed' \
		'Bash should retain its own Arch requirement' || return 1
	if [[ $(<"$CALL_LOG") == *$'stow --no-folding --verbose=2 '* ]]; then
		printf '  declining the real dependency plan should not mutate Stow links\n' >&2
		return 1
	fi

	new_fixture
	local starter=$FIXTURE_REPO/config/tmux/.local/libexec/dotfiles/tmux-starter
	local config=$FIXTURE_REPO/config/tmux/.config/tmux/tmux.conf
	if [[ ! -f $starter || ! -f $config ]]; then
		printf '  the real tmux package must contain its complete config and private starter\n' >&2
		return 1
	fi
	mkdir -p "$FIXTURE_HOME/.config/tmux" "$FIXTURE_HOME/.local/libexec/dotfiles"
	ln -s "$config" "$FIXTURE_HOME/.config/tmux/tmux.conf"
	ln -s "$starter" "$FIXTURE_HOME/.local/libexec/dotfiles/tmux-starter"
	ln -s "$FIXTURE_REPO/config/bash/.bashrc" "$FIXTURE_HOME/.bashrc"
	DOTFILES_TEST_INPUT='3\n' run_dotfiles "$FIXTURE_ROOT" --action remove

	assert_eq 1 "$COMMAND_STATUS" 'linked Bash should block removal of its real tmux dependency' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removal blocked: linked packages depend on tmux:' \
		'real tmux removal should explain its dependency constraint' || return 1
	assert_contains "$COMMAND_OUTPUT" '  bash' 'real tmux removal should name Bash as the blocker' || return 1
	assert_eq "$config" "$(readlink -f "$FIXTURE_HOME/.config/tmux/tmux.conf")" \
		'blocked removal should preserve the complete config link' || return 1
	assert_eq "$starter" "$(readlink -f "$FIXTURE_HOME/.local/libexec/dotfiles/tmux-starter")" \
		'blocked removal should preserve the private starter link' || return 1
	if [[ $(<"$CALL_LOG") == *'stow '* ]]; then
		printf '  blocked real tmux removal should not invoke Stow\n' >&2
		return 1
	fi

	new_fixture
	set_installed_arch_packages thefuck tmux fzf
	starter=$FIXTURE_REPO/config/tmux/.local/libexec/dotfiles/tmux-starter
	config=$FIXTURE_REPO/config/tmux/.config/tmux/tmux.conf
	local config_target=$FIXTURE_HOME/.config/tmux/tmux.conf
	local starter_target=$FIXTURE_HOME/.local/libexec/dotfiles/tmux-starter
	local retained_state=$FIXTURE_STATE/tmux/session-state
	local retained_log=$FIXTURE_CACHE/tmux/server.log
	local tmux_tmpdir=$FIXTURE_TMP/default-tmux
	local real_command_bin=$FIXTURE_ROOT/real-package-bin
	local real_package_path=$real_command_bin:/usr/bin:/bin
	mkdir -p "$FIXTURE_HOME/.config/tmux" "$FIXTURE_HOME/.local/libexec/dotfiles" \
		"$(dirname -- "$retained_state")" "$(dirname -- "$retained_log")" "$tmux_tmpdir" "$real_command_bin"
	ln -s "$FIXTURE_BIN/omarchy" "$real_command_bin/omarchy"
	printf 'retained tmux state\n' >"$retained_state"
	printf 'retained tmux log\n' >"$retained_log"
	if ! TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux -f /dev/null new-session -d -s retained-runtime 'sleep 300'; then
		printf '  could not start the fixture-scoped default tmux server\n' >&2
		return 1
	fi
	cleanup_runtime_server() {
		TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux kill-server >/dev/null 2>&1 || true
	}
	trap cleanup_runtime_server EXIT
	local runtime_pid runtime_pane runtime_prefix
	runtime_pid=$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux display-message -p -t retained-runtime '#{pid}')
	runtime_pane=$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux list-panes -t retained-runtime -F '#{pane_id}')
	runtime_prefix=$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux show-options -gv prefix)

	cp "$config" "$FIXTURE_ROOT/valid-tmux.conf"
	printf 'not-a-valid-tmux-command\n' >"$config"
	DOTFILES_TEST_INPUT='2\ny\n' run_in_sandbox "$FIXTURE_ROOT" "$real_package_path" \
		env TMUX_TMPDIR="$tmux_tmpdir" "$FIXTURE_REPO/bin/dotfiles" --action apply

	assert_eq 1 "$COMMAND_STATUS" 'an invalid complete config should fail the public package validator' || return 1
	assert_contains "$COMMAND_OUTPUT" 'less (required by tmux): will install' \
		'the real tmux plan should attribute missing less to its owning package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Arch packages installed and verified: less' \
		'the generic Arch lifecycle should report less as installed and verified' || return 1
	assert_eq 1 "$(awk '/^pkg add less[|]/ { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'missing less should use one generic Omarchy package-add call' || return 1
	assert_eq 2 "$(awk '/^pkg present less[|]/ { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'missing less should be checked during planning and verified after installation' || return 1
	local less_install less_verify
	less_install=$(awk '/^pkg add less[|]/ { print NR; exit }' "$CALL_LOG")
	less_verify=$(awk '/^pkg present less[|]/ { count++; if (count == 2) { print NR; exit } }' "$CALL_LOG")
	if [[ -z $less_install || -z $less_verify || $less_install -ge $less_verify ]]; then
		printf '  less installation must precede its successful package verification\n' >&2
		return 1
	fi
	assert_eq $'thefuck\ntmux\nfzf\nless' "$(<"$ARCH_PACKAGE_STATE")" \
		'the generic installer should add less without changing existing package state' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Validator failed for tmux:' \
		'the invalid complete config should fail in package verification' || return 1
	if compgen -G "$FIXTURE_TMP/dotfiles-tmux-validator.*" >/dev/null; then
		printf '  failed complete-config validation should remove its isolated socket directory\n' >&2
		return 1
	fi
	assert_eq "$runtime_pid" \
		"$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux display-message -p -t retained-runtime '#{pid}')" \
		'failed config validation should not stop the default tmux server' || return 1
	assert_eq "$runtime_prefix" "$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux show-options -gv prefix)" \
		'failed config validation should not load the candidate into the default server' || return 1
	cp "$FIXTURE_ROOT/valid-tmux.conf" "$config"

	DOTFILES_TEST_INPUT='2\ny\n' run_in_sandbox "$FIXTURE_ROOT" "$real_package_path" \
		env TMUX_TMPDIR="$tmux_tmpdir" "$FIXTURE_REPO/bin/dotfiles" --action apply

	assert_eq 0 "$COMMAND_STATUS" 'the real tmux package should apply through the public command and run its validators' || {
		printf '  output: %s\n' "$COMMAND_OUTPUT" >&2
		return 1
	}
	assert_contains "$COMMAND_OUTPUT" 'Applied and verified package: tmux' \
		'real tmux apply should complete starter and config validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Arch packages verified: tmux fzf less' \
		'the successful real lifecycle should validate every tmux Arch requirement' || return 1
	assert_contains "$COMMAND_OUTPUT" 'dotfiles-tmux-validator' \
		'the public plan should expose isolated complete-config validation' || return 1
	local parent
	for parent in \
		"$FIXTURE_HOME/.config" \
		"$FIXTURE_HOME/.config/tmux" \
		"$FIXTURE_HOME/.local" \
		"$FIXTURE_HOME/.local/libexec" \
		"$FIXTURE_HOME/.local/libexec/dotfiles"; do
		if [[ ! -d $parent || -L $parent ]]; then
			printf '  leaf-only apply should leave a real directory: %s\n' "$parent" >&2
			return 1
		fi
	done
	if [[ ! -L $config_target || ! -L $starter_target ]]; then
		printf '  real Stow apply should create both tmux leaf links\n' >&2
		return 1
	fi
	assert_eq "$config" "$(readlink -f "$config_target")" \
		'leaf-only apply should link tmux.conf to its exact source' || return 1
	assert_eq "$starter" "$(readlink -f "$starter_target")" \
		'leaf-only apply should link tmux-starter to its exact source' || return 1
	if compgen -G "$FIXTURE_TMP/dotfiles-tmux-validator.*" >/dev/null; then
		printf '  complete-config validation should remove its isolated socket directory\n' >&2
		return 1
	fi
	assert_eq "$runtime_pid" \
		"$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux display-message -p -t retained-runtime '#{pid}')" \
		'config validation should not replace or stop the default tmux server' || return 1
	assert_eq "$runtime_pane" \
		"$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux list-panes -t retained-runtime -F '#{pane_id}')" \
		'config validation should leave the default server pane intact' || return 1
	assert_eq "$runtime_prefix" "$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux show-options -gv prefix)" \
		'config validation should not load the candidate into the default server' || return 1

	DOTFILES_TEST_INPUT='3\ny\n' run_in_sandbox "$FIXTURE_ROOT" "$real_package_path" \
		env TMUX_TMPDIR="$tmux_tmpdir" "$FIXTURE_REPO/bin/dotfiles" --action remove

	assert_eq 0 "$COMMAND_STATUS" 'the real tmux package should remove cleanly through the public command' || {
		printf '  output: %s\n' "$COMMAND_OUTPUT" >&2
		return 1
	}
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified package: tmux' \
		'real tmux removal should verify both links are absent' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Arch packages tmux, fzf, and less remain installed' \
		'real tmux removal should report retained Arch packages' || return 1
	assert_contains "$COMMAND_OUTPUT" 'The tmux server, sessions, panes, logs, and other runtime state are not removed' \
		'real tmux removal should report retained runtime state' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Run omarchy refresh tmux after removal to restore the Omarchy baseline' \
		'real tmux removal should report the explicit baseline restoration command' || return 1
	if [[ -e $config_target || -L $config_target || -e $starter_target || -L $starter_target ]]; then
		printf '  tmux removal should remove both managed leaf links\n' >&2
		return 1
	fi
	for parent in \
		"$FIXTURE_HOME/.config" \
		"$FIXTURE_HOME/.config/tmux" \
		"$FIXTURE_HOME/.local" \
		"$FIXTURE_HOME/.local/libexec" \
		"$FIXTURE_HOME/.local/libexec/dotfiles"; do
		if [[ ! -d $parent || -L $parent ]]; then
			printf '  tmux removal should retain the real parent directory: %s\n' "$parent" >&2
			return 1
		fi
	done
	assert_eq 'retained tmux state' "$(<"$retained_state")" 'tmux state should remain after Stow removal' || return 1
	assert_eq 'retained tmux log' "$(<"$retained_log")" 'tmux logs should remain after Stow removal' || return 1
	assert_eq $'thefuck\ntmux\nfzf\nless' "$(<"$ARCH_PACKAGE_STATE")" \
		'tmux, fzf, and less should remain installed after removal' || return 1
	assert_eq "$runtime_pid" \
		"$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux display-message -p -t retained-runtime '#{pid}')" \
		'tmux removal should leave the default server and session running' || return 1
	assert_eq "$runtime_pane" \
		"$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux list-panes -t retained-runtime -F '#{pane_id}')" \
		'tmux removal should leave the default server pane intact' || return 1
	assert_eq "$runtime_prefix" "$(TMUX= TMUX_TMPDIR="$tmux_tmpdir" tmux show-options -gv prefix)" \
		'tmux removal should leave default-server options unchanged' || return 1
	if [[ $(<"$CALL_LOG") == *'refresh tmux'* ]]; then
		printf '  tmux removal must report omarchy refresh tmux without executing it\n' >&2
		return 1
	fi
	if [[ $(<"$CALL_LOG") == *'pkg drop'* ]]; then
		printf '  tmux removal must not remove retained Arch packages\n' >&2
		return 1
	fi
)

set -e
run_test test_apply_requires_explicit_package_and_approval 'apply requires explicit package and approval'
run_test test_apply_plans_simulates_links_and_validates_package 'apply plans, simulates, links, and validates a package'
run_test test_apply_empty_and_requirement_free_selections_skip_arch_package_commands 'empty and requirement-free apply selections skip Arch package commands'
run_test test_apply_install_failure_stops_before_stow_mutation 'Arch package installation failure stops apply before Stow mutation'
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
run_test test_migrate_arch_verification_failure_preserves_target_before_stow_mutation 'migration Arch verification failure preserves the target before Stow mutation'
run_test test_migrate_rejects_relative_state_root_before_confirmation_or_mutation 'migration rejects a relative state root before confirmation or mutation'
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
run_test test_real_starship_pre_migration_lifecycle 'real Starship pre-migration lifecycle is enforced in isolation'
run_test test_starship_validator_fails_on_nonzero_status_and_cleans_cache 'Starship validator fails on nonzero status and cleans its cache'
run_test test_starship_validator_rejects_repeated_status_zero_diagnostics_and_cleans_cache 'Starship validator rejects repeated status-zero diagnostics and cleans its cache'
run_test test_real_tmux_dependency_and_leaf_only_lifecycle 'real tmux dependency and leaf-only lifecycle are enforced'
finish_tests
