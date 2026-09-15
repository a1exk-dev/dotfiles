#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly SYSTEM24_TEMPLATE=$SOURCE_REPO/config/discord-system24/.config/omarchy/themed/discord-system24.css.tpl
readonly SYSTEM24_IMPORT="@import url('https://refact0r.github.io/system24/build/system24.css');"
readonly SYSTEM24_FONT_PLACEHOLDER=__OMARCHY_FONT__
readonly OMARCHY_TEMPLATE_RENDERER=/usr/share/omarchy/bin/omarchy-theme-set-templates
readonly -a SYSTEM24_MAPPED_COLORS=(
	text-0 text-1 text-2 text-3 text-4 text-5
	bg-1 bg-2 bg-3 bg-4
	hover active active-2 button-border
	accent-1 accent-2 accent-3 accent-4 accent-5
	red-1 red-2 red-3 red-4 red-5
	green-1 green-2 green-3 green-4 green-5
	blue-1 blue-2 blue-3 blue-4 blue-5
	yellow-1 yellow-2 yellow-3 yellow-4 yellow-5
	purple-1 purple-2 purple-3 purple-4 purple-5
)

# Renders the template through Omarchy's installed renderer against one stock
# theme's colors.toml and prints the output path.
render_system24_template() {
	local theme=$1
	local home=$FIXTURE_ROOT/render-$theme/home
	local next_theme=$home/.local/state/omarchy/current/next-theme

	mkdir -p "$home/.config/omarchy/themed" "$next_theme" "$FIXTURE_ROOT/render-$theme/omarchy" || return 1
	cp "$SYSTEM24_TEMPLATE" "$home/.config/omarchy/themed/" || return 1
	cp "/usr/share/omarchy/themes/$theme/colors.toml" "$next_theme/colors.toml" || return 1
	env -i HOME="$home" OMARCHY_PATH="$FIXTURE_ROOT/render-$theme/omarchy" \
		PATH=/usr/share/omarchy/bin:/usr/bin LC_ALL=C \
		bash "$OMARCHY_TEMPLATE_RENDERER" >&2 || return 1
	[[ -f $next_theme/discord-system24.css ]] || return 1
	printf '%s\n' "$next_theme/discord-system24.css"
}

# Prints the declarations of every top-level block whose selector is $2.
css_block_declarations() {
	awk -v selector="$2" '
		$0 ~ "^" selector " *\\{" { inside = 1; next }
		inside && /^\}/ { inside = 0; next }
		inside && /:/ { sub(/^[ \t]+/, ""); print }
	' "$1"
}

assert_valid_system24_color() {
	local name=$1 value=$2 channel

	if [[ $value =~ ^#[0-9a-fA-F]{6}$ ]]; then
		return 0
	fi
	if [[ $value =~ ^rgba\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3}),\ (0?\.[0-9]+|1(\.0+)?)\)$ ]]; then
		for channel in "${BASH_REMATCH[@]:1:3}"; do
			((10#$channel <= 255)) || {
				printf '  --%s has an rgba() channel above 255: %s\n' "$name" "$value" >&2
				return 1
			}
		done
		return 0
	fi
	printf '  --%s should be hex or valid rgba(), got %s\n' "$name" "$value" >&2
	return 1
}

assert_rendered_system24_theme() {
	local theme=$1 rendered root name value

	rendered=$(render_system24_template "$theme") || {
		printf '  %s: omarchy-theme-set-templates should render discord-system24.css\n' "$theme" >&2
		return 1
	}
	assert_eq "$SYSTEM24_IMPORT" "$(head -n 1 "$rendered")" \
		"$theme: the system24 @import should be the first line" || return 1
	if grep -q '{{' "$rendered"; then
		printf '  %s: the rendered file should have no leftover {{\n' "$theme" >&2
		return 1
	fi
	root=$(css_block_declarations "$rendered" ':root')
	for name in "${SYSTEM24_MAPPED_COLORS[@]}"; do
		value=$(sed -n "s/^--$name: \(.*\);$/\1/p" <<<"$root")
		[[ -n $value ]] || {
			printf '  %s: :root should map --%s\n' "$theme" "$name" >&2
			return 1
		}
		assert_valid_system24_color "$name" "$value" || return 1
	done
	assert_contains "$root" "color-scheme: $(env -i PATH=/usr/share/omarchy/bin:/usr/bin LC_ALL=C omarchy-theme-color --file "/usr/share/omarchy/themes/$theme/colors.toml" mode);" \
		"$theme: mode should set color-scheme"
}

