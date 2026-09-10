#!/usr/bin/env bash

set -u

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

seed_reviewed_baseline() {
	local target=$1
	mkdir -p "$target"
	cp -a "$SOURCE_REPO/config/hyprland/.config/hypr/." "$target/"
	cp /usr/share/omarchy/config/hypr/hyprland.lua /usr/share/omarchy/config/hypr/input.lua "$target/"
}

apply_noop_remove_round_trip() (
	set -euo pipefail
	local root home call_log baseline_digest after_digest before_calls after_calls backup baseline_definition seams_definition
	local changed_artifact rebuilt_artifact unload_line unlink_line registry_present registry_delay health_build
	root=$(mktemp -d)
	trap 'chmod -R u+w -- "$root" 2>/dev/null || true; rm -rf -- "$root"' EXIT
	home=$root/home
	call_log=$root/calls
	mkdir -p "$home/.config/omarchy"
	seed_reviewed_baseline "$home/.config/hypr"
	chmod 0750 "$home/.config/hypr"
	touch -d '@1700000000' "$home/.config/hypr"
	cat >"$home/.config/omarchy/shell.json" <<'JSON'
{"version":1,"bar":{"layout":{"center":[{"id":"omarchy.clock"},{"id":"omarchy.keyboard-layout","format":"stock"},{"id":"omarchy.weather"}],"left":[],"right":[]}}}
JSON

	export HOME=$home
	export XDG_CONFIG_HOME=$home/.config
	export XDG_DATA_HOME=$home/.local/share
	export XDG_STATE_HOME=$home/.local/state
	export DOTFILES_UI=bash
	export DOTFILES_TEST_OMARCHY_VERSION=4.0.2-1
	: >"$call_log"
	printf '0\n' >"$root/group"
	printf '4.0.2-1\n' >"$root/omarchy-version"
	printf 'false\n' >"$root/registry-present"

	omarchy() {
		printf 'omarchy %s\n' "$*" >>"$call_log"
		case "$*" in
			'plugin list --json')
				if [[ -f $root/registry-delay ]]; then
					registry_delay=$(command cat "$root/registry-delay")
					if ((registry_delay > 0)); then printf '%s\n' "$((registry_delay - 1))" >"$root/registry-delay"
					else
						[[ -L $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout ]] && printf 'true\n' >"$root/registry-present" || printf 'false\n' >"$root/registry-present"
						command rm -f "$root/registry-delay"
					fi
				fi
				registry_present=$(command cat "$root/registry-present")
				jq -n --argjson present "$registry_present" \
					--argjson enabled "$(jq 'any(.bar.layout[][]; .id == "dotfiles.keyboard-layout")' "$HOME/.config/omarchy/shell.json")" \
					'$present | if . then [{id:"dotfiles.keyboard-layout",name:"Flag keyboard layout",enabled:$enabled,kinds:["bar-widget"],firstParty:false,clonedFrom:"omarchy.keyboard-layout"}] else [] end'
				;;
			'shell shell rescanPlugins'|'restart shell') printf '2\n' >"$root/registry-delay" ;;
			'plugin enable dotfiles.keyboard-layout --section right --index 0')
				local temporary=$HOME/.config/omarchy/shell.json.tmp
				jq '
					def eid: if type == "object" then .id else . end;
					([.bar.layout | to_entries[] as $s | $s.value[] | select(eid == "dotfiles.keyboard-layout" or eid == "omarchy.keyboard-layout")][0] // {id:"dotfiles.keyboard-layout"}) as $entry |
					(.bar.layout.left,.bar.layout.center,.bar.layout.right) |= map(select((eid != "dotfiles.keyboard-layout") and (eid != "omarchy.keyboard-layout"))) |
					.bar.layout.right = [($entry | .id = "dotfiles.keyboard-layout")] + .bar.layout.right
				' "$HOME/.config/omarchy/shell.json" >"$temporary" && command mv "$temporary" "$HOME/.config/omarchy/shell.json"
				;;
			'bar move dotfiles.keyboard-layout --section right --index 0')
				local temporary=$HOME/.config/omarchy/shell.json.tmp
				jq '([.bar.layout[][] | select(.id == "dotfiles.keyboard-layout")][0]) as $entry | (.bar.layout.left,.bar.layout.center,.bar.layout.right) |= map(select(.id != "dotfiles.keyboard-layout")) | .bar.layout.right = [$entry] + .bar.layout.right' \
					"$HOME/.config/omarchy/shell.json" >"$temporary" && command mv "$temporary" "$HOME/.config/omarchy/shell.json"
				;;
			'plugin disable dotfiles.keyboard-layout')
				local temporary=$HOME/.config/omarchy/shell.json.tmp
				jq '(.bar.layout.left[],.bar.layout.center[],.bar.layout.right[] | select(.id == "dotfiles.keyboard-layout")).id = "omarchy.keyboard-layout"' \
					"$HOME/.config/omarchy/shell.json" >"$temporary" && command mv "$temporary" "$HOME/.config/omarchy/shell.json"
				;;
			'plugin disable omarchy.keyboard-layout')
				local temporary=$HOME/.config/omarchy/shell.json.tmp
				jq '(.bar.layout.left,.bar.layout.center,.bar.layout.right) |= map(select(.id != "omarchy.keyboard-layout"))' \
					"$HOME/.config/omarchy/shell.json" >"$temporary" && command mv "$temporary" "$HOME/.config/omarchy/shell.json"
				;;
			'bar move omarchy.keyboard-layout --section center --index 1')
				local temporary=$HOME/.config/omarchy/shell.json.tmp
				jq '([.bar.layout[][] | select(.id == "omarchy.keyboard-layout")][0]) as $entry | (.bar.layout.left,.bar.layout.center,.bar.layout.right) |= map(select(.id != "omarchy.keyboard-layout")) | .bar.layout.center = (.bar.layout.center[0:1] + [$entry] + .bar.layout.center[1:])' \
					"$HOME/.config/omarchy/shell.json" >"$temporary" && command mv "$temporary" "$HOME/.config/omarchy/shell.json"
				;;
			*) case ${1-} in
			version) command cat "$root/omarchy-version" ;;
			pkg) [[ ${2-} == present ]] ;;
			shell)
				if [[ ${2-} == shell && ${3-} == ping ]]; then
					printf 'ok\n'
				elif [[ ${2-} == shell && ${3-} == debugBarGeometry ]]; then
					printf '[{"id":"dotfiles.keyboard-layout","monitor":"test-monitor","width":24,"height":26,"visible":true,"itemVisible":true,"itemWidth":24,"itemHeight":26}]\n'
				else
					return 1
				fi
				;;
			*) return 1 ;;
		esac ;;
		esac
	}
	hyprctl() {
		printf 'hyprctl %s\n' "$*" >>"$call_log"
		case "$*" in
			version) command /usr/bin/hyprctl version ;;
			'-j getoption misc:disable_autoreload') printf '{"bool":false}\n' ;;
			'-j plugin list')
				if [[ -e $root/force-loaded-plugin || ( ! -e $root/plugin-unloaded && -f $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua && -L $HOME/.config/hypr/hyprland.lua ) ]]; then
					local artifact metadata
					jq -n '[{name:"Input Languages",author:"dotfiles",version:"test"}]'
				else
					printf '[]\n'
				fi
				;;
			'-j inputlanguages')
				[[ -f $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua && -L $HOME/.config/hypr/hyprland.lua ]] || return 1
				local artifact metadata healthy=true physical='["test-keyboard"]'
				artifact=$(cut -d'"' -f2 "$XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua")
				metadata=$(dirname -- "$artifact")/build.json
				health_build=$(jq -r .build_id "$metadata")
				if [[ -f $root/health-build ]]; then health_build=$(command cat "$root/health-build"); fi
				if [[ -f $root/no-physical-keyboards ]]; then healthy=false; physical='[]'; fi
				jq -n --arg build "$health_build" --arg source "$(jq -r .source_id "$metadata")" --arg compatibility "$(jq -r .compatibility_hash "$metadata")" --argjson group "$(command cat "$root/group")" \
					--argjson healthy "$healthy" --argjson physical "$physical" \
					'{healthy:$healthy,build_id:$build,source_id:$source,compatibility_hash:$compatibility,canonical_group:$group,physical_keyboards:$physical,excluded_keyboards:["test-button"]}'
				;;
			'-j devices')
				jq -n --argjson group "$(command cat "$root/group")" '{keyboards:[{name:"test-keyboard",layout:"us,ru",variant:",",active_layout_index:$group,active_keymap:(if $group == 0 then "English (US)" else "Russian" end)}]}'
				;;
			'-j inputlanguagesreset 0') printf '0\n' >"$root/group"; printf '{"ok":true,"canonical_group":0}\n' ;;
			'-j inputlanguagesreset 1') printf '1\n' >"$root/group"; printf '{"ok":true,"canonical_group":1}\n' ;;
			'plugin unload '*) command touch "$root/plugin-unloaded" ;;
			'keyword misc:disable_autoreload true'|'keyword misc:disable_autoreload false') return 0 ;;
			reload)
				if [[ -f $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua && -L $HOME/.config/hypr/hyprland.lua ]]; then command rm -f "$root/plugin-unloaded"; else command touch "$root/plugin-unloaded"; fi
				;;
			configerrors) return 0 ;;
			*) return 1 ;;
			esac
	}
	mv() {
		local target=${!#}
		if [[ $target == "$XDG_DATA_HOME/dotfiles/input-languages/removals/"* ]]; then
			[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/active.json && ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json && -f $XDG_STATE_HOME/dotfiles/input-languages/remove-cleanup.json ]] || return 75
			command touch "$root/artifact-staged-after-commit"
		fi
		command mv "$@"
	}
	stow() { printf 'stow %s\n' "$*" >>"$call_log"; command /usr/bin/stow "$@"; }
	export -f omarchy hyprctl mv stow

	# shellcheck source=../lib/dotfiles/core.sh
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	# shellcheck source=../lib/dotfiles/input-languages.sh
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	# shellcheck source=../lib/dotfiles/packages.sh
	source "$SOURCE_REPO/lib/dotfiles/packages.sh"
	# Keep this baseline round trip on the immutable version-2 implementation;
	# public version dispatch and expansion are covered by the version-3 suite.
	apply_input_languages() { apply_input_languages_v2 "$@"; }
	remove_input_languages() { remove_input_languages_v2 "$@"; }

	baseline_digest=$(input_languages_tree_digest "$HOME/.config/hypr")
	apply_input_languages --yes >/dev/null || return 1
	[[ -L $HOME/.config/hypr/hyprland.lua ]] || return 1
	[[ -L $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout ]] || return 1
	widget_source=$(jq -r .widget_source "$XDG_STATE_HOME/dotfiles/input-languages/active.json")
	[[ $(readlink "$XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout") == "$widget_source" && -d $widget_source ]] || return 1
	[[ $(find "$widget_source" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort) == $'KeyboardLayout.qml\nKeyboardLayoutModel.js\nmanifest.json' ]] || return 1
	[[ -z $(find "$widget_source" -type l -print -quit) ]] || return 1
	jq -e '.bar.layout.right[0] == {id:"dotfiles.keyboard-layout",format:"stock"} and .bar.layout.center == [{id:"omarchy.clock"},{id:"omarchy.weather"}]' "$HOME/.config/omarchy/shell.json" >/dev/null || return 1
	[[ -f $XDG_STATE_HOME/dotfiles/input-languages/active.json ]] || return 1
	backup=$(jq -r .backup "$XDG_STATE_HOME/dotfiles/input-languages/active.json")
	[[ $(grep -c '^hyprctl reload$' "$call_log") -eq 1 ]] || return 1
	[[ $(grep -c '^hyprctl -j inputlanguagesreset 0$' "$call_log") -eq 1 ]] || return 1
	printf 'foreign canary\n' >"$root/foreign-canary"
	jq --arg foreign "$root/foreign-canary" '.backup = $foreign' "$XDG_STATE_HOME/dotfiles/input-languages/active.json" >"$root/forged-active.json"
	chmod 600 "$root/forged-active.json"
	if input_languages_validate_active_file "$root/forged-active.json"; then return 1; fi
	jq --arg foreign "$root/foreign-canary" '.artifact = $foreign' "$XDG_STATE_HOME/dotfiles/input-languages/active.json" >"$root/forged-active.json"
	chmod 600 "$root/forged-active.json"
	if input_languages_validate_active_file "$root/forged-active.json"; then return 1; fi
	[[ $(<"$root/foreign-canary") == 'foreign canary' ]] || return 1

	before_calls=$(wc -l <"$call_log")
	apply_input_languages --yes >/dev/null || return 1
	after_calls=$(wc -l <"$call_log")
	# Exact no-op performs read-only inspection calls only, with no reload or reset.
	((after_calls > before_calls)) || return 1
	[[ $(grep -c '^hyprctl reload$' "$call_log") -eq 1 ]] || return 1
	[[ $(grep -c '^hyprctl -j inputlanguagesreset 0$' "$call_log") -eq 1 ]] || return 1
	[[ $(jq -r .backup "$XDG_STATE_HOME/dotfiles/input-languages/active.json") == "$backup" ]] || return 1
	# A receipt from the prior placement contract is migrated without losing ownership.
	jq '([.bar.layout.right[] | select(.id == "dotfiles.keyboard-layout")][0]) as $entry | .bar.layout.right |= map(select(.id != "dotfiles.keyboard-layout")) | .bar.layout.center += [$entry]' \
		"$HOME/.config/omarchy/shell.json" >"$HOME/.config/omarchy/shell.updated"
	mv "$HOME/.config/omarchy/shell.updated" "$HOME/.config/omarchy/shell.json"
	jq '.widget_section = "center" | .widget_index = 2' "$XDG_STATE_HOME/dotfiles/input-languages/active.json" >"$root/legacy-active.json"
	mv "$root/legacy-active.json" "$XDG_STATE_HOME/dotfiles/input-languages/active.json"
	chmod 600 "$XDG_STATE_HOME/dotfiles/input-languages/active.json"
	apply_input_languages --yes >/dev/null || return 1
	jq -e '.bar.layout.right[0] == {id:"dotfiles.keyboard-layout",format:"stock"} and .bar.layout.center == [{id:"omarchy.clock"},{id:"omarchy.weather"}]' "$HOME/.config/omarchy/shell.json" >/dev/null || return 1
	[[ $(grep -c '^hyprctl reload$' "$call_log") -eq 2 ]] || return 1
	[[ $(grep -c '^hyprctl -j inputlanguagesreset 0$' "$call_log") -eq 2 ]] || return 1

	# A linked-state link repair must not replace the original migration backup.
	rm "$XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout"
	printf '1\n' >"$root/group"
	apply_input_languages --yes >/dev/null || return 1
	[[ $(jq -r .backup "$XDG_STATE_HOME/dotfiles/input-languages/active.json") == "$backup" ]] || return 1
	[[ -L $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout ]] || return 1
	[[ $(command cat "$root/group") == 0 ]] || return 1
	[[ $(grep -c '^hyprctl reload$' "$call_log") -eq 3 ]] || return 1
	cp "$XDG_STATE_HOME/dotfiles/input-languages/active.json" "$root/approved-active.json"
	wizard_confirm() {
		jq '.transaction_id = "20260906T120000.000000000Z-12345-abcd"' "$XDG_STATE_HOME/dotfiles/input-languages/active.json" >"$root/changed-active.json"
		chmod 600 "$root/changed-active.json"
		command mv "$root/changed-active.json" "$XDG_STATE_HOME/dotfiles/input-languages/active.json"
		return 0
	}
	if remove_input_languages >"$root/stale-remove.out" 2>&1; then return 1; fi
	grep -Fq 'active receipt changed after confirmation' "$root/stale-remove.out" || return 1
	[[ -L $HOME/.config/hypr/hyprland.lua && ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json ]] || return 1
	cp "$root/approved-active.json" "$XDG_STATE_HOME/dotfiles/input-languages/active.json"
	chmod 600 "$XDG_STATE_HOME/dotfiles/input-languages/active.json"

	# Remove blocks rather than deleting the source of a changed owned custom entry.
	jq '(.bar.layout.right[] | select(.id == "dotfiles.keyboard-layout")).label = "changed"' \
		"$HOME/.config/omarchy/shell.json" >"$HOME/.config/omarchy/shell.updated"
	mv "$HOME/.config/omarchy/shell.updated" "$HOME/.config/omarchy/shell.json"
	if remove_input_languages --yes >"$root/changed-widget-remove.out" 2>&1; then return 1; fi
	grep -Fq 'flag widget changed or moved' "$root/changed-widget-remove.out" || return 1
	[[ -L $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout ]] || return 1
	jq 'del((.bar.layout.right[] | select(.id == "dotfiles.keyboard-layout")).label)' "$HOME/.config/omarchy/shell.json" >"$HOME/.config/omarchy/shell.updated"
	mv "$HOME/.config/omarchy/shell.updated" "$HOME/.config/omarchy/shell.json"
	changed_artifact=$(jq -r .artifact "$XDG_STATE_HOME/dotfiles/input-languages/active.json")
	chmod u+w "$changed_artifact"
	printf 'drift\n' >>"$changed_artifact"
	apply_input_languages --yes >/dev/null || return 1
	rebuilt_artifact=$(jq -r .artifact "$XDG_STATE_HOME/dotfiles/input-languages/active.json")
	[[ $rebuilt_artifact != "$changed_artifact" && -f $changed_artifact ]] || return 1
	input_languages_validate_active_file "$XDG_STATE_HOME/dotfiles/input-languages/active.json" || return 1
	printf '5.0.0-1\n' >"$root/omarchy-version"
	DOTFILES_TEST_OMARCHY_VERSION=5.0.0-1
	local unsupported_status
	unsupported_status=$(input_languages_status)
	grep -Fq 'Overall: unsupported' <<<"$unsupported_status" || return 1
	grep -Fq 'choose Remove for receipt-backed removal' <<<"$unsupported_status" || return 1
	if apply_input_languages --yes >"$root/unsupported-apply.out" 2>&1; then return 1; fi
	grep -Fq 'outside supported range' "$root/unsupported-apply.out" || return 1
	[[ -L $HOME/.config/hypr/hyprland.lua ]] || return 1
	printf '%064d\n' 0 >"$root/health-build"
	if remove_input_languages --yes >"$root/mismatched-plugin-remove.out" 2>&1; then return 1; fi
	grep -Fq 'loaded Input Languages build does not match' "$root/mismatched-plugin-remove.out" || return 1
	[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json ]] || return 1
	command rm "$root/health-build"
	seams_definition=$(declare -f input_languages_shell_seams_compatible)
	input_languages_shell_seams_compatible() { return 1; }
	if remove_input_languages --yes >"$root/changed-seam-remove.out" 2>&1; then return 1; fi
	grep -Fq 'Shell mutation seams differ' "$root/changed-seam-remove.out" || return 1
	[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json ]] || return 1
	eval "$seams_definition"

	baseline_definition=$(declare -f input_languages_baseline_matches)
	input_languages_baseline_matches() { return 1; }
	rm() {
		local target=${!#}
		if [[ ${1-} == -rf && $target == "$XDG_DATA_HOME/dotfiles/input-languages/removals/"*/dotfiles.keyboard-layout ]]; then return 74; fi
		command rm "$@"
	}
	if remove_input_languages --yes >"$root/interrupted-cleanup.out" 2>&1; then return 1; fi
	grep -Fq 'Compatibility notice: supported Omarchy 4.0.2 through 4.x; detected 5.0.0-1.' "$root/interrupted-cleanup.out" || return 1
	input_languages_inspect
	if [[ $INPUT_LANGUAGES_CLEANUP_STATE != valid || $INPUT_LANGUAGES_ACTIVE_STATE != absent || $INPUT_LANGUAGES_PENDING_STATE != absent ]]; then
		command cat "$root/interrupted-cleanup.out" >&2
		return 1
	fi
	unset -f rm
	remove_input_languages --recovery-approved >/dev/null || return 1
	eval "$baseline_definition"
	[[ -f $HOME/.config/hypr/hyprland.lua && ! -L $HOME/.config/hypr/hyprland.lua ]] || return 1
	after_digest=$(input_languages_tree_digest "$HOME/.config/hypr")
	[[ $after_digest == "$baseline_digest" ]] || return 1
	[[ $(stat -c '%a|%Y' "$HOME/.config/hypr") == '750|1700000000' ]] || return 1
	[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/active.json ]] || return 1
	[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/remove-cleanup.json ]] || return 1
	[[ -d $XDG_STATE_HOME/dotfiles/input-languages/archive ]] || return 1
	[[ ! -d $XDG_DATA_HOME/dotfiles/input-languages/removals || -z $(find "$XDG_DATA_HOME/dotfiles/input-languages/removals" -mindepth 1 -maxdepth 1 -print -quit) ]] || return 1
	[[ -f $root/artifact-staged-after-commit ]] || return 1
	jq -e '.bar.layout.center[1] == {id:"omarchy.keyboard-layout",format:"stock"} and .bar.layout.center[2].id == "omarchy.weather"' "$HOME/.config/omarchy/shell.json" >/dev/null || return 1
	[[ ! -e $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout && ! -L $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout ]] || return 1
	unload_line=$(grep -n '^hyprctl plugin unload ' "$call_log" | tail -n 1 | cut -d: -f1)
	unlink_line=$(grep -n '^stow --no-folding --delete ' "$call_log" | tail -n 1 | cut -d: -f1)
	[[ -n $unload_line && -n $unlink_line && $unload_line -lt $unlink_line ]] || return 1
	# A complete second round trip records and restores an absent stock widget.
	jq '.bar.layout.center |= map(select(.id != "omarchy.keyboard-layout"))' "$HOME/.config/omarchy/shell.json" >"$HOME/.config/omarchy/shell.updated"
	mv "$HOME/.config/omarchy/shell.updated" "$HOME/.config/omarchy/shell.json"
	printf '4.0.2-1\n' >"$root/omarchy-version"
	DOTFILES_TEST_OMARCHY_VERSION=4.0.2-1
	local prepared_output
	prepared_output=$(apply_input_languages --yes --packages-prepared) || return 1
	[[ $prepared_output != *'Inspected: Hyprland tree='* && $prepared_output != *'Plan: fixed desktop layouts'* ]] || return 1
	[[ $(jq -r .prior_stock_present "$XDG_STATE_HOME/dotfiles/input-languages/active.json") == false ]] || return 1
	jq -e '.bar.layout.center == [{id:"omarchy.clock"},{id:"omarchy.weather"}] and .bar.layout.right == [{id:"dotfiles.keyboard-layout"}]' "$HOME/.config/omarchy/shell.json" >/dev/null || return 1
	command touch "$root/no-physical-keyboards"
	remove_input_languages --yes >/dev/null || return 1
	jq -e '.bar.layout.center == [{id:"omarchy.clock"},{id:"omarchy.weather"}] and .bar.layout.right == []' "$HOME/.config/omarchy/shell.json" >/dev/null || return 1
	remove_input_languages --yes >"$root/remove-noop.out" || return 1
	grep -Fq 'Nothing to remove' "$root/remove-noop.out" || return 1
	command touch "$root/force-loaded-plugin"
	if remove_input_languages --yes >"$root/loaded-without-receipt.out" 2>&1; then return 1; fi
	grep -Fq 'valid active receipt' "$root/loaded-without-receipt.out" || return 1
)

