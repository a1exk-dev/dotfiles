#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

# Stands in for a linked voxtype package: the profiles live in the fixture
# repository and reach the home directory the way Stow links them.
link_voxtype_profiles() {
	local name
	mkdir -p "$FIXTURE_HOME/.config/dotfiles/voxtype"
	for name in "$FIXTURE_REPO"/config/voxtype/.config/dotfiles/voxtype/*.toml; do
		ln -sfn "$name" "$FIXTURE_HOME/.config/dotfiles/voxtype/${name##*/}"
	done
}

# Stands in for the Voxtype executable: logs the call and parses nothing.
fake_voxtype() {
	make_fake voxtype 'printf "voxtype %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exit 0'
}

test_voxtype_profile_links_the_chosen_profile() {
	new_fixture
	link_voxtype_profiles
	fake_voxtype
	# Choose laptop from the Cancel, laptop, pc list, then approve the plan.
	DOTFILES_TEST_INPUT='2\ny\n' run_dotfiles "$FIXTURE_ROOT" --action voxtype-profile

	assert_eq 0 "$COMMAND_STATUS" 'an approved profile selection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Selected and verified Voxtype profile: laptop' \
		'the action should report the verified profile' || return 1
	local config=$FIXTURE_HOME/.config/voxtype/config.toml
	if [[ ! -L $config ]]; then
		printf '  expected a symbolic link at %s\n' "$config" >&2
		return 1
	fi
	assert_eq "$(readlink -f -- "$FIXTURE_REPO/config/voxtype/.config/dotfiles/voxtype/laptop.toml")" \
		"$(readlink -f -- "$config")" 'config.toml should resolve to the tracked laptop profile' || return 1
	assert_contains "$(<"$CALL_LOG")" 'config get engine' 'Voxtype should read the selected profile'
}

test_voxtype_profile_reselection_backs_up_the_previous_link() {
	new_fixture
	link_voxtype_profiles
	fake_voxtype
	DOTFILES_TEST_INPUT='2\ny\n' run_dotfiles "$FIXTURE_ROOT" --action voxtype-profile
	assert_eq 0 "$COMMAND_STATUS" 'the first selection should succeed' || return 1

	DOTFILES_TEST_INPUT='3\ny\n' run_dotfiles "$FIXTURE_ROOT" --action voxtype-profile
	assert_eq 0 "$COMMAND_STATUS" 'the second selection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Selected profile: laptop' 'the plan should name the current selection' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup created:' 'the replaced link should be backed up' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Selected and verified Voxtype profile: pc' \
		'the action should report the new profile' || return 1
	local -a backups=("$FIXTURE_STATE"/dotfiles/backups/voxtype/*/.config/voxtype/config.toml)
	assert_eq 1 "${#backups[@]}" 'exactly one backup should exist' || return 1
	assert_eq "$(readlink -f -- "$FIXTURE_REPO/config/voxtype/.config/dotfiles/voxtype/laptop.toml")" \
		"$(readlink -f -- "${backups[0]}")" 'the backup should keep the previous profile'
}

test_voxtype_profile_decline_makes_no_changes() {
	new_fixture
	link_voxtype_profiles
	fake_voxtype
	DOTFILES_TEST_INPUT='2\n\n' run_dotfiles "$FIXTURE_ROOT" --action voxtype-profile

	assert_eq 0 "$COMMAND_STATUS" 'a declined selection should succeed without changes' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No changes made.' 'declining should say nothing changed' || return 1
	assert_path_absent "$FIXTURE_HOME/.config/voxtype/config.toml" \
		'a declined selection must not write the config link'
}

test_voxtype_profile_requires_the_applied_package() {
	new_fixture
	fake_voxtype
	DOTFILES_TEST_INPUT='2\ny\n' run_dotfiles "$FIXTURE_ROOT" --action voxtype-profile

	assert_eq 1 "$COMMAND_STATUS" 'an unapplied package should fail the action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'the voxtype Stow package is not applied' \
		'the failure should name the missing package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply Stow packages and select voxtype' \
		'the failure should name a recovery' || return 1
	assert_path_absent "$FIXTURE_HOME/.config/voxtype/config.toml" \
		'a refused selection must not write the config link'
}

test_make_voxtype_launches_the_profile_selector() {
	new_fixture
	link_voxtype_profiles
	fake_voxtype
	DOTFILES_TEST_INPUT='2\ny\n' run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		make --no-print-directory -C "$FIXTURE_REPO" voxtype

	assert_eq 0 "$COMMAND_STATUS" 'make voxtype should launch its preselected action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Selected and verified Voxtype profile: laptop' \
		'make voxtype should not require top-level menu selection'
}

run_test test_voxtype_profile_links_the_chosen_profile 'Select Voxtype profile links and verifies the chosen profile'
run_test test_voxtype_profile_reselection_backs_up_the_previous_link 'Select Voxtype profile backs up the previous selection'
run_test test_voxtype_profile_decline_makes_no_changes 'Select Voxtype profile decline makes no changes'
run_test test_voxtype_profile_requires_the_applied_package 'Select Voxtype profile requires the applied package'
run_test test_make_voxtype_launches_the_profile_selector 'make voxtype launches the profile selector'
finish_tests
