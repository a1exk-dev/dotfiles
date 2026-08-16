validate_skill_manifest() {
	if ! jq -e 'type == "object" and (.installer | type == "object") and (.sources | type == "array")' "$SKILL_MANIFEST" >/dev/null 2>&1; then
		printf 'Error: invalid skill manifest: %s\n' "$SKILL_MANIFEST" >&2
		return 1
	fi
	if ! jq -e '.installer.package == "skills" and (.installer.version | type == "string" and test("^[0-9]+[.][0-9]+[.][0-9]+$"))' "$SKILL_MANIFEST" >/dev/null; then
		printf 'Error: invalid Skills CLI installer version\n' >&2
		return 1
	fi
	if ! jq -e '.target == "~/.agents/skills"' "$SKILL_MANIFEST" >/dev/null; then
		printf 'Error: invalid global target; expected ~/.agents/skills\n' >&2
		return 1
	fi
	if ! jq -e '.sources | length == 2 and
		(map(.url) | sort) == (["https://github.com/blader/humanizer", "https://github.com/mattpocock/skills"] | sort) and
		(map(.url) | unique | length) == length and
		(map(.name) | unique | length) == length and
		any(.[]; .name == "humanizer" and .url == "https://github.com/blader/humanizer") and
		any(.[]; .name == "matt-pocock-skills" and .url == "https://github.com/mattpocock/skills")' "$SKILL_MANIFEST" >/dev/null; then
		printf 'Error: unsupported skill source URL; expected the approved Humanizer and Matt Pocock sources\n' >&2
		return 1
	fi
	if ! jq -e 'all(.sources[]; .method == "skills-cli")' "$SKILL_MANIFEST" >/dev/null; then
		printf 'Error: invalid official installation method; expected skills-cli\n' >&2
		return 1
	fi
	if ! jq -e 'all(.sources[]; .revision | type == "string" and test("^[0-9a-f]{40}$"))' "$SKILL_MANIFEST" >/dev/null; then
		printf 'Error: every skill source requires a full 40-character revision\n' >&2
		return 1
	fi
	if ! jq -e 'all(.sources[]; .name | type == "string" and test("^[a-z][a-z0-9-]*$")) and
		all(.sources[]; .expectedSkills | type == "number" and floor == . and . > 0)' "$SKILL_MANIFEST" >/dev/null; then
		printf 'Error: invalid expected installable-skill count or source name\n' >&2
		return 1
	fi
}

skill_mutation_is_approved() {
	local mode=$1
	local source_index=$2
	local name=$3
	if [[ $mode == source ]]; then
		[[ ${SKILL_OWNERS[$name]-} == "$source_index" ]]
	else
		[[ -n ${UPDATE_AFFECTED_SKILLS[$name]-} ]]
	fi
}

skill_paths_match() {
	local expected=$1
	local actual=$2
	local expected_type actual_type
	expected_type=$(path_type "$expected")
	actual_type=$(path_type "$actual")
	if [[ ( ! -e $actual && ! -L $actual ) || $expected_type != "$actual_type" ]]; then
		return 1
	fi
	case $expected_type in
		'symbolic link') [[ $(readlink -- "$expected") == "$(readlink -- "$actual")" ]] ;;
		'regular file' | directory) diff --recursive --brief --no-dereference -- "$expected" "$actual" >/dev/null ;;
		*) return 1 ;;
	esac
}

