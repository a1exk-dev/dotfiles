#!/usr/bin/env bash

set -u

readonly SOURCE_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

TESTS_RUN=0
TESTS_FAILED=0
FIXTURE_ROOT=''
FIXTURE_REPO=''
FIXTURE_HOME=''
FIXTURE_STATE=''
FIXTURE_BIN=''
FIXTURE_CALLS=''
FIXTURE_TEMPLATE_ROOT=''
FIXTURE_ACTIVE_TEMPLATE_ROOT=''
FIXTURE_ACTIVE_SOURCE_ROOT=''

cleanup() {
	if [[ -n $FIXTURE_ROOT ]]; then
		rm -rf -- "$FIXTURE_ROOT"
		FIXTURE_ROOT=''
	fi
}

cleanup_all() {
	cleanup
	[[ -z $FIXTURE_TEMPLATE_ROOT ]] || rm -rf -- "$FIXTURE_TEMPLATE_ROOT"
	[[ -z $FIXTURE_ACTIVE_TEMPLATE_ROOT ]] || rm -rf -- "$FIXTURE_ACTIVE_TEMPLATE_ROOT"
}

trap cleanup_all EXIT

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

call_count() {
	local needle=$1
	awk -v needle="$needle" '$0 == needle {count++} END {print count + 0}' "$FIXTURE_CALLS"
}

omarchy_mutation_count() {
	awk '$0 ~ /^(restart shell|rescan|reload|plugin (enable|disable|remove) )/ {count++} END {print count + 0}' "$FIXTURE_CALLS"
}

make_fake_script() {
	local name=$1
	{
		printf '#!/usr/bin/env bash\nset -euo pipefail\n'
		cat
	} >"$FIXTURE_BIN/$name"
	chmod +x "$FIXTURE_BIN/$name"
}

replace_fixture_identity() {
	local file=$1 identity=$2
	node - "$file" "$identity" <<'NODE'
const fs = require("fs");

const file = process.argv[2];
const identity = process.argv[3];
const prefix = '  readonly property string dotfilesSourceIdentity: "';
const input = fs.readFileSync(file, "utf8");
const pattern = new RegExp(`^${prefix}[0-9a-f]{64}"`, "m");
if (!/^[0-9a-f]{64}$/.test(identity) || !pattern.test(input)) process.exit(1);
fs.writeFileSync(file, input.replace(pattern, `${prefix}${identity}"`));
NODE
}

