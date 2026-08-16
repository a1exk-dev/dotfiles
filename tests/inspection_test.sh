#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

test_status_inspects_empty_relocated_clone() {
	new_fixture
	rm "$FIXTURE_BIN/stow"
	run_dotfiles "$FIXTURE_ROOT" status

	assert_eq 0 "$COMMAND_STATUS" 'status should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'status should report the supported major version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'status should report the detected version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'status should describe the empty catalog' || return 1

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq "version|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" "$calls" \
		'only the fake Omarchy command should observe the isolated user roots'
}

test_check_accepts_empty_catalog() {
	new_fixture
	rm "$FIXTURE_BIN/stow"
	run_dotfiles "$FIXTURE_HOME" check

	assert_eq 0 "$COMMAND_STATUS" 'check should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'check should report the supported major version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'check should report the detected version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid (0 packages)' 'check should accept the empty catalog' || return 1
	assert_contains "$COMMAND_OUTPUT" 'GNU Stow: unavailable (nonfatal until a package operation is selected)' \
		'check should report missing Stow without rejecting an empty catalog' || return 1

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq "version|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" "$calls" \
		'check should use only the fake Omarchy command under isolated roots'
}

test_check_rejects_missing_declared_package_prerequisite() {
	new_fixture
	add_package
	rm "$FIXTURE_BIN/test-validator"
	run_dotfiles "$FIXTURE_ROOT" check

	assert_eq 1 "$COMMAND_STATUS" 'check should fail when a declared package prerequisite is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing package prerequisite for demo: test-validator' \
		'check should identify the package and unavailable command' || return 1
}

test_check_rejects_missing_validator_executable() {
	new_fixture
	add_package
	jq '.packages[0].validators = ["missing-validator --check"]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
	run_dotfiles "$FIXTURE_ROOT" check

	assert_eq 1 "$COMMAND_STATUS" 'check should fail when a validator executable is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing validator executable for demo: missing-validator --check' \
		'check should identify the package and complete validator command' || return 1
	if [[ $(<"$CALL_LOG") == *'missing-validator'* ]]; then
		printf '  structural check must not execute validator commands\n' >&2
		return 1
	fi
}

test_check_rejects_missing_core_and_global_skill_commands() {
	new_fixture
	local check_bin=$FIXTURE_ROOT/check-bin command
	mkdir -p "$check_bin"
	for command in bash dirname jq find git diff; do
		ln -s "$(command -v "$command")" "$check_bin/$command"
	done
	ln -s "$FIXTURE_BIN/omarchy" "$check_bin/omarchy"

	DOTFILES_TEST_PATH=$check_bin run_dotfiles "$FIXTURE_ROOT" check
	assert_eq 1 "$COMMAND_STATUS" 'check should fail before inspection when a core command is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: missing core inspection command: readlink' \
		'check should identify the missing core command' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'missing core commands should stop before Omarchy inspection' || return 1

	ln -s "$(command -v readlink)" "$check_bin/readlink"
	DOTFILES_TEST_PATH=$check_bin run_dotfiles "$FIXTURE_ROOT" check
	assert_eq 1 "$COMMAND_STATUS" 'check should fail when a global-skill prerequisite is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: missing global skill prerequisite: npx' \
		'check should identify the missing global-skill command'
}

test_status_warns_about_version_mismatch_without_mutation() {
	new_fixture
	mkdir -p "$FIXTURE_HOME/.agents/skills" "$FIXTURE_CONFIG/omarchy"
	printf 'user config\n' >"$FIXTURE_CONFIG/omarchy/sentinel"
	printf 'global skill\n' >"$FIXTURE_HOME/.agents/skills/sentinel"
	printf 'state\n' >"$FIXTURE_STATE/sentinel"
	printf 'cache\n' >"$FIXTURE_CACHE/sentinel"
	printf 'packaged config\n' >"$FIXTURE_OMARCHY/sentinel"
	local before
	before=$(snapshot_isolated_paths)

	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 run_dotfiles "$FIXTURE_CONFIG" status

	assert_eq 0 "$COMMAND_STATUS" 'a mismatch should not fail inspection' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'status should preserve the detected version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: detected Omarchy does not match supported version 4' \
		'status should make the mismatch explicit' || return 1
	assert_eq "$before" "$(snapshot_isolated_paths)" \
		'inspection should not mutate user config, global skills, state, cache, or packaged Omarchy fixtures'
}

test_check_rejects_malformed_catalog_without_mutation() {
	new_fixture
	mkdir -p "$FIXTURE_HOME/.agents/skills" "$FIXTURE_CONFIG/omarchy"
	printf 'user config\n' >"$FIXTURE_CONFIG/omarchy/sentinel"
	printf 'global skill\n' >"$FIXTURE_HOME/.agents/skills/sentinel"
	printf 'state\n' >"$FIXTURE_STATE/sentinel"
	printf 'cache\n' >"$FIXTURE_CACHE/sentinel"
	printf 'packaged config\n' >"$FIXTURE_OMARCHY/sentinel"
	printf '{"packages": [}\n' >"$FIXTURE_REPO/packages.json"
	local before_paths before_catalog
	before_paths=$(snapshot_isolated_paths)
	before_catalog=$(sha256sum "$FIXTURE_REPO/packages.json")

	run_dotfiles "$FIXTURE_ROOT" check

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  malformed catalog should fail check\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" "Error: invalid package catalog: $FIXTURE_REPO/packages.json" \
		'check should identify the rejected catalog' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'catalog rejection should happen before external commands run' || return 1
	assert_eq "$before_catalog" "$(sha256sum "$FIXTURE_REPO/packages.json")" \
		'check should not rewrite a malformed catalog' || return 1
	assert_eq "$before_paths" "$(snapshot_isolated_paths)" \
		'catalog rejection should not mutate isolated user or Omarchy paths'
}

