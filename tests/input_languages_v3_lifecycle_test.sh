#!/usr/bin/env bash

set -u

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

direct_v2_expands_to_v3() (
	set -euo pipefail
	local lifecycle_mode=$1 root home transaction backup_transaction build source artifact_sha widget_sha artifact_dir backup digest profile_digest
	root=$(mktemp -d)
	trap 'chmod -R u+w -- "$root" 2>/dev/null || true; rm -rf -- "$root"' EXIT
	home=$root/home
	export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share XDG_STATE_HOME=$home/.local/state
	export XDG_RUNTIME_DIR=$root/runtime DOTFILES_TEST_OMARCHY_VERSION=4.0.2-1 DOTFILES_UI=bash
	mkdir -p "$HOME" "$XDG_CONFIG_HOME/omarchy/plugins" "$XDG_CONFIG_HOME/fcitx5" "$XDG_DATA_HOME/dotfiles/input-languages/plugins" \
		"$XDG_STATE_HOME/dotfiles/input-languages/backups" "$XDG_STATE_HOME/dotfiles/input-languages/diagnostics" \
		"$XDG_STATE_HOME/dotfiles/input-languages/archive" "$XDG_RUNTIME_DIR"
	chmod 700 "$XDG_DATA_HOME/dotfiles/input-languages" "$XDG_DATA_HOME/dotfiles/input-languages/plugins" \
		"$XDG_STATE_HOME/dotfiles/input-languages" "$XDG_STATE_HOME/dotfiles/input-languages/backups" \
		"$XDG_STATE_HOME/dotfiles/input-languages/diagnostics" "$XDG_STATE_HOME/dotfiles/input-languages/archive" "$XDG_RUNTIME_DIR"
	printf 'profile\n' >"$XDG_CONFIG_HOME/fcitx5/profile"
	chmod 600 "$XDG_CONFIG_HOME/fcitx5/profile"
	profile_digest=$(sha256sum "$XDG_CONFIG_HOME/fcitx5/profile" | cut -d' ' -f1)
	printf '%s\n' '{"version":1,"bar":{"layout":{"left":[],"center":[],"right":[{"id":"dotfiles.keyboard-layout"}]}}}' >"$XDG_CONFIG_HOME/omarchy/shell.json"
	/usr/bin/stow --no-folding --dir "$SOURCE_REPO/config" --target "$HOME" hyprland

	# A complete valid version-2 direct installation is the immutable expansion ancestry.
	transaction=20260910T100000.000000000Z-1000-abcd
	backup_transaction=20260909T100000.000000000Z-9999-abcd
	backup=$XDG_STATE_HOME/dotfiles/input-languages/backups/$backup_transaction/tree
	mkdir -p "$backup"
	chmod 700 "$XDG_STATE_HOME/dotfiles/input-languages/backups/$backup_transaction" "$backup"
	build=$(printf old-build | sha256sum | cut -d' ' -f1)
	source=$(printf old-source | sha256sum | cut -d' ' -f1)
	printf 'old plugin\n' >"$root/plugin"
	artifact_sha=$(sha256sum "$root/plugin" | cut -d' ' -f1)
	artifact_dir=$XDG_DATA_HOME/dotfiles/input-languages/plugins/$build-$artifact_sha-$transaction
	mkdir -p "$artifact_dir"
	cp "$root/plugin" "$artifact_dir/input-languages.so"
	cp -a "$SOURCE_REPO/plugins/input-languages/widget/dotfiles.keyboard-layout" "$artifact_dir/dotfiles.keyboard-layout"
	widget_sha=$(source "$SOURCE_REPO/lib/dotfiles/core.sh"; source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"; input_languages_widget_digest "$artifact_dir/dotfiles.keyboard-layout")
	jq -n --arg build "$build" --arg source "$source" --arg sha "$artifact_sha" --arg widget "$widget_sha" \
		'{version:1,build_id:$build,source_id:$source,compatibility_hash:"test-compat",compiler:"test-compiler",dependencies:"test-dependencies",artifact_sha256:$sha,widget_sha256:$widget,exports:["pluginAPIVersion","pluginExit","pluginInit"]}' \
		>"$artifact_dir/build.json"
	chmod 555 "$artifact_dir/input-languages.so"
	chmod 444 "$artifact_dir/build.json" "$artifact_dir/dotfiles.keyboard-layout"/*
	chmod 555 "$artifact_dir" "$artifact_dir/dotfiles.keyboard-layout"
	ln -s "$artifact_dir/dotfiles.keyboard-layout" "$XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout"
	printf 'return "%s"\n' "$artifact_dir/input-languages.so" >"$XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua"
	chmod 600 "$XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua"
	REPOSITORY_ROOT=$SOURCE_REPO
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	input_languages_set_paths
	digest=$(input_languages_tree_digest "$backup")
	jq -n --arg transaction "$transaction" --arg backup_transaction "$backup_transaction" --arg source "$source" --arg build "$build" \
		--arg artifact "$artifact_dir/input-languages.so" --arg sha "$artifact_sha" --arg widget "$widget_sha" --arg backup "$backup" --arg backup_digest "$digest" \
		--arg widget_source "$artifact_dir/dotfiles.keyboard-layout" \
		'{version:2,operation:"active",transaction_id:$transaction,backup_transaction_id:$backup_transaction,source_id:$source,build_id:$build,artifact:$artifact,artifact_sha256:$sha,widget_sha256:$widget,
		compatibility_hash:"test-compat",compiler:"test-compiler",compiler_warning:"",dependencies:"test-dependencies",backup:$backup,backup_digest:$backup_digest,backup_existed:false,
		widget_source:$widget_source,widget_section:"right",widget_index:0,widget_entry:{id:"dotfiles.keyboard-layout"},prior_stock_present:false,prior_stock_section:null,prior_stock_index:null,prior_stock_entry:null}' \
		>"$XDG_STATE_HOME/dotfiles/input-languages/active.json"
	chmod 600 "$XDG_STATE_HOME/dotfiles/input-languages/active.json"
	cp "$XDG_STATE_HOME/dotfiles/input-languages/active.json" "$root/original-v2.json"
	printf '1\n' >"$root/group"
	printf 'inactive\n' >"$root/socket-state"
	printf 'inactive\n' >"$root/service-state"
	if [[ $lifecycle_mode == quiesce-failure ]]; then
		printf 'active\n' >"$root/socket-state"
		printf 'active\n' >"$root/service-state"
	elif [[ $lifecycle_mode == transitional-quiesce ]]; then
		printf 'activating\n' >"$root/socket-state"
		printf 'deactivating\n' >"$root/service-state"
	fi
	printf 'false\n' >"$root/autoreload"
	printf 'active\n' >"$root/plugin-state"
	: >"$root/calls"

	jq -n --arg profile "$XDG_CONFIG_HOME/fcitx5/profile" --arg digest "$profile_digest" --arg method "$([[ $lifecycle_mode == idle ]] && printf '' || printf keyboard-ru)" '
		{identity:{unique_owner:":1.42",owner_epoch:1,supervised:true,upstream_version:"5.1.21",controller_shape:"supported"},
		profile:{path:$profile,safe:true,device:1,inode:2,mode:384,uid:1000,digest:$digest},
		groups:[{name:"Default",default_layout:"us",default_im:"keyboard-ru",properties:{},items:[{method:"keyboard-us",layout_override:"",display_name:"English (US)",native_name:"English (US)",language_code:"en",addon:"keyboard",configurable:true,variant:null,properties:{}},{method:"keyboard-ru",layout_override:"",display_name:"Russian",native_name:"Russian",language_code:"ru",addon:"keyboard",configurable:true,variant:null,properties:{}}]}],
		available_methods:["keyboard-us","keyboard-ru"],addons:[{name:"keyboard",enabled:true,available:true},{name:"dbus",enabled:true,available:true},{name:"dbusfrontend",enabled:true,available:true}],current_group:"Default",observed_method:$method}' >"$root/controller.json"

	omarchy() {
		printf 'omarchy %s\n' "$*" >>"$root/calls"
		case "$*" in
			'plugin list --json')
				if jq -e '.bar.layout.right | any(.[]; .id == "dotfiles.keyboard-layout")' "$XDG_CONFIG_HOME/omarchy/shell.json" >/dev/null; then
					printf '%s\n' '[{"id":"dotfiles.keyboard-layout","name":"Flag keyboard layout","enabled":true,"kinds":["bar-widget"],"firstParty":false,"clonedFrom":"omarchy.keyboard-layout"}]'
				else printf '%s\n' '[]'; fi
				;;
			'plugin disable dotfiles.keyboard-layout')
				jq '.bar.layout.right |= map(select(.id != "dotfiles.keyboard-layout"))' "$XDG_CONFIG_HOME/omarchy/shell.json" >"$root/shell.next"
				mv "$root/shell.next" "$XDG_CONFIG_HOME/omarchy/shell.json"
				;;
			'plugin enable dotfiles.keyboard-layout --section right --index 0')
				jq '.bar.layout.right = ([{"id":"dotfiles.keyboard-layout"}] + [.bar.layout.right[] | select(.id != "dotfiles.keyboard-layout")])' "$XDG_CONFIG_HOME/omarchy/shell.json" >"$root/shell.next"
				mv "$root/shell.next" "$XDG_CONFIG_HOME/omarchy/shell.json"
				;;
			'shell shell ping') printf 'ok\n' ;;
			'shell shell debugBarGeometry') printf '%s\n' '[{"id":"dotfiles.keyboard-layout","width":24,"height":24,"itemWidth":24,"itemHeight":24,"visible":true,"itemVisible":true}]' ;;
			'restart shell'|'shell shell rescanPlugins') return 0 ;;
			*) case ${1-} in version) printf '4.0.2-1\n' ;; pkg) return 0 ;; *) return 0 ;; esac ;;
		esac
	}
	hyprctl() {
		printf 'hyprctl %s\n' "$*" >>"$root/calls"
		case "$*" in
			'-j inputlanguages')
				local pointer current group method
				pointer=$(cut -d'"' -f2 "$XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua")
				group=$(<"$root/group")
				if [[ $pointer == *'/integration-test/input-languages.so' ]]; then
					if [[ $lifecycle_mode == idle ]]; then method=''; else method=$([[ $group == 0 ]] && printf keyboard-us || printf keyboard-ru); fi
					jq -n --argjson group "$group" --arg method "$method" --arg mode "$lifecycle_mode" '{healthy:($mode != "idle"),direct_xkb_health:"healthy",build_id:("b"*64),source_id:("c"*64),compatibility_hash:"test-compat",canonical_group:$group,physical_keyboards:["test-keyboard"],excluded_keyboards:[],indicator_state:"healthy",authority_session:("a"*32),canonical_language:(if $group == 0 then "US" else "Russian" end),canonical_generation:2,physical_groups:[{device:"test-keyboard",group:$group}],physical_synchronized:true,helper_connection:"connected",helper_build_id:("b"*64),protocol_identity:"dotfiles-input-languages-fcitx-seqpacket-v1",offered_generation:2,accepted_generation:2,acknowledged_generation:(if $mode == "idle" then 0 else 2 end),report_sequence:4,report_age_milliseconds:10,coalesced_targets:0,fcitx_owner_epoch:1,managed_group_state:"exact",observed_method:$method,retry_phase:"none",outcome:(if $mode == "idle" then "idle-no-context" else "converged" end),diagnostic:"",report_stale:false}'
				else
					jq -n --argjson group "$group" --arg build "$build" --arg source "$source" '{healthy:true,build_id:$build,source_id:$source,compatibility_hash:"test-compat",canonical_group:$group,physical_keyboards:["test-keyboard"],excluded_keyboards:[]}'
				fi ;;
			'-j devices') jq -n --argjson group "$(<"$root/group")" '{keyboards:[{name:"test-keyboard",layout:"us,ru",variant:",",active_layout_index:$group,active_keymap:(if $group == 0 then "English (US)" else "Russian" end)}]}' ;;
			'-j inputlanguagesreset 0') printf '0\n' >"$root/group"; printf '%s\n' '{"ok":true,"canonical_group":0}' ;;
			'-j inputlanguagesreset 1') printf '1\n' >"$root/group"; printf '%s\n' '{"ok":true,"canonical_group":1}' ;;
			'-j getoption misc:disable_autoreload') jq -n --argjson value "$(<"$root/autoreload")" '{bool:$value}' ;;
			'-j plugin list')
				if [[ $(<"$root/plugin-state") == active ]]; then printf '%s\n' '[{"name":"Input Languages","author":"dotfiles","version":"test"}]'; else printf '%s\n' '[]'; fi
				;;
			plugin\ unload\ *) printf 'inactive\n' >"$root/plugin-state" ;;
			reload)
				if [[ -e $root/fail-remove-reload ]]; then rm -f "$root/fail-remove-reload"; return 1; fi
				if [[ -f $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua ]]; then printf 'active\n' >"$root/plugin-state"; else printf 'inactive\n' >"$root/plugin-state"; fi
				;;
			'keyword misc:disable_autoreload true') printf 'true\n' >"$root/autoreload" ;;
			'keyword misc:disable_autoreload false') printf 'false\n' >"$root/autoreload" ;;
			configerrors) return 0 ;;
			*) return 0 ;;
		esac
	}
	stow() { command /usr/bin/stow "$@"; }
	export -f omarchy hyprctl stow

	input_languages_static_preflight() { return 0; }
	input_languages_stack_identity() { INPUT_LANGUAGES_RUNNING_HASH=test-compat INPUT_LANGUAGES_HEADER_HASH=test-compat INPUT_LANGUAGES_COMPILER=test-compiler INPUT_LANGUAGES_COMPILER_WARNING=''; }
	input_languages_integration_source_identity() { printf c%.0s {1..64}; printf '\n'; }
	input_languages_integration_dependency_identity() { printf 'test-dependencies\n'; }
	input_languages_linker_identity() { printf 'test-linker\n'; }
	input_languages_build_integration_artifact() {
		INPUT_LANGUAGES_INTEGRATION_SOURCE_ID=$(printf c%.0s {1..64})
		INPUT_LANGUAGES_INTEGRATION_BUILD_ID=$(printf b%.0s {1..64})
		INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR=$XDG_DATA_HOME/dotfiles/input-languages/plugins/integration-test
		INPUT_LANGUAGES_INTEGRATION_ARTIFACT=$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/input-languages.so
		INPUT_LANGUAGES_INTEGRATION_HELPER=$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/input-languages-fcitx-helper
		mkdir -p "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/systemd"
		printf 'plugin\n' >"$INPUT_LANGUAGES_INTEGRATION_ARTIFACT"
		printf 'helper\n' >"$INPUT_LANGUAGES_INTEGRATION_HELPER"
		cp -a "$SOURCE_REPO/plugins/input-languages/widget/dotfiles.keyboard-layout" "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/dotfiles.keyboard-layout"
		printf 'socket\n' >"$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/systemd/dotfiles-input-languages-fcitx.socket"
		printf 'service\n' >"$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/systemd/dotfiles-input-languages-fcitx.service"
		jq -n '{version:1,integration:"dotfiles-input-languages-fcitx-v1",source_id:("c"*64),build_id:("b"*64),compatibility_hash:"test-compat",compiler:"test-compiler",linker:"test-linker",dependencies:"test-dependencies",artifact_sha256:("d"*64),helper_sha256:("e"*64),widget_sha256:("f"*64),protocol_identity:"dotfiles-input-languages-fcitx-seqpacket-v1",controller_identity:"dotfiles-input-languages-fcitx-controller-v1",health_identity:"dotfiles-input-languages-health-v1",unit_identity:"dotfiles-input-languages-fcitx-systemd-v1",inventory:["test"]}' >"$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/build.json"
		chmod 555 "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/dotfiles.keyboard-layout"
		chmod 444 "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/dotfiles.keyboard-layout"/*
	}
	input_languages_validate_integration_artifact_self() { [[ -f $1/input-languages-fcitx-helper && $(<"$1/input-languages-fcitx-helper") == helper ]]; }
	input_languages_v3_controller() {
		local helper=$1 operation=$2 expected action argument snapshot snapshot_digest
		shift 2
		operation=${operation#restore-}
		printf 'controller %s %s\n' "$operation" "$*" >>"$root/calls"
		if [[ $operation == inspect ]]; then
			snapshot=$(<"$root/controller.json")
		else
			expected=$1 action=$2 argument=${3-}
			snapshot=$(<"$root/controller.json")
			[[ $(printf '%s' "$snapshot" | sha256sum | cut -d' ' -f1) == "$expected" ]] || return 1
			if [[ $lifecycle_mode == indeterminate && $action == add-managed ]]; then
				snapshot_digest=$(printf '%s' "$snapshot" | sha256sum | cut -d' ' -f1)
				jq -n --argjson snapshot "$snapshot" --arg digest "$snapshot_digest" '{outcome:"timeout-indeterminate",snapshot:$snapshot,snapshot_digest:$digest,diagnostic:"timed out"}'
				return 1
			fi
			case $action in
				add-managed) snapshot=$(jq '.groups += [{name:"Dotfiles Input Languages",default_layout:"us",default_im:"",properties:{},items:[]}]' <<<"$snapshot") ;;
				populate-managed) snapshot=$(jq '.groups |= map(if .name == "Dotfiles Input Languages" then .default_layout="us" | .default_im="keyboard-ru" | .items=[{method:"keyboard-us",layout_override:"",display_name:"English (US)",native_name:"English (US)",language_code:"en",addon:"keyboard",configurable:true,variant:null,properties:{}},{method:"keyboard-ru",layout_override:"",display_name:"Russian",native_name:"Russian",language_code:"ru",addon:"keyboard",configurable:true,variant:null,properties:{}}] else . end)' <<<"$snapshot") ;;
				switch-group) snapshot=$(jq --arg group "$argument" --arg mode "$lifecycle_mode" '.current_group=$group | .groups = ([.groups[] | select(.name == $group)] + [.groups[] | select(.name != $group)]) | .observed_method=(if $mode == "idle" then "" else ([.groups[] | select(.name == $group)][0].default_im // "") end)' <<<"$snapshot") ;;
				set-method) snapshot=$(jq --arg method "$argument" '.observed_method=$method' <<<"$snapshot") ;;
				remove-managed)
					[[ ! -e $root/fail-rollback ]] || return 1
					snapshot=$(jq '.groups |= map(select(.name != "Dotfiles Input Languages"))' <<<"$snapshot")
					;;
				save) : ;;
			esac
			printf '%s\n' "$snapshot" >"$root/controller.json"
		fi
		snapshot_digest=$(printf '%s' "$snapshot" | sha256sum | cut -d' ' -f1)
		jq -n --argjson snapshot "$snapshot" --arg digest "$snapshot_digest" '{outcome:(if $snapshot.observed_method == "" then "idle-no-context" else "pending" end),snapshot:$snapshot,snapshot_digest:$digest,diagnostic:""}'
	}
	input_languages_v3_systemctl() {
		printf 'systemctl %s\n' "$*" >>"$root/calls"
		case $1 in
			show)
				local state=active
				case $2 in
					dotfiles-input-languages-fcitx.socket) state=$(<"$root/socket-state") ;;
					dotfiles-input-languages-fcitx.service) state=$(<"$root/service-state") ;;
				esac
				jq -n --arg unit "$2" --arg state "$state" '{unit:$unit,load_state:"loaded",fragment_path:"/usr/lib/systemd/user/omarchy-fcitx5.service",active_state:$state,sub_state:(if $state == "active" then "running" else "dead" end),main_pid:(if $state == "inactive" then 0 else 42 end)}'
				;;
			start)
				if [[ $lifecycle_mode == rollback || $lifecycle_mode == recovery || $lifecycle_mode == corrupt-recovery || $lifecycle_mode == semantic-phase-drift ]]; then
					if [[ $lifecycle_mode == semantic-phase-drift ]]; then
						: >"$root/semantic-failure"
						jq '.groups |= map(if .name == "Default" then .properties={foreign:true} else . end)' "$root/controller.json" >"$root/controller.next"
					else
						jq '.groups += [{name:"Unrelated",default_layout:"de",default_im:"keyboard-de",properties:{},items:[{method:"keyboard-de",layout_override:"",display_name:"German",native_name:"Deutsch",language_code:"de",addon:"keyboard",configurable:true,variant:null,properties:{}}]}]' "$root/controller.json" >"$root/controller.next"
					fi
					mv "$root/controller.next" "$root/controller.json"
					[[ $lifecycle_mode != recovery && $lifecycle_mode != corrupt-recovery ]] || : >"$root/fail-rollback"
					return 1
				fi
				[[ ${2-} != dotfiles-input-languages-fcitx.socket ]] || printf 'active\n' >"$root/socket-state"
				[[ ${2-} != dotfiles-input-languages-fcitx.service ]] || printf 'active\n' >"$root/service-state"
				;;
			stop)
				[[ $lifecycle_mode != quiesce-failure ]] || return 1
				[[ ${2-} != dotfiles-input-languages-fcitx.socket ]] || printf 'inactive\n' >"$root/socket-state"
				[[ ${2-} != dotfiles-input-languages-fcitx.service ]] || printf 'inactive\n' >"$root/service-state"
				;;
			daemon-reload) return 0 ;;
			*) return 2 ;;
		 esac
	}
	if [[ $lifecycle_mode == phase-interrupt ]]; then
		local update_definition rollback_definition
		update_definition=$(declare -f input_languages_v3_update_pending)
		rollback_definition=$(declare -f input_languages_rollback_pending_v3)
		update_definition=${update_definition/input_languages_v3_update_pending /input_languages_v3_update_pending_recorded }
		eval "$update_definition"
		input_languages_v3_update_pending() {
			input_languages_v3_update_pending_recorded "$@" || return 1
			[[ $1 != "$INPUT_LANGUAGES_TEST_INTERRUPT_PHASE" ]]
		}
		input_languages_rollback_pending_v3() { return 1; }
	fi
	if [[ $lifecycle_mode == semantic-phase-drift ]]; then
		local direct_write_definition
		direct_write_definition=$(declare -f input_languages_publish_pointer)
		direct_write_definition=${direct_write_definition/input_languages_publish_pointer /input_languages_publish_pointer_recorded }
		eval "$direct_write_definition"
		input_languages_publish_pointer() {
			[[ ! -e $root/semantic-failure ]] || printf 'publish-pointer\n' >>"$root/direct-rollback-writes"
			input_languages_publish_pointer_recorded "$@"
		}
		direct_write_definition=$(declare -f input_languages_publish_widget_link)
		direct_write_definition=${direct_write_definition/input_languages_publish_widget_link /input_languages_publish_widget_link_recorded }
		eval "$direct_write_definition"
		input_languages_publish_widget_link() {
			[[ ! -e $root/semantic-failure ]] || printf 'publish-widget\n' >>"$root/direct-rollback-writes"
			input_languages_publish_widget_link_recorded "$@"
		}
		direct_write_definition=$(declare -f input_languages_copy_atomic)
		direct_write_definition=${direct_write_definition/input_languages_copy_atomic /input_languages_copy_atomic_recorded }
		eval "$direct_write_definition"
		input_languages_copy_atomic() {
			[[ ! -e $root/semantic-failure ]] || printf 'copy-receipt\n' >>"$root/direct-rollback-writes"
			input_languages_copy_atomic_recorded "$@"
		}
	fi
	if [[ $lifecycle_mode == post-pause-failure ]]; then
		local reload_definition reload_attempt=0
		reload_definition=$(declare -f input_languages_reload_widget_registry)
		reload_definition=${reload_definition/input_languages_reload_widget_registry /input_languages_reload_widget_registry_recorded }
		eval "$reload_definition"
		input_languages_reload_widget_registry() {
			reload_attempt=$((reload_attempt + 1))
			[[ $reload_attempt -gt 1 ]] || return 1
			input_languages_reload_widget_registry_recorded "$@"
		}
	fi
	if [[ $lifecycle_mode == invalid-evidence ]]; then
		printf '{}\n' >"$INPUT_LANGUAGES_PENDING"
		chmod 600 "$INPUT_LANGUAGES_PENDING"
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		cmp -s "$INPUT_LANGUAGES_ACTIVE" "$root/original-v2.json" || return 1
		[[ $(<"$INPUT_LANGUAGES_PENDING") == '{}' ]] || return 1
		! grep -q '^controller execute' "$root/calls" || return 1
		return 0
	fi
	if [[ $lifecycle_mode == indeterminate ]]; then
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
		input_languages_validate_recovery_file_v3 "$INPUT_LANGUAGES_RECOVERY" || return 1
		[[ $(grep -c '^controller execute' "$root/calls") == 1 ]] || return 1
		jq -e '[.groups[].name] == ["Default"] and .current_group == "Default"' "$root/controller.json" >/dev/null || return 1
		return 0
	fi
	if [[ $lifecycle_mode == quiesce-failure ]]; then
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
		input_languages_validate_recovery_file_v3 "$INPUT_LANGUAGES_RECOVERY" || return 1
		! grep -q '^controller execute' "$root/calls" || return 1
		return 0
	fi
	if [[ $lifecycle_mode == phase-drift ]]; then
		local update_definition mutation_calls
		update_definition=$(declare -f input_languages_v3_update_pending)
		update_definition=${update_definition/input_languages_v3_update_pending /input_languages_v3_update_pending_recorded }
		eval "$update_definition"
		input_languages_v3_update_pending() {
			[[ $1 != pointer-published ]] || return 1
			input_languages_v3_update_pending_recorded "$@"
		}
		input_languages_rollback_pending_v3() { return 1; }
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		[[ $(jq -r .phase "$INPUT_LANGUAGES_PENDING") == socket-started ]] || return 1
		mutation_calls=$(grep -Ec '^(controller execute|systemctl (start|stop|daemon-reload)|hyprctl (-j inputlanguagesreset|reload|keyword)|omarchy (restart|shell shell rescanPlugins))' "$root/calls" || true)
		if apply_input_languages --recovery-approved >/dev/null 2>&1; then return 1; fi
		[[ $(grep -Ec '^(controller execute|systemctl (start|stop|daemon-reload)|hyprctl (-j inputlanguagesreset|reload|keyword)|omarchy (restart|shell shell rescanPlugins))' "$root/calls" || true) == "$mutation_calls" ]] || return 1
		input_languages_validate_recovery_file_v3 "$INPUT_LANGUAGES_RECOVERY" || return 1
		return 0
	fi
	if [[ $lifecycle_mode == semantic-phase-drift ]]; then
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
		input_languages_validate_recovery_file_v3 "$INPUT_LANGUAGES_RECOVERY" || return 1
		cmp -s "$INPUT_LANGUAGES_ACTIVE" "$root/original-v2.json" || return 1
		input_languages_pointer_matches "$artifact_dir/input-languages.so" || return 1
		input_languages_widget_link_matches "$artifact_dir/dotfiles.keyboard-layout" || return 1
		[[ ! -s $root/direct-rollback-writes ]] || return 1
		! grep -Eq '^(hyprctl reload|omarchy (restart shell|shell shell rescanPlugins))$' "$root/calls" || return 1
		return 0
	fi
	if [[ $lifecycle_mode == corrupt-recovery ]]; then
		local helper mutation_calls
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		input_languages_validate_recovery_file_v3 "$INPUT_LANGUAGES_RECOVERY" || return 1
		helper=$(jq -r .integration_artifact.artifact "$INPUT_LANGUAGES_PENDING"); helper=${helper%/*}/input-languages-fcitx-helper
		printf 'corrupted\n' >"$helper"
		mutation_calls=$(grep -c '^controller ' "$root/calls" || true)
		unset INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR INPUT_LANGUAGES_INTEGRATION_ARTIFACT INPUT_LANGUAGES_INTEGRATION_HELPER INPUT_LANGUAGES_INTEGRATION_BUILD_ID
		if apply_input_languages --recovery-approved >/dev/null 2>&1; then return 1; fi
		[[ $(grep -c '^controller ' "$root/calls" || true) == "$mutation_calls" ]] || return 1
		[[ -e $INPUT_LANGUAGES_PENDING && -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		return 0
	fi
	if [[ $lifecycle_mode == phase-interrupt ]]; then
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		[[ -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		eval "$rollback_definition"
		unset INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR INPUT_LANGUAGES_INTEGRATION_ARTIFACT INPUT_LANGUAGES_INTEGRATION_HELPER INPUT_LANGUAGES_INTEGRATION_BUILD_ID
		apply_input_languages --recovery-approved >/dev/null || return 1
		cmp -s "$INPUT_LANGUAGES_ACTIVE" "$root/original-v2.json" || return 1
		[[ ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		return 0
	fi
	if [[ $lifecycle_mode == post-pause-failure ]]; then
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		cmp -s "$INPUT_LANGUAGES_ACTIVE" "$root/original-v2.json" || return 1
		[[ $(<"$root/autoreload") == false && ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		return 0
	fi
	if [[ $lifecycle_mode == stale-helper || $lifecycle_mode == stale-controller ]]; then
		input_languages_v3_set_paths
		wizard_confirm() {
			if [[ $lifecycle_mode == stale-helper ]]; then
				mkdir -p "${INPUT_LANGUAGES_V3_SOCKET_PATH%/*}"
				printf 'foreign\n' >"$INPUT_LANGUAGES_V3_SOCKET_PATH"
			else
				jq '.groups[0].properties={concurrent:true}' "$root/controller.json" >"$root/controller.next"
				mv "$root/controller.next" "$root/controller.json"
			fi
			return 0
		}
		if apply_input_languages --packages-prepared >/dev/null 2>&1; then return 1; fi
		[[ ! -e $INPUT_LANGUAGES_PENDING ]] || return 1
		cmp -s "$INPUT_LANGUAGES_ACTIVE" "$root/original-v2.json" || return 1
		! grep -Eq '^(controller execute|systemctl stop)' "$root/calls" || return 1
		return 0
	fi
	if [[ $lifecycle_mode == stale-build-input ]]; then
		local stale_source_marker=$root/source-drift
		input_languages_integration_source_identity() { if [[ -e $stale_source_marker ]]; then printf d%.0s {1..64}; else printf c%.0s {1..64}; fi; printf '\n'; }
		wizard_confirm() { : >"$stale_source_marker"; return 0; }
		if apply_input_languages --packages-prepared >"$root/stale-build.out" 2>&1; then cat "$root/stale-build.out" >&2; return 1; fi
		[[ ! -e $INPUT_LANGUAGES_PENDING ]] || return 1
		cmp -s "$INPUT_LANGUAGES_ACTIVE" "$root/original-v2.json" || return 1
		! grep -q '^controller execute' "$root/calls" || return 1
		return 0
	fi
	if [[ $lifecycle_mode == partial-helper ]]; then
		input_languages_v3_publish_helper_edges() {
			input_languages_v3_set_paths
			input_languages_v3_publish_link "$INPUT_LANGUAGES_V3_SOCKET_PATH" "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/systemd/$INPUT_LANGUAGES_V3_SOCKET_UNIT"
			return 1
		}
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		cmp -s "$INPUT_LANGUAGES_ACTIVE" "$root/original-v2.json" || return 1
		[[ ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		[[ ! -e $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.socket && ! -e $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.service ]] || return 1
		return 0
	fi
	if [[ $lifecycle_mode == archive-recovery ]]; then
		local archive_definition transaction_id
		archive_definition=$(declare -f input_languages_v3_archive_apply_evidence)
		input_languages_v3_archive_apply_evidence() { return 1; }
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		[[ $(jq -r .version "$INPUT_LANGUAGES_ACTIVE") == 3 && $(jq -r .phase "$INPUT_LANGUAGES_PENDING") == active-published ]] || return 1
		transaction_id=$(jq -r .transaction_id "$INPUT_LANGUAGES_ACTIVE")
		eval "$archive_definition"
		apply_input_languages --recovery-approved >/dev/null || return 1
		[[ ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		[[ -f $INPUT_LANGUAGES_STATE/archive/$transaction_id-apply/prior-active-v2.json && -f $INPUT_LANGUAGES_STATE/archive/$transaction_id-apply/pending.json ]] || return 1
		return 0
	fi

	if [[ $lifecycle_mode == rollback || $lifecycle_mode == recovery ]]; then
		if apply_input_languages --yes --packages-prepared >/dev/null 2>&1; then return 1; fi
		if [[ $lifecycle_mode == recovery ]]; then
			input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
			input_languages_validate_recovery_file_v3 "$INPUT_LANGUAGES_RECOVERY" || return 1
			[[ -L $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.socket ]] || return 1
			rm -f "$root/fail-rollback"
			lifecycle_mode=rollback-complete
			unset INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR INPUT_LANGUAGES_INTEGRATION_ARTIFACT INPUT_LANGUAGES_INTEGRATION_HELPER INPUT_LANGUAGES_INTEGRATION_BUILD_ID
			apply_input_languages --recovery-approved >/dev/null || return 1
		fi
		cmp -s "$INPUT_LANGUAGES_ACTIVE" "$root/original-v2.json" || return 1
		jq -e '[.groups[].name] == ["Default","Unrelated"] and .current_group == "Default" and .observed_method == "keyboard-ru"' "$root/controller.json" >/dev/null || return 1
		[[ ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		[[ ! -e $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.socket && ! -e $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.service ]] || return 1
		[[ $(<"$root/group") == 1 ]] || return 1
		local direct_restore_line fcitx_restore_line
		direct_restore_line=$(grep -n '^hyprctl reload$' "$root/calls" | cut -d: -f1 | { read -r line; printf '%s\n' "$line"; })
		fcitx_restore_line=$(grep -n 'controller execute .* switch-group Default$' "$root/calls" | cut -d: -f1 | { read -r line; printf '%s\n' "$line"; })
		[[ -n $direct_restore_line && -n $fcitx_restore_line && $direct_restore_line -lt $fcitx_restore_line ]] || return 1
		return 0
	fi

	apply_input_languages --yes --packages-prepared >/dev/null || return 1
	input_languages_validate_active_file_v3 "$INPUT_LANGUAGES_ACTIVE" artifact
	jq -e --arg backup "$backup" '
		.version == 3 and .operation == "active" and .direct_ancestry.backup == $backup and
		.managed_group.name == "Dotfiles Input Languages" and .operation_start.canonical_language == "Russian" and
		[.fcitx_before.groups[].name] == ["Default"] and .fcitx_before.current_group == "Default"
	' "$INPUT_LANGUAGES_ACTIVE" >/dev/null
	local ancestry
	ancestry=$(jq -r .direct_ancestry.receipt "$INPUT_LANGUAGES_ACTIVE")
	cmp -s "$ancestry" "$root/original-v2.json"
	[[ $(sha256sum "$ancestry" | cut -d' ' -f1) == "$(jq -r .direct_ancestry.receipt_digest "$INPUT_LANGUAGES_ACTIVE")" ]]
	jq -e --arg method "$([[ $lifecycle_mode == idle ]] && printf '' || printf keyboard-ru)" '[.groups[].name] == ["Dotfiles Input Languages","Default"] and .current_group == "Dotfiles Input Languages" and .observed_method == $method' "$root/controller.json" >/dev/null
	[[ -L $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.socket ]]
	[[ -L $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.service ]]
	[[ ! -e $INPUT_LANGUAGES_PENDING ]]
	[[ $(<"$root/autoreload") == false ]]
	local start_line reset_line pause_line shell_line restore_autoreload_line reload_line
	start_line=$(grep -n '^systemctl start dotfiles-input-languages-fcitx.socket$' "$root/calls" | cut -d: -f1)
	reset_line=$(grep -n '^hyprctl -j inputlanguagesreset 0$' "$root/calls" | cut -d: -f1)
	[[ -n $start_line && -n $reset_line && $start_line -lt $reset_line ]]
	pause_line=$(grep -n '^hyprctl keyword misc:disable_autoreload true$' "$root/calls" | cut -d: -f1)
	shell_line=$(grep -n '^omarchy restart shell$' "$root/calls" | cut -d: -f1)
	restore_autoreload_line=$(grep -n '^hyprctl keyword misc:disable_autoreload false$' "$root/calls" | cut -d: -f1)
	reload_line=$(grep -n '^hyprctl reload$' "$root/calls" | cut -d: -f1)
	[[ -n $pause_line && -n $shell_line && -n $restore_autoreload_line && -n $reload_line &&
		$pause_line -lt $shell_line && $shell_line -lt $restore_autoreload_line && $restore_autoreload_line -lt $reload_line ]]
	local apply_archive=$INPUT_LANGUAGES_STATE/archive/$(jq -r .transaction_id "$INPUT_LANGUAGES_ACTIVE")-apply
	[[ -f $apply_archive/prior-active-v2.json && -f $apply_archive/pending.json ]]
	cmp -s "$apply_archive/prior-active-v2.json" "$root/original-v2.json"
	jq -e '
		.phase == "active-published" and
		[.expected_states[].phase] == ["prepared","prior-helper-quiesced","managed-group-created","managed-group-populated","managed-group-selected","managed-group-saved","units-published","manager-reloaded","socket-started","pointer-published","hyprland-transitioned","hyprland-reloaded","helper-ready","reset-issued","verified","active-published"] and
		all(.expected_states[]; .direct_digest != null and .helper_digest != null) and
		([.expected_states[] | select(.phase | startswith("managed-group")) | .fcitx_semantic_digest] | all(. != null)) and
		.expected_states[-1].receipt_digest != null
	' "$apply_archive/pending.json" >/dev/null
	if [[ $lifecycle_mode == pending-ancestry ]]; then
		local alternate_prior=$root/alternate-prior-v2.json
		cp "$root/original-v2.json" "$alternate_prior"
		chmod 600 "$alternate_prior"
		jq --arg prior "$alternate_prior" '.prior_active=$prior' "$apply_archive/pending.json" >"$INPUT_LANGUAGES_PENDING"
		chmod 600 "$INPUT_LANGUAGES_PENDING"
		! input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
		jq '.helper_target.socket_unit.path="/tmp/foreign-input-languages.socket"' "$apply_archive/pending.json" >"$INPUT_LANGUAGES_PENDING"
		chmod 600 "$INPUT_LANGUAGES_PENDING"
		! input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
		jq '.integration_artifact.protocol_identity="foreign-protocol"' "$apply_archive/pending.json" >"$INPUT_LANGUAGES_PENDING"
		chmod 600 "$INPUT_LANGUAGES_PENDING"
		! input_languages_validate_pending_file_v3 "$INPUT_LANGUAGES_PENDING" || return 1
		return 0
	fi

	# A repeated Apply observes exact persistent state and performs no lifecycle mutation.
	input_languages_integration_source_identity() { printf c%.0s {1..64}; printf '\n'; }
	if [[ $lifecycle_mode == remove-defaultim-drift ]]; then
		jq '.groups |= map(if .name == "Dotfiles Input Languages" then .default_im="keyboard-us" else . end)' "$root/controller.json" >"$root/controller.next"
		mv "$root/controller.next" "$root/controller.json"
	fi
	local active_before controller_before profile_before mutation_calls_before mutation_calls_after
	active_before=$(sha256sum "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1)
	controller_before=$(sha256sum "$root/controller.json" | cut -d' ' -f1)
	profile_before=$(sha256sum "$XDG_CONFIG_HOME/fcitx5/profile" | cut -d' ' -f1)
	mutation_calls_before=$(grep -Ec '^(systemctl (start|stop|daemon-reload)|controller execute|hyprctl (-j inputlanguagesreset|reload|keyword)|omarchy (restart|shell shell rescanPlugins))' "$root/calls" || true)
	apply_input_languages --yes --packages-prepared >/dev/null
	mutation_calls_after=$(grep -Ec '^(systemctl (start|stop|daemon-reload)|controller execute|hyprctl (-j inputlanguagesreset|reload|keyword)|omarchy (restart|shell shell rescanPlugins))' "$root/calls" || true)
	[[ $(sha256sum "$INPUT_LANGUAGES_ACTIVE" | cut -d' ' -f1) == "$active_before" ]]
	[[ $(sha256sum "$root/controller.json" | cut -d' ' -f1) == "$controller_before" ]]
	[[ $(sha256sum "$XDG_CONFIG_HOME/fcitx5/profile" | cut -d' ' -f1) == "$profile_before" ]]
	[[ $mutation_calls_after -eq $mutation_calls_before && ! -e $INPUT_LANGUAGES_PENDING ]]

	if [[ $lifecycle_mode == remove || $lifecycle_mode == remove-rollback || $lifecycle_mode == remove-unsupported || $lifecycle_mode == remove-unrelated-edit || $lifecycle_mode == remove-defaultim-drift ]]; then
		local installed_active=$root/installed-v3.json remove_archive
		cp "$INPUT_LANGUAGES_ACTIVE" "$installed_active"
		if [[ $lifecycle_mode == remove-unsupported ]]; then
			jq '.identity.upstream_version="5.1.22" | .available_methods=[] | .addons=[]' "$root/controller.json" >"$root/controller.next"
			mv "$root/controller.next" "$root/controller.json"
		fi
		if [[ $lifecycle_mode == remove-unrelated-edit ]]; then
			jq '.groups |= map(if .name == "Default" then .properties={user_note:"retained"} else . end)' "$root/controller.json" >"$root/controller.next"
			mv "$root/controller.next" "$root/controller.json"
		fi
		if [[ $lifecycle_mode == remove-rollback ]]; then
			: >"$root/fail-remove-reload"
			if remove_input_languages --yes >"$root/remove-failed.out" 2>&1; then return 1; fi
			grep -Fq 'Remove failed at restore-hyprland; reconstructing the verified version-3 installation.' "$root/remove-failed.out" || return 1
			[[ $(grep -c '^controller execute .* remove-managed' "$root/calls") -ge 1 ]] || return 1
			[[ $(grep -c '^controller execute .* add-managed' "$root/calls") -ge 2 ]] || return 1
			cmp -s "$INPUT_LANGUAGES_ACTIVE" "$installed_active" || return 1
			[[ ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
			input_languages_validate_active_file_v3 "$INPUT_LANGUAGES_ACTIVE" artifact || return 1
			jq -e '[.groups[].name] == ["Dotfiles Input Languages","Default"] and .current_group == "Dotfiles Input Languages" and .observed_method == "keyboard-ru"' "$root/controller.json" >/dev/null || return 1
			[[ -L $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.socket && -L $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.service ]] || return 1
			[[ -L $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout && -f $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua ]] || return 1
			[[ $(<"$root/plugin-state") == active && $(<"$root/group") == 0 && $(<"$root/autoreload") == false ]] || return 1
			return 0
		fi
		remove_input_languages --yes >/dev/null || return 1
		[[ ! -e $INPUT_LANGUAGES_ACTIVE && ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		jq -e '[.groups[].name] == ["Default"] and .current_group == "Default" and .observed_method == "keyboard-ru"' "$root/controller.json" >/dev/null || return 1
		if [[ $lifecycle_mode == remove-unrelated-edit ]]; then jq -e '.groups[0].properties == {user_note:"retained"}' "$root/controller.json" >/dev/null || return 1; fi
		[[ ! -e $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.socket && ! -e $XDG_CONFIG_HOME/systemd/user/dotfiles-input-languages-fcitx.service ]] || return 1
		[[ ! -e $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout && ! -e $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua ]] || return 1
		[[ ! -e $XDG_CONFIG_HOME/hypr && $(<"$root/plugin-state") == inactive ]] || return 1
		remove_archive=$(find "$INPUT_LANGUAGES_STATE/archive" -mindepth 1 -maxdepth 1 -type d -name '*-remove' -print -quit)
		[[ -f $remove_archive/active.json && -f $remove_archive/pending.json ]] || return 1
		cmp -s "$remove_archive/active.json" "$installed_active" || return 1
		input_languages_validate_pending_file_v3 "$remove_archive/pending.json" || return 1
		[[ $(jq -r .phase "$remove_archive/pending.json") == active-archived ]]
	fi
)

direct_v2_expands_to_acknowledged_v3() { direct_v2_expands_to_v3 acknowledged; }
direct_v2_expands_to_idle_v3() { direct_v2_expands_to_v3 idle; }
direct_v2_failure_rolls_back() { direct_v2_expands_to_v3 rollback; }
direct_v2_failed_rollback_recovers() { direct_v2_expands_to_v3 recovery; }
direct_v2_stale_build_input_blocks() { direct_v2_expands_to_v3 stale-build-input; }
direct_v2_partial_helper_publication_rolls_back() { direct_v2_expands_to_v3 partial-helper; }
direct_v3_active_publication_recovers_archive() { direct_v2_expands_to_v3 archive-recovery; }
direct_v3_removes_transactionally() { direct_v2_expands_to_v3 remove; }
direct_v3_failed_remove_reconstructs() { direct_v2_expands_to_v3 remove-rollback; }
direct_v3_remove_uses_restoration_gate() { direct_v2_expands_to_v3 remove-unsupported; }
direct_v2_invalid_evidence_blocks() { direct_v2_expands_to_v3 invalid-evidence; }
direct_v3_pending_ancestry_is_bound() { direct_v2_expands_to_v3 pending-ancestry; }
direct_v3_remove_preserves_unrelated_edits() { direct_v2_expands_to_v3 remove-unrelated-edit; }
direct_v3_defaultim_drift_remains_owned() { direct_v2_expands_to_v3 remove-defaultim-drift; }
direct_v2_indeterminate_write_stops() { direct_v2_expands_to_v3 indeterminate; }
direct_v2_unproved_quiescence_stops() { direct_v2_expands_to_v3 quiesce-failure; }
direct_v2_ambiguous_phase_stops() { direct_v2_expands_to_v3 phase-drift; }
direct_v2_semantic_phase_drift_stops() { direct_v2_expands_to_v3 semantic-phase-drift; }
direct_v2_corrupt_recovery_artifact_stops() { direct_v2_expands_to_v3 corrupt-recovery; }
direct_v2_transitional_helper_quiesces() { direct_v2_expands_to_v3 transitional-quiesce; }
direct_v2_post_pause_failure_restores_autoreload() { direct_v2_expands_to_v3 post-pause-failure; }
direct_v2_durable_phase_interruptions_recover() {
	local phase
	for phase in prior-helper-quiesced managed-group-created managed-group-populated managed-group-selected managed-group-saved units-published manager-reloaded socket-started helper-ready; do
		INPUT_LANGUAGES_TEST_INTERRUPT_PHASE=$phase direct_v2_expands_to_v3 phase-interrupt || return 1
	done
}
direct_v2_stale_helper_plan_blocks() { direct_v2_expands_to_v3 stale-helper; }
direct_v2_stale_controller_plan_blocks() { direct_v2_expands_to_v3 stale-controller; }

run_test direct_v2_expands_to_acknowledged_v3 'healthy direct-v2 installation expands transactionally to acknowledged version 3 and exact no-op'
run_test direct_v2_expands_to_idle_v3 'idle-no-context direct-v2 installation expands transactionally and remains an exact no-op'
run_test direct_v2_failure_rolls_back 'reachable expansion failure restores direct-v2 state and preserves an unrelated Fcitx group'
run_test direct_v2_failed_rollback_recovers 'failed semantic rollback records recovery-required and retries from retained evidence'
run_test direct_v2_stale_build_input_blocks 'confirmed version-3 Apply rechecks build inputs before pending evidence or mutation'
run_test direct_v2_partial_helper_publication_rolls_back 'partial helper publication rolls back every owned edge'
run_test direct_v3_active_publication_recovers_archive 'interrupted active publication archives retained Apply evidence during recovery'
run_test direct_v3_removes_transactionally 'version-3 Remove restores direct and Fcitx ancestry and archives the receipt last'
run_test direct_v3_failed_remove_reconstructs 'failed version-3 Remove reconstructs the installed integration and Remove-start language'
run_test direct_v3_remove_uses_restoration_gate 'receipt-backed Remove uses the narrow Controller restoration gate'
run_test direct_v2_invalid_evidence_blocks 'invalid version-3 lifecycle evidence blocks Apply without mutation'
run_test direct_v3_pending_ancestry_is_bound 'version-3 pending evidence is bound to its validated prior receipt'
run_test direct_v3_remove_preserves_unrelated_edits 'version-3 Remove preserves unrelated group edits made after Apply'
run_test direct_v3_defaultim_drift_remains_owned 'mutable managed-group DefaultIM preserves exact no-op and receipt-backed Remove'
run_test direct_v2_indeterminate_write_stops 'indeterminate Controller write records recovery without another write'
run_test direct_v2_unproved_quiescence_stops 'unproved helper quiescence records recovery before Controller mutation'
run_test direct_v2_ambiguous_phase_stops 'unrecorded durable-state drift records recovery without rollback mutation'
run_test direct_v2_semantic_phase_drift_stops 'semantic phase drift records recovery before direct restoration writes'
run_test direct_v2_corrupt_recovery_artifact_stops 'fresh recovery rejects corrupted retained helper bytes before execution'
run_test direct_v2_transitional_helper_quiesces 'transitional helper units are stopped and reinspected before Controller mutation'
run_test direct_v2_post_pause_failure_restores_autoreload 'post-pause Apply failure restores the original autoreload value'
run_test direct_v2_durable_phase_interruptions_recover 'every durable Fcitx and helper Apply phase supports verified rollback'
run_test direct_v2_stale_helper_plan_blocks 'locked Apply rejects changed helper ownership before pending evidence'
run_test direct_v2_stale_controller_plan_blocks 'locked Apply rejects changed Controller semantics before pending evidence'

finish_tests