test_template_renders_against_a_stock_dark_theme() {
	new_fixture || return 1
	assert_rendered_system24_theme catppuccin
}

test_template_renders_against_a_stock_light_theme() {
	new_fixture || return 1
	assert_rendered_system24_theme catppuccin-latte
}

test_template_body_sets_only_pfp_decor_and_the_font_placeholder() {
	local expected
	expected=$(printf '%s\n' \
		"--font: '$SYSTEM24_FONT_PLACEHOLDER';" \
		"--code-font: '$SYSTEM24_FONT_PLACEHOLDER';" \
		'--remove-pfp-decor: on;')

	assert_eq "$expected" "$(css_block_declarations "$SYSTEM24_TEMPLATE" body)" \
		'body should set only the font variables and --remove-pfp-decor, leaving every other system24 option at upstream' || return 1
	assert_eq 1 "$(grep -c '^body *{' "$SYSTEM24_TEMPLATE")" 'the template should have one body block' || return 1
	assert_eq 2 "$(grep -o "$SYSTEM24_FONT_PLACEHOLDER" "$SYSTEM24_TEMPLATE" | wc -l)" \
		'the font placeholder should appear only in --font and --code-font'
}

test_template_overrides_only_variables_after_the_import() {
	local selectors

	selectors=$(grep -E '^[^ \t/*}].*\{' "$SYSTEM24_TEMPLATE" | sed 's/ *{.*//')
	assert_eq $':root\nbody' "$selectors" 'the template should hold only a :root and a body block' || return 1
	assert_eq 1 "$(grep -c '^@import' "$SYSTEM24_TEMPLATE")" 'the template should import only system24'
}

test_catalog_entry_is_appended_with_the_approved_fields() {
	new_fixture || return 1
	local catalog=$FIXTURE_REPO/packages.json
	local hooks='$HOME/.config/omarchy/hooks'

	assert_eq '["hyprland","claude","discord","discord-system24"]' "$(jq -c '[.packages[-4:][].name]' "$catalog")" \
		'discord-system24 should follow every earlier entry so their wizard numbers stay stable' || return 1
	assert_eq '{"path":"config/discord-system24","dependencies":["discord"],"arch_packages":[],"aur_packages":["vencord-installer-cli-bin"]}' \
		"$(jq -c '.packages[-1] | {path, dependencies, arch_packages, aur_packages}' "$catalog")" \
		'the discord-system24 entry should declare the approved fields' || return 1
	assert_eq "bash -n \"$hooks/theme-set.d/discord-system24\""$'\n'"bash -n \"$hooks/font-set.d/discord-system24\"" \
		"$(jq -r '.packages[-1].validators[]' "$catalog")" 'the validators should run bash -n on both hooks' || return 1
	assert_contains "$(jq -r '.packages[-1].cleanup[]' "$catalog")" 'vencord-installer-cli-bin' \
		'cleanup notes should say the Vencord installer stays installed'
}

test_package_tracks_exactly_the_template_and_both_hooks() {
	new_fixture || return 1
	local package=$FIXTURE_REPO/config/discord-system24 expected

	expected=$(printf '%s\n' \
		"$package/.config/omarchy/hooks/font-set.d/discord-system24" \
		"$package/.config/omarchy/hooks/theme-set.d/discord-system24" \
		"$package/.config/omarchy/themed/discord-system24.css.tpl")
	assert_eq "$expected" "$(find "$package" \( -type f -o -type l \) -print | sort)" \
		'the package should track only the template and the two hooks' || return 1
	assert_eq "$package/.config/omarchy/hooks/theme-set.d/discord-system24" \
		"$(readlink -f "$package/.config/omarchy/hooks/font-set.d/discord-system24")" \
		'the font-set hook should run the same publication as the theme-set hook'
}

