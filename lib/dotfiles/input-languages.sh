readonly INPUT_LANGUAGES_MIN_OMARCHY=4.0.2
readonly INPUT_LANGUAGES_STOCK_WIDGET=omarchy.keyboard-layout
readonly INPUT_LANGUAGES_WIDGET=dotfiles.keyboard-layout
readonly INPUT_LANGUAGES_WIDGET_FILES=(KeyboardLayout.qml KeyboardLayoutModel.js manifest.json)
readonly INPUT_LANGUAGES_FILES=(
	.luarc.json autostart.lua bindings.lua hypridle.conf hyprland.lua hyprlock.conf
	hyprsunset.conf input.lua looknfeel.lua monitors.lua xdph.conf
)
readonly INPUT_LANGUAGES_PKGCONFIG_MODULES=(
	hyprland pixman-1 libdrm aquamarine hyprutils hyprgraphics hyprcursor hyprlang libinput libudev
)
readonly INPUT_LANGUAGES_STACK_PACKAGES=(
	hyprland pixman libdrm aquamarine hyprutils hyprgraphics hyprcursor hyprlang libinput systemd-libs
)
readonly INPUT_LANGUAGES_INTEGRATION_STACK_PACKAGES=(
	hyprland pixman libdrm aquamarine hyprutils hyprgraphics hyprcursor hyprlang libinput systemd-libs openssl fcitx5
	gcc binutils make pkgconf
)
readonly INPUT_LANGUAGES_INTEGRATION_PKGCONFIG_MODULES=(
	hyprland pixman-1 libdrm aquamarine hyprutils hyprgraphics hyprcursor hyprlang libinput libudev libsystemd libcrypto
)
readonly INPUT_LANGUAGES_INTEGRATION_CONTRACT_FILES=(
	active-fixtures.json authority.json evidence-v3.json fcitx.json health.json manifest.json protocol.json systemd.json
)
readonly INPUT_LANGUAGES_INTEGRATION_SOURCE_FILES=(
	integration.mk migration-baseline.json
	include/fcitx-controller.hpp include/fcitx-follower.hpp include/fcitx-helper.hpp include/fcitx-protocol.hpp include/input-language-model.hpp
	src/fcitx-controller.cpp src/fcitx-follower.cpp src/fcitx-helper-main.cpp src/fcitx-helper.cpp src/fcitx-protocol.cpp
	src/fcitx-sd-bus-transport.cpp src/input-language-model.cpp src/integration-artifact-identity.cpp src/plugin.cpp
)
readonly INPUT_LANGUAGES_INTEGRATION_PLUGIN_FLAGS='-std=c++23,-Wall,-Wextra,-Wpedantic,-Werror,-shared,-fPIC,-fno-gnu-unique,-pthread'
readonly INPUT_LANGUAGES_INTEGRATION_HELPER_FLAGS='-std=c++23,-Wall,-Wextra,-Wpedantic,-Werror,-pthread'

input_languages_integration_contract_expected_digest() {
	case $1 in
		active-fixtures.json) printf '%s\n' c8135a04fb250bf523831709f13905a1fbfef513855e4443d906d82c3b64599f ;;
		authority.json) printf '%s\n' 3c7670889f080f5b03c26a51b77a402267c6cb566f7727631717fc33de3f4526 ;;
		evidence-v3.json) printf '%s\n' 52ba3d128bc8a2c2f2c90c495508a8a65c7082d245d68e6b88ec1e06cc762810 ;;
		fcitx.json) printf '%s\n' 113df77363f2d4d1552eacad65170f11bc6c66f842b7369941dc830336e92315 ;;
		health.json) printf '%s\n' 10477d8adc5e186c510928436b31bbdac81fce7083deec5ce5acb7115a4419fe ;;
		manifest.json) printf '%s\n' 84714ebf5bb3d3b2d49c13b72a692da66fea91d896199ea668af384b4eebaaa8 ;;
		protocol.json) printf '%s\n' 3bcc3b22a57bfbf2d8a5d77c90242207a2a3fcad0940e4019bb422e9f3b43990 ;;
		systemd.json) printf '%s\n' 48a3437efc83ec91293c74f1e043cafab98e35c7b5e4e70f4f268d32863a3296 ;;
		*) return 1 ;;
	esac
}

INPUT_LANGUAGES_TREE_STATE=unknown
INPUT_LANGUAGES_ACTIVE_STATE=absent
INPUT_LANGUAGES_PENDING_STATE=absent
INPUT_LANGUAGES_RECOVERY_STATE=absent
INPUT_LANGUAGES_CLEANUP_STATE=absent
INPUT_LANGUAGES_ACTIVE_VALID=false
INPUT_LANGUAGES_WIDGET_PRESENT=false
INPUT_LANGUAGES_WIDGET_COUNT=0
INPUT_LANGUAGES_WIDGET_SECTION=''
INPUT_LANGUAGES_WIDGET_INDEX=''
INPUT_LANGUAGES_WIDGET_ENTRY=null
INPUT_LANGUAGES_WIDGET_STATE=unknown
INPUT_LANGUAGES_STOCK_WIDGET_PRESENT=false
INPUT_LANGUAGES_STOCK_WIDGET_COUNT=0
INPUT_LANGUAGES_STOCK_WIDGET_SECTION=''
INPUT_LANGUAGES_STOCK_WIDGET_INDEX=''
INPUT_LANGUAGES_STOCK_WIDGET_ENTRY=null
INPUT_LANGUAGES_WEATHER_COUNT=0
INPUT_LANGUAGES_WEATHER_SECTION=''
INPUT_LANGUAGES_WEATHER_INDEX=''
INPUT_LANGUAGES_WIDGET_LINK_STATE=absent
INPUT_LANGUAGES_WIDGET_LINK_TARGET=''
INPUT_LANGUAGES_COMPETING_CLONES=''
INPUT_LANGUAGES_PLUGIN_HEALTH=''
INPUT_LANGUAGES_PLUGIN_HEALTH_VALID=false
INPUT_LANGUAGES_INDICATOR_HEALTHY=false
INPUT_LANGUAGES_SUPPORTED=false
INPUT_LANGUAGES_VERSION=unknown
INPUT_LANGUAGES_PREPARED_RESULT=''

input_languages_set_paths() {
	INPUT_LANGUAGES_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
	INPUT_LANGUAGES_DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
	INPUT_LANGUAGES_STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
	INPUT_LANGUAGES_LIVE=$INPUT_LANGUAGES_CONFIG_HOME/hypr
	INPUT_LANGUAGES_SOURCE=$REPOSITORY_ROOT/config/hyprland/.config/hypr
	INPUT_LANGUAGES_PLUGIN_SOURCE=$REPOSITORY_ROOT/plugins/input-languages
	INPUT_LANGUAGES_WIDGET_SOURCE=$INPUT_LANGUAGES_PLUGIN_SOURCE/widget/$INPUT_LANGUAGES_WIDGET
	INPUT_LANGUAGES_DATA=$INPUT_LANGUAGES_DATA_HOME/dotfiles/input-languages
	INPUT_LANGUAGES_ARTIFACTS=$INPUT_LANGUAGES_DATA/plugins
	INPUT_LANGUAGES_POINTER=$INPUT_LANGUAGES_DATA/active-artifact.lua
	INPUT_LANGUAGES_STATE=$INPUT_LANGUAGES_STATE_HOME/dotfiles/input-languages
	INPUT_LANGUAGES_ACTIVE=$INPUT_LANGUAGES_STATE/active.json
	INPUT_LANGUAGES_PENDING=$INPUT_LANGUAGES_STATE/pending.json
	INPUT_LANGUAGES_RECOVERY=$INPUT_LANGUAGES_STATE/recovery-required.json
	INPUT_LANGUAGES_CLEANUP=$INPUT_LANGUAGES_STATE/remove-cleanup.json
	INPUT_LANGUAGES_SHELL=$INPUT_LANGUAGES_CONFIG_HOME/omarchy/shell.json
	INPUT_LANGUAGES_PLUGIN_ROOT=$INPUT_LANGUAGES_CONFIG_HOME/omarchy/plugins
	INPUT_LANGUAGES_WIDGET_LIVE=$INPUT_LANGUAGES_PLUGIN_ROOT/$INPUT_LANGUAGES_WIDGET
}

input_languages_safe_absolute_path() {
	local path=$1
	[[ $path == /* && $path != *$'\n'* && $path != *$'\r'* && $path != *'"'* && $path != *"'"* && \
		$path != *'\\'* && $path != */../* && $path != */.. && $path != */./* && $path != */. ]]
}

