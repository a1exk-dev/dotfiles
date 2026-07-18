#!/bin/sh

for supply in /sys/class/power_supply/*; do
	[ -r "$supply/type" ] && [ -r "$supply/online" ] || continue

	IFS= read -r type < "$supply/type" || continue
	[ "$type" = "Battery" ] && continue

	IFS= read -r online < "$supply/online" || online=0
	[ "$online" = "1" ] && exit 0
done

systemctl suspend
