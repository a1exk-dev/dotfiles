#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -P -- "$TEST_DIR/../.." && pwd)
MANAGER=$REPO_ROOT/theme-tools/.local/bin/dotfiles-theme
ORIGINAL_PATH=$PATH

fail() {
	printf 'not ok - %s\n' "$*" >&2
	exit 1
}

STOW=$(command -v stow || true)
if [[ -z $STOW ]]; then
	printf 'skip - GNU Stow is not installed\n'
	exit 0
fi
"$STOW" --version | grep -Fq 'GNU Stow' || fail "non-GNU Stow found: $STOW"

ROOT=$(mktemp -d "/tmp/dotfiles-theme-real-stow.XXXXXX")
BTOP_NATIVE_THEME=$ROOT/everforest-dark-hard.theme
PREFERRED_GHOSTTY_THEME='/usr/share/ghostty/themes/Everforest Dark Hard'

cleanup() {
	case $ROOT in
		/tmp/dotfiles-theme-real-stow.*) rm -rf -- "$ROOT" ;;
	esac
}
trap cleanup EXIT

mkdir -p "$ROOT"
printf 'isolated native theme\n' >"$BTOP_NATIVE_THEME"

isolated_env() {
	local -a environment=(
		"HOME=$HOME_DIR"
		'USER=dotfiles-theme-test'
		'LOGNAME=dotfiles-theme-test'
		'SHELL=/bin/sh'
		'TERM=xterm-256color'
		"PATH=$ORIGINAL_PATH"
		"XDG_RUNTIME_DIR=$RUNTIME_DIR"
		"TMPDIR=$TEMP_DIR"
		'WAYLAND_DISPLAY=dotfiles-theme-test-no-display'
		'DISPLAY=dotfiles-theme-test-no-display'
		'HYPRLAND_INSTANCE_SIGNATURE='
		"DBUS_SESSION_BUS_ADDRESS=unix:path=$CASE_ROOT/no-dbus"
	)
	if ((CUSTOM_XDG)); then
		environment+=(
			"XDG_CONFIG_HOME=$CONFIG_HOME"
			"XDG_STATE_HOME=$STATE_HOME"
			"XDG_DATA_HOME=$DATA_HOME"
			"XDG_CACHE_HOME=$CACHE_HOME"
		)
	fi
	(
		ulimit -c 0
		cd -- "$UNRELATED_CWD"
		exec env -i "${environment[@]}" "$@"
	)
}

assert_deployed_link() {
	local deployed=$1 expected=$2
	[[ -L $deployed ]] || fail "GNU Stow did not deploy a leaf link: $deployed"
	[[ $(readlink -f -- "$deployed") == "$expected" ]] || \
		fail "deployed link resolves outside its package: $deployed"
}

assert_direct_link() {
	local link=$1 target=$2
	[[ -L $link ]] || fail "expected a symbolic link: $link"
	[[ $(readlink -- "$link") == "$target" ]] || fail "unexpected link target: $link"
}

assert_no_unresolved_source() {
	local log=$1 validator=$2
	if grep -Eqi \
		'(dotfiles-theme.*(no such file|not.?found|error opening)|cannot open .*dotfiles-theme|source=.*(globbing error|found no match))' \
		"$log"; then
		cat -- "$log" >&2
		fail "$validator could not resolve an active theme source"
	fi
}

