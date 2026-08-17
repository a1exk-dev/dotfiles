readonly CLEANUP_MANIFEST="$REPOSITORY_ROOT/cleanup.json"
readonly CLEANUP_APPLICATION_DIR="$HOME/.local/share/applications"
readonly CLEANUP_PROTECTED_PACKAGES=(
	base
	base-devel
	filesystem
	glibc
	amd-ucode
	intel-ucode
	linux
	linux-firmware
	linux-hardened
	linux-lts
	linux-zen
	networkmanager
	systemd
	sudo
	bash
	pacman
	omarchy
	yay
	coreutils
	findutils
	grep
	jq
	gum
)

declare -a CLEANUP_SELECTION=()
declare -a CLEANUP_PROTECTED_ACTIVE=()

cleanup_package_is_protected() {
	local package=$1 protected
	for protected in "${CLEANUP_PROTECTED_ACTIVE[@]:-${CLEANUP_PROTECTED_PACKAGES[@]}}"; do
		[[ $package != "$protected" ]] || return 0
	done
	return 1
}

validate_cleanup_manifest() {
	if ! jq -e '
		type == "object" and
		(keys == ["packages", "tuis", "web_apps"]) and
		(.packages | type == "array") and
		(.web_apps | type == "array") and
		(.tuis | type == "array") and
		all(.packages[]; type == "string") and
		all(.web_apps[]; type == "string") and
		all(.tuis[]; type == "string")
	' "$CLEANUP_MANIFEST" >/dev/null 2>&1; then
		printf 'Error: invalid cleanup manifest: %s\n' "$CLEANUP_MANIFEST" >&2
		return 1
	fi

	local group name item_type encoded_name
	for group in packages web_apps tuis; do
		if [[ $(jq ".${group} | length" "$CLEANUP_MANIFEST") -ne $(jq ".${group} | unique | length" "$CLEANUP_MANIFEST") ]]; then
			printf 'Error: duplicate cleanup %s entry\n' "${group//_/ }" >&2
			return 1
		fi
		while IFS= read -r encoded_name; do
			name=$(jq -r . <<<"$encoded_name")
			if [[ $group == packages ]]; then
				if [[ ! $name =~ ^[a-z0-9][a-z0-9@._+-]*$ ]]; then
					printf 'Error: invalid cleanup package name: %s\n' "$name" >&2
					return 1
				fi
			elif [[ -z $name || $name == . || $name == .. || $name == *'/'* || $name == *','* || $name =~ ^[[:space:]] || $name =~ [[:space:]]$ ]] || printf '%s' "$name" | LC_ALL=C grep -q '[[:cntrl:]]'; then
				[[ $group == web_apps ]] && item_type='web app' || item_type='TUI'
				printf 'Error: invalid cleanup %s name: %s\n' "$item_type" "$name" >&2
				return 1
			fi
		done < <(jq -c ".${group}[]" "$CLEANUP_MANIFEST")
	done

	CLEANUP_PROTECTED_ACTIVE=("${CLEANUP_PROTECTED_PACKAGES[@]}")
	while IFS= read -r name; do
		if cleanup_package_is_protected "$name"; then
			printf 'Error: protected cleanup package default: %s\n' "$name" >&2
			return 1
		fi
	done < <(jq -r '.packages[]' "$CLEANUP_MANIFEST")
}

cleanup_collect_protected_packages() {
	CLEANUP_PROTECTED_ACTIVE=("${CLEANUP_PROTECTED_PACKAGES[@]}")
	local command_path provider runtime
	local -a runtimes=(bash jq find grep sort basename mktemp rm pacman yay omarchy)
	if wizard_uses_gum; then
		runtimes+=(gum)
	fi
	for runtime in "${runtimes[@]}"; do
		command_path=$(command -v "$runtime") || continue
		while IFS= read -r provider; do
			[[ -n $provider ]] && CLEANUP_PROTECTED_ACTIVE+=("$provider")
		done < <(pacman -Qqo "$command_path" 2>/dev/null || true)
	done
}

