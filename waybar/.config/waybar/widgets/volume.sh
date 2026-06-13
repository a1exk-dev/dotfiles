#!/bin/sh

action="${1:-get}"
bar_sections="${VOLUME_BAR_SECTIONS:-10}"
step="${VOLUME_STEP:-5%}"
max_volume="${VOLUME_MAX:-1}"
waybar_signal="${WAYBAR_VOLUME_SIGNAL:-2}"
percent=0
muted=false

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

read_volume_pactl() {
	command -v pactl >/dev/null 2>&1 || return 1

	volume_output=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null) || return 1
	percent=""

	for field in $volume_output; do
		case "$field" in
			*%)
				percent=${field%\%}
				break
				;;
		esac
	done

	case "$percent" in
		"" | *[!0-9]*)
			return 1
			;;
	esac

	mute_output=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null) || return 1
	case "$mute_output" in
		*yes*) muted=true ;;
		*) muted=false ;;
	esac
}

read_volume_wpctl() {
	command -v wpctl >/dev/null 2>&1 || return 1

	volume_output=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || return 1
	set -- $volume_output
	value=$2

	[ -n "$value" ] || return 1

	case "$volume_output" in
		*MUTED*) muted=true ;;
		*) muted=false ;;
	esac

	whole=${value%%.*}
	if [ "$whole" = "$value" ]; then
		frac=0
	else
		frac=${value#*.}
		frac=${frac%%[!0-9]*}
	fi

	[ -n "$whole" ] || whole=0
	[ -n "$frac" ] || frac=0

	case "$whole$frac" in
		*[!0-9]*)
			return 1
			;;
	esac

	if [ ${#frac} -eq 1 ]; then
		frac=${frac}0
	elif [ ${#frac} -gt 2 ]; then
		frac=${frac%"${frac#??}"}
	fi

	percent=$((whole * 100 + frac))
}

read_volume() {
	read_volume_pactl || read_volume_wpctl || exit 1
}

volume_class() {
	if [ "$muted" = true ]; then
		printf 'volume-muted'
	elif [ "$percent" -eq 0 ]; then
		printf 'volume-off'
	elif [ "$percent" -gt 80 ]; then
		printf 'volume-high'
	elif [ "$percent" -gt 60 ]; then
		printf 'volume-medium-high'
	elif [ "$percent" -gt 30 ]; then
		printf 'volume-medium'
	else
		printf 'volume-low'
	fi
}

volume_icon() {
	if [ "$muted" = true ]; then
		printf '󰖁'
	elif [ "$percent" -eq 0 ]; then
		printf '󰖁'
	elif [ "$percent" -gt 50 ]; then
		printf '󰕾'
	else
		printf '󰖀'
	fi
}

print_icon() {
	read_volume
	class=$(volume_class)
	icon=$(volume_icon)

	if [ "$muted" = true ]; then
		tooltip="Unmute"
	else
		tooltip="Mute"
	fi

	printf '{"text":"%s","tooltip":"%s","percentage":%s,"class":["waybar-icon","waybar-icon-volume","%s"]}\n' "$icon" "$tooltip" "$percent" "$class"
}

print_status() {
	normalize_bar_sections
	read_volume

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

	class=$(volume_class)
	printf '{"text":"%s","percentage":%s,"class":["waybar-progress","waybar-progress-volume","%s"]}\n' "$bar" "$percent" "$class"
}

change_volume() {
	case "$1" in
		up)
			if command -v wpctl >/dev/null 2>&1; then
				wpctl set-volume -l "$max_volume" @DEFAULT_AUDIO_SINK@ "${step}+" || exit 1
			else
				command -v pactl >/dev/null 2>&1 || exit 1
				pactl set-sink-volume @DEFAULT_SINK@ "+${step}" || exit 1
			fi
			;;
		down)
			if command -v wpctl >/dev/null 2>&1; then
				wpctl set-volume @DEFAULT_AUDIO_SINK@ "${step}-" || exit 1
			else
				command -v pactl >/dev/null 2>&1 || exit 1
				pactl set-sink-volume @DEFAULT_SINK@ "-${step}" || exit 1
			fi
			;;
		mute)
			if command -v wpctl >/dev/null 2>&1; then
				wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle || exit 1
			else
				command -v pactl >/dev/null 2>&1 || exit 1
				pactl set-sink-mute @DEFAULT_SINK@ toggle || exit 1
			fi
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
		change_volume up
		refresh_waybar
		;;
	down)
		change_volume down
		refresh_waybar
		;;
	mute)
		change_volume mute
		refresh_waybar
		;;
	*)
		printf 'Usage: %s {get|icon|up|down|mute}\n' "$0" >&2
		exit 64
		;;
esac
