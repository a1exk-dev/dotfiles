#!/usr/bin/env bash

set -u

SOURCE_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
BWRAP=$(command -v bwrap)
HOST_NODE_REAL=$(readlink -f -- "$(command -v node)")
HOST_MAGICK_REAL=$(readlink -f -- "$(command -v magick)")
HOST_GIT_REAL=$(readlink -f -- "$(command -v git)")
HOST_FILE_REAL=$(readlink -f -- "$(command -v file)")
BWRAP_EXTRA_ARGS=()
TESTS_RUN=0
TESTS_FAILED=0
PARALLEL_TEST_ROOT=''
declare -a PARALLEL_TEST_PIDS=()
declare -a PARALLEL_TEST_PGIDS=()
declare -a PARALLEL_TEST_START_TIMES=()
declare -a PARALLEL_TEST_PIDFD_INODES=()
declare -a PARALLEL_TEST_WORKER_MARKERS=()
declare -a PARALLEL_TEST_WATCHER_PIDS=()
PARALLEL_TEST_RUNNING=0
PARALLEL_TEST_CLEANUP_ACTIVE=false
PARALLEL_TEST_LAUNCHING=false
PARALLEL_TEST_LAUNCH_PID=''
PARALLEL_TEST_MONITOR_CHANGED=false
PARALLEL_TEST_WORKER_ROOT=''
PARALLEL_TEST_FREEZING=false
PARALLEL_TEST_STARTUP_FAILED=false
PARALLEL_TEST_STARTUP_ERROR=''
declare -a PARALLEL_TEST_CLEANUP_PIDS=()
declare -A PARALLEL_TEST_CLEANUP_PIDFD_INODES=()
declare -A PARALLEL_TEST_CLEANUP_START_TIMES=()
declare -A PARALLEL_TEST_CLEANUP_GROUP_LEADERS=()
declare -A PARALLEL_TEST_CLEANUP_GROUP_INODES=()
declare -A PARALLEL_TEST_CLEANUP_GROUP_START_TIMES=()
declare -A PARALLEL_TEST_CLEANUP_SEEN=()
declare -a PARALLEL_TEST_CLEANUP_GROUPS=()
PARALLEL_TEST_CAPTURED_PIDFD_INODE=''
PARALLEL_TEST_CAPTURED_START_TIME=''
PARALLEL_TEST_WORKER_RESOURCES_STOPPED=false
PARALLEL_TEST_WORKER_ABNORMAL_CLEANUP_DONE=false
PARALLEL_TEST_WORKER_CLEANUP_MARKER=''
PARALLEL_TEST_WORKER_NORMAL_COMPLETION=false
PARALLEL_TEST_WORKER_ABNORMAL_REPORTED=false
PARALLEL_TEST_EVENT_RELAY_PID=''
PARALLEL_TEST_EVENT_READ_FD=''
PARALLEL_TEST_EVENT_SOCKET=''
declare -a PARALLEL_TEST_GROUP_NAMES=()
declare -a PARALLEL_TEST_GROUP_DESCRIPTIONS=()
declare -a PARALLEL_TEST_GROUP_IDS=()
declare -a PARALLEL_TEST_GROUP_ARGUMENTS=()
WALLPAPER_TEST_FAST_SHARED_WORKER=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_START=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_ROOT=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_DIRECTORY=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST_FD=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE_FD=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_ROOT=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_REQUEST=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_RESPONSE=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_OWNER=''
WALLPAPER_TEST_FAST_SHARED_SANDBOX_STDERR=''