setup_system24_hook_fixture() {
	new_fixture || return 1
	SYSTEM24_THEME_HOOK=$FIXTURE_REPO/config/discord-system24/.config/omarchy/hooks/theme-set.d/discord-system24
	SYSTEM24_FONT_HOOK=$FIXTURE_REPO/config/discord-system24/.config/omarchy/hooks/font-set.d/discord-system24
	SYSTEM24_RENDERED=$FIXTURE_HOME/.local/state/omarchy/current/theme/discord-system24.css
	SYSTEM24_OUTPUT=$FIXTURE_CONFIG/Vencord/themes/omarchy-system24.css
	mkdir -p "$(dirname -- "$SYSTEM24_RENDERED")" "$FIXTURE_CONFIG/Vencord/settings" "$FIXTURE_CONFIG/Vencord/dist" || return 1
	printf '{"enabledThemes":["omarchy-system24.css"]}\n' >"$FIXTURE_CONFIG/Vencord/settings/settings.json"
	printf 'client quick css\n' >"$FIXTURE_CONFIG/Vencord/settings/quickCss.css"
	printf 'client build\n' >"$FIXTURE_CONFIG/Vencord/dist/canary"
	SYSTEM24_CLIENT_STATE=$(system24_client_state)
	set_system24_omarchy_version 4.0.3-1
	set_system24_font 'JetBrainsMono Nerd Font'
	make_fake mv 'printf "mv %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exec /usr/bin/mv "$@"'
	write_system24_rendered '#1e1e2e'
}

system24_client_state() {
	(cd -- "$FIXTURE_CONFIG/Vencord" && find settings dist -type f -exec sha256sum {} + | sort)
}

set_system24_omarchy_version() {
	make_fake omarchy "[[ \${1-} == version ]] && printf '%s\n' '$1'"
}

set_system24_font() {
	make_fake omarchy-font-current "printf '%s\n' '$1'"
}

write_system24_rendered() {
	printf "%s\n" ":root {" "	--bg-1: $1;" "}" "body {" \
		"	--font: '$SYSTEM24_FONT_PLACEHOLDER';" "	--code-font: '$SYSTEM24_FONT_PLACEHOLDER';" "}" >"$SYSTEM24_RENDERED"
}

run_system24_hook() {
	local hook=$1 argument=$2
	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" bash "$hook" "$argument"
}

assert_system24_theme() {
	local color=$1 font=$2 context=$3 published

	[[ -f $SYSTEM24_OUTPUT && ! -L $SYSTEM24_OUTPUT ]] || {
		printf '  %s: the Vencord theme should be a regular file\n' "$context" >&2
		return 1
	}
	published=$(<"$SYSTEM24_OUTPUT")
	assert_contains "$published" "--bg-1: $color;" "$context: the theme should carry the rendered colors" || return 1
	assert_contains "$published" "--font: '$font';" "$context: --font should hold the Omarchy font" || return 1
	assert_contains "$published" "--code-font: '$font';" "$context: --code-font should hold the Omarchy font" || return 1
	if [[ $published == *"$SYSTEM24_FONT_PLACEHOLDER"* ]]; then
		printf '  %s: the font placeholder should be filled\n' "$context" >&2
		return 1
	fi
}

assert_system24_client_state_untouched() {
	assert_eq "$SYSTEM24_CLIENT_STATE" "$(system24_client_state)" \
		'the hook must not write Vencord settings, quickCss.css, or dist' || return 1
	assert_eq omarchy-system24.css "$(ls -A "$FIXTURE_CONFIG/Vencord/themes")" \
		'the themes folder should hold only the published theme, with no leftover temp file'
}

