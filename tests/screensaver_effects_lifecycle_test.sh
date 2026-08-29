#!/usr/bin/env bash

set -u

readonly SOURCE_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

TESTS_RUN=0
TESTS_FAILED=0
FIXTURE_ROOT=''

cleanup() {
	[[ -z $FIXTURE_ROOT ]] || rm -rf -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

fail() {
	printf 'not ok %d - %s\n' "$TESTS_RUN" "$1"
	TESTS_FAILED=$((TESTS_FAILED + 1))
}

pass() {
	printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

assert_eq() {
	local expected=$1 actual=$2 message=$3
	if [[ $actual != "$expected" ]]; then
		printf '  %s\n  expected: %q\n  actual:   %q\n' "$message" "$expected" "$actual" >&2
		return 1
	fi
}

assert_contains() {
	local value=$1 expected=$2 message=$3
	if [[ $value != *"$expected"* ]]; then
		printf '  %s\n  missing: %q\n  output:  %q\n' "$message" "$expected" "$value" >&2
		return 1
	fi
}

make_fake() {
	local name=$1 body=$2
	{
		printf '#!/usr/bin/env bash\nset -euo pipefail\n'
		printf '%s\n' "$body"
	} >"$FIXTURE_BIN/$name"
	chmod +x "$FIXTURE_BIN/$name"
}

new_fixture() {
	cleanup
	FIXTURE_ROOT=$(mktemp -d)
	FIXTURE_HOME=$FIXTURE_ROOT/home
	FIXTURE_STATE=$FIXTURE_ROOT/state
	FIXTURE_BIN=$FIXTURE_ROOT/bin
	FIXTURE_CALLS=$FIXTURE_ROOT/calls
	mkdir -p "$FIXTURE_HOME/.config/omarchy/plugins" "$FIXTURE_STATE" "$FIXTURE_BIN"
	: >"$FIXTURE_CALLS"

	cat >"$FIXTURE_HOME/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "idle": {"screensaver": 150, "lock": 300},
  "bar": {
    "layout": {
      "left": [],
      "center": [{"id":"omarchy.indicators","items":["idle"],"custom":true}],
      "right": []
    }
  },
  "plugins": [],
  "stayAwake": {"enabled": true}
}
JSON

	make_fake pacman 'case "$*" in
  "-Q omarchy") printf "omarchy %s\n" "${SCREENSAVER_TEST_PACMAN_OMARCHY_VERSION:-4.0.1-1}" ;;
  "-Q ttfx") printf "ttfx %s\n" "${SCREENSAVER_TEST_PACMAN_TTFX_VERSION:-0.3.2-1}" ;;
  *) exit 1 ;;
esac'
	make_fake omarchy 'if [[ $* == "plugin list --json" ]]; then
  config="$HOME/.config/omarchy/shell.json"
  jq -c '\''
    def entry_id: if type == "object" then .id else . end;
    (.disabledPlugins // []) as $disabled |
    [
      {id:"omarchy.idle",enabled:($disabled | index("omarchy.idle") | not),firstParty:true,clonedFrom:""},
      {id:"omarchy.indicators",enabled:($disabled | index("omarchy.indicators") | not),firstParty:true,clonedFrom:""}
    ]
  '\'' "$config"
  exit 0
fi
exit 64'
	make_fake omarchy-shell 'if [[ $* == "shell listShellConfig" ]]; then
  [[ ${SCREENSAVER_TEST_FAIL_SHELL_INSPECT:-false} == false ]] || exit 75
  jq -c . "$HOME/.config/omarchy/shell.json"
  exit 0
fi
exit 64'
}

setup_package_fixture() {
	FIXTURE_REPO=$FIXTURE_ROOT/repo
	mkdir -p "$FIXTURE_REPO/bin" "$FIXTURE_REPO/lib/dotfiles" \
		"$FIXTURE_REPO/config/screensaver-effects/.config/dotfiles" \
		"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle" \
		"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators" \
		"$FIXTURE_REPO/config/screensaver-effects/.local/libexec/dotfiles"
	cp "$SOURCE_REPO/bin/dotfiles" "$FIXTURE_REPO/bin/dotfiles"
	cp "$SOURCE_REPO/lib/dotfiles/core.sh" "$SOURCE_REPO/lib/dotfiles/packages.sh" \
		"$SOURCE_REPO/lib/dotfiles/screensaver-effects.sh" "$FIXTURE_REPO/lib/dotfiles/"
	cp "$SOURCE_REPO/lib/dotfiles/screensaver-effects-jsonc.mjs" "$FIXTURE_REPO/lib/dotfiles/"
	cat >"$FIXTURE_REPO/packages.json" <<'JSON'
{
  "packages": [{
    "name": "screensaver-effects",
    "path": "config/screensaver-effects",
    "description": "Selective Omarchy screensaver effects",
    "dependencies": [],
    "arch_packages": [],
    "prerequisites": ["node", "omarchy-shell"],
    "validators": [],
    "documentation": null,
    "cleanup": ["Lifecycle state is retained"]
  }]
}
JSON
	cat >"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"dotfiles.idle","name":"Dotfiles Idle","version":"1","kinds":["service"],"entryPoints":{"service":"Service.qml"},"omarchy":{"clonedFrom":"omarchy.idle"}}
JSON
	printf 'Item { property string marker: "idle-v1" }\n' \
		>"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml"
	cat >"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"dotfiles.indicators","name":"Dotfiles Indicators","version":"1","kinds":["bar-widget"],"entryPoints":{"barWidget":"Indicators.qml"},"omarchy":{"clonedFrom":"omarchy.indicators"}}
JSON
	printf 'Item { property string marker: "indicators-v1" }\n' \
		>"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/Indicators.qml"
	printf '["matrix"]\n' >"$FIXTURE_REPO/config/screensaver-effects/.config/dotfiles/screensaver-effects.json"
	printf '#!/usr/bin/env bash\nprintf "selector fixture\\n"\n' \
		>"$FIXTURE_REPO/config/screensaver-effects/.local/libexec/dotfiles/screensaver-effects-selector"
	chmod +x "$FIXTURE_REPO/config/screensaver-effects/.local/libexec/dotfiles/screensaver-effects-selector"

	mkdir -p "$FIXTURE_HOME/.config/omarchy/extensions"
	cat >"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" <<'JSONC'
{
  // unrelated bytes must survive
  "custom.action": {"label":"Keep me","action":"true"},
}
JSONC
	MENU_ORIGINAL=$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")
	MENU_ORIGINAL_SUFFIX=${MENU_ORIGINAL#*$'\n'}

	make_fake stow 'simulate=false
delete=false
directory=""
target=""
package=""
while (($#)); do
  case $1 in
    --simulate) simulate=true ;;
    --delete) delete=true ;;
    --dir) shift; directory=$1 ;;
    --target) shift; target=$1 ;;
    --*) ;;
    *) package=$1 ;;
  esac
  shift
