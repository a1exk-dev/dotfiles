#!/usr/bin/env bash

# Install OBS set: copies a repository machine set (obs/sets/<set>/) into OBS.
# Copied profiles and collections belong to OBS afterwards, so there are no
# receipts and no Remove; the human deletes them inside OBS.

readonly OBS_SETS_ROOT="$REPOSITORY_ROOT/obs/sets"
readonly OBS_SET_COLLECTION_FILE=Omarchy_Scene.json
readonly OBS_SET_SKIPPED=3

# OBS encoder ids, mapped to the ffmpeg encoder a trial encode checks.
declare -A OBS_SET_TRIAL_ENCODERS=(
	[ffmpeg_vaapi_tex]=h264_vaapi
	[hevc_ffmpeg_vaapi_tex]=hevc_vaapi
	[av1_ffmpeg_vaapi_tex]=av1_vaapi
	[obs_x264]=none
)

obs_set_names() {
	find "$OBS_SETS_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Prints the directory of another profile that already carries the name.
obs_set_profile_owner() {
	local name=$1 directory=$2 candidate
	for candidate in "$(obs_config_dir)"/basic/profiles/*/; do
		candidate=${candidate%/}
		[[ -f $candidate/basic.ini && ${candidate##*/} != "$directory" ]] || continue
		if [[ $(obs_ini_value "$candidate/basic.ini" General Name) == "$name" ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

# Prints another collection file that already carries the name.
obs_set_collection_owner() {
	local name=$1 file=$2 candidate
	for candidate in "$(obs_config_dir)"/basic/scenes/*.json; do
		[[ -f $candidate && ${candidate##*/} != "$file" ]] || continue
		if [[ $(jq -r '.name // empty' "$candidate" 2>/dev/null) == "$name" ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

# Checks both encoders of one profile and prints why it is refused, if it is.
obs_set_encoder_refusal() {
	local ini=$1 key id trial
	for key in Encoder RecEncoder; do
		id=$(obs_ini_value "$ini" AdvOut "$key")
		trial=${OBS_SET_TRIAL_ENCODERS[$id]-}
		if [[ -z $trial ]]; then
			printf 'encoder %s is not in the supported table\n' "${id:-<unset>}"
			return 0
		fi
		if [[ $trial != none ]] && ! obs_trial_encode "$trial"; then
			printf 'a one-frame %s trial encode on %s failed\n' "$trial" "$OBS_RENDER_NODE"
			return 0
		fi
	done
	return 1
}

# The temporary copy in progress, removed if the action fails or is interrupted.
OBS_SET_TEMPORARY=''

obs_set_discard_temporary() {
	[[ -z $OBS_SET_TEMPORARY ]] || rm -rf -- "$OBS_SET_TEMPORARY"
	OBS_SET_TEMPORARY=''
}

# Copies one profile through a temporary directory, expanding $HOME.
obs_set_copy_profile() {
	local source=$1 directory=$2 action=$3 profiles file ini backup=''
	profiles=$(obs_config_dir)/basic/profiles
	mkdir -p -- "$profiles" || return 1
	OBS_SET_TEMPORARY=$(mktemp -d "$profiles/.$directory.XXXXXX") || return 1
	for file in basic.ini streamEncoder.json recordEncoder.json; do
		if ! cp -- "$source/$file" "$OBS_SET_TEMPORARY/$file"; then
			obs_set_discard_temporary
			printf 'Error: could not copy %s.\n' "$source/$file" >&2
			return 1
		fi
	done
	if ! ini=$(<"$OBS_SET_TEMPORARY/basic.ini") || ! printf '%s\n' "${ini//\$HOME/$HOME}" >"$OBS_SET_TEMPORARY/basic.ini" ||
		! chmod 0755 -- "$OBS_SET_TEMPORARY"; then
		obs_set_discard_temporary
		return 1
	fi
	if [[ $action == replace ]]; then
		backup=$(obs_backup_path "profile-$directory")
		if ! mkdir -p -- "${backup%/*}" || ! mv -T -- "$profiles/$directory" "$backup"; then
			obs_set_discard_temporary
			printf 'Error: could not back up %s.\n' "$profiles/$directory" >&2
			return 1
		fi
		printf 'Backup created: %s\n' "$backup"
	fi
	if ! mv -T -- "$OBS_SET_TEMPORARY" "$profiles/$directory"; then
		obs_set_discard_temporary
		printf 'Error: could not move the profile into %s.\n' "$profiles/$directory" >&2
		if [[ -n $backup ]] && mv -T -- "$backup" "$profiles/$directory"; then
			printf 'The previous profile was restored from %s.\n' "$backup" >&2
		elif [[ -n $backup ]]; then
			printf 'The previous profile is in %s.\n' "$backup" >&2
		fi
		return 1
	fi
	OBS_SET_TEMPORARY=''
	printf 'Installed profile: %s\n' "$profiles/$directory"
}

# Copies the collection through a temporary file, expanding $HOME in its paths.
obs_set_copy_collection() {
	local source=$1 action=$2 scenes target backup
	scenes=$(obs_config_dir)/basic/scenes
	target=$scenes/$OBS_SET_COLLECTION_FILE
	mkdir -p -- "$scenes" || return 1
	OBS_SET_TEMPORARY=$(mktemp "$scenes/.$OBS_SET_COLLECTION_FILE.XXXXXX") || return 1
	if ! jq --arg home "$HOME" 'walk(if type == "string" then gsub("\\$HOME"; $home) else . end)' "$source" >"$OBS_SET_TEMPORARY"; then
		obs_set_discard_temporary
		printf 'Error: could not copy %s.\n' "$source" >&2
		return 1
	fi
	if [[ $action == replace ]]; then
		backup=$(obs_backup_path "$OBS_SET_COLLECTION_FILE")
		if ! mkdir -p -- "${backup%/*}" || ! cp --archive -- "$target" "$backup"; then
			obs_set_discard_temporary
			printf 'Error: could not back up %s.\n' "$target" >&2
			return 1
		fi
		printf 'Backup created: %s\n' "$backup"
	fi
	if ! chmod 0644 -- "$OBS_SET_TEMPORARY" || ! mv -f -- "$OBS_SET_TEMPORARY" "$target"; then
		obs_set_discard_temporary
		printf 'Error: could not move the collection into %s.\n' "$target" >&2
		return 1
	fi
	OBS_SET_TEMPORARY=''
	printf 'Installed collection: %s\n' "$target"
}

# The geometry is repository data, so it is always written.
obs_set_write_geometry() {
	local source=$1 target temporary
	target=$(obs_scene_dir)/geometry.json
	mkdir -p -- "$(obs_scene_dir)" || return 1
	cmp -s -- "$source" "$target" && return 0
	temporary=$(mktemp "$(obs_scene_dir)/.geometry.json.XXXXXX") || return 1
	if ! cp -- "$source" "$temporary" || ! chmod 0644 -- "$temporary" || ! mv -f -- "$temporary" "$target"; then
		rm -f -- "$temporary"
		return 1
	fi
	printf 'Wrote %s\n' "$target"
}

# install_obs_set [SET] [--force] [--guided]
# --force replaces existing profiles and the collection without asking, after a
# backup. In guided setup a running OBS, a declined plan or a set that does not
# fit returns OBS_SET_SKIPPED instead of failing.
install_obs_set() {
	local set='' guided=false force=false argument
	for argument in "$@"; do
		case $argument in
			--guided) guided=true ;;
			--force) force=true ;;
			-*) printf 'Error: unknown Install OBS set option: %s\n' "$argument" >&2; return 2 ;;
			*) set=$argument ;;
		esac
	done
	# Run alone, a skip fails and a decline is a no-op; guided setup treats both as a skip.
	local skip_status=1 declined_status=0
	if [[ $guided == true ]]; then
		skip_status=$OBS_SET_SKIPPED
		declined_status=$OBS_SET_SKIPPED
	fi

	printf 'Phase: inspect\n'
	if ! command -v obs >/dev/null 2>&1; then
		printf 'Error: the obs command is missing, so no OBS set can be installed.\n' >&2
		printf 'Recovery: install OBS Studio (apply the obs-theme package), then choose Install OBS set in the Dotfiles wizard.\n' >&2
		return 1
	fi
	local -a sets=()
	mapfile -t sets < <(obs_set_names)
	if ((${#sets[@]} == 0)); then
		printf 'No OBS machine sets exist under %s.\n' "$OBS_SETS_ROOT"
		return "$skip_status"
	fi
	if [[ -z $set ]]; then
		if ! set=$(wizard_choose 'Choose an OBS machine set (none selected by default)' Cancel "${sets[@]}") || [[ $set == Cancel ]]; then
			printf 'No OBS set selected; no changes made.\n'
			return "$declined_status"
		fi
	fi
	if ! printf '%s\n' "${sets[@]}" | grep -Fxq -- "$set"; then
		printf 'Error: unknown OBS machine set: %s\n' "$set" >&2
		return 1
	fi
	if obs_is_running; then
		printf 'OBS is running. Close OBS, then choose Install OBS set again; no changes made.\n' >&2
		return "$skip_status"
	fi
	if ! obs_confirm_version; then
		printf 'No changes made.\n'
		return "$declined_status"
	fi
	inspect_omarchy stdout
	if [[ $OMARCHY_VERSION_MISMATCH == true ]] && ! wizard_confirm 'Continue despite the Omarchy version mismatch?'; then
		printf 'No changes made.\n'
		return "$declined_status"
	fi

	printf 'Phase: plan\n'
	local root=$OBS_SETS_ROOT/$set profile name refusal owner refused=false
	local -a install_profiles=() install_names=() profile_actions=()
	for profile in "$root"/profiles/*/; do
		profile=${profile%/}
		name=$(obs_ini_value "$profile/basic.ini" General Name)
		if owner=$(obs_set_profile_owner "$name" "${profile##*/}"); then
			printf 'Refused profile %s: %s already uses that name\n' "$name" "$owner"
			refused=true
		elif refusal=$(obs_set_encoder_refusal "$profile/basic.ini"); then
			printf 'Refused profile %s: %s\n' "$name" "$refusal"
			refused=true
		else
			install_profiles+=("$profile")
			install_names+=("$name")
		fi
	done
	local scene=false collection_action=copy collection_name=''
	if package_is_linked obs-scene; then
		scene=true
		collection_name=$(jq -r .name "$root/scene/$OBS_SET_COLLECTION_FILE")
		if owner=$(obs_set_collection_owner "$collection_name" "$OBS_SET_COLLECTION_FILE"); then
			printf 'Refused collection %s: %s already uses that name\n' "$collection_name" "$owner"
			refused=true
		fi
	fi
	if [[ $refused == true ]]; then
		printf 'OBS set %s does not fit this machine; no changes made.\n' "$set" >&2
		return "$skip_status"
	fi

	local index
	for index in "${!install_profiles[@]}"; do
		name=${install_names[$index]}
		if [[ ! -d $(obs_config_dir)/basic/profiles/${install_profiles[$index]##*/} ]]; then
			profile_actions+=(copy)
			printf 'Plan: copy profile %s\n' "$name"
		elif [[ $force == true ]] || wizard_confirm "Replace the existing profile $name? It is backed up first."; then
			profile_actions+=(replace)
			printf 'Plan: back up and replace profile %s\n' "$name"
		else
			profile_actions+=(keep)
			printf 'Plan: keep the existing profile %s\n' "$name"
		fi
	done
	if [[ $scene == true ]]; then
		if [[ ! -f $(obs_config_dir)/basic/scenes/$OBS_SET_COLLECTION_FILE ]]; then
			printf 'Plan: copy collection %s\n' "$collection_name"
		elif [[ $force == true ]] || wizard_confirm "Replace the existing collection $collection_name? It is backed up first."; then
			collection_action=replace
			printf 'Plan: back up and replace collection %s\n' "$collection_name"
		else
			collection_action=keep
			printf 'Plan: keep the existing collection %s\n' "$collection_name"
		fi
		printf 'Plan: write %s/geometry.json and render the scene assets once\n' "$(obs_scene_dir)"
	else
		collection_action=keep
		printf 'Plan: skip the scene because obs-scene is not applied; apply obs-scene, then choose Install OBS set again.\n'
	fi
	printf 'Plan: select profile %s in user.ini\n' "${install_names[0]}"
	[[ $collection_action == keep ]] || printf 'Plan: select collection %s in user.ini\n' "$collection_name"

	printf 'Phase: confirm\n'
	if ! wizard_confirm "Install OBS set $set?"; then
		printf 'No changes made.\n'
		return "$declined_status"
	fi
	if obs_is_running; then
		printf 'Error: OBS started before the copy; no changes made.\n' >&2
		return 1
	fi

	printf 'Phase: copy\n'
	trap 'obs_set_discard_temporary; exit 130' INT TERM
	local copied=true
	for index in "${!install_profiles[@]}"; do
		[[ ${profile_actions[$index]} != keep ]] || continue
		obs_set_copy_profile "${install_profiles[$index]}" "${install_profiles[$index]##*/}" "${profile_actions[$index]}" || copied=false
	done
	if [[ $copied == true && $scene == true && $collection_action != keep ]]; then
		obs_set_copy_collection "$root/scene/$OBS_SET_COLLECTION_FILE" "$collection_action" || copied=false
	fi
	trap - INT TERM
	[[ $copied == true ]] || return 1
	if [[ $scene == true ]]; then
		obs_set_write_geometry "$root/scene/geometry.json" || {
			printf 'Error: could not write the scene geometry.\n' >&2
			return 1
		}
		obs_scene_render ||
			printf 'Warning: the scene assets were not rendered; fix the reported problem, then run omarchy theme set.\n' >&2
	fi

	printf 'Phase: select\n'
	if [[ ! -f $(obs_config_dir)/user.ini ]]; then
		printf 'OBS has no user.ini yet; select the profile and collection in OBS.\n'
	else
		local -a keys=("Profile=${install_names[0]}" "ProfileDir=${install_profiles[0]##*/}")
		[[ $collection_action == keep ]] || keys+=("SceneCollection=$collection_name" "SceneCollectionFile=${OBS_SET_COLLECTION_FILE%.json}")
		obs_user_ini_set Basic "${keys[@]}" || return 1
	fi
	printf 'Installed OBS set: %s\n' "$set"
	printf 'The copied profiles and collection now belong to OBS; delete them inside OBS when you no longer want them.\n'
}
