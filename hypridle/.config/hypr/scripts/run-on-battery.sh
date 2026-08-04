#!/bin/sh

usage() {
	printf 'Usage: %s command [argument ...]\n' "$0" >&2
	exit 2
}

[ "$#" -ge 1 ] || usage

if ! command -v "$1" >/dev/null 2>&1; then
	printf '%s: command not found: %s\n' "$0" "$1" >&2
	exit 127
fi

for supply in /sys/class/power_supply/*; do
	[ -r "$supply/type" ] && [ -r "$supply/online" ] || continue

	IFS= read -r type < "$supply/type" || continue
	[ "$type" = "Battery" ] && continue

	IFS= read -r online < "$supply/online" || online=0
	[ "$online" = "1" ] && exit 0
done

exec "$@"
