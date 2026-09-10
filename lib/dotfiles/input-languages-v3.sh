#!/usr/bin/env bash

readonly INPUT_LANGUAGES_V3_MANAGED_GROUP='Dotfiles Input Languages'
readonly INPUT_LANGUAGES_V3_SOCKET_UNIT='dotfiles-input-languages-fcitx.socket'
readonly INPUT_LANGUAGES_V3_SERVICE_UNIT='dotfiles-input-languages-fcitx.service'
readonly INPUT_LANGUAGES_V3_RESTORE_DIRECT='Restore the exact retained version-2 receipt, immutable artifact pointer, Hyprland tree, widget ownership, and original backup ancestry.'
readonly INPUT_LANGUAGES_V3_RESTORE_FCITX='Reverse only the managed-group semantic delta and restore the prior current group and still-valid nonempty method without writing profile bytes.'
readonly INPUT_LANGUAGES_V3_RESTORE_HELPER='Quiesce authority, then restore only the exact prior helper unit, enablement, pointer, runtime, and activation edges.'
readonly INPUT_LANGUAGES_V3_RESTORE_LANGUAGE='Publish the operation-start language as one new explicit target after direct authority restoration.'

input_languages_v3_set_paths() {
	INPUT_LANGUAGES_V3_SYSTEMD_USER=$INPUT_LANGUAGES_CONFIG_HOME/systemd/user
	INPUT_LANGUAGES_V3_SOCKET_PATH=$INPUT_LANGUAGES_V3_SYSTEMD_USER/$INPUT_LANGUAGES_V3_SOCKET_UNIT
	INPUT_LANGUAGES_V3_SERVICE_PATH=$INPUT_LANGUAGES_V3_SYSTEMD_USER/$INPUT_LANGUAGES_V3_SERVICE_UNIT
	INPUT_LANGUAGES_V3_WANTS_DIR=$INPUT_LANGUAGES_V3_SYSTEMD_USER/graphical-session.target.wants
	INPUT_LANGUAGES_V3_ENABLEMENT=$INPUT_LANGUAGES_V3_WANTS_DIR/$INPUT_LANGUAGES_V3_SOCKET_UNIT
	INPUT_LANGUAGES_V3_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$EUID}/dotfiles-input-languages
	INPUT_LANGUAGES_V3_RUNTIME_SOCKET=$INPUT_LANGUAGES_V3_RUNTIME_DIR/fcitx.sock
}

input_languages_v3_exact_keys() {
	local file=$1 expression=$2
	jq -e "$expression" "$file" >/dev/null 2>&1
}

input_languages_v3_semantics_valid() {
	jq -e '
		def exact($keys): (keys | sort) == ($keys | sort);
		def item: exact(["method","layout_override","display_name","native_name","language_code","addon","configurable","variant","properties"]) and
			([.method,.display_name,.native_name,.language_code,.addon] | all(type == "string" and length > 0)) and
			(.layout_override == null or (.layout_override | type == "string")) and (.configurable | type == "boolean") and
			(.variant == null or (.variant | type == "string")) and (.properties | type == "object");
		def group: exact(["name","default_layout","default_im","properties","items"]) and
			([.name,.default_layout] | all(type == "string" and length > 0)) and (.default_im == null or (.default_im | type == "string")) and
			(.properties | type == "object") and (.items | type == "array" and all(.[]; item));
		def addon: exact(["name","enabled","available"]) and (.name | type == "string" and length > 0) and
			(.enabled | type == "boolean") and (.available | type == "boolean");
		def service: exact(["unit","fragment_path","fragment_digest","active_state","sub_state","main_pid","unique_owner"]) and
			([.unit,.fragment_path,.fragment_digest,.active_state,.sub_state,.unique_owner] | all(type == "string" and length > 0)) and
			(.fragment_path | startswith("/")) and (.fragment_digest | test("^[0-9a-f]{64}$")) and (.main_pid | type == "number" and . >= 0 and floor == .);
		exact(["profile_evidence","owner","owner_epoch","service","groups","current_group","observed_method","observed_method_nonempty","available_methods","addons"]) and
		(.profile_evidence | exact(["path","type","uid","mode","digest"]) and (.path | startswith("/"))) and
		.profile_evidence.type == "regular" and .profile_evidence.mode == "0600" and
		(.profile_evidence.uid | type == "number" and . >= 0 and floor == .) and (.profile_evidence.digest | test("^[0-9a-f]{64}$")) and
		(.owner | type == "string" and length > 0) and (.owner_epoch | type == "number" and . >= 0 and floor == .) and
		(.service | service) and (.groups | type == "array" and length > 0 and all(.[]; group)) and
		(.current_group | type == "string" and length > 0) and (.observed_method == null or (.observed_method | type == "string")) and
		(.observed_method_nonempty == (.observed_method != null and .observed_method != "")) and
		(.available_methods | type == "array" and all(.[]; type == "string" and length > 0)) and
		(.addons | type == "array" and all(.[]; addon))
	' <<<"$1" >/dev/null 2>&1
}

input_languages_v3_hyprland_ownership_valid() {
	jq -e '
		(keys | sort) == (["tree_state","source_id","active_artifact_pointer","autoreload","canonical_language","physical_groups"] | sort) and
		(.tree_state | type == "string" and length > 0) and (.source_id | test("^[0-9a-f]{64}$")) and
		(.active_artifact_pointer | type == "string" and startswith("/")) and (.autoreload | type == "boolean") and
		(.canonical_language | IN("US","Russian")) and
		(.physical_groups | type == "array" and all(.[];
			(keys | sort) == (["device","group"] | sort) and (.device | type == "string" and length > 0) and
			(.group | type == "number" and . >= 0 and floor == .)))
	' <<<"$1" >/dev/null 2>&1
}

input_languages_v3_widget_ownership_valid() {
	jq -e '
		(keys | sort) == (["source","source_digest","live_link","section","index","entry","prior_stock_present","prior_stock_section","prior_stock_index","prior_stock_entry"] | sort) and
		([.source,.live_link] | all(type == "string" and startswith("/"))) and (.source_digest | test("^[0-9a-f]{64}$")) and
		(.section | type == "string" and length > 0) and (.index | type == "number" and . >= 0 and floor == .) and
		(.entry | type == "object") and (.prior_stock_present | type == "boolean") and
		(.prior_stock_section == null or (.prior_stock_section | type == "string")) and
		(.prior_stock_index == null or (.prior_stock_index | type == "number" and . >= 0 and floor == .)) and
		(.prior_stock_entry == null or (.prior_stock_entry | type == "object"))
	' <<<"$1" >/dev/null 2>&1
}

input_languages_v3_expected_states_valid() {
	local operation=$1 states=$2 phases
	phases=$(input_languages_v3_expected_states "$operation" | jq -c '[.[].phase]') || return 1
	jq -e --argjson phases "$phases" '
		[.[].phase] == $phases and all(.[];
			(keys | sort) == (["phase","direct_digest","fcitx_semantic_digest","helper_digest","receipt_digest"] | sort) and
			all([.direct_digest,.fcitx_semantic_digest,.helper_digest,.receipt_digest][]; . == null or test("^[0-9a-f]{64}$")))
	' <<<"$states" >/dev/null 2>&1
}

input_languages_v3_managed_group_valid() {
	jq -e '
		(keys | sort) == (["name","default_layout","default_im","items"] | sort) and
		.name == "Dotfiles Input Languages" and .default_layout == "us" and
		(.default_im == "" or .default_im == "keyboard-us" or .default_im == "keyboard-ru") and
		.items == [{method:"keyboard-us",layout_override:""},{method:"keyboard-ru",layout_override:""}]
	' <<<"$1" >/dev/null 2>&1
}

input_languages_v3_helper_ownership_valid() {
	jq -e '
		def edge: (keys | sort) == (["path","type","target","digest","enabled","active"] | sort) and
			(.path | type == "string" and startswith("/")) and (.type | IN("absent","symlink","regular","directory","socket")) and
			(.target == null or (.target | type == "string" and startswith("/"))) and
			(.digest == null or (.digest | test("^[0-9a-f]{64}$"))) and (.enabled | type == "boolean") and (.active | type == "boolean");
		(keys | sort) == (["socket_unit","service_unit","socket_enablement","artifact_pointer","runtime_directory","socket_path"] | sort) and all(.[]; edge)
	' <<<"$1" >/dev/null 2>&1
}

input_languages_v3_helper_ownership_bound() {
	local ownership=$1 artifact=$2 root
	input_languages_v3_set_paths
	root=${artifact%/*}
	jq -e --arg socket_unit "$INPUT_LANGUAGES_V3_SOCKET_PATH" --arg socket_target "$root/systemd/$INPUT_LANGUAGES_V3_SOCKET_UNIT" \
		--arg service_unit "$INPUT_LANGUAGES_V3_SERVICE_PATH" --arg service_target "$root/systemd/$INPUT_LANGUAGES_V3_SERVICE_UNIT" \
		--arg enablement "$INPUT_LANGUAGES_V3_ENABLEMENT" --arg enablement_target "$INPUT_LANGUAGES_V3_SOCKET_PATH" \
		--arg pointer "$INPUT_LANGUAGES_POINTER" --arg artifact "$artifact" --arg runtime "$INPUT_LANGUAGES_V3_RUNTIME_DIR" --arg socket "$INPUT_LANGUAGES_V3_RUNTIME_SOCKET" '
		.socket_unit.path == $socket_unit and (.socket_unit.target == null or .socket_unit.target == $socket_target) and
		.service_unit.path == $service_unit and (.service_unit.target == null or .service_unit.target == $service_target) and
		.socket_enablement.path == $enablement and (.socket_enablement.target == null or .socket_enablement.target == $enablement_target) and
		.artifact_pointer.path == $pointer and (.artifact_pointer.target == null or .artifact_pointer.target == $artifact) and
		.runtime_directory.path == $runtime and .runtime_directory.target == null and
		.socket_path.path == $socket and .socket_path.target == null
	' <<<"$ownership" >/dev/null 2>&1
}

input_languages_v3_common_receipt_valid() {
	local file=$1 direct artifact fcitx operation_start restoration artifact_root recorded_artifact
	direct=$(jq -c .direct_ancestry "$file") || return 1
	artifact=$(jq -c .integration_artifact "$file") || return 1
	fcitx=$(jq -c .fcitx_before "$file") || return 1
	operation_start=$(jq -c .operation_start "$file") || return 1
	restoration=$(jq -c .restoration "$file") || return 1
	jq -e '
		(keys | sort) == (["receipt","receipt_digest","backup_transaction_id","backup","backup_digest","backup_existed"] | sort) and
		([.receipt,.backup] | all(type == "string" and startswith("/"))) and
		([.receipt_digest,.backup_digest] | all(test("^[0-9a-f]{64}$"))) and
		(.backup_transaction_id | type == "string" and length > 0) and (.backup_existed | type == "boolean")
	' <<<"$direct" >/dev/null || return 1
	jq -e '
		(keys | sort) == (["source_id","build_id","artifact","artifact_sha256","helper_sha256","widget_sha256","protocol_identity","controller_identity","health_identity","unit_identity","compatibility_hash","compiler","compiler_warning","dependencies","inventory"] | sort) and
		([.source_id,.build_id,.artifact_sha256,.helper_sha256,.widget_sha256] | all(test("^[0-9a-f]{64}$"))) and
		(.artifact | startswith("/")) and ([.protocol_identity,.controller_identity,.health_identity,.unit_identity,.compatibility_hash,.compiler,.dependencies] | all(type == "string" and length > 0)) and
		(.compiler_warning == null or (.compiler_warning | type == "string")) and (.inventory | type == "array" and all(.[]; type == "string"))
	' <<<"$artifact" >/dev/null || return 1
	artifact_root=$(jq -r .artifact <<<"$artifact"); artifact_root=${artifact_root%/*}
	recorded_artifact=$(input_languages_v3_integration_artifact "$artifact_root") || return 1
	[[ $(jq -cS . <<<"$artifact") == "$(jq -cS . <<<"$recorded_artifact")" ]] || return 1
	input_languages_v3_semantics_valid "$fcitx" || return 1
	jq -e '
		(keys | sort) == (["canonical_language","physical_groups","fcitx_method"] | sort) and
		(.canonical_language | IN("US","Russian")) and (.physical_groups | type == "array" and all(.[]; (keys | sort) == (["device","group"] | sort) and (.device | type == "string" and length > 0) and (.group == 0 or .group == 1))) and
		(.fcitx_method == null or (.fcitx_method | type == "string"))
	' <<<"$operation_start" >/dev/null || return 1
	jq -e --arg direct "$INPUT_LANGUAGES_V3_RESTORE_DIRECT" --arg fcitx "$INPUT_LANGUAGES_V3_RESTORE_FCITX" \
		--arg helper "$INPUT_LANGUAGES_V3_RESTORE_HELPER" --arg language "$INPUT_LANGUAGES_V3_RESTORE_LANGUAGE" '
		(keys | sort) == (["direct","fcitx","helper","language"] | sort) and
		. == {direct:$direct,fcitx:$fcitx,helper:$helper,language:$language}
	' <<<"$restoration" >/dev/null || return 1
	local receipt receipt_digest backup backup_transaction backup_digest backup_existed actual
	receipt=$(jq -r .receipt <<<"$direct")
	receipt_digest=$(jq -r .receipt_digest <<<"$direct")
	backup=$(jq -r .backup <<<"$direct")
	backup_transaction=$(jq -r .backup_transaction_id <<<"$direct")
	backup_digest=$(jq -r .backup_digest <<<"$direct")
	backup_existed=$(jq -r .backup_existed <<<"$direct")
	input_languages_file_metadata_safe "$receipt" 600 || return 1
	input_languages_validate_active_evidence_file_v2 "$receipt" || return 1
	actual=$(sha256sum "$receipt") || return 1
	[[ ${actual%% *} == "$receipt_digest" ]] || return 1
	input_languages_backup_valid "$backup" "$backup_transaction" "$backup_existed" "$backup_digest"
}

input_languages_validate_active_file_v3() {
	local file=$1 mode=${2-artifact} artifact widget_source widget_digest
	input_languages_file_metadata_safe "$file" 600 || return 1
	input_languages_v3_exact_keys "$file" '
		(keys | sort) == (["version","operation","transaction_id","direct_ancestry","integration_artifact","fcitx_before","managed_group","helper_ownership","hyprland_ownership","widget_ownership","operation_start","restoration"] | sort) and
		.version == 3 and .operation == "active" and (.transaction_id | type == "string" and length > 0) and
		(.hyprland_ownership | (keys | sort) == (["tree_state","source_id","active_artifact_pointer","autoreload","canonical_language","physical_groups"] | sort)) and
		(.widget_ownership | (keys | sort) == (["source","source_digest","live_link","section","index","entry","prior_stock_present","prior_stock_section","prior_stock_index","prior_stock_entry"] | sort))
	' || return 1
	input_languages_v3_common_receipt_valid "$file" || return 1
	input_languages_v3_managed_group_valid "$(jq -c .managed_group "$file")" || return 1
	input_languages_v3_helper_ownership_valid "$(jq -c .helper_ownership "$file")" || return 1
	artifact=$(jq -r .integration_artifact.artifact "$file")
	input_languages_v3_helper_ownership_bound "$(jq -c .helper_ownership "$file")" "$artifact" || return 1
	input_languages_v3_hyprland_ownership_valid "$(jq -c .hyprland_ownership "$file")" || return 1
	input_languages_v3_widget_ownership_valid "$(jq -c .widget_ownership "$file")" || return 1
	[[ $artifact == */input-languages.so ]] || return 1
	if [[ $mode == artifact ]]; then input_languages_validate_integration_artifact_self "${artifact%/*}" || return 1; fi
	widget_source=$(jq -r .widget_ownership.source "$file")
	widget_digest=$(jq -r .widget_ownership.source_digest "$file")
	[[ $widget_source == "${artifact%/*}/$INPUT_LANGUAGES_WIDGET" && $widget_digest == "$(jq -r .integration_artifact.widget_sha256 "$file")" ]]
}

