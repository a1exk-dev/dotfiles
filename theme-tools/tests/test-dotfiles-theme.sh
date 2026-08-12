#!/usr/bin/env bash

set -uo pipefail

TEST_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MANAGER_SOURCE=$(cd -P -- "$TEST_DIR/../.local/bin" && pwd)/dotfiles-theme
ORIGINAL_PATH=$PATH
TEST_COUNT=0
FAIL_COUNT=0

setup_fixture() {
	ROOT=$(mktemp -d "/tmp/dotfiles-theme-test.XXXXXX")
	REPO=$ROOT/repo
	HOME_DIR=$ROOT/home
	CONFIG=$ROOT/config
	STATE=$ROOT/state
	DATA=$ROOT/data
	TEMP=$ROOT/tmp
	FAKE_BIN=$ROOT/fake-bin
	STOW_LOG=$ROOT/stow.log
	NATIVE_THEME=$ROOT/everforest-dark-hard.theme
	GHOSTTY_NATIVE_THEME="$ROOT/Everforest Dark Hard"
	COMMAND=$REPO/theme-tools/.local/bin/dotfiles-theme

	mkdir -p \
		"$REPO/theme-tools/.local/bin" \
		"$REPO/theme/everforest-hard/.config/starship" \
		"$REPO/theme/everforest-hard/.config/zen/chrome" \
		"$REPO/theme/everforest-hard/.config/hypr" \
		"$REPO/theme/everforest-hard/.config/opencode/themes" \
		"$REPO/theme/everforest-hard/.config/sysc-greet/themes" \
		"$REPO/theme/everforest-hard/.config/waybar" \
		"$REPO/theme/everforest-hard/.local/share/brave/themes/current" \
		"$REPO/starship/.config/starship" \
		"$REPO/zen/profile/chrome" \
		"$HOME_DIR" "$CONFIG" "$STATE" "$DATA" "$TEMP" "$FAKE_BIN"
	cp -- "$MANAGER_SOURCE" "$COMMAND"
	chmod +x "$COMMAND"

	cat >"$REPO/starship/.config/starship/base.toml" <<'EOF'
base_marker = "from-base"

[character]
success_symbol = ">"
EOF
	cat >"$REPO/theme/everforest-hard/.config/starship/palette.toml" <<'EOF'
[palettes.everforest_hard]
green = "#A7C080"
EOF
	cat >"$REPO/zen/profile/user.base.js" <<'EOF'
// base-marker
user_pref("base.preference", true);
EOF
	cat >"$REPO/zen/profile/chrome/userChrome.css" <<'EOF'
@import url("theme.css");
EOF
	cat >"$REPO/theme/everforest-hard/.config/zen/user.js" <<'EOF'
// theme-marker
user_pref("theme.preference", "everforest");
EOF
	cat >"$REPO/theme/everforest-hard/.config/zen/chrome/theme.css" <<'EOF'
:root { --theme: everforest; }
EOF
	cat >"$REPO/theme/everforest-hard/.config/hypr/colors.lua" <<'EOF'
return { primary = "#A7C080" }
EOF
	cat >"$REPO/theme/everforest-hard/.config/opencode/themes/current.json" <<'EOF'
{"theme":{"primary":"green"}}
EOF
	cat >"$REPO/theme/everforest-hard/.local/share/brave/themes/current/manifest.json" <<'EOF'
{"manifest_version":3,"name":"Everforest Hard","version":"1.0.0","theme":{}}
EOF
	cat >"$REPO/theme/everforest-hard/.config/sysc-greet/themes/current.toml" <<'EOF'
name = "current"

[colors]
bg_base = "#1E2326"
bg_active = "#374145"
primary = "#A7C080"
secondary = "#83C092"
accent = "#7FBBB3"
warning = "#DBBC7F"
danger = "#E67E80"
fg_primary = "#D3C6AA"
fg_secondary = "#9DA9A0"
fg_muted = "#859289"
border_focus = "#A7C080"
EOF
	cat >"$REPO/theme/everforest-hard/.config/waybar/theme.css" <<'EOF'
@define-color green #a7c080;
EOF
	printf 'native btop theme\n' >"$NATIVE_THEME"
	printf 'native Ghostty theme\n' >"$GHOSTTY_NATIVE_THEME"

	cat >"$FAKE_BIN/stow" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STOW_LOG:?}"
dry_run=0
for argument in "$@"; do
	[[ $argument == -n ]] && dry_run=1