refresh_fixture_source_identity() {
	local service=$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml
	local identity
	identity=$(DOTFILES_REPOSITORY_ROOT="$FIXTURE_REPO" HOME="$FIXTURE_HOME" XDG_STATE_HOME="$FIXTURE_STATE" bash -c '
source "$1/lib/dotfiles/core.sh"
source "$1/lib/dotfiles/screensaver-effects.sh"
screensaver_effects_set_paths
screensaver_effects_source_identity
' _ "$FIXTURE_REPO") || return 1
	replace_fixture_identity "$service" "$identity"
}

setup_package_fixture() {
	FIXTURE_REPO=$FIXTURE_ROOT/repo
	if [[ -n $FIXTURE_TEMPLATE_ROOT ]]; then
		cp -a -- "$FIXTURE_TEMPLATE_ROOT/repo" "$FIXTURE_REPO" || return 1
		cp -a -- "$FIXTURE_TEMPLATE_ROOT/bin/." "$FIXTURE_BIN/" || return 1
		mkdir -p "$FIXTURE_HOME/.config/omarchy/extensions"
		cat >"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" <<'JSONC'
{
  // unrelated bytes survive lifecycle changes
  "custom.action": {"label":"Keep me","action":"true"},
}
JSONC
		return 0
	fi
	mkdir -p \
		"$FIXTURE_REPO/bin" "$FIXTURE_REPO/lib/dotfiles" \
		"$FIXTURE_REPO/config/screensaver-effects/.config/dotfiles" \
		"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle" \
		"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators" \
		"$FIXTURE_REPO/config/screensaver-effects/.local/libexec/dotfiles"
	cp "$SOURCE_REPO/lib/dotfiles/core.sh" "$SOURCE_REPO/lib/dotfiles/packages.sh" \
		"$SOURCE_REPO/lib/dotfiles/screensaver-effects.sh" "$FIXTURE_REPO/lib/dotfiles/"
	cp "$SOURCE_REPO/lib/dotfiles/screensaver-effects-jsonc.mjs" "$FIXTURE_REPO/lib/dotfiles/"
	cat >"$FIXTURE_REPO/packages.json" <<'JSON'
{"packages":[{"name":"screensaver-effects","path":"config/screensaver-effects","description":"Selective screensaver effects","dependencies":[],"arch_packages":[],"prerequisites":["node","omarchy-shell"],"validators":[],"documentation":null,"cleanup":["Lifecycle state is retained"]}]}
JSON
	cat >"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"dotfiles.idle","name":"Dotfiles Idle","version":"1","kinds":["service"],"entryPoints":{"service":"Service.qml"},"omarchy":{"clonedFrom":"omarchy.idle"}}
JSON
	printf 'Item { property string marker: "idle-v1" }\n  readonly property string dotfilesSourceIdentity: "%064d"\n' 0 \
		>"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml"
	cat >"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"dotfiles.indicators","name":"Dotfiles Indicators","version":"1","kinds":["bar-widget"],"entryPoints":{"barWidget":"Indicators.qml"},"omarchy":{"clonedFrom":"omarchy.indicators"}}
JSON
	printf 'Item { property string marker: "indicators-v1" }\n' \
		>"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/Indicators.qml"
	printf 'var fixtureIdleModel = {}\n' \
		>"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/IdleModel.js"
	printf '["matrix"]\n' >"$FIXTURE_REPO/config/screensaver-effects/.config/dotfiles/screensaver-effects.json"
	printf '#!/usr/bin/env bash\nprintf "selector fixture\\n"\n' \
		>"$FIXTURE_REPO/config/screensaver-effects/.local/libexec/dotfiles/screensaver-effects-selector"
	chmod +x "$FIXTURE_REPO/config/screensaver-effects/.local/libexec/dotfiles/screensaver-effects-selector"
	refresh_fixture_source_identity || return 1
	mkdir -p "$FIXTURE_HOME/.config/omarchy/extensions"
	cat >"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" <<'JSONC'
{
  // unrelated bytes survive lifecycle changes
  "custom.action": {"label":"Keep me","action":"true"},
}
JSONC
	make_fake_script stow <<'STOW'
simulate=false
delete=false
directory=""
target=""
package=""
deleted=0
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
printf 'stow simulate=%s delete=%s package=%s\n' "$simulate" "$delete" "$package" >>"$SCREENSAVER_TEST_CALLS"
[[ $simulate == false ]] || exit 0
if [[ $delete == true && ${SCREENSAVER_TEST_STOW_DELETE_FAILURE:-false} == true ]]; then exit 79; fi
root=$directory/$package
while IFS= read -r -d '' source; do
  relative=${source#"$root/"}
  destination=$target/$relative
  if [[ $delete == true ]]; then
    if [[ -L $destination && $(readlink -f -- "$destination") == $(readlink -f -- "$source") ]]; then
      rm -f -- "$destination"
      deleted=$((deleted + 1))
    fi
  elif [[ ! -e $destination && ! -L $destination ]]; then
    mkdir -p -- "${destination%/*}"
    ln -s -- "$source" "$destination"
  elif [[ ! -L $destination || $(readlink -f -- "$destination") != $(readlink -f -- "$source") ]]; then
    exit 1
  fi
  if [[ $delete == true && ${SCREENSAVER_TEST_STOW_DELETE_PARTIAL_FAILURE:-false} == true && $deleted == 1 ]]; then exit 79; fi
done < <(find "$root" -type f -print0)
STOW
	make_fake_script omarchy <<'OMARCHY'
config="$HOME/.config/omarchy/shell.json"
instance_file="$SCREENSAVER_TEST_CALLS.idle-instance"
generation_file="$SCREENSAVER_TEST_CALLS.idle-generation"
identity_file="$SCREENSAVER_TEST_CALLS.idle-source-identity"
complete_async_plugin_removals() {
  local id pending polls
  for id in dotfiles.idle dotfiles.indicators; do
    pending="$SCREENSAVER_TEST_CALLS.plugin-remove-$id"
    [[ -f $pending ]] || continue
    polls=0
    [[ -f $pending.polls ]] && polls=$(<"$pending.polls")
    polls=$((polls + 1))
    printf '%s\n' "$polls" >"$pending.polls"
    if ((polls >= 2)); then
      rm -f -- "$HOME/.config/omarchy/plugins/$id" "$pending" "$pending.polls"
      : >"$SCREENSAVER_TEST_CALLS.runtime-removal-pending"
      printf 'plugins converged\n' >>"$SCREENSAVER_TEST_CALLS"
    fi
  done
}
runtime_identity() {
  local service="$HOME/.config/omarchy/plugins/dotfiles.idle/Service.qml" line prefix='  readonly property string dotfilesSourceIdentity: "'
  [[ -f $service ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == "$prefix"* ]]; then
      line=${line#"$prefix"}; printf '%s\n' "${line%\"}"; return 0
    fi
  done <"$service"
  return 1
}
new_runtime() {
  local generation=0 started_at prefix
  [[ -f $generation_file ]] && generation=$(<"$generation_file")
  generation=$((generation + 1))
  printf '%s\n' "$generation" >"$generation_file"
  started_at=$(date +%s%3N)
  prefix=$(node -e 'process.stdout.write(Number(process.argv[1]).toString(36))' "$started_at")
  printf '%s-fixture-%s\n' "$prefix" "$generation" >"$instance_file"
  runtime_identity >"$identity_file" || : >"$identity_file"
}
plugin_list() {
  complete_async_plugin_removals
  local idle_installed=false indicators_installed=false legacy_idle_installed=false legacy_indicators_installed=false
  [[ -f $HOME/.config/omarchy/plugins/dotfiles.idle/manifest.json ]] && idle_installed=true
  [[ -f $HOME/.config/omarchy/plugins/dotfiles.indicators/manifest.json ]] && indicators_installed=true
  [[ -f $HOME/.config/omarchy/plugins/legacy.idle/manifest.json ]] && legacy_idle_installed=true
  [[ -f $HOME/.config/omarchy/plugins/legacy.indicators/manifest.json ]] && legacy_indicators_installed=true
  jq -cn --argjson config "$(jq -c . "$config")" --argjson idleInstalled "$idle_installed" --argjson indicatorsInstalled "$indicators_installed" --argjson legacyIdleInstalled "$legacy_idle_installed" --argjson legacyIndicatorsInstalled "$legacy_indicators_installed" '
    def entry_id: if type == "object" then (.id // "") else tostring end;
    ($config.disabledPlugins // []) as $disabled | ([$config.bar.layout[][] | entry_id]) as $bar | ($config.plugins // [] | map(.id)) as $services |
    [{id:"omarchy.idle",enabled:($disabled | index("omarchy.idle") | not),firstParty:true,clonedFrom:""},{id:"omarchy.indicators",enabled:($bar | index("omarchy.indicators") != null),firstParty:true,clonedFrom:""}]
    + (if $idleInstalled then [{id:"dotfiles.idle",enabled:($services | index("dotfiles.idle") != null),firstParty:false,clonedFrom:"omarchy.idle"}] else [] end)
    + (if $indicatorsInstalled then [{id:"dotfiles.indicators",enabled:($bar | index("dotfiles.indicators") != null),firstParty:false,clonedFrom:"omarchy.indicators"}] else [] end)
    + (if $legacyIdleInstalled then [{id:"legacy.idle",enabled:($services | index("legacy.idle") != null),firstParty:false,clonedFrom:"omarchy.idle"}] else [] end)
    + (if $legacyIndicatorsInstalled then [{id:"legacy.indicators",enabled:($bar | index("legacy.indicators") != null),firstParty:false,clonedFrom:"omarchy.indicators"}] else [] end)
  '
}
case "$*" in
  version) printf '4.0.1-1\n' ;;
  'pkg present '*) exit 0 ;;
  'pkg add '*) exit 0 ;;
  'plugin list --json') plugin_list ;;
  'restart shell')
    [[ ${SCREENSAVER_TEST_FAIL_SHELL_RESTART:-false} == false ]] || exit 75
    new_runtime
    printf 'restart shell\n' >>"$SCREENSAVER_TEST_CALLS"
    ;;
  'plugin enable dotfiles.idle')
    [[ ${SCREENSAVER_TEST_FAIL_IDLE_ENABLE:-false} == false ]] || exit 75
    temporary=$config.tmp
    jq '(.disabledPlugins // []) as $disabled | if (.disabledPlugins | type) == "array" then .disabledPlugins = (.disabledPlugins | map(select(. != "dotfiles.idle"))) else . end | if ($disabled | index("omarchy.idle")) == null then .disabledPlugins = ((.disabledPlugins // []) + ["omarchy.idle"]) | .cloneSourceRestores = (((.cloneSourceRestores // []) | map(select(. != "dotfiles.idle"))) + ["dotfiles.idle"]) else . end | .plugins = ((.plugins // []) + [{id:"dotfiles.idle"}] | unique_by(.id)) | .version = 1 | to_entries | reverse | from_entries' "$config" >"$temporary"
    mv -- "$temporary" "$config"
    printf 'plugin enable dotfiles.idle\n' >>"$SCREENSAVER_TEST_CALLS"
    ;;
  'plugin disable dotfiles.idle')
    temporary=$config.tmp
    jq '.plugins = ((.plugins // []) | map(select(.id != "dotfiles.idle"))) | if ((.cloneSourceRestores // []) | index("dotfiles.idle")) != null then .disabledPlugins = ((.disabledPlugins // []) | map(select(. != "omarchy.idle"))) | .cloneSourceRestores = ((.cloneSourceRestores // []) | map(select(. != "dotfiles.idle"))) | if (.cloneSourceRestores | length) == 0 then del(.cloneSourceRestores) else . end else . end | .version = 1 | to_entries | reverse | from_entries' "$config" >"$temporary"
    mv -- "$temporary" "$config"
    printf 'plugin disable dotfiles.idle\n' >>"$SCREENSAVER_TEST_CALLS"
    ;;
  'plugin disable legacy.idle')
    temporary=$config.tmp
    jq '.plugins = ((.plugins // []) | map(select(.id != "legacy.idle"))) | .disabledPlugins = ((.disabledPlugins // []) | map(select(. != "omarchy.idle"))) | .cloneSourceRestores = ((.cloneSourceRestores // []) | map(select(. != "legacy.idle")))' "$config" >"$temporary"
    mv -- "$temporary" "$config"
    printf 'plugin disable legacy.idle\n' >>"$SCREENSAVER_TEST_CALLS"
    ;;
  'plugin disable legacy.indicators')
    temporary=$config.tmp
    jq 'walk(if type == "object" and .id == "legacy.indicators" then .id = "omarchy.indicators" else . end)' "$config" >"$temporary"
    mv -- "$temporary" "$config"
    printf 'plugin disable legacy.indicators\n' >>"$SCREENSAVER_TEST_CALLS"
    ;;
  'plugin remove dotfiles.idle --yes'|'plugin remove dotfiles.indicators --yes')
    id=${3-}
    : >"$SCREENSAVER_TEST_CALLS.plugin-remove-$id"
    printf 'plugin remove %s\n' "$id" >>"$SCREENSAVER_TEST_CALLS"
    ;;
  'plugin remove legacy.idle --yes'|'plugin remove legacy.indicators --yes')
    id=${3-}
    mv -- "$HOME/.config/omarchy/plugins/$id" "$HOME/.config/omarchy/plugins/.$id.bak.fixture"
    printf 'plugin remove %s\n' "$id" >>"$SCREENSAVER_TEST_CALLS"
    ;;
  *) exit 64 ;;