done
printf "stow simulate=%s delete=%s package=%s\n" "$simulate" "$delete" "$package" >>"$SCREENSAVER_TEST_CALLS"
[[ $simulate == false ]] || exit 0
if [[ $delete == true && ${SCREENSAVER_TEST_STOW_DELETE_FAILURE:-false} == true ]]; then exit 79; fi
root=$directory/$package
deleted=0
while IFS= read -r -d "" source; do
  relative=${source#"$root/"}
  destination=$target/$relative
  if [[ $delete == true ]]; then
    if [[ -L $destination && $(readlink -f -- "$destination") == $(readlink -f -- "$source") ]]; then
      rm -f -- "$destination"
      deleted=$((deleted + 1))
      if [[ ${SCREENSAVER_TEST_STOW_DELETE_PARTIAL_FAILURE:-false} == true && $deleted -eq 1 ]]; then exit 79; fi
    fi
  elif [[ ! -e $destination && ! -L $destination ]]; then
    mkdir -p -- "${destination%/*}"
    ln -s -- "$source" "$destination"
  elif [[ ! -L $destination || $(readlink -f -- "$destination") != $(readlink -f -- "$source") ]]; then
    exit 1
  fi
done < <(find "$root" -type f -print0)'

	make_fake omarchy 'config="$HOME/.config/omarchy/shell.json"
plugin_list() {
	  idle_installed=false
	  indicators_installed=false
	  legacy_idle_installed=false
	  legacy_indicators_installed=false
	  [[ -f $HOME/.config/omarchy/plugins/dotfiles.idle/manifest.json ]] && idle_installed=true
	  [[ -f $HOME/.config/omarchy/plugins/dotfiles.indicators/manifest.json ]] && indicators_installed=true
	  [[ -f $HOME/.config/omarchy/plugins/legacy.idle/manifest.json ]] && legacy_idle_installed=true
	  [[ -f $HOME/.config/omarchy/plugins/legacy.indicators/manifest.json ]] && legacy_indicators_installed=true
	  jq -cn --argjson config "$(jq -c . "$config")" --argjson idleInstalled "$idle_installed" --argjson indicatorsInstalled "$indicators_installed" \
	    --argjson legacyIdleInstalled "$legacy_idle_installed" --argjson legacyIndicatorsInstalled "$legacy_indicators_installed" '\''
	    def entry_id: if type == "object" then (.id // "") else tostring end;
	    ($config.disabledPlugins // []) as $disabled |
	    ([$config.bar.layout[][] | entry_id]) as $bar |
	    ($config.plugins // [] | map(.id)) as $services |
    [
	      {id:"omarchy.idle",enabled:($disabled | index("omarchy.idle") | not),firstParty:true,clonedFrom:""},
	      {id:"omarchy.indicators",enabled:($disabled | index("omarchy.indicators") | not),firstParty:true,clonedFrom:""}
	    ]
	    + (if $idleInstalled then [{id:"dotfiles.idle",enabled:($services | index("dotfiles.idle") != null),firstParty:false,clonedFrom:"omarchy.idle"}] else [] end)
	    + (if $indicatorsInstalled then [{id:"dotfiles.indicators",enabled:($bar | index("dotfiles.indicators") != null),firstParty:false,clonedFrom:"omarchy.indicators"}] else [] end)
	    + (if $legacyIdleInstalled then [{id:"legacy.idle",enabled:($services | index("legacy.idle") != null),firstParty:false,clonedFrom:"omarchy.idle"}] else [] end)
	    + (if $legacyIndicatorsInstalled then [{id:"legacy.indicators",enabled:($bar | index("legacy.indicators") != null),firstParty:false,clonedFrom:"omarchy.indicators"}] else [] end)
	  '\''
}
case ${1-} in
  version) printf "%s\n" "${SCREENSAVER_TEST_OMARCHY_CLI_VERSION:-4.0.1-1}" ;;
  pkg)
    [[ ${2-} == present ]] || exit 64
    ;;
  bar)
    [[ ${2-} == set && ${3-} == omarchy.indicators && ${4-} == id && ${5-} == dotfiles.indicators ]] || exit 64
    section=${7-}; index=${9-}
    temporary=$config.tmp
    jq --arg section "$section" --argjson index "$index" '\''.bar.layout[$section][$index].id = "dotfiles.indicators"'\'' "$config" >"$temporary"
    mv "$temporary" "$config"
    printf "bar set %s %s\n" "$section" "$index" >>"$SCREENSAVER_TEST_CALLS"
    ;;
  plugin)
    case ${2-}:${3-} in
      list:--json) plugin_list ;;
      enable:dotfiles.idle)
        [[ ${SCREENSAVER_TEST_FAIL_IDLE_ENABLE:-false} == false ]] || exit 75
        temporary=$config.tmp
        jq '\''
          (.disabledPlugins // []) as $disabled |
          if (.disabledPlugins | type) == "array" then
            .disabledPlugins = (.disabledPlugins | map(select(. != "dotfiles.idle")))
          else . end |
          if ((.plugins // []) | any(.id == "dotfiles.idle")) then .
          else .plugins = ((.plugins // []) + [{id:"dotfiles.idle"}]) end |
          if ($disabled | index("omarchy.idle")) == null then
            .disabledPlugins = ((.disabledPlugins // []) + ["omarchy.idle"]) |
            .cloneSourceRestores = (((.cloneSourceRestores // []) | map(select(. != "dotfiles.idle"))) + ["dotfiles.idle"])
          else . end |
          .version = 1 |
          to_entries | reverse | from_entries
        '\'' "$config" >"$temporary"
        if [[ ${SCREENSAVER_TEST_UNEXPECTED_IDLE_COMMAND_CHANGE:-false} == true ]]; then
          jq '\''.stayAwake.enabled = false'\'' "$temporary" >"$temporary.unexpected"
          mv "$temporary.unexpected" "$temporary"
        fi
        mv "$temporary" "$config"
        chmod 0640 "$config"
        cp -- "$config" "$SCREENSAVER_TEST_CALLS.shell-after-idle-enable"
        printf "plugin enable dotfiles.idle\n" >>"$SCREENSAVER_TEST_CALLS"
        ;;
      disable:dotfiles.idle)
        temporary=$config.tmp
        jq '\''
          .plugins = ((.plugins // []) | map(select(.id != "dotfiles.idle"))) |
          if ((.cloneSourceRestores // []) | index("dotfiles.idle")) != null then
            .disabledPlugins = ((.disabledPlugins // []) | map(select(. != "omarchy.idle"))) |
            .cloneSourceRestores = ((.cloneSourceRestores // []) | map(select(. != "dotfiles.idle"))) |
            if (.cloneSourceRestores | length) == 0 then del(.cloneSourceRestores) else . end
          else . end |
          .version = 1 |
          to_entries | reverse | from_entries
        '\'' "$config" >"$temporary"
        if [[ ${SCREENSAVER_TEST_UNEXPECTED_IDLE_COMMAND_CHANGE:-false} == true ]]; then
          jq '\''.stayAwake.enabled = false'\'' "$temporary" >"$temporary.unexpected"
          mv "$temporary.unexpected" "$temporary"
        fi
        mv "$temporary" "$config"
        chmod 0640 "$config"
        cp -- "$config" "$SCREENSAVER_TEST_CALLS.shell-after-idle-disable"
        printf "plugin disable dotfiles.idle\n" >>"$SCREENSAVER_TEST_CALLS"
        ;;
      disable:dotfiles.indicators) printf "plugin disable dotfiles.indicators\n" >>"$SCREENSAVER_TEST_CALLS" ;;
      disable:legacy.idle)
        temporary=$config.tmp
        jq '\''
          .plugins = ((.plugins // []) | map(select(.id != "legacy.idle"))) |
          .disabledPlugins = ((.disabledPlugins // []) | map(select(. != "omarchy.idle"))) |
          .cloneSourceRestores = ((.cloneSourceRestores // []) | map(select(. != "legacy.idle"))) |
          if (.disabledPlugins | length) == 0 then del(.disabledPlugins) else . end |
          if (.cloneSourceRestores | length) == 0 then del(.cloneSourceRestores) else . end
        '\'' "$config" >"$temporary"
        mv "$temporary" "$config"
        printf "plugin disable legacy.idle\n" >>"$SCREENSAVER_TEST_CALLS"
        ;;
      disable:legacy.indicators)
        temporary=$config.tmp
        jq '\''walk(if type == "object" and .id == "legacy.indicators" then .id = "omarchy.indicators" else . end)'\'' \
          "$config" >"$temporary"
        mv "$temporary" "$config"
        printf "plugin disable legacy.indicators\n" >>"$SCREENSAVER_TEST_CALLS"
        ;;
      remove:dotfiles.idle|remove:dotfiles.indicators)
        rm -f -- "$HOME/.config/omarchy/plugins/${3}"
        printf "plugin remove %s\n" "$3" >>"$SCREENSAVER_TEST_CALLS"
        ;;
      remove:legacy.idle|remove:legacy.indicators)
        mv -- "$HOME/.config/omarchy/plugins/${3}" "$HOME/.config/omarchy/plugins/.${3}.bak.fixture"
        printf "plugin remove %s\n" "$3" >>"$SCREENSAVER_TEST_CALLS"
        ;;
      *) exit 64 ;;
    esac
    ;;
  *) exit 64 ;;
esac'
	make_fake omarchy-shell 'config="$HOME/.config/omarchy/shell.json"
case "$*" in
  "shell listShellConfig")
    [[ ${SCREENSAVER_TEST_FAIL_SHELL_INSPECT:-false} == false ]] || exit 75
    jq -c . "$config"
    ;;
  "shell rescanPlugins") printf "rescan\n" >>"$SCREENSAVER_TEST_CALLS" ;;
  "shell reloadConfig")
    if [[ ${SCREENSAVER_TEST_DRIFT_AFTER_BAR_RELOAD:-false} == true && ! -e $SCREENSAVER_TEST_CALLS.injected-bar-drift ]]; then
      : >"$SCREENSAVER_TEST_CALLS.injected-bar-drift"
      temporary=$config.injected
      jq '\''.bar.layout.center[0].custom = false'\'' "$config" >"$temporary"
      mv "$temporary" "$config"
    fi
    printf "reload\n" >>"$SCREENSAVER_TEST_CALLS"
    ;;
  *) exit 64 ;;
esac'
}

run_package_operation() {
	local function=$1
	shift
	local output_file=$FIXTURE_ROOT/package-output
	set +e
	printf '%b' "${SCREENSAVER_TEST_INPUT-}" | \
		HOME=$FIXTURE_HOME XDG_STATE_HOME=$FIXTURE_STATE PATH="$FIXTURE_BIN:$PATH" DOTFILES_UI=bash \
		SCREENSAVER_TEST_CALLS=$FIXTURE_CALLS SCREENSAVER_TEST_FAIL_IDLE_ENABLE=${SCREENSAVER_TEST_FAIL_IDLE_ENABLE-false} \
		SCREENSAVER_TEST_STOW_DELETE_FAILURE=${SCREENSAVER_TEST_STOW_DELETE_FAILURE-false} \
		SCREENSAVER_TEST_STOW_DELETE_PARTIAL_FAILURE=${SCREENSAVER_TEST_STOW_DELETE_PARTIAL_FAILURE-false} \
		SCREENSAVER_TEST_DRIFT_AFTER_BAR_RELOAD=${SCREENSAVER_TEST_DRIFT_AFTER_BAR_RELOAD-false} \
		SCREENSAVER_TEST_FAIL_SHELL_INSPECT=${SCREENSAVER_TEST_FAIL_SHELL_INSPECT-false} \
		SCREENSAVER_TEST_UNEXPECTED_IDLE_COMMAND_CHANGE=${SCREENSAVER_TEST_UNEXPECTED_IDLE_COMMAND_CHANGE-false} \
		SCREENSAVER_TEST_OMARCHY_CLI_VERSION=${SCREENSAVER_TEST_OMARCHY_CLI_VERSION-4.0.1-1} \
		SCREENSAVER_TEST_PACMAN_OMARCHY_VERSION=${SCREENSAVER_TEST_PACMAN_OMARCHY_VERSION-4.0.1-1} \
		SCREENSAVER_TEST_PACMAN_TTFX_VERSION=${SCREENSAVER_TEST_PACMAN_TTFX_VERSION-0.3.2-1} \
		bash -c 'set -euo pipefail
source "$1/lib/dotfiles/core.sh"
source "$1/lib/dotfiles/screensaver-effects.sh"
source "$1/lib/dotfiles/packages.sh"
shift
"$@"' _ "$FIXTURE_REPO" "$function" "$@" >"$output_file" 2>&1
	COMMAND_STATUS=$?
	set -e
	COMMAND_OUTPUT=$(<"$output_file")
}

assert_fixture_package_links_exact() {
	local package_root=$FIXTURE_REPO/config/screensaver-effects source relative target
	while IFS= read -r -d '' source; do
		relative=${source#"$package_root/"}
		target=$FIXTURE_HOME/$relative
		if [[ ! -L $target || $(readlink -f -- "$target") != "$(readlink -f -- "$source")" ]]; then
			printf '  expected exact package link: %s -> %s\n' "$target" "$source" >&2
			return 1
		fi
	done < <(find "$package_root" -type f -print0)
}

seed_competing_clones() {
	mkdir -p "$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle" "$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators"
	cat >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"legacy.idle","name":"Legacy Idle","version":"1","kinds":["service"],"entryPoints":{"service":"Service.qml"},"omarchy":{"clonedFrom":"omarchy.idle"}}
JSON
	printf 'legacy idle implementation\n' >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/Service.qml"
	printf 'unknown idle customization\n' >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/unknown-file"
	cat >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"legacy.indicators","name":"Legacy Indicators","version":"1","kinds":["bar-widget"],"entryPoints":{"barWidget":"Indicators.qml"},"omarchy":{"clonedFrom":"omarchy.indicators"}}
JSON
	printf 'legacy indicators implementation\n' >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators/Indicators.qml"
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/competing-shell.json
	jq '
	  .plugins = [{id:"legacy.idle"}] |
	  .disabledPlugins = ["omarchy.idle"] |
	  .cloneSourceRestores = ["legacy.idle"] |
	  .bar.layout.center[0].id = "legacy.indicators"
	' "$config" >"$temporary"
	mv "$temporary" "$config"
}

run_status() {
	local output_file=$FIXTURE_ROOT/output
	set +e
	HOME=$FIXTURE_HOME XDG_STATE_HOME=$FIXTURE_STATE PATH="$FIXTURE_BIN:$PATH" \
		SCREENSAVER_TEST_FAIL_SHELL_INSPECT=${SCREENSAVER_TEST_FAIL_SHELL_INSPECT-false} \
		bash -c 'set -euo pipefail
source "$1/lib/dotfiles/core.sh"
source "$1/lib/dotfiles/screensaver-effects.sh"
screensaver_effects_status' _ "$SOURCE_REPO" >"$output_file" 2>&1
	COMMAND_STATUS=$?
	set -e
	COMMAND_OUTPUT=$(<"$output_file")
}

test_status_reports_exact_compatibility_and_inactive_lifecycle() {
	new_fixture
	run_status
	assert_eq 0 "$COMMAND_STATUS" 'read-only lifecycle status should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4.0.1-1' 'status should show the exact supported Omarchy package version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.1-1' 'status should show the exact detected Omarchy package version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported ttfx: 0.3.2-1' 'status should show the exact supported ttfx package version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected ttfx: 0.3.2-1' 'status should show the exact detected ttfx package version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: inactive' 'an unowned installation should be classified as inactive'
}

test_status_requires_readable_shell_without_receipt() {
	new_fixture
	SCREENSAVER_TEST_FAIL_SHELL_INSPECT=true run_status
	assert_eq 0 "$COMMAND_STATUS" 'status should remain available when shell inspection fails' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: recovery-required' \
		'unreceipted shell inspection uncertainty must not be classified as inactive'
}

test_unreceipted_shell_activation_is_conflicting() {
	new_fixture
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/stale-shell.json
	jq '.plugins = [{"id":"dotfiles.idle"}] | .cloneSourceRestores = ["dotfiles.idle"]' "$config" >"$temporary"
	mv -- "$temporary" "$config"
	run_status
	assert_eq 0 "$COMMAND_STATUS" 'status should remain available for unreceipted shell activation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: conflicting' \
		'unreceipted dotfiles plugin activation must not be reported as inactive'
}

test_unreceipted_shell_activation_blocks_removal_before_stow() {
	new_fixture
	setup_package_fixture
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/stale-shell.json
	jq '.plugins = [{"id":"dotfiles.idle"}] | .cloneSourceRestores = ["dotfiles.idle"]' "$config" >"$temporary"
	mv -- "$temporary" "$config"

	run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'unreceipted shell activation should block generic Stow removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'shell.json retains Dotfiles activation, bar, or restoration state' \
		'unreceipted removal should identify the residual shell edge' || return 1
	assert_eq 0 "$(awk '$0 ~ /^stow / { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'unreceipted shell edges should stop removal before Stow simulation or mutation'
}

test_first_apply_and_exact_reapply_publish_one_rescan_and_stable_receipt() {
	new_fixture
	setup_package_fixture
	local shell_before shell_mode_before expected_shell
	shell_before=$(<"$FIXTURE_HOME/.config/omarchy/shell.json")
	shell_mode_before=$(stat -c %a "$FIXTURE_HOME/.config/omarchy/shell.json")
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	if ((COMMAND_STATUS != 0)); then printf '  apply output: %s\n' "$COMMAND_OUTPUT" >&2; fi
	assert_eq 0 "$COMMAND_STATUS" 'first package apply should activate the lifecycle' || return 1
	assert_eq "$FIXTURE_HOME/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle" \
		"$(readlink "$FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle")" \
		'first apply should publish idle as one canonical directory symlink' || return 1
	assert_eq "$FIXTURE_HOME/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators" \
		"$(readlink "$FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators")" \
		'first apply should publish Indicators as one canonical directory symlink' || return 1
	assert_eq 1 "$(awk '$0 == "rescan" { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'first apply should perform exactly one explicit plugin rescan' || return 1
	assert_eq cloneSourceRestores "$(jq -r 'keys_unsorted[0]' "$FIXTURE_CALLS.shell-after-idle-enable")" \
		'the fake supported command should deliberately reorder the complete shell document' || return 1
	expected_shell=${shell_before/'"omarchy.indicators"'/'"dotfiles.indicators"'}
	expected_shell=${expected_shell/'"plugins": []'/'"plugins": [{"id":"dotfiles.idle"}]'}
	expected_shell=${expected_shell/$'\n}'/',"disabledPlugins":["omarchy.idle"],"cloneSourceRestores":["dotfiles.idle"]'$'\n}'}
	assert_eq "$expected_shell" "$(<"$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'Apply should preserve every unrelated shell byte around its narrow lifecycle entries' || return 1
	assert_eq "$shell_mode_before" "$(stat -c %a "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'Apply should preserve shell.json mode despite Omarchy rewriting the file' || return 1
	assert_eq 0 "$(awk '$0 ~ /^bar set / { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'Indicators activation should not use the whole-file Omarchy bar mutation' || return 1
	assert_eq dotfiles.indicators "$(jq -r '.bar.layout.center[0].id' "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'first apply should replace the Indicators identity in place' || return 1
	assert_eq true "$(jq -r '.bar.layout.center[0].custom' "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'first apply should preserve Indicators options' || return 1
	assert_eq true "$(jq -r '.stayAwake.enabled' "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'first apply must not change Stay Awake state' || return 1
	local menu receipt receipt_before
	menu=$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")
	assert_contains "$menu" "$MENU_ORIGINAL_SUFFIX" 'menu publication should retain unrelated bytes as one unchanged suffix' || return 1
	assert_contains "$menu" 'omarchy-shell idle screensaver' 'menu publication should route through the idle IPC seam' || return 1
	receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json
	jq -e '.schema_version == 1 and .state == "active" and .owned_edges.menu_entry == true' "$receipt" >/dev/null || {
		printf '  first apply did not publish a valid active ownership receipt\n' >&2
		return 1
	}
	receipt_before=$(sha256sum "$receipt")

	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'exact reapply should succeed' || return 1
	assert_eq 1 "$(awk '$0 == "rescan" { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'exact reapply should not rescan plugins' || return 1
	assert_eq "$receipt_before" "$(sha256sum "$receipt")" 'exact reapply should not churn receipt metadata'
}

test_changed_validated_source_gets_one_rescan() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'initial apply should succeed before source change' || return 1
	printf 'Item { property string marker: "idle-v2" }\n' \
		>"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml"
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'reapply should accept a validated source change' || return 1
	assert_eq 2 "$(awk '$0 == "rescan" { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'a validated source change should add exactly one explicit rescan' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Screensaver effects lifecycle active and verified' \
		'changed source should converge to a verified active lifecycle'
}

test_missing_owned_link_and_activation_drift_are_repaired() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'initial apply should succeed before owned drift' || return 1
	rm -- "$FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle"
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/drifted-shell.json
	jq '
	  .plugins = ((.plugins // []) | map(select(.id != "dotfiles.idle"))) |
	  .disabledPlugins = ((.disabledPlugins // []) | map(select(. != "omarchy.idle"))) |
	  .cloneSourceRestores = ((.cloneSourceRestores // []) | map(select(. != "dotfiles.idle"))) |
	  if (.disabledPlugins | length) == 0 then del(.disabledPlugins) else . end |
	  if (.cloneSourceRestores | length) == 0 then del(.cloneSourceRestores) else . end
	' "$config" >"$temporary"
	mv -- "$temporary" "$config"

	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should repair a missing receipt-owned link and activation' || return 1
	assert_eq 2 "$(awk '$0 == "rescan" { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'owned link repair should perform exactly one additional rescan' || return 1
	[[ -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle ]] || return 1
	jq -e '.plugins | any(.id == "dotfiles.idle")' "$config" >/dev/null || return 1
	run_package_operation screensaver_effects_status
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: active' 'repaired lifecycle should verify as active'
}

test_unrelated_indicators_bar_drift_stops_before_mutation() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'initial apply should succeed before unrelated bar drift' || return 1
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/foreign-bar.json before calls_before
	jq '.bar.layout.right += [{"id":"omarchy.indicators","foreign":true}]' "$config" >"$temporary"
	mv -- "$temporary" "$config"
	before=$(sha256sum "$config")
	calls_before=$(<"$FIXTURE_CALLS")

	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'unrelated Indicators bar drift should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'receipt-owned Indicators bar positions contain unrelated entries' \
		'bar conflict should identify the unrelated entry boundary' || return 1
	assert_eq "$before" "$(sha256sum "$config")" 'bar conflict should preserve shell bytes' || return 1
	assert_eq "$calls_before" "$(<"$FIXTURE_CALLS")" 'bar conflict should stop before Stow or lifecycle mutation'
}

test_activation_failure_rolls_back_lifecycle_but_retains_stow_links() {
	new_fixture
	setup_package_fixture
	local shell_before menu_before
	shell_before=$(<"$FIXTURE_HOME/.config/omarchy/shell.json")
	menu_before=$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")
	SCREENSAVER_TEST_FAIL_IDLE_ENABLE=true SCREENSAVER_TEST_INPUT='y\n' \
		run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'injected idle activation failure should fail Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stow linked, lifecycle inactive' \
		'failed activation should report the retained recoverable Stow state' || return 1
	[[ -L $FIXTURE_HOME/.config/dotfiles/screensaver-effects.json ]] || {
		printf '  activation rollback removed the valid Stow allowlist link\n' >&2
		return 1
	}
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && ! -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle ]] || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators && ! -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators ]] || return 1
	assert_eq "$shell_before" "$(<"$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'activation rollback should restore exact shell bytes' || return 1
	assert_eq "$menu_before" "$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" \
		'activation rollback should restore exact menu bytes' || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/pending.json ]] || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json ]] || return 1
	[[ -d $FIXTURE_STATE/dotfiles/screensaver-effects/diagnostics ]] || {
		printf '  activation failure did not retain diagnostics\n' >&2
		return 1
	}
}

test_unexpected_idle_command_change_fails_closed_and_restores_bytes() {
	new_fixture
	setup_package_fixture
	local shell_before mode_before
	shell_before=$(<"$FIXTURE_HOME/.config/omarchy/shell.json")
	mode_before=$(stat -c %a "$FIXTURE_HOME/.config/omarchy/shell.json")
	SCREENSAVER_TEST_UNEXPECTED_IDLE_COMMAND_CHANGE=true SCREENSAVER_TEST_INPUT='y\n' \
		run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'unexpected Omarchy shell changes should fail Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unexpected shell configuration changes' \
		'command verification should identify unexpected semantic mutation' || return 1
	assert_eq "$shell_before" "$(<"$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'unexpected command changes should restore exact pre-command bytes' || return 1
	assert_eq "$mode_before" "$(stat -c %a "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'unexpected command changes should restore the pre-command mode' || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json ]]
}

test_activation_rollback_refuses_changed_owned_coordinate() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_DRIFT_AFTER_BAR_RELOAD=true SCREENSAVER_TEST_INPUT='y\n' \
		run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'owned coordinate drift during activation should fail Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package status reports recovery-required' \
		'rollback should report that exact owned-coordinate restoration was refused' || return 1
	assert_eq false "$(jq -r '.bar.layout.center[0].custom' "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'rollback must not overwrite a changed receipt-owned coordinate' || return 1
	jq -e '.state == "recovery-required" and .operation == "apply"' \
		"$FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json" >/dev/null
}

test_removal_restores_prior_state_and_retains_inactive_receipt() {
	new_fixture
	setup_package_fixture
	local menu_before shell_before shell_mode_before
	menu_before=$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")
	shell_before=$(<"$FIXTURE_HOME/.config/omarchy/shell.json")
	shell_mode_before=$(stat -c %a "$FIXTURE_HOME/.config/omarchy/shell.json")
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'apply should succeed before removal' || return 1
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'approved removal should deactivate before generic Stow removal' || return 1
	assert_eq "$shell_before" "$(<"$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'Apply and Remove should restore the exact full pre-Apply shell bytes' || return 1
	assert_eq "$shell_mode_before" "$(stat -c %a "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'Remove should restore the exact pre-Apply shell mode' || return 1
	assert_eq "$menu_before" "$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" \
		'removal should restore exact prior menu bytes' || return 1
	[[ ! -e $FIXTURE_HOME/.config/dotfiles/screensaver-effects.json && ! -L $FIXTURE_HOME/.config/dotfiles/screensaver-effects.json ]] || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && ! -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle ]] || return 1
	jq -e '.schema_version == 1 and .state == "inactive" and .removed_at != null' \
		"$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json" >/dev/null || {
		printf '  removal did not retain a valid inactive lifecycle receipt\n' >&2
		return 1
	}
	assert_contains "$COMMAND_OUTPUT" 'receipt, backups, and diagnostics retained' \
		'removal should report retained recovery evidence'
}

