#!/usr/bin/env bash

# Select Voxtype profile: points ~/.config/voxtype/config.toml at one tracked
# profile from the voxtype Stow package. The package links the profiles into
# ~/.config/dotfiles/voxtype/, and this action owns the config.toml link alone;
# Voxtype keeps owning everything else below ~/.config/voxtype/.

readonly VOXTYPE_PROFILE_DIR="$HOME/.config/dotfiles/voxtype"
readonly VOXTYPE_CONFIG="$HOME/.config/voxtype/config.toml"

voxtype_profile_names() {
	find "$VOXTYPE_PROFILE_DIR" -mindepth 1 -maxdepth 1 -name '*.toml' -printf '%f\n' 2>/dev/null |
		sed 's/\.toml$//' | sort
}

# Prints the selected profile when config.toml resolves to one of them.
voxtype_selected_profile() {
	local resolved name
	resolved=$(readlink -f -- "$VOXTYPE_CONFIG" 2>/dev/null) || return 1
	while IFS= read -r name; do
		if [[ $resolved == "$(readlink -f -- "$VOXTYPE_PROFILE_DIR/$name.toml")" ]]; then
			printf '%s\n' "$name"
			return 0
		fi
	done < <(voxtype_profile_names)
	return 1
}

# select_voxtype_profile [PROFILE]
select_voxtype_profile() {
	local profile=${1-}

	printf 'Phase: inspect\n'
	if ! package_is_linked voxtype; then
		printf 'Error: the voxtype Stow package is not applied, so no profile is available.\n' >&2
		printf 'Recovery: choose Apply Stow packages and select voxtype, then choose Select Voxtype profile in the Dotfiles wizard.\n' >&2
		return 1
	fi
	local -a profiles=()
	mapfile -t profiles < <(voxtype_profile_names)
	if ((${#profiles[@]} == 0)); then
		printf 'Error: no tracked profiles exist in %s.\n' "$VOXTYPE_PROFILE_DIR" >&2
		printf 'Recovery: add a profile to config/voxtype/.config/dotfiles/voxtype/, apply voxtype, then choose Select Voxtype profile in the Dotfiles wizard.\n' >&2
		return 1
	fi
	local current
	if current=$(voxtype_selected_profile); then
		printf 'Selected profile: %s\n' "$current"
	else
		printf 'Selected profile: none\n'
	fi

	if [[ -z $profile ]]; then
		if ! profile=$(wizard_choose 'Choose a Voxtype profile (none selected by default)' Cancel "${profiles[@]}") ||
			[[ $profile == Cancel ]]; then
			printf 'No profile selected; no changes made.\n'
			return 0
		fi
	fi
	if ! printf '%s\n' "${profiles[@]}" | grep -Fxq -- "$profile"; then
		printf 'Error: unknown Voxtype profile: %s\n' "$profile" >&2
		return 1
	fi
	local source=$VOXTYPE_PROFILE_DIR/$profile.toml

	printf 'Phase: plan\n'
	local existing=''
	if [[ -e $VOXTYPE_CONFIG || -L $VOXTYPE_CONFIG ]]; then
		existing=$(path_type "$VOXTYPE_CONFIG")
		printf 'Plan: back up the existing %s at %s\n' "$existing" "$VOXTYPE_CONFIG"
	fi
	printf 'Plan: link %s -> %s\n' "$VOXTYPE_CONFIG" "$source"
	printf 'Plan: verify the link and parse the profile with voxtype\n'

	printf 'Phase: confirm\n'
	if ! wizard_confirm "Select Voxtype profile $profile?"; then
		printf 'No changes made.\n'
		return 0
	fi

	local state_home=${XDG_STATE_HOME:-$HOME/.local/state}
	if [[ $state_home != /* ]]; then
		printf 'Error: XDG_STATE_HOME must be an absolute path: %s\n' "$state_home" >&2
		printf 'Recovery: set XDG_STATE_HOME to an absolute path, then choose Select Voxtype profile in the Dotfiles wizard.\n' >&2
		return 1
	fi
	if [[ -n $existing ]]; then
		local backup
		backup=$state_home/dotfiles/backups/voxtype/$(date -u +%Y%m%dT%H%M%S.%NZ)/.config/voxtype/config.toml
		if ! mkdir -p -- "${backup%/*}" || ! cp --archive -- "$VOXTYPE_CONFIG" "$backup"; then
			printf 'Error: could not back up %s; it remains unchanged.\n' "$VOXTYPE_CONFIG" >&2
			return 1
		fi
		printf 'Backup created: %s\n' "$backup"
	fi

	printf 'Phase: select\n'
	if ! mkdir -p -- "${VOXTYPE_CONFIG%/*}" || ! ln -sfn -- "$source" "$VOXTYPE_CONFIG"; then
		printf 'Error: could not link %s to %s.\n' "$VOXTYPE_CONFIG" "$source" >&2
		return 1
	fi

	printf 'Phase: verify\n'
	if [[ ! -L $VOXTYPE_CONFIG ]] || [[ $(readlink -f -- "$VOXTYPE_CONFIG") != "$(readlink -f -- "$source")" ]]; then
		printf 'Error: %s does not resolve to %s.\n' "$VOXTYPE_CONFIG" "$source" >&2
		return 1
	fi
	if ! voxtype -c "$VOXTYPE_CONFIG" config get engine >/dev/null; then
		printf 'Error: Voxtype could not read the selected profile %s.\n' "$profile" >&2
		printf 'Recovery: fix config/voxtype/.config/dotfiles/voxtype/%s.toml, then choose Select Voxtype profile in the Dotfiles wizard.\n' "$profile" >&2
		return 1
	fi
	printf 'Selected and verified Voxtype profile: %s\n' "$profile"
	printf 'Restart the daemon to pick it up: systemctl --user restart voxtype\n'
}
