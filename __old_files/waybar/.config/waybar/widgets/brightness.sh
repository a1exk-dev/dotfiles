#!/bin/sh

action="${1:-get}"
device="${BRIGHTNESS_DEVICE:-intel_backlight}"
bar_sections="${BRIGHTNESS_BAR_SECTIONS:-10}"
step="${BRIGHTNESS_STEP:-5%}"
waybar_signal="${WAYBAR_BRIGHTNESS_SIGNAL:-1}"
base="/sys/class/backlight/$device"

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

find_backlight() {
	base="/sys/class/backlight/$device"

	if [ -r "$base/brightness" ] && [ -r "$base/max_brightness" ]; then
		return 0
	fi

	base=""

	for candidate in /sys/class/backlight/*; do
		[ -r "$candidate/brightness" ] && [ -r "$candidate/max_brightness" ] || continue
		base="$candidate"
		device="${candidate##*/}"
		return 0
	done

	return 1
}

read_percent() {
	find_backlight || exit 1

	IFS= read -r brightness < "$base/brightness" || exit 1
	IFS= read -r max_brightness < "$base/max_brightness" || exit 1

	case "$brightness" in
		"" | *[!0-9]*)
			exit 1
			;;
	esac

	case "$max_brightness" in
		"" | *[!0-9]*)
			exit 1
			;;
	esac

	if [ "$max_brightness" -le 0 ]; then
		exit 1
	fi

	percent=$((brightness * 100 / max_brightness))

	if [ "$percent" -lt 0 ]; then
		percent=0
	elif [ "$percent" -gt 100 ]; then
		percent=100
	fi
}

brightness_class() {
	if [ "$percent" -gt 70 ]; then
		printf 'brightness-high'
	elif [ "$percent" -gt 25 ]; then
		printf 'brightness-medium'
	else
		printf 'brightness-low'
	fi
}

print_icon() {
	read_percent
	class=$(brightness_class)

	printf '{"text":"󰛨","percentage":%s,"class":["waybar-icon","waybar-icon-brightness","%s"]}\n' "$percent" "$class"
}

print_status() {
	normalize_bar_sections
	read_percent

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

	class=$(brightness_class)
	printf '{"text":"%s","percentage":%s,"class":["waybar-progress","waybar-progress-brightness","%s"]}\n' "$bar" "$percent" "$class"
}

change_brightness() {
	command -v brightnessctl >/dev/null 2>&1 || exit 1
	find_backlight || exit 1

	case "$1" in
		up)
			brightnessctl -q -d "$device" set "${step}+" || exit 1
			;;
		down)
			brightnessctl -q -d "$device" set "${step}-" || exit 1
			;;
	esac
}

refresh_waybar() {
	case "$waybar_signal" in
		"" | *[!0-9]*)
			return 0
			;;
	esac

	command -v pkill >/dev/null 2>&1 || return 0
	pkill "-RTMIN+$waybar_signal" waybar 2>/dev/null || true
}

case "$action" in
	get)
		print_status
		;;
	icon)
		print_icon
		;;
	up)
		change_brightness up
		refresh_waybar
		;;
	down)
		change_brightness down
		refresh_waybar
		;;
	*)
		printf 'Usage: %s {get|icon|up|down}\n' "$0" >&2
		exit 64
		;;
esac
