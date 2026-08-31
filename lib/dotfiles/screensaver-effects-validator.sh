#!/usr/bin/env bash

set -u

readonly SUPPORTED_OMARCHY=4.0.1-1
readonly SUPPORTED_TTFX_PACKAGE=0.3.2-1
readonly SUPPORTED_TTFX_CLI=0.3.2
readonly OMARCHY_ROOT=${DOTFILES_SCREENSAVER_TEST_OMARCHY_ROOT:-/usr/share/omarchy}

errors=0
warnings=0

error() {
	printf 'ERROR: %s\n' "$1" >&2
	errors=$((errors + 1))
}

warning() {
	printf 'Warning: %s\n' "$1"
	warnings=$((warnings + 1))
}

for command in bash cmp find grep jq omarchy pacman realpath sha256sum sort stat tr ttfx; do
	command -v "$command" >/dev/null 2>&1 || error "required validation command is unavailable: $command"
done

if [[ -n ${DOTFILES_REPOSITORY_ROOT:-} ]]; then
	repository=$(realpath -e -- "$DOTFILES_REPOSITORY_ROOT" 2>/dev/null || true)
else
	validator=$(realpath -e -- "${BASH_SOURCE[0]}" 2>/dev/null || true)
	repository=$(cd -- "$(dirname -- "$validator")/../.." 2>/dev/null && pwd -P)