test_status_reports_nonempty_package_states_and_metadata() {
	new_fixture
	add_package linked
	add_dependent_package absent linked
	add_dependent_package invalid linked
	add_dependent_package conflicting linked
	mkdir -p "$FIXTURE_HOME/.config"
	ln -s "$FIXTURE_REPO/config/linked/.config/linked" "$FIXTURE_HOME/.config/linked"
	mkdir -p "$FIXTURE_HOME/.config/invalid"
	ln -s /tmp/not-the-package "$FIXTURE_HOME/.config/invalid/config"
	mkdir -p "$FIXTURE_HOME/.config/conflicting"
	printf 'keep me\n' >"$FIXTURE_HOME/.config/conflicting/config"

	run_dotfiles "$FIXTURE_ROOT" status

	assert_eq 0 "$COMMAND_STATUS" 'status should inspect a nonempty catalog' || return 1
	assert_contains "$COMMAND_OUTPUT" 'linked: linked - Test package' 'status should report a fully linked package and description' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Documentation: linked.md' 'status should report package documentation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'absent: absent - Dependent test package' 'status should report an absent package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'invalid: invalid - Dependent test package' 'status should report an incorrect symbolic link as invalid' || return 1
	assert_contains "$COMMAND_OUTPUT" 'conflicting: conflicting - Dependent test package' 'status should report a normal target conflict' || return 1
}

test_inspection_cannot_access_real_user_or_omarchy_paths() {
	new_fixture
	run_dotfiles_without_real_user_or_omarchy_paths

	assert_eq 0 "$COMMAND_STATUS" 'check should work with real user and Omarchy paths masked' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid (0 packages)' \
		'check should depend only on the temporary clone and fake commands'
}

test_check_validates_complete_package_metadata() {
	new_fixture
	add_package
	run_dotfiles "$FIXTURE_ROOT" check

	assert_eq 0 "$COMMAND_STATUS" 'complete package metadata should pass check' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid (1 packages)' \
		'check should count the validated package'
}

test_check_rejects_each_invalid_package_metadata_field() {
	local jq_filter expected
	while IFS='|' read -r jq_filter expected; do
		new_fixture
		add_package
		jq "$jq_filter" "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.invalid"
		mv "$FIXTURE_REPO/packages.invalid" "$FIXTURE_REPO/packages.json"
		run_dotfiles "$FIXTURE_ROOT" check
		if [[ $COMMAND_STATUS -eq 0 || $COMMAND_OUTPUT != *"$expected"* ]]; then
			printf '  invalid metadata was accepted: %s\n  output: %s\n' "$jq_filter" "$COMMAND_OUTPUT" >&2
			return 1
		fi
		rm -rf "$FIXTURE_ROOT"
	done <<'EOF'
.packages[0].name = "Not-Lower"|package name
.packages[0].path = "config/elsewhere"|package path
.packages[0].description = ""|description
del(.packages[0].dependencies)|dependencies
.packages[0].dependencies = [""]|dependencies
.packages[0].prerequisites = [""]|prerequisites
.packages[0].validators = [""]|validators
.packages[0].documentation = 42|documentation
.packages[0].documentation = "missing.md"|documentation
.packages[0].cleanup = [""]|cleanup
EOF
}

test_check_rejects_missing_dependency_and_cycle() {
	new_fixture
	add_package base
	mkdir -p "$FIXTURE_REPO/config/app"
	jq '.packages += [{
		"name": "app",
		"path": "config/app",
		"description": "Dependent package",
		"dependencies": ["missing"],
		"prerequisites": [],
		"validators": [],
		"documentation": null,
		"cleanup": []
	}]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"

	run_dotfiles "$FIXTURE_ROOT" check
	assert_eq 1 "$COMMAND_STATUS" 'a missing dependency reference should fail check' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: package app depends on missing package: missing' \
		'missing dependency output should name both packages' || return 1

	jq '(.packages[] | select(.name == "app").dependencies) = ["base"] |
		(.packages[] | select(.name == "base").dependencies) = ["app"]' \
		"$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
	run_dotfiles "$FIXTURE_ROOT" check
	assert_eq 1 "$COMMAND_STATUS" 'a dependency cycle should fail check' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: package dependency cycle detected:' \
		'cycle output should explain the graph error' || return 1
	assert_contains "$COMMAND_OUTPUT" 'base' 'cycle output should name a cycle member' || return 1
	assert_contains "$COMMAND_OUTPUT" 'app' 'cycle output should name every cycle member' || return 1
}

set -e
run_test test_status_inspects_empty_relocated_clone 'status inspects an empty relocated clone'
run_test test_check_accepts_empty_catalog 'check accepts an empty package catalog'
run_test test_check_rejects_missing_declared_package_prerequisite 'check rejects missing declared package prerequisite'
run_test test_check_rejects_missing_validator_executable 'check rejects missing validator executable'
run_test test_check_rejects_missing_core_and_global_skill_commands 'check rejects missing core and global skill commands'
run_test test_status_warns_about_version_mismatch_without_mutation 'status warns about mismatch without mutation'
run_test test_check_rejects_malformed_catalog_without_mutation 'check rejects malformed catalog without mutation'
run_test test_status_reports_nonempty_package_states_and_metadata 'status reports nonempty package states and metadata'
run_test test_inspection_cannot_access_real_user_or_omarchy_paths 'inspection cannot access real user or Omarchy paths'
run_test test_check_validates_complete_package_metadata 'check validates complete package metadata'
run_test test_check_rejects_each_invalid_package_metadata_field 'check rejects invalid package metadata fields'
run_test test_check_rejects_missing_dependency_and_cycle 'check rejects missing dependencies and cycles'
finish_tests