test_removal_preserves_unrelated_active_shell_byte_edit() {
	new_fixture
	setup_package_fixture
	local shell_before expected active edited config=$FIXTURE_HOME/.config/omarchy/shell.json
	shell_before=$(<"$config")
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'apply should succeed before an unrelated active shell edit' || return 1
	active=$(<"$config")
	edited=${active/'"stayAwake": {"enabled": true}'/'"stayAwake" : {"enabled": true, "note":"keep-byte-style"}'}
	[[ $edited != "$active" ]] || return 1
	printf '%s\n' "$edited" >"$config"
	expected=${shell_before/'"stayAwake": {"enabled": true}'/'"stayAwake" : {"enabled": true, "note":"keep-byte-style"}'}

	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'removal should accept an unrelated active shell edit' || return 1
	assert_eq "$expected" "$(<"$config")" \
		'supported disable and Indicators restoration should preserve the unrelated edit bytes'
}

test_changed_owned_indicators_coordinate_blocks_removal() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'apply should succeed before owned-coordinate drift' || return 1
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/owned-drift.json before calls_before
	jq '.bar.layout.center[0].custom = false' "$config" >"$temporary"
	mv -- "$temporary" "$config"
	before=$(sha256sum "$config")
	calls_before=$(<"$FIXTURE_CALLS")

	run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'changed data at an owned Indicators coordinate should block removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'active Indicators bar edges moved or were replaced' \
		'removal should identify changed receipt-owned Indicators data' || return 1
	assert_eq "$before" "$(sha256sum "$config")" 'removal refusal should preserve changed shell bytes' || return 1
	assert_eq "$calls_before" "$(<"$FIXTURE_CALLS")" 'owned-coordinate drift should stop before lifecycle or Stow mutation'
}