apply_cancellation_is_pre_mutation() (
	set -euo pipefail
	local root before after output
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	export HOME=$root/home XDG_CONFIG_HOME=$root/home/.config XDG_DATA_HOME=$root/home/.local/share XDG_STATE_HOME=$root/home/.local/state
	export DOTFILES_TEST_OMARCHY_VERSION=4.0.2-1
	mkdir -p "$HOME/.config/omarchy"
	seed_reviewed_baseline "$HOME/.config/hypr"
	printf '%s\n' '{"version":1,"bar":{"layout":{"left":[],"center":[{"id":"omarchy.keyboard-layout"},{"id":"omarchy.weather"}],"right":[]}}}' >"$HOME/.config/omarchy/shell.json"
	omarchy() { case ${1-} in version) printf '4.0.2-1\n' ;; pkg) return 0 ;; *) return 1 ;; esac; }
	hyprctl() { case "$*" in version) command /usr/bin/hyprctl version ;; '-j inputlanguages') return 1 ;; *) return 1 ;; esac; }
	stow() { printf 'stow %s\n' "$*" >>"$root/calls"; command /usr/bin/stow "$@"; }
	export -f omarchy hyprctl stow
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	source "$SOURCE_REPO/lib/dotfiles/packages.sh"
	before=$(input_languages_tree_digest "$HOME/.config/hypr")
	output=$(apply_input_languages </dev/null) || return 1
	after=$(input_languages_tree_digest "$HOME/.config/hypr")
	[[ $before == "$after" && ! -e $XDG_STATE_HOME/dotfiles/input-languages && ! -e $XDG_DATA_HOME/dotfiles/input-languages ]] || return 1
	grep -Fq "Inspected: Hyprland tree=migratable; active receipt=absent; widget=valid; widget link=absent; target=right[0]." <<<"$output" || return 1
	grep -Fq "Paths: package source=$SOURCE_REPO/config/hyprland/.config/hypr; live tree=$HOME/.config/hypr; artifact root=$XDG_DATA_HOME/dotfiles/input-languages/plugins; active pointer=$XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua; lifecycle state=$XDG_STATE_HOME/dotfiles/input-languages." <<<"$output" || return 1
	grep -Fq "Plan: create and verify one timestamped backup of the complete live tree under $XDG_STATE_HOME/dotfiles/input-languages/backups before migration." <<<"$output" || return 1
	[[ ! -e $root/calls ]] || ! grep -Fv -- '--simulate' "$root/calls" >/dev/null
)