fi
if [[ $repository != /* || ! -d $repository ]]; then
	printf 'ERROR: repository root is unavailable\n' >&2
	exit 1
fi

package=$repository/config/screensaver-effects
allowlist=$package/.config/dotfiles/screensaver-effects.json
selector=$package/.local/libexec/dotfiles/screensaver-effects-selector
idle=$package/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle
indicators=$package/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators
shim=$idle/bin/ttfx
launcher=$idle/launch-screensaver

detected_omarchy=unknown
detected_omarchy_package=unknown
detected_ttfx_package=unknown
detected_ttfx_cli=unknown
if command -v omarchy >/dev/null 2>&1; then
	detected_omarchy=$(omarchy version 2>/dev/null | tr -d '\r' || true)
	[[ -n $detected_omarchy ]] || detected_omarchy=unknown
fi
if command -v pacman >/dev/null 2>&1; then
	read -r _ detected_omarchy_package < <(pacman -Q omarchy 2>/dev/null || true)
	read -r _ detected_ttfx_package < <(pacman -Q ttfx 2>/dev/null || true)
	[[ -n $detected_omarchy_package ]] || detected_omarchy_package=unknown
	[[ -n $detected_ttfx_package ]] || detected_ttfx_package=unknown
fi
if command -v ttfx >/dev/null 2>&1; then
	detected_ttfx_cli=$(ttfx --version 2>/dev/null | tr -d '\r' || true)
	detected_ttfx_cli=${detected_ttfx_cli#ttfx }
	[[ -n $detected_ttfx_cli ]] || detected_ttfx_cli=unknown
fi

printf 'Supported Omarchy: %s\n' "$SUPPORTED_OMARCHY"
printf 'Detected Omarchy package/CLI: %s / %s\n' "$detected_omarchy_package" "$detected_omarchy"
printf 'Supported ttfx package/CLI: %s / %s\n' "$SUPPORTED_TTFX_PACKAGE" "$SUPPORTED_TTFX_CLI"
printf 'Detected ttfx package/CLI: %s / %s\n' "$detected_ttfx_package" "$detected_ttfx_cli"

[[ $detected_omarchy == "$SUPPORTED_OMARCHY" && $detected_omarchy_package == "$SUPPORTED_OMARCHY" ]] ||
	warning "supported Omarchy is $SUPPORTED_OMARCHY; detected package/CLI is $detected_omarchy_package / $detected_omarchy"
[[ $detected_ttfx_package == "$SUPPORTED_TTFX_PACKAGE" && $detected_ttfx_cli == "$SUPPORTED_TTFX_CLI" ]] ||
	warning "supported ttfx package/CLI is $SUPPORTED_TTFX_PACKAGE / $SUPPORTED_TTFX_CLI; detected $detected_ttfx_package / $detected_ttfx_cli"

declare -A expected_type=() expected_mode=() seen=()
expect_directory() {
	expected_type[$1]=d
}
expect_file() {
	expected_type[$1]=f
	expected_mode[$1]=$2
}

for path in \
	.config \
	.config/dotfiles \
	.local \
	.local/libexec \
	.local/libexec/dotfiles \
	.local/share \
	.local/share/dotfiles \
	.local/share/dotfiles/screensaver-effects \
	.local/share/dotfiles/screensaver-effects/plugins \
	.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle \
	.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/bin \
	.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators \
	.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/indicators; do
	expect_directory "$path"
done

expect_file .config/dotfiles/screensaver-effects.json 644
expect_file .local/libexec/dotfiles/screensaver-effects-selector 755
expect_file .local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/IdleModel.js 644
expect_file .local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml 644
expect_file .local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/bin/ttfx 755
expect_file .local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/launch-screensaver 755
expect_file .local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/manifest.json 644
expect_file .local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/Indicators.qml 644
expect_file .local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/manifest.json 644
for name in Dictation Dnd NightLight Reminder ScreenRecording StayAwake; do
	expect_file ".local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/indicators/$name.qml" 644
done

if [[ ! -d $package || -L $package ]]; then
	error "package source is not a regular directory: $package"
else
	while IFS=$'\t' read -r path type mode; do
		[[ -n $path ]] || continue
		seen[$path]=1
		if [[ -z ${expected_type[$path]+set} ]]; then
			error "unexpected package inventory path: $path"
			continue
		fi
		[[ $type == "${expected_type[$path]}" ]] || error "package inventory type drift at $path"
		if [[ $type == f && $mode != "${expected_mode[$path]}" ]]; then
			error "package mode drift at $path: expected ${expected_mode[$path]}, detected $mode"
		fi
	done < <(find "$package" -mindepth 1 -printf '%P\t%y\t%m\n' | LC_ALL=C sort)
	for path in "${!expected_type[@]}"; do
		[[ -n ${seen[$path]+set} ]] || error "missing package inventory path: $path"
	done
fi

declare -A source_hashes=(
	[.local/libexec/dotfiles/screensaver-effects-selector]=d0c894345e660063bcd4aef70a35040dfb74546a96412fbe182c1d0f3bad60a6
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/IdleModel.js]=58226a67d5fc2f33b1a23b55cb32764a8b2091cc94c4d02af1b67f369440b9b8
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml]=222d9dc9ac02bb56ea2f2f56c5e81ad9cf901b45c91c5628180bbdf7ea504248
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/bin/ttfx]=823226321fd69cc4e39db88103c08713469c0ab0d3521ad393708df1d78bc61e
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/launch-screensaver]=787332166ac0657f7abea5dc108cad9c200b64469c46a09c78cdd9b12d734651
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/manifest.json]=364274a35801ce043bdd725e5ed8e03f9e8134b05c9515985e9f6cc089980cb0
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/Indicators.qml]=6943c7a0678858baa0ec4e36049dc6d3646307fee727b3bbe5b158e73ec3b29b
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/manifest.json]=165028a5f28d42031c5f28954f4f9fca1c24238a386a0718a7967826e6ee3d99
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/indicators/Dictation.qml]=581498154ecbfaa64dcc0612dbac417968b8567404c0cabb13fa092f339c7ac6
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/indicators/Dnd.qml]=ef3dfda58d9a874d304d6c7742508535957d99e388d2140ca90d14f1b29050d1
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/indicators/NightLight.qml]=9a7d5dbbcf5f2b1612d673cef8fba26c53584364e12b43935f1d02a66fb404d2
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/indicators/Reminder.qml]=51cef554abf4b4b28692cee73add20e2c34bd9883bfed74be10b5334d73f7c7b
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/indicators/ScreenRecording.qml]=e336f4e14e0875fe56cb0c1008799506eb5023051c80e530b9e1f35fedbce2df
	[.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators/indicators/StayAwake.qml]=ef0beece94f74491f2e58b00f91433fe291bd9f12f2bed6ea1a2017268e6d93e
)
for path in "${!source_hashes[@]}"; do
	[[ -f $package/$path && ! -L $package/$path ]] || continue
	actual_hash=$(sha256sum "$package/$path")
	actual_hash=${actual_hash%% *}
	[[ $actual_hash == "${source_hashes[$path]}" ]] || error "reviewed package source drift at $path"
done

if [[ -f $idle/manifest.json ]]; then
	jq -e '
		.schemaVersion == 1 and .id == "dotfiles.idle" and .name == "Dotfiles Idle" and
		.kinds == ["service"] and .keepLoaded == true and
		.entryPoints == {"service":"Service.qml"} and
		.omarchy == {"clonedFrom":"omarchy.idle"}
	' "$idle/manifest.json" >/dev/null 2>&1 || error 'dotfiles.idle manifest contract is invalid'
fi
if [[ -f $indicators/manifest.json ]]; then
	jq -e '
		.schemaVersion == 1 and .id == "dotfiles.indicators" and .name == "Dotfiles Indicators" and
		.kinds == ["bar-widget"] and .entryPoints == {"barWidget":"Indicators.qml"} and
		.barWidget.displayName == "Dotfiles Indicators" and
		.omarchy == {"clonedFrom":"omarchy.indicators"}
	' "$indicators/manifest.json" >/dev/null 2>&1 || error 'dotfiles.indicators manifest contract is invalid'
fi

for script in "$selector" "$launcher" "$shim"; do
	[[ -f $script ]] && bash -n "$script" || error "Bash syntax validation failed: ${script#$repository/}"
done

require_text() {
	local file=$1 text=$2 description=$3
	[[ -f $file ]] && grep -Fq -- "$text" "$file" || error "$description"
}
require_text "$idle/Service.qml" 'function screensaver(): string' 'idle IPC screensaver route is missing'
require_text "$idle/Service.qml" 'dotfilesSourceIdentity: "' 'idle service does not embed its source identity'
require_text "$idle/Service.qml" 'dotfilesInstanceId: root.dotfilesInstanceId' 'idle status lacks its runtime instance marker'
require_text "$idle/Service.qml" 'Qt.resolvedUrl("launch-screensaver")' 'idle service does not resolve its plugin-local launcher'
require_text "$indicators/indicators/StayAwake.qml" 'resolveEnabledId("omarchy.idle")' 'Stay Awake does not resolve the enabled idle implementation'
require_text "$launcher" '"PATH=$shim_dir:$PATH"' 'launcher does not carry the terminal-scoped shim through dispatch'
require_text "$launcher" 'DOTFILES_SCREENSAVER_ATTEMPT_DIR' 'launcher does not share one launch-attempt marker'
require_text "$shim" 'screensaver_retain_failure' 'runtime shim lacks retained-process failure handling'
require_text "$shim" 'printf %s ttfx >"/proc/$$/comm"' 'runtime shim does not retain the process identity polled by Omarchy'
require_text "$shim" '--existing-color-handling ignore' 'runtime shim lacks the reviewed root color policy'
require_text "$selector" 'stdin and stdout must be terminals' 'selector lacks public TTY enforcement'
require_text "$selector" 'mktemp "$allowlist.tmp.XXXXXX"' 'selector does not use a sibling source temporary'

declare -A expected_mapping=() mapping=() discovered=()
for effect in \
	beams bouncyballs bubbles colorshift expand highlight matrix middleout orbittingvolley \
	overflow pour rain randomsequence rings scattered slice slide smoke spotlights spray swarm \
	synthgrid unstable waves wipe; do
	expected_mapping[$effect]=Full
done
for effect in binarypath blackhole burn crumble decrypt errorcorrect fireworks laseretch print sweep thunderstorm vhstape; do
	expected_mapping[$effect]=Partial
done

mapping_output=
if [[ -x $shim ]]; then
	mapping_output=$(env -u DOTFILES_SCREENSAVER_SOURCE_ONLY DOTFILES_SCREENSAVER_INTERNAL=validator \
		"$shim" --dotfiles-mapping-catalog 2>/dev/null || true)
fi
while IFS=$'\t' read -r effect status; do
	[[ -n $effect ]] || continue
	if [[ -n ${mapping[$effect]+set} ]]; then
		error "duplicate runtime mapping: $effect"
		continue
	fi
	mapping[$effect]=$status
done <<<"$mapping_output"
for effect in "${!expected_mapping[@]}"; do
	[[ ${mapping[$effect]:-} == "${expected_mapping[$effect]}" ]] ||
		error "runtime mapping classification drift for $effect"
done
for effect in "${!mapping[@]}"; do
	[[ -n ${expected_mapping[$effect]+set} ]] || error "unexpected runtime mapping: $effect"
done
[[ ${#mapping[@]} == 37 ]] || error "runtime mapping catalog must contain 37 effects; detected ${#mapping[@]}"

discover_effects() {
	local line name in_commands=0
	while IFS= read -r line; do
		if [[ $line == Commands: ]]; then
			in_commands=1
			continue
		fi
		((in_commands)) || continue
		[[ -n ${line//[[:space:]]/} ]] || break
		line=${line#"${line%%[![:space:]]*}"}
		name=${line%%[[:space:]]*}
		[[ $name == help || ! $name =~ ^[a-z0-9]+$ ]] || printf '%s\n' "$name"
	done < <(ttfx --help 2>/dev/null)
}
if command -v ttfx >/dev/null 2>&1; then
	while IFS= read -r effect; do
		[[ -n $effect ]] && discovered[$effect]=1
	done < <(discover_effects | LC_ALL=C sort -u)
	((${#discovered[@]} > 0)) || error 'ttfx exposed no effects through --help'
	for effect in "${!discovered[@]}"; do
		if [[ -z ${expected_mapping[$effect]+set} ]]; then
			if [[ $detected_ttfx_cli == "$SUPPORTED_TTFX_CLI" ]]; then
				error "supported ttfx exposed an Unmapped effect: $effect"
			else
				warning "detected ttfx exposed a new Unmapped effect: $effect"
			fi
		fi
	done
	for effect in "${!expected_mapping[@]}"; do
		if [[ -z ${discovered[$effect]+set} ]]; then
			if [[ $detected_ttfx_cli == "$SUPPORTED_TTFX_CLI" ]]; then
				error "supported ttfx catalog is missing mapped effect: $effect"
			else
				warning "detected ttfx catalog is missing mapped effect: $effect"
			fi
		fi
	done
fi

if [[ ! -f $allowlist || -L $allowlist ]]; then
	error "tracked allowlist is not a regular source file: $allowlist"
elif ! jq -e '
	type == "array" and length > 0 and
	all(.[]; type == "string" and test("^[a-z0-9]+$")) and
	(length == (unique | length))
' "$allowlist" >/dev/null 2>&1; then
	error 'tracked allowlist must be a nonempty array of unique lowercase effect names'
else
	cmp -s "$allowlist" <(LC_ALL=C jq 'sort' "$allowlist") ||
		error 'tracked allowlist is not canonical lexical two-space JSON with a final newline'
	while IFS= read -r effect; do
		[[ -n ${mapping[$effect]+set} ]] || error "allowlisted effect is Unmapped: $effect"
		[[ -n ${discovered[$effect]+set} ]] || error "allowlisted effect is unavailable: $effect"
	done < <(jq -r '.[]' "$allowlist")
fi

deployed=${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/screensaver-effects.json
if [[ -e $deployed || -L $deployed ]]; then
	if [[ ! -L $deployed ]]; then
		error "deployed allowlist leaf is not a Stow symlink: $deployed"
	else
		resolved_allowlist=$(realpath -e -- "$allowlist" 2>/dev/null || true)
		resolved_deployed=$(realpath -e -- "$deployed" 2>/dev/null || true)
		[[ -n $resolved_deployed && $resolved_deployed == "$resolved_allowlist" ]] ||
			error 'deployed allowlist leaf does not resolve to the tracked source'
	fi
fi

host_supported=0
[[ $detected_omarchy == "$SUPPORTED_OMARCHY" && $detected_omarchy_package == "$SUPPORTED_OMARCHY" ]] && host_supported=1

clone_surface_difference() {
	if ((host_supported)); then
		error "supported Omarchy clone surface difference: $1"
	else
		warning "detected Omarchy clone surface differs from the supported baseline: $1"
	fi
}

declare -A expected_clone_type=(
	[shell/plugins/services/idle/manifest.json]=f
	[shell/plugins/services/idle/Service.qml]=f
	[shell/plugins/services/idle/IdleModel.js]=f
	[shell/plugins/bar/widgets/Indicators.manifest.json]=f
	[shell/plugins/bar/widgets/Indicators.qml]=f
	[shell/plugins/bar/indicators/Dictation.qml]=f
	[shell/plugins/bar/indicators/Dnd.qml]=f
	[shell/plugins/bar/indicators/NightLight.qml]=f
	[shell/plugins/bar/indicators/Reminder.qml]=f
	[shell/plugins/bar/indicators/ScreenRecording.qml]=f
	[shell/plugins/bar/indicators/StayAwake.qml]=f
)
declare -A detected_clone_type=()
for surface in shell/plugins/services/idle shell/plugins/bar/indicators; do
	while IFS=$'\t' read -r path type; do
		[[ -n $path ]] && detected_clone_type[$surface/$path]=$type
	done < <(find "$OMARCHY_ROOT/$surface" -mindepth 1 -printf '%P\t%y\n' 2>/dev/null | LC_ALL=C sort)
done
for path in shell/plugins/bar/widgets/Indicators.manifest.json shell/plugins/bar/widgets/Indicators.qml; do
	while IFS= read -r type; do
		detected_clone_type[$path]=$type
	done < <(find "$OMARCHY_ROOT/$path" -maxdepth 0 -printf '%y\n' 2>/dev/null)
done
for path in "${!detected_clone_type[@]}"; do
	if [[ -z ${expected_clone_type[$path]+set} ]]; then
		clone_surface_difference "unexpected path: $OMARCHY_ROOT/$path"
	elif [[ ${detected_clone_type[$path]} != "${expected_clone_type[$path]}" ]]; then
		clone_surface_difference "type drift at $OMARCHY_ROOT/$path: expected ${expected_clone_type[$path]}, detected ${detected_clone_type[$path]}"
	fi
done
for path in "${!expected_clone_type[@]}"; do
	[[ -n ${detected_clone_type[$path]+set} ]] ||
		clone_surface_difference "missing path: $OMARCHY_ROOT/$path"
done

declare -A host_hashes=(
	[shell/plugins/services/idle/manifest.json]=bb8a5f55257dc49c2b7632304dad19aa12bbc7ad641828f09481909232f30a6f
	[shell/plugins/services/idle/Service.qml]=c61f91b55adf864e4ce571526644727b7a2e9f672964af8098b9fd9a4913eee2
	[shell/plugins/services/idle/IdleModel.js]=58226a67d5fc2f33b1a23b55cb32764a8b2091cc94c4d02af1b67f369440b9b8
	[shell/plugins/bar/widgets/Indicators.manifest.json]=3eea8a52c46d7e2436f8967abb4347d56163f7cef622caf0fe2d69bf6858d59b
	[shell/plugins/bar/widgets/Indicators.qml]=f64fc3a122d71e6cc1f9a8b8284416df29cac070306fa6df55e9f1053fe4cf65
	[shell/plugins/bar/indicators/Dictation.qml]=581498154ecbfaa64dcc0612dbac417968b8567404c0cabb13fa092f339c7ac6
	[shell/plugins/bar/indicators/Dnd.qml]=ef3dfda58d9a874d304d6c7742508535957d99e388d2140ca90d14f1b29050d1
	[shell/plugins/bar/indicators/NightLight.qml]=9a7d5dbbcf5f2b1612d673cef8fba26c53584364e12b43935f1d02a66fb404d2
	[shell/plugins/bar/indicators/Reminder.qml]=51cef554abf4b4b28692cee73add20e2c34bd9883bfed74be10b5334d73f7c7b
	[shell/plugins/bar/indicators/ScreenRecording.qml]=e336f4e14e0875fe56cb0c1008799506eb5023051c80e530b9e1f35fedbce2df
	[shell/plugins/bar/indicators/StayAwake.qml]=0701f2231d292af5ab500cb7be574222d0be82a7831eb8188da038f2347bdd13
	[shell/services/PluginRegistry.qml]=63371e4224f948e5444531282ad9f7c74ca2e578470b549f4c6b898c3a15c50f
	[shell/shell.qml]=9f1db77dcc3c111ceccc860ac472d19b35d385958a63d270ea51e413ab86f1f0
	[shell/plugins/menu/Menu.qml]=7fef6394cce563f188324386738a55e3bde36187ba6d1341ac2d4d46e1879df9
	[bin/omarchy-plugin-clone]=0a5d5cd534443262b1cbade2e4f1d787294fa72b9fb1fb6b3719215b4471a4ac
	[bin/omarchy-plugin-enable]=750c18dd96dd75e4811215e3fd13f71f5a11aff8e588b4e21688cdc5dd7c62b5
	[bin/omarchy-plugin-disable]=394414db2d5fd393080f013ba301cf44d81c7bcea7046f7b8c5e34faf1acde15
	[bin/omarchy-plugin-remove]=ea4e4462ab75b28f249d5e03c03890a1821fd9f095346df34bcb431b2c1e3cc2
	[bin/omarchy-plugin-catalog]=f995166899b794b49ac15a256cce4b1513648870a9c951c680c8fac18f627ab8
	[bin/omarchy-plugin-list]=81b990d021a53cbe597c09d8bef92c8909879003db30fb8f56d9f0e03bbcb461
	[bin/omarchy-launch-shell]=484f3af00ee3d13b8f4e33b118d9b7355c72d254a631fc740a160f5f1d140cff
	[bin/omarchy-hyprland-session-locked]=e5004580e41475932f852d622b36ec07bfb0e98633c4d3c3055071a54d0eda07
	[bin/omarchy-restart-shell]=e4c996275a15025c9aac829d34913d6bcaf8a30a17fae5ce5e260df2ddf21cd7
	[bin/omarchy-shell]=538ece231aba80154c76ab48df8ab013b2f02c5171241d08bddbf08a5fe5ac34
	[bin/omarchy-launch-screensaver]=b58b82a6b9edc901c83da50a3e2b2ac7fee8d1311a7f327a9ec8901ff8028338
	[bin/omarchy-screensaver]=9ad1b57d322b5ed04112824ef48c98b7f14f1f08a60b583395558afbfd9fb7d2
	[bin/omarchy-theme-color]=a429ed1b18114ff3e784fc4479c6b829e9effb64c0f9d22d3b15eda4c62d86b5
	[default/alacritty/screensaver.toml]=b47ca28f13c7409f17f0938f6e50eb854509b0c1152e05ecde4f59cc2418cf22
	[default/ghostty/screensaver]=cd14aa796193660808bbd3341d12f5cc69937698399f267015ee2010f627a865
	[default/foot/screensaver.ini]=053150146bccb101eb2f14e0622376cff4d62563c3b1a16ae7dd8668be7ac51c
	[default/omarchy/omarchy-menu.jsonc]=42eafef634bb52c4f23b191ec597f442e35e139232ccded6cecba8f7dbb6f648
	[default/hypr/apps/system.lua]=c0c5a45b7abadb22224089b17381ba7b455a5c5d36f770930fb044d9402b5ef3
)
for path in "${!host_hashes[@]}"; do
	host=$OMARCHY_ROOT/$path
	if [[ ! -f $host ]]; then
		if ((host_supported)); then error "supported Omarchy host seam is missing: $host"
		else warning "detected Omarchy host seam is missing: $host"
		fi
		continue
	fi
	actual_hash=$(sha256sum "$host")
	actual_hash=${actual_hash%% *}
	if [[ $actual_hash != "${host_hashes[$path]}" ]]; then
		if ((host_supported)); then error "supported Omarchy host seam drift: $host"
		else warning "detected Omarchy host seam differs from the supported baseline: $host"
		fi
	fi
done

printf 'Reviewed clone differences: identity metadata, plugin-local idle launch/IPC, Indicators clone path, Stay Awake resolution.\n'
printf 'Clone surface inventory paths checked: %d\n' "${#expected_clone_type[@]}"
printf 'Host baseline seams checked: %d\n' "${#host_hashes[@]}"
if ((errors > 0)); then
	printf 'Screensaver effects structural validation failed with %d error(s) and %d warning(s).\n' "$errors" "$warnings" >&2
	exit 1
fi
printf 'Screensaver effects structural validation passed with %d warning(s).\n' "$warnings"