cleanup_discover_packages() {
	local package explicit_packages
	explicit_packages=$(yay -Qqe) || return 1
	while IFS= read -r package; do
		[[ -n $package ]] || continue
		cleanup_package_is_protected "$package" || printf '%s\n' "$package"
	done <<<"$explicit_packages" | LC_ALL=C sort -u
}

cleanup_launcher_matches() {
	local type=$1 file=$2
	case $type in
		web_app) grep -q '^Exec=.*\(omarchy-launch-webapp\|omarchy-webapp-handler\).*' "$file" ;;
		tui) grep -qE '^Exec=.*(\$TERMINAL|xdg-terminal-exec).*-e' "$file" ;;
	esac
}

cleanup_discover_launchers() {
	local type=$1 file find_output find_status processing_status remove_status
	[[ -d $CLEANUP_APPLICATION_DIR ]] || return 0
	if ! find_output=$(mktemp); then
		printf 'Error: could not create temporary launcher discovery file.\n' >&2
		return 1
	fi
	if find "$CLEANUP_APPLICATION_DIR" -name '*.desktop' -print0 >"$find_output"; then
		find_status=0
	else
		find_status=$?
	fi
	if ((find_status != 0)); then
		rm -f -- "$find_output" || true
		return "$find_status"
	fi
	while IFS= read -r -d '' file; do
		if cleanup_launcher_matches "$type" "$file"; then
			basename "${file%.desktop}"
		fi
	done <"$find_output" | LC_ALL=C sort -u
	processing_status=$?
	if rm -f -- "$find_output"; then
		remove_status=0
	else
		remove_status=$?
	fi
	((processing_status == 0)) || return "$processing_status"
	return "$remove_status"
}