invalid_paths_and_dangling_evidence_are_nonmutating() (
	set -euo pipefail
	local root canary
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	canary=$root/foreign-canary
	printf 'keep\n' >"$canary"
	export HOME=$root/home XDG_CONFIG_HOME=$root/other-config XDG_DATA_HOME=$root/home/.local/share XDG_STATE_HOME=$root/home/.local/state
	export DOTFILES_TEST_OMARCHY_VERSION=4.0.2-1
	mkdir -p "$HOME" "$XDG_CONFIG_HOME"
	omarchy() { printf '4.0.2-1\n'; }
	hyprctl() { return 1; }
	export -f omarchy hyprctl
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	input_languages_set_paths
	if input_languages_paths_are_safe >/dev/null 2>&1; then return 1; fi
	[[ $(<"$canary") == keep ]] || return 1

	export XDG_CONFIG_HOME=$HOME/.config
	input_languages_set_paths
	mkdir -p -m 700 "$INPUT_LANGUAGES_STATE"
	ln -s "$root/missing-pending" "$INPUT_LANGUAGES_PENDING"
	input_languages_inspect
	[[ $INPUT_LANGUAGES_PENDING_STATE == invalid ]] || return 1
	if apply_input_languages --yes >/dev/null 2>&1; then return 1; fi
	[[ -L $INPUT_LANGUAGES_PENDING && $(<"$canary") == keep ]] || return 1
	rm "$INPUT_LANGUAGES_PENDING"
	mkdir -m 0755 "$root/diagnostics-target"
	ln -s "$root/diagnostics-target" "$INPUT_LANGUAGES_STATE/diagnostics"
	if input_languages_prepare_roots >/dev/null 2>&1; then return 1; fi
	[[ $(stat -c %a "$root/diagnostics-target") == 755 ]] || return 1
	rm "$INPUT_LANGUAGES_STATE/diagnostics"
	input_languages_prepare_roots
	local managed target
	for managed in "$INPUT_LANGUAGES_DATA/removals" "$INPUT_LANGUAGES_STATE/backups" "$INPUT_LANGUAGES_STATE/archive"; do
		target=$root/$(basename "$managed")-target
		command rmdir "$managed"
		mkdir -m 0755 "$target"
		ln -s "$target" "$managed"
		if input_languages_paths_are_safe >/dev/null 2>&1; then return 1; fi
		[[ $(stat -c %a "$target") == 755 ]] || return 1
		command rm "$managed"
		command rmdir "$target"
		mkdir -m 0700 "$managed"
	done
	printf 'lock canary\n' >"$root/lock-canary"
	ln -s "$root/lock-canary" "$INPUT_LANGUAGES_STATE/operation.lock"
	if input_languages_acquire_lock Test >/dev/null 2>&1; then return 1; fi
	[[ $(<"$root/lock-canary") == 'lock canary' ]] || return 1
	rm "$INPUT_LANGUAGES_STATE/operation.lock"
	chmod 600 "$root/lock-canary"
	ln "$root/lock-canary" "$INPUT_LANGUAGES_STATE/operation.lock"
	if input_languages_acquire_lock Test >/dev/null 2>&1; then return 1; fi
	[[ $(<"$root/lock-canary") == 'lock canary' ]] || return 1
)