done
if ((dry_run)) && [[ ${STOW_FAIL_AFTER_PARTIAL:-0} == 1 ]]; then
	[[ ! -e ${XDG_CONFIG_HOME:?}/dotfiles-theme/current && ! -L $XDG_CONFIG_HOME/dotfiles-theme/current ]] || exit 96
fi
if ((dry_run == 0)) && [[ ${STOW_FAIL_AFTER_PARTIAL:-0} == 1 ]]; then
	[[ -f ${XDG_CONFIG_HOME:?}/dotfiles-theme/current/.dotfiles-theme-name ]] || exit 97
	[[ -e ${XDG_CONFIG_HOME:?}/ghostty/themes/current ]] || exit 98
	printf 'theme = current\n' >"$XDG_CONFIG_HOME/ghostty/config"
	exit 42
fi
EOF
	chmod +x "$FAKE_BIN/stow"
}

theme() {
	env \
		HOME="$HOME_DIR" \
		XDG_CONFIG_HOME="$CONFIG" \
		XDG_STATE_HOME="$STATE" \
		XDG_DATA_HOME="$DATA" \
		XDG_RUNTIME_DIR= \
		TMPDIR="$TEMP" \
		DOTFILES_THEME_TESTING=1 \
		DOTFILES_THEME_BTOP_NATIVE_THEME="$NATIVE_THEME" \
		DOTFILES_THEME_GHOSTTY_NATIVE_THEME="$GHOSTTY_NATIVE_THEME" \
		STOW_FAIL_AFTER_PARTIAL="${STOW_FAIL_AFTER_PARTIAL:-0}" \
		STOW_LOG="$STOW_LOG" \
		PATH="$FAKE_BIN:$ORIGINAL_PATH" \
		"$COMMAND" "$@"
}

assert_link() {
	local path=$1 target=$2
	[[ -L $path ]]
	[[ $(readlink -- "$path") == "$target" ]]
}

test_set_builds_and_activates_bundle() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT

	theme set everforest-hard >"$ROOT/output" 2>"$ROOT/error"
	local current=$CONFIG/dotfiles-theme/current
	local bundle
	bundle=$(readlink -- "$current")

	[[ -L $current ]]
	[[ $bundle == "$STATE/dotfiles-theme/bundles/everforest-hard-"* ]]
	[[ -d $bundle ]]
	[[ $(<"$STATE/dotfiles-theme/active") == everforest-hard ]]
	[[ -f $bundle/.dotfiles-theme-name && ! -L $bundle/.dotfiles-theme-name ]]
	[[ $(<"$bundle/.dotfiles-theme-name") == everforest-hard ]]
	assert_link "$bundle/.config/waybar/theme.css" \
		"$REPO/theme/everforest-hard/.config/waybar/theme.css"
	assert_link "$bundle/.config/ghostty/themes/current" "$GHOSTTY_NATIVE_THEME"
	[[ ! -e $bundle/.config/ghostty/theme.conf && ! -L $bundle/.config/ghostty/theme.conf ]]
	grep -Fxq '  colorscheme = "everforest",' "$bundle/.config/nvim/theme.lua"
	grep -Fxq '  background = "hard",' "$bundle/.config/nvim/theme.lua"
	assert_link "$bundle/.config/btop/themes/current.theme" "$NATIVE_THEME"
	[[ -z $(find "$CONFIG/dotfiles-theme" -maxdepth 1 -name '.current.*' -print -quit) ]]
	[[ -z $(find "$STATE/dotfiles-theme" -maxdepth 1 -name '.active.*' -print -quit) ]]
	[[ -z $(find "$STATE/dotfiles-theme/bundles" -maxdepth 1 -name '.*.stage.*' -print -quit) ]]
}

test_command_symlink_resolves_repository_root() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local source_command=$COMMAND
	mkdir -p "$HOME_DIR/.local/bin"
	COMMAND=$HOME_DIR/.local/bin/dotfiles-theme
	ln -s "$source_command" "$COMMAND"

	theme set everforest-hard >/dev/null 2>&1
	[[ $(<"$STATE/dotfiles-theme/active") == everforest-hard ]]
	[[ -L $CONFIG/dotfiles-theme/current ]]
}

test_unknown_theme_is_rejected_without_mutation() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT

	if theme set nord >"$ROOT/output" 2>"$ROOT/error"; then
		return 1
	fi
	grep -Fq 'unknown theme' "$ROOT/error"
	[[ ! -e $CONFIG/dotfiles-theme ]]
	[[ ! -e $STATE/dotfiles-theme ]]
}

