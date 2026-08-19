declare -a ARCH_PACKAGE_ORDER=()
declare -a MISSING_ARCH_PACKAGES=()
declare -A ARCH_PACKAGE_OWNERS=()
declare -A ARCH_PACKAGE_STATUS=()
ARCH_PACKAGES_INSTALLED=false

plan_arch_packages() {
	ARCH_PACKAGE_ORDER=()
	MISSING_ARCH_PACKAGES=()
	ARCH_PACKAGE_OWNERS=()
	ARCH_PACKAGE_STATUS=()

	local owner arch_package
	for owner in "$@"; do
		while IFS= read -r arch_package; do
			if [[ -z ${ARCH_PACKAGE_OWNERS[$arch_package]+present} ]]; then
				ARCH_PACKAGE_ORDER+=("$arch_package")
				ARCH_PACKAGE_OWNERS[$arch_package]=$owner
			else
				ARCH_PACKAGE_OWNERS[$arch_package]+=", $owner"
			fi
		done < <(jq -r --arg package "$owner" '.packages[] | select(.name == $package) | .arch_packages[]' "$PACKAGE_CATALOG")
	done

	for arch_package in "${ARCH_PACKAGE_ORDER[@]}"; do
		if omarchy pkg present "$arch_package"; then
			ARCH_PACKAGE_STATUS[$arch_package]=installed
		else
			ARCH_PACKAGE_STATUS[$arch_package]='will install'
			MISSING_ARCH_PACKAGES+=("$arch_package")
		fi
	done
}