test_theme_set_hook_publishes_through_a_same_folder_temp_file() {
	setup_system24_hook_fixture || return 1

	run_system24_hook "$SYSTEM24_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1
	assert_system24_theme '#1e1e2e' 'JetBrainsMono Nerd Font' 'theme set' || return 1
	[[ $(<"$CALL_LOG") =~ mv\ -f\ --\ $FIXTURE_CONFIG/Vencord/themes/\.omarchy-system24\.css\.[A-Za-z0-9]+\ $SYSTEM24_OUTPUT ]] || {
		printf '  the hook should publish by mv from a temp file in the themes folder, calls:\n%s\n' "$(<"$CALL_LOG")" >&2
		return 1
	}
	assert_system24_client_state_untouched
}

test_font_set_hook_republishes_with_the_new_font() {
	setup_system24_hook_fixture || return 1
	run_system24_hook "$SYSTEM24_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1

	set_system24_font 'Fira Code'
	run_system24_hook "$SYSTEM24_FONT_HOOK" 'Fira Code'
	assert_eq 0 "$COMMAND_STATUS" "font-set hook should publish: $COMMAND_OUTPUT" || return 1
	assert_system24_theme '#1e1e2e' 'Fira Code' 'font set' || return 1

	write_system24_rendered '#eff1f5'
	run_system24_hook "$SYSTEM24_THEME_HOOK" catppuccin-latte
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should republish: $COMMAND_OUTPUT" || return 1
	assert_system24_theme '#eff1f5' 'Fira Code' 'theme set after font set' || return 1
	assert_system24_client_state_untouched
}

test_identical_output_leaves_the_theme_untouched() {
	setup_system24_hook_fixture || return 1
	local hook before
	run_system24_hook "$SYSTEM24_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1
	before=$(stat -c '%i %y' "$SYSTEM24_OUTPUT")
	: >"$CALL_LOG"

	for hook in "$SYSTEM24_THEME_HOOK" "$SYSTEM24_FONT_HOOK"; do
		sleep 0.05
		run_system24_hook "$hook" unchanged
		assert_eq 0 "$COMMAND_STATUS" "$hook should succeed on identical output" || return 1
		assert_eq "$before" "$(stat -c '%i %y' "$SYSTEM24_OUTPUT")" "$hook should leave identical output untouched" || return 1
	done
	assert_eq '' "$(grep '^mv ' "$CALL_LOG")" 'identical output should not be moved into place' || return 1
	assert_system24_client_state_untouched
}

test_hooks_fail_closed_and_keep_the_last_good_theme() {
	local hook failure before
	for hook in theme font; do
		for failure in version rendered; do
			setup_system24_hook_fixture || return 1
			run_system24_hook "$SYSTEM24_THEME_HOOK" catppuccin
			assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1
			before=$(sha256sum "$SYSTEM24_OUTPUT")
			set_system24_font 'Fira Code'
			if [[ $failure == version ]]; then
				set_system24_omarchy_version 4.1.0-1
			else
				rm "$SYSTEM24_RENDERED"
			fi
			if [[ $hook == theme ]]; then
				run_system24_hook "$SYSTEM24_THEME_HOOK" catppuccin
			else
				run_system24_hook "$SYSTEM24_FONT_HOOK" 'Fira Code'
			fi
			[[ $COMMAND_STATUS != 0 ]] || {
				printf '  %s hook should exit non-zero on a %s failure\n' "$hook" "$failure" >&2
				return 1
			}
			assert_contains "$COMMAND_OUTPUT" 'Discord system24 hook failed:' "$hook hook should explain the $failure failure" || return 1
			assert_eq "$before" "$(sha256sum "$SYSTEM24_OUTPUT")" "$hook hook should keep the last-good theme on a $failure failure" || return 1
			assert_system24_client_state_untouched || return 1
		done
	done
}

# Creates Discord app-* directories with an unpatched resources folder.
add_discord_app_dirs() {
	local version
	for version in "$@"; do
		mkdir -p "$FIXTURE_CONFIG/discord/app-$version/resources" || return 1
		printf 'stock asar\n' >"$FIXTURE_CONFIG/discord/app-$version/resources/app.asar"
	done
}

