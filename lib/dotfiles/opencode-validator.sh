#!/usr/bin/env bash

set -euo pipefail

if (($# != 2)); then
	printf 'Usage: %s <opencode.json> <tui.json>\n' "$0" >&2
	exit 2
fi

main_config=$1
tui_config=$2

if ! jq -e '
	type == "object" and
	keys_unsorted == ["$schema", "autoupdate"] and
	. == {"$schema":"https://opencode.ai/config.json","autoupdate":false}
' "$main_config" >/dev/null; then
	printf 'Error: OpenCode main config does not match the managed object: %s\n' "$main_config" >&2
	exit 1
fi

if ! jq -e '
	type == "object" and
	keys_unsorted == ["$schema", "theme"] and
	. == {"$schema":"https://opencode.ai/tui.json","theme":"system"}
' "$tui_config" >/dev/null; then
	printf 'Error: OpenCode TUI config does not match the managed object: %s\n' "$tui_config" >&2
	exit 1
fi

main_config=$(realpath -e -- "$main_config")
tui_config=$(realpath -e -- "$tui_config")
if ! opencode_executable=$(command -v opencode) || [[ $opencode_executable != /* ]]; then
	printf 'Error: opencode executable is unavailable\n' >&2
	exit 127
fi
opencode_executable=$(realpath -e -- "$opencode_executable")
if [[ ! -f $opencode_executable || ! -x $opencode_executable ]]; then
	printf 'Error: resolved opencode executable is not executable: %s\n' "$opencode_executable" >&2
	exit 127
fi

validator_root=
cleanup() {
	local status=$?
	trap - EXIT HUP INT TERM
	if [[ -n $validator_root && -d $validator_root ]]; then
		chmod -R u+w -- "$validator_root" 2>/dev/null || true
		rm -rf -- "$validator_root"
	fi
	exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

validator_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-opencode-validator.XXXXXX")
synthetic_home=$validator_root/home
neutral_work=$validator_root/work
isolated_tmp=$validator_root/tmp
xdg_config=$validator_root/xdg-config
xdg_data=$validator_root/xdg-data
xdg_state=$validator_root/xdg-state
xdg_cache=$validator_root/xdg-cache
managed_config=$validator_root/managed

mkdir -p -- \
	"$synthetic_home" \
	"$neutral_work" \
	"$isolated_tmp" \
	"$xdg_config/opencode" \
	"$xdg_data" \
	"$xdg_state" \
	"$xdg_cache" \
	"$managed_config"
chmod 0555 -- "$xdg_config" "$xdg_config/opencode" "$managed_config"

(
	cd -- "$neutral_work"
	env -i \
		HOME="$synthetic_home" \
		PATH=/usr/bin:/bin \
		TMPDIR="$isolated_tmp" \
		XDG_CONFIG_HOME="$xdg_config" \
		XDG_DATA_HOME="$xdg_data" \
		XDG_STATE_HOME="$xdg_state" \
		XDG_CACHE_HOME="$xdg_cache" \
		OPENCODE_CONFIG="$main_config" \
		OPENCODE_CONFIG_CONTENT='{"lsp":false}' \
		OPENCODE_DB=:memory: \
		OPENCODE_PURE=1 \
		OPENCODE_DISABLE_PROJECT_CONFIG=1 \
		OPENCODE_DISABLE_DEFAULT_PLUGINS=1 \
		OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
		OPENCODE_DISABLE_CLAUDE_CODE=1 \
		OPENCODE_DISABLE_MODELS_FETCH=1 \
		OPENCODE_DISABLE_LSP_DOWNLOAD=1 \
		OPENCODE_DISABLE_AUTOUPDATE=1 \
		OPENCODE_TEST_MANAGED_CONFIG_DIR="$managed_config" \
		"$opencode_executable" --pure debug config >/dev/null
)