test_inactive_receipt_shell_drift_blocks_repeated_removal() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'apply should succeed before inactive-receipt drift' || return 1
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'first removal should retain an inactive receipt' || return 1
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/inactive-drift.json calls_before
	jq '.bar.layout.right += [{"id":"dotfiles.indicators","foreign":true}]' "$config" >"$temporary"
	mv -- "$temporary" "$config"
	calls_before=$(<"$FIXTURE_CALLS")

	run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'inactive-receipt Dotfiles drift should block repeated removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'shell.json retains Dotfiles activation, bar, or restoration state' \
		'inactive-receipt removal should identify the residual shell edge' || return 1
	assert_eq "$calls_before" "$(<"$FIXTURE_CALLS")" \
		'inactive-receipt drift should stop before another Stow operation'
}

test_status_requires_readable_shell_with_inactive_receipt() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'apply should succeed before inactive-receipt status coverage' || return 1
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'remove should retain an inactive receipt' || return 1
	SCREENSAVER_TEST_FAIL_SHELL_INSPECT=true run_package_operation screensaver_effects_status
	assert_eq 0 "$COMMAND_STATUS" 'status should remain available when inactive shell inspection fails' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: recovery-required' \
		'inactive-receipt shell inspection uncertainty must not be classified as inactive'
}

