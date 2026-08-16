#!/bin/sh

dnd=$(swaync-client --get-dnd 2>/dev/null)
count=$(swaync-client --count 2>/dev/null)

case "$count" in
	"" | *[!0-9]*)
		count=0
		;;
esac

case "$dnd" in
	true)
		text="󰂛"
		class="notifications-disabled"
		tooltip="Notifications muted ($count)"
		;;
	false)
		if [ "$count" -gt 0 ]; then
			text="󰂞"
			class="notifications-active"
			tooltip="$count notifications"
		else
			text="󰂚"
			class="notifications-enabled"
			tooltip="Notifications"
		fi
		;;
	*)
		text="󰂚"
		class="notifications-unavailable"
		tooltip="SwayNC unavailable"
		;;
esac

printf '{"text":"%s","class":["%s"],"tooltip":"%s"}\n' "$text" "$class" "$tooltip"