esac
OMARCHY
	make_fake_script omarchy-shell <<'OMARCHY_SHELL'
config="$HOME/.config/omarchy/shell.json"
instance_file="$SCREENSAVER_TEST_CALLS.idle-instance"
generation_file="$SCREENSAVER_TEST_CALLS.idle-generation"
identity_file="$SCREENSAVER_TEST_CALLS.idle-source-identity"
runtime_identity() {
  local service="$HOME/.config/omarchy/plugins/dotfiles.idle/Service.qml" line prefix='  readonly property string dotfilesSourceIdentity: "'
  [[ -f $service ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == "$prefix"* ]]; then line=${line#"$prefix"}; printf '%s\n' "${line%\"}"; return 0; fi
  done <"$service"
  return 1
}
new_runtime() {
  local generation=0 started_at prefix
  [[ -f $generation_file ]] && generation=$(<"$generation_file")
  generation=$((generation + 1)); printf '%s\n' "$generation" >"$generation_file"
  started_at=$(date +%s%3N); prefix=$(node -e 'process.stdout.write(Number(process.argv[1]).toString(36))' "$started_at")
  printf '%s-fixture-%s\n' "$prefix" "$generation" >"$instance_file"
  runtime_identity >"$identity_file" || : >"$identity_file"
}
case "$*" in
  'shell listShellConfig')
    [[ ${SCREENSAVER_TEST_FAIL_SHELL_INSPECT:-false} == false ]] || exit 75
    jq -c . "$config"
    ;;
  'idle status')
    builtin_enabled=false
    jq -e '((.disabledPlugins // []) | index("omarchy.idle")) == null' "$config" >/dev/null && builtin_enabled=true
    if jq -e '(.plugins // []) | any(.id == "dotfiles.idle")' "$config" >/dev/null; then
      instance=''; [[ -f $instance_file ]] && instance=$(<"$instance_file")
      identity=''; [[ -f $identity_file ]] && identity=$(<"$identity_file")
      if [[ -n $instance && -n $identity ]]; then
        jq -cn --arg instance "$instance" --arg identity "$identity" --argjson inIdleCycle "${SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE:-false}" '{dotfilesInstanceId:$instance,dotfilesSourceIdentity:$identity,inIdleCycle:$inIdleCycle}'
      else
        jq -cn --argjson inIdleCycle "${SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE:-false}" '{inIdleCycle:$inIdleCycle}'
      fi
    elif [[ $builtin_enabled == true && -e $SCREENSAVER_TEST_CALLS.runtime-removal-pending ]]; then
      polls=0
      [[ -f $SCREENSAVER_TEST_CALLS.runtime-removal-polls ]] && polls=$(<"$SCREENSAVER_TEST_CALLS.runtime-removal-polls")
      polls=$((polls + 1))
      printf '%s\n' "$polls" >"$SCREENSAVER_TEST_CALLS.runtime-removal-polls"
      if ((polls >= 2)); then
        rm -f -- "$SCREENSAVER_TEST_CALLS.runtime-removal-pending"
        printf '{}\n'
      else
        printf 'old runtime observed after removal\n' >>"$SCREENSAVER_TEST_CALLS"
        jq -cn --arg instance "$(<"$instance_file")" --arg identity "$(<"$identity_file")" '{dotfilesInstanceId:$instance,dotfilesSourceIdentity:$identity,inIdleCycle:false}'
      fi
    elif [[ $builtin_enabled == true ]]; then
      jq -cn --argjson inIdleCycle "${SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE:-false}" '{inIdleCycle:$inIdleCycle}'
    else
      exit 127
    fi
    ;;
  'shell rescanPlugins')
    new_runtime
    printf 'rescan\n' >>"$SCREENSAVER_TEST_CALLS"
    ;;
  'shell reloadConfig')
    printf 'reload\n' >>"$SCREENSAVER_TEST_CALLS"
    ;;
  *) exit 64 ;;