test_dry_run_leaves_home_and_xdg_unchanged() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$ROOT/zen-profile
	mkdir -p "$profile"

	theme --dry-run set everforest-hard >"$ROOT/output" 2>"$ROOT/error"
	grep -Fq 'would activate: everforest-hard' "$ROOT/output"
	theme --dry-run install --zen-profile "$profile" >>"$ROOT/output" 2>>"$ROOT/error"
	grep -Fq "would link: $CONFIG/starship.toml" "$ROOT/output"
	[[ -z $(find "$HOME_DIR" -mindepth 1 -print -quit) ]]
	[[ -z $(find "$CONFIG" -mindepth 1 -print -quit) ]]
	[[ -z $(find "$STATE" -mindepth 1 -print -quit) ]]
	[[ -z $(find "$DATA" -mindepth 1 -print -quit) ]]
	[[ -z $(find "$TEMP" -mindepth 1 -print -quit) ]]
	[[ -z $(find "$profile" -mindepth 1 -print -quit) ]]
}

test_generated_files_preserve_required_order() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT

	theme set everforest-hard >/dev/null 2>&1
	local bundle starship base_line palette_line zen base_js_line theme_js_line
	bundle=$(readlink -- "$CONFIG/dotfiles-theme/current")
	starship=$bundle/.config/starship.toml
	zen=$bundle/.config/zen/user.js
	[[ $(sed -n '1p' "$starship") == "palette = 'everforest_hard'" ]]
	base_line=$(grep -nF 'base_marker = "from-base"' "$starship" | cut -d: -f1)
	palette_line=$(grep -nF '[palettes.everforest_hard]' "$starship" | cut -d: -f1)
	((base_line < palette_line))
	base_js_line=$(grep -nF '// base-marker' "$zen" | cut -d: -f1)
	theme_js_line=$(grep -nF '// theme-marker' "$zen" | cut -d: -f1)
	((base_js_line < theme_js_line))
}

test_failed_rebuild_keeps_current_and_state_atomic() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT

	theme set everforest-hard >/dev/null 2>&1
	local old_current old_active bundle_count
	old_current=$(readlink -- "$CONFIG/dotfiles-theme/current")
	old_active=$(<"$STATE/dotfiles-theme/active")
	bundle_count=$(find "$STATE/dotfiles-theme/bundles" -mindepth 1 -maxdepth 1 -type d | wc -l)
	printf 'broken = [\n' >"$REPO/starship/.config/starship/base.toml"
	if theme set everforest-hard >"$ROOT/output" 2>"$ROOT/error"; then
		return 1
	fi
	[[ $(readlink -- "$CONFIG/dotfiles-theme/current") == "$old_current" ]]
	[[ $(<"$STATE/dotfiles-theme/active") == "$old_active" ]]
	[[ $(find "$STATE/dotfiles-theme/bundles" -mindepth 1 -maxdepth 1 -type d | wc -l) == "$bundle_count" ]]
}