# A fake vencord-installer-cli that logs its arguments and, like the real
# --repair, creates _app.asar in the given location unless told to skip it.
make_fake_vencord_cli() {
	local creates_backup=${1:-true}
	make_fake vencord-installer-cli "printf 'vencord-installer-cli %s\n' \"\$*\" >>\"\$DOTFILES_TEST_CALL_LOG\"
[[ \${1-} == --repair && \${2-} == --location && -d \${3-}/resources ]] || exit 64
[[ $creates_backup == false ]] || printf 'stock asar\n' >\"\$3/resources/_app.asar\""
}

# Fakes for every way the action could start or stop Discord.
make_discord_process_fakes() {
	local name
	for name in discord Discord pkill killall systemctl uwsm-app; do
		make_fake "$name" "printf '$name %s\n' \"\$*\" >>\"\$DOTFILES_TEST_CALL_LOG\""
	done
}

assert_discord_never_started_or_stopped() {
	if grep -E '^(discord|Discord|pkill|killall|systemctl|uwsm-app) ' "$CALL_LOG" >&2; then
		printf '  the action must never start or stop Discord\n' >&2
		return 1
	fi
}

setup_discord_patch_fixture() {
	new_fixture || return 1
	add_discord_app_dirs 1.0.9 1.0.157 || return 1
	NEWEST_DISCORD_APP=$FIXTURE_CONFIG/discord/app-1.0.157
	make_fake_vencord_cli
	make_discord_process_fakes
}

vencord_cli_calls() {
	grep '^vencord-installer-cli ' "$CALL_LOG" || true
}

test_patch_previews_then_repairs_the_newest_app_after_confirmation() {
	setup_discord_patch_fixture || return 1

	DOTFILES_TEST_INPUT='y\n' run_dotfiles "$FIXTURE_ROOT" --action discord-patch
	assert_eq 0 "$COMMAND_STATUS" "the patch action should succeed: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" "Discord app: $NEWEST_DISCORD_APP" 'the preview should name the newest app-*' || return 1
	assert_contains "$COMMAND_OUTPUT" "Run: vencord-installer-cli --repair --location $NEWEST_DISCORD_APP" \
		'the preview should show the command' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'the preview should show the detected Omarchy version' || return 1
	assert_eq "vencord-installer-cli --repair --location $NEWEST_DISCORD_APP" "$(vencord_cli_calls)" \
		'the action should repair only the newest app-*' || return 1
	[[ -f $NEWEST_DISCORD_APP/resources/_app.asar ]] || {
		printf '  the newest app-* should be patched\n' >&2
		return 1
	}
	assert_path_absent "$FIXTURE_CONFIG/discord/app-1.0.9/resources/_app.asar" 'older app-* directories stay untouched' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Discord patched and verified' 'the action should report verified success' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Restart Discord' 'the action should tell the human to restart Discord' || return 1
	assert_discord_never_started_or_stopped
}

test_patch_declined_runs_nothing() {
	setup_discord_patch_fixture || return 1

	DOTFILES_TEST_INPUT='n\n' run_dotfiles "$FIXTURE_ROOT" --action discord-patch
	assert_eq 0 "$COMMAND_STATUS" 'a declined patch should be a successful no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No changes made.' 'a declined patch should say nothing changed' || return 1
	assert_eq '' "$(vencord_cli_calls)" 'a declined patch must not run the CLI' || return 1
	assert_path_absent "$NEWEST_DISCORD_APP/resources/_app.asar" 'a declined patch must not patch Discord'
}

test_patch_fails_when_app_asar_backup_is_missing_after_the_cli() {
	setup_discord_patch_fixture || return 1
	make_fake_vencord_cli false

	DOTFILES_TEST_INPUT='y\n' run_dotfiles "$FIXTURE_ROOT" --action discord-patch
	assert_eq 1 "$COMMAND_STATUS" 'the action should fail when _app.asar is missing after the CLI' || return 1
	assert_contains "$COMMAND_OUTPUT" 'patch verification failed' 'the action should report the failed verification' || return 1
	if [[ $COMMAND_OUTPUT == *'Discord patched and verified'* ]]; then
		printf '  the action must not report success without _app.asar\n' >&2
		return 1
	fi
}