esac
OMARCHY_SHELL
	make_fake_script pacman <<'PACMAN'
case "$*" in
  '-Q omarchy') printf 'omarchy 4.0.1-1\n' ;;
  '-Q ttfx') printf 'ttfx 0.3.2-1\n' ;;
  *) exit 1 ;;
esac
PACMAN
	make_fake_script sleep <<'SLEEP'
if [[ ${1-} == 0.05 ]]; then exit 0; fi
exec /usr/bin/sleep "$@"
SLEEP
	make_fake_script refresh-source-identity <<'IDENTITY'
repo=$1
source "$repo/lib/dotfiles/core.sh"
source "$repo/lib/dotfiles/screensaver-effects.sh"
screensaver_effects_set_paths
service=$repo/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml
identity=$(screensaver_effects_source_identity)
node - "$service" "$identity" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const identity = process.argv[3];
const prefix = '  readonly property string dotfilesSourceIdentity: "';
const input = fs.readFileSync(file, "utf8");
const pattern = new RegExp(`^${prefix}[0-9a-f]{64}"`, "m");
if (!pattern.test(input)) process.exit(1);
fs.writeFileSync(file, input.replace(pattern, `${prefix}${identity}"`));
NODE
IDENTITY
	FIXTURE_TEMPLATE_ROOT=$(mktemp -d)
	mkdir -p "$FIXTURE_TEMPLATE_ROOT/bin"
	cp -a -- "$FIXTURE_REPO" "$FIXTURE_TEMPLATE_ROOT/repo"
	cp -a -- "$FIXTURE_BIN/." "$FIXTURE_TEMPLATE_ROOT/bin/"
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
{"version":1,"idle":{"screensaver":150,"lock":300},"bar":{"layout":{"left":[],"center":[{"id":"omarchy.indicators","items":["idle"],"custom":true}],"right":[]}},"plugins":[],"stayAwake":{"enabled":true}}
JSON
	setup_package_fixture
}