input_languages_path_components_no_follow() {
	local path=$1 component='' part metadata uid mode
	local -a parts=()
	input_languages_safe_absolute_path "$path" || return 1
	IFS=/ read -r -a parts <<<"${path#/}"
	for part in "${parts[@]}"; do
		[[ -n $part ]] || continue
		component+=/$part
		if [[ -L $component ]]; then
			return 1
		fi
		if [[ -e $component ]]; then
			[[ -d $component ]] || return 1
			metadata=$(stat -c '%u|%a' -- "$component") || return 1
			IFS='|' read -r uid mode <<<"$metadata"
			if [[ $component == /tmp && $uid == 0 && $mode == 1777 ]]; then continue; fi
			[[ $uid == 0 || $uid == "$EUID" ]] || return 1
			(( (8#$mode & 022) == 0 )) || return 1
		else
			break
		fi
	done
}

input_languages_owned_directory_safe() {
	local path=$1 metadata
	[[ -e $path || -L $path ]] || return 0
	[[ -d $path && ! -L $path ]] || return 1
	metadata=$(stat -c '%u|%a' -- "$path") || return 1
	[[ $metadata == "$EUID|700" ]]
}

input_languages_paths_are_safe() {
	local canonical_home canonical_config path
	for path in "$HOME" "$INPUT_LANGUAGES_CONFIG_HOME" "$INPUT_LANGUAGES_DATA_HOME" "$INPUT_LANGUAGES_STATE_HOME"; do
		if ! input_languages_safe_absolute_path "$path"; then
			printf 'Conflict: Input Languages requires canonical absolute HOME and XDG paths: %s\n' "$path" >&2
			return 1
		fi
	done
	canonical_home=$(readlink -m -- "$HOME") || return 1
	canonical_config=$(readlink -m -- "$INPUT_LANGUAGES_CONFIG_HOME") || return 1
	if [[ $canonical_config != "$canonical_home/.config" || $INPUT_LANGUAGES_CONFIG_HOME != "$HOME/.config" ]]; then
		printf 'Conflict: XDG_CONFIG_HOME must be the canonical Stow target %s; detected %s.\n' "$HOME/.config" "$INPUT_LANGUAGES_CONFIG_HOME" >&2
		return 1
	fi
	for path in "$HOME" "$INPUT_LANGUAGES_CONFIG_HOME" "$INPUT_LANGUAGES_DATA_HOME" "$INPUT_LANGUAGES_STATE_HOME" \
		"$INPUT_LANGUAGES_DATA" "$INPUT_LANGUAGES_ARTIFACTS" "$INPUT_LANGUAGES_STATE" "$INPUT_LANGUAGES_SOURCE" "$INPUT_LANGUAGES_PLUGIN_SOURCE" \
		"$INPUT_LANGUAGES_WIDGET_SOURCE" "$INPUT_LANGUAGES_PLUGIN_ROOT" "$INPUT_LANGUAGES_DATA/removals" \
		"$INPUT_LANGUAGES_STATE/backups" "$INPUT_LANGUAGES_STATE/diagnostics" "$INPUT_LANGUAGES_STATE/archive"; do
		if ! input_languages_path_components_no_follow "$path"; then
			printf 'Conflict: Input Languages path has a symbolic-link or non-directory component: %s\n' "$path" >&2
			return 1
		fi
	done
	for path in "$INPUT_LANGUAGES_DATA" "$INPUT_LANGUAGES_ARTIFACTS" "$INPUT_LANGUAGES_DATA/removals" "$INPUT_LANGUAGES_STATE" \
		"$INPUT_LANGUAGES_STATE/backups" "$INPUT_LANGUAGES_STATE/diagnostics" "$INPUT_LANGUAGES_STATE/archive"; do
		if ! input_languages_owned_directory_safe "$path"; then
			printf 'Conflict: Input Languages managed roots must be invoking-user-owned real 0700 directories: %s\n' "$path" >&2
			return 1
		fi
	done
	[[ -d $INPUT_LANGUAGES_SOURCE && ! -L $INPUT_LANGUAGES_SOURCE && -d $INPUT_LANGUAGES_PLUGIN_SOURCE && ! -L $INPUT_LANGUAGES_PLUGIN_SOURCE && \
		-d $INPUT_LANGUAGES_WIDGET_SOURCE && ! -L $INPUT_LANGUAGES_WIDGET_SOURCE ]] || {
		printf 'Conflict: Input Languages repository source roots must be real directories.\n' >&2
		return 1
	}
}

input_languages_prepare_roots() {
	local path
	for path in "$INPUT_LANGUAGES_DATA" "$INPUT_LANGUAGES_ARTIFACTS" "$INPUT_LANGUAGES_DATA/removals" "$INPUT_LANGUAGES_STATE" \
		"$INPUT_LANGUAGES_STATE/backups" "$INPUT_LANGUAGES_STATE/diagnostics" "$INPUT_LANGUAGES_STATE/archive"; do
		input_languages_owned_directory_safe "$path" || return 1
		mkdir -p -m 0700 -- "$path" || return 1
		chmod 0700 -- "$path" || return 1
		input_languages_owned_directory_safe "$path" || return 1
	done
}

input_languages_detect_support() {
	if [[ -n ${DOTFILES_TEST_OMARCHY_VERSION-} ]]; then
		INPUT_LANGUAGES_VERSION=$DOTFILES_TEST_OMARCHY_VERSION
	else
		INPUT_LANGUAGES_VERSION=$(env -i HOME="$HOME" PATH=/usr/bin:/bin LC_ALL=C OMARCHY_PATH=/usr/share/omarchy \
			/usr/share/omarchy/bin/omarchy version 2>/dev/null || true)
	fi
	local numeric=${INPUT_LANGUAGES_VERSION%%-*}
	numeric=${numeric##* }
	INPUT_LANGUAGES_SUPPORTED=false
	if [[ $numeric =~ ^4([.][0-9]+){1,2}$ ]] && version_at_least "$numeric" "$INPUT_LANGUAGES_MIN_OMARCHY"; then
		INPUT_LANGUAGES_SUPPORTED=true
	fi
}

input_languages_report_mutation_compatibility() {
	[[ $INPUT_LANGUAGES_VERSION != unknown ]] || input_languages_detect_support
	[[ $INPUT_LANGUAGES_SUPPORTED == true ]] && return 0
	printf 'Compatibility notice: supported Omarchy %s through 4.x; detected %s. Receipt-backed recovery and Remove remain available when current inspection proves them safe.\n' \
		"$INPUT_LANGUAGES_MIN_OMARCHY" "$INPUT_LANGUAGES_VERSION"
}

input_languages_transaction_valid() {
	[[ $1 =~ ^[0-9]{8}T[0-9]{6}([.][0-9]+)?Z-[0-9]+-[0-9A-Fa-f]{4,8}$ ]]
}

input_languages_new_transaction() {
	printf '%s-%s-%04x%04x\n' "$(date -u +%Y%m%dT%H%M%S.%NZ)" "$$" "$RANDOM" "$RANDOM"
}

input_languages_file_metadata_safe() {
	local path=$1 mode=$2 metadata
	[[ -f $path && ! -L $path ]] || return 1
	metadata=$(stat -c '%u|%a' -- "$path") || return 1
	[[ $metadata == "$EUID|$mode" ]]
}

input_languages_exact_tree_inventory() {
	local root=$1 existed=$2 name entries
	[[ -d $root && ! -L $root ]] || return 1
	entries=$(find "$root" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort) || return 1
	if [[ $existed == false ]]; then
		[[ -z $entries ]]
		return
	fi
	[[ $existed == true ]] || return 1
	[[ $entries == "$(printf '%s\n' "${INPUT_LANGUAGES_FILES[@]}" | LC_ALL=C sort)" ]] || return 1
	for name in "${INPUT_LANGUAGES_FILES[@]}"; do
		[[ -f $root/$name && ! -L $root/$name ]] || return 1
	done
}

input_languages_tree_digest() {
	local root=$1 name digest metadata
	[[ -d $root && ! -L $root ]] || return 1
	{
		metadata=$(stat -c '%a|%u|%g|%Y' -- "$root") || return 1
		printf '.|%s\n' "$metadata"
		for name in "${INPUT_LANGUAGES_FILES[@]}"; do
			if [[ -f $root/$name && ! -L $root/$name ]]; then
				digest=$(sha256sum -- "$root/$name") || return 1
				metadata=$(stat -c '%a|%u|%g|%s|%Y' -- "$root/$name") || return 1
				printf '%s|%s|%s\n' "$name" "$metadata" "${digest%% *}"
			elif [[ ! -e $root/$name && ! -L $root/$name ]]; then
				printf '%s|absent\n' "$name"
			else
				return 1
			fi
		done
	} | sha256sum | cut -d' ' -f1
}

input_languages_backup_valid() {
	local backup=$1 transaction=$2 existed=$3 digest=$4 actual
	input_languages_transaction_valid "$transaction" || return 1
	[[ $backup == "$INPUT_LANGUAGES_STATE/backups/$transaction/tree" ]] || return 1
	input_languages_exact_tree_inventory "$backup" "$existed" || return 1
	actual=$(input_languages_tree_digest "$backup") || return 1
	[[ $actual == "$digest" ]]
}

input_languages_baseline_matches() {
	local name expected actual
	input_languages_exact_tree_inventory "$INPUT_LANGUAGES_LIVE" true || return 1
	for name in "${INPUT_LANGUAGES_FILES[@]}"; do
		expected=$(jq -r --arg name "$name" '.files[$name] // empty' "$INPUT_LANGUAGES_PLUGIN_SOURCE/migration-baseline.json") || return 1
		actual=$(sha256sum -- "$INPUT_LANGUAGES_LIVE/$name") || return 1
		[[ ${actual%% *} == "$expected" ]] || return 1
	done
}

input_languages_inspect_tree() {
	local name target source linked=0 regular=0 absent=0 unsafe=0 entries=0 source_real target_real
	for name in "${INPUT_LANGUAGES_FILES[@]}"; do
		target=$INPUT_LANGUAGES_LIVE/$name
		source=$INPUT_LANGUAGES_SOURCE/$name
		if [[ -L $target ]]; then
			target_real=$(readlink -f -- "$target" 2>/dev/null || true)
			source_real=$(readlink -f -- "$source" 2>/dev/null || true)
			if [[ -n $target_real && -n $source_real && $target_real == "$source_real" ]]; then linked=$((linked + 1)); else unsafe=$((unsafe + 1)); fi
		elif [[ -f $target ]]; then
			regular=$((regular + 1))
		elif [[ ! -e $target ]]; then
			absent=$((absent + 1))
		else
			unsafe=$((unsafe + 1))
		fi
	done
	if [[ -d $INPUT_LANGUAGES_LIVE && ! -L $INPUT_LANGUAGES_LIVE ]]; then
		entries=$(find "$INPUT_LANGUAGES_LIVE" -mindepth 1 -maxdepth 1 -printf . | wc -c) || { INPUT_LANGUAGES_TREE_STATE=conflict; return; }
	elif [[ -e $INPUT_LANGUAGES_LIVE || -L $INPUT_LANGUAGES_LIVE ]]; then
		unsafe=$((unsafe + 1))
	fi
	INPUT_LANGUAGES_TREE_STATE=conflict
	if ((unsafe > 0)); then
		return
	elif ((linked == ${#INPUT_LANGUAGES_FILES[@]} && entries == ${#INPUT_LANGUAGES_FILES[@]})); then
		INPUT_LANGUAGES_TREE_STATE=linked
	elif ((absent == ${#INPUT_LANGUAGES_FILES[@]} && entries == 0)); then
		INPUT_LANGUAGES_TREE_STATE=uninstalled
	elif ((regular == ${#INPUT_LANGUAGES_FILES[@]} && entries == ${#INPUT_LANGUAGES_FILES[@]})) && input_languages_baseline_matches; then
		INPUT_LANGUAGES_TREE_STATE=migratable
	fi
}

input_languages_widget_tree_valid() {
	local root=$1 directory_mode=$2 file_mode=$3 entries name metadata
	[[ -d $root && ! -L $root ]] || return 1
	metadata=$(stat -c '%u|%a' -- "$root") || return 1
	[[ $metadata == "$EUID|$directory_mode" ]] || return 1
	entries=$(find "$root" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort) || return 1
	[[ $entries == "$(printf '%s\n' "${INPUT_LANGUAGES_WIDGET_FILES[@]}" | LC_ALL=C sort)" ]] || return 1
	for name in "${INPUT_LANGUAGES_WIDGET_FILES[@]}"; do
		input_languages_file_metadata_safe "$root/$name" "$file_mode" || return 1
	done
	jq -e '
		(keys | sort) == (["schemaVersion","id","name","version","author","description","kinds","entryPoints","barWidget","omarchy"] | sort) and
		.schemaVersion == 1 and .id == "dotfiles.keyboard-layout" and .name == "Flag keyboard layout" and
		.version == "1.0.0" and .author == "Dotfiles" and
		.description == "Current US or Russian keyboard layout as a flag, click cycles" and
		.kinds == ["bar-widget"] and .entryPoints == {barWidget:"KeyboardLayout.qml"} and
		.barWidget == {displayName:"Flag keyboard layout",description:"Current US or Russian keyboard layout as a flag, click cycles",category:"Compositor",allowMultiple:false} and
		.omarchy == {clonedFrom:"omarchy.keyboard-layout"}
	' "$root/manifest.json" >/dev/null 2>&1
}

input_languages_widget_digest() {
	local root=$1 name digest
	{
		for name in "${INPUT_LANGUAGES_WIDGET_FILES[@]}"; do
			digest=$(sha256sum -- "$root/$name") || return 1
			printf '%s  %s\n' "${digest%% *}" "$name"
		done
	} | sha256sum | cut -d' ' -f1
}

input_languages_validate_artifact_values() {
	local artifact=$1 build=$2 source=$3 artifact_sha=$4 compatibility=$5 compiler=$6 dependencies=$7 widget_sha=$8
	local state=${9-immutable} directory metadata widget actual entries directory_metadata
	[[ $build =~ ^[0-9a-f]{64}$ && $source =~ ^[0-9a-f]{64}$ && $artifact_sha =~ ^[0-9a-f]{64}$ && $widget_sha =~ ^[0-9a-f]{64}$ && $compatibility != '' ]] || return 1
	directory=${artifact%/*}
	metadata=$directory/build.json
	widget=$directory/$INPUT_LANGUAGES_WIDGET
	input_languages_artifact_path_valid "$artifact" "$build" "$artifact_sha" || return 1
	[[ -d $directory && ! -L $directory ]] || return 1
	[[ -f $artifact && ! -L $artifact && -f $metadata && ! -L $metadata ]] || return 1
	entries=$(find "$directory" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort) || return 1
	[[ $entries == $'build.json\ndotfiles.keyboard-layout\ninput-languages.so' ]] || return 1
	directory_metadata=$(stat -c '%u|%a' -- "$directory") || return 1
	case $state in
		immutable) (( (8#${directory_metadata#*|} & 0222) == 0 )) || return 1 ;;
		cleanup) [[ $directory_metadata == "$EUID|500" || $directory_metadata == "$EUID|700" ]] || return 1 ;;
		*) return 2 ;;
	esac
	[[ $(stat -c %a -- "$artifact") == 555 && $(stat -c %a -- "$metadata") == 444 ]] || return 1
	input_languages_widget_tree_valid "$widget" 555 444 || return 1
	[[ $(input_languages_widget_digest "$widget") == "$widget_sha" ]] || return 1
	actual=$(sha256sum -- "$artifact") || return 1
	[[ ${actual%% *} == "$artifact_sha" ]] || return 1
	jq -e --arg build "$build" --arg source "$source" --arg compatibility "$compatibility" --arg compiler "$compiler" \
		--arg dependencies "$dependencies" --arg artifact_sha "$artifact_sha" --arg widget_sha "$widget_sha" '
		(keys | sort) == (["version","build_id","source_id","compatibility_hash","compiler","dependencies","artifact_sha256","widget_sha256","exports"] | sort) and
		.version == 1 and .build_id == $build and .source_id == $source and .compatibility_hash == $compatibility and
		.compiler == $compiler and .dependencies == $dependencies and .artifact_sha256 == $artifact_sha and .widget_sha256 == $widget_sha and
		.exports == ["pluginAPIVersion","pluginExit","pluginInit"]
	' "$metadata" >/dev/null 2>&1
}

input_languages_artifact_path_valid() {
	local artifact=$1 build=$2 artifact_sha=$3 directory prefix generation
	[[ $build =~ ^[0-9a-f]{64}$ && $artifact_sha =~ ^[0-9a-f]{64}$ ]] || return 1
	directory=${artifact%/*}
	[[ $artifact == "$directory/input-languages.so" ]] || return 1
	prefix=$INPUT_LANGUAGES_ARTIFACTS/$build-$artifact_sha-
	[[ $directory == "$prefix"* ]] || return 1
	generation=${directory#"$prefix"}
	input_languages_transaction_valid "$generation"
}

input_languages_artifact_stage_path() {
	local artifact=$1 transaction=$2 build=$3 artifact_sha=$4 directory
	input_languages_transaction_valid "$transaction" || return 1
	input_languages_artifact_path_valid "$artifact" "$build" "$artifact_sha" || return 1
	directory=${artifact%/*}
	printf '%s/removals/%s-%s\n' "$INPUT_LANGUAGES_DATA" "$transaction" "${directory##*/}"
}

input_languages_validate_artifact_binary() {
	local artifact=$1 build=$2 source=$3 compiler=$4 symbol output identity
	file "$artifact" | grep -F 'shared object' >/dev/null || return 1
	output=$(nm -D --defined-only "$artifact") || return 1
	for symbol in pluginAPIVersion pluginInit pluginExit; do
		grep -Eq "[[:space:]]$symbol$" <<<"$output" || return 1
	done
	for symbol in g_pInputManager g_pKeybindManager; do
		grep -Eq "[[:space:]][uV][[:space:]]$symbol$" <<<"$output" || return 1
	done
	identity=$(readelf -p .input_languages "$artifact" 2>/dev/null) || return 1
	grep -Fq "build_id=$build" <<<"$identity" || return 1
	grep -Fq "source_id=$source" <<<"$identity" || return 1
	grep -Fq "compiler=$compiler" <<<"$identity"
}

input_languages_validate_artifact_self() {
	local artifact=$1 state=${2-immutable} directory metadata build source artifact_sha compatibility compiler dependencies widget_sha
	directory=${artifact%/*}
	metadata=$directory/build.json
	[[ -f $metadata && ! -L $metadata ]] || return 1
	build=$(jq -r .build_id "$metadata") || return 1
	source=$(jq -r .source_id "$metadata") || return 1
	artifact_sha=$(jq -r .artifact_sha256 "$metadata") || return 1
	compatibility=$(jq -r .compatibility_hash "$metadata") || return 1
	compiler=$(jq -r .compiler "$metadata") || return 1
	dependencies=$(jq -r .dependencies "$metadata") || return 1
	widget_sha=$(jq -r .widget_sha256 "$metadata") || return 1
	input_languages_artifact_path_valid "$artifact" "$build" "$artifact_sha" || return 1
	input_languages_validate_artifact_values "$artifact" "$build" "$source" "$artifact_sha" "$compatibility" "$compiler" "$dependencies" "$widget_sha" "$state"
}

input_languages_validate_integration_artifact_binaries() {
	local root=$1 metadata=$1/build.json build source compiler compatibility integration protocol controller health unit
	local plugin=$root/input-languages.so helper=$root/input-languages-fcitx-helper output identity symbol binary_role binary
	build=$(jq -r .build_id "$metadata") || return 1
	source=$(jq -r .source_id "$metadata") || return 1
	compiler=$(jq -r .compiler "$metadata") || return 1
	compatibility=$(jq -r .compatibility_hash "$metadata") || return 1
	integration=$(jq -r .integration "$metadata") || return 1
	protocol=$(jq -r .protocol_identity "$metadata") || return 1
	controller=$(jq -r .controller_identity "$metadata") || return 1
	health=$(jq -r .health_identity "$metadata") || return 1
	unit=$(jq -r .unit_identity "$metadata") || return 1
	file "$plugin" | grep -F 'shared object' >/dev/null || return 1
	file "$helper" | grep -F 'ELF' | grep -F 'executable' >/dev/null || return 1
	output=$(nm -D --defined-only "$plugin") || return 1
	for symbol in pluginAPIVersion pluginInit pluginExit; do
		grep -Eq "[[:space:]]$symbol$" <<<"$output" || return 1
	done
	for symbol in g_pInputManager g_pKeybindManager; do
		grep -Eq "[[:space:]][uV][[:space:]]$symbol$" <<<"$output" || return 1
	done
	nm -D -C "$plugin" | grep -F 'InputLanguages::Fcitx::FcitxFollower' >/dev/null || return 1
	identity=$(readelf -p .input_languages "$plugin" 2>/dev/null) || return 1
	grep -Fq "build_id=$build" <<<"$identity" && grep -Fq "source_id=$source" <<<"$identity" && grep -Fq "compiler=$compiler" <<<"$identity" || return 1
	for binary_role in plugin helper; do
		if [[ $binary_role == plugin ]]; then binary=$plugin; else binary=$helper; fi
		identity=$(readelf -p .input_languages_integration "$binary" 2>/dev/null) || return 1
		grep -Fq "role=$binary_role" <<<"$identity" && grep -Fq "integration=$integration" <<<"$identity" &&
			grep -Fq "build_id=$build" <<<"$identity" && grep -Fq "source_id=$source" <<<"$identity" &&
			grep -Fq "compiler=$compiler" <<<"$identity" && grep -Fq "compatibility=$compatibility" <<<"$identity" && grep -Fq "protocol=$protocol" <<<"$identity" &&
			grep -Fq "controller=$controller" <<<"$identity" && grep -Fq "health=$health" <<<"$identity" && grep -Fq "unit=$unit" <<<"$identity" || return 1
	done
	output=$(readelf -d "$helper") || return 1
	grep -Eq 'NEEDED.*libsystemd[.]so' <<<"$output" && grep -Eq 'NEEDED.*libcrypto[.]so' <<<"$output" || return 1
	! grep -Eq 'NEEDED.*(Fcitx|fcitx)' <<<"$output" || return 1
	output=$(readelf -d "$plugin") || return 1
	! grep -Eq 'NEEDED.*(Fcitx|fcitx|libsystemd|libcrypto)' <<<"$output"
}

input_languages_validate_integration_artifact_values() {
	local root=$1 expected_artifact_dir=${2:-$1} verify_unit_syntax=${3:-true}
	local metadata=$root/build.json source build compatibility compiler linker dependencies plugin_sha helper_sha widget_sha contracts_sha units_sha unit_build_identity
	local integration protocol controller health unit actual expected frozen inventory source_inventory source_paths expected_build expected_publication path source_digest service_template_sha
	[[ -d $root && ! -L $root ]] || return 1
	(( (8#$(stat -c %a -- "$root") & 0222) == 0 )) || return 1
	inventory=$(input_languages_integration_inventory "$root") || return 1
	input_languages_file_metadata_safe "$metadata" 444 || return 1
	source=$(jq -r .source_id "$metadata") || return 1
	build=$(jq -r .build_id "$metadata") || return 1
	compatibility=$(jq -r .compatibility_hash "$metadata") || return 1
	compiler=$(jq -r .compiler "$metadata") || return 1
	linker=$(jq -r .linker "$metadata") || return 1
	dependencies=$(jq -r .dependencies "$metadata") || return 1
	plugin_sha=$(jq -r .artifact_sha256 "$metadata") || return 1
	helper_sha=$(jq -r .helper_sha256 "$metadata") || return 1
	widget_sha=$(jq -r .widget_sha256 "$metadata") || return 1
	contracts_sha=$(jq -r .contracts_sha256 "$metadata") || return 1
	units_sha=$(jq -r .units_sha256 "$metadata") || return 1
	unit_build_identity=$(jq -r .unit_build_identity "$metadata") || return 1
	integration=$(jq -r .integration "$metadata") || return 1
	protocol=$(jq -r .protocol_identity "$metadata") || return 1
	controller=$(jq -r .controller_identity "$metadata") || return 1
	health=$(jq -r .health_identity "$metadata") || return 1
	unit=$(jq -r .unit_identity "$metadata") || return 1
	[[ $source =~ ^[0-9a-f]{64}$ && $build =~ ^[0-9a-f]{64}$ && $plugin_sha =~ ^[0-9a-f]{64}$ && $helper_sha =~ ^[0-9a-f]{64}$ &&
		$widget_sha =~ ^[0-9a-f]{64}$ && $contracts_sha =~ ^[0-9a-f]{64}$ && $units_sha =~ ^[0-9a-f]{64}$ &&
		$unit_build_identity =~ ^[0-9a-f]{64}$ && -n $compatibility && -n $compiler && -n $linker ]] || return 1
	source_inventory=$(jq -r '.source_inventory[]' "$metadata") || return 1
	source_paths=$(awk '{ print $2 }' <<<"$source_inventory") || return 1
	[[ $source_paths == "$(input_languages_integration_expected_source_paths)" ]] || return 1
	source_digest=$(printf '%s\n' "$source_inventory" | sha256sum | cut -d' ' -f1) || return 1
	[[ $source_digest == "$source" ]] || return 1
	expected=$(input_languages_integration_unit_build_identity "$source_inventory") || return 1
	[[ $expected == "$unit_build_identity" ]] || return 1
	expected_publication=$(input_languages_integration_build_identity "$source" "$compiler" "$linker" "$compatibility" "$dependencies" "$unit_build_identity") || return 1
	[[ ${expected_artifact_dir##*/} == "integration-$expected_publication" ]] || return 1
	expected_build=$(input_languages_integration_build_identity "$source" "$compiler" "$linker" "$compatibility" "$dependencies" "$units_sha") || return 1
	[[ $expected_build == "$build" ]] || return 1
	jq -e --arg inventory "$inventory" --arg plugin_flags "$INPUT_LANGUAGES_INTEGRATION_PLUGIN_FLAGS" \
		--arg helper_flags "$INPUT_LANGUAGES_INTEGRATION_HELPER_FLAGS" '
		(keys | sort) == (["version","integration","source_id","build_id","compatibility_hash","compiler","linker","dependencies","plugin_flags","helper_flags","artifact_sha256","helper_sha256","widget_sha256","contracts_sha256","units_sha256","unit_build_identity","protocol_identity","controller_identity","health_identity","unit_identity","source_inventory","inventory","exports"] | sort) and
		.version == 1 and .plugin_flags == $plugin_flags and .helper_flags == $helper_flags and
		.exports == ["pluginAPIVersion","pluginExit","pluginInit"] and .inventory == ($inventory | split("\n")) and
		(.source_inventory | type == "array" and length > 0 and all(.[]; test("^[0-9a-f]{64}  (plugin|contracts|systemd|widget|config)/")))
	' "$metadata" >/dev/null || return 1
	actual=$(sha256sum -- "$root/input-languages.so") || return 1; [[ ${actual%% *} == "$plugin_sha" ]] || return 1
	actual=$(sha256sum -- "$root/input-languages-fcitx-helper") || return 1; [[ ${actual%% *} == "$helper_sha" ]] || return 1
	[[ $(input_languages_widget_digest "$root/$INPUT_LANGUAGES_WIDGET") == "$widget_sha" ]] || return 1
	[[ $(input_languages_integration_contract_digest "$root/contracts") == "$contracts_sha" ]] || return 1
	[[ $(input_languages_integration_unit_digest "$root/systemd") == "$units_sha" ]] || return 1
	for path in "${INPUT_LANGUAGES_INTEGRATION_CONTRACT_FILES[@]}"; do
		expected=$(awk -v wanted="contracts/$path" '$2 == wanted { print $1 }' <<<"$source_inventory")
		actual=$(sha256sum -- "$root/contracts/$path") || return 1
		frozen=$(input_languages_integration_contract_expected_digest "$path") || return 1
		[[ -n $expected && ${actual%% *} == "$expected" && ${actual%% *} == "$frozen" ]] || return 1
	done
	for path in "${INPUT_LANGUAGES_WIDGET_FILES[@]}"; do
		expected=$(awk -v wanted="widget/$path" '$2 == wanted { print $1 }' <<<"$source_inventory")
		actual=$(sha256sum -- "$root/$INPUT_LANGUAGES_WIDGET/$path") || return 1
		[[ -n $expected && ${actual%% *} == "$expected" ]] || return 1
	done
	expected=$(awk '$2 == "systemd/dotfiles-input-languages-fcitx.socket" { print $1 }' <<<"$source_inventory")
	actual=$(sha256sum -- "$root/systemd/dotfiles-input-languages-fcitx.socket") || return 1
	[[ -n $expected && ${actual%% *} == "$expected" ]] || return 1
	expected=$(awk '$2 == "systemd/dotfiles-input-languages-fcitx.service" { print $1 }' <<<"$source_inventory")
	service_template_sha=$(input_languages_integration_service_template_digest "$root/systemd/dotfiles-input-languages-fcitx.service" "$expected_artifact_dir") || return 1
	[[ -n $expected && $service_template_sha == "$expected" ]] || return 1
	[[ $(jq -r .integration "$root/contracts/manifest.json") == "$integration" &&
		$(jq -r .identity "$root/contracts/protocol.json") == "$protocol" &&
		$(jq -r .identity "$root/contracts/fcitx.json") == "$controller" &&
		$(jq -r .identity "$root/contracts/health.json") == "$health" &&
		$(jq -r .identity "$root/contracts/systemd.json") == "$unit" &&
		$(jq -r .protocol "$root/contracts/health.json") == "$protocol" &&
		$(jq -r .protocol "$root/contracts/systemd.json") == "$protocol" ]] || return 1
	jq -e '
		.compatibility.upstream_version == "5.1.21" and .compatibility.transport_library == "libsystemd" and
		.compatibility.bus_api == "sd-bus" and .compatibility.event_api == "sd-event" and .compatibility.fcitx_cpp_abi_linkage == false and
		.controller.well_known_name == "org.fcitx.Fcitx5" and .controller.object_path == "/controller" and
		.controller.interface == "org.fcitx.Fcitx.Controller1" and .controller.activation == "no-auto-start" and
		.controller.addressing == "unique-owner" and
		.controller.members == {
			AddInputMethodGroup:{type:"method",input:"s",output:""}, AvailableInputMethods:{type:"method",input:"",output:"a(ssssssb)"},
			CurrentInputMethod:{type:"method",input:"",output:"s"}, CurrentInputMethodGroup:{type:"method",input:"",output:"s"},
			DebugInfo:{type:"method",input:"",output:"s"}, FullInputMethodGroupInfo:{type:"method",input:"s",output:"sssa{sv}a(sssssssbsa{sv})"},
			GetAddonsV2:{type:"method",input:"",output:"a(sssibbbasas)"}, InputMethodGroupInfo:{type:"method",input:"s",output:"sa(ss)"},
			InputMethodGroups:{type:"method",input:"",output:"as"}, InputMethodGroupsChanged:{type:"signal",input:"",output:""},
			RemoveInputMethodGroup:{type:"method",input:"s",output:""}, Save:{type:"method",input:"",output:""},
			SetCurrentIM:{type:"method",input:"s",output:""}, SetInputMethodGroupInfo:{type:"method",input:"ssa(ss)",output:""},
			SwitchInputMethodGroup:{type:"method",input:"s",output:""}
		} and
		.managed_group == {name:"Dotfiles Input Languages",default_layout:"us",default_im_allowed:["","keyboard-us","keyboard-ru"],items:[{method:"keyboard-us",layout_override:""},{method:"keyboard-ru",layout_override:""}],existing_name_policy:"collision",mutation_seam:"Controller1-followed-by-Save"}
	' "$root/contracts/fcitx.json" >/dev/null || return 1
	jq -e '
		.socket == {unit:"dotfiles-input-languages-fcitx.socket",listen_sequential_packet:"%t/dotfiles-input-languages/fcitx.sock",directory_mode:"0700",socket_mode:"0600",remove_on_stop:true,wanted_by:"graphical-session.target",enabled:true,started:true} and
		.service == {unit:"dotfiles-input-languages-fcitx.service",exec_start:"@ARTIFACT_DIR@/input-languages-fcitx-helper",restart:"on-failure",restart_seconds:2,start_limit_interval_seconds:30,start_limit_burst:5,socket_activated:true,starts_or_restarts_fcitx:false}
	' "$root/contracts/systemd.json" >/dev/null || return 1
	expected=$(input_languages_systemd_exec_path "$expected_artifact_dir") || return 1
	grep -Fxc "ExecStart=:\"$expected/input-languages-fcitx-helper\"" "$root/systemd/dotfiles-input-languages-fcitx.service" >/dev/null || return 1
	! grep -Fq '@ARTIFACT_DIR@' "$root/systemd/dotfiles-input-languages-fcitx.service" || return 1
	input_languages_validate_integration_artifact_binaries "$root" || return 1
	if [[ $verify_unit_syntax == true ]]; then
		input_languages_verify_integration_units "$root" || return 1
	elif [[ $verify_unit_syntax != false ]]; then
		return 2
	fi
}

input_languages_validate_integration_artifact_self() {
	input_languages_validate_integration_artifact_values "$1" "$1" true
}

input_languages_validate_active_evidence_file() {
	local file=$1 transaction backup_transaction backup backup_digest backup_existed artifact build source artifact_sha compatibility compiler dependencies widget_source
	input_languages_file_metadata_safe "$file" 600 || return 1
	jq -e '
		(keys | sort) == (["version","operation","transaction_id","backup_transaction_id","source_id","build_id","artifact","artifact_sha256","widget_sha256","compatibility_hash","compiler","compiler_warning","dependencies","backup","backup_digest","backup_existed","widget_source","widget_section","widget_index","widget_entry","prior_stock_present","prior_stock_section","prior_stock_index","prior_stock_entry"] | sort) and
		.version == 2 and .operation == "active" and
		([.transaction_id,.backup_transaction_id,.source_id,.build_id,.artifact,.artifact_sha256,.widget_sha256,.compatibility_hash,.compiler,.dependencies,.backup,.backup_digest,.widget_source] | all(type == "string" and length > 0)) and
		(.compiler_warning | type == "string") and (.backup_existed | type == "boolean") and
		(.widget_section | IN("left","center","right")) and (.widget_index | type == "number" and . >= 0 and floor == .) and
		(.widget_entry | type == "object" and .id == "dotfiles.keyboard-layout") and (.prior_stock_present | type == "boolean") and
		(if .prior_stock_present then (.prior_stock_section | IN("left","center","right")) and (.prior_stock_index | type == "number" and . >= 0 and floor == .) and
			(.prior_stock_entry | type == "object" and .id == "omarchy.keyboard-layout")
		 else .prior_stock_section == null and .prior_stock_index == null and .prior_stock_entry == null end)
	' "$file" >/dev/null 2>&1 || return 1
	transaction=$(jq -r .transaction_id "$file")
	backup_transaction=$(jq -r .backup_transaction_id "$file")
	backup=$(jq -r .backup "$file")
	backup_digest=$(jq -r .backup_digest "$file")
	backup_existed=$(jq -r .backup_existed "$file")
	artifact=$(jq -r .artifact "$file")
	build=$(jq -r .build_id "$file")
	source=$(jq -r .source_id "$file")
	artifact_sha=$(jq -r .artifact_sha256 "$file")
	compatibility=$(jq -r .compatibility_hash "$file")
	compiler=$(jq -r .compiler "$file")
	dependencies=$(jq -r .dependencies "$file")
	widget_source=$(jq -r .widget_source "$file")
	input_languages_transaction_valid "$transaction" && input_languages_backup_valid "$backup" "$backup_transaction" "$backup_existed" "$backup_digest" && \
		[[ $source =~ ^[0-9a-f]{64}$ && $widget_source == "${artifact%/*}/$INPUT_LANGUAGES_WIDGET" ]] && input_languages_artifact_path_valid "$artifact" "$build" "$artifact_sha"
}

input_languages_validate_active_file() {
	local file=$1 artifact build source artifact_sha compatibility compiler dependencies widget_sha
	input_languages_validate_active_evidence_file "$file" || return 1
	artifact=$(jq -r .artifact "$file")
	build=$(jq -r .build_id "$file")
	source=$(jq -r .source_id "$file")
	artifact_sha=$(jq -r .artifact_sha256 "$file")
	compatibility=$(jq -r .compatibility_hash "$file")
	compiler=$(jq -r .compiler "$file")
	dependencies=$(jq -r .dependencies "$file")
	widget_sha=$(jq -r .widget_sha256 "$file")
	input_languages_validate_artifact_values "$artifact" "$build" "$source" "$artifact_sha" "$compatibility" "$compiler" "$dependencies" "$widget_sha"
}

input_languages_validate_pending_file() {
	local file=$1 transaction backup_transaction backup backup_digest backup_existed artifact prior_active prior_pointer prior_digest pointer_digest
	input_languages_file_metadata_safe "$file" 600 || return 1
	jq -e '
		(keys | sort) == (["version","operation","transaction_id","phase","backup_transaction_id","backup","backup_digest","backup_existed","artifact","prior_tree","prior_active","prior_active_digest","prior_pointer","prior_pointer_digest","prior_group","prior_autoreload","prior_widget_present","prior_widget_section","prior_widget_index","prior_widget_entry","prior_widget_link","widget_action","widget_mutated","widget_section","widget_index","widget_entry","link_mutated"] | sort) and
		.version == 2 and (.operation == "apply" or .operation == "remove") and
		(.transaction_id | type == "string" and length > 0) and
		(.phase | IN("prepared","pointer-changed","tree-changed","link-changed","widget-changed","shell-reloaded","reloaded","active-published")) and
		([.backup_transaction_id,.backup,.backup_digest,.artifact] | all(type == "string" and length > 0)) and
		(.backup_existed | type == "boolean") and (.prior_tree | IN("linked","migratable","uninstalled")) and
		(.prior_active == null or (.prior_active | type == "string" and length > 0)) and
		(.prior_active_digest == null or (.prior_active_digest | type == "string" and test("^[0-9a-f]{64}$"))) and
		(.prior_pointer == null or (.prior_pointer | type == "string" and length > 0)) and
		(.prior_pointer_digest == null or (.prior_pointer_digest | type == "string" and test("^[0-9a-f]{64}$"))) and
		(.prior_group == null or .prior_group == 0 or .prior_group == 1) and (.prior_autoreload | type == "boolean") and (.prior_widget_present | type == "boolean") and
		(if .prior_widget_present then (.prior_widget_section | IN("left","center","right")) and (.prior_widget_index | type == "number" and . >= 0 and floor == .) and (.prior_widget_entry | type == "object" and (.id == "omarchy.keyboard-layout" or .id == "dotfiles.keyboard-layout"))
		 else .prior_widget_section == null and .prior_widget_index == null and .prior_widget_entry == null end) and
		(.prior_widget_link == null or (.prior_widget_link | type == "string" and startswith("/"))) and
		(.widget_action | IN("none","activate","deactivate")) and (.widget_mutated | type == "boolean") and (.link_mutated | type == "boolean") and
		(if .widget_mutated then (.widget_section | IN("left","center","right")) and (.widget_index | type == "number" and . >= 0 and floor == .) and (.widget_entry | type == "object" and .id == "dotfiles.keyboard-layout")
		 else .widget_section == null and .widget_index == null and .widget_entry == null end) and
		(if .operation == "remove" then .prior_tree == "linked" and .widget_action == "deactivate" and .prior_widget_present and .prior_widget_entry.id == "dotfiles.keyboard-layout" and .prior_widget_link != null
		 elif .prior_tree == "linked" then .widget_action == "none" and .prior_widget_present and .prior_widget_entry.id == "dotfiles.keyboard-layout"
		 else .widget_action == "activate" and ((.prior_widget_present and .prior_widget_entry.id == "omarchy.keyboard-layout") or (.prior_widget_present | not)) end) and
		(if .prior_tree == "linked" then .prior_active != null and .prior_active_digest != null and .prior_pointer != null and .prior_pointer_digest != null
		 else .prior_active == null and .prior_active_digest == null and .prior_pointer == null and .prior_pointer_digest == null and .prior_widget_link == null end)
	' "$file" >/dev/null 2>&1 || return 1
	transaction=$(jq -r .transaction_id "$file")
	backup_transaction=$(jq -r .backup_transaction_id "$file")
	backup=$(jq -r .backup "$file")
	backup_digest=$(jq -r .backup_digest "$file")
	backup_existed=$(jq -r .backup_existed "$file")
	artifact=$(jq -r .artifact "$file")
	input_languages_transaction_valid "$transaction" || return 1
	input_languages_validate_artifact_self "$artifact" || return 1
	input_languages_backup_valid "$backup" "$backup_transaction" "$backup_existed" "$backup_digest" || return 1
	prior_active=$(jq -r '.prior_active // empty' "$file")
	prior_digest=$(jq -r '.prior_active_digest // empty' "$file")
	prior_pointer=$(jq -r '.prior_pointer // empty' "$file")
	pointer_digest=$(jq -r '.prior_pointer_digest // empty' "$file")
	if [[ -n $prior_active ]]; then
		[[ $prior_active == "$INPUT_LANGUAGES_STATE/backups/$transaction/prior-active.json" ]] || return 1
		input_languages_validate_active_evidence_file "$prior_active" || return 1
		[[ $(sha256sum -- "$prior_active" | cut -d' ' -f1) == "$prior_digest" ]] || return 1
		[[ $prior_pointer == "$INPUT_LANGUAGES_STATE/backups/$transaction/prior-pointer.lua" ]] || return 1
		input_languages_file_metadata_safe "$prior_pointer" 600 || return 1
		[[ $(sha256sum -- "$prior_pointer" | cut -d' ' -f1) == "$pointer_digest" ]] || return 1
		if [[ $(jq -r '.prior_widget_link // empty' "$file") != '' ]]; then
			[[ $(jq -r .prior_widget_link "$file") == "$(jq -r .widget_source "$prior_active")" ]] || return 1
		fi
	else
		[[ -z $prior_pointer && -z $pointer_digest && -z $prior_digest ]]
	fi
}

input_languages_validate_recovery_file() {
	local file=$1 transaction pending
	input_languages_file_metadata_safe "$file" 600 || return 1
	jq -e '
		(keys | sort) == (["version","state","transaction_id","failed_phase","pending"] | sort) and
		.version == 2 and .state == "recovery-required" and
		([.transaction_id,.failed_phase,.pending] | all(type == "string" and length > 0))
	' "$file" >/dev/null 2>&1 || return 1
	transaction=$(jq -r .transaction_id "$file")
	pending=$(jq -r .pending "$file")
	input_languages_transaction_valid "$transaction" && [[ $pending == "$INPUT_LANGUAGES_PENDING" ]] && \
		input_languages_validate_pending_file "$pending" && [[ $(jq -r .transaction_id "$pending") == "$transaction" ]]
}

input_languages_staged_artifact_safe() {
	local stage=$1 build=$2 expected_sha=$3 entry actual metadata widget_mode
	[[ -d $stage && ! -L $stage ]] || return 1
	metadata=$(stat -c '%u|%a' -- "$stage") || return 1
	[[ $metadata == "$EUID|500" || $metadata == "$EUID|700" ]] || return 1
	while IFS= read -r entry; do
		[[ $entry == build.json || $entry == input-languages.so || $entry == "$INPUT_LANGUAGES_WIDGET" ]] || return 1
	done < <(find "$stage" -mindepth 1 -maxdepth 1 -printf '%f\n')
	if [[ -e $stage/input-languages.so || -L $stage/input-languages.so ]]; then
		[[ -f $stage/input-languages.so && ! -L $stage/input-languages.so ]] || return 1
		actual=$(sha256sum -- "$stage/input-languages.so") || return 1
		[[ ${actual%% *} == "$expected_sha" ]] || return 1
	fi
	if [[ -e $stage/build.json || -L $stage/build.json ]]; then
		[[ -f $stage/build.json && ! -L $stage/build.json ]] || return 1
		jq -e --arg build "$build" --arg sha "$expected_sha" '.build_id == $build and .artifact_sha256 == $sha' "$stage/build.json" >/dev/null 2>&1 || return 1
	fi
	if [[ -e $stage/$INPUT_LANGUAGES_WIDGET || -L $stage/$INPUT_LANGUAGES_WIDGET ]]; then
		[[ -d $stage/$INPUT_LANGUAGES_WIDGET && ! -L $stage/$INPUT_LANGUAGES_WIDGET ]] || return 1
		widget_mode=$(stat -c %a -- "$stage/$INPUT_LANGUAGES_WIDGET") || return 1
		[[ $widget_mode == 555 || $widget_mode == 755 ]] || return 1
		while IFS= read -r entry; do
			case $entry in
				KeyboardLayout.qml|KeyboardLayoutModel.js|manifest.json)
					input_languages_file_metadata_safe "$stage/$INPUT_LANGUAGES_WIDGET/$entry" 444 || return 1
					;;
				*) return 1 ;;
			esac
		done < <(find "$stage/$INPUT_LANGUAGES_WIDGET" -mindepth 1 -maxdepth 1 -printf '%f\n')
	fi
}

input_languages_validate_cleanup_file() {
	local file=$1 transaction archive active_digest pending_digest artifact build artifact_sha stage actual
	input_languages_file_metadata_safe "$file" 600 || return 1
	jq -e '
		(keys | sort) == (["version","state","transaction_id","archive","archive_active_digest","archive_pending_digest","artifact","build_id","artifact_sha256"] | sort) and
		.version == 2 and .state == "remove-cleanup" and
		([.transaction_id,.archive,.artifact,.build_id,.artifact_sha256,.archive_active_digest,.archive_pending_digest] | all(type == "string" and length > 0)) and
		(.build_id | test("^[0-9a-f]{64}$")) and (.artifact_sha256 | test("^[0-9a-f]{64}$")) and
		(.archive_active_digest | test("^[0-9a-f]{64}$")) and (.archive_pending_digest | test("^[0-9a-f]{64}$"))
	' "$file" >/dev/null 2>&1 || return 1
	transaction=$(jq -r .transaction_id "$file")
	archive=$(jq -r .archive "$file")
	active_digest=$(jq -r .archive_active_digest "$file")
	pending_digest=$(jq -r .archive_pending_digest "$file")
	artifact=$(jq -r .artifact "$file")
	build=$(jq -r .build_id "$file")
	artifact_sha=$(jq -r .artifact_sha256 "$file")
	input_languages_transaction_valid "$transaction" || return 1
	[[ $archive == "$INPUT_LANGUAGES_STATE/archive/$transaction-remove" ]] || return 1
	input_languages_owned_directory_safe "$archive" || return 1
	[[ $(find "$archive" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort) == $'active.json\npending.json' ]] || return 1
	input_languages_file_metadata_safe "$archive/active.json" 600 || return 1
	input_languages_file_metadata_safe "$archive/pending.json" 600 || return 1
	actual=$(sha256sum -- "$archive/active.json"); [[ ${actual%% *} == "$active_digest" ]] || return 1
	actual=$(sha256sum -- "$archive/pending.json"); [[ ${actual%% *} == "$pending_digest" ]] || return 1
	jq -e --arg artifact "$artifact" --arg build "$build" --arg sha "$artifact_sha" '.artifact == $artifact and .build_id == $build and .artifact_sha256 == $sha' "$archive/active.json" >/dev/null 2>&1 || return 1
	jq -e --arg transaction "$transaction" --arg artifact "$artifact" '.operation == "remove" and .transaction_id == $transaction and .artifact == $artifact' "$archive/pending.json" >/dev/null 2>&1 || return 1
	stage=$(input_languages_artifact_stage_path "$artifact" "$transaction" "$build" "$artifact_sha") || return 1
	[[ ! ( ( -e $artifact || -L $artifact ) && ( -e $stage || -L $stage ) ) ]] || return 1
	if [[ -e $artifact || -L $artifact ]]; then
		input_languages_validate_artifact_self "$artifact" cleanup
	elif [[ -e $stage || -L $stage ]]; then
		input_languages_staged_artifact_safe "$stage" "$build" "$artifact_sha"
	fi
}

input_languages_classify_evidence() {
	local path=$1 validator=$2 result_name=$3 result=absent
	if [[ -e $path || -L $path ]]; then
		result=invalid
		if "$validator" "$path"; then result=valid; fi
	fi
	printf -v "$result_name" '%s' "$result"
}

input_languages_validate_active_receipt() {
	INPUT_LANGUAGES_ACTIVE_VALID=false
	input_languages_classify_evidence "$INPUT_LANGUAGES_ACTIVE" input_languages_validate_active_evidence_file INPUT_LANGUAGES_ACTIVE_STATE
	[[ $INPUT_LANGUAGES_ACTIVE_STATE != valid ]] || INPUT_LANGUAGES_ACTIVE_VALID=true
}

input_languages_inspect_widget() {
	local source custom stock weather candidate manifest cloned expected
	INPUT_LANGUAGES_WIDGET_PRESENT=false
	INPUT_LANGUAGES_WIDGET_COUNT=0
	INPUT_LANGUAGES_WIDGET_SECTION=''
	INPUT_LANGUAGES_WIDGET_INDEX=''
	INPUT_LANGUAGES_WIDGET_ENTRY=null
	INPUT_LANGUAGES_STOCK_WIDGET_PRESENT=false
	INPUT_LANGUAGES_STOCK_WIDGET_COUNT=0
	INPUT_LANGUAGES_STOCK_WIDGET_SECTION=''
	INPUT_LANGUAGES_STOCK_WIDGET_INDEX=''
	INPUT_LANGUAGES_STOCK_WIDGET_ENTRY=null
	INPUT_LANGUAGES_WEATHER_COUNT=0
	INPUT_LANGUAGES_WEATHER_SECTION=''
	INPUT_LANGUAGES_WEATHER_INDEX=''
	INPUT_LANGUAGES_WIDGET_LINK_STATE=absent
	INPUT_LANGUAGES_WIDGET_LINK_TARGET=''
	INPUT_LANGUAGES_COMPETING_CLONES=''
	INPUT_LANGUAGES_WIDGET_STATE=invalid
	if [[ -e $INPUT_LANGUAGES_SHELL || -L $INPUT_LANGUAGES_SHELL ]]; then
		[[ -f $INPUT_LANGUAGES_SHELL && ! -L $INPUT_LANGUAGES_SHELL ]] || return 0
	fi
	if [[ -s $INPUT_LANGUAGES_SHELL ]]; then source=$INPUT_LANGUAGES_SHELL; else source=/usr/share/omarchy/config/omarchy/shell.json; fi
	[[ -f $source && ! -L $source ]] || return 0
	jq -e '.version == 1 and (.bar.layout | type == "object") and ([.bar.layout.left,.bar.layout.center,.bar.layout.right] | all(type == "array"))' "$source" >/dev/null 2>&1 || return 0
	custom=$(jq -c --arg id "$INPUT_LANGUAGES_WIDGET" '[.bar.layout | to_entries[] as $section | $section.value | to_entries[] | select((if .value | type == "object" then .value.id else .value end) == $id) | {section:$section.key,index:.key,entry:.value}]' "$source") || return 0
	stock=$(jq -c --arg id "$INPUT_LANGUAGES_STOCK_WIDGET" '[.bar.layout | to_entries[] as $section | $section.value | to_entries[] | select((if .value | type == "object" then .value.id else .value end) == $id) | {section:$section.key,index:.key,entry:.value}]' "$source") || return 0
	weather=$(jq -c '[.bar.layout | to_entries[] as $section | $section.value | to_entries[] | select((if .value | type == "object" then .value.id else .value end) == "omarchy.weather") | {section:$section.key,index:.key}]' "$source") || return 0
	INPUT_LANGUAGES_WIDGET_COUNT=$(jq -r length <<<"$custom")
	if ((INPUT_LANGUAGES_WIDGET_COUNT == 1)); then
		INPUT_LANGUAGES_WIDGET_PRESENT=true
		IFS=$'\t' read -r INPUT_LANGUAGES_WIDGET_SECTION INPUT_LANGUAGES_WIDGET_INDEX INPUT_LANGUAGES_WIDGET_ENTRY < <(jq -r '.[0] | [.section,(.index | tostring),(.entry | tojson)] | @tsv' <<<"$custom")
	fi
	INPUT_LANGUAGES_STOCK_WIDGET_COUNT=$(jq -r length <<<"$stock")
	if ((INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 1)); then
		INPUT_LANGUAGES_STOCK_WIDGET_PRESENT=true
		IFS=$'\t' read -r INPUT_LANGUAGES_STOCK_WIDGET_SECTION INPUT_LANGUAGES_STOCK_WIDGET_INDEX INPUT_LANGUAGES_STOCK_WIDGET_ENTRY < <(jq -r '.[0] | [.section,(.index | tostring),(.entry | tojson)] | @tsv' <<<"$stock")
	fi
	INPUT_LANGUAGES_WEATHER_COUNT=$(jq -r length <<<"$weather")
	if ((INPUT_LANGUAGES_WEATHER_COUNT == 1)); then
		IFS=$'\t' read -r INPUT_LANGUAGES_WEATHER_SECTION INPUT_LANGUAGES_WEATHER_INDEX < <(jq -r '.[0] | [.section,(.index | tostring)] | @tsv' <<<"$weather")
	fi
	if [[ -L $INPUT_LANGUAGES_WIDGET_LIVE ]]; then
		INPUT_LANGUAGES_WIDGET_LINK_TARGET=$(readlink -- "$INPUT_LANGUAGES_WIDGET_LIVE" 2>/dev/null || true)
		if [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid ]]; then
			expected=$(jq -r .widget_source "$INPUT_LANGUAGES_ACTIVE")
			[[ $INPUT_LANGUAGES_WIDGET_LINK_TARGET != "$expected" ]] || INPUT_LANGUAGES_WIDGET_LINK_STATE=exact
		fi
		[[ $INPUT_LANGUAGES_WIDGET_LINK_STATE == exact ]] || INPUT_LANGUAGES_WIDGET_LINK_STATE=conflict
	elif [[ -e $INPUT_LANGUAGES_WIDGET_LIVE ]]; then
		INPUT_LANGUAGES_WIDGET_LINK_STATE=conflict
	fi
	if [[ -d $INPUT_LANGUAGES_PLUGIN_ROOT ]]; then
		while IFS= read -r -d '' candidate; do
			[[ ${candidate##*/} != "$INPUT_LANGUAGES_WIDGET" && ${candidate##*/} != .* ]] || continue
			manifest=$candidate/manifest.json
			[[ -f $manifest ]] || continue
			cloned=$(jq -r '.omarchy.clonedFrom // empty' "$manifest" 2>/dev/null || true)
			[[ $cloned != "$INPUT_LANGUAGES_STOCK_WIDGET" ]] || INPUT_LANGUAGES_COMPETING_CLONES+="${INPUT_LANGUAGES_COMPETING_CLONES:+ }${candidate##*/}"
		done < <(find "$INPUT_LANGUAGES_PLUGIN_ROOT" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 | LC_ALL=C sort -z)
	fi
	INPUT_LANGUAGES_WIDGET_STATE=valid
}

input_languages_widget_matches() {
	local present=$1 section=${2-} index=${3-} entry=${4-null}
	input_languages_inspect_widget
	if [[ $present == false ]]; then ((INPUT_LANGUAGES_WIDGET_COUNT == 0)); return; fi
	[[ $present == true && $INPUT_LANGUAGES_WIDGET_COUNT == 1 && $INPUT_LANGUAGES_WIDGET_SECTION == "$section" && $INPUT_LANGUAGES_WIDGET_INDEX == "$index" ]] || return 1
	jq -en --argjson expected "$entry" --argjson actual "$INPUT_LANGUAGES_WIDGET_ENTRY" '$actual == $expected' >/dev/null 2>&1
}

input_languages_stock_widget_matches() {
	local present=$1 section=${2-} index=${3-} entry=${4-null}
	input_languages_inspect_widget
	if [[ $present == false ]]; then ((INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 0)); return; fi
	[[ $present == true && $INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 1 && $INPUT_LANGUAGES_STOCK_WIDGET_SECTION == "$section" && $INPUT_LANGUAGES_STOCK_WIDGET_INDEX == "$index" ]] || return 1
	jq -en --argjson expected "$entry" --argjson actual "$INPUT_LANGUAGES_STOCK_WIDGET_ENTRY" '$actual == $expected' >/dev/null 2>&1
}

input_languages_any_widget_matches() {
	local present=$1 section=${2-} index=${3-} entry=${4-null} id
	if [[ $present == false ]]; then
		input_languages_inspect_widget
		((INPUT_LANGUAGES_WIDGET_COUNT == 0 && INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 0))
		return
	fi
	id=$(jq -r .id <<<"$entry") || return 1
	case $id in
		"$INPUT_LANGUAGES_WIDGET") input_languages_widget_matches true "$section" "$index" "$entry" ;;
		"$INPUT_LANGUAGES_STOCK_WIDGET") input_languages_stock_widget_matches true "$section" "$index" "$entry" ;;
		*) return 1 ;;
	esac
}

input_languages_read_control_state() {
	INPUT_LANGUAGES_PLUGIN_HEALTH_VALID=false
	INPUT_LANGUAGES_PLUGIN_HEALTH=$(hyprctl -j inputlanguages 2>/dev/null || true)
	jq -e '(.healthy | type == "boolean") and (.build_id | type == "string") and (.source_id | type == "string") and
		(.compatibility_hash | type == "string") and (.canonical_group == 0 or .canonical_group == 1) and
		(.physical_keyboards | type == "array") and (.excluded_keyboards | type == "array")' \
		<<<"$INPUT_LANGUAGES_PLUGIN_HEALTH" >/dev/null 2>&1
}

input_languages_read_health() {
	input_languages_read_control_state || return 1
	if jq -e '.healthy == true and (.physical_keyboards | length > 0)' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH" >/dev/null 2>&1; then
		INPUT_LANGUAGES_PLUGIN_HEALTH_VALID=true
		return 0
	fi
	return 1
}

input_languages_reset_group() {
	local group=$1 response
	[[ $group == 0 || $group == 1 ]] || return 1
	response=$(hyprctl -j inputlanguagesreset "$group" 2>/dev/null) || return 1
	jq -e --argjson group "$group" '
		(keys | sort) == (["canonical_group","ok"] | sort) and .ok == true and .canonical_group == $group
	' <<<"$response" >/dev/null 2>&1
}

input_languages_read_indicator_health() {
	INPUT_LANGUAGES_INDICATOR_HEALTHY=false
	[[ $INPUT_LANGUAGES_PLUGIN_HEALTH_VALID == true && $INPUT_LANGUAGES_WIDGET_PRESENT == true ]] || return 1
	local shell_reply geometry devices group physical
	shell_reply=$(omarchy shell shell ping 2>/dev/null) || return 1
	[[ $shell_reply == ok ]] || return 1
	geometry=$(omarchy shell shell debugBarGeometry 2>/dev/null) || return 1
	jq -e --arg widget "$INPUT_LANGUAGES_WIDGET" '
		type == "array" and
		([.[] | select(.id == $widget)] | length > 0) and
		all(.[] | select(.id == $widget); .visible == true and .itemVisible == true and .width > 0 and .height > 0 and .itemWidth > 0 and .itemHeight > 0)
	' <<<"$geometry" >/dev/null 2>&1 || return 1
	devices=$(hyprctl -j devices 2>/dev/null) || return 1
	group=$(jq -r .canonical_group <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH") || return 1
	physical=$(jq -c .physical_keyboards <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH") || return 1
	jq -e --argjson names "$physical" --argjson group "$group" '
		.keyboards as $keyboards |
		($keyboards | type == "array") and
		([$names[] as $name | any($keyboards[];
			.name == $name and .layout == "us,ru" and .variant == "," and
			.active_layout_index == $group and
			(($group == 0 and .active_keymap == "English (US)") or ($group == 1 and .active_keymap == "Russian")))] | all)
	' <<<"$devices" >/dev/null 2>&1 || return 1
	INPUT_LANGUAGES_INDICATOR_HEALTHY=true
}

input_languages_inspect() {
	input_languages_set_paths
	input_languages_detect_support
	input_languages_inspect_tree
	input_languages_validate_active_receipt
	input_languages_classify_evidence "$INPUT_LANGUAGES_PENDING" input_languages_validate_pending_file INPUT_LANGUAGES_PENDING_STATE
	input_languages_classify_evidence "$INPUT_LANGUAGES_RECOVERY" input_languages_validate_recovery_file INPUT_LANGUAGES_RECOVERY_STATE
	input_languages_classify_evidence "$INPUT_LANGUAGES_CLEANUP" input_languages_validate_cleanup_file INPUT_LANGUAGES_CLEANUP_STATE
	input_languages_inspect_widget
	input_languages_read_health || true
	input_languages_read_indicator_health || true
}

input_languages_source_identity_from() {
	local plugin_source=$1 config_source=$2 widget_source path digest
	widget_source=$plugin_source/widget/$INPUT_LANGUAGES_WIDGET
	{
		for path in Makefile migration-baseline.json include/input-language-model.hpp src/input-language-model.cpp src/plugin.cpp; do
			[[ -f $plugin_source/$path && ! -L $plugin_source/$path ]] || return 1
			digest=$(sha256sum -- "$plugin_source/$path") || return 1
			printf '%s  plugin/%s\n' "${digest%% *}" "$path"
		done
		for path in "${INPUT_LANGUAGES_WIDGET_FILES[@]}"; do
			[[ -f $widget_source/$path && ! -L $widget_source/$path ]] || return 1
			digest=$(sha256sum -- "$widget_source/$path") || return 1
			printf '%s  widget/%s\n' "${digest%% *}" "$path"
		done
		for path in "${INPUT_LANGUAGES_FILES[@]}"; do
			[[ -f $config_source/$path && ! -L $config_source/$path ]] || return 1
			digest=$(sha256sum -- "$config_source/$path") || return 1
			printf '%s  config/%s\n' "${digest%% *}" "$path"
		done
	} | sha256sum | cut -d' ' -f1
}

input_languages_source_identity() {
	input_languages_source_identity_from "$INPUT_LANGUAGES_PLUGIN_SOURCE" "$INPUT_LANGUAGES_SOURCE"
}

input_languages_integration_source_inventory_from() {
	local plugin_source=$1 config_source=$2 path digest
	for path in "${INPUT_LANGUAGES_INTEGRATION_SOURCE_FILES[@]}"; do
		[[ -f $plugin_source/$path && ! -L $plugin_source/$path ]] || return 1
		digest=$(sha256sum -- "$plugin_source/$path") || return 1
		printf '%s  plugin/%s\n' "${digest%% *}" "$path"
	done
	for path in "${INPUT_LANGUAGES_INTEGRATION_CONTRACT_FILES[@]}"; do
		[[ -f $plugin_source/contracts/$path && ! -L $plugin_source/contracts/$path ]] || return 1
		digest=$(sha256sum -- "$plugin_source/contracts/$path") || return 1
		printf '%s  contracts/%s\n' "${digest%% *}" "$path"
	done
	for path in dotfiles-input-languages-fcitx.service dotfiles-input-languages-fcitx.socket; do
		[[ -f $plugin_source/systemd/$path && ! -L $plugin_source/systemd/$path ]] || return 1
		digest=$(sha256sum -- "$plugin_source/systemd/$path") || return 1
		printf '%s  systemd/%s\n' "${digest%% *}" "$path"
	done
	for path in "${INPUT_LANGUAGES_WIDGET_FILES[@]}"; do
		[[ -f $plugin_source/widget/$INPUT_LANGUAGES_WIDGET/$path && ! -L $plugin_source/widget/$INPUT_LANGUAGES_WIDGET/$path ]] || return 1
		digest=$(sha256sum -- "$plugin_source/widget/$INPUT_LANGUAGES_WIDGET/$path") || return 1
		printf '%s  widget/%s\n' "${digest%% *}" "$path"
	done
	for path in "${INPUT_LANGUAGES_FILES[@]}"; do
		[[ -f $config_source/$path && ! -L $config_source/$path ]] || return 1
		digest=$(sha256sum -- "$config_source/$path") || return 1
		printf '%s  config/%s\n' "${digest%% *}" "$path"
	done
}

input_languages_integration_expected_source_paths() {
	local path
	for path in "${INPUT_LANGUAGES_INTEGRATION_SOURCE_FILES[@]}"; do printf 'plugin/%s\n' "$path"; done
	for path in "${INPUT_LANGUAGES_INTEGRATION_CONTRACT_FILES[@]}"; do printf 'contracts/%s\n' "$path"; done
	for path in dotfiles-input-languages-fcitx.service dotfiles-input-languages-fcitx.socket; do printf 'systemd/%s\n' "$path"; done
	for path in "${INPUT_LANGUAGES_WIDGET_FILES[@]}"; do printf 'widget/%s\n' "$path"; done
	for path in "${INPUT_LANGUAGES_FILES[@]}"; do printf 'config/%s\n' "$path"; done
}

input_languages_integration_source_identity_from() {
	local inventory
	inventory=$(input_languages_integration_source_inventory_from "$1" "$2") || return 1
	printf '%s\n' "$inventory" | sha256sum | cut -d' ' -f1
}

input_languages_integration_source_identity() {
	input_languages_integration_source_identity_from "$INPUT_LANGUAGES_PLUGIN_SOURCE" "$INPUT_LANGUAGES_SOURCE"
}

input_languages_integration_expected_inventory_paths() {
	printf '%s\n' \
		build.json \
		contracts \
		contracts/active-fixtures.json \
		contracts/authority.json \
		contracts/evidence-v3.json \
		contracts/fcitx.json \
		contracts/health.json \
		contracts/manifest.json \
		contracts/protocol.json \
		contracts/systemd.json \
		dotfiles.keyboard-layout \
		dotfiles.keyboard-layout/KeyboardLayout.qml \
		dotfiles.keyboard-layout/KeyboardLayoutModel.js \
		dotfiles.keyboard-layout/manifest.json \
		input-languages-fcitx-helper \
		input-languages.so \
		systemd \
		systemd/dotfiles-input-languages-fcitx.service \
		systemd/dotfiles-input-languages-fcitx.socket
}

input_languages_integration_inventory_spec() {
	local path type mode
	while IFS= read -r path; do
		case $path in
			contracts|dotfiles.keyboard-layout|systemd) type=directory; mode=555 ;;
			input-languages.so|input-languages-fcitx-helper) type=file; mode=555 ;;
			*) type=file; mode=444 ;;
		esac
		printf '%s|%s|%s\n' "$type" "$mode" "$path"
	done < <(input_languages_integration_expected_inventory_paths)
}

input_languages_integration_inventory() {
	local root=$1 entries expected path type mode digest
	[[ -d $root && ! -L $root ]] || return 1
	entries=$(find "$root" -mindepth 1 -printf '%P\n' | LC_ALL=C sort) || return 1
	expected=$(input_languages_integration_expected_inventory_paths) || return 1
	[[ $entries == "$expected" ]] || return 1
	while IFS= read -r path; do
		[[ ! -L $root/$path ]] || return 1
		mode=$(stat -c %a -- "$root/$path") || return 1
		if [[ -d $root/$path ]]; then
			type=directory
			digest=-
			[[ $mode == 555 ]] || return 1
		elif [[ -f $root/$path ]]; then
			type=file
			case $path in
				input-languages.so|input-languages-fcitx-helper) [[ $mode == 555 ]] || return 1 ;;
				*) [[ $mode == 444 ]] || return 1 ;;
			esac
			if [[ $path == build.json ]]; then
				digest=self
			else
				digest=$(sha256sum -- "$root/$path") || return 1
				digest=${digest%% *}
			fi
		else
			return 1
		fi
		printf '%s|%s|%s|%s\n' "$type" "$mode" "$digest" "$path"
	done <<<"$entries"
}

input_languages_integration_contract_digest() {
	local root=$1 path digest inventory=''
	for path in "${INPUT_LANGUAGES_INTEGRATION_CONTRACT_FILES[@]}"; do
		digest=$(sha256sum -- "$root/$path") || return 1
		inventory+="${digest%% *}  $path"$'\n'
	done
	printf '%s' "$inventory" | sha256sum | cut -d' ' -f1
}

input_languages_integration_unit_digest() {
	local root=$1 path digest inventory=''
	for path in dotfiles-input-languages-fcitx.service dotfiles-input-languages-fcitx.socket; do
		digest=$(sha256sum -- "$root/$path") || return 1
		inventory+="${digest%% *}  $path"$'\n'
	done
	printf '%s' "$inventory" | sha256sum | cut -d' ' -f1
}

input_languages_integration_unit_build_identity() {
	local source_inventory=$1 digest path service_digest='' socket_digest=''
	while read -r digest path; do
		case $path in
			systemd/dotfiles-input-languages-fcitx.service) service_digest=$digest ;;
			systemd/dotfiles-input-languages-fcitx.socket) socket_digest=$digest ;;
		esac
	done <<<"$source_inventory"
	[[ $service_digest =~ ^[0-9a-f]{64}$ && $socket_digest =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s  %s\n%s  %s\n' "$service_digest" dotfiles-input-languages-fcitx.service \
		"$socket_digest" dotfiles-input-languages-fcitx.socket | sha256sum | cut -d' ' -f1
}

input_languages_systemd_exec_path() {
	local path=$1 escaped
	input_languages_safe_absolute_path "$path" || return 1
	escaped=${path//\%/%%}
	printf '%s\n' "$escaped"
}

input_languages_render_integration_service() {
	local template=$1 artifact_dir=$2 line escaped count=0
	escaped=$(input_languages_systemd_exec_path "$artifact_dir") || return 1
	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $line == 'ExecStart="@ARTIFACT_DIR@/input-languages-fcitx-helper"' ]]; then
			printf 'ExecStart=:"%s/input-languages-fcitx-helper"\n' "$escaped"
			((count += 1))
		else
			printf '%s\n' "$line"
		fi
	done <"$template"
	((count == 1))
}

input_languages_integration_service_template_digest() {
	local service=$1 artifact_dir=$2 line escaped count=0 normalized=''
	escaped=$(input_languages_systemd_exec_path "$artifact_dir") || return 1
	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $line == "ExecStart=:\"$escaped/input-languages-fcitx-helper\"" ]]; then
			normalized+='ExecStart="@ARTIFACT_DIR@/input-languages-fcitx-helper"'$'\n'
			((count += 1))
		else
			normalized+="$line"$'\n'
		fi
	done <"$service"
	((count == 1)) || return 1
	printf '%s' "$normalized" | sha256sum | cut -d' ' -f1
}

input_languages_verify_integration_units() {
	local root=$1 temporary status=0
	temporary=$(TMPDIR=/tmp mktemp -d /tmp/input-languages-units.XXXXXX) || return 1
	cp -- "$root/systemd/dotfiles-input-languages-fcitx.socket" "$root/systemd/dotfiles-input-languages-fcitx.service" "$temporary/" || status=1
	if ((status == 0)); then
		systemd-analyze verify "$temporary/dotfiles-input-languages-fcitx.socket" "$temporary/dotfiles-input-languages-fcitx.service" >/dev/null || status=1
	fi
	rm -rf -- "$temporary" || status=1
	return "$status"
}

input_languages_linker_identity() {
	local identity
	IFS= read -r identity < <(/usr/bin/ld --version) || return 1
	[[ -n $identity ]] || return 1
	printf '%s\n' "$identity"
}

input_languages_integration_dependency_identity() {
	local package_versions module_versions plugin_flags helper_flags header_source fcitx_upstream supported_fcitx hyprland_compiler
	package_versions=$(LC_ALL=C /usr/bin/pacman -Q "${INPUT_LANGUAGES_INTEGRATION_STACK_PACKAGES[@]}" | /usr/bin/tr '\n' ',') || return 1
	module_versions=$(LC_ALL=C /usr/bin/pkg-config --modversion "${INPUT_LANGUAGES_INTEGRATION_PKGCONFIG_MODULES[@]}" | /usr/bin/tr '\n' ',') || return 1
	plugin_flags=$(LC_ALL=C /usr/bin/pkg-config --cflags --libs "${INPUT_LANGUAGES_PKGCONFIG_MODULES[@]}") || return 1
	helper_flags=$(LC_ALL=C /usr/bin/pkg-config --cflags --libs libsystemd libcrypto) || return 1
	header_source=$(input_languages_header_source_identity) || return 1
	fcitx_upstream=$(LC_ALL=C /usr/bin/fcitx5 --version 2>/dev/null) || return 1
	supported_fcitx=$(jq -r .compatibility.upstream_version "$INPUT_LANGUAGES_PLUGIN_SOURCE/contracts/fcitx.json") || return 1
	[[ $fcitx_upstream == "$supported_fcitx" ]] || return 1
	hyprland_compiler=$(input_languages_hyprland_compiler) || return 1
	[[ ${hyprland_compiler%%.*} == "${INPUT_LANGUAGES_COMPILER%%.*}" ]] || return 1
	printf 'arch=%s;pkgconfig=%s;plugin-link=%s;helper-link=%s;hyprland-headers=%s;hyprland-compiler=%s;libsystemd=%s;libcrypto=%s;fcitx-upstream=%s\n' \
		"$package_versions" "$module_versions" "$plugin_flags" "$helper_flags" "$header_source" \
		"$hyprland_compiler" "$(/usr/bin/pkg-config --modversion libsystemd)" "$(/usr/bin/pkg-config --modversion libcrypto)" "$fcitx_upstream"
}

input_languages_integration_build_identity() {
	local source=$1 compiler=$2 linker=$3 compatibility=$4 dependencies=$5 unit_build_identity=$6 inventory_spec
	inventory_spec=$(input_languages_integration_inventory_spec) || return 1
	printf '%s' "$source|$compiler|$linker|$compatibility|$dependencies|$INPUT_LANGUAGES_INTEGRATION_PLUGIN_FLAGS|$INPUT_LANGUAGES_INTEGRATION_HELPER_FLAGS|$unit_build_identity|$inventory_spec" |
		sha256sum | cut -d' ' -f1
}

input_languages_build_integration_artifact() {
	local source_inventory source_id dependencies linker compatibility current_compatibility compiler transaction publication_id final work build_source build_config output preview
	local protocol controller health unit integration units_sha unit_build_identity build_id snapshot_inventory current_inventory current_dependencies current_linker current_compiler existing_build
	local artifact_sha helper_sha widget_sha contracts_sha inventory inventory_json source_inventory_json metadata build_log
	input_languages_set_paths
	compiler=${INPUT_LANGUAGES_COMPILER-}
	[[ -n $compiler ]] || compiler=$(/usr/bin/c++ -dumpfullversion -dumpversion) || return 1
	INPUT_LANGUAGES_COMPILER=$compiler
	current_compatibility=$(input_languages_header_hash) || return 1
	compatibility=${INPUT_LANGUAGES_HEADER_HASH:-$current_compatibility}
	[[ $compatibility == "$current_compatibility" ]] || return 1
	linker=$(input_languages_linker_identity) || return 1
	source_inventory=$(input_languages_integration_source_inventory_from "$INPUT_LANGUAGES_PLUGIN_SOURCE" "$INPUT_LANGUAGES_SOURCE") || return 1
	bash "$REPOSITORY_ROOT/lib/dotfiles/input-languages-validator.sh" "$REPOSITORY_ROOT" /usr/share/omarchy --static-only >/dev/null || return 1
	current_inventory=$(input_languages_integration_source_inventory_from "$INPUT_LANGUAGES_PLUGIN_SOURCE" "$INPUT_LANGUAGES_SOURCE") || return 1
	[[ $current_inventory == "$source_inventory" ]] || return 1
	source_id=$(printf '%s\n' "$source_inventory" | sha256sum | cut -d' ' -f1) || return 1
	dependencies=$(input_languages_integration_dependency_identity) || return 1
	unit_build_identity=$(input_languages_integration_unit_build_identity "$source_inventory") || return 1
	publication_id=$(input_languages_integration_build_identity "$source_id" "$compiler" "$linker" "$compatibility" "$dependencies" "$unit_build_identity") || return 1
	final=$INPUT_LANGUAGES_ARTIFACTS/integration-$publication_id
	input_languages_safe_absolute_path "$final" || return 1
	if [[ -e $final || -L $final ]]; then
		[[ -d $final && ! -L $final ]] || return 1
		jq -e --arg source "$source_id" --arg compiler "$compiler" --arg linker "$linker" --arg compatibility "$compatibility" \
			--arg dependencies "$dependencies" --arg unit_build_identity "$unit_build_identity" '
			.source_id == $source and .compiler == $compiler and .linker == $linker and .compatibility_hash == $compatibility and
			.dependencies == $dependencies and .unit_build_identity == $unit_build_identity
		' "$final/build.json" >/dev/null 2>&1 || return 1
		input_languages_validate_integration_artifact_self "$final" || return 1
		existing_build=$(jq -r .build_id "$final/build.json") || return 1
		INPUT_LANGUAGES_INTEGRATION_SOURCE_ID=$source_id
		INPUT_LANGUAGES_INTEGRATION_BUILD_ID=$existing_build
		INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR=$final
		INPUT_LANGUAGES_INTEGRATION_ARTIFACT=$final/input-languages.so
		INPUT_LANGUAGES_INTEGRATION_HELPER=$final/input-languages-fcitx-helper
		return 0
	fi
	transaction=$(input_languages_new_transaction) || return 1
	work=$INPUT_LANGUAGES_ARTIFACTS/.integration-build-$transaction
	build_source=$work/source
	build_config=$work/config
	output=$work/output
	preview=$work/unit-preview
	[[ ! -e $work && ! -L $work ]] || return 1
	mkdir -p -- "$INPUT_LANGUAGES_ARTIFACTS" "$INPUT_LANGUAGES_STATE/diagnostics" || return 1
	[[ -d $INPUT_LANGUAGES_STATE/diagnostics && ! -L $INPUT_LANGUAGES_STATE/diagnostics ]] || return 1
	chmod 700 -- "$INPUT_LANGUAGES_ARTIFACTS" "$INPUT_LANGUAGES_STATE" "$INPUT_LANGUAGES_STATE/diagnostics" 2>/dev/null || return 1
	build_log=$(mktemp "$INPUT_LANGUAGES_STATE/diagnostics/.integration-build.XXXXXX.log") || return 1
	chmod 600 -- "$build_log" || { rm -f -- "$build_log"; return 1; }
	mkdir -m 0700 -- "$work" "$build_source" "$build_config" "$output" "$preview" || { rm -rf -- "$work"; return 1; }
	cp -a -- "$INPUT_LANGUAGES_PLUGIN_SOURCE/." "$build_source/" && cp -a -- "$INPUT_LANGUAGES_SOURCE/." "$build_config/" || { rm -rf -- "$work"; return 1; }
	snapshot_inventory=$(input_languages_integration_source_inventory_from "$build_source" "$build_config") || { rm -rf -- "$work"; return 1; }
	[[ $snapshot_inventory == "$source_inventory" ]] || { rm -rf -- "$work"; return 1; }
	integration=$(jq -r .integration "$build_source/contracts/manifest.json") || { rm -rf -- "$work"; return 1; }
	protocol=$(jq -r .identity "$build_source/contracts/protocol.json") || { rm -rf -- "$work"; return 1; }
	controller=$(jq -r .identity "$build_source/contracts/fcitx.json") || { rm -rf -- "$work"; return 1; }
	health=$(jq -r .identity "$build_source/contracts/health.json") || { rm -rf -- "$work"; return 1; }
	unit=$(jq -r .identity "$build_source/contracts/systemd.json") || { rm -rf -- "$work"; return 1; }
	cp -- "$build_source/systemd/dotfiles-input-languages-fcitx.socket" "$preview/"
	input_languages_render_integration_service "$build_source/systemd/dotfiles-input-languages-fcitx.service" "$final" >"$preview/dotfiles-input-languages-fcitx.service" || { rm -rf -- "$work"; return 1; }
	units_sha=$(input_languages_integration_unit_digest "$preview") || { rm -rf -- "$work"; return 1; }
	build_id=$(input_languages_integration_build_identity "$source_id" "$compiler" "$linker" "$compatibility" "$dependencies" "$units_sha") || { rm -rf -- "$work"; return 1; }
	: >"$build_log" || { rm -rf -- "$work"; return 1; }
	if ! env -i HOME="$HOME" PATH=/usr/bin:/bin LC_ALL=C make --no-print-directory -C "$build_source" -f integration.mk integration-artifact \
		OUTPUT_DIR=../output BUILD_ID="$build_id" SOURCE_ID="$source_id" COMPILER_ID="$compiler" COMPATIBILITY_ID="$compatibility" \
		INTEGRATION_ID="$integration" PROTOCOL_ID="$protocol" CONTROLLER_ID="$controller" HEALTH_ID="$health" UNIT_ID="$unit" CXX=/usr/bin/c++ \
		>"$build_log" 2>&1; then
		/usr/bin/cat "$build_log" >&2
		rm -rf -- "$work"
		return 1
	fi
	cp -- "$preview/dotfiles-input-languages-fcitx.service" "$output/systemd/dotfiles-input-languages-fcitx.service" || { rm -rf -- "$work"; return 1; }
	current_inventory=$(input_languages_integration_source_inventory_from "$INPUT_LANGUAGES_PLUGIN_SOURCE" "$INPUT_LANGUAGES_SOURCE") || { rm -rf -- "$work"; return 1; }
	current_dependencies=$(input_languages_integration_dependency_identity) || { rm -rf -- "$work"; return 1; }
	current_linker=$(input_languages_linker_identity) || { rm -rf -- "$work"; return 1; }
	current_compiler=$(/usr/bin/c++ -dumpfullversion -dumpversion) || { rm -rf -- "$work"; return 1; }
	current_compatibility=$(input_languages_header_hash) || { rm -rf -- "$work"; return 1; }
	[[ $current_inventory == "$source_inventory" && $current_dependencies == "$dependencies" && $current_linker == "$linker" &&
		$current_compiler == "$compiler" && $current_compatibility == "$compatibility" ]] || { rm -rf -- "$work"; return 1; }
	[[ $(input_languages_integration_unit_digest "$output/systemd") == "$units_sha" ]] || { rm -rf -- "$work"; return 1; }
	artifact_sha=$(sha256sum -- "$output/input-languages.so") || { rm -rf -- "$work"; return 1; }; artifact_sha=${artifact_sha%% *}
	helper_sha=$(sha256sum -- "$output/input-languages-fcitx-helper") || { rm -rf -- "$work"; return 1; }; helper_sha=${helper_sha%% *}
	widget_sha=$(input_languages_widget_digest "$output/$INPUT_LANGUAGES_WIDGET") || { rm -rf -- "$work"; return 1; }
	contracts_sha=$(input_languages_integration_contract_digest "$output/contracts") || { rm -rf -- "$work"; return 1; }
	: >"$output/build.json"
	find "$output" -mindepth 1 -type d -exec chmod 555 -- {} + && find "$output" -type f -exec chmod 444 -- {} + &&
		chmod 555 -- "$output/input-languages.so" "$output/input-languages-fcitx-helper" || { chmod -R u+w "$work"; rm -rf -- "$work"; return 1; }
	inventory=$(input_languages_integration_inventory "$output") || { chmod -R u+w "$work"; rm -rf -- "$work"; return 1; }
	inventory_json=$(printf '%s\n' "$inventory" | jq -Rsc 'split("\n")[:-1]') || { chmod -R u+w "$work"; rm -rf -- "$work"; return 1; }
	source_inventory_json=$(printf '%s\n' "$source_inventory" | jq -Rsc 'split("\n")[:-1]') || { chmod -R u+w "$work"; rm -rf -- "$work"; return 1; }
	metadata=$work/build.json
	jq -n --arg integration "$integration" --arg source_id "$source_id" --arg build_id "$build_id" --arg compatibility_hash "$compatibility" \
		--arg compiler "$compiler" --arg linker "$linker" --arg dependencies "$dependencies" \
		--arg plugin_flags "$INPUT_LANGUAGES_INTEGRATION_PLUGIN_FLAGS" --arg helper_flags "$INPUT_LANGUAGES_INTEGRATION_HELPER_FLAGS" \
		--arg artifact_sha256 "$artifact_sha" --arg helper_sha256 "$helper_sha" --arg widget_sha256 "$widget_sha" \
		--arg contracts_sha256 "$contracts_sha" --arg units_sha256 "$units_sha" --arg unit_build_identity "$unit_build_identity" --arg protocol_identity "$protocol" \
		--arg controller_identity "$controller" --arg health_identity "$health" --arg unit_identity "$unit" \
		--argjson source_inventory "$source_inventory_json" --argjson inventory "$inventory_json" '
		{version:1,integration:$integration,source_id:$source_id,build_id:$build_id,compatibility_hash:$compatibility_hash,
		compiler:$compiler,linker:$linker,dependencies:$dependencies,plugin_flags:$plugin_flags,helper_flags:$helper_flags,
		artifact_sha256:$artifact_sha256,helper_sha256:$helper_sha256,widget_sha256:$widget_sha256,contracts_sha256:$contracts_sha256,
		units_sha256:$units_sha256,unit_build_identity:$unit_build_identity,protocol_identity:$protocol_identity,controller_identity:$controller_identity,
		health_identity:$health_identity,unit_identity:$unit_identity,source_inventory:$source_inventory,inventory:$inventory,
		exports:["pluginAPIVersion","pluginExit","pluginInit"]}
	' >"$metadata" || { chmod -R u+w "$work"; rm -rf -- "$work"; return 1; }
	mv -fT -- "$metadata" "$output/build.json" && chmod 444 -- "$output/build.json" && chmod 555 -- "$output" || { chmod -R u+w "$work"; rm -rf -- "$work"; return 1; }
	input_languages_validate_integration_artifact_values "$output" "$final" false || { chmod -R u+w "$work"; rm -rf -- "$work"; return 1; }
	chmod u+w -- "$output" && mv -- "$output" "$final" && chmod 555 -- "$final" || { chmod -R u+w "$work"; rm -rf -- "$work"; return 1; }
	chmod -R u+w -- "$work" && rm -rf -- "$work" || return 1
	if ! input_languages_validate_integration_artifact_self "$final"; then
		chmod -R u+w -- "$final" 2>/dev/null || true
		rm -rf -- "$final"
		return 1
	fi
	INPUT_LANGUAGES_INTEGRATION_SOURCE_ID=$source_id
	INPUT_LANGUAGES_INTEGRATION_BUILD_ID=$build_id
	INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR=$final
	INPUT_LANGUAGES_INTEGRATION_ARTIFACT=$final/input-languages.so
	INPUT_LANGUAGES_INTEGRATION_HELPER=$final/input-languages-fcitx-helper
}

input_languages_source_matches_build() {
	local current_source
	current_source=$(input_languages_source_identity) || return 1
	[[ $current_source == "$INPUT_LANGUAGES_SOURCE_ID" ]]
}

input_languages_dependencies_match_build() {
	local current_dependencies
	current_dependencies=$(input_languages_dependency_identity) || return 1
	[[ $current_dependencies == "$INPUT_LANGUAGES_DEPENDENCIES" ]]
}

input_languages_header_source_identity() {
	local root=${DOTFILES_TEST_HYPRLAND_HEADER_ROOT:-/usr/include/hyprland} entries path digest inventory=''
	[[ -d $root && ! -L $root ]] || return 1
	entries=$(find "$root" \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort) || return 1
	[[ -n $entries ]] || return 1
	while IFS= read -r path; do
		digest=$(sha256sum -- "$root/$path") || return 1
		inventory+="${digest%% *}  $path"$'\n'
	done <<<"$entries"
	printf '%s' "$inventory" | sha256sum | cut -d' ' -f1
}

input_languages_dependency_identity() {
	local package_versions module_versions flags header_source
	package_versions=$(LC_ALL=C /usr/bin/pacman -Q "${INPUT_LANGUAGES_STACK_PACKAGES[@]}" | /usr/bin/tr '\n' ',') || return 1
	module_versions=$(LC_ALL=C /usr/bin/pkg-config --modversion "${INPUT_LANGUAGES_PKGCONFIG_MODULES[@]}" | /usr/bin/tr '\n' ',') || return 1
	flags=$(LC_ALL=C /usr/bin/pkg-config --cflags --libs "${INPUT_LANGUAGES_PKGCONFIG_MODULES[@]}") || return 1
	header_source=$(input_languages_header_source_identity) || return 1
	printf 'arch=%s;pkgconfig=%s;flags=%s;hyprland-headers=%s\n' "$package_versions" "$module_versions" "$flags" "$header_source"
}

input_languages_running_hash() {
	env -i HOME="$HOME" PATH=/usr/bin:/bin LC_ALL=C XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR-}" HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE-}" \
		/usr/bin/hyprctl version 2>/dev/null | while IFS= read -r line; do
		if [[ $line == 'Version ABI string: '* ]]; then printf '%s\n' "${line#Version ABI string: }"; return 0; fi
	done
}

input_languages_pointer_matches() {
	local artifact=$1 expected actual
	input_languages_pointer_file_matches "$INPUT_LANGUAGES_POINTER" "$artifact"
}

input_languages_pointer_file_matches() {
	local pointer=$1 artifact=$2 expected actual
	input_languages_file_metadata_safe "$pointer" 600 || return 1
	printf -v expected 'return "%s"' "$artifact"
	actual=$(<"$pointer") || return 1
	[[ $actual == "$expected" ]]
}

input_languages_active_widget_matches_receipt() {
	local section index entry
	section=$(jq -r .widget_section "$INPUT_LANGUAGES_ACTIVE")
	index=$(jq -r .widget_index "$INPUT_LANGUAGES_ACTIVE")
	entry=$(jq -c .widget_entry "$INPUT_LANGUAGES_ACTIVE")
	input_languages_widget_matches true "$section" "$index" "$entry" || return 1
	((INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 0))
}

input_languages_active_widget_matches() {
	input_languages_active_widget_matches_receipt && input_languages_custom_widget_at_target
}

input_languages_exact_noop() {
	[[ $INPUT_LANGUAGES_TREE_STATE == linked && $INPUT_LANGUAGES_ACTIVE_STATE == valid && $INPUT_LANGUAGES_PENDING_STATE == absent && $INPUT_LANGUAGES_RECOVERY_STATE == absent && $INPUT_LANGUAGES_CLEANUP_STATE == absent ]] || return 1
	input_languages_static_preflight || return 1
	local artifact build source compatibility current_source running compiler dependencies artifact_sha widget_sha errors current_compiler current_dependencies current_header expected_build built_compiler current_warning=''
	artifact=$(jq -r .artifact "$INPUT_LANGUAGES_ACTIVE")
	build=$(jq -r .build_id "$INPUT_LANGUAGES_ACTIVE")
	source=$(jq -r .source_id "$INPUT_LANGUAGES_ACTIVE")
	compatibility=$(jq -r .compatibility_hash "$INPUT_LANGUAGES_ACTIVE")
	compiler=$(jq -r .compiler "$INPUT_LANGUAGES_ACTIVE")
	dependencies=$(jq -r .dependencies "$INPUT_LANGUAGES_ACTIVE")
	artifact_sha=$(jq -r .artifact_sha256 "$INPUT_LANGUAGES_ACTIVE")
	widget_sha=$(jq -r .widget_sha256 "$INPUT_LANGUAGES_ACTIVE")
	current_source=$(input_languages_source_identity) || return 1
	[[ $current_source == "$source" ]] || return 1
	current_compiler=$(/usr/bin/c++ -dumpfullversion -dumpversion 2>/dev/null) || return 1
	current_dependencies=$(input_languages_dependency_identity 2>/dev/null) || return 1
	[[ $current_compiler == "$compiler" && $current_dependencies == "$dependencies" ]] || return 1
	built_compiler=$(input_languages_hyprland_compiler) || return 1
	[[ ${built_compiler%%.*} == "${current_compiler%%.*}" ]] || return 1
	if [[ $built_compiler != "$current_compiler" ]]; then current_warning="Hyprland was built with GCC $built_compiler; plugin will use GCC $current_compiler."; fi
	[[ $current_warning == "$(jq -r .compiler_warning "$INPUT_LANGUAGES_ACTIVE")" ]] || return 1
	current_header=$(input_languages_header_hash) || return 1
	[[ $current_header == "$compatibility" ]] || return 1
	expected_build=$(printf '%s' "$source|$compiler|$compatibility|$dependencies|-std=c++23,-shared,-fPIC,-fno-gnu-unique" | sha256sum | cut -d' ' -f1) || return 1
	[[ $build == "$expected_build" ]] || return 1
	input_languages_validate_artifact_values "$artifact" "$build" "$source" "$artifact_sha" "$compatibility" "$compiler" "$dependencies" "$widget_sha" || return 1
	input_languages_validate_artifact_binary "$artifact" "$build" "$source" "$compiler" || return 1
	input_languages_pointer_matches "$artifact" || return 1
	running=$(input_languages_running_hash) || return 1
	[[ -n $running && $running == "$compatibility" ]] || return 1
	jq -e --arg build "$build" --arg source "$source" --arg compatibility "$compatibility" '
		.healthy == true and .build_id == $build and .source_id == $source and .compatibility_hash == $compatibility and
		(.canonical_group == 0 or .canonical_group == 1) and (.physical_keyboards | length > 0)
	' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH" >/dev/null 2>&1 || return 1
	input_languages_active_widget_matches || return 1
	[[ $INPUT_LANGUAGES_WIDGET_LINK_STATE == exact && -z $INPUT_LANGUAGES_COMPETING_CLONES ]] || return 1
	input_languages_custom_plugin_discovered || return 1
	[[ $INPUT_LANGUAGES_INDICATOR_HEALTHY == true ]] || return 1
	errors=$(hyprctl configerrors 2>/dev/null) || return 1
	[[ -z $errors ]]
}

input_languages_status() {
	input_languages_inspect
	printf 'Portable input language setup: US English first, Russian second; desktop Hyprland/XKB applications only.\n'
	printf 'Boundary: console, locale, display language, input methods, captured guests, and compositor-bypassing applications are unchanged.\n'
	local overall action source_state=unavailable pointer_state=absent artifact_state=absent config_state=unavailable
	local installed_state=false running_state=unavailable-or-unhealthy running_compatibility=unavailable
	if ! input_languages_paths_are_safe >/dev/null 2>&1; then
		overall=conflict; action='Correct unsafe or divergent HOME/XDG paths before mutation.'
	elif [[ $INPUT_LANGUAGES_RECOVERY_STATE != absent ]]; then
		overall=$([[ $INPUT_LANGUAGES_RECOVERY_STATE == valid ]] && printf recovery-required || printf invalid-evidence)
		action='Choose Apply or Remove to review and approve receipt-backed recovery.'
	elif [[ $INPUT_LANGUAGES_PENDING_STATE != absent ]]; then
		overall=$([[ $INPUT_LANGUAGES_PENDING_STATE == valid ]] && printf pending-recovery || printf invalid-evidence)
		action='Choose Apply or Remove to review the interrupted transaction recovery plan.'
	elif [[ $INPUT_LANGUAGES_CLEANUP_STATE != absent ]]; then
		overall=$([[ $INPUT_LANGUAGES_CLEANUP_STATE == valid ]] && printf pending-cleanup || printf invalid-evidence)
		action='Choose Apply or Remove to review and resume receipt-backed artifact cleanup.'
	elif [[ $INPUT_LANGUAGES_ACTIVE_STATE == invalid ]]; then
		overall=invalid-evidence; action='Preserve and repair the invalid active evidence before mutation.'
	elif [[ $INPUT_LANGUAGES_SUPPORTED != true ]]; then
		overall=unsupported
		if [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $INPUT_LANGUAGES_TREE_STATE == linked ]]; then
			action='Restore a supported Omarchy version before Apply, or choose Remove for receipt-backed removal when current inspection proves it safe.'
		else
			action='Restore a supported Omarchy version before choosing Apply.'
		fi
	elif input_languages_exact_noop; then
		overall=healthy; action='No action required.'
	elif [[ $INPUT_LANGUAGES_TREE_STATE == migratable || $INPUT_LANGUAGES_TREE_STATE == uninstalled ]]; then
		overall=available; action='Choose Apply to build and activate the setup.'
	elif [[ $INPUT_LANGUAGES_TREE_STATE == linked ]]; then
		overall=drifted; action='Choose Apply to rebuild or repair verified lifecycle drift.'
	else
		overall=conflict; action='Resolve the Hyprland ownership conflict before mutation.'
	fi
	if input_languages_source_identity >/dev/null 2>&1; then source_state=valid; fi
	if [[ -e $INPUT_LANGUAGES_POINTER || -L $INPUT_LANGUAGES_POINTER ]]; then pointer_state=$([[ -f $INPUT_LANGUAGES_POINTER && ! -L $INPUT_LANGUAGES_POINTER ]] && printf present || printf invalid); fi
	if [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid ]] && input_languages_validate_active_file "$INPUT_LANGUAGES_ACTIVE"; then artifact_state=verified; fi
	if errors=$(hyprctl configerrors 2>/dev/null); then config_state=$([[ -z $errors ]] && printf clean || printf errors); fi
	if [[ $INPUT_LANGUAGES_TREE_STATE == linked ]]; then installed_state=true; fi
	if [[ $INPUT_LANGUAGES_PLUGIN_HEALTH_VALID == true ]]; then running_state=healthy; fi
	running_compatibility=$(input_languages_running_hash 2>/dev/null) || running_compatibility=unavailable
	printf 'Overall: %s\n' "$overall"
	printf 'Support: required Omarchy %s through 4.x; detected %s; supported=%s\n' "$INPUT_LANGUAGES_MIN_OMARCHY" "$INPUT_LANGUAGES_VERSION" "$INPUT_LANGUAGES_SUPPORTED"
	printf 'Installed: package=%s; active-receipt=%s\n' "$installed_state" "$INPUT_LANGUAGES_ACTIVE_STATE"
	printf 'Running: plugin=%s; compositor-compatibility=%s\n' "$running_state" "$running_compatibility"
	printf 'Configured: tree=%s; Hyprland=%s\n' "$INPUT_LANGUAGES_TREE_STATE" "$config_state"
	printf 'Ownership: tree=%s; links=%s; source=%s\n' "$INPUT_LANGUAGES_TREE_STATE" "$INPUT_LANGUAGES_TREE_STATE" "$source_state"
	printf 'Generated: artifact=%s; pointer=%s; configuration=%s\n' "$artifact_state" "$pointer_state" "$config_state"
	printf 'Compatibility: running=%s; artifact=%s\n' "$running_compatibility" "$([[ $INPUT_LANGUAGES_ACTIVE_STATE == valid ]] && jq -r .compatibility_hash "$INPUT_LANGUAGES_ACTIVE" || printf unavailable)"
	printf 'Evidence: active=%s; pending=%s; recovery-required=%s; remove-cleanup=%s\n' "$INPUT_LANGUAGES_ACTIVE_STATE" "$INPUT_LANGUAGES_PENDING_STATE" "$INPUT_LANGUAGES_RECOVERY_STATE" "$INPUT_LANGUAGES_CLEANUP_STATE"
	if [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid ]]; then
		printf 'Build: compiler=%s; artifact-compatibility=%s; dependencies=%s\n' "$(jq -r .compiler "$INPUT_LANGUAGES_ACTIVE")" \
			"$(jq -r .compatibility_hash "$INPUT_LANGUAGES_ACTIVE")" "$(jq -r .dependencies "$INPUT_LANGUAGES_ACTIVE")"
	else
		printf 'Build: compiler=unavailable; artifact-compatibility=unavailable\n'
	fi
	if [[ $INPUT_LANGUAGES_PLUGIN_HEALTH_VALID == true ]]; then
		printf 'Plugin: health=%s; build=%s; source=%s; compatibility=%s\n' \
			"$(jq -r '.healthy' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")" "$(jq -r '.build_id' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")" \
			"$(jq -r '.source_id' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")" "$(jq -r '.compatibility_hash' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")"
		printf 'Keyboards: physical=%s; excluded=%s; synchronized=%s; active-language=%s\n' \
			"$(jq -r '.physical_keyboards | join(", ")' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")" "$(jq -r '.excluded_keyboards | join(", ")' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")" \
			"$(jq -r '.healthy' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")" "$(jq -r 'if .canonical_group == 0 then "US" else "RU" end' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")"
	else
		printf 'Plugin: unavailable or unhealthy\nKeyboards: runtime classification unavailable\n'
	fi
	printf 'Indicator: state=%s; custom-present=%s; custom-entries=%d; stock-entries=%d; link=%s; runtime-healthy=%s; ownership=%s\n' \
		"$INPUT_LANGUAGES_WIDGET_STATE" "$INPUT_LANGUAGES_WIDGET_PRESENT" "$INPUT_LANGUAGES_WIDGET_COUNT" "$INPUT_LANGUAGES_STOCK_WIDGET_COUNT" \
		"$INPUT_LANGUAGES_WIDGET_LINK_STATE" "$INPUT_LANGUAGES_INDICATOR_HEALTHY" "$([[ $INPUT_LANGUAGES_ACTIVE_STATE == valid ]] && printf lifecycle-clone || printf unrecorded)"
	printf 'Required next action: %s\n' "$action"
	printf 'Warning: Omarchy Hyprland refresh commands can write through Stow links into repository sources; review resulting Git changes.\n'
}