parallel_test_stat_field() {
	local pid=$1 field=$2 stat remainder index
	local -a fields=()

	[[ $pid =~ ^[1-9][0-9]*$ && $field =~ ^[0-9]+$ ]] || return 1
	stat=$(<"/proc/$pid/stat") || return 1
	remainder=${stat##*) }
	[[ $remainder != "$stat" ]] || return 1
	read -r -a fields <<<"$remainder" || return 1
	index=$((field - 3))
	(( index >= 0 && index < ${#fields[@]} )) || return 1
	printf '%s\n' "${fields[$index]}"
}

parallel_test_process_start_time() {
	parallel_test_stat_field "$1" 22
}

parallel_test_process_group() {
	parallel_test_stat_field "$1" 5
}

parallel_test_process_parent() {
	parallel_test_stat_field "$1" 4
}

parallel_test_process_identity_matches() {
	local pid=$1 expected_start=$2 current_start

	[[ $pid =~ ^[1-9][0-9]*$ && -n $expected_start ]] || return 1
	current_start=$(parallel_test_process_start_time "$pid" 2>/dev/null) || return 1
	[[ $current_start == "$expected_start" ]]
}

parallel_test_pidfd_inode() {
	local pid=$1 inode

	[[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
	inode=$(/usr/bin/getino --pidfs "$pid" 2>/dev/null) || return 1
	[[ $inode =~ ^[1-9][0-9]*$ ]] || return 1
	/usr/bin/kill --signal 0 -- "$pid:$inode" 2>/dev/null || return 1
	printf '%s\n' "$inode"
}

parallel_test_pidfd_identity_matches() {
	local pid=$1 inode=$2

	[[ $pid =~ ^[1-9][0-9]*$ && $inode =~ ^[1-9][0-9]*$ ]] || return 1
	/usr/bin/kill --signal 0 -- "$pid:$inode" 2>/dev/null
}

parallel_test_capture_process_identity() {
	local pid=$1 expected_start=${2-} inode start

	PARALLEL_TEST_CAPTURED_PIDFD_INODE=''
	PARALLEL_TEST_CAPTURED_START_TIME=''
	inode=$(parallel_test_pidfd_inode "$pid") || return 1
	start=$(parallel_test_process_start_time "$pid" 2>/dev/null) || return 1
	[[ -z $expected_start || $start == "$expected_start" ]] || return 1
	parallel_test_pidfd_identity_matches "$pid" "$inode" || return 1
	PARALLEL_TEST_CAPTURED_PIDFD_INODE=$inode
	PARALLEL_TEST_CAPTURED_START_TIME=$start
}

parallel_test_pidfd_signal() {
	local pid=$1 expected_inode=$2 requested_signal=$3 inode

	[[ $requested_signal =~ ^(STOP|TERM|KILL)$ ]] || return 1
	inode=$(parallel_test_pidfd_inode "$pid") || return 1
	[[ $inode == "$expected_inode" ]] || return 1
	/usr/bin/kill --signal "$requested_signal" -- "$pid:$inode" 2>/dev/null
}

parallel_test_record_process_group() {
	local pid=$1 inode=$2 start=$3 group suite_group

	parallel_test_pidfd_identity_matches "$pid" "$inode" || return 0
	group=$(parallel_test_process_group "$pid" 2>/dev/null) || return 0
	[[ $group =~ ^[1-9][0-9]*$ && $group == "$pid" && $group != 1 ]] || return 0
	suite_group=$(parallel_test_process_group "$$" 2>/dev/null) || return 0
	[[ $suite_group =~ ^[1-9][0-9]*$ && $group != "$suite_group" ]] || return 0

	if [[ ${PARALLEL_TEST_CLEANUP_GROUP_LEADERS[$group]+present} ]]; then
		[[ ${PARALLEL_TEST_CLEANUP_GROUP_LEADERS[$group]} == "$pid" && \
			${PARALLEL_TEST_CLEANUP_GROUP_INODES[$group]} == "$inode" ]] || return 0
	else
		PARALLEL_TEST_CLEANUP_GROUP_LEADERS["$group"]=$pid
		PARALLEL_TEST_CLEANUP_GROUP_INODES["$group"]=$inode
		PARALLEL_TEST_CLEANUP_GROUP_START_TIMES["$group"]=$start
		PARALLEL_TEST_CLEANUP_GROUPS+=("$group")
	fi
}

parallel_test_record_process_tree() {
	local pid=$1 inode=$2 start=$3 keep_root=${4-} child children

	[[ $pid =~ ^[1-9][0-9]*$ && $inode =~ ^[1-9][0-9]*$ && -n $start ]] || return 0
	[[ ${PARALLEL_TEST_CLEANUP_SEEN[$pid]+present} ]] && return 0
	parallel_test_pidfd_identity_matches "$pid" "$inode" || return 0
	if [[ $PARALLEL_TEST_FREEZING == true && $pid != "$keep_root" ]]; then
		parallel_test_pidfd_signal "$pid" "$inode" STOP || return 0
	fi
	PARALLEL_TEST_CLEANUP_SEEN["$pid"]=$inode
	PARALLEL_TEST_CLEANUP_PIDS+=("$pid")
	PARALLEL_TEST_CLEANUP_PIDFD_INODES["$pid"]=$inode
	PARALLEL_TEST_CLEANUP_START_TIMES["$pid"]=$start
	parallel_test_record_process_group "$pid" "$inode" "$start" || true

	children=''
	{ IFS= read -r -d '' children <"/proc/$pid/task/$pid/children" || true; } 2>/dev/null
	for child in $children; do
		[[ $child =~ ^[1-9][0-9]*$ ]] || continue
		parallel_test_capture_process_identity "$child" || continue
		parallel_test_record_process_tree "$child" "$PARALLEL_TEST_CAPTURED_PIDFD_INODE" \
			"$PARALLEL_TEST_CAPTURED_START_TIME" "$keep_root" || true
	done
}

parallel_test_record_exact_process_group() {
	local group=$1 leader=$2 leader_inode=$3 leader_start=$4 keep_root=${5-}
	local path pid member_group member_inode member_start leader_group leader_state

	[[ $group =~ ^[1-9][0-9]*$ && $leader == "$group" && $leader_inode =~ ^[1-9][0-9]*$ && -n $leader_start ]] || return 0
	if parallel_test_pidfd_identity_matches "$leader" "$leader_inode"; then
		leader_group=$(parallel_test_process_group "$leader" 2>/dev/null || true)
		[[ $leader_group == "$group" ]] || return 0
	else
		# A dead but unreaped worker still reserves both its PID and PGID. Its
		# captured start time proves that this exact group has not been reused,
		# allowing the remaining members to be captured by pidfd before wait.
		parallel_test_process_identity_matches "$leader" "$leader_start" || return 0
		leader_state=$(parallel_test_stat_field "$leader" 3 2>/dev/null || true)
		[[ $leader_state == Z ]] || return 0
	fi
	for path in /proc/[1-9]*; do
		[[ -d $path ]] || continue
		pid=${path##*/}
		member_group=$(parallel_test_process_group "$pid" 2>/dev/null || true)
		[[ $member_group == "$group" ]] || continue
		parallel_test_capture_process_identity "$pid" || continue
		member_inode=$PARALLEL_TEST_CAPTURED_PIDFD_INODE
		member_start=$PARALLEL_TEST_CAPTURED_START_TIME
		member_group=$(parallel_test_process_group "$pid" 2>/dev/null || true)
		[[ $member_group == "$group" ]] || continue
		parallel_test_record_process_tree "$pid" "$member_inode" "$member_start" "$keep_root" || true
	done
}

parallel_test_record_process_children() {
	local pid=$1 inode=$2 keep_root=${3-} child children

	parallel_test_pidfd_identity_matches "$pid" "$inode" || return 0
	children=''
	{ IFS= read -r -d '' children <"/proc/$pid/task/$pid/children" || true; } 2>/dev/null
	for child in $children; do
		[[ $child =~ ^[1-9][0-9]*$ ]] || continue
		parallel_test_capture_process_identity "$child" || continue
		parallel_test_record_process_tree "$child" "$PARALLEL_TEST_CAPTURED_PIDFD_INODE" \
			"$PARALLEL_TEST_CAPTURED_START_TIME" "$keep_root" || true
	done
}

parallel_test_record_worker_processes() {
	local pid=$1 inode=$2 start=$3 group=$4 keep_root=${5-}

	parallel_test_record_process_tree "$pid" "$inode" "$start" "$keep_root" || true
	parallel_test_record_exact_process_group "$group" "$pid" "$inode" "$start" "$keep_root" || true
}

parallel_test_expand_recorded_processes() {
	local keep_root=${1-} scan_index=0 group_index=0 pid inode group leader leader_inode leader_start

	while ((scan_index < ${#PARALLEL_TEST_CLEANUP_PIDS[@]} || group_index < ${#PARALLEL_TEST_CLEANUP_GROUPS[@]})); do
		if ((scan_index < ${#PARALLEL_TEST_CLEANUP_PIDS[@]})); then
			pid=${PARALLEL_TEST_CLEANUP_PIDS[$scan_index]}
			inode=${PARALLEL_TEST_CLEANUP_PIDFD_INODES[$pid]-}
			parallel_test_record_process_children "$pid" "$inode" "$keep_root" || true
			scan_index=$((scan_index + 1))
		fi
		if ((group_index < ${#PARALLEL_TEST_CLEANUP_GROUPS[@]})); then
			group=${PARALLEL_TEST_CLEANUP_GROUPS[$group_index]}
			leader=${PARALLEL_TEST_CLEANUP_GROUP_LEADERS[$group]}
			leader_inode=${PARALLEL_TEST_CLEANUP_GROUP_INODES[$group]}
			leader_start=${PARALLEL_TEST_CLEANUP_GROUP_START_TIMES[$group]}
			parallel_test_record_exact_process_group "$group" "$leader" "$leader_inode" "$leader_start" "$keep_root" || true
			group_index=$((group_index + 1))
		fi
	done
}

parallel_test_record_all_processes() {
	local keep_root=${1-} index pid inode start group

	for ((index = 0; index < ${#PARALLEL_TEST_PIDS[@]}; index++)); do
		pid=${PARALLEL_TEST_PIDS[$index]-}
		[[ $pid =~ ^[1-9][0-9]*$ ]] || continue
		if [[ -n ${PARALLEL_TEST_WORKER_MARKERS[$index]-} && \
			-f ${PARALLEL_TEST_WORKER_MARKERS[$index]} ]]; then
			continue
		fi
		inode=${PARALLEL_TEST_PIDFD_INODES[$index]-}
		start=${PARALLEL_TEST_START_TIMES[$index]-}
		group=${PARALLEL_TEST_PGIDS[$index]-}
		if [[ ! $inode =~ ^[1-9][0-9]*$ || -z $start ]]; then
			parallel_test_register_worker_root "$pid" || continue
			inode=${PARALLEL_TEST_PIDFD_INODES[$index]-}
			start=${PARALLEL_TEST_START_TIMES[$index]-}
			group=${PARALLEL_TEST_PGIDS[$index]-}
		fi
		parallel_test_record_worker_processes "$pid" "$inode" "$start" "$group" "$keep_root"
	done
	parallel_test_expand_recorded_processes "$keep_root"
}

parallel_test_capture_worker_processes() {
	local pid=$1 inode=$2 start=$3 group=$4 saved_freezing=$PARALLEL_TEST_FREEZING

	parallel_test_clear_cleanup_records
	PARALLEL_TEST_FREEZING=true
	parallel_test_record_worker_processes "$pid" "$inode" "$start" "$group" "$pid"
	parallel_test_expand_recorded_processes "$pid"
	PARALLEL_TEST_FREEZING=$saved_freezing
}

parallel_test_signal_recorded_processes() {
	local signal=$1 keep_root=${2-} index pid inode

	# Descendants are recorded after their ancestors. Signal them first so a
	# root cannot be reaped before every exact descendant has been consumed.
	for ((index = ${#PARALLEL_TEST_CLEANUP_PIDS[@]} - 1; index >= 0; index--)); do
		pid=${PARALLEL_TEST_CLEANUP_PIDS[$index]}
		[[ $pid == "$keep_root" ]] && continue
		inode=${PARALLEL_TEST_CLEANUP_PIDFD_INODES[$pid]-}
		parallel_test_pidfd_signal "$pid" "$inode" "$signal" || true
	done
}

parallel_test_freeze_worker_roots() {
	local keep_root=${1-} index pid inode marker

	for ((index = 0; index < ${#PARALLEL_TEST_PIDS[@]}; index++)); do
		pid=${PARALLEL_TEST_PIDS[$index]-}
		[[ $pid == "$keep_root" ]] && continue
		marker=${PARALLEL_TEST_WORKER_MARKERS[$index]-}
		[[ -n $marker && -f $marker ]] && continue
		inode=${PARALLEL_TEST_PIDFD_INODES[$index]-}
		if [[ ! $inode =~ ^[1-9][0-9]*$ ]]; then
			parallel_test_register_worker_root "$pid" || continue
			inode=${PARALLEL_TEST_PIDFD_INODES[$index]-}
		fi
		parallel_test_pidfd_signal "$pid" "$inode" STOP || true
	done
}

parallel_test_wait_recorded_processes() {
	local keep_root=${1-} pid

	for pid in "${PARALLEL_TEST_PIDS[@]}"; do
		[[ $pid =~ ^[1-9][0-9]*$ && $pid != "$keep_root" ]] || continue
		wait "$pid" 2>/dev/null || true
	done
	for pid in "${PARALLEL_TEST_CLEANUP_PIDS[@]}"; do
		[[ $pid =~ ^[1-9][0-9]*$ && $pid != "$keep_root" ]] || continue
		wait "$pid" 2>/dev/null || true
	done
}

parallel_test_stop_exact_process_tree() {
	local pid=$1 expected_start=$2 keep_root=${3-} key saved_freezing=$PARALLEL_TEST_FREEZING
	local saved_running=$PARALLEL_TEST_RUNNING saved_cleanup_active=$PARALLEL_TEST_CLEANUP_ACTIVE
	local -a saved_test_pids=("${PARALLEL_TEST_PIDS[@]}")
	local -a saved_test_pgids=("${PARALLEL_TEST_PGIDS[@]}")
	local -a saved_test_starts=("${PARALLEL_TEST_START_TIMES[@]}")
	local -a saved_test_inodes=("${PARALLEL_TEST_PIDFD_INODES[@]}")
	local -a saved_test_markers=("${PARALLEL_TEST_WORKER_MARKERS[@]}")
	local -a saved_cleanup_pids=("${PARALLEL_TEST_CLEANUP_PIDS[@]}")
	local -a saved_cleanup_groups=("${PARALLEL_TEST_CLEANUP_GROUPS[@]}")
	local -A saved_cleanup_inodes=() saved_cleanup_starts=() saved_cleanup_leaders=()
	local -A saved_cleanup_group_inodes=() saved_cleanup_group_starts=() saved_cleanup_seen=()

	for key in "${!PARALLEL_TEST_CLEANUP_PIDFD_INODES[@]}"; do saved_cleanup_inodes["$key"]=${PARALLEL_TEST_CLEANUP_PIDFD_INODES[$key]}; done
	for key in "${!PARALLEL_TEST_CLEANUP_START_TIMES[@]}"; do saved_cleanup_starts["$key"]=${PARALLEL_TEST_CLEANUP_START_TIMES[$key]}; done
	for key in "${!PARALLEL_TEST_CLEANUP_GROUP_LEADERS[@]}"; do saved_cleanup_leaders["$key"]=${PARALLEL_TEST_CLEANUP_GROUP_LEADERS[$key]}; done
	for key in "${!PARALLEL_TEST_CLEANUP_GROUP_INODES[@]}"; do saved_cleanup_group_inodes["$key"]=${PARALLEL_TEST_CLEANUP_GROUP_INODES[$key]}; done
	for key in "${!PARALLEL_TEST_CLEANUP_GROUP_START_TIMES[@]}"; do saved_cleanup_group_starts["$key"]=${PARALLEL_TEST_CLEANUP_GROUP_START_TIMES[$key]}; done
	for key in "${!PARALLEL_TEST_CLEANUP_SEEN[@]}"; do saved_cleanup_seen["$key"]=${PARALLEL_TEST_CLEANUP_SEEN[$key]}; done

	PARALLEL_TEST_PIDS=()
	PARALLEL_TEST_PGIDS=()
	PARALLEL_TEST_START_TIMES=()
	PARALLEL_TEST_PIDFD_INODES=()
	PARALLEL_TEST_WORKER_MARKERS=()
	PARALLEL_TEST_RUNNING=0
	parallel_test_clear_cleanup_records
	if parallel_test_register_worker_root "$pid" "$expected_start"; then
		PARALLEL_TEST_FREEZING=true
		parallel_test_freeze_worker_roots "$keep_root"
		parallel_test_record_all_processes "$keep_root"
		parallel_test_signal_recorded_processes KILL "$keep_root"
		parallel_test_wait_recorded_processes "$keep_root"
	fi

	PARALLEL_TEST_FREEZING=$saved_freezing
	PARALLEL_TEST_PIDS=("${saved_test_pids[@]}")
	PARALLEL_TEST_PGIDS=("${saved_test_pgids[@]}")
	PARALLEL_TEST_START_TIMES=("${saved_test_starts[@]}")
	PARALLEL_TEST_PIDFD_INODES=("${saved_test_inodes[@]}")
	PARALLEL_TEST_WORKER_MARKERS=("${saved_test_markers[@]}")
	PARALLEL_TEST_RUNNING=$saved_running
	PARALLEL_TEST_CLEANUP_ACTIVE=$saved_cleanup_active
	PARALLEL_TEST_CLEANUP_PIDS=("${saved_cleanup_pids[@]}")
	PARALLEL_TEST_CLEANUP_GROUPS=("${saved_cleanup_groups[@]}")
	PARALLEL_TEST_CLEANUP_PIDFD_INODES=()
	PARALLEL_TEST_CLEANUP_START_TIMES=()
	PARALLEL_TEST_CLEANUP_GROUP_LEADERS=()
	PARALLEL_TEST_CLEANUP_GROUP_INODES=()
	PARALLEL_TEST_CLEANUP_GROUP_START_TIMES=()
	PARALLEL_TEST_CLEANUP_SEEN=()
	for key in "${!saved_cleanup_inodes[@]}"; do PARALLEL_TEST_CLEANUP_PIDFD_INODES["$key"]=${saved_cleanup_inodes[$key]}; done
	for key in "${!saved_cleanup_starts[@]}"; do PARALLEL_TEST_CLEANUP_START_TIMES["$key"]=${saved_cleanup_starts[$key]}; done
	for key in "${!saved_cleanup_leaders[@]}"; do PARALLEL_TEST_CLEANUP_GROUP_LEADERS["$key"]=${saved_cleanup_leaders[$key]}; done
	for key in "${!saved_cleanup_group_inodes[@]}"; do PARALLEL_TEST_CLEANUP_GROUP_INODES["$key"]=${saved_cleanup_group_inodes[$key]}; done
	for key in "${!saved_cleanup_group_starts[@]}"; do PARALLEL_TEST_CLEANUP_GROUP_START_TIMES["$key"]=${saved_cleanup_group_starts[$key]}; done
	for key in "${!saved_cleanup_seen[@]}"; do PARALLEL_TEST_CLEANUP_SEEN["$key"]=${saved_cleanup_seen[$key]}; done
}

parallel_test_register_worker_root() {
	local pid=$1 expected_start=${2-} index existing=-1 group suite_group

	[[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
	for ((index = 0; index < ${#PARALLEL_TEST_PIDS[@]}; index++)); do
		if [[ ${PARALLEL_TEST_PIDS[$index]} == "$pid" ]]; then
			existing=$index
			break
		fi
	done
	parallel_test_capture_process_identity "$pid" "$expected_start" || return 1
	group=$(parallel_test_process_group "$pid" 2>/dev/null || true)
	suite_group=$(parallel_test_process_group "$$" 2>/dev/null || true)
	if [[ ! $group =~ ^[1-9][0-9]*$ || $group != "$pid" || $group == "$suite_group" ]]; then
		group=''
	fi
	if ((existing >= 0)); then
		PARALLEL_TEST_START_TIMES[$existing]=$PARALLEL_TEST_CAPTURED_START_TIME
		PARALLEL_TEST_PIDFD_INODES[$existing]=$PARALLEL_TEST_CAPTURED_PIDFD_INODE
		PARALLEL_TEST_PGIDS[$existing]=$group
		return 0
	fi
	PARALLEL_TEST_PIDS+=("$pid")
	PARALLEL_TEST_PGIDS+=("$group")
	PARALLEL_TEST_START_TIMES+=("$PARALLEL_TEST_CAPTURED_START_TIME")
	PARALLEL_TEST_PIDFD_INODES+=("$PARALLEL_TEST_CAPTURED_PIDFD_INODE")
}

parallel_test_register_pending_worker() {
	local pid=$1 parent

	[[ $pid =~ ^[1-9][0-9]*$ ]] || return 0
	parent=$(parallel_test_process_parent "$pid" 2>/dev/null || true)
	if [[ -n $parent ]]; then
		[[ $parent == "$$" ]] || return 0
	fi
	parallel_test_register_worker_root "$pid" || true
}

parallel_test_clear_cleanup_records() {
	PARALLEL_TEST_CLEANUP_PIDS=()
	PARALLEL_TEST_CLEANUP_PIDFD_INODES=()
	PARALLEL_TEST_CLEANUP_START_TIMES=()
	PARALLEL_TEST_CLEANUP_GROUP_LEADERS=()
	PARALLEL_TEST_CLEANUP_GROUP_INODES=()
	PARALLEL_TEST_CLEANUP_GROUP_START_TIMES=()
	PARALLEL_TEST_CLEANUP_SEEN=()
	PARALLEL_TEST_CLEANUP_GROUPS=()
}

parallel_test_start_event_relay() {
	local relay_request_fd relay_response_fd read_fd ready

	[[ -n $PARALLEL_TEST_EVENT_READ_FD && -n $PARALLEL_TEST_EVENT_SOCKET ]] && return 0
	[[ -n $PARALLEL_TEST_ROOT ]] || return 1
	PARALLEL_TEST_EVENT_SOCKET="$PARALLEL_TEST_ROOT/events.sock"
	coproc PARALLEL_TEST_EVENT_RELAY {
		/usr/bin/python3 -u -c '
import os
import socket
import sys

path = sys.argv[1]
server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
try:
    server.bind(path)
except OSError:
    sys.exit(1)
print("ready", flush=True)
try:
    while True:
        message = server.recv(256)
        if message == b"stop":
            break
        print(message.decode("ascii"), flush=True)
finally:
    server.close()
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
' "$PARALLEL_TEST_EVENT_SOCKET"
	}
	relay_request_fd=${PARALLEL_TEST_EVENT_RELAY[1]-}
	relay_response_fd=${PARALLEL_TEST_EVENT_RELAY[0]-}
	PARALLEL_TEST_EVENT_RELAY_PID=${PARALLEL_TEST_EVENT_RELAY_PID-}
	read_fd=''
	if [[ -n $relay_request_fd ]]; then eval "exec ${relay_request_fd}>&-" || true; fi
	if [[ -n $relay_response_fd ]] && exec {read_fd}<&"$relay_response_fd"; then
		eval "exec ${relay_response_fd}<&-" || true
	fi
	if [[ -n $read_fd ]] && IFS= read -r ready <&"$read_fd" && [[ $ready == ready ]]; then
		PARALLEL_TEST_EVENT_READ_FD=$read_fd
		return 0
	fi
	if [[ -n $read_fd ]]; then eval "exec ${read_fd}<&-" || true; fi
	wait "${PARALLEL_TEST_EVENT_RELAY_PID-}" 2>/dev/null || true
	PARALLEL_TEST_EVENT_RELAY_PID=''
	PARALLEL_TEST_EVENT_SOCKET=''
	return 1
}

parallel_test_stop_event_relay() {
	local read_fd=${PARALLEL_TEST_EVENT_READ_FD-} relay_pid=${PARALLEL_TEST_EVENT_RELAY_PID-}
	local socket_path=${PARALLEL_TEST_EVENT_SOCKET-}

	if [[ -S $socket_path ]]; then
		/usr/bin/python3 -c '
import socket
import sys

client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
try:
    client.sendto(b"stop", sys.argv[1])
finally:
    client.close()
' "$socket_path" 2>/dev/null || true
	fi
	if [[ -n $read_fd ]]; then eval "exec ${read_fd}<&-" || true; fi
	if [[ $relay_pid =~ ^[1-9][0-9]*$ ]]; then wait "$relay_pid" 2>/dev/null || true; fi
	PARALLEL_TEST_EVENT_READ_FD=''
	PARALLEL_TEST_EVENT_RELAY_PID=''
	PARALLEL_TEST_EVENT_SOCKET=''
}

parallel_test_send_worker_event() {
	local kind=$1 pid=$2 socket_path=${PARALLEL_TEST_EVENT_SOCKET-}

	[[ $kind =~ ^abnormal$ && $pid =~ ^[1-9][0-9]*$ && -S $socket_path ]] || return 1
	/usr/bin/python3 -c '
import socket
import sys

client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
try:
    client.sendto(f"{sys.argv[1]} {sys.argv[2]}".encode(), sys.argv[3])
finally:
    client.close()
' "$kind" "$pid" "$socket_path"
}

parallel_test_start_worker_exit_watcher() {
	local index=$1 pid=$2 socket_path=$PARALLEL_TEST_EVENT_SOCKET watcher_pid

	[[ $index =~ ^[0-9]+$ && $pid =~ ^[1-9][0-9]*$ && -S $socket_path ]] || return 1
	/usr/bin/python3 -c '
import os
import select
import socket
import sys

pid = int(sys.argv[1])
socket_path = sys.argv[2]
try:
    pidfd = os.pidfd_open(pid)
    poller = select.poll()
    poller.register(pidfd, select.POLLIN)
    poller.poll()
    event = f"exit {pid}".encode()
except OSError:
    event = f"watch-failed {pid}".encode()
try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    client.sendto(event, socket_path)
    client.close()
except OSError:
    pass
' "$pid" "$socket_path" &
	watcher_pid=$!
	PARALLEL_TEST_WATCHER_PIDS[$index]=$watcher_pid
}

parallel_test_wait_worker_watcher() {
	local index watcher_pid
	index=$1
	watcher_pid=${PARALLEL_TEST_WATCHER_PIDS[$index]-}

	if [[ $watcher_pid =~ ^[1-9][0-9]*$ ]]; then wait "$watcher_pid" 2>/dev/null || true; fi
	PARALLEL_TEST_WATCHER_PIDS[$index]=''
}

parallel_test_wait_all_worker_watchers() {
	local index

	for ((index = 0; index < ${#PARALLEL_TEST_WATCHER_PIDS[@]}; index++)); do
		parallel_test_wait_worker_watcher "$index"
	done
}

parallel_test_unregister_worker_root() {
	local index=$1

	parallel_test_wait_worker_watcher "$index"
	PARALLEL_TEST_PIDS[$index]=''
	PARALLEL_TEST_PGIDS[$index]=''
	PARALLEL_TEST_START_TIMES[$index]=''
	PARALLEL_TEST_PIDFD_INODES[$index]=''
	PARALLEL_TEST_WORKER_MARKERS[$index]=''
}

parallel_test_reap_completed_workers() {
	local index pid marker

	for ((index = 0; index < ${#PARALLEL_TEST_PIDS[@]}; index++)); do
		pid=${PARALLEL_TEST_PIDS[$index]-}
		marker=${PARALLEL_TEST_WORKER_MARKERS[$index]-}
		[[ $pid =~ ^[1-9][0-9]*$ && -n $marker && -f $marker ]] || continue
		wait "$pid" 2>/dev/null || true
		parallel_test_unregister_worker_root "$index"
	done
}

parallel_test_wait_captured_worker_processes() {
	local worker_pid=$1 index pid

	wait "$worker_pid" 2>/dev/null || true
	for pid in "${PARALLEL_TEST_CLEANUP_PIDS[@]}"; do
		[[ $pid =~ ^[1-9][0-9]*$ && $pid != "$worker_pid" ]] || continue
		wait "$pid" 2>/dev/null || true
	done
}

parallel_test_abort_worker() {
	local index reason pid inode start group marker
	index=$1
	reason=$2
	pid=${PARALLEL_TEST_PIDS[$index]-}
	marker=${PARALLEL_TEST_WORKER_MARKERS[$index]-}
	if [[ -n $marker && -f $marker ]]; then
		wait "$pid" 2>/dev/null || true
		parallel_test_unregister_worker_root "$index"
		return 0
	fi
	if ! parallel_test_register_worker_root "$pid"; then
		wait "$pid" 2>/dev/null || true
		parallel_test_unregister_worker_root "$index"
		printf 'Error: worker %s exited without a completion marker and could not be captured (%s).\n' \
			"$pid" "$reason" >&2
		return 1
	fi
	inode=${PARALLEL_TEST_PIDFD_INODES[$index]-}
	start=${PARALLEL_TEST_START_TIMES[$index]-}
	group=${PARALLEL_TEST_PGIDS[$index]-}

	parallel_test_clear_cleanup_records
	parallel_test_capture_worker_processes "$pid" "$inode" "$start" "$group"
	parallel_test_signal_recorded_processes KILL
	parallel_test_wait_captured_worker_processes "$pid"
	parallel_test_clear_cleanup_records
	parallel_test_unregister_worker_root "$index"
	printf 'Error: worker %s exited without a completion marker (%s).\n' "$pid" "$reason" >&2
	return 1
}

parallel_test_register_or_reap_completed_worker() {
	local index pid marker
	index=$1
	pid=${PARALLEL_TEST_PIDS[$index]-}
	marker=${PARALLEL_TEST_WORKER_MARKERS[$index]-}

	if [[ -n $marker && -f $marker ]]; then
		wait "$pid" 2>/dev/null || true
		parallel_test_unregister_worker_root "$index"
		return 2
	fi
	parallel_test_start_worker_exit_watcher "$index" "$pid"
}

parallel_test_cleanup() {
	local original_status=$?
	local root pending_pid saved_hup saved_int saved_term

	[[ $PARALLEL_TEST_CLEANUP_ACTIVE == false ]] || return "$original_status"
	PARALLEL_TEST_CLEANUP_ACTIVE=true
	saved_hup=$(trap -p HUP 2>/dev/null || true)
	saved_int=$(trap -p INT 2>/dev/null || true)
	saved_term=$(trap -p TERM 2>/dev/null || true)
	trap '' HUP INT TERM

	if [[ $PARALLEL_TEST_LAUNCHING == true ]]; then
		pending_pid=${PARALLEL_TEST_LAUNCH_PID:-}
		if [[ -z $pending_pid ]]; then pending_pid=${!:-}; fi
		parallel_test_register_pending_worker "$pending_pid" || true
	fi
	parallel_test_reap_completed_workers
	parallel_test_clear_cleanup_records

	PARALLEL_TEST_FREEZING=true
	parallel_test_freeze_worker_roots
	parallel_test_record_all_processes
	parallel_test_signal_recorded_processes KILL
	parallel_test_wait_recorded_processes
	PARALLEL_TEST_FREEZING=false
	parallel_test_wait_all_worker_watchers
	parallel_test_stop_event_relay

	root=$PARALLEL_TEST_ROOT
	if [[ -n $root ]]; then
		rm -rf -- "$root" 2>/dev/null || true
	fi
	PARALLEL_TEST_ROOT=''
	PARALLEL_TEST_PIDS=()
	PARALLEL_TEST_PGIDS=()
	PARALLEL_TEST_START_TIMES=()
	PARALLEL_TEST_PIDFD_INODES=()
	PARALLEL_TEST_WORKER_MARKERS=()
	PARALLEL_TEST_WATCHER_PIDS=()
	PARALLEL_TEST_RUNNING=0
	parallel_test_clear_cleanup_records
	PARALLEL_TEST_LAUNCHING=false
	PARALLEL_TEST_LAUNCH_PID=''
	if [[ $PARALLEL_TEST_MONITOR_CHANGED == true ]]; then
		set +m
		PARALLEL_TEST_MONITOR_CHANGED=false
	fi

	if [[ -n $saved_hup ]]; then eval "$saved_hup"; else trap - HUP; fi
	if [[ -n $saved_int ]]; then eval "$saved_int"; else trap - INT; fi
	if [[ -n $saved_term ]]; then eval "$saved_term"; else trap - TERM; fi
	return "$original_status"
}

parallel_test_exit_trap() {
	local status=$?
	parallel_test_cleanup || true
	return "$status"
}

parallel_test_signal_trap() {
	local status=$1
	[[ $PARALLEL_TEST_CLEANUP_ACTIVE == false ]] || return 0
	parallel_test_cleanup || true
	exit "$status"
}

parallel_test_worker_reset_harness_state() {
	PARALLEL_TEST_ROOT=''
	PARALLEL_TEST_PIDS=()
	PARALLEL_TEST_PGIDS=()
	PARALLEL_TEST_START_TIMES=()
	PARALLEL_TEST_PIDFD_INODES=()
	PARALLEL_TEST_WORKER_MARKERS=()
	PARALLEL_TEST_WATCHER_PIDS=()
	PARALLEL_TEST_RUNNING=0
	PARALLEL_TEST_CLEANUP_ACTIVE=false
	PARALLEL_TEST_LAUNCHING=false
	PARALLEL_TEST_LAUNCH_PID=''
	PARALLEL_TEST_FREEZING=false
	PARALLEL_TEST_MONITOR_CHANGED=false
	PARALLEL_TEST_WORKER_RESOURCES_STOPPED=false
	PARALLEL_TEST_WORKER_ABNORMAL_CLEANUP_DONE=false
	PARALLEL_TEST_WORKER_NORMAL_COMPLETION=false
	PARALLEL_TEST_WORKER_ABNORMAL_REPORTED=false
	parallel_test_clear_cleanup_records
}

parallel_test_worker_report_abnormal_exit() {
	[[ $PARALLEL_TEST_WORKER_NORMAL_COMPLETION == false ]] || return 0
	[[ $PARALLEL_TEST_WORKER_ABNORMAL_REPORTED == false ]] || return 0
	PARALLEL_TEST_WORKER_ABNORMAL_REPORTED=true
	parallel_test_send_worker_event abnormal "$BASHPID" >/dev/null 2>&1 || true
}

parallel_test_worker_cleanup_before_exit() {
	local worker_pid=$BASHPID worker_start

	[[ $PARALLEL_TEST_WORKER_NORMAL_COMPLETION == false ]] || return 0
	[[ $PARALLEL_TEST_WORKER_ABNORMAL_CLEANUP_DONE == false ]] || return 0
	PARALLEL_TEST_WORKER_ABNORMAL_CLEANUP_DONE=true
	parallel_test_worker_report_abnormal_exit
	parallel_test_worker_stop_owned_resources || true
	worker_start=$(parallel_test_process_start_time "$worker_pid" 2>/dev/null || true)
	[[ -n $worker_start ]] || return 0
	# A worker that cannot complete normally owns exact cleanup of its remaining
	# descendants, independently of the parent's cancellation cleanup.
	parallel_test_stop_exact_process_tree "$worker_pid" "$worker_start" "$worker_pid"
}

parallel_test_worker_stop_owned_resources() {
	[[ $PARALLEL_TEST_WORKER_RESOURCES_STOPPED == false ]] || return 0
	wallpaper_test_fast_shared_sandbox_stop || return 1
	PARALLEL_TEST_WORKER_RESOURCES_STOPPED=true
}

parallel_test_worker_mark_normal_completion() {
	[[ -n $PARALLEL_TEST_WORKER_CLEANUP_MARKER ]] || return 1
	[[ $PARALLEL_TEST_WORKER_RESOURCES_STOPPED == true ]] || return 1
	[[ $PARALLEL_TEST_WORKER_NORMAL_COMPLETION == false ]] || return 0
	: >"$PARALLEL_TEST_WORKER_CLEANUP_MARKER" || return 1
	PARALLEL_TEST_WORKER_NORMAL_COMPLETION=true
}

parallel_test_worker_exit_trap() {
	local status=$?

	parallel_test_worker_cleanup_before_exit || true
	return "$status"
}

parallel_test_worker_signal_trap() {
	local status=$1

	parallel_test_worker_cleanup_before_exit || true
	exit "$status"
}

parallel_test_prepare_worker() {
	local marker=$1

	parallel_test_worker_reset_harness_state || return 1
	PARALLEL_TEST_WORKER_CLEANUP_MARKER=$marker
	trap 'parallel_test_worker_exit_trap' EXIT
	trap 'parallel_test_worker_signal_trap 129' HUP
	trap 'parallel_test_worker_signal_trap 130' INT
	trap 'parallel_test_worker_signal_trap 143' TERM
}

trap 'parallel_test_exit_trap' EXIT
trap 'parallel_test_signal_trap 129' HUP
trap 'parallel_test_signal_trap 130' INT
trap 'parallel_test_signal_trap 143' TERM

fail() {
	printf 'not ok %d - %s\n' "$TESTS_RUN" "$1"
	TESTS_FAILED=$((TESTS_FAILED + 1))
}

pass() {
	printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

assert_eq() {
	local expected=$1
	local actual=$2
	local message=$3

	if [[ $actual != "$expected" ]]; then
		printf '  %s\n  expected: %q\n  actual:   %q\n' "$message" "$expected" "$actual" >&2
		return 1
	fi
}

assert_contains() {
	local haystack=$1
	local needle=$2
	local message=$3

	if [[ $haystack != *"$needle"* ]]; then
		printf '  %s\n  missing: %q\n  output:  %q\n' "$message" "$needle" "$haystack" >&2
		return 1
	fi
}

assert_path_absent() {
	local path=$1 message=$2
	if [[ -e $path || -L $path ]]; then
		printf '  %s\n  unexpected path: %s\n' "$message" "$path" >&2
		return 1
	fi
}

wallpaper_test_fast_shared_sandbox_stop() {
	local pid=$WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID
	local start=$WALLPAPER_TEST_FAST_SHARED_SANDBOX_START
	local directory=$WALLPAPER_TEST_FAST_SHARED_SANDBOX_DIRECTORY
	local request_fd=$WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST_FD
	local response_fd=$WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE_FD

	if [[ -n $pid && -n $start ]]; then
		parallel_test_stop_exact_process_tree "$pid" "$start" || true
	fi
	if [[ -n $request_fd ]]; then
		eval "exec ${request_fd}>&-" || true
	fi
	if [[ -n $response_fd ]]; then
		eval "exec ${response_fd}<&-" || true
	fi
	if [[ -n $directory ]]; then
		rm -rf -- "$directory" 2>/dev/null || true
	fi

	WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_START=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_ROOT=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_DIRECTORY=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST_FD=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE_FD=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_ROOT=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_REQUEST=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_RESPONSE=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_OWNER=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_STDERR=''
}

wallpaper_test_fast_shared_sandbox_detach() {
	local request_fd=$WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST_FD
	local response_fd=$WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE_FD

	if [[ -n $request_fd ]]; then
		eval "exec ${request_fd}>&-" || true
	fi
	if [[ -n $response_fd ]]; then
		eval "exec ${response_fd}<&-" || true
	fi
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_START=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_ROOT=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_DIRECTORY=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST_FD=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE_FD=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_ROOT=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_REQUEST=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_RESPONSE=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_OWNER=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_STDERR=''
}

wallpaper_test_fast_shared_sandbox_failure_text() {
	local stderr_file=$WALLPAPER_TEST_FAST_SHARED_SANDBOX_STDERR line

	printf 'Error: fast wallpaper sandbox server failed; its request pipe was closed.\n'
	if [[ -n $stderr_file && -s $stderr_file ]]; then
		while IFS= read -r line || [[ -n $line ]]; do
			printf '%s\n' "$line"
		done <"$stderr_file"
	fi
}

wallpaper_test_fast_shared_sandbox_report_failure() {
	wallpaper_test_fast_shared_sandbox_failure_text >&2
}

wallpaper_test_fast_shared_sandbox_start() {
	local root=${PARALLEL_TEST_WORKER_ROOT:-$FIXTURE_ROOT}
	local directory node_request node_response node_root server_stderr server_failure startup_status
	local server_script startup sandbox_pid sandbox_start request_fd response_fd startup_fd
	local coproc_request_fd coproc_response_fd startup_response_fd startup_relay_pid startup_relay_inode

	if [[ -n $WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID ]]; then
		sandbox_start=$(parallel_test_process_start_time "$WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID" 2>/dev/null || true)
		if [[ $WALLPAPER_TEST_FAST_SHARED_SANDBOX_OWNER == "$BASHPID" && \
			$sandbox_start == "$WALLPAPER_TEST_FAST_SHARED_SANDBOX_START" && \
			$WALLPAPER_TEST_FAST_SHARED_SANDBOX_ROOT == "$root" ]]; then
			return 0
		fi
		if [[ $WALLPAPER_TEST_FAST_SHARED_SANDBOX_OWNER == "$BASHPID" ]]; then
			wallpaper_test_fast_shared_sandbox_stop
		else
			wallpaper_test_fast_shared_sandbox_detach
		fi
	fi
	[[ -d $root ]] || return 1
	directory=$(mktemp -d "$root/.dotfiles-sandbox.XXXXXX") || return 1
	node_request="$directory/node-request"
	node_response="$directory/node-response"
	node_root="$directory/node"
	server_stderr="$directory/server.stderr"
	server_failure="$directory/server.failed"
	startup_status="$directory/startup-status"
	if ! mkdir -p -- "$node_root" || ! mkfifo -- "$node_request" "$node_response" "$startup_status"; then
		rm -rf -- "$directory"
		return 1
	fi
	if ! exec {startup_fd}<>"$startup_status"; then
		rm -rf -- "$directory"
		return 1
	fi
	server_script='
node_pid=
node_input=
node_output=
proxy_input=
proxy_output=
proxy_pid=
startup_complete=false
cleanup() {
	if [[ $startup_complete != true ]]; then printf "failed\n" >"$DOTFILES_TEST_FAST_STARTUP_STATUS" || true; fi
	if [[ -n $proxy_pid ]]; then kill -KILL "$proxy_pid" 2>/dev/null || true; wait "$proxy_pid" 2>/dev/null || true; fi
	if [[ -n $node_pid ]]; then kill -KILL "$node_pid" 2>/dev/null || true; wait "$node_pid" 2>/dev/null || true; fi
	if [[ -n $node_input ]]; then eval "exec ${node_input}>&-" || true; fi
	if [[ -n $node_output ]]; then eval "exec ${node_output}<&-" || true; fi
	if [[ -n $proxy_input ]]; then eval "exec ${proxy_input}>&-" || true; fi
	if [[ -n $proxy_output ]]; then eval "exec ${proxy_output}<&-" || true; fi
}
trap cleanup EXIT
trap "exit 143" TERM
trap "exit 130" INT

server_failure() {
	printf "failed\n" >"$DOTFILES_TEST_FAST_NODE_FAILURE"
}
server_read_response() {
	local header stdout_length stderr_length total
	IFS= read -r header <&"$1" || return 1
	local response_pattern="^status=(0|[1-9][0-9]*) stdout=(0|[1-9][0-9]*) stderr=(0|[1-9][0-9]*)$"
	[[ $header =~ $response_pattern ]] || return 1
	stdout_length=${BASH_REMATCH[2]}
	stderr_length=${BASH_REMATCH[3]}
	total=$((stdout_length + stderr_length + 2))
	dd iflag=fullblock bs=64K count="${total}B" status=none <&"$1" || return 1
}
proxy_request() {
	local request header stdout_length stderr_length total client_request client_response
	while :; do
		client_request=
		client_response=
		exec {client_request}<"$DOTFILES_TEST_FAST_NODE_REQUEST"
		exec {client_response}>"$DOTFILES_TEST_FAST_NODE_RESPONSE"
		while IFS= read -r request <&"$client_request"; do
			if ! printf "%s\n" "$request" >&"$proxy_input"; then
				server_failure
				kill -TERM "$$"
				return
			fi
			if ! IFS= read -r header <&"$proxy_output"; then
				server_failure
				kill -TERM "$$"
				return
			fi
			local response_pattern="^status=(0|[1-9][0-9]*) stdout=(0|[1-9][0-9]*) stderr=(0|[1-9][0-9]*)$"
			if [[ ! $header =~ $response_pattern ]]; then
				server_failure
				kill -TERM "$$"
				return
			fi
			stdout_length=${BASH_REMATCH[2]}
			stderr_length=${BASH_REMATCH[3]}
			total=$((stdout_length + stderr_length + 2))
			if ! { printf "%s\n" "$header"; dd iflag=fullblock bs=64K count="${total}B" status=none <&"$proxy_output"; } >&"$client_response"; then
				server_failure
				kill -TERM "$$"
				return
			fi
		done
		eval "exec ${client_request}<&-"
		eval "exec ${client_response}>&-"
	done
}

coproc WALLPAPER_TEST_FAST_NODE_SERVER { "$DOTFILES_TEST_FAST_NODE" "$DOTFILES_TEST_FAST_NODE_HELPER" --server; }
node_pid=$WALLPAPER_TEST_FAST_NODE_SERVER_PID
node_input=${WALLPAPER_TEST_FAST_NODE_SERVER[1]}
node_output=${WALLPAPER_TEST_FAST_NODE_SERVER[0]}
if ! printf "[\"__dotfiles_test_ready__\"]\n" >&"$node_input" || ! server_read_response "$node_output" >/dev/null; then
	server_failure
	exit 1
fi
exec {proxy_input}>&"$node_input"
exec {proxy_output}<&"$node_output"
eval "exec ${node_input}>&-"
eval "exec ${node_output}<&-"
node_input=
node_output=
if ! printf "ready\n" >"$DOTFILES_TEST_FAST_STARTUP_STATUS"; then
	server_failure
	exit 1
fi
startup_complete=true
proxy_request &
proxy_pid=$!
while IFS= read -r request; do eval "$request"; status=$?; printf "%s\n" "$status"; done'
	coproc WALLPAPER_TEST_FAST_SHARED_SERVER {
		setsid env -i \
		HOME="$FIXTURE_HOME" \
		PATH="/usr/bin:/bin" \
		DOTFILES_TEST_FAST_NODE="${DOTFILES_TEST_FAST_SERVER_NODE:-$node_root/$(basename -- "$HOST_NODE_REAL")}" \
		DOTFILES_TEST_FAST_NODE_HELPER="$FIXTURE_REPO/lib/dotfiles/wallpaper-files.mjs" \
		DOTFILES_TEST_FAST_NODE_REQUEST="$node_request" \
		DOTFILES_TEST_FAST_NODE_RESPONSE="$node_response" \
		DOTFILES_TEST_FAST_NODE_FAILURE="$server_failure" \
		DOTFILES_TEST_FAST_STARTUP_STATUS="$startup_status" \
		"$BWRAP" \
			--ro-bind / / \
			--dev-bind /dev /dev \
			--bind "$root" "$root" \
			--ro-bind "$(dirname -- "$HOST_NODE_REAL")" "$node_root" \
			--tmpfs /home \
			--tmpfs /usr/share/omarchy \
			-- bash -c "$server_script" \
			2>"$server_stderr"
	}
	sandbox_pid=${WALLPAPER_TEST_FAST_SHARED_SERVER_PID-}
	coproc_request_fd=${WALLPAPER_TEST_FAST_SHARED_SERVER[1]-}
	coproc_response_fd=${WALLPAPER_TEST_FAST_SHARED_SERVER[0]-}
	sandbox_start=$(parallel_test_process_start_time "$sandbox_pid" 2>/dev/null || true)
	request_fd=''
	response_fd=''
	if [[ -n $coproc_request_fd ]] && exec {request_fd}>&"$coproc_request_fd"; then
		eval "exec ${coproc_request_fd}>&-" || true
	fi
	if [[ -n $coproc_response_fd ]] && exec {response_fd}<&"$coproc_response_fd"; then
		eval "exec ${coproc_response_fd}<&-" || true
	fi

	WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID=$sandbox_pid
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_START=$sandbox_start
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_ROOT=$root
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_DIRECTORY=$directory
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE=''
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST_FD=$request_fd
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE_FD=$response_fd
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_ROOT=$node_root
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_REQUEST=$node_request
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_RESPONSE=$node_response
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_OWNER=$BASHPID
	WALLPAPER_TEST_FAST_SHARED_SANDBOX_STDERR=$server_stderr
	if [[ -z $sandbox_start || -z $request_fd || -z $response_fd ]]; then
		eval "exec ${startup_fd}>&-" || true
		wallpaper_test_fast_shared_sandbox_report_failure
		wallpaper_test_fast_shared_sandbox_stop
		return 1
	fi
	if ! exec {startup_response_fd}<&"$response_fd"; then
		eval "exec ${startup_fd}>&-" || true
		wallpaper_test_fast_shared_sandbox_report_failure
		wallpaper_test_fast_shared_sandbox_stop
		return 1
	fi
	(
		if ! IFS= read -r _ <&"$startup_response_fd"; then
			printf 'failed\n' >"$startup_status" || true
		fi
	) &
	startup_relay_pid=$!
	startup_relay_inode=$(parallel_test_pidfd_inode "$startup_relay_pid" 2>/dev/null || true)
	eval "exec ${startup_response_fd}<&-" || true

	if ! IFS= read -r startup <&"$startup_fd" || [[ $startup != ready ]]; then
		parallel_test_pidfd_signal "$startup_relay_pid" "$startup_relay_inode" KILL || true
		wait "$startup_relay_pid" 2>/dev/null || true
		eval "exec ${startup_fd}>&-" || true
		wallpaper_test_fast_shared_sandbox_report_failure
		wallpaper_test_fast_shared_sandbox_stop
		return 1
	fi
	parallel_test_pidfd_signal "$startup_relay_pid" "$startup_relay_inode" KILL || true
	wait "$startup_relay_pid" 2>/dev/null || true
	eval "exec ${startup_fd}>&-" || true
}

wallpaper_test_fast_shared_sandbox_run() {
	local working_directory=$1 command_path=$2 input_file output_file request_line quoted assignment argument failure_text
	local real_node="$FIXTURE_REAL_NODE_DIR/$(basename -- "$HOST_NODE_REAL")"
	local -a environment=()
	shift 2

	if [[ -n $WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_ROOT ]]; then
		real_node="$WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_ROOT/$(basename -- "$HOST_NODE_REAL")"
	fi
	environment=(
		"HOME=$FIXTURE_HOME"
		"XDG_DATA_HOME=${DOTFILES_TEST_XDG_DATA_HOME-}"
		"XDG_CONFIG_HOME=$FIXTURE_CONFIG"
		"XDG_STATE_HOME=$FIXTURE_STATE"
		"XDG_CACHE_HOME=$FIXTURE_CACHE"
		"XDG_RUNTIME_DIR=$FIXTURE_RUNTIME"
		"TMPDIR=$FIXTURE_TMP"
		"OMARCHY_PATH=$FIXTURE_OMARCHY"
		"DOTFILES_WALLPAPER_PACKAGED_THEMES_ROOT=$FIXTURE_WALLPAPER_THEMES"
		"PATH=$command_path"
		"DOTFILES_TEST_CALL_LOG=$CALL_LOG"
		"DOTFILES_TEST_REPO=$FIXTURE_REPO"
		"DOTFILES_TEST_FAKE_BIN=$FIXTURE_BIN"
		"DOTFILES_TEST_HOME=$FIXTURE_HOME"
		"DOTFILES_TEST_OMARCHY_VERSION=${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"
		"DOTFILES_TEST_SKILL_COUNT_DRIFT=${DOTFILES_TEST_SKILL_COUNT_DRIFT:-false}"
		"DOTFILES_TEST_SKILL_INSTALL_FAILURE=${DOTFILES_TEST_SKILL_INSTALL_FAILURE:-false}"
		"DOTFILES_TEST_SKILL_VERIFY_FAILURE=${DOTFILES_TEST_SKILL_VERIFY_FAILURE:-false}"
		"DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE=${DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE:-false}"
		"DOTFILES_TEST_SKILL_UPDATE_COLLISION=${DOTFILES_TEST_SKILL_UPDATE_COLLISION:-false}"
		"DOTFILES_TEST_SKILL_UNRELATED_FAILURE=${DOTFILES_TEST_SKILL_UNRELATED_FAILURE:-none}"
		"DOTFILES_TEST_GUM_RESPONSES=${DOTFILES_TEST_GUM_RESPONSES-}"
		"DOTFILES_TEST_XDG_DATA_HOME=${DOTFILES_TEST_XDG_DATA_HOME-}"
		"DOTFILES_TEST_INSTALLED_PACKAGES=$FIXTURE_ROOT/installed-packages"
		"DOTFILES_TEST_EXPLICIT_PACKAGES=$FIXTURE_ROOT/explicit-packages"
		"DOTFILES_TEST_PACKAGE_METADATA=$FIXTURE_ROOT/package-metadata"
		"DOTFILES_TEST_ARCH_PACKAGE_STATE=$ARCH_PACKAGE_STATE"
		"DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER=$ARCH_PACKAGE_ADD_MARKER"
		"DOTFILES_TEST_ARCH_INSTALL_FAILURE=${DOTFILES_TEST_ARCH_INSTALL_FAILURE:-false}"
		"DOTFILES_TEST_ARCH_VERIFY_FAILURE=${DOTFILES_TEST_ARCH_VERIFY_FAILURE:-false}"
		"DOTFILES_TEST_FIND_COUNT=${DOTFILES_TEST_FIND_COUNT-}"
		"DOTFILES_TEST_PACMAN_VERIFY_FAILURE=${DOTFILES_TEST_PACMAN_VERIFY_FAILURE:-false}"
		"DOTFILES_TEST_YAY_METADATA_FAILURE=${DOTFILES_TEST_YAY_METADATA_FAILURE:-false}"
		"DOTFILES_TEST_REAL_NODE=$real_node"
		"DOTFILES_TEST_FAST_SHARED_REQUEST=${WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_REQUEST-}"
		"DOTFILES_TEST_FAST_SHARED_RESPONSE=${WALLPAPER_TEST_FAST_SHARED_SANDBOX_NODE_RESPONSE-}"
		"DOTFILES_TEST_BRAVE_SYSTEM=$FIXTURE_BRAVE_SYSTEM"
		"DOTFILES_TEST_BRAVE_METADATA=$BRAVE_METADATA_ROOT"
		"DOTFILES_TEST_BRAVE_PACKAGES=$BRAVE_PACKAGE_DB"
		"DOTFILES_TEST_BRAVE_PROVIDERS=$BRAVE_PROVIDER_DB"
		"DOTFILES_TEST_BRAVE_OWNERS=$BRAVE_OWNER_DB"
		"DOTFILES_TEST_BRAVE_FAILURE_MARKERS=$BRAVE_FAILURE_MARKERS"
		"DOTFILES_TEST_BRAVE_UID=${DOTFILES_TEST_BRAVE_UID:-$(id -u)}"
		"DOTFILES_TEST_BRAVE_FAIL_BEFORE=${DOTFILES_TEST_BRAVE_FAIL_BEFORE-}"
		"DOTFILES_TEST_BRAVE_FAIL_AFTER=${DOTFILES_TEST_BRAVE_FAIL_AFTER-}"
		"DOTFILES_TEST_BRAVE_FAIL_RECEIPT=${DOTFILES_TEST_BRAVE_FAIL_RECEIPT-}"
		"DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE=${DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE-}"
		"DOTFILES_TEST_BRAVE_FAIL_BACKUP=${DOTFILES_TEST_BRAVE_FAIL_BACKUP:-false}"
		"DOTFILES_TEST_BRAVE_BACKUP_RACE=${DOTFILES_TEST_BRAVE_BACKUP_RACE:-false}"
		"DOTFILES_TEST_BRAVE_SENSITIVE=${DOTFILES_TEST_BRAVE_SENSITIVE:-$FIXTURE_ROOT/brave-sensitive}"
		"DOTFILES_TEST_BRAVE_FAIL_PREVIEW=${DOTFILES_TEST_BRAVE_FAIL_PREVIEW:-false}"
		"DOTFILES_TEST_BRAVE_CORRUPT_STAGE=${DOTFILES_TEST_BRAVE_CORRUPT_STAGE:-false}"
		"DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA=${DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA-}"
		"DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION=${DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION-}"
		"DOTFILES_TEST_BRAVE_STAGE_LINK_KIND=${DOTFILES_TEST_BRAVE_STAGE_LINK_KIND-}"
		"DOTFILES_TEST_BRAVE_STAGE_REFERENT=${DOTFILES_TEST_BRAVE_STAGE_REFERENT:-$FIXTURE_ROOT/brave-stage-referent}"
		"DOTFILES_TEST_BRAVE_RECEIPT_RACE=${DOTFILES_TEST_BRAVE_RECEIPT_RACE-}"
		"DOTFILES_TEST_BRAVE_RECEIPT_REFERENT=${DOTFILES_TEST_BRAVE_RECEIPT_REFERENT:-$FIXTURE_ROOT/brave-receipt-referent}"
		"DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT=${DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT-}"
		"DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER=${DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER-}"
		"DOTFILES_TEST_BRAVE_RENAME_FAILURE=${DOTFILES_TEST_BRAVE_RENAME_FAILURE-}"
		"DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE=${DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE-}"
		"DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER=${DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER-}"
		"DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER=${DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER:-false}"
		"DOTFILES_TEST_BRAVE_FALSE_SUCCESS=${DOTFILES_TEST_BRAVE_FALSE_SUCCESS-}"
		"DOTFILES_TEST_BRAVE_RACE=${DOTFILES_TEST_BRAVE_RACE-}"
		"DOTFILES_TEST_WALLPAPER_FAIL=${DOTFILES_TEST_WALLPAPER_FAIL-}"
		"DOTFILES_TEST_WALLPAPER_FAIL_ROLLBACK=${DOTFILES_TEST_WALLPAPER_FAIL_ROLLBACK:-false}"
		"DOTFILES_TEST_WALLPAPER_VERSION_CHANGES=${DOTFILES_TEST_WALLPAPER_VERSION_CHANGES:-false}"
		"DOTFILES_TEST_WALLPAPER_RACE=${DOTFILES_TEST_WALLPAPER_RACE-}"
		"DOTFILES_TEST_WALLPAPER_RACE_PATH=${DOTFILES_TEST_WALLPAPER_RACE_PATH-}"
		"DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS=${DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS-}"
		"DOTFILES_TEST_WALLPAPER_IMAGE_RACE_PATH=${DOTFILES_TEST_WALLPAPER_IMAGE_RACE_PATH-}"
		"DOTFILES_TEST_WALLPAPER_IMAGE_RACE_REPLACEMENT=${DOTFILES_TEST_WALLPAPER_IMAGE_RACE_REPLACEMENT-}"
		"DOTFILES_TEST_REAL_MAGICK=$HOST_MAGICK_REAL"
		"DOTFILES_TEST_WALLPAPER_SIGNAL=${DOTFILES_TEST_WALLPAPER_SIGNAL-}"
		"DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=${DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE-}"
		"DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH=${DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH-}"
		"DOTFILES_TEST_WALLPAPER_POST_PENDING_REPLACEMENT=${DOTFILES_TEST_WALLPAPER_POST_PENDING_REPLACEMENT-}"
		"DOTFILES_TEST_WALLPAPER_PREPARATION_FAIL=${DOTFILES_TEST_WALLPAPER_PREPARATION_FAIL-}"
		"DOTFILES_TEST_WALLPAPER_DELETE_RACE_PATH=${DOTFILES_TEST_WALLPAPER_DELETE_RACE_PATH-}"
		"DOTFILES_TEST_WALLPAPER_DELETE_RACE_REPLACEMENT=${DOTFILES_TEST_WALLPAPER_DELETE_RACE_REPLACEMENT-}"
		"DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE=${DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE-}"
		"DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE_REPLACEMENT=${DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE_REPLACEMENT-}"
		"DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE=${DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE-}"
		"DOTFILES_TEST_FAST_WALLPAPER_FILES=${DOTFILES_TEST_FAST_WALLPAPER_FILES:-false}"
		"DOTFILES_UI=${DOTFILES_UI:-bash}"
	)
	input_file="$WALLPAPER_TEST_FAST_SHARED_SANDBOX_DIRECTORY/input.$BASHPID.$RANDOM"
	output_file="$WALLPAPER_TEST_FAST_SHARED_SANDBOX_DIRECTORY/output.$BASHPID.$RANDOM"
	if ! printf '%b' "${DOTFILES_TEST_INPUT-}" >"$input_file"; then
		COMMAND_STATUS=1
		COMMAND_OUTPUT=''
		return 1
	fi
	request_line="cd -- $(printf '%q' "$working_directory") && env -i"
	for assignment in "${environment[@]}"; do
		printf -v quoted ' %q' "$assignment"
		request_line+=$quoted
	done
	request_line+=' '
	for argument in "$@"; do
		printf -v quoted '%q ' "$argument"
		request_line+=$quoted
	done
	printf -v quoted '< %q > %q 2>&1' "$input_file" "$output_file"
	request_line+=" $quoted"
	if ! printf '%s\n' "$request_line" >&"$WALLPAPER_TEST_FAST_SHARED_SANDBOX_REQUEST_FD"; then
		COMMAND_STATUS=1
		COMMAND_OUTPUT=$(wallpaper_test_fast_shared_sandbox_failure_text)
		rm -f -- "$input_file" "$output_file"
		return 1
	fi
	if ! IFS= read -r COMMAND_STATUS <&"$WALLPAPER_TEST_FAST_SHARED_SANDBOX_RESPONSE_FD"; then
		COMMAND_STATUS=1
		COMMAND_OUTPUT=$(wallpaper_test_fast_shared_sandbox_failure_text)
		rm -f -- "$input_file" "$output_file"
		return 1
	fi
	if [[ ! $COMMAND_STATUS =~ ^[0-9]+$ || $COMMAND_STATUS -gt 255 ]]; then
		COMMAND_STATUS=1
		COMMAND_OUTPUT=''
		rm -f -- "$input_file" "$output_file"
		return 1
	fi
	if [[ -f $output_file ]]; then COMMAND_OUTPUT=$(<"$output_file"); else COMMAND_OUTPUT=''; fi
	rm -f -- "$input_file" "$output_file"
	if [[ -f $WALLPAPER_TEST_FAST_SHARED_SANDBOX_DIRECTORY/server.failed ]]; then
		failure_text=$(wallpaper_test_fast_shared_sandbox_failure_text)
		if [[ -n $COMMAND_OUTPUT ]]; then COMMAND_OUTPUT+=$'\n'; fi
		COMMAND_OUTPUT+=$failure_text
		COMMAND_STATUS=1
	fi
	return 0
}

new_fixture() {
	if [[ -z $PARALLEL_TEST_WORKER_ROOT ]]; then
		wallpaper_test_fast_shared_sandbox_stop || true
	fi
	BWRAP_EXTRA_ARGS=()
	if [[ -n ${FIXTURE_ROOT-} && -d $FIXTURE_ROOT ]]; then
		rm -rf "$FIXTURE_ROOT"
	fi
	if [[ -n ${OUTSIDE_ROOT-} && -d $OUTSIDE_ROOT ]]; then
		rm -rf "$OUTSIDE_ROOT"
	fi
	if [[ -n $PARALLEL_TEST_WORKER_ROOT && -d $PARALLEL_TEST_WORKER_ROOT ]]; then
		FIXTURE_ROOT=$(mktemp -d "$PARALLEL_TEST_WORKER_ROOT/fixture.XXXXXX")
		OUTSIDE_ROOT=$(mktemp -d "$PARALLEL_TEST_WORKER_ROOT/outside.XXXXXX")
	elif [[ -n $PARALLEL_TEST_ROOT && -d $PARALLEL_TEST_ROOT ]]; then
		FIXTURE_ROOT=$(mktemp -d "$PARALLEL_TEST_ROOT/fixture.XXXXXX")
		OUTSIDE_ROOT=$(mktemp -d "$PARALLEL_TEST_ROOT/outside.XXXXXX")
	else
		FIXTURE_ROOT=$(mktemp -d)
		OUTSIDE_ROOT=$(mktemp -d)
	fi
	FIXTURE_REPO="$FIXTURE_ROOT/relocated/dotfiles"
	FIXTURE_HOME="$FIXTURE_ROOT/user/home"
	FIXTURE_CONFIG="$FIXTURE_ROOT/user/config"
	FIXTURE_STATE="$FIXTURE_ROOT/user/state"
	FIXTURE_CACHE="$FIXTURE_ROOT/user/cache"
	FIXTURE_RUNTIME="$FIXTURE_ROOT/user/runtime"
	FIXTURE_TMP="$FIXTURE_ROOT/tmp"
	FIXTURE_BIN="$FIXTURE_ROOT/fake-bin"
	FIXTURE_WALLPAPER_BIN="$FIXTURE_ROOT/wallpaper-bin"
	FIXTURE_OMARCHY="$FIXTURE_ROOT/packaged-omarchy"
	FIXTURE_WALLPAPER_THEMES="$FIXTURE_OMARCHY/themes"
	CALL_LOG="$FIXTURE_ROOT/external-calls"
	ARCH_PACKAGE_STATE="$FIXTURE_ROOT/installed-arch-packages"
	ARCH_PACKAGE_ADD_MARKER="$FIXTURE_ROOT/arch-package-add-attempted"
	FIXTURE_BRAVE_SYSTEM="$FIXTURE_ROOT/system/etc/brave"
	FIXTURE_POWER_POLICY_SYSTEM="$FIXTURE_ROOT/system/etc"
	POWER_POLICY_METADATA_ROOT="$FIXTURE_ROOT/power-policy-metadata"
	POWER_POLICY_RUNTIME="$FIXTURE_ROOT/power-policy-runtime"
	BRAVE_METADATA_ROOT="$FIXTURE_ROOT/brave-metadata"
	BRAVE_PACKAGE_DB="$FIXTURE_ROOT/brave-packages"
	BRAVE_PROVIDER_DB="$FIXTURE_ROOT/brave-providers"
	BRAVE_OWNER_DB="$FIXTURE_ROOT/brave-provider-owners"
	BRAVE_FAILURE_MARKERS="$FIXTURE_ROOT/brave-failure-markers"
	BRAVE_CANARY_ROOT="$FIXTURE_ROOT/brave-canaries"
	FIXTURE_REAL_NODE_DIR="$FIXTURE_ROOT/real-node"

	mkdir -p "$FIXTURE_REPO/bin" "$FIXTURE_REPO/lib/dotfiles" "$FIXTURE_HOME" "$FIXTURE_CONFIG" \
		"$FIXTURE_STATE" "$FIXTURE_CACHE" "$FIXTURE_RUNTIME" "$FIXTURE_TMP" "$FIXTURE_BIN" "$FIXTURE_WALLPAPER_BIN" "$FIXTURE_OMARCHY" \
		"$FIXTURE_WALLPAPER_THEMES" \
		"$BRAVE_METADATA_ROOT" "$BRAVE_FAILURE_MARKERS" "$BRAVE_CANARY_ROOT" "$FIXTURE_REAL_NODE_DIR" \
		"$POWER_POLICY_METADATA_ROOT" "$POWER_POLICY_RUNTIME" \
		"$OUTSIDE_ROOT/user-config" "$OUTSIDE_ROOT/global-skills" "$OUTSIDE_ROOT/packaged-omarchy"
	ln -s "$HOST_MAGICK_REAL" "$FIXTURE_BIN/magick"
	ln -s "$HOST_GIT_REAL" "$FIXTURE_WALLPAPER_BIN/git"
	if [[ ${DOTFILES_TEST_FAST_WALLPAPER_MAGICK:-false} == true ]]; then
		make_fake magick "file_command=$(printf '%q' "$HOST_FILE_REAL")
if [[ \${1-} == identify && \${2-} == -format && \${3-} == '%m|%w|%h\n' && \$# == 4 ]]; then
	image=\$4
	identify=true
elif [[ \$# == 3 && \$2 == -coalesce && \$3 == null: ]]; then
	image=\$1
	identify=false
else
	exit 64
fi

[[ -f \$image && ! -L \$image ]] || exit 1
mime=\$("\$file_command" --brief --mime-type -- "\$image") || exit 1
case \$mime in
	image/jpeg) format=JPEG ;;
	image/png) format=PNG ;;
	image/gif) format=GIF ;;
	image/bmp|image/x-ms-bmp) format=BMP ;;
	image/webp) format=WEBP ;;
	*) exit 1 ;;
esac
if [[ \$identify == true ]]; then printf '%s|4|3\n' "\$format"; fi
" "$FIXTURE_WALLPAPER_BIN"
	fi
	BWRAP_EXTRA_ARGS+=(--ro-bind "$(dirname -- "$HOST_NODE_REAL")" "$FIXTURE_REAL_NODE_DIR")
	printf 'outside user configuration\n' >"$OUTSIDE_ROOT/user-config/sentinel"
	printf 'outside global skill\n' >"$OUTSIDE_ROOT/global-skills/sentinel"
	printf 'outside packaged Omarchy\n' >"$OUTSIDE_ROOT/packaged-omarchy/sentinel"
	OUTSIDE_SNAPSHOT=$(snapshot_outside_canaries)
	: >"$CALL_LOG"
	printf '%s\n' thefuck tmux fzf less starship btop telegram-desktop zip ttfx jq socat >"$ARCH_PACKAGE_STATE"
	cp "$SOURCE_REPO/bin/dotfiles" "$FIXTURE_REPO/bin/dotfiles"
	if [[ ${DOTFILES_TEST_MINIMAL_WALLPAPER_FIXTURE:-false} == true ]]; then
		cp "$SOURCE_REPO/lib/dotfiles/core.sh" "$SOURCE_REPO/lib/dotfiles/wallpapers.sh" \
			"$SOURCE_REPO/lib/dotfiles/wizard.sh" "$FIXTURE_REPO/lib/dotfiles/"
	else
		cp "$SOURCE_REPO/lib/dotfiles/"*.sh "$FIXTURE_REPO/lib/dotfiles/"
	fi
	cp "$SOURCE_REPO/lib/dotfiles/"*.mjs "$FIXTURE_REPO/lib/dotfiles/"
	if [[ ${DOTFILES_TEST_FAST_WALLPAPER_FILES:-false} == true ]]; then
		cp "$SOURCE_REPO/tests/support/fast_wallpaper_files.sh" "$FIXTURE_REPO/lib/dotfiles/"
	fi
	cp "$SOURCE_REPO/packages.json" "$FIXTURE_REPO/packages.json"
	cp "$SOURCE_REPO/cleanup.json" "$FIXTURE_REPO/cleanup.json"
	if [[ ${DOTFILES_TEST_MINIMAL_WALLPAPER_FIXTURE:-false} != true ]]; then
		if [[ -f $SOURCE_REPO/README.md ]]; then
			cp "$SOURCE_REPO/README.md" "$FIXTURE_REPO/README.md"
		fi
		if [[ -d $SOURCE_REPO/brave ]]; then
			cp -a "$SOURCE_REPO/brave" "$FIXTURE_REPO/brave"
		fi
		if [[ -d $SOURCE_REPO/power-policy ]]; then
			cp -a "$SOURCE_REPO/power-policy" "$FIXTURE_REPO/power-policy"
		fi
		if [[ -d $SOURCE_REPO/config ]]; then
			cp -a "$SOURCE_REPO/config" "$FIXTURE_REPO/config"
		fi
		if [[ -d $SOURCE_REPO/docs ]]; then
			cp -a "$SOURCE_REPO/docs" "$FIXTURE_REPO/docs"
		fi
	fi
	mkdir -p "$FIXTURE_REPO/wallpapers/inbox" "$FIXTURE_REPO/wallpapers/library"
	cp "$SOURCE_REPO/wallpapers/inbox/.gitkeep" "$FIXTURE_REPO/wallpapers/inbox/.gitkeep"
	if [[ ${DOTFILES_TEST_MINIMAL_WALLPAPER_FIXTURE:-false} != true ]]; then
		if [[ -f $SOURCE_REPO/skills.json ]]; then
			cp "$SOURCE_REPO/skills.json" "$FIXTURE_REPO/skills.json"
		fi
		if [[ -f $SOURCE_REPO/Makefile ]]; then
			cp "$SOURCE_REPO/Makefile" "$FIXTURE_REPO/Makefile"
		fi
	fi

	make_fake omarchy 'printf "%s|HOME=%s|XDG_CONFIG_HOME=%s|XDG_STATE_HOME=%s|XDG_CACHE_HOME=%s\n" "$*" "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then
	printf "%s\n" "${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"
	exit 0
fi
if [[ ${1-} == pkg && ${2-} == present ]]; then
	shift 2
	for package in "$@"; do
		grep -Fxq -- "$package" "$DOTFILES_TEST_ARCH_PACKAGE_STATE" || exit 1
	done
	if [[ $DOTFILES_TEST_ARCH_VERIFY_FAILURE == true && -e $DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER ]]; then exit 75; fi
	exit 0
fi
if [[ ${1-} == pkg && ${2-} == add ]]; then
	touch "$DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER"
	[[ $DOTFILES_TEST_ARCH_INSTALL_FAILURE == false ]] || exit 76
	for package in "${@:3}"; do
		grep -Fxq -- "$package" "$DOTFILES_TEST_ARCH_PACKAGE_STATE" || printf "%s\n" "$package" >>"$DOTFILES_TEST_ARCH_PACKAGE_STATE"
	done
	exit 0
fi
exit 64'
	make_fake omarchy-shell 'exit 64'
	make_fake xdg-terminal-exec 'exit 64'
	make_fake hyprctl 'exit 64'
	make_fake omarchy-screensaver 'exit 64'
	make_fake omarchy-toggle-enabled 'exit 64'
	make_fake omarchy-hyprland-monitor-focused 'exit 64'
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake omarchy-pkg-add 'printf "omarchy-pkg-add %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake git 'printf "git %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake npx 'printf "npx %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake node 'if [[ ${1-} == --version ]]; then
	printf "v%s\n" "${DOTFILES_TEST_NODE_VERSION:-22.20.0}"
	exit 0
fi
exec "$DOTFILES_TEST_REAL_NODE" "$@"'
	make_fake npm 'exit 0'
	make_fake opencode 'printf "unexpected generic opencode invocation\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
}

fixture_git() {
	env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
		-u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_QUARANTINE_PATH -u GIT_NAMESPACE \
		-u GIT_CONFIG -u GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT=0 \
		GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null "$HOST_GIT_REAL" -C "$FIXTURE_REPO" "$@"
}

setup_wallpaper_fixture() {
	mkdir -p "$FIXTURE_REPO/wallpapers/inbox" "$FIXTURE_REPO/wallpapers/library" \
		"$FIXTURE_CONFIG/omarchy/themes" "$FIXTURE_CONFIG/omarchy/backgrounds" "$FIXTURE_WALLPAPER_THEMES"
	if [[ ${DOTFILES_TEST_SKIP_WALLPAPER_GIT:-false} == true ]]; then
		return 0
	fi
	setup_wallpaper_git_fixture
}

setup_wallpaper_git_fixture() {
	if [[ ! -d $FIXTURE_REPO/.git ]]; then
		fixture_git init -q --initial-branch=main || return 1
	fi
	fixture_git config --local user.name 'Wallpaper Fixture' || return 1
	fixture_git config --local user.email 'wallpaper-fixture@example.invalid' || return 1
	fixture_git config --local commit.gpgSign false || return 1
	fixture_git config --local core.hooksPath "$FIXTURE_REPO/.git/hooks" || return 1
	if ! fixture_git rev-parse --verify HEAD >/dev/null 2>&1; then
		fixture_git add -- packages.json cleanup.json wallpapers/inbox/.gitkeep || return 1
		fixture_git commit -qm 'Fixture baseline' || return 1
	fi
}

make_wallpaper_image() {
	local format=$1 destination=$2 color=${3-#2457a7} size=${4-4x3}
	magick -size "$size" "xc:$color" "$format:$destination"
}

wallpaper_digest() {
	sha256sum "$1" | { read -r digest _; printf '%s\n' "$digest"; }
}

assign_wallpaper_fixture() {
	local source=$1 theme=$2 extension=$3 digest destination
	digest=$(wallpaper_digest "$source") || return 1
	destination="$FIXTURE_REPO/wallpapers/library/$theme/$digest.$extension"
	mkdir -p "${destination%/*}"
	cp "$source" "$destination"
	printf '%s\n' "$destination"
}

brave_metadata_key() {
	printf '%s' "$1" | sha256sum | { read -r digest _; printf '%s\n' "$digest"; }
}

set_brave_metadata() {
	local logical=$1 uid=$2 gid=$3 mode=$4 key
	key=$(brave_metadata_key "$logical")
	printf '%s %s %s\n' "$uid" "$gid" "$mode" >"$BRAVE_METADATA_ROOT/$key"
}

setup_brave_fixture() {
	mkdir -p "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	chmod 0755 "$FIXTURE_BRAVE_SYSTEM" "$FIXTURE_BRAVE_SYSTEM/policies" "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	set_brave_metadata /etc/brave 0 0 0755
	set_brave_metadata /etc/brave/policies 0 0 0755
	set_brave_metadata /etc/brave/policies/managed 0 0 0755
	: >"$BRAVE_PACKAGE_DB"
	: >"$BRAVE_PROVIDER_DB"
	: >"$BRAVE_OWNER_DB"
}

install_brave_consumer() {
	local package=$1 version=${2-1:1.93.136-1} command path
	case $package in
		brave-bin) command=brave ;;
		brave-origin-bin) command=brave-origin ;;
		*) return 2 ;;
	esac
	path="$FIXTURE_BIN/$command"
	printf '%s|%s\n' "$package" "$version" >>"$BRAVE_PACKAGE_DB"
	printf '%s|%s\n' "$command" "$path" >>"$BRAVE_PROVIDER_DB"
	printf '%s|%s\n' "$path" "$package" >>"$BRAVE_OWNER_DB"
	make_fake "$command" 'printf "BROWSER EXECUTED: %s\n" "$0 $*" >>"$DOTFILES_TEST_CALL_LOG"
	exit 99'
}

add_brave_color_policy() {
	local content=${1-'{"BrowserThemeColor":"#123456","BrowserColorScheme":1}'} uid
	uid=$(id -u)
	printf '%s\n' "$content" >"$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json"
	chmod 0644 "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json"
	set_brave_metadata /etc/brave/policies/managed/color.json "$uid" "$(id -g)" 0644
}

add_brave_foreign_policy() {
	local name=$1 content=$2 uid=${3-0} gid=${4-0} mode=${5-0644}
	printf '%s\n' "$content" >"$FIXTURE_BRAVE_SYSTEM/policies/managed/$name"
	chmod "$mode" "$FIXTURE_BRAVE_SYSTEM/policies/managed/$name"
	set_brave_metadata "/etc/brave/policies/managed/$name" "$uid" "$gid" "$mode"
}

seed_brave_canaries() {
	mkdir -p "$BRAVE_CANARY_ROOT/profile/Default" "$BRAVE_CANARY_ROOT/themes" "$BRAVE_CANARY_ROOT/fonts" "$BRAVE_CANARY_ROOT/packages" \
		"$FIXTURE_HOME/.config" "$FIXTURE_OMARCHY"
	printf 'profile preferences\n' >"$BRAVE_CANARY_ROOT/profile/Default/Preferences"
	printf 'secure preferences\n' >"$BRAVE_CANARY_ROOT/profile/Default/Secure Preferences"
	printf 'local state\n' >"$BRAVE_CANARY_ROOT/profile/Local State"
	printf 'theme state\n' >"$BRAVE_CANARY_ROOT/themes/current"
	printf 'font state\n' >"$BRAVE_CANARY_ROOT/fonts/current"
	printf 'package state\n' >"$BRAVE_CANARY_ROOT/packages/current"
	printf 'brave flags\n' >"$FIXTURE_HOME/.config/brave-flags.conf"
	printf 'origin flags\n' >"$FIXTURE_HOME/.config/brave-origin-flags.conf"
	printf 'packaged Omarchy\n' >"$FIXTURE_OMARCHY/brave-sentinel"
}

snapshot_brave_canaries() {
	(
		cd -- "$FIXTURE_ROOT" || return 1
		find brave-canaries user/home/.config packaged-omarchy -type f -printf '%P|%m|%s|%T@\n' | sort
		find brave-canaries user/home/.config packaged-omarchy -type f -print0 | sort -z | xargs -0 sha256sum
	)
}

seed_active_brave_policy() {
	local source=${1-"$FIXTURE_REPO/brave/managed-policy.json"}
	local digest transaction timestamp state_root receipt
	digest=$(sha256sum "$source" | { read -r value _; printf '%s\n' "$value"; })
	transaction=20260823T120000Z-1000-deadbeef
	timestamp=2026-08-23T12:00:00Z
	state_root="$FIXTURE_STATE/dotfiles/brave-policy"
	mkdir -p "$state_root"
	chmod 0700 "$state_root"
	cp "$source" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	chmod 0644 "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	set_brave_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0644
	receipt=$(jq -cn --arg digest "$digest" --arg transaction "$transaction" --arg timestamp "$timestamp" \
		'{schema_version:1,kind:"active",target:"/etc/brave/policies/managed/dotfiles.json",source:"brave/managed-policy.json",deployed_digest:$digest,transaction_id:$transaction,activated_at:$timestamp,managed_directory_original:{present:true,uid:0,gid:0,mode:"0777"}}')
	printf '%s\n' "$receipt" >"$state_root/active.json"
	chmod 0600 "$state_root/active.json"
}

use_empty_package_catalog() {
	cat >"$FIXTURE_REPO/packages.json" <<'EOF'
{
	"packages": []
}
EOF
}

restricted_path_without_stow() {
	local restricted_bin=$FIXTURE_ROOT/restricted-bin command command_path
	mkdir -p "$restricted_bin"
	for command in bash basename cmp cp date diff dirname env find flock grep head jq ln mkdir mktemp mv pacman realpath readlink rm sha256sum sort stat tr ttfx; do
		command_path=$(command -v "$command") || return 1
		ln -s "$command_path" "$restricted_bin/$command"
	done
	printf '%s:%s\n' "$FIXTURE_BIN" "$restricted_bin"
}

readonly -a TELEGRAM_THEME_COLOR_KEYS=(
	accent selection muted
	background dark_background darker_background lighter_background
	foreground dark_foreground light_foreground bright_foreground
	red yellow green cyan blue magenta
	bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta
)

make_telegram_theme_manifest() {
	local source=$1 slug=$2 destination=$3 line mode='' key value json
	declare -A colors=()
	while IFS= read -r line; do
		if [[ $line =~ ^mode[[:space:]]*=[[:space:]]*\"(dark|light)\" ]]; then
			mode=${BASH_REMATCH[1]}
		elif [[ $line =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*\"(#[0-9A-Fa-f]{6})\" ]]; then
			colors[${BASH_REMATCH[1]}]=${BASH_REMATCH[2],,}
		fi
	done <"$source"
	[[ -n $mode ]] || {
		printf '  Telegram source palette has no supported mode: %s\n' "$source" >&2
		return 1
	}
	json=$(jq -cn --arg slug "$slug" --arg mode "$mode" \
		'{schema_version:1,slug:$slug,mode:$mode,colors:{}}') || return 1
	for key in "${TELEGRAM_THEME_COLOR_KEYS[@]}"; do
		value=${colors[$key]-}
		[[ $value =~ ^#[0-9a-f]{6}$ ]] || {
			printf '  Telegram source palette is missing direct color %s: %s\n' "$key" "$source" >&2
			return 1
		}
		json=$(jq -c --arg key "$key" --arg value "$value" '.colors[$key] = $value' <<<"$json") || return 1
	done
	printf '%s\n' "$json" >"$destination"
}

telegram_theme_test_path_without() {
	local omitted=$1 restricted_bin=$FIXTURE_ROOT/telegram-restricted-bin command source
	mkdir -p "$restricted_bin"
	for command in bash basename chmod dirname env find flock jq mkdir mktemp mv pacman readlink rm sha256sum stat gum omarchy node zip; do
		[[ $command != "$omitted" ]] || continue
		if [[ -x $FIXTURE_BIN/$command ]]; then
			source=$FIXTURE_BIN/$command
		else
			source=$(command -v "$command") || return 1
		fi
		ln -s "$source" "$restricted_bin/$command"
	done
	printf '%s\n' "$restricted_bin"
}

add_package() {
	local name=${1-demo}
	mkdir -p "$FIXTURE_REPO/config/$name/.config/$name"
	printf 'setting=true\n' >"$FIXTURE_REPO/config/$name/.config/$name/config"
	printf 'package documentation\n' >"$FIXTURE_REPO/$name.md"
	cat >"$FIXTURE_REPO/packages.json" <<EOF
{
	"packages": [{
		"name": "$name",
		"path": "config/$name",
		"description": "Test package",
		"dependencies": [],
		"arch_packages": [],
		"prerequisites": ["test-validator", "test-validator-two"],
		"validators": ["test-validator --check", "test-validator-two --check"],
		"documentation": "$name.md",
		"cleanup": ["Generated state remains in ~/.local/state/$name"]
	}]
}
EOF
	make_fake test-validator 'printf "validator %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake test-validator-two 'printf "validator-two %s|PWD=%s\n" "$*" "$PWD" >>"$DOTFILES_TEST_CALL_LOG"'
}

add_dependent_package() {
	local name=$1
	local dependency=$2
	mkdir -p "$FIXTURE_REPO/config/$name/.config/$name"
	printf 'setting=true\n' >"$FIXTURE_REPO/config/$name/.config/$name/config"
	jq --arg name "$name" --arg dependency "$dependency" '.packages += [{
		"name": $name,
		"path": ("config/" + $name),
		"description": "Dependent test package",
		"dependencies": [$dependency],
		"arch_packages": [],
		"prerequisites": [],
		"validators": [],
		"documentation": null,
		"cleanup": []
	}]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
}

set_package_arch_packages() {
	local package=$1
	shift
	local arch_packages
	arch_packages=$(jq -cn --args '$ARGS.positional' "$@")
	jq --arg package "$package" --argjson arch_packages "$arch_packages" \
		'(.packages[] | select(.name == $package).arch_packages) = $arch_packages' \
		"$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
}

set_installed_arch_packages() {
	: >"$ARCH_PACKAGE_STATE"
	if (($# > 0)); then
		printf '%s\n' "$@" >"$ARCH_PACKAGE_STATE"
	fi
}

make_applying_stow() {
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " != *" --simulate "* ]]; then
	package=${!#}
	mkdir -p "$HOME/.config"
	ln -s "$DOTFILES_TEST_REPO/config/$package/.config/$package" "$HOME/.config/$package"
fi'
}

make_fake() {
	local name=$1
	local body=$2
	local directory=${3:-$FIXTURE_BIN}

	{
		printf '#!/usr/bin/env bash\n'
		printf 'set -u\n'
		printf '%s\n' "$body"
	} >"$directory/$name"
	chmod +x "$directory/$name"
}

make_gum_responder() {
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == choose ]]; then
	shift
	delimiter=
	options=()
	while (( $# > 0 )); do
		case $1 in
			--header) shift 2 ;;
			--label-delimiter=*) delimiter=${1#*=}; shift ;;
			--*) shift ;;
			*) options+=("$1"); shift ;;
		esac
	done
	response=$(sed -n "1p" "$DOTFILES_TEST_GUM_RESPONSES")
	sed "1d" "$DOTFILES_TEST_GUM_RESPONSES" >"$DOTFILES_TEST_GUM_RESPONSES.next"
	mv "$DOTFILES_TEST_GUM_RESPONSES.next" "$DOTFILES_TEST_GUM_RESPONSES"
	[[ -n $response ]] || exit 0
	for option in "${options[@]}"; do
		value=$option
		if [[ -n $delimiter && $option == *"$delimiter"* ]]; then value=${option##*"$delimiter"}; fi
		if [[ $response == "$value" ]]; then printf "%s\n" "$value"; exit 0; fi
	done
	exit 65
fi
if [[ ${1-} == confirm ]]; then exit 0; fi
exit 64'
}

configure_cleanup_fakes() {
	local installed=$FIXTURE_ROOT/installed-packages
	local explicit=$FIXTURE_ROOT/explicit-packages
	local metadata=$FIXTURE_ROOT/package-metadata
	printf '%s\n' base bash chromium jq moonlight-qt optional-app yay omarchy >"$installed"
	printf '%s\n' base bash chromium jq moonlight-qt optional-app yay omarchy >"$explicit"
	printf '%s\n' \
		'Name            : chromium' \
		$'Description     : Chromium\t| web browser' \
		'' \
		'Name            : moonlight-qt' \
		'Description     : GameStream client, desktop' \
		'' \
		'Name            : optional-app' \
		'Description     : Optional desktop application' >"$metadata"
	make_fake yay 'printf "yay %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ $* == -Qqe ]]; then cat "$DOTFILES_TEST_EXPLICIT_PACKAGES"; exit 0; fi
if [[ $* == -Qi ]]; then
	[[ $DOTFILES_TEST_YAY_METADATA_FAILURE == false ]] || exit 72
	[[ ${LC_ALL-} == C ]] || exit 66
	cat "$DOTFILES_TEST_PACKAGE_METADATA"
	exit 0
fi
exit 64'
	make_fake pacman 'printf "pacman %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
case ${1-} in
	-Qqo)
		case ${2##*/} in
			bash) printf "bash\n" ;;
			jq) printf "jq\n" ;;
			find) printf "findutils\n" ;;
			grep) printf "grep\n" ;;
			sort|basename|mktemp|rm) printf "coreutils\n" ;;
			pacman) printf "pacman\n" ;;
			yay) printf "yay\n" ;;
			omarchy) printf "omarchy\n" ;;
			gum) printf "gum\n" ;;
		esac
		;;
	-Qq)
		if (( $# == 1 )) && [[ $DOTFILES_TEST_PACMAN_VERIFY_FAILURE == true ]]; then exit 74
		elif (( $# == 1 )); then cat "$DOTFILES_TEST_INSTALLED_PACKAGES"
		elif grep -Fxq -- "$2" "$DOTFILES_TEST_INSTALLED_PACKAGES"; then printf "%s\n" "$2"
		else exit 1
		fi
		;;
	*) exit 64 ;;
esac'
	make_fake omarchy 'printf "%s|HOME=%s|XDG_CONFIG_HOME=%s|XDG_STATE_HOME=%s|XDG_CACHE_HOME=%s\n" "$*" "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "%s\n" "${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"; exit 0; fi
if [[ ${1-} == pkg && ${2-} == present ]]; then
	shift 2
	for package in "$@"; do grep -Fxq -- "$package" "$DOTFILES_TEST_ARCH_PACKAGE_STATE" || exit 1; done
	if [[ $DOTFILES_TEST_ARCH_VERIFY_FAILURE == true && -e $DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER ]]; then exit 75; fi
	exit 0
fi
if [[ ${1-} == pkg && ${2-} == add ]]; then
	touch "$DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER"
	[[ $DOTFILES_TEST_ARCH_INSTALL_FAILURE == false ]] || exit 76
	for package in "${@:3}"; do grep -Fxq -- "$package" "$DOTFILES_TEST_ARCH_PACKAGE_STATE" || printf "%s\n" "$package" >>"$DOTFILES_TEST_ARCH_PACKAGE_STATE"; done
	exit 0
fi
if [[ ${1-} == webapp && ${2-} == remove ]]; then rm -f "$HOME/.local/share/applications/${*:3}.desktop"; exit 0; fi
if [[ ${1-} == tui && ${2-} == remove ]]; then rm -f "$HOME/.local/share/applications/${*:3}.desktop"; exit 0; fi
if [[ ${1-} == pkg && ${2-} == drop ]]; then
	for package in "${@:3}"; do grep -Fvx -- "$package" "$DOTFILES_TEST_INSTALLED_PACKAGES" >"$DOTFILES_TEST_INSTALLED_PACKAGES.next" || true; mv "$DOTFILES_TEST_INSTALLED_PACKAGES.next" "$DOTFILES_TEST_INSTALLED_PACKAGES"; done
	exit 0
fi
exit 64'
}

add_cleanup_launcher() {
	local name=$1
	local exec_line=$2
	mkdir -p "$FIXTURE_HOME/.local/share/applications"
	printf '[Desktop Entry]\nName=%s\nExec=%s\n' "$name" "$exec_line" >"$FIXTURE_HOME/.local/share/applications/$name.desktop"
}

run_in_sandbox() {
	local working_directory=$1
	local command_path=$2
	local outside_before
	shift 2
	outside_before=$(snapshot_outside_canaries)

	set +e
	if [[ -n $WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID ]]; then
		wallpaper_test_fast_shared_sandbox_run "$working_directory" "$command_path" "$@"
	else
		COMMAND_OUTPUT=$(
			cd -- "$working_directory" &&
				printf '%b' "${DOTFILES_TEST_INPUT-}" |
				env -i \
				HOME="$FIXTURE_HOME" \
				XDG_DATA_HOME="${DOTFILES_TEST_XDG_DATA_HOME-}" \
				XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
				XDG_STATE_HOME="${DOTFILES_TEST_XDG_STATE_HOME:-$FIXTURE_STATE}" \
				XDG_CACHE_HOME="$FIXTURE_CACHE" \
				XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" \
				TMPDIR="$FIXTURE_TMP" \
				OMARCHY_PATH="$FIXTURE_OMARCHY" \
				DOTFILES_WALLPAPER_PACKAGED_THEMES_ROOT="$FIXTURE_WALLPAPER_THEMES" \
				PATH="$command_path" \
				DOTFILES_TEST_CALL_LOG="$CALL_LOG" \
				DOTFILES_TEST_REPO="$FIXTURE_REPO" \
				DOTFILES_TEST_FAKE_BIN="$FIXTURE_BIN" \
				DOTFILES_TEST_HOME="$FIXTURE_HOME" \
				DOTFILES_TEST_OMARCHY_VERSION="${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}" \
				DOTFILES_TEST_SKILL_COUNT_DRIFT="${DOTFILES_TEST_SKILL_COUNT_DRIFT:-false}" \
				DOTFILES_TEST_SKILL_INSTALL_FAILURE="${DOTFILES_TEST_SKILL_INSTALL_FAILURE:-false}" \
				DOTFILES_TEST_SKILL_VERIFY_FAILURE="${DOTFILES_TEST_SKILL_VERIFY_FAILURE:-false}" \
				DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE="${DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE:-false}" \
				DOTFILES_TEST_SKILL_UPDATE_COLLISION="${DOTFILES_TEST_SKILL_UPDATE_COLLISION:-false}" \
				DOTFILES_TEST_SKILL_UNRELATED_FAILURE="${DOTFILES_TEST_SKILL_UNRELATED_FAILURE:-none}" \
				DOTFILES_TEST_GUM_RESPONSES="${DOTFILES_TEST_GUM_RESPONSES-}" \
				DOTFILES_TEST_XDG_DATA_HOME="${DOTFILES_TEST_XDG_DATA_HOME-}" \
				DOTFILES_TEST_INSTALLED_PACKAGES="$FIXTURE_ROOT/installed-packages" \
				DOTFILES_TEST_EXPLICIT_PACKAGES="$FIXTURE_ROOT/explicit-packages" \
				DOTFILES_TEST_PACKAGE_METADATA="$FIXTURE_ROOT/package-metadata" \
				DOTFILES_TEST_ARCH_PACKAGE_STATE="$ARCH_PACKAGE_STATE" \
				DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER="$ARCH_PACKAGE_ADD_MARKER" \
				DOTFILES_TEST_ARCH_INSTALL_FAILURE="${DOTFILES_TEST_ARCH_INSTALL_FAILURE:-false}" \
				DOTFILES_TEST_ARCH_VERIFY_FAILURE="${DOTFILES_TEST_ARCH_VERIFY_FAILURE:-false}" \
				DOTFILES_TEST_FIND_COUNT="${DOTFILES_TEST_FIND_COUNT-}" \
				DOTFILES_TEST_PACMAN_VERIFY_FAILURE="${DOTFILES_TEST_PACMAN_VERIFY_FAILURE:-false}" \
				DOTFILES_TEST_YAY_METADATA_FAILURE="${DOTFILES_TEST_YAY_METADATA_FAILURE:-false}" \
				DOTFILES_TEST_REAL_NODE="$FIXTURE_REAL_NODE_DIR/$(basename -- "$HOST_NODE_REAL")" \
				DOTFILES_TEST_BRAVE_SYSTEM="$FIXTURE_BRAVE_SYSTEM" \
				DOTFILES_TEST_BRAVE_METADATA="$BRAVE_METADATA_ROOT" \
				DOTFILES_TEST_BRAVE_PACKAGES="$BRAVE_PACKAGE_DB" \
				DOTFILES_TEST_BRAVE_PROVIDERS="$BRAVE_PROVIDER_DB" \
				DOTFILES_TEST_BRAVE_OWNERS="$BRAVE_OWNER_DB" \
				DOTFILES_TEST_BRAVE_FAILURE_MARKERS="$BRAVE_FAILURE_MARKERS" \
				DOTFILES_TEST_BRAVE_UID="${DOTFILES_TEST_BRAVE_UID:-$(id -u)}" \
				DOTFILES_TEST_BRAVE_FAIL_BEFORE="${DOTFILES_TEST_BRAVE_FAIL_BEFORE-}" \
				DOTFILES_TEST_BRAVE_FAIL_AFTER="${DOTFILES_TEST_BRAVE_FAIL_AFTER-}" \
				DOTFILES_TEST_BRAVE_FAIL_RECEIPT="${DOTFILES_TEST_BRAVE_FAIL_RECEIPT-}" \
				DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE="${DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE-}" \
				DOTFILES_TEST_BRAVE_FAIL_BACKUP="${DOTFILES_TEST_BRAVE_FAIL_BACKUP:-false}" \
				DOTFILES_TEST_BRAVE_BACKUP_RACE="${DOTFILES_TEST_BRAVE_BACKUP_RACE:-false}" \
				DOTFILES_TEST_BRAVE_SENSITIVE="${DOTFILES_TEST_BRAVE_SENSITIVE:-$FIXTURE_ROOT/brave-sensitive}" \
				DOTFILES_TEST_BRAVE_FAIL_PREVIEW="${DOTFILES_TEST_BRAVE_FAIL_PREVIEW:-false}" \
				DOTFILES_TEST_BRAVE_CORRUPT_STAGE="${DOTFILES_TEST_BRAVE_CORRUPT_STAGE:-false}" \
				DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA="${DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA-}" \
				DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION="${DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION-}" \
				DOTFILES_TEST_BRAVE_STAGE_LINK_KIND="${DOTFILES_TEST_BRAVE_STAGE_LINK_KIND-}" \
				DOTFILES_TEST_BRAVE_STAGE_REFERENT="${DOTFILES_TEST_BRAVE_STAGE_REFERENT:-$FIXTURE_ROOT/brave-stage-referent}" \
				DOTFILES_TEST_BRAVE_RECEIPT_RACE="${DOTFILES_TEST_BRAVE_RECEIPT_RACE-}" \
				DOTFILES_TEST_BRAVE_RECEIPT_REFERENT="${DOTFILES_TEST_BRAVE_RECEIPT_REFERENT:-$FIXTURE_ROOT/brave-receipt-referent}" \
				DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT="${DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT-}" \
				DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER="${DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER-}" \
				DOTFILES_TEST_BRAVE_RENAME_FAILURE="${DOTFILES_TEST_BRAVE_RENAME_FAILURE-}" \
				DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE="${DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE-}" \
				DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER="${DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER-}" \
				DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER="${DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER:-false}" \
				DOTFILES_TEST_BRAVE_FALSE_SUCCESS="${DOTFILES_TEST_BRAVE_FALSE_SUCCESS-}" \
				DOTFILES_TEST_BRAVE_RACE="${DOTFILES_TEST_BRAVE_RACE-}" \
				DOTFILES_TEST_POWER_POLICY_FAIL_OPERATION="${DOTFILES_TEST_POWER_POLICY_FAIL_OPERATION-}" \
				DOTFILES_TEST_POWER_POLICY_INTERRUPT="${DOTFILES_TEST_POWER_POLICY_INTERRUPT-}" \
			DOTFILES_TEST_POWER_POLICY_MUTATE_AFTER_ACQUIRE="${DOTFILES_TEST_POWER_POLICY_MUTATE_AFTER_ACQUIRE-}" \
				DOTFILES_TEST_POWER_POLICY_MENU_CHOICE="${DOTFILES_TEST_POWER_POLICY_MENU_CHOICE-}" \
				DOTFILES_TEST_WALLPAPER_FAIL="${DOTFILES_TEST_WALLPAPER_FAIL-}" \
				DOTFILES_TEST_WALLPAPER_FAIL_ROLLBACK="${DOTFILES_TEST_WALLPAPER_FAIL_ROLLBACK:-false}" \
				DOTFILES_TEST_WALLPAPER_VERSION_CHANGES="${DOTFILES_TEST_WALLPAPER_VERSION_CHANGES:-false}" \
				DOTFILES_TEST_WALLPAPER_RACE="${DOTFILES_TEST_WALLPAPER_RACE-}" \
				DOTFILES_TEST_WALLPAPER_RACE_PATH="${DOTFILES_TEST_WALLPAPER_RACE_PATH-}" \
				DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS="${DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS-}" \
				DOTFILES_TEST_WALLPAPER_IMAGE_RACE_PATH="${DOTFILES_TEST_WALLPAPER_IMAGE_RACE_PATH-}" \
				DOTFILES_TEST_WALLPAPER_IMAGE_RACE_REPLACEMENT="${DOTFILES_TEST_WALLPAPER_IMAGE_RACE_REPLACEMENT-}" \
				DOTFILES_TEST_REAL_MAGICK="$HOST_MAGICK_REAL" \
				DOTFILES_TEST_WALLPAPER_SIGNAL="${DOTFILES_TEST_WALLPAPER_SIGNAL-}" \
				DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE="${DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE-}" \
				DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH="${DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH-}" \
				DOTFILES_TEST_WALLPAPER_POST_PENDING_REPLACEMENT="${DOTFILES_TEST_WALLPAPER_POST_PENDING_REPLACEMENT-}" \
				DOTFILES_TEST_WALLPAPER_PREPARATION_FAIL="${DOTFILES_TEST_WALLPAPER_PREPARATION_FAIL-}" \
				DOTFILES_TEST_WALLPAPER_DELETE_RACE_PATH="${DOTFILES_TEST_WALLPAPER_DELETE_RACE_PATH-}" \
				DOTFILES_TEST_WALLPAPER_DELETE_RACE_REPLACEMENT="${DOTFILES_TEST_WALLPAPER_DELETE_RACE_REPLACEMENT-}" \
				DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE="${DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE-}" \
				DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE_REPLACEMENT="${DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE_REPLACEMENT-}" \
				DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE="${DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE-}" \
				DOTFILES_TEST_FAST_WALLPAPER_FILES="${DOTFILES_TEST_FAST_WALLPAPER_FILES:-false}" \
				DOTFILES_UI="${DOTFILES_UI:-bash}" \
				"$BWRAP" \
					--ro-bind / / \
					--dev-bind /dev /dev \
					--bind "$FIXTURE_ROOT" "$FIXTURE_ROOT" \
				--tmpfs /home \
				--tmpfs /usr/share/omarchy \
				"${BWRAP_EXTRA_ARGS[@]}" \
					-- "$@" 2>&1
		)
		COMMAND_STATUS=$?
	fi
	set -e
	if [[ $(snapshot_outside_canaries) != "$outside_before" ]]; then
		OUTSIDE_CANARY_CHANGED=true
	fi
}

run_dotfiles() {
	local working_directory=$1
	shift
	run_in_sandbox "$working_directory" "${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" \
		"$FIXTURE_REPO/bin/dotfiles" "$@"
}

run_operation() {
	local working_directory=$1 operation=$2
	shift 2
	run_in_sandbox "$working_directory" "${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" \
		bash -c '
			set -euo pipefail
			repository=$1
			operation=$2
			shift 2
			source "$repository/lib/dotfiles/core.sh"
			if [[ -f $repository/lib/dotfiles/screensaver-effects.sh ]]; then
				source "$repository/lib/dotfiles/screensaver-effects.sh"
			fi
			source "$repository/lib/dotfiles/packages.sh"
			source "$repository/lib/dotfiles/skills.sh"
			source "$repository/lib/dotfiles/cleanup.sh"
			source "$repository/lib/dotfiles/modem.sh"
			source "$repository/lib/dotfiles/brave.sh"
			if [[ -f $repository/lib/dotfiles/power-policy.sh ]]; then
				source "$repository/lib/dotfiles/power-policy.sh"
			fi
			if [[ -f $repository/lib/dotfiles/telegram-theme.sh ]]; then
				source "$repository/lib/dotfiles/telegram-theme.sh"
			fi
			if [[ -f $repository/lib/dotfiles/wallpapers.sh ]]; then
				source "$repository/lib/dotfiles/wallpapers.sh"
			fi
			source "$repository/lib/dotfiles/wizard.sh"
			"$operation" "$@"
		' bash "$FIXTURE_REPO" "$operation" "$@"
}

run_brave_operation() {
	local working_directory=$1 operation=$2
	shift 2
	run_in_sandbox "$working_directory" "${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" \
		bash -c '
			set -euo pipefail
			repository=$1
			operation=$2
			shift 2
			source "$repository/lib/dotfiles/core.sh"
			source "$repository/lib/dotfiles/brave.sh"

			brave_map_system_path() {
				case $1 in
					/etc/brave) printf "%s\n" "$DOTFILES_TEST_BRAVE_SYSTEM" ;;
					/etc/brave/*) printf "%s/%s\n" "$DOTFILES_TEST_BRAVE_SYSTEM" "${1#/etc/brave/}" ;;
					*) return 2 ;;
				esac
			}
			brave_test_metadata_key() {
				printf "%s" "$1" | sha256sum | { read -r digest _; printf "%s\n" "$digest"; }
			}
			brave_test_set_metadata() {
				local key
				key=$(brave_test_metadata_key "$1")
				printf "%s %s %s\n" "$2" "$3" "$4" >"$DOTFILES_TEST_BRAVE_METADATA/$key"
			}
			brave_test_remove_metadata() {
				local key
				key=$(brave_test_metadata_key "$1")
				rm -f -- "$DOTFILES_TEST_BRAVE_METADATA/$key"
			}
			brave_lstat() {
				local logical=$1 actual type mode uid=0 gid=0 key
				actual=$(brave_map_system_path "$logical") || return 2
				[[ -e $actual || -L $actual ]] || return 1
				type=$(stat -c %F -- "$actual") || return 2
				mode=$(stat -c %a -- "$actual") || return 2
				key=$(brave_test_metadata_key "$logical")
				if [[ -f $DOTFILES_TEST_BRAVE_METADATA/$key ]]; then
					read -r uid gid mode <"$DOTFILES_TEST_BRAVE_METADATA/$key"
				fi
				printf "%s|%s|%s|%s\n" "$type" "$uid" "$gid" "$mode"
			}
			brave_package_version() {
				local wanted=$1 package version
				while IFS="|" read -r package version; do
					[[ $package == "$wanted" ]] || continue
					printf "%s\n" "$version"
					return 0
				done <"$DOTFILES_TEST_BRAVE_PACKAGES"
				return 1
			}
			brave_resolve_provider() {
				local wanted=$1 command provider
				while IFS="|" read -r command provider; do
					[[ $command == "$wanted" ]] || continue
					printf "%s\n" "$provider"
					return 0
				done <"$DOTFILES_TEST_BRAVE_PROVIDERS"
				return 1
			}
			brave_provider_package() {
				local wanted=$1 provider package
				while IFS="|" read -r provider package; do
					[[ $provider == "$wanted" ]] || continue
					printf "%s\n" "$package"
					return 0
				done <"$DOTFILES_TEST_BRAVE_OWNERS"
				return 1
			}
			brave_effective_uid() { printf "%s\n" "$DOTFILES_TEST_BRAVE_UID"; }
			brave_omarchy_version() {
				[[ $DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER != true ]] || printf "recovery-order inspect-omarchy\n" >>"$DOTFILES_TEST_CALL_LOG"
				printf "%s\n" "$DOTFILES_TEST_OMARCHY_VERSION"
			}
			brave_confirm() {
				[[ $DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER != true ]] || printf "recovery-order confirmation %s\n" "$1" >>"$DOTFILES_TEST_CALL_LOG"
				wizard_confirm "$1"
			}
			brave_test_operation_with_context() {
				local requested=$1 outcome=0
				shift
				"$requested" "$@" || outcome=$?
				printf "Brave operation context: %s\n" "$BRAVE_OPERATION_CONTEXT"
				return "$outcome"
			}
			brave_create_state_root() {
				local root=$1 marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/state-root-race"
				if [[ -n $DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT && ! -e $marker ]]; then
					touch "$marker"
					ln -s "$DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT" "$root"
					return 1
				fi
				brave_create_state_root_impl "$root"
			}
			brave_atomic_write_receipt() {
				local kind=$1 marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/receipt-$1"
				if [[ $DOTFILES_TEST_BRAVE_FAIL_RECEIPT == "$kind" && ! -e $marker ]]; then
					touch "$marker"
					return 79
				fi
				brave_atomic_write_receipt_impl "$@"
			}
			brave_publish_receipt_temporary() {
				local temporary=$1 destination=$2 marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/receipt-destination-race"
				if [[ -n $DOTFILES_TEST_BRAVE_RECEIPT_RACE && ! -e $marker ]]; then
					touch "$marker"
					case $DOTFILES_TEST_BRAVE_RECEIPT_RACE in
						directory) mkdir "$destination" ;;
						symlink-directory) ln -s "$DOTFILES_TEST_BRAVE_RECEIPT_REFERENT" "$destination" ;;
						*) return 64 ;;
					esac
				fi
				brave_publish_receipt_temporary_impl "$temporary" "$destination"
			}
			brave_test_attempt_unprivileged_target_replacement() {
				local point=$1 metadata mode_value invoking_uid group allowed=false actual
				metadata=$(brave_lstat /etc/brave/policies/managed) || return 1
				brave_parse_metadata "$metadata" BRAVE_TEST_REPLACEMENT_PARENT || return 1
				mode_value=$(brave_mode_value "$BRAVE_TEST_REPLACEMENT_PARENT_MODE") || return 1
				invoking_uid=$(brave_effective_uid) || return 1
				if [[ $BRAVE_TEST_REPLACEMENT_PARENT_UID == "$invoking_uid" && $((mode_value & 0200)) -ne 0 ]]; then
					allowed=true
				elif (( (mode_value & 0020) != 0 )); then
					for group in $(brave_effective_groups); do
						[[ $group != "$BRAVE_TEST_REPLACEMENT_PARENT_GID" ]] || allowed=true
					done
				fi
				if (( (mode_value & 0002) != 0 )); then allowed=true; fi
				if [[ $allowed != true ]]; then
					printf "unprivileged-target-replacement blocked %s metadata=%s\n" "$point" "$metadata" >>"$DOTFILES_TEST_CALL_LOG"
					return 1
				fi
				actual=$(brave_map_system_path /etc/brave/policies/managed/dotfiles.json) || return 1
				printf "replacement created during owned finalization\n" >"$actual"
				chmod 0644 "$actual"
				brave_test_set_metadata /etc/brave/policies/managed/dotfiles.json "$invoking_uid" "$(id -g)" 0644
				printf "unprivileged-target-replacement created %s metadata=%s\n" "$point" "$metadata" >>"$DOTFILES_TEST_CALL_LOG"
			}
			brave_remove_state_file() {
				local name=${1##*/} marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/remove-${1##*/}"
				[[ $DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER != true ]] || printf "recovery-order remove-state %s\n" "$name" >>"$DOTFILES_TEST_CALL_LOG"
				if [[ $DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE == "$name" && ! -e $DOTFILES_TEST_BRAVE_FAILURE_MARKERS/state-remove-target-replacement ]]; then
					touch "$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/state-remove-target-replacement"
					brave_test_attempt_unprivileged_target_replacement "state-remove-$name" || true
				fi
				if [[ $DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE == "$name" && ! -e $marker ]]; then
					touch "$marker"
					return 80
				fi
				brave_remove_state_file_impl "$@"
			}
			brave_copy_backup() {
				local marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/backup"
				if [[ $DOTFILES_TEST_BRAVE_FAIL_BACKUP == true && ! -e $marker ]]; then
					touch "$marker"
					return 81
				fi
				if [[ $DOTFILES_TEST_BRAVE_BACKUP_RACE == true && $1 == "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/dotfiles.json" && ! -e $DOTFILES_TEST_BRAVE_FAILURE_MARKERS/backup-race ]]; then
					touch "$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/backup-race"
					rm -f -- "$1"
					ln -s "$DOTFILES_TEST_BRAVE_SENSITIVE" "$1"
				fi
				brave_copy_backup_impl "$@"
			}
			brave_copy_preview_snapshot() {
				[[ $DOTFILES_TEST_BRAVE_FAIL_PREVIEW != true ]] || return 82
				brave_copy_backup_impl "$@"
			}
			brave_test_race_once() {
				[[ -n $DOTFILES_TEST_BRAVE_RACE ]] || return 0
				local marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/race-$DOTFILES_TEST_BRAVE_RACE"
				[[ ! -e $marker ]] || return 0
				touch "$marker"
				case $DOTFILES_TEST_BRAVE_RACE in
					source) printf " \n" >>"$repository/brave/managed-policy.json" ;;
					consumers) printf "brave-bin|9:9.9.9-1\n" >"$DOTFILES_TEST_BRAVE_PACKAGES" ;;
					providers) printf "brave|$DOTFILES_TEST_FAKE_BIN/brave\n" >"$DOTFILES_TEST_BRAVE_PROVIDERS"; printf "%s|other-browser\n" "$DOTFILES_TEST_FAKE_BIN/brave" >"$DOTFILES_TEST_BRAVE_OWNERS" ;;
					receipts) [[ ! -f $XDG_STATE_HOME/dotfiles/brave-policy/active.json ]] || printf " \n" >>"$XDG_STATE_HOME/dotfiles/brave-policy/active.json" ;;
					pending) printf " \n" >>"$XDG_STATE_HOME/dotfiles/brave-policy/pending.json" ;;
					backup)
						local recovery_backup
						recovery_backup=$(jq -r ".prior_target.backup_path // .prior_active.backup_path" "$XDG_STATE_HOME/dotfiles/brave-policy/pending.json")
						printf " \n" >>"$recovery_backup"
						;;
					target) [[ ! -f $DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/dotfiles.json ]] || printf " \n" >>"$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/dotfiles.json" ;;
					paths) rm -rf "$DOTFILES_TEST_BRAVE_SYSTEM/policies"; ln -s "$DOTFILES_TEST_BRAVE_SYSTEM" "$DOTFILES_TEST_BRAVE_SYSTEM/policies" ;;
					metadata) brave_test_set_metadata /etc/brave/policies 0 0 0777 ;;
					foreign) printf "{\"RacePolicy\":true}\n" >"$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/race.json"; chmod 0644 "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/race.json"; brave_test_set_metadata /etc/brave/policies/managed/race.json 0 0 0644 ;;
				esac
			}
			brave_test_fail() {
				local phase=$1 operation=$2 configured marker
				[[ $phase == before ]] && configured=$DOTFILES_TEST_BRAVE_FAIL_BEFORE || configured=$DOTFILES_TEST_BRAVE_FAIL_AFTER
				[[ ,$configured, == *,$operation,* ]] || return 1
				marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/$phase-$operation"
				[[ ! -e $marker ]] || return 1
				touch "$marker"
				return 0
			}
			brave_test_seed_stage_link() {
				local operation=$1 stage=$2 marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/stage-link-$1"
				[[ $DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION == "$operation" && ! -e $marker ]] || return 0
				touch "$marker"
				case $DOTFILES_TEST_BRAVE_STAGE_LINK_KIND in
					file|directory) ln -s "$DOTFILES_TEST_BRAVE_STAGE_REFERENT" "$stage" ;;
					*) return 64 ;;
					esac
			}
			brave_privileged_operation() {
				local operation=$1
				shift
				local transaction logical actual stage backup uid gid mode digest expected_identity temporary_mode
				printf "privileged %s" "$operation" >>"$DOTFILES_TEST_CALL_LOG"
				printf " %q" "$@" >>"$DOTFILES_TEST_CALL_LOG"
				printf "\n" >>"$DOTFILES_TEST_CALL_LOG"
				if brave_test_fail before "$operation"; then return 77; fi
				if [[ ,$DOTFILES_TEST_BRAVE_FALSE_SUCCESS, == *,$operation,* ]]; then
					printf "false-success %s\n" "$operation" >>"$DOTFILES_TEST_CALL_LOG"
					return 0
				fi
				case $operation in
					acquire)
						printf "/usr/bin/sudo -v\n" >>"$DOTFILES_TEST_CALL_LOG"
						brave_test_race_once
						;;
					create-managed)
						mkdir -p "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						chmod 0755 "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						brave_test_set_metadata /etc/brave/policies/managed 0 0 0755
						printf "/usr/bin/sudo /usr/bin/install -d -o root -g root -m 0755 -- /etc/brave/policies/managed\n" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					harden-managed)
						chmod 0755 "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						brave_test_set_metadata /etc/brave/policies/managed 0 0 0755
						printf "/usr/bin/sudo /usr/bin/chown 0:0 -- /etc/brave/policies/managed\n/usr/bin/sudo /usr/bin/chmod 0755 -- /etc/brave/policies/managed\n" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					write-stage)
						transaction=$1 logical="/etc/brave/policies/.dotfiles-$transaction.stage" actual=$(brave_map_system_path "$logical")
						brave_test_seed_stage_link write-stage "$actual" || return 1
						rm -f -- "$actual"
						cp "$repository/brave/managed-policy.json" "$actual"
						chmod 0644 "$actual"
						brave_test_set_metadata "$logical" 0 0 0644
						brave_validate_stage "$transaction" || return 1
						printf "brave_json emit-no-follow | /usr/bin/sudo /usr/bin/install -T -o root -g root -m 0644 -- /dev/stdin %s\n" "$logical" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					publish-stage)
						transaction=$1 expected_identity=$2 logical="/etc/brave/policies/.dotfiles-$transaction.stage" stage=$(brave_map_system_path "$logical") actual=$(brave_map_system_path /etc/brave/policies/managed/dotfiles.json)
						[[ $(brave_validate_stage_file_metadata "$transaction" 0 0 0644) == "$expected_identity" ]] || return 1
						printf "/usr/bin/sudo /usr/bin/mv --no-copy -fT -- %s /etc/brave/policies/managed/dotfiles.json\n" "$logical" >>"$DOTFILES_TEST_CALL_LOG"
						if [[ $DOTFILES_TEST_BRAVE_RENAME_FAILURE == publish-stage ]]; then
							printf "simulated cross-filesystem rename failure: publish-stage\n" >>"$DOTFILES_TEST_CALL_LOG"
							return 1
						fi
						/usr/bin/mv --no-copy -fT -- "$stage" "$actual"
						brave_test_remove_metadata "$logical"
						brave_test_set_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0644
						;;
					remove-target)
						rm -f "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/dotfiles.json"
						brave_test_remove_metadata /etc/brave/policies/managed/dotfiles.json
						printf "/usr/bin/sudo /usr/bin/rm -f -- /etc/brave/policies/managed/dotfiles.json\n" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					remove-stage)
						transaction=$1 logical="/etc/brave/policies/.dotfiles-$transaction.stage" actual=$(brave_map_system_path "$logical")
						rm -f "$actual"
						brave_test_remove_metadata "$logical"
						printf "/usr/bin/sudo /usr/bin/rm -f -- %s\n" "$logical" >>"$DOTFILES_TEST_CALL_LOG"
						;;
				restore-target)
					transaction=$1 backup=$2 uid=$3 gid=$4 mode=$5 digest=$6
					temporary_mode=$(brave_mode_without_write_bits "$mode") || return 1
					logical="/etc/brave/policies/.dotfiles-$transaction.stage" stage=$(brave_map_system_path "$logical")
					brave_test_seed_stage_link restore-target "$stage" || return 1
					rm -f -- "$stage"
					cp "$backup" "$stage"
					chmod "$temporary_mode" "$stage"
					brave_test_set_metadata "$logical" "$uid" "$gid" "$temporary_mode"
					brave_validate_restore_stage "$transaction" "$backup" "$uid" "$gid" "$temporary_mode" "$digest" || return 1
					expected_identity=$BRAVE_VALIDATED_STAGE_IDENTITY
					[[ $(brave_validate_stage_file_metadata "$transaction" "$uid" "$gid" "$temporary_mode") == "$expected_identity" ]] || return 1
					actual=$(brave_map_system_path /etc/brave/policies/managed/dotfiles.json)
					printf "brave_json emit-no-follow | /usr/bin/sudo /usr/bin/install -T -o %s -g %s -m %s -- /dev/stdin %s\n/usr/bin/sudo /usr/bin/mv --no-copy -fT -- %s /etc/brave/policies/managed/dotfiles.json\n" "$uid" "$gid" "$temporary_mode" "$logical" "$logical" >>"$DOTFILES_TEST_CALL_LOG"
					if [[ $DOTFILES_TEST_BRAVE_RENAME_FAILURE == restore-target ]]; then
						printf "simulated cross-filesystem rename failure: restore-target\n" >>"$DOTFILES_TEST_CALL_LOG"
						return 1
					fi
					/usr/bin/mv --no-copy -fT -- "$stage" "$actual"
					brave_test_remove_metadata "$logical"
					brave_test_set_metadata /etc/brave/policies/managed/dotfiles.json "$uid" "$gid" "$temporary_mode"
					chmod "$mode" "$actual"
					brave_test_set_metadata /etc/brave/policies/managed/dotfiles.json "$uid" "$gid" "$mode"
					brave_validate_target_against_backup "$backup" "$uid" "$gid" "$mode" "$digest" || return 1
					printf "/usr/bin/sudo /usr/bin/chmod %s -- /etc/brave/policies/managed/dotfiles.json\n" "$mode" >>"$DOTFILES_TEST_CALL_LOG"
					;;
					restore-managed)
						uid=$1 gid=$2 mode=$3
						chmod "$mode" "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						brave_test_set_metadata /etc/brave/policies/managed "$uid" "$gid" "$mode"
						printf "/usr/bin/sudo /usr/bin/chown %s:%s -- /etc/brave/policies/managed\n/usr/bin/sudo /usr/bin/chmod %s -- /etc/brave/policies/managed\n" "$uid" "$gid" "$mode" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					remove-managed)
						rmdir "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						brave_test_remove_metadata /etc/brave/policies/managed
						printf "/usr/bin/sudo /usr/bin/rmdir -- /etc/brave/policies/managed\n" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					*) return 64 ;;
				esac
				if [[ $operation == write-stage && $DOTFILES_TEST_BRAVE_CORRUPT_STAGE == true ]]; then
					printf "corrupt\n" >>"$actual"
				fi
				if [[ $operation == write-stage && -n $DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA ]]; then
					case $DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA in
						owner) brave_test_set_metadata "$logical" 1000 1000 0644 ;;
						group) brave_test_set_metadata "$logical" 0 1000 0644 ;;
						mode) brave_test_set_metadata "$logical" 0 0 0666 ;;
						*) return 64 ;;
					esac
				fi
				if [[ $DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER == "$operation" && ! -e $DOTFILES_TEST_BRAVE_FAILURE_MARKERS/managed-replacement ]]; then
					touch "$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/managed-replacement"
					rmdir "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed" || return 1
					mkdir "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
					chmod 0755 "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
					brave_test_set_metadata /etc/brave/policies/managed 0 0 0755
				fi
				if [[ $DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER == "$operation" && ! -e $DOTFILES_TEST_BRAVE_FAILURE_MARKERS/target-replacement-after-operation ]]; then
					touch "$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/target-replacement-after-operation"
					brave_test_attempt_unprivileged_target_replacement "after-$operation" || true
				fi
				if brave_test_fail after "$operation"; then return 78; fi
			}

			source "$repository/lib/dotfiles/wizard.sh"
			"$operation" "$@"
		' bash "$FIXTURE_REPO" "$operation" "$@"
}

power_policy_metadata_key() {
	local key=$1
	key=${key//%/%25}
	key=${key//\//%2F}
	printf '%s\n' "$key"
}

set_power_policy_metadata() {
	local logical=$1 uid=$2 gid=$3 mode=$4 key
	key=$(power_policy_metadata_key "$logical")
	printf '%s %s %s\n' "$uid" "$gid" "$mode" >"$POWER_POLICY_METADATA_ROOT/$key"
}

setup_power_policy_fixture() {
	mkdir -p "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d" "$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf.d" \
		"$FIXTURE_POWER_POLICY_SYSTEM/../run/systemd/logind.conf.d" "$FIXTURE_POWER_POLICY_SYSTEM/../usr/local/lib/systemd/logind.conf.d" "$FIXTURE_POWER_POLICY_SYSTEM/../usr/lib/systemd/logind.conf.d"
	chmod 0755 "$FIXTURE_POWER_POLICY_SYSTEM" "$FIXTURE_POWER_POLICY_SYSTEM/UPower" "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d" \
		"$FIXTURE_POWER_POLICY_SYSTEM/systemd" "$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf.d"
	set_power_policy_metadata /etc 0 0 0755
	set_power_policy_metadata /etc/UPower 0 0 0755
	set_power_policy_metadata /etc/UPower/UPower.conf.d 0 0 0755
	set_power_policy_metadata /etc/systemd 0 0 0755
	set_power_policy_metadata /etc/systemd/logind.conf.d 0 0 0755
	printf '[Login]\n' >"$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf"
	chmod 0644 "$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf"
	set_power_policy_metadata /etc/systemd/logind.conf 0 0 0644
	printf '[UPower]\nUsePercentageForPolicy=false\nPercentageLow=20.0\nPercentageCritical=10.0\nPercentageAction=5.0\nCriticalPowerAction=Auto\n' \
		>"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf"
	chmod 0644 "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf"
	set_power_policy_metadata /etc/UPower/UPower.conf 0 0 0644
	printf '4.0.1-1\n' >"$POWER_POLICY_RUNTIME/omarchy-version"
	printf 'yes\n' >"$POWER_POLICY_RUNTIME/battery"
	printf 'yes\n' >"$POWER_POLICY_RUNTIME/hibernation"
	printf 'yes\n' >"$POWER_POLICY_RUNTIME/can-hibernate"
	printf 'disabled|inactive\n' >"$POWER_POLICY_RUNTIME/upower-service"
	printf 'suspend||ignore\n' >"$POWER_POLICY_RUNTIME/logind-runtime"
	printf '15000000\n' >"$POWER_POLICY_RUNTIME/inhibit-delay-us"
	printf '15000000\n' >"$POWER_POLICY_RUNTIME/configured-inhibit-delay-us"
	: >"$POWER_POLICY_RUNTIME/restart-delay-us"
	printf 'safe\n' >"$POWER_POLICY_RUNTIME/target-parent-safe"
	printf 'Sleep\n' >"$POWER_POLICY_RUNTIME/upower-critical-action"
	printf 'enabled|active|present\n' >"$POWER_POLICY_RUNTIME/sleep-lock"
	printf 'merged UPower configuration\n' >"$POWER_POLICY_RUNTIME/merged-upower"
	printf 'merged logind configuration\n' >"$POWER_POLICY_RUNTIME/merged-logind"
}

add_power_policy_drop_in() {
	local kind=$1 name=$2 content=$3 directory logical
	case $kind in
		upower) directory="$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d"; logical="/etc/UPower/UPower.conf.d/$name" ;;
		logind) directory="$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf.d"; logical="/etc/systemd/logind.conf.d/$name" ;;
		*) return 2 ;;
	esac
	printf '%s' "$content" >"$directory/$name"
	chmod 0644 "$directory/$name"
	set_power_policy_metadata "$logical" 0 0 0644
}

run_power_policy_operation() {
	local working_directory=$1 operation=$2
	shift 2
	run_in_sandbox "$working_directory" "$FIXTURE_REAL_NODE_DIR:${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" \
		bash -c '
			set -euo pipefail
			repository=$1
			operation=$2
			shift 2
			source "$repository/lib/dotfiles/core.sh"
			source "$repository/lib/dotfiles/power-policy.sh"
			source "$repository/lib/dotfiles/wizard.sh"
			root=${repository%/relocated/dotfiles}
			metadata_root=$root/power-policy-metadata
			runtime=$root/power-policy-runtime
			map_target() {
				case $1 in
					upower|/etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf) printf "%s/system/etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf\n" "$root" ;;
					logind|/etc/systemd/logind.conf.d/90-dotfiles-laptop-power.conf) printf "%s/system/etc/systemd/logind.conf.d/90-dotfiles-laptop-power.conf\n" "$root" ;;
					*) return 2 ;;
				esac
			}
			map_directory() { case $1 in upower) printf "%s/system/etc/UPower/UPower.conf.d\n" "$root" ;; logind) printf "%s/system/etc/systemd/logind.conf.d\n" "$root" ;; *) return 2 ;; esac; }
			state_path_safe() { local path=$1 component='' part; IFS=/ read -r -a parts <<<"${path#/}"; for part in "${parts[@]}"; do [[ -n $part ]] || continue; component+=/$part; [[ -e $component || -L $component ]] || break; [[ -d $component && ! -L $component ]] || return 1; done; }
			meta_key() { local key=$1; key=${key//%/%25}; key=${key//\//%2F}; printf "%s\n" "$key"; }
			logical_target() { case $1 in upower) printf "/etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf\n" ;; logind) printf "/etc/systemd/logind.conf.d/90-dotfiles-laptop-power.conf\n" ;; *) return 2 ;; esac; }
			metadata() {
				local logical=$1 actual=$2 key mode uid=0 gid=0 type
				type=$(power_policy_stat_metadata "$actual") || return 1
				type=${type%%|*}
				mode=$(stat -c %a -- "$actual") || return 1
				key=$(meta_key "$logical")
				[[ ! -f $metadata_root/$key ]] || read -r uid gid mode <"$metadata_root/$key"
				printf "%s|%s|%s|%s\n" "$type" "$uid" "$gid" "$mode"
			}
			set_metadata() { printf "%s %s %s\n" "$2" "$3" "$4" >"$metadata_root/$(meta_key "$1")"; }
			remove_metadata() { rm -f -- "$metadata_root/$(meta_key "$1")"; }
			fail_operation() { [[ ,${DOTFILES_TEST_POWER_POLICY_FAIL_OPERATION-}, == *,$1,* ]]; }
			refresh_runtime() {
				local upower logind action lid external docked
				upower=$(node "$POWER_POLICY_JSON_HELPER" upower-effective "$root/system/etc/UPower/UPower.conf" "$root/system/etc/UPower/UPower.conf.d") || return 1
				action=$(jq -r ".effective.CriticalPowerAction // \"Sleep\"" <<<"$upower")
				case $action in PowerOff|Hibernate) ;; *) action=Sleep ;; esac
				printf "%s\n" "$action" >"$runtime/upower-critical-action"
				logind=$(node "$POWER_POLICY_JSON_HELPER" logind-effective "$root/system/etc/systemd/logind.conf" "$root/system/etc/systemd/logind.conf.d" "$root/system/run/systemd/logind.conf" "$root/system/run/systemd/logind.conf.d" "$root/system/usr/local/lib/systemd/logind.conf" "$root/system/usr/local/lib/systemd/logind.conf.d" "$root/system/usr/lib/systemd/logind.conf" "$root/system/usr/lib/systemd/logind.conf.d") || return 1
				lid=$(jq -r ".effective.HandleLidSwitch // \"suspend\"" <<<"$logind")
				external=$(jq -r ".effective.HandleLidSwitchExternalPower // \"\"" <<<"$logind")
				docked=$(jq -r ".effective.HandleLidSwitchDocked // \"ignore\"" <<<"$logind")
				printf "%s|%s|%s\n" "$lid" "$external" "$docked" >"$runtime/logind-runtime"
				cat "$runtime/configured-inhibit-delay-us" >"$runtime/inhibit-delay-us"
			}
			power_policy_adapter() {
				local group=$1 action=${2-} name=${3-} actual logical stage backup enabled active value
				shift 2
				case "$group:$action" in
					lock:shared|lock:exclusive) printf "lock %s\n" "$action" >>"$DOTFILES_TEST_CALL_LOG" ;;
					lock:release) printf "lock release\n" >>"$DOTFILES_TEST_CALL_LOG" ;;
					inspect:version) cat "$runtime/omarchy-version" ;;
					inspect:battery) [[ $(<"$runtime/battery") == yes ]] ;;
					inspect:hibernation) [[ $(<"$runtime/hibernation") == yes ]] ;;
					inspect:can-hibernate) cat "$runtime/can-hibernate" ;;
					inspect:service) cat "$runtime/upower-service" ;;
					inspect:sleep-lock) cat "$runtime/sleep-lock" ;;
					inspect:critical-action) cat "$runtime/upower-critical-action" ;;
					inspect:logind-runtime) cat "$runtime/logind-runtime" ;;
					inspect:inhibit-delay) cat "$runtime/inhibit-delay-us" ;;
					inspect:target)
						if [[ $name == parent-* ]]; then printf "directory|0|0|0755\n"; return; fi
						actual=$(map_target "$name") || return 2; [[ -e $actual || -L $actual ]] || { printf "absent\n"; return; }; logical=$(logical_target "$name"); value=$(metadata "$logical" "$actual") || return 1; [[ $value == "regular file|"* && ! -L $actual ]] && value+="|$(sha256sum "$actual" | { read -r digest _; printf "%s" "$digest"; })"; printf "%s\n" "$value" ;;
					inspect:target-parent-safe) [[ $(<"$runtime/target-parent-safe") == safe ]] || { cat "$runtime/target-parent-safe"; return; }; [[ ! -L $(map_directory "$name") ]] && printf safe || printf unsafe ;;
					inspect:state-path-safe) state_path_safe "$name" && printf safe ;;
					inspect:stage)
						stage="$root/system$(power_policy_stage_path "$1" "$2")"; [[ -e $stage || -L $stage ]] || return 1; value=$(metadata "$(power_policy_stage_path "$1" "$2")" "$stage") || return 1; [[ $value == "regular file|"* && ! -L $stage ]] && value+="|$(sha256sum "$stage" | { read -r digest _; printf "%s" "$digest"; })"; printf "%s\n" "$value" ;;
					inspect:upower-effective) node "$POWER_POLICY_JSON_HELPER" upower-effective "$root/system/etc/UPower/UPower.conf" "$root/system/etc/UPower/UPower.conf.d" ;;
					inspect:logind-effective) node "$POWER_POLICY_JSON_HELPER" logind-effective "$root/system/etc/systemd/logind.conf" "$root/system/etc/systemd/logind.conf.d" "$root/system/run/systemd/logind.conf" "$root/system/run/systemd/logind.conf.d" "$root/system/usr/local/lib/systemd/logind.conf" "$root/system/usr/local/lib/systemd/logind.conf.d" "$root/system/usr/lib/systemd/logind.conf" "$root/system/usr/lib/systemd/logind.conf.d" ;;
					inspect:upower-plan) node "$POWER_POLICY_JSON_HELPER" upower-plan "$root/system/etc/UPower/UPower.conf" "$root/system/etc/UPower/UPower.conf.d" "$root/system/etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" "$name" ;;
					inspect:logind-plan) node "$POWER_POLICY_JSON_HELPER" logind-plan "$root/system/etc/systemd/logind.conf" "$root/system/etc/systemd/logind.conf.d" "$root/system/run/systemd/logind.conf" "$root/system/run/systemd/logind.conf.d" "$root/system/usr/local/lib/systemd/logind.conf" "$root/system/usr/local/lib/systemd/logind.conf.d" "$root/system/usr/lib/systemd/logind.conf" "$root/system/usr/lib/systemd/logind.conf.d" "$root/system/etc/systemd/logind.conf.d/90-dotfiles-laptop-power.conf" "$name" ;;
					mutate:acquire)
						printf "privileged acquire\n" >>"$DOTFILES_TEST_CALL_LOG"
						case ${DOTFILES_TEST_POWER_POLICY_MUTATE_AFTER_ACQUIRE-} in
							source) printf "[UPower]\nCriticalPowerAction=PowerOff\n" >"$repository/power-policy/upower.conf" ;;
							foreign-upower) printf "[UPower]\nCriticalPowerAction=PowerOff\n" >"$root/system/etc/UPower/UPower.conf.d/99-foreign.conf" ;;
							delay) printf "[Login]\nInhibitDelayMaxSec=22\n" >"$root/system/etc/systemd/logind.conf.d/99-delay.conf" ;;
							backup) backup=$(jq -r ".targets[] | select(.name == \"upower\") | .original.backup_path" "$root/user/state/dotfiles/laptop-power-policy/active.json"); printf "changed\n" >"$backup" ;;
						esac
						if fail_operation acquire; then return 75; fi ;;
					mutate:backup)
						name=$1; backup=$2; printf "privileged backup %s\n" "$name" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation "backup:$name" && return 75; actual=$(map_target "$name"); cp -- "$actual" "$backup" && chmod 0600 "$backup" ;;
					mutate:stage)
						name=$1; stage=$(power_policy_stage_path "$name" "$2"); printf "privileged stage %s\n" "$name" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation "stage:$name" && return 75; cp -- "$repository/power-policy/$name.conf" "$root/system$stage" && chmod 0644 "$root/system$stage"; if [[ ${DOTFILES_TEST_POWER_POLICY_INTERRUPT-} == "stage:$name" ]]; then exit 88; fi ;;
					mutate:publish)
						name=$1; stage=$(power_policy_stage_path "$name" "$2"); printf "privileged publish %s\n" "$name" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation "publish:$name" && return 75; actual=$(map_target "$name"); mv -fT -- "$root/system$stage" "$actual"; set_metadata "$(logical_target "$name")" 0 0 0644; if [[ ${DOTFILES_TEST_POWER_POLICY_INTERRUPT-} == "publish:$name" ]]; then exit 88; fi ;;
					mutate:remove)
						name=$1; printf "privileged remove %s\n" "$name" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation "remove:$name" && return 75; actual=$(map_target "$name"); rm -f -- "$actual"; remove_metadata "$(logical_target "$name")"; if [[ ${DOTFILES_TEST_POWER_POLICY_INTERRUPT-} == "remove:$name" ]]; then exit 88; fi ;;
					mutate:restore)
						name=$1; stage=$(power_policy_stage_path "$name" "$2"); backup=$3; printf "privileged restore %s\n" "$name" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation "restore:$name" && return 75; [[ $(sha256sum "$backup" | { read -r digest _; printf "%s" "$digest"; }) == "$4" ]] || return 75; cp -- "$backup" "$root/system$stage" && chmod 0644 "$root/system$stage" ;;
					mutate:cleanup) rm -f -- "$root/system$(power_policy_stage_path "$1" "$2")" ;;
					mutate:enable) printf "privileged enable\n" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation enable && return 75; IFS="|" read -r _ active <"$runtime/upower-service"; printf "enabled|%s\n" "$active" >"$runtime/upower-service" ;;
					mutate:start) printf "privileged start\n" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation start && return 75; printf "enabled|active\n" >"$runtime/upower-service" ;;
					mutate:reload-logind) printf "privileged reload-logind\n" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation reload-logind && return 75; refresh_runtime ;;
					mutate:restart) printf "privileged restart\n" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation restart && return 75; printf "enabled|active\n" >"$runtime/upower-service"; refresh_runtime || return; if [[ -s $runtime/restart-delay-us ]]; then cat "$runtime/restart-delay-us" >"$runtime/inhibit-delay-us"; : >"$runtime/restart-delay-us"; fi ;;
					mutate:restore-service) enabled=$1; active=$2; printf "privileged restore-service\n" >>"$DOTFILES_TEST_CALL_LOG"; fail_operation restore-service && return 75; printf "%s|%s\n" "$enabled" "$active" >"$runtime/upower-service"; refresh_runtime ;;
					*) return 2 ;;
				esac
			}
			power_policy_test_write_prepared_pending() {
				local transaction pending
				power_policy_state_paths || return 1
				power_policy_collect_apply_snapshot || return 1
				power_policy_prepare_state_root || return 1
				transaction=$(power_policy_transaction) || return 1
				pending=$(power_policy_pending_json apply "$transaction") || return 1
				power_policy_write_receipt pending "$pending"
			}
			wizard_choose() { printf "%s\n" "${DOTFILES_TEST_POWER_POLICY_MENU_CHOICE:-Back}"; }
			"$operation" "$@"
		' bash "$FIXTURE_REPO" "$operation" "$@"
}