run_package_code() {
	local code=$1 output=$FIXTURE_ROOT/package-output
	set +e
	printf '%b' "${SCREENSAVER_TEST_INPUT-}" | \
		HOME=$FIXTURE_HOME XDG_STATE_HOME=$FIXTURE_STATE PATH="$FIXTURE_BIN:$PATH" DOTFILES_UI=bash \
		SCREENSAVER_TEST_ROOT=$FIXTURE_ROOT SCREENSAVER_TEST_CALLS=$FIXTURE_CALLS \
		SCREENSAVER_TEST_INPUT=${SCREENSAVER_TEST_INPUT-} \
		SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE=${SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE-false} \
		SCREENSAVER_TEST_FAIL_IDLE_ENABLE=${SCREENSAVER_TEST_FAIL_IDLE_ENABLE-false} \
		SCREENSAVER_TEST_FAIL_SHELL_RESTART=${SCREENSAVER_TEST_FAIL_SHELL_RESTART-false} \
		SCREENSAVER_TEST_FAIL_SHELL_INSPECT=${SCREENSAVER_TEST_FAIL_SHELL_INSPECT-false} \
		SCREENSAVER_TEST_STOW_DELETE_FAILURE=${SCREENSAVER_TEST_STOW_DELETE_FAILURE-false} \
		SCREENSAVER_TEST_STOW_DELETE_PARTIAL_FAILURE=${SCREENSAVER_TEST_STOW_DELETE_PARTIAL_FAILURE-false} \
		bash -c 'set -euo pipefail
source "$1/lib/dotfiles/core.sh"
source "$1/lib/dotfiles/screensaver-effects.sh"
source "$1/lib/dotfiles/packages.sh"
sequence_run() {
  local name=$1
  shift
  local output="$SCREENSAVER_TEST_ROOT/sequence-$name.output" status
  set +e
  "$@" < <(printf "%b" "${SCREENSAVER_TEST_INPUT-}") >"$output" 2>&1
  status=$?
  printf "%s" "$status" >"$SCREENSAVER_TEST_ROOT/sequence-$name.status"
  set -e
  cat "$output"
}
eval "$2"' _ "$FIXTURE_REPO" "$code" >"$output" 2>&1
	COMMAND_STATUS=$?
	set -e
	COMMAND_OUTPUT=$(<"$output")
}

run_package_operation() {
	local function=$1
	shift
	local code
	printf -v code '%q ' "$function" "$@"
	run_package_code "$code"
}

run_package_sequence() {
	run_package_code "$1"
}

sequence_status() { printf '%s' "$(<"$FIXTURE_ROOT/sequence-$1.status")"; }
sequence_output() { printf '%s' "$(<"$FIXTURE_ROOT/sequence-$1.output")"; }

setup_active_package_fixture() {
	if [[ -n $FIXTURE_ACTIVE_TEMPLATE_ROOT && ${1-} != fresh ]]; then
		cp -a -- "$FIXTURE_ACTIVE_TEMPLATE_ROOT/home/." "$FIXTURE_HOME/" || return 1
		cp -a -- "$FIXTURE_ACTIVE_TEMPLATE_ROOT/state/." "$FIXTURE_STATE/" || return 1
		local link target replacement receipt identity
		while IFS= read -r -d '' link; do
			target=$(readlink -- "$link") || return 1
			if [[ $target == "$FIXTURE_ACTIVE_SOURCE_ROOT/home/"* ]]; then
				replacement=$FIXTURE_HOME/${target#"$FIXTURE_ACTIVE_SOURCE_ROOT/home/"}
			elif [[ $target == "$FIXTURE_ACTIVE_SOURCE_ROOT/repo/"* ]]; then
				replacement=$FIXTURE_REPO/${target#"$FIXTURE_ACTIVE_SOURCE_ROOT/repo/"}
			else
				continue
			fi
			rm -f -- "$link" && ln -s -- "$replacement" "$link" || return 1
		done < <(find "$FIXTURE_HOME" -type l -print0)
		receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json
		identity=$(jq -r .source_identity "$receipt") || return 1
		printf 'm000000-fixture-active\n' >"$FIXTURE_CALLS.idle-instance"
		printf '%s\n' "$identity" >"$FIXTURE_CALLS.idle-source-identity"
		return 0
	fi
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'fixture Apply should succeed' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json ]]
	[[ ${1-} == fresh ]] && return 0
	FIXTURE_ACTIVE_TEMPLATE_ROOT=$(mktemp -d)
	mkdir -p "$FIXTURE_ACTIVE_TEMPLATE_ROOT/home" "$FIXTURE_ACTIVE_TEMPLATE_ROOT/state"
	cp -a -- "$FIXTURE_HOME/." "$FIXTURE_ACTIVE_TEMPLATE_ROOT/home/"
	cp -a -- "$FIXTURE_STATE/." "$FIXTURE_ACTIVE_TEMPLATE_ROOT/state/"
	FIXTURE_ACTIVE_SOURCE_ROOT=$FIXTURE_ROOT
}

seed_competing_clones() {
	mkdir -p "$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle" "$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators"
	cat >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"legacy.idle","name":"Legacy Idle","version":"1","kinds":["service"],"entryPoints":{"service":"Service.qml"},"omarchy":{"clonedFrom":"omarchy.idle"}}
JSON
	printf 'legacy idle\n' >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.idle/Service.qml"
	cat >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"legacy.indicators","name":"Legacy Indicators","version":"1","kinds":["bar-widget"],"entryPoints":{"barWidget":"Indicators.qml"},"omarchy":{"clonedFrom":"omarchy.indicators"}}
JSON
	printf 'legacy indicators\n' >"$FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators/Indicators.qml"
	jq '.plugins=[{"id":"legacy.idle"}] | .disabledPlugins=["omarchy.idle"] | .cloneSourceRestores=["legacy.idle"] | .bar.layout.center[0].id="legacy.indicators"' \
		"$FIXTURE_HOME/.config/omarchy/shell.json" >"$FIXTURE_ROOT/competing-shell.json"
	mv -- "$FIXTURE_ROOT/competing-shell.json" "$FIXTURE_HOME/.config/omarchy/shell.json"
}

test_status_is_inactive_and_reports_versions() {
	new_fixture
	run_package_operation screensaver_effects_status
	assert_eq 0 "$COMMAND_STATUS" 'status should be readable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4.0.1-1' 'status should report the supported Omarchy version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected ttfx: 0.3.2-1' 'status should report the detected ttfx version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: inactive' 'an untouched fixture should be inactive'
}