test_patch_asks_for_consent_on_an_omarchy_mismatch() {
	setup_discord_patch_fixture || return 1

	DOTFILES_TEST_OMARCHY_VERSION=4.1.0-1 DOTFILES_TEST_INPUT='y\nn\n' run_dotfiles "$FIXTURE_ROOT" --action discord-patch
	assert_eq 1 "$COMMAND_STATUS" 'refused mismatch consent should stop the action' || return 1
	assert_contains "$COMMAND_OUTPUT" $'Supported Omarchy: 4.0\nDetected Omarchy: 4.1.0-1' \
		'a mismatch should show the target and detected versions' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Continue despite the Omarchy version mismatch?' 'a mismatch should ask for consent' || return 1
	assert_eq '' "$(vencord_cli_calls)" 'refused consent must not run the CLI' || return 1

	DOTFILES_TEST_OMARCHY_VERSION=4.1.0-1 DOTFILES_TEST_INPUT='y\ny\n' run_dotfiles "$FIXTURE_ROOT" --action discord-patch
	assert_eq 0 "$COMMAND_STATUS" "granted consent should continue: $COMMAND_OUTPUT" || return 1
	assert_eq "vencord-installer-cli --repair --location $NEWEST_DISCORD_APP" "$(vencord_cli_calls)" \
		'granted consent should run the CLI once'
}

test_patch_stops_when_the_cli_is_missing() {
	setup_discord_patch_fixture || return 1
	rm "$FIXTURE_BIN/vencord-installer-cli"

	DOTFILES_TEST_INPUT='y\n' run_dotfiles "$FIXTURE_ROOT" --action discord-patch
	assert_eq 1 "$COMMAND_STATUS" 'a missing CLI should stop the action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'vencord-installer-cli is missing' 'the action should name the missing CLI' || return 1
	if [[ $COMMAND_OUTPUT == *'Patch Discord with Vencord?'* ]]; then
		printf '  a missing CLI should stop before the confirmation\n' >&2
		return 1
	fi
	assert_discord_never_started_or_stopped
}

test_patch_stops_when_no_app_dir_exists() {
	setup_discord_patch_fixture || return 1
	rm -rf "$FIXTURE_CONFIG/discord"

	DOTFILES_TEST_INPUT='y\n' run_dotfiles "$FIXTURE_ROOT" --action discord-patch
	assert_eq 1 "$COMMAND_STATUS" 'a missing app-* should stop the action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'no Discord app-* directory exists' 'the action should explain the missing app-*' || return 1
	assert_eq '' "$(vencord_cli_calls)" 'a missing app-* must not run the CLI' || return 1
	assert_discord_never_started_or_stopped
}

discord_system24_status_lines() {
	grep -A2 '^  discord-system24: ' <<<"$COMMAND_OUTPUT" | tail -n +2
}

discord_system24_tree_state() {
	(cd -- "$FIXTURE_CONFIG" && find discord Vencord -printf '%p %s %T@\n' 2>/dev/null | sort)
}

test_status_reports_unpatched_app_and_absent_theme_without_changes() {
	setup_discord_patch_fixture || return 1
	local before=$(discord_system24_tree_state)

	run_operation "$FIXTURE_ROOT" status
	assert_eq 0 "$COMMAND_STATUS" "status should pass: $COMMAND_OUTPUT" || return 1
	assert_eq "    Discord app: $NEWEST_DISCORD_APP (unpatched)"$'\n'"    Vencord theme: $FIXTURE_CONFIG/Vencord/themes/omarchy-system24.css (absent)" \
		"$(discord_system24_status_lines)" 'status should report the unpatched newest app-* and the absent theme below discord-system24' || return 1
	assert_eq "$before" "$(discord_system24_tree_state)" 'status must change nothing' || return 1
	assert_eq '' "$(vencord_cli_calls)" 'status must not run the CLI'
}

