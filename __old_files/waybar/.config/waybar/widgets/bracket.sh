#!/bin/sh

case "${1:-left}" in
	left | open)
		printf '{"text":"[","class":"waybar-bracket-left"}\n'
		;;
	right | close)
		printf '{"text":"]","class":"waybar-bracket-right"}\n'
		;;
	*)
		printf 'Usage: %s {left|right}\n' "$0" >&2
		exit 64
		;;
esac