transaction_failure_case() (
	set -euo pipefail
	local mode=$1 root baseline after
	root=$(mktemp -d)
	trap 'chmod -R u+w -- "$root" 2>/dev/null || true; rm -rf -- "$root"' EXIT
	export HOME=$root/home XDG_CONFIG_HOME=$root/home/.config XDG_DATA_HOME=$root/home/.local/share XDG_STATE_HOME=$root/home/.local/state
	export DOTFILES_TEST_OMARCHY_VERSION=4.0.2-1
	mkdir -p "$HOME/.config/omarchy"
	seed_reviewed_baseline "$HOME/.config/hypr"
	printf '%s\n' '{"version":1,"bar":{"layout":{"left":[],"center":[{"id":"omarchy.keyboard-layout"},{"id":"omarchy.weather"}],"right":[]}}}' >"$HOME/.config/omarchy/shell.json"
	printf 'false\n' >"$root/autoreload"
	: >"$root/calls"
	omarchy() {
		printf 'omarchy %s\n' "$*" >>"$root/calls"
		case "$*" in
			version) printf '4.0.2-1\n' ;;
			pkg*) return 0 ;;
			'plugin list --json')
				if [[ -L $XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout ]]; then
					jq -n --argjson enabled "$(jq 'any(.bar.layout[][]; .id == "dotfiles.keyboard-layout")' "$HOME/.config/omarchy/shell.json")" '[{id:"dotfiles.keyboard-layout",name:"Flag keyboard layout",enabled:$enabled,kinds:["bar-widget"],firstParty:false,clonedFrom:"omarchy.keyboard-layout"}]'
				else printf '[]\n'; fi
				;;
			'shell shell rescanPlugins'|'restart shell') return 0 ;;
			'plugin enable dotfiles.keyboard-layout --section right --index 0')
				jq '([.bar.layout.center[] | select(.id == "omarchy.keyboard-layout")][0]) as $entry | .bar.layout.center |= map(select(.id != "omarchy.keyboard-layout")) | .bar.layout.right = [($entry | .id = "dotfiles.keyboard-layout")] + .bar.layout.right' "$HOME/.config/omarchy/shell.json" >"$HOME/.config/omarchy/shell.updated" && command mv "$HOME/.config/omarchy/shell.updated" "$HOME/.config/omarchy/shell.json"
				;;
			'plugin disable dotfiles.keyboard-layout')
				jq '(.bar.layout.left[],.bar.layout.center[],.bar.layout.right[] | select(.id == "dotfiles.keyboard-layout")).id = "omarchy.keyboard-layout"' "$HOME/.config/omarchy/shell.json" >"$HOME/.config/omarchy/shell.updated" && command mv "$HOME/.config/omarchy/shell.updated" "$HOME/.config/omarchy/shell.json"
				;;
			'bar move omarchy.keyboard-layout --section center --index 0')
				jq '([.bar.layout[][] | select(.id == "omarchy.keyboard-layout")][0]) as $entry | (.bar.layout.left,.bar.layout.center,.bar.layout.right) |= map(select(.id != "omarchy.keyboard-layout")) | .bar.layout.center = [$entry] + .bar.layout.center' "$HOME/.config/omarchy/shell.json" >"$HOME/.config/omarchy/shell.updated" && command mv "$HOME/.config/omarchy/shell.updated" "$HOME/.config/omarchy/shell.json"
				;;
			*) return 1 ;;
		esac
	}
	hyprctl() {
		printf 'hyprctl %s\n' "$*" >>"$root/calls"
		case "$*" in
			'-j inputlanguages') printf 'unknown request\n' ;;
			'-j plugin list') printf '[]\n' ;;
			'-j inputlanguagesreset 0') printf '{"ok":true,"canonical_group":0}\n' ;;
			'-j inputlanguagesreset 1') printf '{"ok":true,"canonical_group":1}\n' ;;
			'-j getoption misc:disable_autoreload') printf '{"bool":%s}\n' "$(<"$root/autoreload")" ;;
			'keyword misc:disable_autoreload true') printf 'true\n' >"$root/autoreload" ;;
			'keyword misc:disable_autoreload false') printf 'false\n' >"$root/autoreload" ;;
			reload)
				local count=0
				[[ ! -f $root/reloads ]] || count=$(<"$root/reloads")
				count=$((count + 1)); printf '%s\n' "$count" >"$root/reloads"
				if [[ $mode == rollback-once && $count -eq 1 ]]; then return 72; fi
				if [[ $mode == recovery-retry && $count -eq 2 ]]; then return 72; fi
				[[ $mode != rollback-always ]]
				;;
			configerrors) return 0 ;;
			*) return 0 ;;
		esac
	}
	stow() { printf 'stow %s\n' "$*" >>"$root/calls"; command /usr/bin/stow "$@"; }
	mv() {
		local target=${!#}
		if [[ $mode == pending-write && $target == "$XDG_STATE_HOME/dotfiles/input-languages/pending.json" ]]; then return 73; fi
		command mv "$@"
	}
	export -f omarchy hyprctl stow mv
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	source "$SOURCE_REPO/lib/dotfiles/packages.sh"
	input_languages_static_preflight() { return 0; }
	input_languages_stack_identity() {
		INPUT_LANGUAGES_RUNNING_HASH=test-compat
		INPUT_LANGUAGES_HEADER_HASH=test-compat
		INPUT_LANGUAGES_COMPILER=test-compiler
		INPUT_LANGUAGES_COMPILER_WARNING=''
	}
	input_languages_dependencies_match_build() { return 0; }
	input_languages_build_artifact() {
		local generation
		INPUT_LANGUAGES_SOURCE_ID=$(input_languages_source_identity)
		INPUT_LANGUAGES_BUILD_ID=$(printf build | sha256sum | cut -d' ' -f1)
		INPUT_LANGUAGES_DEPENDENCIES=test-dependencies
		INPUT_LANGUAGES_ARTIFACT_SHA=$(printf 'test artifact\n' | sha256sum | cut -d' ' -f1)
		generation=$(input_languages_new_transaction)
		INPUT_LANGUAGES_ARTIFACT_DIR=$INPUT_LANGUAGES_ARTIFACTS/$INPUT_LANGUAGES_BUILD_ID-$INPUT_LANGUAGES_ARTIFACT_SHA-$generation
		INPUT_LANGUAGES_ARTIFACT=$INPUT_LANGUAGES_ARTIFACT_DIR/input-languages.so
		mkdir -m 700 "$INPUT_LANGUAGES_ARTIFACT_DIR"
		printf 'test artifact\n' >"$INPUT_LANGUAGES_ARTIFACT"
		cp -a "$INPUT_LANGUAGES_WIDGET_SOURCE" "$INPUT_LANGUAGES_ARTIFACT_DIR/$INPUT_LANGUAGES_WIDGET"
		INPUT_LANGUAGES_WIDGET_SHA=$(input_languages_widget_digest "$INPUT_LANGUAGES_ARTIFACT_DIR/$INPUT_LANGUAGES_WIDGET")
		jq -n --arg build "$INPUT_LANGUAGES_BUILD_ID" --arg source "$INPUT_LANGUAGES_SOURCE_ID" --arg sha "$INPUT_LANGUAGES_ARTIFACT_SHA" \
			--arg widget "$INPUT_LANGUAGES_WIDGET_SHA" \
			'{version:1,build_id:$build,source_id:$source,compatibility_hash:"test-compat",compiler:"test-compiler",dependencies:"test-dependencies",artifact_sha256:$sha,widget_sha256:$widget,exports:["pluginAPIVersion","pluginExit","pluginInit"]}' \
			>"$INPUT_LANGUAGES_ARTIFACT_DIR/build.json"
		chmod 755 "$INPUT_LANGUAGES_ARTIFACT"
		chmod -R a-w "$INPUT_LANGUAGES_ARTIFACT_DIR"
		if [[ $mode == source-drift ]]; then
			input_languages_source_identity() { printf '%064d\n' 7; }
		elif [[ $mode == source-drift-before-pending ]]; then
			printf '0\n' >"$root/source-checks"
			input_languages_source_matches_build() {
				local count
				count=$(<"$root/source-checks"); count=$((count + 1)); printf '%s\n' "$count" >"$root/source-checks"
				((count == 1))
			}
		elif [[ $mode == source-drift-before-receipt ]]; then
			printf '0\n' >"$root/source-checks"
			input_languages_source_matches_build() {
				local count
				count=$(<"$root/source-checks"); count=$((count + 1)); printf '%s\n' "$count" >"$root/source-checks"
				((count < 3))
			}
		fi
	}
	bash() { return 0; }
	baseline=$(input_languages_tree_digest "$HOME/.config/hypr")
	if [[ $mode == pending-reconcile ]]; then
		local transaction pending_digest
		input_languages_inspect
		input_languages_prepare_roots
		input_languages_build_artifact
		transaction=$(input_languages_new_transaction)
		input_languages_create_backup "$transaction"
		input_languages_create_transaction_snapshots "$transaction"
		input_languages_make_pending apply "$transaction" "$INPUT_LANGUAGES_ARTIFACT" activate null false
		pending_digest=$(sha256sum "$INPUT_LANGUAGES_PENDING")
		wizard_confirm() { return 1; }
		input_languages_reconcile_pending >/dev/null
		[[ $(sha256sum "$INPUT_LANGUAGES_PENDING") == "$pending_digest" && ! -e $root/reloads ]] || return 1
		if grep -Eq '^hyprctl keyword|^stow --no-folding --dir .* hyprland$' "$root/calls"; then return 1; fi
		input_languages_reconcile_pending true >/dev/null
		[[ ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
		[[ $(input_languages_tree_digest "$HOME/.config/hypr") == "$baseline" ]] || return 1
		return 0
	fi
	if apply_input_languages --yes >/dev/null 2>&1; then return 1; fi
	after=$(input_languages_tree_digest "$HOME/.config/hypr")
	[[ $after == "$baseline" && $(<"$root/autoreload") == false ]] || return 1
	case $mode in
		pending-write)
			[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json && ! -e $XDG_STATE_HOME/dotfiles/input-languages/recovery-required.json && ! -e $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua ]] || return 1
			if grep -Eq '^hyprctl keyword|^stow --no-folding --dir .* hyprland$' "$root/calls"; then return 1; fi
			;;
		source-drift)
			[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json && ! -e $XDG_STATE_HOME/dotfiles/input-languages/recovery-required.json && ! -e $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua ]] || return 1
			if grep -Eq '^hyprctl keyword|^stow --no-folding --dir .* hyprland$' "$root/calls"; then return 1; fi
			;;
		source-drift-before-pending)
			[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json && ! -e $XDG_STATE_HOME/dotfiles/input-languages/recovery-required.json && ! -e $XDG_DATA_HOME/dotfiles/input-languages/active-artifact.lua ]] || return 1
			if grep -Eq '^hyprctl keyword|^stow --no-folding --dir .* hyprland$' "$root/calls"; then return 1; fi
			;;
		source-drift-before-receipt)
			[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json && ! -e $XDG_STATE_HOME/dotfiles/input-languages/recovery-required.json ]] || return 1
			[[ $(<"$root/reloads") -eq 2 ]] || return 1
			;;
		rollback-once)
			[[ ! -e $XDG_STATE_HOME/dotfiles/input-languages/pending.json && ! -e $XDG_STATE_HOME/dotfiles/input-languages/recovery-required.json ]] || return 1
			[[ $(<"$root/reloads") -eq 2 ]] || return 1
			;;
		rollback-always)
			input_languages_inspect
			[[ $INPUT_LANGUAGES_PENDING_STATE == valid && $INPUT_LANGUAGES_RECOVERY_STATE == valid ]] || return 1
			[[ $(<"$root/reloads") -ge 2 ]] || return 1
			;;
		recovery-retry)
			input_languages_inspect
			[[ $INPUT_LANGUAGES_PENDING_STATE == valid && $INPUT_LANGUAGES_RECOVERY_STATE == valid ]] || return 1
			apply_input_languages --recovery-approved >/dev/null || return 1
			[[ ! -e $INPUT_LANGUAGES_PENDING && ! -e $INPUT_LANGUAGES_RECOVERY ]] || return 1
			[[ $(input_languages_tree_digest "$HOME/.config/hypr") == "$baseline" ]] || return 1
			[[ $(<"$root/reloads") -eq 3 ]] || return 1
			;;
	esac
)

