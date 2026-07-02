#!/usr/bin/env bash

set -u

ACTIVE_COLOR="${WAYBAR_WORKSPACE_ACTIVE_COLOR:-#dbbc7f}"
RELEVANT_EVENTS='^(workspace|workspacev2|focusedmon|focusedmonv2|createworkspace|createworkspacev2|destroyworkspace|destroyworkspacev2|moveworkspace|moveworkspacev2|renameworkspace)$'

run_hyprctl_json() {
	local command=$1
	local instance=${2:-}
	local output

	if [[ -n "$instance" ]]; then
		output=$(hyprctl -j --instance "$instance" "$command" 2>/dev/null) || return 1
	else
		output=$(hyprctl -j "$command" 2>/dev/null) || return 1
	fi

	jq -e . >/dev/null 2>&1 <<<"$output" || return 1
	printf '%s\n' "$output"
}

live_instance() {
	local instances

	instances=$(run_hyprctl_json instances) || return 1
	jq -r 'if type == "array" and length > 0 then max_by(.time // 0).instance // empty else empty end' <<<"$instances"
}

hyprctl_json() {
	local command=$1
	local instance
	local output

	if output=$(run_hyprctl_json "$command"); then
		printf '%s\n' "$output"
		return 0
	fi

	instance=$(live_instance 2>/dev/null || true)
	if [[ -n "$instance" ]]; then
		run_hyprctl_json "$command" "$instance"
		return
	fi

	return 1
}

print_unavailable() {
	printf '{"text":"","class":["waybar-workspaces-unavailable"]}\n'
}

print_workspaces() {
	local active_id=${1:-}
	local active_name=${2:-}
	local active_workspace
	local workspaces

	if [[ -z "$active_id" && -z "$active_name" ]]; then
		if ! active_workspace=$(hyprctl_json activeworkspace); then
			print_unavailable
			return 1
		fi

		active_id=$(jq -r '.id // empty' <<<"$active_workspace")
		active_name=$(jq -r '.name // empty' <<<"$active_workspace")
	fi

	if ! workspaces=$(hyprctl_json workspaces); then
		print_unavailable
		return 1
	fi

	jq -nc \
		--arg active_id "$active_id" \
		--arg active_name "$active_name" \
		--argjson workspaces "$workspaces" \
		--arg color "$ACTIVE_COLOR" '
		def pango_escape:
			tostring
			| gsub("&"; "&amp;")
			| gsub("<"; "&lt;")
			| gsub(">"; "&gt;")
			| gsub("\\\""; "&quot;");

		if ($workspaces | type) != "array" then
			{text: "", class: ["waybar-workspaces-unavailable"]}
		else
			($color | pango_escape) as $active_color
			| {
				text: (
					$workspaces
					| sort_by(.id // 0)
					| map(
						(.name // "" | pango_escape) as $name
						| if (($active_id != "" and ((.id // "") | tostring) == $active_id) or ($active_id == "" and $active_name != "" and ((.name // "") | tostring) == $active_name)) then
							"<span foreground=\"\($active_color)\"><b>[\($name)]</b></span>"
						else
							$name
						end
					)
					| join(" ")
				),
				class: ["waybar-workspaces"]
			}
		end
	' || {
		print_unavailable
		return 1
	}
}

print_workspaces_for_event() {
	local event=$1
	local payload=$2

	case "$event" in
		workspacev2)
			print_workspaces "${payload%%,*}"
			;;
		focusedmonv2)
			print_workspaces "${payload##*,}"
			;;
		workspace)
			print_workspaces "" "$payload"
			;;
		focusedmon)
			print_workspaces "" "${payload##*,}"
			;;
		*)
			print_workspaces
			;;
	esac
}

event_socket_path() {
	local runtime_dir=${XDG_RUNTIME_DIR:-}
	local instance
	local env_signature=${HYPRLAND_INSTANCE_SIGNATURE:-}
	local signatures=()
	local signature
	local path

	[[ -n "$runtime_dir" ]] || return 1

	instance=$(live_instance 2>/dev/null || true)
	if [[ -n "$instance" ]]; then
		signatures+=("$instance")
	fi

	if [[ -n "$env_signature" && "$env_signature" != "$instance" ]]; then
		signatures+=("$env_signature")
	fi

	for signature in "${signatures[@]}"; do
		path="$runtime_dir/hypr/$signature/.socket2.sock"
		if [[ -e "$path" ]]; then
			printf '%s\n' "$path"
			return 0
		fi
	done

	return 1
}

watch_events() {
	local path
	local line
	local event
	local payload

	print_workspaces

	while true; do
		if ! command -v socat >/dev/null 2>&1; then
			sleep 1
			print_workspaces
			continue
		fi

		path=$(event_socket_path 2>/dev/null || true)
		if [[ -z "$path" ]]; then
			sleep 1
			print_workspaces
			continue
		fi

		while IFS= read -r line; do
			event=${line%%>>*}
			payload=${line#*>>}
			if [[ "$event" =~ $RELEVANT_EVENTS ]]; then
				print_workspaces_for_event "$event" "$payload"
			fi
		done < <(socat - "UNIX-CONNECT:$path" 2>/dev/null)

		sleep 1
		print_workspaces
	done
}

if [[ ${1:-} == "--watch" ]]; then
	watch_events
else
	print_workspaces
fi
