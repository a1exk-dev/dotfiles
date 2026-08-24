readonly BRAVE_POLICY_SOURCE="$REPOSITORY_ROOT/brave/managed-policy.json"
readonly BRAVE_JSON_HELPER="$REPOSITORY_ROOT/lib/dotfiles/brave-json.mjs"
readonly BRAVE_ROOT='/etc/brave'
readonly BRAVE_POLICIES='/etc/brave/policies'
readonly BRAVE_MANAGED='/etc/brave/policies/managed'
readonly BRAVE_POLICY_TARGET='/etc/brave/policies/managed/dotfiles.json'
readonly BRAVE_SOURCE_ID='brave/managed-policy.json'
readonly BRAVE_SCHEMA_VERSION=1
readonly BRAVE_SUPPORTED_OMARCHY_MAJOR=${SUPPORTED_OMARCHY_VERSION:-4}
readonly BRAVE_OMARCHY_BASELINE='4.0.0-1'
readonly BRAVE_PRODUCT_BASELINE='1.93.136'
readonly BRAVE_CHROMIUM_BASELINE='151.0.7922.137'
readonly BRAVE_BROWSER_BASELINE='1:1.93.136-1'
readonly BRAVE_ORIGIN_BASELINE='1:1.93.136-1'
readonly BRAVE_OUTCOME_SUCCESS=0
readonly BRAVE_OUTCOME_DECLINED=10
readonly BRAVE_OUTCOME_UNAVAILABLE=11
readonly BRAVE_INTERNAL_NOTHING_TO_REMOVE=20
readonly BRAVE_OPERATION_CONTEXT_ORDINARY='ordinary'
readonly BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED='recovery-completed'
readonly BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED='recovery-declined'

BRAVE_LOCK_FD=''
BRAVE_STATE_HOME=''
BRAVE_STATE_ROOT=''
BRAVE_STATE_CANONICAL_ROOT=''
BRAVE_ACTIVE_RECEIPT=''
BRAVE_PENDING_RECEIPT=''
BRAVE_RECOVERY_RECEIPT=''
BRAVE_ACTIVE_JSON=''
BRAVE_PENDING_JSON=''
BRAVE_RECOVERY_JSON=''
BRAVE_ACTIVE_DIGEST=''
BRAVE_PENDING_DIGEST=''
BRAVE_RECOVERY_DIGEST=''
BRAVE_STATE_VALID=false
BRAVE_SOURCE_VALID=false
BRAVE_SOURCE_DIGEST=''
BRAVE_SOURCE_RESULT=''
BRAVE_SOURCE_ERROR=''
BRAVE_CONSUMERS_VALID=false
BRAVE_PROVIDERS_VALID=false
BRAVE_CONSUMER_FINGERPRINT=''
BRAVE_SUPPORTED_CONSUMER_COUNT=0
BRAVE_SYSTEM_VALID=false
BRAVE_SYSTEM_FINGERPRINT=''
BRAVE_SYSTEM_CONTENT_FINGERPRINT=''
BRAVE_SYSTEM_SECURED_FINGERPRINT=''
BRAVE_APPLY_SECURED_FINGERPRINT=''
BRAVE_PARENT_FINGERPRINT=''
BRAVE_FOREIGN_FINGERPRINT=''
BRAVE_FOREIGN_SAFE=false
BRAVE_FOREIGN_NON_COLOR_COUNT=0
BRAVE_TARGET_PRESENT=false
BRAVE_TARGET_TYPE='absent'
BRAVE_TARGET_UID=''
BRAVE_TARGET_GID=''
BRAVE_TARGET_MODE=''
BRAVE_TARGET_DIGEST=''
BRAVE_TARGET_READABLE=false
BRAVE_TARGET_POLICY_VALID=false
BRAVE_TARGET_EQUALS_SOURCE=false
BRAVE_MANAGED_PRESENT=false
BRAVE_MANAGED_TYPE='absent'
BRAVE_MANAGED_UID=''
BRAVE_MANAGED_GID=''
BRAVE_MANAGED_MODE=''
BRAVE_MANAGED_REPAIR=false
BRAVE_MANAGED_IDENTITY='absent'
BRAVE_MANAGED_FINGERPRINT=''
BRAVE_PARENT_MISSING=false
BRAVE_PARENT_BLOCKING=false
BRAVE_OMARCHY_VERSION=''
BRAVE_OMARCHY_MAJOR=''
BRAVE_OMARCHY_MISMATCH=false
BRAVE_TRANSACTION_SYSTEM_MUTATED=false
BRAVE_REMOVE_FINAL_ACTION=''
BRAVE_REMOVE_FINAL_EXPECTED_PRESENT=false
BRAVE_REMOVE_FINAL_EXPECTED_UID=''
BRAVE_REMOVE_FINAL_EXPECTED_GID=''
BRAVE_REMOVE_FINAL_EXPECTED_MODE=''
BRAVE_REMOVE_FINAL_NEEDS_HARDENING=false
BRAVE_REMOVE_FINAL_STATE_CLEARED=false
BRAVE_VALIDATED_STAGE_IDENTITY=''
BRAVE_EXPECTED_ACTIVE_JSON=''
BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_ORDINARY

declare -a BRAVE_CONSUMER_LINES=()
declare -a BRAVE_PROVIDER_LINES=()
declare -a BRAVE_VERSION_WARNINGS=()
declare -a BRAVE_PATH_LINES=()
declare -a BRAVE_FOREIGN_LINES=()
declare -a BRAVE_FOREIGN_ERRORS=()
declare -A BRAVE_CANONICAL_KEY_SET=()

# Private adapters are intentionally replaceable after sourcing for isolated tests.
brave_json() {
	node "$BRAVE_JSON_HELPER" "$@"
}

brave_map_system_path() {
	printf '%s\n' "$1"
}

brave_lstat() {
	local actual
	actual=$(brave_map_system_path "$1") || return 2
	stat -c '%F|%u|%g|%a' -- "$actual" 2>/dev/null
}

brave_package_version() {
	local package=$1 metadata name version
	metadata=$(pacman -Q "$package" 2>/dev/null) || return 1
	read -r name version _ <<<"$metadata"
	[[ $name == "$package" && -n $version ]] || return 2
	printf '%s\n' "$version"
}

brave_resolve_provider() {
	command -v "$1"
}

brave_provider_package() {
	pacman -Qqo "$1" 2>/dev/null
}

brave_effective_uid() {
	printf '%s\n' "$EUID"
}

brave_effective_groups() {
	id -G
}

brave_omarchy_version() {
	omarchy version
}

brave_confirm() {
	wizard_confirm "$1"
}

brave_now() {
	date -u +%Y-%m-%dT%H:%M:%SZ
}

brave_new_transaction_id() {
	local stamp
	stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
	printf '%s-%d-%04x%04x\n' "$stamp" "$$" "$RANDOM" "$RANDOM"
}

brave_transaction_id_is_valid() {
	[[ $1 =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9a-f]{8}$ ]]
}

brave_mode_is_valid() {
	[[ $1 =~ ^[0-7]{4}$ ]]
}

brave_mode_without_write_bits() {
	brave_mode_is_valid "$1" || return 1
	printf '%04o\n' "$((8#$1 & 07555))"
}

brave_backup_path_is_valid() {
	local path=$1 transaction=$2 expected_name=$3
	[[ -n $BRAVE_STATE_CANONICAL_ROOT && $path == "$BRAVE_STATE_CANONICAL_ROOT/backups/$transaction/$expected_name" ]]
}