pending_write_failure_precedes_live_mutation() { transaction_failure_case pending-write; }
source_drift_during_build_precedes_live_mutation() { transaction_failure_case source-drift; }
source_drift_before_pending_precedes_live_mutation() { transaction_failure_case source-drift-before-pending; }
source_drift_before_receipt_rolls_back_live_mutation() { transaction_failure_case source-drift-before-receipt; }
post_mutation_failure_rolls_back_completely() { transaction_failure_case rollback-once; }
rollback_failure_records_recovery_required() { transaction_failure_case rollback-always; }
recovery_required_can_retry_verified_rollback() { transaction_failure_case recovery-retry; }
pending_reconciliation_requires_confirmation() { transaction_failure_case pending-reconcile; }

status_is_read_only_without_tools() (
	set -euo pipefail
	local root before after output
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	export HOME=$root/home XDG_CONFIG_HOME=$root/home/.config XDG_DATA_HOME=$root/home/.local/share XDG_STATE_HOME=$root/home/.local/state
	export DOTFILES_TEST_OMARCHY_VERSION=5.0.0-1
	mkdir -p "$HOME"
	omarchy() { printf '5.0.0-1\n'; }
	hyprctl() { return 1; }
	export -f omarchy hyprctl
	# shellcheck source=../lib/dotfiles/core.sh
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	# shellcheck source=../lib/dotfiles/input-languages.sh
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	before=$(find "$root" -mindepth 1 -printf '%P\n' | sort)
	output=$(input_languages_status) || return 1
	after=$(find "$root" -mindepth 1 -printf '%P\n' | sort)
	[[ $before == "$after" ]] || return 1
	for state in Installed Running Configured Generated Ownership Compatibility; do
		grep -Fq "$state:" <<<"$output" || return 1
	done
	grep -Fq 'Overall: unsupported' <<<"$output" || return 1
	grep -Fq 'Restore a supported Omarchy version before choosing Apply.' <<<"$output" || return 1
	if remove_input_languages --yes >/dev/null 2>&1; then return 1; fi
)