test_unreceipted_edges_block_remove() {
	new_fixture
	jq '.plugins=[{"id":"dotfiles.idle"}] | .cloneSourceRestores=["dotfiles.idle"]' \
		"$FIXTURE_HOME/.config/omarchy/shell.json" >"$FIXTURE_ROOT/edges.json"
	mv -- "$FIXTURE_ROOT/edges.json" "$FIXTURE_HOME/.config/omarchy/shell.json"
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'unreceipted lifecycle edges should block Remove' || return 1
	assert_contains "$COMMAND_OUTPUT" 'shell.json retains Dotfiles activation' 'Remove should identify the unowned shell edge' || return 1
	assert_eq 0 "$(call_count 'stow simulate=false delete=true package=screensaver-effects')" 'Remove should stop before Stow'
}

test_first_apply_and_exact_reapply_are_stable() {
	new_fixture
	local receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json before
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'first Apply should activate the lifecycle' || return 1
	before=$(sha256sum "$receipt")
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'exact reapply should succeed' || return 1
	assert_eq 1 "$(call_count rescan)" 'first Apply should use one rescan and exact reapply none' || return 1
	assert_eq "$before" "$(sha256sum "$receipt")" 'exact reapply should not churn the receipt' || return 1
	assert_contains "$COMMAND_OUTPUT" 'no rescan needed' 'exact reapply should publish a no-op'
}

test_changed_source_restarts_shell() {
	new_fixture
	setup_active_package_fixture || return 1
	printf '\n// changed idle source\n' >>"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/IdleModel.js"
	refresh_fixture_source_identity || return 1
	local restart_before
	restart_before=$(call_count 'restart shell')
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'a validated source change should reapply' || return 1
	assert_eq $((restart_before + 1)) "$(call_count 'restart shell')" 'changed source should use one full shell restart' || return 1
	assert_contains "$COMMAND_OUTPUT" 'active and verified' 'changed source should converge to active'
}

test_stale_runtime_identity_restarts_shell() {
	new_fixture
	setup_active_package_fixture || return 1
	printf '%064d\n' 1 >"$FIXTURE_CALLS.idle-source-identity"
	run_package_operation screensaver_effects_status
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: drifted' 'stale loaded identity should make status drifted' || return 1
	local restart_before
	restart_before=$(call_count 'restart shell')
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should repair a stale runtime identity' || return 1
	assert_eq $((restart_before + 1)) "$(call_count 'restart shell')" 'stale runtime identity should use a full restart'
}

test_active_status_requires_a_current_runtime_marker() {
	new_fixture
	setup_active_package_fixture || return 1
	rm -- "$FIXTURE_CALLS.idle-source-identity"
	run_package_operation screensaver_effects_status
	assert_eq 0 "$COMMAND_STATUS" 'status should remain readable without a runtime marker' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Lifecycle: drifted' 'an active receipt without a current runtime marker must not verify active'
}

test_indicators_change_invalidates_active_status_in_process() {
	new_fixture
	setup_active_package_fixture || return 1
	SCREENSAVER_TEST_INPUT='y\n' run_package_sequence '
sequence_run before screensaver_effects_status
printf "\\n// Indicators source changed after validation\\n" >>"$REPOSITORY_ROOT/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/Indicators.qml"
refresh-source-identity "$REPOSITORY_ROOT"
sequence_run after screensaver_effects_status
sequence_run apply apply_packages screensaver-effects
'
	assert_eq 0 "$(sequence_status before)" 'baseline status should succeed' || return 1
	assert_contains "$(sequence_output before)" 'Lifecycle: active' 'baseline status should be active' || return 1
	assert_eq 0 "$(sequence_status after)" 'status should remain readable after source drift' || return 1
	assert_contains "$(sequence_output after)" 'Lifecycle: drifted' 'fresh source bytes should invalidate the active no-op' || return 1
	assert_eq 0 "$(sequence_status apply)" 'Apply should revalidate and activate changed Indicators source' || return 1
	assert_eq 1 "$(call_count 'restart shell')" 'changed Indicators source should restart the loaded runtime' || return 1
}

test_active_idle_cycle_refuses_before_mutation() {
	new_fixture
	setup_active_package_fixture || return 1
	printf '\n// source change during idle cycle\n' >>"$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/IdleModel.js"
	refresh_fixture_source_identity || return 1
	local before receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json
	before=$(sha256sum "$receipt")
	SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE=true SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'source reload during an idle cycle should refuse' || return 1
	assert_contains "$COMMAND_OUTPUT" 'active idle cycle' 'refusal should explain the active cycle' || return 1
	assert_contains "$COMMAND_OUTPUT" 'wait for activity' 'refusal should give a retry condition' || return 1
	assert_eq 0 "$(omarchy_mutation_count)" 'source-change refusal should happen before any Omarchy mutation' || return 1
	assert_eq "$before" "$(sha256sum "$receipt")" 'cycle refusal should not publish a misleading receipt' || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json && ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/pending.json ]]

	new_fixture
	setup_active_package_fixture || return 1
	rm -- "$FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle"
	receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json
	before=$(sha256sum "$receipt")
	SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE=true SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'missing-link repair during an idle cycle should refuse' || return 1
	assert_eq 0 "$(omarchy_mutation_count)" 'missing-link refusal should happen before any Omarchy mutation' || return 1
	assert_eq "$before" "$(sha256sum "$receipt")" 'missing-link refusal should preserve the receipt' || return 1

	new_fixture
	setup_active_package_fixture || return 1
	receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json
	before=$(sha256sum "$receipt")
	SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE=true run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'Remove during an idle cycle should refuse' || return 1
	assert_eq 0 "$(omarchy_mutation_count)" 'Remove refusal should happen before any Omarchy mutation' || return 1
	assert_eq "$before" "$(sha256sum "$receipt")" 'Remove refusal should preserve the active receipt' || return 1

	new_fixture
	seed_competing_clones
	jq 'del(.disabledPlugins)' "$FIXTURE_HOME/.config/omarchy/shell.json" >"$FIXTURE_ROOT/active-cycle-shell.json"
	mv -- "$FIXTURE_ROOT/active-cycle-shell.json" "$FIXTURE_HOME/.config/omarchy/shell.json"
	SCREENSAVER_TEST_IDLE_CYCLE_ACTIVE=true run_package_operation migrate_screensaver_effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'migration during an idle cycle should refuse' || return 1
	assert_eq 0 "$(omarchy_mutation_count)" 'migration refusal should happen before any Omarchy mutation' || return 1
}

