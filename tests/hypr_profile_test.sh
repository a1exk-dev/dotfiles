#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

# Stands in for a linked hyprland package: every tracked file reaches the home
# directory the way Stow links it, so package_is_linked agrees the package applies.
link_hyprland_package() {
	local source relative target
	while IFS= read -r -d '' source; do
		relative=${source#"$FIXTURE_REPO/config/hyprland/"}
		target=$FIXTURE_HOME/$relative
		mkdir -p -- "${target%/*}"
		ln -sfn "$source" "$target"
	done < <(find "$FIXTURE_REPO/config/hyprland" \( -type f -o -type l \) -print0)
}

# Stands in for Hyprland's control socket: logs the call and reports no errors.
fake_hyprctl() {
	make_fake hyprctl 'printf "hyprctl %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exit 0'
}

# Loads a shared Hyprland Lua file against stub globals and prints what it configured.
lua_monitor_calls() {
	lua -e '
		local calls = {}
		hl = {
			env = function(key, value) calls[#calls + 1] = "env " .. key .. "=" .. value end,
			monitor = function(spec)
				calls[#calls + 1] = ("monitor %s %s %s"):format(
					tostring(spec.output), tostring(spec.mode), tostring(spec.scale))
			end,
		}
		package.path = os.getenv("CONFIG_HOME") .. "/?.lua;" .. package.path
		require("hypr.monitors")
		print(table.concat(calls, "\n"))
	' 2>&1
}

test_hypr_profile_links_the_chosen_profile() {
	new_fixture
	link_hyprland_package
	fake_hyprctl
	# Choose laptop from the Cancel, laptop, pc list, then approve the plan.
	DOTFILES_TEST_INPUT='2\ny\n' run_dotfiles "$FIXTURE_ROOT" --action hypr-profile

	assert_eq 0 "$COMMAND_STATUS" 'an approved profile selection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Selected and verified Hyprland machine profile: laptop' \
		'the action should report the verified profile' || return 1
	local machine=$FIXTURE_HOME/.config/hypr/machine
	if [[ ! -L $machine ]]; then
		printf '  expected a symbolic link at %s\n' "$machine" >&2
		return 1
	fi
	assert_eq "$(readlink -f -- "$FIXTURE_HOME/.config/dotfiles/hypr/laptop")" \
		"$(readlink -f -- "$machine")" 'machine should resolve to the tracked laptop profile' || return 1
	assert_contains "$(<"$CALL_LOG")" 'configerrors' 'the action should verify the configuration parses'
}

test_hypr_profile_reselection_backs_up_the_previous_link() {
	new_fixture
	link_hyprland_package
	fake_hyprctl
	DOTFILES_TEST_INPUT='2\ny\n' run_dotfiles "$FIXTURE_ROOT" --action hypr-profile
	assert_eq 0 "$COMMAND_STATUS" 'the first selection should succeed' || return 1

	DOTFILES_TEST_INPUT='3\ny\n' run_dotfiles "$FIXTURE_ROOT" --action hypr-profile
	assert_eq 0 "$COMMAND_STATUS" 'the second selection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Selected profile: laptop' 'the plan should name the current selection' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup created:' 'the replaced link should be backed up' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Selected and verified Hyprland machine profile: pc' \
		'the action should report the new profile' || return 1
	local -a backups=("$FIXTURE_STATE"/dotfiles/backups/hyprland/*/.config/hypr/machine)
	assert_eq 1 "${#backups[@]}" 'exactly one backup should exist' || return 1
	assert_eq "$(readlink -f -- "$FIXTURE_HOME/.config/dotfiles/hypr/laptop")" \
		"$(readlink -f -- "${backups[0]}")" 'the backup should keep the previous profile'
}

test_hypr_profile_decline_makes_no_changes() {
	new_fixture
	link_hyprland_package
	fake_hyprctl
	DOTFILES_TEST_INPUT='2\n\n' run_dotfiles "$FIXTURE_ROOT" --action hypr-profile

	assert_eq 0 "$COMMAND_STATUS" 'a declined selection should succeed without changes' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No changes made.' 'declining should say nothing changed' || return 1
	assert_path_absent "$FIXTURE_HOME/.config/hypr/machine" \
		'a declined selection must not write the machine link'
}

test_hypr_profile_requires_the_applied_package() {
	new_fixture
	fake_hyprctl
	DOTFILES_TEST_INPUT='2\ny\n' run_dotfiles "$FIXTURE_ROOT" --action hypr-profile

	assert_eq 1 "$COMMAND_STATUS" 'an unapplied package should fail the action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'the hyprland Stow package is not applied' \
		'the failure should name the missing package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply Stow packages and select hyprland' \
		'the failure should name a recovery' || return 1
	assert_path_absent "$FIXTURE_HOME/.config/hypr/machine" \
		'a refused selection must not write the machine link'
}

test_shared_monitors_keep_omarchy_defaults_until_a_profile_is_selected() {
	new_fixture
	link_hyprland_package
	local calls
	calls=$(CONFIG_HOME="$FIXTURE_HOME/.config" lua_monitor_calls)

	assert_contains "$calls" 'env GDK_SCALE=2' 'the unselected default should keep GDK_SCALE 2' || return 1
	assert_contains "$calls" 'monitor  preferred auto' \
		'the unselected default should configure every output from its preferred mode'
}

test_shared_monitors_apply_the_selected_profile() {
	new_fixture
	link_hyprland_package
	fake_hyprctl
	# Choose pc from the Cancel, laptop, pc list, then approve the plan.
	DOTFILES_TEST_INPUT='3\ny\n' run_dotfiles "$FIXTURE_ROOT" --action hypr-profile
	assert_eq 0 "$COMMAND_STATUS" 'selecting pc should succeed' || return 1

	local calls
	calls=$(CONFIG_HOME="$FIXTURE_HOME/.config" lua_monitor_calls)
	assert_contains "$calls" 'env GDK_SCALE=1' 'the pc profile should set GDK_SCALE 1' || return 1
	assert_contains "$calls" 'monitor DP-1 2560x1440@240 1.25' \
		'the pc profile should pin the 240 Hz mode on DP-1'
}

run_test test_hypr_profile_links_the_chosen_profile 'Select Hyprland profile links and verifies the chosen profile'
run_test test_hypr_profile_reselection_backs_up_the_previous_link 'Select Hyprland profile backs up the previous selection'
run_test test_hypr_profile_decline_makes_no_changes 'Select Hyprland profile decline makes no changes'
run_test test_hypr_profile_requires_the_applied_package 'Select Hyprland profile requires the applied package'
run_test test_shared_monitors_keep_omarchy_defaults_until_a_profile_is_selected 'Shared monitors keep Omarchy defaults until a profile is selected'
run_test test_shared_monitors_apply_the_selected_profile 'Shared monitors apply the selected machine profile'
finish_tests
