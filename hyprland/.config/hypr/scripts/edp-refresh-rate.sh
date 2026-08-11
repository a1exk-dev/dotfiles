#!/bin/sh

monitor="${HYPR_EDP_MONITOR:-eDP-1}"
ac_mode="${HYPR_EDP_AC_MODE:-2880x1800@120}"
battery_mode="${HYPR_EDP_BATTERY_MODE:-2880x1800@60}"
position="${HYPR_EDP_POSITION:-auto}"
scale="${HYPR_EDP_SCALE:-auto}"
interval="${HYPR_EDP_POLL_INTERVAL:-5}"

is_plugged_in() {
	for supply in /sys/class/power_supply/*; do
		[ -r "$supply/type" ] && [ -r "$supply/online" ] || continue

		IFS= read -r type < "$supply/type" || continue
		[ "$type" = "Battery" ] && continue

		IFS= read -r online < "$supply/online" || online=0
		[ "$online" = "1" ] && return 0
	done

	return 1
}

select_mode() {
	if is_plugged_in; then
		state="ac"
		mode="$ac_mode"
	else
		state="battery"
		mode="$battery_mode"
	fi
}

set_mode() {
	hyprctl eval "hl.monitor({ output = \"$monitor\", mode = \"$1\", position = \"$position\", scale = \"$scale\" })" >/dev/null 2>&1
}

wait_for_mode() {
	expected_rate="${1##*@}"
	wait_attempts=50
	while [ "$wait_attempts" -gt 0 ]; do
		if hyprctl monitors -j 2>/dev/null | jq -e --arg monitor "$monitor" --argjson rate "$expected_rate" \
			'.[] | select(.name == $monitor and (((.refreshRate - $rate) | fabs) < 0.5))' >/dev/null; then
			return 0
		fi

		wait_attempts=$((wait_attempts - 1))
		sleep 0.1
	done

	return 1
}

apply_mode() {
	select_mode

	[ "$state" = "$last_state" ] && return 0

	set_mode "$mode" || return 1
	last_state="$state"
}

reset_mode() {
	select_mode
	if [ "$mode" = "$ac_mode" ]; then
		intermediate_mode="$battery_mode"
	else
		intermediate_mode="$ac_mode"
	fi

	attempts=10
	while [ "$attempts" -gt 0 ]; do
		if hyprctl monitors -j 2>/dev/null | jq -e --arg monitor "$monitor" \
			'.[] | select(.name == $monitor and .dpmsStatus == true and .disabled == false)' >/dev/null; then
			printf 'Resetting %s through %s, then restoring %s\n' "$monitor" "$intermediate_mode" "$mode"
			if set_mode "$intermediate_mode" && wait_for_mode "$intermediate_mode"; then
				if set_mode "$mode" && wait_for_mode "$mode"; then
					printf 'Reset of %s completed at %s\n' "$monitor" "$mode"
					return 0
				fi
			fi

			set_mode "$mode"
		fi

		attempts=$((attempts - 1))
		sleep 0.25
	done

	printf 'Failed to reset %s after resume\n' "$monitor" >&2
	return 1
}

resume_reset() {
	reset_mode || true
	printf 'Waiting for the resumed display stack to settle\n'
	sleep 5
	reset_mode
}

case "$interval" in
	"" | *[!0-9]*)
		interval=5
		;;
esac

if [ "$interval" -le 0 ]; then
	interval=5
fi

if [ "$1" = "--once" ]; then
	apply_mode
	exit $?
fi

if [ "$1" = "--reset" ]; then
	reset_mode
	exit $?
fi

if [ "$1" = "--resume" ]; then
	resume_reset
	exit $?
fi

last_state=""
while :; do
	apply_mode
	sleep "$interval"
done
