#!/usr/bin/env bash

set -u

ACTIVE_COLOR_OVERRIDE=${WAYBAR_PRIVACY_ACTIVE_COLOR:-}
INACTIVE_COLOR_OVERRIDE=${WAYBAR_PRIVACY_INACTIVE_COLOR:-}
UNAVAILABLE_COLOR_OVERRIDE=${WAYBAR_PRIVACY_UNAVAILABLE_COLOR:-}
source "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-theme/current/.config/waybar/theme.sh"
DEFAULT_ACTIVE_COLOR=$WAYBAR_PRIVACY_ACTIVE_COLOR
DEFAULT_INACTIVE_COLOR=$WAYBAR_PRIVACY_INACTIVE_COLOR
DEFAULT_UNAVAILABLE_COLOR=$WAYBAR_PRIVACY_UNAVAILABLE_COLOR
ACTIVE_COLOR=${ACTIVE_COLOR_OVERRIDE:-$DEFAULT_ACTIVE_COLOR}
INACTIVE_COLOR=${INACTIVE_COLOR_OVERRIDE:-$DEFAULT_INACTIVE_COLOR}
UNAVAILABLE_COLOR=${UNAVAILABLE_COLOR_OVERRIDE:-$DEFAULT_UNAVAILABLE_COLOR}
POLL_INTERVAL=${WAYBAR_PRIVACY_POLL_INTERVAL:-1}
RECOVERY_INTERVAL=${WAYBAR_PRIVACY_RECOVERY_INTERVAL:-30}

MIC_ICON=$'\uec1c'
CAMERA_ICON=$'\U000f0100'
LOCATION_ICON=$'\ueb1a'

pipewire_available=false
pipewire_apps='{"microphone":[],"camera":[]}'
direct_microphone_available=false
direct_microphone_apps='[]'
direct_camera_available=false
direct_camera_apps='[]'
location_status=unavailable

microphone_status=unavailable
microphone_apps='[]'
microphone_errors=""
camera_status=unavailable
camera_apps='[]'
camera_errors=""

last_output=""
event_dir=""
event_fifo=""
pipewire_watcher_pid=""
geoclue_watcher_pid=""

normalize_intervals() {
	if [[ ! $POLL_INTERVAL =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ $POLL_INTERVAL == 0 ]]; then
		POLL_INTERVAL=1
	fi

	if [[ ! $RECOVERY_INTERVAL =~ ^[0-9]+$ ]] || ((RECOVERY_INTERVAL < 1)); then
		RECOVERY_INTERVAL=30
	fi
}

normalize_colors() {
	[[ $ACTIVE_COLOR =~ ^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$ ]] || ACTIVE_COLOR=$DEFAULT_ACTIVE_COLOR
	[[ $INACTIVE_COLOR =~ ^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$ ]] || INACTIVE_COLOR=$DEFAULT_INACTIVE_COLOR
	[[ $UNAVAILABLE_COLOR =~ ^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$ ]] || UNAVAILABLE_COLOR=$DEFAULT_UNAVAILABLE_COLOR
}

