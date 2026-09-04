declare -a OPTIONAL_APPLICATION_SELECTION=()
declare -a OPTIONAL_APPLICATION_ORDER=()
declare -a OPTIONAL_APPLICATION_COMPLETED=()
declare -A OPTIONAL_APPLICATION_COMPLETED_IDS=()
declare -A OPTIONAL_APPLICATION_PACKAGE_STATUS=()
declare -A OPTIONAL_APPLICATION_COMMAND_STATUS=()
declare -A OPTIONAL_APPLICATION_PACKAGE_PRESENCE=()

validate_application_catalog() {
	if ! jq -e 'type == "object" and (keys == ["applications"]) and (.applications | type == "array")' \
		"$APPLICATION_CATALOG" >/dev/null 2>&1; then
		printf 'Error: invalid optional application catalog: %s\n' "$APPLICATION_CATALOG" >&2
		return 1
	fi

	local count index id name description package conflict
	count=$(jq '.applications | length' "$APPLICATION_CATALOG")
	for ((index = 0; index < count; index++)); do
		if ! jq -e ".applications[$index] | type == \"object\" and (keys == [\"command\", \"conflicts\", \"description\", \"id\", \"name\", \"package\", \"source\"])" \
			"$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application metadata at index %d\n' "$index" >&2
			return 1
		fi
		if ! jq -e ".applications[$index].id | type == \"string\"" "$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application identifier at index %d: identifier must be a string\n' "$index" >&2
			return 1
		fi
		if ! jq -e ".applications[$index].id | test(\"^[a-z][a-z0-9-]*\\\\z\")" "$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application identifier at index %d\n' "$index" >&2
			return 1
		fi
		id=$(jq -r ".applications[$index].id" "$APPLICATION_CATALOG")
		if [[ $(jq --arg id "$id" '[.applications[] | select(.id == $id)] | length' "$APPLICATION_CATALOG") -ne 1 ]]; then
			printf 'Error: duplicate optional application identifier: %s\n' "$id" >&2
			return 1
		fi
		if ! jq -e ".applications[$index].name | type == \"string\" and test(\"[^[:space:]]\") and test(\"^[^[:cntrl:]]*\\\\z\")" "$APPLICATION_CATALOG" >/dev/null ||
			! jq -e ".applications[$index].description | type == \"string\" and test(\"[^[:space:]]\") and test(\"^[^[:cntrl:]]*\\\\z\")" "$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application name or description: %s\n' "$id" >&2
			return 1
		fi
		name=$(jq -r ".applications[$index].name" "$APPLICATION_CATALOG")
		description=$(jq -r ".applications[$index].description" "$APPLICATION_CATALOG")
		if ! jq -e ".applications[$index].package | type == \"string\"" "$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application package name for %s: package must be a string\n' "$id" >&2
			return 1
		fi
		if ! jq -e ".applications[$index].package | test(\"^[a-z0-9@_+][a-z0-9@._+-]*\\\\z\")" "$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application package name for %s\n' "$id" >&2
			return 1
		fi
		package=$(jq -r ".applications[$index].package" "$APPLICATION_CATALOG")
		if [[ $(jq --arg package "$package" '[.applications[] | select(.package == $package)] | length' "$APPLICATION_CATALOG") -ne 1 ]]; then
			printf 'Error: duplicate optional application package name: %s\n' "$package" >&2
			return 1
		fi
		if ! jq -e ".applications[$index].source | type == \"string\" and (. == \"official\" or . == \"aur\")" \
			"$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application package source for %s\n' "$id" >&2
			return 1
		fi
		if ! jq -e ".applications[$index].command | type == \"string\" and test(\"^[a-z][a-z0-9._+-]*\\\\z\")" \
			"$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application command for %s\n' "$id" >&2
			return 1
		fi
		if ! jq -e ".applications[$index].conflicts | type == \"array\" and all(.[]; type == \"string\" and test(\"^[a-z0-9@_+][a-z0-9@._+-]*\\\\z\")) and (length == (unique | length))" \
			"$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: invalid optional application conflicts for %s\n' "$id" >&2
			return 1
		fi
		while IFS= read -r conflict; do
			if [[ $conflict == "$package" ]]; then
				printf 'Error: optional application %s conflicts with itself: %s\n' "$id" "$package" >&2
				return 1
			fi
		done < <(jq -r ".applications[$index].conflicts[]" "$APPLICATION_CATALOG")
	done
}