input_languages_header_hash() {
	local header=/usr/include/hyprland/src/version.h commit aq hu hg hc hlg
	[[ -f $header && ! -L $header ]] || return 1
	commit=$(grep '^#define GIT_COMMIT_HASH' "$header" | cut -d'"' -f2)
	aq=$(grep '^#define AQUAMARINE_VERSION ' "$header" | cut -d'"' -f2)
	hu=$(grep '^#define HYPRUTILS_VERSION ' "$header" | cut -d'"' -f2)
	hg=$(grep '^#define HYPRGRAPHICS_VERSION ' "$header" | cut -d'"' -f2)
	hc=$(grep '^#define HYPRCURSOR_VERSION ' "$header" | cut -d'"' -f2)
	hlg=$(grep '^#define HYPRLANG_VERSION ' "$header" | cut -d'"' -f2)
	printf '%s_aq_%s.%s_hu_%s.%s_hg_%s.%s_hc_%s.%s_hlg_%s.%s\n' "$commit" "${aq%%.*}" "$(cut -d. -f2 <<<"$aq")" \
		"${hu%%.*}" "$(cut -d. -f2 <<<"$hu")" "${hg%%.*}" "$(cut -d. -f2 <<<"$hg")" \
		"${hc%%.*}" "$(cut -d. -f2 <<<"$hc")" "${hlg%%.*}" "$(cut -d. -f2 <<<"$hlg")"
}

