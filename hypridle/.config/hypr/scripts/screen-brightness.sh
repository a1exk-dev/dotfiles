#!/bin/sh

state_file="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/hypridle-screen-brightness"

case "${1:-}" in
	dim)
		brightness=$(brightnessctl -c backlight get) || exit 1
		case "$brightness" in
			'' | *[!0-9]*) exit 1 ;;
		esac

		printf '%s\n' "$brightness" > "$state_file" || exit 1
		brightnessctl -q -c backlight set 10
		;;
	restore)
		[ -r "$state_file" ] || exit 0
		IFS= read -r brightness < "$state_file" || exit 1
		case "$brightness" in
			'' | *[!0-9]*) exit 1 ;;
		esac

		brightnessctl -q -c backlight set "$brightness" && rm -f "$state_file"
		;;
	*)
		printf 'Usage: %s {dim|restore}\n' "$0" >&2
		exit 2
		;;
esac