run_wallpaper_operation() {
	local working_directory=$1 operation=$2
	local nested_shared_scope=false status
	shift 2
	if [[ ${DOTFILES_TEST_FAST_WALLPAPER_FILES:-false} == true ]]; then
		if [[ -n $WALLPAPER_TEST_FAST_SHARED_WORKER && \
			$BASHPID != "$WALLPAPER_TEST_FAST_SHARED_WORKER" ]]; then
			nested_shared_scope=true
			if [[ -n $WALLPAPER_TEST_FAST_SHARED_SANDBOX_PID ]]; then
				wallpaper_test_fast_shared_sandbox_detach
			fi
		fi
		wallpaper_test_fast_shared_sandbox_start || return 1
	fi
	run_in_sandbox "$working_directory" "$FIXTURE_WALLPAPER_BIN:${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" \
		bash -c '
			set -euo pipefail
			repository=$1
			operation=$2
			shift 2
			source "$repository/lib/dotfiles/core.sh"
			source "$repository/lib/dotfiles/wallpapers.sh"
			if [[ $DOTFILES_TEST_FAST_WALLPAPER_FILES == true ]]; then
				source "$repository/lib/dotfiles/fast_wallpaper_files.sh"
				if [[ -n ${DOTFILES_TEST_FAST_SHARED_REQUEST-} && -n ${DOTFILES_TEST_FAST_SHARED_RESPONSE-} ]]; then
					wallpaper_test_fast_shared_client_stop() {
						local input=${WALLPAPER_TEST_FAST_SERVER_INPUT-} output=${WALLPAPER_TEST_FAST_SERVER_OUTPUT-}
						if [[ -n $input ]]; then eval "exec ${input}>&-" || true; fi
						if [[ -n $output ]]; then eval "exec ${output}<&-" || true; fi
						WALLPAPER_TEST_FAST_SERVER_INPUT=''
						WALLPAPER_TEST_FAST_SERVER_OUTPUT=''
					}
					exec {WALLPAPER_TEST_FAST_SERVER_INPUT}>"$DOTFILES_TEST_FAST_SHARED_REQUEST"
					exec {WALLPAPER_TEST_FAST_SERVER_OUTPUT}<"$DOTFILES_TEST_FAST_SHARED_RESPONSE"
					trap "wallpaper_test_fast_shared_client_stop" EXIT
				else
					wallpaper_test_fast_server_start || exit 1
					trap "wallpaper_test_fast_server_stop" EXIT
				fi
				trap "wallpaper_test_fast_server_stop" EXIT
				trap "wallpaper_test_fast_server_stop; exit 143" TERM
				trap "wallpaper_test_fast_server_stop; exit 130" INT
				wallpaper_files() { wallpaper_test_fast_files "$@"; }
			fi
			source "$repository/lib/dotfiles/wizard.sh"
			wallpaper_test_interrupt() {
				if [[ $DOTFILES_TEST_WALLPAPER_SIGNAL == "$1-kill" ]]; then kill -KILL $$; fi
				[[ $DOTFILES_TEST_WALLPAPER_SIGNAL != "$1" ]] || kill -TERM $$
			}
			wallpaper_test_replace_state_root() {
				local replacement="$WALLPAPER_STATE_ROOT.wallpaper-race-replacement"
				mv -T -- "$WALLPAPER_STATE_ROOT" "$replacement" || return
				mkdir -m 0700 -- "$WALLPAPER_STATE_ROOT"
				DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE=""
			}
			wallpaper_after_lock_acquired() {
				[[ $DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE == after-lock ]] || return 0
				wallpaper_test_replace_state_root
			}
			wallpaper_after_pending_planned() {
				local path=$DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH
				if [[ $DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE == after-pending ]]; then
					wallpaper_test_replace_state_root
					return
				fi
				[[ $DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE == parent ]] || return 0
				mv -T -- "$path" "$path.wallpaper-post-pending-old" || return
				mkdir -- "$path"
				DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=""
			}
			wallpaper_after_pending_staged() {
				local path=$DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH replacement=$DOTFILES_TEST_WALLPAPER_POST_PENDING_REPLACEMENT
				[[ -n $DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE ]] || return 0
				case $DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE in
					file)
						cp --preserve=mode,timestamps -- "$path" "$path.wallpaper-post-pending" || return
						mv -fT -- "$path.wallpaper-post-pending" "$path"
						;;
					active-link)
						ln -s -- "$replacement" "$path.wallpaper-post-pending" || return
						mv -fT -- "$path.wallpaper-post-pending" "$path"
						;;
				esac
				DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=""
			}
			wallpaper_cleanup_checkpoint() {
				wallpaper_test_interrupt "cleanup-$1"
			}
			wallpaper_preparation_checkpoint() {
				wallpaper_test_interrupt "preparing-$1"
				[[ $DOTFILES_TEST_WALLPAPER_PREPARATION_FAIL != "$1" ]] || return 86
			}
			wallpaper_test_replace_before_deletion() {
				local path=$1 replacement=$DOTFILES_TEST_WALLPAPER_DELETE_RACE_REPLACEMENT temporary
				[[ -n $DOTFILES_TEST_WALLPAPER_DELETE_RACE_PATH && $path == "$DOTFILES_TEST_WALLPAPER_DELETE_RACE_PATH" ]] || return 0
				temporary="$path.wallpaper-delete-race"
				cp --preserve=mode,timestamps -- "$replacement" "$temporary" || return
				mv -fT -- "$temporary" "$path"
				DOTFILES_TEST_WALLPAPER_DELETE_RACE_PATH=""
			}
			if [[ $DOTFILES_TEST_WALLPAPER_VERSION_CHANGES == true ]]; then
				wallpaper_omarchy_version() {
					local marker="$TMPDIR/wallpaper-version-inspected"
					if [[ -e $marker ]]; then printf "5.0.0\n"; else : >"$marker"; printf "4.0.0\n"; fi
				}
			fi
			wallpaper_test_replace_after_confirmation() {
				local path=$DOTFILES_TEST_WALLPAPER_RACE_PATH replacement raw
				[[ -n $DOTFILES_TEST_WALLPAPER_RACE ]] || return 0
				replacement="$path.wallpaper-race"
				case $DOTFILES_TEST_WALLPAPER_RACE in
					file)
						cp --preserve=mode,timestamps -- "$path" "$replacement" || return
						mv -fT -- "$replacement" "$path"
						;;
					directory)
						cp -a -- "$path" "$replacement" || return
						mv -T -- "$path" "$path.wallpaper-race-old" || return
						mv -T -- "$replacement" "$path"
						;;
					symlink)
						raw=$(readlink -- "$path") || return
						ln -s -- "$raw" "$replacement" || return
						mv -fT -- "$replacement" "$path"
						;;
				esac
				DOTFILES_TEST_WALLPAPER_RACE=''
			}
			wallpaper_confirm() {
				wizard_confirm "$1" || return
				wallpaper_test_replace_after_confirmation
			}
			wallpaper_publish_file() {
				wallpaper_test_interrupt curation-before
				local source=$1 destination=$2 digest=$3
				if [[ $DOTFILES_TEST_WALLPAPER_FAIL == publish-before ]]; then return 77; fi
				wallpaper_publish_file_impl "$@" || return
				wallpaper_test_interrupt curation-after
				if [[ $DOTFILES_TEST_WALLPAPER_FAIL == publish-after ]]; then return 78; fi
			}
			wallpaper_delete_file() {
				[[ $DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS != target-delete ]] || return 0
				wallpaper_test_replace_before_deletion "$1" || return
				wallpaper_delete_file_impl "$@" || return
				wallpaper_test_interrupt curation-delete-after
				if [[ $DOTFILES_TEST_WALLPAPER_FAIL == delete-after ]]; then return 79; fi
			}
			wallpaper_restore_file() {
				[[ $DOTFILES_TEST_WALLPAPER_FAIL_ROLLBACK != true ]] || return 80
				wallpaper_restore_file_impl "$@"
			}
			wallpaper_restore_from_quarantine() {
				[[ $DOTFILES_TEST_WALLPAPER_FAIL_ROLLBACK != true ]] || return 80
				wallpaper_restore_from_quarantine_impl "$@"
			}
			wallpaper_publish_live_file() {
				wallpaper_test_interrupt live-before
				if [[ $DOTFILES_TEST_WALLPAPER_FAIL == live-publish-before ]]; then return 82; fi
				wallpaper_publish_live_file_impl "$@" || return
				wallpaper_test_interrupt live-after
				if [[ $DOTFILES_TEST_WALLPAPER_FAIL == live-publish-after ]]; then return 83; fi
			}
			wallpaper_delete_live_file() {
				local target
				target=$(wallpaper_live_target_path "$1") || return
				[[ $DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS != live-delete ]] || return 0
				wallpaper_test_replace_before_deletion "$target" || return
				wallpaper_delete_live_file_impl "$@" || return
				wallpaper_test_interrupt live-delete-quarantine-after
				if [[ $DOTFILES_TEST_WALLPAPER_FAIL == live-delete-after ]]; then return 84; fi
			}
			wallpaper_write_state_file() {
				if [[ $DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS == "state-$1-write" ]]; then return 0; fi
				if [[ $DOTFILES_TEST_WALLPAPER_FAIL == "state-$1" ]]; then return 81; fi
				[[ $1 != active ]] || wallpaper_test_interrupt active-before
				wallpaper_write_state_file_impl "$@" || return
				[[ $1 != active ]] || wallpaper_test_interrupt active-after
				if [[ $1 == active && -n $DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE ]]; then
					cp -- "$DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE_REPLACEMENT" "$DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE"
					DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE=""
				fi
			}
			wallpaper_quarantine_prior_active() {
				[[ $DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS != state-active.json-delete ]] || return 0
				wallpaper_quarantine_prior_active_impl "$@"
			}
			wallpaper_remove_state_file() {
				if [[ $DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS == "state-$(basename -- "$1")-delete" ]]; then return 0; fi
				wallpaper_remove_state_file_impl "$@"
			}
			"$operation" "$@"
		' bash "$FIXTURE_REPO" "$operation" "$@"
	status=$?
	if [[ $nested_shared_scope == true ]]; then
		wallpaper_test_fast_shared_sandbox_stop || true
	fi
	return "$status"
}