brave_privileged_operation() {
	local operation=$1
	shift
	local transaction stage backup uid gid mode digest expected_identity temporary_mode
	case $operation in
		acquire)
			(($# == 0)) || return 2
			/usr/bin/sudo -v
			;;
		create-managed)
			(($# == 0)) || return 2
			/usr/bin/sudo /usr/bin/install -d -o root -g root -m 0755 -- "$BRAVE_MANAGED"
			;;
		harden-managed)
			(($# == 0)) || return 2
			/usr/bin/sudo /usr/bin/chown 0:0 -- "$BRAVE_MANAGED" &&
				/usr/bin/sudo /usr/bin/chmod 0755 -- "$BRAVE_MANAGED"
			;;
		write-stage)
			(($# == 1)) || return 2
			transaction=$1
			brave_transaction_id_is_valid "$transaction" || return 2
			stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
			# install -T replaces an unprivileged pre-existing file or directory symlink without opening its referent.
			# Unrelated root can mutate any path directly; ordinary external changes are detected by inode and byte checks.
			(
				set -o pipefail
				brave_json emit-no-follow "$BRAVE_POLICY_SOURCE" "$BRAVE_SOURCE_DIGEST" |
					/usr/bin/sudo /usr/bin/install -T -o root -g root -m 0644 -- /dev/stdin "$stage"
			) && brave_validate_stage "$transaction"
			;;
		publish-stage)
			(($# == 2)) || return 2
			transaction=$1 expected_identity=$2
			brave_transaction_id_is_valid "$transaction" || return 2
			[[ $expected_identity =~ ^[0-9]+\|[0-9]+$ ]] || return 2
			stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
			[[ $(brave_validate_stage_file_metadata "$transaction" 0 0 0644) == "$expected_identity" ]] || return 1
			/usr/bin/sudo /usr/bin/mv --no-copy -fT -- "$stage" "$BRAVE_POLICY_TARGET"
			;;
		remove-target)
			(($# == 0)) || return 2
			/usr/bin/sudo /usr/bin/rm -f -- "$BRAVE_POLICY_TARGET"
			;;
		remove-stage)
			(($# == 1)) || return 2
			transaction=$1
			brave_transaction_id_is_valid "$transaction" || return 2
			stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
			/usr/bin/sudo /usr/bin/rm -f -- "$stage"
			;;
		restore-target)
			(($# == 6)) || return 2
			transaction=$1 backup=$2 uid=$3 gid=$4 mode=$5 digest=$6
			brave_transaction_id_is_valid "$transaction" || return 2
			brave_backup_path_is_valid "$backup" "$transaction" dotfiles.json || return 2
			[[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ ]] || return 2
			brave_mode_is_valid "$mode" || return 2
			[[ $digest =~ ^[0-9a-f]{64}$ ]] || return 2
			temporary_mode=$(brave_mode_without_write_bits "$mode") || return 2
			stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
			# Preserve recorded ownership without letting that owner or group alter the stage before publication.
			(
				set -o pipefail
				brave_json emit-no-follow "$backup" "$digest" |
					/usr/bin/sudo /usr/bin/install -T -o "$uid" -g "$gid" -m "$temporary_mode" -- /dev/stdin "$stage"
			) || return 1
			brave_validate_restore_stage "$transaction" "$backup" "$uid" "$gid" "$temporary_mode" "$digest" || return 1
			expected_identity=$BRAVE_VALIDATED_STAGE_IDENTITY
			[[ $(brave_validate_stage_file_metadata "$transaction" "$uid" "$gid" "$temporary_mode") == "$expected_identity" ]] || return 1
			/usr/bin/sudo /usr/bin/mv --no-copy -fT -- "$stage" "$BRAVE_POLICY_TARGET" || return 1
			/usr/bin/sudo /usr/bin/chmod "$mode" -- "$BRAVE_POLICY_TARGET" || return 1
			brave_validate_target_against_backup "$backup" "$uid" "$gid" "$mode" "$digest"
			;;
		restore-managed)
			(($# == 3)) || return 2
			uid=$1 gid=$2 mode=$3
			[[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ ]] || return 2
			brave_mode_is_valid "$mode" || return 2
			/usr/bin/sudo /usr/bin/chown "$uid:$gid" -- "$BRAVE_MANAGED" &&
				/usr/bin/sudo /usr/bin/chmod "$mode" -- "$BRAVE_MANAGED"
			;;
		remove-managed)
			(($# == 0)) || return 2
			/usr/bin/sudo /usr/bin/rmdir -- "$BRAVE_MANAGED"
			;;
		*)
			printf 'Error: unknown internal Brave privileged operation: %s\n' "$operation" >&2
			return 2
			;;
	esac
}

brave_normalize_mode() {
	local mode=$1
	while ((${#mode} < 4)); do mode=0$mode; done
	printf '%s\n' "$mode"
}

brave_parse_metadata() {
	local metadata=$1 prefix=$2 type uid gid mode
	IFS='|' read -r type uid gid mode <<<"$metadata"
	[[ -n $type && $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ && $mode =~ ^[0-7]+$ ]] || return 1
	[[ $type != 'regular empty file' ]] || type='regular file'
	mode=$(brave_normalize_mode "$mode")
	printf -v "${prefix}_TYPE" '%s' "$type"
	printf -v "${prefix}_UID" '%s' "$uid"
	printf -v "${prefix}_GID" '%s' "$gid"
	printf -v "${prefix}_MODE" '%s' "$mode"
}

brave_native_metadata() {
	stat -c '%F|%u|%g|%a' -- "$1" 2>/dev/null
}

brave_file_digest() {
	local actual output
	actual=$(brave_map_system_path "$1") || return 1
	output=$(brave_json digest-no-follow "$actual") || return 1
	jq -r '.digest' <<<"$output"
}

brave_native_digest() {
	local output
	output=$(brave_json digest-no-follow "$1") || return 1
	jq -r '.digest' <<<"$output"
}

brave_files_equal_no_follow() {
	local output
	output=$(brave_json compare-no-follow "$1" "$2") || return 1
	[[ $(jq -r '.ok // false' <<<"$output") == true && $(jq -r '.equal // false' <<<"$output") == true ]]
}

brave_path_present() {
	local actual
	actual=$(brave_map_system_path "$1") || return 1
	[[ -e $actual || -L $actual ]]
}

brave_path_identity() {
	local actual
	actual=$(brave_map_system_path "$1") || return 1
	stat -c '%d|%i|%s|%y|%z' -- "$actual" 2>/dev/null
}

brave_path_inode_identity() {
	local actual
	actual=$(brave_map_system_path "$1") || return 1
	stat -c '%d|%i' -- "$actual" 2>/dev/null
}

brave_native_path_identity() {
	stat -c '%d|%i|%s|%y|%z' -- "$1" 2>/dev/null
}

brave_validate_stage_file_metadata() {
	local transaction=$1 expected_uid=$2 expected_gid=$3 expected_mode=$4 stage actual metadata
	brave_transaction_id_is_valid "$transaction" || return 2
	stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
	metadata=$(brave_lstat "$stage") || return 1
	brave_parse_metadata "$metadata" BRAVE_STAGE_FILE || return 1
	actual=$(brave_map_system_path "$stage") || return 1
	[[ $BRAVE_STAGE_FILE_TYPE == 'regular file' && $BRAVE_STAGE_FILE_UID == "$expected_uid" && \
		$BRAVE_STAGE_FILE_GID == "$expected_gid" && $BRAVE_STAGE_FILE_MODE == "$expected_mode" && ! -L $actual ]] || return 1
	brave_path_inode_identity "$stage"
}

brave_validate_restore_stage() {
	local transaction=$1 backup=$2 expected_uid=$3 expected_gid=$4 expected_mode=$5 expected_digest=$6 stage actual digest identity
	BRAVE_VALIDATED_STAGE_IDENTITY=''
	identity=$(brave_validate_stage_file_metadata "$transaction" "$expected_uid" "$expected_gid" "$expected_mode") || return 1
	stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
	actual=$(brave_map_system_path "$stage") || return 1
	digest=$(brave_file_digest "$stage") || return 1
	[[ $digest == "$expected_digest" ]] || return 1
	brave_files_equal_no_follow "$backup" "$actual" || return 1
	BRAVE_VALIDATED_STAGE_IDENTITY=$identity
}

brave_validate_target_against_backup() {
	local backup=$1 expected_uid=$2 expected_gid=$3 expected_mode=$4 expected_digest=$5 metadata actual digest identity_before identity_after
	metadata=$(brave_lstat "$BRAVE_POLICY_TARGET") || return 1
	brave_parse_metadata "$metadata" BRAVE_RESTORED_TARGET_FILE || return 1
	actual=$(brave_map_system_path "$BRAVE_POLICY_TARGET") || return 1
	[[ $BRAVE_RESTORED_TARGET_FILE_TYPE == 'regular file' && $BRAVE_RESTORED_TARGET_FILE_UID == "$expected_uid" && \
		$BRAVE_RESTORED_TARGET_FILE_GID == "$expected_gid" && $BRAVE_RESTORED_TARGET_FILE_MODE == "$expected_mode" && ! -L $actual ]] || return 1
	identity_before=$(brave_path_identity "$BRAVE_POLICY_TARGET") || return 1
	digest=$(brave_file_digest "$BRAVE_POLICY_TARGET") || return 1
	[[ $digest == "$expected_digest" ]] || return 1
	brave_files_equal_no_follow "$backup" "$actual" || return 1
	identity_after=$(brave_path_identity "$BRAVE_POLICY_TARGET") || return 1
	[[ $identity_after == "$identity_before" ]]
}

brave_directory_identity() {
	local actual
	actual=$(brave_map_system_path "$1") || return 1
	stat -c '%d|%i' -- "$actual" 2>/dev/null
}

brave_initialize_state_paths() {
	BRAVE_STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
	if [[ $BRAVE_STATE_HOME != /* ]]; then
		printf 'Error: Brave policy state requires an absolute XDG state home: %s\n' "$BRAVE_STATE_HOME" >&2
		return 1
	fi
	BRAVE_STATE_ROOT="$BRAVE_STATE_HOME/dotfiles/brave-policy"
	BRAVE_STATE_CANONICAL_ROOT=$(readlink -m -- "$BRAVE_STATE_ROOT") || {
		printf 'Error: could not canonicalize Brave policy state: %s\n' "$BRAVE_STATE_ROOT" >&2
		return 1
	}
	BRAVE_ACTIVE_RECEIPT="$BRAVE_STATE_CANONICAL_ROOT/active.json"
	BRAVE_PENDING_RECEIPT="$BRAVE_STATE_CANONICAL_ROOT/pending.json"
	BRAVE_RECOVERY_RECEIPT="$BRAVE_STATE_CANONICAL_ROOT/recovery-required.json"
}

brave_validate_receipt_file() {
	local kind=$1 file=$2 output metadata type uid gid mode expected_uid
	metadata=$(brave_native_metadata "$file") || {
		printf 'Error: Brave %s receipt is not an inspectable file: %s\n' "$kind" "$file" >&2
		return 1
	}
	brave_parse_metadata "$metadata" BRAVE_RECEIPT || return 1
	type=$BRAVE_RECEIPT_TYPE uid=$BRAVE_RECEIPT_UID gid=$BRAVE_RECEIPT_GID mode=$BRAVE_RECEIPT_MODE
	expected_uid=$(brave_effective_uid) || return 1
	if [[ $type != 'regular file' || $uid != "$expected_uid" || $mode != 0600 || -L $file ]]; then
		printf 'Error: Brave %s receipt must be a regular invoking-user-owned 0600 file: %s (type=%s uid=%s gid=%s mode=%s)\n' \
			"$kind" "$file" "$type" "$uid" "$gid" "$mode" >&2
		return 1
	fi
	if ! output=$(brave_json receipt "$file" "$kind" "$BRAVE_STATE_CANONICAL_ROOT"); then
		printf 'Error: invalid Brave %s receipt %s: %s\n' "$kind" "$file" "$(jq -r '.error // "JSON validation failed"' <<<"$output" 2>/dev/null)" >&2
		return 1
	fi
	printf '%s\n' "$output"
}

brave_inspect_state() {
	BRAVE_STATE_VALID=true
	BRAVE_ACTIVE_JSON='' BRAVE_PENDING_JSON='' BRAVE_RECOVERY_JSON=''
	BRAVE_ACTIVE_DIGEST='' BRAVE_PENDING_DIGEST='' BRAVE_RECOVERY_DIGEST=''
	local metadata canonical output pending_in_recovery expected_uid state_identity
	local active_identity=absent pending_identity=absent recovery_identity=absent
	if [[ ! -e $BRAVE_STATE_ROOT && ! -L $BRAVE_STATE_ROOT ]]; then
		BRAVE_STATE_FINGERPRINT='state:absent'
		return 0
	fi
	metadata=$(brave_native_metadata "$BRAVE_STATE_ROOT") || {
		printf 'Error: could not inspect Brave state directory: %s\n' "$BRAVE_STATE_ROOT" >&2
		BRAVE_STATE_VALID=false
		return 1
	}
	brave_parse_metadata "$metadata" BRAVE_STATE || {
		BRAVE_STATE_VALID=false
		return 1
	}
	expected_uid=$(brave_effective_uid) || return 1
	canonical=$(readlink -f -- "$BRAVE_STATE_ROOT" 2>/dev/null || true)
	if [[ $BRAVE_STATE_TYPE != directory || -L $BRAVE_STATE_ROOT || $canonical != "$BRAVE_STATE_CANONICAL_ROOT" || \
		$BRAVE_STATE_UID != "$expected_uid" || $BRAVE_STATE_MODE != 0700 ]]; then
		printf 'Error: Brave state directory must be a real invoking-user-owned 0700 directory: %s (type=%s uid=%s gid=%s mode=%s)\n' \
			"$BRAVE_STATE_ROOT" "$BRAVE_STATE_TYPE" "$BRAVE_STATE_UID" "$BRAVE_STATE_GID" "$BRAVE_STATE_MODE" >&2
		BRAVE_STATE_VALID=false
		return 1
	fi

	if [[ -e $BRAVE_ACTIVE_RECEIPT || -L $BRAVE_ACTIVE_RECEIPT ]]; then
		if output=$(brave_validate_receipt_file active "$BRAVE_ACTIVE_RECEIPT"); then
			BRAVE_ACTIVE_JSON=$(jq -c '.value' <<<"$output")
			BRAVE_ACTIVE_DIGEST=$(jq -r '.digest' <<<"$output")
			active_identity=$(brave_native_path_identity "$BRAVE_ACTIVE_RECEIPT") || BRAVE_STATE_VALID=false
		else
			BRAVE_STATE_VALID=false
		fi
	fi
	if [[ -e $BRAVE_PENDING_RECEIPT || -L $BRAVE_PENDING_RECEIPT ]]; then
		if output=$(brave_validate_receipt_file pending "$BRAVE_PENDING_RECEIPT"); then
			BRAVE_PENDING_JSON=$(jq -c '.value' <<<"$output")
			BRAVE_PENDING_DIGEST=$(jq -r '.digest' <<<"$output")
			pending_identity=$(brave_native_path_identity "$BRAVE_PENDING_RECEIPT") || BRAVE_STATE_VALID=false
		else
			BRAVE_STATE_VALID=false
		fi
	fi
	if [[ -e $BRAVE_RECOVERY_RECEIPT || -L $BRAVE_RECOVERY_RECEIPT ]]; then
		if output=$(brave_validate_receipt_file recovery-required "$BRAVE_RECOVERY_RECEIPT"); then
			BRAVE_RECOVERY_JSON=$(jq -c '.value' <<<"$output")
			BRAVE_RECOVERY_DIGEST=$(jq -r '.digest' <<<"$output")
			recovery_identity=$(brave_native_path_identity "$BRAVE_RECOVERY_RECEIPT") || BRAVE_STATE_VALID=false
		else
			BRAVE_STATE_VALID=false
		fi
	fi
	if [[ -n $BRAVE_RECOVERY_JSON ]]; then
		if [[ -z $BRAVE_PENDING_JSON ]]; then
			printf 'Error: recovery-required receipt has no retained pending transaction.\n' >&2
			BRAVE_STATE_VALID=false
		else
			pending_in_recovery=$(jq -Sc '.pending' <<<"$BRAVE_RECOVERY_JSON")
			if [[ $pending_in_recovery != "$(jq -Sc . <<<"$BRAVE_PENDING_JSON")" ]]; then
				printf 'Error: recovery-required receipt does not match pending.json.\n' >&2
				BRAVE_STATE_VALID=false
			fi
		fi
	fi
	state_identity=$(brave_native_path_identity "$BRAVE_STATE_ROOT") || state_identity=uninspectable
	BRAVE_STATE_FINGERPRINT=$(printf 'state:%s:%s|active:%s:%s|pending:%s:%s|recovery:%s:%s' \
		"$metadata" "$state_identity" "$BRAVE_ACTIVE_DIGEST" "$active_identity" "$BRAVE_PENDING_DIGEST" "$pending_identity" \
		"$BRAVE_RECOVERY_DIGEST" "$recovery_identity")
	[[ $BRAVE_STATE_VALID == true ]]
}

brave_create_state_root_impl() {
	mkdir -m 0700 -- "$1"
}

brave_create_state_root() {
	brave_create_state_root_impl "$@"
}

brave_prepare_state_root() {
	local metadata canonical expected_uid parent
	umask 077
	parent=${BRAVE_STATE_ROOT%/*}
	mkdir -p -- "$parent" || {
		printf 'Error: could not create Brave state parent: %s\n' "$parent" >&2
		return 1
	}
	if [[ ! -e $BRAVE_STATE_ROOT && ! -L $BRAVE_STATE_ROOT ]]; then
		if ! brave_create_state_root "$BRAVE_STATE_ROOT" && [[ ! -e $BRAVE_STATE_ROOT && ! -L $BRAVE_STATE_ROOT ]]; then
			printf 'Error: could not create Brave state directory: %s\n' "$BRAVE_STATE_ROOT" >&2
			return 1
		fi
	fi
	metadata=$(brave_native_metadata "$BRAVE_STATE_ROOT") || return 1
	brave_parse_metadata "$metadata" BRAVE_STATE_PREPARED || return 1
	canonical=$(readlink -f -- "$BRAVE_STATE_ROOT") || return 1
	expected_uid=$(brave_effective_uid) || return 1
	if [[ $BRAVE_STATE_PREPARED_TYPE != directory || -L $BRAVE_STATE_ROOT || $canonical != "$BRAVE_STATE_CANONICAL_ROOT" || \
		$BRAVE_STATE_PREPARED_UID != "$expected_uid" || $BRAVE_STATE_PREPARED_MODE != 0700 ]]; then
		printf 'Error: Brave state directory failed its safety check without metadata repair.\n' >&2
		return 1
	fi
}

brave_publish_receipt_temporary_impl() {
	mv -fT -- "$1" "$2"
}

brave_publish_receipt_temporary() {
	brave_publish_receipt_temporary_impl "$@"
}

brave_atomic_write_receipt_impl() {
	local kind=$1 destination=$2 json=$3 temporary output expected_digest published
	case $kind:$destination in
		active:"$BRAVE_ACTIVE_RECEIPT"|pending:"$BRAVE_PENDING_RECEIPT"|recovery-required:"$BRAVE_RECOVERY_RECEIPT") ;;
		*) printf 'Error: refused an unexpected Brave receipt destination.\n' >&2; return 2 ;;
	esac
	temporary=$(mktemp "$BRAVE_STATE_CANONICAL_ROOT/.${kind}.XXXXXX") || return 1
	if ! chmod 0600 -- "$temporary" || ! printf '%s\n' "$json" >"$temporary"; then
		rm -f -- "$temporary"
		return 1
	fi
	if ! output=$(brave_json receipt "$temporary" "$kind" "$BRAVE_STATE_CANONICAL_ROOT"); then
		printf 'Error: generated invalid Brave %s receipt: %s\n' "$kind" "$(jq -r '.error // "validation failed"' <<<"$output" 2>/dev/null)" >&2
		rm -f -- "$temporary"
		return 1
	fi
	expected_digest=$(jq -r '.digest' <<<"$output") || { rm -f -- "$temporary"; return 1; }
	if ! brave_publish_receipt_temporary "$temporary" "$destination"; then
		rm -f -- "$temporary"
		return 1
	fi
	if ! published=$(brave_validate_receipt_file "$kind" "$destination") || \
		[[ $(jq -r '.digest' <<<"$published") != "$expected_digest" ]] || \
		[[ $(jq -Sc '.value' <<<"$published") != "$(jq -Sc . <<<"$json")" ]]; then
		printf 'Error: published Brave %s receipt failed exact post-publication validation: %s\n' "$kind" "$destination" >&2
		return 1
	fi
}

brave_atomic_write_receipt() {
	brave_atomic_write_receipt_impl "$@"
}

brave_atomic_restore_active_receipt() {
	local backup=$1 expected_digest=$2 temporary output published
	temporary=$(mktemp "$BRAVE_STATE_CANONICAL_ROOT/.active-restore.XXXXXX") || return 1
	if ! chmod 0600 -- "$temporary" || ! brave_json emit-no-follow "$backup" "$expected_digest" >"$temporary"; then
		rm -f -- "$temporary"
		return 1
	fi
	if ! output=$(brave_json receipt "$temporary" active "$BRAVE_STATE_CANONICAL_ROOT") || \
		[[ $(jq -r '.digest' <<<"$output") != "$expected_digest" ]]; then
		rm -f -- "$temporary"
		return 1
	fi
	if ! brave_publish_receipt_temporary "$temporary" "$BRAVE_ACTIVE_RECEIPT"; then
		rm -f -- "$temporary"
		return 1
	fi
	if ! published=$(brave_validate_receipt_file active "$BRAVE_ACTIVE_RECEIPT") || \
		[[ $(jq -r '.digest' <<<"$published") != "$expected_digest" ]] || \
		! brave_files_equal_no_follow "$backup" "$BRAVE_ACTIVE_RECEIPT"; then
		printf 'Error: restored Brave active receipt failed exact post-publication validation.\n' >&2
		return 1
	fi
}

brave_remove_state_file_impl() {
	rm -f -- "$1"
}

brave_remove_state_file() {
	brave_remove_state_file_impl "$@"
}

brave_copy_backup_impl() {
	brave_json copy-no-follow "$1" "$2"
}

brave_copy_backup() {
	brave_copy_backup_impl "$@"
}

brave_copy_preview_snapshot() {
	brave_copy_backup_impl "$@"
}

brave_validate_backup_copy() {
	local output=$1 destination=$2 expected_digest=$3 metadata expected_uid actual_digest
	[[ $(jq -r '.ok // false' <<<"$output" 2>/dev/null) == true && \
		$(jq -r '.kind // empty' <<<"$output" 2>/dev/null) == no-follow-copy && \
		$(jq -r '.digest // empty' <<<"$output" 2>/dev/null) == "$expected_digest" ]] || return 1
	metadata=$(brave_native_metadata "$destination") || return 1
	brave_parse_metadata "$metadata" BRAVE_BACKUP_COPY || return 1
	expected_uid=$(brave_effective_uid) || return 1
	[[ $BRAVE_BACKUP_COPY_TYPE == 'regular file' && $BRAVE_BACKUP_COPY_UID == "$expected_uid" && \
		$BRAVE_BACKUP_COPY_MODE == 0600 && ! -L $destination ]] || return 1
	actual_digest=$(brave_native_digest "$destination") || return 1
	[[ $actual_digest == "$expected_digest" ]]
}

brave_remove_failed_backup() {
	[[ ! -f $1 || -L $1 ]] || rm -f -- "$1"
}

brave_validate_source_quiet() {
	BRAVE_SOURCE_VALID=false BRAVE_SOURCE_DIGEST='' BRAVE_SOURCE_RESULT='' BRAVE_SOURCE_ERROR=''
	BRAVE_CANONICAL_KEY_SET=()
	local output
	if [[ ! -f $BRAVE_POLICY_SOURCE || -L $BRAVE_POLICY_SOURCE || ! -r $BRAVE_POLICY_SOURCE ]]; then
		BRAVE_SOURCE_ERROR="source is missing or unreadable: $BRAVE_POLICY_SOURCE"
		return 1
	fi
	if ! output=$(brave_json canonical "$BRAVE_POLICY_SOURCE"); then
		BRAVE_SOURCE_ERROR=$(jq -r '.error // "duplicate-aware JSON validation failed"' <<<"$output" 2>/dev/null)
		return 1
	fi
	BRAVE_SOURCE_RESULT=$output
	BRAVE_SOURCE_DIGEST=$(jq -r '.digest' <<<"$output")
	local encoded
	while IFS= read -r encoded; do BRAVE_CANONICAL_KEY_SET["$encoded"]=canonical; done < <(jq -c '.top_level_keys[]' <<<"$output")
	BRAVE_SOURCE_VALID=true
}

validate_brave_policy_source() {
	if (($# != 0)); then
		printf 'Error: validate_brave_policy_source accepts no arguments.\n' >&2
		return 2
	fi
	if brave_validate_source_quiet; then
		printf 'Brave policy source: valid (11 top-level keys, 14 scalar leaves)\n'
		printf 'Brave policy source digest: %s\n' "$BRAVE_SOURCE_DIGEST"
		return 0
	fi
	printf 'Error: invalid Brave policy source: %s\n' "$BRAVE_SOURCE_ERROR" >&2
	return 1
}

brave_inspect_consumers() {
	BRAVE_CONSUMERS_VALID=true BRAVE_PROVIDERS_VALID=true BRAVE_SUPPORTED_CONSUMER_COUNT=0
	BRAVE_CONSUMER_LINES=() BRAVE_PROVIDER_LINES=() BRAVE_VERSION_WARNINGS=()
	local package command label baseline version package_status resolved resolve_status owner owner_status expected_installed
	local fingerprint=''
	for package in brave-bin brave-origin-bin; do
		if [[ $package == brave-bin ]]; then
			command=brave label='Brave Browser' baseline=$BRAVE_BROWSER_BASELINE
		else
			command=brave-origin label='Brave Origin' baseline=$BRAVE_ORIGIN_BASELINE
		fi
		version=''
		if version=$(brave_package_version "$package"); then
			BRAVE_SUPPORTED_CONSUMER_COUNT=$((BRAVE_SUPPORTED_CONSUMER_COUNT + 1))
			BRAVE_CONSUMER_LINES+=("$label: installed package $package $version")
			[[ $version == "$baseline" ]] || BRAVE_VERSION_WARNINGS+=("$package $version differs from validated baseline $baseline")
			expected_installed=true
		else
			package_status=$?
			if ((package_status != 1)); then
				BRAVE_CONSUMER_LINES+=("$label: package inspection failed")
				BRAVE_CONSUMERS_VALID=false
			else
				BRAVE_CONSUMER_LINES+=("$label: package $package not installed")
			fi
			expected_installed=false
		fi

		resolved=''
		if resolved=$(brave_resolve_provider "$command" 2>/dev/null); then
			if [[ $resolved != /* || $resolved == *$'\n'* ]]; then
				BRAVE_PROVIDER_LINES+=("$command: unsupported non-absolute provider $resolved")
				BRAVE_PROVIDERS_VALID=false
				owner='invalid'
			elif owner=$(brave_provider_package "$resolved" 2>/dev/null); then
				if [[ $owner == "$package" && $expected_installed == true && $owner != *$'\n'* ]]; then
					BRAVE_PROVIDER_LINES+=("$command: supported provider $resolved owned by $owner")
				else
					BRAVE_PROVIDER_LINES+=("$command: unsupported provider $resolved owned by ${owner//$'\n'/, }")
					BRAVE_PROVIDERS_VALID=false
				fi
			else
				owner_status=$?
				if ((owner_status == 1)); then
					BRAVE_PROVIDER_LINES+=("$command: unsupported unowned provider $resolved")
				else
					BRAVE_PROVIDER_LINES+=("$command: provider ownership inspection failed for $resolved")
				fi
				BRAVE_PROVIDERS_VALID=false
				owner='unowned'
			fi
		else
			resolve_status=$?
			owner='missing'
			if [[ $expected_installed == true ]]; then
				BRAVE_PROVIDER_LINES+=("$command: missing command for installed $package")
				BRAVE_PROVIDERS_VALID=false
			elif ((resolve_status == 1)); then
				BRAVE_PROVIDER_LINES+=("$command: no provider resolved")
			else
				BRAVE_PROVIDER_LINES+=("$command: provider resolution failed")
				BRAVE_PROVIDERS_VALID=false
			fi
		fi
		printf -v fingerprint '%s%s|%q|%q|%q;' "$fingerprint" "$package" "$version" "$resolved" "$owner"
	done
	BRAVE_CONSUMER_FINGERPRINT=$fingerprint
	[[ $BRAVE_CONSUMERS_VALID == true && $BRAVE_PROVIDERS_VALID == true ]]
}

brave_inspect_omarchy() {
	BRAVE_OMARCHY_VERSION=$(brave_omarchy_version) || {
		printf 'Error: could not inspect the Omarchy version for the Brave plan.\n' >&2
		return 1
	}
	BRAVE_OMARCHY_MAJOR=''
	BRAVE_OMARCHY_MISMATCH=false
	if [[ $BRAVE_OMARCHY_VERSION =~ (^|[^[:digit:]])([[:digit:]]+)([.]|$) ]]; then
		BRAVE_OMARCHY_MAJOR=${BASH_REMATCH[2]}
	fi
	[[ $BRAVE_OMARCHY_MAJOR == "$BRAVE_SUPPORTED_OMARCHY_MAJOR" ]] || BRAVE_OMARCHY_MISMATCH=true
}

brave_mode_value() {
	local mode=${1#0}
	[[ -n $mode ]] || mode=0
	printf '%d\n' "$((8#$mode))"
}

brave_user_owns_writable_file() {
	local uid=$1 mode=$2 invoking_uid mode_value
	invoking_uid=$(brave_effective_uid) || return 1
	mode_value=$(brave_mode_value "$mode") || return 1
	[[ $uid == "$invoking_uid" && $((mode_value & 0200)) -ne 0 ]]
}

brave_scan_foreign_policies() {
	local strict=$1 actual entry name logical metadata identity type uid gid mode output digest parsed_digest keys encoded owner mode_value
	local invoking_uid old_nullglob=false old_dotglob=false
	BRAVE_FOREIGN_LINES=() BRAVE_FOREIGN_ERRORS=() BRAVE_FOREIGN_FINGERPRINT=''
	BRAVE_FOREIGN_SAFE=true BRAVE_FOREIGN_NON_COLOR_COUNT=0
	declare -A key_owners=()
	for encoded in "${!BRAVE_CANONICAL_KEY_SET[@]}"; do key_owners["$encoded"]=canonical; done
	actual=$(brave_map_system_path "$BRAVE_MANAGED") || return 1
	invoking_uid=$(brave_effective_uid) || return 1
	shopt -q nullglob && old_nullglob=true
	shopt -q dotglob && old_dotglob=true
	shopt -s nullglob dotglob
	local LC_ALL=C
	local -a entries=("$actual"/*)
	[[ $old_nullglob == true ]] || shopt -u nullglob
	[[ $old_dotglob == true ]] || shopt -u dotglob
	for entry in "${entries[@]}"; do
		name=${entry#"$actual/"}
		[[ $name != dotfiles.json ]] || continue
		logical="$BRAVE_MANAGED/$name"
		if ! metadata=$(brave_lstat "$logical"); then
			BRAVE_FOREIGN_ERRORS+=("$name: metadata inspection failed")
			BRAVE_FOREIGN_SAFE=false
			continue
		fi
		if ! brave_parse_metadata "$metadata" BRAVE_FOREIGN_META; then
			BRAVE_FOREIGN_ERRORS+=("$name: invalid metadata")
			BRAVE_FOREIGN_SAFE=false
			continue
		fi
		type=$BRAVE_FOREIGN_META_TYPE uid=$BRAVE_FOREIGN_META_UID gid=$BRAVE_FOREIGN_META_GID mode=$BRAVE_FOREIGN_META_MODE
		identity=$(brave_path_identity "$logical" 2>/dev/null || printf uninspectable)
		printf -v BRAVE_FOREIGN_FINGERPRINT '%s%q|%s|%s;' "$BRAVE_FOREIGN_FINGERPRINT" "$name" "$metadata" "$identity"
		if [[ $type != 'regular file' || -L $entry ]]; then
			BRAVE_FOREIGN_ERRORS+=("$name: disallowed $type")
			BRAVE_FOREIGN_SAFE=false
			continue
		fi
		if [[ ! -r $entry ]]; then
			BRAVE_FOREIGN_ERRORS+=("$name: unreadable regular file")
			BRAVE_FOREIGN_SAFE=false
			continue
		fi
		if ! digest=$(brave_file_digest "$logical"); then
			BRAVE_FOREIGN_ERRORS+=("$name: no-follow content digest failed")
			BRAVE_FOREIGN_SAFE=false
			continue
		fi
		BRAVE_FOREIGN_FINGERPRINT+="digest:$digest;"
		if ! output=$(brave_json inventory "$entry"); then
			BRAVE_FOREIGN_ERRORS+=("$name: $(jq -r '.error // "invalid JSON object"' <<<"$output" 2>/dev/null)")
			BRAVE_FOREIGN_SAFE=false
			continue
		fi
		parsed_digest=$(jq -r '.digest' <<<"$output")
		if [[ $parsed_digest != "$digest" ]]; then
			BRAVE_FOREIGN_FINGERPRINT+="parsed-digest:$parsed_digest;"
			BRAVE_FOREIGN_ERRORS+=("$name: changed between no-follow content reads")
			BRAVE_FOREIGN_SAFE=false
			continue
		fi
		keys=$(jq -c '.top_level_keys' <<<"$output")
		BRAVE_FOREIGN_FINGERPRINT+="keys:$keys;"
		BRAVE_FOREIGN_LINES+=("$name: type=regular file owner=$uid:$gid mode=$mode digest=$digest keys=$keys")
		mode_value=$(brave_mode_value "$mode") || return 1
		if [[ $name == color.json ]]; then
			if [[ $uid != "$invoking_uid" || $((mode_value & 0200)) -eq 0 || $((mode_value & 0022)) -ne 0 ]]; then
				BRAVE_FOREIGN_ERRORS+=("color.json: must be invoking-user-owned, owner-writable, and not group/other-writable")
				BRAVE_FOREIGN_SAFE=false
			fi
		else
			BRAVE_FOREIGN_NON_COLOR_COUNT=$((BRAVE_FOREIGN_NON_COLOR_COUNT + 1))
			if [[ $((mode_value & 0022)) -ne 0 ]] || brave_user_owns_writable_file "$uid" "$mode"; then
				BRAVE_FOREIGN_ERRORS+=("$name: unexpected foreign policy is writable by the invoking user or group/other")
				BRAVE_FOREIGN_SAFE=false
			fi
		fi
		while IFS= read -r encoded; do
			if [[ -n ${key_owners[$encoded]+present} ]]; then
				owner=${key_owners[$encoded]}
				BRAVE_FOREIGN_ERRORS+=("$name: top-level key $encoded collides with $owner")
				BRAVE_FOREIGN_SAFE=false
			else
				key_owners["$encoded"]=$name
			fi
		done < <(jq -c '.top_level_keys[]' <<<"$output")
	done
	if [[ $strict == strict && $BRAVE_FOREIGN_SAFE != true ]]; then
		return 1
	fi
	return 0
}

brave_inspect_parent() {
	local logical=$1 label=$2 metadata identity mode_value
	if ! metadata=$(brave_lstat "$logical"); then
		BRAVE_PATH_LINES+=("$label: absent")
		BRAVE_PARENT_MISSING=true
		BRAVE_SYSTEM_FINGERPRINT+="$logical:absent;"
		BRAVE_PARENT_FINGERPRINT+="$logical:absent;"
		return 0
	fi
	if ! brave_parse_metadata "$metadata" BRAVE_PARENT_META; then
		BRAVE_PATH_LINES+=("$label: invalid metadata")
		BRAVE_PARENT_BLOCKING=true
		return 1
	fi
	BRAVE_PATH_LINES+=("$label: type=$BRAVE_PARENT_META_TYPE owner=$BRAVE_PARENT_META_UID:$BRAVE_PARENT_META_GID mode=$BRAVE_PARENT_META_MODE")
	identity=$(brave_directory_identity "$logical" 2>/dev/null || printf uninspectable)
	BRAVE_SYSTEM_FINGERPRINT+="$logical:$metadata:$identity;"
	BRAVE_PARENT_FINGERPRINT+="$logical:$metadata:$identity;"
	mode_value=$(brave_mode_value "$BRAVE_PARENT_META_MODE") || return 1
	if [[ $BRAVE_PARENT_META_TYPE != directory || $BRAVE_PARENT_META_UID != 0 || $((mode_value & 0022)) -ne 0 || $((mode_value & 0001)) -eq 0 ]]; then
		BRAVE_PARENT_BLOCKING=true
		return 1
	fi
}

brave_inspect_system() {
	local foreign_mode=${1-strict} metadata actual managed_identity mode_value target_output
	BRAVE_SYSTEM_VALID=true BRAVE_SYSTEM_FINGERPRINT='' BRAVE_SYSTEM_CONTENT_FINGERPRINT=''
	BRAVE_SYSTEM_SECURED_FINGERPRINT='' BRAVE_APPLY_SECURED_FINGERPRINT='' BRAVE_PARENT_FINGERPRINT=''
	BRAVE_PATH_LINES=() BRAVE_PARENT_MISSING=false BRAVE_PARENT_BLOCKING=false
	BRAVE_MANAGED_PRESENT=false BRAVE_MANAGED_TYPE=absent BRAVE_MANAGED_UID='' BRAVE_MANAGED_GID='' BRAVE_MANAGED_MODE='' BRAVE_MANAGED_REPAIR=false
	BRAVE_MANAGED_IDENTITY=absent BRAVE_MANAGED_FINGERPRINT=''
	BRAVE_TARGET_PRESENT=false BRAVE_TARGET_TYPE=absent BRAVE_TARGET_UID='' BRAVE_TARGET_GID='' BRAVE_TARGET_MODE='' BRAVE_TARGET_DIGEST=''
	BRAVE_TARGET_READABLE=false
	BRAVE_TARGET_POLICY_VALID=false BRAVE_TARGET_EQUALS_SOURCE=false

	brave_inspect_parent "$BRAVE_ROOT" '/etc/brave' || BRAVE_SYSTEM_VALID=false
	brave_inspect_parent "$BRAVE_POLICIES" '/etc/brave/policies' || BRAVE_SYSTEM_VALID=false
	if metadata=$(brave_lstat "$BRAVE_MANAGED"); then
		BRAVE_MANAGED_PRESENT=true
		if ! brave_parse_metadata "$metadata" BRAVE_MANAGED; then
			BRAVE_SYSTEM_VALID=false
		else
			BRAVE_PATH_LINES+=("managed directory: type=$BRAVE_MANAGED_TYPE owner=$BRAVE_MANAGED_UID:$BRAVE_MANAGED_GID mode=$BRAVE_MANAGED_MODE")
			mode_value=$(brave_mode_value "$BRAVE_MANAGED_MODE") || return 1
			actual=$(brave_map_system_path "$BRAVE_MANAGED") || return 1
			if [[ $BRAVE_MANAGED_TYPE != directory || -L $actual || $BRAVE_MANAGED_UID != 0 ]] || (( (mode_value & 0005) != 0005 )); then
				BRAVE_SYSTEM_VALID=false
				BRAVE_PARENT_BLOCKING=true
			elif [[ $BRAVE_MANAGED_GID != 0 || $BRAVE_MANAGED_MODE != 0755 ]]; then
				BRAVE_MANAGED_REPAIR=true
			fi
		fi
	else
		BRAVE_PATH_LINES+=("managed directory: absent")
		metadata=absent
	fi
	managed_identity=absent
	[[ $BRAVE_MANAGED_PRESENT == false ]] || managed_identity=$(brave_directory_identity "$BRAVE_MANAGED" 2>/dev/null || printf uninspectable)
	BRAVE_MANAGED_IDENTITY=$managed_identity
	BRAVE_MANAGED_FINGERPRINT="$BRAVE_MANAGED:$metadata:$managed_identity;"
	BRAVE_SYSTEM_FINGERPRINT+="$BRAVE_MANAGED:$metadata:$managed_identity;"

	if metadata=$(brave_lstat "$BRAVE_POLICY_TARGET"); then
		BRAVE_TARGET_PRESENT=true
		if brave_parse_metadata "$metadata" BRAVE_TARGET; then
			BRAVE_PATH_LINES+=("target: type=$BRAVE_TARGET_TYPE owner=$BRAVE_TARGET_UID:$BRAVE_TARGET_GID mode=$BRAVE_TARGET_MODE")
			if [[ $BRAVE_TARGET_TYPE == 'regular file' ]]; then
				actual=$(brave_map_system_path "$BRAVE_POLICY_TARGET") || return 1
				if BRAVE_TARGET_DIGEST=$(brave_file_digest "$BRAVE_POLICY_TARGET" 2>/dev/null); then
					BRAVE_TARGET_READABLE=true
				else
					BRAVE_TARGET_DIGEST=''
				fi
				if [[ $BRAVE_TARGET_READABLE == true ]] && target_output=$(brave_json canonical "$actual" 2>/dev/null); then
					BRAVE_TARGET_POLICY_VALID=true
					if ((${#BRAVE_CANONICAL_KEY_SET[@]} == 0)); then
						local encoded
						while IFS= read -r encoded; do BRAVE_CANONICAL_KEY_SET["$encoded"]=canonical; done < <(jq -c '.top_level_keys[]' <<<"$target_output")
					fi
				fi
				if [[ $BRAVE_SOURCE_VALID == true && $BRAVE_TARGET_READABLE == true && $BRAVE_TARGET_DIGEST == "$BRAVE_SOURCE_DIGEST" ]] && \
					brave_files_equal_no_follow "$BRAVE_POLICY_SOURCE" "$actual"; then
					BRAVE_TARGET_EQUALS_SOURCE=true
				fi
			fi
		else
			BRAVE_SYSTEM_VALID=false
		fi
	else
		metadata=absent
		BRAVE_PATH_LINES+=("target: absent")
	fi
	local target_identity='absent'
	[[ $BRAVE_TARGET_PRESENT == false ]] || target_identity=$(brave_path_identity "$BRAVE_POLICY_TARGET" 2>/dev/null || printf uninspectable)
	BRAVE_SYSTEM_FINGERPRINT+="$BRAVE_POLICY_TARGET:$metadata:$target_identity:$BRAVE_TARGET_DIGEST;"
	BRAVE_SYSTEM_CONTENT_FINGERPRINT="target:$metadata:$target_identity:$BRAVE_TARGET_DIGEST;"

	if [[ $BRAVE_MANAGED_PRESENT == true && $BRAVE_MANAGED_TYPE == directory ]]; then
		brave_scan_foreign_policies "$foreign_mode" || {
			[[ $foreign_mode == lenient ]] || BRAVE_SYSTEM_VALID=false
		}
	else
		BRAVE_FOREIGN_LINES=() BRAVE_FOREIGN_ERRORS=() BRAVE_FOREIGN_FINGERPRINT=''
		BRAVE_FOREIGN_SAFE=true BRAVE_FOREIGN_NON_COLOR_COUNT=0
	fi
	BRAVE_SYSTEM_FINGERPRINT+="foreign:$BRAVE_FOREIGN_FINGERPRINT"
	BRAVE_SYSTEM_CONTENT_FINGERPRINT+="foreign:$BRAVE_FOREIGN_FINGERPRINT"
	BRAVE_SYSTEM_SECURED_FINGERPRINT="$BRAVE_PARENT_FINGERPRINT$BRAVE_SYSTEM_CONTENT_FINGERPRINT"
	BRAVE_APPLY_SECURED_FINGERPRINT="$BRAVE_PARENT_FINGERPRINT$BRAVE_MANAGED_FINGERPRINT$BRAVE_SYSTEM_CONTENT_FINGERPRINT"
	[[ $BRAVE_PARENT_BLOCKING == false ]] || BRAVE_SYSTEM_VALID=false
	[[ $BRAVE_SYSTEM_VALID == true ]]
}

brave_print_consumers() {
	printf 'Supported consumers:\n'
	printf '  %s\n' "${BRAVE_CONSUMER_LINES[@]}"
	printf 'Command providers (browsers are inspected, never executed):\n'
	printf '  %s\n' "${BRAVE_PROVIDER_LINES[@]}"
	local warning
	for warning in "${BRAVE_VERSION_WARNINGS[@]}"; do printf 'Warning: %s\n' "$warning"; done
}

brave_print_system_report() {
	printf 'System policy paths (no symlinks followed):\n'
	printf '  %s\n' "${BRAVE_PATH_LINES[@]}"
	if [[ $BRAVE_TARGET_PRESENT == true && $BRAVE_TARGET_TYPE == 'regular file' ]]; then
		printf 'Target digest: %s\n' "${BRAVE_TARGET_DIGEST:-unreadable}"
		printf 'Target exact source bytes: %s\n' "$BRAVE_TARGET_EQUALS_SOURCE"
		printf 'Target exact policy shape: %s\n' "$BRAVE_TARGET_POLICY_VALID"
	fi
	printf 'Foreign managed policies:\n'
	if ((${#BRAVE_FOREIGN_LINES[@]} == 0)); then printf '  none\n'; else printf '  %s\n' "${BRAVE_FOREIGN_LINES[@]}"; fi
	local error
	for error in "${BRAVE_FOREIGN_ERRORS[@]}"; do printf 'Collision or foreign-policy safety error: %s\n' "$error"; done
}

brave_print_state_report() {
	printf 'Receipt state root: %s\n' "$BRAVE_STATE_CANONICAL_ROOT"
	if [[ ! -e $BRAVE_STATE_ROOT && ! -L $BRAVE_STATE_ROOT ]]; then
		printf 'Receipt state: absent\n'
	else
		printf 'Active receipt: %s\n' "$([[ -n $BRAVE_ACTIVE_JSON ]] && printf valid || printf absent)"
		printf 'Pending receipt: %s\n' "$([[ -n $BRAVE_PENDING_JSON ]] && printf interrupted-transaction || printf absent)"
		printf 'Recovery-required receipt: %s\n' "$([[ -n $BRAVE_RECOVERY_JSON ]] && printf present || printf absent)"
	fi
	printf 'Trust limit: user-owned receipts are lifecycle evidence for only %s; they are not administrator-grade authority.\n' "$BRAVE_POLICY_TARGET"
}

brave_receipt_owned_target_is_unreadable() {
	[[ $BRAVE_TARGET_PRESENT == true && $BRAVE_TARGET_TYPE == 'regular file' && $BRAVE_TARGET_READABLE != true ]] || return 1
	[[ -n $BRAVE_ACTIVE_JSON ]] && return 0
	[[ -n $BRAVE_PENDING_JSON && $(jq -r '.operation' <<<"$BRAVE_PENDING_JSON") == apply ]]
}

brave_pending_remove_target_is_unowned() {
	[[ $BRAVE_TARGET_PRESENT == true && -z $BRAVE_ACTIVE_JSON && -n $BRAVE_PENDING_JSON ]] || return 1
	[[ $(jq -r '.operation' <<<"$BRAVE_PENDING_JSON") == remove ]]
}

brave_print_target_permission_repair() {
	printf 'Required action: make the receipt-owned target readable by the invoking user, then rerun.\n'
	printf 'Run: /usr/bin/sudo /usr/bin/chmod 0644 -- %s\n' "$BRAVE_POLICY_TARGET"
}

brave_print_interrupted_remove_unowned_collision() {
	printf 'Error: interrupted Brave removal found an unowned target collision: %s\n' "$BRAVE_POLICY_TARGET" >&2
	printf 'pending.json is recovery evidence and does not claim target ownership without a valid active.json.\n' >&2
	printf 'Required action: preserve or move the unowned target manually, then rerun Apply or Remove.\n' >&2
}

brave_report_invalid_state_remove_collision() {
	local operation
	[[ -n $BRAVE_PENDING_JSON && -z $BRAVE_ACTIVE_JSON ]] || return 1
	operation=$(jq -r '.operation' <<<"$BRAVE_PENDING_JSON") || return 1
	[[ $operation == remove ]] || return 1
	brave_validate_source_quiet || true
	brave_inspect_system lenient || true
	brave_pending_remove_target_is_unowned || return 1
	brave_print_interrupted_remove_unowned_collision
}

brave_acquire_lock() {
	local mode=$1 lock_logical='' lock_actual='' metadata
	BRAVE_LOCK_FD=''
	if metadata=$(brave_lstat "$BRAVE_ROOT"); then
		brave_parse_metadata "$metadata" BRAVE_LOCK_ROOT || return 1
		if [[ $BRAVE_LOCK_ROOT_TYPE != directory ]]; then
			printf 'Error: Brave lock ancestor is not a real directory: %s (%s)\n' "$BRAVE_ROOT" "$BRAVE_LOCK_ROOT_TYPE" >&2
			return 1
		fi
	fi
	if metadata=$(brave_lstat "$BRAVE_POLICIES"); then
		brave_parse_metadata "$metadata" BRAVE_LOCK || return 1
		if [[ $BRAVE_LOCK_TYPE != directory ]]; then
			printf 'Error: Brave lock path is not a real directory: %s (%s)\n' "$BRAVE_POLICIES" "$BRAVE_LOCK_TYPE" >&2
			return 1
		fi
		lock_logical=$BRAVE_POLICIES
	elif [[ -e $BRAVE_STATE_ROOT || -L $BRAVE_STATE_ROOT ]]; then
		metadata=$(brave_native_metadata "$BRAVE_STATE_ROOT") || return 1
		brave_parse_metadata "$metadata" BRAVE_LOCK || return 1
		if [[ $BRAVE_LOCK_TYPE != directory || -L $BRAVE_STATE_ROOT ]]; then
			printf 'Error: Brave fallback lock path is not a real directory: %s\n' "$BRAVE_STATE_ROOT" >&2
			return 1
		fi
		lock_actual=$BRAVE_STATE_ROOT
	else
		return 0
	fi
	[[ -n $lock_actual ]] || lock_actual=$(brave_map_system_path "$lock_logical") || return 1
	exec {BRAVE_LOCK_FD}<"$lock_actual" || {
		printf 'Error: could not open Brave lock directory: %s\n' "${lock_logical:-$lock_actual}" >&2
		BRAVE_LOCK_FD=''
		return 1
	}
	if [[ $mode == shared ]]; then
		flock --shared "$BRAVE_LOCK_FD"
	else
		flock --exclusive "$BRAVE_LOCK_FD"
	fi || {
		exec {BRAVE_LOCK_FD}>&-
		BRAVE_LOCK_FD=''
		printf 'Error: could not acquire the Brave %s lock.\n' "$mode" >&2
		return 1
	}
}

brave_release_lock() {
	if [[ -n $BRAVE_LOCK_FD ]]; then
		flock --unlock "$BRAVE_LOCK_FD" || true
		exec {BRAVE_LOCK_FD}>&-
		BRAVE_LOCK_FD=''
	fi
}

brave_status_locked() {
	local healthy=true active_deployed
	brave_validate_source_quiet || healthy=false
	brave_inspect_consumers || healthy=false
	brave_inspect_state || healthy=false
	brave_inspect_system strict || healthy=false

	if [[ $BRAVE_SOURCE_VALID == true ]]; then
		printf 'Brave policy source: valid\nBrave policy source digest: %s\n' "$BRAVE_SOURCE_DIGEST"
	else
		printf 'Brave policy source: invalid (%s)\n' "$BRAVE_SOURCE_ERROR"
	fi
	printf 'Validated evidence baseline: Omarchy %s, Brave %s, Chromium %s, package %s.\n' \
		"$BRAVE_OMARCHY_BASELINE" "$BRAVE_PRODUCT_BASELINE" "$BRAVE_CHROMIUM_BASELINE" "$BRAVE_BROWSER_BASELINE"
	printf 'Supported Omarchy major: %s.\n' "$BRAVE_SUPPORTED_OMARCHY_MAJOR"
	brave_print_consumers
	brave_print_state_report
	brave_print_system_report

	if brave_pending_remove_target_is_unowned; then
		healthy=false
		printf 'Deployment state: interrupted-remove unowned target collision; pending recovery state does not reserve dotfiles.json.\n'
		brave_print_interrupted_remove_unowned_collision
	elif brave_receipt_owned_target_is_unreadable; then
		healthy=false
		printf 'Deployment state: receipt-owned target unavailable; the regular file is unreadable by the invoking user.\n'
		brave_print_target_permission_repair
	elif [[ -n $BRAVE_PENDING_JSON || -n $BRAVE_RECOVERY_JSON ]]; then
		healthy=false
		printf 'Required action: rerun Apply or Remove from Manage Brave policy to reconcile the interrupted transaction.\n'
	elif [[ -z $BRAVE_ACTIVE_JSON && $BRAVE_TARGET_PRESENT == false ]]; then
		if [[ $BRAVE_PARENT_MISSING == true && $BRAVE_SUPPORTED_CONSUMER_COUNT -gt 0 ]]; then
			healthy=false
			printf 'Deployment state: installed-consumer policy path drift; required /etc/brave parents are missing.\n'
			printf 'Required action: repair the browser policy tree, then Apply from Manage Brave policy.\n'
		elif [[ $BRAVE_PARENT_BLOCKING == true || $BRAVE_MANAGED_REPAIR == true || $BRAVE_FOREIGN_SAFE != true ]]; then
			healthy=false
			printf 'Required action: repair the reported policy path before apply.\n'
		else
			printf 'Deployment state: cleanly absent.\n'
			if ((BRAVE_SUPPORTED_CONSUMER_COUNT == 0)); then
				printf 'Available installers: omarchy install browser brave; omarchy install browser brave-origin\n'
			else
				printf 'Required action: Apply from Manage Brave policy.\n'
			fi
		fi
	elif [[ -z $BRAVE_ACTIVE_JSON && $BRAVE_TARGET_PRESENT == true ]]; then
		healthy=false
		printf 'Deployment state: unowned target collision; no valid active receipt reserves dotfiles.json.\n'
		printf 'Required action: preserve or move the unowned file manually before apply.\n'
	elif [[ -n $BRAVE_ACTIVE_JSON && $BRAVE_TARGET_PRESENT == false ]]; then
		healthy=false
		printf 'Deployment state: stale active receipt; the receipt-owned target is missing.\n'
		printf 'Required action: Apply to redeploy or Remove to clear stale ownership.\n'
	else
		active_deployed=$(jq -r '.deployed_digest' <<<"$BRAVE_ACTIVE_JSON")
		if [[ $BRAVE_TARGET_TYPE == 'regular file' && $BRAVE_TARGET_EQUALS_SOURCE == true && $BRAVE_TARGET_POLICY_VALID == true && \
			$BRAVE_TARGET_UID == 0 && $BRAVE_TARGET_GID == 0 && $BRAVE_TARGET_MODE == 0644 && \
			$BRAVE_MANAGED_UID == 0 && $BRAVE_MANAGED_GID == 0 && $BRAVE_MANAGED_MODE == 0755 && \
			$active_deployed == "$BRAVE_SOURCE_DIGEST" && $BRAVE_FOREIGN_SAFE == true ]]; then
			printf 'Deployment state: exact active deployment.\nRequired action: none.\n'
		else
			healthy=false
			printf 'Deployment state: active-target drift.\nRequired action: Apply to repair or Remove to delete the receipt-owned target.\n'
		fi
	fi
	printf 'Scoped color-policy trust: color.json remains user-owned and can change aggregate policy after this inspection.\n'
	[[ $healthy == true ]]
}

brave_policy_status() {
	if (($# != 0)); then
		printf 'Error: brave_policy_status accepts no arguments.\n' >&2
		return 2
	fi
	brave_initialize_state_paths || return 1
	brave_acquire_lock shared || return 1
	local outcome=0
	brave_status_locked || outcome=$?
	brave_release_lock
	return "$outcome"
}

brave_exact_active_match() {
	local active_deployed
	[[ -n $BRAVE_ACTIVE_JSON && $BRAVE_TARGET_PRESENT == true && $BRAVE_TARGET_TYPE == 'regular file' ]] || return 1
	active_deployed=$(jq -r '.deployed_digest' <<<"$BRAVE_ACTIVE_JSON")
	[[ $active_deployed == "$BRAVE_SOURCE_DIGEST" && $BRAVE_TARGET_EQUALS_SOURCE == true && $BRAVE_TARGET_POLICY_VALID == true && \
		$BRAVE_TARGET_UID == 0 && $BRAVE_TARGET_GID == 0 && $BRAVE_TARGET_MODE == 0644 && \
		$BRAVE_MANAGED_UID == 0 && $BRAVE_MANAGED_GID == 0 && $BRAVE_MANAGED_MODE == 0755 && \
		$BRAVE_FOREIGN_SAFE == true ]]
}

brave_print_source_target_diff() {
	local target_actual work desired_snapshot current_snapshot copy_output diff_status outcome=0
	printf 'Complete source-to-target change:\n'
	work=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-brave-diff.XXXXXX") || return 1
	chmod 0700 -- "$work" || { rm -rf -- "$work"; return 1; }
	desired_snapshot="$work/desired.json"
	current_snapshot="$work/current.json"
	if ! copy_output=$(brave_copy_preview_snapshot "$BRAVE_POLICY_SOURCE" "$desired_snapshot") || \
		! brave_validate_backup_copy "$copy_output" "$desired_snapshot" "$BRAVE_SOURCE_DIGEST"; then
		outcome=1
	elif [[ $BRAVE_TARGET_PRESENT == true && $BRAVE_TARGET_TYPE == 'regular file' ]]; then
		target_actual=$(brave_map_system_path "$BRAVE_POLICY_TARGET") || outcome=1
		if ((outcome == 0)); then
			if ! copy_output=$(brave_copy_preview_snapshot "$target_actual" "$current_snapshot") || \
				! brave_validate_backup_copy "$copy_output" "$current_snapshot" "$BRAVE_TARGET_DIGEST"; then
				outcome=1
			elif diff -u --label "$BRAVE_POLICY_TARGET (current)" --label "$BRAVE_SOURCE_ID (desired)" "$current_snapshot" "$desired_snapshot"; then
				:
			else
				diff_status=$?
				((diff_status == 1)) || outcome=$diff_status
			fi
		fi
	elif diff -u --label "$BRAVE_POLICY_TARGET (absent)" --label "$BRAVE_SOURCE_ID (desired)" /dev/null "$desired_snapshot"; then
		:
	else
		diff_status=$?
		((diff_status == 1)) || outcome=$diff_status
	fi
	rm -rf -- "$work" || outcome=1
	return "$outcome"
}

brave_original_managed_json() {
	if [[ -n $BRAVE_ACTIVE_JSON ]]; then
		jq -c '.managed_directory_original' <<<"$BRAVE_ACTIVE_JSON"
	elif [[ $BRAVE_MANAGED_PRESENT == true ]]; then
		jq -cn --argjson uid "$BRAVE_MANAGED_UID" --argjson gid "$BRAVE_MANAGED_GID" --arg mode "$BRAVE_MANAGED_MODE" \
			'{present:true,uid:$uid,gid:$gid,mode:$mode}'
	else
		printf '%s\n' '{"present":false,"uid":null,"gid":null,"mode":null}'
	fi
}

brave_current_managed_json() {
	if [[ $BRAVE_MANAGED_PRESENT == true ]]; then
		jq -cn --argjson uid "$BRAVE_MANAGED_UID" --argjson gid "$BRAVE_MANAGED_GID" --arg mode "$BRAVE_MANAGED_MODE" \
			'{present:true,uid:$uid,gid:$gid,mode:$mode}'
	else
		printf '%s\n' '{"present":false,"uid":null,"gid":null,"mode":null}'
	fi
}

brave_snapshot_pending_backup_parents() {
	local pending=$1 transaction expected_uid backup_root directory metadata canonical identity fingerprint=''
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	expected_uid=$(brave_effective_uid) || return 1
	backup_root="$BRAVE_STATE_CANONICAL_ROOT/backups/$transaction"
	for directory in "$BRAVE_STATE_CANONICAL_ROOT/backups" "$backup_root"; do
		metadata=$(brave_native_metadata "$directory") || return 1
		brave_parse_metadata "$metadata" BRAVE_BACKUP_PARENT || return 1
		canonical=$(readlink -f -- "$directory") || return 1
		[[ $BRAVE_BACKUP_PARENT_TYPE == directory && $BRAVE_BACKUP_PARENT_UID == "$expected_uid" && \
			$BRAVE_BACKUP_PARENT_MODE == 0700 && ! -L $directory && $canonical == "$directory" ]] || return 1
		identity=$(brave_native_path_identity "$directory") || return 1
		fingerprint+="dir:$metadata:$identity;"
	done
	printf '%s' "$fingerprint"
}

brave_lifecycle_original_from_pending() {
	local pending=$1 transaction backup expected output
	if [[ $(jq -r '.prior_active.present' <<<"$pending") != true ]]; then
		printf '%s\n' '{"present":false,"uid":null,"gid":null,"mode":null}'
		return 0
	fi
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	brave_snapshot_pending_backup_parents "$pending" >/dev/null || return 1
	backup=$(jq -r '.prior_active.backup_path' <<<"$pending")
	brave_backup_path_is_valid "$backup" "$transaction" active.json || return 1
	expected=$(jq -r '.prior_active.digest' <<<"$pending")
	[[ -f $backup && ! -L $backup && $(brave_native_digest "$backup") == "$expected" ]] || return 1
	output=$(brave_json receipt "$backup" active "$BRAVE_STATE_CANONICAL_ROOT") || return 1
	[[ $(jq -r '.digest' <<<"$output") == "$expected" ]] || return 1
	jq -c '.value.managed_directory_original' <<<"$output"
}

brave_generate_transaction() {
	local transaction attempt=0
	while ((attempt < 10)); do
		transaction=$(brave_new_transaction_id) || return 1
		if [[ ! -e $BRAVE_STATE_CANONICAL_ROOT/backups/$transaction && ! -L $BRAVE_STATE_CANONICAL_ROOT/backups/$transaction ]]; then
			printf '%s\n' "$transaction"
			return 0
		fi
		attempt=$((attempt + 1))
	done
	printf 'Error: could not allocate a unique Brave transaction identity.\n' >&2
	return 1
}

brave_print_apply_plan() {
	local transaction=$1 original=$2 target_backup="$BRAVE_STATE_CANONICAL_ROOT/backups/$transaction/dotfiles.json"
	local active_backup="$BRAVE_STATE_CANONICAL_ROOT/backups/$transaction/active.json"
	printf 'Plan: apply one shared Brave managed policy\n'
	brave_print_consumers
	printf 'Validated evidence baseline: Brave/Origin %s, Chromium %s, package baseline %s.\n' \
		"$BRAVE_PRODUCT_BASELINE" "$BRAVE_CHROMIUM_BASELINE" "$BRAVE_ORIGIN_BASELINE"
	printf 'Supported Omarchy: %s\nDetected Omarchy: %s\n' "$BRAVE_SUPPORTED_OMARCHY_MAJOR" "$BRAVE_OMARCHY_VERSION"
	[[ $BRAVE_OMARCHY_MISMATCH == false ]] || printf 'Warning: this plan requires consent to continue despite the Omarchy major-version mismatch.\n'
	printf 'Source: %s\nSource digest: %s\nTarget: %s\nTarget digest: %s\n' \
		"$BRAVE_SOURCE_ID" "$BRAVE_SOURCE_DIGEST" "$BRAVE_POLICY_TARGET" "${BRAVE_TARGET_DIGEST:-absent}"
	brave_print_source_target_diff || {
		printf 'Error: complete Brave source-to-target preview failed; confirmation is unavailable.\n' >&2
		return 1
	}
	brave_print_system_report
	printf 'Managed-directory original metadata: %s\n' "$original"
	printf 'Metadata effect: enforce root:root 0755 on %s and root:root 0644 on %s.\n' "$BRAVE_MANAGED" "$BRAVE_POLICY_TARGET"
	printf 'Transaction backup paths: %s; %s\n' "$target_backup" "$active_backup"
	printf 'Receipt paths: %s; %s; %s\n' "$BRAVE_PENDING_RECEIPT" "$BRAVE_ACTIVE_RECEIPT" "$BRAVE_RECOVERY_RECEIPT"
	printf 'Privileged effects after confirmation: /usr/bin/sudo validation; fixed managed-directory create/hardening; fixed same-filesystem stage; ownership/mode setting; atomic publish; verification and bounded rollback.\n'
	if ((BRAVE_SUPPORTED_CONSUMER_COUNT == 2)); then
		printf 'Both Brave Browser and Brave Origin consume this one byte-identical policy and extension requirement.\n'
	fi
	printf 'Extension effect: AdGuard and Bitwarden become required but disableable; policy does not pin toolbar icons.\n'
	printf 'Reload effect: policy may require a user-controlled Reload policies action or browser relaunch; this operation never launches or signals a browser.\n'
	printf 'Trust limit: receipts are user-owned lifecycle evidence for the fixed target, not administrator-grade proof.\n'
	printf 'color.json limit: it remains user-owned and can change aggregate policy after this transaction.\n'
	printf 'Not changed: color.json, other foreign policy, packages, profiles, browser data, Sync, flags, themes, fonts, default-browser state, or Omarchy packaged files.\n'
}

brave_confirmed_snapshot() {
	printf '%s\n%s\n%s\n%s\n' "$BRAVE_SOURCE_DIGEST" "$BRAVE_CONSUMER_FINGERPRINT" "$BRAVE_STATE_FINGERPRINT" "$BRAVE_SYSTEM_FINGERPRINT"
}

brave_reinspect_for_apply() {
	brave_validate_source_quiet || return 1
	brave_inspect_consumers || return 1
	brave_inspect_state || return 1
	brave_inspect_system strict || return 1
}

brave_report_snapshot_changes() {
	local old_source=$1 old_consumers=$2 old_state=$3 old_system=$4 changed=false
	if [[ $BRAVE_SOURCE_DIGEST != "$old_source" ]]; then printf 'Error: Brave source bytes changed after confirmation.\n' >&2; changed=true; fi
	if [[ $BRAVE_CONSUMER_FINGERPRINT != "$old_consumers" ]]; then printf 'Error: Brave consumers or command providers changed after confirmation.\n' >&2; changed=true; fi
	if [[ $BRAVE_STATE_FINGERPRINT != "$old_state" ]]; then printf 'Error: Brave receipts changed after confirmation.\n' >&2; changed=true; fi
	if [[ $BRAVE_SYSTEM_FINGERPRINT != "$old_system" ]]; then printf 'Error: Brave paths, target, metadata, or foreign inventory changed after confirmation.\n' >&2; changed=true; fi
	[[ $changed == false ]]
}

brave_prepare_backups_and_pending() {
	local operation=$1 transaction=$2 original=$3 desired_digest=${4-}
	local backup_root="$BRAVE_STATE_CANONICAL_ROOT/backups/$transaction"
	local target_backup="$backup_root/dotfiles.json" active_backup="$backup_root/active.json"
	local prior_target prior_active target_digest active_digest copy_output pending created stage
	umask 077
	if [[ -e $BRAVE_STATE_CANONICAL_ROOT/backups || -L $BRAVE_STATE_CANONICAL_ROOT/backups ]]; then
		if [[ ! -d $BRAVE_STATE_CANONICAL_ROOT/backups || -L $BRAVE_STATE_CANONICAL_ROOT/backups ]]; then
			printf 'Error: Brave backup root must be a real directory.\n' >&2
			return 1
		fi
	else
		mkdir -- "$BRAVE_STATE_CANONICAL_ROOT/backups" || return 1
	fi
	if [[ -e $backup_root || -L $backup_root ]]; then
		printf 'Error: Brave transaction backup path was occupied after confirmation.\n' >&2
		return 1
	fi
	mkdir -- "$backup_root" || return 1
	chmod 0700 -- "$BRAVE_STATE_CANONICAL_ROOT/backups" "$backup_root" || return 1
	if [[ -L $BRAVE_STATE_CANONICAL_ROOT/backups || -L $backup_root || $(readlink -f -- "$backup_root") != "$backup_root" ]]; then
		printf 'Error: Brave backup path failed containment or no-follow checks.\n' >&2
		return 1
	fi
	if [[ $BRAVE_TARGET_PRESENT == true ]]; then
		local target_actual
		target_actual=$(brave_map_system_path "$BRAVE_POLICY_TARGET") || return 1
		if ! copy_output=$(brave_copy_backup "$target_actual" "$target_backup") || \
			! brave_validate_backup_copy "$copy_output" "$target_backup" "$BRAVE_TARGET_DIGEST"; then
			brave_remove_failed_backup "$target_backup"
			printf 'Error: no-follow Brave target backup verification failed.\n' >&2
			return 1
		fi
		target_digest=$BRAVE_TARGET_DIGEST
		prior_target=$(jq -cn --arg digest "$target_digest" --argjson uid "$BRAVE_TARGET_UID" --argjson gid "$BRAVE_TARGET_GID" \
			--arg mode "$BRAVE_TARGET_MODE" --arg path "$target_backup" \
			'{present:true,digest:$digest,uid:$uid,gid:$gid,mode:$mode,backup_path:$path}')
	else
		prior_target='{"present":false,"digest":null,"uid":null,"gid":null,"mode":null,"backup_path":null}'
	fi
	if [[ -n $BRAVE_ACTIVE_JSON ]]; then
		if ! copy_output=$(brave_copy_backup "$BRAVE_ACTIVE_RECEIPT" "$active_backup") || \
			! brave_validate_backup_copy "$copy_output" "$active_backup" "$BRAVE_ACTIVE_DIGEST"; then
			brave_remove_failed_backup "$active_backup"
			printf 'Error: no-follow Brave active-receipt backup verification failed.\n' >&2
			return 1
		fi
		active_digest=$BRAVE_ACTIVE_DIGEST
		prior_active=$(jq -cn --arg digest "$active_digest" --arg path "$active_backup" '{present:true,digest:$digest,backup_path:$path}')
	else
		prior_active='{"present":false,"digest":null,"backup_path":null}'
	fi
	created=$(brave_now) || return 1
	if [[ $operation == apply ]]; then
		stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
		pending=$(jq -cn --argjson schema "$BRAVE_SCHEMA_VERSION" --arg operation apply --arg transaction "$transaction" --arg created "$created" \
			--arg target "$BRAVE_POLICY_TARGET" --argjson prior_target "$prior_target" --arg desired "$desired_digest" --arg stage "$stage" \
			--argjson original "$original" --argjson prior_active "$prior_active" \
			'{schema_version:$schema,kind:"pending",operation:$operation,transaction_id:$transaction,created_at:$created,target:$target,prior_target:$prior_target,desired_digest:$desired,stage_path:$stage,managed_directory_original:$original,prior_active:$prior_active}')
	else
		pending=$(jq -cn --argjson schema "$BRAVE_SCHEMA_VERSION" --arg operation remove --arg transaction "$transaction" --arg created "$created" \
			--arg target "$BRAVE_POLICY_TARGET" --argjson prior_target "$prior_target" --argjson original "$original" --argjson prior_active "$prior_active" \
			'{schema_version:$schema,kind:"pending",operation:$operation,transaction_id:$transaction,created_at:$created,target:$target,prior_target:$prior_target,desired_digest:null,stage_path:null,managed_directory_original:$original,prior_active:$prior_active}')
	fi
	brave_atomic_write_receipt pending "$BRAVE_PENDING_RECEIPT" "$pending" || {
		printf 'Error: could not publish pending Brave transaction receipt.\n' >&2
		return 1
	}
	BRAVE_PENDING_JSON=$pending
	BRAVE_PENDING_DIGEST=$(brave_native_digest "$BRAVE_PENDING_RECEIPT") || return 1
}

brave_verify_pending_unchanged() {
	local output
	output=$(brave_validate_receipt_file pending "$BRAVE_PENDING_RECEIPT") || return 1
	[[ $(jq -Sc '.value' <<<"$output") == "$(jq -Sc . <<<"$BRAVE_PENDING_JSON")" ]]
}

brave_verify_prior_active_unchanged() {
	local present expected current
	present=$(jq -r '.prior_active.present' <<<"$BRAVE_PENDING_JSON")
	if [[ $present == true ]]; then
		[[ -f $BRAVE_ACTIVE_RECEIPT && ! -L $BRAVE_ACTIVE_RECEIPT ]] || return 1
		expected=$(jq -r '.prior_active.digest' <<<"$BRAVE_PENDING_JSON")
		current=$(brave_native_digest "$BRAVE_ACTIVE_RECEIPT") || return 1
		[[ $current == "$expected" ]]
	else
		[[ ! -e $BRAVE_ACTIVE_RECEIPT && ! -L $BRAVE_ACTIVE_RECEIPT ]]
	fi
}

brave_validate_stage() {
	local transaction=$1 stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage" metadata actual output digest identity
	BRAVE_VALIDATED_STAGE_IDENTITY=''
	metadata=$(brave_lstat "$stage") || return 1
	brave_parse_metadata "$metadata" BRAVE_STAGE || return 1
	[[ $BRAVE_STAGE_TYPE == 'regular file' && $BRAVE_STAGE_UID == 0 && $BRAVE_STAGE_GID == 0 && $BRAVE_STAGE_MODE == 0644 ]] || return 1
	actual=$(brave_map_system_path "$stage") || return 1
	brave_files_equal_no_follow "$BRAVE_POLICY_SOURCE" "$actual" || return 1
	digest=$(brave_file_digest "$stage") || return 1
	[[ $digest == "$BRAVE_SOURCE_DIGEST" ]] || return 1
	output=$(brave_json canonical "$actual") || return 1
	[[ $(jq -r '.digest' <<<"$output") == "$BRAVE_SOURCE_DIGEST" ]] || return 1
	identity=$(brave_validate_stage_file_metadata "$transaction" 0 0 0644) || return 1
	BRAVE_VALIDATED_STAGE_IDENTITY=$identity
}

brave_activate_receipt() {
	local transaction=$1 original=$2 activated active
	BRAVE_EXPECTED_ACTIVE_JSON=''
	activated=$(brave_now) || return 1
	active=$(jq -cn --argjson schema "$BRAVE_SCHEMA_VERSION" --arg target "$BRAVE_POLICY_TARGET" --arg source "$BRAVE_SOURCE_ID" \
		--arg digest "$BRAVE_SOURCE_DIGEST" --arg transaction "$transaction" --arg activated "$activated" --argjson original "$original" \
		'{schema_version:$schema,kind:"active",target:$target,source:$source,deployed_digest:$digest,transaction_id:$transaction,activated_at:$activated,managed_directory_original:$original}')
	brave_atomic_write_receipt active "$BRAVE_ACTIVE_RECEIPT" "$active" || return 1
	BRAVE_EXPECTED_ACTIVE_JSON=$active
}

brave_verify_activated_receipt() {
	local output
	[[ -n $BRAVE_EXPECTED_ACTIVE_JSON ]] || return 1
	output=$(brave_validate_receipt_file active "$BRAVE_ACTIVE_RECEIPT") || return 1
	[[ $(jq -Sc '.value' <<<"$output") == "$(jq -Sc . <<<"$BRAVE_EXPECTED_ACTIVE_JSON")" ]]
}

brave_write_recovery_required() {
	local step=$1 pending=$2 transaction created recovery
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	created=$(brave_now) || return 1
	recovery=$(jq -cn --argjson schema "$BRAVE_SCHEMA_VERSION" --arg transaction "$transaction" --arg created "$created" --arg step "$step" --argjson pending "$pending" \
		'{schema_version:$schema,kind:"recovery-required",transaction_id:$transaction,created_at:$created,failed_step:$step,pending:$pending}')
	brave_atomic_write_receipt recovery-required "$BRAVE_RECOVERY_RECEIPT" "$recovery"
}

brave_write_remove_recovery_required() {
	local step=$1 pending=$2 output
	if [[ ! -f $BRAVE_PENDING_RECEIPT || -L $BRAVE_PENDING_RECEIPT ]] || \
		! output=$(brave_validate_receipt_file pending "$BRAVE_PENDING_RECEIPT") || \
		[[ $(jq -Sc '.value' <<<"$output") != "$(jq -Sc . <<<"$pending")" ]]; then
		printf 'Error: could not retain a coherent pending receipt for Brave removal recovery; transaction backups remain available for manual repair.\n' >&2
		return 1
	fi
	brave_write_recovery_required "$step" "$pending"
}

brave_restore_active_from_pending() {
	local pending=$1 present backup digest output
	present=$(jq -r '.prior_active.present' <<<"$pending")
	if [[ $present == true ]]; then
		backup=$(jq -r '.prior_active.backup_path' <<<"$pending")
		digest=$(jq -r '.prior_active.digest' <<<"$pending")
		[[ -f $backup && ! -L $backup && $(brave_native_digest "$backup") == "$digest" ]] || return 1
		output=$(brave_json receipt "$backup" active "$BRAVE_STATE_CANONICAL_ROOT") || return 1
		[[ $(jq -r '.digest' <<<"$output") == "$digest" ]] || return 1
		brave_atomic_restore_active_receipt "$backup" "$digest"
	else
		brave_remove_state_file "$BRAVE_ACTIVE_RECEIPT"
	fi
}

brave_restore_prior_system() {
	local pending=$1 transaction prior_present original_present backup digest uid gid mode target_actual stage
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	prior_present=$(jq -r '.prior_target.present' <<<"$pending")
	stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
	if brave_path_present "$stage"; then
		brave_privileged_operation remove-stage "$transaction" || return 1
	fi
	if [[ $prior_present == true ]]; then
		backup=$(jq -r '.prior_target.backup_path' <<<"$pending")
		digest=$(jq -r '.prior_target.digest' <<<"$pending")
		uid=$(jq -r '.prior_target.uid' <<<"$pending")
		gid=$(jq -r '.prior_target.gid' <<<"$pending")
		mode=$(jq -r '.prior_target.mode' <<<"$pending")
		[[ -f $backup && ! -L $backup && $digest == "$(brave_native_digest "$backup" 2>/dev/null)" ]] || return 1
		if ! brave_validate_target_against_backup "$backup" "$uid" "$gid" "$mode" "$digest"; then
			# Never recreate a removed browser policy tree merely to repair user-state bookkeeping.
			brave_path_present "$BRAVE_MANAGED" || return 1
			brave_privileged_operation restore-target "$transaction" "$backup" "$uid" "$gid" "$mode" "$digest" || return 1
		fi
	else
		if brave_path_present "$BRAVE_POLICY_TARGET"; then
			brave_privileged_operation remove-target || return 1
		fi
	fi
	original_present=$(jq -r '.managed_directory_original.present' <<<"$pending")
	if [[ $original_present == true ]]; then
		if brave_path_present "$BRAVE_MANAGED"; then
			uid=$(jq -r '.managed_directory_original.uid' <<<"$pending")
			gid=$(jq -r '.managed_directory_original.gid' <<<"$pending")
			mode=$(jq -r '.managed_directory_original.mode' <<<"$pending")
			brave_privileged_operation restore-managed "$uid" "$gid" "$mode" || return 1
		else
			return 1
		fi
	else
		if brave_path_present "$BRAVE_MANAGED"; then
			local managed_actual
			managed_actual=$(brave_map_system_path "$BRAVE_MANAGED") || return 1
			if [[ -z $(command find "$managed_actual" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
				brave_privileged_operation remove-managed || return 1
			else
				return 1
			fi
		fi
	fi
	brave_restore_active_from_pending "$pending"
}

brave_verify_prior_restored() {
	local pending=$1 prior_present digest metadata original_present uid gid mode backup actual
	prior_present=$(jq -r '.prior_target.present' <<<"$pending")
	if [[ $prior_present == true ]]; then
		metadata=$(brave_lstat "$BRAVE_POLICY_TARGET") || return 1
		brave_parse_metadata "$metadata" BRAVE_RESTORED_TARGET || return 1
		digest=$(brave_file_digest "$BRAVE_POLICY_TARGET") || return 1
		backup=$(jq -r '.prior_target.backup_path' <<<"$pending")
		actual=$(brave_map_system_path "$BRAVE_POLICY_TARGET") || return 1
		[[ $BRAVE_RESTORED_TARGET_TYPE == 'regular file' && $digest == "$(jq -r '.prior_target.digest' <<<"$pending")" && \
			$BRAVE_RESTORED_TARGET_UID == "$(jq -r '.prior_target.uid' <<<"$pending")" && \
			$BRAVE_RESTORED_TARGET_GID == "$(jq -r '.prior_target.gid' <<<"$pending")" && \
			$BRAVE_RESTORED_TARGET_MODE == "$(jq -r '.prior_target.mode' <<<"$pending")" ]] || return 1
		brave_files_equal_no_follow "$backup" "$actual" || return 1
	else
		brave_path_present "$BRAVE_POLICY_TARGET" && return 1
	fi
	original_present=$(jq -r '.managed_directory_original.present' <<<"$pending")
	if [[ $original_present == true ]]; then
		metadata=$(brave_lstat "$BRAVE_MANAGED") || return 1
		brave_parse_metadata "$metadata" BRAVE_RESTORED_MANAGED || return 1
		uid=$(jq -r '.managed_directory_original.uid' <<<"$pending")
		gid=$(jq -r '.managed_directory_original.gid' <<<"$pending")
		mode=$(jq -r '.managed_directory_original.mode' <<<"$pending")
		[[ $BRAVE_RESTORED_MANAGED_TYPE == directory && $BRAVE_RESTORED_MANAGED_UID == "$uid" && \
			$BRAVE_RESTORED_MANAGED_GID == "$gid" && $BRAVE_RESTORED_MANAGED_MODE == "$mode" ]] || return 1
	else
		brave_path_present "$BRAVE_MANAGED" && return 1
	fi
	local prior_active_present current_digest
	prior_active_present=$(jq -r '.prior_active.present' <<<"$pending")
	if [[ $prior_active_present == true ]]; then
		[[ -f $BRAVE_ACTIVE_RECEIPT && ! -L $BRAVE_ACTIVE_RECEIPT ]] || return 1
		current_digest=$(brave_native_digest "$BRAVE_ACTIVE_RECEIPT") || return 1
		[[ $current_digest == "$(jq -r '.prior_active.digest' <<<"$pending")" ]] || return 1
	else
		[[ ! -e $BRAVE_ACTIVE_RECEIPT && ! -L $BRAVE_ACTIVE_RECEIPT ]] || return 1
	fi
}

brave_rollback_transaction() {
	local step=$1 pending=$2 expected_parent expected_foreign expected_backups
	printf 'Transaction failure: %s; restoring the exact prior Brave state.\n' "$step" >&2
	if ! brave_inspect_system lenient; then
		printf 'Error: Brave rollback preflight could not inspect the failed transaction state.\n' >&2
		brave_write_recovery_required "$step" "$pending" || true
		return 1
	fi
	expected_parent=$BRAVE_PARENT_FINGERPRINT
	expected_foreign=$BRAVE_FOREIGN_FINGERPRINT
	expected_backups=$(brave_snapshot_recovery_backups "$pending") || {
		printf 'Error: Brave rollback backup validation failed.\n' >&2
		brave_write_recovery_required "$step" "$pending" || true
		return 1
	}
	if brave_restore_prior_system "$pending" && \
		brave_verify_interrupted_restore_postconditions "$pending" "$expected_parent" "$expected_foreign" "$expected_backups"; then
		brave_remove_state_file "$BRAVE_PENDING_RECEIPT" || return 1
		brave_remove_state_file "$BRAVE_RECOVERY_RECEIPT" || true
		printf 'Rollback verified. Transaction backup retained: %s/backups/%s\n' "$BRAVE_STATE_CANONICAL_ROOT" "$(jq -r '.transaction_id' <<<"$pending")" >&2
		return 0
	fi
	printf 'Error: Brave rollback failed at %s; pending transaction and backups were retained.\n' "$step" >&2
	brave_write_recovery_required "$step" "$pending" || printf 'Error: could not write recovery-required receipt; pending.json remains authoritative recovery evidence.\n' >&2
	return 1
}

brave_finish_apply_transaction() {
	local transaction=$1 original=$2 confirmed_source=$3 confirmed_consumers=$4 confirmed_content=$5 confirmed_parent=$6 confirmed_managed_identity=$7
	local managed_existed=$BRAVE_MANAGED_PRESENT secured_apply secured_managed
	BRAVE_TRANSACTION_SYSTEM_MUTATED=false
	if [[ $BRAVE_MANAGED_PRESENT == false ]]; then
		BRAVE_TRANSACTION_SYSTEM_MUTATED=true
		brave_privileged_operation create-managed || return 1
	elif [[ $BRAVE_MANAGED_UID != 0 || $BRAVE_MANAGED_GID != 0 || $BRAVE_MANAGED_MODE != 0755 ]]; then
		BRAVE_TRANSACTION_SYSTEM_MUTATED=true
		brave_privileged_operation harden-managed || return 1
	fi
	brave_validate_source_quiet && brave_inspect_consumers && brave_inspect_system strict && brave_verify_pending_unchanged && brave_verify_prior_active_unchanged || return 1
	if [[ $BRAVE_SOURCE_DIGEST != "$confirmed_source" || $BRAVE_CONSUMER_FINGERPRINT != "$confirmed_consumers" || \
		$BRAVE_PARENT_FINGERPRINT != "$confirmed_parent" || $BRAVE_SYSTEM_CONTENT_FINGERPRINT != "$confirmed_content" || \
		$BRAVE_MANAGED_UID != 0 || $BRAVE_MANAGED_GID != 0 || $BRAVE_MANAGED_MODE != 0755 || \
		( $managed_existed == true && $BRAVE_MANAGED_IDENTITY != "$confirmed_managed_identity" ) ]]; then
		printf 'Error: confirmed Brave state changed while securing the managed directory.\n' >&2
		return 1
	fi
	secured_apply=$BRAVE_APPLY_SECURED_FINGERPRINT
	secured_managed=$BRAVE_MANAGED_FINGERPRINT
	BRAVE_TRANSACTION_SYSTEM_MUTATED=true
	brave_privileged_operation write-stage "$transaction" || return 1
	brave_validate_stage "$transaction" || {
		printf 'Error: Brave stage failed byte, metadata, digest, or policy validation.\n' >&2
		return 1
	}
	brave_validate_source_quiet && brave_inspect_consumers && brave_inspect_system strict && brave_verify_pending_unchanged && brave_verify_prior_active_unchanged || return 1
	if [[ $BRAVE_SOURCE_DIGEST != "$confirmed_source" || $BRAVE_CONSUMER_FINGERPRINT != "$confirmed_consumers" || \
		$BRAVE_APPLY_SECURED_FINGERPRINT != "$secured_apply" ]]; then
		printf 'Error: confirmed Brave state changed before atomic publication.\n' >&2
		return 1
	fi
	BRAVE_TRANSACTION_SYSTEM_MUTATED=true
	brave_privileged_operation publish-stage "$transaction" "$BRAVE_VALIDATED_STAGE_IDENTITY" || return 1
	brave_validate_source_quiet && brave_inspect_consumers && brave_inspect_system strict && brave_verify_pending_unchanged && brave_verify_prior_active_unchanged || return 1
	if [[ $BRAVE_SOURCE_DIGEST != "$confirmed_source" || $BRAVE_CONSUMER_FINGERPRINT != "$confirmed_consumers" || \
		$BRAVE_TARGET_EQUALS_SOURCE != true || $BRAVE_TARGET_POLICY_VALID != true || $BRAVE_TARGET_UID != 0 || $BRAVE_TARGET_GID != 0 || \
		$BRAVE_TARGET_MODE != 0644 || $BRAVE_MANAGED_UID != 0 || $BRAVE_MANAGED_GID != 0 || $BRAVE_MANAGED_MODE != 0755 || \
		$BRAVE_MANAGED_FINGERPRINT != "$secured_managed" || $BRAVE_PARENT_FINGERPRINT != "$confirmed_parent" || \
		$BRAVE_FOREIGN_FINGERPRINT != "${confirmed_content#*foreign:}" ]]; then
		printf 'Error: Brave publication postconditions failed.\n' >&2
		return 1
	fi
	brave_activate_receipt "$transaction" "$original" || return 1
	if brave_path_present "$BRAVE_POLICIES/.dotfiles-$transaction.stage"; then
		brave_privileged_operation remove-stage "$transaction" || return 1
	fi
	brave_verify_activated_receipt && brave_verify_pending_unchanged || return 1
	if ! brave_remove_state_file "$BRAVE_PENDING_RECEIPT"; then
		printf 'Error: policy is active but pending receipt cleanup failed; rerun Apply to reconcile it.\n' >&2
		return 2
	fi
	brave_remove_state_file "$BRAVE_RECOVERY_RECEIPT" || true
	printf 'Applied and verified shared Brave policy: %s\n' "$BRAVE_POLICY_TARGET"
	printf 'Backup retained: %s/backups/%s\n' "$BRAVE_STATE_CANONICAL_ROOT" "$transaction"
}

brave_apply_preflight() {
	local failed=false
	if ! brave_validate_source_quiet; then printf 'Error: invalid Brave policy source: %s\n' "$BRAVE_SOURCE_ERROR" >&2; failed=true; fi
	brave_inspect_consumers || failed=true
	brave_inspect_state || failed=true
	brave_inspect_system strict || failed=true
	brave_print_consumers
	brave_print_state_report
	brave_print_system_report
	if [[ $BRAVE_PROVIDERS_VALID != true || $BRAVE_CONSUMERS_VALID != true ]]; then failed=true; fi
	if [[ $BRAVE_PARENT_MISSING == true ]]; then
		printf 'Error: /etc/brave and /etc/brave/policies must already exist as safe real directories.\n' >&2
		failed=true
	fi
	if [[ -z $BRAVE_ACTIVE_JSON && $BRAVE_TARGET_PRESENT == true ]]; then
		printf 'Error: pre-existing dotfiles.json is unowned because no valid active receipt reserves it.\n' >&2
		failed=true
	fi
	if [[ -n $BRAVE_ACTIVE_JSON && $BRAVE_TARGET_PRESENT == true && $BRAVE_TARGET_TYPE != 'regular file' ]]; then
		printf 'Error: receipt-owned target drift is not a regular file and cannot be repaired safely.\n' >&2
		failed=true
	fi
	if brave_receipt_owned_target_is_unreadable; then
		printf 'Error: receipt-owned target is unavailable for safe Apply because it is unreadable by the invoking user.\n' >&2
		brave_print_target_permission_repair
		failed=true
	fi
	[[ $failed == false ]]
}

brave_interrupted_apply_is_complete() {
	local desired active
	[[ -n $BRAVE_PENDING_JSON ]] || return 1
	desired=$(jq -r '.desired_digest' <<<"$BRAVE_PENDING_JSON")
	[[ -n $BRAVE_ACTIVE_JSON ]] || return 1
	active=$(jq -r '.deployed_digest' <<<"$BRAVE_ACTIVE_JSON")
	[[ $BRAVE_TARGET_PRESENT == true && $BRAVE_TARGET_TYPE == 'regular file' && $BRAVE_TARGET_DIGEST == "$desired" && \
		$active == "$desired" && $BRAVE_TARGET_POLICY_VALID == true && $BRAVE_TARGET_UID == 0 && $BRAVE_TARGET_GID == 0 && \
		$BRAVE_TARGET_MODE == 0644 && $BRAVE_MANAGED_UID == 0 && $BRAVE_MANAGED_GID == 0 && $BRAVE_MANAGED_MODE == 0755 && \
		$BRAVE_FOREIGN_SAFE == true ]]
}

brave_verify_completed_apply_recovery_snapshot() {
	local expected_state=$1 expected_system=$2
	brave_inspect_state || return 1
	[[ $BRAVE_STATE_FINGERPRINT == "$expected_state" ]] || return 1
	brave_inspect_system strict || return 1
	[[ $BRAVE_SYSTEM_FINGERPRINT == "$expected_system" ]] || return 1
	brave_interrupted_apply_is_complete
}

brave_pending_prior_is_intact() {
	local pending=$1 prior_present prior_active original_present
	prior_present=$(jq -r '.prior_target.present' <<<"$pending")
	if [[ $prior_present == true ]]; then
		[[ $BRAVE_TARGET_PRESENT == true && $BRAVE_TARGET_TYPE == 'regular file' && $BRAVE_TARGET_DIGEST == "$(jq -r '.prior_target.digest' <<<"$pending")" && \
			$BRAVE_TARGET_UID == "$(jq -r '.prior_target.uid' <<<"$pending")" && $BRAVE_TARGET_GID == "$(jq -r '.prior_target.gid' <<<"$pending")" && \
			$BRAVE_TARGET_MODE == "$(jq -r '.prior_target.mode' <<<"$pending")" ]] || return 1
	else
		[[ $BRAVE_TARGET_PRESENT == false ]] || return 1
	fi
	prior_active=$(jq -r '.prior_active.present' <<<"$pending")
	if [[ $prior_active == true ]]; then
		[[ -f $BRAVE_ACTIVE_RECEIPT && ! -L $BRAVE_ACTIVE_RECEIPT && $(brave_native_digest "$BRAVE_ACTIVE_RECEIPT") == "$(jq -r '.prior_active.digest' <<<"$pending")" ]] || return 1
	else
		[[ ! -e $BRAVE_ACTIVE_RECEIPT && ! -L $BRAVE_ACTIVE_RECEIPT ]] || return 1
	fi
	original_present=$(jq -r '.managed_directory_original.present' <<<"$pending")
	if [[ $original_present == true ]]; then
		[[ $BRAVE_MANAGED_PRESENT == true && $BRAVE_MANAGED_TYPE == directory && \
			$BRAVE_MANAGED_UID == "$(jq -r '.managed_directory_original.uid' <<<"$pending")" && \
			$BRAVE_MANAGED_GID == "$(jq -r '.managed_directory_original.gid' <<<"$pending")" && \
			$BRAVE_MANAGED_MODE == "$(jq -r '.managed_directory_original.mode' <<<"$pending")" ]] || return 1
	else
		[[ $BRAVE_MANAGED_PRESENT == false ]] || return 1
	fi
}

brave_snapshot_recovery_stage() {
	local pending=$1 operation transaction stage actual metadata identity digest
	operation=$(jq -r '.operation' <<<"$pending")
	if [[ $operation != apply ]]; then
		printf 'stage:none'
		return 0
	fi
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	stage="$BRAVE_POLICIES/.dotfiles-$transaction.stage"
	if ! brave_path_present "$stage"; then
		printf 'stage:absent'
		return 0
	fi
	metadata=$(brave_lstat "$stage") || return 1
	brave_parse_metadata "$metadata" BRAVE_RECOVERY_STAGE || return 1
	identity=$(brave_path_identity "$stage") || return 1
	actual=$(brave_map_system_path "$stage") || return 1
	digest=unreadable
	if [[ $BRAVE_RECOVERY_STAGE_TYPE == 'regular file' && ! -L $actual ]]; then
		digest=$(brave_file_digest "$stage") || return 1
	fi
	printf 'stage:%s:%s:%s' "$metadata" "$identity" "$digest"
}

brave_snapshot_recovery_backups() {
	local pending=$1 transaction target_present active_present expected_uid path expected metadata identity digest output
	local fingerprint=''
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	target_present=$(jq -r '.prior_target.present' <<<"$pending")
	active_present=$(jq -r '.prior_active.present' <<<"$pending")
	expected_uid=$(brave_effective_uid) || return 1
	if [[ $target_present == true || $active_present == true ]]; then
		fingerprint=$(brave_snapshot_pending_backup_parents "$pending") || return 1
	fi
	if [[ $target_present == true ]]; then
		path=$(jq -r '.prior_target.backup_path' <<<"$pending")
		expected=$(jq -r '.prior_target.digest' <<<"$pending")
		brave_backup_path_is_valid "$path" "$transaction" dotfiles.json || return 1
		metadata=$(brave_native_metadata "$path") || return 1
		brave_parse_metadata "$metadata" BRAVE_RECOVERY_TARGET_BACKUP || return 1
		[[ $BRAVE_RECOVERY_TARGET_BACKUP_TYPE == 'regular file' && $BRAVE_RECOVERY_TARGET_BACKUP_UID == "$expected_uid" && \
			$BRAVE_RECOVERY_TARGET_BACKUP_MODE == 0600 && ! -L $path ]] || return 1
		digest=$(brave_native_digest "$path") || return 1
		[[ $digest == "$expected" ]] || return 1
		identity=$(brave_native_path_identity "$path") || return 1
		fingerprint+="target:$metadata:$identity:$digest;"
	else
		fingerprint+='target:absent;'
	fi
	if [[ $active_present == true ]]; then
		path=$(jq -r '.prior_active.backup_path' <<<"$pending")
		expected=$(jq -r '.prior_active.digest' <<<"$pending")
		brave_backup_path_is_valid "$path" "$transaction" active.json || return 1
		output=$(brave_validate_receipt_file active "$path") || return 1
		digest=$(jq -r '.digest' <<<"$output")
		[[ $digest == "$expected" ]] || return 1
		metadata=$(brave_native_metadata "$path") || return 1
		identity=$(brave_native_path_identity "$path") || return 1
		fingerprint+="active:$metadata:$identity:$digest;"
	else
		fingerprint+='active:absent;'
	fi
	printf '%s' "$fingerprint"
}

brave_verify_interrupted_restore_snapshot() {
	local pending=$1 expected_state=$2 expected_system=$3 expected_stage=$4 expected_backups=$5 current
	brave_inspect_state || return 1
	[[ $BRAVE_STATE_FINGERPRINT == "$expected_state" && $(jq -Sc . <<<"$BRAVE_PENDING_JSON") == "$(jq -Sc . <<<"$pending")" ]] || return 1
	brave_inspect_system lenient || return 1
	[[ $BRAVE_SYSTEM_FINGERPRINT == "$expected_system" ]] || return 1
	current=$(brave_snapshot_recovery_stage "$pending") || return 1
	[[ $current == "$expected_stage" ]] || return 1
	current=$(brave_snapshot_recovery_backups "$pending") || return 1
	[[ $current == "$expected_backups" ]]
}

brave_verify_interrupted_restore_postconditions() {
	local pending=$1 expected_parent=$2 expected_foreign=$3 expected_backups=$4 current stage
	brave_verify_prior_restored "$pending" || return 1
	brave_verify_pending_unchanged || return 1
	brave_inspect_system lenient || return 1
	[[ $BRAVE_PARENT_FINGERPRINT == "$expected_parent" && $BRAVE_FOREIGN_FINGERPRINT == "$expected_foreign" ]] || return 1
	stage=$(brave_snapshot_recovery_stage "$pending") || return 1
	[[ $stage == stage:absent || $stage == stage:none ]] || return 1
	current=$(brave_snapshot_recovery_backups "$pending") || return 1
	[[ $current == "$expected_backups" ]]
}

brave_finalize_interrupted_remove() {
	local pending=$1 expected_foreign=$2 privilege_ready=${3-false} approved_action=${4-} approved_hardening=${5-}
	# Missing system parents are intentionally not recreated during stale bookkeeping cleanup.
	brave_finalize_removed_transaction "$pending" "$expected_foreign" "$privilege_ready" "$approved_action" "$approved_hardening" optional
}

brave_reconcile_interrupted() {
	local requested_operation=$1 pending=$BRAVE_PENDING_JSON operation transaction expected_foreign recovery_prompt confirmed_state confirmed_system
	local confirmed_parent confirmed_foreign approved_remove_hardening
	local confirmed_stage confirmed_backups
	local stage_present=false system_mutation=false needs_confirmation=false
	[[ $requested_operation == apply || $requested_operation == remove ]] || return 2
	[[ -n $pending ]] || return 1
	operation=$(jq -r '.operation' <<<"$pending")
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	brave_validate_source_quiet || true
	brave_inspect_system lenient || true
	expected_foreign=$BRAVE_FOREIGN_FINGERPRINT
	if [[ $operation == remove ]] && brave_pending_remove_target_is_unowned; then
		brave_print_interrupted_remove_unowned_collision
		return 1
	fi
	if brave_receipt_owned_target_is_unreadable; then
		printf 'Error: interrupted Brave recovery is blocked because the receipt-owned target is unreadable by the invoking user.\n' >&2
		brave_print_target_permission_repair
		return 1
	fi
	printf 'Interrupted Brave transaction detected: %s %s\n' "$operation" "$transaction"
	if [[ $operation == apply ]]; then
		brave_scan_foreign_policies strict 2>/dev/null || true
		if brave_interrupted_apply_is_complete; then
			confirmed_state=$BRAVE_STATE_FINGERPRINT
			confirmed_system=$BRAVE_SYSTEM_FINGERPRINT
			printf 'Recovery plan: finish the already-published apply by removing its fixed stage and clearing pending state.\n'
			if brave_path_present "$BRAVE_POLICIES/.dotfiles-$transaction.stage"; then
				stage_present=true
				system_mutation=true
			fi
			if [[ -n $BRAVE_RECOVERY_JSON || $stage_present == true ]]; then needs_confirmation=true; fi
			brave_inspect_omarchy || return 1
			printf 'Supported Omarchy: %s\nDetected Omarchy: %s\n' "$BRAVE_SUPPORTED_OMARCHY_MAJOR" "$BRAVE_OMARCHY_VERSION"
			if [[ $BRAVE_OMARCHY_MISMATCH == true ]]; then
				printf 'Warning: confirmation includes consent to recover despite the Omarchy mismatch.\n'
				needs_confirmation=true
			fi
			recovery_prompt='Complete this displayed Brave recovery plan?'
			if [[ $system_mutation == true || $BRAVE_OMARCHY_MISMATCH == true ]]; then
				recovery_prompt='Complete this displayed Brave recovery plan, including any displayed Omarchy mismatch?'
			fi
			if [[ $needs_confirmation == true ]] && ! brave_confirm "$recovery_prompt"; then
				printf 'No changes made; interrupted recovery remains pending.\n'
				BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED
				return "$BRAVE_OUTCOME_DECLINED"
			fi
			if [[ $stage_present == true ]]; then
				brave_privileged_operation acquire || return 1
				if ! brave_verify_completed_apply_recovery_snapshot "$confirmed_state" "$confirmed_system"; then
					if [[ $BRAVE_STATE_VALID == true && $BRAVE_STATE_FINGERPRINT == "$confirmed_state" ]]; then
						brave_write_recovery_required stage-cleanup-state-changed "$pending" || true
					fi
					printf 'Error: completed apply state changed before interrupted stage cleanup.\n' >&2
					return 1
				fi
				brave_privileged_operation remove-stage "$transaction" || {
					brave_write_recovery_required stage-cleanup "$pending" || true
					return 1
				}
			fi
			if ! brave_verify_completed_apply_recovery_snapshot "$confirmed_state" "$confirmed_system"; then
				if [[ $BRAVE_STATE_VALID == true && $BRAVE_STATE_FINGERPRINT == "$confirmed_state" ]]; then
					brave_write_recovery_required stage-cleanup-postcondition "$pending" || true
				fi
				printf 'Error: completed apply state changed before interrupted receipt cleanup.\n' >&2
				return 1
			fi
			if brave_path_present "$BRAVE_POLICIES/.dotfiles-$transaction.stage"; then
				brave_write_recovery_required stage-cleanup-postcondition "$pending" || true
				printf 'Error: interrupted apply stage remains or appeared before receipt cleanup.\n' >&2
				return 1
			fi
			brave_remove_state_file "$BRAVE_PENDING_RECEIPT" || return 1
			brave_remove_state_file "$BRAVE_RECOVERY_RECEIPT" || return 1
			printf 'Interrupted apply completion reconciled.\n'
			[[ $requested_operation == apply ]] && return "$BRAVE_OUTCOME_SUCCESS"
			BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED
			return "$BRAVE_OUTCOME_SUCCESS"
		fi
		printf 'Recovery plan: restore and verify the prior target, managed-directory metadata, and active receipt from retained backups; then stop.\n'
	else
		if [[ $BRAVE_TARGET_PRESENT == true ]] && brave_pending_prior_is_intact "$pending" && [[ -z $BRAVE_RECOVERY_JSON ]]; then
			confirmed_state=$BRAVE_STATE_FINGERPRINT
			confirmed_system=$BRAVE_SYSTEM_FINGERPRINT
			brave_inspect_omarchy || return 1
			printf 'Supported Omarchy: %s\nDetected Omarchy: %s\n' "$BRAVE_SUPPORTED_OMARCHY_MAJOR" "$BRAVE_OMARCHY_VERSION"
			if [[ $BRAVE_OMARCHY_MISMATCH == true ]]; then
				printf 'Warning: confirmation includes consent to recover despite the Omarchy mismatch.\n'
				if ! brave_confirm 'Complete this displayed Brave recovery plan, including any displayed Omarchy mismatch?'; then
					printf 'No changes made; interrupted recovery remains pending.\n'
					BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED
					return "$BRAVE_OUTCOME_DECLINED"
				fi
			fi
			if ! brave_inspect_state || [[ $BRAVE_STATE_FINGERPRINT != "$confirmed_state" ]] || \
				! brave_inspect_system lenient || [[ $BRAVE_SYSTEM_FINGERPRINT != "$confirmed_system" ]] || \
				! brave_pending_prior_is_intact "$pending"; then
				printf 'Error: interrupted remove state changed before pending receipt cleanup.\n' >&2
				return 1
			fi
			brave_remove_state_file "$BRAVE_PENDING_RECEIPT" || return 1
			printf 'Interrupted remove had not mutated system state; pending state was cleared.\n'
			BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED
			return "$BRAVE_OUTCOME_SUCCESS"
		fi
		if [[ $BRAVE_TARGET_PRESENT == false ]]; then
			printf 'Recovery plan: finish the interrupted removal without reinstalling policy, restore safe directory metadata, and clear receipts.\n'
			if ! brave_plan_removed_system_finalization "$pending" "$expected_foreign"; then
				brave_write_recovery_required remove-finalize-plan "$pending" || true
				return 1
			fi
			approved_remove_hardening=$BRAVE_REMOVE_FINAL_NEEDS_HARDENING
			brave_inspect_omarchy || return 1
			printf 'Supported Omarchy: %s\nDetected Omarchy: %s\n' "$BRAVE_SUPPORTED_OMARCHY_MAJOR" "$BRAVE_OMARCHY_VERSION"
			[[ $BRAVE_OMARCHY_MISMATCH == false ]] || printf 'Warning: confirmation includes consent to recover despite the Omarchy mismatch.\n'
			recovery_prompt='Complete this displayed Brave recovery plan, including any displayed Omarchy mismatch?'
			if ! brave_confirm "$recovery_prompt"; then
				printf 'No changes made; interrupted recovery remains pending.\n'
				BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED
				return "$BRAVE_OUTCOME_DECLINED"
			fi
			if brave_finalize_interrupted_remove "$pending" "$expected_foreign" false "$BRAVE_REMOVE_FINAL_ACTION" "$approved_remove_hardening"; then
				printf 'Interrupted removal reconciled without recreating the policy.\n'
				[[ $requested_operation == remove ]] && return "$BRAVE_OUTCOME_SUCCESS"
				BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED
				return "$BRAVE_OUTCOME_SUCCESS"
			fi
			brave_write_remove_recovery_required remove-finalize "$pending" || true
			return 1
		fi
		printf 'Recovery plan: restore and verify the prior receipt-owned target and metadata from retained backups; then stop.\n'
	fi
	if [[ $BRAVE_PARENT_BLOCKING == true || ( $BRAVE_TARGET_PRESENT == true && $BRAVE_TARGET_TYPE != 'regular file' ) ]]; then
		printf 'Error: interrupted transaction recovery is blocked by an unsafe parent or non-regular target.\n' >&2
		brave_write_recovery_required unsafe-recovery-path "$pending" || true
		return 1
	fi
	confirmed_state=$BRAVE_STATE_FINGERPRINT
	confirmed_system=$BRAVE_SYSTEM_FINGERPRINT
	confirmed_parent=$BRAVE_PARENT_FINGERPRINT
	confirmed_foreign=$BRAVE_FOREIGN_FINGERPRINT
	confirmed_stage=$(brave_snapshot_recovery_stage "$pending") || {
		brave_write_recovery_required interrupted-stage-snapshot "$pending" || true
		return 1
	}
	confirmed_backups=$(brave_snapshot_recovery_backups "$pending") || {
		brave_write_recovery_required interrupted-backup-snapshot "$pending" || true
		printf 'Error: interrupted recovery backup validation failed before confirmation.\n' >&2
		return 1
	}
	brave_inspect_omarchy || return 1
	printf 'Supported Omarchy: %s\nDetected Omarchy: %s\n' "$BRAVE_SUPPORTED_OMARCHY_MAJOR" "$BRAVE_OMARCHY_VERSION"
	[[ $BRAVE_OMARCHY_MISMATCH == false ]] || printf 'Warning: confirmation includes consent to recover despite the Omarchy mismatch.\n'
	if ! brave_confirm 'Apply this displayed Brave recovery plan?'; then
		printf 'No changes made; interrupted recovery remains pending.\n'
		BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED
		return "$BRAVE_OUTCOME_DECLINED"
	fi
	brave_privileged_operation acquire || return 1
	if ! brave_verify_interrupted_restore_snapshot "$pending" "$confirmed_state" "$confirmed_system" "$confirmed_stage" "$confirmed_backups"; then
		if [[ $BRAVE_STATE_VALID == true && -n $BRAVE_PENDING_JSON && $(jq -Sc . <<<"$BRAVE_PENDING_JSON") == "$(jq -Sc . <<<"$pending")" ]]; then
			brave_write_recovery_required interrupted-restore-state-changed "$pending" || true
		fi
		printf 'Error: interrupted recovery state or backup changed after confirmation; no restore mutation was attempted.\n' >&2
		return 1
	fi
	if brave_restore_prior_system "$pending" && \
		brave_verify_interrupted_restore_postconditions "$pending" "$confirmed_parent" "$confirmed_foreign" "$confirmed_backups"; then
		brave_remove_state_file "$BRAVE_PENDING_RECEIPT" || return 1
		brave_remove_state_file "$BRAVE_RECOVERY_RECEIPT" || return 1
		printf 'Interrupted Brave transaction restored and verified; rerun the requested operation.\n'
		BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED
		return "$BRAVE_OUTCOME_SUCCESS"
	fi
	brave_write_recovery_required interrupted-restore "$pending" || true
	printf 'Error: interrupted Brave transaction recovery failed; backups and pending state were retained.\n' >&2
	return 1
}

brave_apply_locked() {
	local outcome transaction original prior_managed old_source old_consumers old_state old_system confirmed_content confirmed_parent confirmed_managed_identity
	if ! brave_inspect_state; then
		brave_report_invalid_state_remove_collision || true
		return 1
	fi
	if [[ -n $BRAVE_PENDING_JSON || -n $BRAVE_RECOVERY_JSON ]]; then
		brave_reconcile_interrupted apply
		return $?
	fi
	if ! brave_validate_source_quiet; then
		printf 'Error: invalid Brave policy source: %s\n' "$BRAVE_SOURCE_ERROR" >&2
		return 1
	fi
	brave_inspect_consumers || {
		brave_print_consumers
		return 1
	}
	if ((BRAVE_SUPPORTED_CONSUMER_COUNT == 0)); then
		brave_print_consumers
		printf 'No supported Brave browser is installed.\n'
		printf 'Install with: omarchy install browser brave\n'
		printf 'Install with: omarchy install browser brave-origin\n'
		return "$BRAVE_OUTCOME_UNAVAILABLE"
	fi
	if ! brave_apply_preflight; then return 1; fi
	if [[ $BRAVE_PROVIDERS_VALID != true || $BRAVE_CONSUMERS_VALID != true ]]; then return 1; fi
	if brave_exact_active_match; then
		printf 'Brave policy is already exact and active; no confirmation, privilege, backup, or receipt change is needed.\n'
		return "$BRAVE_OUTCOME_SUCCESS"
	fi
	brave_inspect_omarchy || return 1
	transaction=$(brave_generate_transaction) || return 1
	original=$(brave_original_managed_json) || return 1
	prior_managed=$(brave_current_managed_json) || return 1
	brave_print_apply_plan "$transaction" "$original" || return 1
	if ! brave_confirm 'Apply this complete Brave policy plan, including any displayed Omarchy mismatch?'; then
		printf 'No changes made.\n'
		return "$BRAVE_OUTCOME_DECLINED"
	fi
	old_source=$BRAVE_SOURCE_DIGEST old_consumers=$BRAVE_CONSUMER_FINGERPRINT old_state=$BRAVE_STATE_FINGERPRINT old_system=$BRAVE_SYSTEM_FINGERPRINT
	confirmed_content=$BRAVE_SYSTEM_CONTENT_FINGERPRINT
	confirmed_parent=$BRAVE_PARENT_FINGERPRINT
	confirmed_managed_identity=$BRAVE_MANAGED_IDENTITY
	brave_privileged_operation acquire || {
		printf 'Error: could not acquire privilege for the confirmed Brave policy plan.\n' >&2
		return 1
	}
	if ! brave_reinspect_for_apply || ! brave_report_snapshot_changes "$old_source" "$old_consumers" "$old_state" "$old_system"; then
		printf 'Error: the confirmed Brave plan is stale; no system mutation was made.\n' >&2
		return 1
	fi
	brave_prepare_state_root || return 1
	if ! brave_prepare_backups_and_pending apply "$transaction" "$prior_managed" "$old_source"; then
		brave_remove_state_file "$BRAVE_PENDING_RECEIPT" || true
		printf 'Error: Brave backup or pending-receipt preparation failed before system mutation.\n' >&2
		return 1
	fi
	BRAVE_TRANSACTION_SYSTEM_MUTATED=false
	if brave_finish_apply_transaction "$transaction" "$original" "$old_source" "$old_consumers" "$confirmed_content" "$confirmed_parent" "$confirmed_managed_identity"; then
		return "$BRAVE_OUTCOME_SUCCESS"
	else
		outcome=$?
	fi
	if ((outcome == 2)); then
		# Active target and receipt are already complete; interrupted-apply reconciliation clears pending state.
		return 1
	fi
	if [[ $BRAVE_TRANSACTION_SYSTEM_MUTATED == true ]]; then
		brave_rollback_transaction apply-failure "$BRAVE_PENDING_JSON" || true
	else
		brave_remove_state_file "$BRAVE_PENDING_RECEIPT" || true
	fi
	return 1
}

apply_brave_policy() {
	BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_ORDINARY
	if (($# != 0)); then
		printf 'Error: apply_brave_policy accepts no target or path arguments.\n' >&2
		return 2
	fi
	if [[ $(brave_effective_uid) == 0 ]]; then
		printf 'Error: Brave policy mutation must run as the invoking user, not root.\n' >&2
		return 1
	fi
	brave_initialize_state_paths || return 1
	brave_acquire_lock exclusive || return 1
	local outcome=0
	brave_apply_locked || outcome=$?
	brave_release_lock
	return "$outcome"
}

brave_print_remove_plan() {
	local transaction=$1 original=$2
	printf 'Plan: remove one shared Brave managed policy\n'
	brave_print_consumers
	printf 'Supported Omarchy: %s\nDetected Omarchy: %s\n' "$BRAVE_SUPPORTED_OMARCHY_MAJOR" "$BRAVE_OMARCHY_VERSION"
	[[ $BRAVE_OMARCHY_MISMATCH == false ]] || printf 'Warning: this plan requires consent to continue despite the Omarchy major-version mismatch.\n'
	printf 'Receipt-owned target: %s\nCurrent target digest: %s\n' "$BRAVE_POLICY_TARGET" "${BRAVE_TARGET_DIGEST:-missing}"
	[[ $BRAVE_TARGET_PRESENT == true ]] && printf 'Target drift from receipt/source is displayed and will be backed up before removal.\n' || printf 'Target is already missing; this plan clears stale receipt state without recreating policy.\n'
	brave_print_system_report
	printf 'Transaction backups: %s/backups/%s/dotfiles.json and active.json (when present).\n' "$BRAVE_STATE_CANONICAL_ROOT" "$transaction"
	printf 'Directory restoration: restore original metadata only when no foreign policy remains except valid color.json; otherwise retain root:root 0755 hardening. Original=%s\n' "$original"
	printf 'Privileged effects after confirmation: fixed directory hardening, fixed target removal, safe metadata restoration, and verification.\n'
	printf 'Extensions may remain installed but become removable. Policy effects may remain until a user reloads policies or relaunches; this operation never does so.\n'
	printf 'color.json may keep Brave managed indicators visible and is never changed.\n'
	printf 'Not changed: canonical source, backups, packages, profiles, browser data, extensions, Sync, flags, themes, fonts, foreign policy, default-browser state, or Omarchy packaged files.\n'
}

brave_remove_preflight() {
	local failed=false
	brave_validate_source_quiet || printf 'Warning: canonical source is unavailable or invalid; receipt-bound removal does not depend on it.\n'
	brave_inspect_consumers || true
	brave_inspect_state || failed=true
	brave_inspect_system lenient || failed=true
	brave_print_consumers
	brave_print_state_report
	brave_print_system_report
	if [[ $BRAVE_STATE_VALID != true ]]; then
		printf 'Error: invalid Brave receipt state blocks removal.\n' >&2
		return 1
	fi
	if [[ -z $BRAVE_ACTIVE_JSON ]]; then
		if [[ $BRAVE_TARGET_PRESENT == false ]]; then
			printf 'Brave policy is already absent and has no active receipt; nothing to remove.\n'
			return "$BRAVE_INTERNAL_NOTHING_TO_REMOVE"
		fi
		printf 'Error: target exists without a valid active receipt and is never removed as repository-owned policy.\n' >&2
		return 1
	fi
	if [[ $BRAVE_TARGET_PRESENT == true ]]; then
		if [[ $BRAVE_TARGET_TYPE != 'regular file' ]]; then
			printf 'Error: receipt-owned target is a %s; removal requires a no-follow regular file.\n' "$BRAVE_TARGET_TYPE" >&2
			failed=true
		fi
		if brave_receipt_owned_target_is_unreadable; then
			printf 'Error: receipt-owned target is unavailable for safe Remove because it is unreadable by the invoking user.\n' >&2
			brave_print_target_permission_repair
			failed=true
		fi
		if [[ $BRAVE_PARENT_MISSING == true || $BRAVE_PARENT_BLOCKING == true || $BRAVE_MANAGED_PRESENT != true || $BRAVE_MANAGED_TYPE != directory ]]; then
			printf 'Error: receipt-owned target cannot be removed through unsafe or missing parent paths.\n' >&2
			failed=true
		fi
	fi
	[[ $failed == false ]]
}

brave_plan_removed_system_finalization() {
	local pending=$1 expected_foreign=$2 original original_present
	BRAVE_REMOVE_FINAL_ACTION=''
	BRAVE_REMOVE_FINAL_EXPECTED_PRESENT=false
	BRAVE_REMOVE_FINAL_EXPECTED_UID=''
	BRAVE_REMOVE_FINAL_EXPECTED_GID=''
	BRAVE_REMOVE_FINAL_EXPECTED_MODE=''
	BRAVE_REMOVE_FINAL_NEEDS_HARDENING=false
	brave_inspect_system lenient || return 1
	if [[ $BRAVE_TARGET_PRESENT == true || $BRAVE_PARENT_BLOCKING == true || $BRAVE_FOREIGN_FINGERPRINT != "$expected_foreign" ]]; then
		printf 'Error: Brave removal finalization state changed before metadata handling.\n' >&2
		return 1
	fi
	if [[ $BRAVE_MANAGED_PRESENT == false ]]; then
		[[ -z $expected_foreign ]] || return 1
		BRAVE_REMOVE_FINAL_ACTION=none
		return 0
	fi
	if [[ $BRAVE_MANAGED_TYPE != directory || $BRAVE_MANAGED_UID != 0 ]]; then
		printf 'Error: Brave managed directory is unsafe during removal finalization.\n' >&2
		return 1
	fi
	if [[ $BRAVE_MANAGED_UID != 0 || $BRAVE_MANAGED_GID != 0 || $BRAVE_MANAGED_MODE != 0755 ]]; then
		BRAVE_REMOVE_FINAL_NEEDS_HARDENING=true
	fi
	original=$(brave_lifecycle_original_from_pending "$pending") || return 1
	original_present=$(jq -r '.present' <<<"$original")
	if [[ $BRAVE_FOREIGN_SAFE == true && $BRAVE_FOREIGN_NON_COLOR_COUNT -eq 0 && $original_present == true ]]; then
		BRAVE_REMOVE_FINAL_EXPECTED_PRESENT=true
		BRAVE_REMOVE_FINAL_EXPECTED_UID=$(jq -r '.uid' <<<"$original")
		BRAVE_REMOVE_FINAL_EXPECTED_GID=$(jq -r '.gid' <<<"$original")
		BRAVE_REMOVE_FINAL_EXPECTED_MODE=$(jq -r '.mode' <<<"$original")
		if [[ $BRAVE_REMOVE_FINAL_EXPECTED_UID == 0 && $BRAVE_REMOVE_FINAL_EXPECTED_GID == 0 && \
			$BRAVE_REMOVE_FINAL_EXPECTED_MODE == 0755 ]]; then
			BRAVE_REMOVE_FINAL_ACTION=none
		else
			BRAVE_REMOVE_FINAL_ACTION=restore
		fi
	elif [[ $BRAVE_FOREIGN_SAFE == true && $BRAVE_FOREIGN_NON_COLOR_COUNT -eq 0 && $original_present == false && ${#BRAVE_FOREIGN_LINES[@]} -eq 0 ]]; then
		BRAVE_REMOVE_FINAL_ACTION=remove
	else
		BRAVE_REMOVE_FINAL_EXPECTED_PRESENT=true
		BRAVE_REMOVE_FINAL_EXPECTED_UID=0
		BRAVE_REMOVE_FINAL_EXPECTED_GID=0
		BRAVE_REMOVE_FINAL_EXPECTED_MODE=0755
		BRAVE_REMOVE_FINAL_ACTION=none
	fi
}

brave_remove_finalization_plan_is_approved() {
	local approved_action=$1 approved_hardening=$2
	if [[ -n $approved_action && $BRAVE_REMOVE_FINAL_ACTION != "$approved_action" ]]; then
		printf 'Error: Brave removal finalization action changed after confirmation.\n' >&2
		return 1
	fi
	if [[ -n $approved_hardening && $BRAVE_REMOVE_FINAL_NEEDS_HARDENING != "$approved_hardening" ]]; then
		printf 'Error: Brave removal hardening requirement changed after confirmation.\n' >&2
		return 1
	fi
}

brave_verify_remove_active_state() {
	local mode=$1
	if [[ $mode == optional && ! -e $BRAVE_ACTIVE_RECEIPT && ! -L $BRAVE_ACTIVE_RECEIPT ]]; then
		return 0
	fi
	brave_verify_prior_active_unchanged
}

brave_retain_remove_finalization_state() {
	local pending=$1 output
	if [[ -e $BRAVE_PENDING_RECEIPT || -L $BRAVE_PENDING_RECEIPT ]]; then
		output=$(brave_validate_receipt_file pending "$BRAVE_PENDING_RECEIPT") || return 1
		[[ $(jq -Sc '.value' <<<"$output") == "$(jq -Sc . <<<"$pending")" ]] || return 1
	else
		brave_atomic_write_receipt pending "$BRAVE_PENDING_RECEIPT" "$pending" || return 1
	fi
	if ! brave_path_present "$BRAVE_POLICY_TARGET"; then
		brave_restore_active_from_pending "$pending" || return 1
	fi
	BRAVE_REMOVE_FINAL_STATE_CLEARED=false
}

brave_retain_failed_remove_finalization() {
	local pending=$1
	brave_inspect_system lenient || return 1
	if [[ $BRAVE_MANAGED_PRESENT == true ]]; then
		if [[ $BRAVE_MANAGED_TYPE != directory || $BRAVE_MANAGED_UID != 0 ]]; then
			return 1
		fi
		if [[ $BRAVE_MANAGED_GID != 0 || $BRAVE_MANAGED_MODE != 0755 ]]; then
			brave_privileged_operation harden-managed || return 1
			brave_inspect_system lenient || return 1
			[[ $BRAVE_MANAGED_PRESENT == true && $BRAVE_MANAGED_TYPE == directory && $BRAVE_MANAGED_UID == 0 && \
				$BRAVE_MANAGED_GID == 0 && $BRAVE_MANAGED_MODE == 0755 ]] || return 1
		fi
	fi
	brave_retain_remove_finalization_state "$pending"
}

brave_verify_removed_system_finalization() {
	local expected_foreign=$1
	if [[ $BRAVE_TARGET_PRESENT == true || $BRAVE_FOREIGN_FINGERPRINT != "$expected_foreign" ]]; then
		printf 'Error: Brave removal finalization changed the target or foreign inventory.\n' >&2
		return 1
	fi
	if [[ $BRAVE_REMOVE_FINAL_EXPECTED_PRESENT == true ]]; then
		if [[ $BRAVE_MANAGED_PRESENT != true || $BRAVE_MANAGED_TYPE != directory || \
			$BRAVE_MANAGED_UID != "$BRAVE_REMOVE_FINAL_EXPECTED_UID" || $BRAVE_MANAGED_GID != "$BRAVE_REMOVE_FINAL_EXPECTED_GID" || \
			$BRAVE_MANAGED_MODE != "$BRAVE_REMOVE_FINAL_EXPECTED_MODE" ]]; then
			printf 'Error: Brave managed-directory metadata postcondition failed.\n' >&2
			return 1
		fi
	else
		if [[ $BRAVE_MANAGED_PRESENT == true ]]; then
			printf 'Error: originally absent empty Brave managed directory remains after removal.\n' >&2
			return 1
		fi
	fi
}

brave_print_removed_system_finalization() {
	local action=$1
	case $action in
		restore) printf 'Managed-directory original metadata restored: %s:%s %s\n' "$BRAVE_REMOVE_FINAL_EXPECTED_UID" "$BRAVE_REMOVE_FINAL_EXPECTED_GID" "$BRAVE_REMOVE_FINAL_EXPECTED_MODE" ;;
		remove) printf 'Managed directory removed because it was originally absent and is now empty.\n' ;;
		none)
			if [[ $BRAVE_REMOVE_FINAL_EXPECTED_PRESENT == true && $BRAVE_REMOVE_FINAL_EXPECTED_MODE == 0755 ]]; then
				printf 'Managed-directory hardening retained: foreign policy or color.json prevents removal or metadata restoration.\n'
			fi
			;;
	esac
}

brave_finalize_removed_transaction() {
	local pending=$1 expected_foreign=$2 privilege_ready=${3-false} approved_action=${4-} approved_hardening=${5-} active_mode=${6-strict}
	local action expected_present expected_uid expected_gid expected_mode
	BRAVE_REMOVE_FINAL_STATE_CLEARED=false
	brave_plan_removed_system_finalization "$pending" "$expected_foreign" || return 1
	[[ -n $approved_action ]] || approved_action=$BRAVE_REMOVE_FINAL_ACTION
	[[ -n $approved_hardening ]] || approved_hardening=$BRAVE_REMOVE_FINAL_NEEDS_HARDENING
	brave_remove_finalization_plan_is_approved "$approved_action" "$approved_hardening" || return 1
	if [[ ( $BRAVE_REMOVE_FINAL_NEEDS_HARDENING == true || $BRAVE_REMOVE_FINAL_ACTION != none ) && $privilege_ready != true ]]; then
		brave_privileged_operation acquire || return 1
		privilege_ready=true
		brave_verify_pending_unchanged && brave_verify_remove_active_state "$active_mode" || return 1
		brave_plan_removed_system_finalization "$pending" "$expected_foreign" || return 1
		brave_remove_finalization_plan_is_approved "$approved_action" "$approved_hardening" || return 1
	fi
	if [[ $BRAVE_REMOVE_FINAL_NEEDS_HARDENING == true ]]; then
		brave_privileged_operation harden-managed || return 1
	fi
	brave_inspect_system lenient || return 1
	if [[ $BRAVE_TARGET_PRESENT == true || $BRAVE_FOREIGN_FINGERPRINT != "$expected_foreign" || \
		( $BRAVE_MANAGED_PRESENT == true && ( $BRAVE_MANAGED_TYPE != directory || $BRAVE_MANAGED_UID != 0 || \
		$BRAVE_MANAGED_GID != 0 || $BRAVE_MANAGED_MODE != 0755 ) ) ]]; then
		printf 'Error: Brave managed-directory metadata postcondition failed before receipt finalization.\n' >&2
		return 1
	fi
	brave_verify_pending_unchanged && brave_verify_remove_active_state "$active_mode" || return 1
	action=$BRAVE_REMOVE_FINAL_ACTION
	expected_present=$BRAVE_REMOVE_FINAL_EXPECTED_PRESENT
	expected_uid=$BRAVE_REMOVE_FINAL_EXPECTED_UID
	expected_gid=$BRAVE_REMOVE_FINAL_EXPECTED_GID
	expected_mode=$BRAVE_REMOVE_FINAL_EXPECTED_MODE
	if ! brave_remove_state_file "$BRAVE_ACTIVE_RECEIPT"; then
		brave_retain_remove_finalization_state "$pending" || true
		return 1
	fi
	if ! brave_remove_state_file "$BRAVE_PENDING_RECEIPT"; then
		brave_retain_remove_finalization_state "$pending" || true
		return 1
	fi
	if ! brave_remove_state_file "$BRAVE_RECOVERY_RECEIPT"; then
		brave_retain_remove_finalization_state "$pending" || true
		return 1
	fi
	if ! brave_inspect_state || [[ -n $BRAVE_ACTIVE_JSON || -n $BRAVE_PENDING_JSON || -n $BRAVE_RECOVERY_JSON ]]; then
		printf 'Error: Brave removal receipts were not fully cleared under managed-directory hardening.\n' >&2
		brave_retain_remove_finalization_state "$pending" || true
		return 1
	fi
	BRAVE_REMOVE_FINAL_STATE_CLEARED=true
	BRAVE_REMOVE_FINAL_EXPECTED_PRESENT=$expected_present
	BRAVE_REMOVE_FINAL_EXPECTED_UID=$expected_uid
	BRAVE_REMOVE_FINAL_EXPECTED_GID=$expected_gid
	BRAVE_REMOVE_FINAL_EXPECTED_MODE=$expected_mode
	case $action in
		restore)
			if ! brave_privileged_operation restore-managed "$expected_uid" "$expected_gid" "$expected_mode"; then
				brave_retain_failed_remove_finalization "$pending" || true
				return 1
			fi
			;;
		remove)
			if ! brave_privileged_operation remove-managed; then
				brave_retain_failed_remove_finalization "$pending" || true
				return 1
			fi
			;;
		none) ;;
		*) return 1 ;;
	esac
	if ! brave_inspect_system lenient || ! brave_verify_removed_system_finalization "$expected_foreign"; then
		brave_retain_failed_remove_finalization "$pending" || true
		return 1
	fi
	brave_print_removed_system_finalization "$action"
}

brave_remove_locked() {
	local outcome transaction original prior_managed old_consumers old_state old_system old_secured confirmed_foreign pending target_was_present
	brave_inspect_state || {
		brave_report_invalid_state_remove_collision || true
		printf 'Error: invalid Brave receipt state blocks removal.\n' >&2
		return 1
	}
	if [[ -n $BRAVE_PENDING_JSON || -n $BRAVE_RECOVERY_JSON ]]; then
		brave_reconcile_interrupted remove
		return $?
	fi
	if brave_remove_preflight; then :; else outcome=$?; ((outcome == BRAVE_INTERNAL_NOTHING_TO_REMOVE)) && return "$BRAVE_OUTCOME_SUCCESS"; return "$outcome"; fi
	brave_inspect_omarchy || return 1
	transaction=$(brave_generate_transaction) || return 1
	original=$(brave_original_managed_json) || return 1
	prior_managed=$(brave_current_managed_json) || return 1
	brave_print_remove_plan "$transaction" "$original"
	if ! brave_confirm 'Remove this complete Brave policy plan, including any displayed Omarchy mismatch?'; then
		printf 'No changes made.\n'
		return "$BRAVE_OUTCOME_DECLINED"
	fi
	old_consumers=$BRAVE_CONSUMER_FINGERPRINT old_state=$BRAVE_STATE_FINGERPRINT old_system=$BRAVE_SYSTEM_FINGERPRINT
	old_secured=$BRAVE_SYSTEM_SECURED_FINGERPRINT
	if [[ $BRAVE_TARGET_PRESENT == true ]]; then brave_privileged_operation acquire || return 1; fi
	brave_inspect_consumers || true
	brave_inspect_state || return 1
	brave_inspect_system lenient || return 1
	if [[ $BRAVE_CONSUMER_FINGERPRINT != "$old_consumers" || $BRAVE_STATE_FINGERPRINT != "$old_state" || $BRAVE_SYSTEM_FINGERPRINT != "$old_system" ]]; then
		printf 'Error: confirmed Brave removal state changed; no system mutation was made.\n' >&2
		return 1
	fi
	confirmed_foreign=$BRAVE_FOREIGN_FINGERPRINT
	brave_prepare_state_root || return 1
	target_was_present=$BRAVE_TARGET_PRESENT
	if ! brave_prepare_backups_and_pending remove "$transaction" "$prior_managed"; then
		brave_remove_state_file "$BRAVE_PENDING_RECEIPT" || true
		printf 'Error: Brave removal backup or pending receipt failed before system mutation.\n' >&2
		return 1
	fi
	pending=$BRAVE_PENDING_JSON
	if [[ $target_was_present == false ]]; then
		if ! brave_finalize_removed_transaction "$pending" "$confirmed_foreign" false; then
			brave_write_remove_recovery_required stale-remove-finalize "$pending" || true
			printf 'Error: stale target is absent but managed-directory finalization failed; receipts were retained.\n' >&2
			return 1
		fi
		printf 'Cleared stale Brave active receipt without recreating /etc/brave or policy.\n'
		return "$BRAVE_OUTCOME_SUCCESS"
	fi
	BRAVE_TRANSACTION_SYSTEM_MUTATED=false
	if [[ $BRAVE_MANAGED_UID != 0 || $BRAVE_MANAGED_GID != 0 || $BRAVE_MANAGED_MODE != 0755 ]]; then
		BRAVE_TRANSACTION_SYSTEM_MUTATED=true
		if ! brave_privileged_operation harden-managed; then
			brave_rollback_transaction remove-harden "$pending" || true
			return 1
		fi
	fi
	brave_inspect_consumers || true
	if ! brave_inspect_system lenient || ! brave_verify_pending_unchanged || ! brave_verify_prior_active_unchanged; then
		brave_rollback_transaction remove-recheck "$pending" || true
		return 1
	fi
	if [[ $BRAVE_CONSUMER_FINGERPRINT != "$old_consumers" || $BRAVE_SYSTEM_SECURED_FINGERPRINT != "$old_secured" ]]; then
		brave_rollback_transaction remove-recheck "$pending" || true
		return 1
	fi
	BRAVE_TRANSACTION_SYSTEM_MUTATED=true
	if ! brave_privileged_operation remove-target; then
		brave_inspect_system lenient || true
		if [[ $BRAVE_TARGET_PRESENT == true ]]; then brave_rollback_transaction remove-target "$pending" || true; fi
		return 1
	fi
	brave_inspect_system lenient || true
	if [[ $BRAVE_TARGET_PRESENT == true ]]; then
		brave_rollback_transaction remove-verification "$pending" || true
		return 1
	fi
	if ! brave_finalize_removed_transaction "$pending" "$confirmed_foreign" true; then
		brave_write_remove_recovery_required remove-metadata "$pending" || true
		printf 'Error: target is absent but removal metadata cleanup failed; policy will not be reinstalled.\n' >&2
		return 1
	fi
	printf 'Removed and verified shared Brave policy: %s\n' "$BRAVE_POLICY_TARGET"
	printf 'Backup retained: %s/backups/%s\n' "$BRAVE_STATE_CANONICAL_ROOT" "$transaction"
	printf 'Extensions may remain but are now removable; policy effects may remain until a user reloads or relaunches Brave.\n'
	printf 'color.json and all foreign policy remain unchanged; color.json may keep the managed indicator visible.\n'
}

remove_brave_policy() {
	BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_ORDINARY
	if (($# != 0)); then
		printf 'Error: remove_brave_policy accepts no target or path arguments.\n' >&2
		return 2
	fi
	if [[ $(brave_effective_uid) == 0 ]]; then
		printf 'Error: Brave policy mutation must run as the invoking user, not root.\n' >&2
		return 1
	fi
	brave_initialize_state_paths || return 1
	brave_acquire_lock exclusive || return 1
	local outcome=0
	brave_remove_locked || outcome=$?
	brave_release_lock
	return "$outcome"
}

manage_brave_policy() {
	BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_ORDINARY
	if (($# != 0)); then
		printf 'Error: manage_brave_policy accepts no arguments.\n' >&2
		return 2
	fi
	local choice outcome
	while true; do
		if ! choice=$(wizard_choose 'Manage Brave policy' Status Apply Remove Back); then
			printf 'No Brave policy operation selected.\n'
			return 0
		fi
		case $choice in
			Status) brave_policy_status || return $? ;;
			Apply)
				if apply_brave_policy; then outcome=0; else outcome=$?; fi
				case $outcome:$BRAVE_OPERATION_CONTEXT in
					"$BRAVE_OUTCOME_SUCCESS:$BRAVE_OPERATION_CONTEXT_ORDINARY"|"$BRAVE_OUTCOME_SUCCESS:$BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED") return "$BRAVE_OUTCOME_SUCCESS" ;;
					"$BRAVE_OUTCOME_DECLINED:$BRAVE_OPERATION_CONTEXT_ORDINARY"|"$BRAVE_OUTCOME_DECLINED:$BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED") printf 'Brave policy apply declined; no change made.\n'; return "$BRAVE_OUTCOME_SUCCESS" ;;
					"$BRAVE_OUTCOME_UNAVAILABLE:$BRAVE_OPERATION_CONTEXT_ORDINARY") printf 'Error: install Brave Browser or Brave Origin before standalone policy apply.\n' >&2; return 1 ;;
					*) return "$outcome" ;;
				esac
				;;
			Remove)
				if remove_brave_policy; then outcome=0; else outcome=$?; fi
				if [[ $outcome == "$BRAVE_OUTCOME_DECLINED" && \
					( $BRAVE_OPERATION_CONTEXT == "$BRAVE_OPERATION_CONTEXT_ORDINARY" || $BRAVE_OPERATION_CONTEXT == "$BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED" ) ]]; then
					printf 'Brave policy removal declined; no change made.\n'
					return "$BRAVE_OUTCOME_SUCCESS"
				fi
				return "$outcome"
				;;
			Back) return 0 ;;
		esac
	done
}