test_install_creates_idempotent_bridges_and_preserves_legacy_paths() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$ROOT/zen-profile current=$CONFIG/dotfiles-theme/current
	local old_hypr=$REPO/hyprland/.config/hypr
	local old_waybar=$REPO/waybar/.config/waybar
	local old_opencode=$REPO/opencode/.config/opencode/themes
	local old_brave=$REPO/brave/.local/share/brave/themes/everforest-hard
	local old_sysc=$REPO/sysc-greet/.config/sysc-greet/themes
	mkdir -p \
		"$profile" \
		"$old_hypr/colors" \
		"$old_waybar" \
		"$old_opencode" \
		"$old_brave" \
		"$old_sysc" \
		"$CONFIG/hypr/colors" \
		"$CONFIG/waybar" \
		"$CONFIG/opencode/themes" \
		"$CONFIG/sysc-greet/themes" \
		"$DATA/brave/themes/everforest-hard"
	printf 'return { old = true }\n' >"$old_hypr/colors.lua"
	printf 'return { old_named = true }\n' >"$old_hypr/colors/everforest-hard.lua"
	printf '@define-color old #000000;\n' >"$old_waybar/colors.css"
	printf '{"old":true}\n' >"$old_opencode/everforest-hard.json"
	printf '{"old":true}\n' >"$old_brave/manifest.json"
	printf 'name = "old"\n' >"$old_sysc/everforest-hard.toml"
	ln -s "$old_hypr/colors.lua" "$CONFIG/hypr/colors.lua"
	ln -s "$old_hypr/colors/everforest-hard.lua" "$CONFIG/hypr/colors/everforest-hard.lua"
	ln -s "$old_waybar/colors.css" "$CONFIG/waybar/colors.css"
	ln -s "$old_opencode/everforest-hard.json" "$CONFIG/opencode/themes/everforest-hard.json"
	ln -s "$old_brave/manifest.json" "$DATA/brave/themes/everforest-hard/manifest.json"
	ln -s "$old_sysc/everforest-hard.toml" "$CONFIG/sysc-greet/themes/everforest-hard.toml"
	printf 'runtime cache\n' >"$DATA/brave/themes/everforest-hard/Cached Theme.pak"

	theme install --zen-profile "$profile" >"$ROOT/output" 2>"$ROOT/error"
	assert_link "$CONFIG/btop/themes/current.theme" "$current/.config/btop/themes/current.theme"
	assert_link "$CONFIG/ghostty/themes/current" "$current/.config/ghostty/themes/current"
	assert_link "$CONFIG/hypr/colors.lua" "$current/.config/hypr/colors.lua"
	assert_link "$CONFIG/hypr/colors/everforest-hard.lua" "$current/.config/hypr/colors.lua"
	assert_link "$CONFIG/waybar/colors.css" "$current/.config/waybar/theme.css"
	assert_link "$CONFIG/opencode/themes/current.json" "$current/.config/opencode/themes/current.json"
	assert_link "$CONFIG/opencode/themes/everforest-hard.json" "$current/.config/opencode/themes/current.json"
	assert_link "$DATA/brave/themes/current/manifest.json" \
		"$current/.local/share/brave/themes/current/manifest.json"
	assert_link "$DATA/brave/themes/everforest-hard/manifest.json" \
		"$current/.local/share/brave/themes/current/manifest.json"
	assert_link "$CONFIG/sysc-greet/themes/everforest-hard.toml" \
		"$current/.config/sysc-greet/themes/current.toml"
	assert_link "$CONFIG/starship.toml" "$current/.config/starship.toml"
	assert_link "$profile/chrome/theme.css" "$current/.config/zen/chrome/theme.css"
	assert_link "$profile/chrome/userChrome.css" "$REPO/zen/profile/chrome/userChrome.css"
	assert_link "$profile/user.js" "$current/.config/zen/user.js"
	[[ -d $DATA/brave/themes/current && ! -L $DATA/brave/themes/current ]]
	[[ -d $DATA/brave/themes/everforest-hard && ! -L $DATA/brave/themes/everforest-hard ]]
	[[ $(<"$DATA/brave/themes/everforest-hard/Cached Theme.pak") == 'runtime cache' ]]
	printf 'current runtime cache\n' >"$DATA/brave/themes/current/Cached Theme.pak"

	rm -f -- \
		"$old_hypr/colors.lua" \
		"$old_hypr/colors/everforest-hard.lua" \
		"$old_waybar/colors.css" \
		"$old_opencode/everforest-hard.json" \
		"$old_brave/manifest.json" \
		"$old_sysc/everforest-hard.toml"
	[[ -f $CONFIG/hypr/colors.lua ]]
	[[ -f $CONFIG/hypr/colors/everforest-hard.lua ]]
	[[ -f $CONFIG/waybar/colors.css ]]
	[[ -f $CONFIG/opencode/themes/everforest-hard.json ]]
	[[ -f $DATA/brave/themes/everforest-hard/manifest.json ]]
	[[ -f $CONFIG/sysc-greet/themes/everforest-hard.toml ]]
	grep -Fq '#A7C080' "$CONFIG/hypr/colors.lua"
	grep -Fq '@define-color green #a7c080;' "$CONFIG/waybar/colors.css"
	grep -Fq '"primary":"green"' "$CONFIG/opencode/themes/everforest-hard.json"
	grep -Fq '"Everforest Hard"' "$DATA/brave/themes/everforest-hard/manifest.json"
	grep -Fq 'name = "current"' "$CONFIG/sysc-greet/themes/everforest-hard.toml"
	grep -Fq -- '--no-folding -R' "$STOW_LOG"
	! grep -Fq -- '--adopt' "$STOW_LOG"

	theme install --zen-profile "$profile" >>"$ROOT/output" 2>>"$ROOT/error"
	assert_link "$CONFIG/starship.toml" "$current/.config/starship.toml"
	assert_link "$CONFIG/ghostty/themes/current" "$current/.config/ghostty/themes/current"
	assert_link "$CONFIG/hypr/colors.lua" "$current/.config/hypr/colors.lua"
	assert_link "$DATA/brave/themes/everforest-hard/manifest.json" \
		"$current/.local/share/brave/themes/current/manifest.json"
	assert_link "$profile/chrome/userChrome.css" "$REPO/zen/profile/chrome/userChrome.css"
	assert_link "$profile/user.js" "$current/.config/zen/user.js"
	[[ $(<"$DATA/brave/themes/everforest-hard/Cached Theme.pak") == 'runtime cache' ]]
	[[ $(<"$DATA/brave/themes/current/Cached Theme.pak") == 'current runtime cache' ]]
}