test_missing_owned_leaf_is_repaired_by_apply() {
	new_fixture
	setup_active_package_fixture || return 1
	local leaf=$FIXTURE_HOME/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/IdleModel.js
	rm -- "$leaf"
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should repair a missing owned deployed leaf' || return 1
	[[ -L $leaf && $(readlink -f -- "$leaf") == "$(readlink -f -- "$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/IdleModel.js")" ]] || return 1
	assert_contains "$COMMAND_OUTPUT" 'no rescan needed' 'leaf repair with unchanged source should remain a no-op'
}

test_foreign_extra_leaf_blocks_status_and_apply() {
	new_fixture
	setup_active_package_fixture || return 1
	printf 'foreign extra\n' >"$FIXTURE_HOME/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/foreign.qml"
	SCREENSAVER_TEST_INPUT='y\n' run_package_sequence '
sequence_run status screensaver_effects_status
sequence_run apply apply_packages screensaver-effects
'
	assert_contains "$(sequence_output status)" 'Lifecycle: drifted' 'foreign leaves should make status drifted' || return 1
	assert_eq 1 "$(sequence_status apply)" 'foreign leaves should block Apply' || return 1
	assert_contains "$(sequence_output apply)" 'Foreign extra path exists' 'Apply should identify the foreign leaf'
}

test_remove_waits_for_async_plugin_removal() {
	new_fixture
	jq '.disabledPlugins=["omarchy.idle"]' "$FIXTURE_HOME/.config/omarchy/shell.json" >"$FIXTURE_ROOT/disabled-shell.json"
	mv -- "$FIXTURE_ROOT/disabled-shell.json" "$FIXTURE_HOME/.config/omarchy/shell.json"
	setup_active_package_fixture fresh || return 1
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'normal Remove should succeed' || return 1
	assert_eq 2 "$(call_count 'plugins converged')" 'Remove should wait for both asynchronous plugin removals' || return 1
	assert_eq 0 "$(call_count 'old runtime observed after removal')" 'disabled built-in idle should not require an old idle runtime' || return 1
	assert_contains "$COMMAND_OUTPUT" 'receipt, backups, and diagnostics retained' 'Remove should publish the inactive receipt after convergence' || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators ]] || return 1
	jq -e '(.disabledPlugins | index("omarchy.idle")) != null' "$FIXTURE_HOME/.config/omarchy/shell.json" >/dev/null || return 1
	jq -e '.state == "inactive"' "$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json" >/dev/null
}

test_activation_failure_rolls_back_without_live_links() {
	new_fixture
	SCREENSAVER_TEST_FAIL_IDLE_ENABLE=true SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'activation failure should fail Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stow linked, lifecycle inactive' 'failed activation should retain recoverable Stow state' || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators ]] || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json && ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/pending.json ]]
}

test_legacy_upgrade_and_inactive_remove_noop() {
	new_fixture
	setup_active_package_fixture || return 1
	local receipt=$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json
	jq 'del(.source_identity)' "$receipt" >"$FIXTURE_ROOT/legacy.json"
	mv -- "$FIXTURE_ROOT/legacy.json" "$receipt"
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'Apply should upgrade a legacy receipt' || return 1
	jq -e '.source_identity | type == "string"' "$receipt" >/dev/null || return 1
	run_package_sequence '
sequence_run first_remove remove_package screensaver-effects --yes
jq "del(.source_identity)" "$SCREENSAVER_TEST_ROOT/state/dotfiles/screensaver-effects/receipt.json" >"$SCREENSAVER_TEST_ROOT/legacy-inactive.json"
mv -- "$SCREENSAVER_TEST_ROOT/legacy-inactive.json" "$SCREENSAVER_TEST_ROOT/state/dotfiles/screensaver-effects/receipt.json"
sequence_run second_remove remove_package screensaver-effects --yes
'
	assert_eq 0 "$(sequence_status first_remove)" 'Remove should retain an inactive receipt' || return 1
	assert_eq 0 "$(sequence_status second_remove)" 'inactive legacy Remove should be an idempotent no-op'
}

test_migration_success_retains_backup() {
	new_fixture
	seed_competing_clones
	run_package_operation migrate_screensaver_effects --yes
	assert_eq 0 "$COMMAND_STATUS" 'migration should activate the package' || return 1
	jq -e '.state == "active" and .migration.performed == true and (.migration.backup | type == "string")' \
		"$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json" >/dev/null || return 1
	[[ -d $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && ! -d $FIXTURE_HOME/.config/omarchy/plugins/legacy.idle ]]
}