cleanup_select_many() {
	local prompt=$1 candidates_name=$2 defaults_name=$3
	local -n candidates_ref=$candidates_name
	local -n defaults_ref=$defaults_name
	CLEANUP_SELECTION=()
	printf 'Selection: %s\n' "$prompt"
	if ((${#candidates_ref[@]} == 0)); then
		printf '  No candidates available.\n'
		return 0
	fi

	local candidate default selected=false
	local -a selected_args=()
	for default in "${defaults_ref[@]}"; do
		selected_args+=("$default")
	done
	if wizard_uses_gum; then
		local selected_csv='' gum_output gum_status
		if ((${#selected_args[@]} > 0)); then
			local IFS=,
			selected_csv=${selected_args[*]}
		fi
		if gum_output=$(gum choose --no-limit --header "$prompt" --selected="$selected_csv" "${candidates_ref[@]}"); then
			[[ -z $gum_output ]] || mapfile -t CLEANUP_SELECTION <<<"$gum_output"
			return 0
		else
			gum_status=$?
			return "$gum_status"
		fi
	fi

	local index=1 marker
	for candidate in "${candidates_ref[@]}"; do
		marker=' '
		for default in "${defaults_ref[@]}"; do
			[[ $candidate != "$default" ]] || marker=x
		done
		printf '  %d. [%s] %s\n' "$index" "$marker" "$candidate"
		index=$((index + 1))
	done
	printf 'Choose final selections by number (comma-separated, Enter keeps defaults, 0 selects none): '
	local answer
	read -r answer || answer=''
	if [[ -z $answer ]]; then
		CLEANUP_SELECTION=("${defaults_ref[@]}")
		return 0
	fi
	[[ $answer == 0 ]] && return 0
	answer=${answer//,/ }
	local choice
	for choice in $answer; do
		if [[ ! $choice =~ ^[0-9]+$ || $choice -lt 1 || $choice -gt ${#candidates_ref[@]} ]]; then
			printf 'Error: invalid selection for %s: %s\n' "$prompt" "$choice" >&2
			return 1
		fi
		candidate=${candidates_ref[$((choice - 1))]}
		selected=false
		for default in "${CLEANUP_SELECTION[@]}"; do
			[[ $candidate != "$default" ]] || selected=true
		done
		[[ $selected == true ]] || CLEANUP_SELECTION+=("$candidate")
	done
}

cleanup_installed_defaults() {
	local candidates_name=$1 manifest_group=$2 installed_name=$3 missing_name=$4
	local -n candidates_ref=$candidates_name
	local -n installed_ref=$installed_name
	local -n missing_ref=$missing_name
	local default candidate found
	while IFS= read -r default; do
		found=false
		for candidate in "${candidates_ref[@]}"; do
			if [[ $candidate == "$default" ]]; then
				installed_ref+=("$default")
				found=true
				break
			fi
		done
		[[ $found == true ]] || missing_ref+=("$default")
	done < <(jq -r ".${manifest_group}[]" "$CLEANUP_MANIFEST")
}

cleanup_print_group() {
	local label=$1 items_name=$2
	local -n items_ref=$items_name
	printf '  %s:\n' "$label"
	if ((${#items_ref[@]} == 0)); then
		printf '    none\n'
	else
		printf '    %s\n' "${items_ref[@]}"
	fi
}

cleanup_launcher_present() {
	local type=$1 name=$2 file find_output find_status remove_status
	[[ -d $CLEANUP_APPLICATION_DIR ]] || return 1
	if ! find_output=$(mktemp); then
		printf 'Error: could not create temporary launcher verification file for %s.\n' "$name" >&2
		return 2
	fi
	if find "$CLEANUP_APPLICATION_DIR" -name '*.desktop' -print0 >"$find_output"; then
		find_status=0
	else
		find_status=$?
	fi
	if ((find_status != 0)); then
		rm -f -- "$find_output" || true
		printf 'Error: could not inspect Omarchy launchers while verifying %s.\n' "$name" >&2
		return 2
	fi
	local present=false
	while IFS= read -r -d '' file; do
		if [[ $(basename "${file%.desktop}") == "$name" ]] && cleanup_launcher_matches "$type" "$file"; then
			present=true
			break
		fi
	done <"$find_output"
	if rm -f -- "$find_output"; then
		remove_status=0
	else
		remove_status=$?
	fi
	if ((remove_status != 0)); then
		printf 'Error: could not remove temporary launcher verification file for %s.\n' "$name" >&2
		return 2
	fi
	[[ $present == true ]]
}

cleanup_report_failure() {
	local failed_index=$1 labels_name=$2
	local -n labels_ref=$labels_name
	printf 'Cleanup incomplete items:\n' >&2
	local index
	for ((index = failed_index; index < ${#labels_ref[@]}; index++)); do
		printf '  %s\n' "${labels_ref[$index]}" >&2
	done
	printf 'Recovery: rerun the Dotfiles wizard and choose Clean up Omarchy applications.\n' >&2
	return 1
}

cleanup_applications() {
	validate_cleanup_manifest || return 1
	local command
	for command in yay pacman find grep sort basename mktemp rm omarchy; do
		if ! command -v "$command" >/dev/null 2>&1; then
			printf 'Error: missing cleanup runtime command: %s\n' "$command" >&2
			return 1
		fi
	done
	inspect_omarchy stdout
	cleanup_collect_protected_packages

	local -a package_candidates=() web_app_candidates=() tui_candidates=()
	local discovered
	if ! discovered=$(cleanup_discover_packages); then
		printf 'Error: could not discover explicitly installed packages with yay -Qqe.\n' >&2
		return 1
	fi
	[[ -z $discovered ]] || mapfile -t package_candidates <<<"$discovered"
	if ! discovered=$(cleanup_discover_launchers web_app); then
		printf 'Error: could not discover Omarchy web app launchers.\n' >&2
		return 1
	fi
	[[ -z $discovered ]] || mapfile -t web_app_candidates <<<"$discovered"
	if ! discovered=$(cleanup_discover_launchers tui); then
		printf 'Error: could not discover Omarchy TUI launchers.\n' >&2
		return 1
	fi
	[[ -z $discovered ]] || mapfile -t tui_candidates <<<"$discovered"
	local -a package_defaults=() web_app_defaults=() tui_defaults=() missing_packages=() missing_web_apps=() missing_tuis=()
	cleanup_installed_defaults package_candidates packages package_defaults missing_packages
	cleanup_installed_defaults web_app_candidates web_apps web_app_defaults missing_web_apps
	cleanup_installed_defaults tui_candidates tuis tui_defaults missing_tuis
	if ((${#missing_packages[@]} + ${#missing_web_apps[@]} + ${#missing_tuis[@]} > 0)); then
		printf 'Unavailable cleanup defaults:\n'
		((${#missing_packages[@]} == 0)) || printf '  Packages: %s\n' "${missing_packages[*]}"
		((${#missing_web_apps[@]} == 0)) || printf '  Web apps: %s\n' "${missing_web_apps[*]}"
		((${#missing_tuis[@]} == 0)) || printf '  TUIs: %s\n' "${missing_tuis[*]}"
	fi

	local -a selected_packages=() selected_web_apps=() selected_tuis=()
	local selection_status
	if cleanup_select_many 'Packages to remove' package_candidates package_defaults; then
		:
	else
		selection_status=$?
		return "$selection_status"
	fi
	selected_packages=("${CLEANUP_SELECTION[@]}")
	if cleanup_select_many 'Web apps to remove' web_app_candidates web_app_defaults; then
		:
	else
		selection_status=$?
		return "$selection_status"
	fi
	selected_web_apps=("${CLEANUP_SELECTION[@]}")
	if cleanup_select_many 'TUIs to remove' tui_candidates tui_defaults; then
		:
	else
		selection_status=$?
		return "$selection_status"
	fi
	selected_tuis=("${CLEANUP_SELECTION[@]}")
	if ((${#selected_packages[@]} + ${#selected_web_apps[@]} + ${#selected_tuis[@]} == 0)); then
		printf 'No cleanup items selected; no changes made.\n'
		return 0
	fi

	printf 'Plan: application cleanup\n'
	cleanup_print_group 'Web apps' selected_web_apps
	cleanup_print_group 'TUIs' selected_tuis
	cleanup_print_group 'Packages' selected_packages
	if ! wizard_confirm 'Apply this complete cleanup plan?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true ]]; then
		if ! wizard_confirm 'Continue despite the Omarchy version mismatch?'; then
			printf 'Confirmation required: review Omarchy compatibility, then choose Clean up Omarchy applications in the Dotfiles wizard.\n' >&2
			return 1
		fi
		printf 'Approval: Omarchy version mismatch accepted interactively\n'
	fi

	local -a labels=()
	local name verification_status installed_packages installed=false installed_name
	for name in "${selected_web_apps[@]}"; do labels+=("Web app: $name"); done
	for name in "${selected_tuis[@]}"; do labels+=("TUI: $name"); done
	for name in "${selected_packages[@]}"; do labels+=("Package: $name"); done
	local index=0
	for name in "${selected_web_apps[@]}"; do
		if ! omarchy webapp remove "$name"; then
			cleanup_report_failure "$index" labels
			return 1
		fi
		if cleanup_launcher_present web_app "$name"; then
			cleanup_report_failure "$index" labels
			return 1
		else
			verification_status=$?
			if ((verification_status != 1)); then
				cleanup_report_failure "$index" labels
				return 1
			fi
		fi
		printf 'Removed and verified web app: %s\n' "$name"
		index=$((index + 1))
	done
	for name in "${selected_tuis[@]}"; do
		if ! omarchy tui remove "$name"; then
			cleanup_report_failure "$index" labels
			return 1
		fi
		if cleanup_launcher_present tui "$name"; then
			cleanup_report_failure "$index" labels
			return 1
		else
			verification_status=$?
			if ((verification_status != 1)); then
				cleanup_report_failure "$index" labels
				return 1
			fi
		fi
		printf 'Removed and verified TUI: %s\n' "$name"
		index=$((index + 1))
	done
	for name in "${selected_packages[@]}"; do
		if ! omarchy pkg drop "$name"; then
			cleanup_report_failure "$index" labels
			return 1
		fi
		if ! installed_packages=$(pacman -Qq); then
			printf 'Error: could not query installed packages while verifying %s.\n' "$name" >&2
			cleanup_report_failure "$index" labels
			return 1
		fi
		installed=false
		while IFS= read -r installed_name; do
			if [[ $installed_name == "$name" ]]; then
				installed=true
				break
			fi
		done <<<"$installed_packages"
		if [[ $installed == true ]]; then
			cleanup_report_failure "$index" labels
			return 1
		fi
		printf 'Removed and verified package: %s\n' "$name"
		index=$((index + 1))
	done
}
