#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly CLAUDE_SETTINGS_RELATIVE=.claude/settings.json

prepare_claude_apply() {
	local version=$1
	new_fixture || return 1
	make_fake claude "if [[ \${1-} == --version ]]; then printf '%s (Claude Code)\n' '$version'; exit 0; fi; exit 64"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " != *" --simulate "* ]]; then
	mkdir -p "$HOME/.claude"
	ln -s "$DOTFILES_TEST_REPO/config/claude/.claude/settings.json" "$HOME/.claude/settings.json"
fi'
}

assert_claude_not_linked() {
	if [[ -e $FIXTURE_HOME/$CLAUDE_SETTINGS_RELATIVE || -L $FIXTURE_HOME/$CLAUDE_SETTINGS_RELATIVE ]]; then
		printf '  %s\n' "$1" >&2
		return 1
	fi
}

test_claude_catalog_entry_is_appended_with_the_approved_fields() {
	new_fixture || return 1
	local catalog=$FIXTURE_REPO/packages.json

	assert_eq '["bash","tmux","ghostty","starship","btop","opencode","telegram-theme","screensaver-effects","hyprland","claude"]' \
		"$(jq -c '[.packages[:10][].name]' "$catalog")" \
		'claude should follow every earlier entry so their wizard numbers stay stable' || return 1
	assert_eq '{"path":"config/claude","dependencies":[],"arch_packages":[],"prerequisites":["claude","node"],"validators":[],"documentation":"docs/claude.md"}' \
		"$(jq -c '.packages[9] | {path, dependencies, arch_packages, prerequisites, validators, documentation}' "$catalog")" \
		'the claude entry should declare the approved fields' || return 1
	assert_contains "$(jq -r '.packages[9].cleanup[]' "$catalog")" '~/.claude/settings.json' \
		'cleanup notes should say which target removal leaves absent'
}

test_claude_package_tracks_only_portable_settings() {
	new_fixture || return 1
	local settings=$FIXTURE_REPO/config/claude/$CLAUDE_SETTINGS_RELATIVE command

	assert_eq "$FIXTURE_REPO/config/claude/$CLAUDE_SETTINGS_RELATIVE" \
		"$(find "$FIXTURE_REPO/config/claude" \( -type f -o -type l \) -print)" \
		'the package should hold only settings.json' || return 1
	assert_eq '["attribution","enabledPlugins","extraKnownMarketplaces","model","modelSettings","skipDangerousModePermissionPrompt","statusLine","theme","voice"]' \
		"$(jq -c 'keys' "$settings")" 'settings should hold exactly the approved keys' || return 1
	assert_eq custom:omarchy "$(jq -r '.theme' "$settings")" 'the Omarchy theme should be tracked' || return 1
	assert_eq '{"source":"github","repo":"jarrodwatts/claude-hud"}' \
		"$(jq -c '.extraKnownMarketplaces["claude-hud"].source' "$settings")" 'the claude-hud marketplace should be declared' || return 1
	assert_eq true "$(jq -r '.enabledPlugins["claude-hud@claude-hud"]' "$settings")" 'claude-hud should be enabled' || return 1
	assert_eq command "$(jq -r '.statusLine.type' "$settings")" 'the statusLine should be a command' || return 1
	command=$(jq -r '.statusLine.command' "$settings")
	assert_contains "$command" 'exec node "${plugin_dir}dist/index.js"' 'the statusLine should resolve node from PATH' || return 1
	if [[ $command == *'/home/'* || $command == *'mise/installs'* ]]; then
		printf '  the statusLine must not contain a home or versioned runtime path\n' >&2
		return 1
	fi
}

test_claude_apply_passes_at_the_minimum_version() {
	prepare_claude_apply 2.1.270 || return 1
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages claude

	assert_eq 0 "$COMMAND_STATUS" 'apply should pass at 2.1.270' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Claude Code: 2.1.270' 'the gate should report the detected version' || return 1
	assert_eq "$FIXTURE_REPO/config/claude/$CLAUDE_SETTINGS_RELATIVE" \
		"$(readlink -f "$FIXTURE_HOME/$CLAUDE_SETTINGS_RELATIVE")" 'apply should link settings.json' || return 1
	if [[ -L $FIXTURE_HOME/.claude ]]; then
		printf '  ~/.claude must stay an ordinary directory\n' >&2
		return 1
	fi
}

test_claude_apply_blocks_below_the_minimum_version() {
	prepare_claude_apply 2.1.269 || return 1
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages claude

	assert_eq 1 "$COMMAND_STATUS" 'apply should block below 2.1.270' || return 1
	assert_contains "$COMMAND_OUTPUT" 'below the minimum supported version 2.1.270' 'the block should name the floor' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: plan phase failed for package claude.' 'the block should happen in planning' || return 1
	assert_claude_not_linked 'a blocked apply must not link settings.json'
}

test_claude_apply_warns_and_continues_on_another_minor() {
	prepare_claude_apply 2.2.0 || return 1
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages claude

	assert_eq 0 "$COMMAND_STATUS" 'another minor should warn and continue' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: detected Claude Code 2.2.0 is outside the supported 2.1 series' \
		'the warning should name both versions' || return 1
	assert_contains "$COMMAND_OUTPUT" 'docs/claude.md' 'the warning should point at the default-config re-check' || return 1
	assert_eq "$FIXTURE_REPO/config/claude/$CLAUDE_SETTINGS_RELATIVE" \
		"$(readlink -f "$FIXTURE_HOME/$CLAUDE_SETTINGS_RELATIVE")" 'apply should still link settings.json'
}

test_claude_apply_blocks_when_the_version_is_unreadable() {
	prepare_claude_apply 2.1.270 || return 1
	make_fake claude 'exit 1'
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages claude

	assert_eq 1 "$COMMAND_STATUS" 'a claude command without a readable version should block apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: cannot read the Claude Code version' 'the block should say why' || return 1
	assert_claude_not_linked 'an unreadable version must not link settings.json'
}

test_claude_apply_stops_when_the_cli_is_missing() {
	prepare_claude_apply 2.1.270 || return 1
	rm "$FIXTURE_BIN/claude"
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages claude

	assert_eq 1 "$COMMAND_STATUS" 'a missing claude prerequisite should stop apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing package prerequisite for claude: claude' 'the missing command should be named' || return 1
	assert_claude_not_linked 'a missing prerequisite must not link settings.json'
}

run_test test_claude_catalog_entry_is_appended_with_the_approved_fields 'claude catalog entry is appended with the approved fields'
run_test test_claude_package_tracks_only_portable_settings 'claude package tracks only portable settings'
run_test test_claude_apply_passes_at_the_minimum_version 'claude apply passes at 2.1.270'
run_test test_claude_apply_blocks_below_the_minimum_version 'claude apply blocks at 2.1.269'
run_test test_claude_apply_warns_and_continues_on_another_minor 'claude apply warns and continues at 2.2.0'
run_test test_claude_apply_blocks_when_the_version_is_unreadable 'claude apply blocks when the version is unreadable'
run_test test_claude_apply_stops_when_the_cli_is_missing 'claude apply stops when the CLI is missing'
finish_tests