test_migration_failure_restores_competing_clones() {
	new_fixture
	seed_competing_clones
	SCREENSAVER_TEST_FAIL_IDLE_ENABLE=true run_package_operation migrate_screensaver_effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'migration activation failure should fail the operation' || return 1
	assert_eq 2 "$(call_count 'plugins converged')" 'migration rollback should wait for both asynchronous Dotfiles removals' || return 1
	[[ -d $FIXTURE_HOME/.config/omarchy/plugins/legacy.idle && -d $FIXTURE_HOME/.config/omarchy/plugins/legacy.indicators ]] || return 1
	[[ ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && ! -e $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators ]] || return 1
	[[ ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/pending.json && ! -e $FIXTURE_STATE/dotfiles/screensaver-effects/recovery-required.json ]]
}

test_pending_state_blocks_apply() {
	new_fixture
	mkdir -p "$FIXTURE_STATE/dotfiles/screensaver-effects"
	cat >"$FIXTURE_STATE/dotfiles/screensaver-effects/pending.json" <<'JSON'
{"schema_version":1,"package":"screensaver-effects","operation":"apply","attempt_id":"fixture","started_at":"2026-08-30T00:00:00Z","prior_receipt_sha256":null}
JSON
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'pending evidence should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'pending apply operation' 'Apply should name pending evidence' || return 1
	assert_eq 0 "$(call_count 'stow simulate=false delete=false package=screensaver-effects')" 'pending evidence should stop before Stow'
}

test_menu_conflict_blocks_apply() {
	new_fixture
	cat >"$FIXTURE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" <<'JSONC'
{"system.screensaver":{"label":"Foreign","action":"custom"}}
JSONC
	SCREENSAVER_TEST_INPUT='y\n' run_package_operation apply_packages screensaver-effects
	assert_eq 1 "$COMMAND_STATUS" 'a different menu entry should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'different system.screensaver menu entry' 'Apply should identify the menu conflict'
}

test_owned_bar_conflict_blocks_remove() {
	new_fixture
	setup_active_package_fixture || return 1
	jq '.bar.layout.center[0].custom=false' "$FIXTURE_HOME/.config/omarchy/shell.json" >"$FIXTURE_ROOT/bar.json"
	mv -- "$FIXTURE_ROOT/bar.json" "$FIXTURE_HOME/.config/omarchy/shell.json"
	run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'changed owned bar data should block Remove' || return 1
	assert_contains "$COMMAND_OUTPUT" 'active Indicators bar edges moved or were replaced' 'Remove should identify the owned bar conflict'
}

test_stow_removal_failure_restores_active_lifecycle() {
	new_fixture
	setup_active_package_fixture || return 1
	SCREENSAVER_TEST_STOW_DELETE_FAILURE=true run_package_operation remove_package screensaver-effects --yes
	assert_eq 1 "$COMMAND_STATUS" 'Stow removal failure should fail Remove' || return 1
	assert_contains "$COMMAND_OUTPUT" 'active state restored after Stow removal failure' 'Remove should restore the active lifecycle' || return 1
	jq -e '.state == "active"' "$FIXTURE_STATE/dotfiles/screensaver-effects/receipt.json" >/dev/null || return 1
	[[ -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.idle && -L $FIXTURE_HOME/.config/omarchy/plugins/dotfiles.indicators ]]
}

test_source_identity_refresh_covers_embedded_and_both_trees() {
	new_fixture
	local indicators=$FIXTURE_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/Indicators.qml
	printf '\n// Indicators source change\n' >>"$indicators"
	run_package_operation screensaver_effects_check
	assert_eq 1 "$COMMAND_STATUS" 'changed Indicators source should reject its old embedded identity' || return 1
	refresh_fixture_source_identity || return 1
	run_package_operation screensaver_effects_check
	assert_eq 0 "$COMMAND_STATUS" 'refreshing the embedded identity should restore source validity'
}

run_test() {
	local function=$1 description=$2
	TESTS_RUN=$((TESTS_RUN + 1))
	if "$function"; then pass "$description"; else fail "$description"; fi
}

set -e
run_test test_status_is_inactive_and_reports_versions 'status reports compatibility and inactive lifecycle'
run_test test_unreceipted_edges_block_remove 'unreceipted edges block Remove'
run_test test_first_apply_and_exact_reapply_are_stable 'first Apply and exact reapply are stable'
run_test test_changed_source_restarts_shell 'changed source uses a full shell restart'
run_test test_stale_runtime_identity_restarts_shell 'stale loaded identity uses a full shell restart'
run_test test_active_status_requires_a_current_runtime_marker 'active status requires a current runtime marker'
run_test test_indicators_change_invalidates_active_status_in_process 'Indicators source changes invalidate an active no-op'
run_test test_active_idle_cycle_refuses_before_mutation 'active idle cycles refuse before mutation'
run_test test_missing_owned_leaf_is_repaired_by_apply 'Apply repairs a missing owned leaf'
run_test test_foreign_extra_leaf_blocks_status_and_apply 'foreign extra leaves block status and Apply'
run_test test_remove_waits_for_async_plugin_removal 'Remove waits for asynchronous plugin removal'
run_test test_activation_failure_rolls_back_without_live_links 'activation failure rolls back without live links'
run_test test_legacy_upgrade_and_inactive_remove_noop 'legacy receipts upgrade and inactive Remove is idempotent'
run_test test_migration_success_retains_backup 'migration succeeds and retains its backup'
run_test test_migration_failure_restores_competing_clones 'migration failure restores competing clones'
run_test test_pending_state_blocks_apply 'pending state blocks Apply'
run_test test_menu_conflict_blocks_apply 'menu conflicts block Apply'
run_test test_owned_bar_conflict_blocks_remove 'owned bar conflicts block Remove'
run_test test_stow_removal_failure_restores_active_lifecycle 'Stow removal failure restores active lifecycle'
run_test test_source_identity_refresh_covers_embedded_and_both_trees 'source identity covers embedded and both plugin trees'

printf '1..%d\n' "$TESTS_RUN"
((TESTS_FAILED == 0))
