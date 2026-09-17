#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly OBS_THEME_PACKAGE=config/obs-theme
readonly OBS_THEME_TEMPLATE=$SOURCE_REPO/$OBS_THEME_PACKAGE/.config/omarchy/themed/obs-omarchy.ovt.tpl
readonly OBS_THEME_FRAGMENT=$SOURCE_REPO/$OBS_THEME_PACKAGE/.config/omarchy/hooks/theme-set.d/obs-theme.d/light-icons.ovt
readonly OBS_THEME_ID=dev.dotfiles.omarchy
readonly OBS_STOCK_LIGHT=/usr/share/obs/obs-studio/themes/Yami_Light.ovt
readonly OMARCHY_TEMPLATE_RENDERER=/usr/share/omarchy/bin/omarchy-theme-set-templates

# Renders the template through Omarchy's installed renderer against one stock
# theme's colors.toml and prints the output path.
render_obs_template() {
	local theme=$1
	local home=$FIXTURE_ROOT/render-$theme/home
	local next_theme=$home/.local/state/omarchy/current/next-theme

	mkdir -p "$home/.config/omarchy/themed" "$next_theme" "$FIXTURE_ROOT/render-$theme/omarchy" || return 1
	cp "$OBS_THEME_TEMPLATE" "$home/.config/omarchy/themed/" || return 1
	cp "/usr/share/omarchy/themes/$theme/colors.toml" "$next_theme/colors.toml" || return 1
	env -i HOME="$home" OMARCHY_PATH="$FIXTURE_ROOT/render-$theme/omarchy" \
		PATH=/usr/share/omarchy/bin:/usr/bin LC_ALL=C \
		bash "$OMARCHY_TEMPLATE_RENDERER" >&2 || return 1
	[[ -f $next_theme/obs-omarchy.ovt ]] || return 1
	printf '%s\n' "$next_theme/obs-omarchy.ovt"
}

stock_color() {
	env -i PATH=/usr/share/omarchy/bin:/usr/bin LC_ALL=C \
		omarchy-theme-color --file "/usr/share/omarchy/themes/$1/colors.toml" "$2"
}