test_stow_failure_leaves_partial_deployment_with_valid_theme_targets() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$ROOT/zen-profile current=$CONFIG/dotfiles-theme/current
	local -a stow_calls=()
	mkdir -p "$profile"
	STOW_FAIL_AFTER_PARTIAL=1

	if theme install --zen-profile "$profile" >"$ROOT/output" 2>"$ROOT/error"; then
		return 1
	fi
	[[ $(<"$CONFIG/ghostty/config") == 'theme = current' ]]
	[[ -L $current ]]
	[[ $(<"$current/.dotfiles-theme-name") == everforest-hard ]]
	assert_link "$CONFIG/ghostty/themes/current" "$current/.config/ghostty/themes/current"
	[[ $(readlink -f -- "$CONFIG/ghostty/themes/current") == "$GHOSTTY_NATIVE_THEME" ]]
	[[ $(<"$STATE/dotfiles-theme/active") == everforest-hard ]]
	mapfile -t stow_calls <"$STOW_LOG"
	((${#stow_calls[@]} == 2))
	[[ ${stow_calls[0]} == '-n --no-folding -R '* ]]
	[[ ${stow_calls[1]} == '--no-folding -R '* ]]
}

test_install_stows_bridge_packages_but_not_nvim_starship_or_zsh() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$ROOT/zen-profile package
	mkdir -p \
		"$profile" \
		"$REPO/btop" \
		"$REPO/brave" \
		"$REPO/opencode" \
		"$REPO/nvim" \
		"$REPO/zsh"

	theme install --zen-profile "$profile" >/dev/null 2>&1
	for package in theme-tools btop brave opencode; do
		grep -Eq "(^|[[:space:]])$package([[:space:]]|$)" "$STOW_LOG"
	done
	for package in nvim starship zsh; do
		! grep -Eq "(^|[[:space:]])$package([[:space:]]|$)" "$STOW_LOG"
	done
}

test_install_unfolds_only_repository_ancestors() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$ROOT/zen-profile source_dir=$REPO/opencode/.config/opencode
	mkdir -p "$profile" "$source_dir/themes"
	printf '{}\n' >"$source_dir/themes/everforest-hard.json"
	ln -s "$source_dir" "$CONFIG/opencode"

	theme install --zen-profile "$profile" >/dev/null 2>&1
	[[ -d $CONFIG/opencode && ! -L $CONFIG/opencode ]]
	[[ -d $CONFIG/opencode/themes && ! -L $CONFIG/opencode/themes ]]
	assert_link "$CONFIG/opencode/themes/everforest-hard.json" \
		"$CONFIG/dotfiles-theme/current/.config/opencode/themes/current.json"
	assert_link "$CONFIG/opencode/themes/current.json" \
		"$CONFIG/dotfiles-theme/current/.config/opencode/themes/current.json"
}

test_install_refuses_plain_destination_before_stow() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$ROOT/zen-profile
	mkdir -p "$profile" "$CONFIG/ghostty/themes"
	printf 'personal theme\n' >"$CONFIG/ghostty/themes/current"

	if theme install --zen-profile "$profile" >"$ROOT/output" 2>"$ROOT/error"; then
		return 1
	fi
	grep -Fq 'refusing existing plain destination' "$ROOT/error"
	[[ $(<"$CONFIG/ghostty/themes/current") == 'personal theme' ]]
	[[ ! -e $STOW_LOG ]]
	[[ ! -e $STATE/dotfiles-theme ]]
}

test_install_refuses_foreign_destination_link() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$ROOT/zen-profile foreign=$ROOT/foreign.theme
	mkdir -p "$profile" "$CONFIG/ghostty/themes"
	printf 'foreign\n' >"$foreign"
	ln -s "$foreign" "$CONFIG/ghostty/themes/current"

	if theme install --zen-profile "$profile" >"$ROOT/output" 2>"$ROOT/error"; then
		return 1
	fi
	grep -Fq 'refusing foreign destination link' "$ROOT/error"
	assert_link "$CONFIG/ghostty/themes/current" "$foreign"
	[[ ! -e $STOW_LOG ]]
}

