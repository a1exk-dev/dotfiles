#!/usr/bin/env bash

# Adapted from Hyprlock-Dots layout 18 playerctlock.sh.
# Original script is Spotify-only; this keeps the same interface and /tmp paths
# while using the active MPRIS player so Chromium/Firefox/etc. also work.

THUMB=/tmp/hyde-mpris
THUMB_BLURRED=/tmp/hyde-mpris-blurred

if [ $# -eq 0 ]; then
    echo "Usage: $0 --title | --arturl | --artist | --position | --length | --album | --source | --cover | --placeholder | --previous | --toggle | --next"
    exit 1
fi

active_player() {
    local player status fallback=""

    while IFS= read -r player; do
        [ -z "$player" ] && continue

        status=$(playerctl -p "$player" status 2>/dev/null || true)
        if [ "$status" = "Playing" ]; then
            echo "$player"
            return 0
        fi

        if [ -z "$fallback" ] && [ "$status" = "Paused" ]; then
            fallback="$player"
        fi
    done < <(playerctl -l 2>/dev/null || true)

    if [ -n "$fallback" ]; then
        echo "$fallback"
        return 0
    fi

    return 1
}

player=$(active_player || true)

get_metadata() {
    key=$1
    [ -z "$player" ] && return 1
    playerctl -p "$player" metadata --format "{{ $key }}" 2>/dev/null
}

get_source_info() {
    [ -z "$player" ] && return 0
    echo "$player"
}

get_position() {
    [ -z "$player" ] && return 1
    playerctl -p "$player" position 2>/dev/null
}

convert_length() {
    local length=$1
    local seconds=$((length / 1000000))
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    printf "%d:%02d" "$minutes" "$remaining_seconds"
}

convert_position() {
    local position=$1
    local seconds=${position%.*}
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    printf "%d:%02d" "$minutes" "$remaining_seconds"
}

fallback_thumb() {
    local out

    out=$(mktemp "${THUMB}.png.XXXXXX") || return 0

    if command -v magick >/dev/null 2>&1; then
        magick -size 640x640 xc:'#384B55' \
            -fill '#2E383C' -draw 'roundrectangle 64,64 576,576 60,60' \
            -fill '#1E2326' -draw 'circle 320,280 320,120' \
            -fill '#7FBBB3' -draw 'circle 320,280 320,165' \
            -fill '#384B55' -draw 'circle 320,280 320,230' \
            -fill '#D3C6AA' -draw 'roundrectangle 260,380 380,415 14,14' \
            -fill '#A7C080' -draw 'roundrectangle 220,455 420,485 12,12' \
            -fill '#859289' -draw 'roundrectangle 250,500 390,520 8,8' \
            "$out" 2>/dev/null || return 0
    else
        return 0
    fi

    mv "$out" "${THUMB}.png"
    printf 'placeholder\n' > "${THUMB}.inf"
}

fetch_thumb() (
    local artUrl cacheKey current tmp out blurred_out title artist length lockdir art_path art_stat

    lockdir="${THUMB}.lock"
    if ! mkdir "$lockdir" 2>/dev/null; then
        if [ -d "$lockdir" ] && [ $(( $(date +%s) - $(stat -c %Y "$lockdir" 2>/dev/null || echo 0) )) -gt 10 ]; then
            rmdir "$lockdir" 2>/dev/null || true
            mkdir "$lockdir" 2>/dev/null || return 0
        else
            return 0
        fi
    fi
    trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT

    fail_to_wallpaper() {
        rm -f "$tmp" "$out" "$blurred_out"
        fallback_thumb
        return 0
    }

    [ -z "$player" ] && { fallback_thumb; return 0; }

    artUrl=$(get_metadata "mpris:artUrl" || true)
    [ -n "$artUrl" ] || { fallback_thumb; return 0; }

    title=$(get_metadata "xesam:title" || true)
    artist=$(get_metadata "xesam:artist" || true)
    length=$(get_metadata "mpris:length" || true)
    art_stat=""
    if [[ "$artUrl" == file://* ]]; then
        art_path="${artUrl#file://}"
        art_stat=$(stat -c '%s:%Y' "$art_path" 2>/dev/null || true)
    fi
    cacheKey="$artUrl|$art_stat|$title|$artist|$length"

    current=$(cat "${THUMB}.inf" 2>/dev/null || true)
    if [ "$cacheKey" = "$current" ] && [ -s "${THUMB}.png" ]; then
        return 0
    fi

    tmp=$(mktemp "${THUMB}.src.XXXXXX") || return 0
    out=$(mktemp "${THUMB}.png.XXXXXX") || { rm -f "$tmp"; return 0; }
    blurred_out=$(mktemp "${THUMB_BLURRED}.png.XXXXXX") || { rm -f "$tmp" "$out"; return 0; }

    case "$artUrl" in
        file://*) cp "${artUrl#file://}" "$tmp" || fail_to_wallpaper ;;
        http://*|https://*) curl -fsSL "$artUrl" -o "$tmp" || fail_to_wallpaper ;;
        /*) cp "$artUrl" "$tmp" || fail_to_wallpaper ;;
        *) fail_to_wallpaper ;;
    esac

    [ -s "$tmp" ] || fail_to_wallpaper

    if command -v magick >/dev/null 2>&1; then
        magick "$tmp" -resize 640x640^ -gravity center -extent 640x640 "$out" 2>/dev/null || cp "$tmp" "$out"
        magick "$out" -blur 200x7 -resize 1920x^ -gravity center -extent 1920x1080\! "$blurred_out" 2>/dev/null || true
    else
        cp "$tmp" "$out"
    fi

    mv "$out" "${THUMB}.png"
    [ -s "$blurred_out" ] && mv "$blurred_out" "${THUMB_BLURRED}.png" || rm -f "$blurred_out"
    printf "%s\n" "$cacheKey" > "${THUMB}.inf"
    rm -f "$tmp"

    pkill -USR2 hyprlock 2>/dev/null || true
)

run_control() {
    local action="$1"

    [ -z "$player" ] && return 0

    if [ "$action" = "previous" ]; then
        playerctl -p "$player" position 0 2>/dev/null || true
        sleep 0.05
        playerctl -p "$player" previous 2>/dev/null || true
    else
        playerctl -p "$player" "$action" 2>/dev/null || true
    fi

    sleep 0.2
    fetch_thumb >/dev/null 2>&1 &
}

case "$1" in
--cover|--arturl)
    fetch_thumb
    echo "${THUMB}.png"
    ;;
--placeholder)
    fallback_thumb
    echo "${THUMB}.png"
    ;;
--title)
    fetch_thumb &
    title=$(get_metadata "xesam:title" || true)
    if [ -z "$title" ]; then
        echo "No media"
    else
        echo "${title:0:32}"
    fi
    ;;
--artist)
    fetch_thumb &
    artist=$(get_metadata "xesam:artist" || true)
    if [ -z "$artist" ]; then
        echo "Ready to unlock"
    else
        echo "${artist:0:32}"
    fi
    ;;
--position)
    fetch_thumb &
    position=$(get_position || true)
    length=$(get_metadata "mpris:length" || true)
    if [ -z "$position" ] || [ -z "$length" ]; then
        echo ""
    else
        position_formatted=$(convert_position "$position")
        length_formatted=$(convert_length "$length")
        echo "$position_formatted / $length_formatted"
    fi
    ;;
--length)
    length=$(get_metadata "mpris:length" || true)
    if [ -n "$length" ]; then
        convert_length "$length"
    fi
    ;;
--status)
    fetch_thumb &
    status=$(playerctl -p "$player" status 2>/dev/null || true)
    if [ "$status" = "Playing" ]; then
        echo ""
    elif [ "$status" = "Paused" ]; then
        echo ""
    else
        echo ""
    fi
    ;;
--album)
    album=$(get_metadata "xesam:album" || true)
    if [ -n "$album" ]; then
        echo "$album"
    fi
    ;;
--source)
    get_source_info
    ;;
--previous)
    run_control previous
    ;;
--toggle)
    run_control play-pause
    ;;
--next)
    run_control next
    ;;
*)
    echo "Invalid option: $1"
    echo "Usage: $0 --title | --arturl | --artist | --position | --length | --album | --source | --cover | --placeholder | --previous | --toggle | --next"
    exit 1
    ;;
esac