configure_skill_fakes() {
	make_fake git 'printf "git %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == clone ]]; then
	destination=${!#}
	mkdir -p "$destination"
	case $* in
		*blader/humanizer*) printf "humanizer\n" >"$destination/.test-source" ;;
		*mattpocock/skills*) printf "matt\n" >"$destination/.test-source" ;;
	esac
fi'
	make_fake npx 'printf "npx %s|HOME=%s|STATE=%s|CACHE=%s|TELEMETRY=%s\n" "$*" "$HOME" "$XDG_STATE_HOME" "$npm_config_cache" "$DISABLE_TELEMETRY" >>"$DOTFILES_TEST_CALL_LOG"
source_root=${4-}
source_name=$(<"$source_root/.test-source")
target=$HOME/.agents/skills
mkdir -p "$target"
if [[ $source_name == humanizer ]]; then
	mkdir -p "$target/humanizer/references"
	printf "approved humanizer\n" >"$target/humanizer/SKILL.md"
	printf "support file\n" >"$target/humanizer/references/style.md"
else
	count=35
	if [[ $DOTFILES_TEST_SKILL_COUNT_DRIFT == true ]]; then count=34; fi
	for ((i = 1; i <= count; i++)); do
		name=$(printf "matt-skill-%02d" "$i")
		mkdir -p "$target/$name/assets"
		printf "approved %s\n" "$name" >"$target/$name/SKILL.md"
		printf "payload %s\n" "$name" >"$target/$name/assets/example.txt"
	done
	if [[ $HOME == "$DOTFILES_TEST_HOME" && $DOTFILES_TEST_SKILL_VERIFY_FAILURE == true ]]; then
		printf "corrupt global payload\n" >"$target/matt-skill-01/SKILL.md"
	fi
	if [[ $HOME == "$DOTFILES_TEST_HOME" && $DOTFILES_TEST_SKILL_INSTALL_FAILURE == true ]]; then
		printf "mutated before installer failure\n" >"$target/matt-skill-01/SKILL.md"
		exit 71
	fi