input_languages_validate_pending_file_v3() {
	local file=$1 operation phase prior prior_digest actual artifact
	input_languages_file_metadata_safe "$file" 600 || return 1
	input_languages_v3_exact_keys "$file" '
		(keys | sort) == (["version","operation","transaction_id","phase","prior_active","prior_active_digest","direct_ancestry","integration_artifact","fcitx_before","managed_group_before","managed_group_target","helper_before","helper_target","hyprland_before","widget_before","operation_start","expected_states","restoration"] | sort) and
		.version == 3 and (.operation | IN("apply","remove")) and (.transaction_id | type == "string" and length > 0) and
		(.prior_active | type == "string" and startswith("/")) and (.prior_active_digest | test("^[0-9a-f]{64}$")) and
		(.expected_states | type == "array" and length > 0 and all(.[]; (keys | sort) == (["phase","direct_digest","fcitx_semantic_digest","helper_digest","receipt_digest"] | sort)))
	' || return 1
	input_languages_v3_common_receipt_valid "$file" || return 1
	artifact=$(jq -r .integration_artifact.artifact "$file")
	input_languages_validate_integration_artifact_self "${artifact%/*}" || return 1
	input_languages_v3_semantics_valid "$(jq -c .fcitx_before "$file")" || return 1
	operation=$(jq -r .operation "$file")
	if [[ $operation == apply ]]; then
		[[ $(jq -r .managed_group_before "$file") == null ]] || return 1
		input_languages_v3_managed_group_valid "$(jq -c .managed_group_target "$file")" || return 1
	else
		input_languages_v3_managed_group_valid "$(jq -c .managed_group_before "$file")" || return 1
		[[ $(jq -r .managed_group_target "$file") == null ]] || return 1
	fi
	input_languages_v3_helper_ownership_valid "$(jq -c .helper_before "$file")" || return 1
	input_languages_v3_helper_ownership_valid "$(jq -c .helper_target "$file")" || return 1
	input_languages_v3_helper_ownership_bound "$(jq -c .helper_before "$file")" "$artifact" || return 1
	input_languages_v3_helper_ownership_bound "$(jq -c .helper_target "$file")" "$artifact" || return 1
	input_languages_v3_hyprland_ownership_valid "$(jq -c .hyprland_before "$file")" || return 1
	input_languages_v3_widget_ownership_valid "$(jq -c .widget_before "$file")" || return 1
	input_languages_v3_expected_states_valid "$operation" "$(jq -c .expected_states "$file")" || return 1
	phase=$(jq -r .phase "$file")
	case $operation:$phase in
		apply:prepared|apply:prior-helper-quiesced|apply:managed-group-created|apply:managed-group-populated|apply:managed-group-selected|apply:managed-group-saved|apply:units-published|apply:manager-reloaded|apply:socket-started|apply:pointer-published|apply:hyprland-transitioned|apply:hyprland-reloaded|apply:helper-ready|apply:reset-issued|apply:verified|apply:active-published) ;;
		remove:prepared|remove:authority-quiesced|remove:prior-group-selected|remove:prior-method-restored|remove:managed-group-removed|remove:managed-group-saved|remove:hyprland-restored|remove:helper-edges-removed|remove:manager-reloaded|remove:verified|remove:active-archived) ;;
		*) return 1 ;;
	esac
	prior=$(jq -r .prior_active "$file")
	prior_digest=$(jq -r .prior_active_digest "$file")
	input_languages_file_metadata_safe "$prior" 600 || return 1
	actual=$(sha256sum "$prior") || return 1
	[[ ${actual%% *} == "$prior_digest" ]] || return 1
	if [[ $operation == apply ]]; then
		[[ $prior == "$(jq -r .direct_ancestry.receipt "$file")" ]] || return 1
		input_languages_validate_active_evidence_file_v2 "$prior"
	else
		input_languages_validate_active_file_v3 "$prior" evidence
	fi
}

input_languages_validate_recovery_file_v3() {
	local file=$1 pending digest actual
	input_languages_file_metadata_safe "$file" 600 || return 1
	input_languages_v3_exact_keys "$file" '
		(keys | sort) == (["version","state","transaction_id","failed_phase","pending","pending_digest","restoration"] | sort) and
		.version == 3 and .state == "recovery-required" and (.transaction_id | type == "string" and length > 0) and
		(.failed_phase | IN("authority-quiesced","direct-restored","fcitx-semantic-delta-reversed","helper-state-restored","operation-start-language-restored","verified")) and
		(.pending | type == "string" and startswith("/")) and
		(.pending_digest | test("^[0-9a-f]{64}$"))
	' || return 1
	pending=$(jq -r .pending "$file")
	digest=$(jq -r .pending_digest "$file")
	[[ $pending == "$INPUT_LANGUAGES_PENDING" ]] || return 1
	input_languages_validate_pending_file_v3 "$pending" || return 1
	jq -e --argjson pending_restoration "$(jq -c .restoration "$pending")" '.restoration == $pending_restoration' "$file" >/dev/null 2>&1 || return 1
	actual=$(sha256sum "$pending") || return 1
	[[ ${actual%% *} == "$digest" ]]
}

input_languages_validate_cleanup_file_v3() {
	local file=$1
	input_languages_file_metadata_safe "$file" 600 || return 1
	input_languages_v3_exact_keys "$file" '
		(keys | sort) == (["version","state","transaction_id","archive","archive_active_digest","archive_pending_digest","integration_cleanup"] | sort) and
		.version == 3 and .state == "remove-cleanup" and (.transaction_id | type == "string" and length > 0) and
		(.archive | type == "string" and startswith("/")) and ([.archive_active_digest,.archive_pending_digest] | all(test("^[0-9a-f]{64}$"))) and
		(.integration_cleanup | (keys | sort) == (["artifact","build_id","artifact_sha256","helper_edges","runtime_edges"] | sort))
	'
}

input_languages_validate_active_evidence_file() {
	local version
	version=$(jq -r '.version // empty' "$1" 2>/dev/null) || return 1
	case $version in 2) input_languages_validate_active_evidence_file_v2 "$1" ;; 3) input_languages_validate_active_file_v3 "$1" evidence ;; *) return 1 ;; esac
}

input_languages_validate_active_file() {
	local version
	version=$(jq -r '.version // empty' "$1" 2>/dev/null) || return 1
	case $version in 2) input_languages_validate_active_file_v2 "$1" ;; 3) input_languages_validate_active_file_v3 "$1" artifact ;; *) return 1 ;; esac
}

input_languages_validate_pending_file() {
	local version
	version=$(jq -r '.version // empty' "$1" 2>/dev/null) || return 1
	case $version in 2) input_languages_validate_pending_file_v2 "$1" ;; 3) input_languages_validate_pending_file_v3 "$1" ;; *) return 1 ;; esac
}

input_languages_validate_recovery_file() {
	local version
	version=$(jq -r '.version // empty' "$1" 2>/dev/null) || return 1
	case $version in 2) input_languages_validate_recovery_file_v2 "$1" ;; 3) input_languages_validate_recovery_file_v3 "$1" ;; *) return 1 ;; esac
}

input_languages_validate_cleanup_file() {
	local version
	version=$(jq -r '.version // empty' "$1" 2>/dev/null) || return 1
	case $version in 2) input_languages_validate_cleanup_file_v2 "$1" ;; 3) input_languages_validate_cleanup_file_v3 "$1" ;; *) return 1 ;; esac
}

input_languages_receipt_widget_source() {
	case $(jq -r .version "$1") in 2) jq -r .widget_source "$1" ;; 3) jq -r .widget_ownership.source "$1" ;; *) return 1 ;; esac
}

input_languages_v3_controller() {
	local helper=$1
	shift
	env -i HOME="$HOME" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR-}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS-}" PATH=/usr/bin:/bin LC_ALL=C "$helper" controller "$@"
}

input_languages_v3_systemctl() {
	local operation=$1 unit=${2-}
	case $operation in
		show)
			local properties load fragment active sub pid status=0
			properties=$(/usr/bin/systemctl --user show "$unit" --property=LoadState,FragmentPath,ActiveState,SubState,MainPID --no-pager 2>/dev/null) || status=$?
			load=$(awk -F= '$1 == "LoadState" {print substr($0,index($0,"=")+1)}' <<<"$properties")
			fragment=$(awk -F= '$1 == "FragmentPath" {print substr($0,index($0,"=")+1)}' <<<"$properties")
			active=$(awk -F= '$1 == "ActiveState" {print substr($0,index($0,"=")+1)}' <<<"$properties")
			sub=$(awk -F= '$1 == "SubState" {print substr($0,index($0,"=")+1)}' <<<"$properties")
			pid=$(awk -F= '$1 == "MainPID" {print $2}' <<<"$properties")
			[[ $status == 0 || $load == not-found ]] || return 1
			[[ -n $load && -n $active && ${pid:-} =~ ^[0-9]+$ ]] || return 1
			jq -cn --arg unit "$unit" --arg load_state "$load" --arg fragment_path "$fragment" --arg active_state "$active" --arg sub_state "$sub" --argjson main_pid "$pid" \
				'{unit:$unit,load_state:$load_state,fragment_path:$fragment_path,active_state:$active_state,sub_state:$sub_state,main_pid:$main_pid}'
			;;
		stop|start) /usr/bin/systemctl --user "$operation" "$unit" ;;
		daemon-reload) /usr/bin/systemctl --user daemon-reload ;;
		*) return 2 ;;
	esac
}

input_languages_v3_service_snapshot() {
	local controller=$1 service fragment digest
	service=$(input_languages_v3_systemctl show omarchy-fcitx5.service) || return 1
	fragment=$(jq -r .fragment_path <<<"$service")
	digest=$(sha256sum "$fragment" 2>/dev/null | cut -d' ' -f1 || true)
	[[ $digest =~ ^[0-9a-f]{64}$ ]] || digest=$(printf unavailable | sha256sum | cut -d' ' -f1)
	jq -cn --argjson service "$service" --arg digest "$digest" --arg owner "$(jq -r .snapshot.identity.unique_owner <<<"$controller")" '
		{unit:$service.unit,fragment_path:$service.fragment_path,fragment_digest:$digest,active_state:$service.active_state,
		sub_state:$service.sub_state,main_pid:$service.main_pid,unique_owner:$owner}'
}

input_languages_v3_fcitx_evidence() {
	local controller=$1 service
	service=$(input_languages_v3_service_snapshot "$controller") || return 1
	jq -cn --argjson result "$controller" --argjson service "$service" '
		$result.snapshot as $s |
		{profile_evidence:{path:$s.profile.path,type:"regular",uid:$s.profile.uid,mode:"0600",digest:$s.profile.digest},
		owner:$s.identity.unique_owner,owner_epoch:$s.identity.owner_epoch,service:$service,groups:$s.groups,current_group:$s.current_group,
		observed_method:$s.observed_method,observed_method_nonempty:($s.observed_method != ""),available_methods:$s.available_methods,addons:$s.addons}'
}