backup_unrelated_skills() {
	local global_target=$1
	local backup_root=$2
	local mode=$3
	local source_index=$4
	if ! mkdir -p -- "$backup_root"; then
		printf 'Error: could not create unrelated global skill backup: %s\n' "$backup_root" >&2
		return 1
	fi
	[[ -d $global_target ]] || return 0

	local entry name
	while IFS= read -r -d '' entry; do
		name=${entry##*/}
		if ! skill_mutation_is_approved "$mode" "$source_index" "$name"; then
			if ! cp --archive -- "$entry" "$backup_root/$name"; then
				printf 'Error: could not protect unrelated global skill before installation: %s\n' "$entry" >&2
				return 1
			fi
		fi
	done < <(find "$global_target" -mindepth 1 -maxdepth 1 -print0)
}

verify_unrelated_skills() {
	local global_target=$1
	local backup_root=$2
	local mode=$3
	local source_index=$4
	local entry name target

	while IFS= read -r -d '' entry; do
		name=${entry##*/}
		target=$global_target/$name
		if ! skill_paths_match "$entry" "$target"; then
			printf 'Safety verification failed: unrelated global skill changed or was deleted: %s\n' "$target" >&2
			return 1
		fi
	done < <(find "$backup_root" -mindepth 1 -maxdepth 1 -print0)

	[[ -d $global_target ]] || return 0
	while IFS= read -r -d '' entry; do
		name=${entry##*/}
		if ! skill_mutation_is_approved "$mode" "$source_index" "$name" && \
			[[ ! -e $backup_root/$name && ! -L $backup_root/$name ]]; then
			printf 'Safety verification failed: official installer added an unapproved global skill: %s\n' "$entry" >&2
			return 1
		fi
	done < <(find "$global_target" -mindepth 1 -maxdepth 1 -print0)
}

restore_unrelated_skills() {
	local global_target=$1
	local backup_root=$2
	local mode=$3
	local source_index=$4
	local entry name restore_failed=false
	if ! mkdir -p -- "$global_target"; then
		printf 'Error: could not recreate the global skill target during recovery: %s\n' "$global_target" >&2
		return 1
	fi

	while IFS= read -r -d '' entry; do
		name=${entry##*/}
		if ! skill_mutation_is_approved "$mode" "$source_index" "$name" && \
			[[ ! -e $backup_root/$name && ! -L $backup_root/$name ]]; then
			if ! rm -rf -- "$entry"; then
				printf 'Error: could not remove unapproved installer addition: %s\n' "$entry" >&2
				restore_failed=true
			fi
		fi
	done < <(find "$global_target" -mindepth 1 -maxdepth 1 -print0)
	while IFS= read -r -d '' entry; do
		name=${entry##*/}
		if ! rm -rf -- "$global_target/$name"; then
			printf 'Error: could not clear damaged unrelated global skill: %s\n' "$global_target/$name" >&2
			restore_failed=true
			continue
		fi
		if ! cp --archive -- "$entry" "$global_target/$name"; then
			printf 'Error: could not restore unrelated global skill %s from %s\n' "$name" "$entry" >&2
			restore_failed=true
		fi
	done < <(find "$backup_root" -mindepth 1 -maxdepth 1 -print0)
	if [[ $restore_failed == true ]]; then
		printf 'Error: unrelated global skill recovery was incomplete; backup retained at %s\n' "$backup_root" >&2
		return 1
	fi
	printf 'Restored unrelated global skills from %s\n' "$backup_root" >&2
}

restore_skill_source() {
	local source_index=$1
	local global_target=$2
	local backup_root=$3
	local name state
	while IFS= read -r name; do
		state=${SKILL_STATES[$name]}
		if [[ $state != ADD ]]; then
			rm -rf -- "$global_target/$name"
			if cp --archive -- "$backup_root/$name" "$global_target/$name"; then
				printf 'Restored: %s from %s\n' "$name" "$backup_root/$name" >&2
			else
				printf 'Error: restore failed for %s; backup retained at %s\n' "$name" "$backup_root/$name" >&2
			fi
		elif [[ $state == ADD ]]; then
			rm -rf -- "$global_target/$name"
			printf 'Removed failed addition: %s\n' "$global_target/$name" >&2
		fi
	done < <(printf '%s\n' ${SKILLS_BY_SOURCE[$source_index]})
}

install_skills() {
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
				printf 'Error: unknown skills option: %s\n' "$option" >&2
				return 2
				;;
		esac
	done

	validate_skill_manifest || return 1
	for option in git npx jq diff; do
		if ! command -v "$option" >/dev/null 2>&1; then
			printf 'Error: missing skill installation prerequisite: %s\n' "$option" >&2
			return 1
		fi
	done
	local state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
	if [[ $state_home != /* ]]; then
		printf 'Error: XDG_STATE_HOME must be an absolute path\n' >&2
		return 1
	fi

	local work_root cleanup_command
	work_root=$(mktemp -d)
	printf -v cleanup_command 'rm -rf -- %q' "$work_root"
	trap "$cleanup_command" EXIT

	local installer_version global_target source_count source_index
	installer_version=$(jq -r '.installer.version' "$SKILL_MANIFEST")
	global_target=$HOME/.agents/skills
	source_count=$(jq '.sources | length' "$SKILL_MANIFEST")
	declare -A SKILL_CANDIDATES=()
	declare -A SKILL_STATES=()
	declare -A SKILL_OWNERS=()
	declare -A SKILLS_BY_SOURCE=()
	declare -A SOURCE_HAS_MUTATION=()

	printf 'Phase: inspect\n'
	for ((source_index = 0; source_index < source_count; source_index++)); do
		SOURCE_HAS_MUTATION[$source_index]=false
		local url revision expected checkout preview_home preview_state preview_cache candidate_root
		url=$(jq -r ".sources[$source_index].url" "$SKILL_MANIFEST")
		revision=$(jq -r ".sources[$source_index].revision" "$SKILL_MANIFEST")
		expected=$(jq ".sources[$source_index].expectedSkills" "$SKILL_MANIFEST")
		checkout=$work_root/source-$source_index
		preview_home=$work_root/preview-$source_index/home
		preview_state=$work_root/preview-$source_index/state
		preview_cache=$work_root/preview-$source_index/cache
		mkdir -p -- "$preview_home" "$preview_state" "$preview_cache/npm"
		if ! git clone --quiet -- "$url" "$checkout" || ! git -C "$checkout" checkout --quiet --detach "$revision"; then
			printf 'Error: could not check out pinned skill source %s at %s\n' "$url" "$revision" >&2
			return 1
		fi
		if ! HOME="$preview_home" XDG_STATE_HOME="$preview_state" XDG_CACHE_HOME="$preview_cache" \
			npm_config_cache="$preview_cache/npm" DISABLE_TELEMETRY=1 \
			npx --yes "skills@$installer_version" add "$checkout" --global --yes; then
			printf 'Error: official installer preview failed for %s\n' "$url" >&2
			return 1
		fi

		candidate_root=$preview_home/.agents/skills
		local -a discovered=()
		if [[ -d $candidate_root ]]; then
			mapfile -d '' -t discovered < <(find "$candidate_root" -mindepth 1 -maxdepth 1 -print0 | sort -z)
		fi
		if ((${#discovered[@]} != expected)); then
			printf 'Error: %s expected %d installable skills, discovered %d\n' "$url" "$expected" "${#discovered[@]}" >&2
			return 1
		fi
		local candidate name
		for candidate in "${discovered[@]}"; do
			name=${candidate##*/}
			if [[ ! $name =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
				printf 'Error: official installer produced an invalid skill name: %s\n' "$name" >&2
				return 1
			fi
			if [[ ! -d $candidate || -L $candidate ]]; then
				printf 'Error: official installer produced an unexpected skill type: %s\n' "$candidate" >&2
				return 1
			fi
			if [[ -n ${SKILL_OWNERS[$name]-} ]]; then
				printf 'Error: official skill name is owned by multiple sources: %s\n' "$name" >&2
				return 1
			fi
			SKILL_CANDIDATES[$name]=$candidate
			SKILL_OWNERS[$name]=$source_index
			SKILLS_BY_SOURCE[$source_index]+="$name "
		done
	done

	printf 'Phase: plan\n'
	local has_mutation=false has_conflict=false name candidate target state detail
	for ((source_index = 0; source_index < source_count; source_index++)); do
		while IFS= read -r name; do
			candidate=${SKILL_CANDIDATES[$name]}
			target=$global_target/$name
			detail=''
			if [[ ! -e $target && ! -L $target ]]; then
				state=ADD
				has_mutation=true
				SOURCE_HAS_MUTATION[$source_index]=true
			elif [[ -d $target && ! -L $target ]]; then
				if diff --recursive --brief --no-dereference -- "$target" "$candidate" >/dev/null; then
					state=UNCHANGED
				else
					state=CHANGE
					has_mutation=true
					SOURCE_HAS_MUTATION[$source_index]=true
				fi
			else
				state=CONFLICT
				has_conflict=true
				detail=$(path_type "$target")
				if [[ -L $target ]]; then
					detail+=" -> $(readlink -- "$target")"
				fi
			fi
			SKILL_STATES[$name]=$state
			printf '%s %s' "$state" "$name"
			[[ -n $detail ]] && printf ': %s' "$detail"
			printf '\n'
			if [[ $state == CHANGE ]]; then
				diff --recursive --no-dereference -- "$target" "$candidate" || true
			fi
		done < <(printf '%s\n' ${SKILLS_BY_SOURCE[$source_index]})
	done

	inspect_omarchy stderr
	if [[ $has_conflict == true ]]; then
		printf 'Error: resolve each CONFLICT, review the plan, then rerun with --yes; no global changes were made.\n' >&2
		return 2
	fi
	if [[ $has_mutation != true ]]; then
		printf 'All manifest-owned skills already match the approved versions.\n'
		return 0
	fi
	printf 'Phase: confirm\n'
	if [[ $interactive == true ]] && ! wizard_confirm 'Install this complete global skill plan?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if [[ $approved != true && $interactive != true ]]; then
		printf 'Decision required: review the plan and rerun with --yes to approve these global changes.\n' >&2
		return 2
	fi
	if [[ $interactive == true ]]; then
		printf 'Approval: accepted interactively\n'
	else
		printf 'Approval: accepted by --yes\n'
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true ]]; then
		if [[ $allow_mismatch != true ]]; then
			if [[ $interactive == true ]] && wizard_confirm "Continue despite the Omarchy version mismatch?"; then
				allow_mismatch=true
			fi
		fi
		if [[ $allow_mismatch != true ]]; then
			printf 'Confirmation required: review compatibility, then rerun: bin/dotfiles skills --yes --allow-omarchy-mismatch\n' >&2
			return 1
		fi
		printf 'Approval: Omarchy mismatch accepted by --allow-omarchy-mismatch\n'
	fi

	local timestamp backup_root
	timestamp=$(date -u +%Y%m%dT%H%M%S.%NZ)
	backup_root=$state_home/dotfiles/skill-backups/$timestamp
	for ((source_index = 0; source_index < source_count; source_index++)); do
		if [[ ${SOURCE_HAS_MUTATION[$source_index]} != true ]]; then
			printf 'Source unchanged: %s (official global installer skipped)\n' "$(jq -r ".sources[$source_index].name" "$SKILL_MANIFEST")"
			continue
		fi
		while IFS= read -r name; do
			if [[ ${SKILL_STATES[$name]} != ADD ]]; then
				mkdir -p -- "$backup_root"
				if ! cp --archive -- "$global_target/$name" "$backup_root/$name"; then
					printf 'Error: could not back up %s; global installation stopped\n' "$global_target/$name" >&2
					return 1
				fi
				printf 'Backup created: %s\n' "$backup_root/$name"
			fi
			done < <(printf '%s\n' ${SKILLS_BY_SOURCE[$source_index]})
		local unrelated_backup=$backup_root/unrelated-source-$source_index
		if ! backup_unrelated_skills "$global_target" "$unrelated_backup" source "$source_index"; then
			return 1
		fi

		local checkout=$work_root/source-$source_index
		printf 'Phase: apply (%s)\n' "$(jq -r ".sources[$source_index].name" "$SKILL_MANIFEST")"
		mkdir -p -- "$global_target"
		if ! DISABLE_TELEMETRY=1 npm_config_cache="${XDG_CACHE_HOME:-$HOME/.cache}/npm" \
			npx --yes "skills@$installer_version" add "$checkout" --global --yes; then
			printf 'Error: official global installer failed for %s\n' "$(jq -r ".sources[$source_index].url" "$SKILL_MANIFEST")" >&2
			restore_skill_source "$source_index" "$global_target" "$backup_root"
			restore_unrelated_skills "$global_target" "$unrelated_backup" source "$source_index" || true
			return 1
		fi

		printf 'Phase: verify (%s)\n' "$(jq -r ".sources[$source_index].name" "$SKILL_MANIFEST")"
		if ! verify_unrelated_skills "$global_target" "$unrelated_backup" source "$source_index"; then
			restore_skill_source "$source_index" "$global_target" "$backup_root"
			restore_unrelated_skills "$global_target" "$unrelated_backup" source "$source_index" || true
			return 1
		fi
		local source_failed=false
		while IFS= read -r name; do
			candidate=${SKILL_CANDIDATES[$name]}
			target=$global_target/$name
			if [[ ! -d $target || -L $target ]] || ! diff --recursive --brief --no-dereference -- "$target" "$candidate" >/dev/null; then
				printf 'Verification failed: %s: %s\n' "$name" "$target" >&2
				source_failed=true
				break
			fi
			printf 'Verified: %s: %s\n' "$name" "$target"
		done < <(printf '%s\n' ${SKILLS_BY_SOURCE[$source_index]})
		if [[ $source_failed == true ]]; then
			restore_skill_source "$source_index" "$global_target" "$backup_root"
			restore_unrelated_skills "$global_target" "$unrelated_backup" source "$source_index" || true
			return 1
		fi
	done
	printf 'Restart the agent or reload its skills to use the installed versions.\n'
}

preview_skill_checkout() {
	local checkout=$1
	local preview_root=$2
	local installer_version=$3
	local preview_home=$preview_root/home
	local preview_state=$preview_root/state
	local preview_cache=$preview_root/cache
	mkdir -p -- "$preview_home" "$preview_state" "$preview_cache/npm"
	HOME="$preview_home" XDG_STATE_HOME="$preview_state" XDG_CACHE_HOME="$preview_cache" \
		npm_config_cache="$preview_cache/npm" DISABLE_TELEMETRY=1 \
		npx --yes "skills@$installer_version" add "$checkout" --global --yes
}

restore_skill_update() {
	local global_target=$1
	local backup_root=$2
	local name restore_failed=false
	while IFS= read -r name; do
		[[ -n $name ]] || continue
		rm -rf -- "$global_target/$name"
		if [[ ${UPDATE_SKILL_EXISTED[$name]-false} == true ]]; then
			if ! cp --archive -- "$backup_root/skills/$name" "$global_target/$name"; then
				printf 'Error: could not restore affected skill %s from %s\n' "$name" "$backup_root/skills/$name" >&2
				restore_failed=true
			fi
		fi
	done < <(printf '%s\n' "${!UPDATE_AFFECTED_SKILLS[@]}" | sort)

	if ! cp --archive -- "$backup_root/skills.json" "$SKILL_MANIFEST.restore" || \
		! mv -- "$SKILL_MANIFEST.restore" "$SKILL_MANIFEST"; then
		printf 'Error: could not restore the skill manifest from %s\n' "$backup_root/skills.json" >&2
		restore_failed=true
	fi
	if [[ -d $backup_root/unrelated ]] && ! restore_unrelated_skills "$global_target" "$backup_root/unrelated" update 0; then
		restore_failed=true
	fi
	if [[ $restore_failed == true ]]; then
		printf 'Error: update rollback was incomplete; backups remain at %s\n' "$backup_root" >&2
		return 1
	fi
	printf 'Rolled back manifest and all affected global skills.\n' >&2
}

update_skills() {
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
				printf 'Error: unknown skills-update option: %s\n' "$option" >&2
				return 2
				;;
		esac
	done

	validate_skill_manifest || return 1
	for option in git npx jq diff; do
		if ! command -v "$option" >/dev/null 2>&1; then
			printf 'Error: missing skill update prerequisite: %s\n' "$option" >&2
			return 1
		fi
	done
	local state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
	if [[ $state_home != /* ]]; then
		printf 'Error: XDG_STATE_HOME must be an absolute path\n' >&2
		return 1
	fi

	local work_root cleanup_command
	work_root=$(mktemp -d)
	printf -v cleanup_command 'rm -rf -- %q' "$work_root"
	trap "$cleanup_command" EXIT

	local installer_version global_target source_count source_index
	installer_version=$(jq -r '.installer.version' "$SKILL_MANIFEST")
	global_target=$HOME/.agents/skills
	source_count=$(jq '.sources | length' "$SKILL_MANIFEST")
	local proposed_manifest=$work_root/skills.json
	cp -- "$SKILL_MANIFEST" "$proposed_manifest"
	declare -A UPDATE_SOURCE_CHANGED=()
	declare -A UPDATE_SOURCE_CHECKOUT=()
	declare -A UPDATE_SOURCE_OLD_SKILLS=()
	declare -A UPDATE_SOURCE_NEW_SKILLS=()
	declare -A UPDATE_OLD_CANDIDATES=()
	declare -A UPDATE_NEW_CANDIDATES=()
	declare -A UPDATE_AFFECTED_SKILLS=()
	declare -A UPDATE_SKILL_EXISTED=()
	declare -A UPDATE_NEW_OWNERS=()
	declare -A UPDATE_OLD_OWNERS=()
	local has_update=false has_conflict=false

	printf 'Phase: inspect\n'
	for ((source_index = 0; source_index < source_count; source_index++)); do
		local source_name url old_revision new_revision checkout
		source_name=$(jq -r ".sources[$source_index].name" "$SKILL_MANIFEST")
		url=$(jq -r ".sources[$source_index].url" "$SKILL_MANIFEST")
		old_revision=$(jq -r ".sources[$source_index].revision" "$SKILL_MANIFEST")
		checkout=$work_root/source-$source_index
		if ! git clone --quiet -- "$url" "$checkout"; then
			printf 'Error: could not discover upstream revision for %s\n' "$url" >&2
			return 1
		fi
		new_revision=$(git -C "$checkout" rev-parse HEAD) || {
			printf 'Error: could not resolve upstream revision for %s\n' "$url" >&2
			return 1
		}
		if [[ ! $new_revision =~ ^[0-9a-f]{40}$ ]]; then
			printf 'Error: upstream returned an invalid revision for %s: %s\n' "$url" "$new_revision" >&2
			return 1
		fi
		local source_changed=false
		local new_preview=$work_root/new-$source_index
		local -a old_discovered=() new_discovered=()
		local expected
		expected=$(jq ".sources[$source_index].expectedSkills" "$SKILL_MANIFEST")
		if [[ $new_revision == "$old_revision" ]]; then
			printf 'Source current: %s at %s\n' "$source_name" "$old_revision"
			UPDATE_SOURCE_CHANGED[$source_index]=false
		else
			source_changed=true
			has_update=true
			UPDATE_SOURCE_CHANGED[$source_index]=true
			UPDATE_SOURCE_CHECKOUT[$source_index]=$checkout
			printf 'Source update: %s\n' "$source_name"
			printf '  Revision: %s -> %s\n' "$old_revision" "$new_revision"
			printf '  Commit summaries:\n'
			git -C "$checkout" log --oneline "$old_revision..$new_revision" || {
				printf 'Error: could not summarize upstream commits for %s\n' "$source_name" >&2
				return 1
			}
			printf '  Source diff:\n'
			git -C "$checkout" diff --no-ext-diff "$old_revision" "$new_revision" || {
				printf 'Error: could not diff upstream revisions for %s\n' "$source_name" >&2
				return 1
			}

			local old_preview=$work_root/old-$source_index
			if ! git -C "$checkout" checkout --quiet --detach "$old_revision" || \
				! preview_skill_checkout "$checkout" "$old_preview" "$installer_version"; then
				printf 'Error: official installer preview failed for pinned source %s\n' "$url" >&2
				return 1
			fi
			if [[ -d $old_preview/home/.agents/skills ]]; then
				mapfile -d '' -t old_discovered < <(find "$old_preview/home/.agents/skills" -mindepth 1 -maxdepth 1 -print0 | sort -z)
			fi
			if ((${#old_discovered[@]} != expected)); then
				printf 'Error: pinned %s expected %d installable skills, discovered %d\n' "$url" "$expected" "${#old_discovered[@]}" >&2
				return 1
			fi
		fi

		if ! git -C "$checkout" checkout --quiet --detach "$new_revision" || \
			! preview_skill_checkout "$checkout" "$new_preview" "$installer_version"; then
			printf 'Error: official installer preview failed for proposed source %s\n' "$url" >&2
			return 1
		fi
		if [[ -d $new_preview/home/.agents/skills ]]; then
			mapfile -d '' -t new_discovered < <(find "$new_preview/home/.agents/skills" -mindepth 1 -maxdepth 1 -print0 | sort -z)
		fi
		if ((${#new_discovered[@]} == 0)); then
			printf 'Error: proposed %s discovered no installable skills\n' "$url" >&2
			return 1
		fi
		if [[ $source_changed != true && ${#new_discovered[@]} -ne $expected ]]; then
			printf 'Error: proposed %s expected %d installable skills, discovered %d\n' "$url" "$expected" "${#new_discovered[@]}" >&2
			return 1
		fi

		local candidate name
		for candidate in "${old_discovered[@]}"; do
			name=${candidate##*/}
			if [[ ! $name =~ ^[a-z0-9][a-z0-9-]*$ || ! -d $candidate || -L $candidate ]]; then
				printf 'Error: pinned official installer produced an invalid skill: %s\n' "$name" >&2
				return 1
			fi
			if [[ -n ${UPDATE_OLD_OWNERS[$name]-} && ${UPDATE_OLD_OWNERS[$name]} != "$source_index" ]]; then
				printf 'Error: pinned official skill name is owned by multiple sources: %s\n' "$name" >&2
				return 1
			fi
			UPDATE_OLD_CANDIDATES[$name]=$candidate
			UPDATE_OLD_OWNERS[$name]=$source_index
			UPDATE_SOURCE_OLD_SKILLS[$source_index]+="$name "
			[[ $source_changed == true ]] && UPDATE_AFFECTED_SKILLS[$name]=true
		done
		for candidate in "${new_discovered[@]}"; do
			name=${candidate##*/}
			if [[ ! $name =~ ^[a-z0-9][a-z0-9-]*$ || ! -d $candidate || -L $candidate ]]; then
				printf 'Error: proposed official installer produced an invalid skill: %s\n' "$name" >&2
				return 1
			fi
			if [[ -n ${UPDATE_NEW_OWNERS[$name]-} && ${UPDATE_NEW_OWNERS[$name]} != "$source_index" ]]; then
				local existing_owner
				existing_owner=$(jq -r ".sources[${UPDATE_NEW_OWNERS[$name]}].name" "$SKILL_MANIFEST")
				printf 'Error: proposed official skill name is owned by multiple sources: %s (%s and %s)\n' "$name" "$existing_owner" "$source_name" >&2
				return 1
			fi
			UPDATE_NEW_CANDIDATES[$name]=$candidate
			UPDATE_NEW_OWNERS[$name]=$source_index
			UPDATE_SOURCE_NEW_SKILLS[$source_index]+="$name "
			[[ $source_changed == true ]] && UPDATE_AFFECTED_SKILLS[$name]=true
		done

		if [[ $source_changed == true ]]; then
			local next_manifest=$work_root/skills-$source_index.json
			if ! jq --argjson index "$source_index" --arg revision "$new_revision" --argjson count "${#new_discovered[@]}" \
				'.sources[$index].revision = $revision | .sources[$index].expectedSkills = $count' \
				"$proposed_manifest" >"$next_manifest"; then
				printf 'Error: could not prepare the proposed skill manifest\n' >&2
				return 1
			fi
			mv -- "$next_manifest" "$proposed_manifest"
		fi
	done

	if [[ $has_update != true ]]; then
		printf 'No upstream skill updates are available.\n'
		return 0
	fi

	printf 'Phase: plan\n'
	for ((source_index = 0; source_index < source_count; source_index++)); do
		[[ ${UPDATE_SOURCE_CHANGED[$source_index]-false} == true ]] || continue
		local source_name
		source_name=$(jq -r ".sources[$source_index].name" "$SKILL_MANIFEST")
		printf 'Candidate collection changes: %s\n' "$source_name"
		local name old_candidate new_candidate target state detail
		while IFS= read -r name; do
			[[ -n $name ]] || continue
			old_candidate=${UPDATE_OLD_CANDIDATES[$name]-}
			new_candidate=${UPDATE_NEW_CANDIDATES[$name]-}
			if [[ -z $old_candidate ]]; then
				state=ADD
			elif [[ -z $new_candidate ]]; then
				state=REMOVE
			elif diff --recursive --brief --no-dereference -- "$old_candidate" "$new_candidate" >/dev/null; then
				state=UNCHANGED
			else
				state=CHANGE
			fi
			printf 'CANDIDATE %s %s\n' "$state" "$name"
			if [[ $state == CHANGE ]]; then
				diff --recursive --no-dereference -- "$old_candidate" "$new_candidate" || true
			fi
		done < <(printf '%s\n' ${UPDATE_SOURCE_OLD_SKILLS[$source_index]-} ${UPDATE_SOURCE_NEW_SKILLS[$source_index]-} | sort -u)

		printf 'Installed collection changes: %s\n' "$source_name"
		while IFS= read -r name; do
			[[ -n $name ]] || continue
			new_candidate=${UPDATE_NEW_CANDIDATES[$name]-}
			target=$global_target/$name
			detail=''
			if [[ -z $new_candidate ]]; then
				[[ -e $target || -L $target ]] || continue
				if [[ -d $target && ! -L $target ]]; then
					state=REMOVE
				else
					state=CONFLICT
					has_conflict=true
					detail=$(path_type "$target")
					[[ -L $target ]] && detail+=" -> $(readlink -- "$target")"
				fi
			elif [[ ! -e $target && ! -L $target ]]; then
				state=ADD
			elif [[ -d $target && ! -L $target ]]; then
				if diff --recursive --brief --no-dereference -- "$target" "$new_candidate" >/dev/null; then
					state=UNCHANGED
				else
					state=CHANGE
				fi
			else
				state=CONFLICT
				has_conflict=true
				detail=$(path_type "$target")
				[[ -L $target ]] && detail+=" -> $(readlink -- "$target")"
			fi
			printf 'INSTALLED %s %s' "$state" "$name"
			[[ -n $detail ]] && printf ': %s' "$detail"
			printf '\n'
			if [[ $state == CHANGE ]]; then
				diff --recursive --no-dereference -- "$target" "$new_candidate" || true
			fi
		done < <(printf '%s\n' ${UPDATE_SOURCE_OLD_SKILLS[$source_index]-} ${UPDATE_SOURCE_NEW_SKILLS[$source_index]-} | sort -u)
	done

	inspect_omarchy stderr
	if [[ $has_conflict == true ]]; then
		printf 'Error: resolve each CONFLICT before approving the update; no changes were made.\n' >&2
		return 2
	fi

	printf 'Phase: confirm\n'
	if [[ $interactive == true ]] && ! wizard_confirm 'Apply this complete skill update plan?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if [[ $approved != true && $interactive != true ]]; then
		printf 'Decision required: review the complete update plan and rerun with --yes.\n' >&2
		return 2
	fi
	if [[ $interactive == true ]]; then
		printf 'Approval: complete update plan accepted interactively\n'
	else
		printf 'Approval: complete update plan accepted by --yes\n'
	fi
	if [[ $OMARCHY_VERSION_MISMATCH == true ]]; then
		if [[ $allow_mismatch != true ]]; then
			if [[ $interactive == true ]] && wizard_confirm "Continue despite the Omarchy version mismatch?"; then
				allow_mismatch=true
			fi
		fi
		if [[ $allow_mismatch != true ]]; then
			printf 'Confirmation required: review compatibility, then rerun: bin/dotfiles skills-update --yes --allow-omarchy-mismatch\n' >&2
			return 1
		fi
		printf 'Approval: Omarchy mismatch accepted by --allow-omarchy-mismatch\n'
	fi

	local timestamp backup_root
	timestamp=$(date -u +%Y%m%dT%H%M%S.%NZ)
	backup_root=$state_home/dotfiles/skill-update-backups/$timestamp
	if ! mkdir -p -- "$backup_root/skills" || ! cp --archive -- "$SKILL_MANIFEST" "$backup_root/skills.json"; then
		printf 'Error: could not preserve the old skill manifest; update stopped before mutation\n' >&2
		return 1
	fi
	printf 'Manifest backup created: %s\n' "$backup_root/skills.json"
	local name
	while IFS= read -r name; do
		[[ -n $name ]] || continue
		if [[ -e $global_target/$name || -L $global_target/$name ]]; then
			UPDATE_SKILL_EXISTED[$name]=true
			if ! cp --archive -- "$global_target/$name" "$backup_root/skills/$name"; then
				printf 'Error: could not preserve affected skill %s; update stopped before mutation\n' "$name" >&2
				return 1
			fi
			printf 'Skill backup created: %s\n' "$backup_root/skills/$name"
		else
			UPDATE_SKILL_EXISTED[$name]=false
		fi
	done < <(printf '%s\n' "${!UPDATE_AFFECTED_SKILLS[@]}" | sort)
	if ! backup_unrelated_skills "$global_target" "$backup_root/unrelated" update 0; then
		printf 'Error: could not protect unrelated global skills; update stopped before mutation\n' >&2
		return 1
	fi

	printf 'Phase: apply manifest\n'
	if ! cp -- "$proposed_manifest" "$SKILL_MANIFEST.update" || ! mv -- "$SKILL_MANIFEST.update" "$SKILL_MANIFEST"; then
		printf 'Error: could not apply the proposed skill manifest\n' >&2
		restore_skill_update "$global_target" "$backup_root" || true
		return 1
	fi
	for ((source_index = 0; source_index < source_count; source_index++)); do
		[[ ${UPDATE_SOURCE_CHANGED[$source_index]-false} == true ]] || continue
		local source_checkout=${UPDATE_SOURCE_CHECKOUT[$source_index]}
		printf 'Phase: apply (%s)\n' "$(jq -r ".sources[$source_index].name" "$SKILL_MANIFEST")"
		if ! mkdir -p -- "$global_target"; then
			printf 'Error: could not create the global skill target: %s\n' "$global_target" >&2
			restore_skill_update "$global_target" "$backup_root" || true
			return 1
		fi
		if ! DISABLE_TELEMETRY=1 npm_config_cache="${XDG_CACHE_HOME:-$HOME/.cache}/npm" \
			npx --yes "skills@$installer_version" add "$source_checkout" --global --yes; then
			printf 'Error: official global installer failed for %s\n' "$(jq -r ".sources[$source_index].url" "$SKILL_MANIFEST")" >&2
			restore_skill_update "$global_target" "$backup_root" || true
			return 1
		fi
		while IFS= read -r name; do
			[[ -n $name ]] || continue
			if [[ -z ${UPDATE_NEW_CANDIDATES[$name]-} ]] && ! rm -rf -- "$global_target/$name"; then
				printf 'Error: could not remove retired skill %s\n' "$name" >&2
				restore_skill_update "$global_target" "$backup_root" || true
				return 1
			fi
		done < <(printf '%s\n' ${UPDATE_SOURCE_OLD_SKILLS[$source_index]-})
	done

	printf 'Phase: verify\n'
	if ! validate_skill_manifest; then
		restore_skill_update "$global_target" "$backup_root" || true
		return 1
	fi
	if ! verify_unrelated_skills "$global_target" "$backup_root/unrelated" update 0; then
		restore_skill_update "$global_target" "$backup_root" || true
		return 1
	fi
	for ((source_index = 0; source_index < source_count; source_index++)); do
		[[ ${UPDATE_SOURCE_CHANGED[$source_index]-false} == true ]] || continue
		local verified_count=0 source_failed=false
		while IFS= read -r name; do
			[[ -n $name ]] || continue
			local candidate=${UPDATE_NEW_CANDIDATES[$name]}
			local target=$global_target/$name
			if [[ ! -d $target || -L $target ]] || ! diff --recursive --brief --no-dereference -- "$target" "$candidate" >/dev/null; then
				printf 'Verification failed: %s: %s\n' "$name" "$target" >&2
				source_failed=true
				break
			fi
			verified_count=$((verified_count + 1))
		done < <(printf '%s\n' ${UPDATE_SOURCE_NEW_SKILLS[$source_index]-})
		if [[ $source_failed != true ]]; then
			while IFS= read -r name; do
				[[ -n $name ]] || continue
				if [[ -z ${UPDATE_NEW_CANDIDATES[$name]-} && ( -e $global_target/$name || -L $global_target/$name ) ]]; then
					printf 'Verification failed: retired skill remains: %s\n' "$global_target/$name" >&2
					source_failed=true
					break
				fi
			done < <(printf '%s\n' ${UPDATE_SOURCE_OLD_SKILLS[$source_index]-})
		fi
		local expected
		expected=$(jq ".sources[$source_index].expectedSkills" "$SKILL_MANIFEST")
		if [[ $source_failed == true || $verified_count -ne $expected ]]; then
			[[ $source_failed == true ]] || printf 'Verification failed: expected %d skills, verified %d\n' "$expected" "$verified_count" >&2
			restore_skill_update "$global_target" "$backup_root" || true
			return 1
		fi
		printf 'Verified collection: %s (%d skills)\n' "$(jq -r ".sources[$source_index].name" "$SKILL_MANIFEST")" "$verified_count"
	done
	printf 'Updated skill manifest and global collections atomically.\n'
	printf 'Restart the agent or reload its skills to use the installed versions.\n'
}
