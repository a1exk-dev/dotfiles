readonly WALLPAPER_INBOX_ROOT="$REPOSITORY_ROOT/wallpapers/inbox"
readonly WALLPAPER_LIBRARY_ROOT="$REPOSITORY_ROOT/wallpapers/library"
readonly WALLPAPER_FILES_HELPER="$REPOSITORY_ROOT/lib/dotfiles/wallpaper-files.mjs"
readonly WALLPAPER_SCHEMA_VERSION=1
readonly WALLPAPER_SUPPORTED_OMARCHY_MAJOR=${SUPPORTED_OMARCHY_VERSION:-4}
readonly WALLPAPER_OPERATION_CONTEXT_ORDINARY='ordinary'
readonly WALLPAPER_OPERATION_CONTEXT_RECOVERY_COMPLETED='recovery-completed'

WALLPAPER_IMAGE_FORMAT=''
WALLPAPER_IMAGE_EXTENSION=''
WALLPAPER_IMAGE_DIGEST=''
WALLPAPER_IMAGE_WIDTH=''
WALLPAPER_IMAGE_HEIGHT=''
WALLPAPER_IMAGE_FRAMES=''
WALLPAPER_IMAGE_SIZE=''
WALLPAPER_IMAGE_IDENTITY=''
WALLPAPER_IMAGE_ERROR=''
WALLPAPER_LIBRARY_ERROR=''
WALLPAPER_LIBRARY_ASSIGNMENTS=0
WALLPAPER_LIBRARY_MANAGED=0

wallpaper_files() {
	node "$WALLPAPER_FILES_HELPER" "$@"
}

wallpaper_image_format_extension() {
	case $1 in
		JPEG) printf 'jpg\n' ;;
		PNG) printf 'png\n' ;;
		GIF) printf 'gif\n' ;;
		BMP) printf 'bmp\n' ;;
		WEBP) printf 'webp\n' ;;
		*) return 1 ;;
	esac
}

wallpaper_file_digest() {
	local identity
	identity=$(wallpaper_files identity "$1") || return 1
	jq -er '.digest' <<<"$identity"
}

wallpaper_file_identity() {
	wallpaper_files identity "$1"
}

wallpaper_live_file_identity() {
	wallpaper_files identity-live "$1"
}

wallpaper_files_are_same() {
	wallpaper_files same "$1" "$2"
}

wallpaper_live_file_matches_source() {
	wallpaper_files same-live "$1" "$2"
}

wallpaper_file_mode() {
	local identity
	identity=$(wallpaper_file_identity "$1") || return 1
	jq -er '.mode' <<<"$identity"
}

wallpaper_identity_json_is_valid() {
	local identity=$1 expected_mode=${2-} expected_digest=${3-}
	jq -e --arg mode "$expected_mode" --arg digest "$expected_digest" '
		type == "object" and
		keys == ["ctime_ns","device","digest","gid","inode","mode","mtime_ns","nlink","size","uid"] and
		all(.ctime_ns,.device,.gid,.inode,.mtime_ns,.size,.uid; type == "string" and test("^[0-9]+$")) and
		(.digest | type == "string" and test("^[0-9a-f]{64}$")) and
		(.mode | type == "string" and test("^0[0-7]{3}$")) and .nlink == 1 and
		($mode == "" or .mode == $mode) and ($digest == "" or .digest == $digest)
	' <<<"$identity" >/dev/null 2>&1
}

wallpaper_identity_matches() {
	local path=$1 expected=$2 actual
	actual=$(wallpaper_file_identity "$path") || return 1
	[[ $(jq -Sc . <<<"$actual") == "$(jq -Sc . <<<"$expected")" ]]
}

wallpaper_identity_matches_exchange() {
	local path=$1 expected=$2 actual
	actual=$(wallpaper_file_identity "$path") || return 1
	[[ $(jq -Sc 'del(.ctime_ns)' <<<"$actual") == "$(jq -Sc 'del(.ctime_ns)' <<<"$expected")" ]]
}

wallpaper_live_identity_json_is_valid() {
	local identity=$1 expected_digest=${2-}
	jq -e --arg digest "$expected_digest" '
		type == "object" and
		keys == ["ctime_ns","device","digest","gid","inode","mode","mtime_ns","nlink","size","uid"] and
		all(.ctime_ns,.device,.gid,.inode,.mtime_ns,.size,.uid; type == "string" and test("^[0-9]+$")) and
		(.digest | type == "string" and test("^[0-9a-f]{64}$")) and
		(.mode | type == "string" and test("^0[0-7]{3}$")) and
		(.nlink | type == "number" and . >= 1) and
		($digest == "" or .digest == $digest)
	' <<<"$identity" >/dev/null 2>&1
}

wallpaper_live_identity_matches() {
	local path=$1 expected=$2 actual
	actual=$(wallpaper_live_file_identity "$path") || return 1
	[[ $(jq -Sc . <<<"$actual") == "$(jq -Sc . <<<"$expected")" ]]
}

wallpaper_live_identity_matches_exchange() {
	local path=$1 expected=$2 actual
	actual=$(wallpaper_live_file_identity "$path") || return 1
	[[ $(jq -Sc 'del(.ctime_ns)' <<<"$actual") == "$(jq -Sc 'del(.ctime_ns)' <<<"$expected")" ]]
}

wallpaper_lstat_identity_json_is_valid() {
	local identity=$1 expected_type=${2-}
	jq -e --arg type "$expected_type" '
		type == "object" and
		keys == ["ctime_ns","device","gid","inode","mode","mtime_ns","nlink","size","target","type","uid"] and
		all(.ctime_ns,.device,.gid,.inode,.mtime_ns,.size,.uid; type == "string" and test("^[0-9]+$")) and
		(.mode | type == "string" and test("^0[0-7]{3}$")) and (.nlink | type == "number" and . >= 1) and
		(.type == "directory" or .type == "regular" or .type == "symlink" or .type == "other") and
		((.type == "symlink" and (.target | type == "string")) or (.type != "symlink" and .target == null)) and
		($type == "" or .type == $type)
	' <<<"$identity" >/dev/null 2>&1
}

wallpaper_object_identity_matches() {
	local path=$1 expected=$2 actual
	actual=$(wallpaper_files lstat "$path") || return 1
	[[ $(jq -Sc '{device,gid,inode,mode,type,uid}' <<<"$actual") == \
		"$(jq -Sc '{device,gid,inode,mode,type,uid}' <<<"$expected")" ]]
}

wallpaper_pending_has_parent() {
	local pending=$1 path=$2
	jq -e --arg path "$path" '[.parents[] | select(.path == $path)] | length == 1' <<<"$pending" >/dev/null
}

wallpaper_after_pending_planned() { :; }
wallpaper_after_pending_staged() { :; }
wallpaper_after_lock_acquired() { :; }
wallpaper_preparation_checkpoint() { :; }
wallpaper_cleanup_checkpoint() { :; }

wallpaper_path_is_pending_curation_resource() {
	local path=$1
	[[ -n ${WALLPAPER_PENDING_JSON-} ]] || return 1
	[[ $(jq -r '.domain // empty' <<<"$WALLPAPER_PENDING_JSON" 2>/dev/null) == curation ]] || return 1
	jq -e --arg path "$path" 'any(
		.changes[];
		.desired.stage_path == $path or .quarantine_path == $path
	)' <<<"$WALLPAPER_PENDING_JSON" >/dev/null
}

wallpaper_regular_file_is_exact() {
	local path=$1 digest=$2 mode=${3-} identity
	identity=$(wallpaper_file_identity "$path") || return 1
	wallpaper_identity_json_is_valid "$identity" "$mode" "$digest"
}

wallpaper_regular_live_file_is_exact() {
	local path=$1 digest=$2 identity
	identity=$(wallpaper_live_file_identity "$path") || return 1
	wallpaper_live_identity_json_is_valid "$identity" "$digest"
}

wallpaper_path_is_absent() {
	wallpaper_files absent "$1" >/dev/null 2>&1
}

