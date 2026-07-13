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

apply_mode() {
	if is_plugged_in; then
		state="ac"
		mode="$ac_mode"
	else
		state="battery"
		mode="$battery_mode"
	fi

	[ "$state" = "$last_state" ] && return 0

	hyprctl eval "hl.monitor({ output = \"$monitor\", mode = \"$mode\", position = \"$position\", scale = \"$scale\" })" >/dev/null 2>&1 || return 1
	last_state="$state"
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

last_state=""
while :; do
	apply_mode
	sleep "$interval"
done
