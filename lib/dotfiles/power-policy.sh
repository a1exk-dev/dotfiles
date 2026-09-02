readonly POWER_POLICY_UPOWER_SOURCE="$REPOSITORY_ROOT/power-policy/upower.conf"
readonly POWER_POLICY_LOGIND_SOURCE="$REPOSITORY_ROOT/power-policy/logind.conf"
readonly POWER_POLICY_JSON_HELPER="$REPOSITORY_ROOT/lib/dotfiles/power-policy-json.mjs"
readonly POWER_POLICY_UPOWER_TARGET='/etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf'
readonly POWER_POLICY_LOGIND_TARGET='/etc/systemd/logind.conf.d/90-dotfiles-laptop-power.conf'
readonly POWER_POLICY_STATE_NAME='laptop-power-policy'
readonly POWER_POLICY_OUTCOME_SUCCESS=0
readonly POWER_POLICY_OUTCOME_DECLINED=10
readonly POWER_POLICY_OUTCOME_INELIGIBLE=11
readonly POWER_POLICY_OPERATION_CONTEXT_ORDINARY='ordinary'
readonly POWER_POLICY_OPERATION_CONTEXT_RECOVERY_COMPLETED='recovery-completed'
readonly POWER_POLICY_OPERATION_CONTEXT_RECOVERY_DECLINED='recovery-declined'

POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_ORDINARY
POWER_POLICY_STATE_ROOT=''
POWER_POLICY_ACTIVE_PATH=''
POWER_POLICY_PENDING_PATH=''
POWER_POLICY_LOCK_FD=''
POWER_POLICY_UPOWER_DIGEST=''
POWER_POLICY_LOGIND_DIGEST=''
POWER_POLICY_ACTIVE=''
POWER_POLICY_PENDING=''
POWER_POLICY_ACTIVE_DIGEST=''
POWER_POLICY_PENDING_DIGEST=''
POWER_POLICY_VERSION=''
POWER_POLICY_SERVICE=''
POWER_POLICY_SLEEP_LOCK=''
POWER_POLICY_CAN_HIBERNATE=''
POWER_POLICY_BATTERY=''
POWER_POLICY_HIBERNATION=''
POWER_POLICY_CRITICAL_ACTION=''
POWER_POLICY_LOGIND_RUNTIME=''
POWER_POLICY_INHIBIT_DELAY_US=''
POWER_POLICY_UPOWER_EFFECTIVE=''
POWER_POLICY_LOGIND_EFFECTIVE=''
POWER_POLICY_UPOWER_PLAN=''
POWER_POLICY_LOGIND_PLAN=''
POWER_POLICY_ACTIVE_BACKUPS=''
POWER_POLICY_PENDING_BACKUPS=''
POWER_POLICY_STATE_ERROR=''
POWER_POLICY_ACTIVE_LABEL='absent'
POWER_POLICY_PENDING_LABEL='absent'
declare -A POWER_POLICY_TARGET=()

power_policy_stat_metadata() {
	local metadata
	metadata=$(LC_ALL=C stat -c '%F|%u|%g|%a' -- "$1") || return 1
	printf '%s\n' "${metadata/#regular empty file|/regular file|}"
}

