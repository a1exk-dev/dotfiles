#!/bin/sh

action="${1:-get}"
device="${BRIGHTNESS_DEVICE:-intel_backlight}"
bar_sections="${BRIGHTNESS_BAR_SECTIONS:-10}"
step="${BRIGHTNESS_STEP:-5%}"
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

print_status() {
	normalize_bar_sections
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

	printf '{"text":"%s","percentage":%s}\n' "$bar" "$percent"
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

case "$action" in
	get)
		print_status
		;;
	up)
		change_brightness up
		;;
	down)
		change_brightness down
		;;
	*)
		printf 'Usage: %s {get|up|down}\n' "$0" >&2
		exit 64
		;;
esac