input_languages_v3_edge() {
	local path=$1 enabled=$2 active=$3 type=absent target=null digest=null value
	if [[ -L $path ]]; then
		type=symlink
		value=$(readlink "$path") || return 1
		[[ $value == /* ]] || value=$(readlink -m "${path%/*}/$value")
		target=$(jq -Rn --arg value "$value" '$value')
		if [[ -f $value ]]; then value=$(sha256sum "$value" | cut -d' ' -f1); digest=$(jq -Rn --arg value "$value" '$value'); fi
	elif [[ -f $path ]]; then
		type=regular; value=$(sha256sum "$path" | cut -d' ' -f1); digest=$(jq -Rn --arg value "$value" '$value')
	elif [[ -d $path ]]; then type=directory
	elif [[ -S $path ]]; then type=socket
	elif [[ -e $path ]]; then return 1
	fi
	jq -cn --arg path "$path" --arg type "$type" --argjson target "$target" --argjson digest "$digest" --argjson enabled "$enabled" --argjson active "$active" \
		'{path:$path,type:$type,target:$target,digest:$digest,enabled:$enabled,active:$active}'
}

input_languages_v3_helper_ownership() {
	input_languages_v3_set_paths
	local socket_active=false service_active=false socket service enablement pointer runtime socket_path socket_state service_state
	socket_state=$(input_languages_v3_systemctl show "$INPUT_LANGUAGES_V3_SOCKET_UNIT" 2>/dev/null) || return 1
	service_state=$(input_languages_v3_systemctl show "$INPUT_LANGUAGES_V3_SERVICE_UNIT" 2>/dev/null) || return 1
	[[ $(jq -r .active_state <<<"$socket_state") != active ]] || socket_active=true
	[[ $(jq -r .active_state <<<"$service_state") != active ]] || service_active=true
	socket=$(input_languages_v3_edge "$INPUT_LANGUAGES_V3_SOCKET_PATH" false "$socket_active") || return 1
	service=$(input_languages_v3_edge "$INPUT_LANGUAGES_V3_SERVICE_PATH" false "$service_active") || return 1
	enablement=$(input_languages_v3_edge "$INPUT_LANGUAGES_V3_ENABLEMENT" "$([[ -L $INPUT_LANGUAGES_V3_ENABLEMENT ]] && printf true || printf false)" false) || return 1
	pointer=$(input_languages_v3_edge "$INPUT_LANGUAGES_POINTER" false false) || return 1
	runtime=$(input_languages_v3_edge "$INPUT_LANGUAGES_V3_RUNTIME_DIR" false "$([[ -d $INPUT_LANGUAGES_V3_RUNTIME_DIR ]] && printf true || printf false)") || return 1
	socket_path=$(input_languages_v3_edge "$INPUT_LANGUAGES_V3_RUNTIME_SOCKET" false "$([[ -S $INPUT_LANGUAGES_V3_RUNTIME_SOCKET ]] && printf true || printf false)") || return 1
	jq -cn --argjson socket "$socket" --argjson service "$service" --argjson enablement "$enablement" --argjson pointer "$pointer" --argjson runtime "$runtime" --argjson socket_path "$socket_path" \
		'{socket_unit:$socket,service_unit:$service,socket_enablement:$enablement,artifact_pointer:$pointer,runtime_directory:$runtime,socket_path:$socket_path}'
}

input_languages_v3_target_helper_ownership() {
	input_languages_v3_set_paths
	local root=$1 socket_digest service_digest pointer_digest
	socket_digest=$(sha256sum "$root/systemd/$INPUT_LANGUAGES_V3_SOCKET_UNIT" | cut -d' ' -f1) || return 1
	service_digest=$(sha256sum "$root/systemd/$INPUT_LANGUAGES_V3_SERVICE_UNIT" | cut -d' ' -f1) || return 1
	pointer_digest=$(printf 'return "%s"\n' "$root/input-languages.so" | sha256sum | cut -d' ' -f1)
	jq -cn --arg socket_path "$INPUT_LANGUAGES_V3_SOCKET_PATH" --arg socket_target "$root/systemd/$INPUT_LANGUAGES_V3_SOCKET_UNIT" --arg socket_digest "$socket_digest" \
		--arg service_path "$INPUT_LANGUAGES_V3_SERVICE_PATH" --arg service_target "$root/systemd/$INPUT_LANGUAGES_V3_SERVICE_UNIT" --arg service_digest "$service_digest" \
		--arg enablement "$INPUT_LANGUAGES_V3_ENABLEMENT" --arg enablement_target "$INPUT_LANGUAGES_V3_SOCKET_PATH" --arg pointer "$INPUT_LANGUAGES_POINTER" \
		--arg pointer_digest "$pointer_digest" --arg runtime "$INPUT_LANGUAGES_V3_RUNTIME_DIR" --arg socket "$INPUT_LANGUAGES_V3_RUNTIME_SOCKET" '
		{socket_unit:{path:$socket_path,type:"symlink",target:$socket_target,digest:$socket_digest,enabled:false,active:true},
		service_unit:{path:$service_path,type:"symlink",target:$service_target,digest:$service_digest,enabled:false,active:false},
		socket_enablement:{path:$enablement,type:"symlink",target:$enablement_target,digest:$socket_digest,enabled:true,active:false},
		artifact_pointer:{path:$pointer,type:"regular",target:null,digest:$pointer_digest,enabled:false,active:false},
		runtime_directory:{path:$runtime,type:"directory",target:null,digest:null,enabled:false,active:true},
		socket_path:{path:$socket,type:"socket",target:null,digest:null,enabled:false,active:true}}'
}

input_languages_v3_integration_artifact() {
	local root=$1 metadata
	metadata=$root/build.json
	jq -c '
		{source_id,build_id,artifact:(input_filename | sub("/build.json$"; "/input-languages.so")),artifact_sha256,
		helper_sha256,widget_sha256,protocol_identity,controller_identity,health_identity,unit_identity,compatibility_hash,compiler,
		compiler_warning:null,dependencies,inventory}
	' "$metadata"
}

input_languages_v3_build_inputs_match() {
	local root=$1 metadata source dependencies linker
	metadata=$root/build.json
	input_languages_validate_integration_artifact_self "$root" || return 1
	source=$(input_languages_integration_source_identity) || return 1
	dependencies=$(input_languages_integration_dependency_identity) || return 1
	linker=$(input_languages_linker_identity) || return 1
	input_languages_stack_identity || return 1
	jq -e --arg source "$source" --arg dependencies "$dependencies" --arg linker "$linker" \
		--arg compatibility "$INPUT_LANGUAGES_HEADER_HASH" --arg compiler "$INPUT_LANGUAGES_COMPILER" '
		.source_id == $source and .dependencies == $dependencies and .linker == $linker and
		.compatibility_hash == $compatibility and .compiler == $compiler
	' "$metadata" >/dev/null 2>&1
}

input_languages_v3_apply_plan_matches() {
	local helper=$1 planned_controller=$2 planned_helper=$3 planned_hyprland=$4 current
	input_languages_v3_controller_inspect "$helper" || return 1
	input_languages_v3_controller_supported "$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE" || return 1
	[[ $(jq -cS .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") == "$(jq -cS .snapshot <<<"$planned_controller")" ]] || return 1
	current=$(input_languages_v3_helper_ownership) || return 1
	[[ $(jq -cS . <<<"$current") == "$(jq -cS . <<<"$planned_helper")" ]] || return 1
	current=$(input_languages_v3_hyprland_ownership "$INPUT_LANGUAGES_PLUGIN_HEALTH") || return 1
	[[ $(jq -cS . <<<"$current") == "$(jq -cS . <<<"$planned_hyprland")" ]]
}

input_languages_v3_managed_group() {
	local default_im=${1-}
	jq -cn --arg default_im "$default_im" '{name:"Dotfiles Input Languages",default_layout:"us",default_im:$default_im,items:[{method:"keyboard-us",layout_override:""},{method:"keyboard-ru",layout_override:""}]}'
}

input_languages_v3_hyprland_ownership() {
	local health=$1 language groups source pointer autoreload
	language=$(jq -r 'if .canonical_group == 0 then "US" else "Russian" end' <<<"$health")
	groups=$(jq -c '[.physical_keyboards[] as $device | {device:$device,group:.canonical_group}]' <<<"$health") || return 1
	source=$(jq -r '.source_id // empty' <<<"$health")
	pointer=$(cut -d'"' -f2 "$INPUT_LANGUAGES_POINTER" 2>/dev/null || true)
	autoreload=$(input_languages_current_autoreload) || return 1
	jq -cn --arg tree "$INPUT_LANGUAGES_TREE_STATE" --arg source "$source" --arg pointer "$pointer" --argjson autoreload "$autoreload" --arg language "$language" --argjson groups "$groups" \
		'{tree_state:$tree,source_id:$source,active_artifact_pointer:$pointer,autoreload:$autoreload,canonical_language:$language,physical_groups:$groups}'
}

input_languages_v3_widget_ownership() {
	local source=$1 digest=$2 prior=$3
	jq -cn --arg source "$source" --arg digest "$digest" --arg live "$INPUT_LANGUAGES_WIDGET_LIVE" --arg section "$INPUT_LANGUAGES_WIDGET_SECTION" \
		--argjson index "${INPUT_LANGUAGES_WIDGET_INDEX:-0}" --argjson entry "$INPUT_LANGUAGES_WIDGET_ENTRY" --argjson prior "$prior" '
		{source:$source,source_digest:$digest,live_link:$live,section:$section,index:$index,entry:$entry,
		prior_stock_present:$prior.prior_stock_present,prior_stock_section:$prior.prior_stock_section,prior_stock_index:$prior.prior_stock_index,prior_stock_entry:$prior.prior_stock_entry}'
}

input_languages_v3_restoration() {
	jq -cn --arg direct "$INPUT_LANGUAGES_V3_RESTORE_DIRECT" --arg fcitx "$INPUT_LANGUAGES_V3_RESTORE_FCITX" --arg helper "$INPUT_LANGUAGES_V3_RESTORE_HELPER" --arg language "$INPUT_LANGUAGES_V3_RESTORE_LANGUAGE" \
		'{direct:$direct,fcitx:$fcitx,helper:$helper,language:$language}'
}

input_languages_v3_expected_states() {
	local operation=$1 phases phase first=true
	if [[ $operation == apply ]]; then
		phases='prepared prior-helper-quiesced managed-group-created managed-group-populated managed-group-selected managed-group-saved units-published manager-reloaded socket-started pointer-published hyprland-transitioned hyprland-reloaded helper-ready reset-issued verified active-published'
	else
		phases='prepared authority-quiesced prior-group-selected prior-method-restored managed-group-removed managed-group-saved hyprland-restored helper-edges-removed manager-reloaded verified active-archived'
	fi
	printf '['
	for phase in $phases; do
		[[ $first == true ]] || printf ','
		first=false
		jq -cn --arg phase "$phase" '{phase:$phase,direct_digest:null,fcitx_semantic_digest:null,helper_digest:null,receipt_digest:null}'
	done
	printf ']\n'
}

input_languages_v3_state_digest() {
	printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

input_languages_v3_json_digest() {
	jq -cS . <<<"$1" | sha256sum | cut -d' ' -f1
}

input_languages_v3_fcitx_phase_digest() {
	local snapshot=$1 before projection
	before=$(jq -c .fcitx_before "$INPUT_LANGUAGES_PENDING") || return 1
	projection=$(jq -c --argjson before "$before" --arg managed "$INPUT_LANGUAGES_V3_MANAGED_GROUP" '
		.groups = [.groups[] | select(.name == $managed or .name as $name | any($before.groups[]; .name == $name))]
	' <<<"$snapshot") || return 1
	input_languages_v3_json_digest "$projection"
}

input_languages_v3_update_pending() {
	local phase=$1 fcitx=${2-null} fcitx_digest=null helper direct receipt content
	direct=$(input_languages_v3_state_digest "$(input_languages_tree_digest "$INPUT_LANGUAGES_LIVE" 2>/dev/null || printf absent)|$(sha256sum "$INPUT_LANGUAGES_POINTER" 2>/dev/null || true)")
	helper=$(input_languages_v3_json_digest "$(input_languages_v3_helper_ownership)") || return 1
	if [[ $fcitx != null ]]; then
		fcitx_digest=$(input_languages_v3_fcitx_phase_digest "$fcitx") || return 1
	elif [[ $(jq -r .operation "$INPUT_LANGUAGES_PENDING") == remove || $phase =~ ^(prior-helper-quiesced|managed-group-created|managed-group-populated|managed-group-selected|managed-group-saved|units-published|manager-reloaded)$ ]]; then
		fcitx_digest=$(jq -r '[.expected_states[].fcitx_semantic_digest | select(. != null)] | last // "null"' "$INPUT_LANGUAGES_PENDING") || return 1
	fi
	receipt=null
	if [[ -f $INPUT_LANGUAGES_ACTIVE ]]; then receipt=$(sha256sum "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1); fi
	content=$(jq -c --arg phase "$phase" --arg direct "$direct" --arg helper "$helper" --arg fcitx_digest "$fcitx_digest" --arg receipt "$receipt" '
		.phase=$phase | .expected_states |= map(if .phase == $phase then .direct_digest=$direct | .helper_digest=$helper |
			.fcitx_semantic_digest=(if $fcitx_digest == "null" then null else $fcitx_digest end) | .receipt_digest=(if $receipt == "null" then null else $receipt end) else . end)
	' "$INPUT_LANGUAGES_PENDING") || return 1
	input_languages_write_json_atomic "$INPUT_LANGUAGES_PENDING" "$content" pending
}

input_languages_v3_controller_inspect() {
	local helper=$1 response operation=inspect
	[[ ${INPUT_LANGUAGES_V3_RESTORATION_MODE-false} != true ]] || operation=restore-inspect
	response=$(input_languages_v3_controller "$helper" "$operation") || return 1
	jq -e '(.outcome | IN("pending","converged","idle-no-context","drift")) and (.snapshot_digest | test("^[0-9a-f]{64}$")) and (.snapshot | type == "object")' <<<"$response" >/dev/null || return 1
	INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE=$response
}

input_languages_v3_controller_supported() {
	jq -e '
		. as $response |
		.snapshot.identity.supervised == true and .snapshot.identity.upstream_version == "5.1.21" and
		.snapshot.identity.controller_shape == "supported" and .snapshot.profile.safe == true and
		.snapshot.profile.mode == 384 and (.snapshot.profile.uid | type == "number" and . >= 0 and floor == .) and
		(["keyboard-us","keyboard-ru"] - .snapshot.available_methods | length == 0) and
		all(["keyboard","dbus","dbusfrontend"][]; . as $required |
			any($response.snapshot.addons[]; .name == $required and .enabled == true and .available == true))
	' <<<"$1" >/dev/null 2>&1
}

input_languages_v3_controller_restoration_supported() {
	jq -e '
		.snapshot as $snapshot |
		$snapshot.identity.supervised == true and $snapshot.identity.controller_shape == "supported" and
		$snapshot.profile.safe == true and $snapshot.profile.mode == 384 and
		($snapshot.profile.uid | type == "number" and . >= 0 and floor == .) and
		($snapshot.current_group | type == "string" and length > 0) and
		([$snapshot.groups[].name] | length == (unique | length)) and
		any($snapshot.groups[]; .name == $snapshot.current_group)
	' <<<"$1" >/dev/null 2>&1
}

input_languages_v3_observed_managed_group() {
	jq -c --arg name "$INPUT_LANGUAGES_V3_MANAGED_GROUP" '
		[.snapshot.groups[] | select(.name == $name)] |
		if length == 1 then .[0] | {name,default_layout,default_im,items:[.items[] | {method,layout_override}]} else null end
	' <<<"$1"
}

input_languages_v3_managed_group_owned() {
	jq -e --argjson expected "$2" '
		(.default_im | IN("","keyboard-us","keyboard-ru")) and
		(del(.default_im) == ($expected | del(.default_im)))
	' <<<"$1" >/dev/null 2>&1
}

input_languages_exact_noop_v3() {
	[[ $INPUT_LANGUAGES_TREE_STATE == linked && $INPUT_LANGUAGES_ACTIVE_STATE == valid &&
		$INPUT_LANGUAGES_PENDING_STATE == absent && $INPUT_LANGUAGES_RECOVERY_STATE == absent && $INPUT_LANGUAGES_CLEANUP_STATE == absent ]] || return 1
	[[ $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 3 ]] || return 1
	input_languages_validate_active_file_v3 "$INPUT_LANGUAGES_ACTIVE" artifact || return 1
	local artifact_root helper controller managed expected helper_current widget errors source
	artifact_root=$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_ACTIVE"); artifact_root=${artifact_root%/*}
	helper=$artifact_root/input-languages-fcitx-helper
	input_languages_v3_controller_inspect "$helper" || return 1
	controller=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
	input_languages_v3_controller_supported "$controller" || return 1
	managed=$(input_languages_v3_observed_managed_group "$controller") || return 1
	expected=$(jq -c .managed_group "$INPUT_LANGUAGES_ACTIVE") || return 1
	input_languages_v3_managed_group_owned "$managed" "$expected" || return 1
	[[ $(jq -r .snapshot.current_group <<<"$controller") == "$INPUT_LANGUAGES_V3_MANAGED_GROUP" ]] || return 1
	jq -e '.snapshot.observed_method == "" or .snapshot.observed_method == null or (.snapshot.observed_method | IN("keyboard-us","keyboard-ru"))' <<<"$controller" >/dev/null 2>&1 || return 1
	helper_current=$(input_languages_v3_helper_ownership) || return 1
	[[ $(jq -cS . <<<"$helper_current") == "$(jq -cS .helper_ownership "$INPUT_LANGUAGES_ACTIVE")" ]] || return 1
	input_languages_pointer_matches "$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_ACTIVE")" || return 1
	widget=$(jq -c .widget_ownership "$INPUT_LANGUAGES_ACTIVE") || return 1
	input_languages_widget_matches true "$(jq -r .section <<<"$widget")" "$(jq -r .index <<<"$widget")" "$(jq -c .entry <<<"$widget")" || return 1
	input_languages_widget_link_matches "$(jq -r .source <<<"$widget")" || return 1
	[[ $INPUT_LANGUAGES_WIDGET_LINK_STATE == exact && -z $INPUT_LANGUAGES_COMPETING_CLONES ]] || return 1
	input_languages_custom_plugin_discovered || return 1
	jq -e '.indicator_state == "healthy"' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH" >/dev/null 2>&1 || return 1
	source=$(input_languages_integration_source_identity) || return 1
	[[ $source == "$(jq -r .integration_artifact.source_id "$INPUT_LANGUAGES_ACTIVE")" ]] || return 1
	jq -e --arg build "$(jq -r .integration_artifact.build_id "$INPUT_LANGUAGES_ACTIVE")" --arg protocol "$(jq -r .integration_artifact.protocol_identity "$INPUT_LANGUAGES_ACTIVE")" '
		.direct_xkb_health == "healthy" and .helper_connection == "connected" and .helper_build_id == $build and .protocol_identity == $protocol and
		.managed_group_state == "exact" and .report_stale == false and
		((.outcome == "converged" and .acknowledged_generation == .canonical_generation) or (.outcome == "idle-no-context" and .observed_method == ""))
	' <<<"$INPUT_LANGUAGES_PLUGIN_HEALTH" >/dev/null 2>&1 || return 1
	errors=$(hyprctl configerrors 2>/dev/null) || return 1
	[[ -z $errors ]]
}

input_languages_v3_controller_execute() {
	local helper=$1 action=$2 argument=${3-} digest response operation=execute status=0
	[[ ${INPUT_LANGUAGES_V3_RESTORATION_MODE-false} != true ]] || operation=restore-execute
	digest=$(jq -r .snapshot_digest <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") || return 1
	if [[ -n $argument ]]; then response=$(input_languages_v3_controller "$helper" "$operation" "$digest" "$action" "$argument") || status=$?
	else response=$(input_languages_v3_controller "$helper" "$operation" "$digest" "$action") || status=$?; fi
	jq -e '(.outcome | IN("pending","converged","idle-no-context","timeout-indeterminate")) and (.snapshot_digest | test("^[0-9a-f]{64}$"))' <<<"$response" >/dev/null || return 1
	INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE=$response
	if [[ $(jq -r .outcome <<<"$response") == timeout-indeterminate ]]; then INPUT_LANGUAGES_V3_WRITE_INDETERMINATE=true; return 1; fi
	[[ $status == 0 ]]
}

input_languages_v3_publish_link() {
	local path=$1 target=$2 allow_symlink_target=${3-false} temporary
	[[ ! -e $path && ! -L $path && -f $target ]] || return 1
	[[ ! -L $target || $allow_symlink_target == true ]] || return 1
	mkdir -p "${path%/*}" || return 1
	temporary=${path%/*}/.${path##*/}.$$.${RANDOM}
	ln -s "$target" "$temporary" && mv -T "$temporary" "$path" || { rm -f "$temporary"; return 1; }
	[[ -L $path && $(readlink "$path") == "$target" ]]
}

input_languages_v3_publish_helper_edges() {
	local root=$1
	input_languages_v3_set_paths
	input_languages_v3_publish_link "$INPUT_LANGUAGES_V3_SOCKET_PATH" "$root/systemd/$INPUT_LANGUAGES_V3_SOCKET_UNIT" || return 1
	input_languages_v3_publish_link "$INPUT_LANGUAGES_V3_SERVICE_PATH" "$root/systemd/$INPUT_LANGUAGES_V3_SERVICE_UNIT" || return 1
	mkdir -p "$INPUT_LANGUAGES_V3_WANTS_DIR" || return 1
	input_languages_v3_publish_link "$INPUT_LANGUAGES_V3_ENABLEMENT" "$INPUT_LANGUAGES_V3_SOCKET_PATH" true
}

input_languages_v3_remove_helper_edges() {
	input_languages_v3_set_paths
	local path expected=${1-}
	for path in "$INPUT_LANGUAGES_V3_ENABLEMENT" "$INPUT_LANGUAGES_V3_SOCKET_PATH" "$INPUT_LANGUAGES_V3_SERVICE_PATH"; do
		if [[ -n $expected ]]; then
			local key current target digest
			case $path in "$INPUT_LANGUAGES_V3_ENABLEMENT") key=socket_enablement ;; "$INPUT_LANGUAGES_V3_SOCKET_PATH") key=socket_unit ;; *) key=service_unit ;; esac
			current=$(input_languages_v3_edge "$path" "$(jq -r ".$key.enabled" <<<"$expected")" "$(jq -r ".$key.active" <<<"$expected")") || return 1
			target=$(jq -c ".$key" <<<"$expected") || return 1
			[[ $(jq -r .type <<<"$current") == absent || $(jq -cS . <<<"$current") == "$(jq -cS . <<<"$target")" ]] || return 1
		fi
		if [[ -e $path || -L $path ]]; then input_languages_remove_file_verified "$path" || return 1; fi
	done
}