optional_application_value() {
	local id=$1 field=$2
	jq -r --arg id "$id" --arg field "$field" '.applications[] | select(.id == $id) | .[$field]' "$APPLICATION_CATALOG"
}

optional_application_package_present() {
	local package=$1
	if [[ ! ${OPTIONAL_APPLICATION_PACKAGE_PRESENCE[$package]+present} ]]; then
		if omarchy pkg present "$package"; then
			OPTIONAL_APPLICATION_PACKAGE_PRESENCE["$package"]=installed
		else
			OPTIONAL_APPLICATION_PACKAGE_PRESENCE["$package"]=missing
		fi
	fi
	[[ ${OPTIONAL_APPLICATION_PACKAGE_PRESENCE[$package]} == installed ]]
}

optional_application_command_available() {
	command -v -- "$1" >/dev/null 2>&1
}

optional_application_resolve_selection() {
	OPTIONAL_APPLICATION_ORDER=()
	local selected id
	for selected in "$@"; do
		if [[ -z $selected ]]; then
			printf 'Error: unknown optional application selection: %s\n' "$selected" >&2
			return 1
		fi
		if ! jq -e --arg id "$selected" 'any(.applications[]; .id == $id)' "$APPLICATION_CATALOG" >/dev/null; then
			printf 'Error: unknown optional application selection: %s\n' "$selected" >&2
			return 1
		fi
	done
	while IFS= read -r id; do
		for selected in "$@"; do
			[[ $selected != "$id" ]] || { OPTIONAL_APPLICATION_ORDER+=("$id"); break; }
		done
	done < <(jq -r '.applications[].id' "$APPLICATION_CATALOG")
}