wallpaper_timestamp_is_strict() {
	local value=$1 normalized
	[[ $value =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$ ]] || return 1
	normalized=$(date -u -d "$value" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || return 1
	[[ $normalized == "$value" ]]
}

wallpaper_read_file_stable() {
	wallpaper_files read "$@"
}

wallpaper_cleanup_image_snapshot() {
	local directory=$1 snapshot=$2 identity=$3 diagnostics=$4
	[[ ! -e $diagnostics && ! -L $diagnostics ]] || rm -f -- "$diagnostics"
	wallpaper_path_is_absent "$snapshot" || wallpaper_files remove "$snapshot" "$identity" >/dev/null || return 1
	rmdir -- "$directory"
}

wallpaper_validate_image_quiet() {
	local path=$1 diagnostics identify_output line format width height snapshot_directory snapshot snapshot_result snapshot_identity
	local first_format='' first_width='' first_height='' frames=0 identity_before identity_after digest_before digest_after
	WALLPAPER_IMAGE_FORMAT='' WALLPAPER_IMAGE_EXTENSION='' WALLPAPER_IMAGE_DIGEST=''
	WALLPAPER_IMAGE_WIDTH='' WALLPAPER_IMAGE_HEIGHT='' WALLPAPER_IMAGE_FRAMES=''
	WALLPAPER_IMAGE_SIZE='' WALLPAPER_IMAGE_IDENTITY='' WALLPAPER_IMAGE_ERROR=''

	if ! command -v magick >/dev/null 2>&1; then
		WALLPAPER_IMAGE_ERROR='ImageMagick command is unavailable: magick'
		return 1
	fi
	if [[ ! -f $path || -L $path || ! -r $path ]]; then
		WALLPAPER_IMAGE_ERROR='image must be a readable regular non-symlink file'
		return 1
	fi
	if ! identity_before=$(wallpaper_file_identity "$path" 2>&1); then
		WALLPAPER_IMAGE_ERROR=${identity_before#Error: }
		return 1
	fi
	digest_before=$(jq -er '.digest' <<<"$identity_before") || return 1
	snapshot_directory=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-wallpaper-image.XXXXXX") || {
		WALLPAPER_IMAGE_ERROR='could not create isolated ImageMagick snapshot directory'
		return 1
	}
	chmod 0700 -- "$snapshot_directory" || { rmdir -- "$snapshot_directory"; return 1; }
	snapshot="$snapshot_directory/image"
	if ! snapshot_result=$(wallpaper_files copy "$path" "$snapshot" 0600 "$identity_before"); then
		WALLPAPER_IMAGE_ERROR='image changed while creating the stable no-follow decode snapshot'
		rmdir -- "$snapshot_directory" 2>/dev/null || true
		return 1
	fi
	snapshot_identity=$(jq -c '.destination' <<<"$snapshot_result") || return 1
	diagnostics="$snapshot_directory/diagnostics"
	: >"$diagnostics" || { wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true; return 1; }
	if ! identify_output=$(magick identify -format '%m|%w|%h\n' "$snapshot" 2>"$diagnostics"); then
		WALLPAPER_IMAGE_ERROR="ImageMagick could not identify every image frame$(if [[ -s $diagnostics ]]; then printf ': %s' "$(<"$diagnostics")"; fi)"
		wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true
		return 1
	fi
	if [[ -s $diagnostics ]]; then
		WALLPAPER_IMAGE_ERROR="ImageMagick emitted diagnostics while identifying image data: $(<"$diagnostics")"
		wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true
		return 1
	fi
	while IFS= read -r line; do
		[[ -n $line ]] || continue
		IFS='|' read -r format width height <<<"$line"
		if [[ -z $format || ! $width =~ ^[0-9]+$ || ! $height =~ ^[0-9]+$ || $width == 0 || $height == 0 ]]; then
			WALLPAPER_IMAGE_ERROR='ImageMagick returned invalid or zero image dimensions'
			wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true
			return 1
		fi
		if [[ -z $first_format ]]; then
			first_format=$format first_width=$width first_height=$height
		elif [[ $format != "$first_format" ]]; then
			WALLPAPER_IMAGE_ERROR='ImageMagick reported inconsistent frame formats'
			wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true
			return 1
		fi
		frames=$((frames + 1))
	done <<<"$identify_output"
	if ((frames == 0)); then
		WALLPAPER_IMAGE_ERROR='ImageMagick returned no decodable image frames'
		wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true
		return 1
	fi
	if ! WALLPAPER_IMAGE_EXTENSION=$(wallpaper_image_format_extension "$first_format"); then
		WALLPAPER_IMAGE_ERROR="unsupported image format: $first_format"
		wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true
		return 1
	fi
	: >"$diagnostics"
	if ! magick "$snapshot" -coalesce null: >/dev/null 2>"$diagnostics"; then
		WALLPAPER_IMAGE_ERROR="ImageMagick could not completely decode all image data$(if [[ -s $diagnostics ]]; then printf ': %s' "$(<"$diagnostics")"; fi)"
		wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true
		return 1
	fi
	if [[ -s $diagnostics ]]; then
		WALLPAPER_IMAGE_ERROR="ImageMagick emitted diagnostics during complete decode: $(<"$diagnostics")"
		wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || true
		return 1
	fi
	wallpaper_cleanup_image_snapshot "$snapshot_directory" "$snapshot" "$snapshot_identity" "$diagnostics" || {
		WALLPAPER_IMAGE_ERROR='could not clean the stable ImageMagick snapshot'
		return 1
	}
	if ! identity_after=$(wallpaper_file_identity "$path" 2>&1); then
		WALLPAPER_IMAGE_ERROR=${identity_after#Error: }
		return 1
	fi
	digest_after=$(jq -er '.digest' <<<"$identity_after") || return 1
	if [[ $identity_after != "$identity_before" || $digest_after != "$digest_before" ]]; then
		WALLPAPER_IMAGE_ERROR='image changed during validation'
		return 1
	fi
	WALLPAPER_IMAGE_FORMAT=$first_format
	WALLPAPER_IMAGE_DIGEST=$digest_before
	WALLPAPER_IMAGE_WIDTH=$first_width
	WALLPAPER_IMAGE_HEIGHT=$first_height
	WALLPAPER_IMAGE_FRAMES=$frames
	WALLPAPER_IMAGE_SIZE=$(jq -er '.size' <<<"$identity_after") || return 1
	WALLPAPER_IMAGE_IDENTITY=$identity_before
}

validate_wallpaper_image() {
	if (($# != 1)); then
		printf 'Error: validate_wallpaper_image requires exactly one image path.\n' >&2
		return 2
	fi
	if ! wallpaper_validate_image_quiet "$1"; then
		printf 'Error: invalid wallpaper image %s: %s\n' "$1" "$WALLPAPER_IMAGE_ERROR" >&2
		return 1
	fi
	printf 'Wallpaper image: valid\n'
	printf 'Path: %s\n' "$1"
	printf 'Format: %s\n' "$WALLPAPER_IMAGE_FORMAT"
	printf 'Canonical extension: %s\n' "$WALLPAPER_IMAGE_EXTENSION"
	printf 'Dimensions: %sx%s\n' "$WALLPAPER_IMAGE_WIDTH" "$WALLPAPER_IMAGE_HEIGHT"
	printf 'Frames: %s\n' "$WALLPAPER_IMAGE_FRAMES"
	printf 'Size: %s bytes\n' "$WALLPAPER_IMAGE_SIZE"
	printf 'SHA-256: %s\n' "$WALLPAPER_IMAGE_DIGEST"
}

wallpaper_slug_is_safe() {
	local LC_ALL=C
	[[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

wallpaper_repository_directory_path_is_safe() {
	local path=$1 current canonical
	[[ $path == "$REPOSITORY_ROOT/"* ]] || return 1
	canonical=$(readlink -m -- "$path") || return 1
	[[ $canonical == "$path" ]] || return 1
	current=$path
	while [[ ! -e $current && ! -L $current ]]; do
		[[ $current != "$REPOSITORY_ROOT" ]] || break
		current=${current%/*}
	done
	[[ -d $current && ! -L $current && $(readlink -f -- "$current" 2>/dev/null) == "$current" ]]
}

wallpaper_library_entries() {
	[[ -d $WALLPAPER_LIBRARY_ROOT && ! -L $WALLPAPER_LIBRARY_ROOT ]] || return 0
	find "$WALLPAPER_LIBRARY_ROOT" -mindepth 1 -maxdepth 1 -print0 | sort -z
}

wallpaper_validate_library_quiet() {
	local theme_path theme file_path file_name named_digest named_extension existing
	local assignments=0 managed=0 error='' canonical
	declare -A digest_path=()
	WALLPAPER_LIBRARY_ERROR=''
	WALLPAPER_LIBRARY_ASSIGNMENTS=0
	WALLPAPER_LIBRARY_MANAGED=0
	if ! wallpaper_repository_directory_path_is_safe "$WALLPAPER_LIBRARY_ROOT"; then
		WALLPAPER_LIBRARY_ERROR="library path must remain in real repository directories: $WALLPAPER_LIBRARY_ROOT"
		return 1
	fi
	if [[ -e $WALLPAPER_LIBRARY_ROOT || -L $WALLPAPER_LIBRARY_ROOT ]]; then
		if [[ ! -d $WALLPAPER_LIBRARY_ROOT || -L $WALLPAPER_LIBRARY_ROOT || \
			$(readlink -f -- "$WALLPAPER_LIBRARY_ROOT" 2>/dev/null) != "$WALLPAPER_LIBRARY_ROOT" ]]; then
			WALLPAPER_LIBRARY_ERROR="library root must be a real directory: $WALLPAPER_LIBRARY_ROOT"
			return 1
		fi
	else
		return 0
	fi
	while IFS= read -r -d '' theme_path; do
		theme=${theme_path##*/}
		if ! wallpaper_slug_is_safe "$theme"; then
			error="unsafe theme slug: $theme"
			break
		fi
		if [[ ! -d $theme_path || -L $theme_path ]]; then
			error="theme groups must be real direct-child directories: $theme_path"
			break
		fi
		while IFS= read -r -d '' file_path; do
			if wallpaper_path_is_pending_curation_resource "$file_path"; then continue; fi
			file_name=${file_path##*/}
			if [[ ! -f $file_path || -L $file_path ]]; then
				error="library assignments must be direct regular non-symlink files: $file_path"
				break 2
			fi
			if [[ ! $file_name =~ ^([0-9a-f]{64})[.]([a-z0-9]+)$ ]]; then
				error="invalid library filename; expected <sha256>.<canonical-extension>: $file_path"
				break 2
			fi
			named_digest=${BASH_REMATCH[1]} named_extension=${BASH_REMATCH[2]}
			if ! wallpaper_validate_image_quiet "$file_path"; then
				error="invalid library image $file_path: $WALLPAPER_IMAGE_ERROR"
				break 2
			fi
			if [[ $named_extension != "$WALLPAPER_IMAGE_EXTENSION" ]]; then
				error="library filename does not use canonical extension $WALLPAPER_IMAGE_EXTENSION: $file_path"
				break 2
			fi
			if [[ $named_digest != "$WALLPAPER_IMAGE_DIGEST" ]]; then
				error="library filename digest does not match exact bytes: $file_path"
				break 2
			fi
			if [[ -n ${digest_path[$named_digest]+present} ]]; then
				existing=${digest_path[$named_digest]}
				if ! wallpaper_files_are_same "$existing" "$file_path"; then
					error="fatal SHA-256 collision; equal digests have different bytes: $existing and $file_path"
					break 2
				fi
			else
				digest_path[$named_digest]=$file_path
				managed=$((managed + 1))
			fi
			assignments=$((assignments + 1))
		done < <(find "$theme_path" -mindepth 1 -maxdepth 1 -print0 | sort -z)
	done < <(wallpaper_library_entries)
	if [[ -n $error ]]; then
		WALLPAPER_LIBRARY_ERROR=$error
		return 1
	fi
	WALLPAPER_LIBRARY_ASSIGNMENTS=$assignments
	WALLPAPER_LIBRARY_MANAGED=$managed
}

validate_wallpaper_library() {
	if (($# != 0)); then
		printf 'Error: validate_wallpaper_library accepts no arguments.\n' >&2
		return 2
	fi
	if ! wallpaper_validate_library_quiet; then
		printf 'Error: invalid Wallpaper library: %s\n' "$WALLPAPER_LIBRARY_ERROR" >&2
		return 1
	fi
	printf 'Wallpaper library: valid\n'
	printf 'Managed wallpapers: %s\n' "$WALLPAPER_LIBRARY_MANAGED"
	printf 'Theme assignments: %s\n' "$WALLPAPER_LIBRARY_ASSIGNMENTS"
}

WALLPAPER_STATE_ROOT=''
WALLPAPER_STATE_CANONICAL_ROOT=''
WALLPAPER_ACTIVE_RECEIPT=''
WALLPAPER_PENDING_RECEIPT=''
WALLPAPER_RECOVERY_RECEIPT=''
WALLPAPER_ACTIVE_JSON=''
WALLPAPER_PENDING_JSON=''
WALLPAPER_RECOVERY_JSON=''
WALLPAPER_ACTIVE_IDENTITY=''
WALLPAPER_PENDING_IDENTITY=''
WALLPAPER_RECOVERY_IDENTITY=''
WALLPAPER_PUBLISHED_STATE_IDENTITY=''
WALLPAPER_LIVE_ROOT=''
WALLPAPER_LOCK_FD=''
WALLPAPER_LOCKED_STATE_ROOT_IDENTITY=''
WALLPAPER_OMARCHY_VERSION=''
WALLPAPER_OMARCHY_MAJOR=''
WALLPAPER_OMARCHY_MISMATCH=false
WALLPAPER_APPROVED_OMARCHY_VERSION=''
WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_ORDINARY
WALLPAPER_STATE_ERROR=''
declare -a WALLPAPER_THEME_SLUGS=()
declare -a WALLPAPER_THEME_LABELS=()
declare -a WALLPAPER_TRANSACTION_PATHS=()
declare -a WALLPAPER_TRANSACTION_DESIRED_PRESENT=()
declare -a WALLPAPER_TRANSACTION_DESIRED_DIGEST=()

wallpaper_initialize_paths() {
	local state_home=${XDG_STATE_HOME:-"$HOME/.local/state"} canonical
	local config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
	if [[ $state_home != /* || $config_home != /* ]]; then
		printf 'Error: wallpaper XDG state and config homes must be absolute paths.\n' >&2
		return 1
	fi
	WALLPAPER_STATE_ROOT="$state_home/dotfiles/wallpapers"
	canonical=$(readlink -m -- "$WALLPAPER_STATE_ROOT") || return 1
	if [[ $canonical != "$WALLPAPER_STATE_ROOT" ]]; then
		printf 'Error: wallpaper state path must not traverse symbolic links: %s\n' "$WALLPAPER_STATE_ROOT" >&2
		return 1
	fi
	WALLPAPER_STATE_CANONICAL_ROOT=$canonical
	WALLPAPER_ACTIVE_RECEIPT="$WALLPAPER_STATE_CANONICAL_ROOT/active.json"
	WALLPAPER_PENDING_RECEIPT="$WALLPAPER_STATE_CANONICAL_ROOT/pending.json"
	WALLPAPER_RECOVERY_RECEIPT="$WALLPAPER_STATE_CANONICAL_ROOT/recovery-required.json"
	WALLPAPER_LIVE_ROOT="$config_home/omarchy/backgrounds"
	canonical=$(readlink -m -- "$WALLPAPER_LIVE_ROOT") || return 1
	if [[ $canonical != "$WALLPAPER_LIVE_ROOT" ]]; then
		printf 'Error: live wallpaper path must not traverse symbolic links: %s\n' "$WALLPAPER_LIVE_ROOT" >&2
		return 1
	fi
}

wallpaper_packaged_themes_root() {
	printf '%s\n' "${DOTFILES_WALLPAPER_PACKAGED_THEMES_ROOT:-/usr/share/omarchy/themes}"
}

wallpaper_user_themes_root() {
	printf '%s\n' "${XDG_CONFIG_HOME:-"$HOME/.config"}/omarchy/themes"
}

wallpaper_active_background_link() {
	printf '%s\n' "$HOME/.local/state/omarchy/current/background"
}

wallpaper_effective_uid() {
	printf '%s\n' "$EUID"
}

wallpaper_omarchy_version() {
	omarchy version
}

wallpaper_confirm() {
	wizard_confirm "$1"
}

wallpaper_now() {
	date -u +%Y-%m-%dT%H:%M:%SZ
}

wallpaper_new_transaction_id() {
	local stamp
	stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
	printf '%s-%d-%04x%04x\n' "$stamp" "$$" "$RANDOM" "$RANDOM"
}

wallpaper_transaction_id_is_safe() {
	[[ $1 =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9a-f]{8}$ ]]
}

wallpaper_inspect_omarchy() {
	WALLPAPER_OMARCHY_VERSION=$(wallpaper_omarchy_version) || {
		printf 'Error: could not inspect the Omarchy version for wallpaper mutation.\n' >&2
		return 1
	}
	WALLPAPER_OMARCHY_MAJOR=''
	WALLPAPER_OMARCHY_MISMATCH=false
	if [[ $WALLPAPER_OMARCHY_VERSION =~ (^|[^[:digit:]])([[:digit:]]+)([.]|$) ]]; then
		WALLPAPER_OMARCHY_MAJOR=${BASH_REMATCH[2]}
	fi
	[[ $WALLPAPER_OMARCHY_MAJOR == "$WALLPAPER_SUPPORTED_OMARCHY_MAJOR" ]] || WALLPAPER_OMARCHY_MISMATCH=true
	printf 'Supported Omarchy: %s\nDetected Omarchy: %s\n' "$WALLPAPER_SUPPORTED_OMARCHY_MAJOR" "$WALLPAPER_OMARCHY_VERSION"
}

wallpaper_require_compatible_mutation() {
	local unattended=$1 override=$2
	wallpaper_inspect_omarchy || return 1
	if [[ $WALLPAPER_OMARCHY_MISMATCH == true ]]; then
		printf 'Warning: detected Omarchy does not match supported version %s.\n' "$WALLPAPER_SUPPORTED_OMARCHY_MAJOR"
		if [[ $unattended == true && $override != true ]]; then
			printf 'Error: unattended wallpaper mutation requires --allow-omarchy-mismatch for this version.\n' >&2
			return 1
		fi
		[[ $override != true ]] || printf 'Explicit Omarchy mismatch override supplied.\n'
	fi
	WALLPAPER_APPROVED_OMARCHY_VERSION=$WALLPAPER_OMARCHY_VERSION
}

wallpaper_recheck_approved_omarchy() {
	local approved=$WALLPAPER_APPROVED_OMARCHY_VERSION
	[[ -n $approved ]] || return 1
	wallpaper_inspect_omarchy >/dev/null || return 1
	if [[ $WALLPAPER_OMARCHY_VERSION != "$approved" ]]; then
		printf 'Error: Omarchy version changed after wallpaper mutation approval (approved: %s, current: %s).\n' \
			"$approved" "$WALLPAPER_OMARCHY_VERSION" >&2
		return 1
	fi
}

wallpaper_theme_display_name() {
	local slug=$1 word display='' LC_ALL=C
	slug=${slug//-/ } slug=${slug//_/ }
	for word in $slug; do
		[[ -z $display ]] || display+=' '
		display+="${word^}"
	done
	printf '%s\n' "$display"
}

wallpaper_discover_themes() {
	local packaged user root origin entry slug target display
	local -a sorted=()
	declare -A origins=()
	WALLPAPER_THEME_SLUGS=()
	WALLPAPER_THEME_LABELS=()
	packaged=$(wallpaper_packaged_themes_root) || return 1
	user=$(wallpaper_user_themes_root) || return 1
	for root in "$packaged" "$user"; do
		[[ $root == /* ]] || {
			printf 'Error: theme discovery root must be absolute: %s\n' "$root" >&2
			return 1
		}
		[[ -e $root || -L $root ]] || continue
		if [[ ! -d $root || -L $root ]]; then
			printf 'Error: theme discovery root must be a real directory: %s\n' "$root" >&2
			return 1
		fi
		[[ $root == "$packaged" ]] && origin=stock || origin=user
		while IFS= read -r -d '' entry; do
			slug=${entry##*/}
			if ! wallpaper_slug_is_safe "$slug"; then
				printf 'Error: installed theme has an unsafe direct-child entry: %s\n' "$entry" >&2
				return 1
			fi
			if [[ $origin == stock ]]; then
				if [[ ! -d $entry || -L $entry ]]; then
					printf 'Error: packaged theme must be a direct real directory: %s\n' "$entry" >&2
					return 1
				fi
			elif [[ -L $entry ]]; then
				target=$(readlink -f -- "$entry" 2>/dev/null) || target=''
				if [[ -z $target || ! -d $target ]]; then
					printf 'Error: unsafe user theme symlink must resolve to a directory: %s\n' "$entry" >&2
					return 1
				fi
			elif [[ ! -d $entry ]]; then
				printf 'Error: user theme must be a direct directory or safe directory symlink: %s\n' "$entry" >&2
				return 1
			fi
			if [[ -n ${origins[$slug]+present} && ${origins[$slug]} != "$origin" ]]; then
				origins[$slug]='stock + user overlay'
			else
				origins[$slug]=$origin
			fi
		done < <(find "$root" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 | sort -z)
	done
	if ((${#origins[@]} > 0)); then
		mapfile -t sorted < <(printf '%s\n' "${!origins[@]}" | LC_ALL=C sort)
	fi
	for slug in "${sorted[@]}"; do
		display=$(wallpaper_theme_display_name "$slug") || return 1
		WALLPAPER_THEME_SLUGS+=("$slug")
		WALLPAPER_THEME_LABELS+=("$display [$slug] (${origins[$slug]})")
	done
}

wallpaper_theme_fingerprint() {
	local index slug label root entry fingerprint=''
	wallpaper_discover_themes || return 1
	for index in "${!WALLPAPER_THEME_SLUGS[@]}"; do
		slug=${WALLPAPER_THEME_SLUGS[$index]} label=${WALLPAPER_THEME_LABELS[$index]}
		fingerprint+="$slug|$label;"
		for root in "$(wallpaper_packaged_themes_root)" "$(wallpaper_user_themes_root)"; do
			entry="$root/$slug"
			[[ -d $entry || -L $entry ]] || continue
			fingerprint+="$entry|$(wallpaper_files lstat "$entry");"
			if [[ -L $entry ]]; then
				fingerprint+="target|$(readlink -f -- "$entry")|$(wallpaper_files lstat "$(readlink -f -- "$entry")");"
			fi
		done
	done
	printf '%s\n' "$fingerprint"
}

wallpaper_theme_is_installed() {
	local wanted=$1 slug
	wallpaper_slug_is_safe "$wanted" || return 1
	for slug in "${WALLPAPER_THEME_SLUGS[@]}"; do [[ $slug != "$wanted" ]] || return 0; done
	return 1
}

wallpaper_intake_path_is_safe() {
	local path=$1 parent name
	[[ $path == /* ]] || path="$WALLPAPER_INBOX_ROOT/$path"
	parent=${path%/*} name=${path##*/}
	wallpaper_repository_directory_path_is_safe "$WALLPAPER_INBOX_ROOT" && \
		[[ $parent == "$WALLPAPER_INBOX_ROOT" && -n $name && $name != . && $name != .. && -f $path && ! -L $path && \
			$(readlink -f -- "$path" 2>/dev/null) == "$path" ]]
}

wallpaper_library_snapshot() {
	local entry snapshot='' metadata
	wallpaper_validate_library_quiet || return 1
	if [[ ! -e $WALLPAPER_LIBRARY_ROOT && ! -L $WALLPAPER_LIBRARY_ROOT ]]; then
		printf 'absent\n'
		return 0
	fi
	while IFS= read -r -d '' entry; do
		metadata=$(wallpaper_files lstat "$entry") || return 1
		snapshot+="${entry#"$WALLPAPER_LIBRARY_ROOT"}|$metadata"
		[[ $(jq -r '.type' <<<"$metadata") != regular ]] || snapshot+="|$(wallpaper_file_identity "$entry")"
		snapshot+=';'
	done < <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 1 -print0 | sort -z)
	printf '%s\n' "$snapshot"
}

wallpaper_intake_snapshot() {
	local entry snapshot='' metadata
	wallpaper_repository_directory_path_is_safe "$WALLPAPER_INBOX_ROOT" || return 1
	if [[ ! -e $WALLPAPER_INBOX_ROOT && ! -L $WALLPAPER_INBOX_ROOT ]]; then
		printf 'absent\n'
		return 0
	fi
	if [[ ! -d $WALLPAPER_INBOX_ROOT || -L $WALLPAPER_INBOX_ROOT ]]; then return 1; fi
	while IFS= read -r -d '' entry; do
		metadata=$(wallpaper_files lstat "$entry") || return 1
		snapshot+="${entry#"$WALLPAPER_INBOX_ROOT"}|$metadata"
		[[ $(jq -r '.type' <<<"$metadata") != regular ]] || snapshot+="|$(wallpaper_file_identity "$entry")"
		snapshot+=';'
	done < <(find "$WALLPAPER_INBOX_ROOT" -mindepth 1 -maxdepth 1 -print0 | sort -z)
	printf '%s\n' "$snapshot"
}

inspect_wallpapers() {
	if (($# != 0)); then
		printf 'Error: inspect_wallpapers accepts no arguments.\n' >&2
		return 2
	fi
	local library_before intake_before entry name valid_count=0 invalid_count=0 index duplicate assignment theme digest
	declare -A inspected=()
	library_before=$(wallpaper_library_snapshot) || {
		printf 'Error: invalid Wallpaper library: %s\n' "$WALLPAPER_LIBRARY_ERROR" >&2
		return 1
	}
	intake_before=$(wallpaper_intake_snapshot) || {
		printf 'Error: Wallpaper inbox must be a real directory when present.\n' >&2
		return 1
	}
	wallpaper_discover_themes || return 1
	wallpaper_validate_library_quiet || return 1
	printf 'Installed wallpaper themes:\n'
	if ((${#WALLPAPER_THEME_LABELS[@]} == 0)); then
		printf '  none\n'
	else
		for index in "${!WALLPAPER_THEME_LABELS[@]}"; do printf '  %s\n' "${WALLPAPER_THEME_LABELS[$index]}"; done
	fi
	printf 'Wallpaper inbox:\n'
	if [[ -d $WALLPAPER_INBOX_ROOT && ! -L $WALLPAPER_INBOX_ROOT ]]; then
		while IFS= read -r -d '' entry; do
			name=${entry##*/}
			if [[ -f $entry && ! -L $entry ]] && wallpaper_validate_image_quiet "$entry"; then
				duplicate=false
				while IFS= read -r -d '' assignment; do duplicate=true; done \
					< <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f \
						-name "$WALLPAPER_IMAGE_DIGEST.$WALLPAPER_IMAGE_EXTENSION" -print0 2>/dev/null | sort -z)
				printf '  %s: valid format=%s size=%s dimensions=%sx%s frames=%s digest=%s duplicate=%s path=%s\n' \
					"$name" "$WALLPAPER_IMAGE_FORMAT" "$WALLPAPER_IMAGE_SIZE" "$WALLPAPER_IMAGE_WIDTH" \
					"$WALLPAPER_IMAGE_HEIGHT" "$WALLPAPER_IMAGE_FRAMES" "$WALLPAPER_IMAGE_DIGEST" \
					"$duplicate" "$entry"
				if [[ $duplicate == true ]]; then
					while IFS= read -r -d '' assignment; do
						theme=${assignment#"$WALLPAPER_LIBRARY_ROOT"/} theme=${theme%%/*}
						printf '    Existing Theme assignment: %s (%s)\n' "$theme" "$assignment"
					done < <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f \
						-name "$WALLPAPER_IMAGE_DIGEST.$WALLPAPER_IMAGE_EXTENSION" -print0 2>/dev/null | sort -z)
				fi
				valid_count=$((valid_count + 1))
			else
				if [[ ! -f $entry || -L $entry ]]; then
					printf '  %s: invalid (not a direct regular non-symlink file) path=%s\n' "$name" "$entry"
				else
					printf '  %s: invalid (%s) path=%s\n' "$name" "$WALLPAPER_IMAGE_ERROR" "$entry"
				fi
				invalid_count=$((invalid_count + 1))
			fi
		done < <(find "$WALLPAPER_INBOX_ROOT" -mindepth 1 -maxdepth 1 -print0 | sort -z)
	fi
	if ((valid_count == 0 && invalid_count == 0)); then printf '  empty\n'; fi
	printf 'Wallpaper library: valid\nManaged wallpapers: %s\nTheme assignments: %s\n' \
		"$WALLPAPER_LIBRARY_MANAGED" "$WALLPAPER_LIBRARY_ASSIGNMENTS"
	printf 'Managed wallpaper details:\n'
	if ((WALLPAPER_LIBRARY_MANAGED == 0)); then
		printf '  none\n'
	elif [[ -d $WALLPAPER_LIBRARY_ROOT && ! -L $WALLPAPER_LIBRARY_ROOT ]]; then
		while IFS= read -r -d '' assignment; do
			name=${assignment##*/} digest=${name%%.*}
			[[ -z ${inspected[$digest]+present} ]] || continue
			inspected[$digest]=1
			wallpaper_validate_image_quiet "$assignment" || {
				printf 'Error: managed wallpaper changed during inspection: %s\n' "$assignment" >&2
				return 1
			}
			printf '  SHA-256: %s\n  Format: %s\n  Size: %s bytes\n  Dimensions: %sx%s\n  Frames: %s\n' \
				"$digest" "$WALLPAPER_IMAGE_FORMAT" "$WALLPAPER_IMAGE_SIZE" "$WALLPAPER_IMAGE_WIDTH" \
				"$WALLPAPER_IMAGE_HEIGHT" "$WALLPAPER_IMAGE_FRAMES"
			while IFS= read -r -d '' entry; do
				theme=${entry#"$WALLPAPER_LIBRARY_ROOT"/} theme=${theme%%/*}
				printf '    Theme assignment: %s\n    Repository path: %s\n' "$theme" "$entry"
			done < <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f -name "$name" -print0 | sort -z)
		done < <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f -print0 | sort -z)
	fi
	if [[ $(wallpaper_library_snapshot) != "$library_before" || $(wallpaper_intake_snapshot) != "$intake_before" ]]; then
		printf 'Error: wallpaper state changed during read-only inspection; rerun Inspect.\n' >&2
		return 1
	fi
}

wallpaper_prepare_state_root() {
	local parent metadata uid mode canonical
	wallpaper_initialize_paths || return 1
	umask 077
	parent=${WALLPAPER_STATE_ROOT%/*}
	if [[ -e $parent || -L $parent ]]; then
		[[ -d $parent && ! -L $parent ]] || {
			printf 'Error: wallpaper state parent must be a real directory: %s\n' "$parent" >&2
			return 1
		}
	else
		mkdir -p -- "$parent" || return 1
	fi
	if [[ ! -e $WALLPAPER_STATE_ROOT && ! -L $WALLPAPER_STATE_ROOT ]]; then
		mkdir -m 0700 -- "$WALLPAPER_STATE_ROOT" || return 1
	fi
	metadata=$(stat -c '%F|%u|%a' -- "$WALLPAPER_STATE_ROOT" 2>/dev/null) || return 1
	IFS='|' read -r _ uid mode <<<"$metadata"
	canonical=$(readlink -f -- "$WALLPAPER_STATE_ROOT" 2>/dev/null) || return 1
	if [[ ! -d $WALLPAPER_STATE_ROOT || -L $WALLPAPER_STATE_ROOT || $uid != "$(wallpaper_effective_uid)" || \
		$mode != 700 || $canonical != "$WALLPAPER_STATE_CANONICAL_ROOT" ]]; then
		printf 'Error: wallpaper state root must be a real invoking-user-owned 0700 directory: %s\n' "$WALLPAPER_STATE_ROOT" >&2
		return 1
	fi
}

wallpaper_acquire_lock() {
	local identity fd_device fd_inode
	WALLPAPER_LOCK_FD=''
	WALLPAPER_LOCKED_STATE_ROOT_IDENTITY=''
	exec {WALLPAPER_LOCK_FD}<"$WALLPAPER_STATE_ROOT" || return 1
	flock --exclusive "$WALLPAPER_LOCK_FD" || {
		exec {WALLPAPER_LOCK_FD}>&-
		WALLPAPER_LOCK_FD=''
		return 1
	}
	identity=$(wallpaper_files lstat "$WALLPAPER_STATE_ROOT") || { wallpaper_release_lock; return 1; }
	wallpaper_lstat_identity_json_is_valid "$identity" directory || { wallpaper_release_lock; return 1; }
	IFS='|' read -r fd_device fd_inode < <(stat -Lc '%d|%i' -- "/proc/self/fd/$WALLPAPER_LOCK_FD") || { wallpaper_release_lock; return 1; }
	[[ $fd_device == "$(jq -r '.device' <<<"$identity")" && $fd_inode == "$(jq -r '.inode' <<<"$identity")" ]] || {
		wallpaper_release_lock
		return 1
	}
	WALLPAPER_LOCKED_STATE_ROOT_IDENTITY=$identity
	wallpaper_assert_locked_state_root || { wallpaper_release_lock; return 1; }
	wallpaper_after_lock_acquired || { wallpaper_release_lock; return 1; }
	wallpaper_assert_locked_state_root || { wallpaper_release_lock; return 1; }
}

wallpaper_release_lock() {
	if [[ -n $WALLPAPER_LOCK_FD ]]; then
		flock --unlock "$WALLPAPER_LOCK_FD" || true
		exec {WALLPAPER_LOCK_FD}>&-
		WALLPAPER_LOCK_FD=''
	fi
	WALLPAPER_LOCKED_STATE_ROOT_IDENTITY=''
}

wallpaper_assert_locked_state_root() {
	local current fd_device fd_inode
	[[ -n $WALLPAPER_LOCK_FD && -n $WALLPAPER_LOCKED_STATE_ROOT_IDENTITY ]] || return 1
	IFS='|' read -r fd_device fd_inode < <(stat -Lc '%d|%i' -- "/proc/self/fd/$WALLPAPER_LOCK_FD") || return 1
	[[ $fd_device == "$(jq -r '.device' <<<"$WALLPAPER_LOCKED_STATE_ROOT_IDENTITY")" && \
		$fd_inode == "$(jq -r '.inode' <<<"$WALLPAPER_LOCKED_STATE_ROOT_IDENTITY")" ]] || return 1
	current=$(wallpaper_files lstat "$WALLPAPER_STATE_ROOT") || {
		printf 'Error: locked wallpaper state root pathname changed after lock acquisition: %s\n' "$WALLPAPER_STATE_ROOT" >&2
		return 1
	}
	if [[ $(jq -Sc '{device,gid,inode,mode,type,uid}' <<<"$current") != \
		$(jq -Sc '{device,gid,inode,mode,type,uid}' <<<"$WALLPAPER_LOCKED_STATE_ROOT_IDENTITY") ]]; then
		printf 'Error: locked wallpaper state root pathname changed after lock acquisition: %s\n' "$WALLPAPER_STATE_ROOT" >&2
		return 1
	fi
}

wallpaper_assert_locked_state_root_if_locked() {
	[[ -z $WALLPAPER_LOCK_FD ]] || wallpaper_assert_locked_state_root
}

wallpaper_state_file_is_secure() {
	local file=$1 identity
	identity=$(wallpaper_file_identity "$file") || return 1
	wallpaper_identity_json_is_valid "$identity" 0600 && [[ $(jq -r '.uid' <<<"$identity") == "$(wallpaper_effective_uid)" ]]
}

wallpaper_private_directory_is_secure() {
	local directory=$1 identity
	identity=$(wallpaper_files lstat "$directory") || return 1
	jq -e --arg uid "$(wallpaper_effective_uid)" '
		.type == "directory" and .mode == "0700" and .uid == $uid
	' <<<"$identity" >/dev/null
}

wallpaper_backup_path_is_safe() {
	local path=$1 transaction=$2 backup_root transaction_root
	backup_root="$WALLPAPER_STATE_CANONICAL_ROOT/backups"
	transaction_root="$backup_root/$transaction"
	wallpaper_backup_path_is_well_formed "$path" "$transaction" || return 1
	wallpaper_private_directory_is_secure "$backup_root" && \
		wallpaper_private_directory_is_secure "$transaction_root" && \
		[[ $(readlink -f -- "$path" 2>/dev/null) == "$path" ]]
}

wallpaper_backup_path_is_well_formed() {
	local path=$1 transaction=$2
	[[ $path == "$WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction/"* ]] &&
		[[ ${path##*/} == active.json || ${path##*/} =~ ^[0-9]+[.]bin$ ]]
}

wallpaper_prepare_backup_root() {
	local transaction=$1 backup_root transaction_root
	wallpaper_assert_locked_state_root || return 1
	backup_root="$WALLPAPER_STATE_CANONICAL_ROOT/backups"
	transaction_root="$backup_root/$transaction"
	if [[ ! -e $backup_root && ! -L $backup_root ]]; then mkdir -m 0700 -- "$backup_root" || return 1; fi
	wallpaper_private_directory_is_secure "$backup_root" || return 1
	[[ ! -e $transaction_root && ! -L $transaction_root ]] || return 1
	mkdir -m 0700 -- "$transaction_root" || return 1
	wallpaper_private_directory_is_secure "$transaction_root"
}

wallpaper_validate_backup_inventory() {
	local pending=$1 backup_root transaction transaction_root entry phase
	local -A expected=()
	backup_root="$WALLPAPER_STATE_CANONICAL_ROOT/backups"
	[[ -e $backup_root || -L $backup_root ]] || return 0
	wallpaper_private_directory_is_secure "$backup_root" || return 1
	[[ -n $pending ]] || return 1
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	phase=$(jq -r '.phase' <<<"$pending")
	transaction_root="$backup_root/$transaction"
	if [[ ! -e $transaction_root && ! -L $transaction_root ]]; then
		[[ $phase != prepared ]] || return 1
		while IFS= read -r -d '' entry; do return 1; done < <(find "$backup_root" -mindepth 1 -maxdepth 1 -print0)
		return 0
	fi
	wallpaper_private_directory_is_secure "$transaction_root" || return 1
	while IFS= read -r entry; do [[ -z $entry ]] || expected[$entry]=1; done \
		< <(jq -r '(.changes[] | select(.prior.present).prior.backup_path), (.prior_active? | select(.present).backup_path) | select(. != null)' <<<"$pending")
	while IFS= read -r -d '' entry; do [[ $entry == "$transaction_root" ]] || return 1; done \
		< <(find "$backup_root" -mindepth 1 -maxdepth 1 -print0 | sort -z)
	while IFS= read -r -d '' entry; do [[ -n ${expected[$entry]+present} ]] || return 1; done \
		< <(find "$transaction_root" -mindepth 1 -maxdepth 1 -print0 | sort -z)
	if [[ $phase == prepared ]]; then
		for entry in "${!expected[@]}"; do [[ -f $entry && ! -L $entry ]] || return 1; done
	fi
}

wallpaper_cleanup_transaction_backups() {
	local pending=$1 backup_root transaction transaction_root entry identity
	wallpaper_assert_locked_state_root || return 1
	backup_root="$WALLPAPER_STATE_CANONICAL_ROOT/backups"
	[[ -e $backup_root || -L $backup_root ]] || return 0
	wallpaper_validate_backup_inventory "$pending" || return 1
	transaction=$(jq -r '.transaction_id' <<<"$pending")
	transaction_root="$backup_root/$transaction"
	if [[ ! -e $transaction_root && ! -L $transaction_root ]]; then
		wallpaper_remove_pending_directory "$backup_root" "$pending"
		return
	fi
	while IFS= read -r -d '' entry; do
		identity=$(jq -c --arg path "$entry" '
			. as $pending |
			first((
				($pending.changes[].prior | select(.present and .backup_path == $path) | .backup_identity),
				($pending.prior_active? | select(.present and .backup_path == $path) | .backup_identity)
			))
		' <<<"$pending") || return 1
		[[ $identity != null ]] || return 1
		wallpaper_assert_locked_state_root || return 1
		wallpaper_files remove "$entry" "$identity" >/dev/null || return 1
		wallpaper_path_is_absent "$entry" || return 1
		wallpaper_cleanup_checkpoint backup-entry
	done < <(find "$transaction_root" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)
	wallpaper_remove_pending_directory "$transaction_root" "$pending" || return 1
	wallpaper_remove_pending_directory "$backup_root" "$pending" || return 1
	[[ ! -e $transaction_root && ! -L $transaction_root ]]
}

wallpaper_curation_path_is_safe() {
	local path=$1 relative theme name
	case $path in
		"$WALLPAPER_INBOX_ROOT"/*)
			relative=${path#"$WALLPAPER_INBOX_ROOT"/}
			[[ -n $relative && $relative != */* && $relative != . && $relative != .. ]]
			;;
		"$WALLPAPER_LIBRARY_ROOT"/*/*)
			relative=${path#"$WALLPAPER_LIBRARY_ROOT"/}
			theme=${relative%%/*} name=${relative#*/}
			wallpaper_slug_is_safe "$theme" && [[ $name =~ ^[0-9a-f]{64}[.](jpg|png|gif|bmp|webp)$ ]]
			;;
		*) return 1 ;;
	esac
}

wallpaper_validate_curation_pending() {
	local json=$1 transaction path prior_present backup digest mode identity backup_identity desired_present desired_digest directory relative stage stage_identity parent phase
	local source_identity quarantine expected index=0 created
	wallpaper_repository_directory_path_is_safe "$WALLPAPER_INBOX_ROOT" || return 1
	wallpaper_repository_directory_path_is_safe "$WALLPAPER_LIBRARY_ROOT" || return 1
	if ! jq -e --argjson schema "$WALLPAPER_SCHEMA_VERSION" '
		type == "object" and keys == ["changes","created_at","created_directories","domain","kind","operation","parents","phase","repository_root","schema_version","transaction_id"] and
		.schema_version == $schema and .kind == "pending" and .domain == "curation" and
		(.operation == "add" or .operation == "move" or .operation == "remove") and
		(.phase == "preparing" or .phase == "prepared" or .phase == "complete" or .phase == "rolled_back") and
		(.transaction_id | type == "string") and (.created_at | type == "string" and length > 0) and
		(.repository_root | type == "string") and (.changes | type == "array" and length > 0) and
		(.created_directories | type == "array" and . == sort and length == (unique | length)) and
		(.parents | type == "array" and length > 0 and all(.[]; type == "object" and keys == ["created","identity","path"] and (.path | type == "string") and (.created | type == "boolean"))) and
		all(.changes[]; type == "object" and keys == ["desired","path","prior","quarantine_path"] and
			(.path | type == "string") and
			(.prior | type == "object" and keys == ["backup_identity","backup_path","digest","identity","mode","present"]) and
			(.desired | type == "object" and keys == ["digest","identity","present","source_identity","stage_identity","stage_path"]) and
			(.quarantine_path | type == "string") and
			(.prior.present | type == "boolean") and (.desired.present | type == "boolean"))' <<<"$json" >/dev/null; then
		return 1
	fi
	transaction=$(jq -r '.transaction_id' <<<"$json")
	phase=$(jq -r '.phase' <<<"$json")
	wallpaper_transaction_id_is_safe "$transaction" || return 1
	wallpaper_timestamp_is_strict "$(jq -r '.created_at' <<<"$json")" || return 1
	[[ $(jq -r '.repository_root' <<<"$json") == "$REPOSITORY_ROOT" ]] || return 1
	while IFS= read -r path; do
		wallpaper_curation_path_is_safe "$path" || return 1
		prior_present=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.present' <<<"$json")
		desired_present=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .desired.present' <<<"$json")
		if [[ $prior_present == true ]]; then
			backup=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.backup_path' <<<"$json")
			digest=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.digest' <<<"$json")
			mode=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.mode' <<<"$json")
			identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .prior.identity' <<<"$json")
			backup_identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .prior.backup_identity' <<<"$json")
			wallpaper_backup_path_is_well_formed "$backup" "$transaction" || return 1
			[[ $digest =~ ^[0-9a-f]{64}$ && $mode =~ ^[0-7]{3,4}$ ]] || return 1
			wallpaper_identity_json_is_valid "$identity" "0${mode#0}" "$digest" || return 1
			if [[ $backup_identity != null ]]; then wallpaper_identity_json_is_valid "$backup_identity" 0600 "$digest" || return 1; fi
			if [[ -e $backup || -L $backup ]]; then
				wallpaper_backup_path_is_safe "$backup" "$transaction" && wallpaper_state_file_is_secure "$backup" || return 1
				if [[ $backup_identity == null ]]; then wallpaper_regular_file_is_exact "$backup" "$digest" 0600; else wallpaper_identity_matches "$backup" "$backup_identity"; fi || return 1
			else
				[[ $phase != prepared ]] || return 1
			fi
			[[ $phase != prepared || $backup_identity != null ]] || return 1
		else
			[[ $(jq -r --arg path "$path" '.changes[] | select(.path == $path) | (.prior.digest == null and .prior.mode == null and .prior.backup_path == null and .prior.identity == null and .prior.backup_identity == null)' <<<"$json") == true ]] || return 1
		fi
		if [[ $desired_present == true ]]; then
			desired_digest=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .desired.digest' <<<"$json")
			[[ $desired_digest =~ ^[0-9a-f]{64}$ ]] || return 1
			identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .desired.identity' <<<"$json")
			[[ $identity == null ]] || return 1
			source_identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .desired.source_identity' <<<"$json")
			wallpaper_identity_json_is_valid "$source_identity" '' "$desired_digest" || return 1
			stage=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .desired.stage_path' <<<"$json")
			stage_identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .desired.stage_identity' <<<"$json")
			[[ $stage == "${path%/*}/.dotfiles-wallpaper-$transaction-$index.stage" ]] || return 1
			if [[ $stage_identity != null ]]; then wallpaper_identity_json_is_valid "$stage_identity" 0644 "$desired_digest" || return 1; fi
			if [[ -e $stage || -L $stage ]]; then
				if [[ $stage_identity == null ]]; then wallpaper_regular_file_is_exact "$stage" "$desired_digest" 0644; else wallpaper_identity_matches "$stage" "$stage_identity"; fi || return 1
			fi
			[[ $phase != prepared || $stage_identity != null ]] || return 1
		else
			[[ $(jq -r --arg path "$path" '.changes[] | select(.path == $path) | (.desired.digest == null and .desired.identity == null and .desired.source_identity == null and .desired.stage_path == null and .desired.stage_identity == null)' <<<"$json") == true ]] || return 1
		fi
		quarantine=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .quarantine_path' <<<"$json")
		[[ $quarantine == "${path%/*}/.dotfiles-wallpaper-$transaction-$index.quarantine" ]] || return 1
		if [[ $phase == preparing ]]; then
			wallpaper_path_is_absent "$quarantine" || return 1
		elif [[ -e $quarantine || -L $quarantine ]]; then
			if [[ $prior_present == true ]]; then expected=$identity; expected=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .prior.identity' <<<"$json"); else expected=$stage_identity; fi
			wallpaper_identity_matches_exchange "$quarantine" "$expected" || return 1
		fi
		index=$((index + 1))
	done < <(jq -r '.changes[].path' <<<"$json")
	[[ $(jq -r '[.changes[].path] | length == (unique | length)' <<<"$json") == true ]] || return 1
	while IFS= read -r directory; do
		[[ $directory == "$WALLPAPER_LIBRARY_ROOT" ]] || {
			relative=${directory#"$WALLPAPER_LIBRARY_ROOT"/}
			[[ $directory == "$WALLPAPER_LIBRARY_ROOT/"* && $relative != */* ]] && wallpaper_slug_is_safe "$relative"
		} || return 1
	done < <(jq -r '.created_directories[]' <<<"$json")
	while IFS= read -r parent; do
		case $parent in
			"$WALLPAPER_INBOX_ROOT"|"$WALLPAPER_LIBRARY_ROOT"|"$WALLPAPER_LIBRARY_ROOT"/*|"$WALLPAPER_STATE_CANONICAL_ROOT"|"$WALLPAPER_STATE_CANONICAL_ROOT/backups"|"$WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction") ;;
			*) return 1 ;;
		esac
		identity=$(jq -c --arg path "$parent" '.parents[] | select(.path == $path) | .identity' <<<"$json")
		created=$(jq -r --arg path "$parent" '.parents[] | select(.path == $path) | .created' <<<"$json")
		if [[ $identity == null ]]; then
			[[ $phase == preparing && $created == true ]] || return 1
			if [[ -e $parent || -L $parent ]]; then
				[[ -d $parent && ! -L $parent && $(readlink -f -- "$parent") == "$parent" ]] || return 1
				case $parent in "$WALLPAPER_STATE_CANONICAL_ROOT"/*) wallpaper_private_directory_is_secure "$parent" || return 1 ;; esac
			fi
		else
			wallpaper_lstat_identity_json_is_valid "$identity" directory || return 1
			if [[ -e $parent || -L $parent ]]; then wallpaper_object_identity_matches "$parent" "$identity" || return 1; elif [[ $created != true || $phase == prepared ]]; then return 1; fi
		fi
	done < <(jq -r '.parents[].path' <<<"$json")
	[[ $(jq -r '[.parents[].path] | length == (unique | length)' <<<"$json") == true ]] || return 1
	for parent in "$WALLPAPER_STATE_CANONICAL_ROOT" "$WALLPAPER_STATE_CANONICAL_ROOT/backups" "$WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction"; do
		wallpaper_pending_has_parent "$json" "$parent" || return 1
	done
	while IFS= read -r path; do wallpaper_pending_has_parent "$json" "${path%/*}" || return 1; done < <(jq -r '.changes[].path' <<<"$json")
	while IFS= read -r directory; do wallpaper_pending_has_parent "$json" "$directory" || return 1; done < <(jq -r '.created_directories[]' <<<"$json")
	[[ $(jq -r '[.changes[].desired.stage_path,.changes[].quarantine_path | select(. != null)] | length == (unique | length)' <<<"$json") == true ]]
}

wallpaper_validate_recovery_json() {
	local json=$1 pending=$2 transaction pending_digest
	jq -e --argjson schema "$WALLPAPER_SCHEMA_VERSION" '
		type == "object" and keys == ["created_at","failed_step","kind","pending_digest","schema_version","transaction_id"] and
		.schema_version == $schema and .kind == "recovery-required" and
		all(.transaction_id,.created_at,.failed_step,.pending_digest; type == "string" and length > 0)' <<<"$json" >/dev/null || return 1
	transaction=$(jq -r '.transaction_id' <<<"$json")
	pending_digest=$(jq -r '.pending_digest' <<<"$json")
	wallpaper_timestamp_is_strict "$(jq -r '.created_at' <<<"$json")" || return 1
	[[ $transaction == "$(jq -r '.transaction_id' <<<"$pending")" && $pending_digest == "$(printf '%s\n' "$pending" | sha256sum | { read -r value _; printf '%s' "$value"; })" ]]
}

wallpaper_inspect_state() {
	local file json identity
	WALLPAPER_ACTIVE_JSON='' WALLPAPER_PENDING_JSON='' WALLPAPER_RECOVERY_JSON='' WALLPAPER_STATE_ERROR=''
	WALLPAPER_ACTIVE_IDENTITY='' WALLPAPER_PENDING_IDENTITY='' WALLPAPER_RECOVERY_IDENTITY=''
	wallpaper_initialize_paths || return 1
	if ! wallpaper_assert_locked_state_root_if_locked; then
		WALLPAPER_STATE_ERROR='locked wallpaper state root pathname changed after lock acquisition'
		return 1
	fi
	if [[ ! -e $WALLPAPER_STATE_ROOT && ! -L $WALLPAPER_STATE_ROOT ]]; then return 0; fi
	if ! wallpaper_prepare_state_root; then
		WALLPAPER_STATE_ERROR='unsafe wallpaper state root'
		return 1
	fi
	for file in "$WALLPAPER_ACTIVE_RECEIPT" "$WALLPAPER_PENDING_RECEIPT" "$WALLPAPER_RECOVERY_RECEIPT"; do
		[[ -e $file || -L $file ]] || continue
		if ! wallpaper_state_file_is_secure "$file"; then
			WALLPAPER_STATE_ERROR="state evidence must be a regular invoking-user-owned 0600 file: $file"
			return 1
		fi
		identity=$(wallpaper_file_identity "$file") || return 1
		json=$(wallpaper_read_file_stable "$file" "$identity") || {
			WALLPAPER_STATE_ERROR="state evidence changed during no-follow read: $file"
			return 1
		}
		if ! wallpaper_identity_matches "$file" "$identity"; then
			WALLPAPER_STATE_ERROR="state evidence identity changed during validation: $file"
			return 1
		fi
		case $file in
			"$WALLPAPER_ACTIVE_RECEIPT")
				if ! wallpaper_validate_active_json "$json"; then
					WALLPAPER_STATE_ERROR='invalid active receipt'
					return 1
				fi
				WALLPAPER_ACTIVE_JSON=$json
				WALLPAPER_ACTIVE_IDENTITY=$identity
				;;
			"$WALLPAPER_PENDING_RECEIPT")
				if [[ $(jq -r '.domain // empty' <<<"$json" 2>/dev/null) == curation ]]; then
					wallpaper_validate_curation_pending "$json" || {
						WALLPAPER_STATE_ERROR='invalid curation pending receipt'
						return 1
					}
				elif [[ $(jq -r '.domain // empty' <<<"$json" 2>/dev/null) == deployment ]]; then
					wallpaper_validate_deployment_pending "$json" || {
						WALLPAPER_STATE_ERROR='invalid deployment pending receipt'
						return 1
					}
				else
					WALLPAPER_STATE_ERROR='invalid or unsupported wallpaper pending receipt'
					return 1
				fi
				WALLPAPER_PENDING_JSON=$json
				WALLPAPER_PENDING_IDENTITY=$identity
				;;
			"$WALLPAPER_RECOVERY_RECEIPT") WALLPAPER_RECOVERY_JSON=$json WALLPAPER_RECOVERY_IDENTITY=$identity ;;
		esac
	done
	if [[ -n $WALLPAPER_RECOVERY_JSON ]]; then
		if [[ -z $WALLPAPER_PENDING_JSON ]] || ! wallpaper_validate_recovery_json "$WALLPAPER_RECOVERY_JSON" "$WALLPAPER_PENDING_JSON"; then
			WALLPAPER_STATE_ERROR='invalid recovery-required receipt or missing matching pending evidence'
			return 1
		fi
	fi
	if ! wallpaper_validate_backup_inventory "$WALLPAPER_PENDING_JSON"; then
		WALLPAPER_STATE_ERROR='unexpected, insecure, or orphaned wallpaper transaction backups'
		return 1
	fi
}

wallpaper_state_file_path() {
	case $1 in
		active) printf '%s\n' "$WALLPAPER_ACTIVE_RECEIPT" ;;
		pending) printf '%s\n' "$WALLPAPER_PENDING_RECEIPT" ;;
		recovery-required) printf '%s\n' "$WALLPAPER_RECOVERY_RECEIPT" ;;
		*) return 2 ;;
	esac
}

wallpaper_verify_state_file() {
	local kind=$1 json=$2 destination content
	destination=$(wallpaper_state_file_path "$kind") || return 2
	wallpaper_state_file_is_secure "$destination" || return 1
	if [[ -n $WALLPAPER_PUBLISHED_STATE_IDENTITY ]]; then
		content=$(wallpaper_read_file_stable "$destination" "$WALLPAPER_PUBLISHED_STATE_IDENTITY") || return 1
	else
		content=$(wallpaper_read_file_stable "$destination") || return 1
	fi
	[[ $content == "$json" ]] || return 1
	case $kind in
		active) wallpaper_validate_active_json "$content" ;;
		pending)
			case $(jq -r '.domain // empty' <<<"$content" 2>/dev/null) in
				curation) wallpaper_validate_curation_pending "$content" ;;
				deployment) wallpaper_validate_deployment_pending "$content" ;;
				*) return 1 ;;
			esac
		;;
		recovery-required) [[ -n $WALLPAPER_PENDING_JSON ]] && wallpaper_validate_recovery_json "$content" "$WALLPAPER_PENDING_JSON" ;;
	esac
}

wallpaper_stage_copy() {
	local source=$1 parent=$2 prefix=$3 mode=$4 expected_source=${5-} attempt result
	WALLPAPER_STAGE_PATH=''
	WALLPAPER_STAGE_IDENTITY=''
	wallpaper_assert_locked_state_root_if_locked || return 1
	for ((attempt = 0; attempt < 10; attempt++)); do
		printf -v WALLPAPER_STAGE_PATH '%s/.%s.%d.%04x%04x' "$parent" "$prefix" "$$" "$RANDOM" "$RANDOM"
		wallpaper_path_is_absent "$WALLPAPER_STAGE_PATH" || continue
		if [[ -n $expected_source ]]; then
			result=$(wallpaper_files copy "$source" "$WALLPAPER_STAGE_PATH" "$mode" "$expected_source") || return 1
		else
			result=$(wallpaper_files copy "$source" "$WALLPAPER_STAGE_PATH" "$mode") || return 1
		fi
		WALLPAPER_STAGE_IDENTITY=$(jq -c '.destination' <<<"$result") || return 1
		return 0
	done
	return 1
}

wallpaper_cleanup_staged_file() {
	local path=$1 identity=$2
	wallpaper_assert_locked_state_root_if_locked || return 1
	wallpaper_path_is_absent "$path" && return 0
	wallpaper_identity_json_is_valid "$identity" || return 1
	wallpaper_files remove-core "$path" "$identity" >/dev/null
}

wallpaper_cleanup_quarantine_file() {
	local path=$1 expected=$2 actual
	wallpaper_assert_locked_state_root || return 1
	wallpaper_path_is_absent "$path" && return 0
	actual=$(wallpaper_live_file_identity "$path") || return 1
	[[ $(jq -Sc 'del(.ctime_ns)' <<<"$actual") == "$(jq -Sc 'del(.ctime_ns)' <<<"$expected")" ]] || return 1
	wallpaper_files remove "$path" "$actual" >/dev/null || return 1
	wallpaper_path_is_absent "$path"
}

wallpaper_remove_to_quarantine() {
	local path=$1 expected=$2 quarantine=$3 relaxed=${4-false}
	wallpaper_assert_locked_state_root || return 1
	wallpaper_path_is_absent "$quarantine" || return 1
	wallpaper_files remove-to "$path" "$expected" "$quarantine" >/dev/null || return 1
	wallpaper_path_is_absent "$path" || return 1
	if [[ $relaxed == true ]]; then
		wallpaper_live_identity_matches_exchange "$quarantine" "$expected"
	else
		wallpaper_identity_matches_exchange "$quarantine" "$expected"
	fi
}

wallpaper_restore_from_quarantine_impl() {
	local quarantine=$1 expected=$2 destination=$3 relaxed=${4-false} actual
	wallpaper_assert_locked_state_root || return 1
	wallpaper_path_is_absent "$destination" || return 1
	if [[ $relaxed == true ]]; then
		actual=$(wallpaper_live_file_identity "$quarantine") || return 1
		[[ $(jq -Sc 'del(.ctime_ns)' <<<"$actual") == "$(jq -Sc 'del(.ctime_ns)' <<<"$expected")" ]] || return 1
	else
		actual=$(wallpaper_file_identity "$quarantine") || return 1
		[[ $(jq -Sc 'del(.ctime_ns)' <<<"$actual") == "$(jq -Sc 'del(.ctime_ns)' <<<"$expected")" ]] || return 1
	fi
	wallpaper_files remove-to "$quarantine" "$actual" "$destination" >/dev/null || return 1
	wallpaper_path_is_absent "$quarantine" || return 1
	if [[ $relaxed == true ]]; then
		wallpaper_live_identity_matches_exchange "$destination" "$actual"
	else
		wallpaper_identity_matches_exchange "$destination" "$actual"
	fi
}

wallpaper_restore_from_quarantine() {
	wallpaper_restore_from_quarantine_impl "$@"
}

wallpaper_parent_evidence() {
	local parent identity item result='[]'
	declare -A seen=()
	for parent in "$@"; do
		[[ -z ${seen[$parent]+present} ]] || continue
		identity=$(wallpaper_files lstat "$parent") || return 1
		wallpaper_lstat_identity_json_is_valid "$identity" directory || return 1
		item=$(jq -cn --arg path "$parent" --argjson identity "$identity" '{path:$path,identity:$identity,created:false}') || return 1
		result=$(jq -c --argjson item "$item" '. + [$item]' <<<"$result") || return 1
		seen[$parent]=1
	done
	jq -c 'sort_by(.path)' <<<"$result"
}

wallpaper_parent_intent_evidence() {
	local parent identity item result='[]' created
	declare -A seen=()
	for parent in "$@"; do
		[[ -z ${seen[$parent]+present} ]] || continue
		[[ $(readlink -m -- "$parent") == "$parent" ]] || return 1
		if wallpaper_path_is_absent "$parent"; then
			identity=null created=true
		else
			identity=$(wallpaper_files lstat "$parent") || return 1
			wallpaper_lstat_identity_json_is_valid "$identity" directory || return 1
			created=false
		fi
		item=$(jq -cn --arg path "$parent" --argjson identity "$identity" --argjson created "$created" \
			'{path:$path,identity:$identity,created:$created}') || return 1
		result=$(jq -c --argjson item "$item" '. + [$item]' <<<"$result") || return 1
		seen[$parent]=1
	done
	jq -c 'sort_by(.path)' <<<"$result"
}

wallpaper_verify_pending_parent() {
	local parent=$1 pending=${2-$WALLPAPER_PENDING_JSON} identity
	identity=$(jq -c --arg path "$parent" 'first(.parents[] | select(.path == $path) | .identity) // null' <<<"$pending") || return 1
	[[ $identity != null ]] && wallpaper_object_identity_matches "$parent" "$identity"
}

wallpaper_update_pending_parent_identity() {
	local parent=$1 identity updated
	identity=$(wallpaper_files lstat "$parent") || return 1
	wallpaper_lstat_identity_json_is_valid "$identity" directory || return 1
	updated=$(jq -c --arg path "$parent" --argjson identity "$identity" '
		.parents = [.parents[] | if .path == $path then .identity = $identity else . end]
	' <<<"$WALLPAPER_PENDING_JSON") || return 1
	wallpaper_update_pending_evidence "$updated"
}

wallpaper_prepare_pending_directory() {
	local directory=$1 mode=${2-0700} expected created
	wallpaper_assert_locked_state_root || return 1
	expected=$(jq -c --arg path "$directory" 'first(.parents[] | select(.path == $path)) // null' <<<"$WALLPAPER_PENDING_JSON") || return 1
	[[ $expected != null ]] || return 1
	created=$(jq -r '.created' <<<"$expected")
	if wallpaper_path_is_absent "$directory"; then
		[[ $created == true ]] || return 1
		mkdir -m "$mode" -- "$directory" || return 1
		wallpaper_preparation_checkpoint directory-created || return 1
	fi
	[[ -d $directory && ! -L $directory && $(readlink -f -- "$directory") == "$directory" ]] || return 1
	wallpaper_update_pending_parent_identity "$directory"
}

wallpaper_remove_pending_directory() {
	local directory=$1 pending=${2-$WALLPAPER_PENDING_JSON} identity entry
	wallpaper_assert_locked_state_root || return 1
	wallpaper_path_is_absent "$directory" && return 0
	identity=$(jq -c --arg path "$directory" 'first(.parents[] | select(.path == $path) | .identity) // null' <<<"$pending") || return 1
	[[ $identity != null ]] && wallpaper_object_identity_matches "$directory" "$identity" || return 1
	if wallpaper_files remove-dir "$directory" "$identity" >/dev/null 2>&1; then return 0; fi
	wallpaper_object_identity_matches "$directory" "$identity" || return 1
	entry=$(find "$directory" -mindepth 1 -maxdepth 1 -print -quit) || return 1
	[[ -n $entry ]]
}

wallpaper_cleanup_pending_publication_stages() {
	local pending=$1 stage identity
	wallpaper_assert_locked_state_root || return 1
	while IFS=$'\t' read -r stage identity; do
		[[ -n $stage ]] || continue
		wallpaper_path_is_absent "$stage" && continue
		[[ $identity != null ]] || return 1
		wallpaper_cleanup_staged_file "$stage" "$identity" || return 1
	done < <(jq -r '(
		(.changes[] | select(.desired.stage_path != null) | [.desired.stage_path,(.desired.stage_identity | tojson)]),
		(.active_stage? | select(. != null) | [.path,(.identity | tojson)])
	) | @tsv' <<<"$pending")
}

wallpaper_cleanup_pending_quarantines() {
	local pending=$1 quarantine expected
	wallpaper_assert_locked_state_root || return 1
	while IFS=$'\t' read -r quarantine expected; do
		[[ -n $quarantine ]] || continue
		wallpaper_cleanup_quarantine_file "$quarantine" "$expected" || return 1
	done < <(jq -r '(
		(.changes[] | select(.quarantine_path != null) |
			[.quarantine_path, ((if .prior.present then .prior.identity else .desired.stage_identity end) | tojson)]),
		(.prior_active? | select(.quarantine_path != null and .present) | [.quarantine_path,(.identity | tojson)]),
		(.active_stage? | select(.rollback_quarantine_path != null) | [.rollback_quarantine_path,(.identity | tojson)])
		) | @tsv
	' <<<"$pending")
}

wallpaper_write_state_file_impl() {
	local kind=$1 json=$2 expected_identity=${3-} prepared_stage=${4-} prepared_identity=${5-} destination temporary result temporary_identity attempt
	wallpaper_assert_locked_state_root || return 1
	case $kind in
		active) destination=$WALLPAPER_ACTIVE_RECEIPT ;;
		pending) destination=$WALLPAPER_PENDING_RECEIPT ;;
		recovery-required) destination=$WALLPAPER_RECOVERY_RECEIPT ;;
		*) return 2 ;;
	esac
	if [[ -n $prepared_stage || -n $prepared_identity ]]; then
		[[ $kind == active && -n $prepared_stage && -n $prepared_identity ]] || return 1
		wallpaper_verify_pending_parent "$WALLPAPER_STATE_CANONICAL_ROOT" || return 1
		wallpaper_identity_matches "$prepared_stage" "$prepared_identity" || return 1
		if [[ -n $expected_identity ]]; then
			WALLPAPER_PUBLISHED_STATE_IDENTITY=$(wallpaper_files publish-replace "$prepared_stage" "$destination" "$expected_identity") || return 1
		else
			WALLPAPER_PUBLISHED_STATE_IDENTITY=$(wallpaper_files publish-absent "$prepared_stage" "$destination") || return 1
		fi
		wallpaper_identity_matches_exchange "$destination" "$prepared_identity"
		return
	fi
	for ((attempt = 0; attempt < 10; attempt++)); do
		printf -v temporary '%s/.%s.%d.%04x%04x' "$WALLPAPER_STATE_CANONICAL_ROOT" "$kind" "$$" "$RANDOM" "$RANDOM"
		wallpaper_path_is_absent "$temporary" || continue
		result=$(wallpaper_files create "$temporary" 0600 "$json"$'\n') || return 1
		temporary_identity=$result
		break
	done
	[[ -n ${temporary_identity-} ]] || return 1
	wallpaper_state_file_is_secure "$temporary" || { wallpaper_cleanup_staged_file "$temporary" "$temporary_identity" || true; return 1; }
	if [[ -n $expected_identity ]]; then
		WALLPAPER_PUBLISHED_STATE_IDENTITY=$(wallpaper_files publish-replace "$temporary" "$destination" "$expected_identity") || { wallpaper_cleanup_staged_file "$temporary" "$temporary_identity" || true; return 1; }
	else
		WALLPAPER_PUBLISHED_STATE_IDENTITY=$(wallpaper_files publish-absent "$temporary" "$destination") || { wallpaper_cleanup_staged_file "$temporary" "$temporary_identity" || true; return 1; }
	fi
}

wallpaper_write_state_file() {
	wallpaper_write_state_file_impl "$@"
}

wallpaper_write_state_file_verified() {
	local kind=$1 json=$2 destination identity
	WALLPAPER_PUBLISHED_STATE_IDENTITY=''
	wallpaper_write_state_file "$@" || return 1
	wallpaper_verify_state_file "$kind" "$json" || return 1
	destination=$(wallpaper_state_file_path "$kind") || return 1
	identity=$WALLPAPER_PUBLISHED_STATE_IDENTITY
	wallpaper_identity_json_is_valid "$identity" 0600 || return 1
	wallpaper_identity_matches "$destination" "$identity" || return 1
	case $kind in
		active) WALLPAPER_ACTIVE_IDENTITY=$identity ;;
		pending) WALLPAPER_PENDING_IDENTITY=$identity ;;
		recovery-required) WALLPAPER_RECOVERY_IDENTITY=$identity ;;
	esac
}

wallpaper_remove_state_file_impl() {
	local path=$1 expected_identity=${2-}
	wallpaper_assert_locked_state_root || return 1
	wallpaper_path_is_absent "$path" && return 0
	if [[ -z $expected_identity ]]; then expected_identity=$(wallpaper_file_identity "$path") || return 1; fi
	wallpaper_files remove "$path" "$expected_identity" >/dev/null
}

wallpaper_remove_state_file() {
	wallpaper_remove_state_file_impl "$@"
}

wallpaper_remove_state_file_verified() {
	local path=$1
	wallpaper_remove_state_file "$@" || return 1
	wallpaper_path_is_absent "$path" || return 1
	case $path in
		"$WALLPAPER_ACTIVE_RECEIPT") WALLPAPER_ACTIVE_IDENTITY='' ;;
		"$WALLPAPER_PENDING_RECEIPT") WALLPAPER_PENDING_IDENTITY='' ;;
		"$WALLPAPER_RECOVERY_RECEIPT") WALLPAPER_RECOVERY_IDENTITY='' ;;
	esac
}

wallpaper_update_pending_evidence() {
	local updated=$1 domain expected_identity
	[[ -n $WALLPAPER_PENDING_JSON ]] || return 1
	domain=$(jq -r '.domain' <<<"$updated") || return 1
	case $domain in
		curation) wallpaper_validate_curation_pending "$updated" || return 1 ;;
		deployment) wallpaper_validate_deployment_pending "$updated" || return 1 ;;
		*) return 1 ;;
	esac
	expected_identity=$WALLPAPER_PENDING_IDENTITY
	[[ -n $expected_identity ]] || return 1
	wallpaper_write_state_file_verified pending "$updated" "$expected_identity" || return 1
	WALLPAPER_PENDING_JSON=$updated
}

wallpaper_copy_backup() {
	local source=$1 destination=$2 expected=$3 source_identity=$4 result
	wallpaper_assert_locked_state_root || return 1
	result=$(wallpaper_files copy "$source" "$destination" 0600 "$source_identity") || return 1
	wallpaper_state_file_is_secure "$destination" || return 1
	[[ $(wallpaper_file_digest "$destination") == "$expected" ]] && wallpaper_files_are_same "$source" "$destination"
}

wallpaper_publish_file_impl() {
	local source=$1 destination=$2 expected=$3 source_identity=$4 parent stage stage_identity actual published
	wallpaper_assert_locked_state_root || return 1
	[[ $(jq -r '.phase' <<<"$WALLPAPER_PENDING_JSON") == prepared ]] || return 1
	parent=${destination%/*}
	wallpaper_repository_directory_path_is_safe "$WALLPAPER_LIBRARY_ROOT" || return 1
	[[ -d $WALLPAPER_LIBRARY_ROOT && ! -L $WALLPAPER_LIBRARY_ROOT ]] || return 1
	[[ -d $parent && ! -L $parent && $(readlink -f -- "$parent") == "$parent" ]] || return 1
	wallpaper_verify_pending_parent "$parent" || return 1
	wallpaper_identity_matches "$source" "$source_identity" || return 1
	stage=$(jq -r --arg path "$destination" '.changes[] | select(.path == $path) | .desired.stage_path' <<<"$WALLPAPER_PENDING_JSON") || return 1
	stage_identity=$(jq -c --arg path "$destination" '.changes[] | select(.path == $path) | .desired.stage_identity' <<<"$WALLPAPER_PENDING_JSON") || return 1
	wallpaper_identity_matches "$stage" "$stage_identity" || return 1
	actual=$(wallpaper_file_digest "$stage") || return 1
	if [[ $actual != "$expected" ]] || ! wallpaper_files_are_same "$source" "$stage" || [[ -L $stage ]]; then
		return 1
	fi
	published=$(wallpaper_files publish-absent "$stage" "$destination") || return 1
	wallpaper_regular_file_is_exact "$destination" "$expected" 0644 || return 1
	wallpaper_identity_matches_exchange "$destination" "$stage_identity" && wallpaper_identity_matches "$destination" "$published"
}

wallpaper_publish_file() {
	wallpaper_publish_file_impl "$@"
}

wallpaper_delete_file_impl() {
	local path=$1 expected=$2 expected_identity=${3-} actual quarantine
	wallpaper_assert_locked_state_root || return 1
	[[ $(jq -r '.phase' <<<"$WALLPAPER_PENDING_JSON") == prepared ]] || return 1
	actual=$(wallpaper_file_identity "$path") || return 1
	wallpaper_identity_json_is_valid "$actual" '' "$expected" || return 1
	if [[ -n $expected_identity && $(jq -Sc . <<<"$actual") != "$(jq -Sc . <<<"$expected_identity")" ]]; then return 1; fi
	quarantine=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .quarantine_path' <<<"$WALLPAPER_PENDING_JSON") || return 1
	wallpaper_remove_to_quarantine "$path" "$actual" "$quarantine"
}

wallpaper_delete_file() {
	wallpaper_delete_file_impl "$@"
}

wallpaper_delete_file_verified() {
	local path=$1 domain
	if [[ -n ${WALLPAPER_PENDING_JSON-} ]]; then
		domain=$(jq -r '.domain // empty' <<<"$WALLPAPER_PENDING_JSON") || return 1
		if [[ $domain == curation ]]; then wallpaper_verify_pending_parent "${path%/*}" || return 1; fi
	fi
	wallpaper_delete_file "$@" || return 1
	wallpaper_path_is_absent "$path"
}

wallpaper_restore_file_impl() {
	local backup=$1 destination=$2 expected=$3 mode=$4 backup_identity=$5 parent stage current published
	wallpaper_assert_locked_state_root || return 1
	wallpaper_state_file_is_secure "$backup" || return 1
	[[ $(wallpaper_file_digest "$backup") == "$expected" ]] || return 1
	parent=${destination%/*}
	[[ $(readlink -m -- "$parent") == "$parent" ]] || return 1
	if [[ ! -e $parent && ! -L $parent ]]; then mkdir -p -- "$parent" || return 1; fi
	[[ -d $parent && ! -L $parent && $(readlink -f -- "$parent" 2>/dev/null) == "$parent" ]] || return 1
	printf -v mode '0%s' "${mode#0}"
	wallpaper_stage_copy "$backup" "$parent" dotfiles-wallpaper-restore "$mode" "$backup_identity" || return 1
	stage=$WALLPAPER_STAGE_PATH
	if wallpaper_path_is_absent "$destination"; then
		published=$(wallpaper_files publish-absent "$stage" "$destination") || { wallpaper_cleanup_staged_file "$stage" "$WALLPAPER_STAGE_IDENTITY" || true; return 1; }
	else
		current=$(wallpaper_file_identity "$destination") || { wallpaper_cleanup_staged_file "$stage" "$WALLPAPER_STAGE_IDENTITY" || true; return 1; }
		published=$(wallpaper_files publish-replace "$stage" "$destination" "$current") || { wallpaper_cleanup_staged_file "$stage" "$WALLPAPER_STAGE_IDENTITY" || true; return 1; }
	fi
	wallpaper_identity_matches "$destination" "$published" && wallpaper_identity_json_is_valid "$published" "$mode" "$expected"
}

wallpaper_restore_file() {
	wallpaper_restore_file_impl "$@"
}

wallpaper_record_created_directories() {
	local path parent json='[]'
	declare -A seen=()
	for path in "${WALLPAPER_TRANSACTION_PATHS[@]}"; do
		[[ $path == "$WALLPAPER_LIBRARY_ROOT/"* ]] || continue
		parent=${path%/*}
		if [[ ! -e $WALLPAPER_LIBRARY_ROOT && ! -L $WALLPAPER_LIBRARY_ROOT && -z ${seen[$WALLPAPER_LIBRARY_ROOT]+present} ]]; then
			json=$(jq -c --arg path "$WALLPAPER_LIBRARY_ROOT" '. + [$path]' <<<"$json") || return 1
			seen[$WALLPAPER_LIBRARY_ROOT]=1
		fi
		if [[ ! -e $parent && ! -L $parent && -z ${seen[$parent]+present} ]]; then
			json=$(jq -c --arg path "$parent" '. + [$path]' <<<"$json") || return 1
			seen[$parent]=1
		fi
	done
	printf '%s\n' "$json"
}

wallpaper_prepare_curation_directories() {
	local directories=$1 directory
	wallpaper_assert_locked_state_root || return 1
	while IFS= read -r directory; do
		if [[ ! -e $directory && ! -L $directory ]]; then mkdir -- "$directory" || return 1; fi
		[[ -d $directory && ! -L $directory && $(readlink -f -- "$directory") == "$directory" ]] || return 1
	done < <(jq -r '.[]' <<<"$directories")
}

wallpaper_begin_curation_transaction() {
	local operation=$1 transaction=$2 stage_source=${3-} backup_root index path prior desired change changes='[]' created created_at
	local digest mode identity backup backup_identity desired_present desired_digest pending source_identity stage stage_identity parents quarantine result directory updated
	local -a parent_paths=()
	wallpaper_assert_locked_state_root || return 1
	backup_root="$WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction"
	if [[ -n $stage_source ]]; then source_identity=$(wallpaper_file_identity "$stage_source") || return 1; else source_identity=null; fi
	for index in "${!WALLPAPER_TRANSACTION_PATHS[@]}"; do
		path=${WALLPAPER_TRANSACTION_PATHS[$index]}
		desired_present=${WALLPAPER_TRANSACTION_DESIRED_PRESENT[$index]}
		desired_digest=${WALLPAPER_TRANSACTION_DESIRED_DIGEST[$index]}
		wallpaper_curation_path_is_safe "$path" || return 1
		if [[ -e $path || -L $path ]]; then
			[[ -f $path && ! -L $path ]] || return 1
			identity=$(wallpaper_file_identity "$path") || return 1
			digest=$(jq -er '.digest' <<<"$identity") || return 1
			mode=$(jq -er '.mode' <<<"$identity") || return 1
			backup="$backup_root/$index.bin"
			prior=$(jq -cn --arg digest "$digest" --arg mode "$mode" --arg backup "$backup" --argjson identity "$identity" \
				'{present:true,digest:$digest,mode:$mode,identity:$identity,backup_path:$backup,backup_identity:null}') || return 1
		else
			prior='{"present":false,"digest":null,"mode":null,"identity":null,"backup_path":null,"backup_identity":null}'
		fi
		if [[ $desired_present == true ]]; then
			[[ $source_identity != null ]] || return 1
			stage="${path%/*}/.dotfiles-wallpaper-$transaction-$index.stage"
			desired=$(jq -cn --arg digest "$desired_digest" --arg stage "$stage" --argjson source_identity "$source_identity" \
				'{present:true,digest:$digest,source_identity:$source_identity,identity:null,stage_path:$stage,stage_identity:null}') || return 1
		else
			desired='{"present":false,"digest":null,"source_identity":null,"identity":null,"stage_path":null,"stage_identity":null}'
		fi
		quarantine="${path%/*}/.dotfiles-wallpaper-$transaction-$index.quarantine"
		change=$(jq -cn --arg path "$path" --arg quarantine "$quarantine" --argjson prior "$prior" --argjson desired "$desired" \
			'{path:$path,prior:$prior,desired:$desired,quarantine_path:$quarantine}') || return 1
		changes=$(jq -c --argjson change "$change" '. + [$change]' <<<"$changes") || return 1
	done
	created=$(wallpaper_record_created_directories) || return 1
	created=$(jq -c 'sort | unique' <<<"$created") || return 1
	for path in "${WALLPAPER_TRANSACTION_PATHS[@]}"; do parent_paths+=("${path%/*}"); done
	while IFS= read -r path; do parent_paths+=("$path"); done < <(jq -r '.[]' <<<"$created")
	parent_paths+=("$WALLPAPER_STATE_CANONICAL_ROOT" "$WALLPAPER_STATE_CANONICAL_ROOT/backups" "$backup_root")
	parents=$(wallpaper_parent_intent_evidence "${parent_paths[@]}") || return 1
	wallpaper_path_is_absent "$backup_root" || return 1
	while IFS= read -r path; do wallpaper_path_is_absent "$path" || return 1; done \
		< <(jq -r '(.changes[].prior.backup_path,.changes[].desired.stage_path,.changes[].quarantine_path) | select(. != null)' <<<"$changes")
	created_at=$(wallpaper_now) || return 1
	pending=$(jq -cn --argjson schema "$WALLPAPER_SCHEMA_VERSION" --arg operation "$operation" --arg transaction "$transaction" \
		--arg created_at "$created_at" --arg repository "$REPOSITORY_ROOT" --argjson changes "$changes" --argjson directories "$created" --argjson parents "$parents" \
		'{schema_version:$schema,kind:"pending",domain:"curation",operation:$operation,transaction_id:$transaction,created_at:$created_at,phase:"preparing",repository_root:$repository,changes:$changes,created_directories:$directories,parents:$parents}') || return 1
	wallpaper_validate_curation_pending "$pending" || return 1
	wallpaper_write_state_file_verified pending "$pending" || return 1
	WALLPAPER_PENDING_JSON=$pending
	wallpaper_after_pending_planned || { wallpaper_abort_preparing_transaction curation-after-pending || true; return 1; }
	while IFS= read -r directory; do
		wallpaper_prepare_pending_directory "$directory" 0700 || { wallpaper_abort_preparing_transaction curation-directory-preparation || true; return 1; }
	done < <(jq -r '.parents[] | select(.created) | .path' <<<"$WALLPAPER_PENDING_JSON")
	for index in "${!WALLPAPER_TRANSACTION_PATHS[@]}"; do
		path=${WALLPAPER_TRANSACTION_PATHS[$index]}
		if [[ $(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.present' <<<"$WALLPAPER_PENDING_JSON") == true ]]; then
			backup=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.backup_path' <<<"$WALLPAPER_PENDING_JSON")
			identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .prior.identity' <<<"$WALLPAPER_PENDING_JSON")
			digest=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.digest' <<<"$WALLPAPER_PENDING_JSON")
			wallpaper_copy_backup "$path" "$backup" "$digest" "$identity" || { wallpaper_abort_preparing_transaction curation-backup || true; return 1; }
			wallpaper_preparation_checkpoint backup-created || { wallpaper_abort_preparing_transaction curation-backup-checkpoint || true; return 1; }
			backup_identity=$(wallpaper_file_identity "$backup") || { wallpaper_abort_preparing_transaction curation-backup-identity || true; return 1; }
			updated=$(jq -c --arg path "$path" --argjson identity "$backup_identity" '
				.changes = [.changes[] | if .path == $path then .prior.backup_identity = $identity else . end]
			' <<<"$WALLPAPER_PENDING_JSON") || { wallpaper_abort_preparing_transaction curation-backup-evidence || true; return 1; }
			wallpaper_update_pending_evidence "$updated" || { wallpaper_abort_preparing_transaction curation-backup-evidence || true; return 1; }
		fi
		[[ ${WALLPAPER_TRANSACTION_DESIRED_PRESENT[$index]} == true ]] || continue
		wallpaper_assert_locked_state_root || { wallpaper_abort_preparing_transaction curation-stage-root-identity || true; return 1; }
		stage=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .desired.stage_path' <<<"$WALLPAPER_PENDING_JSON")
		source_identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .desired.source_identity' <<<"$WALLPAPER_PENDING_JSON")
		result=$(wallpaper_files copy "$stage_source" "$stage" 0644 "$source_identity") || { wallpaper_abort_preparing_transaction curation-stage || true; return 1; }
		wallpaper_preparation_checkpoint stage-created || { wallpaper_abort_preparing_transaction curation-stage-checkpoint || true; return 1; }
		stage_identity=$(jq -c '.destination' <<<"$result") || { wallpaper_abort_preparing_transaction curation-stage-identity || true; return 1; }
		updated=$(jq -c --arg path "$path" --argjson identity "$stage_identity" '
			.changes = [.changes[] | if .path == $path then .desired.stage_identity = $identity else . end]
		' <<<"$WALLPAPER_PENDING_JSON") || { wallpaper_abort_preparing_transaction curation-stage-evidence || true; return 1; }
		wallpaper_update_pending_evidence "$updated" || { wallpaper_abort_preparing_transaction curation-stage-evidence || true; return 1; }
	done
	wallpaper_after_pending_staged || { wallpaper_abort_preparing_transaction curation-after-staging || true; return 1; }
	wallpaper_verify_curation_prepared "$WALLPAPER_PENDING_JSON" || { wallpaper_abort_preparing_transaction curation-prepared-verification || true; return 1; }
	updated=$(jq -c '.phase = "prepared"' <<<"$WALLPAPER_PENDING_JSON") || { wallpaper_abort_preparing_transaction curation-phase-transition || true; return 1; }
	wallpaper_update_pending_evidence "$updated" || { wallpaper_abort_preparing_transaction curation-phase-transition || true; return 1; }
}

wallpaper_verify_curation_prepared() {
	local pending=$1 change path identity backup stage quarantine parent source
	[[ $(jq -r '.phase' <<<"$pending") == preparing ]] || return 1
	while IFS= read -r parent; do
		identity=$(jq -c --arg path "$parent" '.parents[] | select(.path == $path) | .identity' <<<"$pending") || return 1
		[[ $identity != null ]] && wallpaper_object_identity_matches "$parent" "$identity" || return 1
	done < <(jq -r '.parents[].path' <<<"$pending")
	while IFS= read -r change; do
		path=$(jq -r '.path' <<<"$change")
		identity=$(jq -c '.prior.identity' <<<"$change")
		if [[ $(jq -r '.prior.present' <<<"$change") == true ]]; then
			wallpaper_identity_matches "$path" "$identity" || return 1
			backup=$(jq -r '.prior.backup_path' <<<"$change")
			identity=$(jq -c '.prior.backup_identity' <<<"$change")
			[[ $identity != null ]] && wallpaper_identity_matches "$backup" "$identity" || return 1
		else
			wallpaper_path_is_absent "$path" || return 1
		fi
		stage=$(jq -r '.desired.stage_path // empty' <<<"$change")
		if [[ -n $stage ]]; then
			identity=$(jq -c '.desired.stage_identity' <<<"$change")
			[[ $identity != null ]] && wallpaper_identity_matches "$stage" "$identity" || return 1
			identity=$(jq -c '.desired.source_identity' <<<"$change")
			source=$(jq -r --argjson identity "$identity" 'first(.changes[] | select(.prior.identity == $identity) | .path) // empty' <<<"$pending") || return 1
			[[ -n $source ]] && wallpaper_identity_matches "$source" "$identity" || return 1
			wallpaper_files_are_same "$source" "$stage" || return 1
		fi
		quarantine=$(jq -r '.quarantine_path' <<<"$change")
		wallpaper_path_is_absent "$quarantine" || return 1
	done < <(jq -c '.changes[]' <<<"$pending")
}

wallpaper_verify_curation_preparing_prior() {
	local pending=$1 change path identity
	while IFS= read -r change; do
		path=$(jq -r '.path' <<<"$change")
		if [[ $(jq -r '.prior.present' <<<"$change") == true ]]; then
			identity=$(jq -c '.prior.identity' <<<"$change")
			wallpaper_identity_matches "$path" "$identity" || return 1
		else
			wallpaper_path_is_absent "$path" || return 1
		fi
	done < <(jq -c '.changes[]' <<<"$pending")
}

wallpaper_preparing_resources_have_recorded_ownership() {
	local pending=$1 path identity
	while IFS=$'\t' read -r path identity; do
		[[ -n $path ]] || continue
		if ! wallpaper_path_is_absent "$path"; then [[ $identity != null ]] || return 1; fi
	done < <(jq -r '(
		(.changes[] | select(.desired.stage_path != null) | [.desired.stage_path,(.desired.stage_identity | tojson)]),
		(.changes[] | select(.prior.backup_path != null) | [.prior.backup_path,(.prior.backup_identity | tojson)]),
		(.prior_active? | select(.backup_path != null) | [.backup_path,(.backup_identity | tojson)]),
		(.active_stage? | select(.path != null) | [.path,(.identity | tojson)]),
		(.parents[] | select(.created) | [.path,(.identity | tojson)])
	) | @tsv' <<<"$pending")
}

wallpaper_cleanup_preparing_resources() {
	local pending=$1 domain path identity parent created actual
	wallpaper_assert_locked_state_root || return 1
	[[ $(jq -r '.phase' <<<"$pending") == preparing ]] || return 1
	wallpaper_preparing_resources_have_recorded_ownership "$pending" || return 1
	domain=$(jq -r '.domain' <<<"$pending")
	case $domain in
		curation) wallpaper_verify_curation_preparing_prior "$pending" || return 1 ;;
		deployment) wallpaper_verify_deployment_preparing_prior "$pending" || return 1 ;;
		*) return 1 ;;
	esac
	while IFS= read -r path; do wallpaper_path_is_absent "$path" || return 1; done \
		< <(jq -r '(.changes[].quarantine_path?,.prior_active?.quarantine_path?,.active_stage?.rollback_quarantine_path?) | select(. != null)' <<<"$pending")
	while IFS=$'\t' read -r path identity; do
		[[ -n $path ]] || continue
		wallpaper_path_is_absent "$path" && continue
		[[ $identity != null ]] || return 1
		actual=$identity
		wallpaper_identity_matches "$path" "$actual" || return 1
		wallpaper_cleanup_staged_file "$path" "$actual" || return 1
	done < <(jq -r '
		.changes[] | select(.desired.stage_path != null) |
		[.desired.stage_path,(.desired.stage_identity | tojson)] | @tsv
	' <<<"$pending")
	path=$(jq -r '.active_stage.path // empty' <<<"$pending") || return 1
	if [[ -n $path ]] && ! wallpaper_path_is_absent "$path"; then
		identity=$(jq -c '.active_stage.identity' <<<"$pending") || return 1
		[[ $identity != null ]] || return 1
		actual=$identity
		wallpaper_identity_matches "$path" "$actual" || return 1
		wallpaper_cleanup_staged_file "$path" "$actual" || return 1
	fi
	while IFS=$'\t' read -r path identity; do
		[[ -n $path ]] || continue
		wallpaper_path_is_absent "$path" && continue
		[[ $identity != null ]] || return 1
		actual=$identity
		wallpaper_identity_matches "$path" "$actual" || return 1
		wallpaper_cleanup_staged_file "$path" "$actual" || return 1
	done < <(jq -r '(
		(.changes[] | select(.prior.backup_path != null) | [.prior.backup_path,(.prior.backup_identity | tojson)]),
		(.prior_active? | select(.backup_path != null) | [.backup_path,(.backup_identity | tojson)])
		) | @tsv
	' <<<"$pending")
	while IFS=$'\t' read -r parent created identity; do
		[[ $created == true ]] || continue
		wallpaper_path_is_absent "$parent" && continue
		[[ $identity != null ]] || return 1
		actual=$(wallpaper_files lstat "$parent") || return 1
		wallpaper_lstat_identity_json_is_valid "$actual" directory || return 1
		[[ $(jq -Sc '{device,gid,inode,mode,type,uid}' <<<"$actual") == "$(jq -Sc '{device,gid,inode,mode,type,uid}' <<<"$identity")" ]] || return 1
		wallpaper_assert_locked_state_root || return 1
		wallpaper_files remove-dir "$parent" "$actual" >/dev/null || return 1
	done < <(jq -r '.parents | sort_by(.path | length) | reverse[] | [.path,(.created | tostring),(.identity | tojson)] | @tsv' <<<"$pending")
	case $domain in
		curation) wallpaper_verify_curation_preparing_prior "$pending" || return 1 ;;
		deployment) wallpaper_verify_deployment_preparing_prior "$pending" || return 1 ;;
	esac
	wallpaper_remove_state_file_verified "$WALLPAPER_RECOVERY_RECEIPT" "$WALLPAPER_RECOVERY_IDENTITY" || return 1
	wallpaper_remove_state_file_verified "$WALLPAPER_PENDING_RECEIPT" "$WALLPAPER_PENDING_IDENTITY"
}

wallpaper_abort_preparing_transaction() {
	local step=$1 pending=$WALLPAPER_PENDING_JSON current identity domain
	[[ -n $pending ]] || return 1
	wallpaper_assert_locked_state_root || return 1
	if [[ -e $WALLPAPER_PENDING_RECEIPT && ! -L $WALLPAPER_PENDING_RECEIPT ]]; then
		identity=$(wallpaper_file_identity "$WALLPAPER_PENDING_RECEIPT") || return 1
		current=$(wallpaper_read_file_stable "$WALLPAPER_PENDING_RECEIPT" "$identity") || return 1
		[[ $(jq -r '.transaction_id' <<<"$current" 2>/dev/null) == "$(jq -r '.transaction_id' <<<"$pending")" ]] || return 1
		domain=$(jq -r '.domain' <<<"$current") || return 1
		case $domain in
			curation) wallpaper_validate_curation_pending "$current" || return 1 ;;
			deployment) wallpaper_validate_deployment_pending "$current" || return 1 ;;
			*) return 1 ;;
		esac
		WALLPAPER_PENDING_JSON=$current
		WALLPAPER_PENDING_IDENTITY=$identity
		pending=$current
	fi
	if [[ $(jq -r '.phase' <<<"$pending") == prepared ]]; then
		domain=$(jq -r '.domain' <<<"$pending")
		case $domain in
			curation)
				wallpaper_restore_curation_pending "$pending" && wallpaper_verify_curation_prior "$pending" && \
					wallpaper_mark_transaction_rolled_back && wallpaper_clear_transaction_evidence "$WALLPAPER_PENDING_JSON"
				return
				;;
			deployment)
				wallpaper_restore_deployment_pending "$pending" && wallpaper_verify_deployment_prior "$pending" && \
					wallpaper_mark_transaction_rolled_back && wallpaper_clear_transaction_evidence "$WALLPAPER_PENDING_JSON"
				return
				;;
		esac
	fi
	[[ $(jq -r '.phase' <<<"$pending") == preparing ]] || return 1
	if wallpaper_cleanup_preparing_resources "$pending"; then
		WALLPAPER_PENDING_JSON=''
		return 0
	fi
	wallpaper_write_recovery_required "$step" "$WALLPAPER_PENDING_JSON" || true
	printf 'Error: wallpaper transaction preparation could not be cleaned safely; recovery evidence was retained.\n' >&2
	return 1
}

wallpaper_write_recovery_required() {
	local step=$1 pending=$2 transaction created digest recovery
	wallpaper_assert_locked_state_root || return 1
	if [[ -n $WALLPAPER_RECOVERY_JSON && -n $WALLPAPER_RECOVERY_IDENTITY ]]; then
		wallpaper_validate_recovery_json "$WALLPAPER_RECOVERY_JSON" "$pending" && \
			wallpaper_identity_matches "$WALLPAPER_RECOVERY_RECEIPT" "$WALLPAPER_RECOVERY_IDENTITY" && return 0
		return 1
	fi
	transaction=$(jq -r '.transaction_id' <<<"$pending") || return 1
	created=$(wallpaper_now) || return 1
	digest=$(printf '%s\n' "$pending" | sha256sum | { read -r value _; printf '%s' "$value"; }) || return 1
	recovery=$(jq -cn --argjson schema "$WALLPAPER_SCHEMA_VERSION" --arg transaction "$transaction" --arg created "$created" \
		--arg step "$step" --arg digest "$digest" \
		'{schema_version:$schema,kind:"recovery-required",transaction_id:$transaction,created_at:$created,failed_step:$step,pending_digest:$digest}') || return 1
	wallpaper_write_state_file_verified recovery-required "$recovery"
}

wallpaper_clear_transaction_evidence() {
	local pending=$1
	wallpaper_assert_locked_state_root || return 1
	wallpaper_cleanup_pending_publication_stages "$pending" || return 1
	wallpaper_cleanup_pending_quarantines "$pending" || return 1
	if [[ $(jq -r '.domain' <<<"$pending") == deployment && $(jq -r '.phase' <<<"$pending") == complete ]]; then
		wallpaper_cleanup_completed_deployment_directories "$pending" || return 1
	fi
	wallpaper_cleanup_transaction_backups "$pending" || return 1
	wallpaper_remove_state_file_verified "$WALLPAPER_RECOVERY_RECEIPT" "$WALLPAPER_RECOVERY_IDENTITY" || return 1
	wallpaper_remove_state_file_verified "$WALLPAPER_PENDING_RECEIPT" "$WALLPAPER_PENDING_IDENTITY" || return 1
}

wallpaper_mark_transaction_complete() {
	local updated
	[[ $(jq -r '.phase' <<<"$WALLPAPER_PENDING_JSON") == prepared ]] || return 1
	updated=$(jq -c '.phase = "complete"' <<<"$WALLPAPER_PENDING_JSON") || return 1
	wallpaper_update_pending_evidence "$updated" || return 1
	wallpaper_cleanup_checkpoint completion-marked
}

wallpaper_mark_transaction_rolled_back() {
	local updated
	updated=$(jq -c '.phase = "rolled_back"' <<<"$WALLPAPER_PENDING_JSON") || return 1
	wallpaper_update_pending_evidence "$updated"
}

wallpaper_complete_transaction() {
	wallpaper_mark_transaction_complete || return 1
	wallpaper_clear_transaction_evidence "$WALLPAPER_PENDING_JSON"
}

wallpaper_verify_completed_transaction() {
	local pending=$1 domain
	[[ $(jq -r '.phase' <<<"$pending") == complete ]] || return 1
	domain=$(jq -r '.domain' <<<"$pending")
	case $domain in
		curation) wallpaper_verify_curation_desired "$pending" ;;
		deployment) wallpaper_verify_deployment_desired_from_pending "$pending" ;;
		*) return 1 ;;
	esac
}

wallpaper_verify_rolled_back_transaction() {
	local pending=$1 domain
	[[ $(jq -r '.phase' <<<"$pending") == rolled_back ]] || return 1
	domain=$(jq -r '.domain' <<<"$pending")
	case $domain in
		curation) wallpaper_verify_curation_prior "$pending" ;;
		deployment) wallpaper_verify_deployment_prior "$pending" ;;
		*) return 1 ;;
	esac
}

wallpaper_restore_curation_pending() {
	local pending=$1 change path parent prior_present prior_digest prior_mode prior_identity backup backup_identity desired_present desired_digest stage_identity current_identity directory quarantine quarantine_identity
	wallpaper_assert_locked_state_root || return 1
	while IFS= read -r change; do
		path=$(jq -r '.path' <<<"$change")
		parent=${path%/*}
		wallpaper_verify_pending_parent "$parent" "$pending" || return 1
		prior_present=$(jq -r '.prior.present' <<<"$change")
		desired_present=$(jq -r '.desired.present' <<<"$change")
		quarantine=$(jq -r '.quarantine_path' <<<"$change")
		if [[ $prior_present == true ]]; then
			prior_digest=$(jq -r '.prior.digest' <<<"$change")
			prior_mode=$(jq -r '.prior.mode' <<<"$change")
			prior_identity=$(jq -c '.prior.identity' <<<"$change")
			backup=$(jq -r '.prior.backup_path' <<<"$change") backup_identity=$(jq -c '.prior.backup_identity' <<<"$change")
			if [[ -e $path || -L $path ]]; then
				[[ -f $path && ! -L $path ]] || return 1
				if wallpaper_identity_matches "$path" "$prior_identity"; then
					wallpaper_path_is_absent "$quarantine" || return 1
					continue
				fi
				return 1
			fi
			if [[ -e $quarantine || -L $quarantine ]]; then
				wallpaper_restore_from_quarantine "$quarantine" "$prior_identity" "$path" || return 1
			else
				wallpaper_restore_file "$backup" "$path" "$prior_digest" "$prior_mode" "$backup_identity" || return 1
			fi
		else
			if [[ -e $path || -L $path ]]; then
				[[ -f $path && ! -L $path && $desired_present == true ]] || return 1
				desired_digest=$(jq -r '.desired.digest' <<<"$change")
				stage_identity=$(jq -c '.desired.stage_identity' <<<"$change")
				wallpaper_identity_matches_exchange "$path" "$stage_identity" || return 1
				current_identity=$(wallpaper_file_identity "$path") || return 1
				wallpaper_remove_to_quarantine "$path" "$current_identity" "$quarantine" || return 1
			fi
		fi
		done < <(jq -c '.changes | reverse[]' <<<"$pending")
	wallpaper_cleanup_pending_publication_stages "$pending" || return 1
	wallpaper_cleanup_pending_quarantines "$pending" || return 1
	while IFS= read -r directory; do
		wallpaper_remove_pending_directory "$directory" "$pending" || return 1
	done < <(jq -r '.created_directories | reverse[]' <<<"$pending")
}

wallpaper_verify_curation_desired() {
	local pending=$1 change path present digest stage_identity
	while IFS= read -r change; do
		path=$(jq -r '.path' <<<"$change") present=$(jq -r '.desired.present' <<<"$change")
		if [[ $present == true ]]; then
			digest=$(jq -r '.desired.digest' <<<"$change") stage_identity=$(jq -c '.desired.stage_identity' <<<"$change")
			wallpaper_regular_file_is_exact "$path" "$digest" 0644 && wallpaper_identity_matches_exchange "$path" "$stage_identity" || return 1
		else
			wallpaper_path_is_absent "$path" || return 1
		fi
	done < <(jq -c '.changes[]' <<<"$pending")
	wallpaper_validate_library_quiet
}

wallpaper_verify_curation_prior() {
	local pending=$1 change path present digest mode
	while IFS= read -r change; do
		path=$(jq -r '.path' <<<"$change") present=$(jq -r '.prior.present' <<<"$change")
		if [[ $present == true ]]; then
			digest=$(jq -r '.prior.digest' <<<"$change") mode=$(jq -r '.prior.mode' <<<"$change")
			[[ -f $path && ! -L $path ]] && wallpaper_regular_file_is_exact "$path" "$digest" "0${mode#0}" || return 1
		else
			[[ ! -e $path && ! -L $path ]] || return 1
		fi
	done < <(jq -c '.changes[]' <<<"$pending")
	wallpaper_validate_library_quiet
}

wallpaper_rollback_curation() {
	local step=$1 pending=$2
	printf 'Transaction failure: %s; restoring prior Wallpaper library and intake state.\n' "$step" >&2
	if wallpaper_validate_curation_pending "$pending" && wallpaper_restore_curation_pending "$pending" && wallpaper_verify_curation_prior "$pending" && wallpaper_mark_transaction_rolled_back; then
		wallpaper_clear_transaction_evidence "$WALLPAPER_PENDING_JSON" || return 1
		printf 'Wallpaper curation rollback verified.\n' >&2
		return 0
	fi
	wallpaper_write_recovery_required "$step" "$pending" || true
	printf 'Error: wallpaper curation rollback failed; pending evidence and backups were retained.\n' >&2
	return 1
}

wallpaper_recover_interrupted() {
	local pending=$WALLPAPER_PENDING_JSON domain
	wallpaper_assert_locked_state_root || return 1
	[[ -n $pending ]] || return 1
	domain=$(jq -r '.domain' <<<"$pending")
	if [[ $(jq -r '.phase' <<<"$pending") == preparing ]]; then
		printf 'Interrupted wallpaper transaction preparation detected: %s\n' "$(jq -r '.operation' <<<"$pending")"
		if wallpaper_cleanup_preparing_resources "$pending"; then
			printf 'Interrupted wallpaper transaction preparation recovered and verified; rerun the requested operation.\n'
			WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_RECOVERY_COMPLETED
			return 0
		fi
		wallpaper_write_recovery_required interrupted-preparation-recovery "$WALLPAPER_PENDING_JSON" || true
		printf 'Error: interrupted wallpaper preparation could not be cleaned safely; ordinary wallpaper mutation remains blocked.\n' >&2
		return 1
	fi
	if [[ $(jq -r '.phase' <<<"$pending") == rolled_back ]]; then
		printf 'Rolled-back wallpaper transaction cleanup was interrupted: %s\n' "$(jq -r '.operation' <<<"$pending")"
		if wallpaper_verify_rolled_back_transaction "$pending" && wallpaper_clear_transaction_evidence "$pending"; then
			printf 'Interrupted wallpaper transaction cleanup recovered and verified; rerun the requested operation.\n'
			WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_RECOVERY_COMPLETED
			return 0
		fi
		wallpaper_write_recovery_required interrupted-rollback-cleanup "$pending" || true
		printf 'Error: rolled-back wallpaper transaction cleanup could not be resumed safely.\n' >&2
		return 1
	fi
	if [[ $(jq -r '.phase' <<<"$pending") == complete ]]; then
		printf 'Completed wallpaper transaction cleanup was interrupted: %s\n' "$(jq -r '.operation' <<<"$pending")"
		if wallpaper_verify_completed_transaction "$pending" && wallpaper_clear_transaction_evidence "$pending"; then
			printf 'Interrupted wallpaper transaction cleanup recovered and verified; rerun the requested operation.\n'
			WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_RECOVERY_COMPLETED
			return 0
		fi
		wallpaper_write_recovery_required interrupted-completion-cleanup "$pending" || true
		printf 'Error: completed wallpaper transaction cleanup could not be resumed safely.\n' >&2
		return 1
	fi
	if [[ $domain != curation ]]; then
		if [[ $domain == deployment ]]; then
			wallpaper_recover_deployment "$pending"
			return $?
		fi
		printf 'Error: unsupported interrupted wallpaper transaction domain: %s\n' "$domain" >&2
		return 1
	fi
	printf 'Interrupted wallpaper curation transaction detected: %s\n' "$(jq -r '.operation' <<<"$pending")"
	if wallpaper_restore_curation_pending "$pending" && wallpaper_verify_curation_prior "$pending" && wallpaper_mark_transaction_rolled_back; then
		wallpaper_clear_transaction_evidence "$WALLPAPER_PENDING_JSON" || return 1
		printf 'Interrupted wallpaper transaction recovered and verified; rerun the requested operation.\n'
		WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_RECOVERY_COMPLETED
		return 0
	fi
	wallpaper_write_recovery_required interrupted-recovery "$pending" || true
	printf 'Error: interrupted wallpaper recovery failed; ordinary wallpaper mutation remains blocked.\n' >&2
	return 1
}

wallpaper_lock_and_recover() {
	wallpaper_prepare_state_root || return 1
	wallpaper_acquire_lock || return 1
	wallpaper_assert_locked_state_root || return 1
	wallpaper_recheck_approved_omarchy || return 1
	if ! wallpaper_inspect_state; then
		printf 'Error: invalid wallpaper state blocks mutation: %s\n' "$WALLPAPER_STATE_ERROR" >&2
		return 1
	fi
	if [[ -n $WALLPAPER_PENDING_JSON || -n $WALLPAPER_RECOVERY_JSON ]]; then
		wallpaper_recover_interrupted
		return $?
	fi
	return 2
}

wallpaper_recover_before_preflight() {
	local unattended=$1 override=$2 status
	wallpaper_initialize_paths || return 1
	if [[ ! -e $WALLPAPER_PENDING_RECEIPT && ! -L $WALLPAPER_PENDING_RECEIPT && \
		! -e $WALLPAPER_RECOVERY_RECEIPT && ! -L $WALLPAPER_RECOVERY_RECEIPT ]]; then
		return 2
	fi
	wallpaper_require_compatible_mutation "$unattended" "$override" || return 1
	if [[ $WALLPAPER_OMARCHY_MISMATCH == true && $unattended != true && $override != true ]] && \
		! wallpaper_confirm 'Recover the interrupted wallpaper transaction despite the Omarchy version mismatch?'; then
		printf 'No recovery changes made.\n'
		return 1
	fi
	if wallpaper_lock_and_recover; then
		wallpaper_release_lock
		return 0
	else
		status=$?
	fi
	wallpaper_release_lock
	return "$status"
}

wallpaper_allocate_transaction() {
	local transaction attempt=0
	while ((attempt < 10)); do
		transaction=$(wallpaper_new_transaction_id) || return 1
		if [[ ! -e $WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction && ! -L $WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction ]]; then
			printf '%s\n' "$transaction"
			return 0
		fi
		attempt=$((attempt + 1))
	done
	return 1
}

wallpaper_parse_common_flag() {
	case $1 in
		--yes) WALLPAPER_OPTION_YES=true ;;
		--allow-omarchy-mismatch) WALLPAPER_OPTION_OVERRIDE=true ;;
		*) return 1 ;;
	esac
}

add_wallpaper() {
	WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_ORDINARY
	if (($# < 2)); then
		printf 'Error: add_wallpaper requires one Intake path and at least one installed theme slug.\n' >&2
		return 2
	fi
	local intake=$1 argument theme digest extension format identity library_before themes_before intake_before transaction lock_status target existing existing_theme
	local duplicate=false mutation_started=false outcome=0
	local -a themes=() new_targets=()
	declare -A selected=()
	shift
	WALLPAPER_OPTION_YES=false WALLPAPER_OPTION_OVERRIDE=false
	for argument in "$@"; do
		if [[ $argument == --* ]]; then
			wallpaper_parse_common_flag "$argument" || { printf 'Error: unknown add_wallpaper option: %s\n' "$argument" >&2; return 2; }
		else
			[[ -z ${selected[$argument]+present} ]] || continue
			selected[$argument]=1 themes+=("$argument")
		fi
	done
	((${#themes[@]} > 0)) || { printf 'Error: add_wallpaper requires at least one theme slug.\n' >&2; return 2; }
	if wallpaper_recover_before_preflight "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE"; then return 0; else lock_status=$?; fi
	((lock_status == 2)) || return "$lock_status"
	[[ $intake == /* ]] || intake="$WALLPAPER_INBOX_ROOT/$intake"
	wallpaper_intake_path_is_safe "$intake" || { printf 'Error: Add requires a direct regular Intake file: %s\n' "$intake" >&2; return 1; }
	wallpaper_validate_image_quiet "$intake" || { printf 'Error: invalid Intake image: %s\n' "$WALLPAPER_IMAGE_ERROR" >&2; return 1; }
	digest=$WALLPAPER_IMAGE_DIGEST extension=$WALLPAPER_IMAGE_EXTENSION format=$WALLPAPER_IMAGE_FORMAT identity=$WALLPAPER_IMAGE_IDENTITY
	library_before=$(wallpaper_library_snapshot) || { printf 'Error: invalid Wallpaper library: %s\n' "$WALLPAPER_LIBRARY_ERROR" >&2; return 1; }
	intake_before=$(wallpaper_intake_snapshot) || return 1
	themes_before=$(wallpaper_theme_fingerprint) || return 1
	wallpaper_discover_themes || return 1
	for theme in "${themes[@]}"; do
		if ! wallpaper_theme_is_installed "$theme"; then
			printf 'Error: Add destination is not an installed theme slug: %s\n' "$theme" >&2
			return 1
		fi
		target="$WALLPAPER_LIBRARY_ROOT/$theme/$digest.$extension"
		if [[ -e $target || -L $target ]]; then
			if [[ ! -f $target || -L $target || $(wallpaper_file_digest "$target") != "$digest" ]] || ! wallpaper_files_are_same "$intake" "$target"; then
				printf 'Error: Add destination conflicts with different existing state: %s\n' "$target" >&2
				return 1
			fi
			duplicate=true
		else
			new_targets+=("$target")
		fi
	done
	if [[ $duplicate == false ]]; then
		while IFS= read -r -d '' existing; do
			[[ ${existing##*/} != "$digest.$extension" ]] || duplicate=true
		done < <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f -print0 2>/dev/null | sort -z)
	fi
	printf 'Plan: Add one Intake image to the Wallpaper library\nValidation: valid\nFormat: %s\nSHA-256: %s\nDuplicate managed identity: %s\n' \
		"$format" "$digest" "$([[ $duplicate == true ]] && printf yes || printf no)"
	while IFS= read -r -d '' existing; do
		existing_theme=${existing#"$WALLPAPER_LIBRARY_ROOT"/} existing_theme=${existing_theme%%/*}
		printf 'Current assignment: %s (%s)\n' "$existing_theme" "$existing"
	done < <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f -name "$digest.$extension" -print0 2>/dev/null | sort -z)
	for theme in "${themes[@]}"; do
		target="$WALLPAPER_LIBRARY_ROOT/$theme/$digest.$extension"
		if [[ -e $target ]]; then printf 'No-op assignment: %s (%s)\n' "$theme" "$target"; else printf 'New assignment: %s (%s)\n' "$theme" "$target"; fi
	done
	printf 'Delete Intake after complete verification: %s\n' "$intake"
	[[ $WALLPAPER_OPTION_YES == true ]] || {
		wallpaper_require_compatible_mutation false "$WALLPAPER_OPTION_OVERRIDE" || return 1
		if ! wallpaper_confirm 'Apply this complete wallpaper Add plan, including any displayed Omarchy mismatch?'; then printf 'No changes made.\n'; return 0; fi
	}
	wallpaper_require_compatible_mutation "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE" || return 1
	if wallpaper_lock_and_recover; then wallpaper_release_lock; return 0; else lock_status=$?; fi
	if ((lock_status != 2)); then wallpaper_release_lock; return "$lock_status"; fi
	if [[ $(wallpaper_library_snapshot) != "$library_before" || $(wallpaper_intake_snapshot) != "$intake_before" || \
		$(wallpaper_theme_fingerprint) != "$themes_before" ]]; then
		printf 'Error: confirmed wallpaper Add plan is stale; no repository mutation was made.\n' >&2
		wallpaper_release_lock
		return 1
	fi
	wallpaper_validate_image_quiet "$intake" || { wallpaper_release_lock; return 1; }
	[[ $WALLPAPER_IMAGE_DIGEST == "$digest" && $WALLPAPER_IMAGE_IDENTITY == "$identity" ]] || { wallpaper_release_lock; return 1; }
	WALLPAPER_TRANSACTION_PATHS=() WALLPAPER_TRANSACTION_DESIRED_PRESENT=() WALLPAPER_TRANSACTION_DESIRED_DIGEST=()
	for target in "${new_targets[@]}"; do
		WALLPAPER_TRANSACTION_PATHS+=("$target") WALLPAPER_TRANSACTION_DESIRED_PRESENT+=(true) WALLPAPER_TRANSACTION_DESIRED_DIGEST+=("$digest")
	done
	WALLPAPER_TRANSACTION_PATHS+=("$intake") WALLPAPER_TRANSACTION_DESIRED_PRESENT+=(false) WALLPAPER_TRANSACTION_DESIRED_DIGEST+=('')
	transaction=$(wallpaper_allocate_transaction) || { wallpaper_release_lock; return 1; }
	wallpaper_begin_curation_transaction add "$transaction" "$intake" || { wallpaper_release_lock; return 1; }
	mutation_started=true
	for target in "${new_targets[@]}"; do
		if ! wallpaper_publish_file "$intake" "$target" "$digest" \
			"$(jq -c --arg path "$intake" '.changes[] | select(.path == $path) | .prior.identity' <<<"$WALLPAPER_PENDING_JSON")"; then outcome=1; break; fi
	done
	if ((outcome == 0)); then
		for theme in "${themes[@]}"; do
			target="$WALLPAPER_LIBRARY_ROOT/$theme/$digest.$extension"
			[[ -f $target && ! -L $target && $(wallpaper_file_digest "$target") == "$digest" ]] && wallpaper_files_are_same "$intake" "$target" || { outcome=1; break; }
		done
	fi
	if ((outcome == 0)) && ! wallpaper_delete_file_verified "$intake" "$digest" \
		"$(jq -c --arg path "$intake" '.changes[] | select(.path == $path) | .prior.identity' <<<"$WALLPAPER_PENDING_JSON")"; then outcome=1; fi
	if ((outcome == 0)) && { [[ -e $intake || -L $intake ]] || ! wallpaper_validate_library_quiet; }; then outcome=1; fi
	if ((outcome != 0)); then
		[[ $mutation_started == false ]] || wallpaper_rollback_curation add-failure "$WALLPAPER_PENDING_JSON" || true
		wallpaper_release_lock
		return 1
	fi
	wallpaper_complete_transaction || { [[ ! -e $WALLPAPER_PENDING_RECEIPT ]] || wallpaper_write_recovery_required completion-cleanup "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; }
	wallpaper_release_lock
	printf 'Wallpaper Add committed and verified. Live Omarchy backgrounds are unchanged; run Apply wallpapers to deploy.\n'
}

wallpaper_find_assignment() {
	local digest=$1 theme=$2 candidate
	[[ $digest =~ ^[0-9a-f]{64}$ ]] || return 1
	wallpaper_slug_is_safe "$theme" || return 1
	for candidate in "$WALLPAPER_LIBRARY_ROOT/$theme/$digest."*; do
		[[ -f $candidate && ! -L $candidate ]] || continue
		printf '%s\n' "$candidate"
		return 0
	done
	return 1
}

move_wallpaper() {
	WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_ORDINARY
	if (($# < 3)); then printf 'Error: move_wallpaper requires digest, source theme, and destination theme.\n' >&2; return 2; fi
	local digest=$1 source_theme=$2 destination_theme=$3 argument source destination extension library_before themes_before transaction lock_status
	local destination_exists=false outcome=0
	shift 3
	WALLPAPER_OPTION_YES=false WALLPAPER_OPTION_OVERRIDE=false
	for argument in "$@"; do wallpaper_parse_common_flag "$argument" || return 2; done
	if wallpaper_recover_before_preflight "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE"; then return 0; else lock_status=$?; fi
	((lock_status == 2)) || return "$lock_status"
	[[ $source_theme != "$destination_theme" ]] || { printf 'Error: Move destination must differ from source theme.\n' >&2; return 1; }
	library_before=$(wallpaper_library_snapshot) || { printf 'Error: invalid Wallpaper library: %s\n' "$WALLPAPER_LIBRARY_ERROR" >&2; return 1; }
	themes_before=$(wallpaper_theme_fingerprint) || return 1
	wallpaper_discover_themes || return 1
	wallpaper_theme_is_installed "$destination_theme" || { printf 'Error: Move destination is not an installed theme slug: %s\n' "$destination_theme" >&2; return 1; }
	source=$(wallpaper_find_assignment "$digest" "$source_theme") || { printf 'Error: source assignment was not found.\n' >&2; return 1; }
	extension=${source##*.} destination="$WALLPAPER_LIBRARY_ROOT/$destination_theme/$digest.$extension"
	if [[ -e $destination || -L $destination ]]; then
		[[ -f $destination && ! -L $destination && $(wallpaper_file_digest "$destination") == "$digest" ]] && wallpaper_files_are_same "$source" "$destination" || {
			printf 'Error: Move destination conflicts with different state: %s\n' "$destination" >&2
			return 1
		}
		destination_exists=true
	fi
	printf 'Plan: Move one Theme assignment\nSource assignment: %s\nDestination assignment: %s\nDestination publication: %s\nSource removal occurs only after destination verification.\n' \
		"$source" "$destination" "$([[ $destination_exists == true ]] && printf 'exact no-op' || printf 'new copy')"
	[[ $WALLPAPER_OPTION_YES == true ]] || {
		wallpaper_require_compatible_mutation false "$WALLPAPER_OPTION_OVERRIDE" || return 1
		if ! wallpaper_confirm 'Apply this complete wallpaper Move plan, including any displayed Omarchy mismatch?'; then printf 'No changes made.\n'; return 0; fi
	}
	wallpaper_require_compatible_mutation "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE" || return 1
	if wallpaper_lock_and_recover; then wallpaper_release_lock; return 0; else lock_status=$?; fi
	if ((lock_status != 2)); then wallpaper_release_lock; return "$lock_status"; fi
	if [[ $(wallpaper_library_snapshot) != "$library_before" || $(wallpaper_theme_fingerprint) != "$themes_before" ]]; then
		printf 'Error: confirmed Move plan is stale.\n' >&2; wallpaper_release_lock; return 1
	fi
	WALLPAPER_TRANSACTION_PATHS=() WALLPAPER_TRANSACTION_DESIRED_PRESENT=() WALLPAPER_TRANSACTION_DESIRED_DIGEST=()
	if [[ $destination_exists == false ]]; then
		WALLPAPER_TRANSACTION_PATHS+=("$destination") WALLPAPER_TRANSACTION_DESIRED_PRESENT+=(true) WALLPAPER_TRANSACTION_DESIRED_DIGEST+=("$digest")
	fi
	WALLPAPER_TRANSACTION_PATHS+=("$source") WALLPAPER_TRANSACTION_DESIRED_PRESENT+=(false) WALLPAPER_TRANSACTION_DESIRED_DIGEST+=('')
	transaction=$(wallpaper_allocate_transaction) || { wallpaper_release_lock; return 1; }
	wallpaper_begin_curation_transaction move "$transaction" "$source" || { wallpaper_release_lock; return 1; }
	if [[ $destination_exists == false ]] && ! wallpaper_publish_file "$source" "$destination" "$digest" \
		"$(jq -c --arg path "$source" '.changes[] | select(.path == $path) | .prior.identity' <<<"$WALLPAPER_PENDING_JSON")"; then outcome=1; fi
	if ((outcome == 0)) && { [[ ! -f $destination || -L $destination || $(wallpaper_file_digest "$destination") != "$digest" ]] || ! wallpaper_files_are_same "$source" "$destination"; }; then outcome=1; fi
	if ((outcome == 0)) && ! wallpaper_delete_file_verified "$source" "$digest" \
		"$(jq -c --arg path "$source" '.changes[] | select(.path == $path) | .prior.identity' <<<"$WALLPAPER_PENDING_JSON")"; then outcome=1; fi
	if ((outcome == 0)) && ! wallpaper_validate_library_quiet; then outcome=1; fi
	if ((outcome != 0)); then wallpaper_rollback_curation move-failure "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; fi
	wallpaper_complete_transaction || { [[ ! -e $WALLPAPER_PENDING_RECEIPT ]] || wallpaper_write_recovery_required completion-cleanup "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; }
	wallpaper_remove_pending_directory "${source%/*}" "$WALLPAPER_PENDING_JSON" || true
	wallpaper_release_lock
	printf 'Wallpaper Move committed and verified. Live Omarchy backgrounds are unchanged; run Apply wallpapers to deploy.\n'
}

remove_wallpaper_assignment() {
	WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_ORDINARY
	if (($# < 2)); then printf 'Error: remove_wallpaper_assignment requires digest and theme.\n' >&2; return 2; fi
	local digest=$1 theme=$2 argument source library_before transaction lock_status assignments=0 candidate outcome=0 final=false
	shift 2
	WALLPAPER_OPTION_YES=false WALLPAPER_OPTION_OVERRIDE=false
	for argument in "$@"; do wallpaper_parse_common_flag "$argument" || return 2; done
	if wallpaper_recover_before_preflight "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE"; then return 0; else lock_status=$?; fi
	((lock_status == 2)) || return "$lock_status"
	library_before=$(wallpaper_library_snapshot) || { printf 'Error: invalid Wallpaper library: %s\n' "$WALLPAPER_LIBRARY_ERROR" >&2; return 1; }
	source=$(wallpaper_find_assignment "$digest" "$theme") || { printf 'Error: selected Theme assignment was not found.\n' >&2; return 1; }
	while IFS= read -r -d '' candidate; do [[ ${candidate##*/} != "$digest.${source##*.}" ]] || assignments=$((assignments + 1)); done \
		< <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f -print0 | sort -z)
	((assignments == 1)) && final=true
	printf 'Plan: Remove one Theme assignment\nAssignment: %s\n' "$source"
	[[ $final == false ]] || printf 'Managed wallpaper will cease to exist after this final Theme assignment is removed.\n'
	[[ $WALLPAPER_OPTION_YES == true ]] || {
		wallpaper_require_compatible_mutation false "$WALLPAPER_OPTION_OVERRIDE" || return 1
		if [[ $final == true ]]; then
			wallpaper_confirm 'Remove this final Theme assignment and delete the Managed wallpaper, including any displayed Omarchy mismatch?' || { printf 'No changes made.\n'; return 0; }
		else
			wallpaper_confirm 'Remove this wallpaper Theme assignment, including any displayed Omarchy mismatch?' || { printf 'No changes made.\n'; return 0; }
		fi
	}
	wallpaper_require_compatible_mutation "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE" || return 1
	if wallpaper_lock_and_recover; then wallpaper_release_lock; return 0; else lock_status=$?; fi
	if ((lock_status != 2)); then wallpaper_release_lock; return "$lock_status"; fi
	if [[ $(wallpaper_library_snapshot) != "$library_before" ]]; then printf 'Error: confirmed Remove plan is stale.\n' >&2; wallpaper_release_lock; return 1; fi
	WALLPAPER_TRANSACTION_PATHS=("$source") WALLPAPER_TRANSACTION_DESIRED_PRESENT=(false) WALLPAPER_TRANSACTION_DESIRED_DIGEST=('')
	transaction=$(wallpaper_allocate_transaction) || { wallpaper_release_lock; return 1; }
	wallpaper_begin_curation_transaction remove "$transaction" || { wallpaper_release_lock; return 1; }
	wallpaper_delete_file_verified "$source" "$digest" \
		"$(jq -c --arg path "$source" '.changes[] | select(.path == $path) | .prior.identity' <<<"$WALLPAPER_PENDING_JSON")" || outcome=1
	if ((outcome == 0)) && ! wallpaper_validate_library_quiet; then outcome=1; fi
	if ((outcome != 0)); then wallpaper_rollback_curation remove-failure "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; fi
	wallpaper_complete_transaction || { [[ ! -e $WALLPAPER_PENDING_RECEIPT ]] || wallpaper_write_recovery_required completion-cleanup "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; }
	wallpaper_remove_pending_directory "${source%/*}" "$WALLPAPER_PENDING_JSON" || true
	wallpaper_release_lock
	printf 'Wallpaper assignment removal committed and verified. Live Omarchy backgrounds are unchanged; run Apply wallpapers to deploy.\n'
}

manage_wallpapers() {
	if (($# != 0)); then
		printf 'Error: manage_wallpapers accepts no arguments.\n' >&2
		return 2
	fi
	local choice selected label entry name theme source_theme digest library_before library_after status index selected_index
	local destination_theme='' changed=false canceled=false
	local -a paths=() labels=() values=() selected_themes=() menu_labels=() menu_values=()
	local -A chosen_themes=()

	if wallpaper_recover_before_preflight false false; then
		return 0
	else
		status=$?
	fi
	((status == 2)) || return "$status"

	while true; do
		if ! choice=$(wizard_choose 'Manage wallpapers' 'Add' 'Inspect' 'Move' 'Remove' 'Back'); then choice=Back; fi
		case $choice in
			Inspect)
				inspect_wallpapers || printf 'Inspect could not produce a coherent read-only snapshot; fix the reported state and retry.\n' >&2
				;;
			Add)
				paths=() labels=()
				if ! wallpaper_repository_directory_path_is_safe "$WALLPAPER_INBOX_ROOT"; then
					printf 'Error: Wallpaper inbox path must remain in real repository directories: %s\n' "$WALLPAPER_INBOX_ROOT" >&2
					continue
				fi
				if [[ -e $WALLPAPER_INBOX_ROOT || -L $WALLPAPER_INBOX_ROOT ]]; then
					if [[ ! -d $WALLPAPER_INBOX_ROOT || -L $WALLPAPER_INBOX_ROOT ]]; then
						printf 'Error: Wallpaper inbox must be a real directory: %s\n' "$WALLPAPER_INBOX_ROOT" >&2
						continue
					fi
					while IFS= read -r -d '' entry; do
						name=${entry##*/}
						if [[ -f $entry && ! -L $entry ]] && wallpaper_validate_image_quiet "$entry"; then
							paths+=("$entry")
							printf -v label 'Intake: %q' "$name"
							labels+=("$label")
						else
							if [[ ! -f $entry || -L $entry ]]; then
								printf 'Rejected Intake: %q (not a direct regular non-symlink file)\n' "$name"
							else
								printf 'Rejected Intake: %q (%s)\n' "$name" "$WALLPAPER_IMAGE_ERROR"
							fi
						fi
					done < <(find "$WALLPAPER_INBOX_ROOT" -mindepth 1 -maxdepth 1 -print0 | sort -z)
				fi
				if ((${#paths[@]} == 0)); then
					printf 'No valid Intake images are available; Add made no changes. Use Inspect for rejection details.\n'
					continue
				fi
				menu_labels=("${labels[@]}" Back)
				if ! selected=$(wizard_choose 'Choose one valid Intake image' "${menu_labels[@]}"); then continue; fi
				[[ $selected != Back ]] || continue
				selected_index=-1
				for index in "${!labels[@]}"; do [[ ${labels[$index]} != "$selected" ]] || selected_index=$index; done
				((selected_index >= 0)) || continue
				entry=${paths[$selected_index]}
				if ! wallpaper_discover_themes; then continue; fi
				if ((${#WALLPAPER_THEME_SLUGS[@]} == 0)); then
					printf 'No installed packaged or user themes are available for Add.\n'
					continue
				fi
				selected_themes=() chosen_themes=() canceled=false
				while true; do
					menu_labels=() menu_values=()
					for index in "${!WALLPAPER_THEME_SLUGS[@]}"; do
						theme=${WALLPAPER_THEME_SLUGS[$index]}
						[[ -z ${chosen_themes[$theme]+present} ]] || continue
						menu_labels+=("${WALLPAPER_THEME_LABELS[$index]}") menu_values+=("$theme")
					done
					menu_labels+=('Done selecting themes' Back)
					if ! selected=$(wizard_choose 'Choose an additional destination theme' "${menu_labels[@]}"); then canceled=true; break; fi
					if [[ $selected == Back ]]; then canceled=true; break; fi
					if [[ $selected == 'Done selecting themes' ]]; then
						if ((${#selected_themes[@]} == 0)); then
							printf 'Select at least one destination theme or choose Back.\n'
							continue
						fi
						break
					fi
					selected_index=-1
					for index in "${!menu_values[@]}"; do [[ ${menu_labels[$index]} != "$selected" ]] || selected_index=$index; done
					((selected_index >= 0)) || continue
					theme=${menu_values[$selected_index]}
					chosen_themes[$theme]=1 selected_themes+=("$theme")
				done
				[[ $canceled == false ]] || continue
				library_before=$(wallpaper_library_snapshot) || { printf 'Error: invalid Wallpaper library: %s\n' "$WALLPAPER_LIBRARY_ERROR" >&2; continue; }
				status=0
				add_wallpaper "$entry" "${selected_themes[@]}" || status=$?
				if ((status != 0)); then
					printf 'Add did not complete; inspect the reported state, then retry Add.\n' >&2
					continue
				fi
				library_after=$(wallpaper_library_snapshot) || { printf 'Error: Add returned without a valid Wallpaper library.\n' >&2; return 1; }
				[[ $library_after == "$library_before" ]] || changed=true
				;;
			Move|Remove)
				if ! wallpaper_validate_library_quiet; then
					printf 'Error: invalid Wallpaper library: %s\n' "$WALLPAPER_LIBRARY_ERROR" >&2
					continue
				fi
				paths=() labels=()
				if [[ -d $WALLPAPER_LIBRARY_ROOT && ! -L $WALLPAPER_LIBRARY_ROOT ]]; then
					while IFS= read -r -d '' entry; do
						theme=${entry#"$WALLPAPER_LIBRARY_ROOT"/} theme=${theme%%/*}
						paths+=("$entry") labels+=("$theme / ${entry##*/}")
					done < <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f -print0 | sort -z)
				fi
				if ((${#paths[@]} == 0)); then
					printf 'The Wallpaper library has no Theme assignments; %s made no changes.\n' "$choice"
					continue
				fi
				menu_labels=("${labels[@]}" Back)
				if ! selected=$(wizard_choose "Choose one Theme assignment to $choice" "${menu_labels[@]}"); then continue; fi
				[[ $selected != Back ]] || continue
				selected_index=-1
				for index in "${!labels[@]}"; do [[ ${labels[$index]} != "$selected" ]] || selected_index=$index; done
				((selected_index >= 0)) || continue
				entry=${paths[$selected_index]} name=${entry##*/} digest=${name%%.*}
				source_theme=${entry#"$WALLPAPER_LIBRARY_ROOT"/} source_theme=${source_theme%%/*}
				library_before=$(wallpaper_library_snapshot) || { printf 'Error: invalid Wallpaper library: %s\n' "$WALLPAPER_LIBRARY_ERROR" >&2; continue; }
				status=0
				if [[ $choice == Move ]]; then
					if ! wallpaper_discover_themes; then continue; fi
					menu_labels=() menu_values=()
					for index in "${!WALLPAPER_THEME_SLUGS[@]}"; do
						theme=${WALLPAPER_THEME_SLUGS[$index]}
						[[ $theme == "$source_theme" ]] && continue
						menu_labels+=("${WALLPAPER_THEME_LABELS[$index]}") menu_values+=("$theme")
					done
					if ((${#menu_values[@]} == 0)); then
						printf 'No different installed destination theme is available for Move.\n'
						continue
					fi
					menu_labels+=(Back)
					if ! selected=$(wizard_choose 'Choose the destination theme' "${menu_labels[@]}"); then continue; fi
					[[ $selected != Back ]] || continue
					selected_index=-1
					for index in "${!menu_values[@]}"; do [[ ${menu_labels[$index]} != "$selected" ]] || selected_index=$index; done
					((selected_index >= 0)) || continue
					destination_theme=${menu_values[$selected_index]}
					move_wallpaper "$digest" "$source_theme" "$destination_theme" || status=$?
				else
					remove_wallpaper_assignment "$digest" "$source_theme" || status=$?
				fi
				if ((status != 0)); then
					printf '%s did not complete; inspect the reported state, then retry %s.\n' "$choice" "$choice" >&2
					continue
				fi
				library_after=$(wallpaper_library_snapshot) || { printf 'Error: %s returned without a valid Wallpaper library.\n' "$choice" >&2; return 1; }
				[[ $library_after == "$library_before" ]] || changed=true
				;;
			Back) break ;;
		esac
	done

	if [[ $changed == true ]]; then
		if ! choice=$(wizard_choose 'The Wallpaper library changed; choose when to deploy it' 'Apply now' 'Apply later'); then choice='Apply later'; fi
		if [[ $choice == 'Apply now' ]]; then
			apply_wallpapers
			return $?
		fi
		printf 'Wallpaper library changes are preserved. To deploy later, choose Apply wallpapers in the Dotfiles wizard.\n'
	fi
}

WALLPAPER_DESIRED_JSON='[]'
WALLPAPER_PLAN_JSON='[]'
WALLPAPER_PLAN_ERROR=''
WALLPAPER_DEPLOYMENT_FINGERPRINT=''
WALLPAPER_NEXT_CREATED_ROOT=false
WALLPAPER_NEXT_CREATED_DIRECTORIES='[]'

wallpaper_relative_target_is_safe() {
	local relative=$1 digest=${2-} theme name named_digest extension
	[[ $relative != /* && $relative == */* && $relative != */*/* ]] || return 1
	theme=${relative%%/*} name=${relative#*/}
	wallpaper_slug_is_safe "$theme" || return 1
	[[ $name =~ ^([0-9a-f]{64})[.](jpg|png|gif|bmp|webp)$ ]] || return 1
	named_digest=${BASH_REMATCH[1]} extension=${BASH_REMATCH[2]}
	[[ -z $digest || $digest == "$named_digest" ]]
}

wallpaper_validate_active_json() {
	local json=$1 path digest directory previous=''
	jq -e --argjson schema "$WALLPAPER_SCHEMA_VERSION" '
		type == "object" and keys == ["activated_at","created_directories","created_root","kind","schema_version","targets","transaction_id"] and
		.schema_version == $schema and .kind == "active" and (.transaction_id | type == "string") and
		(.activated_at | type == "string" and length > 0) and (.created_root | type == "boolean") and
		(.created_directories | type == "array" and . == sort and length == (unique | length) and all(.[]; type == "string")) and
		(.targets | type == "array" and length > 0 and all(.[]; type == "object" and keys == ["digest","path"] and
			(.path | type == "string") and (.digest | type == "string")))' <<<"$json" >/dev/null || return 1
	wallpaper_transaction_id_is_safe "$(jq -r '.transaction_id' <<<"$json")" || return 1
	wallpaper_timestamp_is_strict "$(jq -r '.activated_at' <<<"$json")" || return 1
	while IFS=$'\t' read -r path digest; do
		wallpaper_relative_target_is_safe "$path" "$digest" || return 1
		[[ -z $previous || $path > "$previous" ]] || return 1
		previous=$path
	done < <(jq -r '.targets[] | [.path,.digest] | @tsv' <<<"$json")
	while IFS= read -r directory; do wallpaper_slug_is_safe "$directory" || return 1; done < <(jq -r '.created_directories[]' <<<"$json")
}

wallpaper_validate_deployment_pending() {
	local json=$1 transaction path action prior_present desired_present backup digest mode identity source_identity backup_identity active_present active_backup active_digest directory
	local phase stage stage_identity parent active_stage next_active active_background expected_targets config_home target quarantine index=0 created expected rollback_quarantine source_digest
	jq -e --argjson schema "$WALLPAPER_SCHEMA_VERSION" '
		type == "object" and keys == ["active_background","active_stage","changes","created_at","created_directories","created_root","domain","kind","live_root","next_active","observed_targets","operation","parents","phase","prior_active","schema_version","transaction_id"] and
		.schema_version == $schema and .kind == "pending" and .domain == "deployment" and
		(.operation == "apply" or .operation == "remove") and (.transaction_id | type == "string") and
		(.phase == "preparing" or .phase == "prepared" or .phase == "complete" or .phase == "rolled_back") and
		(.created_at | type == "string" and length > 0) and (.live_root | type == "string") and
		(.created_root | type == "boolean") and (.created_directories | type == "array" and . == sort and length == (unique | length)) and
		(.parents | type == "array" and length > 0 and all(.[]; type == "object" and keys == ["created","identity","path"] and (.path | type == "string") and (.created | type == "boolean"))) and
		(.observed_targets | type == "array" and all(.[]; type == "object" and keys == ["identity","path","source_digest","source_identity"] and
			(.path | type == "string") and (.source_digest | type == "string"))) and
		(.active_background | type == "object" and keys == ["identity","path"] and (.path | type == "string")) and
		(.active_stage == null or (.active_stage | type == "object" and keys == ["identity","path","rollback_quarantine_path"])) and
		(.next_active == null or (.next_active | type == "object")) and
		(.prior_active | type == "object" and keys == ["backup_identity","backup_path","digest","identity","present","quarantine_path"] and (.present | type == "boolean")) and
		(.changes | type == "array" and length > 0 and all(.[]; type == "object" and keys == ["action","desired","path","prior","quarantine_path"] and
			(.action == "add" or .action == "adopt" or .action == "remove") and (.path | type == "string") and
			(.prior | type == "object" and keys == ["backup_identity","backup_path","digest","identity","mode","present"] and (.present | type == "boolean")) and
			(.desired | type == "object" and keys == ["digest","identity","present","source_identity","stage_identity","stage_path"] and (.present | type == "boolean")) and
			(.quarantine_path == null or (.quarantine_path | type == "string"))))' <<<"$json" >/dev/null || return 1
	transaction=$(jq -r '.transaction_id' <<<"$json")
	phase=$(jq -r '.phase' <<<"$json")
	wallpaper_transaction_id_is_safe "$transaction" || return 1
	wallpaper_timestamp_is_strict "$(jq -r '.created_at' <<<"$json")" || return 1
	[[ $(jq -r '.live_root' <<<"$json") == "$WALLPAPER_LIVE_ROOT" ]] || return 1
	while IFS= read -r directory; do wallpaper_slug_is_safe "$directory" || return 1; done < <(jq -r '.created_directories[]' <<<"$json")
	while IFS=$'\t' read -r path action; do
		wallpaper_relative_target_is_safe "$path" || return 1
		prior_present=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.present' <<<"$json")
		desired_present=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .desired.present' <<<"$json")
		if [[ $prior_present == true ]]; then
			backup=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.backup_path' <<<"$json")
			digest=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.digest' <<<"$json")
			mode=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .prior.mode' <<<"$json")
			identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .prior.identity' <<<"$json")
			backup_identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .prior.backup_identity' <<<"$json")
			[[ $digest =~ ^[0-9a-f]{64}$ && $mode =~ ^[0-7]{3,4}$ ]] || return 1
			wallpaper_live_identity_json_is_valid "$identity" "$digest" || return 1
			[[ $backup == null && $backup_identity == null ]] || return 1
		else
			[[ $(jq -r --arg path "$path" '.changes[] | select(.path == $path) | (.prior.digest == null and .prior.mode == null and .prior.backup_path == null and .prior.identity == null and .prior.backup_identity == null)' <<<"$json") == true ]] || return 1
		fi
		if [[ $desired_present == true ]]; then
			digest=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .desired.digest' <<<"$json")
			wallpaper_relative_target_is_safe "$path" "$digest" || return 1
			source_identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .desired.source_identity' <<<"$json")
			wallpaper_identity_json_is_valid "$source_identity" '' "$digest" || return 1
			identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .desired.identity' <<<"$json")
			stage=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .desired.stage_path' <<<"$json")
			stage_identity=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .desired.stage_identity' <<<"$json")
			if [[ $action == add ]]; then
				[[ $identity == null && $stage == "$WALLPAPER_LIVE_ROOT/${path%/*}/.dotfiles-wallpaper-$transaction-$index.stage" ]] || return 1
				if [[ $stage_identity != null ]]; then wallpaper_identity_json_is_valid "$stage_identity" 0644 "$digest" || return 1; fi
				if [[ -e $stage || -L $stage ]]; then
					if [[ $stage_identity == null ]]; then wallpaper_regular_file_is_exact "$stage" "$digest" 0644; else wallpaper_identity_matches "$stage" "$stage_identity"; fi || return 1
				fi
				[[ $phase != prepared || $stage_identity != null ]] || return 1
			else
				wallpaper_live_identity_json_is_valid "$identity" "$digest" || return 1
				[[ $stage == null && $stage_identity == null ]] || return 1
			fi
		else
			[[ $(jq -r --arg path "$path" '.changes[] | select(.path == $path) | (.desired.digest == null and .desired.identity == null and .desired.source_identity == null and .desired.stage_path == null and .desired.stage_identity == null)' <<<"$json") == true ]] || return 1
		fi
		case $action:$prior_present:$desired_present in
			add:false:true|adopt:true:true|remove:true:false) ;;
			*) return 1 ;;
		esac
		quarantine=$(jq -r --arg path "$path" '.changes[] | select(.path == $path) | .quarantine_path' <<<"$json")
		if [[ $action == adopt ]]; then
			[[ $quarantine == null ]] || return 1
		else
			[[ $quarantine == "$WALLPAPER_LIVE_ROOT/${path%/*}/.dotfiles-wallpaper-$transaction-$index.quarantine" ]] || return 1
			if [[ $phase == preparing ]]; then
				wallpaper_path_is_absent "$quarantine" || return 1
			elif [[ -e $quarantine || -L $quarantine ]]; then
				if [[ $prior_present == true ]]; then expected=$(jq -c --arg path "$path" '.changes[] | select(.path == $path) | .prior.identity' <<<"$json"); else expected=$stage_identity; fi
				wallpaper_live_identity_matches_exchange "$quarantine" "$expected" || return 1
			fi
		fi
		index=$((index + 1))
	done < <(jq -r '.changes[] | [.path,.action] | @tsv' <<<"$json")
	[[ $(jq -r '[.changes[].path] | length == (unique | length)' <<<"$json") == true ]] || return 1
	active_present=$(jq -r '.prior_active.present' <<<"$json")
	if [[ $active_present == true ]]; then
		active_backup=$(jq -r '.prior_active.backup_path' <<<"$json")
		active_digest=$(jq -r '.prior_active.digest' <<<"$json")
		identity=$(jq -c '.prior_active.identity' <<<"$json")
		backup_identity=$(jq -c '.prior_active.backup_identity' <<<"$json")
		wallpaper_backup_path_is_well_formed "$active_backup" "$transaction" || return 1
		wallpaper_identity_json_is_valid "$identity" 0600 "$active_digest" || return 1
		if [[ $backup_identity != null ]]; then wallpaper_identity_json_is_valid "$backup_identity" 0600 "$active_digest" || return 1; fi
		if [[ -e $active_backup || -L $active_backup ]]; then
			wallpaper_backup_path_is_safe "$active_backup" "$transaction" && wallpaper_state_file_is_secure "$active_backup" || return 1
			if [[ $backup_identity == null ]]; then wallpaper_regular_file_is_exact "$active_backup" "$active_digest" 0600; else wallpaper_identity_matches "$active_backup" "$backup_identity"; fi || return 1
			wallpaper_validate_active_json "$(wallpaper_read_file_stable "$active_backup")" || return 1
		else
			[[ $phase != prepared ]] || return 1
		fi
		[[ $phase != prepared || $backup_identity != null ]] || return 1
		quarantine=$(jq -r '.prior_active.quarantine_path' <<<"$json")
		[[ $quarantine == "$WALLPAPER_STATE_CANONICAL_ROOT/.active-$transaction.quarantine" ]] || return 1
		if [[ $phase == preparing ]]; then wallpaper_path_is_absent "$quarantine" || return 1
		elif [[ -e $quarantine || -L $quarantine ]]; then wallpaper_identity_matches_exchange "$quarantine" "$identity" || return 1; fi
	else
		[[ $(jq -r '.prior_active.digest == null and .prior_active.backup_path == null and .prior_active.identity == null and .prior_active.backup_identity == null and .prior_active.quarantine_path == null' <<<"$json") == true ]] || return 1
	fi
	while IFS= read -r parent; do
		case $parent in
			"${XDG_CONFIG_HOME:-$HOME/.config}"|"${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"|"$WALLPAPER_LIVE_ROOT"|"$WALLPAPER_LIVE_ROOT"/*|"$WALLPAPER_STATE_CANONICAL_ROOT"|"$WALLPAPER_STATE_CANONICAL_ROOT/backups"|"$WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction") ;;
			*) return 1 ;;
		esac
		identity=$(jq -c --arg path "$parent" '.parents[] | select(.path == $path) | .identity' <<<"$json")
		created=$(jq -r --arg path "$parent" '.parents[] | select(.path == $path) | .created' <<<"$json")
		if [[ $identity == null ]]; then
			[[ $phase == preparing && $created == true ]] || return 1
			if [[ -e $parent || -L $parent ]]; then
				[[ -d $parent && ! -L $parent && $(readlink -f -- "$parent") == "$parent" ]] || return 1
				case $parent in "$WALLPAPER_STATE_CANONICAL_ROOT"/*) wallpaper_private_directory_is_secure "$parent" || return 1 ;; esac
			fi
		else
			wallpaper_lstat_identity_json_is_valid "$identity" directory || return 1
			if [[ -e $parent || -L $parent ]]; then
				wallpaper_object_identity_matches "$parent" "$identity" || return 1
			elif [[ $phase == complete && ( $parent == "$WALLPAPER_LIVE_ROOT" || $parent == "$WALLPAPER_LIVE_ROOT/"* ) ]]; then
				:
			elif [[ $created != true || $phase == prepared ]]; then return 1
			fi
		fi
	done < <(jq -r '.parents[].path' <<<"$json")
	[[ $(jq -r '[.parents[].path] | length == (unique | length)' <<<"$json") == true ]] || return 1
	config_home=${XDG_CONFIG_HOME:-$HOME/.config}
	for parent in "$config_home" "$config_home/omarchy" "$WALLPAPER_LIVE_ROOT" "$WALLPAPER_STATE_CANONICAL_ROOT" "$WALLPAPER_STATE_CANONICAL_ROOT/backups" "$WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction"; do
		wallpaper_pending_has_parent "$json" "$parent" || return 1
	done
	while IFS= read -r path; do
		target=$(wallpaper_live_target_path "$path") || return 1
		wallpaper_pending_has_parent "$json" "${target%/*}" || return 1
	done < <(jq -r '.changes[].path' <<<"$json")
	[[ $(jq -r '[.changes[].desired.stage_path | select(. != null)] | length == (unique | length)' <<<"$json") == true ]] || return 1
	while IFS= read -r path; do
		source_digest=$(jq -r --arg path "$path" '.observed_targets[] | select(.path == $path) | .source_digest' <<<"$json")
		wallpaper_relative_target_is_safe "$path" "$source_digest" || return 1
		identity=$(jq -c --arg path "$path" '.observed_targets[] | select(.path == $path) | .identity' <<<"$json")
		wallpaper_live_identity_json_is_valid "$identity" "$source_digest" || return 1
		source_identity=$(jq -c --arg path "$path" '.observed_targets[] | select(.path == $path) | .source_identity' <<<"$json")
		wallpaper_identity_json_is_valid "$source_identity" '' "$source_digest" || return 1
	done < <(jq -r '.observed_targets[].path' <<<"$json")
	[[ $(jq -r '[.observed_targets[].path] | length == (unique | length)' <<<"$json") == true ]] || return 1
	active_background=$(wallpaper_active_background_link) || return 1
	[[ $(jq -r '.active_background.path' <<<"$json") == "$active_background" ]] || return 1
	identity=$(jq -c '.active_background.identity' <<<"$json")
	[[ $identity == null ]] || wallpaper_lstat_identity_json_is_valid "$identity" symlink || return 1
	active_stage=$(jq -c '.active_stage' <<<"$json") next_active=$(jq -c '.next_active' <<<"$json")
	expected_targets=$(jq -c '[
		(.changes[] | select(.desired.present) | {path,digest:.desired.digest}),
		(.observed_targets[] | {path,digest:.source_digest})
	] | sort_by(.path)' <<<"$json") || return 1
	[[ $(jq -r 'length == (unique_by(.path) | length)' <<<"$expected_targets") == true ]] || return 1
	if [[ $active_stage == null ]]; then
		[[ $next_active == null && $(jq 'length' <<<"$expected_targets") -eq 0 ]] || return 1
	else
		stage=$(jq -r '.path' <<<"$active_stage") stage_identity=$(jq -c '.identity' <<<"$active_stage")
		rollback_quarantine=$(jq -r '.rollback_quarantine_path' <<<"$active_stage")
		[[ $stage == "$WALLPAPER_STATE_CANONICAL_ROOT/.active-$transaction.stage" && $rollback_quarantine == "$WALLPAPER_STATE_CANONICAL_ROOT/.active-$transaction.rollback-quarantine" ]] || return 1
		if [[ $stage_identity != null ]]; then wallpaper_identity_json_is_valid "$stage_identity" 0600 || return 1; fi
		[[ $next_active != null ]] && wallpaper_validate_active_json "$next_active" || return 1
		digest=$(printf '%s\n' "$next_active" | sha256sum | { read -r value _; printf '%s' "$value"; }) || return 1
		if [[ $stage_identity != null ]]; then [[ $(jq -r '.digest' <<<"$stage_identity") == "$digest" ]] || return 1; fi
		if [[ -e $stage || -L $stage ]]; then
			if [[ $stage_identity == null ]]; then wallpaper_regular_file_is_exact "$stage" "$digest" 0600; else wallpaper_identity_matches "$stage" "$stage_identity"; fi || return 1
		fi
		[[ $phase != prepared || $stage_identity != null ]] || return 1
		if [[ $phase == preparing ]]; then wallpaper_path_is_absent "$rollback_quarantine" || return 1
		elif [[ -e $rollback_quarantine || -L $rollback_quarantine ]]; then wallpaper_identity_matches_exchange "$rollback_quarantine" "$stage_identity" || return 1; fi
		[[ $(jq -Sc '.targets' <<<"$next_active") == "$(jq -Sc . <<<"$expected_targets")" ]] || return 1
	fi
	[[ $(jq -r '[.changes[].desired.stage_path,.changes[].quarantine_path,.prior_active.quarantine_path,.active_stage.path,.active_stage.rollback_quarantine_path | select(. != null)] | length == (unique | length)' <<<"$json") == true ]]
}

wallpaper_live_target_path() {
	local relative=$1
	wallpaper_relative_target_is_safe "$relative" || return 1
	printf '%s/%s\n' "$WALLPAPER_LIVE_ROOT" "$relative"
}

wallpaper_validate_live_ancestor() {
	local path=$1 canonical
	canonical=$(readlink -m -- "$path") || return 1
	if [[ $canonical != "$path" ]]; then
		WALLPAPER_PLAN_ERROR="live wallpaper parent must be a real directory path without symbolic links: $path"
		return 1
	fi
	[[ -e $path || -L $path ]] || return 0
	if [[ ! -d $path || -L $path ]]; then
		WALLPAPER_PLAN_ERROR="live wallpaper parent must be a real directory: $path"
		return 1
	fi
}

wallpaper_validate_live_parent() {
	local relative=$1 config_home omarchy_root theme_root theme
	config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
	omarchy_root="$config_home/omarchy"
	theme=${relative%%/*}
	theme_root="$WALLPAPER_LIVE_ROOT/$theme"
	wallpaper_validate_live_ancestor "$config_home" || return 1
	wallpaper_validate_live_ancestor "$omarchy_root" || return 1
	wallpaper_validate_live_ancestor "$WALLPAPER_LIVE_ROOT" || return 1
	wallpaper_validate_live_ancestor "$theme_root"
}

wallpaper_build_desired_inventory() {
	local file relative digest identity item desired='[]'
	wallpaper_validate_library_quiet || {
		WALLPAPER_PLAN_ERROR="invalid Wallpaper library: $WALLPAPER_LIBRARY_ERROR"
		return 1
	}
	if [[ -d $WALLPAPER_LIBRARY_ROOT && ! -L $WALLPAPER_LIBRARY_ROOT ]]; then
		while IFS= read -r -d '' file; do
			relative=${file#"$WALLPAPER_LIBRARY_ROOT"/}
			digest=${file##*/} digest=${digest%%.*}
			identity=$(wallpaper_file_identity "$file") || return 1
			item=$(jq -cn --arg path "$relative" --arg digest "$digest" --argjson source_identity "$identity" \
				'{path:$path,digest:$digest,source_identity:$source_identity}') || return 1
			desired=$(jq -c --argjson item "$item" '. + [$item]' <<<"$desired") || return 1
		done < <(find "$WALLPAPER_LIBRARY_ROOT" -mindepth 2 -maxdepth 2 -type f -print0 | sort -z)
	fi
	WALLPAPER_DESIRED_JSON=$desired
}

wallpaper_receipt_target_is_exact() {
	local relative=$1 digest=$2 target
	target=$(wallpaper_live_target_path "$relative") || return 1
	[[ -f $target && ! -L $target ]] && wallpaper_regular_live_file_is_exact "$target" "$digest"
}

wallpaper_active_background_target() {
	local link raw
	link=$(wallpaper_active_background_link) || return 1
	[[ -L $link ]] || return 1
	raw=$(readlink -- "$link") || return 1
	if [[ $raw == /* ]]; then readlink -m -- "$raw"; else readlink -m -- "${link%/*}/$raw"; fi
}

wallpaper_deletion_is_active() {
	local target=$1 active
	active=$(wallpaper_active_background_target 2>/dev/null) || return 1
	[[ $(readlink -m -- "$target") == "$active" ]]
}

wallpaper_verify_active_background_evidence() {
	local pending=$1 path expected actual
	path=$(jq -r '.active_background.path' <<<"$pending") || return 1
	expected=$(jq -c '.active_background.identity' <<<"$pending") || return 1
	if [[ $expected == null ]]; then
		wallpaper_path_is_absent "$path"
	else
		actual=$(wallpaper_files lstat "$path") || return 1
		[[ $(jq -Sc . <<<"$actual") == "$(jq -Sc . <<<"$expected")" ]]
	fi
}

wallpaper_path_identity_snapshot() {
	local path=$1 metadata
	if [[ ! -e $path && ! -L $path ]]; then
		printf 'absent\n'
		return 0
	fi
	metadata=$(wallpaper_files lstat "$path") || return 1
	if [[ $(jq -r '.type' <<<"$metadata") == regular ]]; then
		wallpaper_file_identity "$path"
	else
		printf '%s\n' "$metadata"
	fi
}

wallpaper_live_path_identity_snapshot() {
	local path=$1 metadata
	if [[ ! -e $path && ! -L $path ]]; then
		printf 'absent\n'
		return 0
	fi
	metadata=$(wallpaper_files lstat "$path") || return 1
	if [[ $(jq -r '.type' <<<"$metadata") == regular ]]; then
		wallpaper_live_file_identity "$path"
	else
		printf '%s\n' "$metadata"
	fi
}

wallpaper_deployment_snapshot() {
	local json=$1 item relative digest target parent snapshot='' active_link
	snapshot+="active|$(wallpaper_path_identity_snapshot "$WALLPAPER_ACTIVE_RECEIPT")" || return 1
	snapshot+=';'
	while IFS= read -r item; do
		relative=$(jq -r '.path' <<<"$item") digest=$(jq -r '.digest' <<<"$item")
		target=$(wallpaper_live_target_path "$relative") || return 1
		parent=${target%/*}
		snapshot+="parent|$parent|$(wallpaper_path_identity_snapshot "$parent");" || return 1
		snapshot+="target|$relative|$(wallpaper_live_path_identity_snapshot "$target");" || return 1
	done < <(jq -c 'sort_by(.path) | .[]' <<<"$json")
	active_link=$(wallpaper_active_background_link)
	snapshot+="current|$(wallpaper_path_identity_snapshot "$active_link");" || return 1
	printf '%s\n' "$snapshot"
}

wallpaper_build_apply_plan() {
	local item relative digest target source action change plan='[]' combined identity
	declare -A active_digest=() desired_digest=()
	WALLPAPER_PLAN_ERROR=''
	if [[ -n $WALLPAPER_ACTIVE_JSON ]]; then
		while IFS=$'\t' read -r relative digest; do active_digest[$relative]=$digest; done \
			< <(jq -r '.targets[] | [.path,.digest] | @tsv' <<<"$WALLPAPER_ACTIVE_JSON")
	fi
	while IFS=$'\t' read -r relative digest; do desired_digest[$relative]=$digest; done \
		< <(jq -r '.[] | [.path,.digest] | @tsv' <<<"$WALLPAPER_DESIRED_JSON")
	for relative in "${!active_digest[@]}"; do
		digest=${active_digest[$relative]}
		wallpaper_validate_live_parent "$relative" || return 1
		target=$(wallpaper_live_target_path "$relative") || return 1
		if [[ ! -f $target || -L $target ]]; then
			WALLPAPER_PLAN_ERROR="receipt-owned target changed, disappeared, or is not a regular file: $target"
			return 1
		fi
		if ! identity=$(wallpaper_live_file_identity "$target" 2>&1) || ! wallpaper_live_identity_json_is_valid "$identity" "$digest"; then
			WALLPAPER_PLAN_ERROR="receipt-owned target changed; expected a regular non-symlink file with the recorded bytes: $target${identity:+ ($identity)}"
			return 1
		fi
		source="$WALLPAPER_LIBRARY_ROOT/$relative"
		if [[ -e $source && ! -L $source ]] && ! wallpaper_live_file_matches_source "$source" "$target"; then
			WALLPAPER_PLAN_ERROR="receipt-owned target bytes no longer match the repository source: $target"
			return 1
		fi
	done
	if ((${#desired_digest[@]} > 0)); then
		mapfile -t WALLPAPER_SORTED_PATHS < <(printf '%s\n' "${!desired_digest[@]}" | LC_ALL=C sort)
	else
		WALLPAPER_SORTED_PATHS=()
	fi
	for relative in "${WALLPAPER_SORTED_PATHS[@]}"; do
		digest=${desired_digest[$relative]}
		[[ -n ${active_digest[$relative]+present} ]] && continue
		wallpaper_validate_live_parent "$relative" || return 1
		target=$(wallpaper_live_target_path "$relative") || return 1
		if [[ -e $target || -L $target ]]; then
			if [[ ! -f $target || -L $target ]]; then
				WALLPAPER_PLAN_ERROR="unowned target conflict; exact-byte adoption is unavailable: $target"
				return 1
			fi
			if ! identity=$(wallpaper_live_file_identity "$target" 2>&1) || ! wallpaper_live_identity_json_is_valid "$identity" "$digest" || \
				! wallpaper_live_file_matches_source "$WALLPAPER_LIBRARY_ROOT/$relative" "$target"; then
				WALLPAPER_PLAN_ERROR="unowned target conflict; adoption requires a regular non-symlink file with the exact repository bytes: $target${identity:+ ($identity)}"
				return 1
			fi
			action=adopt
		else
			action=add
		fi
		change=$(jq -cn --arg action "$action" --arg path "$relative" --arg digest "$digest" '{action:$action,path:$path,digest:$digest}') || return 1
		plan=$(jq -c --argjson change "$change" '. + [$change]' <<<"$plan") || return 1
	done
	if ((${#active_digest[@]} > 0)); then
		mapfile -t WALLPAPER_SORTED_PATHS < <(printf '%s\n' "${!active_digest[@]}" | LC_ALL=C sort)
	else
		WALLPAPER_SORTED_PATHS=()
	fi
	for relative in "${WALLPAPER_SORTED_PATHS[@]}"; do
		[[ -z ${desired_digest[$relative]+present} ]] || continue
		digest=${active_digest[$relative]} target=$(wallpaper_live_target_path "$relative") || return 1
		if wallpaper_deletion_is_active "$target"; then
			WALLPAPER_PLAN_ERROR="planned deletion is the current active background: $target"
			return 1
		fi
		change=$(jq -cn --arg path "$relative" --arg digest "$digest" '{action:"remove",path:$path,digest:$digest}') || return 1
		plan=$(jq -c --argjson change "$change" '. + [$change]' <<<"$plan") || return 1
	done
	WALLPAPER_PLAN_JSON=$plan
	combined=$(jq -cn --argjson desired "$WALLPAPER_DESIRED_JSON" --argjson active "${WALLPAPER_ACTIVE_JSON:-null}" '$desired + (($active.targets // [])) | unique_by(.path)') || return 1
	WALLPAPER_DEPLOYMENT_FINGERPRINT=$(wallpaper_deployment_snapshot "$combined") || return 1
}

wallpaper_build_remove_plan() {
	local relative digest target change plan='[]' identity
	WALLPAPER_PLAN_ERROR=''
	[[ -n $WALLPAPER_ACTIVE_JSON ]] || { WALLPAPER_PLAN_JSON='[]'; WALLPAPER_DEPLOYMENT_FINGERPRINT=$(wallpaper_deployment_snapshot '[]'); return 0; }
	while IFS=$'\t' read -r relative digest; do
		wallpaper_validate_live_parent "$relative" || return 1
		target=$(wallpaper_live_target_path "$relative") || return 1
		if [[ ! -f $target || -L $target ]]; then
			WALLPAPER_PLAN_ERROR="receipt-owned target changed, disappeared, or is not a regular file: $target"
			return 1
		fi
		if ! identity=$(wallpaper_live_file_identity "$target" 2>&1) || ! wallpaper_live_identity_json_is_valid "$identity" "$digest"; then
			WALLPAPER_PLAN_ERROR="receipt-owned target changed; expected a regular non-symlink file with the recorded bytes: $target${identity:+ ($identity)}"
			return 1
		fi
		if wallpaper_deletion_is_active "$target"; then
			WALLPAPER_PLAN_ERROR="planned deletion is the current active background: $target"
			return 1
		fi
		change=$(jq -cn --arg path "$relative" --arg digest "$digest" '{action:"remove",path:$path,digest:$digest}') || return 1
		plan=$(jq -c --argjson change "$change" '. + [$change]' <<<"$plan") || return 1
	done < <(jq -r '.targets[] | [.path,.digest] | @tsv' <<<"$WALLPAPER_ACTIVE_JSON")
	WALLPAPER_PLAN_JSON=$plan
	WALLPAPER_DEPLOYMENT_FINGERPRINT=$(wallpaper_deployment_snapshot "$(jq -c '.targets' <<<"$WALLPAPER_ACTIVE_JSON")") || return 1
}

wallpaper_missing_theme_slugs() {
	local theme slug
	declare -A installed=() reported=()
	wallpaper_discover_themes || return 1
	for slug in "${WALLPAPER_THEME_SLUGS[@]}"; do installed[$slug]=1; done
	while IFS= read -r theme; do
		[[ -n ${installed[$theme]+present} || -n ${reported[$theme]+present} ]] && continue
		printf '%s\n' "$theme"
		reported[$theme]=1
	done < <(jq -r '.[].path | split("/")[0]' <<<"$WALLPAPER_DESIRED_JSON")
}

wallpaper_print_apply_plan() {
	local item action relative target missing any_missing=false
	printf 'Plan: converge the repository Wallpaper library to regular Omarchy background copies\n'
	while IFS= read -r item; do
		action=$(jq -r '.action' <<<"$item") relative=$(jq -r '.path' <<<"$item") target=$(wallpaper_live_target_path "$relative")
		case $action in
			add) printf 'Add regular target: %s\n' "$target" ;;
			adopt) printf 'Adopt exact unowned target: %s\n' "$target" ;;
			remove) printf 'Remove stale receipt-owned target: %s\n' "$target" ;;
		esac
	done < <(jq -c '.[]' <<<"$WALLPAPER_PLAN_JSON")
	while IFS= read -r missing; do
		[[ -n $missing ]] || continue
		printf 'dormant assignment: theme %s is not installed locally; its background is still deployed.\n' "$missing"
		any_missing=true
	done < <(wallpaper_missing_theme_slugs)
	[[ $any_missing == true ]] || printf 'Dormant assignments: none\n'
	printf 'Unrelated backgrounds and theme state are preserved.\n'
}

wallpaper_prepare_next_directory_inventory() {
	local item action relative theme directory created='[]' prior_root=false prior_directories='[]'
	if [[ -n $WALLPAPER_ACTIVE_JSON ]]; then
		prior_root=$(jq -r '.created_root' <<<"$WALLPAPER_ACTIVE_JSON")
		prior_directories=$(jq -c '.created_directories' <<<"$WALLPAPER_ACTIVE_JSON")
	fi
	WALLPAPER_NEXT_CREATED_ROOT=false
	if [[ $prior_root == true ]] && jq -e 'length > 0' <<<"$WALLPAPER_DESIRED_JSON" >/dev/null; then WALLPAPER_NEXT_CREATED_ROOT=true; fi
	if [[ ! -e $WALLPAPER_LIVE_ROOT && ! -L $WALLPAPER_LIVE_ROOT ]] && jq -e 'any(.[]; .action == "add")' <<<"$WALLPAPER_PLAN_JSON" >/dev/null; then
		WALLPAPER_NEXT_CREATED_ROOT=true
	fi
	while IFS= read -r theme; do
		jq -e --arg theme "$theme" 'any(.[]; (.path | split("/")[0]) == $theme)' <<<"$WALLPAPER_DESIRED_JSON" >/dev/null || continue
		created=$(jq -c --arg theme "$theme" '. + [$theme] | unique | sort' <<<"$created") || return 1
	done < <(jq -r '.[]' <<<"$prior_directories")
	while IFS= read -r item; do
		action=$(jq -r '.action' <<<"$item")
		[[ $action == add ]] || continue
		relative=$(jq -r '.path' <<<"$item") theme=${relative%%/*} directory="$WALLPAPER_LIVE_ROOT/$theme"
		if [[ ! -e $directory && ! -L $directory ]]; then
			created=$(jq -c --arg theme "$theme" '. + [$theme] | unique | sort' <<<"$created") || return 1
		fi
	done < <(jq -c '.[]' <<<"$WALLPAPER_PLAN_JSON")
	WALLPAPER_NEXT_CREATED_DIRECTORIES=$created
}

wallpaper_begin_deployment_transaction() {
	local operation=$1 transaction=$2 next_active=${3-null} backup_root changes='[]' item action relative digest target prior desired backup mode change
	local prior_active active_backup active_digest active_identity active_backup_identity identity source_identity backup_identity
	local created_at pending newly_created='[]' created_root=false theme directory stage stage_identity active_stage=null active_link active_background parents observed='[]' observed_item source_digest
	local quarantine index=0 result updated rollback_quarantine
	local -a parent_paths=()
	wallpaper_assert_locked_state_root || return 1
	backup_root="$WALLPAPER_STATE_CANONICAL_ROOT/backups/$transaction"
	if [[ -n $WALLPAPER_ACTIVE_JSON ]]; then
		active_backup="$backup_root/active.json"
		active_identity=$(wallpaper_file_identity "$WALLPAPER_ACTIVE_RECEIPT") || return 1
		active_digest=$(jq -er '.digest' <<<"$active_identity") || return 1
		prior_active=$(jq -cn --arg digest "$active_digest" --arg backup "$active_backup" --argjson identity "$active_identity" \
			--arg quarantine "$WALLPAPER_STATE_CANONICAL_ROOT/.active-$transaction.quarantine" \
			'{present:true,digest:$digest,identity:$identity,backup_path:$backup,backup_identity:null,quarantine_path:$quarantine}') || return 1
	else
		prior_active='{"present":false,"digest":null,"identity":null,"backup_path":null,"backup_identity":null,"quarantine_path":null}'
	fi
	if [[ ! -e $WALLPAPER_LIVE_ROOT && ! -L $WALLPAPER_LIVE_ROOT ]] && jq -e 'any(.[]; .action == "add")' <<<"$WALLPAPER_PLAN_JSON" >/dev/null; then created_root=true; fi
	while IFS= read -r item; do
		action=$(jq -r '.action' <<<"$item") relative=$(jq -r '.path' <<<"$item") digest=$(jq -r '.digest' <<<"$item")
		if [[ $action != remove ]]; then
			source_identity=$(jq -c --arg path "$relative" '.[] | select(.path == $path) | .source_identity' <<<"$WALLPAPER_DESIRED_JSON") || return 1
		else
			source_identity=null
		fi
		target=$(wallpaper_live_target_path "$relative") || return 1
		if [[ -e $target || -L $target ]]; then
			[[ -f $target && ! -L $target ]] || return 1
			identity=$(wallpaper_live_file_identity "$target") || return 1
			mode=$(jq -er '.mode' <<<"$identity") || return 1
			prior=$(jq -cn --arg digest "$digest" --arg mode "$mode" --argjson identity "$identity" \
				'{present:true,digest:$digest,mode:$mode,identity:$identity,backup_path:null,backup_identity:null}') || return 1
		else
			prior='{"present":false,"digest":null,"mode":null,"identity":null,"backup_path":null,"backup_identity":null}'
		fi
		if [[ $action == remove ]]; then
			desired='{"present":false,"digest":null,"source_identity":null,"identity":null,"stage_path":null,"stage_identity":null}'
		elif [[ $action == adopt ]]; then
			desired=$(jq -cn --arg digest "$digest" --argjson source_identity "$source_identity" --argjson identity "$identity" \
				'{present:true,digest:$digest,source_identity:$source_identity,identity:$identity,stage_path:null,stage_identity:null}') || return 1
		else
			stage="$WALLPAPER_LIVE_ROOT/${relative%/*}/.dotfiles-wallpaper-$transaction-$index.stage"
			desired=$(jq -cn --arg digest "$digest" --arg stage "$stage" --argjson source_identity "$source_identity" \
				'{present:true,digest:$digest,source_identity:$source_identity,identity:null,stage_path:$stage,stage_identity:null}') || return 1
		fi
		if [[ $action == adopt ]]; then quarantine=null; else quarantine=$(jq -Rn --arg value "$WALLPAPER_LIVE_ROOT/${relative%/*}/.dotfiles-wallpaper-$transaction-$index.quarantine" '$value'); fi
		change=$(jq -cn --arg action "$action" --arg path "$relative" --argjson quarantine "$quarantine" --argjson prior "$prior" --argjson desired "$desired" \
			'{action:$action,path:$path,prior:$prior,desired:$desired,quarantine_path:$quarantine}') || return 1
		changes=$(jq -c --argjson change "$change" '. + [$change]' <<<"$changes") || return 1
		if [[ $action == add ]]; then
			theme=${relative%%/*} directory="$WALLPAPER_LIVE_ROOT/$theme"
			if [[ ! -e $directory && ! -L $directory ]]; then newly_created=$(jq -c --arg theme "$theme" '. + [$theme] | unique | sort' <<<"$newly_created") || return 1; fi
		fi
		index=$((index + 1))
	done < <(jq -c '.[]' <<<"$WALLPAPER_PLAN_JSON")
	if [[ $next_active != null ]]; then
		stage="$WALLPAPER_STATE_CANONICAL_ROOT/.active-$transaction.stage"
		rollback_quarantine="$WALLPAPER_STATE_CANONICAL_ROOT/.active-$transaction.rollback-quarantine"
		active_stage=$(jq -cn --arg path "$stage" --arg rollback "$rollback_quarantine" \
			'{path:$path,identity:null,rollback_quarantine_path:$rollback}') || return 1
	fi
	while IFS=$'\t' read -r relative digest; do
		jq -e --arg path "$relative" 'any(.[]; .path == $path)' <<<"$WALLPAPER_PLAN_JSON" >/dev/null && continue
		target=$(wallpaper_live_target_path "$relative") || return 1
		identity=$(wallpaper_live_file_identity "$target") || return 1
		source_digest=$(jq -r --arg path "$relative" '.[] | select(.path == $path) | .digest' <<<"$WALLPAPER_DESIRED_JSON") || return 1
		source_identity=$(jq -c --arg path "$relative" '.[] | select(.path == $path) | .source_identity' <<<"$WALLPAPER_DESIRED_JSON") || return 1
		[[ -n $source_digest && $source_identity != null ]] || return 1
		observed_item=$(jq -cn --arg path "$relative" --arg digest "$source_digest" --argjson identity "$identity" --argjson source_identity "$source_identity" \
			'{path:$path,identity:$identity,source_digest:$digest,source_identity:$source_identity}') || return 1
		observed=$(jq -c --argjson item "$observed_item" '. + [$item]' <<<"$observed") || return 1
	done < <(if [[ -n $WALLPAPER_ACTIVE_JSON ]]; then jq -r '.targets[] | [.path,.digest] | @tsv' <<<"$WALLPAPER_ACTIVE_JSON"; fi)
	while IFS= read -r relative; do
		target=$(wallpaper_live_target_path "$relative") || return 1
		parent_paths+=("${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy" "$WALLPAPER_LIVE_ROOT" "${target%/*}")
	done < <(jq -r '.[].path' <<<"$changes")
	parent_paths+=("$WALLPAPER_STATE_CANONICAL_ROOT" "$WALLPAPER_STATE_CANONICAL_ROOT/backups" "$backup_root")
	parents=$(wallpaper_parent_intent_evidence "${parent_paths[@]}") || return 1
	active_link=$(wallpaper_active_background_link) || return 1
	if wallpaper_path_is_absent "$active_link"; then
		active_background=$(jq -cn --arg path "$active_link" '{path:$path,identity:null}') || return 1
	else
		identity=$(wallpaper_files lstat "$active_link") || return 1
		wallpaper_lstat_identity_json_is_valid "$identity" symlink || return 1
		active_background=$(jq -cn --arg path "$active_link" --argjson identity "$identity" '{path:$path,identity:$identity}') || return 1
	fi
	created_at=$(wallpaper_now) || return 1
	pending=$(jq -cn --argjson schema "$WALLPAPER_SCHEMA_VERSION" --arg operation "$operation" --arg transaction "$transaction" \
		--arg created "$created_at" --arg live "$WALLPAPER_LIVE_ROOT" --argjson prior_active "$prior_active" --argjson changes "$changes" \
		--argjson created_root "$created_root" --argjson directories "$newly_created" --argjson parents "$parents" --argjson observed "$observed" \
		--argjson active_background "$active_background" --argjson active_stage "$active_stage" --argjson next_active "$next_active" \
		'{schema_version:$schema,kind:"pending",domain:"deployment",operation:$operation,transaction_id:$transaction,created_at:$created,phase:"preparing",live_root:$live,prior_active:$prior_active,changes:$changes,created_root:$created_root,created_directories:$directories,parents:$parents,observed_targets:$observed,active_background:$active_background,active_stage:$active_stage,next_active:$next_active}') || return 1
	wallpaper_path_is_absent "$backup_root" || return 1
	while IFS= read -r stage; do wallpaper_path_is_absent "$stage" || return 1; done \
		< <(jq -r '(.prior_active.backup_path,.prior_active.quarantine_path,.changes[].desired.stage_path,.changes[].quarantine_path,.active_stage.path,.active_stage.rollback_quarantine_path) | select(. != null)' <<<"$pending")
	wallpaper_validate_deployment_pending "$pending" || return 1
	wallpaper_write_state_file_verified pending "$pending" || return 1
	WALLPAPER_PENDING_JSON=$pending
	wallpaper_after_pending_planned || { wallpaper_abort_preparing_transaction deployment-after-pending || true; return 1; }
	while IFS= read -r directory; do
		wallpaper_prepare_pending_directory "$directory" 0700 || { wallpaper_abort_preparing_transaction deployment-directory-preparation || true; return 1; }
	done < <(jq -r '.parents[] | select(.created) | .path' <<<"$WALLPAPER_PENDING_JSON")
	if [[ $(jq -r '.prior_active.present' <<<"$WALLPAPER_PENDING_JSON") == true ]]; then
		active_backup=$(jq -r '.prior_active.backup_path' <<<"$WALLPAPER_PENDING_JSON")
		active_identity=$(jq -c '.prior_active.identity' <<<"$WALLPAPER_PENDING_JSON")
		active_digest=$(jq -r '.prior_active.digest' <<<"$WALLPAPER_PENDING_JSON")
		wallpaper_copy_backup "$WALLPAPER_ACTIVE_RECEIPT" "$active_backup" "$active_digest" "$active_identity" || { wallpaper_abort_preparing_transaction deployment-active-backup || true; return 1; }
		wallpaper_preparation_checkpoint backup-created || { wallpaper_abort_preparing_transaction deployment-backup-checkpoint || true; return 1; }
		active_backup_identity=$(wallpaper_file_identity "$active_backup") || { wallpaper_abort_preparing_transaction deployment-active-backup-identity || true; return 1; }
		updated=$(jq -c --argjson identity "$active_backup_identity" '.prior_active.backup_identity = $identity' <<<"$WALLPAPER_PENDING_JSON") || { wallpaper_abort_preparing_transaction deployment-active-backup-evidence || true; return 1; }
		wallpaper_update_pending_evidence "$updated" || { wallpaper_abort_preparing_transaction deployment-active-backup-evidence || true; return 1; }
	fi
	while IFS= read -r item; do
		action=$(jq -r '.action' <<<"$item")
		[[ $action == add ]] || continue
		wallpaper_assert_locked_state_root || { wallpaper_abort_preparing_transaction deployment-stage-root-identity || true; return 1; }
		relative=$(jq -r '.path' <<<"$item")
		stage=$(jq -r '.desired.stage_path' <<<"$item")
		source_identity=$(jq -c '.desired.source_identity' <<<"$item")
		result=$(wallpaper_files copy "$WALLPAPER_LIBRARY_ROOT/$relative" "$stage" 0644 "$source_identity") || { wallpaper_abort_preparing_transaction deployment-stage || true; return 1; }
		wallpaper_preparation_checkpoint stage-created || { wallpaper_abort_preparing_transaction deployment-stage-checkpoint || true; return 1; }
		stage_identity=$(jq -c '.destination' <<<"$result") || { wallpaper_abort_preparing_transaction deployment-stage-identity || true; return 1; }
		updated=$(jq -c --arg path "$relative" --argjson identity "$stage_identity" '.changes = [.changes[] | if .path == $path then .desired.stage_identity = $identity else . end]' <<<"$WALLPAPER_PENDING_JSON") || { wallpaper_abort_preparing_transaction deployment-stage-evidence || true; return 1; }
		wallpaper_update_pending_evidence "$updated" || { wallpaper_abort_preparing_transaction deployment-stage-evidence || true; return 1; }
	done < <(jq -c '.changes[]' <<<"$WALLPAPER_PENDING_JSON")
	stage=$(jq -r '.active_stage.path // empty' <<<"$WALLPAPER_PENDING_JSON")
	if [[ -n $stage ]]; then
		wallpaper_assert_locked_state_root || { wallpaper_abort_preparing_transaction deployment-active-stage-root-identity || true; return 1; }
		stage_identity=$(wallpaper_files create "$stage" 0600 "$next_active"$'\n') || { wallpaper_abort_preparing_transaction deployment-active-stage || true; return 1; }
		wallpaper_preparation_checkpoint active-stage-created || { wallpaper_abort_preparing_transaction deployment-active-stage-checkpoint || true; return 1; }
		updated=$(jq -c --argjson identity "$stage_identity" '.active_stage.identity = $identity' <<<"$WALLPAPER_PENDING_JSON") || { wallpaper_abort_preparing_transaction deployment-active-stage-evidence || true; return 1; }
		wallpaper_update_pending_evidence "$updated" || { wallpaper_abort_preparing_transaction deployment-active-stage-evidence || true; return 1; }
	fi
	wallpaper_after_pending_staged || { wallpaper_abort_preparing_transaction deployment-after-staging || true; return 1; }
	wallpaper_verify_deployment_prepared "$WALLPAPER_PENDING_JSON" || { wallpaper_abort_preparing_transaction deployment-prepared-verification || true; return 1; }
	updated=$(jq -c '.phase = "prepared"' <<<"$WALLPAPER_PENDING_JSON") || { wallpaper_abort_preparing_transaction deployment-phase-transition || true; return 1; }
	wallpaper_update_pending_evidence "$updated" || { wallpaper_abort_preparing_transaction deployment-phase-transition || true; return 1; }
}

wallpaper_verify_desired_repository_sources() {
	local pending=$1 desired relative source identity digest
	while IFS= read -r desired; do
		relative=$(jq -r '.path' <<<"$desired")
		source="$WALLPAPER_LIBRARY_ROOT/$relative"
		identity=$(jq -c '.source_identity' <<<"$desired")
		digest=$(jq -r '.digest' <<<"$desired")
		wallpaper_identity_json_is_valid "$identity" '' "$digest" || return 1
		wallpaper_identity_matches "$source" "$identity" || return 1
	done < <(jq -c '(
		.changes[] | select(.desired.present) | {path,digest:.desired.digest,source_identity:.desired.source_identity}
	), (
		.observed_targets[] | {path,digest:.source_digest,source_identity}
	)' <<<"$pending")
}

wallpaper_verify_deployment_preparing_prior() {
	local pending=$1 change action relative target identity observed
	wallpaper_verify_active_background_evidence "$pending" || return 1
	if [[ $(jq -r '.prior_active.present' <<<"$pending") == true ]]; then
		identity=$(jq -c '.prior_active.identity' <<<"$pending")
		wallpaper_identity_matches "$WALLPAPER_ACTIVE_RECEIPT" "$identity" || return 1
	else
		wallpaper_path_is_absent "$WALLPAPER_ACTIVE_RECEIPT" || return 1
	fi
	while IFS= read -r change; do
		action=$(jq -r '.action' <<<"$change") relative=$(jq -r '.path' <<<"$change")
		target=$(wallpaper_live_target_path "$relative") || return 1
		if [[ $(jq -r '.prior.present' <<<"$change") == true ]]; then
			identity=$(jq -c '.prior.identity' <<<"$change")
			wallpaper_live_identity_matches "$target" "$identity" || return 1
		else
			wallpaper_path_is_absent "$target" || return 1
		fi
	done < <(jq -c '.changes[]' <<<"$pending")
	while IFS= read -r observed; do
		relative=$(jq -r '.path' <<<"$observed") target=$(wallpaper_live_target_path "$relative") || return 1
		identity=$(jq -c '.identity' <<<"$observed")
		wallpaper_live_identity_matches "$target" "$identity" || return 1
	done < <(jq -c '.observed_targets[]' <<<"$pending")
}

wallpaper_verify_deployment_prepared() {
	local pending=$1 parent identity change action stage quarantine backup
	[[ $(jq -r '.phase' <<<"$pending") == preparing ]] || return 1
	wallpaper_verify_deployment_preparing_prior "$pending" || return 1
	wallpaper_verify_desired_repository_sources "$pending" || return 1
	while IFS= read -r parent; do
		identity=$(jq -c --arg path "$parent" '.parents[] | select(.path == $path) | .identity' <<<"$pending")
		[[ $identity != null ]] && wallpaper_object_identity_matches "$parent" "$identity" || return 1
	done < <(jq -r '.parents[].path' <<<"$pending")
	if [[ $(jq -r '.prior_active.present' <<<"$pending") == true ]]; then
		backup=$(jq -r '.prior_active.backup_path' <<<"$pending") identity=$(jq -c '.prior_active.backup_identity' <<<"$pending")
		[[ $identity != null ]] && wallpaper_identity_matches "$backup" "$identity" || return 1
		wallpaper_path_is_absent "$(jq -r '.prior_active.quarantine_path' <<<"$pending")" || return 1
	fi
	while IFS= read -r change; do
		action=$(jq -r '.action' <<<"$change")
		stage=$(jq -r '.desired.stage_path // empty' <<<"$change")
		if [[ -n $stage ]]; then
			identity=$(jq -c '.desired.stage_identity' <<<"$change")
			[[ $identity != null ]] && wallpaper_identity_matches "$stage" "$identity" || return 1
		fi
		quarantine=$(jq -r '.quarantine_path // empty' <<<"$change")
		[[ -z $quarantine ]] || wallpaper_path_is_absent "$quarantine" || return 1
	done < <(jq -c '.changes[]' <<<"$pending")
	stage=$(jq -r '.active_stage.path // empty' <<<"$pending")
	if [[ -n $stage ]]; then
		identity=$(jq -c '.active_stage.identity' <<<"$pending")
		[[ $identity != null ]] && wallpaper_identity_matches "$stage" "$identity" || return 1
		wallpaper_path_is_absent "$(jq -r '.active_stage.rollback_quarantine_path' <<<"$pending")" || return 1
	fi
}

wallpaper_prepare_live_parent() {
	local relative=$1 config_home omarchy theme
	wallpaper_assert_locked_state_root || return 1
	wallpaper_validate_live_parent "$relative" || return 1
	config_home=${XDG_CONFIG_HOME:-"$HOME/.config"} omarchy="$config_home/omarchy" theme=${relative%%/*}
	[[ -d $config_home && ! -L $config_home ]] || return 1
	if [[ ! -e $omarchy && ! -L $omarchy ]]; then mkdir -- "$omarchy" || return 1; fi
	if [[ ! -e $WALLPAPER_LIVE_ROOT && ! -L $WALLPAPER_LIVE_ROOT ]]; then mkdir -- "$WALLPAPER_LIVE_ROOT" || return 1; fi
	if [[ ! -e $WALLPAPER_LIVE_ROOT/$theme && ! -L $WALLPAPER_LIVE_ROOT/$theme ]]; then mkdir -- "$WALLPAPER_LIVE_ROOT/$theme" || return 1; fi
	wallpaper_validate_live_parent "$relative"
}

wallpaper_publish_live_file_impl() {
	local source=$1 relative=$2 digest=$3 source_identity=$4 target parent stage stage_identity published
	wallpaper_assert_locked_state_root || return 1
	[[ $(jq -r '.phase' <<<"$WALLPAPER_PENDING_JSON") == prepared ]] || return 1
	wallpaper_validate_live_parent "$relative" || return 1
	target=$(wallpaper_live_target_path "$relative") || return 1
	parent=${target%/*}
	wallpaper_verify_pending_parent "$parent" || return 1
	wallpaper_identity_matches "$source" "$source_identity" || return 1
	stage=$(jq -r --arg path "$relative" '.changes[] | select(.path == $path) | .desired.stage_path' <<<"$WALLPAPER_PENDING_JSON") || return 1
	stage_identity=$(jq -c --arg path "$relative" '.changes[] | select(.path == $path) | .desired.stage_identity' <<<"$WALLPAPER_PENDING_JSON") || return 1
	wallpaper_identity_matches "$stage" "$stage_identity" || return 1
	published=$(wallpaper_files publish-absent "$stage" "$target") || return 1
	wallpaper_regular_file_is_exact "$target" "$digest" 0644 || return 1
	wallpaper_identity_matches_exchange "$target" "$stage_identity" && wallpaper_identity_matches "$target" "$published"
}

wallpaper_publish_live_file() {
	wallpaper_publish_live_file_impl "$@"
}

wallpaper_delete_live_file_impl() {
	local relative=$1 digest=$2 expected_identity=${3-} target parent actual quarantine
	wallpaper_assert_locked_state_root || return 1
	[[ $(jq -r '.phase' <<<"$WALLPAPER_PENDING_JSON") == prepared ]] || return 1
	target=$(wallpaper_live_target_path "$relative") || return 1
	parent=${target%/*}
	wallpaper_validate_live_parent "$relative" && wallpaper_verify_pending_parent "$parent" || return 1
	wallpaper_verify_active_background_evidence "$WALLPAPER_PENDING_JSON" || return 1
	if wallpaper_deletion_is_active "$target"; then return 1; fi
	actual=$(wallpaper_live_file_identity "$target") || return 1
	wallpaper_live_identity_json_is_valid "$actual" "$digest" || return 1
	[[ -z $expected_identity || $(jq -Sc . <<<"$actual") == "$(jq -Sc . <<<"$expected_identity")" ]] || return 1
	quarantine=$(jq -r --arg path "$relative" '.changes[] | select(.path == $path) | .quarantine_path' <<<"$WALLPAPER_PENDING_JSON") || return 1
	wallpaper_remove_to_quarantine "$target" "$actual" "$quarantine" true
}

wallpaper_delete_live_file() {
	wallpaper_delete_live_file_impl "$@"
}

wallpaper_delete_live_file_verified() {
	local relative=$1 target
	target=$(wallpaper_live_target_path "$relative") || return 1
	wallpaper_delete_live_file "$@" || return 1
	wallpaper_path_is_absent "$target"
}

wallpaper_generate_active_receipt() {
	local transaction=$1 activated targets
	activated=$(wallpaper_now) || return 1
	targets=$(jq -c '[.[] | {path,digest}]' <<<"$WALLPAPER_DESIRED_JSON") || return 1
	jq -cn --argjson schema "$WALLPAPER_SCHEMA_VERSION" --arg transaction "$transaction" --arg activated "$activated" \
		--argjson targets "$targets" --argjson created_root "$WALLPAPER_NEXT_CREATED_ROOT" \
		--argjson directories "$WALLPAPER_NEXT_CREATED_DIRECTORIES" \
		'{schema_version:$schema,kind:"active",transaction_id:$transaction,activated_at:$activated,targets:$targets,created_root:$created_root,created_directories:$directories}'
}

wallpaper_quarantine_prior_active_impl() {
	local pending=$1 present identity quarantine
	wallpaper_assert_locked_state_root || return 1
	[[ $(jq -r '.phase' <<<"$pending") == prepared ]] || return 1
	present=$(jq -r '.prior_active.present' <<<"$pending")
	if [[ $present != true ]]; then
		wallpaper_path_is_absent "$WALLPAPER_ACTIVE_RECEIPT"
		return
	fi
	identity=$(jq -c '.prior_active.identity' <<<"$pending")
	quarantine=$(jq -r '.prior_active.quarantine_path' <<<"$pending")
	wallpaper_remove_to_quarantine "$WALLPAPER_ACTIVE_RECEIPT" "$identity" "$quarantine"
}

wallpaper_quarantine_prior_active() {
	wallpaper_quarantine_prior_active_impl "$@"
}

wallpaper_restore_prior_active() {
	local pending=$1 present backup digest prior_identity backup_identity active_stage_identity current_identity='' backup_content quarantine rollback_quarantine
	wallpaper_assert_locked_state_root || return 1
	present=$(jq -r '.prior_active.present' <<<"$pending")
	active_stage_identity=$(jq -c '.active_stage.identity // null' <<<"$pending")
	quarantine=$(jq -r '.prior_active.quarantine_path // empty' <<<"$pending")
	rollback_quarantine=$(jq -r '.active_stage.rollback_quarantine_path // empty' <<<"$pending")
	if [[ $present == true ]]; then
		backup=$(jq -r '.prior_active.backup_path' <<<"$pending") digest=$(jq -r '.prior_active.digest' <<<"$pending")
		prior_identity=$(jq -c '.prior_active.identity' <<<"$pending")
		backup_identity=$(jq -c '.prior_active.backup_identity' <<<"$pending")
		backup_content=$(wallpaper_read_file_stable "$backup" "$backup_identity") || return 1
		if [[ -e $WALLPAPER_ACTIVE_RECEIPT || -L $WALLPAPER_ACTIVE_RECEIPT ]]; then
			if wallpaper_identity_matches "$WALLPAPER_ACTIVE_RECEIPT" "$prior_identity"; then
				wallpaper_path_is_absent "$quarantine" || return 1
				return 0
			fi
			[[ $active_stage_identity != null && -n $rollback_quarantine ]] || return 1
			current_identity=$(wallpaper_file_identity "$WALLPAPER_ACTIVE_RECEIPT") || return 1
			wallpaper_identity_matches_exchange "$WALLPAPER_ACTIVE_RECEIPT" "$active_stage_identity" || return 1
			wallpaper_remove_to_quarantine "$WALLPAPER_ACTIVE_RECEIPT" "$current_identity" "$rollback_quarantine" || return 1
		fi
		if [[ -e $quarantine || -L $quarantine ]]; then
			wallpaper_restore_from_quarantine "$quarantine" "$prior_identity" "$WALLPAPER_ACTIVE_RECEIPT" || return 1
		else
			wallpaper_write_state_file_verified active "$backup_content" || return 1
		fi
	else
		if [[ -e $WALLPAPER_ACTIVE_RECEIPT || -L $WALLPAPER_ACTIVE_RECEIPT ]]; then
			[[ $active_stage_identity != null && -n $rollback_quarantine ]] || return 1
			current_identity=$(wallpaper_file_identity "$WALLPAPER_ACTIVE_RECEIPT") || return 1
			wallpaper_identity_matches_exchange "$WALLPAPER_ACTIVE_RECEIPT" "$active_stage_identity" || return 1
			wallpaper_remove_to_quarantine "$WALLPAPER_ACTIVE_RECEIPT" "$current_identity" "$rollback_quarantine" || return 1
		fi
	fi
	if [[ -n $rollback_quarantine ]]; then wallpaper_cleanup_quarantine_file "$rollback_quarantine" "$active_stage_identity" || return 1; fi
}

wallpaper_restore_deployment_pending() {
	local pending=$1 change relative parent prior_present prior_digest prior_mode prior_identity backup backup_identity desired_present desired_digest stage_identity current_identity target theme directory quarantine
	wallpaper_assert_locked_state_root || return 1
	while IFS= read -r change; do
		relative=$(jq -r '.path' <<<"$change") target=$(wallpaper_live_target_path "$relative") || return 1
		parent=${target%/*}
		prior_present=$(jq -r '.prior.present' <<<"$change") desired_present=$(jq -r '.desired.present' <<<"$change")
		quarantine=$(jq -r '.quarantine_path // empty' <<<"$change")
		if [[ -e $parent || -L $parent ]]; then wallpaper_verify_pending_parent "$parent" "$pending" || return 1; elif [[ $prior_present == true ]]; then return 1; fi
		if [[ $prior_present == true ]]; then
			prior_digest=$(jq -r '.prior.digest' <<<"$change") prior_mode=$(jq -r '.prior.mode' <<<"$change")
			prior_identity=$(jq -c '.prior.identity' <<<"$change") backup=$(jq -r '.prior.backup_path' <<<"$change")
			backup_identity=$(jq -c '.prior.backup_identity' <<<"$change")
			if [[ -e $target || -L $target ]]; then
				[[ -f $target && ! -L $target ]] || return 1
				if wallpaper_live_identity_matches "$target" "$prior_identity"; then
					[[ -z $quarantine ]] || wallpaper_path_is_absent "$quarantine" || return 1
					continue
				fi
				return 1
			fi
			[[ -n $quarantine && ( -e $quarantine || -L $quarantine ) ]] || return 1
			wallpaper_restore_from_quarantine "$quarantine" "$prior_identity" "$target" true || return 1
		else
			if [[ -e $target || -L $target ]]; then
				[[ -f $target && ! -L $target && $desired_present == true ]] || return 1
				desired_digest=$(jq -r '.desired.digest' <<<"$change")
				stage_identity=$(jq -c '.desired.stage_identity' <<<"$change")
				wallpaper_identity_matches_exchange "$target" "$stage_identity" || return 1
				current_identity=$(wallpaper_live_file_identity "$target") || return 1
				wallpaper_remove_to_quarantine "$target" "$current_identity" "$quarantine" true || return 1
			fi
		fi
	done < <(jq -c '.changes | reverse[]' <<<"$pending")
	wallpaper_restore_prior_active "$pending" || return 1
	wallpaper_cleanup_pending_publication_stages "$pending" || return 1
	wallpaper_cleanup_pending_quarantines "$pending" || return 1
	while IFS= read -r theme; do directory="$WALLPAPER_LIVE_ROOT/$theme"; wallpaper_remove_pending_directory "$directory" "$pending" || return 1; done \
		< <(jq -r '.created_directories | reverse[]' <<<"$pending")
	if [[ $(jq -r '.created_root' <<<"$pending") == true ]]; then wallpaper_remove_pending_directory "$WALLPAPER_LIVE_ROOT" "$pending" || return 1; fi
}

wallpaper_verify_deployment_mutation_boundary() {
	local pending=$1 change action relative target identity stage_identity parent observed quarantine
	[[ $(jq -r '.phase' <<<"$pending") == prepared || $(jq -r '.phase' <<<"$pending") == complete ]] || return 1
	wallpaper_verify_pending_parent "$WALLPAPER_STATE_CANONICAL_ROOT" "$pending" || return 1
	wallpaper_verify_active_background_evidence "$pending" || return 1
	while IFS= read -r change; do
		action=$(jq -r '.action' <<<"$change") relative=$(jq -r '.path' <<<"$change")
		target=$(wallpaper_live_target_path "$relative") || return 1
		case $action in
			add)
				parent=${target%/*}; wallpaper_verify_pending_parent "$parent" "$pending" || return 1
				stage_identity=$(jq -c '.desired.stage_identity' <<<"$change")
				wallpaper_identity_matches_exchange "$target" "$stage_identity" || return 1
				;;
			adopt)
				parent=${target%/*}; wallpaper_verify_pending_parent "$parent" "$pending" || return 1
				identity=$(jq -c '.desired.identity' <<<"$change")
				wallpaper_live_identity_matches "$target" "$identity" || return 1
				;;
			remove)
				wallpaper_path_is_absent "$target" || return 1
				quarantine=$(jq -r '.quarantine_path' <<<"$change") identity=$(jq -c '.prior.identity' <<<"$change")
				if [[ -e $quarantine || -L $quarantine ]]; then wallpaper_live_identity_matches_exchange "$quarantine" "$identity" || return 1
				else [[ $(jq -r '.phase' <<<"$pending") == complete ]] || return 1
				fi
				;;
		esac
	done < <(jq -c '.changes[]' <<<"$pending")
	while IFS= read -r observed; do
		relative=$(jq -r '.path' <<<"$observed") target=$(wallpaper_live_target_path "$relative") || return 1
		identity=$(jq -c '.identity' <<<"$observed")
		wallpaper_live_identity_matches "$target" "$identity" || return 1
	done < <(jq -c '.observed_targets[]' <<<"$pending")
}

wallpaper_verify_deployment_desired_from_pending() {
	local pending=$1 next_active stage_identity active_identity content
	wallpaper_verify_deployment_mutation_boundary "$pending" || return 1
	next_active=$(jq -c '.next_active' <<<"$pending") || return 1
	if [[ $next_active == null ]]; then
		wallpaper_path_is_absent "$WALLPAPER_ACTIVE_RECEIPT"
	else
		stage_identity=$(jq -c '.active_stage.identity' <<<"$pending") || return 1
		wallpaper_identity_matches_exchange "$WALLPAPER_ACTIVE_RECEIPT" "$stage_identity" || return 1
		active_identity=$(wallpaper_file_identity "$WALLPAPER_ACTIVE_RECEIPT") || return 1
		content=$(wallpaper_read_file_stable "$WALLPAPER_ACTIVE_RECEIPT" "$active_identity") || return 1
		[[ $(jq -Sc . <<<"$content") == "$(jq -Sc . <<<"$next_active")" ]]
	fi
}

wallpaper_verify_deployment_prior() {
	local pending=$1 change relative target present digest mode active_present active_digest
	while IFS= read -r change; do
		relative=$(jq -r '.path' <<<"$change")
		target=$(wallpaper_live_target_path "$relative") || return 1
		present=$(jq -r '.prior.present' <<<"$change")
		if [[ $present == true ]]; then
			digest=$(jq -r '.prior.digest' <<<"$change") mode=$(jq -r '.prior.mode' <<<"$change")
			[[ -f $target && ! -L $target ]] && wallpaper_regular_live_file_is_exact "$target" "$digest" || return 1
		else
			[[ ! -e $target && ! -L $target ]] || return 1
		fi
	done < <(jq -c '.changes[]' <<<"$pending")
	active_present=$(jq -r '.prior_active.present' <<<"$pending")
	if [[ $active_present == true ]]; then
		active_digest=$(jq -r '.prior_active.digest' <<<"$pending")
		[[ -f $WALLPAPER_ACTIVE_RECEIPT && ! -L $WALLPAPER_ACTIVE_RECEIPT ]] && wallpaper_regular_file_is_exact "$WALLPAPER_ACTIVE_RECEIPT" "$active_digest" 0600 || return 1
	else
		[[ ! -e $WALLPAPER_ACTIVE_RECEIPT && ! -L $WALLPAPER_ACTIVE_RECEIPT ]] || return 1
	fi
}

wallpaper_rollback_deployment() {
	local step=$1 pending=$2
	printf 'Transaction failure: %s; restoring prior wallpaper deployment and receipt.\n' "$step" >&2
	if wallpaper_validate_deployment_pending "$pending" && wallpaper_restore_deployment_pending "$pending" && wallpaper_verify_deployment_prior "$pending" && wallpaper_mark_transaction_rolled_back; then
		wallpaper_clear_transaction_evidence "$WALLPAPER_PENDING_JSON" || return 1
		printf 'Wallpaper deployment rollback verified.\n' >&2
		return 0
	fi
	wallpaper_write_recovery_required "$step" "$pending" || true
	printf 'Error: wallpaper deployment rollback failed; pending evidence and backups were retained.\n' >&2
	return 1
}

wallpaper_cleanup_created_directories() {
	local active=$1 theme directory
	while IFS= read -r theme; do
		jq -e --arg theme "$theme" 'any(.[]; . == $theme)' <<<"$WALLPAPER_NEXT_CREATED_DIRECTORIES" >/dev/null && continue
		directory="$WALLPAPER_LIVE_ROOT/$theme"
		wallpaper_remove_pending_directory "$directory" || return 1
	done < <(jq -r '.created_directories | reverse[]' <<<"$active")
	if [[ $(jq -r '.created_root' <<<"$active") == true && $WALLPAPER_NEXT_CREATED_ROOT != true ]]; then wallpaper_remove_pending_directory "$WALLPAPER_LIVE_ROOT" || return 1; fi
}

wallpaper_cleanup_completed_deployment_directories() {
	local pending=$1 backup backup_identity prior theme directory next_directories='[]' next_root=false
	wallpaper_assert_locked_state_root || return 1
	[[ $(jq -r '.phase' <<<"$pending") == complete ]] || return 1
	if [[ $(jq -r '.next_active != null' <<<"$pending") == true ]]; then
		next_directories=$(jq -c '.next_active.created_directories' <<<"$pending") || return 1
		next_root=$(jq -r '.next_active.created_root' <<<"$pending") || return 1
	fi
	[[ $(jq -r '.prior_active.present' <<<"$pending") == true ]] || return 0
	backup=$(jq -r '.prior_active.backup_path' <<<"$pending") backup_identity=$(jq -c '.prior_active.backup_identity' <<<"$pending")
	wallpaper_path_is_absent "$backup" && return 0
	prior=$(wallpaper_read_file_stable "$backup" "$backup_identity") || return 1
	wallpaper_validate_active_json "$prior" || return 1
	while IFS= read -r theme; do
		jq -e --arg theme "$theme" 'any(.[]; . == $theme)' <<<"$next_directories" >/dev/null && continue
		directory="$WALLPAPER_LIVE_ROOT/$theme"
		wallpaper_remove_pending_directory "$directory" "$pending" || return 1
	done < <(jq -r '.created_directories | reverse[]' <<<"$prior")
	if [[ $(jq -r '.created_root' <<<"$prior") == true && $next_root != true ]]; then
		wallpaper_remove_pending_directory "$WALLPAPER_LIVE_ROOT" "$pending" || return 1
	fi
}

wallpaper_recover_deployment() {
	local pending=$1
	wallpaper_assert_locked_state_root || return 1
	printf 'Interrupted wallpaper deployment transaction detected: %s\n' "$(jq -r '.operation' <<<"$pending")"
	if wallpaper_restore_deployment_pending "$pending" && wallpaper_verify_deployment_prior "$pending" && wallpaper_mark_transaction_rolled_back; then
		wallpaper_clear_transaction_evidence "$WALLPAPER_PENDING_JSON" || return 1
		printf 'Interrupted wallpaper deployment recovered and verified; rerun the requested operation.\n'
		WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_RECOVERY_COMPLETED
		return 0
	fi
	wallpaper_write_recovery_required interrupted-deployment-recovery "$pending" || true
	printf 'Error: interrupted wallpaper deployment recovery failed; ordinary wallpaper mutation remains blocked.\n' >&2
	return 1
}

apply_wallpapers() {
	WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_ORDINARY
	local argument state_status plan_before fingerprint_before library_before transaction item action relative digest source outcome=0 active next_active=null expected_identity expected_active published_active active_stage active_stage_identity
	WALLPAPER_OPTION_YES=false WALLPAPER_OPTION_OVERRIDE=false
	for argument in "$@"; do wallpaper_parse_common_flag "$argument" || { printf 'Error: unknown apply_wallpapers option: %s\n' "$argument" >&2; return 2; }; done
	if wallpaper_recover_before_preflight "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE"; then return 0; else state_status=$?; fi
	((state_status == 2)) || return "$state_status"
	wallpaper_initialize_paths || return 1
	if ! wallpaper_inspect_state; then printf 'Error: invalid wallpaper state blocks Apply: %s\n' "$WALLPAPER_STATE_ERROR" >&2; return 1; fi
	wallpaper_build_desired_inventory || { printf 'Error: %s\n' "$WALLPAPER_PLAN_ERROR" >&2; return 1; }
	library_before=$(wallpaper_library_snapshot) || return 1
	wallpaper_build_apply_plan || { printf 'Error: %s\n' "$WALLPAPER_PLAN_ERROR" >&2; return 1; }
	if [[ $(jq 'length' <<<"$WALLPAPER_PLAN_JSON") -eq 0 ]]; then
		if [[ -z $WALLPAPER_ACTIVE_JSON && $(jq 'length' <<<"$WALLPAPER_DESIRED_JSON") -eq 0 ]]; then
			printf 'Wallpaper library is empty and no wallpaper deployment is active; exact no-op.\n'
		else
			printf 'Wallpaper deployment is already an exact no-op; live files and receipt metadata were preserved.\n'
		fi
		return 0
	fi
	plan_before=$(jq -Sc . <<<"$WALLPAPER_PLAN_JSON")
	fingerprint_before=$WALLPAPER_DEPLOYMENT_FINGERPRINT
	wallpaper_print_apply_plan || return 1
	wallpaper_require_compatible_mutation "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE" || return 1
	if [[ $WALLPAPER_OPTION_YES != true ]] && ! wallpaper_confirm 'Apply this complete wallpaper deployment plan, including any displayed Omarchy mismatch?'; then
		printf 'No changes made.\n'
		return 0
	fi
	wallpaper_prepare_state_root || return 1
	wallpaper_acquire_lock || return 1
	if ! wallpaper_recheck_approved_omarchy; then wallpaper_release_lock; return 1; fi
	if ! wallpaper_inspect_state; then printf 'Error: invalid wallpaper state blocks Apply: %s\n' "$WALLPAPER_STATE_ERROR" >&2; wallpaper_release_lock; return 1; fi
	if [[ -n $WALLPAPER_PENDING_JSON || -n $WALLPAPER_RECOVERY_JSON ]]; then wallpaper_recover_interrupted; outcome=$?; wallpaper_release_lock; return "$outcome"; fi
	wallpaper_build_desired_inventory || { wallpaper_release_lock; return 1; }
	wallpaper_build_apply_plan || { printf 'Error: %s\n' "$WALLPAPER_PLAN_ERROR" >&2; wallpaper_release_lock; return 1; }
	if [[ $(wallpaper_library_snapshot) != "$library_before" || $(jq -Sc . <<<"$WALLPAPER_PLAN_JSON") != "$plan_before" ||
		$WALLPAPER_DEPLOYMENT_FINGERPRINT != "$fingerprint_before" ]]; then
		printf 'Error: confirmed wallpaper Apply plan changed before mutation.\n' >&2
		wallpaper_release_lock
		return 1
	fi
	wallpaper_prepare_next_directory_inventory || { wallpaper_release_lock; return 1; }
	transaction=$(wallpaper_allocate_transaction) || { wallpaper_release_lock; return 1; }
	if [[ $(jq 'length' <<<"$WALLPAPER_DESIRED_JSON") -gt 0 ]]; then
		next_active=$(wallpaper_generate_active_receipt "$transaction") || { wallpaper_release_lock; return 1; }
	fi
	wallpaper_begin_deployment_transaction apply "$transaction" "$next_active" || { wallpaper_release_lock; return 1; }
	active=$WALLPAPER_ACTIVE_JSON
	while IFS= read -r item; do
		action=$(jq -r '.action' <<<"$item") relative=$(jq -r '.path' <<<"$item") digest=$(jq -r '.digest' <<<"$item")
		case $action in
			add)
				source="$WALLPAPER_LIBRARY_ROOT/$relative"
				expected_identity=$(jq -c --arg path "$relative" '.changes[] | select(.path == $path) | .desired.source_identity' <<<"$WALLPAPER_PENDING_JSON")
				wallpaper_publish_live_file "$source" "$relative" "$digest" "$expected_identity" || { outcome=1; break; }
				;;
			adopt) ;;
			remove)
				expected_identity=$(jq -c --arg path "$relative" '.changes[] | select(.path == $path) | .prior.identity' <<<"$WALLPAPER_PENDING_JSON")
				wallpaper_delete_live_file_verified "$relative" "$digest" "$expected_identity" || { outcome=1; break; }
				;;
		esac
	done < <(jq -c '.[]' <<<"$WALLPAPER_PLAN_JSON")
	if ((outcome == 0)) && ! wallpaper_verify_deployment_mutation_boundary "$WALLPAPER_PENDING_JSON"; then outcome=1; fi
	if ((outcome == 0)); then
		if ((outcome == 0)) && ! wallpaper_verify_desired_repository_sources "$WALLPAPER_PENDING_JSON"; then outcome=1; fi
		if ((outcome == 0)) && ! wallpaper_quarantine_prior_active "$WALLPAPER_PENDING_JSON"; then outcome=1; fi
		if [[ $(jq 'length' <<<"$WALLPAPER_DESIRED_JSON") -gt 0 ]]; then
			active_stage=$(jq -r '.active_stage.path' <<<"$WALLPAPER_PENDING_JSON") active_stage_identity=$(jq -c '.active_stage.identity' <<<"$WALLPAPER_PENDING_JSON")
			if ((outcome == 0)) && { ! wallpaper_validate_active_json "$next_active" || ! wallpaper_write_state_file_verified active "$next_active" '' "$active_stage" "$active_stage_identity"; }; then outcome=1; fi
			if ((outcome == 0)); then published_active=$(wallpaper_read_file_stable "$WALLPAPER_ACTIVE_RECEIPT") || outcome=1; fi
			if ((outcome == 0)) && [[ $(jq -Sc . <<<"$published_active") != "$(jq -Sc . <<<"$next_active")" ]]; then outcome=1; fi
		else
			if ((outcome == 0)); then wallpaper_path_is_absent "$WALLPAPER_ACTIVE_RECEIPT" || outcome=1; fi
		fi
		if ((outcome == 0)) && ! wallpaper_verify_desired_repository_sources "$WALLPAPER_PENDING_JSON"; then outcome=1; fi
	fi
	if ((outcome == 0)) && ! wallpaper_verify_deployment_desired_from_pending "$WALLPAPER_PENDING_JSON"; then outcome=1; fi
	if ((outcome != 0)); then wallpaper_rollback_deployment apply-failure "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; fi
	wallpaper_complete_transaction || { [[ ! -e $WALLPAPER_PENDING_RECEIPT ]] || wallpaper_write_recovery_required completion-cleanup "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; }
	wallpaper_release_lock
	printf 'Wallpaper deployment applied and verified with regular files.\n'
}

remove_wallpapers() {
	WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_ORDINARY
	local argument state_status plan_before fingerprint_before transaction item relative digest expected_identity expected_active outcome=0 active
	WALLPAPER_OPTION_YES=false WALLPAPER_OPTION_OVERRIDE=false
	for argument in "$@"; do wallpaper_parse_common_flag "$argument" || { printf 'Error: unknown remove_wallpapers option: %s\n' "$argument" >&2; return 2; }; done
	if wallpaper_recover_before_preflight "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE"; then return 0; else state_status=$?; fi
	((state_status == 2)) || return "$state_status"
	wallpaper_initialize_paths || return 1
	if ! wallpaper_inspect_state; then printf 'Error: invalid wallpaper state blocks removal: %s\n' "$WALLPAPER_STATE_ERROR" >&2; return 1; fi
	if [[ -z $WALLPAPER_ACTIVE_JSON ]]; then printf 'Wallpaper deployment is already absent; exact no-op.\n'; return 0; fi
	wallpaper_build_remove_plan || { printf 'Error: %s\n' "$WALLPAPER_PLAN_ERROR" >&2; return 1; }
	plan_before=$(jq -Sc . <<<"$WALLPAPER_PLAN_JSON")
	fingerprint_before=$WALLPAPER_DEPLOYMENT_FINGERPRINT
	printf 'Plan: remove every unchanged receipt-owned wallpaper target\n'
	while IFS= read -r item; do relative=$(jq -r '.path' <<<"$item"); printf 'Remove receipt-owned target: %s\n' "$(wallpaper_live_target_path "$relative")"; done < <(jq -c '.[]' <<<"$WALLPAPER_PLAN_JSON")
	printf 'Unrelated backgrounds and nonempty directories are preserved.\n'
	wallpaper_require_compatible_mutation "$WALLPAPER_OPTION_YES" "$WALLPAPER_OPTION_OVERRIDE" || return 1
	if [[ $WALLPAPER_OPTION_YES != true ]] && ! wallpaper_confirm 'Remove this complete wallpaper deployment plan, including any displayed Omarchy mismatch?'; then printf 'No changes made.\n'; return 0; fi
	wallpaper_prepare_state_root || return 1
	wallpaper_acquire_lock || return 1
	if ! wallpaper_recheck_approved_omarchy; then wallpaper_release_lock; return 1; fi
	if ! wallpaper_inspect_state; then printf 'Error: invalid wallpaper state blocks removal: %s\n' "$WALLPAPER_STATE_ERROR" >&2; wallpaper_release_lock; return 1; fi
	if [[ -n $WALLPAPER_PENDING_JSON || -n $WALLPAPER_RECOVERY_JSON ]]; then wallpaper_recover_interrupted; outcome=$?; wallpaper_release_lock; return "$outcome"; fi
	wallpaper_build_remove_plan || { printf 'Error: %s\n' "$WALLPAPER_PLAN_ERROR" >&2; wallpaper_release_lock; return 1; }
	if [[ $(jq -Sc . <<<"$WALLPAPER_PLAN_JSON") != "$plan_before" || $WALLPAPER_DEPLOYMENT_FINGERPRINT != "$fingerprint_before" ]]; then printf 'Error: confirmed wallpaper removal plan changed before mutation.\n' >&2; wallpaper_release_lock; return 1; fi
	transaction=$(wallpaper_allocate_transaction) || { wallpaper_release_lock; return 1; }
	wallpaper_begin_deployment_transaction remove "$transaction" null || { wallpaper_release_lock; return 1; }
	active=$WALLPAPER_ACTIVE_JSON
	while IFS= read -r item; do
		relative=$(jq -r '.path' <<<"$item") digest=$(jq -r '.digest' <<<"$item")
		expected_identity=$(jq -c --arg path "$relative" '.changes[] | select(.path == $path) | .prior.identity' <<<"$WALLPAPER_PENDING_JSON")
		wallpaper_delete_live_file_verified "$relative" "$digest" "$expected_identity" || { outcome=1; break; }
	done < <(jq -c '.[]' <<<"$WALLPAPER_PLAN_JSON")
	if ((outcome == 0)); then
		while IFS= read -r item; do relative=$(jq -r '.path' <<<"$item"); [[ ! -e $(wallpaper_live_target_path "$relative") && ! -L $(wallpaper_live_target_path "$relative") ]] || { outcome=1; break; }; done < <(jq -c '.[]' <<<"$WALLPAPER_PLAN_JSON")
	fi
	if ((outcome == 0)) && ! wallpaper_quarantine_prior_active "$WALLPAPER_PENDING_JSON"; then outcome=1; fi
	if ((outcome == 0)) && ! wallpaper_verify_deployment_desired_from_pending "$WALLPAPER_PENDING_JSON"; then outcome=1; fi
	if ((outcome != 0)); then wallpaper_rollback_deployment remove-failure "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; fi
	wallpaper_complete_transaction || { [[ ! -e $WALLPAPER_PENDING_RECEIPT ]] || wallpaper_write_recovery_required completion-cleanup "$WALLPAPER_PENDING_JSON" || true; wallpaper_release_lock; return 1; }
	wallpaper_release_lock
	printf 'Wallpaper deployment removal committed and verified.\n'
}

validate_wallpaper_deployment_state() {
	if (($# != 0)); then printf 'Error: validate_wallpaper_deployment_state accepts no arguments.\n' >&2; return 2; fi
	local relative digest target count=0
	wallpaper_initialize_paths || return 1
	if ! wallpaper_inspect_state; then printf 'Error: invalid wallpaper deployment state: %s (state evidence requires 0700 directories and 0600 files).\n' "$WALLPAPER_STATE_ERROR" >&2; return 1; fi
	if [[ -n $WALLPAPER_PENDING_JSON || -n $WALLPAPER_RECOVERY_JSON ]]; then
		printf 'Error: wallpaper deployment has a valid interrupted transaction requiring recovery.\n' >&2
		return 1
	fi
	if [[ -z $WALLPAPER_ACTIVE_JSON ]]; then printf 'Wallpaper deployment state: cleanly absent.\n'; return 0; fi
	while IFS=$'\t' read -r relative digest; do
		wallpaper_validate_live_parent "$relative" || { printf 'Error: %s\n' "$WALLPAPER_PLAN_ERROR" >&2; return 1; }
		target=$(wallpaper_live_target_path "$relative") || return 1
		if [[ ! -f $target || -L $target ]] || ! wallpaper_regular_live_file_is_exact "$target" "$digest"; then
			printf 'Error: receipt-owned wallpaper target is not a regular non-symlink file with the recorded bytes: %s\n' "$target" >&2
			return 1
		fi
		count=$((count + 1))
	done < <(jq -r '.targets[] | [.path,.digest] | @tsv' <<<"$WALLPAPER_ACTIVE_JSON")
	printf 'Wallpaper deployment state: exact active deployment.\nReceipt-owned targets: %s\n' "$count"
}