fi
if [[ $HOME == "$DOTFILES_TEST_HOME" ]]; then
	case $DOTFILES_TEST_SKILL_UNRELATED_FAILURE in
		modify) printf "installer damage\n" >"$target/private-skill" ;;
		delete) rm -rf "$target/private-skill" ;;
		add) printf "unexpected\n" >"$target/rogue-skill" ;;
		other-source) if [[ $source_name == matt ]]; then printf "installer damage\n" >"$target/humanizer/SKILL.md"; fi ;;
	esac
fi'
}

configure_skill_update_fakes() {
	configure_skill_fakes
	make_fake git 'printf "git %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
old_humanizer=523374dee72d67c7b2b5f858ea0094ffda49c3ac
old_matt=068b6e0c62393147daf03530149cdce209c93da8
new_matt=ffffffffffffffffffffffffffffffffffffffff
if [[ ${1-} == clone ]]; then
	destination=${!#}
	mkdir -p "$destination"
	case $* in
		*blader/humanizer*) printf "humanizer\n" >"$destination/.test-source"; revision=$old_humanizer ;;
		*mattpocock/skills*) printf "matt\n" >"$destination/.test-source"; revision=$new_matt ;;
	esac
	if [[ $DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE == true ]]; then
		[[ $(<"$destination/.test-source") == humanizer ]] && revision=$old_humanizer || revision=$old_matt
	fi
	printf "%s\n" "$revision" >"$destination/.test-revision"
	exit 0