hyprland_header_content_changes_identity() (
	set -euo pipefail
	local root before after
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	export DOTFILES_TEST_HYPRLAND_HEADER_ROOT=$root/headers
	mkdir -p "$DOTFILES_TEST_HYPRLAND_HEADER_ROOT"
	printf 'first\n' >"$DOTFILES_TEST_HYPRLAND_HEADER_ROOT/example.hpp"
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	before=$(input_languages_header_source_identity)
	printf 'second\n' >"$DOTFILES_TEST_HYPRLAND_HEADER_ROOT/example.hpp"
	after=$(input_languages_header_source_identity)
	[[ $before != "$after" ]]
)

expected_noop_blocks_new_mutation_plan() (
	set -euo pipefail
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	input_languages_prepare_apply() { INPUT_LANGUAGES_PREPARED_RESULT=change; }
	if apply_input_languages --yes --packages-prepared --expect-noop >/dev/null 2>&1; then return 1; fi
)

complete_live_baseline_is_enforced() (
	set -euo pipefail
	local root
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	export HOME=$root/home XDG_CONFIG_HOME=$root/home/.config XDG_DATA_HOME=$root/home/.local/share XDG_STATE_HOME=$root/home/.local/state
	seed_reviewed_baseline "$HOME/.config/hypr"
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	input_languages_set_paths
	input_languages_baseline_matches || return 1
	printf '\n# unreviewed idle change\n' >>"$HOME/.config/hypr/hypridle.conf"
	if input_languages_baseline_matches; then return 1; fi
	cp "$SOURCE_REPO/config/hyprland/.config/hypr/hypridle.conf" "$HOME/.config/hypr/hypridle.conf"
	printf '\n# unreviewed lock change\n' >>"$HOME/.config/hypr/hyprlock.conf"
	! input_languages_baseline_matches
)

