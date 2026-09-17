#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly OBS_SCENE_PACKAGE=config/obs-scene
readonly OBS_SCENE_LIBEXEC=.local/libexec/dotfiles/obs-scene
readonly HOST_BUN=$(command -v bun)
readonly LAPTOP_GEOMETRY='{"canvas": {"width": 1920, "height": 1080}, "bar_crop": 52, "strip_width": 70}'
readonly PC_GEOMETRY='{"canvas": {"width": 2560, "height": 1440}, "bar_crop": 52, "strip_width": 0}'
readonly -a SCENE_SVGS=(
	cam-frame.svg card-brb.svg card-ending.svg card-intro.svg card-privacy.svg card-starting.svg
	card-pulse-0.svg card-pulse-1.svg card-pulse-2.svg card-pulse-3.svg card-pulse-4.svg card-pulse-5.svg
	stream-overlay.svg
)
readonly -a STRIP_SVGS=(
	screen.svg strip-pulse-0.svg strip-pulse-1.svg strip-pulse-2.svg strip-pulse-3.svg strip-pulse-4.svg strip-pulse-5.svg
)

stock_color() {
	sed -n "s/^$2 *= *\"\(.*\)\"/\1/p" "/usr/share/omarchy/themes/$1/colors.toml"
}

expected_mix() {
	local a=${1#\#} b=${2#\#} percent=$3 index out='#' x y
	for index in 0 2 4; do
		x=$((16#${a:index:2}))
		y=$((16#${b:index:2}))
		out+=$(printf '%02x' $(((x * (100 - percent) + y * percent + 50) / 100)))
	done
	printf '%s\n' "$out"
}

# OBS stores colours as 0xAABBGGRR integers.
obs_color() {
	local hex=${1#\#}
	printf '%d\n' $((0xff000000 | 16#${hex:4:2} << 16 | 16#${hex:2:2} << 8 | 16#${hex:0:2}))
}

set_scene_omarchy_version() {
	make_fake omarchy "[[ \${1-} == version ]] && printf '%s\n' '$1'"
}

set_scene_font() {
	make_fake omarchy-font-current "printf '%s\n' '$1'"
}

set_scene_obs_version() {
	make_fake obs "[[ \${1-} == --version ]] && printf 'OBS Studio - %s\n' '$1'"
}

use_scene_theme() {
	SCENE_THEME=$1
	cp "/usr/share/omarchy/themes/$1/colors.toml" "$FIXTURE_HOME/.local/state/omarchy/current/theme/colors.toml"
}

write_geometry() {
	mkdir -p "$SCENE_OUTPUT" && printf '%s\n' "$1" >"$SCENE_OUTPUT/geometry.json"
}

# Wraps the real bun so every rename the generator makes is logged.
make_renaming_bun() {
	cat >"$FIXTURE_ROOT/rename-spy.ts" <<'EOF'
import fs from "node:fs";
const rename = fs.renameSync;
fs.renameSync = (from: fs.PathLike, to: fs.PathLike) => {
	fs.appendFileSync(process.env.DOTFILES_TEST_CALL_LOG!, `rename ${from} ${to}\n`);
	return rename(from, to);
};
EOF
	make_fake bun "exec '$HOST_BUN' --preload '$FIXTURE_ROOT/rename-spy.ts' \"\$@\""
}

readonly AVATAR_LAYERS=(avatar-back.png avatar-eyes.png avatar-glow.png avatar-head1.png avatar-head2.png avatar-head3.png)
readonly PINNED_AVATAR_SHA256=df58402f9dde4149751c0a6dae239169efb752cc567849431c0836fd664dcf02

# A synthetic 860x1229 stand-in for the tracked portrait, laid out on the
# geometry the generator pins: a hood rim, glowing eyes, a window and a black
# and a white patch of body colour on a grey sky. Every render needs one,
# because the package ships a portrait and every collection declares the layers.
make_avatar_fixture() {
	SCENE_AVATAR=$FIXTURE_HOME/.config/dotfiles/obs-avatar.jpg
	mkdir -p "${SCENE_AVATAR%/*}" || return 1
	magick -size 860x1229 xc:'#3c3c3c' \
		-fill '#bc005e' -draw 'rectangle 250,200 270,580' -draw 'rectangle 570,200 590,580' \
		-fill '#ff0080' -draw 'rectangle 380,398 460,428' \
		-fill '#8c0046' -draw 'rectangle 336,398 356,428' \
		-fill '#ff8c00' -draw 'rectangle 700,250 800,350' \
		-fill '#ffffff' -draw 'rectangle 20,250 120,350' \
		-fill '#000000' -draw 'rectangle 20,450 120,550' \
		-quality 100 "$SCENE_AVATAR" || return 1
}

# Pins the fixture copy of the generator to the synthetic image.
pin_avatar_fixture() {
	local hash
	read -r hash _ < <(sha256sum "$SCENE_AVATAR")
	sed -i "s/$PINNED_AVATAR_SHA256/$hash/" "$FIXTURE_REPO/$OBS_SCENE_PACKAGE/$OBS_SCENE_LIBEXEC/generate.ts"
}

setup_scene_fixture() {
	new_fixture || return 1
	SCENE_THEME_HOOK=$FIXTURE_REPO/$OBS_SCENE_PACKAGE/.config/omarchy/hooks/theme-set.d/obs-scene
	SCENE_FONT_HOOK=$FIXTURE_REPO/$OBS_SCENE_PACKAGE/.config/omarchy/hooks/font-set.d/obs-scene
	SCENE_OUTPUT=$FIXTURE_CONFIG/obs-studio/omarchy-scene
	mkdir -p "$FIXTURE_HOME/.local/state/omarchy/current/theme" || return 1
	set_scene_omarchy_version 4.0.3-1
	set_scene_font 'JetBrainsMono Nerd Font'
	set_scene_obs_version 32.2.2
	make_renaming_bun
	use_scene_theme catppuccin
	make_avatar_fixture && pin_avatar_fixture || return 1
	write_geometry "$LAPTOP_GEOMETRY"
}

run_scene_hook() {
	run_in_sandbox "$FIXTURE_ROOT" "${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" bash "$1" "$2"
}

scene_file_list() {
	(cd -- "$SCENE_OUTPUT" && find . -type f -printf '%P\n' | sort)
}

scene_state() {
	(cd -- "$SCENE_OUTPUT" && find . -type f -printf '%P %i %T@\n' | sort)
}

svg_size() {
	sed -n 's/^<svg[^>]* width="\([0-9]*\)" height="\([0-9]*\)".*/\1x\2/p' "$1"
}

assert_scene_render() {
	local width=$1 height=$2 strips=$3 context=$4 name expected background foreground accent border
	local -a names=(chat.css geometry.json theme.txt title.txt "${AVATAR_LAYERS[@]}" "${SCENE_SVGS[@]}")
	[[ $strips == false ]] || names+=("${STRIP_SVGS[@]}")
	expected=$(printf '%s\n' "${names[@]}" | sort)
	assert_eq "$expected" "$(scene_file_list)" "$context: the render should write exactly the listed files" || return 1
	for name in "${SCENE_SVGS[@]}"; do
		assert_eq "${width}x$height" "$(svg_size "$SCENE_OUTPUT/$name")" "$context: $name should use the native canvas size" || return 1
		xmllint --noout "$SCENE_OUTPUT/$name" || return 1
	done
	assert_eq "$width $height" "$(magick "$SCENE_OUTPUT/card-starting.svg" -format '%w %h' info:)" \
		"$context: librsvg should render the starting card" || return 1

	background=$(stock_color "$SCENE_THEME" background)
	foreground=$(stock_color "$SCENE_THEME" foreground)
	accent=$(stock_color "$SCENE_THEME" accent)
	border=$(expected_mix "$foreground" "$background" 40)
	assert_contains "$(<"$SCENE_OUTPUT/card-brb.svg")" "fill=\"$background\"" "$context: cards use the theme background" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/card-brb.svg")" "stroke=\"$accent\"" "$context: cards use an accent border" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/card-privacy.svg")" "stroke=\"$(stock_color "$SCENE_THEME" red)\"" "$context: privacy uses a red border" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/card-starting.svg")" 'font-family="JetBrainsMono Nerd Font"' "$context: SVG text uses the Omarchy font" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/stream-overlay.svg")" "fill=\"$background\" fill-opacity=\"0.88\"" "$context: overlay boxes are translucent" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/stream-overlay.svg")" "stroke=\"$border\"" "$context: overlay boxes use the border mix" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/cam-frame.svg")" "stroke=\"$accent\"" "$context: the camera box uses an accent border" || return 1
	if [[ $strips == true ]]; then
		assert_contains "$(<"$SCENE_OUTPUT/screen.svg")" "stroke=\"$border\"" "$context: the screen edges use the border mix" || return 1
		assert_eq "${width}x$height" "$(svg_size "$SCENE_OUTPUT/strip-pulse-0.svg")" "$context: strip pulses use the canvas size" || return 1
	fi

	assert_eq 'face=JetBrainsMono Nerd Font' "$(head -n 1 "$SCENE_OUTPUT/theme.txt")" "$context: theme.txt names the font face" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/theme.txt")" "Clock	$(obs_color "$foreground")	" "$context: the clock uses the foreground" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/theme.txt")" "Countdown	$(obs_color "$accent")	" "$context: the countdown uses the accent" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/theme.txt")" "Title	$(obs_color "$foreground")	" "$context: the title uses the foreground" || return 1
	assert_contains "$(<"$SCENE_OUTPUT/theme.txt")" "Date	$(obs_color "$foreground")	" "$context: the date uses the foreground" || return 1
	assert_scene_chat_css "$foreground" "$accent" "$context"
}

assert_scene_chat_css() {
	local foreground=$1 accent=$2 context=$3 css selector
	css=$(<"$SCENE_OUTPUT/chat.css")
	assert_contains "$css" 'background: transparent !important' "$context: chat has a transparent ground" || return 1
	assert_contains "$css" 'font-family: "JetBrainsMono Nerd Font"' "$context: chat uses the Omarchy font" || return 1
	assert_contains "$css" "--color-text-base: $foreground" "$context: Twitch chat text uses the foreground" || return 1
	assert_contains "$css" "--yt-live-chat-primary-text-color: $foreground" "$context: YouTube chat text uses the foreground" || return 1
	assert_contains "$css" "#author-name { color: $accent" "$context: YouTube authors use the accent" || return 1
	for selector in .stream-chat-header .chat-input 'yt-live-chat-header-renderer' '#input-panel' \
		'[class*="hype-train"]' '[class*="pinned-chat"]' '[class*="paid-pinned"]' '[class*="channel-leaderboard"]' \
		'[class*="consent-banner"]'; do
		assert_contains "$css" "$selector" "$context: chat.css should hide $selector" || return 1
	done
}

test_render_on_a_dark_theme_at_the_laptop_geometry() {
	setup_scene_fixture || return 1
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	assert_scene_render 1920 1080 true 'dark laptop'
}

test_render_on_a_light_theme_at_the_pc_geometry() {
	setup_scene_fixture || return 1
	use_scene_theme catppuccin-latte
	write_geometry "$PC_GEOMETRY"
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin-latte
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	assert_scene_render 2560 1440 false 'light pc'
}

test_render_on_a_light_theme_at_the_laptop_geometry() {
	setup_scene_fixture || return 1
	use_scene_theme catppuccin-latte
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin-latte
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	assert_scene_render 1920 1080 true 'light laptop'
}

test_render_on_a_dark_theme_at_the_pc_geometry() {
	setup_scene_fixture || return 1
	write_geometry "$PC_GEOMETRY"
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	assert_scene_render 2560 1440 false 'dark pc'
}

test_render_writes_every_file_through_a_same_folder_rename() {
	setup_scene_fixture || return 1
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	local name renames
	renames=$(grep '^rename ' "$CALL_LOG")
	for name in chat.css theme.txt title.txt "${AVATAR_LAYERS[@]}" "${SCENE_SVGS[@]}" "${STRIP_SVGS[@]}"; do
		[[ $renames =~ rename\ $SCENE_OUTPUT/\.$name\.[A-Za-z0-9]+\ $SCENE_OUTPUT/$name($'\n'|$) ]] || {
			printf '  %s should be renamed into place from a same-folder temporary file, renames:\n%s\n' "$name" "$renames" >&2
			return 1
		}
	done
	assert_eq '' "$(find "$SCENE_OUTPUT" -name '.*')" 'no temporary file should remain'
}

test_title_is_created_once_and_never_overwritten() {
	setup_scene_fixture || return 1
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	[[ -s $SCENE_OUTPUT/title.txt ]] || {
		printf '  the first render should create a non-empty title.txt\n' >&2
		return 1
	}
	printf 'my episode\n' >"$SCENE_OUTPUT/title.txt"
	use_scene_theme catppuccin-latte
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin-latte
	assert_eq 0 "$COMMAND_STATUS" "the hook should rerender: $COMMAND_OUTPUT" || return 1
	assert_eq 'my episode' "$(<"$SCENE_OUTPUT/title.txt")" 'an existing title.txt keeps its content'
}

test_font_hook_rerenders_with_the_new_font() {
	setup_scene_fixture || return 1
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	set_scene_font 'Fira Code'
	run_scene_hook "$SCENE_FONT_HOOK" 'Fira Code'
	assert_eq 0 "$COMMAND_STATUS" "the font hook should render: $COMMAND_OUTPUT" || return 1
	assert_eq 'face=Fira Code' "$(head -n 1 "$SCENE_OUTPUT/theme.txt")" 'theme.txt should name the new font' || return 1
	assert_contains "$(<"$SCENE_OUTPUT/chat.css")" 'font-family: "Fira Code"' 'chat.css should use the new font' || return 1
	assert_contains "$(<"$SCENE_OUTPUT/card-brb.svg")" 'font-family="Fira Code"' 'the cards should use the new font'
}

test_identical_output_leaves_every_file_untouched() {
	setup_scene_fixture || return 1
	local hook before
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	before=$(scene_state)
	: >"$CALL_LOG"
	for hook in "$SCENE_THEME_HOOK" "$SCENE_FONT_HOOK"; do
		sleep 0.05
		run_scene_hook "$hook" unchanged
		assert_eq 0 "$COMMAND_STATUS" "$hook should succeed on identical output: $COMMAND_OUTPUT" || return 1
		assert_eq "$before" "$(scene_state)" "$hook should leave identical output untouched" || return 1
	done
	assert_eq '' "$(grep '^rename ' "$CALL_LOG")" 'identical output should not be renamed into place'
}

test_hooks_fail_closed_and_keep_the_last_output() {
	local hook failure before
	for hook in theme font; do
		for failure in version colors; do
			setup_scene_fixture || return 1
			run_scene_hook "$SCENE_THEME_HOOK" catppuccin
			assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
			before=$(scene_state)
			set_scene_font 'Fira Code'
			if [[ $failure == version ]]; then
				set_scene_omarchy_version 4.1.0-1
			else
				rm "$FIXTURE_HOME/.local/state/omarchy/current/theme/colors.toml"
			fi
			if [[ $hook == theme ]]; then
				run_scene_hook "$SCENE_THEME_HOOK" catppuccin
			else
				run_scene_hook "$SCENE_FONT_HOOK" 'Fira Code'
			fi
			[[ $COMMAND_STATUS != 0 ]] || {
				printf '  %s hook should exit non-zero on a %s failure\n' "$hook" "$failure" >&2
				return 1
			}
			assert_contains "$COMMAND_OUTPUT" 'OBS scene hook failed:' "the hook should explain the $failure failure" || return 1
			assert_eq "$before" "$(scene_state)" "the hook should keep the last output on a $failure failure" || return 1
		done
	done
	setup_scene_fixture || return 1
	set_scene_omarchy_version 4.1.0-1
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_contains "$COMMAND_OUTPUT" 'Required: 4.0.x; detected: 4.1.0-1' 'the version failure should name both versions'
}

test_hooks_warn_and_render_outside_the_obs_series() {
	setup_scene_fixture || return 1
	set_scene_obs_version 33.0.1
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "an OBS mismatch should still render: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: OBS 33.0.1 is outside the tested 32.2 series' 'the hook should warn with both versions' || return 1
	[[ -f $SCENE_OUTPUT/theme.txt ]] || {
		printf '  the hook should still render\n' >&2
		return 1
	}
}

test_hooks_without_geometry_write_nothing_and_succeed() {
	setup_scene_fixture || return 1
	rm -rf "$SCENE_OUTPUT"
	local hook
	for hook in "$SCENE_THEME_HOOK" "$SCENE_FONT_HOOK"; do
		run_scene_hook "$hook" catppuccin
		assert_eq 0 "$COMMAND_STATUS" "$hook should succeed without geometry: $COMMAND_OUTPUT" || return 1
		assert_path_absent "$SCENE_OUTPUT" "$hook should write nothing without geometry" || return 1
	done
	set_scene_omarchy_version 4.1.0-1
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "without geometry the hook has nothing to protect: $COMMAND_OUTPUT" || return 1
	assert_eq '' "$(grep '^rename ' "$CALL_LOG")" 'nothing should be written'
}

test_lua_script_compiles_and_exposes_the_countdown_setting() {
	local script=$SOURCE_REPO/$OBS_SCENE_PACKAGE/$OBS_SCENE_LIBEXEC/omarchy-scene.lua
	luajit -bl "$script" /dev/null || return 1
	assert_contains "$(<"$script")" 'obs.obs_properties_add_int(properties, "countdown_minutes", "Starting countdown (minutes)", 1, 60, 1)' \
		'the script should expose the countdown setting' || return 1
	assert_contains "$(<"$script")" 'obs.obs_data_set_default_int(settings, "countdown_minutes", 5)' 'the countdown should default to 5 minutes' || return 1
	if grep -v '^ *--' "$script" | grep -Eq 'require|socket|websocket|io\.popen|os\.execute'; then
		printf '  the script should open no port\n' >&2
		return 1
	fi
}

test_catalog_entry_follows_obs_theme_with_the_approved_fields() {
	new_fixture || return 1
	local catalog=$FIXTURE_REPO/packages.json hooks='$HOME/.config/omarchy/hooks'
	assert_eq '["obs-theme","obs-scene"]' "$(jq -c '[.packages[].name] | .[index("obs-theme"):index("obs-scene") + 1]' "$catalog")" \
		'obs-scene should directly follow obs-theme' || return 1
	assert_eq '{"path":"config/obs-scene","dependencies":["obs-theme"],"arch_packages":["obs-studio","obs-studio-plugin-browser","imagemagick","bun"],"aur_packages":["obs-backgroundremoval"],"prerequisites":[],"documentation":"docs/obs.md"}' \
		"$(jq -c '.packages[] | select(.name == "obs-scene") | {path, dependencies, arch_packages, aur_packages, prerequisites, documentation}' "$catalog")" \
		'the obs-scene entry should declare the approved fields' || return 1
	assert_eq "bash -n \"$hooks/theme-set.d/obs-scene\""$'\n'"bash -n \"$hooks/font-set.d/obs-scene\""$'\n''luajit -bl "$HOME/.local/libexec/dotfiles/obs-scene/omarchy-scene.lua" /dev/null' \
		"$(jq -r '.packages[] | select(.name == "obs-scene") | .validators[]' "$catalog")" \
		'the validators should check both hooks and compile the Lua script'
}

test_package_tracks_exactly_the_generator_script_and_hooks() {
	new_fixture || return 1
	local package=$FIXTURE_REPO/$OBS_SCENE_PACKAGE expected tracked_hash
	expected=$(printf '%s\n' \
		"$package/$OBS_SCENE_LIBEXEC/generate.ts" \
		"$package/$OBS_SCENE_LIBEXEC/omarchy-scene.lua" \
		"$package/.config/dotfiles/obs-avatar.jpg" \
		"$package/.config/omarchy/hooks/font-set.d/obs-scene" \
		"$package/.config/omarchy/hooks/theme-set.d/obs-scene" | sort)
	assert_eq "$expected" "$(find "$package" \( -type f -o -type l \) -print | sort)" \
		'the package should track the generator, the Lua script, the portrait and both hooks' || return 1
	read -r tracked_hash _ < <(sha256sum "$package/.config/dotfiles/obs-avatar.jpg")
	assert_eq "$PINNED_AVATAR_SHA256" "$tracked_hash" 'the tracked portrait should be the pinned image' || return 1
	assert_eq "$package/.config/omarchy/hooks/theme-set.d/obs-scene" \
		"$(readlink -f "$package/.config/omarchy/hooks/font-set.d/obs-scene")" \
		'the font-set hook should run the same render'
}

# An installed set leaves a geometry file behind, so applying the package has to
# reach it: this is what a package update owes an already copied collection.
test_apply_renders_the_scene_of_an_installed_set() {
	new_fixture || return 1
	ln -sf /usr/bin/stow "$FIXTURE_BIN/stow"
	set_installed_arch_packages obs-studio obs-studio-plugin-browser imagemagick bun obs-backgroundremoval
	set_scene_obs_version 32.2.2
	set_scene_font 'JetBrainsMono Nerd Font'
	make_fake pgrep 'exit 1'
	mkdir -p "$FIXTURE_CONFIG/obs-studio" "$FIXTURE_HOME/.local/state/omarchy/current/theme" || return 1
	printf '[Appearance]\nTheme=com.obsproject.Yami\n' >"$FIXTURE_CONFIG/obs-studio/user.ini"
	use_scene_theme catppuccin
	printf 'catppuccin\n' >"$FIXTURE_HOME/.local/state/omarchy/current/theme.name"
	SCENE_OUTPUT=$FIXTURE_CONFIG/obs-studio/omarchy-scene
	write_geometry "$LAPTOP_GEOMETRY" || return 1

	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages obs-scene
	assert_eq 0 "$COMMAND_STATUS" "apply should pass: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Phase: render the scene assets' 'apply should render the installed scene' || return 1
	local name
	for name in theme.txt "${AVATAR_LAYERS[@]}"; do
		[[ -f $SCENE_OUTPUT/$name ]] || {
			printf '  apply should render %s from the linked portrait\n' "$name" >&2
			return 1
		}
	done

	rm "$FIXTURE_HOME/.local/state/omarchy/current/theme/colors.toml"
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages obs-scene
	[[ $COMMAND_STATUS != 0 ]] || {
		printf '  a failed render should fail the apply: %s\n' "$COMMAND_OUTPUT" >&2
		return 1
	}
	assert_contains "$COMMAND_OUTPUT" 'Stow linked, scene assets not rendered' 'apply should name the failed render'
}

setup_scene_package_fixture() {
	new_fixture || return 1
	ln -sf /usr/bin/stow "$FIXTURE_BIN/stow"
	set_installed_arch_packages obs-studio obs-studio-plugin-browser imagemagick bun obs-backgroundremoval
	set_scene_obs_version 32.2.2
	make_fake pgrep 'exit 1'
	mkdir -p "$FIXTURE_CONFIG/obs-studio" || return 1
	printf '[Appearance]\nTheme=com.obsproject.Yami\n' >"$FIXTURE_CONFIG/obs-studio/user.ini"
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages obs-scene
	assert_eq 0 "$COMMAND_STATUS" "apply should link obs-scene with obs-theme: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package state: obs-scene: succeeded' 'apply should link obs-scene' || return 1
	SCENE_OUTPUT=$FIXTURE_CONFIG/obs-studio/omarchy-scene
	SCENE_COLLECTION=$FIXTURE_CONFIG/obs-studio/basic/scenes/Omarchy_Scene.json
	SCENE_AVATAR=$FIXTURE_HOME/.config/dotfiles/obs-avatar.jpg
	mkdir -p "$SCENE_OUTPUT" "${SCENE_COLLECTION%/*}" || return 1
	printf '%s\n' "$LAPTOP_GEOMETRY" >"$SCENE_OUTPUT/geometry.json"
	printf 'my episode\n' >"$SCENE_OUTPUT/title.txt"
	printf '{}\n' >"$SCENE_COLLECTION"
	[[ -L $SCENE_AVATAR ]] || {
		printf '  apply should link the tracked portrait to %s\n' "$SCENE_AVATAR" >&2
		return 1
	}
}

test_remove_is_blocked_while_obs_runs() {
	setup_scene_package_fixture || return 1
	make_fake pgrep '[[ $* == "-x obs" ]]'
	run_operation "$FIXTURE_ROOT" remove_package obs-scene --yes
	assert_eq 1 "$COMMAND_STATUS" "removal should be blocked: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'OBS is running' 'removal should say why it stopped' || return 1
	[[ -f $SCENE_OUTPUT/title.txt && -L $FIXTURE_HOME/.config/omarchy/hooks/theme-set.d/obs-scene ]] || {
		printf '  the scene folder and links should stay in place\n' >&2
		return 1
	}
}

test_remove_deletes_the_scene_folder_and_keeps_the_collection_and_image() {
	setup_scene_package_fixture || return 1
	run_operation "$FIXTURE_ROOT" remove_package obs-scene --yes
	assert_eq 0 "$COMMAND_STATUS" "removal should succeed: $COMMAND_OUTPUT" || return 1
	assert_path_absent "$SCENE_OUTPUT" 'removal should delete the scene folder' || return 1
	assert_path_absent "$FIXTURE_HOME/.config/omarchy/hooks/theme-set.d/obs-scene" 'removal should unlink the package' || return 1
	[[ -f $SCENE_COLLECTION ]] || {
		printf '  removal must keep the copied collection\n' >&2
		return 1
	}
	assert_path_absent "$SCENE_AVATAR" 'removal should unlink the tracked portrait' || return 1
	[[ -L $FIXTURE_HOME/.config/omarchy/hooks/theme-set.d/obs-theme ]] || {
		printf '  removal must keep obs-theme\n' >&2
		return 1
	}
	local note
	for note in 'missing images and a missing script' 'title.txt was deleted' 'portrait is unlinked' \
		'obs-backgroundremoval' 'obs-studio-plugin-browser' 'imagemagick' 'bun' 'obs-studio remain installed'; do
		assert_contains "$COMMAND_OUTPUT" "$note" 'removal should print every cleanup note' || return 1
	done
}

pixel() {
	local hex
	hex=$(magick "$SCENE_OUTPUT/$1" -format "%[hex:p{$2,$3}]" info:) || return 1
	printf '#%s\n' "${hex:0:6}" | tr '[:upper:]' '[:lower:]'
}

# Prints "top bottom" rows of a layer's opaque pixels.
opaque_rows() {
	magick "$SCENE_OUTPUT/$1" -alpha extract -format '%@' info: |
		sed -n 's/^[0-9]*x\([0-9]*\)+[0-9]*+\([0-9]*\)$/\2 \1/p' | awk '{ print $1, $1 + $2 - 1 }'
}

assert_avatar_colours() {
	local context=$1 background foreground accent yellow white=#ffffff black=#000000 dark light
	background=$(stock_color "$SCENE_THEME" background)
	foreground=$(stock_color "$SCENE_THEME" foreground)
	accent=$(stock_color "$SCENE_THEME" accent)
	yellow=$(stock_color "$SCENE_THEME" yellow)
	if [[ $(stock_color "$SCENE_THEME" mode) == light ]]; then
		dark=$(expected_mix "$foreground" "$black" 50)
		light=$(expected_mix "$foreground" "$background" 70)
	else
		dark=$(expected_mix "$background" "$black" 60)
		light=$(expected_mix "$background" "$foreground" 34)
	fi
	assert_eq "$dark" "$(pixel avatar-back.png 33 149)" "$context: black base pixels take the darkest ramp step" || return 1
	assert_eq "$light" "$(pixel avatar-back.png 33 56)" "$context: white base pixels take the lightest ramp step" || return 1
	assert_eq "$yellow" "$(pixel avatar-back.png 349 56)" "$context: warm pixels take yellow" || return 1
	assert_eq "$(expected_mix "$accent" "$white" 45)" "$(pixel avatar-eyes.png 195 106)" "$context: bright hot pixels take the lightened accent" || return 1
	assert_eq "$(expected_mix "$accent" "$background" 30)" "$(pixel avatar-glow.png 159 106)" "$context: dim hot pixels take a darker accent step" || return 1
	assert_eq "$accent" "$(pixel avatar-head2.png 123 100)" "$context: the hood rim takes the accent" || return 1
}

assert_avatar_bands() {
	local head1 head2 head3
	read -r -a head1 <<<"$(opaque_rows avatar-head1.png)"
	read -r -a head2 <<<"$(opaque_rows avatar-head2.png)"
	read -r -a head3 <<<"$(opaque_rows avatar-head3.png)"
	((${#head1[@]} == 2 && ${#head2[@]} == 2 && ${#head3[@]} == 2)) || {
		printf '  every head band should hold pixels: %s | %s | %s\n' "${head1[*]}" "${head2[*]}" "${head3[*]}" >&2
		return 1
	}
	((head3[1] < head2[0] && head2[1] < head1[0])) || {
		printf '  head bands should not overlap and each should lie above the one below it: head3 %s, head2 %s, head1 %s\n' \
			"${head3[*]}" "${head2[*]}" "${head1[*]}" >&2
		return 1
	}
}

assert_no_avatar_layers() {
	local name
	for name in "${AVATAR_LAYERS[@]}"; do
		assert_path_absent "$SCENE_OUTPUT/$name" "$1: $name should not be written" || return 1
	done
}

test_avatar_is_recoloured_on_a_dark_and_a_light_theme() {
	setup_scene_fixture || return 1
	local theme name
	for theme in catppuccin catppuccin-latte; do
		use_scene_theme "$theme"
		run_scene_hook "$SCENE_THEME_HOOK" "$theme"
		assert_eq 0 "$COMMAND_STATUS" "the hook should render the avatar: $COMMAND_OUTPUT" || return 1
		for name in "${AVATAR_LAYERS[@]}"; do
			assert_eq '400 225' "$(magick "$SCENE_OUTPUT/$name" -format '%w %h' info:)" "$theme: $name should be 400x225" || return 1
		done
		assert_avatar_colours "$theme" || return 1
		assert_avatar_bands || return 1
	done
	local before
	before=$(scene_state)
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin-latte
	assert_eq "$before" "$(scene_state)" 'an unchanged avatar render leaves every layer untouched'
}

test_render_fails_when_the_portrait_is_missing_or_different() {
	local case
	for case in missing different; do
		setup_scene_fixture || return 1
		# The collection declares the avatar layers, so a scene without them is broken.
		if [[ $case == different ]]; then
			magick -size 860x1229 xc:'#101010' -quality 100 "$SCENE_AVATAR" || return 1
		else
			rm "$SCENE_AVATAR" || return 1
		fi
		run_scene_hook "$SCENE_THEME_HOOK" catppuccin
		[[ $COMMAND_STATUS != 0 ]] || {
			printf '  a %s portrait should fail the hook: %s\n' "$case" "$COMMAND_OUTPUT" >&2
			return 1
		}
		assert_contains "$COMMAND_OUTPUT" 'OBS scene hook failed:' "a $case portrait should explain the failure" || return 1
		assert_contains "$COMMAND_OUTPUT" 'avatar' "a $case portrait should name the avatar" || return 1
		assert_no_avatar_layers "$case portrait" || return 1
		assert_path_absent "$SCENE_OUTPUT/theme.txt" "a $case portrait should write no asset at all" || return 1
	done
	# A portrait that breaks after a good render keeps the last output.
	setup_scene_fixture || return 1
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin
	assert_eq 0 "$COMMAND_STATUS" "the hook should render: $COMMAND_OUTPUT" || return 1
	local before
	before=$(scene_state)
	rm "$SCENE_AVATAR"
	use_scene_theme catppuccin-latte
	run_scene_hook "$SCENE_THEME_HOOK" catppuccin-latte
	[[ $COMMAND_STATUS != 0 ]] || {
		printf '  a removed portrait should fail the hook: %s\n' "$COMMAND_OUTPUT" >&2
		return 1
	}
	assert_eq "$before" "$(scene_state)" 'a failed avatar render keeps the last output'
}

test_lua_script_exposes_the_avatar_tempo_setting() {
	local script=$SOURCE_REPO/$OBS_SCENE_PACKAGE/$OBS_SCENE_LIBEXEC/omarchy-scene.lua
	assert_contains "$(<"$script")" 'obs.obs_properties_add_int(properties, "avatar_bpm", "Avatar nod tempo (BPM)", 40, 200, 1)' \
		'the script should expose the avatar tempo setting' || return 1
	assert_contains "$(<"$script")" 'obs.obs_data_set_default_int(settings, "avatar_bpm", 90)' 'the tempo should default to 90 BPM'
}

run_test test_render_on_a_dark_theme_at_the_laptop_geometry 'scene renders a dark theme at the laptop geometry'
run_test test_render_on_a_light_theme_at_the_laptop_geometry 'scene renders a light theme at the laptop geometry'
run_test test_render_on_a_dark_theme_at_the_pc_geometry 'scene renders a dark theme at the pc geometry without strips'
run_test test_render_on_a_light_theme_at_the_pc_geometry 'scene renders a light theme at the pc geometry without strips'
run_test test_render_writes_every_file_through_a_same_folder_rename 'scene render writes every file through a same-folder rename'
run_test test_title_is_created_once_and_never_overwritten 'scene title is created once and never overwritten'
run_test test_font_hook_rerenders_with_the_new_font 'scene font hook rerenders with the new font'
run_test test_identical_output_leaves_every_file_untouched 'scene hooks leave identical output untouched'
run_test test_hooks_fail_closed_and_keep_the_last_output 'scene hooks fail closed and keep the last output'
run_test test_hooks_warn_and_render_outside_the_obs_series 'scene hooks warn and render outside the OBS series'
run_test test_hooks_without_geometry_write_nothing_and_succeed 'scene hooks without geometry write nothing and succeed'
run_test test_lua_script_compiles_and_exposes_the_countdown_setting 'scene Lua script compiles and exposes the countdown setting'
run_test test_avatar_is_recoloured_on_a_dark_and_a_light_theme 'scene avatar is recoloured on a dark and a light theme'
run_test test_render_fails_when_the_portrait_is_missing_or_different 'scene render fails when the portrait is missing or different'
run_test test_lua_script_exposes_the_avatar_tempo_setting 'scene Lua script exposes the avatar tempo setting'
run_test test_catalog_entry_follows_obs_theme_with_the_approved_fields 'obs-scene catalog entry follows obs-theme with the approved fields'
run_test test_package_tracks_exactly_the_generator_script_and_hooks 'obs-scene package tracks the generator, script, portrait and hooks'
run_test test_apply_renders_the_scene_of_an_installed_set 'obs-scene apply renders the scene of an installed set'
run_test test_remove_is_blocked_while_obs_runs 'obs-scene removal is blocked while OBS runs'
run_test test_remove_deletes_the_scene_folder_and_keeps_the_collection_and_image 'obs-scene removal deletes the scene folder and unlinks the portrait'
finish_tests