fi
if [[ ${1-} == -C ]]; then
	checkout=$2
	command=$3
	case $command in
		checkout) printf "%s\n" "${6-}" >"$checkout/.test-revision" ;;
		rev-parse) cat "$checkout/.test-revision" ;;
		log) printf "fffffff Add and revise official skills\n" ;;
		diff) printf "diff --git a/skills/matt b/skills/matt\n+upstream source change\n" ;;
	esac
fi'
	make_fake npx 'printf "npx %s|HOME=%s|STATE=%s|CACHE=%s|TELEMETRY=%s\n" "$*" "$HOME" "$XDG_STATE_HOME" "$npm_config_cache" "$DISABLE_TELEMETRY" >>"$DOTFILES_TEST_CALL_LOG"
source_root=${4-}
source_name=$(<"$source_root/.test-source")
revision=$(<"$source_root/.test-revision")
target=$HOME/.agents/skills
mkdir -p "$target"
if [[ $source_name == humanizer ]]; then
	mkdir -p "$target/humanizer/references"
	printf "approved humanizer\n" >"$target/humanizer/SKILL.md"
	printf "support file\n" >"$target/humanizer/references/style.md"
else
	old_matt=068b6e0c62393147daf03530149cdce209c93da8
	if [[ $revision == "$old_matt" ]]; then
		names=$(seq -w 1 35)
	else
		names="$(seq -w 1 34) 36 37"
	fi
	for i in $names; do
		name=matt-skill-$i
		mkdir -p "$target/$name/assets"
		if [[ $revision != "$old_matt" && $i == 01 ]]; then
			printf "updated %s\n" "$name" >"$target/$name/SKILL.md"
		else
			printf "approved %s\n" "$name" >"$target/$name/SKILL.md"
		fi
		printf "payload %s\n" "$name" >"$target/$name/assets/example.txt"
	done
	if [[ $revision != "$old_matt" && $DOTFILES_TEST_SKILL_UPDATE_COLLISION == true ]]; then
		mkdir -p "$target/humanizer"
		printf "colliding matt humanizer\n" >"$target/humanizer/SKILL.md"
	fi
	if [[ $HOME == "$DOTFILES_TEST_HOME" && $revision != "$old_matt" && $DOTFILES_TEST_SKILL_VERIFY_FAILURE == true ]]; then
		printf "corrupt global payload\n" >"$target/matt-skill-01/SKILL.md"
	fi
	if [[ $HOME == "$DOTFILES_TEST_HOME" && $revision != "$old_matt" && $DOTFILES_TEST_SKILL_INSTALL_FAILURE == true ]]; then
		printf "mutated before installer failure\n" >"$target/matt-skill-02/SKILL.md"
		exit 71
	fi