input_languages_hyprland_compiler() {
	LC_ALL=C /usr/bin/readelf -p .comment /usr/bin/Hyprland 2>/dev/null | grep -Eo 'GCC: \(GNU\) [0-9]+([.][0-9]+)+' | sed 's/.* //g' | sort -V | head -n 1
}

input_languages_stack_identity() {
	INPUT_LANGUAGES_RUNNING_HASH=$(input_languages_running_hash)
	INPUT_LANGUAGES_HEADER_HASH=$(input_languages_header_hash)
	[[ -n $INPUT_LANGUAGES_RUNNING_HASH && $INPUT_LANGUAGES_RUNNING_HASH == "$INPUT_LANGUAGES_HEADER_HASH" ]] || {
		printf 'Conflict: running Hyprland ABI %s does not match installed headers %s.\n' "${INPUT_LANGUAGES_RUNNING_HASH:-unknown}" "${INPUT_LANGUAGES_HEADER_HASH:-unknown}" >&2
		return 1
	}
	INPUT_LANGUAGES_COMPILER=$(/usr/bin/c++ -dumpfullversion -dumpversion) || return 1
	local built_compiler
	built_compiler=$(input_languages_hyprland_compiler)
	[[ -n $built_compiler && ${built_compiler%%.*} == "${INPUT_LANGUAGES_COMPILER%%.*}" ]] || {
		printf 'Conflict: Hyprland compiler GCC %s does not match installed GCC %s by family and major.\n' "${built_compiler:-unknown}" "$INPUT_LANGUAGES_COMPILER" >&2
		return 1
	}
	INPUT_LANGUAGES_COMPILER_WARNING=''
	if [[ $built_compiler != "$INPUT_LANGUAGES_COMPILER" ]]; then
		INPUT_LANGUAGES_COMPILER_WARNING="Hyprland was built with GCC $built_compiler; plugin will use GCC $INPUT_LANGUAGES_COMPILER."
		printf 'Warning: %s\n' "$INPUT_LANGUAGES_COMPILER_WARNING"
	fi
}