effective_shell_state_is_validated() (
	set -euo pipefail
	local root
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	export HOME=$root/home XDG_CONFIG_HOME=$root/home/.config XDG_DATA_HOME=$root/home/.local/share XDG_STATE_HOME=$root/home/.local/state
	mkdir -p "$HOME/.config/omarchy"
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	input_languages_set_paths
	input_languages_inspect_widget
	[[ $INPUT_LANGUAGES_WIDGET_STATE == valid && $INPUT_LANGUAGES_WIDGET_PRESENT == false && $INPUT_LANGUAGES_STOCK_WIDGET_PRESENT == true && $INPUT_LANGUAGES_WEATHER_COUNT == 1 ]] || return 1
	printf '{\n' >"$INPUT_LANGUAGES_SHELL"
	input_languages_inspect_widget
	[[ $INPUT_LANGUAGES_WIDGET_STATE == invalid && $INPUT_LANGUAGES_WIDGET_PRESENT == false ]] || return 1
	printf '%s\n' '{"bar":{"layout":{"left":[],"center":[],"right":[]}}}' >"$INPUT_LANGUAGES_SHELL"
	input_languages_inspect_widget
	[[ $INPUT_LANGUAGES_WIDGET_STATE == invalid && $INPUT_LANGUAGES_WIDGET_PRESENT == false ]] || return 1
	rm "$INPUT_LANGUAGES_SHELL"
	ln -s /usr/share/omarchy/config/omarchy/shell.json "$INPUT_LANGUAGES_SHELL"
	input_languages_inspect_widget
	[[ $INPUT_LANGUAGES_WIDGET_STATE == invalid && $INPUT_LANGUAGES_WIDGET_PRESENT == false ]]
)

