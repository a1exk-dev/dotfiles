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
	while IFS= read -r package; do
		choices+=("$package")
	done < <(jq -r '.packages[].name' "$PACKAGE_CATALOG")
	if ((${#choices[@]} == 1)); then
		printf 'No packages are available.\n' >&2
		return 1
	fi
	if ! package=$(wizard_choose 'Choose a package (none selected by default)' "${choices[@]}"); then
		printf 'No package selected.\n' >&2
		return 1
	fi
	if [[ $package == Cancel ]]; then
		printf 'No package selected.\n' >&2
		return 1
	fi
	printf '%s\n' "$package"
}

wizard() {
	printf 'Dotfiles wizard\n'
	local action package relative
	local -a actions=(
		'Exit'
		'Package status'
		'Apply package'
		'Migrate existing target'
		'Remove package'
		'Set up prerequisites'
		'Set up global skills'
		'Update global skills'
		'Run structural checks'
	)
	if ! action=$(wizard_choose 'Choose an action (none selected by default)' "${actions[@]}"); then
		printf 'No action selected.\n'
		return 0
	fi
	case $action in
		Exit)
			printf 'No action selected.\n'
			;;
		'Package status') status ;;
		'Apply package')
			package=$(wizard_package) || return 0
			apply_package "$package" --interactive
			;;
		'Migrate existing target')
			package=$(wizard_package) || return 0
			if ! relative=$(wizard_input 'Home-relative target path'); then
				printf 'No migration path selected.\n'
				return 0
			fi
			migrate_target "$package" "$relative" --interactive
			;;
		'Remove package')
			package=$(wizard_package) || return 0
			remove_package "$package" --interactive
			;;
		'Set up prerequisites') setup_prerequisites --interactive ;;
		'Set up global skills') install_skills --interactive ;;
		'Update global skills') update_skills --interactive ;;
		'Run structural checks') check ;;
		*)
			printf 'No action selected.\n'
			return 0
			;;
	esac
}
