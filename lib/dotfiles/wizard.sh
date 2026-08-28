wizard_choose() {
	local prompt=$1
	shift
	if wizard_uses_gum; then
		gum choose --header "$prompt" "$@"
		return
	fi
	printf '%s\n' "$prompt" >&2
	local index=1 option selection
	for option in "$@"; do
		printf '  %d. %s\n' "$index" "$option" >&2
		index=$((index + 1))
	done
	printf 'Choice: ' >&2
	read -r selection || selection=''
	if [[ ! $selection =~ ^[0-9]+$ || $selection -lt 1 || $selection -gt $# ]]; then
		return 1
	fi
	printf '%s\n' "${!selection}"
}

wizard_input() {
	local prompt=$1
	if wizard_uses_gum; then
		gum input --prompt "$prompt: "
		return
	fi
	local value
	printf '%s: ' "$prompt" >&2
	read -r value || value=''
	[[ -n $value ]] || return 1
	printf '%s\n' "$value"
}

wizard_package() {
	validate_catalog || return 1
	local -a choices=(Cancel)
	local package
	while IFS= read -r package; do choices+=("$package"); done < <(jq -r '.packages[].name' "$PACKAGE_CATALOG")
	if ((${#choices[@]} == 1)); then
		printf 'No packages are available.\n' >&2
		return 1
	fi
	if ! package=$(wizard_choose 'Choose a package (none selected by default)' "${choices[@]}") || [[ $package == Cancel ]]; then
		printf 'No package selected.\n' >&2
		return 1
	fi
	printf '%s\n' "$package"
}

wizard_packages() {
	validate_catalog || return 1
	local -a packages=()
	mapfile -t packages < <(jq -r '.packages[].name' "$PACKAGE_CATALOG")
	WIZARD_PACKAGES=()
	if ((${#packages[@]} == 0)); then
		printf 'No packages are available.\n'
		return 0
	fi
	if wizard_uses_gum; then
		local output selection_status
		if output=$(gum choose --no-limit --header 'Choose Stow packages (none selected by default)' "${packages[@]}"); then
			[[ -z $output ]] || mapfile -t WIZARD_PACKAGES <<<"$output"
			return 0
		else
			selection_status=$?
			return "$selection_status"
		fi
	fi
	printf 'Choose Stow packages (none selected by default)\n'
	local index=1 package answer choice
	for package in "${packages[@]}"; do printf '  %d. [ ] %s\n' "$index" "$package"; index=$((index + 1)); done
	printf 'Choose packages by number (comma-separated, Enter selects none): '
	read -r answer || answer=''
	[[ -n $answer ]] || return 0
	answer=${answer//,/ }
	for choice in $answer; do
		if [[ ! $choice =~ ^[0-9]+$ || $choice -lt 1 || $choice -gt ${#packages[@]} ]]; then
			printf 'Error: invalid Stow package selection: %s\n' "$choice" >&2
			return 1
		fi
		WIZARD_PACKAGES+=("${packages[$((choice - 1))]}")
	done
}

wizard_run_action() {
	local action=$1 package relative
	case $action in
		guided) guided_setup ;;
		status) status ;;
		check) check ;;
		apply)
			wizard_packages || return $?
			apply_packages "${WIZARD_PACKAGES[@]}"
			;;
		migrate)
			package=$(wizard_package) || return 0
			relative=$(wizard_input 'Home-relative target path') || { printf 'No migration path selected.\n'; return 0; }
			migrate_target "$package" "$relative" --interactive
			;;
		remove)
			package=$(wizard_package) || return 0
			remove_package "$package" --interactive
			;;
		prerequisites) setup_prerequisites --interactive ;;
		cleanup) cleanup_applications ;;
		skills) install_skills --interactive ;;
		skills-update) update_skills --interactive ;;
		modem) recover_zte_usb_modem ;;
		brave) manage_brave_policy ;;
		telegram-theme) manage_telegram_theme ;;
		wallpapers) manage_wallpapers ;;
		wallpapers-apply) apply_wallpapers ;;
		wallpapers-remove) remove_wallpapers ;;
		exit) printf 'No action selected.\n' ;;
		*) printf 'Error: unknown wizard action: %s\n' "$action" >&2; return 2 ;;
	esac
}