query_pipewire() {
	local dump
	local parsed

	if ! command -v pw-dump >/dev/null 2>&1; then
		pipewire_available=false
		pipewire_apps='{"microphone":[],"camera":[]}'
		return
	fi

	if ! dump=$(pw-dump 2>/dev/null); then
		pipewire_available=false
		pipewire_apps='{"microphone":[],"camera":[]}'
		return
	fi

	if ! parsed=$(jq -ce '
		def props($object): $object.info.props // {};
		def running($object): (($object.info.state // "") | ascii_downcase) == "running";
		def truthy($value):
			$value == true or $value == 1 or (($value // "") | tostring | ascii_downcase) == "true";
		def loopback($node):
			props($node) as $props
			| truthy($props["node.loopback"])
				or (($props["application.process.binary"] // "") == "pw-loopback")
				or (($props["node.group"] // "") | tostring | startswith("loopback-"))
				or (($props["node.link-group"] // "") | tostring | startswith("loopback-"))
				or (($props["node.name"] // "") | tostring | ascii_downcase | test("loopback|snd_aloop"));
		def present($value):
			if $value == null or (($value | tostring) == "") then null else $value end;
		def app_info($stream; $clients):
			props($stream) as $stream_props
			| ($clients[(($stream_props["client.id"] // -1) | tostring)] // {}) as $client
			| props($client) as $client_props
			| {
				name: (
					present($stream_props["application.name"])
					// present($stream_props["pipewire.access.portal.app_id"])
					// present($stream_props["application.id"])
					// present($client_props["application.name"])
					// present($client_props["pipewire.access.portal.app_id"])
					// present($client_props["application.process.binary"])
					// "Unknown application"
				),
				pid: (
					present($stream_props["pipewire.sec.pid"])
					// present($stream_props["application.process.id"])
					// present($client_props["pipewire.sec.pid"])
					// present($client_props["application.process.id"])
					| if . == null then null else tostring end
				)
			};

		. as $all
		| ($all | map(select(.type == "PipeWire:Interface:Node")) | INDEX(.id | tostring)) as $nodes
		| ($all | map(select(.type == "PipeWire:Interface:Port")) | INDEX(.id | tostring)) as $ports
		| ($all | map(select(.type == "PipeWire:Interface:Client")) | INDEX(.id | tostring)) as $clients
		| [
			$all[]
			| select(.type == "PipeWire:Interface:Link")
			| select(((.info.state // "") | ascii_downcase) == "active")
			| . as $link
			| ($nodes[(($link.info["input-node-id"] // -1) | tostring)] // {}) as $stream
			| ($nodes[(($link.info["output-node-id"] // -1) | tostring)] // {}) as $source
			| ($ports[(($link.info["output-port-id"] // -1) | tostring)] // {}) as $source_port
			| props($stream) as $stream_props
			| props($source) as $source_props
			| props($source_port) as $port_props
			| select(running($stream) and running($source))
			| if $stream_props["media.class"] == "Stream/Input/Audio" then
				select(
					(truthy($stream_props["stream.monitor"])
					or truthy($stream_props["stream.capture.sink"])
					or ($stream_props["media.category"] == "Monitor")
					or loopback($stream)) | not
				)
				| select(($source_props["media.class"] // "") | startswith("Audio/Source"))
				| select($source_props["device.id"] != null)
				| select($source_props["device.api"] == "alsa" or $source_props["device.api"] == "bluez5")
				| select(
					(truthy($source_props["stream.monitor"])
					or truthy($source_props["stream.capture.sink"])
					or ($source_props["media.category"] == "Monitor")
					or truthy($port_props["port.monitor"])
					or loopback($source)) | not
				)
				| {sensor: "microphone"} + app_info($stream; $clients)
			elif $stream_props["media.class"] == "Stream/Input/Video" then
				select(loopback($stream) | not)
				| select($source_props["media.class"] == "Video/Source")
				| select($source_props["device.id"] != null)
				| select($source_props["device.api"] == "v4l2" or $source_props["device.api"] == "libcamera")
				| select((($source_props["api.v4l2.cap.driver"] // "") | ascii_downcase | contains("loopback")) | not)
				| select(loopback($source) | not)
				| {sensor: "camera"} + app_info($stream; $clients)
			else
				empty
			end
		] as $captures
		| {
			microphone: ([$captures[] | select(.sensor == "microphone") | del(.sensor)] | unique_by([.name, .pid])),
			camera: ([$captures[] | select(.sensor == "camera") | del(.sensor)] | unique_by([.name, .pid]))
		}
	' <<<"$dump" 2>/dev/null); then
		pipewire_available=false
		pipewire_apps='{"microphone":[],"camera":[]}'
		return
	fi

	pipewire_available=true
	pipewire_apps=$parsed
}

query_direct_devices() {
	local sensor=$1
	shift
	local available_variable="direct_${sensor}_available"
	local apps_variable="direct_${sensor}_apps"
	local output=""
	local result=0
	local token
	local pid
	local name
	local entry
	local apps='[]'
	local entries=()

	if ! command -v fuser >/dev/null 2>&1; then
		printf -v "$available_variable" '%s' false
		printf -v "$apps_variable" '%s' '[]'
		return
	fi

	if (($# == 0)); then
		printf -v "$available_variable" '%s' true
		printf -v "$apps_variable" '%s' '[]'
		return
	fi

	output=$(fuser "$@" 2>/dev/null) || result=$?
	if ((result > 1)); then
		printf -v "$available_variable" '%s' false
		printf -v "$apps_variable" '%s' '[]'
		return
	fi

	for token in $output; do
		pid=${token//[^0-9]/}
		[[ -n $pid ]] || continue

		name=""
		if [[ -r /proc/$pid/comm ]]; then
			IFS= read -r name < "/proc/$pid/comm" || name=""
		fi
		[[ -n $name ]] || name="Unknown process"

		case ${name,,} in
			pipewire* | wireplumber | pipewire-media-session)
				continue
				;;
		esac

		entry=$(jq -nc --arg name "$name" --arg pid "$pid" '{name: $name, pid: $pid}') || continue
		entries+=("$entry")
	done

	if ((${#entries[@]} > 0)); then
		apps=$(printf '%s\n' "${entries[@]}" | jq -sc 'unique_by(.pid)') || apps='[]'
	fi

	printf -v "$available_variable" '%s' true
	printf -v "$apps_variable" '%s' "$apps"
}

query_direct_capture() {
	local all_microphone_devices=()
	local all_camera_devices=()
	local microphone_devices=()
	local camera_devices=()
	local device
	local sysfs_path
	local microphone_probe_failed=false
	local camera_probe_failed=false

	shopt -s nullglob
	all_microphone_devices=(/dev/snd/pcm*C*c)
	all_camera_devices=(/dev/video*)
	shopt -u nullglob

	for device in "${all_microphone_devices[@]}"; do
		if [[ ! -r $device ]] || ! sysfs_path=$(readlink -f "/sys/class/sound/${device##*/}/device" 2>/dev/null); then
			microphone_probe_failed=true
			continue
		fi
		[[ $sysfs_path == */virtual/* ]] || microphone_devices+=("$device")
	done

	if ((${#all_camera_devices[@]} > 0)) && ! command -v v4l2-ctl >/dev/null 2>&1; then
		camera_probe_failed=true
	else
		for device in "${all_camera_devices[@]}"; do
			if [[ ! -r $device ]] || ! sysfs_path=$(readlink -f "/sys/class/video4linux/${device##*/}/device" 2>/dev/null); then
				camera_probe_failed=true
				continue
			fi
			[[ $sysfs_path == */virtual/* ]] && continue
			if v4l2-ctl --device "$device" --get-fmt-video >/dev/null 2>&1; then
				camera_devices+=("$device")
			fi
		done
	fi

	query_direct_devices microphone "${microphone_devices[@]}"
	query_direct_devices camera "${camera_devices[@]}"

	if [[ $microphone_probe_failed == true ]]; then
		direct_microphone_available=false
	fi
	if [[ $camera_probe_failed == true ]]; then
		direct_camera_available=false
	fi
}

query_location() {
	local response
	local in_use

	if ! command -v busctl >/dev/null 2>&1; then
		location_status=unavailable
		return
	fi

	if ! response=$(busctl --system --json=short call \
		org.freedesktop.GeoClue2 \
		/org/freedesktop/GeoClue2/Manager \
		org.freedesktop.DBus.Properties \
		Get ss \
		org.freedesktop.GeoClue2.Manager \
		InUse 2>/dev/null); then
		location_status=unavailable
		return
	fi

	if ! in_use=$(jq -r '
		if .type == "v" and .data[0].type == "b" then
			.data[0].data
		else
			error("unexpected GeoClue response")
		end
	' <<<"$response" 2>/dev/null); then
		location_status=unavailable
		return
	fi

	if [[ $in_use == true ]]; then
		location_status=active
	else
		location_status=inactive
	fi
}

join_errors() {
	local first=true
	local item

	for item in "$@"; do
		if [[ $first == true ]]; then
			printf '%s' "$item"
			first=false
		else
			printf ', %s' "$item"
		fi
	done
}

combine_sensor_state() {
	local sensor=$1
	local pipewire_sensor_apps
	local direct_available_variable="direct_${sensor}_available"
	local direct_apps_variable="direct_${sensor}_apps"
	local status_variable="${sensor}_status"
	local apps_variable="${sensor}_apps"
	local errors_variable="${sensor}_errors"
	local direct_label
	local direct_available=${!direct_available_variable}
	local direct_apps=${!direct_apps_variable}
	local combined_apps
	local app_count
	local errors=()

	pipewire_sensor_apps=$(jq -c --arg sensor "$sensor" '.[$sensor] // []' <<<"$pipewire_apps") || pipewire_sensor_apps='[]'
	combined_apps=$(jq -nc --argjson pipewire "$pipewire_sensor_apps" --argjson direct "$direct_apps" \
		'$pipewire + $direct | unique_by([.name, .pid])') || combined_apps='[]'
	app_count=$(jq -r 'length' <<<"$combined_apps") || app_count=0

	if [[ $pipewire_available != true ]]; then
		errors+=(PipeWire)
	fi

	if [[ $sensor == microphone ]]; then
		direct_label="direct ALSA"
	else
		direct_label="direct camera"
	fi
	if [[ $direct_available != true ]]; then
		errors+=("$direct_label")
	fi

	printf -v "$apps_variable" '%s' "$combined_apps"
	printf -v "$errors_variable" '%s' "$(join_errors "${errors[@]}")"

	if ((app_count > 0)); then
		printf -v "$status_variable" '%s' active
	elif ((${#errors[@]} > 0)); then
		printf -v "$status_variable" '%s' unavailable
	else
		printf -v "$status_variable" '%s' inactive
	fi
}

combine_state() {
	combine_sensor_state microphone
	combine_sensor_state camera
}

refresh_all() {
	query_pipewire
	query_direct_capture
	query_location
	combine_state
}

refresh_direct() {
	query_direct_capture
	combine_state
}

color_for_status() {
	case $1 in
		active)
			printf '%s' "$ACTIVE_COLOR"
			;;
		inactive)
			printf '%s' "$INACTIVE_COLOR"
			;;
		*)
			printf '%s' "$UNAVAILABLE_COLOR"
			;;
	esac
}

format_apps() {
	jq -r '
		def pango_escape:
			tostring
			| gsub("&"; "&amp;")
			| gsub("<"; "&lt;")
			| gsub(">"; "&gt;")
			| gsub("\\\""; "&quot;");
		map(
			(.name | pango_escape) as $name
			| if .pid != null and .pid != "" then
				"\($name) (PID \(.pid))"
			else
				$name
			end
		) | join(", ")
	' <<<"$1" 2>/dev/null
}

format_sensor_line() {
	local label=$1
	local status=$2
	local apps=$3
	local errors=$4
	local app_list
	local line="$label: $status"

	if [[ $status == active ]]; then
		app_list=$(format_apps "$apps")
		if [[ -n $app_list ]]; then
			line+=" - $app_list"
		fi
		if [[ -n $errors ]]; then
			line+=" (coverage unavailable: $errors)"
		fi
	elif [[ $status == unavailable && -n $errors ]]; then
		line+=" ($errors)"
	fi

	printf '%s' "$line"
}

render_state() {
	local microphone_color
	local camera_color
	local location_color
	local text
	local tooltip
	local location_line

	microphone_color=$(color_for_status "$microphone_status")
	camera_color=$(color_for_status "$camera_status")
	location_color=$(color_for_status "$location_status")

	text="<span foreground=\"$microphone_color\">$MIC_ICON</span> <span foreground=\"$camera_color\">$CAMERA_ICON</span> <span foreground=\"$location_color\">$LOCATION_ICON</span>"

	if [[ $location_status == active ]]; then
		location_line="Location: active (requester hidden by GeoClue)"
	elif [[ $location_status == unavailable ]]; then
		location_line="Location: unavailable (GeoClue)"
	else
		location_line="Location: inactive"
	fi

	tooltip="$(format_sensor_line Microphone "$microphone_status" "$microphone_apps" "$microphone_errors")"
	tooltip+=$'\n'
	tooltip+="$(format_sensor_line Camera "$camera_status" "$camera_apps" "$camera_errors")"
	tooltip+=$'\n'
	tooltip+="$location_line"

	jq -nc \
		--arg text "$text" \
		--arg tooltip "$tooltip" \
		--arg microphone "microphone-$microphone_status" \
		--arg camera "camera-$camera_status" \
		--arg location "location-$location_status" \
		'{text: $text, tooltip: $tooltip, class: ["waybar-privacy", $microphone, $camera, $location]}'
}

emit_state() {
	local output

	output=$(render_state) || return
	if [[ $output != "$last_output" ]]; then
		printf '%s\n' "$output"
		last_output=$output
	fi
}

pipewire_event_feed() {
	local monitor_pid
	local monitor_fd
	local line
	local action=""
	local object_id=""
	local relevant=false
	local known_relevant=false
	local -A relevant_objects=()

	coproc PRIVACY_PW_MONITOR { exec pw-mon -N -o -a -p 2>/dev/null; }
	monitor_pid=$PRIVACY_PW_MONITOR_PID
	monitor_fd=${PRIVACY_PW_MONITOR[0]}
	trap 'kill "$monitor_pid" 2>/dev/null || true' EXIT INT TERM HUP

	while IFS= read -r -u "$monitor_fd" line; do
		case $line in
			added: | changed: | removed:)
				action=${line%:}
				object_id=""
				relevant=false
				;;
			*"id: "*)
				if [[ -z $object_id ]]; then
					object_id=${line##*id: }
					object_id=${object_id%%[!0-9]*}
				fi
				;;
			*"type: PipeWire:Interface:Node"* | *"type: PipeWire:Interface:Link"*)
				relevant=true
				;;
			"")
				known_relevant=false
				if [[ -n $object_id ]]; then
					known_relevant=${relevant_objects[$object_id]:-false}
				fi
				if [[ $action == removed ]]; then
					relevant=$known_relevant
					[[ -n $object_id ]] && unset 'relevant_objects[$object_id]'
				elif [[ -n $object_id ]]; then
					relevant_objects[$object_id]=$relevant
				fi

				if [[ $relevant == true && -n $object_id ]]; then
					printf 'pipewire\n'
				fi
				action=""
				object_id=""
				relevant=false
				;;
		esac
	done
}

geoclue_event_feed() {
	local monitor_pid
	local monitor_fd
	local line

	coproc PRIVACY_GEOCLUE_MONITOR {
		exec dbus-monitor --system \
			"type='signal',path='/org/freedesktop/GeoClue2/Manager',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'" \
			2>/dev/null
	}
	monitor_pid=$PRIVACY_GEOCLUE_MONITOR_PID
	monitor_fd=${PRIVACY_GEOCLUE_MONITOR[0]}
	trap 'kill "$monitor_pid" 2>/dev/null || true' EXIT INT TERM HUP

	while IFS= read -r -u "$monitor_fd" line; do
		printf 'geoclue\n'
	done
}

start_watchers() {
	if [[ -z $pipewire_watcher_pid ]] || ! kill -0 "$pipewire_watcher_pid" 2>/dev/null; then
		pipewire_watcher_pid=""
		if command -v pw-mon >/dev/null 2>&1; then
			pipewire_event_feed >&3 &
			pipewire_watcher_pid=$!
		fi
	fi

	if [[ -z $geoclue_watcher_pid ]] || ! kill -0 "$geoclue_watcher_pid" 2>/dev/null; then
		geoclue_watcher_pid=""
		if command -v dbus-monitor >/dev/null 2>&1; then
			geoclue_event_feed >&3 &
			geoclue_watcher_pid=$!
		fi
	fi
}

cleanup_watchers() {
	if [[ -n $pipewire_watcher_pid ]]; then
		kill "$pipewire_watcher_pid" 2>/dev/null || true
		wait "$pipewire_watcher_pid" 2>/dev/null || true
		pipewire_watcher_pid=""
	fi

	if [[ -n $geoclue_watcher_pid ]]; then
		kill "$geoclue_watcher_pid" 2>/dev/null || true
		wait "$geoclue_watcher_pid" 2>/dev/null || true
		geoclue_watcher_pid=""
	fi

	exec 3>&- 3<&- 2>/dev/null || true

	if [[ -n $event_fifo ]]; then
		rm -f "$event_fifo"
		event_fifo=""
	fi
	if [[ -n $event_dir ]]; then
		rmdir "$event_dir" 2>/dev/null || true
		event_dir=""
	fi
}

poll_events() {
	while true; do
		sleep "$POLL_INTERVAL"
		refresh_all
		emit_state
	done
}

watch_events() {
	local runtime_base=${XDG_RUNTIME_DIR:-/tmp}
	local event_received
	local last_recovery
	local drain_count
	local pipewire_watcher_healthy
	local geoclue_watcher_healthy

	refresh_all
	emit_state

	if ! event_dir=$(mktemp -d "$runtime_base/waybar-privacy.XXXXXX" 2>/dev/null); then
		poll_events
		return
	fi
	event_fifo=$event_dir/events
	if ! mkfifo "$event_fifo"; then
		rmdir "$event_dir" 2>/dev/null || true
		event_dir=""
		poll_events
		return
	fi

	exec 3<>"$event_fifo"
	trap 'cleanup_watchers' EXIT
	trap 'exit 0' INT TERM HUP
	start_watchers
	last_recovery=$SECONDS

	while true; do
		event_received=false
		if IFS= read -r -t "$POLL_INTERVAL" -u 3; then
			event_received=true
			for ((drain_count = 0; drain_count < 200; drain_count++)); do
				IFS= read -r -t 0.01 -u 3 || break
			done
		fi

		pipewire_watcher_healthy=false
		geoclue_watcher_healthy=false
		if [[ -n $pipewire_watcher_pid ]] && kill -0 "$pipewire_watcher_pid" 2>/dev/null; then
			pipewire_watcher_healthy=true
		fi
		if [[ -n $geoclue_watcher_pid ]] && kill -0 "$geoclue_watcher_pid" 2>/dev/null; then
			geoclue_watcher_healthy=true
		fi

		refresh_direct
		if [[ $event_received == true || $pipewire_watcher_healthy != true || $geoclue_watcher_healthy != true ]] \
			|| ((SECONDS - last_recovery >= RECOVERY_INTERVAL)); then
			query_pipewire
			query_location
			combine_state
			last_recovery=$SECONDS
		fi
		start_watchers
		emit_state
	done
}

normalize_intervals
normalize_colors

if ! command -v jq >/dev/null 2>&1; then
	printf '{"text":"<span foreground=\\\"%s\\\">%s</span> <span foreground=\\\"%s\\\">%s</span> <span foreground=\\\"%s\\\">%s</span>","tooltip":"Privacy status unavailable: jq is missing","class":["waybar-privacy","privacy-unavailable"]}\n' \
		"$UNAVAILABLE_COLOR" "$MIC_ICON" "$UNAVAILABLE_COLOR" "$CAMERA_ICON" "$UNAVAILABLE_COLOR" "$LOCATION_ICON"
	if [[ ${1:-} == --watch ]]; then
		while sleep 3600; do :; done
	fi
	exit 0
fi

if [[ ${1:-} == --watch ]]; then
	watch_events
else
	refresh_all
	emit_state
fi