validate_deployment() {
	if command -v hyprland >/dev/null 2>&1; then
		if ! isolated_env hyprland --verify-config --config "$HYPRLAND_CONFIG" \
			>"$CASE_ROOT/hyprland.log" 2>&1; then
			cat -- "$CASE_ROOT/hyprland.log" >&2
			fail "Hyprland rejected the $CASE_NAME deployment"
		fi
		assert_no_unresolved_source "$CASE_ROOT/hyprland.log" Hyprland
	else
		printf 'skip - Hyprland validator is not installed (%s)\n' "$CASE_NAME"
	fi

	if command -v hyprlock >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
		set +e
		isolated_env timeout --signal=TERM --kill-after=1 4 \
			hyprlock --verbose --display dotfiles-theme-test-no-display --config "$HYPRLOCK_CONFIG" \
			>"$CASE_ROOT/hyprlock.log" 2>&1
		hyprlock_status=$?
		set -e
		((hyprlock_status != 126 && hyprlock_status != 127)) || fail 'Hyprlock parser did not start'
		assert_no_unresolved_source "$CASE_ROOT/hyprlock.log" Hyprlock
		if grep -Eqi \
			'(cannot parse "\$[[:alnum:]_]+" as an int|error parsing gradient \$[[:alnum:]_]+)' \
			"$CASE_ROOT/hyprlock.log"; then
			cat -- "$CASE_ROOT/hyprlock.log" >&2
			fail "Hyprlock did not load active theme variables in $CASE_NAME"
		fi
	else
		printf 'skip - Hyprlock parser or timeout is not installed (%s)\n' "$CASE_NAME"
	fi

	if ! command -v ghostty >/dev/null 2>&1; then
		printf 'skip - Ghostty validator is not installed (%s)\n' "$CASE_NAME"
	elif [[ ! -e $GHOSTTY_BRIDGE ]]; then
		printf 'skip - Ghostty native theme is unavailable (%s)\n' "$CASE_NAME"
	elif ! isolated_env ghostty +validate-config --config-file="$GHOSTTY_CONFIG" \
		>"$CASE_ROOT/ghostty.log" 2>&1; then
		cat -- "$CASE_ROOT/ghostty.log" >&2
		fail "Ghostty rejected the $CASE_NAME deployment"
	else
		assert_no_unresolved_source "$CASE_ROOT/ghostty.log" Ghostty
	fi
}