input_languages_v3_quiesce_helper() {
	input_languages_v3_set_paths
	local unit path state load active pid
	for unit in "$INPUT_LANGUAGES_V3_SOCKET_UNIT" "$INPUT_LANGUAGES_V3_SERVICE_UNIT"; do
		case $unit in "$INPUT_LANGUAGES_V3_SOCKET_UNIT") path=$INPUT_LANGUAGES_V3_SOCKET_PATH ;; *) path=$INPUT_LANGUAGES_V3_SERVICE_PATH ;; esac
		state=$(input_languages_v3_systemctl show "$unit" 2>/dev/null) || return 1
		load=$(jq -r '.load_state // "loaded"' <<<"$state")
		active=$(jq -r .active_state <<<"$state")
		pid=$(jq -r .main_pid <<<"$state")
		if [[ $load == not-found ]]; then
			[[ ! -e $path && ! -L $path && $active == inactive && $pid == 0 ]] || return 1
			continue
		fi
		if [[ $active != inactive && $active != failed || $pid != 0 ]]; then
			input_languages_v3_systemctl stop "$unit" >/dev/null 2>&1 || return 1
			state=$(input_languages_v3_systemctl show "$unit" 2>/dev/null) || return 1
			active=$(jq -r .active_state <<<"$state")
			pid=$(jq -r .main_pid <<<"$state")
			[[ ( $active == inactive || $active == failed ) && $pid == 0 ]] || return 1
		fi
	done
}

input_languages_v3_managed_state_reconcilable() {
	local controller=$1 expected=$2 observed
	observed=$(input_languages_v3_observed_managed_group "$controller") || return 1
	[[ $observed == null || $observed == "$expected" ]] && return 0
	jq -e --arg name "$INPUT_LANGUAGES_V3_MANAGED_GROUP" '
		.name == $name and (.default_layout | type == "string" and length > 0) and .default_im == "" and .items == []
	' <<<"$observed" >/dev/null 2>&1
}

input_languages_v3_fcitx_restored() {
	local controller=$1 before=$2
	jq -e --argjson before "$before" --arg name "$INPUT_LANGUAGES_V3_MANAGED_GROUP" '
		. as $result |
		all(.snapshot.groups[]; .name != $name) and
		all($before.groups[]; . as $group | any($result.snapshot.groups[]; . == $group)) and
		([.snapshot.groups[].name] | map(select(. as $candidate | any($before.groups[]; .name == $candidate)))) == [$before.groups[].name] and
		.snapshot.current_group == $before.current_group and
		(if $before.observed_method_nonempty then .snapshot.observed_method == $before.observed_method else true end)
	' <<<"$controller" >/dev/null 2>&1
}

input_languages_v3_remove_anchors_valid() {
	local controller=$1 before=$2
	jq -e --argjson before "$before" --arg name "$INPUT_LANGUAGES_V3_MANAGED_GROUP" '
		.snapshot as $snapshot |
		any($snapshot.groups[]; .name == $before.current_group) and
		(if $before.observed_method_nonempty then
			any($snapshot.groups[]; .name == $before.current_group and any(.items[]; .method == $before.observed_method))
		else true end) and
		([$snapshot.groups[] | select(.name == $name)] | length == 1)
	' <<<"$controller" >/dev/null 2>&1
}

input_languages_v3_remove_fcitx_restored() {
	local controller=$1 remove_start=$2 ancestry=$3
	jq -e --argjson start "$remove_start" --argjson ancestry "$ancestry" --arg name "$INPUT_LANGUAGES_V3_MANAGED_GROUP" '
		.snapshot as $snapshot |
		all($snapshot.groups[]; .name != $name) and
		([$snapshot.groups[] | select(.name != $name)] == [$start.groups[] | select(.name != $name)]) and
		$snapshot.current_group == $ancestry.current_group and
		(if $ancestry.observed_method_nonempty then $snapshot.observed_method == $ancestry.observed_method else true end)
	' <<<"$controller" >/dev/null 2>&1
}

input_languages_v3_absent_helper_ownership() {
	input_languages_v3_set_paths
	jq -cn --arg socket_unit "$INPUT_LANGUAGES_V3_SOCKET_PATH" --arg service_unit "$INPUT_LANGUAGES_V3_SERVICE_PATH" \
		--arg enablement "$INPUT_LANGUAGES_V3_ENABLEMENT" --arg pointer "$INPUT_LANGUAGES_POINTER" \
		--arg runtime "$INPUT_LANGUAGES_V3_RUNTIME_DIR" --arg socket "$INPUT_LANGUAGES_V3_RUNTIME_SOCKET" '
		def absent($path): {path:$path,type:"absent",target:null,digest:null,enabled:false,active:false};
		{socket_unit:absent($socket_unit),service_unit:absent($service_unit),socket_enablement:absent($enablement),
		artifact_pointer:absent($pointer),runtime_directory:absent($runtime),socket_path:absent($socket)}'
}

input_languages_v3_remove_state_exact() {
	local active=$1 controller managed expected helper_current helper_expected artifact health widget language
	input_languages_validate_active_file_v3 "$active" artifact || return 1
	artifact=$(jq -r .integration_artifact.artifact "$active")
	input_languages_pointer_matches "$artifact" || return 1
	input_languages_inspect_tree
	[[ $INPUT_LANGUAGES_TREE_STATE == linked ]] || return 1
	input_languages_widget_matches true "$(jq -r .widget_ownership.section "$active")" "$(jq -r .widget_ownership.index "$active")" "$(jq -c .widget_ownership.entry "$active")" || return 1
	input_languages_widget_link_matches "$(jq -r .widget_ownership.source "$active")" || return 1
	input_languages_custom_plugin_discovered true || return 1
	helper_current=$(input_languages_v3_helper_ownership) || return 1
	helper_expected=$(jq -c .helper_ownership "$active") || return 1
	[[ $(jq -cS . <<<"$helper_current") == "$(jq -cS . <<<"$helper_expected")" ]] || return 1
	input_languages_v3_controller_inspect "${artifact%/*}/input-languages-fcitx-helper" || return 1
	controller=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
	input_languages_v3_controller_restoration_supported "$controller" || return 1
	managed=$(input_languages_v3_observed_managed_group "$controller") || return 1
	expected=$(jq -c .managed_group "$active") || return 1
	input_languages_v3_managed_group_owned "$managed" "$expected" || return 1
	[[ $(jq -r .snapshot.current_group <<<"$controller") == "$INPUT_LANGUAGES_V3_MANAGED_GROUP" ]] || return 1
	input_languages_v3_remove_anchors_valid "$controller" "$(jq -c .fcitx_before "$active")" || return 1
	health=$INPUT_LANGUAGES_PLUGIN_HEALTH
	language=$(jq -r .hyprland_ownership.canonical_language "$active")
	jq -e --arg build "$(jq -r .integration_artifact.build_id "$active")" --arg source "$(jq -r .integration_artifact.source_id "$active")" \
		--arg compatibility "$(jq -r .integration_artifact.compatibility_hash "$active")" --arg language "$language" '
		.build_id == $build and .source_id == $source and .compatibility_hash == $compatibility and
		.direct_xkb_health == "healthy" and .indicator_state == "healthy" and
		((.canonical_group == 0 and $language == "US") or (.canonical_group == 1 and $language == "Russian"))
	' <<<"$health" >/dev/null 2>&1
}

input_languages_v3_verify_apply_rollback() {
	local prior=$1 response helper_before helper_current helper
	helper=$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_PENDING"); helper=${helper%/*}/input-languages-fcitx-helper
	input_languages_v3_controller_inspect "$helper" || return 1
	response=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
	input_languages_v3_fcitx_restored "$response" "$(jq -c .fcitx_before "$INPUT_LANGUAGES_PENDING")" || return 1
	helper_before=$(jq -c .helper_before "$INPUT_LANGUAGES_PENDING") || return 1
	helper_current=$(input_languages_v3_helper_ownership) || return 1
	[[ $(jq -cS . <<<"$helper_current") == "$(jq -cS . <<<"$helper_before")" ]] || return 1
	cmp -s "$prior" "$INPUT_LANGUAGES_ACTIVE" || return 1
	input_languages_validate_active_file_v2 "$INPUT_LANGUAGES_ACTIVE" || return 1
	input_languages_inspect_tree
	[[ $INPUT_LANGUAGES_TREE_STATE == linked ]] || return 1
	input_languages_pointer_matches "$(jq -r .artifact "$prior")" || return 1
	input_languages_widget_link_matches "$(jq -r .widget_source "$prior")" || return 1
	[[ $(jq -r .canonical_group <<<"$(hyprctl -j inputlanguages)") == "$([[ $(jq -r .operation_start.canonical_language "$INPUT_LANGUAGES_PENDING") == US ]] && printf 0 || printf 1)" ]]
}

input_languages_v3_wait_for_health() {
	local mode=$1 build=$2 protocol=$3 attempt health
	for ((attempt = 0; attempt < 40; attempt++)); do
		health=$(hyprctl -j inputlanguages 2>/dev/null || true)
		if jq -e --arg mode "$mode" --arg build "$build" --arg protocol "$protocol" '
			.direct_xkb_health == "healthy" and .helper_connection == "connected" and
			.helper_build_id == $build and .protocol_identity == $protocol and .managed_group_state == "exact" and .report_stale == false and
			(if $mode == "ready" then .accepted_generation == .canonical_generation and (.outcome | IN("converged","pending","idle-no-context"))
			 else (.outcome == "idle-no-context" and .observed_method == "") or
				(.healthy == true and .outcome == "converged" and .acknowledged_generation == .canonical_generation and
				 ((.canonical_group == 0 and .observed_method == "keyboard-us") or (.canonical_group == 1 and .observed_method == "keyboard-ru"))) end)
		' <<<"$health" >/dev/null 2>&1; then INPUT_LANGUAGES_PLUGIN_HEALTH=$health; return 0; fi
		sleep 0.05
	done
	return 1
}