absent_stock_is_restored_as_absent() (
	set -euo pipefail
	local root
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	export HOME=$root/home XDG_CONFIG_HOME=$root/home/.config XDG_DATA_HOME=$root/home/.local/share XDG_STATE_HOME=$root/home/.local/state
	mkdir -p "$XDG_CONFIG_HOME/omarchy"
	printf '%s\n' '{"version":1,"bar":{"layout":{"left":[],"center":[{"id":"omarchy.weather"},{"id":"dotfiles.keyboard-layout"}],"right":[]}}}' >"$XDG_CONFIG_HOME/omarchy/shell.json"
	omarchy() {
		local temporary=$XDG_CONFIG_HOME/omarchy/shell.updated
		case "$*" in
			'plugin disable dotfiles.keyboard-layout') jq '(.bar.layout.center[] | select(.id == "dotfiles.keyboard-layout")).id = "omarchy.keyboard-layout"' "$XDG_CONFIG_HOME/omarchy/shell.json" >"$temporary" ;;
			'plugin disable omarchy.keyboard-layout') jq '.bar.layout.center |= map(select(.id != "omarchy.keyboard-layout"))' "$XDG_CONFIG_HOME/omarchy/shell.json" >"$temporary" ;;
			*) return 1 ;;
		esac
		command mv "$temporary" "$XDG_CONFIG_HOME/omarchy/shell.json"
	}
	export -f omarchy
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	input_languages_set_paths
	input_languages_restore_stock_widget false
	jq -e '.bar.layout.center == [{id:"omarchy.weather"}]' "$XDG_CONFIG_HOME/omarchy/shell.json" >/dev/null
)

foreign_and_competing_clones_block_apply() (
	set -euo pipefail
	local root
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	export HOME=$root/home XDG_CONFIG_HOME=$root/home/.config XDG_DATA_HOME=$root/home/.local/share XDG_STATE_HOME=$root/home/.local/state
	export DOTFILES_TEST_OMARCHY_VERSION=4.0.2-1
	mkdir -p "$XDG_CONFIG_HOME/omarchy/plugins"
	seed_reviewed_baseline "$XDG_CONFIG_HOME/hypr"
	printf '%s\n' '{"version":1,"bar":{"layout":{"left":[],"center":[{"id":"omarchy.keyboard-layout"},{"id":"omarchy.weather"}],"right":[]}}}' >"$XDG_CONFIG_HOME/omarchy/shell.json"
	ln -s "$root/foreign" "$XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout"
	omarchy() { case ${1-} in version) printf '4.0.2-1\n' ;; pkg) return 0 ;; *) return 1 ;; esac; }
	hyprctl() { case "$*" in version) command /usr/bin/hyprctl version ;; *) return 1 ;; esac; }
	export -f omarchy hyprctl
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	source "$SOURCE_REPO/lib/dotfiles/packages.sh"
	if apply_input_languages --yes >"$root/foreign.out" 2>&1; then return 1; fi
	grep -Fq 'foreign or partial' "$root/foreign.out" || return 1
	rm "$XDG_CONFIG_HOME/omarchy/plugins/dotfiles.keyboard-layout"
	mkdir "$XDG_CONFIG_HOME/omarchy/plugins/other.keyboard"
	printf '%s\n' '{"schemaVersion":1,"id":"other.keyboard","omarchy":{"clonedFrom":"omarchy.keyboard-layout"}}' >"$XDG_CONFIG_HOME/omarchy/plugins/other.keyboard/manifest.json"
	if apply_input_languages --yes >"$root/competing.out" 2>&1; then return 1; fi
	grep -Fq 'competing keyboard-layout clones' "$root/competing.out"
)

changed_widget_source_uses_shell_restart() (
	set -euo pipefail
	local root
	root=$(mktemp -d)
	trap 'rm -rf -- "$root"' EXIT
	: >"$root/calls"
	omarchy() { printf '%s\n' "$*" >>"$root/calls"; }
	export -f omarchy
	source "$SOURCE_REPO/lib/dotfiles/core.sh"
	source "$SOURCE_REPO/lib/dotfiles/input-languages.sh"
	input_languages_reload_widget_registry true
	[[ $(<"$root/calls") == 'restart shell' ]]
)

run_test apply_noop_remove_round_trip 'version-2 Apply, exact no-op, and receipt-backed Remove round trip'
run_test apply_cancellation_is_pre_mutation 'Apply cancellation occurs after read-only preparation and before mutation'
run_test invalid_paths_and_dangling_evidence_are_nonmutating 'noncanonical paths and dangling lifecycle evidence block without mutation'
run_test pending_write_failure_precedes_live_mutation 'pending evidence publication failure precedes every live mutation'
run_test source_drift_during_build_precedes_live_mutation 'source drift during artifact build precedes every live mutation'
run_test source_drift_before_pending_precedes_live_mutation 'source drift before pending evidence precedes every live mutation'
run_test source_drift_before_receipt_rolls_back_live_mutation 'source drift before active receipt publication rolls back live mutation'
run_test post_mutation_failure_rolls_back_completely 'reachable post-mutation failure restores and verifies prior state'
run_test rollback_failure_records_recovery_required 'rollback failure retains valid pending and recovery-required evidence'
run_test recovery_required_can_retry_verified_rollback 'recovery-required state can retry and verify receipt-backed rollback'
run_test pending_reconciliation_requires_confirmation 'pending reconciliation is default-No and mutates only after approval'
run_test status_is_read_only_without_tools 'Status remains read-only when unsupported and tools are unavailable'
run_test hyprland_header_content_changes_identity 'Hyprland header content participates in build identity'
run_test expected_noop_blocks_new_mutation_plan 'an inspected exact no-op cannot become an unplanned mutation'
run_test complete_live_baseline_is_enforced 'all eleven live baseline files are enforced'
run_test effective_shell_state_is_validated 'effective Shell fallback is inspected and unsafe user state is rejected'
run_test absent_stock_is_restored_as_absent 'Remove restores absence when the stock keyboard-layout widget was absent'
run_test foreign_and_competing_clones_block_apply 'foreign live links and competing keyboard-layout clones block Apply'
run_test changed_widget_source_uses_shell_restart 'changed active widget source uses a full Shell restart'

finish_tests