# This is the only production boundary for system inspection and privileged work.
# Isolated tests replace it after sourcing this module.
power_policy_adapter() {
	local group=$1 action=${2-} name=${3-} stage target backup enabled active output
	shift 2
	case "$group:$action" in
		lock:shared|lock:exclusive)
			local metadata type uid gid mode
			metadata=$(power_policy_stat_metadata /run/lock 2>/dev/null) || return 1
			IFS='|' read -r type uid gid mode <<<"$metadata"
			[[ $type == directory && $uid == 0 && $gid == 0 && $mode =~ ^0?7[0-7][0-7]$ && ! -L /run/lock ]] || return 1
			exec {POWER_POLICY_LOCK_FD}</run/lock || return 1
			if [[ $action == shared ]]; then flock --shared "$POWER_POLICY_LOCK_FD"; else flock --exclusive "$POWER_POLICY_LOCK_FD"; fi
			;;
		lock:release) [[ -z $POWER_POLICY_LOCK_FD ]] || { flock --unlock "$POWER_POLICY_LOCK_FD" || true; exec {POWER_POLICY_LOCK_FD}>&-; POWER_POLICY_LOCK_FD=''; } ;;
		inspect:version) /usr/bin/env -i OMARCHY_PATH=/usr/share/omarchy PATH=/usr/bin LC_ALL=C LANG=C /usr/bin/omarchy version ;;
		inspect:battery) omarchy-battery-present ;;
		inspect:hibernation) omarchy-hibernation-available ;;
		inspect:can-hibernate)
			output=$(/usr/bin/busctl --system call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate) || return 1
			[[ $output =~ ^s[[:space:]]+\"(yes|no|challenge)\"$ ]] || return 1; printf '%s\n' "${BASH_REMATCH[1]}" ;;
		inspect:service)
			local enabled_status=0 active_status=0
			enabled=$(/usr/bin/systemctl is-enabled upower.service 2>/dev/null) || enabled_status=$?
			active=$(/usr/bin/systemctl is-active upower.service 2>/dev/null) || active_status=$?
			[[ $enabled =~ ^(enabled|disabled)$ && $active =~ ^(active|inactive)$ ]] || return 1
			printf '%s|%s\n' "$enabled" "$active" ;;
		inspect:sleep-lock)
			enabled=$(/usr/bin/systemctl --user is-enabled omarchy-sleep-lock.service 2>/dev/null || true)
			active=$(/usr/bin/systemctl --user is-active omarchy-sleep-lock.service 2>/dev/null || true)
			if /usr/bin/systemd-inhibit --list --no-pager --no-legend | /usr/bin/grep -Eq '^Omarchy[[:space:]].*systemd-inhibit[[:space:]]+sleep[[:space:]].*delay[[:space:]]*$'; then printf '%s|%s|present\n' "$enabled" "$active"; else printf '%s|%s|absent\n' "$enabled" "$active"; fi ;;
		inspect:critical-action) /usr/bin/busctl --system call org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower GetCriticalAction | { read -r _ output; printf '%s\n' "${output//\"/}"; } ;;
		inspect:logind-runtime)
			local lid external docked value
			for name in HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked; do
				value=$(/usr/bin/busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$name") || return 1
				value=${value#* }; value=${value//\"/}
				case $name in HandleLidSwitch) lid=$value ;; HandleLidSwitchExternalPower) external=$value ;; *) docked=$value ;; esac
			done
			printf '%s|%s|%s\n' "$lid" "$external" "$docked" ;;
		inspect:inhibit-delay)
			output=$(/usr/bin/busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager InhibitDelayMaxUSec) || return 1
		[[ $output =~ ^t[[:space:]]+([0-9]+)$ ]] || return 1
			printf '%s\n' "${BASH_REMATCH[1]}" ;;
		inspect:target)
			case $name in upower) target=$POWER_POLICY_UPOWER_TARGET ;; logind) target=$POWER_POLICY_LOGIND_TARGET ;; parent-upower) target=${POWER_POLICY_UPOWER_TARGET%/*} ;; parent-logind) target=${POWER_POLICY_LOGIND_TARGET%/*} ;; *) return 2 ;; esac
			[[ -e $target || -L $target ]] || { printf 'absent\n'; return 0; }
			output=$(power_policy_stat_metadata "$target") || return 1
			if [[ $name == parent-* ]]; then printf '%s\n' "$output"; return; fi
			[[ ! -L $target ]] || { printf '%s\n' "$output"; return; }
			output+="|$(node "$POWER_POLICY_JSON_HELPER" digest "$target" | jq -r .digest)"; printf '%s\n' "$output" ;;
		inspect:target-parent-safe)
			case $name in upower) target=${POWER_POLICY_UPOWER_TARGET%/*} ;; logind) target=${POWER_POLICY_LOGIND_TARGET%/*} ;; *) return 2 ;; esac
			power_policy_fixed_parent_components_safe "$target" && printf 'safe\n' ;;
		inspect:state-path-safe) power_policy_path_components_safe "$name" state && printf 'safe\n' ;;
		inspect:stage)
			stage=$(power_policy_stage_path "$1" "$2") || return 2
			output=$(power_policy_stat_metadata "$stage" 2>/dev/null) || return 1
			[[ ! -L $stage ]] || { printf '%s\n' "$output"; return; }
			output+="|$(node "$POWER_POLICY_JSON_HELPER" digest "$stage" | jq -r .digest)"; printf '%s\n' "$output" ;;
		inspect:upower-effective) node "$POWER_POLICY_JSON_HELPER" upower-effective /etc/UPower/UPower.conf /etc/UPower/UPower.conf.d ;;
		inspect:upower-plan) node "$POWER_POLICY_JSON_HELPER" upower-plan /etc/UPower/UPower.conf /etc/UPower/UPower.conf.d "$POWER_POLICY_UPOWER_TARGET" "$name" ;;
		inspect:logind-effective) node "$POWER_POLICY_JSON_HELPER" logind-effective /etc/systemd/logind.conf /etc/systemd/logind.conf.d /run/systemd/logind.conf /run/systemd/logind.conf.d /usr/local/lib/systemd/logind.conf /usr/local/lib/systemd/logind.conf.d /usr/lib/systemd/logind.conf /usr/lib/systemd/logind.conf.d ;;
		inspect:logind-plan) node "$POWER_POLICY_JSON_HELPER" logind-plan /etc/systemd/logind.conf /etc/systemd/logind.conf.d /run/systemd/logind.conf /run/systemd/logind.conf.d /usr/local/lib/systemd/logind.conf /usr/local/lib/systemd/logind.conf.d /usr/lib/systemd/logind.conf /usr/lib/systemd/logind.conf.d "$POWER_POLICY_LOGIND_TARGET" "$name" ;;
		mutate:acquire) /usr/bin/sudo -v ;;
		mutate:backup)
			name=$1; backup=$2; target=$(power_policy_target_path "$name") || return 2
			/usr/bin/sudo /usr/bin/install -T -o "$EUID" -g "$(id -g)" -m 0600 -- "$target" "$backup" ;;
		mutate:stage)
			name=$1; stage=$(power_policy_stage_path "$name" "$2") || return 2
			target=$(power_policy_source_path "$name") || return 2
			(set -o pipefail; node "$POWER_POLICY_JSON_HELPER" source-bytes "$target" "$name" | /usr/bin/sudo /usr/bin/install -T -o root -g root -m 0644 -- /dev/stdin "$stage") ;;
		mutate:publish) stage=$(power_policy_stage_path "$1" "$2") || return 2; target=$(power_policy_target_path "$1") || return 2; /usr/bin/sudo /usr/bin/mv --no-copy -fT -- "$stage" "$target" ;;
		mutate:remove) target=$(power_policy_target_path "$1") || return 2; /usr/bin/sudo /usr/bin/rm -f -- "$target" ;;
		mutate:restore)
			name=$1; stage=$(power_policy_stage_path "$name" "$2") || return 2; backup=$3; target=$(power_policy_target_path "$name") || return 2
			(set -o pipefail; node "$POWER_POLICY_JSON_HELPER" digest-bytes "$backup" "$4" | /usr/bin/sudo /usr/bin/install -T -o root -g root -m 0644 -- /dev/stdin "$stage") ;;
		mutate:cleanup) stage=$(power_policy_stage_path "$1" "$2") || return 2; /usr/bin/sudo /usr/bin/rm -f -- "$stage" ;;
		mutate:enable) /usr/bin/sudo /usr/bin/systemctl enable upower.service ;;
		mutate:start) /usr/bin/sudo /usr/bin/systemctl start upower.service ;;
		mutate:reload-logind) /usr/bin/sudo /usr/bin/systemctl reload systemd-logind.service ;;
		mutate:restart) /usr/bin/sudo /usr/bin/systemctl restart upower.service ;;
		mutate:restore-service)
			enabled=$1; active=$2
			if [[ $enabled == enabled ]]; then /usr/bin/sudo /usr/bin/systemctl enable upower.service; else /usr/bin/sudo /usr/bin/systemctl disable upower.service; fi &&
			if [[ $active == active ]]; then /usr/bin/sudo /usr/bin/systemctl restart upower.service; else /usr/bin/sudo /usr/bin/systemctl stop upower.service; fi ;;
		*) return 2 ;;
	esac
}

power_policy_source_path() { case $1 in upower) printf '%s\n' "$POWER_POLICY_UPOWER_SOURCE" ;; logind) printf '%s\n' "$POWER_POLICY_LOGIND_SOURCE" ;; *) return 2 ;; esac; }
power_policy_target_path() { case $1 in upower) printf '%s\n' "$POWER_POLICY_UPOWER_TARGET" ;; logind) printf '%s\n' "$POWER_POLICY_LOGIND_TARGET" ;; *) return 2 ;; esac; }
power_policy_source_id() { printf 'power-policy/%s.conf\n' "$1"; }
power_policy_stage_path() { local directory; directory=$(power_policy_target_path "$1") || return 1; printf '%s/.dotfiles-%s.stage\n' "${directory%/*}" "$2"; }
power_policy_backup_path() { printf '%s/backups/%s/%s.conf\n' "$POWER_POLICY_STATE_ROOT" "$1" "$2"; }
power_policy_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
power_policy_transaction() { printf '%s-%s-%04x%04x\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "$RANDOM" "$RANDOM"; }

power_policy_state_paths() {
	local state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
	while [[ $state_home != / && $state_home == */ ]]; do state_home=${state_home%/}; done
	[[ $state_home == /* ]] || { printf 'Error: laptop power-policy state requires an absolute XDG state home.\n' >&2; return 1; }
	POWER_POLICY_STATE_ROOT="$state_home/dotfiles/$POWER_POLICY_STATE_NAME"
	POWER_POLICY_ACTIVE_PATH="$POWER_POLICY_STATE_ROOT/active.json"
	POWER_POLICY_PENDING_PATH="$POWER_POLICY_STATE_ROOT/pending.json"
}

power_policy_path_components_safe() {
	local path=$1 owner=$2 component='' part metadata type uid gid mode
	[[ $path == /* ]] || return 1
	metadata=$(power_policy_stat_metadata / 2>/dev/null) || return 1
	IFS='|' read -r type uid gid mode <<<"$metadata"
	[[ $type == directory && ! -L / && $uid == 0 && $((8#$mode & 022)) == 0 ]] || return 1
	IFS=/ read -r -a parts <<<"${path#/}"
	for part in "${parts[@]}"; do
		[[ -n $part ]] || continue
		component+=/$part
		[[ -e $component || -L $component ]] || break
		metadata=$(power_policy_stat_metadata "$component" 2>/dev/null) || return 1
		IFS='|' read -r type uid gid mode <<<"$metadata"
		[[ $type == directory && ! -L $component ]] || return 1
		if [[ $component == /tmp && $uid == 0 && $mode == 1777 ]]; then continue; fi
		if [[ $owner == state ]]; then [[ $uid == 0 || $uid == "$EUID" ]] || return 1; else [[ $uid == 0 ]] || return 1; fi
		(( (8#$mode & 022) == 0 )) || return 1
	done
}

power_policy_fixed_parent_components_safe() { power_policy_path_components_safe "$1" root; }
power_policy_state_path_components_safe() { [[ $(power_policy_adapter inspect state-path-safe "$1") == safe ]]; }

power_policy_state_root_is_safe() {
	local path=$1 metadata type uid gid mode
	power_policy_state_path_components_safe "$path" || return 1
	[[ -e $path || -L $path ]] || return 0
	metadata=$(power_policy_stat_metadata "$path" 2>/dev/null) || return 1
	IFS='|' read -r type uid gid mode <<<"$metadata"
	[[ $type == directory && ! -L $path && $uid == "$EUID" && $mode == 700 ]]
}

power_policy_prepare_state_root() {
	local parent=${POWER_POLICY_STATE_ROOT%/*}
	power_policy_state_path_components_safe "$POWER_POLICY_STATE_ROOT" || { printf 'Error: laptop power-policy state path has an unsafe component.\n' >&2; return 1; }
	if [[ ! -e $POWER_POLICY_STATE_ROOT && ! -L $POWER_POLICY_STATE_ROOT ]]; then
		mkdir -p -m 0700 -- "$parent" || return 1
		power_policy_state_path_components_safe "$parent" || return 1
		mkdir -m 0700 -- "$POWER_POLICY_STATE_ROOT" || return 1
	fi
	power_policy_state_root_is_safe "$POWER_POLICY_STATE_ROOT" || { printf 'Error: laptop power-policy state must be a real invoking-user-owned 0700 directory.\n' >&2; return 1; }
}

power_policy_read_receipt() {
	local kind=$1 file=$2 metadata type uid gid mode result
	[[ -e $file || -L $file ]] || return 2
	metadata=$(power_policy_stat_metadata "$file" 2>/dev/null) || return 1
	IFS='|' read -r type uid gid mode <<<"$metadata"
	[[ $type == 'regular file' && ! -L $file && $uid == "$EUID" && $mode == 600 ]] || return 1
	result=$(node "$POWER_POLICY_JSON_HELPER" receipt "$file" "$kind" "$POWER_POLICY_STATE_ROOT") || return 1
	jq -c '.value' <<<"$result"
}

power_policy_read_state() {
	local failed=false saved_active saved_digest saved_backups
	POWER_POLICY_ACTIVE='' POWER_POLICY_PENDING='' POWER_POLICY_ACTIVE_DIGEST='' POWER_POLICY_PENDING_DIGEST='' POWER_POLICY_ACTIVE_BACKUPS='' POWER_POLICY_PENDING_BACKUPS='' POWER_POLICY_STATE_ERROR='' POWER_POLICY_ACTIVE_LABEL=absent POWER_POLICY_PENDING_LABEL=absent
	power_policy_state_root_is_safe "$POWER_POLICY_STATE_ROOT" || { POWER_POLICY_STATE_ERROR='unsafe state path'; POWER_POLICY_ACTIVE_LABEL=unavailable; POWER_POLICY_PENDING_LABEL=unavailable; printf 'Error: laptop power-policy state is unsafe.\n' >&2; return 1; }
	if [[ -e $POWER_POLICY_ACTIVE_PATH || -L $POWER_POLICY_ACTIVE_PATH ]]; then
		POWER_POLICY_ACTIVE_LABEL=invalid
		if POWER_POLICY_ACTIVE=$(power_policy_read_receipt active "$POWER_POLICY_ACTIVE_PATH") && POWER_POLICY_ACTIVE_DIGEST=$(node "$POWER_POLICY_JSON_HELPER" digest "$POWER_POLICY_ACTIVE_PATH" | jq -r .digest) && power_policy_active_backups_valid; then
			POWER_POLICY_ACTIVE_LABEL=valid
		else
			POWER_POLICY_ACTIVE='' POWER_POLICY_ACTIVE_DIGEST='' POWER_POLICY_ACTIVE_BACKUPS=''
			POWER_POLICY_STATE_ERROR+='invalid active receipt or backup; '
			failed=true
		fi
	fi
	if [[ -e $POWER_POLICY_PENDING_PATH || -L $POWER_POLICY_PENDING_PATH ]]; then
		POWER_POLICY_PENDING_LABEL=invalid
		if POWER_POLICY_PENDING=$(power_policy_read_receipt pending "$POWER_POLICY_PENDING_PATH") && POWER_POLICY_PENDING_DIGEST=$(node "$POWER_POLICY_JSON_HELPER" digest "$POWER_POLICY_PENDING_PATH" | jq -r .digest) && power_policy_pending_backups_valid; then
			if [[ $(jq -r '.prior_active != null' <<<"$POWER_POLICY_PENDING") == true ]]; then
				saved_active=$POWER_POLICY_ACTIVE; saved_digest=$POWER_POLICY_ACTIVE_DIGEST; saved_backups=$POWER_POLICY_ACTIVE_BACKUPS
				if POWER_POLICY_ACTIVE=$(jq -c .prior_active <<<"$POWER_POLICY_PENDING") && power_policy_active_backups_valid; then
					POWER_POLICY_ACTIVE=$saved_active POWER_POLICY_ACTIVE_DIGEST=$saved_digest POWER_POLICY_ACTIVE_BACKUPS=$saved_backups
				else
					POWER_POLICY_ACTIVE=$saved_active POWER_POLICY_ACTIVE_DIGEST=$saved_digest POWER_POLICY_ACTIVE_BACKUPS=$saved_backups
					POWER_POLICY_PENDING='' POWER_POLICY_PENDING_DIGEST='' POWER_POLICY_PENDING_BACKUPS=''
					POWER_POLICY_STATE_ERROR+='invalid pending active backup; '
					failed=true
				fi
			fi
			if [[ -n $POWER_POLICY_PENDING ]]; then POWER_POLICY_PENDING_LABEL=valid; fi
		else
			POWER_POLICY_PENDING='' POWER_POLICY_PENDING_DIGEST='' POWER_POLICY_PENDING_BACKUPS=''
			POWER_POLICY_STATE_ERROR+='invalid pending receipt or backup; '
			failed=true
		fi
	fi
	if [[ $failed == true ]]; then printf 'Error: laptop power-policy state is invalid: %s\n' "$POWER_POLICY_STATE_ERROR" >&2; return 1; fi
}

power_policy_write_receipt() {
	local kind=$1 value=$2 destination temporary
	destination=$POWER_POLICY_STATE_ROOT/$kind.json
	temporary=$(mktemp "$POWER_POLICY_STATE_ROOT/.${kind}.XXXXXX") || return 1
	chmod 0600 -- "$temporary" || { rm -f -- "$temporary"; return 1; }
	printf '%s\n' "$value" >"$temporary" || { rm -f -- "$temporary"; return 1; }
	node "$POWER_POLICY_JSON_HELPER" receipt "$temporary" "$kind" "$POWER_POLICY_STATE_ROOT" >/dev/null || { rm -f -- "$temporary"; return 1; }
	mv -fT -- "$temporary" "$destination"
}

power_policy_validate_sources() {
	local source result
	for source in upower logind; do
		result=$(node "$POWER_POLICY_JSON_HELPER" source "$(power_policy_source_path "$source")" "$source" 2>/dev/null) || { printf 'Error: invalid laptop power-policy source: %s\n' "$source" >&2; return 1; }
		case $source in upower) POWER_POLICY_UPOWER_DIGEST=$(jq -r .digest <<<"$result") ;; logind) POWER_POLICY_LOGIND_DIGEST=$(jq -r .digest <<<"$result") ;; esac
	done
}

validate_power_policy_sources() {
	(($# == 0)) || return 2
	power_policy_validate_sources || return 1
	printf 'UPower source: valid\nUPower source digest: %s\nlogind source: valid\nlogind source digest: %s\n' "$POWER_POLICY_UPOWER_DIGEST" "$POWER_POLICY_LOGIND_DIGEST"
}

power_policy_target_state() {
	local name=$1 value
	value=$(power_policy_adapter inspect target "$name") || return 1
	POWER_POLICY_TARGET["$name"]=$value
}

power_policy_target_safe() {
	local name=$1 state=${POWER_POLICY_TARGET[$1]-}
	[[ $(power_policy_adapter inspect target-parent-safe "$name") == safe ]] || return 1
	[[ $state == absent ]] && return 0
	[[ $state =~ ^regular\ file\|0\|0\|0?644\|[0-9a-f]{64}$ ]]
}

power_policy_target_matches() {
	local name=$1 state=$2 present digest current=${POWER_POLICY_TARGET[$name]-}
	present=$(jq -r .present <<<"$state") || return 1
	[[ $present == false ]] && [[ $current == absent ]] && return
	digest=$(jq -r .digest <<<"$state") || return 1
	[[ $current == "regular file|0|0|0644|$digest" || $current == "regular file|0|0|644|$digest" ]]
}

power_policy_backup_valid() {
	local state=$1 backup digest metadata type uid gid mode
	[[ $(jq -r .present <<<"$state") == true ]] || return 0
	backup=$(jq -r .backup_path <<<"$state"); digest=$(jq -r .digest <<<"$state")
	power_policy_state_path_components_safe "${backup%/*}" || return 1
	metadata=$(power_policy_stat_metadata "$backup" 2>/dev/null) || return 1
	IFS='|' read -r type uid gid mode <<<"$metadata"
	[[ $type == 'regular file' && ! -L $backup && $uid == "$EUID" && $mode == 600 && $(node "$POWER_POLICY_JSON_HELPER" digest "$backup" | jq -r .digest) == "$digest" ]]
}

power_policy_active_backups_valid() {
	local name original backup fingerprint=''
	[[ -n $POWER_POLICY_ACTIVE ]] || return 0
	for name in upower logind; do
		original=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .original' <<<"$POWER_POLICY_ACTIVE") || return 1
		power_policy_backup_valid "$original" || return 1
		if [[ $(jq -r .present <<<"$original") == true ]]; then
			backup=$(jq -r .backup_path <<<"$original")
			fingerprint+="$name:$(node "$POWER_POLICY_JSON_HELPER" digest "$backup" | jq -r .digest)|"
		fi
	done
	POWER_POLICY_ACTIVE_BACKUPS=$fingerprint
}

power_policy_pending_backups_valid() {
	local name prior backup fingerprint=''
	[[ -n $POWER_POLICY_PENDING ]] || return 0
	for name in upower logind; do
		prior=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .prior' <<<"$POWER_POLICY_PENDING") || return 1
		power_policy_backup_valid "$prior" || return 1
		if [[ $(jq -r .present <<<"$prior") == true ]]; then
			backup=$(jq -r .backup_path <<<"$prior")
			fingerprint+="$name:$(node "$POWER_POLICY_JSON_HELPER" digest "$backup" | jq -r .digest)|"
		fi
	done
	POWER_POLICY_PENDING_BACKUPS=$fingerprint
}

power_policy_active_sources_match() {
	local name digest
	[[ -n $POWER_POLICY_ACTIVE ]] || return 1
	for name in upower logind; do
		digest=$(jq -r --arg name "$name" '.targets[] | select(.name == $name) | .digest' <<<"$POWER_POLICY_ACTIVE") || return 1
		[[ $digest == "$(power_policy_digest_for "$name")" ]] || return 1
	done
}

power_policy_inspect_observed_runtime() {
	POWER_POLICY_VERSION=$(power_policy_adapter inspect version) || return 1
	POWER_POLICY_SERVICE=$(power_policy_adapter inspect service) || return 1
	POWER_POLICY_SLEEP_LOCK=$(power_policy_adapter inspect sleep-lock) || return 1
	POWER_POLICY_CAN_HIBERNATE=$(power_policy_adapter inspect can-hibernate) || return 1
	POWER_POLICY_INHIBIT_DELAY_US=$(power_policy_adapter inspect inhibit-delay) || return 1
	if power_policy_adapter inspect battery; then POWER_POLICY_BATTERY=yes; else POWER_POLICY_BATTERY=no; fi
	if power_policy_adapter inspect hibernation; then POWER_POLICY_HIBERNATION=yes; else POWER_POLICY_HIBERNATION=no; fi
	POWER_POLICY_LOGIND_RUNTIME=$(power_policy_adapter inspect logind-runtime) || return 1
	power_policy_target_state upower && power_policy_target_state logind || return 1
	if [[ $POWER_POLICY_SERVICE == *'|active' ]]; then POWER_POLICY_CRITICAL_ACTION=$(power_policy_adapter inspect critical-action) || return 1; else POWER_POLICY_CRITICAL_ACTION=inactive; fi
}

power_policy_inspect_runtime() {
	power_policy_inspect_observed_runtime || return 1
	POWER_POLICY_UPOWER_EFFECTIVE=$(power_policy_adapter inspect upower-effective) || return 1
	POWER_POLICY_LOGIND_EFFECTIVE=$(power_policy_adapter inspect logind-effective) || return 1
}

power_policy_supported() { [[ ${POWER_POLICY_VERSION%%.*} == "${SUPPORTED_OMARCHY_VERSION:-4}" ]]; }
power_policy_eligible() {
	power_policy_supported || { printf 'Error: laptop power policy supports Omarchy %s, but detected %s.\n' "${SUPPORTED_OMARCHY_VERSION:-4}" "$POWER_POLICY_VERSION" >&2; return 1; }
	[[ $POWER_POLICY_BATTERY == yes ]] || { printf 'Ineligible laptop power-policy system: omarchy-battery-present did not find a built-in laptop battery.\n' >&2; return "$POWER_POLICY_OUTCOME_INELIGIBLE"; }
	[[ $POWER_POLICY_HIBERNATION == yes ]] || { printf 'Ineligible laptop power-policy system: omarchy-hibernation-available did not report working hibernation.\n' >&2; return "$POWER_POLICY_OUTCOME_INELIGIBLE"; }
	[[ $POWER_POLICY_CAN_HIBERNATE == yes ]] || { printf 'Error: logind CanHibernate must report "yes".\n' >&2; return 1; }
	[[ $POWER_POLICY_SLEEP_LOCK == 'enabled|active|present' ]] || { printf 'Error: Omarchy sleep lock must be enabled, active, and hold its delay inhibitor.\n' >&2; return 1; }
}

power_policy_desired_effective() {
	jq -e '.effective.UsePercentageForPolicy == "true" and .effective.PercentageLow == "20.0" and .effective.PercentageCritical == "10.0" and .effective.PercentageAction == "5.0" and .effective.CriticalPowerAction == "Hibernate"' <<<"$1" >/dev/null &&
	jq -e '.effective.HandleLidSwitch == "hibernate" and .effective.HandleLidSwitchExternalPower == "suspend" and .effective.HandleLidSwitchDocked == "ignore"' <<<"$2" >/dev/null
}

power_policy_runtime_desired() {
	[[ $POWER_POLICY_SERVICE == 'enabled|active' && $POWER_POLICY_CRITICAL_ACTION == Hibernate && $POWER_POLICY_LOGIND_RUNTIME == 'hibernate|suspend|ignore' ]]
}

power_policy_runtime_restored() {
	local raw lid external docked runtime_lid runtime_external runtime_docked
	lid=$(jq -r '.effective.HandleLidSwitch // "suspend"' <<<"$POWER_POLICY_LOGIND_EFFECTIVE") || return 1
	external=$(jq -r '.effective.HandleLidSwitchExternalPower // empty' <<<"$POWER_POLICY_LOGIND_EFFECTIVE") || return 1
	docked=$(jq -r '.effective.HandleLidSwitchDocked // "ignore"' <<<"$POWER_POLICY_LOGIND_EFFECTIVE") || return 1
	IFS='|' read -r runtime_lid runtime_external runtime_docked <<<"$POWER_POLICY_LOGIND_RUNTIME"
	[[ $runtime_lid == "$lid" && $runtime_external == "$external" && $runtime_docked == "$docked" ]] || return 1
	[[ $POWER_POLICY_SERVICE == *'|active' ]] || return 0
	raw=$(jq -r '.effective.CriticalPowerAction // ""' <<<"$POWER_POLICY_UPOWER_EFFECTIVE") || return 1
	if [[ $raw == PowerOff ]]; then [[ $POWER_POLICY_CRITICAL_ACTION == PowerOff ]]; else [[ $POWER_POLICY_CRITICAL_ACTION =~ ^(HybridSleep|Hibernate|PowerOff|Suspend|Ignore|Sleep)$ ]]; fi
}

power_policy_plan_apply() {
	POWER_POLICY_UPOWER_PLAN=$(power_policy_adapter inspect upower-plan "$POWER_POLICY_UPOWER_SOURCE") || return 1
	POWER_POLICY_LOGIND_PLAN=$(power_policy_adapter inspect logind-plan "$POWER_POLICY_LOGIND_SOURCE") || return 1
	power_policy_desired_effective "$POWER_POLICY_UPOWER_PLAN" "$POWER_POLICY_LOGIND_PLAN" || { printf 'Error: a later competing drop-in prevents the fixed policy from being effective.\n' >&2; return 1; }
}

power_policy_active_targets_match() {
	local name state
	[[ -n $POWER_POLICY_ACTIVE ]] || return 1
	for name in upower logind; do state=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | {present:true,digest:.digest,backup_path:null}' <<<"$POWER_POLICY_ACTIVE") || return 1; power_policy_target_matches "$name" "$state" || return 1; done
}

power_policy_active_managed_target_drift() {
	local name state current
	[[ -n $POWER_POLICY_ACTIVE ]] || return 1
	for name in upower logind; do
		state=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | {present:true,digest:.digest,backup_path:null}' <<<"$POWER_POLICY_ACTIVE") || return 1
		current=${POWER_POLICY_TARGET[$name]-}
		[[ $current == absent || $current =~ ^regular\ file\|0\|0\|0?644\|[0-9a-f]{64}$ ]] && ! power_policy_target_matches "$name" "$state" && return 0
	done
	return 1
}

power_policy_active_exact() {
	power_policy_active_targets_match && power_policy_active_backups_valid && power_policy_active_sources_match && power_policy_desired_effective "$POWER_POLICY_UPOWER_EFFECTIVE" "$POWER_POLICY_LOGIND_EFFECTIVE" && power_policy_runtime_desired && power_policy_eligible
}

power_policy_desired_targets_match() {
	local name expected
	for name in upower logind; do
		expected=$(power_policy_digest_for "$name") || return 1
		[[ ${POWER_POLICY_TARGET[$name]-} == "regular file|0|0|0644|$expected" || ${POWER_POLICY_TARGET[$name]-} == "regular file|0|0|644|$expected" ]] || return 1
	done
}

power_policy_snapshot() {
	jq -cn --arg version "$POWER_POLICY_VERSION" --arg sources "$POWER_POLICY_UPOWER_DIGEST|$POWER_POLICY_LOGIND_DIGEST" --arg active "$POWER_POLICY_ACTIVE_DIGEST" --arg backups "$POWER_POLICY_ACTIVE_BACKUPS" --arg service "$POWER_POLICY_SERVICE" --arg battery "$POWER_POLICY_BATTERY" --arg hibernation "$POWER_POLICY_HIBERNATION" --arg can_hibernate "$POWER_POLICY_CAN_HIBERNATE" --arg sleep_lock "$POWER_POLICY_SLEEP_LOCK" --arg critical "$POWER_POLICY_CRITICAL_ACTION" --arg lid "$POWER_POLICY_LOGIND_RUNTIME" --arg delay "$POWER_POLICY_INHIBIT_DELAY_US" --arg targets "${POWER_POLICY_TARGET[upower]}|${POWER_POLICY_TARGET[logind]}" --arg upower "$POWER_POLICY_UPOWER_EFFECTIVE" --arg logind "$POWER_POLICY_LOGIND_EFFECTIVE" --arg upower_plan "$POWER_POLICY_UPOWER_PLAN" --arg logind_plan "$POWER_POLICY_LOGIND_PLAN" '{version:$version,sources:$sources,active:$active,backups:$backups,service:$service,battery:$battery,hibernation:$hibernation,can_hibernate:$can_hibernate,sleep_lock:$sleep_lock,critical:$critical,lid:$lid,delay:$delay,targets:$targets,upower:$upower,logind:$logind,upower_plan:$upower_plan,logind_plan:$logind_plan}'
}

power_policy_collect_apply_snapshot() {
	power_policy_read_state || return 1
	power_policy_validate_sources || return 1
	power_policy_inspect_runtime || return 1
	power_policy_eligible || return $?
	local name
	for name in upower logind; do power_policy_target_safe "$name" || { printf 'Error: %s target must be absent or a root:root 0644 regular file.\n' "$name" >&2; return 1; }; done
	power_policy_plan_apply
}

power_policy_print_apply_plan() {
	local transaction=$1 name source target
	printf 'Plan: apply laptop power policy\nSupported Omarchy: %s\nDetected Omarchy: %s\n' "${SUPPORTED_OMARCHY_VERSION:-4}" "$POWER_POLICY_VERSION"
	printf '  receipts: active=%s pending=%s\n' "$POWER_POLICY_ACTIVE_PATH" "$POWER_POLICY_PENDING_PATH"
	for name in upower logind; do source=$(power_policy_source_path "$name"); target=$(power_policy_target_path "$name"); printf '  %s: source=%s digest=%s target=%s current=%s stage=%s backup=%s\n' "$name" "$source" "$(power_policy_digest_for "$name")" "$target" "${POWER_POLICY_TARGET[$name]}" "$(power_policy_stage_path "$name" "$transaction")" "$(power_policy_backup_path "$transaction" "$name")"; done
	printf '  UPower relevant settings: %s\n' "$(power_policy_plan_classification "$POWER_POLICY_UPOWER_PLAN")"
	printf '  logind relevant settings: %s\n' "$(power_policy_plan_classification "$POWER_POLICY_LOGIND_PLAN")"
	printf '  service: %s -> enabled|active; reload systemd-logind and restart UPower\n  verification: desired merged settings, critical action=Hibernate, lid=hibernate|suspend|ignore, and unchanged inhibit delay\n  rollback: restore prior targets, service, and active receipt from pending evidence.\n  eventual Remove: restore the recorded prior targets and original UPower service state.\n' "$POWER_POLICY_SERVICE"
}

power_policy_plan_summary() { jq -r '[.files[] | "\(.path):\([.entries[] | "\(.key)=\(.value)"] | join(","))"] | join("; ") // "none"' <<<"$1"; }
power_policy_managed_effective_values() { jq -c '.effective | del(.InhibitDelayMaxSec)' <<<"$1"; }
power_policy_plan_classification() { jq -r '.effective as $effective | [.files[] | .path as $path | .entries[] | select(.key != "InhibitDelayMaxSec") | "\($path):\(.key)=\(.value) [\(if $effective[.key] == .value then "retained" else "overridden" end)]"] | if length == 0 then "none" else join("; ") end' <<<"$1"; }

power_policy_original_summary() {
	local state=$1
	if [[ $(jq -r .present <<<"$state") == true ]]; then printf 'present digest=%s backup=%s' "$(jq -r .digest <<<"$state")" "$(jq -r .backup_path <<<"$state")"; else printf 'absent'; fi
}

power_policy_digest_for() {
	local name=$1 digest
	case $name in
		upower) digest=$POWER_POLICY_UPOWER_DIGEST ;;
		logind) digest=$POWER_POLICY_LOGIND_DIGEST ;;
		*) return 2 ;;
	esac
	if [[ -z $digest && -n $POWER_POLICY_ACTIVE ]]; then
		digest=$(jq -r --arg name "$name" '.targets[] | select(.name == $name) | .digest' <<<"$POWER_POLICY_ACTIVE") || return 1
	fi
	[[ $digest =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s\n' "$digest"
}

power_policy_make_state() {
	local name=$1 transaction=$2 existing=$3 digest backup
	[[ $existing == absent ]] && { printf '{"present":false,"digest":null,"backup_path":null}\n'; return; }
	digest=${existing##*|}; backup=$(power_policy_backup_path "$transaction" "$name")
	jq -cn --arg digest "$digest" --arg backup "$backup" '{present:true,digest:$digest,backup_path:$backup}'
}

power_policy_original_state() {
	local name=$1 transaction=$2
	if [[ -n $POWER_POLICY_PENDING ]]; then
		jq -c --arg name "$name" '.targets[] | select(.name == $name) | .original' <<<"$POWER_POLICY_PENDING"
	elif [[ -n $POWER_POLICY_ACTIVE ]]; then
		jq -c --arg name "$name" '.targets[] | select(.name == $name) | .original' <<<"$POWER_POLICY_ACTIVE"
	else
		power_policy_make_state "$name" "$transaction" "${POWER_POLICY_TARGET[$name]}"
	fi
}

power_policy_backup_prior_targets() {
	local transaction=$1 name state backup
	power_policy_state_path_components_safe "$POWER_POLICY_STATE_ROOT/backups/$transaction" || return 1
	mkdir -m 0700 -p -- "$POWER_POLICY_STATE_ROOT/backups/$transaction" || return 1
	power_policy_state_path_components_safe "$POWER_POLICY_STATE_ROOT/backups/$transaction" || return 1
	for name in upower logind; do
		state=${POWER_POLICY_TARGET[$name]}
		[[ $state == absent ]] && continue
		backup=$(power_policy_backup_path "$transaction" "$name")
		power_policy_adapter mutate backup "$name" "$backup" || return 1
		power_policy_backup_valid "$(power_policy_make_state "$name" "$transaction" "$state")" || return 1
	done
}

power_policy_pending_json() {
	local operation=$1 transaction=$2 targets='[]' name prior original desired
	for name in upower logind; do
		prior=$(power_policy_make_state "$name" "$transaction" "${POWER_POLICY_TARGET[$name]}") || return 1
		original=$(power_policy_original_state "$name" "$transaction") || return 1
		desired=$(power_policy_digest_for "$name")
		targets=$(jq -c --arg name "$name" --arg target "$(power_policy_target_path "$name")" --arg digest "$desired" --arg stage "$(power_policy_stage_path "$name" "$transaction")" --argjson prior "$prior" --argjson original "$original" '. + [{name:$name,target:$target,desired_digest:$digest,stage_path:$stage,prior:$prior,original:$original}]' <<<"$targets") || return 1
	done
	[[ $POWER_POLICY_INHIBIT_DELAY_US =~ ^[0-9]+$ ]] || return 1
	jq -cn --arg operation "$operation" --arg transaction "$transaction" --argjson targets "$targets" --arg service "$POWER_POLICY_SERVICE" --argjson delay "$POWER_POLICY_INHIBIT_DELAY_US" --argjson original_service "$(if [[ -n $POWER_POLICY_ACTIVE ]]; then jq -c .service_original <<<"$POWER_POLICY_ACTIVE"; else jq -cn --arg service "$POWER_POLICY_SERVICE" '$service | split("|") | {enabled:.[0],active:.[1]}'; fi)" --argjson active "${POWER_POLICY_ACTIVE:-null}" '
		($service | split("|")) as $prior | {schema_version:1,kind:"pending",operation:$operation,phase:"prepared",transaction_id:$transaction,targets:$targets,service_prior:{enabled:$prior[0],active:$prior[1]},service_original:$original_service,inhibit_delay_prior:$delay,prior_active:$active}'
}

power_policy_publish_active() {
	local transaction=$1 targets='[]' name original service_original
	for name in upower logind; do original=$(power_policy_original_state "$name" "$transaction") || return 1; targets=$(jq -c --arg name "$name" --arg source "$(power_policy_source_id "$name")" --arg target "$(power_policy_target_path "$name")" --arg digest "$(power_policy_digest_for "$name")" --argjson original "$original" '. + [{name:$name,source:$source,target:$target,digest:$digest,original:$original}]' <<<"$targets") || return 1; done
	service_original=$(jq -c .service_original <<<"$POWER_POLICY_PENDING") || return 1
	jq -cn --arg transaction "$transaction" --arg now "$(power_policy_now)" --argjson targets "$targets" --argjson service_original "$service_original" '{schema_version:1,kind:"active",transaction_id:$transaction,activated_at:$now,targets:$targets,service_original:$service_original}'
}

power_policy_pending_set_phase() {
	POWER_POLICY_PENDING=$(jq -c '.phase = "mutating"' <<<"$POWER_POLICY_PENDING") || return 1
	power_policy_write_receipt pending "$POWER_POLICY_PENDING"
}

power_policy_stage_valid() {
	local name=$1 transaction=$2 expected=$3 stage
	stage=$(power_policy_adapter inspect stage "$name" "$transaction") || return 1
	[[ $stage == "regular file|0|0|0644|$expected" || $stage == "regular file|0|0|644|$expected" ]]
}

power_policy_pending_target_allowed() {
	local name=$1 target prior original current
	target=$(jq -c --arg name "$name" '.targets[] | select(.name == $name)' <<<"$POWER_POLICY_PENDING") || return 1
	prior=$(jq -c .prior <<<"$target"); original=$(jq -c .original <<<"$target")
	power_policy_target_matches "$name" "$prior" && return 0
	power_policy_target_matches "$name" "$original" && return 0
	current=${POWER_POLICY_TARGET[$name]}
	[[ $current == "regular file|0|0|0644|$(jq -r .desired_digest <<<"$target")" || $current == "regular file|0|0|644|$(jq -r .desired_digest <<<"$target")" ]]
}

power_policy_pending_delay_matches() {
	[[ $POWER_POLICY_INHIBIT_DELAY_US == "$(jq -r .inhibit_delay_prior <<<"$POWER_POLICY_PENDING")" ]]
}

power_policy_pending_prior_active_matches() {
	local prior current
	prior=$(jq -cS .prior_active <<<"$POWER_POLICY_PENDING") || return 1
	if [[ $prior == null ]]; then [[ -z $POWER_POLICY_ACTIVE ]]; return; fi
	[[ -n $POWER_POLICY_ACTIVE ]] || return 1
	current=$(jq -cS . <<<"$POWER_POLICY_ACTIVE") || return 1
	[[ $current == "$prior" ]]
}

power_policy_prepared_pending_matches() {
	local name prior enabled active
	power_policy_inspect_observed_runtime || return 1
	for name in upower logind; do
		prior=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .prior' <<<"$POWER_POLICY_PENDING") || return 1
		power_policy_target_safe "$name" && power_policy_target_matches "$name" "$prior" || return 1
	done
	IFS='|' read -r enabled active <<<"$(jq -r '.service_prior | "\(.enabled)|\(.active)"' <<<"$POWER_POLICY_PENDING")"
	[[ $POWER_POLICY_SERVICE == "$enabled|$active" ]] && power_policy_pending_delay_matches && power_policy_pending_prior_active_matches
}

power_policy_terminal_apply_receipt_matches() {
	local name pending_target active_target
	[[ $(jq -r .operation <<<"$POWER_POLICY_PENDING") == apply && $(jq -r .phase <<<"$POWER_POLICY_PENDING") == mutating && -n $POWER_POLICY_ACTIVE && $(jq -r .transaction_id <<<"$POWER_POLICY_ACTIVE") == "$(jq -r .transaction_id <<<"$POWER_POLICY_PENDING")" ]] || return 1
	for name in upower logind; do
		pending_target=$(jq -c --arg name "$name" '.targets[] | select(.name == $name)' <<<"$POWER_POLICY_PENDING") || return 1
		active_target=$(jq -c --arg name "$name" '.targets[] | select(.name == $name)' <<<"$POWER_POLICY_ACTIVE") || return 1
		[[ $(jq -r .target <<<"$active_target") == "$(jq -r .target <<<"$pending_target")" && $(jq -r .source <<<"$active_target") == "$(power_policy_source_id "$name")" && $(jq -r .digest <<<"$active_target") == "$(jq -r .desired_digest <<<"$pending_target")" && $(jq -cS .original <<<"$active_target") == "$(jq -cS .original <<<"$pending_target")" ]] || return 1
	done
}

power_policy_terminal_apply_matches() {
	local name
	power_policy_terminal_apply_receipt_matches || return 1
	power_policy_inspect_runtime || return 1
	for name in upower logind; do power_policy_target_safe "$name" || return 1; done
	power_policy_active_targets_match && power_policy_active_backups_valid && power_policy_pending_backups_valid && power_policy_desired_effective "$POWER_POLICY_UPOWER_EFFECTIVE" "$POWER_POLICY_LOGIND_EFFECTIVE" && power_policy_runtime_desired && power_policy_pending_delay_matches
}

power_policy_terminal_remove_matches() {
	local name original enabled active
	[[ $(jq -r .operation <<<"$POWER_POLICY_PENDING") == remove && $(jq -r .phase <<<"$POWER_POLICY_PENDING") == mutating && -z $POWER_POLICY_ACTIVE ]] || return 1
	power_policy_inspect_runtime || return 1
	for name in upower logind; do
		original=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .original' <<<"$POWER_POLICY_PENDING") || return 1
		power_policy_target_safe "$name" && power_policy_target_matches "$name" "$original" || return 1
	done
	IFS='|' read -r enabled active <<<"$(jq -r '.service_original | "\(.enabled)|\(.active)"' <<<"$POWER_POLICY_PENDING")"
	[[ $POWER_POLICY_SERVICE == "$enabled|$active" ]] && power_policy_pending_backups_valid && power_policy_runtime_restored && power_policy_pending_delay_matches
}

power_policy_complete_terminal_recovery() {
	local operation=$1
	printf 'Plan: complete interrupted %s receipt cleanup\n  pending receipt=%s\n  behavior: remove only pending evidence; no privilege or system mutation.\n' "$operation" "$POWER_POLICY_PENDING_PATH"
	if ! wizard_confirm 'Complete this interrupted laptop power-policy receipt cleanup?'; then POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_RECOVERY_DECLINED; printf 'Recovery declined; pending evidence is unchanged.\n'; return "$POWER_POLICY_OUTCOME_DECLINED"; fi
	rm -f -- "$POWER_POLICY_PENDING_PATH" || return 1
	POWER_POLICY_PENDING=''
	POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_RECOVERY_COMPLETED
	printf 'Completed %s recovery; removed terminal pending evidence. Run the requested operation again.\n' "$operation"
}

power_policy_recovery_snapshot() {
	jq -cn --arg active "$POWER_POLICY_ACTIVE_DIGEST" --arg pending "$POWER_POLICY_PENDING_DIGEST" --arg active_backups "$POWER_POLICY_ACTIVE_BACKUPS" --arg pending_backups "$POWER_POLICY_PENDING_BACKUPS" --arg service "$POWER_POLICY_SERVICE" --arg critical "$POWER_POLICY_CRITICAL_ACTION" --arg lid "$POWER_POLICY_LOGIND_RUNTIME" --arg delay "$POWER_POLICY_INHIBIT_DELAY_US" --arg targets "${POWER_POLICY_TARGET[upower]}|${POWER_POLICY_TARGET[logind]}" --arg upower "$POWER_POLICY_UPOWER_EFFECTIVE" --arg logind "$POWER_POLICY_LOGIND_EFFECTIVE" '{active:$active,pending:$pending,active_backups:$active_backups,pending_backups:$pending_backups,service:$service,critical:$critical,lid:$lid,delay:$delay,targets:$targets,upower:$upower,logind:$logind}'
}

power_policy_collect_recovery_snapshot() {
	local name
	power_policy_read_state || return 1
	[[ -n $POWER_POLICY_PENDING ]] || return 1
	power_policy_inspect_runtime || return 1
	for name in upower logind; do
		power_policy_target_safe "$name" && power_policy_pending_target_allowed "$name" || return 1
	done
	power_policy_pending_backups_valid && power_policy_pending_delay_matches && power_policy_pending_prior_active_matches
}

power_policy_print_recovery_plan() {
	local transaction=$1 operation=$2 name target prior
	printf 'Plan: recover interrupted laptop power-policy transaction\n  operation=%s transaction=%s\n' "$operation" "$transaction"
	for name in upower logind; do
		target=$(jq -c --arg name "$name" '.targets[] | select(.name == $name)' <<<"$POWER_POLICY_PENDING")
		prior=$(jq -c .prior <<<"$target")
		if [[ $(jq -r .present <<<"$prior") == true ]]; then
			printf '  %s: parent-safety=verified transaction-allowed current=%s restore backup=%s digest=%s through stage=%s\n' "$name" "${POWER_POLICY_TARGET[$name]}" "$(jq -r .backup_path <<<"$prior")" "$(jq -r .digest <<<"$prior")" "$(jq -r .stage_path <<<"$target")"
		else
			printf '  %s: parent-safety=verified transaction-allowed current=%s remove target; cleanup stage=%s\n' "$name" "${POWER_POLICY_TARGET[$name]}" "$(jq -r .stage_path <<<"$target")"
		fi
	done
	printf '  current service=%s critical action=%s lid=%s inhibit delay=%s\n' "$POWER_POLICY_SERVICE" "$POWER_POLICY_CRITICAL_ACTION" "$POWER_POLICY_LOGIND_RUNTIME" "$POWER_POLICY_INHIBIT_DELAY_US"
	printf '  current receipts: active=%s pending=%s pending backups=%s\n' "${POWER_POLICY_ACTIVE_DIGEST:-absent}" "$POWER_POLICY_PENDING_DIGEST" "${POWER_POLICY_PENDING_BACKUPS:-none}"
	printf '  current UPower merged values: %s\n  current UPower relevant files/settings: %s\n' "$(power_policy_managed_effective_values "$POWER_POLICY_UPOWER_EFFECTIVE")" "$(power_policy_plan_classification "$POWER_POLICY_UPOWER_EFFECTIVE")"
	printf '  current logind merged values: %s\n  current logind relevant files/settings: %s\n' "$(power_policy_managed_effective_values "$POWER_POLICY_LOGIND_EFFECTIVE")" "$(power_policy_plan_classification "$POWER_POLICY_LOGIND_EFFECTIVE")"
	printf '  service: restore %s\n  receipt: restore prior active receipt and remove pending evidence\n  behavior: stop after recovery; run the requested operation again.\n' "$(jq -r '.service_prior | "\(.enabled)|\(.active)"' <<<"$POWER_POLICY_PENDING")"
}

power_policy_restore_pending_receipt() {
	local previous
	previous=$(jq -c .prior_active <<<"$POWER_POLICY_PENDING") || return 1
	if [[ $previous == null ]]; then rm -f -- "$POWER_POLICY_ACTIVE_PATH"; else power_policy_write_receipt active "$previous"; fi
}

power_policy_rollback_pending() {
	local transaction name target prior backup enabled active failed=''
	transaction=$(jq -r .transaction_id <<<"$POWER_POLICY_PENDING") || return 1
	for name in upower logind; do
		power_policy_target_state "$name" || { failed="inspect-$name"; break; }
		power_policy_target_safe "$name" || { failed="unsafe-$name"; break; }
		power_policy_pending_target_allowed "$name" || { failed="conflict-$name"; break; }
		target=$(jq -c --arg name "$name" '.targets[] | select(.name == $name)' <<<"$POWER_POLICY_PENDING") || { failed="receipt-$name"; break; }
		prior=$(jq -c .prior <<<"$target")
		if [[ $(jq -r .present <<<"$prior") == true ]]; then backup=$(jq -r .backup_path <<<"$prior"); power_policy_backup_valid "$prior" && power_policy_adapter mutate restore "$name" "$transaction" "$backup" "$(jq -r .digest <<<"$prior")" && power_policy_stage_valid "$name" "$transaction" "$(jq -r .digest <<<"$prior")" && power_policy_adapter mutate publish "$name" "$transaction" || { failed="restore-$name"; break; }; else power_policy_adapter mutate remove "$name" || { failed="remove-$name"; break; }; fi
	done
	if [[ -z $failed ]]; then
		power_policy_adapter mutate reload-logind || failed=reload-logind
		IFS='|' read -r enabled active <<<"$(jq -r '.service_prior | "\(.enabled)|\(.active)"' <<<"$POWER_POLICY_PENDING")"
		[[ -n $failed ]] || power_policy_adapter mutate restore-service "$enabled" "$active" || failed=restore-service
	fi
	[[ -n $failed ]] || power_policy_inspect_runtime || failed=verify-runtime
	if [[ -z $failed ]]; then
		for name in upower logind; do power_policy_target_state "$name" || { failed="verify-$name"; break; }; prior=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .prior' <<<"$POWER_POLICY_PENDING"); power_policy_target_matches "$name" "$prior" || { failed="verify-$name"; break; }; done
	fi
	if [[ -z $failed ]]; then
		[[ $POWER_POLICY_SERVICE == "$enabled|$active" ]] && power_policy_runtime_restored && power_policy_pending_delay_matches || failed=verify-service
	fi
	if [[ -z $failed ]]; then power_policy_restore_pending_receipt || failed=restore-active; fi
	for name in upower logind; do power_policy_adapter mutate cleanup "$name" "$transaction" || { [[ -n $failed ]] || failed="cleanup-$name"; }; done
	if [[ -n $failed ]]; then printf 'Recovery failed at %s; pending.json and transaction backups are retained: %s/backups/%s\n' "$failed" "$POWER_POLICY_STATE_ROOT" "$transaction" >&2; return 1; fi
	rm -f -- "$POWER_POLICY_PENDING_PATH" || { printf 'Recovery failed at remove-pending; pending.json and transaction backups are retained: %s/backups/%s\n' "$POWER_POLICY_STATE_ROOT" "$transaction" >&2; return 1; }
	POWER_POLICY_PENDING=''
}

power_policy_recover() {
	local transaction operation snapshot
	operation=$(jq -r .operation <<<"$POWER_POLICY_PENDING"); transaction=$(jq -r .transaction_id <<<"$POWER_POLICY_PENDING")
	if [[ $(jq -r .phase <<<"$POWER_POLICY_PENDING") == prepared ]]; then
		power_policy_prepared_pending_matches || { printf 'Error: prepared laptop power-policy transaction no longer matches its recorded pre-operation state.\n' >&2; return 1; }
		rm -f -- "$POWER_POLICY_PENDING_PATH" || return 1
		POWER_POLICY_PENDING=''
		POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_RECOVERY_COMPLETED
		printf 'Recovered prepared laptop power-policy transaction; no system mutation was needed. Run the requested operation again.\n'
		return 0
	fi
	if power_policy_terminal_apply_matches; then power_policy_complete_terminal_recovery Apply; return $?; fi
	if power_policy_terminal_remove_matches; then power_policy_complete_terminal_recovery Remove; return $?; fi
	power_policy_collect_recovery_snapshot || { printf 'Error: current laptop power-policy recovery state is unsafe or conflicting.\n' >&2; return 1; }
	snapshot=$(power_policy_recovery_snapshot) || return 1
	power_policy_print_recovery_plan "$transaction" "$operation"
	if ! wizard_confirm 'Recover this interrupted laptop power-policy transaction?'; then POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_RECOVERY_DECLINED; printf 'Recovery declined; pending evidence is unchanged.\n'; return "$POWER_POLICY_OUTCOME_DECLINED"; fi
	power_policy_adapter mutate acquire || return 1
	power_policy_collect_recovery_snapshot && [[ $(power_policy_recovery_snapshot) == "$snapshot" ]] || { printf 'Error: recovery inputs changed after confirmation.\n' >&2; return 1; }
	power_policy_rollback_pending || return 1
	POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_RECOVERY_COMPLETED
	printf 'Recovered interrupted laptop power-policy transaction. Run the requested operation again.\n'
}

power_policy_apply_mutation() {
	local transaction=$1 active
	power_policy_pending_set_phase || return 1
	for active in upower logind; do power_policy_adapter mutate stage "$active" "$transaction" || return 1; power_policy_stage_valid "$active" "$transaction" "$(power_policy_digest_for "$active")" || return 1; done
	for active in upower logind; do power_policy_adapter mutate publish "$active" "$transaction" || return 1; done
	power_policy_adapter mutate enable && power_policy_adapter mutate start && power_policy_adapter mutate reload-logind && power_policy_adapter mutate restart
}

apply_power_policy() {
	(($# == 0)) || return 2
	POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_ORDINARY
	power_policy_state_paths || return 1; power_policy_adapter lock exclusive || return 1
	local outcome=0 transaction snapshot pending active
	power_policy_read_state || outcome=1
	if ((outcome == 0)) && [[ -n $POWER_POLICY_PENDING ]]; then
		POWER_POLICY_VERSION=$(power_policy_adapter inspect version) || outcome=1
		if ((outcome == 0)) && ! power_policy_supported; then printf 'Error: laptop power policy supports Omarchy %s, but detected %s.\n' "${SUPPORTED_OMARCHY_VERSION:-4}" "$POWER_POLICY_VERSION" >&2; outcome=1; fi
		if ((outcome == 0)); then power_policy_recover || outcome=$?; fi
		power_policy_adapter lock release
		return "$outcome"
	fi
	if ((outcome == 0)) && power_policy_collect_apply_snapshot; then :; else outcome=$?; fi
	if ((outcome == 0)) && [[ -n $POWER_POLICY_ACTIVE ]] && power_policy_active_exact; then printf 'Laptop power policy is already exact and active; no confirmation, privilege, backup, receipt, reload, or restart is needed.\n'; power_policy_adapter lock release; return 0; fi
	((outcome == 0)) || { power_policy_adapter lock release; return "$outcome"; }
	transaction=$(power_policy_transaction); snapshot=$(power_policy_snapshot)
	power_policy_print_apply_plan "$transaction"
	if ! wizard_confirm 'Apply this complete laptop power-policy plan?'; then printf 'No changes made.\n'; power_policy_adapter lock release; return "$POWER_POLICY_OUTCOME_DECLINED"; fi
	power_policy_adapter mutate acquire || { power_policy_adapter lock release; return 1; }
	power_policy_collect_apply_snapshot || { power_policy_adapter lock release; return 1; }
	[[ $(power_policy_snapshot) == "$snapshot" ]] || { printf 'Error: approved power-policy inputs changed after confirmation.\n' >&2; power_policy_adapter lock release; return 1; }
	power_policy_prepare_state_root || { power_policy_adapter lock release; return 1; }
	power_policy_backup_prior_targets "$transaction" || { power_policy_adapter lock release; return 1; }
	pending=$(power_policy_pending_json apply "$transaction") || { power_policy_adapter lock release; return 1; }
	power_policy_write_receipt pending "$pending" || { power_policy_adapter lock release; return 1; }; POWER_POLICY_PENDING=$pending
	if ! power_policy_apply_mutation "$transaction"; then power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; fi
	power_policy_collect_apply_snapshot && [[ $POWER_POLICY_INHIBIT_DELAY_US == "$(jq -r .delay <<<"$snapshot")" ]] && power_policy_desired_targets_match && power_policy_desired_effective "$POWER_POLICY_UPOWER_EFFECTIVE" "$POWER_POLICY_LOGIND_EFFECTIVE" && power_policy_runtime_desired || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }
	active=$(power_policy_publish_active "$transaction") || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }
	power_policy_write_receipt active "$active" && rm -f -- "$POWER_POLICY_PENDING_PATH" || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }
	printf 'Applied and verified laptop power policy.\n'; power_policy_adapter lock release
}

power_policy_plan_remove() {
	local name original replacement
	for name in upower logind; do original=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .original' <<<"$POWER_POLICY_ACTIVE") || return 1; if [[ $(jq -r .present <<<"$original") == true ]]; then replacement=$(jq -r .backup_path <<<"$original"); power_policy_backup_valid "$original" || return 1; else replacement=-; fi; case $name in upower) POWER_POLICY_UPOWER_PLAN=$(power_policy_adapter inspect upower-plan "$replacement") ;; logind) POWER_POLICY_LOGIND_PLAN=$(power_policy_adapter inspect logind-plan "$replacement") ;; esac; done
}

power_policy_collect_remove_snapshot() {
	local name
	power_policy_read_state || return 1
	[[ -n $POWER_POLICY_ACTIVE && -z $POWER_POLICY_PENDING ]] || return 1
	power_policy_inspect_runtime || return 1
	power_policy_supported || return 1
	for name in upower logind; do power_policy_target_safe "$name" || return 1; done
	power_policy_active_targets_match || return 1
	power_policy_active_backups_valid || return 1
	power_policy_plan_remove
}

remove_power_policy() {
	(($# == 0)) || return 2
	POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_ORDINARY
	power_policy_state_paths || return 1; power_policy_adapter lock exclusive || return 1
	local outcome=0 transaction snapshot pending name original enabled active
	power_policy_read_state || outcome=1
	if ((outcome == 0)) && [[ -n $POWER_POLICY_PENDING ]]; then
		POWER_POLICY_VERSION=$(power_policy_adapter inspect version) || outcome=1
		if ((outcome == 0)) && ! power_policy_supported; then printf 'Error: laptop power policy supports Omarchy %s, but detected %s.\n' "${SUPPORTED_OMARCHY_VERSION:-4}" "$POWER_POLICY_VERSION" >&2; outcome=1; fi
		if ((outcome == 0)); then power_policy_recover || outcome=$?; fi
		power_policy_adapter lock release; return "$outcome"
	fi
	if ((outcome == 0)) && [[ -z $POWER_POLICY_ACTIVE ]]; then
		power_policy_target_state upower && power_policy_target_state logind || outcome=1
		if ((outcome == 0)) && [[ ${POWER_POLICY_TARGET[upower]} == absent && ${POWER_POLICY_TARGET[logind]} == absent ]]; then printf 'Laptop power policy has nothing to remove.\n'; power_policy_adapter lock release; return 0; fi
		printf 'Error: fixed laptop power-policy target is foreign; no ownership receipt authorizes Remove.\n' >&2; power_policy_adapter lock release; return 1
	fi
	((outcome == 0)) || { power_policy_adapter lock release; return "$outcome"; }
	POWER_POLICY_VERSION=$(power_policy_adapter inspect version) || { power_policy_adapter lock release; return 1; }
	power_policy_supported || { printf 'Error: laptop power policy supports Omarchy %s, but detected %s.\n' "${SUPPORTED_OMARCHY_VERSION:-4}" "$POWER_POLICY_VERSION" >&2; power_policy_adapter lock release; return 1; }
	power_policy_collect_remove_snapshot || { printf 'Error: receipt-owned target, backup, or restored effective configuration is invalid; Remove is blocked.\n' >&2; power_policy_adapter lock release; return 1; }
	transaction=$(power_policy_transaction); snapshot=$(power_policy_snapshot)
	printf 'Plan: remove laptop power policy\n'
	for name in upower logind; do original=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .original' <<<"$POWER_POLICY_ACTIVE"); printf '  %s: current=%s original=%s stage=%s rollback-backup=%s\n' "$name" "${POWER_POLICY_TARGET[$name]}" "$(power_policy_original_summary "$original")" "$(power_policy_stage_path "$name" "$transaction")" "$(power_policy_backup_path "$transaction" "$name")"; done
	printf '  service: %s -> %s\n  planned UPower merged values: %s\n  planned UPower relevant settings: %s\n  planned logind merged values: %s\n  planned logind relevant settings: %s\n  receipt cleanup: active=%s pending=%s\n  postconditions: target originals, service state, live lid settings, critical action, and inhibit delay\n' "$POWER_POLICY_SERVICE" "$(jq -r '.service_original | "\(.enabled)|\(.active)"' <<<"$POWER_POLICY_ACTIVE")" "$(power_policy_managed_effective_values "$POWER_POLICY_UPOWER_PLAN")" "$(power_policy_plan_classification "$POWER_POLICY_UPOWER_PLAN")" "$(power_policy_managed_effective_values "$POWER_POLICY_LOGIND_PLAN")" "$(power_policy_plan_classification "$POWER_POLICY_LOGIND_PLAN")" "$POWER_POLICY_ACTIVE_PATH" "$POWER_POLICY_PENDING_PATH"
	if ! wizard_confirm 'Remove this complete laptop power-policy plan?'; then printf 'No changes made.\n'; power_policy_adapter lock release; return "$POWER_POLICY_OUTCOME_DECLINED"; fi
	power_policy_adapter mutate acquire || { power_policy_adapter lock release; return 1; }
	power_policy_collect_remove_snapshot && [[ $(power_policy_snapshot) == "$snapshot" ]] || { printf 'Error: approved power-policy inputs changed after confirmation.\n' >&2; power_policy_adapter lock release; return 1; }
	power_policy_prepare_state_root && power_policy_backup_prior_targets "$transaction" || { power_policy_adapter lock release; return 1; }
	pending=$(power_policy_pending_json remove "$transaction") || { power_policy_adapter lock release; return 1; }; power_policy_write_receipt pending "$pending" || { power_policy_adapter lock release; return 1; }; POWER_POLICY_PENDING=$pending
	power_policy_pending_set_phase || { power_policy_adapter lock release; return 1; }
	for name in upower logind; do original=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .original' <<<"$POWER_POLICY_PENDING"); if [[ $(jq -r .present <<<"$original") == true ]]; then power_policy_backup_valid "$original" && power_policy_adapter mutate restore "$name" "$transaction" "$(jq -r .backup_path <<<"$original")" "$(jq -r .digest <<<"$original")" && power_policy_stage_valid "$name" "$transaction" "$(jq -r .digest <<<"$original")" && power_policy_adapter mutate publish "$name" "$transaction" || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }; else power_policy_adapter mutate remove "$name" || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }; fi; done
	power_policy_adapter mutate reload-logind || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }
	IFS='|' read -r enabled active <<<"$(jq -r '.service_original | "\(.enabled)|\(.active)"' <<<"$POWER_POLICY_PENDING")"
	power_policy_adapter mutate restore-service "$enabled" "$active" || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }
	power_policy_inspect_runtime || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }
	for name in upower logind; do original=$(jq -c --arg name "$name" '.targets[] | select(.name == $name) | .original' <<<"$POWER_POLICY_PENDING"); power_policy_target_matches "$name" "$original" || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }; done
	[[ $POWER_POLICY_SERVICE == "$enabled|$active" ]] && power_policy_runtime_restored && power_policy_pending_delay_matches || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }
	rm -f -- "$POWER_POLICY_ACTIVE_PATH" && rm -f -- "$POWER_POLICY_PENDING_PATH" || { power_policy_rollback_pending || true; power_policy_adapter lock release; return 1; }
	printf 'Removed and verified laptop power policy.\n'; power_policy_adapter lock release
}

power_policy_status_apply_eligibility() {
	[[ $POWER_POLICY_BATTERY == yes && $POWER_POLICY_HIBERNATION == yes ]] || return 10
	[[ $POWER_POLICY_CAN_HIBERNATE == yes && $POWER_POLICY_SLEEP_LOCK == 'enabled|active|present' ]]
}

power_policy_status_remove_available() {
	local name
	power_policy_inspect_runtime || return 1
	for name in upower logind; do power_policy_target_safe "$name" || return 1; done
	power_policy_active_targets_match && power_policy_active_backups_valid && power_policy_plan_remove
}

power_policy_status_pending_recovery_available() {
	case $(jq -r .phase <<<"$POWER_POLICY_PENDING") in
		prepared) power_policy_prepared_pending_matches ;;
		mutating)
			if power_policy_terminal_apply_matches || power_policy_terminal_remove_matches; then return 0; fi
			power_policy_collect_recovery_snapshot
			;;
		*) return 1 ;;
	esac
}

power_policy_status() {
	(($# == 0)) || return 2
	power_policy_state_paths || return 1; power_policy_adapter lock shared || return 1
	local healthy=true name source result service_prior='absent' source_error='' state_error='' runtime_error='' target_error='' precedence_error='' compatibility_error='' apply_reason='' eligibility=0 remove_available=false apply_available=false upower_source_status=invalid logind_source_status=invalid upower_status logind_status
	POWER_POLICY_UPOWER_DIGEST='' POWER_POLICY_LOGIND_DIGEST=''
	for source in upower logind; do
		if result=$(node "$POWER_POLICY_JSON_HELPER" source "$(power_policy_source_path "$source")" "$source" 2>/dev/null); then
			case $source in upower) POWER_POLICY_UPOWER_DIGEST=$(jq -r .digest <<<"$result") ;; logind) POWER_POLICY_LOGIND_DIGEST=$(jq -r .digest <<<"$result") ;; esac
		else
			source_error+="$source "
		fi
	done
	[[ -z $POWER_POLICY_UPOWER_DIGEST ]] || upower_source_status="digest=$POWER_POLICY_UPOWER_DIGEST"
	[[ -z $POWER_POLICY_LOGIND_DIGEST ]] || logind_source_status="digest=$POWER_POLICY_LOGIND_DIGEST"
	[[ -z $source_error ]] || source_error="invalid canonical source: ${source_error% }"
	power_policy_read_state || state_error=${POWER_POLICY_STATE_ERROR:-invalid lifecycle evidence}
	power_policy_inspect_runtime || runtime_error='unreadable or invalid live configuration'
	if [[ -z $runtime_error ]]; then
		for name in upower logind; do power_policy_target_safe "$name" || target_error="unsafe or unsupported $name target"; done
		power_policy_supported || compatibility_error='unsupported Omarchy version'
	fi
	if [[ -n $POWER_POLICY_PENDING ]]; then service_prior=$(jq -r '.service_prior | "\(.enabled)|\(.active)"' <<<"$POWER_POLICY_PENDING"); elif [[ -n $POWER_POLICY_ACTIVE ]]; then service_prior=$(jq -r '.service_original | "\(.enabled)|\(.active)"' <<<"$POWER_POLICY_ACTIVE"); fi
	upower_status=$POWER_POLICY_UPOWER_EFFECTIVE; logind_status=$POWER_POLICY_LOGIND_EFFECTIVE
	[[ -n $upower_status ]] || upower_status='{"effective":{},"files":[]}'
	[[ -n $logind_status ]] || logind_status='{"effective":{},"files":[]}'
	printf 'UPower source: %s\nlogind source: %s\nSupported Omarchy: %s\nDetected Omarchy: %s\n' "$upower_source_status" "$logind_source_status" "${SUPPORTED_OMARCHY_VERSION:-4}" "${POWER_POLICY_VERSION:-unavailable}"
	printf 'Eligibility: battery=%s hibernation=%s CanHibernate=%s\nUPower service: current=%s prior=%s\nOmarchy sleep lock: %s\nCritical action: %s\nLive lid settings: %s\nInhibit delay (us): %s\n' "${POWER_POLICY_BATTERY:-unavailable}" "${POWER_POLICY_HIBERNATION:-unavailable}" "${POWER_POLICY_CAN_HIBERNATE:-unavailable}" "${POWER_POLICY_SERVICE:-unavailable}" "$service_prior" "${POWER_POLICY_SLEEP_LOCK:-unavailable}" "${POWER_POLICY_CRITICAL_ACTION:-unavailable}" "${POWER_POLICY_LOGIND_RUNTIME:-unavailable}" "${POWER_POLICY_INHIBIT_DELAY_US:-unavailable}"
	for name in upower logind; do printf '%s target: %s\n' "$name" "${POWER_POLICY_TARGET[$name]:-unavailable}"; done
	printf 'UPower merged values: %s\nUPower relevant files/settings: %s\nlogind merged values: %s\nlogind relevant files/settings: %s\n' "$(jq -c '.effective // {}' <<<"$upower_status")" "$(power_policy_plan_summary "$upower_status")" "$(jq -c '.effective // {}' <<<"$logind_status")" "$(power_policy_plan_summary "$logind_status")"
	printf 'Active receipt: %s\nPending receipt: %s\n' "$POWER_POLICY_ACTIVE_LABEL" "$POWER_POLICY_PENDING_LABEL"
	if [[ -n $state_error || -n $compatibility_error ]]; then
		healthy=false
		printf 'Required action: conflict detected; lifecycle evidence or Omarchy compatibility blocks Apply, Remove, and recovery; do not Apply or Remove.\n'
	elif [[ -n $POWER_POLICY_PENDING ]]; then
		if power_policy_status_pending_recovery_available; then
			healthy=false
			printf 'Required action: recovery is available from Manage laptop power policy; ordinary Apply and Remove are unavailable until it completes.\n'
		else
			healthy=false
			printf 'Required action: conflict detected; pending recovery is blocked because current state is not transaction-allowed.\n'
		fi
	elif [[ -n $POWER_POLICY_ACTIVE ]]; then
		if power_policy_status_remove_available; then remove_available=true; fi
		if [[ -n $source_error ]]; then apply_reason='canonical source is invalid'
		elif [[ -n $runtime_error || -n $target_error ]]; then apply_reason='live configuration or target safety is conflicting'
		else
			if power_policy_status_apply_eligibility; then eligibility=0; else eligibility=$?; fi
			case $eligibility in
				0) if power_policy_plan_apply; then apply_available=true; else precedence_error='unreadable configuration or blocking precedence'; apply_reason='configuration precedence is conflicting'; fi ;;
				10) apply_reason='laptop prerequisites are ineligible' ;;
				*) apply_reason='CanHibernate or the Omarchy sleep lock is conflicting' ;;
			esac
		fi
		if [[ $apply_available == true ]] && power_policy_active_exact; then
			printf 'Required action: none; laptop power policy is exact and active.\n'
		elif [[ $apply_available == true ]] && power_policy_active_managed_target_drift; then
			healthy=false
			printf 'Required action: Apply is available to repair managed-target drift; Remove is blocked.\n'
		elif [[ $remove_available == true ]]; then
			healthy=false
			if [[ $apply_available == true ]]; then printf 'Required action: Apply is available to repair runtime policy; Remove remains available to restore the recorded prior state.\n'; else printf 'Required action: Remove remains available; Apply is unavailable because %s.\n' "$apply_reason"; fi
		else
			healthy=false
			printf 'Required action: conflict detected; receipt-owned targets or restored configuration drift block Remove and Apply. Remove is blocked.\n'
		fi
	else
		if [[ -n $source_error || -n $runtime_error || -n $target_error ]]; then
			healthy=false
			printf 'Required action: conflict detected; current source, runtime, or target state blocks Apply.\n'
		else
			if power_policy_status_apply_eligibility; then eligibility=0; else eligibility=$?; fi
			if [[ $eligibility == 10 ]]; then
				healthy=false
				printf 'Required action: laptop prerequisites are ineligible; Apply is unavailable.\n'
			elif [[ $eligibility != 0 ]]; then
				healthy=false
				printf 'Required action: conflict detected; CanHibernate or the Omarchy sleep lock blocks Apply.\n'
			elif power_policy_plan_apply; then
				printf 'Required action: Apply from Manage laptop power policy.\n'
			else
				healthy=false; precedence_error='unreadable configuration or blocking precedence'
				printf 'Required action: conflict detected; configuration precedence blocks Apply.\n'
			fi
		fi
	fi
	printf 'Checks: source=%s state=%s runtime=%s target=%s precedence=%s\n' "${source_error:-ok}" "${state_error:-ok}" "${runtime_error:-ok}" "${target_error:-ok}" "${precedence_error:-ok}"
	power_policy_adapter lock release
	[[ $healthy == true ]]
}

manage_power_policy() {
	local choice outcome
	while :; do
		choice=$(wizard_choose 'Manage laptop power policy' Status Apply Remove Back) || return 0
		case $choice in Status) power_policy_status || true ;; Apply) if apply_power_policy; then :; else outcome=$?; [[ $outcome == "$POWER_POLICY_OUTCOME_INELIGIBLE" ]] && { printf 'Error: unmet laptop prerequisites.\n' >&2; return 1; }; return "$outcome"; fi ;; Remove) remove_power_policy || return $? ;; Back) return 0 ;; esac
	done
}