print_arch_package_plan() {
	printf 'Plan: Arch package requirements:\n'
	if ((${#ARCH_PACKAGE_ORDER[@]} == 0)); then
		printf '  none\n'
		return
	fi

	local arch_package
	for arch_package in "${ARCH_PACKAGE_ORDER[@]}"; do
		printf '  %s (required by %s): %s\n' "$arch_package" \
			"${ARCH_PACKAGE_OWNERS[$arch_package]}" "${ARCH_PACKAGE_STATUS[$arch_package]}"
	done
}

install_missing_arch_packages() {
	local recovery_action=$1
	ARCH_PACKAGES_INSTALLED=false
	((${#MISSING_ARCH_PACKAGES[@]} > 0)) || return 0

	printf 'Phase: install Arch packages\n'
	if ! omarchy pkg add "${MISSING_ARCH_PACKAGES[@]}"; then
		printf 'Error: Arch package installation failed.\n' >&2
		printf 'Recovery: resolve the Omarchy package error, then choose %s in the Dotfiles wizard.\n' "$recovery_action" >&2
		return 1
	fi
	ARCH_PACKAGES_INSTALLED=true
}

verify_arch_packages() {
	local recovery_action=$1
	((${#ARCH_PACKAGE_ORDER[@]} > 0)) || return 0

	printf 'Phase: verify Arch packages\n'
	local arch_package
	for arch_package in "${ARCH_PACKAGE_ORDER[@]}"; do
		if ! omarchy pkg present "$arch_package"; then
			printf 'Error: Arch package verification failed: %s\n' "$arch_package" >&2
			printf 'Recovery: repair the package installation, then choose %s in the Dotfiles wizard.\n' "$recovery_action" >&2
			return 1
		fi
	done
	if [[ $ARCH_PACKAGES_INSTALLED == true ]]; then
		printf 'Arch packages installed and verified: %s\n' "${MISSING_ARCH_PACKAGES[*]}"
	else
		printf 'Arch packages verified: %s\n' "${ARCH_PACKAGE_ORDER[*]}"
	fi
}

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
	validate_cleanup_manifest
	printf 'Cleanup manifest: valid (%s defaults)\n' "$(jq '[.packages[], .web_apps[], .tuis[]] | length' "$CLEANUP_MANIFEST")"
	validate_skill_manifest
	printf 'Skill manifest: valid (%s sources)\n' "$(jq '.sources | length' "$SKILL_MANIFEST")"

	for command in git npx diff; do
		if ! command -v "$command" >/dev/null 2>&1; then
			printf 'Error: missing global skill prerequisite: %s\n' "$command" >&2
			missing=true
		fi
	done
	local package prerequisite arch_package
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
	local -a catalog_packages=()
	mapfile -t catalog_packages < <(jq -r '.packages[].name' "$PACKAGE_CATALOG")
	resolve_dependency_order "${catalog_packages[@]}"
	plan_arch_packages "${DEPENDENCY_ORDER[@]}"
	for arch_package in "${MISSING_ARCH_PACKAGES[@]}"; do
		printf 'Missing declared Arch package for %s: %s\n' "${ARCH_PACKAGE_OWNERS[$arch_package]}" "$arch_package" >&2
		missing=true
	done
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
	if ! stow --no-folding --simulate --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" "$package"; then
		phase_error apply "$package" 'resolve the reported target conflict without deleting it, then rerun the Dotfiles wizard and choose Apply Stow packages'
		return 1
	fi
}

apply_one_package() {
	local package=$1
	local package_json
	package_json=$(jq -c --arg package "$package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")

	printf 'Phase: apply (%s)\n' "$package"
	if ! stow --no-folding --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" "$package"; then
		phase_error apply "$package" 'inspect HOME for partial links, then rerun the Dotfiles wizard and choose Apply Stow packages'
		return 1
	fi

	printf 'Phase: verify (%s)\n' "$package"
	local source relative target
	while IFS= read -r -d '' source; do
		relative=${source#"$REPOSITORY_ROOT/config/$package/"}
		target=$HOME/$relative
		if [[ ( ! -e $target && ! -L $target ) || $(readlink -f -- "$target") != "$(readlink -f -- "$source")" ]]; then
			printf 'Expected link is missing or incorrect: %s -> %s\n' "$target" "$source" >&2
			phase_error verify "$package" "remove partial links with: stow --no-folding --delete --dir '$REPOSITORY_ROOT/config' --target '$HOME' '$package'; then choose Apply Stow packages in the Dotfiles wizard"
			return 1
		fi
	done < <(find "$REPOSITORY_ROOT/config/$package" \( -type f -o -type l \) -print0)

	local validator
	while IFS= read -r validator; do
		if ! (cd -- "$REPOSITORY_ROOT" && bash -c "$validator"); then
			printf 'Validator failed for %s: %s\n' "$package" "$validator" >&2
			phase_error verify "$package" "fix the linked configuration, validate with: $validator; then choose Apply Stow packages in the Dotfiles wizard"
			return 1
		fi
	done < <(jq -r '.validators[]' <<<"$package_json")
	printf 'Applied and verified package: %s\n' "$package"
}

migration_paths_are_unchanged() {
	local package=$1 target=$2 source=$3 canonical_home=$4 canonical_package_root=$5 actor=$6
	if [[ ! -f $target || -L $target || -e $source || -L $source ]]; then
		phase_error plan "$package" "$actor changed the migration target or package destination; inspect both paths, then choose Migrate existing target in the Dotfiles wizard"
		return 1
	fi

	local canonical_target canonical_source
	canonical_target=$(readlink -f -- "$target") || {
		phase_error plan "$package" "$actor made the migration target unavailable; inspect it, then choose Migrate existing target in the Dotfiles wizard"
		return 1
	}
	canonical_source=$(readlink -m -- "$source") || {
		phase_error plan "$package" "$actor made the package destination unresolvable; inspect it, then choose Migrate existing target in the Dotfiles wizard"
		return 1
	}
	if [[ $canonical_target != "$canonical_home/"* || $canonical_source != "$canonical_package_root/"* ]]; then
		phase_error plan "$package" "$actor changed path containment; the selected target was not moved, inspect both paths, then choose Migrate existing target in the Dotfiles wizard"
		return 1
	fi
}

migrate_target() {
	local package=${1-}
	local relative=${2-}
	shift 2 2>/dev/null || true
	if [[ -z $package || -z $relative ]]; then
		printf 'Migration needs a package and home-relative target; choose Migrate existing target in the Dotfiles wizard.\n' >&2
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
		phase_error inspect "$package" 'correct packages.json, then choose Migrate existing target in the Dotfiles wizard'
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
		printf 'Inspection required: inspect for sensitive or machine-specific content before approving the wizard prompt.\n' >&2
		return 2
	fi

	inspect_omarchy stderr
	if [[ $OMARCHY_VERSION_MISMATCH == true ]]; then
		if [[ $allow_mismatch != true && $interactive != true ]]; then
			phase_error confirm "$package" 'review compatibility, then choose Migrate existing target in the Dotfiles wizard'
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
		phase_error plan "$package" 'install the listed prerequisite commands, then choose Migrate existing target in the Dotfiles wizard'
		return 1
	fi
	if ! validator_executables_available "${packages[@]}"; then
		phase_error plan "$package" 'install each declared validator executable, then choose Migrate existing target in the Dotfiles wizard'
		return 1
	fi
	if ! command -v stow >/dev/null 2>&1; then
		phase_error plan "$package" 'choose Prepare prerequisites, then retry Migrate existing target in the Dotfiles wizard'
		return 1
	fi
	local state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
	if [[ $state_home != /* ]]; then
		phase_error backup "$package" 'set XDG_STATE_HOME to an absolute path; the target is unchanged, then choose Migrate existing target in the Dotfiles wizard'
		return 1
	fi
	plan_arch_packages "${packages[@]}"

	printf 'Phase: conflict simulation\n'
	for planned_package in "${packages[@]}"; do
		if ! simulate_apply_package "$planned_package"; then
			[[ $planned_package == "$package" ]] && printf 'Recovery: resolve the reported tracked target conflict; the migration target is unchanged, then choose Migrate existing target in the Dotfiles wizard.\n' >&2
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
	print_arch_package_plan
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
			phase_error confirm "$package" 'review compatibility, then choose Migrate existing target in the Dotfiles wizard when ready'
			return 1
		fi
	fi
	install_missing_arch_packages 'Migrate existing target' || return 1
	verify_arch_packages 'Migrate existing target' || return 1
	if [[ $ARCH_PACKAGES_INSTALLED == true ]]; then
		printf 'Phase: repeat conflict simulation after Arch package installation\n'
		for planned_package in "${packages[@]}"; do
			simulate_apply_package "$planned_package" || return 1
		done
		migration_paths_are_unchanged "$package" "$target" "$source" "$canonical_home" "$canonical_package_root" \
			'Arch package installation' || return 1
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
	migration_paths_are_unchanged "$package" "$target" "$source" "$canonical_home" "$canonical_package_root" \
		'dependency application' || return 1

	local timestamp backup
	timestamp=$(date -u +%Y%m%dT%H%M%S.%NZ)
	backup=$state_home/dotfiles/backups/$package/$timestamp/$relative
	if ! mkdir -p -- "$(dirname -- "$backup")" || ! cp --archive -- "$target" "$backup"; then
		phase_error backup "$package" "could not create $backup; the target remains unchanged, then choose Migrate existing target in the Dotfiles wizard"
		return 1
	fi
	printf 'Backup created: %s\n' "$backup"

	if ! mkdir -p -- "$(dirname -- "$source")"; then
		printf 'Backup retained: %s\n' "$backup" >&2
		phase_error migrate "$package" "could not create package destination parent; target remains at $target, then choose Migrate existing target in the Dotfiles wizard"
		return 1
	fi
	if ! mv --no-clobber -- "$target" "$source" || [[ -e $target || ! -f $source ]]; then
		printf 'Backup retained: %s\n' "$backup" >&2
		phase_error migrate "$package" "move did not complete without clobbering; restore with: cp --archive '$backup' '$target'; then choose Migrate existing target in the Dotfiles wizard"
		return 1
	fi
	printf 'Moved approved content into package: %s\n' "$source"

	# Migration changes the package tree after its initial conflict review, so validate the new tree before applying it.
	if ! simulate_apply_package "$package" || ! apply_one_package "$package"; then
		printf 'Backup retained: %s\n' "$backup" >&2
		printf 'Recovery: remove any repository-owned partial links with: stow --no-folding --delete --dir %q --target %q %q; then restore the original target with: cp --archive %q %q; then choose Migrate existing target in the Dotfiles wizard\n' \
			"$REPOSITORY_ROOT/config" "$HOME" "$package" "$backup" "$target" >&2
		return 1
	fi
	printf 'Migrated and verified package: %s\n' "$package"
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
		printf 'Choose a package through Remove Stow package in the Dotfiles wizard.\n' >&2
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
		phase_error inspect "$package" 'correct packages.json, then choose Remove Stow package in the Dotfiles wizard'
		return 1
	fi
	local package_json
	package_json=$(jq -c --arg package "$package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
	if [[ -z $package_json ]]; then
		printf 'Error: unknown package: %s\n' "$package" >&2
		phase_error inspect "$package" 'choose a package offered by Remove Stow package in the Dotfiles wizard'
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
		phase_error plan "$package" 'remove the named dependent packages first, or retain this package; then choose Remove Stow package in the Dotfiles wizard'
		return 1
	fi
	if ! command -v stow >/dev/null 2>&1; then
		printf 'Missing prerequisite: GNU Stow is required to remove packages.\n' >&2
		phase_error plan "$package" 'choose Prepare prerequisites, then retry Remove Stow package in the Dotfiles wizard'
		return 1
	fi
	printf 'Plan simulation: remove %s\n' "$package"
	if ! stow --no-folding --simulate --delete --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" "$package"; then
		phase_error remove "$package" 'inspect the Stow simulation error, then choose Remove Stow package in the Dotfiles wizard'
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
		phase_error confirm "$package" 'review compatibility, then choose Remove Stow package in the Dotfiles wizard'
		return 1
	fi
	if [[ $interactive == true ]]; then
		printf 'Approval: accepted interactively\n'
	else
		printf 'Approval: accepted by --yes\n'
	fi

	printf 'Phase: remove\n'
	if ! stow --no-folding --delete --verbose=2 --dir "$REPOSITORY_ROOT/config" --target "$HOME" "$package"; then
		phase_error remove "$package" 'inspect HOME for remaining links, then choose Remove Stow package in the Dotfiles wizard'
		return 1
	fi

	printf 'Phase: verify\n'
	local source relative target
	while IFS= read -r -d '' source; do
		relative=${source#"$REPOSITORY_ROOT/config/$package/"}
		target=$HOME/$relative
		if [[ -e $target || -L $target ]]; then
			printf 'Managed link target remains after removal: %s\n' "$target" >&2
			phase_error verify "$package" 'inspect and remove only the remaining repository-owned link, then choose Remove Stow package in the Dotfiles wizard'
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
	local approved=false allow_mismatch=false interactive=false required=false option
	for option in "$@"; do
		case $option in
			--yes) approved=true ;;
			--allow-omarchy-mismatch) allow_mismatch=true ;;
			--interactive) interactive=true ;;
			--required) required=true ;;
			*)
				printf 'Error: unknown prerequisites option: %s\n' "$option" >&2
				return 2
				;;
		esac
	done

	printf 'Phase: inspect\n'
	local core_tool core_missing=false
	for core_tool in jq find readlink git diff sort omarchy; do
		if ! command -v "$core_tool" >/dev/null 2>&1; then
			printf 'Error: missing core prerequisite command: %s\n' "$core_tool" >&2
			core_missing=true
		fi
	done
	if [[ $core_missing == true ]]; then
		printf 'Recovery: restore the listed core tools, then choose Prepare prerequisites in the Dotfiles wizard.\n' >&2
		return 1
	fi
	validate_catalog || return 1
	inspect_omarchy stderr

	printf 'Phase: plan\n'
	local stow_missing=false node_missing=false node_version=''
	command -v stow >/dev/null 2>&1 || stow_missing=true
	if command -v node >/dev/null 2>&1; then
		node_version=$(node --version)
		node_version=${node_version#v}
	fi
	if [[ -z $node_version ]] || ! version_at_least "$node_version" "$MINIMUM_NODE_VERSION" || \
		! command -v npm >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
		node_missing=true
	fi
	if [[ $stow_missing == false && $node_missing == false ]]; then
		printf 'Prerequisites verified: GNU Stow, Node.js %s, npm, and npx.\n' "$node_version"
		return 0
	fi
	if ! command -v omarchy >/dev/null 2>&1; then
		printf 'Error: missing Omarchy prerequisite installer: omarchy\n' >&2
		printf 'Recovery: restore Omarchy, then rerun the Dotfiles wizard and choose Prepare prerequisites.\n' >&2
		return 1
	fi
	printf 'Dependencies: none\n'
	printf 'Conflicts: none detected\n'
	[[ $stow_missing == false ]] || printf 'Plan: install GNU Stow with omarchy pkg add stow.\n'
	[[ $node_missing == false ]] || printf 'Plan: install Node.js %s or newer, npm, and npx with omarchy install dev-env node.\n' "$MINIMUM_NODE_VERSION"
	printf 'Plan: verify every required tool after installation.\n'
	printf 'Phase: confirm\n'
	if [[ $interactive == true ]]; then
		if ! wizard_confirm 'Apply this complete prerequisite plan?'; then
			printf 'No changes made.\n'
			if [[ $required == true ]]; then
				printf 'Error: required prerequisites remain unsatisfied.\n' >&2
				return 1
			fi
			return 0
		fi
	elif [[ $approved != true ]]; then
		printf 'Decision required: review and approve the plan in Prepare prerequisites in the Dotfiles wizard.\n' >&2
		return 2
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true && $allow_mismatch != true ]]; then
		if [[ $interactive == true ]] && wizard_confirm "Continue despite the Omarchy version mismatch?"; then
			allow_mismatch=true
		fi
		if [[ $allow_mismatch != true ]]; then
			printf 'Recovery: review compatibility, then rerun the Dotfiles wizard and choose Prepare prerequisites.\n' >&2
			return 1
		fi
	fi

	printf 'Phase: apply\n'
	if [[ $stow_missing == true ]] && ! omarchy pkg add stow; then
		printf 'Error: GNU Stow installation failed.\n' >&2
		printf 'Recovery: resolve the Omarchy package error, then choose Prepare prerequisites in the Dotfiles wizard.\n' >&2
		return 1
	fi
	if [[ $node_missing == true ]] && ! omarchy install dev-env node; then
		printf 'Error: Node.js toolchain installation failed.\n' >&2
		printf 'Recovery: resolve the Omarchy installer error, then choose Prepare prerequisites in the Dotfiles wizard.\n' >&2
		return 1
	fi
	printf 'Phase: verify\n'
	if ! command -v stow >/dev/null 2>&1; then
		printf 'Error: GNU Stow is still unavailable after installation.\n' >&2
		printf 'Recovery: fix the installation or PATH, then choose Prepare prerequisites in the Dotfiles wizard.\n' >&2
		return 1
	fi
	if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
		printf 'Error: Node.js, npm, or npx is still unavailable after installation.\n' >&2
		printf 'Recovery: fix the installation or PATH, then choose Prepare prerequisites in the Dotfiles wizard.\n' >&2
		return 1
	fi
	node_version=$(node --version)
	node_version=${node_version#v}
	if ! version_at_least "$node_version" "$MINIMUM_NODE_VERSION"; then
		printf 'Error: Node.js %s is below required version %s after installation.\n' "$node_version" "$MINIMUM_NODE_VERSION" >&2
		printf 'Recovery: fix the Node.js installation, then choose Prepare prerequisites in the Dotfiles wizard.\n' >&2
		return 1
	fi
	printf 'Prerequisites installed and verified: GNU Stow, Node.js %s, npm, and npx.\n' "$node_version"
}

apply_packages() {
	validate_catalog || return 1
	if (($# == 0)); then
		printf 'No Stow packages selected; no changes made.\n'
		return 0
	fi
	inspect_omarchy stdout
	if ! command -v stow >/dev/null 2>&1; then
		printf 'Error: GNU Stow is required.\nRecovery: choose Prepare prerequisites in the Dotfiles wizard.\n' >&2
		return 1
	fi
	resolve_dependency_order "$@" || return 1
	local -a selected=("$@") packages=("${DEPENDENCY_ORDER[@]}")
	local package prerequisite missing=false selected_label
	for package in "${packages[@]}"; do
		while IFS= read -r prerequisite; do
			if ! command -v "$prerequisite" >/dev/null 2>&1; then
				printf 'Missing package prerequisite for %s: %s\n' "$package" "$prerequisite" >&2
				missing=true
			fi
		done < <(jq -r --arg package "$package" '.packages[] | select(.name == $package) | .prerequisites[]' "$PACKAGE_CATALOG")
	done
	if [[ $missing == true ]]; then
		phase_error plan "${selected[0]}" 'install the listed prerequisite commands, then choose Apply Stow packages in the Dotfiles wizard'
		return 1
	fi
	if ! validator_executables_available "${packages[@]}"; then
		phase_error plan "${selected[0]}" 'install each declared validator executable, then choose Apply Stow packages in the Dotfiles wizard'
		return 1
	fi
	plan_arch_packages "${packages[@]}"
	for package in "${packages[@]}"; do simulate_apply_package "$package" || return 1; done
	printf 'Plan: apply packages in dependency order:\n'
	local position=1 candidate package_json
	for package in "${packages[@]}"; do
		selected_label='required by selection'
		for candidate in "${selected[@]}"; do [[ $candidate != "$package" ]] || selected_label=selected; done
		printf '  %d. %s (%s)\n' "$position" "$package" "$selected_label"
		position=$((position + 1))
	done
	print_arch_package_plan
	for package in "${packages[@]}"; do
		printf 'Plan: apply %s from config/%s to %s\n' "$package" "$package" "$HOME"
		package_json=$(jq -c --arg package "$package" '.packages[] | select(.name == $package)' "$PACKAGE_CATALOG")
		printf 'Package %s prerequisites: %s\n' "$package" "$(jq -r '.prerequisites | if length == 0 then "none" else join(", ") end' <<<"$package_json")"
		printf 'Package %s validators: %s\n' "$package" "$(jq -r '.validators | if length == 0 then "none" else join("; ") end' <<<"$package_json")"
	done
	printf 'Phase: confirm\n'
	if ! wizard_confirm 'Apply this complete Stow plan?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true ]] && ! wizard_confirm 'Continue despite the Omarchy version mismatch?'; then
		printf 'Recovery: review compatibility, then choose Apply Stow packages in the Dotfiles wizard.\n' >&2
		return 1
	fi
	install_missing_arch_packages 'Apply Stow packages' || return 1
	verify_arch_packages 'Apply Stow packages' || return 1
	if [[ $ARCH_PACKAGES_INSTALLED == true ]]; then
		printf 'Phase: repeat conflict simulation after Arch package installation\n'
		for package in "${packages[@]}"; do simulate_apply_package "$package" || return 1; done
	fi
	for package in "${packages[@]}"; do
		if apply_one_package "$package"; then
			printf 'Package state: %s: succeeded\n' "$package"
		else
			printf 'Package state: %s: failed\n' "$package" >&2
			printf 'Recovery: rerun the Dotfiles wizard and choose Apply Stow packages.\n' >&2
			return 1
		fi
	done
}
