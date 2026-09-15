#!/usr/bin/env bash

# Patches Discord's self-updated app-* directory with Vencord and reports the
# integration state. Discord and Vencord own their settings; this module never
# starts or stops Discord.

discord_system24_config_home() {
	printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# Prints the newest ~/.config/discord/app-* directory, or fails when none exists.
discord_system24_newest_app_dir() {
	local -a app_dirs=()
	mapfile -t app_dirs < <(compgen -G "$(discord_system24_config_home)/discord/app-*/" | sed 's:/$::' | sort -V)
	((${#app_dirs[@]} > 0)) || return 1
	printf '%s\n' "${app_dirs[-1]}"
}

discord_system24_theme_path() {
	printf '%s/Vencord/themes/omarchy-system24.css\n' "$(discord_system24_config_home)"
}

discord_system24_status() {
	local app_dir theme
	if app_dir=$(discord_system24_newest_app_dir); then
		if [[ -e $app_dir/resources/_app.asar ]]; then
			printf '    Discord app: %s (patched)\n' "$app_dir"
		else
			printf '    Discord app: %s (unpatched)\n' "$app_dir"
		fi
	else
		printf '    Discord app: no app-* directory found\n'
	fi
	theme=$(discord_system24_theme_path)
	if [[ -f $theme ]]; then
		printf '    Vencord theme: %s (present)\n' "$theme"
	else
		printf '    Vencord theme: %s (absent)\n' "$theme"
	fi
}

# Previews the removal steps and sets DISCORD_SYSTEM24_UNPATCH_DIR to the
# patched newest app-*, or to empty when there is nothing to unpatch.
discord_system24_prepare_remove() {
	local app_dir
	DISCORD_SYSTEM24_UNPATCH_DIR=''
	if ! app_dir=$(discord_system24_newest_app_dir); then
		printf 'Plan: skip the Vencord unpatch; no Discord app-* directory exists\n'
	elif [[ ! -e $app_dir/resources/_app.asar ]]; then
		printf 'Plan: skip the Vencord unpatch; %s is not patched\n' "$app_dir"
	elif ! command -v vencord-installer-cli >/dev/null 2>&1; then
		printf 'Error: vencord-installer-cli is missing, so %s cannot be unpatched.\n' "$app_dir" >&2
		return 1
	else
		DISCORD_SYSTEM24_UNPATCH_DIR=$app_dir
		printf 'Plan: unpatch the newest Discord app directory\n'
		printf '  Discord app: %s (patched)\n' "$app_dir"
		printf '  Run: vencord-installer-cli --uninstall --location %s\n' "$app_dir"
		printf '  Verify: %s/resources/_app.asar is gone.\n' "$app_dir"
	fi
	printf 'Plan: delete %s\n' "$(discord_system24_theme_path)"
}

# Unpatches the planned app-*, then deletes the Vencord theme. Fails before
# the theme when the unpatch cannot be verified.
discord_system24_remove_client_state() {
	local app_dir=$DISCORD_SYSTEM24_UNPATCH_DIR
	if [[ -n $app_dir ]]; then
		if ! vencord-installer-cli --uninstall --location "$app_dir"; then
			printf 'Error: vencord-installer-cli could not unpatch %s.\n' "$app_dir" >&2
			return 1
		fi
		if [[ -e $app_dir/resources/_app.asar ]]; then
			printf 'Error: unpatch verification failed: %s/resources/_app.asar remains.\n' "$app_dir" >&2
			return 1
		fi
		printf 'Discord unpatched and verified: %s\n' "$app_dir"
	fi
	rm -f -- "$(discord_system24_theme_path)"
}

patch_discord_with_vencord() {
	local app_dir
	if ! command -v vencord-installer-cli >/dev/null 2>&1; then
		printf 'Error: vencord-installer-cli is missing.\n' >&2
		printf 'Recovery: apply the discord-system24 package to install vencord-installer-cli-bin, then choose Patch Discord with Vencord in the Dotfiles wizard.\n' >&2
		return 1
	fi
	if ! app_dir=$(discord_system24_newest_app_dir); then
		printf 'Error: no Discord app-* directory exists in %s/discord.\n' "$(discord_system24_config_home)" >&2
		printf 'Recovery: start Discord once so it installs its app directory, then choose Patch Discord with Vencord in the Dotfiles wizard.\n' >&2
		return 1
	fi
	inspect_omarchy stdout
	printf 'Plan: patch the newest Discord app directory with Vencord\n'
	printf '  Discord app: %s\n' "$app_dir"
	printf '  Run: vencord-installer-cli --repair --location %s\n' "$app_dir"
	printf '  Verify: %s/resources/_app.asar exists.\n' "$app_dir"
	printf '  Discord will not be started or stopped.\n'
	if ! wizard_confirm 'Patch Discord with Vencord?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true ]] && ! wizard_confirm 'Continue despite the Omarchy version mismatch?'; then
		printf 'Recovery: review compatibility, then choose Patch Discord with Vencord in the Dotfiles wizard.\n' >&2
		return 1
	fi
	if ! vencord-installer-cli --repair --location "$app_dir"; then
		printf 'Error: vencord-installer-cli could not patch %s.\n' "$app_dir" >&2
		printf 'Recovery: resolve the installer error, then choose Patch Discord with Vencord in the Dotfiles wizard.\n' >&2
		return 1
	fi
	if [[ ! -e $app_dir/resources/_app.asar ]]; then
		printf 'Error: patch verification failed: %s/resources/_app.asar is missing.\n' "$app_dir" >&2
		printf 'Recovery: inspect the installer output, then choose Patch Discord with Vencord in the Dotfiles wizard.\n' >&2
		return 1
	fi
	printf 'Discord patched and verified: %s\n' "$app_dir"
	printf 'Restart Discord to load Vencord.\n'
}