fi
if [[ $HOME == "$DOTFILES_TEST_HOME" ]]; then
	case $DOTFILES_TEST_SKILL_UNRELATED_FAILURE in
		modify) printf "installer damage\n" >"$target/private-skill" ;;
		delete) rm -rf "$target/private-skill" ;;
		add) printf "unexpected\n" >"$target/rogue-skill" ;;
		other-source) if [[ $source_name == matt ]]; then printf "installer damage\n" >"$target/humanizer/SKILL.md"; fi ;;
	esac
fi'
}

seed_current_global_skills() {
	mkdir -p "$FIXTURE_HOME/.agents/skills/humanizer/references"
	printf 'approved humanizer\n' >"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md"
	printf 'support file\n' >"$FIXTURE_HOME/.agents/skills/humanizer/references/style.md"
	local i name
	for ((i = 1; i <= 35; i++)); do
		name=$(printf 'matt-skill-%02d' "$i")
		mkdir -p "$FIXTURE_HOME/.agents/skills/$name/assets"
		printf 'approved %s\n' "$name" >"$FIXTURE_HOME/.agents/skills/$name/SKILL.md"
		printf 'payload %s\n' "$name" >"$FIXTURE_HOME/.agents/skills/$name/assets/example.txt"
	done
}

global_skill_installer_calls() {
	awk -v home="HOME=$FIXTURE_HOME" '/^npx / && index($0, home) { count++ } END { print count + 0 }' "$CALL_LOG"
}

