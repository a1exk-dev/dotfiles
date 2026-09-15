#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly DISCORD_SETTINGS_RELATIVE=.config/discord/settings.json

test_discord_catalog_entry_is_appended_with_the_approved_fields() {
	new_fixture || return 1
	local catalog=$FIXTURE_REPO/packages.json

	assert_eq '["bash","tmux","ghostty","starship","btop","opencode","telegram-theme","screensaver-effects","hyprland","claude","discord"]' \
		"$(jq -c '[.packages[:11][].name]' "$catalog")" \
		'discord should follow every earlier entry so their wizard numbers stay stable' || return 1
	assert_eq '{"path":"config/discord","dependencies":[],"arch_packages":["discord"],"prerequisites":[],"documentation":"docs/discord.md"}' \
		"$(jq -c '.packages[10] | {path, dependencies, arch_packages, prerequisites, documentation}' "$catalog")" \
		'the discord entry should declare the approved fields' || return 1
	assert_contains "$(jq -r '.packages[10].cleanup[]' "$catalog")" '~/.config/discord/settings.json' \
		'cleanup notes should say which target removal leaves absent'
}

test_discord_package_tracks_only_client_settings() {
	new_fixture || return 1
	local settings=$FIXTURE_REPO/config/discord/$DISCORD_SETTINGS_RELATIVE

	assert_eq "$settings" "$(find "$FIXTURE_REPO/config/discord" \( -type f -o -type l \) -print)" \
		'the package should hold only settings.json' || return 1
	jq -e 'type == "object"' "$settings" >/dev/null || {
		printf '  settings.json should be a JSON object\n' >&2
		return 1
	}
	if grep -q -i -E 'token|email|user_?id|/home/' "$settings"; then
		printf '  settings.json must not contain account data or home paths\n' >&2
		return 1
	fi
}

test_discord_apply_links_settings_and_runs_the_validator() {
	new_fixture || return 1
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " != *" --simulate "* ]]; then
	mkdir -p "$HOME/.config/discord"
	ln -s "$DOTFILES_TEST_REPO/config/discord/.config/discord/settings.json" "$HOME/.config/discord/settings.json"
fi'
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages discord

	assert_eq 0 "$COMMAND_STATUS" 'apply should pass' || return 1
	assert_eq "$FIXTURE_REPO/config/discord/$DISCORD_SETTINGS_RELATIVE" \
		"$(readlink -f "$FIXTURE_HOME/$DISCORD_SETTINGS_RELATIVE")" 'apply should link settings.json' || return 1
	if [[ -L $FIXTURE_HOME/.config/discord ]]; then
		printf '  ~/.config/discord must stay an ordinary directory\n' >&2
		return 1
	fi
}

run_test test_discord_catalog_entry_is_appended_with_the_approved_fields 'discord catalog entry is appended with the approved fields'
run_test test_discord_package_tracks_only_client_settings 'discord package tracks only client settings'
run_test test_discord_apply_links_settings_and_runs_the_validator 'discord apply links settings.json and runs the validator'
finish_tests
