#!/bin/sh

action="${1:-progress}"
battery_device="${BATTERY_DEVICE:-BAT0}"
bar_sections="${BATTERY_BAR_SECTIONS:-10}"
base="/sys/class/power_supply/$battery_device"

find_battery() {
	base="/sys/class/power_supply/$battery_device"

	if [ -r "$base/capacity" ] && [ -r "$base/status" ]; then
		return 0
	fi

	base=""

	for candidate in /sys/class/power_supply/*; do
		[ -r "$candidate/type" ] || continue
		IFS= read -r type < "$candidate/type" || continue
		[ "$type" = "Battery" ] || continue
		[ -r "$candidate/capacity" ] && [ -r "$candidate/status" ] || continue
		base="$candidate"
		battery_device="${candidate##*/}"
		return 0
	done

	return 1
}

read_number() {
	file=$1
	value=""

	[ -r "$file" ] || return 1
	IFS= read -r value < "$file" || return 1

	case "$value" in
		"" | *[!0-9]*)
			return 1
			;;
	esac

	printf '%s\n' "$value"
}

normalize_bar_sections() {
	case "$bar_sections" in
		"" | *[!0-9]*)
			bar_sections=10
			;;
	esac

	if [ "$bar_sections" -le 0 ]; then
		bar_sections=10
	fi
}

read_battery() {
	find_battery || exit 1

	capacity=$(read_number "$base/capacity") || exit 1
	IFS= read -r status < "$base/status" || exit 1

	if [ "$capacity" -lt 0 ]; then
		capacity=0
	elif [ "$capacity" -gt 100 ]; then
		capacity=100
	fi

	connected=false
	for supply in /sys/class/power_supply/*; do
		[ -r "$supply/type" ] && [ -r "$supply/online" ] || continue
		IFS= read -r type < "$supply/type" || continue
		[ "$type" = "Battery" ] && continue
		online=$(read_number "$supply/online") || online=0
		if [ "$online" -eq 1 ]; then
			connected=true
			break
		fi
	done
}

battery_level() {
	if [ "$capacity" -gt 75 ]; then
		printf '4'
	elif [ "$capacity" -gt 50 ]; then
		printf '3'
	elif [ "$capacity" -gt 25 ]; then
		printf '2'
	else
		printf '1'
	fi
}

battery_state() {
	level=$1

	if [ "$connected" = true ]; then
		printf '"battery-connected",'
	else
		printf '"battery-disconnected",'
	fi

	if [ "$status" = "Full" ]; then
		printf '"battery-full",'
	fi

	printf '"battery-level-%s"' "$level"
}

battery_icon() {
	level=$1

	if [ "$connected" = true ]; then
		case "$level" in
			1) printf '󰂆' ;;
			2) printf '󰂈' ;;
			3) printf '󰢞' ;;
			*) printf '󰂅' ;;
		esac
	else
		case "$level" in
			1) printf '󰁻' ;;
			2) printf '󰁾' ;;
			3) printf '󰂀' ;;
			*) printf '󰁹' ;;
		esac
	fi
}

battery_progress() {
	percent=$1
	normalize_bar_sections

	filled=$(((percent * bar_sections + 50) / 100))

	if [ "$filled" -lt 0 ]; then
		filled=0
	elif [ "$filled" -gt "$bar_sections" ]; then
		filled="$bar_sections"
	fi

	empty=$((bar_sections - filled))
	bar=""

	while [ "$filled" -gt 0 ]; do
		bar="${bar}█"
		filled=$((filled - 1))
	done

	while [ "$empty" -gt 0 ]; do
		bar="${bar}░"
		empty=$((empty - 1))
	done

	printf '%s' "$bar"
}

format_minutes() {
	minutes=$1

	if [ "$minutes" -le 0 ]; then
		printf '--'
		return
	fi

	hours=$((minutes / 60))
	minutes=$((minutes % 60))

	if [ "$hours" -gt 0 ]; then
		printf '%dh%02dm' "$hours" "$minutes"
	else
		printf '%dm' "$minutes"
	fi
}

battery_time() {
	power_now=$(read_number "$base/power_now") || power_now=0
	energy_now=$(read_number "$base/energy_now") || energy_now=0
	energy_full=$(read_number "$base/energy_full") || energy_full=0

	if [ "$status" = "Full" ]; then
		printf 'full'
		return
	fi

	if [ "$power_now" -le 0 ]; then
		printf '--'
		return
	fi

	if [ "$connected" = true ]; then
		remaining=$((energy_full - energy_now))
	else
		remaining=$energy_now
	fi

	if [ "$remaining" -le 0 ]; then
		printf '--'
		return
	fi

	format_minutes $(((remaining * 60 + power_now / 2) / power_now))
}

battery_tooltip() {
	time_left=$(battery_time)
	printf '%s %s%%' "$time_left" "$capacity"
}

print_icon() {
	read_battery
	level=$(battery_level)
	classes=$(battery_state "$level")
	icon=$(battery_icon "$level")
	tooltip=$(battery_tooltip)

	printf '{"text":"%s","tooltip":"%s","percentage":%s,"class":["waybar-icon","waybar-icon-battery",%s]}\n' "$icon" "$tooltip" "$capacity" "$classes"
}

print_progress() {
	read_battery
	level=$(battery_level)
	classes=$(battery_state "$level")
	bar=$(battery_progress "$capacity")
	tooltip=$(battery_tooltip)

	printf '{"text":"%s","tooltip":"%s","percentage":%s,"class":["waybar-progress","waybar-progress-battery",%s]}\n' "$bar" "$tooltip" "$capacity" "$classes"
}

case "$action" in
	icon)
		print_icon
		;;
	progress | get)
		print_progress
		;;
	*)
		printf 'Usage: %s {icon|progress}\n' "$0" >&2
		exit 64
		;;
esac