run_case() {
	CASE_NAME=$1
	CUSTOM_XDG=$2
	CASE_ROOT=$ROOT/$CASE_NAME
	HOME_DIR=$CASE_ROOT/home
	HOME_CONFIG=$HOME_DIR/.config
	RUNTIME_DIR=$CASE_ROOT/runtime
	TEMP_DIR=$CASE_ROOT/tmp
	UNRELATED_CWD=$CASE_ROOT/unrelated
	if ((CUSTOM_XDG)); then
		CONFIG_TARGET=$CASE_ROOT/xdg-root
		CONFIG_HOME=$CONFIG_TARGET/.config
		STATE_HOME=$CASE_ROOT/xdg-state
		DATA_HOME=$CASE_ROOT/xdg-data
		CACHE_HOME=$CASE_ROOT/xdg-cache
	else
		CONFIG_TARGET=$HOME_DIR
		CONFIG_HOME=$HOME_CONFIG
		STATE_HOME=$HOME_DIR/.local/state
		DATA_HOME=$HOME_DIR/.local/share
		CACHE_HOME=$HOME_DIR/.cache
	fi

	mkdir -p \
		"$HOME_DIR" \
		"$CONFIG_HOME" \
		"$STATE_HOME" \
		"$DATA_HOME" \
		"$CACHE_HOME" \
		"$RUNTIME_DIR" \
		"$TEMP_DIR" \
		"$UNRELATED_CWD"

	if ! isolated_env \
		DOTFILES_THEME_TESTING=1 \
		DOTFILES_THEME_DISABLE_RELOAD=1 \
		DOTFILES_THEME_BTOP_NATIVE_THEME="$BTOP_NATIVE_THEME" \
		DOTFILES_THEME_STOW="$STOW" \
		"$MANAGER" install >"$CASE_ROOT/install.log" 2>&1; then
		cat -- "$CASE_ROOT/install.log" >&2
		fail "manager install failed for $CASE_NAME"
	fi

	if ((CUSTOM_XDG)); then
		if ! env -i HOME="$HOME_DIR" PATH="$ORIGINAL_PATH" \
			"$STOW" --no-folding -R -d "$REPO_ROOT" -t "$CONFIG_TARGET" hyprland ghostty \
			>"$CASE_ROOT/custom-xdg-stow.log" 2>&1; then
			cat -- "$CASE_ROOT/custom-xdg-stow.log" >&2
			fail 'GNU Stow could not deploy app configs into the custom XDG root'
		fi
	fi

	HYPRLAND_CONFIG=$CONFIG_HOME/hypr/hyprland.lua
	HYPRLOCK_CONFIG=$CONFIG_HOME/hypr/hyprlock.conf
	GHOSTTY_CONFIG=$CONFIG_HOME/ghostty/config
	GHOSTTY_TAB_BAR_CSS=$CONFIG_HOME/ghostty/tab-bar.css
	CURRENT=$CONFIG_HOME/dotfiles-theme/current
	GHOSTTY_SELECTOR=$CURRENT/.config/ghostty/themes/current
	GHOSTTY_BRIDGE=$CONFIG_HOME/ghostty/themes/current

	[[ -d $CONFIG_HOME/hypr && ! -L $CONFIG_HOME/hypr ]] || fail "Hyprland config parent was folded ($CASE_NAME)"
	[[ -d $CONFIG_HOME/ghostty && ! -L $CONFIG_HOME/ghostty ]] || fail "Ghostty config parent was folded ($CASE_NAME)"
	assert_deployed_link "$HYPRLAND_CONFIG" "$REPO_ROOT/hyprland/.config/hypr/hyprland.lua"
	assert_deployed_link "$HYPRLOCK_CONFIG" "$REPO_ROOT/hyprland/.config/hypr/hyprlock.conf"
	assert_deployed_link "$GHOSTTY_CONFIG" "$REPO_ROOT/ghostty/.config/ghostty/config"
	assert_deployed_link "$GHOSTTY_TAB_BAR_CSS" "$REPO_ROOT/ghostty/.config/ghostty/tab-bar.css"
	[[ -f $CURRENT/.config/hypr/colors.lua ]] || fail "active Hyprland bundle path is unresolved ($CASE_NAME)"
	[[ -f $CURRENT/.config/hypr/hyprlock-colors.conf ]] || fail "active Hyprlock bundle path is unresolved ($CASE_NAME)"
	[[ -L $GHOSTTY_SELECTOR ]] || fail "active Ghostty selector is missing ($CASE_NAME)"
	assert_direct_link "$GHOSTTY_BRIDGE" "$CURRENT/.config/ghostty/themes/current"
	[[ ! -e $CURRENT/.config/ghostty/theme.conf && ! -L $CURRENT/.config/ghostty/theme.conf ]] || \
		fail "obsolete Ghostty config fragment was generated ($CASE_NAME)"

	GHOSTTY_SELECTOR_TARGET=$(readlink -- "$GHOSTTY_SELECTOR")
	[[ ${GHOSTTY_SELECTOR_TARGET##*/} == 'Everforest Dark Hard' ]] || \
		fail "Ghostty selector does not target the packaged native theme ($CASE_NAME)"
	if [[ -f $PREFERRED_GHOSTTY_THEME ]]; then
		[[ $GHOSTTY_SELECTOR_TARGET == "$PREFERRED_GHOSTTY_THEME" ]] || \
			fail "Ghostty selector did not prefer $PREFERRED_GHOSTTY_THEME"
	fi

	grep -Fq 'dotfiles-theme/current' "$HYPRLAND_CONFIG" || fail 'Hyprland config does not load the active bundle'
	grep -Fq 'dotfiles-theme/current' "$HYPRLOCK_CONFIG" || fail 'Hyprlock config does not source the active bundle'
	grep -Eq '^[[:space:]]*theme[[:space:]]*=[[:space:]]*current[[:space:]]*$' "$GHOSTTY_CONFIG" || \
		fail 'Ghostty app config does not select the native current theme'
	grep -Eq '^[[:space:]]*background-opacity[[:space:]]*=' "$GHOSTTY_CONFIG" || \
		fail 'Ghostty app config lost its standalone opacity setting'
	grep -Eq '^[[:space:]]*gtk-custom-css[[:space:]]*=[[:space:]]*tab-bar\.css[[:space:]]*$' "$GHOSTTY_CONFIG" || \
		fail 'Ghostty app config does not load the compact tab bar CSS'

	validate_deployment
	printf 'ok - real GNU Stow paths passed (%s)\n' "$CASE_NAME"
}

run_case custom-xdg 1
run_case home-fallback 0

printf 'real GNU Stow path regression passed\n'