test_competing_clones_require_dedicated_migration_and_remain_only_in_backup() {
	new_fixture
	setup_package_fixture
	seed_competing_clones
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'normal Apply should reject competing idle and Indicators clones' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migrate competing screensaver clones' \
		'normal Apply should direct the dedicated migration route' || return 1
	assert_eq 0 "$(awk '$0 ~ /^stow / { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'competing clones should stop normal Apply before Stow simulation or mutation' || return 1

	SCREENSAVER_TEST_INPUT='y\n' run_package_operation migrate_screensaver_effects --interactive
	if ((COMMAND_STATUS != 0)); then printf '  migration output: %s\n' "$COMMAND_OUTPUT" >&2; fi
	assert_eq 0 "$COMMAND_STATUS" 'one confirmed dedicated migration should activate the package' || return 1
	assert_eq 1 "$(awk 'index($0, "[y/N]") { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'dedicated migration should use exactly one confirmation' || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/legacy.idle && ! -L $FIXTURE_HOME/.config/omarchy/plugins/legacy.idle ]] || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators && ! -L $FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators ]] || return 1
	local receipt backup
	receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json
	backup=$(jq -r .migration.backup "$receipt")
	jq -e '.state == "active" and .migration.performed and (.migration.clone_ids | sort) == ["legacy.idle","legacy.indicators"]' \
		"$receipt" >/dev/null || return 1
	[[ -f $backup/plugins/legacy.idle/unknown-file ]] || {
		printf '  migration backup did not preserve the unknown clone file\n' >&2
		return 1
	}
	if [[ -e $FIXTURE_HOME/.config/omarchy/plugins/.legacy.idle.bak.fixture || -e $FIXTURE_HOME/.config/omarchy/plugins/.legacy.indicators.bak.fixture ]]; then
		printf '  Omarchy command backups should be retained only under XDG state\n' >&2
		return 1
	fi

	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'normal removal should succeed after migration' || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/legacy.idle && ! -L $FIXTURE_HOME/.config/omarchy/plugins/legacy.idle ]] || {
		printf '  normal removal incorrectly restored a migrated competing clone\n' >&2
		return 1
	}
	[[ -f $backup/plugins/legacy.idle/unknown-file ]] || return 1
}