test_status_reports_patched_app_and_present_theme() {
	setup_discord_patch_fixture || return 1
	printf 'stock asar\n' >"$NEWEST_DISCORD_APP/resources/_app.asar"
	mkdir -p "$FIXTURE_CONFIG/Vencord/themes"
	printf ':root {}\n' >"$FIXTURE_CONFIG/Vencord/themes/omarchy-system24.css"
	local before=$(discord_system24_tree_state)

	run_operation "$FIXTURE_ROOT" status
	assert_eq 0 "$COMMAND_STATUS" "status should pass: $COMMAND_OUTPUT" || return 1
	assert_eq "    Discord app: $NEWEST_DISCORD_APP (patched)"$'\n'"    Vencord theme: $FIXTURE_CONFIG/Vencord/themes/omarchy-system24.css (present)" \
		"$(discord_system24_status_lines)" 'status should report the patched newest app-* and the present theme' || return 1
	assert_eq "$before" "$(discord_system24_tree_state)" 'status must change nothing'
}

test_apply_does_not_patch_and_names_the_patch_action() {
	setup_discord_patch_fixture || return 1
	ln -sf /usr/bin/stow "$FIXTURE_BIN/stow"
	set_installed_arch_packages discord vencord-installer-cli-bin

	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages discord-system24
	assert_eq 0 "$COMMAND_STATUS" "apply should pass: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package state: discord-system24: succeeded' 'apply should link discord-system24' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Next step: choose Patch Discord with Vencord' 'apply should name the patch action as the next step' || return 1
	assert_eq '' "$(vencord_cli_calls)" 'apply must not run the CLI' || return 1
	assert_path_absent "$NEWEST_DISCORD_APP/resources/_app.asar" 'apply must not patch Discord'
}

run_test test_catalog_entry_is_appended_with_the_approved_fields 'discord-system24 catalog entry is appended with the approved fields'
run_test test_package_tracks_exactly_the_template_and_both_hooks 'discord-system24 package tracks exactly the template and both hooks'
run_test test_theme_set_hook_publishes_through_a_same_folder_temp_file 'system24 theme-set hook publishes through a same-folder temp file'
run_test test_font_set_hook_republishes_with_the_new_font 'system24 font-set hook republishes with the new font'
run_test test_identical_output_leaves_the_theme_untouched 'system24 hooks leave identical output untouched'
run_test test_hooks_fail_closed_and_keep_the_last_good_theme 'system24 hooks fail closed and keep the last-good theme'
run_test test_template_renders_against_a_stock_dark_theme 'system24 template renders against a stock dark theme'
run_test test_template_renders_against_a_stock_light_theme 'system24 template renders against a stock light theme'
run_test test_template_body_sets_only_pfp_decor_and_the_font_placeholder 'system24 template body sets only pfp decorations and the font placeholder'
run_test test_template_overrides_only_variables_after_the_import 'system24 template overrides only variables after the import'
run_test test_patch_previews_then_repairs_the_newest_app_after_confirmation 'Discord patch previews, then repairs the newest app-* after confirmation'
run_test test_patch_declined_runs_nothing 'Discord patch declined runs nothing'
run_test test_patch_fails_when_app_asar_backup_is_missing_after_the_cli 'Discord patch fails when _app.asar is missing after the CLI'
run_test test_patch_asks_for_consent_on_an_omarchy_mismatch 'Discord patch asks for consent on an Omarchy mismatch'
run_test test_patch_stops_when_the_cli_is_missing 'Discord patch stops when the CLI is missing'
run_test test_patch_stops_when_no_app_dir_exists 'Discord patch stops when no app-* exists'
run_test test_status_reports_unpatched_app_and_absent_theme_without_changes 'status reports an unpatched app-* and absent theme without changes'
run_test test_status_reports_patched_app_and_present_theme 'status reports a patched app-* and present theme'
run_test test_apply_does_not_patch_and_names_the_patch_action 'apply does not patch Discord and names the patch action'
finish_tests