test_zen_explicit_profile_overrides_discovery() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local discovered=$CONFIG/zen/Profiles/discovered explicit=$ROOT/explicit-profile
	mkdir -p "$discovered" "$explicit"
	cat >"$CONFIG/zen/installs.ini" <<'EOF'
[A1B2C3D4]
Default=Profiles/discovered
Locked=1
EOF

	theme install --zen-profile "$explicit" >/dev/null 2>&1
	assert_link "$explicit/user.js" "$CONFIG/dotfiles-theme/current/.config/zen/user.js"
	[[ ! -e $discovered/user.js ]]

	if theme install --zen-profile "$ROOT/does-not-exist" >"$ROOT/output" 2>"$ROOT/error"; then
		return 1
	fi
	grep -Fq 'explicit Zen profile is not an existing directory' "$ROOT/error"
}

test_zen_install_default_discovery_and_ambiguity() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$CONFIG/zen/Profiles/default ignored=$CONFIG/zen/Profiles/ignored
	mkdir -p "$profile" "$ignored"
	cat >"$CONFIG/zen/profiles.ini" <<'EOF'
[Profile0]
Default=Profiles/ignored
[InstallABC]
Default=Profiles/default
Locked=1
EOF
	theme install >/dev/null 2>&1
	assert_link "$profile/chrome/theme.css" "$CONFIG/dotfiles-theme/current/.config/zen/chrome/theme.css"
	assert_link "$profile/chrome/userChrome.css" "$REPO/zen/profile/chrome/userChrome.css"

	mkdir -p "$HOME_DIR/.zen"
	cat >"$HOME_DIR/.zen/installs.ini" <<EOF
[A1B2C3D4]
Default=$profile
EOF
	theme install >/dev/null 2>&1
	assert_link "$profile/user.js" "$CONFIG/dotfiles-theme/current/.config/zen/user.js"

	rm -f -- "$profile/chrome/theme.css" "$profile/chrome/userChrome.css" "$profile/user.js"
	mkdir -p "$HOME_DIR/.zen/Profiles/other"
	cat >"$HOME_DIR/.zen/installs.ini" <<'EOF'
[E5F6A7B8]
Default=Profiles/other
EOF
	theme install >"$ROOT/output" 2>"$ROOT/error"
	grep -Fq 'ambiguous Zen install defaults' "$ROOT/error"
	[[ ! -e $profile/user.js ]]
	[[ ! -e $HOME_DIR/.zen/Profiles/other/user.js ]]
}

test_zen_native_installs_registry_discovery() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local zen_root=$CONFIG/zen profile=$CONFIG/zen/Profiles/default
	mkdir -p "$profile"
	cat >"$zen_root/installs.ini" <<'EOF'
[1234ABCD]
Default=Profiles/default
EOF

	theme install >/dev/null 2>&1
	assert_link "$profile/chrome/theme.css" "$CONFIG/dotfiles-theme/current/.config/zen/chrome/theme.css"
	assert_link "$profile/chrome/userChrome.css" "$REPO/zen/profile/chrome/userChrome.css"
	assert_link "$profile/user.js" "$CONFIG/dotfiles-theme/current/.config/zen/user.js"
}

test_zen_tarball_registry_discovery() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local zen_root=$HOME_DIR/.zen profile=$HOME_DIR/.zen/Profiles/default
	mkdir -p "$profile"
	cat >"$zen_root/installs.ini" <<'EOF'
[FEDCBA98]
Default=Profiles/default
EOF

	theme install >/dev/null 2>&1
	assert_link "$profile/chrome/theme.css" "$CONFIG/dotfiles-theme/current/.config/zen/chrome/theme.css"
	assert_link "$profile/chrome/userChrome.css" "$REPO/zen/profile/chrome/userChrome.css"
	assert_link "$profile/user.js" "$CONFIG/dotfiles-theme/current/.config/zen/user.js"
}

test_zen_flatpak_registry_is_warned_and_ignored() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local native_root=$CONFIG/zen native_profile=$CONFIG/zen/Profiles/default
	local flatpak_root=$HOME_DIR/.var/app/app.zen_browser.zen/zen
	local flatpak_profile=$flatpak_root/Profiles/default
	mkdir -p "$native_profile" "$flatpak_profile"
	cat >"$native_root/installs.ini" <<'EOF'
[1234ABCD]
Default=Profiles/default
EOF
	cat >"$flatpak_root/installs.ini" <<'EOF'
[FEDCBA98]
Default=Profiles/default
EOF

	theme install >"$ROOT/output" 2>"$ROOT/error"
	grep -Fq 'Flatpak Zen is unsupported' "$ROOT/error"
	assert_link "$native_profile/user.js" "$CONFIG/dotfiles-theme/current/.config/zen/user.js"
	[[ ! -e $flatpak_profile/user.js ]]
}