guided_setup() {
	printf 'Guided setup\n'
	printf 'Guided phase 1: prerequisite preparation\n'
	setup_prerequisites --interactive --required || { printf 'Recovery: choose Prepare prerequisites in the Dotfiles wizard.\n' >&2; return 1; }
	printf 'Guided phase 2: pinned global skills installation\n'
	install_skills --interactive || { printf 'Recovery: choose Install pinned global skills in the Dotfiles wizard.\n' >&2; return 1; }
	printf 'Guided phase 3: application cleanup\n'
	cleanup_applications || { printf 'Recovery: choose Clean up Omarchy applications in the Dotfiles wizard.\n' >&2; return 1; }
	printf 'Guided phase 4: Stow application\n'
	if ! wizard_packages; then
		printf 'Recovery: choose Apply Stow packages in the Dotfiles wizard.\n' >&2
		return 1
	fi
	apply_packages "${WIZARD_PACKAGES[@]}" || { printf 'Recovery: choose Apply Stow packages in the Dotfiles wizard.\n' >&2; return 1; }
	printf 'Guided phase 5: Wallpaper library deployment\n'
	local wallpaper_outcome
	if apply_wallpapers; then
		wallpaper_outcome=0
	else
		wallpaper_outcome=$?
	fi
	case $WALLPAPER_OPERATION_CONTEXT in
		"$WALLPAPER_OPERATION_CONTEXT_ORDINARY") ;;
		"$WALLPAPER_OPERATION_CONTEXT_RECOVERY_COMPLETED")
			printf 'Recovery: choose Apply wallpapers in the Dotfiles wizard.\n' >&2
			return 1
			;;
		*)
			printf 'Recovery: choose Apply wallpapers in the Dotfiles wizard.\n' >&2
			return 1
			;;
	esac
	if ((wallpaper_outcome != 0)); then
		printf 'Recovery: choose Apply wallpapers in the Dotfiles wizard.\n' >&2
		return "$wallpaper_outcome"
	fi
	printf 'Guided phase 6: optional Brave policy\n'
	local brave_outcome
	if apply_brave_policy; then
		brave_outcome=$BRAVE_OUTCOME_SUCCESS
	else
		brave_outcome=$?
	fi
	case $BRAVE_OPERATION_CONTEXT in
		"$BRAVE_OPERATION_CONTEXT_ORDINARY") ;;
		"$BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED"|"$BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED")
			printf 'Recovery: choose Manage Brave policy in the Dotfiles wizard.\n' >&2
			return 1
			;;
		*)
			printf 'Recovery: choose Manage Brave policy in the Dotfiles wizard.\n' >&2
			return 1
			;;
	esac
	case $brave_outcome in
		"$BRAVE_OUTCOME_SUCCESS") ;;
		"$BRAVE_OUTCOME_DECLINED") printf 'Guided phase 6 skipped: Brave policy plan declined.\n' ;;
		"$BRAVE_OUTCOME_UNAVAILABLE") printf 'Guided phase 6 skipped: no supported Brave browser is installed.\n' ;;
		*)
			printf 'Recovery: choose Manage Brave policy in the Dotfiles wizard.\n' >&2
			return "$brave_outcome"
			;;
	esac
	printf 'Guided setup complete.\n'
}

wizard() {
	printf 'Dotfiles wizard\n'
	local choice
	local -a labels=(
		'Guided setup'
		'Package status'
		'Run structural checks'
		'Apply Stow packages'
		'Migrate existing target'
		'Remove Stow package'
		'Prepare prerequisites'
		'Clean up Omarchy applications'
		'Install pinned global skills'
		'Update pinned global skills'
		'Recover ZTE USB modem'
		'Manage Brave policy'
		'Manage Telegram theme'
		'Manage wallpapers'
		'Apply wallpapers'
		'Remove deployed wallpapers'
		'Exit'
	)
	local -a actions=(guided status check apply migrate remove prerequisites cleanup skills skills-update modem brave telegram-theme wallpapers wallpapers-apply wallpapers-remove exit)
	if ! choice=$(wizard_choose 'Choose an action (none selected by default)' "${labels[@]}"); then
		printf 'No action selected.\n'
		return 0
	fi
	local index
	for index in "${!labels[@]}"; do
		if [[ ${labels[$index]} == "$choice" ]]; then
			wizard_run_action "${actions[$index]}"
			return
		fi
	done
	printf 'No action selected.\n'
}