input_languages_build_artifact() {
	INPUT_LANGUAGES_SOURCE_ID=$(input_languages_source_identity) || return 1
	local dependency_versions build_input stage build_source snapshot_source build_log cleanup_ok=true generation existing_artifact
	dependency_versions=$(input_languages_dependency_identity) || return 1
	INPUT_LANGUAGES_DEPENDENCIES=$dependency_versions
	build_input="$INPUT_LANGUAGES_SOURCE_ID|$INPUT_LANGUAGES_COMPILER|$INPUT_LANGUAGES_HEADER_HASH|$dependency_versions|-std=c++23,-shared,-fPIC,-fno-gnu-unique"
	INPUT_LANGUAGES_BUILD_ID=$(printf '%s' "$build_input" | sha256sum | cut -d' ' -f1)
	if [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .build_id "$INPUT_LANGUAGES_ACTIVE") == "$INPUT_LANGUAGES_BUILD_ID" && $(jq -r .source_id "$INPUT_LANGUAGES_ACTIVE") == "$INPUT_LANGUAGES_SOURCE_ID" ]]; then
		existing_artifact=$(jq -r .artifact "$INPUT_LANGUAGES_ACTIVE")
		if input_languages_validate_active_file "$INPUT_LANGUAGES_ACTIVE" && input_languages_validate_artifact_binary "$existing_artifact" "$INPUT_LANGUAGES_BUILD_ID" "$INPUT_LANGUAGES_SOURCE_ID" "$INPUT_LANGUAGES_COMPILER"; then
			INPUT_LANGUAGES_ARTIFACT=$existing_artifact
			INPUT_LANGUAGES_ARTIFACT_DIR=${existing_artifact%/*}
			INPUT_LANGUAGES_ARTIFACT_SHA=$(jq -r .artifact_sha256 "$INPUT_LANGUAGES_ACTIVE")
			INPUT_LANGUAGES_WIDGET_SHA=$(jq -r .widget_sha256 "$INPUT_LANGUAGES_ACTIVE")
			return 0
		fi
		printf 'Warning: changed immutable artifact retained; rebuilding to a new path: %s\n' "${existing_artifact%/*}" >&2
	fi
	stage=$INPUT_LANGUAGES_ARTIFACTS/.build-$INPUT_LANGUAGES_BUILD_ID-$$-$RANDOM
	build_source=$stage/.source
	build_log=$INPUT_LANGUAGES_STATE/diagnostics/$INPUT_LANGUAGES_BUILD_ID-build.log
	[[ ! -e $stage && ! -L $stage ]] || return 1
	mkdir -m 0700 -- "$stage" || return 1
	mkdir -m 0700 -- "$build_source" || { rm -rf -- "$stage"; return 1; }
	cp -a -- "$INPUT_LANGUAGES_PLUGIN_SOURCE/." "$build_source/" || { rm -rf -- "$stage"; return 1; }
	snapshot_source=$(input_languages_source_identity_from "$build_source" "$INPUT_LANGUAGES_SOURCE") || { rm -rf -- "$stage"; return 1; }
	[[ $snapshot_source == "$INPUT_LANGUAGES_SOURCE_ID" ]] || { rm -rf -- "$stage"; printf 'Build preflight failed: repository source changed while the build snapshot was created.\n' >&2; return 1; }
	input_languages_write_content_atomic "$build_log" '' 600 || { rm -rf -- "$stage"; return 1; }
	if ! env -i HOME="$HOME" PATH=/usr/bin:/bin LC_ALL=C make --no-print-directory -C "$build_source" artifact OUTPUT_DIR="$stage" BUILD_ID="$INPUT_LANGUAGES_BUILD_ID" SOURCE_ID="$INPUT_LANGUAGES_SOURCE_ID" COMPILER_ID="$INPUT_LANGUAGES_COMPILER" CXX=/usr/bin/c++ >"$build_log" 2>&1; then
		/usr/bin/cat "$build_log" >&2
		if ! rm -rf -- "$stage"; then printf 'Warning: failed build stage is retained at %s\n' "$stage" >&2; fi
		return 1
	fi
	snapshot_source=$(input_languages_source_identity_from "$build_source" "$INPUT_LANGUAGES_SOURCE") || cleanup_ok=false
	if [[ $cleanup_ok == true && $snapshot_source != "$INPUT_LANGUAGES_SOURCE_ID" ]]; then cleanup_ok=false; fi
	if [[ $cleanup_ok == true ]] && ! input_languages_source_matches_build; then cleanup_ok=false; fi
	if [[ $cleanup_ok == true ]] && ! input_languages_dependencies_match_build; then cleanup_ok=false; fi
	if [[ $cleanup_ok == true ]] && ! rm -rf -- "$build_source"; then cleanup_ok=false; fi
	if ! input_languages_validate_artifact_binary "$stage/input-languages.so" "$INPUT_LANGUAGES_BUILD_ID" "$INPUT_LANGUAGES_SOURCE_ID" "$INPUT_LANGUAGES_COMPILER"; then cleanup_ok=false; fi
	if [[ $cleanup_ok != true ]]; then if ! rm -rf -- "$stage"; then printf 'Warning: invalid build stage is retained at %s\n' "$stage" >&2; fi; return 1; fi
	INPUT_LANGUAGES_ARTIFACT_SHA=$(sha256sum -- "$stage/input-languages.so"); INPUT_LANGUAGES_ARTIFACT_SHA=${INPUT_LANGUAGES_ARTIFACT_SHA%% *}
	INPUT_LANGUAGES_WIDGET_SHA=$(input_languages_widget_digest "$stage/$INPUT_LANGUAGES_WIDGET") || { if ! rm -rf -- "$stage"; then printf 'Warning: invalid build stage is retained at %s\n' "$stage" >&2; fi; return 1; }
	generation=$(input_languages_new_transaction) || { if ! rm -rf -- "$stage"; then printf 'Warning: valid build stage is retained at %s\n' "$stage" >&2; fi; return 1; }
	INPUT_LANGUAGES_ARTIFACT_DIR=$INPUT_LANGUAGES_ARTIFACTS/$INPUT_LANGUAGES_BUILD_ID-$INPUT_LANGUAGES_ARTIFACT_SHA-$generation
	INPUT_LANGUAGES_ARTIFACT=$INPUT_LANGUAGES_ARTIFACT_DIR/input-languages.so
	[[ ! -e $INPUT_LANGUAGES_ARTIFACT_DIR && ! -L $INPUT_LANGUAGES_ARTIFACT_DIR ]] || { if ! rm -rf -- "$stage"; then printf 'Warning: valid build stage is retained at %s\n' "$stage" >&2; fi; return 1; }
	jq -n --arg build_id "$INPUT_LANGUAGES_BUILD_ID" --arg source_id "$INPUT_LANGUAGES_SOURCE_ID" --arg compatibility_hash "$INPUT_LANGUAGES_HEADER_HASH" \
		--arg compiler "$INPUT_LANGUAGES_COMPILER" --arg dependencies "$dependency_versions" --arg artifact_sha256 "$INPUT_LANGUAGES_ARTIFACT_SHA" \
		--arg widget_sha256 "$INPUT_LANGUAGES_WIDGET_SHA" \
		'{version:1,build_id:$build_id,source_id:$source_id,compatibility_hash:$compatibility_hash,compiler:$compiler,dependencies:$dependencies,artifact_sha256:$artifact_sha256,widget_sha256:$widget_sha256,exports:["pluginAPIVersion","pluginExit","pluginInit"]}' \
		>"$stage/build.json" || { if ! rm -rf -- "$stage"; then printf 'Warning: incomplete build stage is retained at %s\n' "$stage" >&2; fi; return 1; }
	chmod -R a-w -- "$stage" || { if ! rm -rf -- "$stage"; then printf 'Warning: incomplete build stage is retained at %s\n' "$stage" >&2; fi; return 1; }
	mv -- "$stage" "$INPUT_LANGUAGES_ARTIFACT_DIR" || return 1
	input_languages_validate_artifact_values "$INPUT_LANGUAGES_ARTIFACT" "$INPUT_LANGUAGES_BUILD_ID" "$INPUT_LANGUAGES_SOURCE_ID" \
		"$INPUT_LANGUAGES_ARTIFACT_SHA" "$INPUT_LANGUAGES_HEADER_HASH" "$INPUT_LANGUAGES_COMPILER" "$dependency_versions" "$INPUT_LANGUAGES_WIDGET_SHA"
}

input_languages_write_content_atomic() {
	local target=$1 content=$2 mode=${3-600} directory temporary metadata
	directory=${target%/*}
	[[ -d $directory && ! -L $directory ]] || return 1
	temporary=$(mktemp "$directory/.${target##*/}.XXXXXX") || return 1
	if ! chmod "$mode" -- "$temporary" || ! printf '%s\n' "$content" >"$temporary" || ! mv -fT -- "$temporary" "$target"; then
		if ! rm -f -- "$temporary" 2>/dev/null; then printf 'Warning: failed temporary file is retained at %s\n' "$temporary" >&2; fi
		return 1
	fi
	[[ ! -e $temporary && ! -L $temporary && -f $target && ! -L $target && $(<"$target") == "$content" ]] || return 1
	metadata=$(stat -c '%u|%a' -- "$target") || return 1
	[[ $metadata == "$EUID|$mode" ]]
}

input_languages_write_json_atomic() {
	local target=$1 content=$2 kind=${3-} temporary directory validator
	directory=${target%/*}
	[[ -d $directory && ! -L $directory ]] || return 1
	temporary=$(mktemp "$directory/.${target##*/}.XXXXXX") || return 1
	if ! chmod 600 -- "$temporary" || ! printf '%s\n' "$content" >"$temporary"; then if ! rm -f -- "$temporary" 2>/dev/null; then printf 'Warning: failed temporary file is retained at %s\n' "$temporary" >&2; fi; return 1; fi
	case $kind in active) validator=input_languages_validate_active_file ;; pending) validator=input_languages_validate_pending_file ;; recovery) validator=input_languages_validate_recovery_file ;; cleanup) validator=input_languages_validate_cleanup_file ;; '') validator='' ;; *) if ! rm -f -- "$temporary"; then printf 'Warning: failed temporary file is retained at %s\n' "$temporary" >&2; fi; return 2 ;; esac
	if [[ -n $validator ]] && ! "$validator" "$temporary"; then if ! rm -f -- "$temporary"; then printf 'Warning: invalid temporary file is retained at %s\n' "$temporary" >&2; fi; return 1; fi
	if ! mv -fT -- "$temporary" "$target"; then if ! rm -f -- "$temporary" 2>/dev/null; then printf 'Warning: failed temporary file is retained at %s\n' "$temporary" >&2; fi; return 1; fi
	[[ ! -e $temporary && ! -L $temporary && -f $target && ! -L $target && $(<"$target") == "$content" ]] || return 1
	[[ -z $validator ]] || "$validator" "$target"
}

input_languages_remove_file_verified() {
	local path=$1 result=0
	rm -f -- "$path" || result=$?
	if [[ ! -e $path && ! -L $path ]]; then return 0; fi
	((result == 0)) || return "$result"
	return 1
}

input_languages_copy_atomic() {
	local source=$1 target=$2 content
	[[ -f $source && ! -L $source ]] || return 1
	content=$(<"$source") || return 1
	input_languages_write_content_atomic "$target" "$content" 600
}

input_languages_acquire_lock() {
	local context=$1 lock=$INPUT_LANGUAGES_STATE/operation.lock metadata path_identity descriptor_identity
	input_languages_paths_are_safe || return 1
	if [[ ! -e $lock && ! -L $lock ]]; then
		(umask 077; set -o noclobber; : >"$lock") 2>/dev/null || true
	fi
	[[ -f $lock && ! -L $lock ]] || { printf '%s blocked: operation lock is unsafe.\n' "$context" >&2; return 1; }
	metadata=$(stat -c '%u|%a|%h' -- "$lock") || return 1
	if [[ $metadata == "$EUID|644|1" ]]; then chmod 600 -- "$lock" || return 1; metadata=$(stat -c '%u|%a|%h' -- "$lock") || return 1; fi
	[[ $metadata == "$EUID|600|1" ]] || { printf '%s blocked: operation lock is unsafe.\n' "$context" >&2; return 1; }
	exec {input_languages_lock}<>"$lock" || return 1
	path_identity=$(stat -Lc '%d|%i|%h' -- "$lock") || { input_languages_unlock || true; return 1; }
	descriptor_identity=$(stat -Lc '%d|%i|%h' -- "/proc/$BASHPID/fd/$input_languages_lock") || { input_languages_unlock || true; return 1; }
	[[ $path_identity == "$descriptor_identity" && $descriptor_identity == *'|1' ]] || { printf '%s blocked: operation lock changed while opening.\n' "$context" >&2; input_languages_unlock || true; return 1; }
	flock -n "$input_languages_lock" || { printf '%s blocked: another Input Languages mutation is running.\n' "$context" >&2; input_languages_unlock || true; return 1; }
}

input_languages_unlock() {
	local descriptor=${input_languages_lock-}
	[[ $descriptor =~ ^[0-9]+$ ]] || return 0
	flock -u "$descriptor" 2>/dev/null || return 1
	eval "exec ${descriptor}>&-" || return 1
	input_languages_lock=''
}

input_languages_update_pending() {
	local phase=$1 widget_mutated=${2-} section=${3-} index=${4-} entry=${5-null} content
	if [[ -n $widget_mutated ]]; then
		content=$(jq -c --arg phase "$phase" --argjson mutated "$widget_mutated" --arg section "$section" --argjson index "$index" --argjson entry "$entry" \
			'.phase=$phase | .widget_mutated=$mutated | if $mutated then .widget_section=$section | .widget_index=$index | .widget_entry=$entry else .widget_section=null | .widget_index=null | .widget_entry=null end' "$INPUT_LANGUAGES_PENDING") || return 1
	else
		content=$(jq -c --arg phase "$phase" '.phase=$phase' "$INPUT_LANGUAGES_PENDING") || return 1
	fi
	input_languages_write_json_atomic "$INPUT_LANGUAGES_PENDING" "$content" pending
}

input_languages_update_pending_link() {
	local phase=$1 mutated=$2 content
	content=$(jq -c --arg phase "$phase" --argjson mutated "$mutated" '.phase=$phase | .link_mutated=$mutated' "$INPUT_LANGUAGES_PENDING") || return 1
	input_languages_write_json_atomic "$INPUT_LANGUAGES_PENDING" "$content" pending
}

input_languages_publish_pointer() {
	local artifact=$1 content
	printf -v content 'return "%s"' "$artifact"
	input_languages_write_content_atomic "$INPUT_LANGUAGES_POINTER" "$content" 600 && input_languages_pointer_matches "$artifact"
}

input_languages_create_backup() {
	local transaction=$1 transaction_root name
	transaction_root=$INPUT_LANGUAGES_STATE/backups/$transaction
	INPUT_LANGUAGES_BACKUP=$transaction_root/tree
	[[ ! -e $transaction_root && ! -L $transaction_root ]] || return 1
	mkdir -m 0700 -- "$transaction_root" || return 1
	mkdir -m 0700 -- "$INPUT_LANGUAGES_BACKUP" || return 1
	INPUT_LANGUAGES_BACKUP_EXISTED=false
	if [[ $INPUT_LANGUAGES_TREE_STATE == migratable ]]; then
		INPUT_LANGUAGES_BACKUP_EXISTED=true
		input_languages_exact_tree_inventory "$INPUT_LANGUAGES_LIVE" true || return 1
		for name in "${INPUT_LANGUAGES_FILES[@]}"; do cp -a -- "$INPUT_LANGUAGES_LIVE/$name" "$INPUT_LANGUAGES_BACKUP/$name" || return 1; done
		chmod --reference="$INPUT_LANGUAGES_LIVE" "$INPUT_LANGUAGES_BACKUP" || return 1
		touch --reference="$INPUT_LANGUAGES_LIVE" "$INPUT_LANGUAGES_BACKUP" || return 1
	elif [[ $INPUT_LANGUAGES_TREE_STATE != uninstalled ]]; then
		return 1
	fi
	input_languages_exact_tree_inventory "$INPUT_LANGUAGES_BACKUP" "$INPUT_LANGUAGES_BACKUP_EXISTED" || return 1
	INPUT_LANGUAGES_BACKUP_DIGEST=$(input_languages_tree_digest "$INPUT_LANGUAGES_BACKUP") || return 1
	INPUT_LANGUAGES_BACKUP_TRANSACTION=$transaction
}

input_languages_create_transaction_snapshots() {
	local transaction=$1 transaction_root active_digest pointer_digest
	transaction_root=$INPUT_LANGUAGES_STATE/backups/$transaction
	if [[ ! -d $transaction_root ]]; then mkdir -m 0700 -- "$transaction_root" || return 1; fi
	[[ -d $transaction_root && ! -L $transaction_root ]] || return 1
	INPUT_LANGUAGES_PRIOR_ACTIVE=null
	INPUT_LANGUAGES_PRIOR_ACTIVE_DIGEST=null
	INPUT_LANGUAGES_PRIOR_POINTER=null
	INPUT_LANGUAGES_PRIOR_POINTER_DIGEST=null
	if [[ $INPUT_LANGUAGES_TREE_STATE == linked ]]; then
		INPUT_LANGUAGES_PRIOR_ACTIVE=$transaction_root/prior-active.json
		INPUT_LANGUAGES_PRIOR_POINTER=$transaction_root/prior-pointer.lua
		input_languages_copy_atomic "$INPUT_LANGUAGES_ACTIVE" "$INPUT_LANGUAGES_PRIOR_ACTIVE" || return 1
		input_languages_copy_atomic "$INPUT_LANGUAGES_POINTER" "$INPUT_LANGUAGES_PRIOR_POINTER" || return 1
		input_languages_validate_active_evidence_file "$INPUT_LANGUAGES_PRIOR_ACTIVE" || return 1
		input_languages_pointer_file_matches "$INPUT_LANGUAGES_PRIOR_POINTER" "$(jq -r .artifact "$INPUT_LANGUAGES_PRIOR_ACTIVE")" || return 1
		active_digest=$(sha256sum -- "$INPUT_LANGUAGES_PRIOR_ACTIVE") || return 1
		pointer_digest=$(sha256sum -- "$INPUT_LANGUAGES_PRIOR_POINTER") || return 1
		INPUT_LANGUAGES_PRIOR_ACTIVE_DIGEST=${active_digest%% *}
		INPUT_LANGUAGES_PRIOR_POINTER_DIGEST=${pointer_digest%% *}
	fi
}

input_languages_remove_regular_tree() {
	local expected_digest=${1-} name current
	input_languages_exact_tree_inventory "$INPUT_LANGUAGES_LIVE" true || return 1
	if [[ -n $expected_digest ]]; then current=$(input_languages_tree_digest "$INPUT_LANGUAGES_LIVE") || return 1; [[ $current == "$expected_digest" ]] || return 1; fi
	for name in "${INPUT_LANGUAGES_FILES[@]}"; do input_languages_remove_file_verified "$INPUT_LANGUAGES_LIVE/$name" || return 1; done
	rmdir -- "$INPUT_LANGUAGES_LIVE" || return 1
	[[ ! -e $INPUT_LANGUAGES_LIVE && ! -L $INPUT_LANGUAGES_LIVE ]]
}

input_languages_transaction_tree_allowed() {
	local backup=$1 existed=$2 entry name target source target_real source_real target_metadata backup_metadata known
	[[ ! -e $INPUT_LANGUAGES_LIVE && ! -L $INPUT_LANGUAGES_LIVE ]] && return 0
	[[ -d $INPUT_LANGUAGES_LIVE && ! -L $INPUT_LANGUAGES_LIVE ]] || return 1
	while IFS= read -r entry; do
		known=false
		for name in "${INPUT_LANGUAGES_FILES[@]}"; do [[ $entry != "$name" ]] || known=true; done
		[[ $known == true ]] || return 1
	done < <(find "$INPUT_LANGUAGES_LIVE" -mindepth 1 -maxdepth 1 -printf '%f\n')
	for name in "${INPUT_LANGUAGES_FILES[@]}"; do
		target=$INPUT_LANGUAGES_LIVE/$name
		source=$INPUT_LANGUAGES_SOURCE/$name
		if [[ -L $target ]]; then
			target_real=$(readlink -f -- "$target" 2>/dev/null || true)
			source_real=$(readlink -f -- "$source" 2>/dev/null || true)
			[[ -n $target_real && $target_real == "$source_real" ]] || return 1
		elif [[ -e $target ]]; then
			[[ $existed == true && -f $target && ! -L $target && -f $backup/$name && ! -L $backup/$name ]] || return 1
			cmp -s -- "$target" "$backup/$name" || return 1
			target_metadata=$(stat -c '%a|%u|%g|%s|%Y' -- "$target") || return 1
			backup_metadata=$(stat -c '%a|%u|%g|%s|%Y' -- "$backup/$name") || return 1
			[[ $target_metadata == "$backup_metadata" ]] || return 1
		fi
	done
}

input_languages_clear_transaction_tree() {
	local backup=$1 existed=$2 name has_link=false
	input_languages_transaction_tree_allowed "$backup" "$existed" || return 1
	[[ -e $INPUT_LANGUAGES_LIVE || -L $INPUT_LANGUAGES_LIVE ]] || return 0
	for name in "${INPUT_LANGUAGES_FILES[@]}"; do [[ ! -L $INPUT_LANGUAGES_LIVE/$name ]] || has_link=true; done
	if [[ $has_link == true ]]; then
		stow --no-folding --delete --dir "$REPOSITORY_ROOT/config" --target "$HOME" hyprland >/dev/null || return 1
	fi
	input_languages_transaction_tree_allowed "$backup" "$existed" || return 1
	for name in "${INPUT_LANGUAGES_FILES[@]}"; do
		if [[ -e $INPUT_LANGUAGES_LIVE/$name || -L $INPUT_LANGUAGES_LIVE/$name ]]; then
			[[ -f $INPUT_LANGUAGES_LIVE/$name && ! -L $INPUT_LANGUAGES_LIVE/$name ]] || return 1
			input_languages_remove_file_verified "$INPUT_LANGUAGES_LIVE/$name" || return 1
		fi
	done
	if [[ -d $INPUT_LANGUAGES_LIVE ]]; then rmdir -- "$INPUT_LANGUAGES_LIVE" || return 1; fi
	[[ ! -e $INPUT_LANGUAGES_LIVE && ! -L $INPUT_LANGUAGES_LIVE ]]
}

