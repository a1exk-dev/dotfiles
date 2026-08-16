status() {
	inspect_environment
	if [[ $(jq '.packages | length' "$PACKAGE_CATALOG") -eq 0 ]]; then
		printf 'Packages: none\n'
		return
	fi

	printf 'Packages:\n'
	local package description documentation source relative target state
	local found linked absent invalid conflicting
	while IFS= read -r package; do
		found=false
		linked=0
		absent=0
		invalid=false
		conflicting=false
		while IFS= read -r -d '' source; do
			found=true
			relative=${source#"$REPOSITORY_ROOT/config/$package/"}
			target=$HOME/$relative
			if [[ ( -e $target || -L $target ) && $(readlink -f -- "$target") == "$(readlink -f -- "$source")" ]]; then
				linked=$((linked + 1))
			elif [[ -L $target ]]; then
				invalid=true
			elif [[ -e $target ]]; then
				conflicting=true
			else
				absent=$((absent + 1))
			fi
		done < <(find "$REPOSITORY_ROOT/config/$package" \( -type f -o -type l \) -print0)

		if [[ $found != true || $invalid == true || ( $linked -gt 0 && $absent -gt 0 ) ]]; then
			state=invalid
		elif [[ $conflicting == true ]]; then
			state=conflicting
		elif [[ $linked -gt 0 ]]; then
			state=linked
		else
			state=absent
		fi
		description=$(jq -r --arg package "$package" '.packages[] | select(.name == $package) | .description' "$PACKAGE_CATALOG")
		documentation=$(jq -r --arg package "$package" '.packages[] | select(.name == $package) | .documentation // empty' "$PACKAGE_CATALOG")
		printf '  %s: %s - %s\n' "$package" "$state" "$description"
		[[ -z $documentation ]] || printf '    Documentation: %s\n' "$documentation"
	done < <(jq -r '.packages[].name' "$PACKAGE_CATALOG")
}

check() {
	local command missing=false
	for command in jq find readlink omarchy; do
		if ! command -v "$command" >/dev/null 2>&1; then
			printf 'Error: missing core inspection command: %s\n' "$command" >&2
			missing=true
		fi
	done
	[[ $missing == false ]] || return 1

	inspect_environment
	printf 'Package catalog: valid (%s packages)\n' "$(jq '.packages | length' "$PACKAGE_CATALOG")"
	validate_skill_manifest
	printf 'Skill manifest: valid (%s sources)\n' "$(jq '.sources | length' "$SKILL_MANIFEST")"

	for command in git npx diff; do
		if ! command -v "$command" >/dev/null 2>&1; then
			printf 'Error: missing global skill prerequisite: %s\n' "$command" >&2
			missing=true
		fi
	done
	local package prerequisite
	while IFS= read -r package; do
		while IFS= read -r prerequisite; do
			if ! command -v "$prerequisite" >/dev/null 2>&1; then
				printf 'Missing package prerequisite for %s: %s\n' "$package" "$prerequisite" >&2
				missing=true
			fi
			done < <(jq -r --arg package "$package" '.packages[] | select(.name == $package) | .prerequisites[]' "$PACKAGE_CATALOG")
		if ! validator_executables_available "$package"; then
			missing=true
		fi
	done < <(jq -r '.packages[].name' "$PACKAGE_CATALOG")
	if command -v stow >/dev/null 2>&1; then
		printf 'GNU Stow: available\n'
	else
		printf 'GNU Stow: unavailable (nonfatal until a package operation is selected)\n'
	fi
	[[ $missing == false ]]
}
report_normal_target_conflicts() {
	local package=$1
	local source relative target
	while IFS= read -r -d '' source; do
		relative=${source#"$REPOSITORY_ROOT/config/$package/"}
		target=$HOME/$relative
		if [[ -e $target && ! -L $target ]]; then
			printf 'Conflict: %s: %s\n' "$(path_type "$target")" "$target" >&2
		fi
	done < <(find "$REPOSITORY_ROOT/config/$package" \( -type f -o -type l \) -print0)
}

simulate_apply_package() {
	local package=$1
	printf 'Plan simulation: apply %s\n' "$package"
	report_normal_target_conflicts "$package"
	if ! stow --simulate --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" "$package"; then
		phase_error apply "$package" "resolve the reported target conflict without deleting it, then rerun: bin/dotfiles apply $package --yes"
		return 1
	fi
}

apply_one_package() {
	local package=$1
	local package_json
	package_json=$(jq -c --arg package "$package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")

	printf 'Phase: apply (%s)\n' "$package"
	if ! stow --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" "$package"; then
		phase_error apply "$package" "inspect $HOME for partial links, then rerun: bin/dotfiles apply $package --yes"
		return 1
	fi

	printf 'Phase: verify (%s)\n' "$package"
	local source relative target
	while IFS= read -r -d '' source; do
		relative=${source#"$REPOSITORY_ROOT/config/$package/"}
		target=$HOME/$relative
		if [[ ( ! -e $target && ! -L $target ) || $(readlink -f -- "$target") != "$(readlink -f -- "$source")" ]]; then
			printf 'Expected link is missing or incorrect: %s -> %s\n' "$target" "$source" >&2
			phase_error verify "$package" "remove partial links with: stow --delete --dir '$REPOSITORY_ROOT/config' --target '$HOME' '$package'; then rerun apply"
			return 1
		fi
	done < <(find "$REPOSITORY_ROOT/config/$package" \( -type f -o -type l \) -print0)

	local validator
	while IFS= read -r validator; do
		if ! (cd -- "$REPOSITORY_ROOT" && bash -c "$validator"); then
			printf 'Validator failed for %s: %s\n' "$package" "$validator" >&2
			phase_error verify "$package" "fix the linked configuration, validate with: $validator; then rerun apply"
			return 1
		fi
	done < <(jq -r '.validators[]' <<<"$package_json")
	printf 'Applied and verified package: %s\n' "$package"
}

migrate_target() {
	local package=${1-}
	local relative=${2-}
	shift 2 2>/dev/null || true
	if [[ -z $package || -z $relative ]]; then
		printf 'Usage: dotfiles migrate <package> <home-relative-target> --yes --inspection-approved [--allow-omarchy-mismatch]\n' >&2
		return 2
	fi

	local approved=false
	local inspection_approved=false
	local allow_mismatch=false
	local interactive=false
	local option
	for option in "$@"; do
		case $option in
			--yes) approved=true ;;
			--inspection-approved) inspection_approved=true ;;
			--allow-omarchy-mismatch) allow_mismatch=true ;;
			--interactive) interactive=true ;;
			*)
				printf 'Error: unknown migrate option: %s\n' "$option" >&2
				return 2
				;;
		esac
	done

	if ! validate_catalog; then
		phase_error inspect "$package" 'correct packages.json and rerun the migrate command'
		return 1
	fi
	local package_json
	package_json=$(jq -c --arg package "$package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
	if [[ -z $package_json ]]; then
		printf 'Error: unknown package: %s\n' "$package" >&2
		return 1
	fi
	if [[ $relative == /* || $relative == .. || $relative == ../* || $relative == */../* || $relative == */.. ]]; then
		printf 'Error: migration target must be a path below HOME\n' >&2
		return 2
	fi

	local target=$HOME/$relative
	local source=$REPOSITORY_ROOT/config/$package/$relative
	if [[ ! -f $target || -L $target ]]; then
		printf 'Error: migration target is not an existing regular file: %s\n' "$target" >&2
		return 1
	fi
	if [[ -e $source || -L $source ]]; then
		printf 'Error: package destination already exists; migration will not overwrite it: %s\n' "$source" >&2
		return 1
	fi
	local canonical_home canonical_target package_root canonical_package_root canonical_source
	canonical_home=$(readlink -f -- "$HOME") || {
		printf 'Error: could not canonicalize HOME for migration: %s\n' "$HOME" >&2
		return 1
	}
	canonical_target=$(readlink -f -- "$target") || {
		printf 'Error: could not canonicalize migration target: %s\n' "$target" >&2
		return 1
	}
	if [[ $canonical_target != "$canonical_home/"* ]]; then
		printf 'Error: migration target resolves outside HOME: %s -> %s\n' "$target" "$canonical_target" >&2
		return 1
	fi
	package_root=$REPOSITORY_ROOT/config/$package
	canonical_package_root=$(readlink -f -- "$package_root") || {
		printf 'Error: could not canonicalize package directory: %s\n' "$package_root" >&2
		return 1
	}
	canonical_source=$(readlink -m -- "$source") || {
		printf 'Error: could not canonicalize package destination: %s\n' "$source" >&2
		return 1
	}
	if [[ $canonical_source != "$canonical_package_root/"* ]]; then
		printf 'Error: package destination resolves outside package %s: %s -> %s\n' "$package" "$source" "$canonical_source" >&2
		return 1
	fi

	resolve_dependency_order "$package"
	local -a packages=("${DEPENDENCY_ORDER[@]}")

	printf 'Migration candidate: %s: %s\n' "$(path_type "$target")" "$target"
	printf 'Package destination: %s\n' "$source"
	if [[ $approved != true && $interactive != true ]]; then
		printf 'Error: migration requires explicit mutation approval with --yes\n' >&2
		return 2
	fi
	if [[ $inspection_approved != true && $interactive != true ]]; then
		printf 'Inspection required: inspect for sensitive or machine-specific content, then rerun with --inspection-approved.\n' >&2
		return 2
	fi

	inspect_omarchy stderr
	if [[ $OMARCHY_VERSION_MISMATCH == true ]]; then
		if [[ $allow_mismatch != true && $interactive != true ]]; then
			phase_error confirm "$package" "review compatibility, then rerun with --allow-omarchy-mismatch"
			return 1
		fi
	fi

	local planned_package prerequisite missing=false
	for planned_package in "${packages[@]}"; do
		while IFS= read -r prerequisite; do
			if ! command -v "$prerequisite" >/dev/null 2>&1; then
				printf 'Missing package prerequisite for %s: %s\n' "$planned_package" "$prerequisite" >&2
				missing=true
			fi
		done < <(jq -r --arg package "$planned_package" '.packages[] | select(.name == $package) | .prerequisites[]' "$PACKAGE_CATALOG")
	done
	if [[ $missing == true ]]; then
		phase_error plan "$package" 'install the listed prerequisite commands, then rerun the migrate command'
		return 1
	fi
	if ! validator_executables_available "${packages[@]}"; then
		phase_error plan "$package" 'install each declared validator executable, then rerun the migrate command'
		return 1
	fi
	if ! command -v stow >/dev/null 2>&1; then
		phase_error plan "$package" 'install GNU Stow, then rerun the migrate command'
		return 1
	fi

	printf 'Phase: conflict simulation\n'
	for planned_package in "${packages[@]}"; do
		if ! simulate_apply_package "$planned_package"; then
			[[ $planned_package == "$package" ]] && printf 'Recovery: resolve the reported tracked target conflict; the migration target is unchanged, then rerun migrate.\n' >&2
			return 1
		fi
	done
	printf 'Plan: migration package order:\n'
	local position=1 selection_label planned_json
	for planned_package in "${packages[@]}"; do
		selection_label='required dependency; apply only'
		[[ $planned_package == "$package" ]] && selection_label='selected; migrate and apply'
		printf '  %d. %s (%s)\n' "$position" "$planned_package" "$selection_label"
		position=$((position + 1))
	done
	for planned_package in "${packages[@]}"; do
		planned_json=$(jq -c --arg package "$planned_package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
		printf 'Package %s prerequisites: %s\n' "$planned_package" "$(jq -r '.prerequisites | if length == 0 then "none" else join(", ") end' <<<"$planned_json")"
		printf 'Package %s validators: %s\n' "$planned_package" "$(jq -r '.validators | if length == 0 then "none" else join("; ") end' <<<"$planned_json")"
	done
	printf 'Plan: back up %s, move it to %s, apply %s, and verify every link and validator.\n' "$target" "$source" "$package"
	if [[ $interactive == true ]]; then
		printf 'Phase: confirm\n'
		if ! wizard_confirm 'Migrate this complete plan?'; then
			printf 'No changes made.\n'
			return 0
		fi
		if ! wizard_confirm 'Has the candidate been inspected for sensitive and machine-specific content?'; then
			printf 'No changes made.\n'
			return 0
		fi
		if [[ $OMARCHY_VERSION_MISMATCH == true ]] && ! wizard_confirm "Continue despite the Omarchy version mismatch?"; then
			phase_error confirm "$package" 'review compatibility and rerun the migration when ready'
			return 1
		fi
	fi

	for planned_package in "${packages[@]}"; do
		[[ $planned_package == "$package" ]] && continue
		if apply_one_package "$planned_package"; then
			printf 'Package state: %s: succeeded\n' "$planned_package"
		else
			printf 'Package state: %s: failed\n' "$planned_package" >&2
			return 1
		fi
	done
	if [[ ! -f $target || -L $target || -e $source || -L $source ]]; then
		phase_error plan "$package" 'dependency application changed the migration target or package destination; inspect both paths before retrying'
		return 1
	fi
	canonical_target=$(readlink -f -- "$target") || {
		phase_error plan "$package" 'dependency application made the migration target unavailable; inspect it before retrying'
		return 1
	}
	canonical_source=$(readlink -m -- "$source") || {
		phase_error plan "$package" 'dependency application made the package destination unresolvable; inspect it before retrying'
		return 1
	}
	if [[ $canonical_target != "$canonical_home/"* || $canonical_source != "$canonical_package_root/"* ]]; then
		phase_error plan "$package" 'dependency application changed path containment; the selected target was not moved'
		return 1
	fi

	local state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
	if [[ $state_home != /* ]]; then
		phase_error backup "$package" 'set XDG_STATE_HOME to an absolute path and rerun; the target is unchanged'
		return 1
	fi
	local timestamp backup
	timestamp=$(date -u +%Y%m%dT%H%M%S.%NZ)
	backup=$state_home/dotfiles/backups/$package/$timestamp/$relative
	if ! mkdir -p -- "$(dirname -- "$backup")" || ! cp --archive -- "$target" "$backup"; then
		phase_error backup "$package" "could not create $backup; the target remains unchanged"
		return 1
	fi
	printf 'Backup created: %s\n' "$backup"

	if ! mkdir -p -- "$(dirname -- "$source")"; then
		printf 'Backup retained: %s\n' "$backup" >&2
		phase_error migrate "$package" "could not create package destination parent; target remains at $target"
		return 1
	fi
	if ! mv --no-clobber -- "$target" "$source" || [[ -e $target || ! -f $source ]]; then
		printf 'Backup retained: %s\n' "$backup" >&2
		phase_error migrate "$package" "move did not complete without clobbering; restore with: cp --archive '$backup' '$target'"
		return 1
	fi
	printf 'Moved approved content into package: %s\n' "$source"

	# Migration changes the package tree after its initial conflict review, so validate the new tree before applying it.
	if ! simulate_apply_package "$package" || ! apply_one_package "$package"; then
		printf 'Backup retained: %s\n' "$backup" >&2
		printf 'Recovery: remove any repository-owned partial links with: stow --delete --dir %q --target %q %q; then restore the original target with: cp --archive %q %q\n' \
			"$REPOSITORY_ROOT/config" "$HOME" "$package" "$backup" "$target" >&2
		return 1
	fi
	printf 'Migrated and verified package: %s\n' "$package"
}

apply_package() {
	local package=${1-}
	shift || true
	if [[ -z $package ]]; then
		printf 'Usage: dotfiles apply <package> --yes [--allow-omarchy-mismatch] [--install-stow]\n' >&2
		return 2
	fi

	local approved=false
	local allow_mismatch=false
	local install_stow=false
	local interactive=false
	local option
	for option in "$@"; do
		case $option in
			--yes) approved=true ;;
			--allow-omarchy-mismatch) allow_mismatch=true ;;
			--install-stow) install_stow=true ;;
			--interactive) interactive=true ;;
			*)
				printf 'Error: unknown apply option: %s\n' "$option" >&2
				return 2
				;;
		esac
	done
	if [[ $approved != true && $interactive != true ]]; then
		printf 'Error: apply requires explicit approval with --yes\n' >&2
		return 2
	fi

	printf 'Phase: inspect\n'
	if ! validate_catalog; then
		phase_error inspect "$package" 'correct packages.json and rerun the apply command'
		return 1
	fi
	local package_json
	package_json=$(jq -c --arg package "$package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
	if [[ -z $package_json ]]; then
		printf 'Error: unknown package: %s\n' "$package" >&2
		phase_error inspect "$package" "choose a package listed by bin/dotfiles status"
		return 1
	fi
	resolve_dependency_order "$package"
	local -a packages=("${DEPENDENCY_ORDER[@]}")

	inspect_omarchy stdout

	printf 'Phase: plan\n'
	local stow_missing=false
	if ! command -v stow >/dev/null 2>&1; then
		stow_missing=true
		printf 'Missing prerequisite: GNU Stow is required to apply packages.\n' >&2
		printf 'Omarchy-supported install: omarchy-pkg-add stow\n' >&2
	fi

	local planned_package prerequisite missing=false
	for planned_package in "${packages[@]}"; do
		while IFS= read -r prerequisite; do
			if ! command -v "$prerequisite" >/dev/null 2>&1; then
				printf 'Missing package prerequisite for %s: %s\n' "$planned_package" "$prerequisite" >&2
				missing=true
			fi
		done < <(jq -r --arg package "$planned_package" '.packages[] | select(.name == $package) | .prerequisites[]' "$PACKAGE_CATALOG")
	done
	if [[ $missing == true ]]; then
		phase_error plan "$package" 'install the listed prerequisite commands, then rerun the apply command'
		return 1
	fi
	if ! validator_executables_available "${packages[@]}"; then
		phase_error plan "$package" 'install each declared validator executable, then rerun the apply command'
		return 1
	fi

	if [[ $stow_missing == true ]]; then
		printf 'Plan: install GNU Stow with omarchy-pkg-add stow\n'
		printf 'Phase: confirm prerequisite\n'
		if [[ $OMARCHY_VERSION_MISMATCH == true && $allow_mismatch != true ]]; then
			if [[ $interactive == true ]] && wizard_confirm "Install prerequisites despite the Omarchy version mismatch?"; then
				allow_mismatch=true
			fi
			if [[ $allow_mismatch != true ]]; then
				printf 'Confirmation required: rerun with --allow-omarchy-mismatch to mutate on Omarchy %s.\n' "$OMARCHY_DETECTED_VERSION" >&2
				phase_error confirm "$package" "review compatibility, then rerun: bin/dotfiles apply $package --yes --allow-omarchy-mismatch"
				return 1
			fi
		fi
		if [[ $install_stow != true ]]; then
			if [[ $interactive == true ]] && wizard_confirm 'Install GNU Stow with omarchy-pkg-add stow?'; then
				install_stow=true
			fi
			if [[ $install_stow != true ]]; then
				phase_error confirm "$package" "confirm installation by rerunning: bin/dotfiles apply $package --yes --install-stow"
				return 1
			fi
		fi
		printf 'Phase: apply prerequisite\n'
		if ! omarchy-pkg-add stow; then
			phase_error apply "$package" 'GNU Stow installation failed; resolve the Omarchy package error and rerun the apply command'
			return 1
		fi
		if ! command -v stow >/dev/null 2>&1; then
			phase_error verify "$package" 'GNU Stow is still unavailable; fix PATH or installation, then rerun the apply command'
			return 1
		fi
		printf 'Prerequisite verified: GNU Stow\n'
		local rerun_command="bin/dotfiles apply $package --yes"
		if [[ $OMARCHY_VERSION_MISMATCH == true ]]; then
			rerun_command+=' --allow-omarchy-mismatch'
		fi
		printf 'Prerequisite setup complete; rerun: %s\n' "$rerun_command"
		return 0
	fi

	for planned_package in "${packages[@]}"; do
		simulate_apply_package "$planned_package" || return 1
	done

	printf 'Plan: apply packages in dependency order:\n'
	local position=1 selection_label
	for planned_package in "${packages[@]}"; do
		selection_label='required by selection'
		[[ $planned_package == "$package" ]] && selection_label=selected
		printf '  %d. %s (%s)\n' "$position" "$planned_package" "$selection_label"
		position=$((position + 1))
	done
	for planned_package in "${packages[@]}"; do
		printf 'Plan: apply %s from config/%s to %s\n' "$planned_package" "$planned_package" "$HOME"
	done
	local planned_json
	for planned_package in "${packages[@]}"; do
		planned_json=$(jq -c --arg package "$planned_package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
		printf 'Package %s prerequisites: %s\n' "$planned_package" "$(jq -r '.prerequisites | if length == 0 then "none" else join(", ") end' <<<"$planned_json")"
		printf 'Package %s validators: %s\n' "$planned_package" "$(jq -r '.validators | if length == 0 then "none" else join("; ") end' <<<"$planned_json")"
	done
	printf 'Phase: confirm\n'
	if [[ $interactive == true ]] && ! wizard_confirm 'Apply this complete plan?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true && $allow_mismatch != true ]]; then
		if [[ $interactive == true ]] && wizard_confirm "Continue despite the Omarchy version mismatch?"; then
			allow_mismatch=true
		fi
		if [[ $allow_mismatch != true ]]; then
			printf 'Confirmation required: rerun with --allow-omarchy-mismatch to mutate on Omarchy %s.\n' "$OMARCHY_DETECTED_VERSION" >&2
			phase_error confirm "$package" "review compatibility, then rerun: bin/dotfiles apply $package --yes --allow-omarchy-mismatch"
			return 1
		fi
	fi
	if [[ $interactive == true ]]; then
		printf 'Approval: accepted interactively\n'
	else
		printf 'Approval: accepted by --yes\n'
	fi
	for planned_package in "${packages[@]}"; do
		if apply_one_package "$planned_package"; then
			printf 'Package state: %s: succeeded\n' "$planned_package"
		else
			printf 'Package state: %s: failed\n' "$planned_package" >&2
			return 1
		fi
	done
}

package_is_linked() {
	local package=$1
	local source relative target
	local found=false
	while IFS= read -r -d '' source; do
		found=true
		relative=${source#"$REPOSITORY_ROOT/config/$package/"}
		target=$HOME/$relative
		if [[ ( ! -e $target && ! -L $target ) || $(readlink -f -- "$target") != "$(readlink -f -- "$source")" ]]; then
			return 1
		fi
	done < <(find "$REPOSITORY_ROOT/config/$package" \( -type f -o -type l \) -print0)
	[[ $found == true ]]
}

package_depends_on() {
	local package=$1
	local dependency=$2
	resolve_dependency_order "$package" || return 1
	local resolved
	for resolved in "${DEPENDENCY_ORDER[@]}"; do
		if [[ $resolved == "$dependency" && $resolved != "$package" ]]; then
			return 0
		fi
	done
	return 1
}

remove_package() {
	local package=${1-}
	shift || true
	if [[ -z $package ]]; then
		printf 'Usage: dotfiles remove <package> --yes [--allow-omarchy-mismatch]\n' >&2
		return 2
	fi

	local approved=false
	local allow_mismatch=false
	local interactive=false
	local option
	for option in "$@"; do
		case $option in
			--yes) approved=true ;;
			--allow-omarchy-mismatch) allow_mismatch=true ;;
			--interactive) interactive=true ;;
			*)
				printf 'Error: unknown remove option: %s\n' "$option" >&2
				return 2
				;;
		esac
	done
	if [[ $approved != true && $interactive != true ]]; then
		printf 'Error: remove requires explicit approval with --yes\n' >&2
		return 2
	fi

	printf 'Phase: inspect\n'
	if ! validate_catalog; then
		phase_error inspect "$package" 'correct packages.json and rerun the remove command'
		return 1
	fi
	local package_json
	package_json=$(jq -c --arg package "$package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
	if [[ -z $package_json ]]; then
		printf 'Error: unknown package: %s\n' "$package" >&2
		phase_error inspect "$package" 'choose a package listed by bin/dotfiles status'
		return 1
	fi

	inspect_omarchy stdout

	printf 'Phase: plan\n'
	local -a blockers=()
	local candidate
	while IFS= read -r candidate; do
		if [[ $candidate != "$package" ]] && package_is_linked "$candidate" && package_depends_on "$candidate" "$package"; then
			blockers+=("$candidate")
		fi
	done < <(jq -r '.packages[].name' "$PACKAGE_CATALOG")
	if ((${#blockers[@]} > 0)); then
		printf 'Removal blocked: linked packages depend on %s:\n' "$package" >&2
		for candidate in "${blockers[@]}"; do
			printf '  %s\n' "$candidate" >&2
		done
		phase_error plan "$package" 'remove the named dependent packages first, or retain this package'
		return 1
	fi
	if ! command -v stow >/dev/null 2>&1; then
		printf 'Missing prerequisite: GNU Stow is required to remove packages.\n' >&2
		phase_error plan "$package" 'install GNU Stow, then rerun the remove command'
		return 1
	fi
	printf 'Plan simulation: remove %s\n' "$package"
	if ! stow --simulate --delete --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" "$package"; then
		phase_error remove "$package" "inspect the Stow simulation error, then rerun: bin/dotfiles remove $package --yes"
		return 1
	fi
	printf 'Plan: remove %s links from %s\n' "$package" "$HOME"
	printf 'Cleanup notes (not deleted):\n'
	if [[ $(jq '.cleanup | length' <<<"$package_json") -eq 0 ]]; then
		printf '  none\n'
	else
		jq -r '.cleanup[] | "  " + .' <<<"$package_json"
	fi

	printf 'Phase: confirm\n'
	if [[ $interactive == true ]] && ! wizard_confirm 'Remove this complete plan?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true && $allow_mismatch != true ]]; then
		if [[ $interactive == true ]] && wizard_confirm "Continue despite the Omarchy version mismatch?"; then
			allow_mismatch=true
		fi
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true && $allow_mismatch != true ]]; then
		phase_error confirm "$package" "review compatibility, then rerun: bin/dotfiles remove $package --yes --allow-omarchy-mismatch"
		return 1
	fi
	if [[ $interactive == true ]]; then
		printf 'Approval: accepted interactively\n'
	else
		printf 'Approval: accepted by --yes\n'
	fi

	printf 'Phase: remove\n'
	if ! stow --delete --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" "$package"; then
		phase_error remove "$package" "inspect $HOME for remaining links, then rerun: bin/dotfiles remove $package --yes"
		return 1
	fi

	printf 'Phase: verify\n'
	local source relative target
	while IFS= read -r -d '' source; do
		relative=${source#"$REPOSITORY_ROOT/config/$package/"}
		target=$HOME/$relative
		if [[ -e $target || -L $target ]]; then
			printf 'Managed link target remains after removal: %s\n' "$target" >&2
			phase_error verify "$package" "inspect and remove only the remaining repository-owned link, then rerun removal"
			return 1
		fi
	done < <(find "$REPOSITORY_ROOT/config/$package" \( -type f -o -type l \) -print0)
	printf 'Removed and verified package: %s\n' "$package"
	printf 'Cleanup notes (not deleted):\n'
	if [[ $(jq '.cleanup | length' <<<"$package_json") -eq 0 ]]; then
		printf '  none\n'
	else
		jq -r '.cleanup[] | "  " + .' <<<"$package_json"
	fi
}
setup_prerequisites() {
	local approved=false allow_mismatch=false interactive=false option
	for option in "$@"; do
		case $option in
			--yes) approved=true ;;
			--allow-omarchy-mismatch) allow_mismatch=true ;;
			--interactive) interactive=true ;;
			*)
				printf 'Error: unknown prerequisites option: %s\n' "$option" >&2
				return 2
				;;
		esac
	done

	printf 'Phase: inspect\n'
	validate_catalog || return 1
	inspect_omarchy stderr

	printf 'Phase: plan\n'
	if command -v stow >/dev/null 2>&1; then
		printf 'GNU Stow is already available; no prerequisite changes are needed.\n'
		return 0
	fi
	if ! command -v omarchy-pkg-add >/dev/null 2>&1; then
		printf 'Error: missing Omarchy prerequisite installer: omarchy-pkg-add\n' >&2
		printf 'Recovery: restore the supported Omarchy package command, then rerun prerequisite setup.\n' >&2
		return 1
	fi
	printf 'Dependencies: none\n'
	printf 'Conflicts: none detected\n'
	printf 'Plan: install GNU Stow with omarchy-pkg-add stow, then verify it is available.\n'
	printf 'Phase: confirm\n'
	if [[ $interactive == true ]]; then
		if ! wizard_confirm 'Apply this complete prerequisite plan?'; then
			printf 'No changes made.\n'
			return 0
		fi
	elif [[ $approved != true ]]; then
		printf 'Decision required: review the plan and rerun with --yes.\n' >&2
		return 2
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true && $allow_mismatch != true ]]; then
		if [[ $interactive == true ]] && wizard_confirm "Continue despite the Omarchy version mismatch?"; then
			allow_mismatch=true
		fi
		if [[ $allow_mismatch != true ]]; then
			printf 'Recovery: review compatibility, then rerun: bin/dotfiles prerequisites --yes --allow-omarchy-mismatch\n' >&2
			return 1
		fi
	fi

	printf 'Phase: apply\n'
	if ! omarchy-pkg-add stow; then
		printf 'Error: prerequisite installation failed.\n' >&2
		printf 'Recovery: resolve the Omarchy package error, then rerun prerequisite setup.\n' >&2
		return 1
	fi
	printf 'Phase: verify\n'
	if ! command -v stow >/dev/null 2>&1; then
		printf 'Error: GNU Stow is still unavailable after installation.\n' >&2
		printf 'Recovery: fix the installation or PATH, then rerun prerequisite setup.\n' >&2
		return 1
	fi
	printf 'GNU Stow installed and verified.\n'
}