input_languages_v3_publish_active() {
	local transaction=$1 pending=$INPUT_LANGUAGES_PENDING metadata artifact helper fcitx managed helper_ownership health hypr widget prior content
	metadata=$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/build.json
	artifact=$(input_languages_v3_integration_artifact "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR") || return 1
	helper=$INPUT_LANGUAGES_INTEGRATION_HELPER
	input_languages_v3_controller_inspect "$helper" || return 1
	fcitx=$(jq -c .fcitx_before "$pending") || return 1
	managed=$(input_languages_v3_managed_group "$(jq -r '.snapshot.groups[] | select(.name == "Dotfiles Input Languages").default_im' <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")") || return 1
	helper_ownership=$(input_languages_v3_helper_ownership) || return 1
	health=$(hyprctl -j inputlanguages) || return 1
	input_languages_inspect_tree
	hypr=$(input_languages_v3_hyprland_ownership "$health") || return 1
	input_languages_inspect_widget
	prior=$(jq -c '.widget_before | {prior_stock_present,prior_stock_section,prior_stock_index,prior_stock_entry}' "$pending") || return 1
	widget=$(input_languages_v3_widget_ownership "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/$INPUT_LANGUAGES_WIDGET" "$(jq -r .widget_sha256 "$metadata")" "$prior") || return 1
	content=$(jq -cn --arg transaction "$transaction" --argjson direct "$(jq -c .direct_ancestry "$pending")" --argjson artifact "$artifact" \
		--argjson fcitx "$fcitx" --argjson managed "$managed" --argjson helper "$helper_ownership" --argjson hypr "$hypr" --argjson widget "$widget" \
		--argjson operation_start "$(jq -c .operation_start "$pending")" --argjson restoration "$(jq -c .restoration "$pending")" '
		{version:3,operation:"active",transaction_id:$transaction,direct_ancestry:$direct,integration_artifact:$artifact,fcitx_before:$fcitx,
		managed_group:$managed,helper_ownership:$helper,hyprland_ownership:$hypr,widget_ownership:$widget,operation_start:$operation_start,restoration:$restoration}') || return 1
	input_languages_write_json_atomic "$INPUT_LANGUAGES_ACTIVE" "$content" active
}

input_languages_v3_archive_apply_evidence() {
	local transaction=$1 prior=$2 archive_root stage final prior_digest pending_digest
	archive_root=$INPUT_LANGUAGES_STATE/archive
	stage=$archive_root/.apply-$transaction-$$-$RANDOM
	final=$archive_root/$transaction-apply
	[[ ! -e $stage && ! -L $stage && ! -e $final && ! -L $final ]] || return 1
	mkdir -m 0700 "$stage" || return 1
	cp -a "$prior" "$stage/prior-active-v2.json" || return 1
	cp -a "$INPUT_LANGUAGES_PENDING" "$stage/pending.json" || return 1
	chmod 600 "$stage/prior-active-v2.json" "$stage/pending.json" || return 1
	prior_digest=$(sha256sum "$stage/prior-active-v2.json" | cut -d' ' -f1) || return 1
	pending_digest=$(sha256sum "$stage/pending.json" | cut -d' ' -f1) || return 1
	[[ $prior_digest == "$(jq -r .prior_active_digest "$stage/pending.json")" ]] || return 1
	[[ $pending_digest =~ ^[0-9a-f]{64}$ ]] || return 1
	input_languages_validate_active_evidence_file_v2 "$stage/prior-active-v2.json" || return 1
	input_languages_validate_pending_file_v3 "$stage/pending.json" || return 1
	mv "$stage" "$final" || return 1
	[[ -d $final && ! -L $final ]]
}

input_languages_apply_v3() {
	local INPUT_LANGUAGES_V3_WRITE_INDETERMINATE=false
	local approved=false packages_prepared=false expect_noop=false option transaction transaction_root prior_receipt prior_digest direct artifact controller fcitx_before active_digest
	local helper_before helper_target health hypr_before widget_before operation_start expected restoration managed_target pending_content failed='' prior_widget source_changed=true
	for option in "$@"; do case $option in --yes) approved=true ;; --packages-prepared) packages_prepared=true ;; --expect-noop) expect_noop=true ;; --recovery-approved) ;; *) return 2 ;; esac; done
	input_languages_inspect
	[[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 2 && $INPUT_LANGUAGES_TREE_STATE == linked ]] || return 1
	if [[ $expect_noop == true ]]; then
		printf 'Apply blocked: Input Languages changed after its exact no-op was inspected; review a new complete plan.\n' >&2
		return 1
	fi
	input_languages_validate_active_file_v2 "$INPUT_LANGUAGES_ACTIVE" || { printf 'Apply blocked: the direct version-2 ancestry is not exact.\n' >&2; return 1; }
	input_languages_paths_are_safe || return 1
	[[ $INPUT_LANGUAGES_SUPPORTED == true ]] || return 1
	input_languages_static_preflight || return 1
	input_languages_prepare_roots || return 1
	input_languages_stack_identity || return 1
	input_languages_build_integration_artifact || return 1
	input_languages_validate_integration_artifact_self "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" || return 1
	input_languages_v3_controller_inspect "$INPUT_LANGUAGES_INTEGRATION_HELPER" || { printf 'Apply blocked: Fcitx Controller inspection failed.\n' >&2; return 1; }
	controller=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
	input_languages_v3_controller_supported "$controller" || { printf 'Apply blocked: the supervised Fcitx Controller restoration seam is not supported.\n' >&2; return 1; }
	jq -e --arg name "$INPUT_LANGUAGES_V3_MANAGED_GROUP" 'all(.snapshot.groups[]; .name != $name)' <<<"$controller" >/dev/null || { printf 'Apply blocked: the managed Fcitx group name already exists.\n' >&2; return 1; }
	input_languages_v3_set_paths
	for prior_widget in "$INPUT_LANGUAGES_V3_SOCKET_PATH" "$INPUT_LANGUAGES_V3_SERVICE_PATH" "$INPUT_LANGUAGES_V3_ENABLEMENT" "$INPUT_LANGUAGES_V3_RUNTIME_DIR"; do
		[[ ! -e $prior_widget && ! -L $prior_widget ]] || { printf 'Apply blocked: a helper ownership edge already exists: %s\n' "$prior_widget" >&2; return 1; }
	done
	fcitx_before=$(input_languages_v3_fcitx_evidence "$controller") || return 1
	helper_before=$(input_languages_v3_helper_ownership) || return 1
	helper_target=$(input_languages_v3_target_helper_ownership "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR") || return 1
	health=$INPUT_LANGUAGES_PLUGIN_HEALTH
	hypr_before=$(input_languages_v3_hyprland_ownership "$health") || return 1
	prior_widget=$(jq -c '{prior_stock_present,prior_stock_section,prior_stock_index,prior_stock_entry}' "$INPUT_LANGUAGES_ACTIVE")
	widget_before=$(input_languages_v3_widget_ownership "$(jq -r .widget_source "$INPUT_LANGUAGES_ACTIVE")" "$(jq -r .widget_sha256 "$INPUT_LANGUAGES_ACTIVE")" "$prior_widget") || return 1
	operation_start=$(jq -cn --arg language "$(jq -r 'if .canonical_group == 0 then "US" else "Russian" end' <<<"$health")" \
		--argjson groups "$(jq -c '[.physical_keyboards[] as $device | {device:$device,group:.canonical_group}]' <<<"$health")" \
		--arg method "$(jq -r .snapshot.observed_method <<<"$controller")" '{canonical_language:$language,physical_groups:$groups,fcitx_method:$method}')
	managed_target=$(input_languages_v3_managed_group "$([[ $(jq -r .canonical_language <<<"$operation_start") == US ]] && printf keyboard-us || printf keyboard-ru)") || return 1
	restoration=$(input_languages_v3_restoration)
	active_digest=$(sha256sum "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) || return 1
	printf 'Plan: expand the exact version-2 Input Languages installation through one version-3 Fcitx and helper transaction.\n'
	if [[ $approved != true ]] && ! wizard_confirm 'Apply this complete Input Languages expansion plan?'; then printf 'Apply canceled; no changes made.\n'; return 0; fi
	input_languages_acquire_lock Apply || return 1
	input_languages_inspect
	[[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 2 && $INPUT_LANGUAGES_TREE_STATE == linked &&
		$(sha256sum "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) == "$active_digest" ]] || { input_languages_unlock || true; return 1; }
	input_languages_v3_build_inputs_match "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" || { printf 'Apply blocked: integration build inputs changed after confirmation.\n' >&2; input_languages_unlock || true; return 1; }
	input_languages_v3_apply_plan_matches "$INPUT_LANGUAGES_INTEGRATION_HELPER" "$controller" "$helper_before" "$hypr_before" || { printf 'Apply blocked: the confirmed runtime plan changed before pending evidence.\n' >&2; input_languages_unlock || true; return 1; }
	transaction=$(input_languages_new_transaction) || { input_languages_unlock || true; return 1; }
	transaction_root=$INPUT_LANGUAGES_STATE/backups/$transaction
	mkdir -m 0700 "$transaction_root" || { input_languages_unlock || true; return 1; }
	prior_receipt=$transaction_root/prior-active-v2.json
	input_languages_copy_atomic "$INPUT_LANGUAGES_ACTIVE" "$prior_receipt" || { input_languages_unlock || true; return 1; }
	prior_digest=$(sha256sum "$prior_receipt" | cut -d' ' -f1)
	direct=$(jq -cn --arg receipt "$prior_receipt" --arg receipt_digest "$prior_digest" --arg backup_transaction_id "$(jq -r .backup_transaction_id "$prior_receipt")" \
		--arg backup "$(jq -r .backup "$prior_receipt")" --arg backup_digest "$(jq -r .backup_digest "$prior_receipt")" --argjson backup_existed "$(jq -r .backup_existed "$prior_receipt")" \
		'{receipt:$receipt,receipt_digest:$receipt_digest,backup_transaction_id:$backup_transaction_id,backup:$backup,backup_digest:$backup_digest,backup_existed:$backup_existed}')
	artifact=$(input_languages_v3_integration_artifact "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR") || { input_languages_unlock || true; return 1; }
	expected=$(input_languages_v3_expected_states apply)
	pending_content=$(jq -cn --arg transaction "$transaction" --arg prior "$prior_receipt" --arg prior_digest "$prior_digest" --argjson direct "$direct" --argjson artifact "$artifact" \
		--argjson fcitx "$fcitx_before" --argjson managed "$managed_target" --argjson helper_before "$helper_before" --argjson helper_target "$helper_target" \
		--argjson hypr "$hypr_before" --argjson widget "$widget_before" --argjson operation_start "$operation_start" --argjson expected "$expected" --argjson restoration "$restoration" '
		{version:3,operation:"apply",transaction_id:$transaction,phase:"prepared",prior_active:$prior,prior_active_digest:$prior_digest,direct_ancestry:$direct,
		integration_artifact:$artifact,fcitx_before:$fcitx,managed_group_before:null,managed_group_target:$managed,helper_before:$helper_before,
		helper_target:$helper_target,hyprland_before:$hypr,widget_before:$widget,operation_start:$operation_start,expected_states:$expected,restoration:$restoration}') || { input_languages_unlock || true; return 1; }
	input_languages_write_json_atomic "$INPUT_LANGUAGES_PENDING" "$pending_content" pending || { input_languages_unlock || true; return 1; }
	input_languages_v3_update_pending prepared "$(jq -c .snapshot <<<"$controller")" || { input_languages_unlock || true; return 1; }
	input_languages_v3_quiesce_helper || failed=quiesce-helper
	if [[ -z $failed ]]; then input_languages_v3_update_pending prior-helper-quiesced || failed=record-quiesce; fi
	INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE=$controller
	if [[ -z $failed ]]; then input_languages_v3_controller_execute "$INPUT_LANGUAGES_INTEGRATION_HELPER" add-managed || failed=create-group; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending managed-group-created "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-created; fi
	if [[ -z $failed ]]; then input_languages_v3_controller_execute "$INPUT_LANGUAGES_INTEGRATION_HELPER" populate-managed || failed=populate-group; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending managed-group-populated "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-populated; fi
	if [[ -z $failed ]]; then input_languages_v3_controller_execute "$INPUT_LANGUAGES_INTEGRATION_HELPER" switch-group "$INPUT_LANGUAGES_V3_MANAGED_GROUP" || failed=select-group; fi
	if [[ -z $failed && $(jq -r .operation_start.fcitx_method "$INPUT_LANGUAGES_PENDING") != '' ]]; then input_languages_v3_controller_execute "$INPUT_LANGUAGES_INTEGRATION_HELPER" set-method "$(jq -r .managed_group_target.default_im "$INPUT_LANGUAGES_PENDING")" || failed=restore-start-method; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending managed-group-selected "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-selected; fi
	if [[ -z $failed ]]; then input_languages_v3_controller_execute "$INPUT_LANGUAGES_INTEGRATION_HELPER" save || failed=save-group; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending managed-group-saved "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-saved; fi
	if [[ -z $failed ]]; then input_languages_v3_publish_helper_edges "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" || failed=publish-units; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending units-published || failed=record-units; fi
	if [[ -z $failed ]]; then input_languages_v3_systemctl daemon-reload || failed=daemon-reload; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending manager-reloaded || failed=record-manager-reload; fi
	if [[ -z $failed ]]; then input_languages_v3_systemctl start "$INPUT_LANGUAGES_V3_SOCKET_UNIT" || failed=start-socket; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending socket-started || failed=record-socket; fi
	if [[ -z $failed ]]; then input_languages_publish_pointer "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT" || failed=publish-pointer; fi
	if [[ -z $failed ]]; then hyprctl keyword misc:disable_autoreload true >/dev/null || failed=pause-autoreload; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending pointer-published || failed=record-pointer; fi
	prior_widget=$(jq -r .widget_before.source "$INPUT_LANGUAGES_PENDING")
	if [[ -z $failed ]]; then input_languages_publish_widget_link "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/$INPUT_LANGUAGES_WIDGET" "$prior_widget" || failed=publish-widget; fi
	if [[ -z $failed ]]; then input_languages_reload_widget_registry "$source_changed" || failed=reload-shell; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending hyprland-transitioned || failed=record-transition; fi
	if [[ -z $failed ]]; then hyprctl keyword misc:disable_autoreload "$(jq -r .hyprland_before.autoreload "$INPUT_LANGUAGES_PENDING")" >/dev/null || failed=restore-autoreload; fi
	if [[ -z $failed ]]; then hyprctl reload >/dev/null || failed=reload-hyprland; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending hyprland-reloaded || failed=record-reload; fi
	if [[ -z $failed ]]; then input_languages_v3_wait_for_health ready "$INPUT_LANGUAGES_INTEGRATION_BUILD_ID" "$(jq -r .protocol_identity "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/build.json")" || failed=helper-ready; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending helper-ready || failed=record-helper-ready; fi
	if [[ -z $failed ]]; then input_languages_reset_group 0 || failed=reset-us; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending reset-issued || failed=record-reset; fi
	if [[ -z $failed ]]; then input_languages_v3_wait_for_health acknowledged "$INPUT_LANGUAGES_INTEGRATION_BUILD_ID" "$(jq -r .protocol_identity "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/build.json")" || failed=verify-acknowledgement; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending verified || failed=record-verified; fi
	if [[ -z $failed ]]; then input_languages_v3_build_inputs_match "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" || failed=build-input-drift; fi
	if [[ -z $failed ]]; then input_languages_v3_publish_active "$transaction" || failed=publish-active; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending active-published || failed=record-active; fi
	if [[ -z $failed ]]; then input_languages_v3_archive_apply_evidence "$transaction" "$prior_receipt" || failed=archive-pending; fi
	if [[ -z $failed ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING" || failed=remove-pending; fi
	if [[ -n $failed ]]; then
		if [[ -f $INPUT_LANGUAGES_ACTIVE && $(jq -r '.version == 3 and .transaction_id == $transaction' --arg transaction "$transaction" "$INPUT_LANGUAGES_ACTIVE") == true &&
			$(jq -r .phase "$INPUT_LANGUAGES_PENDING") == active-published ]]; then
			printf 'Apply committed but evidence finalization failed at %s; rerun Apply to reconcile it.\n' "$failed" >&2
			input_languages_unlock || true
			return 1
		fi
		if [[ $INPUT_LANGUAGES_V3_WRITE_INDETERMINATE == true ]]; then
			input_languages_record_recovery_v3 "$transaction" verified || true
			printf 'Apply stopped after an indeterminate Controller write at %s; no further write was attempted.\n' "$failed" >&2
			input_languages_unlock || true
			return 1
		fi
		printf 'Apply failed at %s; restoring the verified direct version-2 state.\n' "$failed" >&2
		input_languages_rollback_pending_v3 || true
		input_languages_unlock || true
		return 1
	fi
	input_languages_unlock || return 1
	printf 'Apply completed: Input Languages version 3 is installed with Fcitx delivery.\n'
}

input_languages_v3_remove_runtime_edges() {
	local expected=$1 expected_socket expected_runtime
	input_languages_v3_set_paths
	expected_socket=$(jq -r .socket_path.type <<<"$expected")
	expected_runtime=$(jq -r .runtime_directory.type <<<"$expected")
	if [[ -e $INPUT_LANGUAGES_V3_RUNTIME_SOCKET || -L $INPUT_LANGUAGES_V3_RUNTIME_SOCKET ]]; then
		[[ $expected_socket == socket && -S $INPUT_LANGUAGES_V3_RUNTIME_SOCKET ]] || return 1
		input_languages_remove_file_verified "$INPUT_LANGUAGES_V3_RUNTIME_SOCKET" || return 1
	fi
	if [[ -e $INPUT_LANGUAGES_V3_RUNTIME_DIR || -L $INPUT_LANGUAGES_V3_RUNTIME_DIR ]]; then
		[[ $expected_runtime == directory && -d $INPUT_LANGUAGES_V3_RUNTIME_DIR && ! -L $INPUT_LANGUAGES_V3_RUNTIME_DIR ]] || return 1
		rmdir "$INPUT_LANGUAGES_V3_RUNTIME_DIR" || return 1
	fi
	[[ ! -e $INPUT_LANGUAGES_V3_RUNTIME_SOCKET && ! -L $INPUT_LANGUAGES_V3_RUNTIME_SOCKET && ! -e $INPUT_LANGUAGES_V3_RUNTIME_DIR && ! -L $INPUT_LANGUAGES_V3_RUNTIME_DIR ]]
}

input_languages_v3_restore_original_direct() {
	local active=$1 artifact widget_source prior_present prior_section prior_index prior_entry backup transaction existed digest autoreload
	artifact=$(jq -r .integration_artifact.artifact "$active")
	widget_source=$(jq -r .widget_ownership.source "$active")
	prior_present=$(jq -r .widget_ownership.prior_stock_present "$active")
	prior_section=$(jq -r '.widget_ownership.prior_stock_section // empty' "$active")
	prior_index=$(jq -r '.widget_ownership.prior_stock_index // empty' "$active")
	prior_entry=$(jq -c .widget_ownership.prior_stock_entry "$active")
	backup=$(jq -r .direct_ancestry.backup "$active")
	transaction=$(jq -r .direct_ancestry.backup_transaction_id "$active")
	existed=$(jq -r .direct_ancestry.backup_existed "$active")
	digest=$(jq -r .direct_ancestry.backup_digest "$active")
	autoreload=$(jq -r .hyprland_before.autoreload "$INPUT_LANGUAGES_PENDING")
	hyprctl keyword misc:disable_autoreload true >/dev/null || return 1
	hyprctl plugin unload "$artifact" >/dev/null || return 1
	input_languages_plugin_unloaded || return 1
	input_languages_pointer_matches "$artifact" || return 1
	input_languages_remove_file_verified "$INPUT_LANGUAGES_POINTER" || return 1
	input_languages_restore_stock_widget "$prior_present" "$prior_section" "$prior_index" "$prior_entry" || return 1
	input_languages_remove_widget_link "$widget_source" || return 1
	input_languages_reload_widget_registry false || return 1
	input_languages_wait_for_custom_plugin absent || return 1
	input_languages_unlink_package || return 1
	input_languages_restore_backup "$backup" "$existed" "$digest" "$transaction" || return 1
	hyprctl keyword misc:disable_autoreload "$autoreload" >/dev/null || return 1
	hyprctl reload >/dev/null
}

input_languages_v3_restore_installed_direct() {
	local active=$1 backup transaction existed digest artifact widget_source widget_entry prior_present autoreload
	backup=$(jq -r .direct_ancestry.backup "$active")
	transaction=$(jq -r .direct_ancestry.backup_transaction_id "$active")
	existed=$(jq -r .direct_ancestry.backup_existed "$active")
	digest=$(jq -r .direct_ancestry.backup_digest "$active")
	artifact=$(jq -r .integration_artifact.artifact "$active")
	widget_source=$(jq -r .widget_ownership.source "$active")
	widget_entry=$(jq -c .widget_ownership.entry "$active")
	prior_present=$(jq -r .widget_ownership.prior_stock_present "$active")
	autoreload=$(jq -r .hyprland_before.autoreload "$INPUT_LANGUAGES_PENDING")
	hyprctl keyword misc:disable_autoreload true >/dev/null || return 1
	input_languages_clear_transaction_tree "$backup" "$existed" || return 1
	input_languages_link_package || return 1
	input_languages_publish_pointer "$artifact" || return 1
	if ! input_languages_widget_link_matches "$widget_source"; then
		[[ ! -e $INPUT_LANGUAGES_WIDGET_LIVE && ! -L $INPUT_LANGUAGES_WIDGET_LIVE ]] || return 1
		input_languages_publish_widget_link "$widget_source" || return 1
	fi
	input_languages_reload_widget_registry true || return 1
	if [[ $prior_present == true ]]; then omarchy plugin disable "$INPUT_LANGUAGES_STOCK_WIDGET" >/dev/null || return 1; fi
	if ! input_languages_widget_matches true "$(jq -r .widget_ownership.section "$active")" "$(jq -r .widget_ownership.index "$active")" "$widget_entry"; then
		input_languages_activate_widget "$widget_entry" || return 1
	fi
	hyprctl keyword misc:disable_autoreload "$autoreload" >/dev/null || return 1
	hyprctl reload >/dev/null
}

input_languages_v3_restore_helper_ownership() {
	local expected=$1 artifact_root=$2 current path key actual target published=false
	input_languages_v3_set_paths
	current=$(input_languages_v3_helper_ownership) || return 1
	if [[ $(jq -cS . <<<"$current") != "$(jq -cS . <<<"$expected")" ]]; then
		for path in "$INPUT_LANGUAGES_V3_SOCKET_PATH" "$INPUT_LANGUAGES_V3_SERVICE_PATH" "$INPUT_LANGUAGES_V3_ENABLEMENT"; do
			case $path in "$INPUT_LANGUAGES_V3_SOCKET_PATH") key=socket_unit ;; "$INPUT_LANGUAGES_V3_SERVICE_PATH") key=service_unit ;; *) key=socket_enablement ;; esac
			actual=$(jq -c ".$key" <<<"$current") || return 1
			target=$(jq -c ".$key" <<<"$expected") || return 1
			if [[ $(jq -r .type <<<"$actual") == absent ]]; then
				input_languages_v3_publish_link "$path" "$(jq -r .target <<<"$target")" "$([[ $key == socket_enablement ]] && printf true || printf false)" || return 1
				published=true
			else
				[[ $(jq -cS 'del(.active)' <<<"$actual") == "$(jq -cS 'del(.active)' <<<"$target")" ]] || return 1
			fi
		done
		[[ $published != true ]] || input_languages_v3_systemctl daemon-reload || return 1
		[[ $(jq -r .socket_unit.active <<<"$expected") != true ]] || input_languages_v3_systemctl start "$INPUT_LANGUAGES_V3_SOCKET_UNIT" || return 1
		[[ $(jq -r .service_unit.active <<<"$expected") != true ]] || input_languages_v3_systemctl start "$INPUT_LANGUAGES_V3_SERVICE_UNIT" || return 1
	fi
	current=$(input_languages_v3_helper_ownership) || return 1
	[[ $(jq -cS . <<<"$current") == "$(jq -cS . <<<"$expected")" ]]
}

input_languages_v3_verify_removed() {
	local active=$1 helper=$2 controller expected_helper backup transaction existed digest prior_present prior_section prior_index prior_entry
	input_languages_v3_controller_inspect "$helper" || return 1
	controller=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
	input_languages_v3_remove_fcitx_restored "$controller" "$(jq -c .fcitx_before "$INPUT_LANGUAGES_PENDING")" "$(jq -c .fcitx_before "$active")" || return 1
	expected_helper=$(input_languages_v3_absent_helper_ownership) || return 1
	[[ $(jq -cS . <<<"$(input_languages_v3_helper_ownership)") == "$(jq -cS . <<<"$expected_helper")" ]] || return 1
	backup=$(jq -r .direct_ancestry.backup "$active")
	transaction=$(jq -r .direct_ancestry.backup_transaction_id "$active")
	existed=$(jq -r .direct_ancestry.backup_existed "$active")
	digest=$(jq -r .direct_ancestry.backup_digest "$active")
	input_languages_backup_valid "$backup" "$transaction" "$existed" "$digest" || return 1
	input_languages_inspect_tree
	if [[ $existed == true ]]; then
		[[ $INPUT_LANGUAGES_TREE_STATE == migratable && $(input_languages_tree_digest "$INPUT_LANGUAGES_LIVE") == "$digest" ]] || return 1
	else [[ $INPUT_LANGUAGES_TREE_STATE == uninstalled ]] || return 1; fi
	prior_present=$(jq -r .widget_ownership.prior_stock_present "$active")
	prior_section=$(jq -r '.widget_ownership.prior_stock_section // empty' "$active")
	prior_index=$(jq -r '.widget_ownership.prior_stock_index // empty' "$active")
	prior_entry=$(jq -c .widget_ownership.prior_stock_entry "$active")
	input_languages_stock_widget_matches "$prior_present" "$prior_section" "$prior_index" "$prior_entry" || return 1
	[[ ! -e $INPUT_LANGUAGES_WIDGET_LIVE && ! -L $INPUT_LANGUAGES_WIDGET_LIVE && ! -e $INPUT_LANGUAGES_POINTER && ! -L $INPUT_LANGUAGES_POINTER ]] || return 1
	input_languages_custom_plugin_absent && input_languages_plugin_unloaded
}

input_languages_remove_v3() {
	local INPUT_LANGUAGES_V3_RESTORATION_MODE=true
	local INPUT_LANGUAGES_V3_WRITE_INDETERMINATE=false
	local approved=false recovery_approved=false option active_digest artifact_root helper controller fcitx_start helper_before helper_target health
	local operation_start transaction transaction_root prior_active prior_digest pending_content managed failed='' committed=false
	for option in "$@"; do case $option in --yes) approved=true ;; --recovery-approved) recovery_approved=true ;; *) printf 'Error: unknown Input Languages Remove option: %s\n' "$option" >&2; return 2 ;; esac; done
	input_languages_inspect
	input_languages_paths_are_safe || return 1
	if [[ $INPUT_LANGUAGES_RECOVERY_STATE != absent || $INPUT_LANGUAGES_PENDING_STATE != absent ]]; then
		[[ $INPUT_LANGUAGES_PENDING_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_PENDING") == 3 ]] || { printf 'Remove blocked: version-3 recovery evidence is invalid.\n' >&2; return 1; }
		input_languages_reconcile_pending_v3 "$recovery_approved"
		return
	fi
	[[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 3 ]] || return 1
	input_languages_v3_remove_state_exact "$INPUT_LANGUAGES_ACTIVE" || { printf 'Remove blocked: the version-3 installation or restoration anchors are not exact.\n' >&2; return 1; }
	artifact_root=$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_ACTIVE"); artifact_root=${artifact_root%/*}
	helper=$artifact_root/input-languages-fcitx-helper
	controller=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
	fcitx_start=$(input_languages_v3_fcitx_evidence "$controller") || return 1
	helper_before=$(input_languages_v3_helper_ownership) || return 1
	helper_target=$(input_languages_v3_absent_helper_ownership) || return 1
	health=$INPUT_LANGUAGES_PLUGIN_HEALTH
	operation_start=$(jq -cn --arg language "$(jq -r 'if .canonical_group == 0 then "US" else "Russian" end' <<<"$health")" \
		--argjson groups "$(jq -c '[.physical_keyboards[] as $device | {device:$device,group:.canonical_group}]' <<<"$health")" \
		--arg method "$(jq -r .snapshot.observed_method <<<"$controller")" '{canonical_language:$language,physical_groups:$groups,fcitx_method:$method}')
	active_digest=$(sha256sum "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) || return 1
	printf 'Plan: remove the exact version-3 Input Languages integration, restore its direct-XKB ancestry and prior Fcitx semantics, and retain immutable artifacts.\n'
	if [[ $approved != true ]] && ! wizard_confirm 'Remove this complete Input Languages version-3 plan?'; then printf 'Remove canceled; no changes made.\n'; return 0; fi
	input_languages_prepare_roots || return 1
	input_languages_acquire_lock Remove || return 1
	input_languages_inspect
	[[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(sha256sum "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) == "$active_digest" && $INPUT_LANGUAGES_PENDING_STATE == absent && $INPUT_LANGUAGES_RECOVERY_STATE == absent ]] || { input_languages_unlock || true; return 1; }
	input_languages_v3_remove_state_exact "$INPUT_LANGUAGES_ACTIVE" || { input_languages_unlock || true; return 1; }
	transaction=$(input_languages_new_transaction) || { input_languages_unlock || true; return 1; }
	transaction_root=$INPUT_LANGUAGES_STATE/backups/$transaction
	mkdir -m 0700 "$transaction_root" || { input_languages_unlock || true; return 1; }
	prior_active=$transaction_root/prior-active-v3.json
	input_languages_copy_atomic "$INPUT_LANGUAGES_ACTIVE" "$prior_active" || { input_languages_unlock || true; return 1; }
	prior_digest=$(sha256sum "$prior_active" | cut -d' ' -f1) || { input_languages_unlock || true; return 1; }
	controller=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
	fcitx_start=$(input_languages_v3_fcitx_evidence "$controller") || { input_languages_unlock || true; return 1; }
	managed=$(input_languages_v3_observed_managed_group "$controller") || { input_languages_unlock || true; return 1; }
	helper_before=$(input_languages_v3_helper_ownership) || { input_languages_unlock || true; return 1; }
	pending_content=$(jq -cn --arg transaction "$transaction" --arg prior "$prior_active" --arg prior_digest "$prior_digest" \
		--argjson direct "$(jq -c .direct_ancestry "$prior_active")" --argjson artifact "$(jq -c .integration_artifact "$prior_active")" \
		--argjson fcitx "$fcitx_start" --argjson managed "$managed" --argjson helper_before "$helper_before" \
		--argjson helper_target "$helper_target" --argjson hypr "$(jq -c .hyprland_ownership "$prior_active")" --argjson widget "$(jq -c .widget_ownership "$prior_active")" \
		--argjson operation_start "$operation_start" --argjson expected "$(input_languages_v3_expected_states remove)" --argjson restoration "$(jq -c .restoration "$prior_active")" '
		{version:3,operation:"remove",transaction_id:$transaction,phase:"prepared",prior_active:$prior,prior_active_digest:$prior_digest,direct_ancestry:$direct,
		integration_artifact:$artifact,fcitx_before:$fcitx,managed_group_before:$managed,managed_group_target:null,helper_before:$helper_before,
		helper_target:$helper_target,hyprland_before:$hypr,widget_before:$widget,operation_start:$operation_start,expected_states:$expected,restoration:$restoration}') || { input_languages_unlock || true; return 1; }
	input_languages_write_json_atomic "$INPUT_LANGUAGES_PENDING" "$pending_content" pending || { input_languages_unlock || true; return 1; }
	input_languages_v3_update_pending prepared "$(jq -c .snapshot <<<"$controller")" || { input_languages_unlock || true; return 1; }
	input_languages_v3_quiesce_helper || failed=quiesce-helper
	if [[ -z $failed ]]; then input_languages_v3_update_pending authority-quiesced || failed=record-quiesce; fi
	if [[ -z $failed ]]; then input_languages_v3_controller_inspect "$helper" || failed=inspect-controller; fi
	if [[ -z $failed ]]; then
		controller=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
		input_languages_v3_remove_anchors_valid "$controller" "$(jq -c .fcitx_before "$prior_active")" || failed=restore-anchor
		input_languages_v3_managed_group_owned "$(input_languages_v3_observed_managed_group "$controller")" "$(jq -c .managed_group_before "$INPUT_LANGUAGES_PENDING")" || failed=managed-group
	fi
	if [[ -z $failed && $(jq -r .snapshot.current_group <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") != "$(jq -r .fcitx_before.current_group "$prior_active")" ]]; then
		input_languages_v3_controller_execute "$helper" switch-group "$(jq -r .fcitx_before.current_group "$prior_active")" || failed=restore-group
	fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending prior-group-selected "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-prior-group; fi
	if [[ -z $failed && $(jq -r .fcitx_before.observed_method_nonempty "$prior_active") == true && $(jq -r .snapshot.observed_method <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") != "$(jq -r .fcitx_before.observed_method "$prior_active")" ]]; then
		input_languages_v3_controller_execute "$helper" set-method "$(jq -r .fcitx_before.observed_method "$prior_active")" || failed=restore-method
	fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending prior-method-restored "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-prior-method; fi
	if [[ -z $failed ]]; then input_languages_v3_controller_execute "$helper" remove-managed || failed=remove-managed; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending managed-group-removed "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-removed; fi
	if [[ -z $failed ]]; then input_languages_v3_controller_execute "$helper" save || failed=save-group; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending managed-group-saved "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-save; fi
	if [[ -z $failed ]]; then input_languages_v3_restore_original_direct "$prior_active" || failed=restore-hyprland; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending hyprland-restored || failed=record-hyprland; fi
	if [[ -z $failed ]]; then input_languages_v3_remove_helper_edges "$(jq -c .helper_before "$INPUT_LANGUAGES_PENDING")" || failed=remove-helper-edges; fi
	if [[ -z $failed ]]; then input_languages_v3_remove_runtime_edges "$(jq -c .helper_before "$INPUT_LANGUAGES_PENDING")" || failed=remove-runtime; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending helper-edges-removed || failed=record-helper-edges; fi
	if [[ -z $failed ]]; then input_languages_v3_systemctl daemon-reload || failed=daemon-reload; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending manager-reloaded || failed=record-manager-reload; fi
	if [[ -z $failed ]]; then input_languages_v3_verify_removed "$prior_active" "$helper" || failed=verify-removal; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending verified "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-verified; fi
	if [[ -z $failed ]]; then input_languages_v3_update_pending active-archived "$(jq -c .snapshot <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" || failed=record-archive; fi
	if [[ -z $failed ]]; then input_languages_archive_remove_evidence "$transaction" || failed=archive-evidence; fi
	if [[ -z $failed ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_ACTIVE" || failed=remove-active; fi
	if [[ -z $failed ]]; then committed=true; input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING" || failed=remove-pending; fi
	if [[ -n $failed ]]; then
		if [[ $INPUT_LANGUAGES_V3_WRITE_INDETERMINATE == true ]]; then
			input_languages_record_recovery_v3 "$transaction" verified || true
			printf 'Remove stopped after an indeterminate Controller write at %s; no further write was attempted.\n' "$failed" >&2
			input_languages_unlock || true
			return 1
		fi
		if [[ $committed == true ]]; then
			printf 'Remove committed but final evidence cleanup failed at %s; rerun Remove to reconcile it.\n' "$failed" >&2
		else
			printf 'Remove failed at %s; reconstructing the verified version-3 installation.\n' "$failed" >&2
			input_languages_rollback_pending_v3 || true
		fi
		input_languages_unlock || true
		return 1
	fi
	input_languages_unlock || return 1
	printf 'Remove completed: prior direct-XKB and Fcitx state restored; immutable artifacts, backups, archive, diagnostics, sources, and Arch packages retained.\n'
}

input_languages_record_recovery_v3() {
	local transaction=$1 phase=$2 digest content
	digest=$(sha256sum "$INPUT_LANGUAGES_PENDING" | cut -d' ' -f1) || return 1
	content=$(jq -cn --arg transaction "$transaction" --arg phase "$phase" --arg pending "$INPUT_LANGUAGES_PENDING" --arg digest "$digest" --argjson restoration "$(jq -c .restoration "$INPUT_LANGUAGES_PENDING")" \
		'{version:3,state:"recovery-required",transaction_id:$transaction,failed_phase:$phase,pending:$pending,pending_digest:$digest,restoration:$restoration}') || return 1
	input_languages_write_json_atomic "$INPUT_LANGUAGES_RECOVERY" "$content" recovery
}

input_languages_v3_recovery_phase() {
	case $1 in
		quiesce|inspect-controller) printf 'authority-quiesced\n' ;;
		restore-pointer|restore-widget-link|reload-shell|reload-hyprland|restore-receipt|restore-direct) printf 'direct-restored\n' ;;
		restore-group|restore-method|remove-group|save-restoration|reconstruct-group) printf 'fcitx-semantic-delta-reversed\n' ;;
		remove-helper-edges|restore-helper-state) printf 'helper-state-restored\n' ;;
		restore-language) printf 'operation-start-language-restored\n' ;;
		*) printf 'verified\n' ;;
	esac
}

input_languages_v3_recorded_phase_matches_fcitx() {
	local phase expected actual
	phase=$(jq -r .phase "$INPUT_LANGUAGES_PENDING") || return 1
	expected=$(jq -r --arg phase "$phase" '.expected_states[] | select(.phase == $phase) | .fcitx_semantic_digest // ""' "$INPUT_LANGUAGES_PENDING") || return 1
	[[ -n $expected ]] || return 0
	actual=$(input_languages_v3_fcitx_phase_digest "$(jq -c .snapshot <<<"$1")") || return 1
	[[ $actual == "$expected" ]]
}

input_languages_v3_helper_state_between() {
	local current before=$1 after=$2
	current=$(input_languages_v3_helper_ownership) || return 1
	jq -e --argjson current "$current" --argjson before "$before" --argjson after "$after" '
		all(["socket_unit","service_unit","socket_enablement","artifact_pointer","runtime_directory","socket_path"][]; . as $key |
			($current[$key] | del(.active)) == ($before[$key] | del(.active)) or
			($current[$key] | del(.active)) == ($after[$key] | del(.active)))
	' <<<null >/dev/null 2>&1
}

input_languages_v3_apply_rollback_direct_safe() {
	local prior=$1 current_widget=$2 target_artifact
	target_artifact=$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_PENDING")
	cmp -s "$prior" "$INPUT_LANGUAGES_ACTIVE" || return 1
	input_languages_inspect_tree
	[[ $INPUT_LANGUAGES_TREE_STATE == linked ]] || return 1
	input_languages_widget_matches true "$(jq -r .widget_before.section "$INPUT_LANGUAGES_PENDING")" "$(jq -r .widget_before.index "$INPUT_LANGUAGES_PENDING")" "$(jq -c .widget_before.entry "$INPUT_LANGUAGES_PENDING")" || return 1
	input_languages_pointer_matches "$(jq -r .artifact "$prior")" || input_languages_pointer_matches "$target_artifact" || return 1
	input_languages_widget_link_matches "$(jq -r .widget_source "$prior")" || input_languages_widget_link_matches "$current_widget"
}

input_languages_v3_remove_rollback_direct_safe() {
	local active=$1 artifact backup existed digest
	artifact=$(jq -r .integration_artifact.artifact "$active")
	if [[ -e $INPUT_LANGUAGES_ACTIVE || -L $INPUT_LANGUAGES_ACTIVE ]]; then cmp -s "$active" "$INPUT_LANGUAGES_ACTIVE" || return 1; fi
	if [[ -e $INPUT_LANGUAGES_POINTER || -L $INPUT_LANGUAGES_POINTER ]]; then input_languages_pointer_matches "$artifact" || return 1; fi
	if [[ -e $INPUT_LANGUAGES_WIDGET_LIVE || -L $INPUT_LANGUAGES_WIDGET_LIVE ]]; then input_languages_widget_link_matches "$(jq -r .widget_ownership.source "$active")" || return 1; fi
	input_languages_inspect_tree
	[[ $INPUT_LANGUAGES_TREE_STATE == linked ]] && return 0
	backup=$(jq -r .direct_ancestry.backup "$active")
	existed=$(jq -r .direct_ancestry.backup_existed "$active")
	digest=$(jq -r .direct_ancestry.backup_digest "$active")
	if [[ $existed == true ]]; then [[ $INPUT_LANGUAGES_TREE_STATE == migratable && $(input_languages_tree_digest "$INPUT_LANGUAGES_LIVE") == "$digest" ]]
	else [[ $INPUT_LANGUAGES_TREE_STATE == uninstalled ]]; fi
}

input_languages_rollback_apply_pending_v3() {
	local INPUT_LANGUAGES_V3_RESTORATION_MODE=true
	local transaction helper prior response prior_group prior_method current_widget failed=''
	input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
	transaction=$(jq -r .transaction_id "$INPUT_LANGUAGES_PENDING")
	helper=$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_PENDING"); helper=${helper%/*}/input-languages-fcitx-helper
	input_languages_v3_quiesce_helper || failed=quiesce
	prior=$(jq -r .direct_ancestry.receipt "$INPUT_LANGUAGES_PENDING")
	current_widget=$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_PENDING"); current_widget=${current_widget%/*}/$INPUT_LANGUAGES_WIDGET
	if [[ -z $failed ]]; then input_languages_v3_controller_inspect "$helper" || failed=inspect-controller; fi
	if [[ -z $failed ]]; then
		response=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
		if [[ ! -e $INPUT_LANGUAGES_RECOVERY && ! -L $INPUT_LANGUAGES_RECOVERY ]]; then input_languages_v3_recorded_phase_matches_fcitx "$response" || failed=ambiguous-phase; fi
		if [[ -z $failed ]]; then input_languages_v3_managed_state_reconcilable "$response" "$(jq -c .managed_group_target "$INPUT_LANGUAGES_PENDING")" || failed=foreign-managed-group; fi
		prior_group=$(jq -r .fcitx_before.current_group "$INPUT_LANGUAGES_PENDING")
		prior_method=$(jq -r .fcitx_before.observed_method "$INPUT_LANGUAGES_PENDING")
		if [[ -z $failed ]] && ! jq -e --argjson before "$(jq -c .fcitx_before "$INPUT_LANGUAGES_PENDING")" --arg group "$prior_group" '
			any(.snapshot.groups[]; .name == $group and . == ($before.groups[] | select(.name == $group)))
		' <<<"$response" >/dev/null 2>&1; then failed=restore-anchor; fi
	fi
	if [[ -z $failed ]]; then input_languages_v3_helper_state_between "$(jq -c .helper_before "$INPUT_LANGUAGES_PENDING")" "$(jq -c .helper_target "$INPUT_LANGUAGES_PENDING")" || failed=foreign-helper-state; fi
	if [[ -z $failed ]]; then input_languages_v3_apply_rollback_direct_safe "$prior" "$current_widget" || failed=foreign-direct-state; fi
	if [[ -z $failed ]]; then input_languages_publish_pointer "$(jq -r .artifact "$prior")" || failed=restore-pointer; fi
	if [[ -z $failed ]]; then input_languages_publish_widget_link "$(jq -r .widget_source "$prior")" "$current_widget" || failed=restore-widget-link; fi
	if [[ -z $failed ]]; then input_languages_reload_widget_registry true || failed=reload-shell; fi
	if [[ -z $failed ]]; then hyprctl keyword misc:disable_autoreload "$(jq -r .hyprland_before.autoreload "$INPUT_LANGUAGES_PENDING")" >/dev/null || failed=restore-autoreload; fi
	if [[ -z $failed ]]; then hyprctl reload >/dev/null || failed=reload-hyprland; fi
	if [[ -z $failed ]]; then input_languages_copy_atomic "$prior" "$INPUT_LANGUAGES_ACTIVE" || failed=restore-receipt; fi
	if [[ -z $failed ]]; then
		if jq -e --arg name "$INPUT_LANGUAGES_V3_MANAGED_GROUP" 'any(.snapshot.groups[]; .name == $name)' <<<"$response" >/dev/null; then
			if [[ $(jq -r .snapshot.current_group <<<"$response") != "$prior_group" ]]; then input_languages_v3_controller_execute "$helper" switch-group "$prior_group" || failed=restore-group; fi
			if [[ -z $failed && -n $prior_method ]] && jq -e --arg group "$prior_group" --arg method "$prior_method" 'any(.snapshot.groups[]; .name == $group and any(.items[]; .method == $method))' <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE" >/dev/null; then
				[[ $(jq -r .snapshot.observed_method <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") == "$prior_method" ]] || input_languages_v3_controller_execute "$helper" set-method "$prior_method" || failed=restore-method
			fi
			if [[ -z $failed ]]; then input_languages_v3_controller_execute "$helper" remove-managed || failed=remove-group; fi
			if [[ -z $failed ]]; then input_languages_v3_controller_execute "$helper" save || failed=save-restoration; fi
		fi
	fi
	if [[ -z $failed ]]; then input_languages_v3_remove_helper_edges "$(jq -c .helper_target "$INPUT_LANGUAGES_PENDING")" || failed=remove-helper-edges; fi
	if [[ -z $failed ]]; then input_languages_v3_remove_runtime_edges "$(jq -c .helper_target "$INPUT_LANGUAGES_PENDING")" || failed=remove-helper-edges; fi
	if [[ -z $failed ]]; then input_languages_reset_group "$([[ $(jq -r .operation_start.canonical_language "$INPUT_LANGUAGES_PENDING") == US ]] && printf 0 || printf 1)" || failed=restore-language; fi
	if [[ -z $failed ]]; then input_languages_v3_verify_apply_rollback "$prior" || failed=verify-restoration; fi
	if [[ -z $failed && ( -e $INPUT_LANGUAGES_RECOVERY || -L $INPUT_LANGUAGES_RECOVERY ) ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_RECOVERY" || failed=remove-recovery; fi
	if [[ -z $failed ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING" || failed=remove-pending; fi
	if [[ -z $failed ]]; then return 0; fi
	input_languages_record_recovery_v3 "$transaction" "$(input_languages_v3_recovery_phase "$failed")" || true
	return 1
}

input_languages_v3_remove_rollback_reconcilable() {
	local controller=$1 before=$2 expected=$3
	jq -e --argjson before "$before" --argjson expected "$expected" --arg name "$INPUT_LANGUAGES_V3_MANAGED_GROUP" '
		. as $result |
		([$result.snapshot.groups[] | select(.name == $name)][0] // null) as $managed |
		([$result.snapshot.groups[] | select(.name != $name)] == [$before.groups[] | select(.name != $name)]) and
		([$result.snapshot.groups[] | select(.name == $name)] | length <= 1) and
		($managed == null or
			(({name:$managed.name,default_layout:$managed.default_layout,default_im:$managed.default_im,items:[$managed.items[] | {method,layout_override}]} | del(.default_im)) == ($expected | del(.default_im)) and
			 ($managed.default_im | IN("","keyboard-us","keyboard-ru"))) or
			($managed.name == $name and ($managed.default_layout | type == "string" and length > 0) and $managed.default_im == "" and $managed.items == []))
	' <<<"$controller" >/dev/null 2>&1
}

input_languages_rollback_remove_pending_v3() {
	local INPUT_LANGUAGES_V3_RESTORATION_MODE=true
	local transaction active helper artifact_root controller observed expected start_method failed=''
	input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
	[[ $(jq -r .operation "$INPUT_LANGUAGES_PENDING") == remove ]] || return 1
	transaction=$(jq -r .transaction_id "$INPUT_LANGUAGES_PENDING")
	active=$(jq -r .prior_active "$INPUT_LANGUAGES_PENDING")
	helper=$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_PENDING"); artifact_root=${helper%/*}; helper=$artifact_root/input-languages-fcitx-helper
	expected=$(jq -c .managed_group_before "$INPUT_LANGUAGES_PENDING")
	input_languages_v3_quiesce_helper || failed=quiesce
	if [[ -z $failed ]]; then input_languages_v3_controller_inspect "$helper" || failed=inspect-controller; fi
	if [[ -z $failed ]]; then
		controller=$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE
		if [[ ! -e $INPUT_LANGUAGES_RECOVERY && ! -L $INPUT_LANGUAGES_RECOVERY ]]; then input_languages_v3_recorded_phase_matches_fcitx "$controller" || failed=ambiguous-phase; fi
		if [[ -z $failed ]]; then input_languages_v3_remove_rollback_reconcilable "$controller" "$(jq -c .fcitx_before "$INPUT_LANGUAGES_PENDING")" "$expected" || failed=foreign-managed-group; fi
	fi
	if [[ -z $failed ]]; then input_languages_v3_helper_state_between "$(jq -c .helper_before "$INPUT_LANGUAGES_PENDING")" "$(jq -c .helper_target "$INPUT_LANGUAGES_PENDING")" || failed=foreign-helper-state; fi
	if [[ -z $failed ]]; then input_languages_v3_remove_rollback_direct_safe "$active" || failed=foreign-direct-state; fi
	if [[ -z $failed ]]; then
		observed=$(input_languages_v3_observed_managed_group "$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") || failed=inspect-managed
		if [[ -z $failed && $observed == null ]]; then input_languages_v3_controller_execute "$helper" add-managed || failed=reconstruct-group; fi
		if [[ -z $failed ]]; then
			observed=$(input_languages_v3_observed_managed_group "$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") || failed=inspect-managed
			if ! input_languages_v3_managed_group_owned "$observed" "$expected"; then input_languages_v3_controller_execute "$helper" populate-managed || failed=reconstruct-group; fi
		fi
		if [[ -z $failed ]] && ! input_languages_v3_managed_group_owned "$(input_languages_v3_observed_managed_group "$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE")" "$expected"; then failed=reconstruct-group; fi
	fi
	if [[ -z $failed && $(jq -r .snapshot.current_group <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") != "$INPUT_LANGUAGES_V3_MANAGED_GROUP" ]]; then
		input_languages_v3_controller_execute "$helper" switch-group "$INPUT_LANGUAGES_V3_MANAGED_GROUP" || failed=reconstruct-group
	fi
	start_method=$(jq -r '.operation_start.fcitx_method // empty' "$INPUT_LANGUAGES_PENDING")
	if [[ -z $failed && -n $start_method && $(jq -r .snapshot.observed_method <<<"$INPUT_LANGUAGES_V3_CONTROLLER_RESPONSE") != "$start_method" ]]; then
		input_languages_v3_controller_execute "$helper" set-method "$start_method" || failed=reconstruct-group
	fi
	if [[ -z $failed ]]; then input_languages_v3_controller_execute "$helper" save || failed=reconstruct-group; fi
	if [[ -z $failed ]]; then input_languages_v3_restore_installed_direct "$active" || failed=restore-direct; fi
	if [[ -z $failed ]]; then input_languages_v3_restore_helper_ownership "$(jq -c .helper_before "$INPUT_LANGUAGES_PENDING")" "$artifact_root" || failed=restore-helper-state; fi
	if [[ -z $failed ]]; then input_languages_reset_group "$([[ $(jq -r .operation_start.canonical_language "$INPUT_LANGUAGES_PENDING") == US ]] && printf 0 || printf 1)" || failed=restore-language; fi
	if [[ -z $failed ]]; then
		if [[ ! -e $INPUT_LANGUAGES_ACTIVE && ! -L $INPUT_LANGUAGES_ACTIVE ]]; then input_languages_copy_atomic "$active" "$INPUT_LANGUAGES_ACTIVE" || failed=restore-receipt
		else cmp -s "$active" "$INPUT_LANGUAGES_ACTIVE" || failed=restore-receipt; fi
	fi
	if [[ -z $failed ]]; then
		input_languages_inspect
		input_languages_v3_remove_state_exact "$INPUT_LANGUAGES_ACTIVE" || failed=verify-restoration
	fi
	if [[ -z $failed && ( -e $INPUT_LANGUAGES_RECOVERY || -L $INPUT_LANGUAGES_RECOVERY ) ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_RECOVERY" || failed=remove-recovery; fi
	if [[ -z $failed ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING" || failed=remove-pending; fi
	if [[ -z $failed ]]; then return 0; fi
	input_languages_record_recovery_v3 "$transaction" "$(input_languages_v3_recovery_phase "$failed")" || true
	return 1
}

input_languages_rollback_pending_v3() {
	case $(jq -r '.operation // empty' "$INPUT_LANGUAGES_PENDING" 2>/dev/null) in
		apply) input_languages_rollback_apply_pending_v3 ;;
		remove) input_languages_rollback_remove_pending_v3 ;;
		*) return 1 ;;
	esac
}

input_languages_v3_recorded_phase_matches_direct_state() {
	local phase expected direct helper receipt=null
	phase=$(jq -r .phase "$INPUT_LANGUAGES_PENDING") || return 1
	expected=$(jq -c --arg phase "$phase" '.expected_states[] | select(.phase == $phase)' "$INPUT_LANGUAGES_PENDING") || return 1
	direct=$(input_languages_v3_state_digest "$(input_languages_tree_digest "$INPUT_LANGUAGES_LIVE" 2>/dev/null || printf absent)|$(sha256sum "$INPUT_LANGUAGES_POINTER" 2>/dev/null || true)") || return 1
	helper=$(input_languages_v3_json_digest "$(input_languages_v3_helper_ownership)") || return 1
	if [[ -f $INPUT_LANGUAGES_ACTIVE ]]; then receipt=$(sha256sum "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) || return 1; fi
	jq -e --arg direct "$direct" --arg helper "$helper" --arg receipt "$receipt" '
		.direct_digest == $direct and .helper_digest == $helper and
		.receipt_digest == (if $receipt == "null" then null else $receipt end)
	' <<<"$expected" >/dev/null 2>&1
}

input_languages_reconcile_pending_v3() {
	local approved=${1-false} transaction operation archive prior result
	input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
	transaction=$(jq -r .transaction_id "$INPUT_LANGUAGES_PENDING")
	operation=$(jq -r .operation "$INPUT_LANGUAGES_PENDING")
	if [[ -f $INPUT_LANGUAGES_ACTIVE && $(jq -r '.version == 3 and .transaction_id == $transaction' --arg transaction "$transaction" "$INPUT_LANGUAGES_ACTIVE") == true ]]; then
		[[ $operation == apply && $(jq -r .phase "$INPUT_LANGUAGES_PENDING") == active-published ]] || return 1
		input_languages_acquire_lock Recovery || return 1
		input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || { input_languages_unlock || true; return 1; }
		[[ $(jq -r '.version == 3 and .transaction_id == $transaction' --arg transaction "$transaction" "$INPUT_LANGUAGES_ACTIVE") == true ]] || { input_languages_unlock || true; return 1; }
		archive=$INPUT_LANGUAGES_STATE/archive/$transaction-apply
		prior=$(jq -r .prior_active "$INPUT_LANGUAGES_PENDING")
		if [[ ! -e $archive && ! -L $archive ]]; then
			input_languages_v3_archive_apply_evidence "$transaction" "$prior" || { input_languages_unlock || true; return 1; }
		else
			[[ -d $archive && ! -L $archive && -f $archive/prior-active-v2.json && -f $archive/pending.json ]] || { input_languages_unlock || true; return 1; }
			cmp -s "$archive/prior-active-v2.json" "$prior" && cmp -s "$archive/pending.json" "$INPUT_LANGUAGES_PENDING" || { input_languages_unlock || true; return 1; }
		fi
		if [[ -e $INPUT_LANGUAGES_RECOVERY || -L $INPUT_LANGUAGES_RECOVERY ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_RECOVERY" || { input_languages_unlock || true; return 1; }; fi
		input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING"
		result=$?
		input_languages_unlock || true
		return "$result"
	fi
	if [[ $operation == remove && ! -e $INPUT_LANGUAGES_ACTIVE && ! -L $INPUT_LANGUAGES_ACTIVE ]]; then
		archive=$INPUT_LANGUAGES_STATE/archive/$transaction-remove
		[[ -d $archive && ! -L $archive && -f $archive/active.json && -f $archive/pending.json ]] || return 1
		cmp -s "$archive/pending.json" "$INPUT_LANGUAGES_PENDING" || return 1
		input_languages_validate_active_evidence_file "$archive/active.json" || return 1
		if [[ -e $INPUT_LANGUAGES_RECOVERY || -L $INPUT_LANGUAGES_RECOVERY ]]; then input_languages_remove_file_verified "$INPUT_LANGUAGES_RECOVERY" || return 1; fi
		input_languages_remove_file_verified "$INPUT_LANGUAGES_PENDING"
		return
	fi
	printf 'Plan: reconcile interrupted version-3 transaction %s by semantic rollback.\n' "$transaction"
	if [[ $approved != true ]] && ! wizard_confirm 'Recover this interrupted Input Languages transaction?'; then return 0; fi
	input_languages_acquire_lock Recovery || return 1
	input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || { input_languages_unlock || true; return 1; }
	if [[ -e $INPUT_LANGUAGES_RECOVERY || -L $INPUT_LANGUAGES_RECOVERY ]]; then
		input_languages_validate_recovery_file_v3 "$INPUT_LANGUAGES_RECOVERY" || { input_languages_unlock || true; return 1; }
	elif ! input_languages_v3_recorded_phase_matches_direct_state; then
		input_languages_record_recovery_v3 "$transaction" verified || { input_languages_unlock || true; return 1; }
		printf 'Recovery required: observed direct/helper state does not match recorded phase %s; no rollback write was attempted.\n' "$(jq -r .phase "$INPUT_LANGUAGES_PENDING")" >&2
		input_languages_unlock || true
		return 1
	fi
	input_languages_rollback_pending_v3
	local result=$?
	input_languages_unlock || true
	return "$result"
}

input_languages_reconcile_pending() {
	if [[ $(jq -r '.version // empty' "$INPUT_LANGUAGES_PENDING" 2>/dev/null) == 3 ]]; then input_languages_reconcile_pending_v3 "$@"; else input_languages_reconcile_pending_v2 "$@"; fi
}

input_languages_reconcile_cleanup() {
	if [[ $(jq -r '.version // empty' "$INPUT_LANGUAGES_CLEANUP" 2>/dev/null) == 3 ]]; then return 1; else input_languages_reconcile_cleanup_v2 "$@"; fi
}

input_languages_prepare_apply() {
	input_languages_prepare_apply_v2 || return 1
	if [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 2 &&
		$INPUT_LANGUAGES_TREE_STATE == linked && $INPUT_LANGUAGES_PREPARED_RESULT == noop ]]; then
		INPUT_LANGUAGES_PREPARED_RESULT=change
	elif [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 3 ]]; then
		if input_languages_exact_noop_v3; then INPUT_LANGUAGES_PREPARED_RESULT=noop
		else printf 'Apply blocked: the version-3 installation is not exact; preserve evidence and resolve the conflict before mutation.\n' >&2; return 1; fi
	fi
}

apply_input_languages() {
	input_languages_inspect
	if [[ $INPUT_LANGUAGES_PENDING_STATE != absent || $INPUT_LANGUAGES_RECOVERY_STATE != absent || $INPUT_LANGUAGES_CLEANUP_STATE != absent ]]; then
		if [[ $INPUT_LANGUAGES_PENDING_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_PENDING") == 3 ]]; then
			local recovery=false option
			for option in "$@"; do [[ $option != --recovery-approved ]] || recovery=true; done
			input_languages_reconcile_pending_v3 "$recovery"
			return
		fi
		if [[ ( $INPUT_LANGUAGES_PENDING_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_PENDING") == 2 ) ||
			( $INPUT_LANGUAGES_CLEANUP_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_CLEANUP") == 2 ) ]]; then
			apply_input_languages_v2 "$@"
			return
		fi
		printf 'Apply blocked: Input Languages lifecycle evidence is invalid or unsupported; preserve it for recovery.\n' >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 3 ]]; then
		local expect_noop=false option
		for option in "$@"; do [[ $option != --expect-noop ]] || expect_noop=true; done
		if input_languages_exact_noop_v3; then printf 'Exact no-op: Portable input language setup is healthy; active language preserved.\n'; return 0; fi
		if [[ $expect_noop == true ]]; then printf 'Apply blocked: Input Languages changed after its exact no-op was inspected; review a new complete plan.\n' >&2; return 1; fi
		printf 'Apply blocked: the version-3 installation is not exact; preserve evidence and resolve the conflict before mutation.\n' >&2
		return 1
	fi
	if [[ $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 2 && $INPUT_LANGUAGES_TREE_STATE == linked ]]; then input_languages_apply_v3 "$@"; return; fi
	apply_input_languages_v2 "$@"
}

remove_input_languages() {
	input_languages_inspect
	if [[ ( $INPUT_LANGUAGES_ACTIVE_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 3 ) ||
		( $INPUT_LANGUAGES_PENDING_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_PENDING") == 3 ) ||
		( $INPUT_LANGUAGES_RECOVERY_STATE == valid && $(jq -r .version "$INPUT_LANGUAGES_RECOVERY") == 3 ) ]]; then
		input_languages_remove_v3 "$@"
		return
	fi
	remove_input_languages_v2 "$@"
}
