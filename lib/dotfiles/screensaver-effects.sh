readonly SCREENSAVER_EFFECTS_PACKAGE=screensaver-effects
readonly SCREENSAVER_EFFECTS_SUPPORTED_OMARCHY_VERSION=4.0.1-1
readonly SCREENSAVER_EFFECTS_SUPPORTED_TTFX_VERSION=0.3.2-1
readonly SCREENSAVER_EFFECTS_SOURCE_IDENTITY_SENTINEL=0000000000000000000000000000000000000000000000000000000000000000

SCREENSAVER_EFFECTS_STATE_ROOT=''
SCREENSAVER_EFFECTS_RECEIPT=''
SCREENSAVER_EFFECTS_PENDING=''
SCREENSAVER_EFFECTS_RECOVERY=''
SCREENSAVER_EFFECTS_MENU_FILE=''
SCREENSAVER_EFFECTS_SHELL_FILE=''
SCREENSAVER_EFFECTS_PLUGIN_ROOT=''
SCREENSAVER_EFFECTS_DEPLOYED_PLUGIN_ROOT=''
SCREENSAVER_EFFECTS_IDLE_SOURCE=''
SCREENSAVER_EFFECTS_INDICATORS_SOURCE=''
SCREENSAVER_EFFECTS_IDLE_DEPLOYED=''
SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED=''
SCREENSAVER_EFFECTS_IDLE_LIVE=''
SCREENSAVER_EFFECTS_INDICATORS_LIVE=''
SCREENSAVER_EFFECTS_JSONC_HELPER=''
SCREENSAVER_EFFECTS_PLUGIN_JSON='[]'
SCREENSAVER_EFFECTS_SHELL_JSON='{}'
SCREENSAVER_EFFECTS_MENU_JSON='{}'
SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID=''
SCREENSAVER_EFFECTS_IDLE_STARTED_AT_MS=''
SCREENSAVER_EFFECTS_IDLE_SOURCE_IDENTITY=''
SCREENSAVER_EFFECTS_IDLE_IN_CYCLE=''
SCREENSAVER_EFFECTS_IDLE_FINGERPRINT=''
SCREENSAVER_EFFECTS_INDICATORS_FINGERPRINT=''
SCREENSAVER_EFFECTS_SOURCE_IDENTITY=''
SCREENSAVER_EFFECTS_EMBEDDED_SOURCE_IDENTITY=''
SCREENSAVER_EFFECTS_IDLE_SHAPE_SIGNATURE=''
SCREENSAVER_EFFECTS_INDICATORS_SHAPE_SIGNATURE=''
SCREENSAVER_EFFECTS_LIFECYCLE_STATE=inactive
SCREENSAVER_EFFECTS_APPLY_NOOP=false
SCREENSAVER_EFFECTS_PRE_MUTATION_IDLE_GUARD=false
SCREENSAVER_EFFECTS_APPLY_RECEIPT=''
SCREENSAVER_EFFECTS_APPLY_PRIOR=''
SCREENSAVER_EFFECTS_REMOVAL_DEACTIVATED=false
SCREENSAVER_EFFECTS_RECOVERY_EVIDENCE_REQUIRED=false
declare -a SCREENSAVER_EFFECTS_COMPETING_CLONES=()
declare -A SCREENSAVER_EFFECTS_PREEXISTING_REMOVE_BACKUPS=()

screensaver_effects_set_paths() {
	SCREENSAVER_EFFECTS_STATE_ROOT=${XDG_STATE_HOME:-"$HOME/.local/state"}/dotfiles/screensaver-effects
	SCREENSAVER_EFFECTS_RECEIPT=$SCREENSAVER_EFFECTS_STATE_ROOT/receipt.json
	SCREENSAVER_EFFECTS_PENDING=$SCREENSAVER_EFFECTS_STATE_ROOT/pending.json
	SCREENSAVER_EFFECTS_RECOVERY=$SCREENSAVER_EFFECTS_STATE_ROOT/recovery-required.json
	SCREENSAVER_EFFECTS_MENU_FILE=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
	SCREENSAVER_EFFECTS_SHELL_FILE=$HOME/.config/omarchy/shell.json
	SCREENSAVER_EFFECTS_PLUGIN_ROOT=$HOME/.config/omarchy/plugins
	SCREENSAVER_EFFECTS_DEPLOYED_PLUGIN_ROOT=$HOME/.local/share/dotfiles/screensaver-effects/plugins
	SCREENSAVER_EFFECTS_IDLE_SOURCE=$REPOSITORY_ROOT/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle
	SCREENSAVER_EFFECTS_INDICATORS_SOURCE=$REPOSITORY_ROOT/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.indicators
	SCREENSAVER_EFFECTS_IDLE_DEPLOYED=$SCREENSAVER_EFFECTS_DEPLOYED_PLUGIN_ROOT/dotfiles.idle
	SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED=$SCREENSAVER_EFFECTS_DEPLOYED_PLUGIN_ROOT/dotfiles.indicators
	SCREENSAVER_EFFECTS_IDLE_LIVE=$SCREENSAVER_EFFECTS_PLUGIN_ROOT/dotfiles.idle
	SCREENSAVER_EFFECTS_INDICATORS_LIVE=$SCREENSAVER_EFFECTS_PLUGIN_ROOT/dotfiles.indicators
	SCREENSAVER_EFFECTS_JSONC_HELPER=$REPOSITORY_ROOT/lib/dotfiles/screensaver-effects-jsonc.mjs
}

screensaver_effects_package_version() {
	local package=$1 line name version extra
	if ! line=$(LC_ALL=C pacman -Q "$package" 2>/dev/null); then
		printf 'unavailable\n'
		return 0
	fi
	read -r name version extra <<<"$line"
	if [[ $name != "$package" || -z $version || -n ${extra-} ]]; then
		printf 'unavailable\n'
	else
		printf '%s\n' "$version"
	fi
}

screensaver_effects_print_versions() {
	local detected_omarchy detected_ttfx
	detected_omarchy=$(screensaver_effects_package_version omarchy)
	detected_ttfx=$(screensaver_effects_package_version ttfx)
	printf 'Supported Omarchy: %s\n' "$SCREENSAVER_EFFECTS_SUPPORTED_OMARCHY_VERSION"
	printf 'Detected Omarchy: %s\n' "$detected_omarchy"
	if [[ $detected_omarchy != "$SCREENSAVER_EFFECTS_SUPPORTED_OMARCHY_VERSION" ]]; then
		printf 'Warning: screensaver-effects was verified with Omarchy %s; detected %s. Concrete validation still applies.\n' \
			"$SCREENSAVER_EFFECTS_SUPPORTED_OMARCHY_VERSION" "$detected_omarchy"
	fi
	printf 'Supported ttfx: %s\n' "$SCREENSAVER_EFFECTS_SUPPORTED_TTFX_VERSION"
	printf 'Detected ttfx: %s\n' "$detected_ttfx"
	if [[ $detected_ttfx != "$SCREENSAVER_EFFECTS_SUPPORTED_TTFX_VERSION" ]]; then
		printf 'Warning: screensaver-effects mappings were verified with ttfx %s; detected %s. Previously mapped discovered effects remain available.\n' \
			"$SCREENSAVER_EFFECTS_SUPPORTED_TTFX_VERSION" "$detected_ttfx"
	fi
}

screensaver_effects_validate_receipt() {
	local receipt=$1
	[[ -f $receipt && ! -L $receipt ]] || return 1
	jq -e '
		def exact_keys($keys): (keys | sort) == ($keys | sort);
		def digest: type == "string" and test("^[0-9a-f]{64}$");
		def plugin_id: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$") and (contains("..") | not);
		((exact_keys(["schema_version","package","state","recoverability","source_fingerprints","source_identity","prior","owned_edges","migration","activated_at","removed_at"]))
		 or (exact_keys(["schema_version","package","state","recoverability","source_fingerprints","prior","owned_edges","migration","activated_at","removed_at"])))
		and .schema_version == 1
		and .package == "screensaver-effects"
		and (.state == "active" or .state == "inactive")
		and .recoverability == "verified"
		and (.source_fingerprints | exact_keys(["dotfiles.idle","dotfiles.indicators"]))
		and (.source_fingerprints["dotfiles.idle"] | digest)
		and (.source_fingerprints["dotfiles.indicators"] | digest)
		and ((has("source_identity") | not) or (.source_identity | digest))
		and (.prior | exact_keys(["plugin_states","indicators_entries","menu","shell_fields"]))
		and (.prior.plugin_states | exact_keys(["omarchy.idle","omarchy.indicators","dotfiles.idle","dotfiles.indicators"]))
		and (.prior.plugin_states | all(.[]; type == "boolean"))
		and (.prior.indicators_entries | type == "array")
		and (.prior.indicators_entries | all(.[];
			exact_keys(["section","index","entry"])
			and (.section == "left" or .section == "center" or .section == "right")
			and (.index | type == "number" and . >= 0 and floor == .)
			and (.entry | type == "object" and .id == "omarchy.indicators")))
		and ((.prior.indicators_entries | map(.section + ":" + (.index | tostring)) | unique | length) == (.prior.indicators_entries | length))
		and (.prior.plugin_states["omarchy.indicators"] == ((.prior.indicators_entries | length) > 0))
		and (.prior.menu | exact_keys(["file_existed","entry_present","identical"]))
		and (.prior.menu | all(.[]; type == "boolean"))
		and (.prior.menu.identical == .prior.menu.entry_present)
		and ((.prior.menu.entry_present | not) or .prior.menu.file_existed)
		and (.prior.shell_fields | exact_keys(["plugins","disabled_plugins","clone_source_restores"]))
		and (.prior.shell_fields | all(.[]; type == "boolean"))
		and (.prior.plugin_states["dotfiles.idle"] | not)
		and (.prior.plugin_states["dotfiles.indicators"] | not)
		and (.owned_edges | exact_keys(["idle_link","indicators_link","idle_activation","indicators_activation","menu_entry"]))
		and (.owned_edges | all(.[]; type == "boolean"))
		and .owned_edges.idle_link and .owned_edges.indicators_link and .owned_edges.idle_activation
		and (.owned_edges.indicators_activation == (.prior.indicators_entries | length > 0))
		and (.owned_edges.menu_entry == (.prior.menu.entry_present | not))
		and (.migration | exact_keys(["performed","backup","clone_ids"]))
		and (.migration.performed | type == "boolean")
		and ((.migration.backup == null) or (.migration.backup | type == "string" and startswith("/")))
		and (.migration.clone_ids | type == "array" and all(.[]; plugin_id) and (length == (unique | length)))
		and (if .migration.performed then (.migration.backup != null and (.migration.clone_ids | length > 0))
		     else (.migration.backup == null and (.migration.clone_ids | length == 0)) end)
		and (.activated_at | type == "string" and length > 0)
		and ((.removed_at == null) or (.removed_at | type == "string" and length > 0))
		and (if .state == "active" then .removed_at == null else .removed_at != null end)
	' "$receipt" >/dev/null 2>&1
}

screensaver_effects_validate_pending() {
	local pending=$1
	[[ -f $pending && ! -L $pending ]] || return 1
	jq -e '
		(keys | sort) == (["schema_version","package","operation","attempt_id","started_at","prior_receipt_sha256"] | sort)
		and .schema_version == 1 and .package == "screensaver-effects"
		and (.operation == "apply" or .operation == "remove" or .operation == "migrate")
		and (.attempt_id | type == "string" and length > 0)
		and (.started_at | type == "string" and length > 0)
		and ((.prior_receipt_sha256 == null) or (.prior_receipt_sha256 | type == "string" and test("^[0-9a-f]{64}$")))
	' "$pending" >/dev/null 2>&1
}

screensaver_effects_validate_recovery() {
	local recovery=$1
	[[ -f $recovery && ! -L $recovery ]] || return 1
	jq -e '
		(keys | sort) == (["schema_version","package","state","operation","reason","recorded_at"] | sort)
		and .schema_version == 1 and .package == "screensaver-effects" and .state == "recovery-required"
		and (.operation == "apply" or .operation == "remove" or .operation == "migrate")
		and (.reason | type == "string" and length > 0)
		and (.recorded_at | type == "string" and length > 0)
	' "$recovery" >/dev/null 2>&1
}