test_retained_inactive_receipt_allows_later_competing_clone_migration() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'apply should succeed before the retained-receipt sequence' || return 1
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'remove should retain a valid inactive receipt' || return 1
	jq -e '.state == "inactive"' "$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json" >/dev/null || return 1
	seed_competing_clones

	run_package_operation migrate_screensaver_effects --yes
	if ((COMMAND_STATUS != 0)); then printf '  retained-receipt migration output: %s\n' "$COMMAND_OUTPUT" >&2; fi
	assert_eq 0 "$COMMAND_STATUS" 'a later competing-clone migration should accept an edge-free inactive receipt' || return 1
	jq -e '.state == "active" and .migration.performed' \
		"$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json" >/dev/null || return 1
	[[ -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators ]] || return 1
}

test_migration_leaves_preexisting_omarchy_backups_untouched() {
	new_fixture
	setup_package_fixture
	seed_competing_clones
	local prior_backup=$FIXTURE_HOME/.config/omarchy/plugins/.legacy.idle.bak.old
	mkdir -p "$prior_backup"
	printf 'unrelated historical backup\n' >"$prior_backup/sentinel"
	local before
	before=$(sha256sum "$prior_backup/sentinel")

	run_package_operation migrate_screensaver_effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'dedicated migration should succeed beside an existing Omarchy backup' || return 1
	assert_eq "$before" "$(sha256sum "$prior_backup/sentinel")" \
		'migration must not move or rewrite a pre-existing hidden Omarchy backup' || return 1
	local receipt backup
	receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json
	backup=$(jq -r .migration.backup "$receipt")
	[[ -d $backup/omarchy-remove-backups/.legacy.idle.bak.fixture ]] || {
		printf '  migration did not retain its newly created Omarchy removal backup under XDG state\n' >&2
		return 1
	}
	[[ ! -e $backup/omarchy-remove-backups/.legacy.idle.bak.old ]] || {
		printf '  migration incorrectly claimed a pre-existing hidden Omarchy backup\n' >&2
		return 1
	}
}

test_failed_migration_exactly_restores_competing_clone_state() {
	new_fixture
	setup_package_fixture
	seed_competing_clones
	local shell_before menu_before clone_before
	shell_before=$(sha256sum "$FIXTURE_HOME/.config/omarchy/shell.json")
	menu_before=$(sha256sum "$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")
	clone_before=$(sha256sum "$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/manifest.json" \
		"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/Service.qml" \
		"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/unknown-file" \
		"$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators/manifest.json" \
		"$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators/Indicators.qml")
	SCREENSAVER_TEST_FAIL_IDLE_ENABLE=true run_package_operation migrate_screensaver_effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'injected activation failure should fail dedicated migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migration rollback restored the exact prior' \
		'failed migration should report exact rollback' || return 1
	assert_eq "$shell_before" "$(sha256sum "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'failed migration should restore exact shell and bar bytes' || return 1
	assert_eq "$menu_before" "$(sha256sum "$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" \
		'failed migration should restore exact menu bytes' || return 1
	assert_eq "$clone_before" "$(sha256sum "$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/manifest.json" \
		"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/Service.qml" \
		"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/unknown-file" \
		"$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators/manifest.json" \
		"$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators/Indicators.qml")" \
		'failed migration should restore every competing clone byte' || return 1
	[[ ! -e $FIXTURE_HOME/.config/dotfiles/screensaver-effects.json && ! -L $FIXTURE_HOME/.config/dotfiles/screensaver-effects.json ]] || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/pending.json ]] || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json ]] || return 1
	[[ -d $FIXTURE_STATE/dotfiles/screensaver-effects/backups ]] || {
		printf '  failed migration did not retain its complete XDG backup\n' >&2
		return 1
	}
}

test_failed_migration_preserves_prelinked_stow_package() {
	new_fixture
	setup_package_fixture
	run_package_operation apply_one_package screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'generic setup should prelink the complete package without lifecycle edges' || return 1
	assert_fixture_package_links_exact || return 1
	seed_competing_clones
	local stow_delete_before
	stow_delete_before=$(awk '$0 ~ /^stow / && $0 ~ /delete=true/ { count++ } END { print count + 0 }' "$FIXTURE_CALLS")

	SCREENSAVER_TEST_FAIL_IDLE_ENABLE=true run_package_operation migrate_screensaver_effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'injected activation failure should fail migration of a prelinked package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migration rollback restored the exact prior' \
		'prelinked-package migration should still restore the competing clone state exactly' || return 1
	assert_fixture_package_links_exact || return 1
	assert_eq "$stow_delete_before" \
		"$(awk '$0 ~ /^stow / && $0 ~ /delete=true/ { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'rollback must not delete Stow links that were exact before migration' || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json ]]
}