# Omarchy's mix, recomputed here so the test does not trust the renderer's own arithmetic.
expected_mix() {
	local a=${1#\#} b=${2#\#} percent=$3 index out='#' x y
	for index in 0 2 4; do
		x=$((16#${a:index:2}))
		y=$((16#${b:index:2}))
		out+=$(printf '%02x' $(((x * (100 - percent) + y * percent + 50) / 100)))
	done
	printf '%s\n' "$out"
}

ovt_variable() {
	sed -n "s/^ *--$2: \(.*\);$/\1/p" "$1"
}

assert_ovt_variable() {
	local file=$1 name=$2 expected=$3 context=$4
	assert_eq "$expected" "$(ovt_variable "$file" "$name")" "$context: --$name"
}

assert_rendered_obs_theme() {
	local theme=$1 rendered background foreground accent

	rendered=$(render_obs_template "$theme") || {
		printf '  %s: omarchy-theme-set-templates should render obs-omarchy.ovt\n' "$theme" >&2
		return 1
	}
	if grep -q '{{' "$rendered"; then
		printf '  %s: the rendered file should have no leftover {{\n' "$theme" >&2
		return 1
	fi
	assert_contains "$(<"$rendered")" "/* Omarchy mode: $(stock_color "$theme" mode) */" \
		"$theme: the render should carry the theme mode for the publish hook" || return 1
	assert_contains "$(<"$rendered")" "extends: 'com.obsproject.Yami';" "$theme: the theme should extend Yami" || return 1
	background=$(stock_color "$theme" background)
	foreground=$(stock_color "$theme" foreground)
	accent=$(stock_color "$theme" accent)
	assert_ovt_variable "$rendered" bg_window "$background" "$theme: flat surface" || return 1
	assert_ovt_variable "$rendered" bg_base "$background" "$theme: flat surface" || return 1
	assert_ovt_variable "$rendered" border_color "$(expected_mix "$foreground" "$background" 40)" "$theme: 1px border" || return 1
	assert_ovt_variable "$rendered" input_border_focus "$accent" "$theme: focus" || return 1
	assert_ovt_variable "$rendered" list_item_bg_selected "$(stock_color "$theme" selection)" "$theme: selection" || return 1
	assert_ovt_variable "$rendered" border_radius 0px "$theme: square corners" || return 1
	assert_ovt_variable "$rendered" red3 "$(stock_color "$theme" red)" "$theme: own red" || return 1
	assert_ovt_variable "$rendered" green3 "$(stock_color "$theme" green)" "$theme: own green" || return 1
	assert_ovt_variable "$rendered" yellow3 "$(stock_color "$theme" yellow)" "$theme: own yellow" || return 1
	assert_ovt_variable "$rendered" danger "$(stock_color "$theme" red)" "$theme: danger" || return 1
	assert_ovt_variable "$rendered" warning "$(stock_color "$theme" yellow)" "$theme: warning" || return 1
	assert_ovt_variable "$rendered" grey1 "$(expected_mix "$foreground" "$background" 25)" "$theme: grey ramp" || return 1
	assert_ovt_variable "$rendered" grey3 "$(expected_mix "$background" "$foreground" 20)" "$theme: grey ramp"
}

test_template_renders_against_a_stock_dark_theme() {
	new_fixture || return 1
	assert_rendered_obs_theme catppuccin
}

test_template_renders_against_a_stock_light_theme() {
	new_fixture || return 1
	assert_rendered_obs_theme catppuccin-latte
}

# Prints "selector|declaration" pairs for every theme:Light/ declaration.
light_icon_pairs() {
	awk '
		BEGIN { RS = "}" }
		{
			block = $0
			gsub(/\/\*[^*]*\*\//, "", block)
			if (index(block, "{") == 0 || block ~ /@OBSTheme/) next
			selector = substr(block, 1, index(block, "{") - 1)
			gsub(/[ \t\n]+/, " ", selector)
			gsub(/^ | $/, "", selector)
			n = split(substr(block, index(block, "{") + 1), declarations, ";")
			for (i = 1; i <= n; i++) {
				declaration = declarations[i]
				gsub(/^[ \t\n]+|[ \t\n]+$/, "", declaration)
				if (declaration ~ /theme:Light\//) print selector "|" declaration
			}
		}
	' "$1" | sort
}

test_light_icon_fragment_matches_the_installed_yami_light() {
	if [[ ! -f $OBS_STOCK_LIGHT ]]; then
		printf '  notice: OBS is not installed; skipped the Yami_Light.ovt comparison\n' >&2
		return 0
	fi
	local expected
	expected=$(light_icon_pairs "$OBS_STOCK_LIGHT")
	assert_eq 83 "$(wc -l <<<"$expected")" 'Yami_Light.ovt should hold 83 light-icon declarations' || return 1
	assert_eq "$expected" "$(light_icon_pairs "$OBS_THEME_FRAGMENT")" \
		'the fragment should hold exactly the theme:Light/ declarations of the installed Yami_Light.ovt' || return 1
	if grep ';' "$OBS_THEME_FRAGMENT" | grep -qv 'theme:Light/'; then
		printf '  the fragment should declare nothing but light icons\n' >&2
		return 1
	fi
}

test_catalog_entry_follows_every_earlier_entry_with_the_approved_fields() {
	new_fixture || return 1
	local catalog=$FIXTURE_REPO/packages.json hooks='$HOME/.config/omarchy/hooks'

	assert_eq '["discord-system24","obs-theme"]' \
		"$(jq -c '[.packages[] | .name] | .[index("discord-system24"):index("obs-theme") + 1]' "$catalog")" \
		'obs-theme should follow every entry that existed before it' || return 1
	assert_eq '{"path":"config/obs-theme","dependencies":[],"arch_packages":["obs-studio"],"aur_packages":null,"prerequisites":[],"documentation":"docs/obs.md"}' \
		"$(jq -c '.packages[] | select(.name == "obs-theme") | {path, dependencies, arch_packages, aur_packages, prerequisites, documentation}' "$catalog")" \
		'the obs-theme entry should declare the approved fields' || return 1
	assert_eq "bash -n \"$hooks/theme-set.d/obs-theme\""$'\n'"bash -n \"$hooks/font-set.d/obs-theme\"" \
		"$(jq -r '.packages[] | select(.name == "obs-theme") | .validators[]' "$catalog")" \
		'the validators should run bash -n on both hooks' || return 1
	assert_eq false "$(jq '[.applications[] | tostring | test("obs-studio")] | any' "$FIXTURE_REPO/applications.json")" \
		'obs-studio should not be an optional application'
}

test_package_tracks_exactly_the_template_hooks_and_fragment() {
	new_fixture || return 1
	local package=$FIXTURE_REPO/$OBS_THEME_PACKAGE expected

	expected=$(printf '%s\n' \
		"$package/.config/omarchy/hooks/font-set.d/obs-theme" \
		"$package/.config/omarchy/hooks/theme-set.d/obs-theme" \
		"$package/.config/omarchy/hooks/theme-set.d/obs-theme.d/light-icons.ovt" \
		"$package/.config/omarchy/themed/obs-omarchy.ovt.tpl")
	assert_eq "$expected" "$(find "$package" \( -type f -o -type l \) -print | sort)" \
		'the package should track only the template, both hooks and the fragment' || return 1
	assert_eq "$package/.config/omarchy/hooks/theme-set.d/obs-theme" \
		"$(readlink -f "$package/.config/omarchy/hooks/font-set.d/obs-theme")" \
		'the font-set hook should run the same publish script'
}

set_obs_omarchy_version() {
	make_fake omarchy "[[ \${1-} == version ]] && printf '%s\n' '$1'"
}

set_obs_font() {
	make_fake omarchy-font-current "printf '%s\n' '$1'"
}

set_obs_version() {
	make_fake obs "[[ \${1-} == --version ]] && printf 'OBS Studio - %s\n' '$1'"
}

set_obs_running() {
	if [[ $1 == true ]]; then
		make_fake pgrep '[[ $* == "-x obs" ]] && exit 0; exit 1'
	else
		make_fake pgrep 'exit 1'
	fi
}

# Copies a real render for one stock theme into Omarchy's current theme state.
use_rendered_theme() {
	local rendered
	rendered=$(render_obs_template "$1") || return 1
	cp "$rendered" "$OBS_RENDERED"
}

setup_obs_hook_fixture() {
	new_fixture || return 1
	OBS_THEME_HOOK=$FIXTURE_REPO/$OBS_THEME_PACKAGE/.config/omarchy/hooks/theme-set.d/obs-theme
	OBS_FONT_HOOK=$FIXTURE_REPO/$OBS_THEME_PACKAGE/.config/omarchy/hooks/font-set.d/obs-theme
	OBS_RENDERED=$FIXTURE_HOME/.local/state/omarchy/current/theme/obs-omarchy.ovt
	OBS_THEMES=$FIXTURE_CONFIG/obs-studio/themes
	OBS_OUTPUT=$OBS_THEMES/Omarchy.ovt
	mkdir -p "$(dirname -- "$OBS_RENDERED")" || return 1
	set_obs_omarchy_version 4.0.3-1
	set_obs_font 'JetBrainsMono Nerd Font'
	set_obs_version 32.2.2
	make_fake mv 'printf "mv %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exec /usr/bin/mv "$@"'
	use_rendered_theme catppuccin
}

run_obs_hook() {
	run_in_sandbox "$FIXTURE_ROOT" "${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" bash "$1" "$2"
}

assert_published_obs_theme() {
	local mode=$1 font=$2 context=$3 published

	[[ -f $OBS_OUTPUT && ! -L $OBS_OUTPUT ]] || {
		printf '  %s: Omarchy.ovt should be a regular file\n' "$context" >&2
		return 1
	}
	published=$(<"$OBS_OUTPUT")
	assert_contains "$published" "id: '$OBS_THEME_ID';" "$context: the theme should carry the Omarchy id" || return 1
	assert_contains "$published" "name: 'Omarchy';" "$context: the theme should carry a name" || return 1
	assert_contains "$published" "extends: 'com.obsproject.Yami';" "$context: the theme should extend Yami" || return 1
	assert_contains "$published" "font-family: \"$font\";" "$context: the theme should use the Omarchy font" || return 1
	if [[ $published == *__OMARCHY* ]]; then
		printf '  %s: every placeholder should be filled\n' "$context" >&2
		return 1
	fi
	if [[ $mode == light ]]; then
		assert_contains "$published" "dark: 'false';" "$context: a light theme is not dark" || return 1
		assert_eq 83 "$(grep -c 'theme:Light/' "$OBS_OUTPUT")" "$context: a light theme should carry the light icons"
	else
		assert_contains "$published" "dark: 'true';" "$context: a dark theme is dark" || return 1
		assert_eq 0 "$(grep -c 'theme:Light/' "$OBS_OUTPUT")" "$context: a dark theme should keep Yami's icons"
	fi
}

assert_only_the_theme_in_the_themes_folder() {
	assert_eq Omarchy.ovt "$(ls -A "$OBS_THEMES")" \
		'the themes folder should hold only Omarchy.ovt, with no leftover temp file'
}

test_theme_hook_publishes_a_dark_theme_through_a_same_folder_temp_file() {
	setup_obs_hook_fixture || return 1

	run_obs_hook "$OBS_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1
	assert_published_obs_theme dark 'JetBrainsMono Nerd Font' 'dark theme' || return 1
	[[ $(<"$CALL_LOG") =~ mv\ -f\ --\ $OBS_THEMES/\.Omarchy\.ovt\.[A-Za-z0-9]+\ $OBS_OUTPUT ]] || {
		printf '  the hook should publish by mv from a temp file in the themes folder, calls:\n%s\n' "$(<"$CALL_LOG")" >&2
		return 1
	}
	assert_only_the_theme_in_the_themes_folder
}

test_theme_hook_appends_the_light_icons_on_a_light_theme() {
	setup_obs_hook_fixture || return 1
	use_rendered_theme catppuccin-latte || return 1

	run_obs_hook "$OBS_THEME_HOOK" catppuccin-latte
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1
	assert_published_obs_theme light 'JetBrainsMono Nerd Font' 'light theme' || return 1

	use_rendered_theme catppuccin || return 1
	run_obs_hook "$OBS_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should republish: $COMMAND_OUTPUT" || return 1
	assert_published_obs_theme dark 'JetBrainsMono Nerd Font' 'dark theme after light'
}

test_font_hook_republishes_with_the_new_font() {
	setup_obs_hook_fixture || return 1
	run_obs_hook "$OBS_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1

	set_obs_font 'Fira Code'
	run_obs_hook "$OBS_FONT_HOOK" 'Fira Code'
	assert_eq 0 "$COMMAND_STATUS" "font-set hook should publish: $COMMAND_OUTPUT" || return 1
	assert_published_obs_theme dark 'Fira Code' 'font set' || return 1
	assert_only_the_theme_in_the_themes_folder
}

test_identical_output_leaves_the_theme_untouched() {
	setup_obs_hook_fixture || return 1
	local hook before
	run_obs_hook "$OBS_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1
	before=$(stat -c '%i %y' "$OBS_OUTPUT")
	: >"$CALL_LOG"

	for hook in "$OBS_THEME_HOOK" "$OBS_FONT_HOOK"; do
		sleep 0.05
		run_obs_hook "$hook" unchanged
		assert_eq 0 "$COMMAND_STATUS" "$hook should succeed on identical output" || return 1
		assert_eq "$before" "$(stat -c '%i %y' "$OBS_OUTPUT")" "$hook should leave identical output untouched" || return 1
	done
	assert_eq '' "$(grep '^mv ' "$CALL_LOG")" 'identical output should not be moved into place' || return 1
	assert_only_the_theme_in_the_themes_folder
}

test_hooks_fail_closed_and_keep_the_last_published_theme() {
	local hook failure before
	for hook in theme font; do
		for failure in version rendered; do
			setup_obs_hook_fixture || return 1
			run_obs_hook "$OBS_THEME_HOOK" catppuccin
			assert_eq 0 "$COMMAND_STATUS" "theme-set hook should publish: $COMMAND_OUTPUT" || return 1
			before=$(sha256sum "$OBS_OUTPUT")
			set_obs_font 'Fira Code'
			if [[ $failure == version ]]; then
				set_obs_omarchy_version 4.1.0-1
			else
				rm "$OBS_RENDERED"
			fi
			if [[ $hook == theme ]]; then
				run_obs_hook "$OBS_THEME_HOOK" catppuccin
			else
				run_obs_hook "$OBS_FONT_HOOK" 'Fira Code'
			fi
			[[ $COMMAND_STATUS != 0 ]] || {
				printf '  %s hook should exit non-zero on a %s failure\n' "$hook" "$failure" >&2
				return 1
			}
			assert_contains "$COMMAND_OUTPUT" 'OBS theme hook failed:' "the hook should explain the $failure failure" || return 1
			assert_eq "$before" "$(sha256sum "$OBS_OUTPUT")" "the hook should keep the last theme on a $failure failure" || return 1
		done
	done
	setup_obs_hook_fixture || return 1
	set_obs_omarchy_version 4.1.0-1
	run_obs_hook "$OBS_THEME_HOOK" catppuccin
	assert_contains "$COMMAND_OUTPUT" 'Required: 4.0.x; detected: 4.1.0-1' 'the version failure should name both versions'
}

# Prints a PATH of fake-bin and every host /usr/bin command except obs.
obs_test_path_without_obs() {
	local restricted_bin=$FIXTURE_ROOT/obs-restricted-bin source
	mkdir -p "$restricted_bin"
	for source in /usr/bin/*; do
		[[ ${source##*/} != obs ]] || continue
		ln -s "$source" "$restricted_bin/"
	done
	printf '%s:%s\n' "$FIXTURE_BIN" "$restricted_bin"
}

test_hooks_warn_and_publish_outside_the_obs_series() {
	setup_obs_hook_fixture || return 1
	set_obs_version 33.0.1

	run_obs_hook "$OBS_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "an OBS mismatch should still publish: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: OBS 33.0.1 is outside the tested 32.2 series' 'the hook should warn with both versions' || return 1
	assert_published_obs_theme dark 'JetBrainsMono Nerd Font' 'OBS mismatch' || return 1

	rm "$FIXTURE_BIN/obs" "$OBS_OUTPUT"
	DOTFILES_TEST_PATH=$(obs_test_path_without_obs) run_obs_hook "$OBS_FONT_HOOK" 'JetBrainsMono Nerd Font'
	assert_eq 0 "$COMMAND_STATUS" "a missing OBS should still publish: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: could not detect the OBS version' 'the hook should warn about the missing OBS' || return 1
	assert_published_obs_theme dark 'JetBrainsMono Nerd Font' 'missing OBS'
}

# A user.ini shaped like the one OBS writes: sections separated by blank lines.
write_user_ini() {
	mkdir -p "$FIXTURE_CONFIG/obs-studio" || return 1
	printf '%s\n' "$@" >"$FIXTURE_CONFIG/obs-studio/user.ini"
}

user_ini() {
	cat "$FIXTURE_CONFIG/obs-studio/user.ini"
}

setup_obs_apply_fixture() {
	new_fixture || return 1
	ln -sf /usr/bin/stow "$FIXTURE_BIN/stow"
	set_installed_arch_packages obs-studio
	set_obs_version 32.2.2
	set_obs_running false
	OBS_USER_INI=$FIXTURE_CONFIG/obs-studio/user.ini
	OBS_BACKUPS=$FIXTURE_CONFIG/obs-studio/backups
}

apply_obs_theme() {
	DOTFILES_TEST_INPUT=${1-'y\n'} run_operation "$FIXTURE_ROOT" apply_packages obs-theme
}

test_apply_selects_the_theme_and_changes_only_the_two_keys() {
	setup_obs_apply_fixture || return 1
	write_user_ini '[General]' 'FirstRun=true' '' '[Appearance]' 'FontScale=10' 'Theme=com.obsproject.Yami.Grey' '' '[Basic]' 'Profile=Twitch'

	apply_obs_theme
	assert_eq 0 "$COMMAND_STATUS" "apply should pass: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package state: obs-theme: succeeded' 'apply should link obs-theme' || return 1
	assert_eq "$(printf '%s\n' '[General]' 'FirstRun=true' '' '[Appearance]' 'FontScale=10' "Theme=$OBS_THEME_ID" 'AutoReload=true' '' '[Basic]' 'Profile=Twitch')" \
		"$(user_ini)" 'apply should set only Theme and AutoReload' || return 1
	assert_eq 1 "$(find "$OBS_BACKUPS" -name 'user.ini.*' | wc -l)" 'apply should back up user.ini once' || return 1
	assert_contains "$(cat "$OBS_BACKUPS"/user.ini.*)" 'Theme=com.obsproject.Yami.Grey' 'the backup should hold the previous user.ini' || return 1
	assert_eq '' "$(find "$FIXTURE_CONFIG/obs-studio" -maxdepth 1 -name '.*')" 'no temporary file should remain' || return 1
	[[ -L $FIXTURE_HOME/.config/omarchy/hooks/theme-set.d/obs-theme ]] || {
		printf '  the theme hook should be linked\n' >&2
		return 1
	}

	apply_obs_theme
	assert_eq 0 "$COMMAND_STATUS" "a second apply should pass: $COMMAND_OUTPUT" || return 1
	assert_eq 1 "$(find "$OBS_BACKUPS" -name 'user.ini.*' | wc -l)" 'an unchanged user.ini should not be backed up again'
}

test_apply_adds_a_missing_appearance_section() {
	setup_obs_apply_fixture || return 1
	write_user_ini '[General]' 'FirstRun=true' '' '[Basic]' 'Profile=Twitch'

	apply_obs_theme
	assert_eq 0 "$COMMAND_STATUS" "apply should pass: $COMMAND_OUTPUT" || return 1
	assert_eq "$(printf '%s\n' '[General]' 'FirstRun=true' '' '[Basic]' 'Profile=Twitch' '' '[Appearance]' "Theme=$OBS_THEME_ID" 'AutoReload=true')" \
		"$(user_ini)" 'apply should append the Appearance section'
}

test_apply_leaves_user_ini_alone_while_obs_runs() {
	setup_obs_apply_fixture || return 1
	write_user_ini '[Appearance]' 'Theme=com.obsproject.Yami'
	set_obs_running true
	local before=$(user_ini)

	apply_obs_theme
	assert_eq 0 "$COMMAND_STATUS" "apply should still pass: $COMMAND_OUTPUT" || return 1
	assert_eq "$before" "$(user_ini)" 'a running OBS must keep user.ini unchanged' || return 1
	assert_contains "$COMMAND_OUTPUT" 'OBS is running' 'apply should say why it skipped' || return 1
	assert_contains "$COMMAND_OUTPUT" 'close OBS, then choose Apply Stow packages again' 'apply should name the rerun' || return 1
	assert_path_absent "$OBS_BACKUPS" 'a skipped step should not back up user.ini'
}

test_apply_skips_the_step_before_obs_first_ran() {
	setup_obs_apply_fixture || return 1

	apply_obs_theme
	assert_eq 0 "$COMMAND_STATUS" "apply should pass: $COMMAND_OUTPUT" || return 1
	assert_path_absent "$OBS_USER_INI" 'apply must not create user.ini' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Start and close OBS once' 'apply should say how to create user.ini'
}

test_apply_asks_for_consent_outside_the_obs_series() {
	setup_obs_apply_fixture || return 1
	write_user_ini '[Appearance]' 'Theme=com.obsproject.Yami'
	set_obs_version 33.0.1
	local before=$(user_ini)

	apply_obs_theme 'y\nn\n'
	assert_eq 0 "$COMMAND_STATUS" "a declined OBS consent should skip the step: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" $'Tested OBS: 32.2\nDetected OBS: 33.0.1' 'the step should show both versions' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Continue despite the OBS version mismatch?' 'the step should ask for consent' || return 1
	assert_eq "$before" "$(user_ini)" 'a declined consent must keep user.ini unchanged' || return 1

	apply_obs_theme 'y\ny\n'
	assert_eq 0 "$COMMAND_STATUS" "a granted consent should write: $COMMAND_OUTPUT" || return 1
	assert_contains "$(user_ini)" "Theme=$OBS_THEME_ID" 'a granted consent should select the theme'
}

setup_obs_remove_fixture() {
	setup_obs_apply_fixture || return 1
	write_user_ini '[Appearance]' 'FontScale=10' '' '[Basic]' 'Profile=Twitch'
	apply_obs_theme
	assert_eq 0 "$COMMAND_STATUS" "apply should link obs-theme: $COMMAND_OUTPUT" || return 1
	mkdir -p "$FIXTURE_CONFIG/obs-studio/themes" || return 1
	printf 'published\n' >"$FIXTURE_CONFIG/obs-studio/themes/Omarchy.ovt"
	printf 'other\n' >"$FIXTURE_CONFIG/obs-studio/themes/Other.ovt"
}

test_remove_is_blocked_while_obs_runs() {
	setup_obs_remove_fixture || return 1
	set_obs_running true
	local before=$(user_ini)

	run_operation "$FIXTURE_ROOT" remove_package obs-theme --yes
	assert_eq 1 "$COMMAND_STATUS" "removal should be blocked: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'OBS is running' 'removal should say why it stopped' || return 1
	[[ -f $FIXTURE_CONFIG/obs-studio/themes/Omarchy.ovt && -L $FIXTURE_HOME/.config/omarchy/hooks/theme-set.d/obs-theme ]] || {
		printf '  the theme and links should stay in place\n' >&2
		return 1
	}
	assert_eq "$before" "$(user_ini)" 'a blocked removal must keep user.ini unchanged'
}

test_remove_deletes_the_theme_and_resets_a_matching_id() {
	setup_obs_remove_fixture || return 1

	run_operation "$FIXTURE_ROOT" remove_package obs-theme --yes
	assert_eq 0 "$COMMAND_STATUS" "removal should succeed: $COMMAND_OUTPUT" || return 1
	assert_path_absent "$FIXTURE_CONFIG/obs-studio/themes/Omarchy.ovt" 'removal should delete Omarchy.ovt' || return 1
	[[ -f $FIXTURE_CONFIG/obs-studio/themes/Other.ovt ]] || {
		printf '  removal must keep other themes\n' >&2
		return 1
	}
	assert_path_absent "$FIXTURE_HOME/.config/omarchy/hooks/theme-set.d/obs-theme" 'removal should unlink the package' || return 1
	assert_eq "$(printf '%s\n' '[Appearance]' 'FontScale=10' 'Theme=com.obsproject.Yami' 'AutoReload=true' '' '[Basic]' 'Profile=Twitch')" \
		"$(user_ini)" 'removal should reset only the theme id and keep AutoReload' || return 1
	local note
	for note in 'AutoReload=true remains' 'obs-studio remains installed' 'obs-omarchy.ovt stays in Omarchy' 'belong to OBS'; do
		assert_contains "$COMMAND_OUTPUT" "$note" 'removal should print every cleanup note' || return 1
	done
}

test_remove_keeps_a_theme_id_the_human_changed() {
	setup_obs_remove_fixture || return 1
	write_user_ini '[Appearance]' 'Theme=com.obsproject.Yami.Grey' 'AutoReload=true'
	local before=$(user_ini)

	run_operation "$FIXTURE_ROOT" remove_package obs-theme --yes
	assert_eq 0 "$COMMAND_STATUS" "removal should succeed: $COMMAND_OUTPUT" || return 1
	assert_eq "$before" "$(user_ini)" 'removal must keep a theme id that is not the Omarchy one' || return 1
	assert_path_absent "$FIXTURE_CONFIG/obs-studio/themes/Omarchy.ovt" 'removal should delete Omarchy.ovt'
}

run_test test_template_renders_against_a_stock_dark_theme 'OBS template renders against a stock dark theme'
run_test test_template_renders_against_a_stock_light_theme 'OBS template renders against a stock light theme'
run_test test_light_icon_fragment_matches_the_installed_yami_light 'light-icon fragment matches the installed Yami_Light.ovt'
run_test test_catalog_entry_follows_every_earlier_entry_with_the_approved_fields 'obs-theme catalog entry follows earlier entries with the approved fields'
run_test test_package_tracks_exactly_the_template_hooks_and_fragment 'obs-theme package tracks exactly the template, hooks and fragment'
run_test test_theme_hook_publishes_a_dark_theme_through_a_same_folder_temp_file 'OBS theme hook publishes a dark theme through a same-folder temp file'
run_test test_theme_hook_appends_the_light_icons_on_a_light_theme 'OBS theme hook appends the light icons on a light theme'
run_test test_font_hook_republishes_with_the_new_font 'OBS font hook republishes with the new font'
run_test test_identical_output_leaves_the_theme_untouched 'OBS hooks leave identical output untouched'
run_test test_hooks_fail_closed_and_keep_the_last_published_theme 'OBS hooks fail closed and keep the last theme'
run_test test_hooks_warn_and_publish_outside_the_obs_series 'OBS hooks warn and publish outside the OBS series'
run_test test_apply_selects_the_theme_and_changes_only_the_two_keys 'apply selects the theme and changes only two user.ini keys'
run_test test_apply_adds_a_missing_appearance_section 'apply adds a missing Appearance section'
run_test test_apply_leaves_user_ini_alone_while_obs_runs 'apply leaves user.ini alone while OBS runs'
run_test test_apply_skips_the_step_before_obs_first_ran 'apply skips the theme step before OBS first ran'
run_test test_apply_asks_for_consent_outside_the_obs_series 'apply asks for consent outside the OBS series'
run_test test_remove_is_blocked_while_obs_runs 'obs-theme removal is blocked while OBS runs'
run_test test_remove_deletes_the_theme_and_resets_a_matching_id 'obs-theme removal deletes the theme and resets a matching id'
run_test test_remove_keeps_a_theme_id_the_human_changed 'obs-theme removal keeps a theme id the human changed'
finish_tests
