readonly TELEGRAM_THEME_ARCHIVE_NAME='current.tdesktop-theme'
readonly TELEGRAM_THEME_EXPECTED_OMARCHY='4.0.1-1'
readonly TELEGRAM_THEME_EXPECTED_TELEGRAM='7.0.9-4'

telegram_theme_state_home() {
	printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

telegram_theme_archive_path() {
	printf '%s/dotfiles/telegram-theme/%s\n' "$(telegram_theme_state_home)" "$TELEGRAM_THEME_ARCHIVE_NAME"
}

telegram_theme_status_path() {
	printf '%s/dotfiles/telegram-theme/status.json\n' "$(telegram_theme_state_home)"
}

telegram_theme_active_slug_path() {
	printf '%s/omarchy/current/theme.name\n' "$(telegram_theme_state_home)"
}

telegram_theme_active_manifest_path() {
	printf '%s/omarchy/current/theme/telegram-omarchy-theme.json\n' "$(telegram_theme_state_home)"
}

telegram_theme_installed_hook() {
	printf '%s/.config/omarchy/hooks/theme-set.d/telegram-theme\n' "$HOME"
}

telegram_theme_assets_are_linked() {
	local package_root="$REPOSITORY_ROOT/config/telegram-theme"
	local source relative target source_canonical target_canonical found=false
	while IFS= read -r -d '' source; do
		found=true
		relative=${source#"$package_root/"}
		target=$HOME/$relative
		if [[ ! -e $target && ! -L $target ]]; then
			printf 'Required Telegram theme asset is not linked: %s\n' "$target" >&2
			return 1
		fi
		source_canonical=$(readlink -f -- "$source") || return 1
		target_canonical=$(readlink -f -- "$target") || return 1
		if [[ $target_canonical != "$source_canonical" ]]; then
			printf 'Required Telegram theme asset is not linked from this repository: %s\n' "$target" >&2
			return 1
		fi
	done < <(find "$package_root" -type f -print0)
	if [[ $found != true ]]; then
		printf 'Required Telegram theme package assets are unavailable: %s\n' "$package_root" >&2
		return 1
	fi
	local hook
	hook=$(telegram_theme_installed_hook)
	if [[ ! -x $hook ]]; then
		printf 'Installed Telegram theme hook is not executable: %s\n' "$hook" >&2
		return 1
	fi
}

telegram_theme_require_linked_assets() {
	telegram_theme_assets_are_linked || {
		printf 'Recovery: choose Apply Stow packages and select telegram-theme, then retry this operation.\n' >&2
		return 1
	}
}

telegram_theme_installed_package_version() {
	local package=$1 metadata name version extra
	metadata=$(LC_ALL=C pacman -Q "$package" 2>/dev/null) || return 1
	[[ $metadata != *$'\n'* ]] || return 1
	read -r name version extra <<<"$metadata"
	[[ $name == "$package" && -n $version && -z $extra ]] || return 1
	printf '%s\n' "$version"
}

telegram_theme_require_compatible_packages() {
	local detected_omarchy=unavailable detected_telegram=unavailable version
	if version=$(telegram_theme_installed_package_version omarchy); then
		detected_omarchy=$version
	fi
	if version=$(telegram_theme_installed_package_version telegram-desktop); then
		detected_telegram=$version
	fi
	printf 'Expected Telegram theme packages: omarchy %s; telegram-desktop %s\n' \
		"$TELEGRAM_THEME_EXPECTED_OMARCHY" "$TELEGRAM_THEME_EXPECTED_TELEGRAM"
	printf 'Detected Telegram theme packages: omarchy %s; telegram-desktop %s\n' \
		"$detected_omarchy" "$detected_telegram"
	if [[ $detected_omarchy != "$TELEGRAM_THEME_EXPECTED_OMARCHY" ||
		$detected_telegram != "$TELEGRAM_THEME_EXPECTED_TELEGRAM" ]]; then
		printf 'Error: Telegram theme setup is blocked by an unsupported or unverifiable package version.\n' >&2
		printf 'Recovery: restore the exact supported package versions or update this repository compatibility baseline, then choose Setup / refresh again.\n' >&2
		return 1
	fi
}

telegram_theme_path_is_writable_or_creatable() {
	local path=$1 ancestor=$1 parent
	[[ $path == /* ]] || return 1
	if [[ -e $path || -L $path ]]; then
		[[ -d $path && -w $path && -x $path ]]
		return
	fi
	while [[ ! -e $ancestor && ! -L $ancestor ]]; do
		parent=${ancestor%/*}
		[[ -n $parent && $parent != "$ancestor" ]] || return 1
		ancestor=$parent
	done
	[[ -d $ancestor && -w $ancestor && -x $ancestor ]]
}

telegram_theme_require_setup_runtime() {
	local command missing=false
	for command in node zip flock; do
		if ! command -v "$command" >/dev/null 2>&1; then
			printf 'Error: missing Telegram theme runtime command: %s\n' "$command" >&2
			missing=true
		fi
	done
	if [[ $missing == true ]]; then
		printf 'Recovery: restore the declared telegram-theme package requirements, then choose Setup / refresh again.\n' >&2
		return 1
	fi
	local node_output node_version
	if ! node_output=$(node --version 2>/dev/null) || [[ $node_output == *$'\n'* ]] ||
		[[ ! $node_output =~ ^v([0-9]+[.][0-9]+[.][0-9]+)$ ]]; then
		printf 'Error: Node.js version is unavailable or malformed; required version is %s or newer.\n' "$MINIMUM_NODE_VERSION" >&2
		printf 'Recovery: choose Prepare prerequisites, then choose Setup / refresh again.\n' >&2
		return 1
	fi
	node_version=${node_output#v}
	if ! version_at_least "$node_version" "$MINIMUM_NODE_VERSION"; then
		printf 'Error: Node.js %s is below required version %s.\n' "$node_version" "$MINIMUM_NODE_VERSION" >&2
		printf 'Recovery: choose Prepare prerequisites, then choose Setup / refresh again.\n' >&2
		return 1
	fi

	local state_home runtime_dir=${XDG_RUNTIME_DIR:-}
	state_home=$(telegram_theme_state_home)
	if [[ $state_home != /* ]] || ! telegram_theme_path_is_writable_or_creatable "$state_home" ||
		! telegram_theme_path_is_writable_or_creatable "$state_home/dotfiles/telegram-theme"; then
		printf 'Error: Telegram theme setup requires an absolute writable XDG_STATE_HOME: %s\n' "$state_home" >&2
		printf 'Recovery: set XDG_STATE_HOME to an absolute writable state directory, then choose Setup / refresh again.\n' >&2
		return 1
	fi
	if [[ -z $runtime_dir || $runtime_dir != /* || ! -d $runtime_dir || ! -w $runtime_dir || ! -x $runtime_dir ]]; then
		printf 'Error: Telegram theme setup requires an existing absolute writable XDG_RUNTIME_DIR: %s\n' "${runtime_dir:-unset}" >&2
		printf 'Recovery: restore the user runtime directory and XDG_RUNTIME_DIR, then choose Setup / refresh again.\n' >&2
		return 1
	fi
}

telegram_theme_verify_publication() {
	local archive status_file active_slug_path active_slug expected_hash actual_hash
	archive=$(telegram_theme_archive_path)
	status_file=$(telegram_theme_status_path)
	active_slug_path=$(telegram_theme_active_slug_path)
	if [[ ! -f $archive || -L $archive || ! -s $archive || ! -r $active_slug_path ]]; then
		return 1
	fi
	active_slug=$(<"$active_slug_path")
	[[ -n $active_slug ]] || return 1
	expected_hash=$(jq -er --arg slug "$active_slug" \
		'select(.schema_version == 1 and .status == "ok" and .slug == $slug and (.archive_sha256 | type == "string")) | .archive_sha256' \
		"$status_file" 2>/dev/null) || return 1
	[[ $expected_hash =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
	read -r actual_hash _ < <(sha256sum "$archive") || return 1
	[[ $actual_hash == "${expected_hash,,}" ]]
}

telegram_theme_print_import_instructions() {
	local archive
	archive=$(telegram_theme_archive_path)
	printf 'Telegram theme archive generated and verified: %s\n' "$archive"
	printf 'One-time Telegram action (Dotfiles will not perform it):\n'
	printf '  Import %s in Telegram Desktop.\n' "$archive"
	printf '  Review the preview and select Keep Changes.\n'
}

telegram_theme_status() {
	if (($# != 0)); then
		printf 'Error: telegram_theme_status accepts no arguments.\n' >&2
		return 2
	fi
	local archive status_file status slug message
	archive=$(telegram_theme_archive_path)
	status_file=$(telegram_theme_status_path)
	if [[ ! -e $status_file && ! -e $archive ]]; then
		printf 'Telegram theme integration is not set up. Apply the telegram-theme package, then choose Setup / refresh.\n'
		return 0
	fi
	printf 'Telegram theme archive: %s (%s)\n' "$archive" "$([[ -s $archive ]] && printf present || printf absent)"
	if [[ ! -r $status_file ]] || ! jq -e '.schema_version == 1 and (.status == "ok" or .status == "error")' \
		"$status_file" >/dev/null 2>&1; then
		printf 'Telegram theme status: unavailable or invalid (%s)\n' "$status_file"
		return 0
	fi
	status=$(jq -r '.status' "$status_file")
	slug=$(jq -r '.slug // "unknown"' "$status_file")
	printf 'Telegram theme status: %s\n' "$status"
	printf 'Active theme slug: %s\n' "$slug"
	if [[ $status == error ]]; then
		message=$(jq -r '.message // "No diagnostic message was recorded."' "$status_file")
		printf 'Diagnostic: %s\n' "$message"
		printf 'Recovery: choose Retry after resolving the diagnostic.\n'
	fi
}

setup_telegram_theme() {
	if (($# != 0)); then
		printf 'Error: setup_telegram_theme accepts no arguments.\n' >&2
		return 2
	fi
	telegram_theme_require_linked_assets || return 1
	telegram_theme_require_compatible_packages || return 1
	telegram_theme_require_setup_runtime || return 1
	printf 'Plan: set up Telegram theme synchronization\n'
	printf '  Run: omarchy theme refresh\n'
	printf '  Omarchy will regenerate the active manifest and invoke the installed theme-set hook.\n'
	printf '  Verify: %s and its structured status.\n' "$(telegram_theme_archive_path)"
	printf '  Telegram will not be launched, restarted, signaled, imported into, or otherwise controlled.\n'
	if ! wizard_confirm 'Run omarchy theme refresh to generate the Telegram theme?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if ! omarchy theme refresh; then
		printf 'Error: omarchy theme refresh did not complete successfully.\n' >&2
		printf 'Recovery: choose Retry in Manage Telegram theme after resolving the refresh error.\n' >&2
		return 1
	fi
	if ! telegram_theme_verify_publication; then
		printf 'Error: Telegram theme refresh did not produce a verified stable archive.\n' >&2
		telegram_theme_status
		printf 'Recovery: choose Retry in Manage Telegram theme after resolving the diagnostic.\n' >&2
		return 1
	fi
	telegram_theme_print_import_instructions
}

retry_telegram_theme() {
	if (($# != 0)); then
		printf 'Error: retry_telegram_theme accepts no arguments.\n' >&2
		return 2
	fi
	telegram_theme_require_linked_assets || return 1
	local slug_path manifest hook slug
	slug_path=$(telegram_theme_active_slug_path)
	manifest=$(telegram_theme_active_manifest_path)
	hook=$(telegram_theme_installed_hook)
	if [[ ! -r $slug_path ]]; then
		printf 'Error: active Omarchy theme slug is unavailable: %s\n' "$slug_path" >&2
		printf 'Recovery: select an Omarchy theme, then choose Retry in Manage Telegram theme.\n' >&2
		return 1
	fi
	slug=$(<"$slug_path")
	if [[ -z $slug || ! -r $manifest ]]; then
		printf 'Error: the promoted Omarchy theme manifest is unavailable for retry: %s\n' "$manifest" >&2
		printf 'Recovery: choose Setup / refresh in Manage Telegram theme.\n' >&2
		return 1
	fi
	printf 'Retrying Telegram theme generation for active Omarchy theme: %s\n' "$slug"
	if ! "$hook" "$slug"; then
		printf 'Error: Telegram theme retry failed.\n' >&2
		telegram_theme_status
		return 1
	fi
	if ! telegram_theme_verify_publication; then
		printf 'Error: Telegram theme retry did not produce a verified stable archive.\n' >&2
		telegram_theme_status
		return 1
	fi
	printf 'Telegram theme retry succeeded: %s\n' "$(telegram_theme_archive_path)"
	printf 'If Telegram no longer watches this file, import it again and select Keep Changes.\n'
}

manage_telegram_theme() {
	if (($# != 0)); then
		printf 'Error: manage_telegram_theme accepts no arguments.\n' >&2
		return 2
	fi
	local choice
	while true; do
		if ! choice=$(wizard_choose 'Manage Telegram theme' 'Status' 'Setup / refresh' 'Retry' 'Back'); then
			printf 'No Telegram theme operation selected.\n'
			return 0
		fi
		case $choice in
			Status) telegram_theme_status || return $? ;;
			'Setup / refresh') setup_telegram_theme; return $? ;;
			Retry) retry_telegram_theme; return $? ;;
			Back) return 0 ;;
		esac
	done
}