global_skill_installer_calls_for_source() {
	local source_index=$1
	awk -v home="HOME=$FIXTURE_HOME" -v source="/source-$source_index " \
		'/^npx / && index($0, home) && index($0, source) { count++ } END { print count + 0 }' "$CALL_LOG"
}

run_make() {
	local working_directory=$1
	run_in_sandbox "$working_directory" "$FIXTURE_BIN:/usr/bin:/bin" \
		make --no-print-directory -C "$FIXTURE_REPO"
}

run_dotfiles_without_real_user_or_omarchy_paths() {
	run_operation "$FIXTURE_ROOT" check
}

snapshot_isolated_paths() {
	local path
	for path in \
		"$FIXTURE_HOME/.agents/skills/sentinel" \
		"$FIXTURE_CONFIG/omarchy/sentinel" \
		"$FIXTURE_STATE/sentinel" \
		"$FIXTURE_CACHE/sentinel" \
		"$FIXTURE_OMARCHY/sentinel"; do
		printf '%s:' "$path"
		if [[ -e $path ]]; then
			sha256sum "$path"
		else
			printf 'missing\n'
		fi
	done
}

snapshot_outside_canaries() {
	(
		cd -- "$OUTSIDE_ROOT" || return 1
		find . -printf '%P|%y|%m|%s|%T@\n' | sort
		sha256sum user-config/sentinel global-skills/sentinel packaged-omarchy/sentinel
	)
}

run_test() {
	local name=$1
	local description=$2
	local test_failed=false
	shift 2

	WALLPAPER_TEST_FAST_SHARED_WORKER=$BASHPID
	TESTS_RUN=$((TESTS_RUN + 1))
	OUTSIDE_CANARY_CHANGED=false
	if ! "$name" "$@"; then
		test_failed=true
	fi
	if [[ $OUTSIDE_CANARY_CHANGED == true ]] || \
		{ [[ -n ${OUTSIDE_ROOT-} && -d $OUTSIDE_ROOT ]] && \
			[[ $(snapshot_outside_canaries) != "$OUTSIDE_SNAPSHOT" ]]; }; then
		printf '  paths outside the fixture roots changed during %s\n' "$description" >&2
		test_failed=true
	fi
	if [[ $test_failed == true ]]; then
		fail "$description"
	else
		pass "$description"
	fi
	if [[ ${DOTFILES_TEST_REUSE_WALLPAPER_SANDBOX:-false} != true ]]; then
		wallpaper_test_fast_shared_sandbox_stop || true
	fi
	WALLPAPER_TEST_FAST_SHARED_WORKER=''
	if [[ -n ${FIXTURE_ROOT-} && -d $FIXTURE_ROOT ]]; then
		rm -rf "$FIXTURE_ROOT"
	fi
	if [[ -n ${OUTSIDE_ROOT-} && -d $OUTSIDE_ROOT ]]; then
		rm -rf "$OUTSIDE_ROOT"
	fi
}

run_test_group() {
	local group=$1 name=$2 description=$3 argument=${4-}

	[[ $group =~ ^[1-9][0-9]*$ ]] || return 1
	PARALLEL_TEST_GROUP_NAMES+=("$name")
	PARALLEL_TEST_GROUP_DESCRIPTIONS+=("$description")
	PARALLEL_TEST_GROUP_IDS+=("$group")
	PARALLEL_TEST_GROUP_ARGUMENTS+=("$argument")
	TESTS_RUN=$((TESTS_RUN + 1))
}

parallel_test_wait_for_one_worker_completion() {
	local kind event_pid index pid marker

	[[ $PARALLEL_TEST_EVENT_READ_FD =~ ^[0-9]+$ ]] || return 1
	while IFS=' ' read -r kind event_pid <&"$PARALLEL_TEST_EVENT_READ_FD"; do
		[[ $kind =~ ^(abnormal|exit|watch-failed)$ && $event_pid =~ ^[1-9][0-9]*$ ]] || continue
		index=-1
		for ((index = 0; index < ${#PARALLEL_TEST_PIDS[@]}; index++)); do
			[[ ${PARALLEL_TEST_PIDS[$index]-} == "$event_pid" ]] || continue
			break
		done
		if ((index >= ${#PARALLEL_TEST_PIDS[@]})); then
			# An abnormal worker notifies before its pidfd watcher; consume that
			# later watcher event after the worker has been unregistered.
			continue
		fi
		pid=${PARALLEL_TEST_PIDS[$index]}
		marker=${PARALLEL_TEST_WORKER_MARKERS[$index]-}
		if [[ -n $marker && -f $marker ]]; then
			# Completion is worker-owned: its resources are already stopped and the
			# marker is the final publication. Reap only this registered root.
			wait "$pid" 2>/dev/null || true
			parallel_test_unregister_worker_root "$index"
			return 0
		fi
		parallel_test_abort_worker "$index" "$kind" && return 0
		return 1
	done
	printf 'Error: parallel test worker event relay closed before a worker completed.\n' >&2
	parallel_test_cleanup || true
	return 1
}

run_queued_test_groups() {
	local group_count=0 group index total_tests worker_pid worker_root worker_marker registration_status
	local limit=${DOTFILES_TEST_PARALLEL_LIMIT:-10}

	for group in "${PARALLEL_TEST_GROUP_IDS[@]}"; do
		if ((group > group_count)); then group_count=$group; fi
	done
	[[ $group_count -gt 0 ]] || return 0
	total_tests=$TESTS_RUN
	PARALLEL_TEST_STARTUP_FAILED=false
	PARALLEL_TEST_STARTUP_ERROR=''
	if ! PARALLEL_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test-workers.XXXXXX"); then
		PARALLEL_TEST_STARTUP_FAILED=true
		PARALLEL_TEST_STARTUP_ERROR='could not create queued test worker root'
		printf 'Error: %s.\n' "$PARALLEL_TEST_STARTUP_ERROR" >&2
		return 1
	fi
	PARALLEL_TEST_PIDS=()
	PARALLEL_TEST_PGIDS=()
	PARALLEL_TEST_START_TIMES=()
	PARALLEL_TEST_PIDFD_INODES=()
	PARALLEL_TEST_WORKER_MARKERS=()
	PARALLEL_TEST_WATCHER_PIDS=()
	PARALLEL_TEST_RUNNING=0
	if ! parallel_test_start_event_relay; then
		PARALLEL_TEST_STARTUP_FAILED=true
		PARALLEL_TEST_STARTUP_ERROR='could not start queued test worker event relay'
		printf 'Error: %s.\n' "$PARALLEL_TEST_STARTUP_ERROR" >&2
		return 1
	fi

	for ((group = 1; group <= group_count; group++)); do
	if [[ $limit =~ ^[1-9][0-9]*$ ]]; then
			while ((PARALLEL_TEST_RUNNING >= limit)); do
				parallel_test_wait_for_one_worker_completion || return 1
				PARALLEL_TEST_RUNNING=$((PARALLEL_TEST_RUNNING - 1))
			done
		fi
		worker_root="$PARALLEL_TEST_ROOT/worker-${BASHPID}-${group}"
		if ! mkdir -p -- "$worker_root"; then
			PARALLEL_TEST_STARTUP_FAILED=true
			PARALLEL_TEST_STARTUP_ERROR="could not create queued worker directory for group $group"
			printf 'Error: %s.\n' "$PARALLEL_TEST_STARTUP_ERROR" >&2
			return 1
		fi
		worker_marker="$PARALLEL_TEST_ROOT/group-$group.complete"
		PARALLEL_TEST_LAUNCHING=true
		if [[ $- != *m* ]]; then
			set -m
			PARALLEL_TEST_MONITOR_CHANGED=true
		fi
		PARALLEL_TEST_LAUNCH_PID=''
		(
			worker_results_root=$PARALLEL_TEST_ROOT
			parallel_test_prepare_worker "$worker_marker" || exit 1
			PARALLEL_TEST_WORKER_ROOT=$worker_root
			DOTFILES_TEST_REUSE_WALLPAPER_SANDBOX=true
			TESTS_FAILED=0
			worker_statuses=()
			for ((index = 1; index <= total_tests; index++)); do
				[[ ${PARALLEL_TEST_GROUP_IDS[$((index - 1))]} == "$group" ]] || continue
				TESTS_RUN=$((index - 1))
				TESTS_FAILED=0
				if [[ -n ${PARALLEL_TEST_GROUP_ARGUMENTS[$((index - 1))]} ]]; then
					run_test "${PARALLEL_TEST_GROUP_NAMES[$((index - 1))]}" \
						"${PARALLEL_TEST_GROUP_DESCRIPTIONS[$((index - 1))]}" \
						"${PARALLEL_TEST_GROUP_ARGUMENTS[$((index - 1))]}" \
						>"$worker_results_root/$index.output" 2>&1 || true
				else
					run_test "${PARALLEL_TEST_GROUP_NAMES[$((index - 1))]}" \
						"${PARALLEL_TEST_GROUP_DESCRIPTIONS[$((index - 1))]}" \
						>"$worker_results_root/$index.output" 2>&1 || true
				fi
				worker_statuses[$index]=$TESTS_FAILED
			done
			parallel_test_worker_stop_owned_resources || exit 1
			for ((index = 1; index <= total_tests; index++)); do
				[[ ${PARALLEL_TEST_GROUP_IDS[$((index - 1))]} == "$group" ]] || continue
				printf '%s\n' "${worker_statuses[$index]}" >"$worker_results_root/$index.status" || exit 1
			done
			parallel_test_worker_mark_normal_completion || exit 1
		) >"$PARALLEL_TEST_ROOT/group-$group.output" 2>&1 &
		worker_pid=$!
		PARALLEL_TEST_LAUNCH_PID=$worker_pid
		PARALLEL_TEST_PIDS+=("$worker_pid")
		PARALLEL_TEST_START_TIMES+=('')
		PARALLEL_TEST_PGIDS+=('')
		PARALLEL_TEST_PIDFD_INODES+=('')
		PARALLEL_TEST_WORKER_MARKERS+=("$worker_marker")
		PARALLEL_TEST_RUNNING=$((PARALLEL_TEST_RUNNING + 1))
		if parallel_test_register_or_reap_completed_worker "$(( ${#PARALLEL_TEST_PIDS[@]} - 1 ))"; then
			registration_status=0
		else
			registration_status=$?
		fi
		if ((registration_status == 2)); then
			PARALLEL_TEST_RUNNING=$((PARALLEL_TEST_RUNNING - 1))
		elif ((registration_status != 0)); then
			PARALLEL_TEST_STARTUP_FAILED=true
			PARALLEL_TEST_STARTUP_ERROR="could not register queued worker $worker_pid"
			printf 'Error: %s.\n' "$PARALLEL_TEST_STARTUP_ERROR" >&2
			return 1
		fi
		PARALLEL_TEST_LAUNCHING=false
		PARALLEL_TEST_LAUNCH_PID=''
	done
}

run_test_parallel() {
	local name=$1
	local description=$2
	local index limit=${DOTFILES_TEST_PARALLEL_LIMIT:-15}
	local worker_pid worker_root worker_marker registration_status
	[[ $PARALLEL_TEST_CLEANUP_ACTIVE == false ]] || return 1
	if [[ -z $PARALLEL_TEST_ROOT ]]; then
		PARALLEL_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test-workers.XXXXXX") || return 1
		parallel_test_start_event_relay || return 1
	fi
	if [[ $limit =~ ^[1-9][0-9]*$ ]]; then
		while ((PARALLEL_TEST_RUNNING >= limit)); do
			parallel_test_wait_for_one_worker_completion || return 1
			PARALLEL_TEST_RUNNING=$((PARALLEL_TEST_RUNNING - 1))
		done
	fi
	TESTS_RUN=$((TESTS_RUN + 1))
	index=$TESTS_RUN
	worker_root="$PARALLEL_TEST_ROOT/worker-${BASHPID}-${index}"
	mkdir -p -- "$worker_root" || return 1
	worker_marker="$PARALLEL_TEST_ROOT/$index.complete"
	PARALLEL_TEST_LAUNCHING=true
	if [[ $- != *m* ]]; then
		set -m
		PARALLEL_TEST_MONITOR_CHANGED=true
	fi
	PARALLEL_TEST_LAUNCH_PID=''
	(
		worker_results_root=$PARALLEL_TEST_ROOT
		parallel_test_prepare_worker "$worker_marker" || exit 1
		PARALLEL_TEST_WORKER_ROOT=$worker_root
		TESTS_RUN=$((index - 1))
		TESTS_FAILED=0
		run_test "$name" "$description"
		parallel_test_worker_stop_owned_resources || exit 1
		printf '%s\n' "$TESTS_FAILED" >"$worker_results_root/$index.status" || exit 1
		parallel_test_worker_mark_normal_completion || exit 1
	) >"$PARALLEL_TEST_ROOT/$index.output" 2>&1 &
	worker_pid=$!
	PARALLEL_TEST_LAUNCH_PID=$worker_pid
	PARALLEL_TEST_PIDS+=("$worker_pid")
	PARALLEL_TEST_START_TIMES+=('')
	PARALLEL_TEST_PGIDS+=('')
	PARALLEL_TEST_PIDFD_INODES+=('')
	PARALLEL_TEST_WORKER_MARKERS+=("$worker_marker")
	PARALLEL_TEST_RUNNING=$((PARALLEL_TEST_RUNNING + 1))
	if parallel_test_register_or_reap_completed_worker "$(( ${#PARALLEL_TEST_PIDS[@]} - 1 ))"; then
		registration_status=0
	else
		registration_status=$?
	fi
	if ((registration_status == 2)); then
		PARALLEL_TEST_RUNNING=$((PARALLEL_TEST_RUNNING - 1))
	elif ((registration_status != 0)); then
		return 1
	fi
	PARALLEL_TEST_LAUNCHING=false
	PARALLEL_TEST_LAUNCH_PID=''
}

finish_tests() {
	local index pid status
	if ((${#PARALLEL_TEST_GROUP_NAMES[@]} > 0)); then
		if ! run_queued_test_groups; then
			TESTS_FAILED=$((TESTS_FAILED + 1))
			printf 'not ok 0 - queued test worker startup failed: %s\n' "${PARALLEL_TEST_STARTUP_ERROR:-unknown error}"
		fi
	fi
	if [[ -n $PARALLEL_TEST_ROOT ]]; then
		while ((PARALLEL_TEST_RUNNING > 0)); do
			if ! parallel_test_wait_for_one_worker_completion; then
				TESTS_FAILED=$((TESTS_FAILED + 1))
				break
			fi
			PARALLEL_TEST_RUNNING=$((PARALLEL_TEST_RUNNING - 1))
		done
		for ((index = 1; index <= TESTS_RUN; index++)); do
			if [[ -f $PARALLEL_TEST_ROOT/$index.output ]]; then
				cat "$PARALLEL_TEST_ROOT/$index.output"
			else
				printf 'not ok %d - test worker exited before producing output\n' "$index"
				TESTS_FAILED=$((TESTS_FAILED + 1))
			fi
			if [[ -f $PARALLEL_TEST_ROOT/$index.status ]]; then
				status=$(<"$PARALLEL_TEST_ROOT/$index.status")
				[[ $status == 0 ]] || TESTS_FAILED=$((TESTS_FAILED + 1))
			elif [[ -f $PARALLEL_TEST_ROOT/$index.output ]]; then
				printf 'not ok %d - test worker exited before reporting its result\n' "$index"
				TESTS_FAILED=$((TESTS_FAILED + 1))
			fi
		done
		parallel_test_cleanup || true
	fi
	printf '1..%d\n' "$TESTS_RUN"
	return "$TESTS_FAILED"
}