screensaver_effects_state_is_mutable() {
	screensaver_effects_set_paths
	if [[ $SCREENSAVER_EFFECTS_STATE_ROOT != /* ]]; then
		printf 'Error: XDG state path for screensaver-effects must be absolute: %s\n' "$SCREENSAVER_EFFECTS_STATE_ROOT" >&2
		return 1
	fi
	if [[ -e $SCREENSAVER_EFFECTS_PENDING || -L $SCREENSAVER_EFFECTS_PENDING ]]; then
		if screensaver_effects_validate_pending "$SCREENSAVER_EFFECTS_PENDING"; then
			printf 'Error: screensaver-effects has a pending %s operation.\n' "$(jq -r .operation "$SCREENSAVER_EFFECTS_PENDING")" >&2
		else
			printf 'Error: screensaver-effects has invalid pending state: %s\n' "$SCREENSAVER_EFFECTS_PENDING" >&2
		fi
		printf 'Recovery: inspect Package status and retained state before another mutation.\n' >&2
		return 1
	fi
	if [[ -e $SCREENSAVER_EFFECTS_RECOVERY || -L $SCREENSAVER_EFFECTS_RECOVERY ]]; then
		if screensaver_effects_validate_recovery "$SCREENSAVER_EFFECTS_RECOVERY"; then
			printf 'Error: screensaver-effects is recovery-required: %s\n' "$(jq -r .reason "$SCREENSAVER_EFFECTS_RECOVERY")" >&2
		else
			printf 'Error: screensaver-effects has invalid recovery state: %s\n' "$SCREENSAVER_EFFECTS_RECOVERY" >&2
		fi
		printf 'Recovery: inspect Package status and retained diagnostics before another mutation.\n' >&2
		return 1
	fi
	if [[ -e $SCREENSAVER_EFFECTS_RECEIPT || -L $SCREENSAVER_EFFECTS_RECEIPT ]]; then
		if ! screensaver_effects_validate_receipt "$SCREENSAVER_EFFECTS_RECEIPT"; then
			printf 'Error: screensaver-effects receipt is invalid: %s\n' "$SCREENSAVER_EFFECTS_RECEIPT" >&2
			printf 'Recovery: preserve the receipt and inspect Package status before another mutation.\n' >&2
			return 1
		fi
	fi
}

screensaver_effects_write_json() {
	local target=$1 content=$2 temporary
	mkdir -p -- "$(dirname -- "$target")" || return 1
	chmod 0700 -- "$(dirname -- "$target")" || return 1
	temporary=$(mktemp "$(dirname -- "$target")/.${target##*/}.XXXXXX") || return 1
	if ! printf '%s\n' "$content" >"$temporary" || ! chmod 0600 "$temporary" || ! mv -f -- "$temporary" "$target"; then
		rm -f -- "$temporary"
		return 1
	fi
}

screensaver_effects_timestamp() {
	date -u +%Y-%m-%dT%H:%M:%S.%NZ
}

screensaver_effects_write_pending() {
	local operation=$1 prior_digest=null timestamp attempt pending
	if [[ -f $SCREENSAVER_EFFECTS_RECEIPT ]]; then
		prior_digest=$(sha256sum "$SCREENSAVER_EFFECTS_RECEIPT")
		prior_digest=${prior_digest%% *}
	fi
	timestamp=$(screensaver_effects_timestamp)
	attempt="${timestamp//[^0-9A-Za-z]/}-$$-$RANDOM"
	if [[ $prior_digest == null ]]; then
		pending=$(jq -cn --arg operation "$operation" --arg attempt "$attempt" --arg timestamp "$timestamp" \
			'{schema_version:1,package:"screensaver-effects",operation:$operation,attempt_id:$attempt,started_at:$timestamp,prior_receipt_sha256:null}')
	else
		pending=$(jq -cn --arg operation "$operation" --arg attempt "$attempt" --arg timestamp "$timestamp" --arg digest "$prior_digest" \
			'{schema_version:1,package:"screensaver-effects",operation:$operation,attempt_id:$attempt,started_at:$timestamp,prior_receipt_sha256:$digest}')
	fi
	screensaver_effects_write_json "$SCREENSAVER_EFFECTS_PENDING" "$pending"
}

screensaver_effects_mark_recovery() {
	local operation=$1 reason=$2 timestamp recovery
	timestamp=$(screensaver_effects_timestamp)
	recovery=$(jq -cn --arg operation "$operation" --arg reason "$reason" --arg timestamp "$timestamp" \
		'{schema_version:1,package:"screensaver-effects",state:"recovery-required",operation:$operation,reason:$reason,recorded_at:$timestamp}')
	if ! screensaver_effects_write_json "$SCREENSAVER_EFFECTS_RECOVERY" "$recovery"; then
		SCREENSAVER_EFFECTS_RECOVERY_EVIDENCE_REQUIRED=true
		return 1
	fi
	return 0
}

screensaver_effects_record_diagnostic() {
	local operation=$1 reason=$2 timestamp directory file
	timestamp=$(screensaver_effects_timestamp)
	directory=$SCREENSAVER_EFFECTS_STATE_ROOT/diagnostics
	file=$directory/${timestamp//:/-}-$operation.log
	mkdir -p -- "$directory" || return 0
	chmod 0700 -- "$directory" || true
	printf '%s\noperation=%s\nreason=%s\n' "$timestamp" "$operation" "$reason" >"$file" || return 0
	chmod 0600 -- "$file" || true
}

screensaver_effects_fingerprint_normalized_service() {
	local file=$1 digest data prefix='  readonly property string dotfilesSourceIdentity: "' before after line normalized
	local LC_ALL=C
	[[ -f $file && ! -L $file ]] || return 1
	IFS= read -r -d '' data <"$file" || [[ -n $data ]] || return 1
	[[ $data == *"$prefix"* ]] || return 1
	before=${data%%"$prefix"*}
	after=${data#*"$prefix"}
	[[ $after != *"$prefix"* ]] || return 1
	[[ -z $before || ${before: -1} == $'\n' ]] || return 1
	line=${after%%$'\n'*}
	[[ ${#line} == 65 && ${line:64:1} == '"' && ${line:0:64} =~ ^[0-9a-f]{64}$ ]] || return 1
	normalized=${before}${prefix}${SCREENSAVER_EFFECTS_SOURCE_IDENTITY_SENTINEL}${after:64}
	digest=$(printf '%s' "$normalized" | LC_ALL=C sha256sum) || return 1
	digest=${digest%% *}
	printf '%s\n' "$digest"
}

screensaver_effects_extract_source_identity() {
	local line prefix='  readonly property string dotfilesSourceIdentity: "' value count=0
	SCREENSAVER_EFFECTS_EMBEDDED_SOURCE_IDENTITY=''
	[[ -f $SCREENSAVER_EFFECTS_IDLE_SOURCE/Service.qml && ! -L $SCREENSAVER_EFFECTS_IDLE_SOURCE/Service.qml ]] || return 1
	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $line == "$prefix"* ]]; then
			value=${line#"$prefix"}
			value=${value%\"}
			[[ $value =~ ^[0-9a-f]{64}$ ]] || return 1
			SCREENSAVER_EFFECTS_EMBEDDED_SOURCE_IDENTITY=$value
			count=$((count + 1))
		fi
	done <"$SCREENSAVER_EFFECTS_IDLE_SOURCE/Service.qml"
	[[ $count == 1 && -n $SCREENSAVER_EFFECTS_EMBEDDED_SOURCE_IDENTITY ]]
}

screensaver_effects_fingerprint_tree() {
	local root=$1 normalize_identity=${2-false}
	[[ -d $root && ! -L $root ]] || return 1
	(
		cd -- "$root" || exit 1
		local file digest mode record index
		local -a files=() hash_inputs=() hash_records=() modes=()
		local -A hashes=() normalized_hashes=()
		mapfile -d '' -t files < <(find . -type f -print0 | LC_ALL=C sort -z)
		((${#files[@]} > 0)) || exit 1
		for file in "${files[@]}"; do
			if [[ $normalize_identity == true && $file == ./Service.qml ]]; then
				normalized_hashes["$file"]=$(screensaver_effects_fingerprint_normalized_service "$file") || exit 1
			else
				hash_inputs+=("$file")
			fi
		done
		if ((${#hash_inputs[@]} > 0)); then
			mapfile -d '' -t hash_records < <(sha256sum --zero -- "${hash_inputs[@]}")
			((${#hash_records[@]} == ${#hash_inputs[@]})) || exit 1
			for index in "${!hash_inputs[@]}"; do
				record=${hash_records[index]}
				hashes["${hash_inputs[index]}"]=${record%% *}
			done
		fi
		mapfile -t modes < <(stat -c %a -- "${files[@]}")
		((${#modes[@]} == ${#files[@]})) || exit 1
		for index in "${!files[@]}"; do
			file=${files[index]}
			if [[ $normalize_identity == true && $file == ./Service.qml ]]; then
				digest=${normalized_hashes["$file"]}
			else
				digest=${hashes["$file"]}
			fi
			mode=${modes[index]}
			printf '%s %s %s\0' "$mode" "$digest" "${file#./}"
		done
	) | sha256sum | { read -r digest _; printf '%s\n' "$digest"; }
}

screensaver_effects_fingerprint_tree_pair() {
	local root=$1
	(
		cd -- "$root" || exit 1
		local file digest mode record index raw_digest normalized_digest
		local -a files=() hash_records=() modes=()
		local -A hashes=()
		mapfile -d '' -t files < <(find . -type f -print0 | LC_ALL=C sort -z)
		((${#files[@]} > 0)) || exit 1
		mapfile -d '' -t hash_records < <(sha256sum --zero -- "${files[@]}")
		((${#hash_records[@]} == ${#files[@]})) || exit 1
		for index in "${!files[@]}"; do
			record=${hash_records[index]}
			hashes["${files[index]}"]=${record%% *}
		done
		mapfile -t modes < <(stat -c %a -- "${files[@]}")
		((${#modes[@]} == ${#files[@]})) || exit 1
		raw_digest=$(
			for index in "${!files[@]}"; do
				file=${files[index]}
				printf '%s %s %s\0' "${modes[index]}" "${hashes["$file"]}" "${file#./}"
			done | sha256sum | { read -r digest _; printf '%s' "$digest"; }
		)
		normalized_digest=$(
			for index in "${!files[@]}"; do
				file=${files[index]}
				if [[ $file == ./Service.qml ]]; then
					digest=$(screensaver_effects_fingerprint_normalized_service "$file") || exit 1
				else
					digest=${hashes["$file"]}
				fi
				printf '%s %s %s\0' "${modes[index]}" "$digest" "${file#./}"
			done | sha256sum | { read -r digest _; printf '%s' "$digest"; }
		)
		printf '%s\t%s\n' "$raw_digest" "$normalized_digest"
	)
}

screensaver_effects_source_shape_signature() {
	local root=$1 digest
	digest=$(find "$root" -mindepth 1 -printf '%P\t%y\t%m\0' | LC_ALL=C sort -z | sha256sum) || return 1
	digest=${digest%% *}
	printf '%s\n' "$digest"
}

screensaver_effects_source_identity() {
	local idle indicators idle_raw idle_normalized indicators_raw indicators_normalized
	IFS=$'\t' read -r idle_raw idle_normalized < <(screensaver_effects_fingerprint_tree_pair "$SCREENSAVER_EFFECTS_IDLE_SOURCE") || return 1
	IFS=$'\t' read -r indicators_raw indicators_normalized < <(screensaver_effects_fingerprint_tree_pair "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE") || return 1
	idle=$idle_normalized
	indicators=$indicators_raw
	printf 'dotfiles.idle\t%s\ndotfiles.indicators\t%s\n' "$idle" "$indicators" |
		LC_ALL=C sha256sum | { read -r digest _; printf '%s\n' "$digest"; }
}

screensaver_effects_validate_source_shape() {
	screensaver_effects_set_paths
	local package_json manifest id cloned idle_raw idle_normalized indicators_raw indicators_normalized
	SCREENSAVER_EFFECTS_SOURCE_IDENTITY=''
	SCREENSAVER_EFFECTS_EMBEDDED_SOURCE_IDENTITY=''
	SCREENSAVER_EFFECTS_IDLE_SHAPE_SIGNATURE=''
	SCREENSAVER_EFFECTS_INDICATORS_SHAPE_SIGNATURE=''
	package_json=$(jq -c --arg package "$SCREENSAVER_EFFECTS_PACKAGE" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
	if [[ -z $package_json ]]; then
		printf 'Error: package catalog is missing screensaver-effects.\n' >&2
		return 1
	fi
	for manifest in "$SCREENSAVER_EFFECTS_IDLE_SOURCE/manifest.json" "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE/manifest.json"; do
		if [[ ! -f $manifest || -L $manifest ]] || ! jq -e . "$manifest" >/dev/null 2>&1; then
			printf 'Error: invalid screensaver-effects plugin manifest: %s\n' "$manifest" >&2
			return 1
		fi
	done
	id=$(jq -r '.id // empty' "$SCREENSAVER_EFFECTS_IDLE_SOURCE/manifest.json")
	cloned=$(jq -r '.omarchy.clonedFrom // empty' "$SCREENSAVER_EFFECTS_IDLE_SOURCE/manifest.json")
	if [[ $id != dotfiles.idle || $cloned != omarchy.idle ]]; then
		printf 'Error: idle source must declare dotfiles.idle clonedFrom omarchy.idle.\n' >&2
		return 1
	fi
	id=$(jq -r '.id // empty' "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE/manifest.json")
	cloned=$(jq -r '.omarchy.clonedFrom // empty' "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE/manifest.json")
	if [[ $id != dotfiles.indicators || $cloned != omarchy.indicators ]]; then
		printf 'Error: Indicators source must declare dotfiles.indicators clonedFrom omarchy.indicators.\n' >&2
		return 1
	fi
	if [[ ! -f $SCREENSAVER_EFFECTS_JSONC_HELPER || -L $SCREENSAVER_EFFECTS_JSONC_HELPER ]]; then
		printf 'Error: missing screensaver-effects JSONC lifecycle helper: %s\n' "$SCREENSAVER_EFFECTS_JSONC_HELPER" >&2
		return 1
	fi
	if find "$SCREENSAVER_EFFECTS_IDLE_SOURCE" "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE" -type l -print -quit | read -r; then
		printf 'Error: canonical screensaver-effects plugin sources must not contain symlinks.\n' >&2
		return 1
	fi
	if ! screensaver_effects_extract_source_identity; then
		printf 'Error: idle source must expose exactly one lowercase hexadecimal dotfilesSourceIdentity.\n' >&2
		return 1
	fi
	IFS=$'\t' read -r idle_raw idle_normalized < <(screensaver_effects_fingerprint_tree_pair "$SCREENSAVER_EFFECTS_IDLE_SOURCE") || return 1
	IFS=$'\t' read -r indicators_raw indicators_normalized < <(screensaver_effects_fingerprint_tree_pair "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE") || return 1
	SCREENSAVER_EFFECTS_SOURCE_IDENTITY=$(printf 'dotfiles.idle\t%s\ndotfiles.indicators\t%s\n' "$idle_normalized" "$indicators_raw" |
		LC_ALL=C sha256sum | { read -r digest _; printf '%s\n' "$digest"; }) || return 1
	if [[ $SCREENSAVER_EFFECTS_EMBEDDED_SOURCE_IDENTITY != "$SCREENSAVER_EFFECTS_SOURCE_IDENTITY" ]]; then
		printf 'Error: idle source dotfilesSourceIdentity does not match the normalized plugin source fingerprint.\n' >&2
		return 1
	fi
	SCREENSAVER_EFFECTS_IDLE_FINGERPRINT=$idle_raw
	SCREENSAVER_EFFECTS_INDICATORS_FINGERPRINT=$indicators_raw
	SCREENSAVER_EFFECTS_IDLE_SHAPE_SIGNATURE=$(screensaver_effects_source_shape_signature "$SCREENSAVER_EFFECTS_IDLE_SOURCE") || return 1
	SCREENSAVER_EFFECTS_INDICATORS_SHAPE_SIGNATURE=$(screensaver_effects_source_shape_signature "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE") || return 1
	return 0
}

screensaver_effects_validate_source() {
	screensaver_effects_validate_source_shape || return 1
	local package_json validator validation_root structural_validator
	package_json=$(jq -c --arg package "$SCREENSAVER_EFFECTS_PACKAGE" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
	structural_validator=$REPOSITORY_ROOT/lib/dotfiles/screensaver-effects-validator.sh
	if [[ ! -f $structural_validator || -L $structural_validator ]] && \
		jq -e '.validators | type == "array" and length == 0' <<<"$package_json" >/dev/null; then
		return 0
	fi
	validation_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-screensaver-source.XXXXXX") || return 1
	mkdir -p "$validation_root/home" "$validation_root/config" "$validation_root/state" "$validation_root/runtime" || {
		rm -rf -- "$validation_root"
		return 1
	}
	if [[ -f $structural_validator && ! -L $structural_validator ]]; then
		if ! (cd -- "$REPOSITORY_ROOT" && env \
			HOME="$validation_root/home" XDG_CONFIG_HOME="$validation_root/config" XDG_STATE_HOME="$validation_root/state" \
			XDG_RUNTIME_DIR="$validation_root/runtime" DOTFILES_REPOSITORY_ROOT="$REPOSITORY_ROOT" \
			bash "$structural_validator"); then
			rm -rf -- "$validation_root"
			printf 'Error: screensaver-effects source structural validator failed: %s\n' "$structural_validator" >&2
			return 1
		fi
	else
		while IFS= read -r validator; do
			if ! (cd -- "$REPOSITORY_ROOT" && env \
				HOME="$validation_root/home" XDG_CONFIG_HOME="$validation_root/config" XDG_STATE_HOME="$validation_root/state" \
				XDG_RUNTIME_DIR="$validation_root/runtime" DOTFILES_REPOSITORY_ROOT="$REPOSITORY_ROOT" \
				bash -c "$validator"); then
				rm -rf -- "$validation_root"
				printf 'Error: screensaver-effects source validator failed: %s\n' "$validator" >&2
				return 1
			fi
		done < <(jq -r '.validators[]' <<<"$package_json")
	fi
	rm -rf -- "$validation_root"
}

screensaver_effects_check() {
	screensaver_effects_print_versions
	if screensaver_effects_validate_source; then
		printf 'Screensaver effects source: structurally valid\n'
	else
		return 1
	fi
}

screensaver_effects_read_plugins() {
	if ! SCREENSAVER_EFFECTS_PLUGIN_JSON=$(omarchy plugin list --json 2>/dev/null); then
		return 1
	fi
	jq -e 'type == "array" and all(.[]; type == "object" and (.id | type == "string") and (.enabled | type == "boolean")) and ((map(.id) | length) == (map(.id) | unique | length))' \
		<<<"$SCREENSAVER_EFFECTS_PLUGIN_JSON" >/dev/null 2>&1
}

screensaver_effects_read_shell() {
	if ! SCREENSAVER_EFFECTS_SHELL_JSON=$(omarchy-shell shell listShellConfig 2>/dev/null); then
		return 1
	fi
	jq -e '
		type == "object" and (.bar | type == "object") and (.bar.layout | type == "object")
		and (.bar.layout.left | type == "array") and (.bar.layout.center | type == "array") and (.bar.layout.right | type == "array")
		and ((.plugins // []) | type == "array" and all(.[]; type == "object" and (.id | type == "string")))
		and ((.disabledPlugins // []) | type == "array" and all(.[]; type == "string"))
		and ((.cloneSourceRestores // []) | type == "array" and all(.[]; type == "string"))
	' <<<"$SCREENSAVER_EFFECTS_SHELL_JSON" >/dev/null 2>&1
}

screensaver_effects_wait_for_plugins() {
	local attempt id ready
	local OMARCHY_SHELL_IPC_TIMEOUT=0.1s
	export OMARCHY_SHELL_IPC_TIMEOUT
	(($# > 0)) || return 1
	for ((attempt = 0; attempt < 40; attempt++)); do
		if screensaver_effects_read_plugins; then
			ready=true
			for id in "$@"; do
				if ! jq -e --arg id "$id" 'any(.[]; .id == $id)' <<<"$SCREENSAVER_EFFECTS_PLUGIN_JSON" >/dev/null; then
					ready=false
					break
				fi
			done
			[[ $ready != true ]] || return 0
		fi
		sleep 0.05
	done
	return 1
}

screensaver_effects_wait_for_shell() {
	local expected actual attempt
	local OMARCHY_SHELL_IPC_TIMEOUT=0.1s
	export OMARCHY_SHELL_IPC_TIMEOUT
	expected=$(jq -S -c . "$SCREENSAVER_EFFECTS_SHELL_FILE" 2>/dev/null) || return 1
	for ((attempt = 0; attempt < 40; attempt++)); do
		if screensaver_effects_read_shell; then
			actual=$(jq -S -c . <<<"$SCREENSAVER_EFFECTS_SHELL_JSON" 2>/dev/null) || actual=''
			[[ $actual != "$expected" ]] || return 0
		fi
		sleep 0.05
	done
	return 1
}

screensaver_effects_read_idle_instance() {
	local status prefix
	SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID=''
	SCREENSAVER_EFFECTS_IDLE_STARTED_AT_MS=''
	SCREENSAVER_EFFECTS_IDLE_SOURCE_IDENTITY=''
	SCREENSAVER_EFFECTS_IDLE_IN_CYCLE=''
	if ! status=$(OMARCHY_SHELL_IPC_TIMEOUT=0.1s omarchy-shell idle status 2>/dev/null); then
		return 1
	fi
	jq -e '
		type == "object"
		and ((has("dotfilesInstanceId") | not) or (.dotfilesInstanceId | type == "string" and length > 0))
		and ((has("dotfilesSourceIdentity") | not) or (.dotfilesSourceIdentity | type == "string" and test("^[0-9a-f]{64}$")))
		and ((has("inIdleCycle") | not) or (.inIdleCycle | type == "boolean"))
	' <<<"$status" >/dev/null 2>&1 || return 1
	SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID=$(jq -r '.dotfilesInstanceId // ""' <<<"$status")
	SCREENSAVER_EFFECTS_IDLE_SOURCE_IDENTITY=$(jq -r '.dotfilesSourceIdentity // ""' <<<"$status")
	SCREENSAVER_EFFECTS_IDLE_IN_CYCLE=$(jq -r 'if .inIdleCycle == true then "true" elif .inIdleCycle == false then "false" else "" end' <<<"$status")
	[[ -z $SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID ]] && return 0
	prefix=${SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID%%-*}
	[[ $SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID == "$prefix"-?* && $prefix =~ ^[0-9a-z]{1,10}$ ]] || return 1
	SCREENSAVER_EFFECTS_IDLE_STARTED_AT_MS=$((36#$prefix))
}

screensaver_effects_capture_idle_instance() {
	local attempt
	local OMARCHY_SHELL_IPC_TIMEOUT=0.1s
	export OMARCHY_SHELL_IPC_TIMEOUT
	SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID=''
	for ((attempt = 0; attempt < 4; attempt++)); do
		if screensaver_effects_read_idle_instance; then
			return 0
		fi
		sleep 0.05
	done
	SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID=''
	SCREENSAVER_EFFECTS_IDLE_STARTED_AT_MS=''
	SCREENSAVER_EFFECTS_IDLE_SOURCE_IDENTITY=''
	SCREENSAVER_EFFECTS_IDLE_IN_CYCLE=''
	return 0
}

screensaver_effects_require_idle_cycle_inactive() {
	if ! screensaver_effects_read_idle_instance; then
		return 0
	fi
	if [[ $SCREENSAVER_EFFECTS_IDLE_IN_CYCLE == true ]]; then
		printf 'Conflict: the dotfiles idle service is in an active idle cycle; wait for activity to end it, then retry the screensaver-effects operation.\n' >&2
		return 1
	fi
}

screensaver_effects_wait_for_idle_instance() {
	local prior=$1 requested_at_ms=$2 expected_identity=${3-} attempt
	local OMARCHY_SHELL_IPC_TIMEOUT=0.1s
	export OMARCHY_SHELL_IPC_TIMEOUT
	[[ -n $expected_identity ]] || return 1
	for ((attempt = 0; attempt < 40; attempt++)); do
		if screensaver_effects_read_idle_instance && \
			[[ -n $SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID && $SCREENSAVER_EFFECTS_IDLE_STARTED_AT_MS =~ ^[0-9]+$ ]] && \
			[[ $SCREENSAVER_EFFECTS_IDLE_SOURCE_IDENTITY == "$expected_identity" ]] && \
			[[ -z $prior || $SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID != "$prior" ]] && \
			((10#$SCREENSAVER_EFFECTS_IDLE_STARTED_AT_MS >= 10#$requested_at_ms)); then
			return 0
		fi
		sleep 0.05
	done
	return 1
}

screensaver_effects_reload_shell() {
	screensaver_effects_require_idle_cycle_inactive || return 1
	omarchy-shell shell reloadConfig >/dev/null || return 1
	screensaver_effects_wait_for_shell
}

screensaver_effects_source_snapshot_matches() {
	local expected_idle=$1 expected_indicators=$2 expected_identity=$3
	screensaver_effects_extract_source_identity || return 1
	[[ $SCREENSAVER_EFFECTS_EMBEDDED_SOURCE_IDENTITY == "$expected_identity" ]] || return 1
	local idle_fingerprint indicators_fingerprint idle_shape indicators_shape
	idle_fingerprint=$(screensaver_effects_fingerprint_tree "$SCREENSAVER_EFFECTS_IDLE_SOURCE") || return 1
	[[ $idle_fingerprint == "$expected_idle" ]] || return 1
	indicators_fingerprint=$(screensaver_effects_fingerprint_tree "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE") || return 1
	[[ $indicators_fingerprint == "$expected_indicators" ]] || return 1
	[[ -n $SCREENSAVER_EFFECTS_IDLE_SHAPE_SIGNATURE && -n $SCREENSAVER_EFFECTS_INDICATORS_SHAPE_SIGNATURE ]] || return 1
	idle_shape=$(screensaver_effects_source_shape_signature "$SCREENSAVER_EFFECTS_IDLE_SOURCE") || return 1
	[[ $idle_shape == "$SCREENSAVER_EFFECTS_IDLE_SHAPE_SIGNATURE" ]] || return 1
	indicators_shape=$(screensaver_effects_source_shape_signature "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE") || return 1
	[[ $indicators_shape == "$SCREENSAVER_EFFECTS_INDICATORS_SHAPE_SIGNATURE" ]]
}

screensaver_effects_idle_runtime_matches_identity() {
	local expected_identity=$1
	screensaver_effects_read_idle_instance || return 1
	[[ -n $SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID && $SCREENSAVER_EFFECTS_IDLE_SOURCE_IDENTITY == "$expected_identity" ]]
}

screensaver_effects_shell_has_dotfiles_edges() {
	jq -e '
		def entry_id: if type == "object" then (.id // "") else tostring end;
		any((.plugins // [])[]; .id == "dotfiles.idle" or .id == "dotfiles.indicators")
		or any(.bar.layout[][]; (entry_id == "dotfiles.indicators"))
		or ((.disabledPlugins // []) | index("dotfiles.idle") != null)
		or ((.disabledPlugins // []) | index("dotfiles.indicators") != null)
		or ((.cloneSourceRestores // []) | index("dotfiles.idle") != null)
		or ((.cloneSourceRestores // []) | index("dotfiles.indicators") != null)
	' <<<"$SCREENSAVER_EFFECTS_SHELL_JSON" >/dev/null 2>&1
}

screensaver_effects_require_inactive_edges_absent() {
	if [[ $(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED") != absent || \
		$(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED") != absent ]]; then
		printf 'Conflict: Dotfiles live plugin links remain without an active ownership receipt.\n' >&2
		return 1
	fi
	if jq -e '.owned_marker' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
		printf 'Conflict: a receipt-owned system.screensaver menu marker remains without an active ownership receipt.\n' >&2
		return 1
	fi
	if screensaver_effects_shell_has_dotfiles_edges; then
		printf 'Conflict: shell.json retains Dotfiles activation, bar, or restoration state without an active ownership receipt.\n' >&2
		return 1
	fi
}

screensaver_effects_require_migration_lifecycle_inactive() {
	if [[ -f $SCREENSAVER_EFFECTS_RECEIPT && $(jq -r .state "$SCREENSAVER_EFFECTS_RECEIPT") != inactive ]]; then
		printf 'Conflict: dedicated migration found an active Dotfiles lifecycle receipt.\n' >&2
		return 1
	fi
	screensaver_effects_require_inactive_edges_absent
}

screensaver_effects_plugin_enabled() {
	local id=$1
	jq -r --arg id "$id" '[.[] | select(.id == $id) | .enabled][0] // false' <<<"$SCREENSAVER_EFFECTS_PLUGIN_JSON"
}

screensaver_effects_bar_entries() {
	local id=$1
	jq -c --arg id "$id" '
		def entry_id: if type == "object" then (.id // "") else tostring end;
		[.bar.layout | to_entries[] as $section | $section.value | to_entries[]
		 | select(.value | entry_id == $id)
		 | {section:$section.key,index:.key,entry:.value}]
	' <<<"$SCREENSAVER_EFFECTS_SHELL_JSON"
}

screensaver_effects_inspect_menu() {
	if ! SCREENSAVER_EFFECTS_MENU_JSON=$(node "$SCREENSAVER_EFFECTS_JSONC_HELPER" inspect "$SCREENSAVER_EFFECTS_MENU_FILE" 2>/dev/null); then
		return 1
	fi
	jq -e '
		(keys | sort) == (["file_exists","present","identical","owned_marker"] | sort)
		and all(.[]; type == "boolean")
	' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null 2>&1
}

screensaver_effects_find_competing_clones() {
	SCREENSAVER_EFFECTS_COMPETING_CLONES=()
	[[ -d $SCREENSAVER_EFFECTS_PLUGIN_ROOT ]] || return 0
	local candidate manifest id cloned
	while IFS= read -r -d '' candidate; do
		id=${candidate##*/}
		[[ $id != dotfiles.idle && $id != dotfiles.indicators && $id != .* ]] || continue
		manifest=$candidate/manifest.json
		[[ -f $manifest ]] || continue
		cloned=$(jq -r '.omarchy.clonedFrom // empty' "$manifest" 2>/dev/null) || continue
		if [[ $cloned == omarchy.idle || $cloned == omarchy.indicators ]]; then
			SCREENSAVER_EFFECTS_COMPETING_CLONES+=("$id")
		fi
	done < <(find "$SCREENSAVER_EFFECTS_PLUGIN_ROOT" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 | LC_ALL=C sort -z)
}

screensaver_effects_link_state() {
	local live=$1 deployed=$2
	if [[ -L $live ]]; then
		if [[ $(readlink -- "$live") == "$deployed" ]]; then
			printf 'exact\n'
		else
			printf 'conflicting\n'
		fi
	elif [[ -e $live ]]; then
		printf 'conflicting\n'
	else
		printf 'absent\n'
	fi
}

screensaver_effects_current_prior() {
	local idle_builtin indicators_builtin indicators_present dotfiles_idle dotfiles_indicators entries menu_exists menu_present menu_identical shell_fields
	if ! jq -e 'any(.[]; .id == "omarchy.idle") and any(.[]; .id == "omarchy.indicators")' <<<"$SCREENSAVER_EFFECTS_PLUGIN_JSON" >/dev/null; then
		printf 'Error: required built-in Omarchy plugins are unavailable before prior-state capture.\n' >&2
		return 1
	fi
	idle_builtin=$(screensaver_effects_plugin_enabled omarchy.idle)
	indicators_builtin=$(screensaver_effects_plugin_enabled omarchy.indicators)
	dotfiles_idle=$(screensaver_effects_plugin_enabled dotfiles.idle)
	dotfiles_indicators=$(screensaver_effects_plugin_enabled dotfiles.indicators)
	entries=$(screensaver_effects_bar_entries omarchy.indicators)
	indicators_present=$(jq -r 'length > 0' <<<"$entries")
	if [[ $indicators_builtin != "$indicators_present" ]]; then
		printf 'Error: omarchy.indicators plugin state does not match its prior bar presence.\n' >&2
		return 1
	fi
	if ! jq -e 'all(.[]; .entry | type == "object")' <<<"$entries" >/dev/null; then
		printf 'Error: every omarchy.indicators bar entry must be an object so its options can be preserved.\n' >&2
		return 1
	fi
	menu_exists=$(jq -r .file_exists <<<"$SCREENSAVER_EFFECTS_MENU_JSON")
	menu_present=$(jq -r .present <<<"$SCREENSAVER_EFFECTS_MENU_JSON")
	menu_identical=$(jq -r .identical <<<"$SCREENSAVER_EFFECTS_MENU_JSON")
	shell_fields=$(node "$SCREENSAVER_EFFECTS_JSONC_HELPER" shell-fields "$SCREENSAVER_EFFECTS_SHELL_FILE") || return 1
	jq -cn \
		--argjson idleBuiltin "$idle_builtin" --argjson indicatorsBuiltin "$indicators_builtin" \
		--argjson dotfilesIdle "$dotfiles_idle" --argjson dotfilesIndicators "$dotfiles_indicators" \
		--argjson entries "$entries" --argjson menuExists "$menu_exists" --argjson menuPresent "$menu_present" --argjson menuIdentical "$menu_identical" \
		--argjson shellFields "$shell_fields" '
		{
			plugin_states:{
				"omarchy.idle":$idleBuiltin,
				"omarchy.indicators":$indicatorsBuiltin,
				"dotfiles.idle":$dotfilesIdle,
				"dotfiles.indicators":$dotfilesIndicators
			},
			indicators_entries:$entries,
			menu:{file_existed:$menuExists,entry_present:$menuPresent,identical:$menuIdentical},
			shell_fields:$shellFields
		}'
}

screensaver_effects_expected_active_bar() {
	local prior=$1
	jq -c '[.indicators_entries[] | .entry | .id = "dotfiles.indicators"]' <<<"$prior"
}

screensaver_effects_validate_owned_bar_positions() {
	local receipt=$1 mode=${2-apply} prior
	prior=$(jq -c .prior <<<"$receipt")
	jq -e --arg mode "$mode" --argjson expected "$(jq -c .indicators_entries <<<"$prior")" '
		def entry_id: if type == "object" then (.id // "") else tostring end;
		def active_entry: .entry + {id:"dotfiles.indicators"};
		def coordinate($section; $index): $section + ":" + ($index | tostring);
		. as $config |
		([$expected[] | coordinate(.section; .index)]) as $coordinates |
		([$config.bar.layout | to_entries[] as $section | $section.value | to_entries[]
		  | select((.value | entry_id) == "dotfiles.indicators" or (.value | entry_id) == "omarchy.indicators")
		  | coordinate($section.key; .key)]) as $current_coordinates |
		(all($expected[];
			. as $entry | $config.bar.layout[$entry.section][$entry.index] as $actual |
			if $mode == "remove" then $actual == ($entry | active_entry)
			else ($actual == $entry.entry or $actual == ($entry | active_entry)) end))
		and (all($current_coordinates[]; . as $coordinate | ($coordinates | index($coordinate)) != null))
	' <<<"$SCREENSAVER_EFFECTS_SHELL_JSON" >/dev/null 2>&1
}

screensaver_effects_validate_idle_restore_metadata() {
	local receipt=$1 prior_enabled marker_present source_disabled
	prior_enabled=$(jq -r '.prior.plugin_states["omarchy.idle"]' <<<"$receipt")
	marker_present=$(jq -r '(.cloneSourceRestores // []) | index("dotfiles.idle") != null' <<<"$SCREENSAVER_EFFECTS_SHELL_JSON")
	source_disabled=$(jq -r '(.disabledPlugins // []) | index("omarchy.idle") != null' <<<"$SCREENSAVER_EFFECTS_SHELL_JSON")
	[[ $source_disabled == true && $marker_present == "$prior_enabled" ]]
}

screensaver_effects_active_matches_receipt() {
	local receipt=$1
	local expected_bar current_bar prior expected_idle_builtin expected_indicators
	screensaver_effects_stow_links_are_complete || return 1
	[[ $(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED") == exact ]] || return 1
	[[ $(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED") == exact ]] || return 1
	screensaver_effects_validate_source >/dev/null 2>&1 || return 1
	[[ $(jq -r '.source_fingerprints["dotfiles.idle"]' <<<"$receipt") == "$SCREENSAVER_EFFECTS_IDLE_FINGERPRINT" ]] || return 1
	[[ $(jq -r '.source_fingerprints["dotfiles.indicators"]' <<<"$receipt") == "$SCREENSAVER_EFFECTS_INDICATORS_FINGERPRINT" ]] || return 1
	[[ $(jq -r '.source_identity' <<<"$receipt") == "$SCREENSAVER_EFFECTS_SOURCE_IDENTITY" ]] || return 1
	screensaver_effects_read_plugins || return 1
	jq -e '
		any(.[]; .id == "omarchy.idle")
		and any(.[]; .id == "omarchy.indicators")
		and any(.[]; .id == "dotfiles.idle")
		and any(.[]; .id == "dotfiles.indicators")
	' <<<"$SCREENSAVER_EFFECTS_PLUGIN_JSON" >/dev/null || return 1
	screensaver_effects_read_shell || return 1
	screensaver_effects_idle_runtime_matches_identity "$SCREENSAVER_EFFECTS_SOURCE_IDENTITY" || return 1
	screensaver_effects_validate_owned_bar_positions "$receipt" remove || return 1
	screensaver_effects_validate_idle_restore_metadata "$receipt" || return 1
	[[ $(screensaver_effects_plugin_enabled dotfiles.idle) == true ]] || return 1
	prior=$(jq -c .prior <<<"$receipt")
	expected_idle_builtin=$(jq -r '.plugin_states["omarchy.idle"]' <<<"$prior")
	if [[ $expected_idle_builtin == true ]]; then expected_idle_builtin=false; fi
	[[ $(screensaver_effects_plugin_enabled omarchy.idle) == "$expected_idle_builtin" ]] || return 1
	expected_bar=$(screensaver_effects_expected_active_bar "$prior")
	current_bar=$(screensaver_effects_bar_entries dotfiles.indicators | jq -c '[.[].entry]')
	[[ $(jq -S -c . <<<"$current_bar") == "$(jq -S -c . <<<"$expected_bar")" ]] || return 1
	expected_indicators=$(jq -r '.indicators_entries | length > 0' <<<"$prior")
	[[ $(screensaver_effects_plugin_enabled dotfiles.indicators) == "$expected_indicators" ]] || return 1
	[[ $(screensaver_effects_plugin_enabled omarchy.indicators) == false ]] || return 1
	[[ $(screensaver_effects_bar_entries omarchy.indicators | jq length) -eq 0 ]] || return 1
	screensaver_effects_inspect_menu || return 1
	if [[ $(jq -r .owned_edges.menu_entry <<<"$receipt") == true ]]; then
		jq -e '.present and .identical and .owned_marker' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null || return 1
	else
		jq -e '.present and .identical and (.owned_marker | not)' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null || return 1
	fi
}

screensaver_effects_classify() {
	screensaver_effects_set_paths
	SCREENSAVER_EFFECTS_LIFECYCLE_STATE=inactive
	local stow_state
	if [[ $SCREENSAVER_EFFECTS_STATE_ROOT != /* ]]; then
		SCREENSAVER_EFFECTS_LIFECYCLE_STATE=recovery-required
		return 0
	fi
	if [[ -e $SCREENSAVER_EFFECTS_PENDING || -L $SCREENSAVER_EFFECTS_PENDING || -e $SCREENSAVER_EFFECTS_RECOVERY || -L $SCREENSAVER_EFFECTS_RECOVERY ]]; then
		SCREENSAVER_EFFECTS_LIFECYCLE_STATE=recovery-required
		return 0
	fi
	if [[ -e $SCREENSAVER_EFFECTS_RECEIPT || -L $SCREENSAVER_EFFECTS_RECEIPT ]]; then
		if ! screensaver_effects_validate_receipt "$SCREENSAVER_EFFECTS_RECEIPT"; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=recovery-required
			return 0
		fi
		SCREENSAVER_EFFECTS_APPLY_RECEIPT=$(<"$SCREENSAVER_EFFECTS_RECEIPT")
	else
		SCREENSAVER_EFFECTS_APPLY_RECEIPT=''
	fi
	screensaver_effects_find_competing_clones
	if ((${#SCREENSAVER_EFFECTS_COMPETING_CLONES[@]} > 0)); then
		SCREENSAVER_EFFECTS_LIFECYCLE_STATE=conflicting
		return 0
	fi
	if [[ $(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED") == conflicting || \
		$(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED") == conflicting ]]; then
		SCREENSAVER_EFFECTS_LIFECYCLE_STATE=conflicting
		return 0
	fi
	if ! screensaver_effects_inspect_menu; then
		SCREENSAVER_EFFECTS_LIFECYCLE_STATE=conflicting
		return 0
	fi
	if jq -e '.present and (.identical | not)' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
		SCREENSAVER_EFFECTS_LIFECYCLE_STATE=conflicting
		return 0
	fi
	if [[ -z $SCREENSAVER_EFFECTS_APPLY_RECEIPT ]]; then
		stow_state=$(screensaver_effects_stow_package_state)
		if [[ $stow_state != absent ]]; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=conflicting
		elif [[ $(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED") != absent || \
			$(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED") != absent ]] || \
			jq -e '.owned_marker' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=conflicting
		elif ! screensaver_effects_read_shell; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=recovery-required
		elif screensaver_effects_shell_has_dotfiles_edges; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=conflicting
		fi
		return 0
	fi
	if [[ $(jq -r .state <<<"$SCREENSAVER_EFFECTS_APPLY_RECEIPT") == inactive ]]; then
		stow_state=$(screensaver_effects_stow_package_state)
		if [[ $stow_state != absent ]]; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=drifted
		elif [[ $(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED") != absent || \
			$(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED") != absent ]] || \
			jq -e '.owned_marker' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=drifted
		elif ! screensaver_effects_read_shell; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=recovery-required
		elif screensaver_effects_shell_has_dotfiles_edges; then
			SCREENSAVER_EFFECTS_LIFECYCLE_STATE=drifted
		fi
		return 0
	fi
	if screensaver_effects_active_matches_receipt "$SCREENSAVER_EFFECTS_APPLY_RECEIPT"; then
		SCREENSAVER_EFFECTS_LIFECYCLE_STATE=active
	else
		SCREENSAVER_EFFECTS_LIFECYCLE_STATE=drifted
	fi
}

screensaver_effects_status() {
	screensaver_effects_print_versions
	screensaver_effects_classify
	printf 'Lifecycle: %s\n' "$SCREENSAVER_EFFECTS_LIFECYCLE_STATE"
	if [[ $SCREENSAVER_EFFECTS_LIFECYCLE_STATE == conflicting && ${#SCREENSAVER_EFFECTS_COMPETING_CLONES[@]} -gt 0 ]]; then
		printf 'Competing clones: %s\n' "${SCREENSAVER_EFFECTS_COMPETING_CLONES[*]}"
		printf 'Recovery: choose Migrate competing screensaver clones in the Dotfiles wizard.\n'
	elif [[ $SCREENSAVER_EFFECTS_LIFECYCLE_STATE == recovery-required ]]; then
		printf 'Recovery: inspect %s and retained diagnostics before mutation.\n' "$SCREENSAVER_EFFECTS_STATE_ROOT"
	elif [[ $SCREENSAVER_EFFECTS_LIFECYCLE_STATE == drifted ]]; then
		printf 'Recovery: choose Apply Stow packages and select screensaver-effects.\n'
	fi
}

screensaver_effects_preflight_common() {
	local allow_competing=${1-false} source_validation=${2-full} command
	screensaver_effects_state_is_mutable || return 1
	for command in node jq sha256sum find sort omarchy omarchy-shell; do
		if ! command -v "$command" >/dev/null 2>&1; then
			printf 'Error: missing screensaver-effects lifecycle command: %s\n' "$command" >&2
			return 1
		fi
	done
	case $source_validation in
		full) screensaver_effects_validate_source || return 1 ;;
		shape) screensaver_effects_validate_source_shape || return 1 ;;
		*) printf 'Error: invalid screensaver-effects source validation mode: %s\n' "$source_validation" >&2; return 1 ;;
	esac
	screensaver_effects_wait_for_plugins omarchy.idle omarchy.indicators || {
		printf 'Error: required built-in Omarchy plugins did not become available.\n' >&2
		return 1
	}
	screensaver_effects_read_shell || {
		printf 'Error: could not inspect effective Omarchy shell configuration.\n' >&2
		return 1
	}
	screensaver_effects_inspect_menu || {
		printf 'Error: could not validate the Omarchy menu extension JSONC.\n' >&2
		return 1
	}
	if jq -e '.present and (.identical | not)' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
		printf 'Conflict: a different system.screensaver menu entry already exists: %s\n' "$SCREENSAVER_EFFECTS_MENU_FILE" >&2
		return 1
	fi
	screensaver_effects_find_competing_clones
	if [[ $allow_competing != true && ${#SCREENSAVER_EFFECTS_COMPETING_CLONES[@]} -gt 0 ]]; then
		printf 'Conflict: competing Omarchy clones replace the screensaver integration: %s\n' "${SCREENSAVER_EFFECTS_COMPETING_CLONES[*]}" >&2
		printf 'Recovery: choose Migrate competing screensaver clones in the Dotfiles wizard.\n' >&2
		return 1
	fi
	if [[ $SCREENSAVER_EFFECTS_PRE_MUTATION_IDLE_GUARD == true ]]; then
		local exact_noop=false
		if [[ $SCREENSAVER_EFFECTS_APPLY_NOOP == true && -n $SCREENSAVER_EFFECTS_APPLY_RECEIPT ]] && \
			screensaver_effects_active_matches_receipt "$SCREENSAVER_EFFECTS_APPLY_RECEIPT"; then
			exact_noop=true
		fi
		if [[ $exact_noop != true ]] && ! screensaver_effects_require_idle_cycle_inactive; then
			return 1
		fi
	fi
}

screensaver_effects_prepare_apply() {
	local allow_competing=${1-false} idle_link indicators_link receipt_state menu_owned source_validation=full
	SCREENSAVER_EFFECTS_APPLY_NOOP=false
	SCREENSAVER_EFFECTS_PRE_MUTATION_IDLE_GUARD=false
	SCREENSAVER_EFFECTS_APPLY_RECEIPT=''
	printf 'Screensaver effects compatibility:\n'
	screensaver_effects_print_versions
	if declare -p MISSING_ARCH_PACKAGES >/dev/null 2>&1 && ((${#MISSING_ARCH_PACKAGES[@]} > 0)); then
		source_validation=shape
	fi
	screensaver_effects_preflight_common "$allow_competing" "$source_validation" || return 1
	idle_link=$(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED")
	indicators_link=$(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED")
	if [[ $idle_link == conflicting || $indicators_link == conflicting ]]; then
		printf 'Conflict: a live Dotfiles plugin path is not the receipt-owned canonical symlink.\n' >&2
		return 1
	fi
	if ! screensaver_effects_stow_links_are_safe_to_apply; then
		printf 'Conflict: existing screensaver-effects Stow leaves are missing, changed, or foreign; Apply cannot adopt them.\n' >&2
		return 1
	fi
	if [[ -f $SCREENSAVER_EFFECTS_RECEIPT ]]; then
		SCREENSAVER_EFFECTS_APPLY_RECEIPT=$(<"$SCREENSAVER_EFFECTS_RECEIPT")
		receipt_state=$(jq -r .state <<<"$SCREENSAVER_EFFECTS_APPLY_RECEIPT")
		if [[ $receipt_state == inactive && ( $idle_link != absent || $indicators_link != absent ) ]]; then
			printf 'Conflict: an inactive receipt cannot own installed live plugin links.\n' >&2
			return 1
		fi
		if [[ $receipt_state == active ]]; then
			if ! screensaver_effects_validate_owned_bar_positions "$SCREENSAVER_EFFECTS_APPLY_RECEIPT" apply; then
				printf 'Conflict: receipt-owned Indicators bar positions contain unrelated entries or moved clone edges.\n' >&2
				return 1
			fi
			if [[ $idle_link == exact ]] && ! screensaver_effects_validate_idle_restore_metadata "$SCREENSAVER_EFFECTS_APPLY_RECEIPT"; then
				printf 'Conflict: receipt-owned idle restoration metadata changed.\n' >&2
				return 1
			fi
			menu_owned=$(jq -r .owned_edges.menu_entry <<<"$SCREENSAVER_EFFECTS_APPLY_RECEIPT")
			if [[ $menu_owned == true ]] && ! jq -e '(.present | not) or (.identical and .owned_marker)' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
				printf 'Conflict: the receipt-owned system.screensaver menu entry changed.\n' >&2
				return 1
			fi
			if [[ $menu_owned == false ]] && ! jq -e '.present and .identical and (.owned_marker | not)' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
				printf 'Conflict: the unowned system.screensaver menu entry changed.\n' >&2
				return 1
			fi
			if screensaver_effects_active_matches_receipt "$SCREENSAVER_EFFECTS_APPLY_RECEIPT"; then
				SCREENSAVER_EFFECTS_APPLY_NOOP=true
			fi
		fi
	fi
	if [[ -z $SCREENSAVER_EFFECTS_APPLY_RECEIPT || $(jq -r .state <<<"$SCREENSAVER_EFFECTS_APPLY_RECEIPT") == inactive ]]; then
		if [[ $idle_link != absent || $indicators_link != absent ]] || jq -e '.owned_marker' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
			printf 'Conflict: lifecycle edges exist without an active ownership receipt.\n' >&2
			return 1
		fi
		if screensaver_effects_shell_has_dotfiles_edges; then
			printf 'Conflict: Dotfiles plugin activation state exists without an active ownership receipt.\n' >&2
			return 1
		fi
		SCREENSAVER_EFFECTS_APPLY_PRIOR=$(screensaver_effects_current_prior) || return 1
		if jq -e '.plugin_states["dotfiles.idle"] or .plugin_states["dotfiles.indicators"]' <<<"$SCREENSAVER_EFFECTS_APPLY_PRIOR" >/dev/null; then
			printf 'Conflict: Dotfiles plugin identities are active without an ownership receipt.\n' >&2
			return 1
		fi
	else
		SCREENSAVER_EFFECTS_APPLY_PRIOR=$(jq -c .prior <<<"$SCREENSAVER_EFFECTS_APPLY_RECEIPT")
	fi
	if [[ $SCREENSAVER_EFFECTS_APPLY_NOOP != true ]] && ! screensaver_effects_require_idle_cycle_inactive; then
		return 1
	fi
	SCREENSAVER_EFFECTS_PRE_MUTATION_IDLE_GUARD=true
	printf 'Plan: screensaver-effects lifecycle:\n'
	if [[ $SCREENSAVER_EFFECTS_APPLY_NOOP == true ]]; then
		printf '  exact active state; no plugin rescan or lifecycle mutation\n'
	else
		printf '  validate canonical plugin sources and receipt state\n'
		printf '  publish dotfiles.idle and dotfiles.indicators as whole-directory symlinks\n'
		printf '  rescan after link publication; restart the shell when active source bytes changed or the loaded idle source identity is stale or missing\n'
		printf '  replace each existing omarchy.indicators bar entry in place; add none when absent\n'
		printf '  enable dotfiles.idle through Omarchy and publish system.screensaver last\n'
		printf '  record recoverable ownership under %s\n' "$SCREENSAVER_EFFECTS_STATE_ROOT"
	fi
}

screensaver_effects_publish_link() {
	local live=$1 deployed=$2 created_name=$3 state
	state=$(screensaver_effects_link_state "$live" "$deployed")
	case $state in
		exact) printf -v "$created_name" false ;;
		absent)
			mkdir -p -- "$SCREENSAVER_EFFECTS_PLUGIN_ROOT" || return 1
			ln -s -- "$deployed" "$live" || return 1
			printf -v "$created_name" true
			;;
		*) return 1 ;;
	esac
}

screensaver_effects_switch_bar_to_clone() {
	local prior=$1 entries result
	entries=$(jq -c .indicators_entries <<<"$prior") || return 1
	result=$(node "$SCREENSAVER_EFFECTS_JSONC_HELPER" shell-bar-activate "$SCREENSAVER_EFFECTS_SHELL_FILE" "$entries") || return 1
	if [[ $(jq -r .changed <<<"$result") == true ]]; then
		screensaver_effects_reload_shell || return 1
	fi
}

screensaver_effects_restore_bar_snapshot() {
	local entries=$1 result
	result=$(node "$SCREENSAVER_EFFECTS_JSONC_HELPER" shell-bar-restore "$SCREENSAVER_EFFECTS_SHELL_FILE" "$entries") || return 1
	if [[ $(jq -r .changed <<<"$result") == true ]]; then
		screensaver_effects_reload_shell || return 1
	fi
}

screensaver_effects_make_receipt() {
	local prior=$1 migration=$2 menu_owned=$3 activated_at=$4
	local idle=${5-$SCREENSAVER_EFFECTS_IDLE_FINGERPRINT}
	local indicators=${6-$SCREENSAVER_EFFECTS_INDICATORS_FINGERPRINT}
	local source_identity=${7-$SCREENSAVER_EFFECTS_SOURCE_IDENTITY}
	local indicators_active
	indicators_active=$(jq -r '.indicators_entries | length > 0' <<<"$prior")
	jq -cn \
		--arg idle "$idle" --arg indicators "$indicators" --arg sourceIdentity "$source_identity" \
		--argjson prior "$prior" --argjson menuOwned "$menu_owned" --argjson indicatorsActive "$indicators_active" \
		--argjson migration "$migration" --arg activatedAt "$activated_at" '
		{
			schema_version:1,
			package:"screensaver-effects",
			state:"active",
			recoverability:"verified",
			source_fingerprints:{"dotfiles.idle":$idle,"dotfiles.indicators":$indicators},
			source_identity:$sourceIdentity,
			prior:$prior,
			owned_edges:{idle_link:true,indicators_link:true,idle_activation:true,indicators_activation:$indicatorsActive,menu_entry:$menuOwned},
			migration:$migration,
			activated_at:$activatedAt,
			removed_at:null
		}'
}

screensaver_effects_archive_inactive_receipt() {
	[[ -f $SCREENSAVER_EFFECTS_RECEIPT ]] || return 0
	[[ $(jq -r .state "$SCREENSAVER_EFFECTS_RECEIPT") == inactive ]] || return 0
	local directory timestamp archive
	directory=$SCREENSAVER_EFFECTS_STATE_ROOT/receipts
	timestamp=$(screensaver_effects_timestamp)
	archive=$directory/${timestamp//:/-}-inactive.json
	mkdir -p -- "$directory" || return 1
	cp --archive -- "$SCREENSAVER_EFFECTS_RECEIPT" "$archive" || return 1
}

screensaver_effects_remove_live_link() {
	local id=$1 live=$SCREENSAVER_EFFECTS_PLUGIN_ROOT/$1
	[[ -e $live || -L $live ]] || return 0
	omarchy plugin remove "$id" --yes >/dev/null
}

screensaver_effects_run_idle_plugin_command() {
	local operation=$1 shell_fields=${2-'{}'} snapshot result command_failed=false
	snapshot=$(mktemp "${TMPDIR:-/tmp}/dotfiles-screensaver-shell.XXXXXX") || return 1
	if ! cp --archive -- "$SCREENSAVER_EFFECTS_SHELL_FILE" "$snapshot"; then
		rm -f -- "$snapshot"
		return 1
	fi
	if ! omarchy plugin "$operation" dotfiles.idle >/dev/null; then
		command_failed=true
	fi
	if [[ $command_failed == true ]]; then
		node "$SCREENSAVER_EFFECTS_JSONC_HELPER" shell-restore-snapshot "$SCREENSAVER_EFFECTS_SHELL_FILE" "$snapshot" >/dev/null || {
			rm -f -- "$snapshot"
			return 1
		}
		screensaver_effects_reload_shell || true
		rm -f -- "$snapshot"
		return 1
	fi
	if ! result=$(node "$SCREENSAVER_EFFECTS_JSONC_HELPER" "shell-idle-$operation" \
		"$SCREENSAVER_EFFECTS_SHELL_FILE" "$snapshot" "$shell_fields"); then
		node "$SCREENSAVER_EFFECTS_JSONC_HELPER" shell-restore-snapshot "$SCREENSAVER_EFFECTS_SHELL_FILE" "$snapshot" >/dev/null || {
			rm -f -- "$snapshot"
			return 1
		}
		screensaver_effects_reload_shell || true
		rm -f -- "$snapshot"
		return 1
	fi
	rm -f -- "$snapshot"
	jq -e '.changed | type == "boolean"' <<<"$result" >/dev/null || return 1
	screensaver_effects_reload_shell
}

screensaver_effects_rollback_apply() {
	local bar_snapshot=$1 idle_was_enabled=$2 menu_inserted=$3 menu_file_existed=$4 idle_link_created=$5 indicators_link_created=$6
	local preserve_pending=${7-false}
	local prior=${8-'{}'}
	local recovery_operation=${9-apply}
	local failed=false
	if [[ $menu_inserted == true ]]; then
		node "$SCREENSAVER_EFFECTS_JSONC_HELPER" remove "$SCREENSAVER_EFFECTS_MENU_FILE" "$menu_file_existed" >/dev/null || failed=true
	fi
	if screensaver_effects_read_plugins && [[ $idle_was_enabled == false && $(screensaver_effects_plugin_enabled dotfiles.idle) == true ]]; then
		screensaver_effects_run_idle_plugin_command disable "$(jq -c .shell_fields <<<"$prior")" || failed=true
	fi
	if [[ $(jq length <<<"$bar_snapshot") -gt 0 ]]; then
		screensaver_effects_restore_bar_snapshot "$bar_snapshot" || failed=true
	fi
	if [[ $idle_link_created == true ]]; then
		screensaver_effects_remove_live_link dotfiles.idle || failed=true
	fi
	if [[ $indicators_link_created == true ]]; then
		screensaver_effects_remove_live_link dotfiles.indicators || failed=true
	fi
	if [[ $failed == false && ( $idle_link_created == true || $indicators_link_created == true ) ]] && \
		! screensaver_effects_wait_for_removal_convergence; then
		failed=true
	fi
	if [[ $failed == true ]]; then
		if ! screensaver_effects_mark_recovery "$recovery_operation" 'activation rollback could not restore every lifecycle edge'; then
			printf 'Recovery: could not publish activation rollback evidence; pending state was retained.\n' >&2
		fi
		return 1
	fi
	if [[ $preserve_pending != true ]]; then
		rm -f -- "$SCREENSAVER_EFFECTS_PENDING"
	fi
}

screensaver_effects_activate() {
	local pending_operation=${1-apply} migration=${2-'{"performed":false,"backup":null,"clone_ids":[]}'}
	screensaver_effects_set_paths
	if [[ $pending_operation != apply ]]; then
		screensaver_effects_validate_source || return 1
		screensaver_effects_wait_for_plugins omarchy.idle omarchy.indicators || return 1
		screensaver_effects_read_shell || return 1
		screensaver_effects_inspect_menu || return 1
	fi
	if ! screensaver_effects_repair_stale_owned_stow_links || ! screensaver_effects_stow_links_are_complete; then
		printf 'Conflict: screensaver-effects Stow deployment is not complete and exact after Stow; lifecycle mutation was skipped.\n' >&2
		return 1
	fi
	local expected_idle_fingerprint=$SCREENSAVER_EFFECTS_IDLE_FINGERPRINT
	local expected_indicators_fingerprint=$SCREENSAVER_EFFECTS_INDICATORS_FINGERPRINT
	local expected_source_identity=$SCREENSAVER_EFFECTS_SOURCE_IDENTITY
	if [[ ! -d $SCREENSAVER_EFFECTS_IDLE_DEPLOYED || ! -d $SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED ]]; then
		printf 'Error: verified Stow plugin sources are not deployed.\n' >&2
		return 1
	fi
	local receipt='' prior activated_at menu_owned=false
	if [[ -f $SCREENSAVER_EFFECTS_RECEIPT ]]; then
		receipt=$(<"$SCREENSAVER_EFFECTS_RECEIPT")
	fi
	if [[ -n $receipt && $(jq -r .state <<<"$receipt") == active ]] && screensaver_effects_active_matches_receipt "$receipt"; then
		printf 'Screensaver effects lifecycle already active; no rescan needed.\n'
		return 0
	fi
	if ! screensaver_effects_require_idle_cycle_inactive; then
		return 1
	fi
	if [[ -n $receipt && $(jq -r .state <<<"$receipt") == active ]]; then
		prior=$(jq -c .prior <<<"$receipt")
		activated_at=$(jq -r .activated_at <<<"$receipt")
		migration=$(jq -c .migration <<<"$receipt")
	else
		prior=$(screensaver_effects_current_prior) || return 1
		activated_at=$(screensaver_effects_timestamp)
		screensaver_effects_archive_inactive_receipt || return 1
	fi
	local bar_snapshot idle_was_enabled menu_file_existed
	bar_snapshot=$(jq -c '
		def entry_id: if type == "object" then (.id // "") else tostring end;
		[.bar.layout | to_entries[] as $section | $section.value | to_entries[]
		 | select(.value | entry_id == "omarchy.indicators" or entry_id == "dotfiles.indicators")
		 | {section:$section.key,index:.key,entry:.value}]
	' <<<"$SCREENSAVER_EFFECTS_SHELL_JSON")
	idle_was_enabled=$(screensaver_effects_plugin_enabled dotfiles.idle)
	menu_file_existed=$(jq -r .file_exists <<<"$SCREENSAVER_EFFECTS_MENU_JSON")
	if [[ $pending_operation == apply ]]; then
		screensaver_effects_write_pending apply || return 1
	fi
	local idle_link_created=false indicators_link_created=false menu_inserted=false needs_rescan=false needs_shell_restart=false
	local needs_activation_runtime=false activation_prior_instance='' activation_requested_at_ms=''
	local reason='activation failed' result current_idle current_indicators receipt_identity prior_idle_instance='' prior_idle_started_at_ms='' reload_requested_at_ms=''
	local preserve_pending=false
	if ! screensaver_effects_publish_link "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED" idle_link_created || \
		! screensaver_effects_publish_link "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED" indicators_link_created; then
		reason='could not publish canonical live plugin links'
	elif [[ $idle_link_created == true || $indicators_link_created == true ]]; then
		needs_rescan=true
	fi
	if [[ -n $receipt && $(jq -r .state <<<"$receipt") == active ]]; then
		current_idle=$(jq -r '.source_fingerprints["dotfiles.idle"]' <<<"$receipt")
		current_indicators=$(jq -r '.source_fingerprints["dotfiles.indicators"]' <<<"$receipt")
		receipt_identity=$(jq -r '.source_identity' <<<"$receipt")
		if [[ $current_idle != "$expected_idle_fingerprint" || $current_indicators != "$expected_indicators_fingerprint" || \
			$receipt_identity != "$expected_source_identity" ]]; then
			needs_shell_restart=true
		elif ! screensaver_effects_idle_runtime_matches_identity "$expected_source_identity"; then
			needs_shell_restart=true
		fi
	fi
	if [[ $reason == 'activation failed' && ( $needs_rescan == true || $needs_shell_restart == true ) ]]; then
		if ! screensaver_effects_require_idle_cycle_inactive; then
			reason='reload refused while the idle cycle is active; wait for activity, then retry'
		else
			screensaver_effects_capture_idle_instance
			prior_idle_instance=$SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID
			prior_idle_started_at_ms=$SCREENSAVER_EFFECTS_IDLE_STARTED_AT_MS
		fi
	fi
	if [[ $reason == 'activation failed' && ( $needs_rescan == true || $needs_shell_restart == true ) ]]; then
		reload_requested_at_ms=$(date +%s%3N)
		if [[ ! $reload_requested_at_ms =~ ^[0-9]+$ ]]; then
			reason='could not record the plugin reload request time'
		elif [[ $needs_shell_restart == true ]] && ! omarchy restart shell >/dev/null; then
			reason='the Omarchy shell restart for changed plugin sources failed'
		elif [[ $needs_shell_restart != true ]] && ! omarchy-shell shell rescanPlugins >/dev/null; then
			reason='the explicit plugin rescan failed'
		fi
	fi
	if [[ $reason == 'activation failed' ]]; then
		if ! screensaver_effects_wait_for_plugins omarchy.idle omarchy.indicators dotfiles.idle dotfiles.indicators; then
			reason='the published plugins were not discovered'
		fi
	fi
	if [[ $reason == 'activation failed' ]]; then
		screensaver_effects_read_plugins || reason='plugin state became unavailable before idle activation'
	fi
	if [[ $reason == 'activation failed' && $(screensaver_effects_plugin_enabled dotfiles.idle) != true ]]; then
		if [[ $needs_rescan != true && $needs_shell_restart != true ]]; then
			screensaver_effects_capture_idle_instance
			activation_prior_instance=$SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID
			activation_requested_at_ms=$(date +%s%3N)
			if [[ ! $activation_requested_at_ms =~ ^[0-9]+$ ]]; then
				reason='could not record the idle activation request time'
			else
				needs_activation_runtime=true
			fi
		fi
		if [[ $reason == 'activation failed' ]] && ! screensaver_effects_run_idle_plugin_command enable; then
			reason='dotfiles.idle activation failed'
		fi
	fi
	if [[ $reason == 'activation failed' && ( $needs_rescan == true || $needs_shell_restart == true ) ]]; then
		if ! screensaver_effects_wait_for_idle_instance "$prior_idle_instance" "$reload_requested_at_ms" "$expected_source_identity"; then
			reason='the reloaded idle runtime did not become ready'
		fi
	fi
	if [[ $reason == 'activation failed' && $needs_activation_runtime == true ]] && \
		! screensaver_effects_wait_for_idle_instance "$activation_prior_instance" "$activation_requested_at_ms" "$expected_source_identity"; then
		reason='the activated idle runtime did not become ready'
	fi
	if [[ $reason == 'activation failed' ]]; then
		if ! screensaver_effects_switch_bar_to_clone "$prior"; then
			reason='Indicators bar replacement failed'
		fi
	fi
	if [[ $reason == 'activation failed' ]]; then
		if ! result=$(node "$SCREENSAVER_EFFECTS_JSONC_HELPER" insert "$SCREENSAVER_EFFECTS_MENU_FILE"); then
			reason='system.screensaver menu publication failed'
		else
			menu_owned=$(jq -r .owned <<<"$result")
			menu_inserted=$(jq -r .changed <<<"$result")
		fi
	fi
	if [[ $reason == 'activation failed' ]] && ! screensaver_effects_source_snapshot_matches \
		"$expected_idle_fingerprint" "$expected_indicators_fingerprint" "$expected_source_identity"; then
		reason='validated plugin sources changed during activation'
	fi
	if [[ $reason == 'activation failed' ]]; then
		receipt=$(screensaver_effects_make_receipt "$prior" "$migration" "$menu_owned" "$activated_at" \
			"$expected_idle_fingerprint" "$expected_indicators_fingerprint" "$expected_source_identity") || reason='receipt construction failed'
	fi
	if [[ $reason == 'activation failed' ]]; then
		if ! screensaver_effects_active_matches_receipt "$receipt"; then
			reason='active lifecycle verification failed'
		fi
	fi
	if [[ $reason == 'activation failed' ]]; then
		if ! screensaver_effects_write_json "$SCREENSAVER_EFFECTS_RECEIPT" "$receipt"; then
			reason='active receipt publication failed'
		fi
	fi
	if [[ $reason != 'activation failed' ]]; then
		printf 'Error: screensaver-effects %s.\n' "$reason" >&2
		screensaver_effects_record_diagnostic "$pending_operation" "$reason"
		if [[ $pending_operation == migrate ]]; then
			preserve_pending=true
		fi
		if ! screensaver_effects_rollback_apply "$bar_snapshot" "$idle_was_enabled" "$menu_inserted" "$menu_file_existed" "$idle_link_created" "$indicators_link_created" \
			"$preserve_pending" "$prior" "$pending_operation"; then
			printf 'Recovery: Package status reports recovery-required; preserve retained state.\n' >&2
		else
			printf 'Recovery: choose Apply Stow packages and select screensaver-effects.\n' >&2
		fi
		return 1
	fi
	rm -f -- "$SCREENSAVER_EFFECTS_PENDING"
	printf 'Screensaver effects lifecycle active and verified.\n'
}

screensaver_effects_prepare_remove() {
	SCREENSAVER_EFFECTS_REMOVAL_DEACTIVATED=false
	SCREENSAVER_EFFECTS_PRE_MUTATION_IDLE_GUARD=false
	printf 'Screensaver effects compatibility:\n'
	screensaver_effects_print_versions
	screensaver_effects_preflight_common false || return 1
	if [[ ! -f $SCREENSAVER_EFFECTS_RECEIPT ]]; then
		screensaver_effects_require_inactive_edges_absent || return 1
		if ! screensaver_effects_stow_links_are_removable; then
			return 1
		fi
		printf 'Plan: screensaver-effects lifecycle is inactive; remove only verified Stow links.\n'
		return 0
	fi
	SCREENSAVER_EFFECTS_APPLY_RECEIPT=$(<"$SCREENSAVER_EFFECTS_RECEIPT")
	if [[ $(jq -r .state <<<"$SCREENSAVER_EFFECTS_APPLY_RECEIPT") == inactive ]]; then
		screensaver_effects_require_inactive_edges_absent || return 1
		if ! screensaver_effects_stow_links_are_removable; then
			return 1
		fi
		printf 'Plan: screensaver-effects lifecycle is already inactive; remove only verified Stow links.\n'
		return 0
	fi
	if ! screensaver_effects_require_idle_cycle_inactive; then
		return 1
	fi
	if ! jq -e 'has("source_identity")' <<<"$SCREENSAVER_EFFECTS_APPLY_RECEIPT" >/dev/null; then
		printf 'Conflict: legacy schema-1 receipt lacks source_identity; run Apply once to upgrade it before Remove.\n' >&2
		return 1
	fi
	if ! screensaver_effects_stow_links_are_complete; then
		printf 'Conflict: active receipt Stow deployment is missing, changed, or has foreign extra leaves; run Apply before removal.\n' >&2
		return 1
	fi
	if [[ $(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED") != exact || \
		$(screensaver_effects_link_state "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED") != exact ]]; then
		printf 'Conflict: active receipt live plugin links are missing or changed; run Apply to repair them before removal.\n' >&2
		return 1
	fi
	if ! screensaver_effects_validate_owned_bar_positions "$SCREENSAVER_EFFECTS_APPLY_RECEIPT" remove; then
		printf 'Conflict: active Indicators bar edges moved or were replaced; run Apply to repair before removal.\n' >&2
		return 1
	fi
	if ! screensaver_effects_validate_idle_restore_metadata "$SCREENSAVER_EFFECTS_APPLY_RECEIPT"; then
		printf 'Conflict: active idle restoration metadata changed; removal cannot prove exact source restoration.\n' >&2
		return 1
	fi
	local menu_owned
	menu_owned=$(jq -r .owned_edges.menu_entry <<<"$SCREENSAVER_EFFECTS_APPLY_RECEIPT")
	if [[ $menu_owned == true ]] && ! jq -e '.present and .identical and .owned_marker' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
		printf 'Conflict: receipt-owned system.screensaver entry changed; removal will not delete it.\n' >&2
		return 1
	fi
	if [[ $menu_owned == false ]] && ! jq -e '.present and .identical and (.owned_marker | not)' <<<"$SCREENSAVER_EFFECTS_MENU_JSON" >/dev/null; then
		printf 'Conflict: unowned system.screensaver entry changed or disappeared.\n' >&2
		return 1
	fi
	printf 'Plan: deactivate screensaver-effects before Stow removal:\n'
	printf '  remove only an unchanged receipt-owned menu entry\n'
	printf '  restore exact prior idle and Indicators bar state without changing Stay Awake\n'
	printf '  remove both live plugin links through Omarchy, then remove Stow links\n'
	printf '  retain receipt, backups, and diagnostics under %s\n' "$SCREENSAVER_EFFECTS_STATE_ROOT"
}

screensaver_effects_verify_prior_state() {
	local prior=$1 expected actual section index
	screensaver_effects_read_plugins || return 1
	screensaver_effects_read_shell || return 1
	expected=$(jq -r '.plugin_states["omarchy.idle"]' <<<"$prior")
	[[ $(screensaver_effects_plugin_enabled omarchy.idle) == "$expected" ]] || return 1
	expected=$(jq -r '.plugin_states["omarchy.indicators"]' <<<"$prior")
	[[ $(screensaver_effects_plugin_enabled omarchy.indicators) == "$expected" ]] || return 1
	[[ $(screensaver_effects_plugin_enabled dotfiles.idle) == false ]] || return 1
	[[ $(screensaver_effects_plugin_enabled dotfiles.indicators) == false ]] || return 1
	! screensaver_effects_shell_has_dotfiles_edges || return 1
	while IFS=$'\t' read -r section index expected; do
		actual=$(jq -S -c --arg section "$section" --argjson index "$index" '.bar.layout[$section][$index]' <<<"$SCREENSAVER_EFFECTS_SHELL_JSON")
		[[ $actual == "$(jq -S -c . <<<"$expected")" ]] || return 1
	done < <(jq -r '.indicators_entries[] | [.section,.index,(.entry | @json)] | @tsv' <<<"$prior")
}

screensaver_effects_wait_for_removal_convergence() {
	local prior=${1-} attempt prior_idle_enabled
	local OMARCHY_SHELL_IPC_TIMEOUT=0.1s
	export OMARCHY_SHELL_IPC_TIMEOUT
	for ((attempt = 0; attempt < 40; attempt++)); do
		if ! screensaver_effects_read_plugins || ! jq -e 'all(.[]; .id != "dotfiles.idle" and .id != "dotfiles.indicators")' \
			<<<"$SCREENSAVER_EFFECTS_PLUGIN_JSON" >/dev/null; then
			sleep 0.05
			continue
		fi
		if [[ -n $prior ]]; then
			if ! screensaver_effects_verify_prior_state "$prior"; then
				sleep 0.05
				continue
			fi
			prior_idle_enabled=$(jq -r '.plugin_states["omarchy.idle"]' <<<"$prior")
		else
			prior_idle_enabled=$(screensaver_effects_plugin_enabled omarchy.idle)
		fi
		if [[ $prior_idle_enabled == true ]]; then
			if screensaver_effects_read_idle_instance && \
				[[ -z $SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID && -z $SCREENSAVER_EFFECTS_IDLE_SOURCE_IDENTITY ]]; then
				return 0
			fi
		elif ! screensaver_effects_read_idle_instance || \
			[[ -z $SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID && -z $SCREENSAVER_EFFECTS_IDLE_SOURCE_IDENTITY ]]; then
			return 0
		fi
		sleep 0.05
	done
	return 1
}

screensaver_effects_deactivate() {
	screensaver_effects_set_paths
	SCREENSAVER_EFFECTS_REMOVAL_DEACTIVATED=false
	[[ -f $SCREENSAVER_EFFECTS_RECEIPT ]] || return 0
	local receipt prior menu_owned menu_file_existed entries
	receipt=$(<"$SCREENSAVER_EFFECTS_RECEIPT")
	[[ $(jq -r .state <<<"$receipt") == active ]] || return 0
	if ! screensaver_effects_require_idle_cycle_inactive; then
		return 1
	fi
	if ! screensaver_effects_stow_links_are_complete; then
		printf 'Conflict: active receipt Stow deployment is missing, changed, or has foreign extra leaves; removal was skipped.\n' >&2
		return 1
	fi
	prior=$(jq -c .prior <<<"$receipt")
	menu_owned=$(jq -r .owned_edges.menu_entry <<<"$receipt")
	menu_file_existed=$(jq -r .prior.menu.file_existed <<<"$receipt")
	screensaver_effects_write_pending remove || return 1
	local reason='deactivation failed'
	if [[ $menu_owned == true ]] && ! node "$SCREENSAVER_EFFECTS_JSONC_HELPER" remove "$SCREENSAVER_EFFECTS_MENU_FILE" "$menu_file_existed" >/dev/null; then
		reason='receipt-owned menu removal failed'
	fi
	if [[ $reason == 'deactivation failed' ]]; then
		screensaver_effects_read_plugins || reason='plugin state became unavailable during removal'
	fi
	if [[ $reason == 'deactivation failed' ]] && \
		( [[ $(screensaver_effects_plugin_enabled dotfiles.idle) == true ]] || screensaver_effects_shell_has_dotfiles_edges ); then
		screensaver_effects_run_idle_plugin_command disable "$(jq -c .shell_fields <<<"$prior")" || reason='dotfiles.idle disable failed'
	fi
	entries=$(jq -c .indicators_entries <<<"$prior")
	if [[ $reason == 'deactivation failed' && $(jq length <<<"$entries") -gt 0 ]]; then
		screensaver_effects_restore_bar_snapshot "$entries" || reason='exact Indicators bar restoration failed'
	fi
	if [[ $reason == 'deactivation failed' ]]; then
		screensaver_effects_remove_live_link dotfiles.idle || reason='dotfiles.idle link removal failed'
	fi
	if [[ $reason == 'deactivation failed' ]]; then
		screensaver_effects_remove_live_link dotfiles.indicators || reason='dotfiles.indicators link removal failed'
	fi
	if [[ $reason == 'deactivation failed' ]] && ! screensaver_effects_wait_for_removal_convergence "$prior"; then
		reason='removed plugins and restored idle state did not converge'
	fi
	if [[ $reason != 'deactivation failed' ]]; then
		printf 'Error: screensaver-effects %s.\n' "$reason" >&2
		screensaver_effects_record_diagnostic remove "$reason"
		return 1
	fi
	SCREENSAVER_EFFECTS_REMOVAL_DEACTIVATED=true
	printf 'Screensaver effects lifecycle deactivated; Stow sources remain pending removal.\n'
}

screensaver_effects_stow_plugin_roots() {
	printf '%s\t%s\n' "$SCREENSAVER_EFFECTS_IDLE_SOURCE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED"
	printf '%s\t%s\n' "$SCREENSAVER_EFFECTS_INDICATORS_SOURCE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED"
}

screensaver_effects_stow_target_is_owned_stale() {
	local source_root=$1 relative=$2 target=$3 canonical_source expected_target actual_target
	[[ -L $target ]] || return 1
	canonical_source=$(readlink -f -- "$source_root") || return 1
	expected_target=$(readlink -m -- "$canonical_source/$relative") || return 1
	actual_target=$(readlink -m -- "$target") || return 1
	[[ $actual_target == "$canonical_source/"* && $actual_target == "$expected_target" ]] || return 1
	[[ ! -e $actual_target && ! -L $actual_target ]]
}

screensaver_effects_stow_links_audit() {
	local mode=${1-complete} package_root=$REPOSITORY_ROOT/config/screensaver-effects
	local source relative target found=false source_root target_root expected
	case $mode in
		safe-apply|complete|absent) ;;
		*) printf 'Error: invalid screensaver-effects Stow audit mode: %s\n' "$mode" >&2; return 1 ;;
	esac
	while IFS= read -r -d '' source; do
		found=true
		relative=${source#"$package_root/"}
		target=$HOME/$relative
		case $mode in
			safe-apply)
				if [[ -e $target || -L $target ]] && \
					{ [[ ! -L $target ]] || [[ $(readlink -f -- "$target") != "$(readlink -f -- "$source")" ]]; }; then
					printf 'Expected deployed Stow leaf is already present but incorrect: %s\n' "$target" >&2
					return 1
				fi
				;;
			complete)
				if [[ ! -L $target ]] || [[ $(readlink -f -- "$target") != "$(readlink -f -- "$source")" ]]; then
					printf 'Expected deployed Stow leaf is missing or incorrect: %s\n' "$target" >&2
					return 1
				fi
				;;
			absent)
				if [[ -e $target || -L $target ]]; then
					printf 'Managed Stow leaf remains after removal: %s\n' "$target" >&2
					return 1
				fi
				;;
		esac
	done < <(find "$package_root" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
	[[ $found == true ]] || return 1

	while IFS=$'\t' read -r source_root target_root; do
		if [[ -e $target_root || -L $target_root ]]; then
			if [[ ! -d $target_root || -L $target_root ]]; then
				printf 'Foreign extra path exists in the deployed screensaver-effects plugin tree: %s\n' "$target_root" >&2
				return 1
			fi
		else
			continue
		fi
		while IFS= read -r -d '' target; do
			relative=${target#"$target_root/"}
			expected=$source_root/$relative
			[[ -f $expected && ! -L $expected ]] && continue
			if [[ $mode == safe-apply ]] && screensaver_effects_stow_target_is_owned_stale "$source_root" "$relative" "$target"; then
				continue
			fi
			if screensaver_effects_stow_target_is_owned_stale "$source_root" "$relative" "$target"; then
				printf 'Stale owned Stow leaf remains after its source was removed: %s\n' "$target" >&2
			else
				printf 'Foreign extra path exists in the deployed screensaver-effects plugin tree: %s\n' "$target" >&2
			fi
			return 1
		done < <(find "$target_root" -mindepth 1 \( -type f -o -type l \) -print0 2>/dev/null | LC_ALL=C sort -z)
	done < <(screensaver_effects_stow_plugin_roots)
}

screensaver_effects_stow_links_are_safe_to_apply() {
	screensaver_effects_stow_links_audit safe-apply
}

screensaver_effects_stow_links_are_complete() {
	screensaver_effects_stow_links_audit complete
}

screensaver_effects_stow_links_are_absent() {
	screensaver_effects_stow_links_audit absent
}

screensaver_effects_stow_links_are_removable() {
	if screensaver_effects_stow_links_are_complete >/dev/null 2>&1 || screensaver_effects_stow_links_are_absent >/dev/null 2>&1; then
		return 0
	fi
	printf 'Conflict: screensaver-effects Stow deployment is partial or contains foreign extra leaves; removal cannot claim an exact package boundary.\n' >&2
	return 1
}

screensaver_effects_repair_stale_owned_stow_links() {
	local source_root target_root target relative expected
	screensaver_effects_stow_links_are_safe_to_apply || return 1
	while IFS=$'\t' read -r source_root target_root; do
		[[ -d $target_root && ! -L $target_root ]] || continue
		while IFS= read -r -d '' target; do
			relative=${target#"$target_root/"}
			expected=$source_root/$relative
			[[ -f $expected && ! -L $expected ]] && continue
			if screensaver_effects_stow_target_is_owned_stale "$source_root" "$relative" "$target"; then
				rm -f -- "$target" || {
					printf 'Conflict: could not remove stale owned Stow leaf during Apply repair: %s\n' "$target" >&2
					return 1
				}
				printf 'Repaired stale owned Stow leaf: %s\n' "$target"
			fi
		done < <(find "$target_root" -mindepth 1 \( -type f -o -type l \) -print0 2>/dev/null | LC_ALL=C sort -z)
	done < <(screensaver_effects_stow_plugin_roots)
}

screensaver_effects_stow_package_state() {
	if screensaver_effects_stow_links_are_complete >/dev/null 2>&1; then
		printf 'linked\n'
	elif screensaver_effects_stow_links_are_absent >/dev/null 2>&1; then
		printf 'absent\n'
	else
		printf 'partial\n'
	fi
}

screensaver_effects_restore_active_after_remove_failure() {
	screensaver_effects_set_paths
	local receipt prior menu_owned expected_source_identity
	local prior_idle_instance='' rescan_requested_at_ms='' activation_prior_instance='' activation_requested_at_ms=''
	local created_idle=false created_indicators=false needs_runtime=false needs_activation_runtime=false reason='restore failed'
	[[ -f $SCREENSAVER_EFFECTS_RECEIPT ]] || return 1
	receipt=$(<"$SCREENSAVER_EFFECTS_RECEIPT")
	prior=$(jq -c .prior <<<"$receipt")
	menu_owned=$(jq -r .owned_edges.menu_entry <<<"$receipt")
	expected_source_identity=$(jq -r .source_identity <<<"$receipt")
	if ! screensaver_effects_stow_links_are_complete; then
		reason='Stow removal changed one or more deployed package leaves, so active state cannot be restored'
	fi
	if [[ $reason == 'restore failed' ]]; then
		screensaver_effects_capture_idle_instance
		prior_idle_instance=$SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID
	fi
	if [[ $reason == 'restore failed' ]]; then
		if ! screensaver_effects_publish_link "$SCREENSAVER_EFFECTS_IDLE_LIVE" "$SCREENSAVER_EFFECTS_IDLE_DEPLOYED" created_idle || \
			! screensaver_effects_publish_link "$SCREENSAVER_EFFECTS_INDICATORS_LIVE" "$SCREENSAVER_EFFECTS_INDICATORS_DEPLOYED" created_indicators; then
			reason='live plugin links could not be restored'
		fi
	fi
	if [[ $reason == 'restore failed' && ( $created_idle == true || $created_indicators == true ) ]]; then
		needs_runtime=true
		rescan_requested_at_ms=$(date +%s%3N)
		if [[ ! $rescan_requested_at_ms =~ ^[0-9]+$ ]]; then
			reason='could not record the restoration rescan request time'
		elif ! screensaver_effects_require_idle_cycle_inactive; then
			reason='restoration reload refused while the idle cycle is active; wait for activity, then retry'
		elif ! omarchy-shell shell rescanPlugins >/dev/null; then
			reason='plugin rescan failed while restoring active state'
		fi
	fi
	if [[ $reason == 'restore failed' ]]; then
		screensaver_effects_wait_for_plugins omarchy.idle omarchy.indicators dotfiles.idle dotfiles.indicators || reason='plugin state became unavailable during restoration'
	fi
	if [[ $reason == 'restore failed' && $(screensaver_effects_plugin_enabled dotfiles.idle) != true ]]; then
		if [[ $needs_runtime != true ]]; then
			screensaver_effects_capture_idle_instance
			activation_prior_instance=$SCREENSAVER_EFFECTS_IDLE_INSTANCE_ID
			activation_requested_at_ms=$(date +%s%3N)
			if [[ ! $activation_requested_at_ms =~ ^[0-9]+$ ]]; then
				reason='could not record the restoration activation request time'
			else
				needs_activation_runtime=true
			fi
		fi
		if [[ $reason == 'restore failed' ]] && ! screensaver_effects_run_idle_plugin_command enable; then
			reason='dotfiles.idle could not be reactivated'
		fi
	fi
	if [[ $reason == 'restore failed' && $needs_runtime == true ]] && ! screensaver_effects_wait_for_idle_instance \
		"$prior_idle_instance" "$rescan_requested_at_ms" "$expected_source_identity"; then
		reason='restored idle runtime did not become ready'
	fi
	if [[ $reason == 'restore failed' && $needs_activation_runtime == true ]] && \
		! screensaver_effects_wait_for_idle_instance "$activation_prior_instance" "$activation_requested_at_ms" "$expected_source_identity"; then
		reason='reactivated idle runtime did not become ready'
	fi
	if [[ $reason == 'restore failed' ]] && ! screensaver_effects_switch_bar_to_clone "$prior"; then
		reason='Indicators state could not be reactivated'
	fi
	if [[ $reason == 'restore failed' && $menu_owned == true ]] && ! node "$SCREENSAVER_EFFECTS_JSONC_HELPER" insert "$SCREENSAVER_EFFECTS_MENU_FILE" >/dev/null; then
		reason='receipt-owned menu entry could not be restored'
	fi
	if [[ $reason == 'restore failed' ]] && ! screensaver_effects_active_matches_receipt "$receipt"; then
		reason='restored active lifecycle did not verify'
	fi
	if [[ $reason != 'restore failed' ]]; then
		if ! screensaver_effects_mark_recovery remove "$reason"; then
			printf 'Recovery: could not publish removal recovery evidence; pending state was retained.\n' >&2
		fi
		screensaver_effects_record_diagnostic remove "$reason"
		printf 'Error: %s. Lifecycle is recovery-required.\n' "$reason" >&2
		return 1
	fi
	rm -f -- "$SCREENSAVER_EFFECTS_PENDING"
	printf 'Screensaver effects active state restored after Stow removal failure.\n'
}

screensaver_effects_finish_remove() {
	if ! screensaver_effects_stow_links_are_absent; then
		if ! screensaver_effects_mark_recovery remove 'Stow removal left one or more managed or extra deployed plugin leaves'; then
			printf 'Recovery: could not publish removal verification evidence; inspect Package status before another mutation.\n' >&2
		fi
		return 1
	fi
	[[ $SCREENSAVER_EFFECTS_REMOVAL_DEACTIVATED == true ]] || return 0
	local receipt timestamp inactive
	receipt=$(<"$SCREENSAVER_EFFECTS_RECEIPT")
	if ! screensaver_effects_wait_for_removal_convergence "$(jq -c .prior <<<"$receipt")"; then
		if ! screensaver_effects_mark_recovery remove 'removed plugins and restored state did not converge before inactive publication'; then
			printf 'Recovery: could not publish removal recovery evidence; pending state was retained.\n' >&2
		fi
		return 1
	fi
	timestamp=$(screensaver_effects_timestamp)
	inactive=$(jq -c --arg timestamp "$timestamp" '.state = "inactive" | .removed_at = $timestamp' <<<"$receipt") || return 1
	if ! screensaver_effects_write_json "$SCREENSAVER_EFFECTS_RECEIPT" "$inactive"; then
		if ! screensaver_effects_mark_recovery remove 'Stow links were removed but the retained inactive receipt could not be published'; then
			printf 'Recovery: could not publish removal recovery evidence; pending state was retained.\n' >&2
		fi
		return 1
	fi
	rm -f -- "$SCREENSAVER_EFFECTS_PENDING"
	printf 'Screensaver effects receipt, backups, and diagnostics retained: %s\n' "$SCREENSAVER_EFFECTS_STATE_ROOT"
}

manage_screensaver_effects() {
	local selector=$HOME/.local/libexec/dotfiles/screensaver-effects-selector
	if [[ ! -x $selector ]]; then
		printf 'Error: screensaver-effects selector is not deployed: %s\n' "$selector" >&2
		printf 'Recovery: choose Apply Stow packages and select screensaver-effects.\n' >&2
		return 1
	fi
	"$selector"
}

screensaver_effects_create_migration_backup() {
	local timestamp backup inventory='[]' id source type target hidden
	timestamp=$(screensaver_effects_timestamp)
	backup=$SCREENSAVER_EFFECTS_STATE_ROOT/backups/${timestamp//:/-}-migration
	mkdir -p -- "$backup/plugins" "$backup/plugin-content" "$backup/omarchy-remove-backups" || return 1
	chmod 0700 -- "$SCREENSAVER_EFFECTS_STATE_ROOT" "$SCREENSAVER_EFFECTS_STATE_ROOT/backups" "$backup" || return 1
	if [[ -f $HOME/.config/omarchy/shell.json && ! -L $HOME/.config/omarchy/shell.json ]]; then
		cp --archive -- "$HOME/.config/omarchy/shell.json" "$backup/shell.json" || return 1
		printf 'true\n' >"$backup/shell.existed"
	else
		printf 'false\n' >"$backup/shell.existed"
	fi
	if [[ -f $SCREENSAVER_EFFECTS_MENU_FILE && ! -L $SCREENSAVER_EFFECTS_MENU_FILE ]]; then
		cp --archive -- "$SCREENSAVER_EFFECTS_MENU_FILE" "$backup/menu.jsonc" || return 1
		printf 'true\n' >"$backup/menu.existed"
	else
		printf 'false\n' >"$backup/menu.existed"
	fi
	if [[ -f $SCREENSAVER_EFFECTS_RECEIPT && ! -L $SCREENSAVER_EFFECTS_RECEIPT ]]; then
		cp --archive -- "$SCREENSAVER_EFFECTS_RECEIPT" "$backup/receipt.json" || return 1
		printf 'true\n' >"$backup/receipt.existed"
	else
		printf 'false\n' >"$backup/receipt.existed"
	fi
	SCREENSAVER_EFFECTS_PREEXISTING_REMOVE_BACKUPS=()
	for id in "${SCREENSAVER_EFFECTS_COMPETING_CLONES[@]}"; do
		for hidden in "$SCREENSAVER_EFFECTS_PLUGIN_ROOT/.${id}.bak."*; do
			[[ -e $hidden || -L $hidden ]] || continue
			SCREENSAVER_EFFECTS_PREEXISTING_REMOVE_BACKUPS["$hidden"]=1
		done
	done
	for id in "${SCREENSAVER_EFFECTS_COMPETING_CLONES[@]}"; do
		source=$SCREENSAVER_EFFECTS_PLUGIN_ROOT/$id
		if [[ -L $source ]]; then
			type=symlink
			target=$(readlink -- "$source") || return 1
			mkdir -p -- "$backup/plugin-content/$id" || return 1
			cp --archive --dereference -- "$source/." "$backup/plugin-content/$id/" || return 1
		else
			type=directory
			target=''
			cp --archive -- "$source" "$backup/plugins/$id" || return 1
		fi
		inventory=$(jq -c --arg id "$id" --arg type "$type" --arg target "$target" \
			'. + [{id:$id,type:$type,target:(if $target == "" then null else $target end)}]' <<<"$inventory") || return 1
	done
	jq -cn --arg created "$timestamp" --argjson plugins "$inventory" \
		'{schema_version:1,package:"screensaver-effects",kind:"migration-backup",created_at:$created,plugins:$plugins}' \
		>"$backup/inventory.json" || return 1
	chmod 0600 -- "$backup/inventory.json" "$backup/shell.existed" "$backup/menu.existed" "$backup/receipt.existed" || return 1
	[[ ! -f $backup/receipt.json ]] || chmod 0600 -- "$backup/receipt.json" || return 1
	SCREENSAVER_EFFECTS_MIGRATION_BACKUP=$backup
}

screensaver_effects_move_omarchy_remove_backup() {
	local id=$1 hidden destination name
	for hidden in "$SCREENSAVER_EFFECTS_PLUGIN_ROOT/.${id}.bak."*; do
		[[ -e $hidden || -L $hidden ]] || continue
		[[ -z ${SCREENSAVER_EFFECTS_PREEXISTING_REMOVE_BACKUPS["$hidden"]+present} ]] || continue
		name=${hidden##*/}
		destination=$SCREENSAVER_EFFECTS_MIGRATION_BACKUP/omarchy-remove-backups/$name
		[[ ! -e $destination && ! -L $destination ]] || return 1
		mv -- "$hidden" "$destination" || return 1
	done
}

screensaver_effects_restore_migration_files() {
	local backup=$1 id type target destination source
	while IFS=$'\t' read -r id type target; do
		destination=$SCREENSAVER_EFFECTS_PLUGIN_ROOT/$id
		[[ ! -e $destination && ! -L $destination ]] || return 1
		case $type in
			directory)
			source=$backup/plugins/$id
			[[ -d $source && ! -L $source ]] || return 1
			cp --archive -- "$source" "$destination" || return 1
			;;
			symlink)
			[[ -n $target && -d $backup/plugin-content/$id ]] || return 1
			ln -s -- "$target" "$destination" || return 1
			;;
			*) return 1 ;;
		esac
	done < <(jq -r '.plugins[] | [.id,.type,(.target // "")] | @tsv' "$backup/inventory.json")
	if [[ $(<"$backup/shell.existed") == true ]]; then
		mkdir -p -- "$HOME/.config/omarchy" || return 1
		cp --archive -- "$backup/shell.json" "$HOME/.config/omarchy/shell.json" || return 1
	else
		rm -f -- "$HOME/.config/omarchy/shell.json" || return 1
	fi
	if [[ $(<"$backup/menu.existed") == true ]]; then
		mkdir -p -- "$(dirname -- "$SCREENSAVER_EFFECTS_MENU_FILE")" || return 1
		cp --archive -- "$backup/menu.jsonc" "$SCREENSAVER_EFFECTS_MENU_FILE" || return 1
	else
		rm -f -- "$SCREENSAVER_EFFECTS_MENU_FILE" || return 1
	fi
	if [[ $(<"$backup/receipt.existed") == true ]]; then
		mkdir -p -- "$SCREENSAVER_EFFECTS_STATE_ROOT" || return 1
		cp --archive -- "$backup/receipt.json" "$SCREENSAVER_EFFECTS_RECEIPT" || return 1
	else
		rm -f -- "$SCREENSAVER_EFFECTS_RECEIPT" || return 1
	fi
}

screensaver_effects_verify_migration_restore() {
	local backup=$1 id type target destination
	if [[ $(<"$backup/shell.existed") == true ]]; then
		cmp -s -- "$backup/shell.json" "$HOME/.config/omarchy/shell.json" || return 1
	else
		[[ ! -e $HOME/.config/omarchy/shell.json && ! -L $HOME/.config/omarchy/shell.json ]] || return 1
	fi
	if [[ $(<"$backup/menu.existed") == true ]]; then
		cmp -s -- "$backup/menu.jsonc" "$SCREENSAVER_EFFECTS_MENU_FILE" || return 1
	else
		[[ ! -e $SCREENSAVER_EFFECTS_MENU_FILE && ! -L $SCREENSAVER_EFFECTS_MENU_FILE ]] || return 1
	fi
	if [[ $(<"$backup/receipt.existed") == true ]]; then
		cmp -s -- "$backup/receipt.json" "$SCREENSAVER_EFFECTS_RECEIPT" || return 1
		screensaver_effects_validate_receipt "$SCREENSAVER_EFFECTS_RECEIPT" || return 1
	else
		[[ ! -e $SCREENSAVER_EFFECTS_RECEIPT && ! -L $SCREENSAVER_EFFECTS_RECEIPT ]] || return 1
	fi
	while IFS=$'\t' read -r id type target; do
		destination=$SCREENSAVER_EFFECTS_PLUGIN_ROOT/$id
		case $type in
			directory) diff -qr -- "$backup/plugins/$id" "$destination" >/dev/null || return 1 ;;
			symlink) [[ -L $destination && $(readlink -- "$destination") == "$target" ]] || return 1 ;;
		esac
	done < <(jq -r '.plugins[] | [.id,.type,(.target // "")] | @tsv' "$backup/inventory.json")
}

screensaver_effects_rollback_migration() {
	local backup=$1 stow_introduced=$2 failed=false id shell_fields
	if [[ -f $backup/shell.json && ! -L $backup/shell.json ]]; then
		shell_fields=$(node "$SCREENSAVER_EFFECTS_JSONC_HELPER" shell-fields "$backup/shell.json") || failed=true
	else
		shell_fields='{"plugins":false,"disabled_plugins":false,"clone_source_restores":false}'
	fi
	if screensaver_effects_read_plugins; then
		if [[ $(screensaver_effects_plugin_enabled dotfiles.idle) == true ]]; then
			screensaver_effects_run_idle_plugin_command disable "$shell_fields" || failed=true
		fi
	fi
	for id in dotfiles.idle dotfiles.indicators; do
		if [[ -e $SCREENSAVER_EFFECTS_PLUGIN_ROOT/$id || -L $SCREENSAVER_EFFECTS_PLUGIN_ROOT/$id ]]; then
			omarchy plugin remove "$id" --yes >/dev/null || failed=true
		fi
	done
	if [[ $stow_introduced == true ]]; then
		stow --no-folding --delete --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" screensaver-effects >/dev/null 2>&1 || failed=true
		screensaver_effects_stow_links_are_absent || failed=true
	else
		screensaver_effects_stow_links_are_complete || failed=true
	fi
	while IFS= read -r id; do
		if [[ -e $SCREENSAVER_EFFECTS_PLUGIN_ROOT/$id || -L $SCREENSAVER_EFFECTS_PLUGIN_ROOT/$id ]]; then
			omarchy plugin remove "$id" --yes >/dev/null || failed=true
			screensaver_effects_move_omarchy_remove_backup "$id" || failed=true
		fi
	done < <(jq -r '.plugins[].id' "$backup/inventory.json")
	screensaver_effects_restore_migration_files "$backup" || failed=true
	if [[ $failed == false ]]; then
		if ! screensaver_effects_require_idle_cycle_inactive; then
			failed=true
		else
			omarchy-shell shell rescanPlugins >/dev/null || failed=true
		fi
	fi
	if [[ $failed == false ]]; then
		if [[ -f $SCREENSAVER_EFFECTS_SHELL_FILE ]]; then
			screensaver_effects_reload_shell || failed=true
		else
			omarchy-shell shell reloadConfig >/dev/null || failed=true
		fi
	fi
	if [[ $failed == false ]]; then
		screensaver_effects_wait_for_removal_convergence || failed=true
	fi
	screensaver_effects_verify_migration_restore "$backup" || failed=true
	if [[ $failed == true ]]; then
		if ! screensaver_effects_mark_recovery migrate 'migration rollback could not restore exact plugin, bar, menu, and directory state'; then
			printf 'Recovery: could not publish migration rollback evidence; pending state was retained.\n' >&2
		fi
		return 1
	fi
	if [[ $SCREENSAVER_EFFECTS_RECOVERY_EVIDENCE_REQUIRED == true || -e $SCREENSAVER_EFFECTS_RECOVERY || -L $SCREENSAVER_EFFECTS_RECOVERY ]]; then
		if [[ ! -e $SCREENSAVER_EFFECTS_RECOVERY && ! -L $SCREENSAVER_EFFECTS_RECOVERY ]]; then
			if ! screensaver_effects_mark_recovery migrate 'inner migration activation recovery evidence could not be cleared safely'; then
				printf 'Recovery: could not publish migration recovery evidence; pending state was retained.\n' >&2
			fi
		fi
		return 1
	fi
	rm -f -- "$SCREENSAVER_EFFECTS_PENDING" "$SCREENSAVER_EFFECTS_RECOVERY"
}

migrate_screensaver_effects() {
	local approved=false interactive=false option
	for option in "$@"; do
		case $option in
			--yes) approved=true ;;
			--interactive) interactive=true ;;
			*) printf 'Error: unknown screensaver-effects migration option: %s\n' "$option" >&2; return 2 ;;
		esac
	done
	if [[ $approved != true && $interactive != true ]]; then
		printf 'Error: screensaver-effects migration requires explicit approval with --yes.\n' >&2
		return 2
	fi
	printf 'Phase: inspect\n'
	validate_catalog || return 1
	if ! jq -e '.packages[] | select(.name == "screensaver-effects") | .dependencies == []' "$PACKAGE_CATALOG" >/dev/null; then
		printf 'Error: screensaver-effects migration requires the package contract with no Stow dependencies.\n' >&2
		return 1
	fi
	if ! command -v stow >/dev/null 2>&1; then
		printf 'Error: GNU Stow is required for screensaver-effects migration.\n' >&2
		return 1
	fi
	inspect_omarchy stdout
	local prerequisite missing=false
	while IFS= read -r prerequisite; do
		if ! command -v "$prerequisite" >/dev/null 2>&1; then
			printf 'Missing package prerequisite for screensaver-effects: %s\n' "$prerequisite" >&2
			missing=true
		fi
	done < <(jq -r '.packages[] | select(.name == "screensaver-effects") | .prerequisites[]' "$PACKAGE_CATALOG")
	[[ $missing == false ]] || return 1
	validator_executables_available screensaver-effects || return 1
	plan_arch_packages screensaver-effects
	screensaver_effects_prepare_apply true || return 1
	if ((${#SCREENSAVER_EFFECTS_COMPETING_CLONES[@]} == 0)); then
		printf 'No competing screensaver plugin clones were detected; no migration is needed.\n'
		return 0
	fi
	if ! screensaver_effects_require_migration_lifecycle_inactive; then
		printf 'Conflict: dedicated migration requires an inactive, edge-free Dotfiles lifecycle.\n' >&2
		return 1
	fi
	local planned_stow_state current_stow_state
	planned_stow_state=$(screensaver_effects_stow_package_state) || return 1
	if [[ $planned_stow_state == partial ]]; then
		printf 'Conflict: screensaver-effects has a partial or conflicting Stow deployment; migration will not change any package leaf.\n' >&2
		return 1
	fi
	simulate_apply_package screensaver-effects || return 1
	printf 'Plan: migrate competing screensaver clones:\n'
	printf '  competing clones: %s\n' "${SCREENSAVER_EFFECTS_COMPETING_CLONES[*]}"
	printf '  back up complete clone directories, shell state, bar state, and menu bytes under %s/backups\n' "$SCREENSAVER_EFFECTS_STATE_ROOT"
	printf '  disable and remove competing clones through Omarchy, preserving unknown files only in the XDG backup\n'
	printf '  apply and activate screensaver-effects; retain the migration backup after later normal removal\n'
	print_arch_package_plan
	printf 'Phase: confirm\n'
	if [[ $interactive == true ]] && ! wizard_confirm 'Migrate competing clones and activate screensaver-effects with this complete plan?'; then
		printf 'No changes made.\n'
		return 0
	fi
	printf 'Approval: accepted %s\n' "$([[ $interactive == true ]] && printf interactively || printf 'by --yes')"
	install_missing_arch_packages 'Migrate competing screensaver clones' || return 1
	verify_arch_packages 'Migrate competing screensaver clones' || return 1
	if [[ $ARCH_PACKAGES_INSTALLED == true ]]; then
		simulate_apply_package screensaver-effects || return 1
	fi
	local -a planned_clones=("${SCREENSAVER_EFFECTS_COMPETING_CLONES[@]}")
	screensaver_effects_preflight_common true || return 1
	if ! screensaver_effects_require_migration_lifecycle_inactive; then
		printf 'Error: Dotfiles lifecycle state changed after confirmation; no migration mutation started.\n' >&2
		return 1
	fi
	current_stow_state=$(screensaver_effects_stow_package_state) || return 1
	if [[ $current_stow_state != "$planned_stow_state" ]]; then
		printf 'Error: screensaver-effects Stow deployment changed after confirmation; no migration mutation started.\n' >&2
		return 1
	fi
	if [[ ${SCREENSAVER_EFFECTS_COMPETING_CLONES[*]} != "${planned_clones[*]}" ]]; then
		printf 'Error: competing clone inventory changed after confirmation; no migration mutation started.\n' >&2
		return 1
	fi
	screensaver_effects_write_pending migrate || return 1
	SCREENSAVER_EFFECTS_MIGRATION_BACKUP=''
	if ! screensaver_effects_create_migration_backup; then
		rm -f -- "$SCREENSAVER_EFFECTS_PENDING"
		printf 'Error: could not create the complete screensaver-effects migration backup.\n' >&2
		return 1
	fi
	local reason='' id stow_introduced=false migration clone_json enabled
	for id in "${planned_clones[@]}"; do
		screensaver_effects_read_plugins || { reason='plugin state became unavailable during migration'; break; }
		enabled=$(screensaver_effects_plugin_enabled "$id")
		if [[ $enabled == true ]] && ! omarchy plugin disable "$id" >/dev/null; then
			reason="could not disable competing clone $id"
			break
		fi
		if ! omarchy plugin remove "$id" --yes >/dev/null; then
			reason="could not remove competing clone $id"
			break
		fi
		if ! screensaver_effects_move_omarchy_remove_backup "$id"; then
			reason="could not retain Omarchy's removal backup for $id in XDG state"
			break
		fi
	done
	if [[ -z $reason ]]; then
		if [[ $planned_stow_state == absent ]]; then
			stow_introduced=true
		fi
		if ! apply_one_package screensaver-effects; then
			reason='Stow application or source verification failed during migration'
		fi
	fi
	if [[ -z $reason ]]; then
		clone_json=$(printf '%s\n' "${planned_clones[@]}" | jq -R . | jq -sc .)
		migration=$(jq -cn --arg backup "$SCREENSAVER_EFFECTS_MIGRATION_BACKUP" --argjson clones "$clone_json" \
			'{performed:true,backup:$backup,clone_ids:$clones}')
		if ! screensaver_effects_activate migrate "$migration"; then
			reason='Dotfiles activation failed during competing-clone migration'
		fi
	fi
	if [[ -n $reason ]]; then
		printf 'Error: %s.\n' "$reason" >&2
		screensaver_effects_record_diagnostic migrate "$reason"
		if screensaver_effects_rollback_migration "$SCREENSAVER_EFFECTS_MIGRATION_BACKUP" "$stow_introduced"; then
			printf 'Migration rollback restored the exact prior plugin, bar, menu, and directory state.\n' >&2
		else
			printf 'Recovery: Package status reports recovery-required; preserve %s.\n' "$SCREENSAVER_EFFECTS_MIGRATION_BACKUP" >&2
		fi
		return 1
	fi
	printf 'Migrated competing clones and activated screensaver-effects. Backup retained: %s\n' "$SCREENSAVER_EFFECTS_MIGRATION_BACKUP"
}
