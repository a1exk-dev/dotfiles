#!/usr/bin/env bash

# Select Hyprland machine profile: points ~/.config/hypr/machine at one tracked
# profile directory from the hyprland Stow package. The package links the profiles
# into ~/.config/dotfiles/hypr/, and this action owns the machine link alone; the
# shared Hyprland files keep owning everything else below ~/.config/hypr/.

readonly HYPR_PROFILE_DIR="$HOME/.config/dotfiles/hypr"
readonly HYPR_MACHINE_LINK="$HOME/.config/hypr/machine"

hypr_profile_names() {
	find "$HYPR_PROFILE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Prints the selected profile when the machine link resolves to one of them.
hypr_selected_profile() {
	local resolved name
	resolved=$(readlink -f -- "$HYPR_MACHINE_LINK" 2>/dev/null) || return 1
	[[ -n $resolved ]] || return 1
	while IFS= read -r name; do
		if [[ $resolved == "$(readlink -f -- "$HYPR_PROFILE_DIR/$name")" ]]; then
			printf '%s\n' "$name"
			return 0
		fi
	done < <(hypr_profile_names)
	return 1
}

# Reports the Hyprland configuration errors that follow a reload, if any.
hypr_profile_config_errors() {
	local errors
	hyprctl reload >/dev/null 2>&1 || return 0
	errors=$(hyprctl configerrors 2>/dev/null) || return 0
	errors=${errors//no errors/}
	[[ -n ${errors//[[:space:]]/} ]] && printf '%s\n' "$errors"
	return 0
}

# select_hypr_profile [PROFILE]
select_hypr_profile() {
	local profile=${1-}

	printf 'Phase: inspect\n'
	if ! package_is_linked hyprland; then
		printf 'Error: the hyprland Stow package is not applied, so no profile is available.\n' >&2
		printf 'Recovery: choose Apply Stow packages and select hyprland, then choose Select Hyprland profile in the Dotfiles wizard.\n' >&2
		return 1
	fi
	local -a profiles=()
	mapfile -t profiles < <(hypr_profile_names)
	if ((${#profiles[@]} == 0)); then
		printf 'Error: no tracked profiles exist in %s.\n' "$HYPR_PROFILE_DIR" >&2
		printf 'Recovery: add a profile directory to config/hyprland/.config/dotfiles/hypr/, apply hyprland, then choose Select Hyprland profile in the Dotfiles wizard.\n' >&2
		return 1
	fi
	local current
	if current=$(hypr_selected_profile); then
		printf 'Selected profile: %s\n' "$current"
	else
		printf 'Selected profile: none\n'
	fi

	if [[ -z $profile ]]; then
		if ! profile=$(wizard_choose 'Choose a Hyprland machine profile (none selected by default)' Cancel "${profiles[@]}") ||
			[[ $profile == Cancel ]]; then
			printf 'No profile selected; no changes made.\n'
			return 0
		fi
	fi
	if ! printf '%s\n' "${profiles[@]}" | grep -Fxq -- "$profile"; then
		printf 'Error: unknown Hyprland machine profile: %s\n' "$profile" >&2
		return 1
	fi
	local source=$HYPR_PROFILE_DIR/$profile

	printf 'Phase: plan\n'
	local existing=''
	if [[ -e $HYPR_MACHINE_LINK || -L $HYPR_MACHINE_LINK ]]; then
		existing=$(path_type "$HYPR_MACHINE_LINK")
		printf 'Plan: back up the existing %s at %s\n' "$existing" "$HYPR_MACHINE_LINK"
	fi
	printf 'Plan: link %s -> %s\n' "$HYPR_MACHINE_LINK" "$source"
	printf 'Plan: reload Hyprland and verify the configuration parses\n'
	printf 'Note: GDK_SCALE is read when Hyprland starts, so a change to it needs a new session.\n'

	printf 'Phase: confirm\n'
	if ! wizard_confirm "Select Hyprland machine profile $profile?"; then
		printf 'No changes made.\n'
		return 0
	fi

	local state_home=${XDG_STATE_HOME:-$HOME/.local/state}
	if [[ $state_home != /* ]]; then
		printf 'Error: XDG_STATE_HOME must be an absolute path: %s\n' "$state_home" >&2
		printf 'Recovery: set XDG_STATE_HOME to an absolute path, then choose Select Hyprland profile in the Dotfiles wizard.\n' >&2
		return 1
	fi
	if [[ -n $existing ]]; then
		local backup
		backup=$state_home/dotfiles/backups/hyprland/$(date -u +%Y%m%dT%H%M%S.%NZ)/.config/hypr/machine
		if ! mkdir -p -- "${backup%/*}" || ! cp --archive -- "$HYPR_MACHINE_LINK" "$backup"; then
			printf 'Error: could not back up %s; it remains unchanged.\n' "$HYPR_MACHINE_LINK" >&2
			return 1
		fi
		printf 'Backup created: %s\n' "$backup"
		# A real directory would make ln place the link inside it, so replace it.
		if [[ $existing == directory ]] && ! rm -rf -- "$HYPR_MACHINE_LINK"; then
			printf 'Error: could not replace the existing directory at %s.\n' "$HYPR_MACHINE_LINK" >&2
			return 1
		fi
	fi

	printf 'Phase: select\n'
	if ! mkdir -p -- "${HYPR_MACHINE_LINK%/*}" || ! ln -sfn -- "$source" "$HYPR_MACHINE_LINK"; then
		printf 'Error: could not link %s to %s.\n' "$HYPR_MACHINE_LINK" "$source" >&2
		return 1
	fi

	printf 'Phase: verify\n'
	if [[ ! -L $HYPR_MACHINE_LINK ]] || [[ $(readlink -f -- "$HYPR_MACHINE_LINK") != "$(readlink -f -- "$source")" ]]; then
		printf 'Error: %s does not resolve to %s.\n' "$HYPR_MACHINE_LINK" "$source" >&2
		return 1
	fi
	local errors
	errors=$(hypr_profile_config_errors)
	if [[ -n $errors ]]; then
		printf 'Error: Hyprland reported configuration errors after selecting %s:\n%s\n' "$profile" "$errors" >&2
		printf 'Recovery: fix config/hyprland/.config/dotfiles/hypr/%s/, then choose Select Hyprland profile in the Dotfiles wizard.\n' "$profile" >&2
		return 1
	fi
	printf 'Selected and verified Hyprland machine profile: %s\n' "$profile"
}