test_migration_refuses_partial_prelinked_stow_package_without_mutation() {
	new_fixture
	setup_package_fixture
	local source=$FIXTURE_REPO/config/screensaver-effects/.config/dotfiles/screensaver-effects.json
	local target=$FIXTURE_HOME/.config/dotfiles/screensaver-effects.json
	mkdir -p -- "${target%/*}"
	ln -s -- "$source" "$target"
	seed_competing_clones
	local shell_before clone_before
	shell_before=$(sha256sum "$FIXTURE_HOME/.config/omarchy/shell.json")
	clone_before=$(sha256sum "$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/unknown-file")

	run_package_operation migrate_screensaver_effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'partial prelinked Stow state should block migration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'partial or conflicting Stow deployment' \
		'migration should identify the partial package conflict' || return 1
	assert_eq 0 "$(awk '$0 ~ /^stow / { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'partial package state should stop before Stow simulation or mutation' || return 1
	assert_eq "$source" "$(readlink -- "$target")" 'the pre-existing package leaf should remain exact' || return 1
	assert_eq "$shell_before" "$(sha256sum "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'partial-package rejection should preserve shell state' || return 1
	assert_eq "$clone_before" "$(sha256sum "$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/unknown-file")" \
		'partial-package rejection should preserve competing clones' || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/pending.json ]]
}

test_version_mismatches_warn_without_a_second_screensaver_confirmation() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_OMARCHY_CLI_VERSION=5.0.0-1 \
		SCREENSAVER_TEST_PACMAN_OMARCHY_VERSION=5.0.0-1 \
		SCREENSAVER_TEST_PACMAN_TTFX_VERSION=0.4.0-1 \
		SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'screensaver-only Apply should continue after visible version warnings' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: screensaver-effects was verified with Omarchy 4.0.1-1; detected 5.0.0-1' \
		'Apply should show the exact Omarchy mismatch warning' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: screensaver-effects mappings were verified with ttfx 0.3.2-1; detected 0.4.0-1' \
		'Apply should show the exact ttfx mismatch warning' || return 1
	assert_eq 1 "$(awk 'index($0, "[y/N]") { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'screensaver-only Apply should use only its complete-plan confirmation'
}

test_pending_state_blocks_mutation_and_reports_recovery_required() {
	new_fixture
	setup_package_fixture
	local state=$FIXTURE_STATE/dotfiles/screensaver-effects
	mkdir -p "$state"
	cat >"$state/pending.json" <<'JSON'
{"schema_version":1,"package":"screensaver-effects","operation":"apply","attempt_id":"fixture-attempt","started_at":"2026-08-29T00:00:00Z","prior_receipt_sha256":null}
JSON
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'pending lifecycle evidence should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'has a pending apply operation' 'blocked Apply should identify pending evidence' || return 1
	assert_eq 0 "$(awk '$0 ~ /^stow / { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'pending evidence should stop before Stow simulation or mutation' || return 1
	run_package_operation screensaver_effects_status
	assert_eq 0 "$COMMAND_STATUS" 'status should remain available with pending evidence' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: recovery-required' \
		'status should classify pending evidence as recovery-required'
}

test_identical_preexisting_menu_entry_remains_unowned_after_removal() {
	new_fixture
	setup_package_fixture
	cat >"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" <<'JSONC'
{
  // user-owned identical override
  "system.screensaver": {"label":"Screensaver","action":"omarchy-shell idle screensaver","icon":"\udb84\udd04"},
  "custom.action": {"label":"Keep me","action":"true"},
}
JSONC
	local menu_before
	menu_before=$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should accept an identical preexisting menu entry' || return 1
	assert_eq false "$(jq -r .owned_edges.menu_entry "$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json")" \
		'identical preexisting menu entry should remain unowned' || return 1
	assert_eq "$menu_before" "$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" \
		'Apply should not rewrite an identical preexisting menu entry' || return 1
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'removal should succeed with an unowned identical menu entry' || return 1
	assert_eq "$menu_before" "$(<"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" \
		'removal should retain exact unowned menu bytes'
}

test_missing_unowned_menu_entry_is_a_conflict() {
	new_fixture
	setup_package_fixture
	cat >"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" <<'JSONC'
{
  "system.screensaver": {"label":"Screensaver","action":"omarchy-shell idle screensaver","icon":"\udb84\udd04"},
}
JSONC
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should initially accept the unowned identical menu entry' || return 1
	printf '{}\n' >"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
	local before calls_before
	before=$(sha256sum "$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")
	calls_before=$(<"$FIXTURE_CALLS")

	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'Apply should not adopt a disappeared unowned menu entry' || return 1
	assert_contains "$COMMAND_OUTPUT" 'the unowned system.screensaver menu entry changed' \
		'unowned menu disappearance should retain the foreign ownership boundary' || return 1
	assert_eq "$before" "$(sha256sum "$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" \
		'unowned menu conflict should preserve exact bytes' || return 1
	assert_eq "$calls_before" "$(<"$FIXTURE_CALLS")" 'unowned menu conflict should stop before mutation'
}

test_different_preexisting_menu_entry_stops_before_stow() {
	new_fixture
	setup_package_fixture
	cat >"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" <<'JSONC'
{
  "system.screensaver": {"icon":"foreign","label":"Different","action":"custom-screensaver"},
  "custom.action": {"label":"Keep me","action":"true"},
}
JSONC
	local before
	before=$(sha256sum "$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'a different pre-existing menu override should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'a different system.screensaver menu entry already exists' \
		'menu conflict should identify the shared entry' || return 1
	assert_eq "$before" "$(sha256sum "$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" \
		'menu conflict should preserve exact shared-file bytes' || return 1
	assert_eq 0 "$(awk '$0 ~ /^stow / { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'menu conflict should stop before Stow simulation or mutation'
}

test_dangling_menu_symlink_stops_without_replacement() {
	new_fixture
	setup_package_fixture
	local menu=$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc
	rm -- "$menu"
	ln -s -- "$FIXTURE_ROOT/missing-foreign-menu" "$menu"
	local target
	target=$(readlink -- "$menu")

	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'a dangling foreign menu symlink should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'could not validate the Omarchy menu extension JSONC' \
		'dangling menu rejection should remain in preflight' || return 1
	[[ -L $menu ]] || {
		printf '  dangling foreign menu symlink was replaced\n' >&2
		return 1
	}
	assert_eq "$target" "$(readlink -- "$menu")" 'dangling foreign menu symlink target should remain exact' || return 1
	[[ ! -e $FIXTURE_ROOT/missing-foreign-menu ]] || return 1
	assert_eq 0 "$(awk '$0 ~ /^stow / { count++ } END { print count + 0 }' "$FIXTURE_CALLS")" \
		'dangling menu conflict should stop before Stow simulation or mutation'
}

test_absent_indicators_preserve_enabled_first_party_infrastructure() {
	new_fixture
	setup_package_fixture
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/prior-shell.json
	jq '.bar.layout.center = [] | .disabledPlugins = ["omarchy.idle"]' "$config" >"$temporary"
	mv -- "$temporary" "$config"
	local before
	before=$(<"$config")

	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should support enabled first-party Indicators absent from the bar' || return 1
	assert_eq 0 "$(jq '.bar.layout.left + .bar.layout.center + .bar.layout.right | length' "$config")" \
		'Apply must not add an Indicators widget that was absent' || return 1
	assert_eq true "$(jq -r '.prior.plugin_states["omarchy.indicators"]' "$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json")" \
		'receipt should retain enabled first-party Indicators independently from bar presence' || return 1
	assert_eq false "$(jq -r '.owned_edges.indicators_activation' "$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json")" \
		'receipt should record that no Indicators activation edge was owned' || return 1
	run_package_operation screensaver_effects_status
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: active' 'status should verify absent but enabled first-party Indicators' || return 1
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'removal should preserve enabled first-party Indicators without adding a widget' || return 1
	assert_eq "$before" "$(<"$config")" \
		'removal should restore exact absent-Indicators shell bytes'
}

test_absent_indicators_preserve_disabled_first_party_infrastructure() {
	new_fixture
	setup_package_fixture
	local config=$FIXTURE_HOME/.config/omarchy/shell.json temporary=$FIXTURE_ROOT/prior-shell.json
	jq '.bar.layout.center = [] | .disabledPlugins = ["omarchy.idle","omarchy.indicators"]' "$config" >"$temporary"
	mv -- "$temporary" "$config"
	local before
	before=$(<"$config")

	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should support explicitly disabled first-party Indicators absent from the bar' || return 1
	assert_eq false "$(jq -r '.prior.plugin_states["omarchy.indicators"]' "$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json")" \
		'receipt should retain disabled first-party Indicators independently from bar presence' || return 1
	run_package_operation screensaver_effects_status
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: active' 'status should verify absent and disabled first-party Indicators' || return 1
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'removal should preserve disabled first-party Indicators without adding a widget' || return 1
	assert_eq "$before" "$(<"$config")" \
		'removal should restore exact explicitly disabled Indicators shell bytes'
}

test_stow_removal_failure_restores_active_lifecycle() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should succeed before injected Stow removal failure' || return 1
	SCREENSAVER_TEST_STOW_DELETE_FAILURE=true run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'injected Stow removal failure should fail Remove' || return 1
	assert_contains "$COMMAND_OUTPUT" 'active state restored after Stow removal failure' \
		'Remove failure should report successful lifecycle restoration' || return 1
	jq -e '.state == "active"' "$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json" >/dev/null || return 1
	[[ -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators ]] || {
		printf '  Stow removal failure did not restore live plugin links\n' >&2
		return 1
	}
	assert_eq dotfiles.indicators "$(jq -r '.bar.layout.center[0].id' "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'Stow removal failure should restore the active Indicators identity' || return 1
	assert_eq true "$(jq -r '.stayAwake.enabled' "$FIXTURE_HOME/.config/omarchy/shell.json")" \
		'Stow removal recovery must not change Stay Awake state' || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json ]] || return 1
}