test_zen_explicit_flatpak_profile_is_rejected() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local profile=$HOME_DIR/.var/app/app.zen_browser.zen/zen/Profiles/default alias=$ROOT/flatpak-profile-alias
	mkdir -p "$profile"
	ln -s "$profile" "$alias"

	if theme install --zen-profile "$profile" >"$ROOT/output" 2>"$ROOT/error"; then
		return 1
	fi
	grep -Fq 'Flatpak Zen profiles are unsupported' "$ROOT/error"
	if theme install --zen-profile "$alias" >"$ROOT/output" 2>"$ROOT/error"; then
		return 1
	fi
	grep -Fq 'Flatpak Zen profiles are unsupported' "$ROOT/error"
	[[ ! -e $STOW_LOG ]]
	[[ ! -e $STATE/dotfiles-theme ]]
}

test_zen_registry_candidate_alias_into_flatpak_is_skipped() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	local zen_root=$CONFIG/zen alias=$CONFIG/zen/Profiles/flatpak-alias
	local flatpak_profile=$HOME_DIR/.var/app/app.zen_browser.zen/zen/Profiles/default
	mkdir -p "$zen_root/Profiles" "$flatpak_profile"
	ln -s "$flatpak_profile" "$alias"
	cat >"$zen_root/installs.ini" <<'EOF'
[1234ABCD]
Default=Profiles/flatpak-alias
EOF

	theme install >"$ROOT/output" 2>"$ROOT/error"
	grep -Fq 'Flatpak Zen profile is unsupported' "$ROOT/error"
	[[ ! -e $flatpak_profile/user.js ]]
	[[ ! -e $flatpak_profile/chrome/userChrome.css ]]
}

test_missing_native_themes_warn_without_blocking() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	NATIVE_THEME=$ROOT/missing-native.theme
	GHOSTTY_NATIVE_THEME=$ROOT/missing-ghostty-native-theme

	theme set everforest-hard >"$ROOT/output" 2>"$ROOT/error"
	local bundle
	bundle=$(readlink -- "$CONFIG/dotfiles-theme/current")
	grep -Fq 'btop native theme not found' "$ROOT/error"
	grep -Fq 'Ghostty native theme not found' "$ROOT/error"
	assert_link "$bundle/.config/btop/themes/current.theme" "$NATIVE_THEME"
	assert_link "$bundle/.config/ghostty/themes/current" "$GHOSTTY_NATIVE_THEME"
	[[ ! -e $bundle/.config/btop/themes/current.theme ]]
	[[ ! -e $bundle/.config/ghostty/themes/current ]]
}

test_list_and_status_report_activation() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT

	[[ $(theme list) == everforest-hard ]]
	theme status >"$ROOT/before"
	grep -Fxq 'active: none' "$ROOT/before"
	grep -Fxq 'current: missing' "$ROOT/before"
	theme set everforest-hard >/dev/null 2>&1
	theme status >"$ROOT/after"
	grep -Fxq 'active: everforest-hard' "$ROOT/after"
	grep -Fq "current: $STATE/dotfiles-theme/bundles/everforest-hard-" "$ROOT/after"
	[[ $(theme list) == 'everforest-hard (active)' ]]

	printf 'stale-theme\n' >"$STATE/dotfiles-theme/active"
	theme status >"$ROOT/stale"
	grep -Fxq 'active: everforest-hard' "$ROOT/stale"
	[[ $(theme list) == 'everforest-hard (active)' ]]
	rm -f -- "$STATE/dotfiles-theme/active"
	theme status >"$ROOT/missing-record"
	grep -Fxq 'active: everforest-hard' "$ROOT/missing-record"
	theme set everforest-hard >/dev/null 2>&1
	[[ $(<"$STATE/dotfiles-theme/active") == everforest-hard ]]
}

test_sync_greeter_dry_run_never_invokes_sudo() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	theme set everforest-hard >/dev/null 2>&1
	local marker=$ROOT/sudo-invoked
	cat >"$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
: >"${SUDO_MARKER:?}"
exit 99
EOF
	chmod +x "$FAKE_BIN/sudo"
	export SUDO_MARKER=$marker

	theme --dry-run sync-greeter >"$ROOT/output" 2>"$ROOT/error"
	[[ ! -e $marker ]]
	[[ -z $(find "$TEMP" -mindepth 1 -print -quit) ]]
	grep -Fq '/var/lib/greeter/.config/sysc-greet/themes/current.toml' "$ROOT/output"
	grep -Fq 'mode 0644, atomic rename' "$ROOT/output"
}