wizard_optional_applications() {
	validate_application_catalog || return 1
	OPTIONAL_APPLICATION_SELECTION=()
	local -a ids=() options=()
	local id name description
	mapfile -t ids < <(jq -r '.applications[].id' "$APPLICATION_CATALOG")
	if ((${#ids[@]} == 0)); then
		printf 'No optional applications are available.\n'
		return 0
	fi
	for id in "${ids[@]}"; do
		name=$(optional_application_value "$id" name)
		description=$(optional_application_value "$id" description)
		options+=("$name — $description"$'\t'"$id")
	done
	if wizard_uses_gum; then
		local output selection_status
		if output=$(gum choose --no-limit --header 'Choose optional applications (none selected by default)' --label-delimiter=$'\t' "${options[@]}"); then
			[[ -z $output ]] || mapfile -t OPTIONAL_APPLICATION_SELECTION <<<"$output"
			return 0
		else
			selection_status=$?
			return "$selection_status"
		fi
	fi

	printf 'Choose optional applications (none selected by default)\n'
	local index=1 answer choice
	for id in "${ids[@]}"; do
		name=$(optional_application_value "$id" name)
		description=$(optional_application_value "$id" description)
		printf '  %d. [ ] %s — %s\n' "$index" "$name" "$description"
		index=$((index + 1))
	done
	printf 'Choose applications by number (comma-separated, Enter selects none): '
	read -r answer || answer=''
	[[ -n $answer ]] || return 0
	answer=${answer//,/ }
	for choice in $answer; do
		if [[ ! $choice =~ ^[0-9]+$ || $choice -lt 1 || $choice -gt ${#ids[@]} ]]; then
			printf 'Error: invalid optional application selection: %s\n' "$choice" >&2
			return 1
		fi
		OPTIONAL_APPLICATION_SELECTION+=("${ids[$((choice - 1))]}")
	done
}

optional_application_print_plan() {
	printf 'Plan: optional application installation\n'
	local id name package source status
	for id in "${OPTIONAL_APPLICATION_ORDER[@]}"; do
		name=$(optional_application_value "$id" name)
		package=$(optional_application_value "$id" package)
		source=$(optional_application_value "$id" source)
		status=${OPTIONAL_APPLICATION_PACKAGE_STATUS[$id]}
		if [[ $status == installed && ${OPTIONAL_APPLICATION_COMMAND_STATUS[$id]} == unavailable ]]; then
			status='installed (command unavailable)'
		fi
		printf '  %s (%s, %s): %s\n' "$name" "$package" "$source" "$status"
	done
}

optional_application_report_failure() {
	printf 'Optional application installation incomplete.\n' >&2
	printf 'Completed applications:\n' >&2
	if ((${#OPTIONAL_APPLICATION_COMPLETED[@]} == 0)); then
		printf '  none\n' >&2
	else
		printf '  %s\n' "${OPTIONAL_APPLICATION_COMPLETED[@]}" >&2
	fi
	printf 'Incomplete applications:\n' >&2
	local id name package
	for id in "${OPTIONAL_APPLICATION_ORDER[@]}"; do
		[[ ${OPTIONAL_APPLICATION_COMPLETED_IDS[$id]+completed} ]] && continue
		name=$(optional_application_value "$id" name)
		package=$(optional_application_value "$id" package)
		printf '  %s (%s)\n' "$name" "$package" >&2
	done
	printf 'Recovery: resolve the reported issue, then choose Install optional applications in the Dotfiles wizard.\n' >&2
	return 1
}

install_optional_applications() {
	validate_application_catalog || return 1
	optional_application_resolve_selection "$@" || return 1
	if ((${#OPTIONAL_APPLICATION_ORDER[@]} == 0)); then
		printf 'No optional applications selected; no changes made.\n'
		return 0
	fi

	OPTIONAL_APPLICATION_COMPLETED=()
	OPTIONAL_APPLICATION_COMPLETED_IDS=()
	OPTIONAL_APPLICATION_PACKAGE_STATUS=()
	OPTIONAL_APPLICATION_COMMAND_STATUS=()
	OPTIONAL_APPLICATION_PACKAGE_PRESENCE=()
	if ! inspect_omarchy stdout strict || [[ -z $OMARCHY_DETECTED_VERSION ]]; then
		printf 'Error: optional application installation requires a successful Omarchy version probe.\n' >&2
		printf 'Recovery: restore Omarchy version inspection, then choose Install optional applications in the Dotfiles wizard.\n' >&2
		return 1
	fi
	local id package command conflict name source
	local -a detected_conflicts=()
	local -A selected_pending_packages=()
	for id in "${OPTIONAL_APPLICATION_ORDER[@]}"; do
		package=$(optional_application_value "$id" package)
		command=$(optional_application_value "$id" command)
		if optional_application_package_present "$package"; then
			OPTIONAL_APPLICATION_PACKAGE_STATUS["$id"]=installed
			if optional_application_command_available "$command"; then
				OPTIONAL_APPLICATION_COMMAND_STATUS["$id"]=available
			else
				OPTIONAL_APPLICATION_COMMAND_STATUS["$id"]=unavailable
			fi
		else
			OPTIONAL_APPLICATION_PACKAGE_STATUS["$id"]=pending
			OPTIONAL_APPLICATION_COMMAND_STATUS["$id"]=unknown
		fi
	done
	for id in "${OPTIONAL_APPLICATION_ORDER[@]}"; do
		[[ ${OPTIONAL_APPLICATION_PACKAGE_STATUS[$id]} == pending ]] || continue
		package=$(optional_application_value "$id" package)
		selected_pending_packages["$package"]=$id
	done
	for id in "${OPTIONAL_APPLICATION_ORDER[@]}"; do
		[[ ${OPTIONAL_APPLICATION_PACKAGE_STATUS[$id]} == pending ]] || continue
		while IFS= read -r conflict; do
			if [[ ${selected_pending_packages[$conflict]+selected} ]]; then
				detected_conflicts+=("$id:$conflict:${selected_pending_packages[$conflict]}")
			elif optional_application_package_present "$conflict"; then
				detected_conflicts+=("$id:$conflict")
			fi
		done < <(jq -r --arg id "$id" '.applications[] | select(.id == $id) | .conflicts[]' "$APPLICATION_CATALOG")
	done

	optional_application_print_plan
	if ((${#detected_conflicts[@]} > 0)); then
		local pair conflict_id conflict_package selected_id selected_name selected_package
		for pair in "${detected_conflicts[@]}"; do
			IFS=: read -r conflict_id conflict_package selected_id <<<"$pair"
			name=$(optional_application_value "$conflict_id" name)
			package=$(optional_application_value "$conflict_id" package)
			if [[ -n $selected_id ]]; then
				selected_name=$(optional_application_value "$selected_id" name)
				selected_package=$(optional_application_value "$selected_id" package)
				printf 'Conflict: %s (%s) cannot install because its declared conflicting package %s is selected for %s (%s).\n' \
					"$name" "$package" "$conflict_package" "$selected_name" "$selected_package" >&2
			else
				printf 'Conflict: %s (%s) cannot install because conflicting package %s is installed.\n' \
					"$name" "$package" "$conflict_package" >&2
			fi
		done
		printf 'Recovery: resolve the conflicting package choice, then choose Install optional applications in the Dotfiles wizard.\n' >&2
		return 1
	fi

	local index pending=false failed_initial_index=-1
	for index in "${!OPTIONAL_APPLICATION_ORDER[@]}"; do
		id=${OPTIONAL_APPLICATION_ORDER[$index]}
		if [[ ${OPTIONAL_APPLICATION_PACKAGE_STATUS[$id]} == installed ]]; then
			if [[ ${OPTIONAL_APPLICATION_COMMAND_STATUS[$id]} == available ]]; then
				name=$(optional_application_value "$id" name)
				package=$(optional_application_value "$id" package)
				OPTIONAL_APPLICATION_COMPLETED+=("$name ($package)")
				OPTIONAL_APPLICATION_COMPLETED_IDS["$id"]=true
			elif ((failed_initial_index < 0)); then
				failed_initial_index=$index
			fi
		else
			pending=true
		fi
	done
	if ((failed_initial_index >= 0)); then
		id=${OPTIONAL_APPLICATION_ORDER[$failed_initial_index]}
		name=$(optional_application_value "$id" name)
		command=$(optional_application_value "$id" command)
		printf 'Error: optional application verification failed for %s: expected command is unavailable: %s\n' "$name" "$command" >&2
		optional_application_report_failure
		return 1
	fi
	if [[ $pending == false ]]; then
		printf 'Optional applications already installed and verified; no changes made.\n'
		return 0
	fi

	printf 'Phase: confirm\n'
	if ! wizard_confirm 'Install this complete optional application plan?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true ]] && ! wizard_confirm 'Continue despite the Omarchy version mismatch?'; then
		printf 'Recovery: review compatibility, then choose Install optional applications in the Dotfiles wizard.\n' >&2
		return 1
	fi

	for index in "${!OPTIONAL_APPLICATION_ORDER[@]}"; do
		id=${OPTIONAL_APPLICATION_ORDER[$index]}
		[[ ${OPTIONAL_APPLICATION_PACKAGE_STATUS[$id]} == pending ]] || continue
		name=$(optional_application_value "$id" name)
		package=$(optional_application_value "$id" package)
		source=$(optional_application_value "$id" source)
		command=$(optional_application_value "$id" command)
		printf 'Phase: install (%s)\n' "$name"
		if [[ $source == official ]]; then
			if ! omarchy pkg add "$package"; then
				printf 'Error: optional application installation failed for %s: %s\n' "$name" "$package" >&2
				optional_application_report_failure
				return 1
			fi
		elif ! omarchy pkg aur add "$package"; then
			printf 'Error: optional application installation failed for %s: %s\n' "$name" "$package" >&2
			optional_application_report_failure
			return 1
		fi
		unset "OPTIONAL_APPLICATION_PACKAGE_PRESENCE[$package]"
		if ! optional_application_package_present "$package"; then
			printf 'Error: optional application package verification failed for %s: %s\n' "$name" "$package" >&2
			optional_application_report_failure
			return 1
		fi
		if ! optional_application_command_available "$command"; then
			printf 'Error: optional application command verification failed for %s: %s\n' "$name" "$command" >&2
			optional_application_report_failure
			return 1
		fi
		OPTIONAL_APPLICATION_COMPLETED+=("$name ($package)")
		OPTIONAL_APPLICATION_COMPLETED_IDS["$id"]=true
		printf 'Installed and verified optional application: %s (%s)\n' "$name" "$package"
	done
}