test_partial_stow_removal_failure_requires_recovery() {
	new_fixture
	setup_package_fixture
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should succeed before partial Stow removal failure' || return 1
	SCREENSAVER_TEST_STOW_DELETE_PARTIAL_FAILURE=true run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'partial Stow deletion followed by failure should fail Remove' || return 1
	assert_contains "$COMMAND_OUTPUT" 'one or more deployed package leaves' \
		'partial deletion should identify incomplete deployed Stow state' || return 1
	if [[ $COMMAND_OUTPUT == *'active state restored after Stow removal failure'* ]]; then
		printf '  partial Stow deletion was incorrectly reported as an active-state restoration\n' >&2
		return 1
	fi
	jq -e '.state == "recovery-required" and .operation == "remove"' \
		"$FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json" >/dev/null || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && ! -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle ]] || return 1
	local package_root=$FIXTURE_REPO/config/screensaver-effects source relative target missing=false
	while IFS= read -r -d '' source; do
		relative=${source#"$package_root/"}
		target=$FIXTURE_HOME/$relative
		if [[ ! -L $target ]]; then missing=true; break; fi
	done < <(find "$package_root" -type f -print0)
	[[ $missing == true ]]
}

run_test() {
	local function=$1 description=$2
	TESTS_RUN=$((TESTS_RUN + 1))
	if "$function"; then
		pass "$description"
	else
		fail "$description"
	fi
}

set -e
run_test test_status_reports_exact_compatibility_and_inactive_lifecycle 'status reports exact compatibility and inactive lifecycle'
run_test test_status_requires_readable_shell_without_receipt 'status requires readable shell state without a receipt'
run_test test_unreceipted_shell_activation_is_conflicting 'unreceipted shell activation is conflicting'
run_test test_unreceipted_shell_activation_blocks_removal_before_stow 'unreceipted shell activation blocks removal before Stow'
run_test test_first_apply_and_exact_reapply_publish_one_rescan_and_stable_receipt 'first apply and exact reapply publish one rescan and a stable receipt'
run_test test_changed_validated_source_gets_one_rescan 'changed validated source gets one rescan'
run_test test_missing_owned_link_and_activation_drift_are_repaired 'missing owned link and activation drift are repaired'
run_test test_unrelated_indicators_bar_drift_stops_before_mutation 'unrelated Indicators bar drift stops before mutation'
run_test test_activation_failure_rolls_back_lifecycle_but_retains_stow_links 'activation failure rolls back lifecycle but retains Stow links'
run_test test_unexpected_idle_command_change_fails_closed_and_restores_bytes 'unexpected idle command change fails closed and restores bytes'
run_test test_activation_rollback_refuses_changed_owned_coordinate 'activation rollback refuses a changed owned coordinate'
run_test test_removal_restores_prior_state_and_retains_inactive_receipt 'removal restores prior state and retains an inactive receipt'
run_test test_removal_preserves_unrelated_active_shell_byte_edit 'removal preserves an unrelated active shell byte edit'
run_test test_changed_owned_indicators_coordinate_blocks_removal 'changed owned Indicators coordinate blocks removal'
run_test test_inactive_receipt_shell_drift_blocks_repeated_removal 'inactive-receipt shell drift blocks repeated removal'
run_test test_status_requires_readable_shell_with_inactive_receipt 'status requires readable shell state with an inactive receipt'
run_test test_competing_clones_require_dedicated_migration_and_remain_only_in_backup 'competing clones require dedicated migration and remain only in backup'
run_test test_retained_inactive_receipt_allows_later_competing_clone_migration 'retained inactive receipt allows later competing-clone migration'
run_test test_migration_leaves_preexisting_omarchy_backups_untouched 'migration leaves pre-existing Omarchy backups untouched'
run_test test_failed_migration_exactly_restores_competing_clone_state 'failed migration exactly restores competing clone state'
run_test test_failed_migration_preserves_prelinked_stow_package 'failed migration preserves a prelinked Stow package'
run_test test_migration_refuses_partial_prelinked_stow_package_without_mutation 'migration refuses partial prelinked Stow state without mutation'
run_test test_version_mismatches_warn_without_a_second_screensaver_confirmation 'version mismatches warn without a second screensaver confirmation'
run_test test_pending_state_blocks_mutation_and_reports_recovery_required 'pending state blocks mutation and reports recovery-required'
run_test test_identical_preexisting_menu_entry_remains_unowned_after_removal 'identical preexisting menu entry remains unowned after removal'
run_test test_missing_unowned_menu_entry_is_a_conflict 'missing unowned menu entry is a conflict'
run_test test_different_preexisting_menu_entry_stops_before_stow 'different pre-existing menu entry stops before Stow'
run_test test_dangling_menu_symlink_stops_without_replacement 'dangling menu symlink stops without replacement'
run_test test_absent_indicators_preserve_enabled_first_party_infrastructure 'absent Indicators preserve enabled first-party infrastructure'
run_test test_absent_indicators_preserve_disabled_first_party_infrastructure 'absent Indicators preserve disabled first-party infrastructure'
run_test test_stow_removal_failure_restores_active_lifecycle 'Stow removal failure restores active lifecycle'
run_test test_partial_stow_removal_failure_requires_recovery 'partial Stow removal failure requires recovery'

printf '1..%d\n' "$TESTS_RUN"
((TESTS_FAILED == 0))
