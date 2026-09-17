#!/usr/bin/env bash

# OBS-owned state that the obs-theme and obs-scene packages touch outside their Stow links.
# OBS rewrites user.ini on exit, so every write here runs only while OBS is
# closed and changes single keys through a backup, a temporary file and a rename.

readonly OBS_SUPPORTED_SERIES=32.2
readonly OBS_THEME_ID=dev.dotfiles.omarchy
readonly OBS_STOCK_THEME_ID=com.obsproject.Yami

obs_config_dir() {
	printf '%s/obs-studio\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

obs_is_running() {
	pgrep -x obs >/dev/null 2>&1
}

# Prints the installed OBS version, such as 32.2.2, or fails.
obs_detected_version() {
	local output
	output=$(obs --version 2>/dev/null) || return 1
	output=${output##* }
	[[ $output =~ ^[0-9]+\.[0-9]+ ]] || return 1
	printf '%s\n' "$output"
}

# Shows the tested and detected OBS versions and asks for consent outside the
# tested series. Succeeds without asking inside it.
obs_confirm_version() {
	local detected
	detected=$(obs_detected_version) || detected=unknown
	printf 'Tested OBS: %s\n' "$OBS_SUPPORTED_SERIES"
	printf 'Detected OBS: %s\n' "$detected"
	version_in_series "$OBS_SUPPORTED_SERIES" "$detected" && return 0
	wizard_confirm 'Continue despite the OBS version mismatch?'
}

# Prints the value of one key in one section of an OBS ini file, or nothing.
obs_ini_value() {
	local file=$1 section=$2 key=$3
	awk -v section="[$section]" -v key="$key" '
		/^\[/ { inside = ($0 == section); next }
		inside && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
	' "$file"
}

# Prints a new backup path under ~/.config/obs-studio/backups/ for the named item.
obs_backup_path() {
	printf '%s/backups/%s.%s\n' "$(obs_config_dir)" "$1" "$(date -u +%Y%m%dT%H%M%S.%NZ)"
}

# Sets KEY=VALUE pairs in one user.ini section, adding the keys or the section
# when missing and leaving every other line as it was. An unchanged file is not
# rewritten; a changed one is backed up first.
obs_user_ini_set() {
	local section=$1
	shift
	local ini temporary backup
	ini=$(obs_config_dir)/user.ini
	temporary=$(mktemp "$(obs_config_dir)/.user.ini.XXXXXX") || return 1
	if ! awk -v section="[$section]" -v pairs="$(printf '%s\n' "$@")" '
		BEGIN {
			count = split(pairs, list, "\n")
			for (i = 1; i <= count; i++) {
				if (list[i] == "") continue
				key = substr(list[i], 1, index(list[i], "=") - 1)
				keys[++total] = key
				values[key] = substr(list[i], index(list[i], "=") + 1)
			}
		}
		function flush_missing(   i) {
			for (i = 1; i <= total; i++)
				if (!(keys[i] in written)) { print keys[i] "=" values[keys[i]]; written[keys[i]] = 1 }
		}
		{ lines[NR] = $0 }
		END {
			# The section ends at the next header; missing keys go after its last non-blank line.
			start = 0
			for (n = 1; n <= NR; n++) if (lines[n] == section) { start = n; break }
			if (start) {
				stop = NR
				for (n = start + 1; n <= NR; n++) if (lines[n] ~ /^\[/) { stop = n - 1; break }
				last = start
				for (n = start + 1; n <= stop; n++) if (lines[n] != "") last = n
			}
			for (n = 1; n <= NR; n++) {
				line = lines[n]
				if (start && n > start && n <= stop) {
					key = substr(line, 1, index(line, "=") - 1)
					if (index(line, "=") && (key in values)) { line = key "=" values[key]; written[key] = 1 }
				}
				print line
				if (start && n == last) flush_missing()
			}
			if (!start) {
				if (NR > 0 && lines[NR] != "") print ""
				print section
				flush_missing()
			}
		}
	' "$ini" >"$temporary"; then
		rm -f -- "$temporary"
		return 1
	fi
	if cmp -s -- "$temporary" "$ini"; then
		rm -f -- "$temporary"
		printf 'user.ini already has the requested [%s] values.\n' "$section"
		return 0
	fi
	backup=$(obs_backup_path user.ini)
	if ! mkdir -p -- "${backup%/*}" || ! cp --archive -- "$ini" "$backup"; then
		rm -f -- "$temporary"
		printf 'Error: could not back up %s.\n' "$ini" >&2
		return 1
	fi
	printf 'Backup created: %s\n' "$backup"
	if ! chmod --reference="$ini" -- "$temporary" || ! mv -f -- "$temporary" "$ini"; then
		rm -f -- "$temporary"
		printf 'Error: could not write %s; the backup is %s.\n' "$ini" "$backup" >&2
		return 1
	fi
	printf 'Updated %s [%s]: %s\n' "$ini" "$section" "$*"
}

# Selects the Omarchy theme and turns on live reloading after obs-theme is
# applied. A running OBS, a missing user.ini or a declined version consent
# skips the step without failing the apply.
obs_theme_select() {
	printf 'Phase: select the Omarchy OBS theme\n'
	if obs_is_running; then
		printf 'OBS is running, so user.ini was not changed. To select the Omarchy theme, close OBS, then choose Apply Stow packages again.\n'
		return 0
	fi
	if [[ ! -f $(obs_config_dir)/user.ini ]]; then
		printf 'OBS has no user.ini yet, so the theme was not selected. Start and close OBS once, then choose Apply Stow packages again.\n'
		return 0
	fi
	if ! obs_confirm_version; then
		printf 'No user.ini changes made.\n'
		return 0
	fi
	obs_user_ini_set Appearance "Theme=$OBS_THEME_ID" AutoReload=true || return 1
	printf 'Next step: run omarchy theme set once so the hook publishes Omarchy.ovt, then restart OBS so it finds the new theme file.\n'
}

obs_theme_prepare_remove() {
	if obs_is_running; then
		printf 'Error: OBS is running. Close OBS before removing obs-theme, because OBS rewrites user.ini on exit.\n' >&2
		return 1
	fi
	printf 'Plan: delete %s/themes/Omarchy.ovt\n' "$(obs_config_dir)"
	printf 'Plan: reset user.ini [Appearance] Theme to %s only if it is still %s\n' "$OBS_STOCK_THEME_ID" "$OBS_THEME_ID"
}

obs_theme_remove_state() {
	if obs_is_running; then
		printf 'Error: OBS started during removal; nothing was changed.\n' >&2
		return 1
	fi
	if [[ -f $(obs_config_dir)/user.ini && $(obs_ini_value "$(obs_config_dir)/user.ini" Appearance Theme) == "$OBS_THEME_ID" ]]; then
		obs_user_ini_set Appearance "Theme=$OBS_STOCK_THEME_ID" || return 1
	fi
	rm -f -- "$(obs_config_dir)/themes/Omarchy.ovt"
}

obs_scene_dir() {
	printf '%s/omarchy-scene\n' "$(obs_config_dir)"
}

obs_scene_prepare_remove() {
	if obs_is_running; then
		printf 'Error: OBS is running. Close OBS before removing obs-scene, because the copied collection uses its files.\n' >&2
		return 1
	fi
	printf 'Plan: delete %s, including title.txt, the avatar layers and the geometry file\n' "$(obs_scene_dir)"
}

obs_scene_remove_state() {
	if obs_is_running; then
		printf 'Error: OBS started during removal; nothing was changed.\n' >&2
		return 1
	fi
	rm -rf -- "$(obs_scene_dir)"
}

readonly OBS_RENDER_NODE=/dev/dri/renderD128
readonly OMARCHY_BAR_HEIGHT=26

# Encodes one frame with an ffmpeg VAAPI encoder on the default render node.
obs_trial_encode() {
	ffmpeg -nostdin -hide_banner -loglevel error -init_hw_device "vaapi=va:$OBS_RENDER_NODE" -filter_hw_device va \
		-f lavfi -i color=black:s=256x256:r=1 -frames:v 1 -vf format=nv12,hwupload -c:v "$1" -f null - >/dev/null 2>&1
}

# Collects the display and encoder facts a new OBS machine set needs, so a set
# can be written from the machine it targets.
obs_diagnose_machine() {
	local report encoder
	report=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/obs-diagnosis.txt
	mkdir -p -- "${report%/*}" || return 1
	{
		printf 'OBS machine diagnosis, %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf 'Omarchy: %s\n' "$(omarchy version 2>/dev/null || printf unknown)"
		printf 'OBS: %s\n' "$(obs_detected_version || printf 'not installed')"
		printf 'Monitors (bar crop = %s logical px x scale, rounded up):\n' "$OMARCHY_BAR_HEIGHT"
		local monitors
		if ! monitors=$(hyprctl monitors -j 2>/dev/null) || ! jq -r --argjson bar "$OMARCHY_BAR_HEIGHT" '
			.[] | (($bar * .scale) | ceil) as $crop
			| "  \(.name): \(.width)x\(.height) at scale \(.scale), bar crop \($crop) px",
			  ([1080, 1440][] as $h | ($h * 16 / 9) as $w
			  | (($h * .width / (.height - $crop)) | round) as $screen
			  | "    canvas \($w)x\($h): screen \($screen) px wide, strip width \([(($w - $screen) / 2 | floor), 0] | max) px")
		' <<<"$monitors"; then
			printf '  unavailable: hyprctl monitors failed\n'
		fi
		printf 'VAAPI trial encodes on %s:\n' "$OBS_RENDER_NODE"
		for encoder in h264_vaapi hevc_vaapi av1_vaapi; do
			if obs_trial_encode "$encoder"; then
				printf '  %s: ok\n' "$encoder"
			else
				printf '  %s: failed\n' "$encoder"
			fi
		done
	} | tee -- "$report"
	printf 'Report saved: %s\n' "$report"
}