test_sync_greeter_uses_validated_snapshot_bytes() {
	setup_fixture
	trap 'rm -rf -- "$ROOT"' EXIT
	theme set everforest-hard >/dev/null 2>&1
	local source=$CONFIG/dotfiles-theme/current/.config/sysc-greet/themes/current.toml
	local expected=$ROOT/expected.toml capture=$ROOT/captured.toml
	cp -- "$source" "$expected"
	cat >"$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $1 == -u && $2 == greeter ]]
shift 2
[[ $1 == sh && $2 == -c ]]
[[ $(stat -Lc '%a' /proc/self/fd/0) == 600 ]]
[[ $(readlink -- /proc/self/fd/0) == *' (deleted)' ]]
printf 'raced source\n' >"${GREETER_RACE_SOURCE:?}"
cat >"${SUDO_CAPTURE:?}"
EOF
	chmod +x "$FAKE_BIN/sudo"
	export GREETER_RACE_SOURCE=$source SUDO_CAPTURE=$capture

	theme sync-greeter >"$ROOT/output" 2>"$ROOT/error"
	[[ $(<"$source") == 'raced source' ]]
	cmp -- "$expected" "$capture"
	[[ -z $(find "$TEMP" -name 'dotfiles-theme-greeter.*' -print -quit) ]]
}

run_test() {
	local name=$1 function_name=$2 status
	TEST_COUNT=$((TEST_COUNT + 1))
	(set -Eeuo pipefail; "$function_name")
	status=$?
	if ((status == 0)); then
		printf 'ok %d - %s\n' "$TEST_COUNT" "$name"
	else
		printf 'not ok %d - %s\n' "$TEST_COUNT" "$name"
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
}

run_test 'set builds and atomically activates a bundle' test_set_builds_and_activates_bundle
run_test 'installed command symlink resolves the repository root' test_command_symlink_resolves_repository_root
run_test 'unknown themes fail without mutation' test_unknown_theme_is_rejected_without_mutation
run_test 'dry-run leaves HOME and XDG roots unchanged' test_dry_run_leaves_home_and_xdg_unchanged
run_test 'generated Starship and Zen files preserve ordering' test_generated_files_preserve_required_order
run_test 'failed rebuild keeps current and active state' test_failed_rebuild_keeps_current_and_state_atomic
run_test 'install creates idempotent bridges and preserves legacy paths' test_install_creates_idempotent_bridges_and_preserves_legacy_paths
run_test 'Stow failure leaves partial deployment with valid theme targets' test_stow_failure_leaves_partial_deployment_with_valid_theme_targets
run_test 'install excludes nvim, starship, and zsh from Stow' test_install_stows_bridge_packages_but_not_nvim_starship_or_zsh
run_test 'install safely unfolds repository-owned ancestors' test_install_unfolds_only_repository_ancestors
run_test 'install refuses a plain destination before Stow' test_install_refuses_plain_destination_before_stow
run_test 'install refuses a foreign destination link' test_install_refuses_foreign_destination_link
run_test 'explicit Zen profile overrides discovery' test_zen_explicit_profile_overrides_discovery
run_test 'Zen profiles.ini fallback works and ambiguity is skipped' test_zen_install_default_discovery_and_ambiguity
run_test 'Zen native installs.ini accepts bare install hashes' test_zen_native_installs_registry_discovery
run_test 'Zen tarball registry discovery works' test_zen_tarball_registry_discovery
run_test 'Zen Flatpak registry is warned and ignored' test_zen_flatpak_registry_is_warned_and_ignored
run_test 'explicit Zen Flatpak profiles are rejected' test_zen_explicit_flatpak_profile_is_rejected
run_test 'Zen registry aliases into Flatpak are skipped' test_zen_registry_candidate_alias_into_flatpak_is_skipped
run_test 'missing native themes only warn' test_missing_native_themes_warn_without_blocking
run_test 'list and status report activation' test_list_and_status_report_activation
run_test 'sync-greeter dry-run never invokes sudo' test_sync_greeter_dry_run_never_invokes_sudo
run_test 'sync-greeter drops privilege and copies validated snapshot bytes' test_sync_greeter_uses_validated_snapshot_bytes

if ((FAIL_COUNT > 0)); then
	printf '%d of %d tests failed\n' "$FAIL_COUNT" "$TEST_COUNT" >&2
	exit 1
fi

printf 'all %d tests passed\n' "$TEST_COUNT"