input_languages_unlink_package() {
	input_languages_inspect_tree
	[[ $INPUT_LANGUAGES_TREE_STATE == linked ]] || return 1
	stow --no-folding --delete --dir "$REPOSITORY_ROOT/config" --target "$HOME" hyprland >/dev/null || return 1
	input_languages_inspect_tree
	[[ $INPUT_LANGUAGES_TREE_STATE == uninstalled ]]
}

input_languages_link_package() {
	stow --no-folding --dir "$REPOSITORY_ROOT/config" --target "$HOME" hyprland >/dev/null || return 1
	input_languages_inspect_tree
	[[ $INPUT_LANGUAGES_TREE_STATE == linked ]]
}

input_languages_restore_backup() {
	local backup=$1 existed=$2 digest=$3 transaction=${4-} name
	[[ -n $transaction ]] || transaction=${backup#"$INPUT_LANGUAGES_STATE/backups/"}; transaction=${transaction%%/*}
	input_languages_backup_valid "$backup" "$transaction" "$existed" "$digest" || return 1
	input_languages_clear_transaction_tree "$backup" "$existed" || return 1
	if [[ $existed == true ]]; then
		mkdir -p -m 0700 -- "$INPUT_LANGUAGES_LIVE" || return 1
		for name in "${INPUT_LANGUAGES_FILES[@]}"; do cp -a -- "$backup/$name" "$INPUT_LANGUAGES_LIVE/$name" || return 1; done
		chmod --reference="$backup" "$INPUT_LANGUAGES_LIVE" || return 1
		touch --reference="$backup" "$INPUT_LANGUAGES_LIVE" || return 1
		input_languages_exact_tree_inventory "$INPUT_LANGUAGES_LIVE" true || return 1
		[[ $(input_languages_tree_digest "$INPUT_LANGUAGES_LIVE") == "$digest" ]] || return 1
	else
		[[ ! -e $INPUT_LANGUAGES_LIVE && ! -L $INPUT_LANGUAGES_LIVE ]]
	fi
}

input_languages_current_autoreload() {
	local value
	value=$(hyprctl -j getoption misc:disable_autoreload 2>/dev/null | jq -r '.bool') || return 1
	[[ $value == true || $value == false ]] || return 1
	printf '%s\n' "$value"
}

input_languages_widget_link_matches() {
	local target=$1
	[[ -L $INPUT_LANGUAGES_WIDGET_LIVE && $(readlink -- "$INPUT_LANGUAGES_WIDGET_LIVE") == "$target" ]]
}

input_languages_publish_widget_link() {
	local target=$1 expected_current=${2-} temporary
	input_languages_widget_tree_valid "$target" 555 444 || return 1
	if input_languages_widget_link_matches "$target"; then return 0; fi
	if [[ -e $INPUT_LANGUAGES_WIDGET_LIVE || -L $INPUT_LANGUAGES_WIDGET_LIVE ]]; then
		[[ -n $expected_current ]] && input_languages_widget_link_matches "$expected_current" || return 1
	fi
	mkdir -p -- "$INPUT_LANGUAGES_PLUGIN_ROOT" || return 1
	temporary=$INPUT_LANGUAGES_PLUGIN_ROOT/.$INPUT_LANGUAGES_WIDGET.$$.${RANDOM}.link
	[[ ! -e $temporary && ! -L $temporary ]] || return 1
	ln -s -- "$target" "$temporary" || return 1
	if ! mv -fT -- "$temporary" "$INPUT_LANGUAGES_WIDGET_LIVE"; then
		rm -f -- "$temporary" 2>/dev/null || true
		return 1
	fi
	input_languages_widget_link_matches "$target"
}

input_languages_remove_widget_link() {
	local expected=$1
	input_languages_widget_link_matches "$expected" || return 1
	input_languages_remove_file_verified "$INPUT_LANGUAGES_WIDGET_LIVE"
}

input_languages_custom_widget_at_target() {
	((INPUT_LANGUAGES_WIDGET_COUNT == 1 && INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 0)) || return 1
	[[ $INPUT_LANGUAGES_WIDGET_SECTION == right && $INPUT_LANGUAGES_WIDGET_INDEX -eq 0 ]]
}

input_languages_custom_plugin_discovered() {
	local expected_enabled=${1-true} plugins
	plugins=$(omarchy plugin list --json 2>/dev/null) || return 1
	jq -e --arg id "$INPUT_LANGUAGES_WIDGET" --arg source "$INPUT_LANGUAGES_STOCK_WIDGET" --argjson expected "$expected_enabled" '
		type == "array" and ([.[] | select(.id == $id)] | length == 1) and
		any(.[]; .id == $id and .name == "Flag keyboard layout" and .kinds == ["bar-widget"] and .firstParty == false and .clonedFrom == $source and
			(.enabled == $expected or $expected == null))
	' <<<"$plugins" >/dev/null 2>&1
}

input_languages_custom_plugin_absent() {
	local plugins
	plugins=$(omarchy plugin list --json 2>/dev/null) || return 1
	jq -e --arg id "$INPUT_LANGUAGES_WIDGET" 'type == "array" and all(.[]; .id != $id)' <<<"$plugins" >/dev/null 2>&1
}

input_languages_wait_for_custom_plugin() {
	local state=$1 expected_enabled=${2-null} attempt
	local OMARCHY_SHELL_IPC_TIMEOUT=0.1s
	export OMARCHY_SHELL_IPC_TIMEOUT
	for ((attempt = 0; attempt < 40; attempt++)); do
		case $state in
			present) input_languages_custom_plugin_discovered "$expected_enabled" && return 0 ;;
			absent) input_languages_custom_plugin_absent && return 0 ;;
			*) return 2 ;;
		esac
		sleep 0.05
	done
	return 1
}

input_languages_reload_widget_registry() {
	if [[ $1 == true ]]; then
		omarchy restart shell >/dev/null
	else
		omarchy shell shell rescanPlugins >/dev/null
	fi
}

input_languages_activate_widget() {
	local expected_entry=$1
	omarchy plugin enable "$INPUT_LANGUAGES_WIDGET" --section right --index 0 >/dev/null || return 1
	input_languages_inspect_widget
	input_languages_custom_widget_at_target || return 1
	jq -en --argjson expected "$expected_entry" --argjson actual "$INPUT_LANGUAGES_WIDGET_ENTRY" '$actual == $expected' >/dev/null 2>&1 || return 1
	input_languages_wait_for_custom_plugin present true
}

input_languages_move_widget_to_target() {
	local expected_entry=$1
	omarchy bar move "$INPUT_LANGUAGES_WIDGET" --section right --index 0 >/dev/null || return 1
	input_languages_inspect_widget
	input_languages_custom_widget_at_target || return 1
	jq -en --argjson expected "$expected_entry" --argjson actual "$INPUT_LANGUAGES_WIDGET_ENTRY" '$actual == $expected' >/dev/null 2>&1
}

input_languages_restore_stock_widget() {
	local prior_present=$1 prior_section=${2-} prior_index=${3-} prior_entry=${4-null}
	input_languages_inspect_widget
	if ((INPUT_LANGUAGES_WIDGET_COUNT == 1)); then
		omarchy plugin disable "$INPUT_LANGUAGES_WIDGET" >/dev/null || return 1
	fi
	input_languages_inspect_widget
	((INPUT_LANGUAGES_WIDGET_COUNT == 0)) || return 1
	if [[ $prior_present == false ]]; then
		if ((INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 1)); then omarchy plugin disable "$INPUT_LANGUAGES_STOCK_WIDGET" >/dev/null || return 1; fi
		input_languages_stock_widget_matches false
		return
	fi
	((INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 1)) || return 1
	jq -en --argjson expected "$prior_entry" --argjson actual "$INPUT_LANGUAGES_STOCK_WIDGET_ENTRY" '$actual == $expected' >/dev/null 2>&1 || return 1
	if [[ $INPUT_LANGUAGES_STOCK_WIDGET_SECTION != "$prior_section" || $INPUT_LANGUAGES_STOCK_WIDGET_INDEX != "$prior_index" ]]; then
		omarchy bar move "$INPUT_LANGUAGES_STOCK_WIDGET" --section "$prior_section" --index "$prior_index" >/dev/null || return 1
	fi
	input_languages_stock_widget_matches true "$prior_section" "$prior_index" "$prior_entry"
}

input_languages_restore_widget_from_pending() {
	local prior_present prior_section prior_index prior_entry prior_id current_action
	prior_present=$(jq -r .prior_widget_present "$INPUT_LANGUAGES_PENDING")
	prior_section=$(jq -r '.prior_widget_section // empty' "$INPUT_LANGUAGES_PENDING")
	prior_index=$(jq -r '.prior_widget_index // empty' "$INPUT_LANGUAGES_PENDING")
	prior_entry=$(jq -c '.prior_widget_entry' "$INPUT_LANGUAGES_PENDING")
	current_action=$(jq -r .widget_action "$INPUT_LANGUAGES_PENDING")
	if input_languages_any_widget_matches "$prior_present" "$prior_section" "$prior_index" "$prior_entry"; then return 0; fi
	if [[ $prior_present == true ]]; then
		prior_id=$(jq -r .id <<<"$prior_entry")
		if [[ $prior_id == "$INPUT_LANGUAGES_WIDGET" ]]; then
			if input_languages_widget_matches true "$prior_section" "$prior_index" "$prior_entry"; then return 0; fi
			input_languages_inspect_widget
			if ((INPUT_LANGUAGES_WIDGET_COUNT == 0 && INPUT_LANGUAGES_STOCK_WIDGET_COUNT <= 1)); then
				input_languages_activate_widget "$prior_entry" || return 1
			else
				((INPUT_LANGUAGES_WIDGET_COUNT == 1 && INPUT_LANGUAGES_STOCK_WIDGET_COUNT == 0)) || return 1
				jq -en --argjson expected "$prior_entry" --argjson actual "$INPUT_LANGUAGES_WIDGET_ENTRY" '$actual == $expected' >/dev/null 2>&1 || return 1
			fi
			if [[ $INPUT_LANGUAGES_WIDGET_SECTION != "$prior_section" || $INPUT_LANGUAGES_WIDGET_INDEX != "$prior_index" ]]; then
				omarchy bar move "$INPUT_LANGUAGES_WIDGET" --section "$prior_section" --index "$prior_index" >/dev/null || return 1
			fi
			input_languages_widget_matches true "$prior_section" "$prior_index" "$prior_entry"
			return
		fi
		[[ $prior_id == "$INPUT_LANGUAGES_STOCK_WIDGET" && $current_action == activate ]] || return 1
		input_languages_restore_stock_widget true "$prior_section" "$prior_index" "$prior_entry"
		return
	fi
	[[ $current_action == activate ]] || return 1
	input_languages_restore_stock_widget false
}

input_languages_restore_pointer_from_pending() {
	local prior_pointer artifact
	prior_pointer=$(jq -r '.prior_pointer // empty' "$INPUT_LANGUAGES_PENDING")
	if [[ -n $prior_pointer ]]; then
		input_languages_copy_atomic "$prior_pointer" "$INPUT_LANGUAGES_POINTER" || return 1
		artifact=$(cut -d'"' -f2 "$prior_pointer") || return 1
		input_languages_pointer_matches "$artifact"
	else
		if [[ -e $INPUT_LANGUAGES_POINTER || -L $INPUT_LANGUAGES_POINTER ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_POINTER" || return 1; fi
		[[ ! -e $INPUT_LANGUAGES_POINTER && ! -L $INPUT_LANGUAGES_POINTER ]]
	fi
}

input_languages_restore_widget_link_from_pending() {
	local prior current artifact prior_active new_target mutated=false source_changed=false
	prior=$(jq -r '.prior_widget_link // empty' "$INPUT_LANGUAGES_PENDING")
	artifact=$(jq -r .artifact "$INPUT_LANGUAGES_PENDING")
	new_target=${artifact%/*}/$INPUT_LANGUAGES_WIDGET
	if [[ -n $prior ]]; then
		if input_languages_widget_link_matches "$prior"; then return 0; fi
		current=''
		if [[ -L $INPUT_LANGUAGES_WIDGET_LIVE ]]; then current=$(readlink -- "$INPUT_LANGUAGES_WIDGET_LIVE"); fi
		[[ -z $current || $current == "$new_target" ]] || return 1
		input_languages_publish_widget_link "$prior" "$current" || return 1
		mutated=true
		prior_active=$(jq -r '.prior_active // empty' "$INPUT_LANGUAGES_PENDING")
		if [[ -n $prior_active && $(jq -r .widget_sha256 "$prior_active") != "$(jq -r .widget_sha256 "${artifact%/*}/build.json")" ]]; then
			source_changed=true
		fi
	else
		if [[ ! -e $INPUT_LANGUAGES_WIDGET_LIVE && ! -L $INPUT_LANGUAGES_WIDGET_LIVE ]]; then return 0; fi
		input_languages_remove_widget_link "$new_target" || return 1
		mutated=true
	fi
	if [[ $mutated == true ]]; then
		input_languages_reload_widget_registry "$source_changed" || return 1
		if [[ -n $prior ]]; then input_languages_wait_for_custom_plugin present null
		else input_languages_wait_for_custom_plugin absent; fi
	fi
}

input_languages_restore_active_from_pending() {
	local prior_active
	prior_active=$(jq -r '.prior_active // empty' "$INPUT_LANGUAGES_PENDING")
	if [[ -n $prior_active ]]; then
		input_languages_copy_atomic "$prior_active" "$INPUT_LANGUAGES_ACTIVE" || return 1
		input_languages_validate_active_evidence_file "$INPUT_LANGUAGES_ACTIVE"
	else
		if [[ -e $INPUT_LANGUAGES_ACTIVE || -L $INPUT_LANGUAGES_ACTIVE ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_ACTIVE" || return 1; fi
		[[ ! -e $INPUT_LANGUAGES_ACTIVE && ! -L $INPUT_LANGUAGES_ACTIVE ]]
	fi
}

input_languages_verify_prior_state() {
	local prior_tree prior_active prior_group prior_autoreload prior_widget_present prior_widget_section prior_widget_index prior_widget_entry prior_widget_link current_source
	prior_tree=$(jq -r .prior_tree "$INPUT_LANGUAGES_PENDING")
	prior_active=$(jq -r '.prior_active // empty' "$INPUT_LANGUAGES_PENDING")
	prior_group=$(jq -r .prior_group "$INPUT_LANGUAGES_PENDING")
	prior_autoreload=$(jq -r .prior_autoreload "$INPUT_LANGUAGES_PENDING")
	prior_widget_present=$(jq -r .prior_widget_present "$INPUT_LANGUAGES_PENDING")
	prior_widget_section=$(jq -r '.prior_widget_section // empty' "$INPUT_LANGUAGES_PENDING")
	prior_widget_index=$(jq -r '.prior_widget_index // empty' "$INPUT_LANGUAGES_PENDING")
	prior_widget_entry=$(jq -c .prior_widget_entry "$INPUT_LANGUAGES_PENDING")
	prior_widget_link=$(jq -r '.prior_widget_link // empty' "$INPUT_LANGUAGES_PENDING")
	input_languages_inspect_tree
	[[ $INPUT_LANGUAGES_TREE_STATE == "$prior_tree" ]] || return 1
	[[ $(input_languages_current_autoreload) == "$prior_autoreload" ]] || return 1
	input_languages_any_widget_matches "$prior_widget_present" "$prior_widget_section" "$prior_widget_index" "$prior_widget_entry" || return 1
	if [[ -n $prior_widget_link ]]; then input_languages_widget_link_matches "$prior_widget_link" || return 1
	else [[ ! -e $INPUT_LANGUAGES_WIDGET_LIVE && ! -L $INPUT_LANGUAGES_WIDGET_LIVE ]] || return 1
	fi
	if [[ -n $prior_active ]]; then
		current_source=$(input_languages_source_identity) || return 1
		[[ $current_source == "$(jq -r .source_id "$prior_active")" ]] || return 1
		input_languages_validate_active_file "$INPUT_LANGUAGES_ACTIVE" || return 1
		[[ $(sha256sum -- "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) == "$(sha256sum -- "$prior_active" | cut -d' ' -f1)" ]] || return 1
		input_languages_pointer_matches "$(jq -r .artifact "$prior_active")" || return 1
		input_languages_read_control_state || return 1
		input_languages_custom_plugin_discovered true || return 1
		jq -e --arg build "$(jq -r .build_id "$prior_active")" --arg source "$(jq -r .source_id "$prior_active")" --arg compatibility "$(jq -r .compatibility_hash "$prior_active")" --argjson group "$prior_group" \
			'.healthy == true and .build_id == $build and .source_id == $source and .compatibility_hash == $compatibility and ($group == null or .canonical_group == $group)' \
			<<<"$INPUT_LANGUAGES_PLUGIN_HEALTH" >/dev/null 2>&1
	else
		[[ ! -e $INPUT_LANGUAGES_ACTIVE && ! -L $INPUT_LANGUAGES_ACTIVE && ! -e $INPUT_LANGUAGES_POINTER && ! -L $INPUT_LANGUAGES_POINTER ]] || return 1
		input_languages_plugin_unloaded
	fi
}

input_languages_plugin_unloaded() {
	local plugins
	plugins=$(hyprctl -j plugin list 2>/dev/null) || return 1
	jq -e '
		type == "array" and
		all(.[]; type == "object" and (.name | type == "string") and (.author | type == "string")) and
		all(.[]; .name != "Input Languages" or .author != "dotfiles")
	' <<<"$plugins" >/dev/null 2>&1
}

input_languages_plugin_matches_receipt() {
	local receipt=$1
	jq -e --arg build "$(jq -r .build_id "$receipt")" --arg source "$(jq -r .source_id "$receipt")" \
		--arg compatibility "$(jq -r .compatibility_hash "$receipt")" '
		(.healthy | type == "boolean") and (.canonical_group == 0 or .canonical_group == 1) and
		.build_id == $build and .source_id == $source and .compatibility_hash == $compatibility
	' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH" >/dev/null 2>&1
}

input_languages_shell_seams_compatible() {
	local seam expected actual root=${DOTFILES_TEST_OMARCHY_ROOT:-/usr/share/omarchy}
	while IFS=$'\t' read -r seam expected; do
		[[ -f $root/$seam ]] || return 1
		actual=$(sha256sum -- "$root/$seam") || return 1
		[[ ${actual%% *} == "$expected" ]] || return 1
	done < <(jq -r '.seams | to_entries[] | [.key,.value] | @tsv' "$INPUT_LANGUAGES_PLUGIN_SOURCE/migration-baseline.json")
}

input_languages_record_recovery() {
	local transaction=$1 phase=$2 content
	content=$(jq -cn --arg transaction_id "$transaction" --arg failed_phase "$phase" --arg pending "$INPUT_LANGUAGES_PENDING" \
		'{version:2,state:"recovery-required",transaction_id:$transaction_id,failed_phase:$failed_phase,pending:$pending}') || return 1
	input_languages_write_json_atomic "$INPUT_LANGUAGES_RECOVERY" "$content" recovery
}

input_languages_rollback_pending() {
	local transaction operation prior_tree backup backup_transaction existed digest prior_group prior_autoreload failed=''
	input_languages_validate_pending_file "$INPUT_LANGUAGES_PENDING" || return 1
	transaction=$(jq -r .transaction_id "$INPUT_LANGUAGES_PENDING")
	operation=$(jq -r .operation "$INPUT_LANGUAGES_PENDING")
	prior_tree=$(jq -r .prior_tree "$INPUT_LANGUAGES_PENDING")
	backup=$(jq -r .backup "$INPUT_LANGUAGES_PENDING")
	backup_transaction=$(jq -r .backup_transaction_id "$INPUT_LANGUAGES_PENDING")
	existed=$(jq -r .backup_existed "$INPUT_LANGUAGES_PENDING")
	digest=$(jq -r .backup_digest "$INPUT_LANGUAGES_PENDING")
	prior_group=$(jq -r .prior_group "$INPUT_LANGUAGES_PENDING")
	prior_autoreload=$(jq -r .prior_autoreload "$INPUT_LANGUAGES_PENDING")
	if [[ $prior_tree == linked ]]; then
		input_languages_clear_transaction_tree "$backup" "$existed" || failed=clear-current
		[[ -n $failed ]] || input_languages_link_package || failed=relink-prior
	else
		input_languages_restore_backup "$backup" "$existed" "$digest" "$backup_transaction" || failed=restore-tree
	fi
	[[ -n $failed ]] || input_languages_restore_pointer_from_pending || failed=restore-pointer
	if [[ -z $failed && $operation == remove ]]; then input_languages_restore_widget_link_from_pending || failed=restore-widget-link; fi
	[[ -n $failed ]] || input_languages_restore_widget_from_pending || failed=restore-widget
	if [[ -z $failed && $operation == apply ]]; then input_languages_restore_widget_link_from_pending || failed=restore-widget-link; fi
	[[ -n $failed ]] || hyprctl keyword misc:disable_autoreload "$prior_autoreload" >/dev/null || failed=restore-autoreload
	[[ -n $failed ]] || hyprctl reload >/dev/null || failed=reload
	if [[ -z $failed && $prior_tree == linked && $prior_group != null ]]; then
		input_languages_reset_group "$prior_group" || failed=restore-group
	fi
	[[ -n $failed ]] || input_languages_restore_active_from_pending || failed=restore-active
	[[ -n $failed ]] || input_languages_verify_prior_state || failed=verify-prior
	if [[ -z $failed ]]; then
		input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING" || failed=remove-pending
	fi
	if [[ -z $failed ]]; then
		printf '%s failed; rollback verified.\n' "${operation^}"
		return 0
	fi
	input_languages_record_recovery "$transaction" "$operation-rollback-$failed" || \
		printf 'Recovery evidence publication also failed; valid pending evidence remains at %s\n' "$INPUT_LANGUAGES_PENDING" >&2
	printf 'Recovery required: %s rollback failed at %s. Evidence retained at %s\n' "${operation^}" "$failed" "$INPUT_LANGUAGES_STATE" >&2
	return 1
}

input_languages_recovery_plan() {
	local operation transaction phase prior_tree
	operation=$(jq -r .operation "$INPUT_LANGUAGES_PENDING")
	transaction=$(jq -r .transaction_id "$INPUT_LANGUAGES_PENDING")
	phase=$(jq -r .phase "$INPUT_LANGUAGES_PENDING")
	prior_tree=$(jq -r .prior_tree "$INPUT_LANGUAGES_PENDING")
	printf 'Plan: recover interrupted Input Languages %s transaction %s from phase %s.\n' "$operation" "$transaction" "$phase"
	printf 'Plan: re-inspect and restore prior tree=%s, exact pointer/artifact identity, flag-widget clone link, prior bar entry, autoreload value, canonical group, and active receipt.\n' "$prior_tree"
	printf 'Plan: reload once, verify the complete prior filesystem/runtime/lifecycle state, then and only then remove pending evidence.\n'
	printf 'Plan: on any unproved restoration retain pending evidence and publish recovery-required; preserve backups, artifacts, archives, and diagnostics.\n'
}

input_languages_recovery_preflight() {
	local command prior_active running expected
	for command in stow hyprctl jq flock sha256sum diff omarchy; do
		command -v "$command" >/dev/null 2>&1 || { printf 'Recovery blocked: required command is unavailable: %s\n' "$command" >&2; return 1; }
	done
	input_languages_shell_seams_compatible || { printf 'Recovery blocked: current Omarchy Shell mutation seams differ from the reviewed baseline.\n' >&2; return 1; }
	prior_active=$(jq -r '.prior_active // empty' "$INPUT_LANGUAGES_PENDING") || return 1
	[[ -n $prior_active ]] || return 0
	input_languages_validate_active_file "$prior_active" || { printf 'Recovery blocked: the prior active artifact or lifecycle evidence is no longer valid.\n' >&2; return 1; }
	running=$(input_languages_running_hash) || return 1
	expected=$(jq -r .compatibility_hash "$prior_active") || return 1
	[[ -n $running && $running == "$expected" ]] || {
		printf 'Recovery blocked: running Hyprland compatibility %s does not match the prior artifact %s.\n' "${running:-unavailable}" "$expected" >&2
		return 1
	}
}

input_languages_reconcile_pending() {
	local approved=${1-false} snapshot recovery_snapshot='' cleanup_snapshot='' transaction operation had_recovery=false had_cleanup=false
	input_languages_set_paths
	input_languages_paths_are_safe || return 1
	if ! input_languages_validate_pending_file "$INPUT_LANGUAGES_PENDING"; then
		printf 'Conflict: pending Input Languages evidence is invalid; no recovery mutation was attempted.\n' >&2
		return 1
	fi
	input_languages_inspect
	[[ $INPUT_LANGUAGES_PENDING_STATE == valid ]] || { printf 'Conflict: pending evidence or current recovery state changed during inspection.\n' >&2; return 1; }
	[[ $INPUT_LANGUAGES_RECOVERY_STATE != invalid ]] || { printf 'Recovery blocked: recovery-required evidence is invalid.\n' >&2; return 1; }
	input_languages_report_mutation_compatibility || return 1
	input_languages_recovery_preflight || return 1
	if [[ $INPUT_LANGUAGES_RECOVERY_STATE == valid ]]; then had_recovery=true; fi
	transaction=$(jq -r .transaction_id "$INPUT_LANGUAGES_PENDING")
	operation=$(jq -r .operation "$INPUT_LANGUAGES_PENDING")
	if [[ $INPUT_LANGUAGES_CLEANUP_STATE != absent ]]; then
		[[ $INPUT_LANGUAGES_CLEANUP_STATE == valid && $operation == remove && $(jq -r .transaction_id "$INPUT_LANGUAGES_CLEANUP") == "$transaction" ]] || {
			printf 'Recovery blocked: Remove cleanup evidence does not match the pending transaction.\n' >&2
			return 1
		}
		had_cleanup=true
	fi
	snapshot=$(sha256sum -- "$INPUT_LANGUAGES_PENDING") || return 1
	if [[ $had_recovery == true ]]; then recovery_snapshot=$(sha256sum -- "$INPUT_LANGUAGES_RECOVERY") || return 1; fi
	if [[ $had_cleanup == true ]]; then cleanup_snapshot=$(sha256sum -- "$INPUT_LANGUAGES_CLEANUP") || return 1; fi
	input_languages_recovery_plan
	if [[ $approved != true ]] && ! wizard_confirm 'Recover this interrupted Input Languages transaction?'; then
		printf 'Recovery canceled; pending evidence is unchanged.\n'
		return 0
	fi
	input_languages_acquire_lock Recovery || return 1
	input_languages_inspect
	if [[ $INPUT_LANGUAGES_PENDING_STATE != valid || $(sha256sum -- "$INPUT_LANGUAGES_PENDING" | cut -d' ' -f1) != "${snapshot%% *}" ||
		( $had_recovery == true && ( $INPUT_LANGUAGES_RECOVERY_STATE != valid || $(sha256sum -- "$INPUT_LANGUAGES_RECOVERY" | cut -d' ' -f1) != "${recovery_snapshot%% *}" ) ) ||
		( $had_recovery == false && $INPUT_LANGUAGES_RECOVERY_STATE != absent ) ||
		( $had_cleanup == true && ( $INPUT_LANGUAGES_CLEANUP_STATE != valid || $(sha256sum -- "$INPUT_LANGUAGES_CLEANUP" | cut -d' ' -f1) != "${cleanup_snapshot%% *}" ) ) ||
		( $had_cleanup == false && $INPUT_LANGUAGES_CLEANUP_STATE != absent ) ]]; then
		printf 'Recovery blocked: lifecycle or live state changed after approval.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	if [[ $had_cleanup == true ]] && ! input_languages_remove_file_verified "$INPUT_LANGUAGES_CLEANUP"; then
		printf 'Recovery blocked: Remove cleanup evidence could not be retired before rollback.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	if [[ $had_recovery == true ]] && ! input_languages_remove_file_verified "$INPUT_LANGUAGES_RECOVERY"; then
		printf 'Recovery blocked: recovery-required evidence could not be retired before the verified retry.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	if input_languages_rollback_pending; then
		input_languages_unlock || return 1
		printf 'Interrupted transaction %s reconciled by verified rollback. Run the requested operation again.\n' "$transaction"
		return 0
	fi
	input_languages_unlock || true
	return 1
}

input_languages_apply_plan() {
	local packages_shown=${1-false}
	printf 'Inspected: Hyprland tree=%s; active receipt=%s; widget=%s; widget link=%s; target=right[0].\n' \
		"$INPUT_LANGUAGES_TREE_STATE" "$INPUT_LANGUAGES_ACTIVE_STATE" "$INPUT_LANGUAGES_WIDGET_STATE" "$INPUT_LANGUAGES_WIDGET_LINK_STATE"
	printf 'Paths: package source=%s; live tree=%s; artifact root=%s; active pointer=%s; lifecycle state=%s.\n' \
		"$INPUT_LANGUAGES_SOURCE" "$INPUT_LANGUAGES_LIVE" "$INPUT_LANGUAGES_ARTIFACTS" "$INPUT_LANGUAGES_POINTER" "$INPUT_LANGUAGES_STATE"
	if [[ $INPUT_LANGUAGES_TREE_STATE == linked ]]; then
		printf 'Plan: retain and reuse the verified original pre-first-Apply backup at %s.\n' "$(jq -r .backup "$INPUT_LANGUAGES_ACTIVE")"
	elif [[ $INPUT_LANGUAGES_TREE_STATE == migratable ]]; then
		printf 'Plan: create and verify one timestamped backup of the complete live tree under %s/backups before migration.\n' "$INPUT_LANGUAGES_STATE"
	else
		printf 'Plan: record the absent pre-Apply tree under %s/backups so Remove can restore that absence exactly.\n' "$INPUT_LANGUAGES_STATE"
	fi
	printf 'Plan: fixed desktop layouts US then Russian, empty variants, and no XKB group-toggle option.\n'
	printf 'Plan: verify Omarchy 4.0.2-4.x, packaged defaults, plugin interfaces, compiler, headers, complete ABI hash, canonical no-follow paths, lifecycle evidence, and Stow ownership.\n'
	if [[ $packages_shown != true ]]; then print_arch_package_plan; fi
	printf 'Plan: validate source, build or reuse one immutable exact-stack plugin artifact containing the complete flag-widget clone, and retain build diagnostics.\n'
	printf 'Plan: atomically publish pending recovery evidence, pause autoreload, and link every package file with Stow --no-folding.\n'
	printf 'Plan: publish the clone as one directory link, rescan on first publication or restart Shell for changed active QML, place the flag at right[0] immediately after the Shell-pinned system tray, issue one Hyprland reload, verify discovery/configuration/keyboards/indicator geometry, reset changed Apply to US, then atomically publish the active receipt.\n'
	printf 'Plan: on failure restore and verify the complete prior tree, artifact/plugin identity, widget state, autoreload value, canonical group, and active receipt; otherwise record recovery-required.\n'
	printf 'Plan: retain repository sources, Arch packages, backups, immutable artifacts, archived evidence, and diagnostics.\n'
	printf 'Warning: Omarchy Hyprland refresh commands can write through Stow links into repository sources.\n'
}

input_languages_static_preflight() {
	bash "$REPOSITORY_ROOT/lib/dotfiles/input-languages-validator.sh" "$REPOSITORY_ROOT" /usr/share/omarchy --static-only >/dev/null
}

input_languages_prepare_apply() {
	INPUT_LANGUAGES_PREPARED_RESULT=''
	input_languages_inspect
	input_languages_paths_are_safe || return 1
	if [[ $INPUT_LANGUAGES_RECOVERY_STATE != absent ]]; then
		if [[ $INPUT_LANGUAGES_RECOVERY_STATE == valid && $INPUT_LANGUAGES_PENDING_STATE == valid ]]; then INPUT_LANGUAGES_PREPARED_RESULT=pending; return 0; fi
		printf 'Apply blocked: recovery-required evidence is %s at %s.\n' "$INPUT_LANGUAGES_RECOVERY_STATE" "$INPUT_LANGUAGES_RECOVERY" >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_PENDING_STATE != absent ]]; then
		if [[ $INPUT_LANGUAGES_PENDING_STATE == valid ]]; then INPUT_LANGUAGES_PREPARED_RESULT=pending; return 0; fi
		printf 'Apply blocked: pending lifecycle evidence is invalid.\n' >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_CLEANUP_STATE != absent ]]; then
		if [[ $INPUT_LANGUAGES_CLEANUP_STATE == valid ]]; then INPUT_LANGUAGES_PREPARED_RESULT=cleanup; return 0; fi
		printf 'Apply blocked: Remove cleanup evidence is invalid.\n' >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_ACTIVE_STATE == invalid ]]; then
		printf 'Apply blocked: active lifecycle evidence is invalid.\n' >&2
		return 1
	fi
	[[ $INPUT_LANGUAGES_SUPPORTED == true ]] || { printf 'Apply blocked: Omarchy %s is outside supported range %s through 4.x.\n' "$INPUT_LANGUAGES_VERSION" "$INPUT_LANGUAGES_MIN_OMARCHY" >&2; return 1; }
	if input_languages_exact_noop; then INPUT_LANGUAGES_PREPARED_RESULT=noop; return 0; fi
	if [[ $INPUT_LANGUAGES_TREE_STATE == conflict || ( $INPUT_LANGUAGES_TREE_STATE == linked && $INPUT_LANGUAGES_ACTIVE_STATE != valid ) ]]; then
		printf 'Apply blocked: complete Hyprland tree state is %s and cannot be safely adopted.\n' "$INPUT_LANGUAGES_TREE_STATE" >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_TREE_STATE == linked && $INPUT_LANGUAGES_PLUGIN_HEALTH_VALID != true ]]; then
		printf 'Apply blocked: the current plugin group is unavailable, so rollback could not preserve the active language.\n' >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_TREE_STATE != linked && ( -e $INPUT_LANGUAGES_POINTER || -L $INPUT_LANGUAGES_POINTER ) ]]; then
		printf 'Apply blocked: an unowned artifact pointer exists outside a valid linked lifecycle.\n' >&2
		return 1
	fi
	[[ $INPUT_LANGUAGES_WIDGET_STATE == valid ]] || { printf 'Apply blocked: effective Omarchy Shell bar state is missing or invalid.\n' >&2; return 1; }
	[[ -z $INPUT_LANGUAGES_COMPETING_CLONES ]] || { printf 'Apply blocked: competing keyboard-layout clones are present: %s\n' "$INPUT_LANGUAGES_COMPETING_CLONES" >&2; return 1; }
	[[ $INPUT_LANGUAGES_WIDGET_LINK_STATE != conflict ]] || { printf 'Apply blocked: the live dotfiles.keyboard-layout path is foreign or partial.\n' >&2; return 1; }
	if [[ $INPUT_LANGUAGES_TREE_STATE == linked ]]; then
		input_languages_active_widget_matches_receipt || { printf 'Apply blocked: the receipt-owned flag widget entry changed or moved.\n' >&2; return 1; }
	else
		((INPUT_LANGUAGES_WIDGET_COUNT == 0 && INPUT_LANGUAGES_STOCK_WIDGET_COUNT <= 1)) || { printf 'Apply blocked: keyboard-layout bar entries are ambiguous or foreign.\n' >&2; return 1; }
		if [[ $INPUT_LANGUAGES_STOCK_WIDGET_PRESENT == true ]] && ! jq -e 'type == "object" and .id == "omarchy.keyboard-layout"' <<<"$INPUT_LANGUAGES_STOCK_WIDGET_ENTRY" >/dev/null; then
			printf 'Apply blocked: the stock keyboard-layout entry must be an object so it can be restored exactly.\n' >&2
			return 1
		fi
	fi
	input_languages_static_preflight || { printf 'Apply blocked: Input Languages source or integration-seam validation failed.\n' >&2; return 1; }
	local command all_stack_tools=true
	for command in c++ readelf hyprctl; do command -v "$command" >/dev/null 2>&1 || all_stack_tools=false; done
	if [[ $all_stack_tools == true ]]; then input_languages_stack_identity || return 1; fi
	if [[ $INPUT_LANGUAGES_TREE_STATE != migratable ]]; then
		stow --no-folding --simulate --dir "$REPOSITORY_ROOT/config" --target "$HOME" hyprland >/dev/null || { printf 'Apply blocked: Input Languages Stow simulation failed.\n' >&2; return 1; }
	fi
	INPUT_LANGUAGES_PREPARED_RESULT=change
}

input_languages_make_pending() {
	local operation=$1 transaction=$2 artifact=$3 widget_action=$4 prior_group=$5 prior_autoreload=$6 content
	local prior_widget_present=false prior_widget_section=null prior_widget_index=null prior_widget_entry=null prior_widget_link=null
	if [[ $INPUT_LANGUAGES_WIDGET_PRESENT == true ]]; then
		prior_widget_present=true
		prior_widget_section=$(jq -Rn --arg value "$INPUT_LANGUAGES_WIDGET_SECTION" '$value')
		prior_widget_index=$INPUT_LANGUAGES_WIDGET_INDEX
		prior_widget_entry=$INPUT_LANGUAGES_WIDGET_ENTRY
	elif [[ $INPUT_LANGUAGES_STOCK_WIDGET_PRESENT == true ]]; then
		prior_widget_present=true
		prior_widget_section=$(jq -Rn --arg value "$INPUT_LANGUAGES_STOCK_WIDGET_SECTION" '$value')
		prior_widget_index=$INPUT_LANGUAGES_STOCK_WIDGET_INDEX
		prior_widget_entry=$INPUT_LANGUAGES_STOCK_WIDGET_ENTRY
	fi
	if [[ $INPUT_LANGUAGES_TREE_STATE == linked ]] && input_languages_widget_link_matches "$(jq -r .widget_source "$INPUT_LANGUAGES_ACTIVE")"; then
		prior_widget_link=$(jq -Rn --arg value "$(jq -r .widget_source "$INPUT_LANGUAGES_ACTIVE")" '$value')
	fi
	content=$(jq -cn --arg operation "$operation" --arg transaction "$transaction" --arg backup_transaction "$INPUT_LANGUAGES_BACKUP_TRANSACTION" \
		--arg backup "$INPUT_LANGUAGES_BACKUP" --arg backup_digest "$INPUT_LANGUAGES_BACKUP_DIGEST" --arg artifact "$artifact" --arg prior_tree "$INPUT_LANGUAGES_TREE_STATE" \
		--argjson backup_existed "$INPUT_LANGUAGES_BACKUP_EXISTED" --argjson prior_active "$([[ $INPUT_LANGUAGES_PRIOR_ACTIVE == null ]] && printf null || jq -Rn --arg value "$INPUT_LANGUAGES_PRIOR_ACTIVE" '$value')" \
		--argjson prior_active_digest "$([[ $INPUT_LANGUAGES_PRIOR_ACTIVE_DIGEST == null ]] && printf null || jq -Rn --arg value "$INPUT_LANGUAGES_PRIOR_ACTIVE_DIGEST" '$value')" \
		--argjson prior_pointer "$([[ $INPUT_LANGUAGES_PRIOR_POINTER == null ]] && printf null || jq -Rn --arg value "$INPUT_LANGUAGES_PRIOR_POINTER" '$value')" \
		--argjson prior_pointer_digest "$([[ $INPUT_LANGUAGES_PRIOR_POINTER_DIGEST == null ]] && printf null || jq -Rn --arg value "$INPUT_LANGUAGES_PRIOR_POINTER_DIGEST" '$value')" \
		--argjson prior_group "$prior_group" --argjson prior_autoreload "$prior_autoreload" --argjson prior_widget_present "$prior_widget_present" \
		--argjson prior_widget_section "$prior_widget_section" --argjson prior_widget_index "$prior_widget_index" --argjson prior_widget_entry "$prior_widget_entry" \
		--argjson prior_widget_link "$prior_widget_link" --arg widget_action "$widget_action" '
		{version:2,operation:$operation,transaction_id:$transaction,phase:"prepared",backup_transaction_id:$backup_transaction,backup:$backup,backup_digest:$backup_digest,backup_existed:$backup_existed,
		 artifact:$artifact,prior_tree:$prior_tree,prior_active:$prior_active,prior_active_digest:$prior_active_digest,prior_pointer:$prior_pointer,prior_pointer_digest:$prior_pointer_digest,
		 prior_group:$prior_group,prior_autoreload:$prior_autoreload,prior_widget_present:$prior_widget_present,prior_widget_section:$prior_widget_section,prior_widget_index:$prior_widget_index,
		 prior_widget_entry:$prior_widget_entry,prior_widget_link:$prior_widget_link,widget_action:$widget_action,widget_mutated:false,widget_section:null,widget_index:null,widget_entry:null,link_mutated:false}') || return 1
	input_languages_write_json_atomic "$INPUT_LANGUAGES_PENDING" "$content" pending
}

input_languages_publish_active() {
	local transaction=$1 widget_section widget_index widget_entry prior_stock_section=null prior_stock_index=null prior_stock_entry=null content
	widget_section=$(jq -Rn --arg value "$INPUT_LANGUAGES_WIDGET_SECTION" '$value')
	widget_index=$INPUT_LANGUAGES_WIDGET_INDEX
	widget_entry=$INPUT_LANGUAGES_WIDGET_ENTRY
	if [[ $INPUT_LANGUAGES_PRIOR_STOCK_PRESENT == true ]]; then
		prior_stock_section=$(jq -Rn --arg value "$INPUT_LANGUAGES_PRIOR_STOCK_SECTION" '$value')
		prior_stock_index=$INPUT_LANGUAGES_PRIOR_STOCK_INDEX
		prior_stock_entry=$INPUT_LANGUAGES_PRIOR_STOCK_ENTRY
	fi
	content=$(jq -cn --arg transaction "$transaction" --arg backup_transaction "$INPUT_LANGUAGES_BACKUP_TRANSACTION" --arg source "$INPUT_LANGUAGES_SOURCE_ID" --arg build "$INPUT_LANGUAGES_BUILD_ID" \
		--arg artifact "$INPUT_LANGUAGES_ARTIFACT" --arg artifact_sha "$INPUT_LANGUAGES_ARTIFACT_SHA" --arg compatibility "$INPUT_LANGUAGES_HEADER_HASH" --arg compiler "$INPUT_LANGUAGES_COMPILER" \
		--arg compiler_warning "$INPUT_LANGUAGES_COMPILER_WARNING" --arg dependencies "$INPUT_LANGUAGES_DEPENDENCIES" --arg backup "$INPUT_LANGUAGES_BACKUP" --arg backup_digest "$INPUT_LANGUAGES_BACKUP_DIGEST" \
		--arg widget_sha "$INPUT_LANGUAGES_WIDGET_SHA" --arg widget_source "$INPUT_LANGUAGES_ARTIFACT_DIR/$INPUT_LANGUAGES_WIDGET" \
		--argjson backup_existed "$INPUT_LANGUAGES_BACKUP_EXISTED" --argjson widget_section "$widget_section" --argjson widget_index "$widget_index" --argjson widget_entry "$widget_entry" \
		--argjson prior_stock_present "$INPUT_LANGUAGES_PRIOR_STOCK_PRESENT" --argjson prior_stock_section "$prior_stock_section" --argjson prior_stock_index "$prior_stock_index" --argjson prior_stock_entry "$prior_stock_entry" '
		{version:2,operation:"active",transaction_id:$transaction,backup_transaction_id:$backup_transaction,source_id:$source,build_id:$build,artifact:$artifact,artifact_sha256:$artifact_sha,widget_sha256:$widget_sha,
		 compatibility_hash:$compatibility,compiler:$compiler,compiler_warning:$compiler_warning,dependencies:$dependencies,backup:$backup,backup_digest:$backup_digest,backup_existed:$backup_existed,
		 widget_source:$widget_source,widget_section:$widget_section,widget_index:$widget_index,widget_entry:$widget_entry,prior_stock_present:$prior_stock_present,
		 prior_stock_section:$prior_stock_section,prior_stock_index:$prior_stock_index,prior_stock_entry:$prior_stock_entry}') || return 1
	input_languages_write_json_atomic "$INPUT_LANGUAGES_ACTIVE" "$content" active
}

apply_input_languages() {
	local approved=false packages_prepared=false recovery_approved=false expect_noop=false option
	for option in "$@"; do
		case $option in
			--yes) approved=true ;;
			--packages-prepared) packages_prepared=true ;;
			--recovery-approved) recovery_approved=true ;;
			--expect-noop) expect_noop=true ;;
			*) printf 'Error: unknown Input Languages Apply option: %s\n' "$option" >&2; return 2 ;;
		esac
	done
	input_languages_prepare_apply || return 1
	if [[ $expect_noop == true && $INPUT_LANGUAGES_PREPARED_RESULT != noop ]]; then
		printf 'Apply blocked: Input Languages changed after its exact no-op was inspected; review a new complete plan.\n' >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_PREPARED_RESULT == pending ]]; then input_languages_reconcile_pending "$recovery_approved"; return; fi
	if [[ $INPUT_LANGUAGES_PREPARED_RESULT == cleanup ]]; then input_languages_reconcile_cleanup "$recovery_approved"; return; fi
	if [[ $INPUT_LANGUAGES_PREPARED_RESULT == noop ]]; then printf 'Exact no-op: Portable input language setup is healthy; active language preserved.\n'; return 0; fi
	if [[ $packages_prepared != true ]]; then plan_arch_packages hyprland; fi
	if [[ $packages_prepared != true || $approved != true ]]; then input_languages_apply_plan; fi
	if [[ $approved != true ]] && ! wizard_confirm 'Apply this complete Input Languages plan?'; then printf 'Apply canceled; no changes made.\n'; return 0; fi
	if [[ $packages_prepared != true ]]; then
		install_missing_arch_packages 'Settings -> Input Languages -> Apply' || return 1
		verify_arch_packages 'Settings -> Input Languages -> Apply' || return 1
	fi
	local required
	for required in c++ make pkg-config readelf nm file xkbcli luac stow hyprctl jq flock sha256sum diff omarchy; do
		command -v "$required" >/dev/null 2>&1 || { printf 'Build preflight failed: missing command after package preparation: %s\n' "$required" >&2; return 1; }
	done
	bash "$REPOSITORY_ROOT/lib/dotfiles/input-languages-validator.sh" || { printf 'Build preflight failed: Input Languages source validation failed.\n' >&2; return 1; }
	input_languages_stack_identity || return 1
	input_languages_prepare_roots || return 1
	input_languages_acquire_lock Apply || return 1
	input_languages_prepare_apply || { input_languages_unlock || true; return 1; }
	if [[ $INPUT_LANGUAGES_PREPARED_RESULT == noop ]]; then input_languages_unlock || return 1; printf 'Exact no-op: Portable input language setup is healthy; active language preserved.\n'; return 0; fi
	[[ $INPUT_LANGUAGES_PREPARED_RESULT == change ]] || { input_languages_unlock || true; return 1; }
	input_languages_build_artifact || { printf 'Build preflight failed; live setup is unchanged.\n' >&2; input_languages_unlock || true; return 1; }
	if ! input_languages_source_matches_build || ! input_languages_dependencies_match_build; then
		printf 'Build preflight failed: repository source or stack inputs changed during the artifact build; the built artifact was not activated.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	local transaction prior_group=null prior_autoreload widget_action=none failed='' prior_widget_link='' target_widget_link expected_widget_entry
	local link_mutated=false source_changed=false needs_plugin_rescan=false
	transaction=$(input_languages_new_transaction) || { input_languages_unlock || true; return 1; }
	if [[ $INPUT_LANGUAGES_TREE_STATE == linked ]]; then
		INPUT_LANGUAGES_BACKUP_TRANSACTION=$(jq -r .backup_transaction_id "$INPUT_LANGUAGES_ACTIVE")
		INPUT_LANGUAGES_BACKUP=$(jq -r .backup "$INPUT_LANGUAGES_ACTIVE")
		INPUT_LANGUAGES_BACKUP_DIGEST=$(jq -r .backup_digest "$INPUT_LANGUAGES_ACTIVE")
		INPUT_LANGUAGES_BACKUP_EXISTED=$(jq -r .backup_existed "$INPUT_LANGUAGES_ACTIVE")
		INPUT_LANGUAGES_PRIOR_STOCK_PRESENT=$(jq -r .prior_stock_present "$INPUT_LANGUAGES_ACTIVE")
		INPUT_LANGUAGES_PRIOR_STOCK_SECTION=$(jq -r '.prior_stock_section // empty' "$INPUT_LANGUAGES_ACTIVE")
		INPUT_LANGUAGES_PRIOR_STOCK_INDEX=$(jq -r '.prior_stock_index // empty' "$INPUT_LANGUAGES_ACTIVE")
		INPUT_LANGUAGES_PRIOR_STOCK_ENTRY=$(jq -c .prior_stock_entry "$INPUT_LANGUAGES_ACTIVE")
		prior_widget_link=$(jq -r .widget_source "$INPUT_LANGUAGES_ACTIVE")
		expected_widget_entry=$(jq -c .widget_entry "$INPUT_LANGUAGES_ACTIVE")
		if [[ $(jq -r .widget_sha256 "$INPUT_LANGUAGES_ACTIVE") != "$INPUT_LANGUAGES_WIDGET_SHA" ]]; then source_changed=true; fi
		if ! input_languages_custom_plugin_discovered true; then needs_plugin_rescan=true; fi
		input_languages_create_transaction_snapshots "$transaction" || { input_languages_unlock || true; return 1; }
	else
		INPUT_LANGUAGES_PRIOR_STOCK_PRESENT=$INPUT_LANGUAGES_STOCK_WIDGET_PRESENT
		INPUT_LANGUAGES_PRIOR_STOCK_SECTION=$INPUT_LANGUAGES_STOCK_WIDGET_SECTION
		INPUT_LANGUAGES_PRIOR_STOCK_INDEX=$INPUT_LANGUAGES_STOCK_WIDGET_INDEX
		INPUT_LANGUAGES_PRIOR_STOCK_ENTRY=$INPUT_LANGUAGES_STOCK_WIDGET_ENTRY
		if [[ $INPUT_LANGUAGES_STOCK_WIDGET_PRESENT == true ]]; then
			expected_widget_entry=$(jq -c --arg id "$INPUT_LANGUAGES_WIDGET" '.id=$id' <<<"$INPUT_LANGUAGES_STOCK_WIDGET_ENTRY")
		else
			expected_widget_entry=$(jq -cn --arg id "$INPUT_LANGUAGES_WIDGET" '{id:$id}')
		fi
		widget_action=activate
		input_languages_create_backup "$transaction" || { input_languages_unlock || true; return 1; }
		input_languages_create_transaction_snapshots "$transaction" || { input_languages_unlock || true; return 1; }
	fi
	if [[ $INPUT_LANGUAGES_TREE_STATE == linked ]]; then
		input_languages_read_health || { printf 'Apply blocked: the current plugin group became unavailable before mutation.\n' >&2; input_languages_unlock || true; return 1; }
		prior_group=$(jq -r .canonical_group <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")
	fi
	prior_autoreload=$(input_languages_current_autoreload) || { input_languages_unlock || true; return 1; }
	if ! input_languages_source_matches_build || ! input_languages_dependencies_match_build; then
		printf 'Apply blocked: repository source or stack inputs changed before live mutation; the built artifact was not activated.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	input_languages_make_pending apply "$transaction" "$INPUT_LANGUAGES_ARTIFACT" "$widget_action" "$prior_group" "$prior_autoreload" || { input_languages_unlock || true; return 1; }
	input_languages_validate_pending_file "$INPUT_LANGUAGES_PENDING" || { input_languages_unlock || true; return 1; }
	if ! input_languages_publish_pointer "$INPUT_LANGUAGES_ARTIFACT"; then failed=publish-pointer
	elif ! hyprctl keyword misc:disable_autoreload true >/dev/null; then failed=pause-autoreload
	elif ! input_languages_update_pending pointer-changed; then failed=record-pointer
	fi
	if [[ -z $failed && $INPUT_LANGUAGES_TREE_STATE == migratable ]]; then input_languages_remove_regular_tree "$INPUT_LANGUAGES_BACKUP_DIGEST" || failed=remove-migration-tree; fi
	if [[ -z $failed ]]; then input_languages_link_package || failed=link-package; fi
	if [[ -z $failed ]]; then input_languages_update_pending tree-changed || failed=record-tree; fi
	target_widget_link=$INPUT_LANGUAGES_ARTIFACT_DIR/$INPUT_LANGUAGES_WIDGET
	if [[ -z $failed ]] && ! input_languages_widget_link_matches "$target_widget_link"; then
		if input_languages_publish_widget_link "$target_widget_link" "$prior_widget_link"; then
			link_mutated=true
			input_languages_update_pending_link link-changed true || failed=record-widget-link
		else failed=publish-widget-link
		fi
	fi
	if [[ -z $failed && ( $link_mutated == true || $needs_plugin_rescan == true ) ]]; then
		input_languages_reload_widget_registry "$source_changed" || failed=$([[ $source_changed == true ]] && printf restart-shell || printf rescan-plugins)
		if [[ -z $failed ]]; then input_languages_update_pending shell-reloaded || failed=record-shell-reload; fi
	fi
	if [[ -z $failed ]]; then input_languages_wait_for_custom_plugin present null || failed=discover-widget; fi
	if [[ -z $failed && $widget_action == activate ]]; then
		if input_languages_activate_widget "$expected_widget_entry"; then
			input_languages_update_pending widget-changed true "$INPUT_LANGUAGES_WIDGET_SECTION" "$INPUT_LANGUAGES_WIDGET_INDEX" "$INPUT_LANGUAGES_WIDGET_ENTRY" || failed=record-widget
		else failed=activate-widget
		fi
	elif [[ -z $failed ]]; then
		input_languages_inspect_widget
		if ! input_languages_custom_widget_at_target; then
			if input_languages_move_widget_to_target "$expected_widget_entry"; then
				input_languages_update_pending widget-changed true "$INPUT_LANGUAGES_WIDGET_SECTION" "$INPUT_LANGUAGES_WIDGET_INDEX" "$INPUT_LANGUAGES_WIDGET_ENTRY" || failed=record-widget
			else failed=move-widget
			fi
		fi
	fi
	if [[ -z $failed ]]; then hyprctl keyword misc:disable_autoreload "$prior_autoreload" >/dev/null || failed=restore-autoreload; fi
	if [[ -z $failed ]]; then hyprctl reload >/dev/null || failed=reload; fi
	if [[ -z $failed ]]; then input_languages_update_pending reloaded || failed=record-reload; fi
	if [[ -z $failed ]]; then
		input_languages_inspect
		local errors
		errors=$(hyprctl configerrors 2>/dev/null) || failed=config-inspection
		if [[ -z $failed && ( $INPUT_LANGUAGES_TREE_STATE != linked || $INPUT_LANGUAGES_INDICATOR_HEALTHY != true || -n $errors ) ]]; then failed=live-verification; fi
		if [[ -z $failed ]] && ! input_languages_widget_link_matches "$target_widget_link"; then failed=live-widget-link; fi
		if [[ -z $failed ]] && ! input_languages_custom_widget_at_target; then failed=widget-placement; fi
		if [[ -z $failed ]] && ! input_languages_custom_plugin_discovered true; then failed=widget-discovery; fi
		if [[ -z $failed ]] && ! jq -e --arg build "$INPUT_LANGUAGES_BUILD_ID" --arg source "$INPUT_LANGUAGES_SOURCE_ID" --arg compatibility "$INPUT_LANGUAGES_HEADER_HASH" \
			'.healthy == true and .build_id == $build and .source_id == $source and .compatibility_hash == $compatibility and (.physical_keyboards | length > 0)' \
			<<<"$INPUT_LANGUAGES_PLUGIN_HEALTH" >/dev/null 2>&1; then failed=plugin-verification; fi
	fi
	if [[ -z $failed ]] && ! input_languages_reset_group 0; then failed=reset-us; fi
	if [[ -z $failed ]]; then
		input_languages_read_health || failed=reset-verification
		if [[ -z $failed ]] && [[ $(jq -r .canonical_group <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH") != 0 ]]; then failed=reset-verification; fi
	fi
	if [[ -z $failed ]] && { ! input_languages_source_matches_build || ! input_languages_dependencies_match_build; }; then failed=build-input-drift; fi
	if [[ -z $failed ]]; then
		input_languages_publish_active "$transaction" || failed=publish-active
	fi
	if [[ -z $failed ]]; then input_languages_update_pending active-published || failed=record-active; fi
	if [[ -z $failed ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING" || failed=remove-pending; fi
	if [[ -n $failed ]]; then
		printf 'Apply failed at %s; restoring the verified prior state.\n' "$failed" >&2
		input_languages_rollback_pending || true
		input_languages_unlock || true
		return 1
	fi
	input_languages_unlock || return 1
	printf 'Apply completed: Portable input language setup is healthy and reset to US.\n'
}

input_languages_remove_plan() {
	local backup=$1
	printf 'Plan: compare current repository Hyprland source with the verified pre-Apply backup at %s; later source edits will not be merged.\n' "$backup"
	printf '%s\n' 'Backup-to-current-source difference:'
	local diff_status=0
	diff -ruN -- "$backup" "$INPUT_LANGUAGES_SOURCE" || diff_status=$?
	((diff_status <= 1)) || return 1
	printf 'Plan: atomically publish pending evidence, pause autoreload, unload the receipt artifact, restore the exact pre-Apply stock widget state, remove the exact clone link, unlink the complete package, and restore the exact regular backup.\n'
	printf 'Plan: issue one reload, verify plugin absence and complete restored ownership/runtime state, then atomically archive active and pending evidence before deleting them.\n'
	printf 'Plan: before the cleanup commit, rollback failures to the linked package, prior artifact/plugin, whole-directory widget link, custom bar entry, autoreload, and language; afterward resume exact receipt-owned artifact and clone-subtree deletion from durable cleanup evidence.\n'
	printf 'Plan: retain repository sources, Arch packages, original backups, archived lifecycle evidence, and diagnostics.\n'
}

input_languages_archive_remove_evidence() {
	local transaction=$1 archive_root stage final active_digest pending_digest
	archive_root=$INPUT_LANGUAGES_STATE/archive
	stage=$archive_root/.remove-$transaction-$$-$RANDOM
	final=$archive_root/$transaction-remove
	[[ ! -e $stage && ! -L $stage && ! -e $final && ! -L $final ]] || return 1
	mkdir -m 0700 -- "$stage" || return 1
	cp -a -- "$INPUT_LANGUAGES_ACTIVE" "$stage/active.json" || return 1
	cp -a -- "$INPUT_LANGUAGES_PENDING" "$stage/pending.json" || return 1
	chmod 600 -- "$stage/active.json" "$stage/pending.json" || return 1
	active_digest=$(sha256sum -- "$INPUT_LANGUAGES_ACTIVE") || return 1
	pending_digest=$(sha256sum -- "$INPUT_LANGUAGES_PENDING") || return 1
	[[ $(sha256sum -- "$stage/active.json" | cut -d' ' -f1) == "${active_digest%% *}" && $(sha256sum -- "$stage/pending.json" | cut -d' ' -f1) == "${pending_digest%% *}" ]] || return 1
	input_languages_validate_active_file "$stage/active.json" || return 1
	input_languages_validate_pending_file "$stage/pending.json" || return 1
	mv -- "$stage" "$final" || return 1
	[[ -d $final && ! -L $final && -f $final/active.json && -f $final/pending.json ]]
}

input_languages_publish_cleanup() {
	local transaction=$1 artifact=$2 archive active_digest pending_digest build artifact_sha content
	archive=$INPUT_LANGUAGES_STATE/archive/$transaction-remove
	[[ -d $archive && ! -L $archive ]] || return 1
	active_digest=$(sha256sum -- "$archive/active.json" | cut -d' ' -f1) || return 1
	pending_digest=$(sha256sum -- "$archive/pending.json" | cut -d' ' -f1) || return 1
	build=$(jq -r .build_id "$archive/active.json") || return 1
	artifact_sha=$(jq -r .artifact_sha256 "$archive/active.json") || return 1
	content=$(jq -cn --arg transaction "$transaction" --arg archive "$archive" --arg active_digest "$active_digest" --arg pending_digest "$pending_digest" \
		--arg artifact "$artifact" --arg build "$build" --arg artifact_sha "$artifact_sha" \
		'{version:2,state:"remove-cleanup",transaction_id:$transaction,archive:$archive,archive_active_digest:$active_digest,archive_pending_digest:$pending_digest,artifact:$artifact,build_id:$build,artifact_sha256:$artifact_sha}') || return 1
	input_languages_write_json_atomic "$INPUT_LANGUAGES_CLEANUP" "$content" cleanup
}

input_languages_stage_artifact_removal() {
	local artifact=$1 transaction=$2 build=$3 artifact_sha=$4 directory removals stage
	directory=${artifact%/*}
	removals=$INPUT_LANGUAGES_DATA/removals
	stage=$(input_languages_artifact_stage_path "$artifact" "$transaction" "$build" "$artifact_sha") || return 1
	input_languages_validate_artifact_self "$artifact" cleanup || return 1
	input_languages_owned_directory_safe "$removals" || return 1
	mkdir -p -m 0700 -- "$removals" || return 1
	chmod 0700 -- "$removals" || return 1
	[[ ! -e $stage && ! -L $stage ]] || return 1
	chmod u+w -- "$directory" || return 1
	if ! mv -- "$directory" "$stage"; then
		chmod a-w -- "$directory" || return 1
		return 1
	fi
	[[ ! -e $directory && ! -L $directory && -d $stage && ! -L $stage ]] || return 1
	INPUT_LANGUAGES_REMOVED_ARTIFACT_STAGE=$stage
}

input_languages_delete_staged_artifact() {
	local stage=$1 artifact=$2 transaction=$3 build=$4 expected_sha=$5 expected_stage
	expected_stage=$(input_languages_artifact_stage_path "$artifact" "$transaction" "$build" "$expected_sha") || return 1
	[[ $stage == "$expected_stage" ]] || return 1
	input_languages_staged_artifact_safe "$stage" "$build" "$expected_sha" || return 1
	find "$stage" -type d -exec chmod u+w -- {} + || return 1
	if [[ -e $stage/$INPUT_LANGUAGES_WIDGET || -L $stage/$INPUT_LANGUAGES_WIDGET ]]; then rm -rf -- "$stage/$INPUT_LANGUAGES_WIDGET" || return 1; fi
	if [[ -e $stage/input-languages.so || -L $stage/input-languages.so ]]; then input_languages_remove_file_verified "$stage/input-languages.so" || return 1; fi
	if [[ -e $stage/build.json || -L $stage/build.json ]]; then input_languages_remove_file_verified "$stage/build.json" || return 1; fi
	rmdir -- "$stage" || return 1
}

input_languages_reconcile_cleanup() {
	local approved=${1-false} snapshot transaction artifact build artifact_sha stage
	input_languages_set_paths
	input_languages_paths_are_safe || return 1
	input_languages_detect_support
	input_languages_validate_cleanup_file "$INPUT_LANGUAGES_CLEANUP" || { printf 'Cleanup blocked: Remove cleanup evidence is invalid.\n' >&2; return 1; }
	input_languages_report_mutation_compatibility || return 1
	transaction=$(jq -r .transaction_id "$INPUT_LANGUAGES_CLEANUP")
	artifact=$(jq -r .artifact "$INPUT_LANGUAGES_CLEANUP")
	build=$(jq -r .build_id "$INPUT_LANGUAGES_CLEANUP")
	artifact_sha=$(jq -r .artifact_sha256 "$INPUT_LANGUAGES_CLEANUP")
	stage=$(input_languages_artifact_stage_path "$artifact" "$transaction" "$build" "$artifact_sha") || return 1
	snapshot=$(sha256sum -- "$INPUT_LANGUAGES_CLEANUP" | cut -d' ' -f1) || return 1
	printf 'Plan: resume interrupted Input Languages Remove artifact cleanup for transaction %s.\n' "$transaction"
	printf 'Plan: verify archived evidence, remove only artifact build %s, and clear cleanup evidence after deletion is proved.\n' "$build"
	if [[ $approved != true ]] && ! wizard_confirm 'Resume this receipt-backed Input Languages Remove cleanup?'; then
		printf 'Cleanup canceled; receipt-backed evidence is unchanged.\n'
		return 0
	fi
	input_languages_prepare_roots || return 1
	input_languages_acquire_lock Cleanup || return 1
	input_languages_inspect
	if [[ $INPUT_LANGUAGES_CLEANUP_STATE != valid || $(sha256sum -- "$INPUT_LANGUAGES_CLEANUP" | cut -d' ' -f1) != "$snapshot" ||
		$INPUT_LANGUAGES_ACTIVE_STATE != absent || $INPUT_LANGUAGES_PENDING_STATE != absent || $INPUT_LANGUAGES_RECOVERY_STATE != absent ]]; then
		printf 'Cleanup blocked: lifecycle state changed after approval.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	if [[ -e $artifact || -L $artifact ]]; then
		input_languages_stage_artifact_removal "$artifact" "$transaction" "$build" "$artifact_sha" || { input_languages_unlock || true; return 1; }
	fi
	if [[ -e $stage || -L $stage ]]; then
		input_languages_delete_staged_artifact "$stage" "$artifact" "$transaction" "$build" "$artifact_sha" || { input_languages_unlock || true; return 1; }
	fi
	[[ ! -e $artifact && ! -L $artifact && ! -e $stage && ! -L $stage ]] || { input_languages_unlock || true; return 1; }
	input_languages_remove_file_verified "$INPUT_LANGUAGES_CLEANUP" || { input_languages_unlock || true; return 1; }
	input_languages_unlock || return 1
	printf 'Interrupted Remove cleanup completed; archived lifecycle evidence remains at %s.\n' "$INPUT_LANGUAGES_STATE/archive/$transaction-remove"
}

remove_input_languages() {
	local approved=false recovery_approved=false option
	for option in "$@"; do case $option in --yes) approved=true ;; --recovery-approved) recovery_approved=true ;; *) printf 'Error: unknown Input Languages Remove option: %s\n' "$option" >&2; return 2 ;; esac; done
	input_languages_inspect
	input_languages_paths_are_safe || return 1
	if [[ ( $INPUT_LANGUAGES_TREE_STATE == uninstalled || $INPUT_LANGUAGES_TREE_STATE == migratable ) && $INPUT_LANGUAGES_ACTIVE_STATE == absent && ! -e $INPUT_LANGUAGES_POINTER && ! -L $INPUT_LANGUAGES_POINTER && \
		$INPUT_LANGUAGES_PENDING_STATE == absent && $INPUT_LANGUAGES_RECOVERY_STATE == absent && $INPUT_LANGUAGES_CLEANUP_STATE == absent && \
		! -e $INPUT_LANGUAGES_WIDGET_LIVE && ! -L $INPUT_LANGUAGES_WIDGET_LIVE && $INPUT_LANGUAGES_WIDGET_COUNT == 0 && -z $INPUT_LANGUAGES_COMPETING_CLONES ]] && \
		input_languages_plugin_unloaded; then
		printf 'Nothing to remove: Portable input language setup is cleanly uninstalled.\n'; return 0
	fi
	input_languages_report_mutation_compatibility || return 1
	if [[ $INPUT_LANGUAGES_RECOVERY_STATE != absent ]]; then
		if [[ $INPUT_LANGUAGES_RECOVERY_STATE == valid && $INPUT_LANGUAGES_PENDING_STATE == valid ]]; then input_languages_reconcile_pending "$recovery_approved"; return; fi
		printf 'Remove blocked: recovery-required evidence is %s and must be resolved first.\n' "$INPUT_LANGUAGES_RECOVERY_STATE" >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_PENDING_STATE != absent ]]; then
		[[ $INPUT_LANGUAGES_PENDING_STATE == valid ]] || { printf 'Remove blocked: pending lifecycle evidence is invalid.\n' >&2; return 1; }
		input_languages_reconcile_pending "$recovery_approved"; return
	fi
	if [[ $INPUT_LANGUAGES_CLEANUP_STATE != absent ]]; then
		[[ $INPUT_LANGUAGES_CLEANUP_STATE == valid ]] || { printf 'Remove blocked: Remove cleanup evidence is invalid.\n' >&2; return 1; }
		input_languages_reconcile_cleanup "$recovery_approved"; return
	fi
	[[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $INPUT_LANGUAGES_TREE_STATE == linked ]] || { printf 'Remove blocked: a valid active receipt and complete linked Hyprland tree are required.\n' >&2; return 1; }
	input_languages_validate_active_file "$INPUT_LANGUAGES_ACTIVE" || { printf 'Remove blocked: the receipt-owned artifact is changed or unavailable; run Apply to rebuild it first.\n' >&2; return 1; }
	input_languages_read_control_state || { printf 'Remove blocked: the plugin identity or canonical group is unavailable, so rollback could not preserve the active language.\n' >&2; return 1; }
	input_languages_plugin_matches_receipt "$INPUT_LANGUAGES_ACTIVE" || { printf 'Remove blocked: the loaded Input Languages build does not match the active receipt.\n' >&2; return 1; }
	input_languages_shell_seams_compatible || { printf 'Remove blocked: the current Omarchy Shell mutation seams differ from the reviewed baseline.\n' >&2; return 1; }
	[[ $INPUT_LANGUAGES_WIDGET_LINK_STATE == exact && -z $INPUT_LANGUAGES_COMPETING_CLONES ]] || { printf 'Remove blocked: the receipt-owned flag-widget link or clone registry is not exact.\n' >&2; return 1; }
	input_languages_active_widget_matches_receipt || { printf 'Remove blocked: the receipt-owned flag widget changed or moved.\n' >&2; return 1; }
	input_languages_custom_plugin_discovered true || { printf 'Remove blocked: the receipt-owned flag widget is not discovered and enabled.\n' >&2; return 1; }
	local command
	for command in stow hyprctl jq flock diff sha256sum omarchy; do
		command -v "$command" >/dev/null 2>&1 || { printf 'Remove blocked: required command is unavailable: %s\n' "$command" >&2; return 1; }
	done
	local backup backup_transaction backup_digest backup_existed artifact build artifact_sha widget_source widget_section widget_index widget_entry approved_active_digest
	local prior_stock_present prior_stock_section prior_stock_index prior_stock_entry
	backup=$(jq -r .backup "$INPUT_LANGUAGES_ACTIVE")
	backup_transaction=$(jq -r .backup_transaction_id "$INPUT_LANGUAGES_ACTIVE")
	backup_digest=$(jq -r .backup_digest "$INPUT_LANGUAGES_ACTIVE")
	backup_existed=$(jq -r .backup_existed "$INPUT_LANGUAGES_ACTIVE")
	artifact=$(jq -r .artifact "$INPUT_LANGUAGES_ACTIVE")
	build=$(jq -r .build_id "$INPUT_LANGUAGES_ACTIVE")
	artifact_sha=$(jq -r .artifact_sha256 "$INPUT_LANGUAGES_ACTIVE")
	widget_source=$(jq -r .widget_source "$INPUT_LANGUAGES_ACTIVE")
	widget_section=$(jq -r '.widget_section // empty' "$INPUT_LANGUAGES_ACTIVE")
	widget_index=$(jq -r '.widget_index // empty' "$INPUT_LANGUAGES_ACTIVE")
	widget_entry=$(jq -c .widget_entry "$INPUT_LANGUAGES_ACTIVE")
	prior_stock_present=$(jq -r .prior_stock_present "$INPUT_LANGUAGES_ACTIVE")
	prior_stock_section=$(jq -r '.prior_stock_section // empty' "$INPUT_LANGUAGES_ACTIVE")
	prior_stock_index=$(jq -r '.prior_stock_index // empty' "$INPUT_LANGUAGES_ACTIVE")
	prior_stock_entry=$(jq -c .prior_stock_entry "$INPUT_LANGUAGES_ACTIVE")
	input_languages_backup_valid "$backup" "$backup_transaction" "$backup_existed" "$backup_digest" || { printf 'Remove blocked: pre-Apply backup cannot be verified.\n' >&2; return 1; }
	input_languages_pointer_matches "$artifact" || { printf 'Remove blocked: active artifact pointer is not exact.\n' >&2; return 1; }
	input_languages_widget_link_matches "$widget_source" || { printf 'Remove blocked: active flag-widget link is not exact.\n' >&2; return 1; }
	approved_active_digest=$(sha256sum -- "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) || return 1
	input_languages_remove_plan "$backup" || { printf 'Remove blocked: backup-to-current-source comparison failed.\n' >&2; return 1; }
	if [[ $approved != true ]] && ! wizard_confirm 'Remove this complete Input Languages plan?'; then printf 'Remove canceled; no changes made.\n'; return 0; fi
	input_languages_prepare_roots || return 1
	input_languages_acquire_lock Remove || return 1
	input_languages_inspect
	[[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $INPUT_LANGUAGES_TREE_STATE == linked && $INPUT_LANGUAGES_PENDING_STATE == absent && $INPUT_LANGUAGES_RECOVERY_STATE == absent && $INPUT_LANGUAGES_CLEANUP_STATE == absent ]] || { printf 'Remove blocked: state changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	[[ $(sha256sum -- "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) == "$approved_active_digest" ]] || { printf 'Remove blocked: active receipt changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	input_languages_backup_valid "$backup" "$backup_transaction" "$backup_existed" "$backup_digest" || { printf 'Remove blocked: pre-Apply backup changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	input_languages_pointer_matches "$artifact" || { printf 'Remove blocked: active artifact pointer changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	input_languages_read_control_state || { printf 'Remove blocked: plugin identity or canonical group changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	input_languages_plugin_matches_receipt "$INPUT_LANGUAGES_ACTIVE" || { printf 'Remove blocked: loaded plugin identity changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	input_languages_shell_seams_compatible || { printf 'Remove blocked: Omarchy Shell mutation seams changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	if ! input_languages_widget_matches true "$widget_section" "$widget_index" "$widget_entry" || ! input_languages_widget_link_matches "$widget_source"; then
		printf 'Remove blocked: receipt-owned flag widget or link changed after confirmation.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	local transaction prior_group=null prior_autoreload widget_action=deactivate failed='' artifact_stage=''
	transaction=$(input_languages_new_transaction) || { input_languages_unlock || true; return 1; }
	INPUT_LANGUAGES_BACKUP_TRANSACTION=$backup_transaction INPUT_LANGUAGES_BACKUP=$backup INPUT_LANGUAGES_BACKUP_DIGEST=$backup_digest INPUT_LANGUAGES_BACKUP_EXISTED=$backup_existed
	input_languages_create_transaction_snapshots "$transaction" || { input_languages_unlock || true; return 1; }
	input_languages_read_control_state || { printf 'Remove blocked: plugin identity or canonical group changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	prior_group=$(jq -r .canonical_group <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH")
	prior_autoreload=$(input_languages_current_autoreload) || { input_languages_unlock || true; return 1; }
	input_languages_make_pending remove "$transaction" "$artifact" "$widget_action" "$prior_group" "$prior_autoreload" || { input_languages_unlock || true; return 1; }
	input_languages_validate_pending_file "$INPUT_LANGUAGES_PENDING" || { input_languages_unlock || true; return 1; }
	if ! hyprctl keyword misc:disable_autoreload true >/dev/null; then failed=pause-autoreload
	elif ! hyprctl plugin unload "$artifact" >/dev/null; then failed=unload-plugin
	elif ! input_languages_plugin_unloaded; then failed=verify-unloaded
	elif ! input_languages_remove_file_verified "$INPUT_LANGUAGES_POINTER"; then failed=remove-pointer
	elif ! input_languages_update_pending pointer-changed; then failed=record-pointer
	fi
	if [[ -z $failed ]]; then
		if input_languages_restore_stock_widget "$prior_stock_present" "$prior_stock_section" "$prior_stock_index" "$prior_stock_entry"; then
			input_languages_update_pending widget-changed true "$widget_section" "$widget_index" "$widget_entry" || failed=record-widget
		else failed=restore-stock-widget
		fi
	fi
	if [[ -z $failed ]]; then input_languages_remove_widget_link "$widget_source" || failed=remove-widget-link; fi
	if [[ -z $failed ]]; then input_languages_update_pending_link link-changed true || failed=record-widget-link; fi
	if [[ -z $failed ]]; then omarchy shell shell rescanPlugins >/dev/null || failed=rescan-plugins; fi
	if [[ -z $failed ]]; then input_languages_update_pending shell-reloaded || failed=record-shell-reload; fi
	if [[ -z $failed ]]; then input_languages_wait_for_custom_plugin absent || failed=verify-widget-removal; fi
	if [[ -z $failed ]]; then input_languages_unlink_package || failed=unlink-package; fi
	if [[ -z $failed ]]; then input_languages_restore_backup "$backup" "$backup_existed" "$backup_digest" "$backup_transaction" || failed=restore-backup; fi
	if [[ -z $failed ]]; then input_languages_update_pending tree-changed || failed=record-tree; fi
	if [[ -z $failed ]]; then hyprctl keyword misc:disable_autoreload "$prior_autoreload" >/dev/null || failed=restore-autoreload; fi
	if [[ -z $failed ]]; then hyprctl reload >/dev/null || failed=reload; fi
	if [[ -z $failed ]]; then input_languages_update_pending reloaded || failed=record-reload; fi
	if [[ -z $failed ]]; then
		if [[ $backup_existed == true ]]; then
			input_languages_exact_tree_inventory "$INPUT_LANGUAGES_LIVE" true && [[ $(input_languages_tree_digest "$INPUT_LANGUAGES_LIVE") == "$backup_digest" ]] || failed=verify-tree
		else [[ $INPUT_LANGUAGES_TREE_STATE == uninstalled ]] || failed=verify-tree
		fi
		if [[ -z $failed ]] && ! input_languages_plugin_unloaded; then failed=verify-unloaded; fi
		if [[ -z $failed ]] && ! input_languages_stock_widget_matches "$prior_stock_present" "$prior_stock_section" "$prior_stock_index" "$prior_stock_entry"; then failed=verify-widget; fi
		if [[ -z $failed && ( -e $INPUT_LANGUAGES_WIDGET_LIVE || -L $INPUT_LANGUAGES_WIDGET_LIVE ) ]]; then failed=verify-widget-link; fi
		if [[ -z $failed ]] && ! input_languages_custom_plugin_absent; then failed=verify-widget-removal; fi
	fi
	if [[ -z $failed ]]; then input_languages_archive_remove_evidence "$transaction" || failed=archive-evidence; fi
	if [[ -z $failed ]]; then input_languages_publish_cleanup "$transaction" "$artifact" || failed=publish-cleanup; fi
	if [[ -z $failed ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_ACTIVE" || failed=remove-active; fi
	if [[ -z $failed ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING" || failed=remove-pending; fi
	if [[ -n $failed ]]; then
		if [[ -e $INPUT_LANGUAGES_CLEANUP || -L $INPUT_LANGUAGES_CLEANUP ]]; then
			input_languages_remove_file_verified "$INPUT_LANGUAGES_CLEANUP" || { input_languages_record_recovery "$transaction" 'remove-rollback-retire-cleanup' || true; input_languages_unlock || true; return 1; }
		fi
		printf 'Remove failed at %s; restoring the verified active state.\n' "$failed" >&2
		input_languages_rollback_pending || true
		input_languages_unlock || true
		return 1
	fi
	if ! input_languages_stage_artifact_removal "$artifact" "$transaction" "$build" "$artifact_sha"; then
		printf 'Remove completed but receipt-owned artifact staging failed; archived evidence and the immutable artifact are retained.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	artifact_stage=$INPUT_LANGUAGES_REMOVED_ARTIFACT_STAGE
	if ! input_languages_delete_staged_artifact "$artifact_stage" "$artifact" "$transaction" "$build" "$artifact_sha"; then
		printf 'Remove completed but receipt-owned artifact cleanup failed at %s; archived evidence is retained.\n' "$artifact_stage" >&2
		input_languages_unlock || true
		return 1
	fi
	if ! input_languages_remove_file_verified "$INPUT_LANGUAGES_CLEANUP"; then
		printf 'Remove completed but cleanup evidence could not be retired; rerun Remove to reconcile it.\n' >&2
		input_languages_unlock || true
		return 1
	fi
	input_languages_unlock || return 1
	printf 'Remove completed: pre-Apply Hyprland tree restored as regular files; retained backups, archived evidence, diagnostics, sources, and Arch packages.\n'
}

input_languages_check() {
	bash "$REPOSITORY_ROOT/lib/dotfiles/input-languages-validator.sh"
}

input_languages_wait_for_navigation() {
	local allow_status=${1:-true} choice
	while :; do
		if [[ $allow_status == true ]]; then
			choice=$(wizard_choose_repeating 'Input Languages result' 'Return to Input Languages' Status) || choice='Return to Input Languages'
		else
			choice=$(wizard_choose_repeating 'Input Languages result' 'Return to Input Languages') || choice='Return to Input Languages'
		fi
		case $choice in
			'Return to Input Languages') return 0 ;;
			Status)
				input_languages_status
				allow_status=false
				;;
		esac
	done
}

manage_input_languages() {
	local choice
	while :; do
		choice=$(wizard_choose_repeating 'Input Languages' Status Apply Remove Back) || choice=Back
		case $choice in
			Status) input_languages_status; input_languages_wait_for_navigation false ;;
			Apply) apply_input_languages || true; input_languages_wait_for_navigation ;;
			Remove) remove_input_languages || true; input_languages_wait_for_navigation ;;
			Back) return 0 ;;
		esac
	done
}
