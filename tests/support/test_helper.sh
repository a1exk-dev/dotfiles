#!/usr/bin/env bash

set -u

SOURCE_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
BWRAP=$(command -v bwrap)
HOST_NODE_REAL=$(readlink -f -- "$(command -v node)")
BWRAP_EXTRA_ARGS=()
TESTS_RUN=0
TESTS_FAILED=0

fail() {
	printf 'not ok %d - %s\n' "$TESTS_RUN" "$1"
	TESTS_FAILED=$((TESTS_FAILED + 1))
}

pass() {
	printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

assert_eq() {
	local expected=$1
	local actual=$2
	local message=$3

	if [[ $actual != "$expected" ]]; then
		printf '  %s\n  expected: %q\n  actual:   %q\n' "$message" "$expected" "$actual" >&2
		return 1
	fi
}

assert_contains() {
	local haystack=$1
	local needle=$2
	local message=$3

	if [[ $haystack != *"$needle"* ]]; then
		printf '  %s\n  missing: %q\n  output:  %q\n' "$message" "$needle" "$haystack" >&2
		return 1
	fi
}

new_fixture() {
	BWRAP_EXTRA_ARGS=()
	if [[ -n ${FIXTURE_ROOT-} && -d $FIXTURE_ROOT ]]; then
		rm -rf "$FIXTURE_ROOT"
	fi
	if [[ -n ${OUTSIDE_ROOT-} && -d $OUTSIDE_ROOT ]]; then
		rm -rf "$OUTSIDE_ROOT"
	fi
	FIXTURE_ROOT=$(mktemp -d)
	OUTSIDE_ROOT=$(mktemp -d)
	FIXTURE_REPO="$FIXTURE_ROOT/relocated/dotfiles"
	FIXTURE_HOME="$FIXTURE_ROOT/user/home"
	FIXTURE_CONFIG="$FIXTURE_ROOT/user/config"
	FIXTURE_STATE="$FIXTURE_ROOT/user/state"
	FIXTURE_CACHE="$FIXTURE_ROOT/user/cache"
	FIXTURE_TMP="$FIXTURE_ROOT/tmp"
	FIXTURE_BIN="$FIXTURE_ROOT/fake-bin"
	FIXTURE_OMARCHY="$FIXTURE_ROOT/packaged-omarchy"
	CALL_LOG="$FIXTURE_ROOT/external-calls"
	ARCH_PACKAGE_STATE="$FIXTURE_ROOT/installed-arch-packages"
	ARCH_PACKAGE_ADD_MARKER="$FIXTURE_ROOT/arch-package-add-attempted"
	FIXTURE_BRAVE_SYSTEM="$FIXTURE_ROOT/system/etc/brave"
	BRAVE_METADATA_ROOT="$FIXTURE_ROOT/brave-metadata"
	BRAVE_PACKAGE_DB="$FIXTURE_ROOT/brave-packages"
	BRAVE_PROVIDER_DB="$FIXTURE_ROOT/brave-providers"
	BRAVE_OWNER_DB="$FIXTURE_ROOT/brave-provider-owners"
	BRAVE_FAILURE_MARKERS="$FIXTURE_ROOT/brave-failure-markers"
	BRAVE_CANARY_ROOT="$FIXTURE_ROOT/brave-canaries"
	FIXTURE_REAL_NODE_DIR="$FIXTURE_ROOT/real-node"

	mkdir -p "$FIXTURE_REPO/bin" "$FIXTURE_REPO/lib/dotfiles" "$FIXTURE_HOME" "$FIXTURE_CONFIG" \
		"$FIXTURE_STATE" "$FIXTURE_CACHE" "$FIXTURE_TMP" "$FIXTURE_BIN" "$FIXTURE_OMARCHY" \
		"$BRAVE_METADATA_ROOT" "$BRAVE_FAILURE_MARKERS" "$BRAVE_CANARY_ROOT" "$FIXTURE_REAL_NODE_DIR" \
		"$OUTSIDE_ROOT/user-config" "$OUTSIDE_ROOT/global-skills" "$OUTSIDE_ROOT/packaged-omarchy"
	BWRAP_EXTRA_ARGS+=(--ro-bind "$(dirname -- "$HOST_NODE_REAL")" "$FIXTURE_REAL_NODE_DIR")
	printf 'outside user configuration\n' >"$OUTSIDE_ROOT/user-config/sentinel"
	printf 'outside global skill\n' >"$OUTSIDE_ROOT/global-skills/sentinel"
	printf 'outside packaged Omarchy\n' >"$OUTSIDE_ROOT/packaged-omarchy/sentinel"
	OUTSIDE_SNAPSHOT=$(snapshot_outside_canaries)
	: >"$CALL_LOG"
	printf '%s\n' thefuck tmux fzf less starship >"$ARCH_PACKAGE_STATE"
	cp "$SOURCE_REPO/bin/dotfiles" "$FIXTURE_REPO/bin/dotfiles"
	cp "$SOURCE_REPO/lib/dotfiles/"*.sh "$FIXTURE_REPO/lib/dotfiles/"
	cp "$SOURCE_REPO/lib/dotfiles/"*.mjs "$FIXTURE_REPO/lib/dotfiles/"
	cp "$SOURCE_REPO/packages.json" "$FIXTURE_REPO/packages.json"
	cp "$SOURCE_REPO/cleanup.json" "$FIXTURE_REPO/cleanup.json"
	if [[ -f $SOURCE_REPO/README.md ]]; then
		cp "$SOURCE_REPO/README.md" "$FIXTURE_REPO/README.md"
	fi
	if [[ -d $SOURCE_REPO/brave ]]; then
		cp -a "$SOURCE_REPO/brave" "$FIXTURE_REPO/brave"
	fi
	if [[ -d $SOURCE_REPO/config ]]; then
		cp -a "$SOURCE_REPO/config" "$FIXTURE_REPO/config"
	fi
	if [[ -d $SOURCE_REPO/docs ]]; then
		cp -a "$SOURCE_REPO/docs" "$FIXTURE_REPO/docs"
	fi
	if [[ -f $SOURCE_REPO/skills.json ]]; then
		cp "$SOURCE_REPO/skills.json" "$FIXTURE_REPO/skills.json"
	fi
	if [[ -f $SOURCE_REPO/Makefile ]]; then
		cp "$SOURCE_REPO/Makefile" "$FIXTURE_REPO/Makefile"
	fi

	make_fake omarchy 'printf "%s|HOME=%s|XDG_CONFIG_HOME=%s|XDG_STATE_HOME=%s|XDG_CACHE_HOME=%s\n" "$*" "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then
	printf "%s\n" "${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"
	exit 0
fi
if [[ ${1-} == pkg && ${2-} == present ]]; then
	shift 2
	for package in "$@"; do
		grep -Fxq -- "$package" "$DOTFILES_TEST_ARCH_PACKAGE_STATE" || exit 1
	done
	if [[ $DOTFILES_TEST_ARCH_VERIFY_FAILURE == true && -e $DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER ]]; then exit 75; fi
	exit 0
fi
if [[ ${1-} == pkg && ${2-} == add ]]; then
	touch "$DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER"
	[[ $DOTFILES_TEST_ARCH_INSTALL_FAILURE == false ]] || exit 76
	for package in "${@:3}"; do
		grep -Fxq -- "$package" "$DOTFILES_TEST_ARCH_PACKAGE_STATE" || printf "%s\n" "$package" >>"$DOTFILES_TEST_ARCH_PACKAGE_STATE"
	done
	exit 0
fi
exit 64'
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake omarchy-pkg-add 'printf "omarchy-pkg-add %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake git 'printf "git %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake npx 'printf "npx %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake node 'if [[ ${1-} == --version ]]; then
	printf "v%s\n" "${DOTFILES_TEST_NODE_VERSION:-22.20.0}"
	exit 0
fi
exec "$DOTFILES_TEST_REAL_NODE" "$@"'
	make_fake npm 'exit 0'
}

brave_metadata_key() {
	printf '%s' "$1" | sha256sum | { read -r digest _; printf '%s\n' "$digest"; }
}

set_brave_metadata() {
	local logical=$1 uid=$2 gid=$3 mode=$4 key
	key=$(brave_metadata_key "$logical")
	printf '%s %s %s\n' "$uid" "$gid" "$mode" >"$BRAVE_METADATA_ROOT/$key"
}

setup_brave_fixture() {
	mkdir -p "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	chmod 0755 "$FIXTURE_BRAVE_SYSTEM" "$FIXTURE_BRAVE_SYSTEM/policies" "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	set_brave_metadata /etc/brave 0 0 0755
	set_brave_metadata /etc/brave/policies 0 0 0755
	set_brave_metadata /etc/brave/policies/managed 0 0 0755
	: >"$BRAVE_PACKAGE_DB"
	: >"$BRAVE_PROVIDER_DB"
	: >"$BRAVE_OWNER_DB"
}

install_brave_consumer() {
	local package=$1 version=${2-1:1.93.136-1} command path
	case $package in
		brave-bin) command=brave ;;
		brave-origin-bin) command=brave-origin ;;
		*) return 2 ;;
	esac
	path="$FIXTURE_BIN/$command"
	printf '%s|%s\n' "$package" "$version" >>"$BRAVE_PACKAGE_DB"
	printf '%s|%s\n' "$command" "$path" >>"$BRAVE_PROVIDER_DB"
	printf '%s|%s\n' "$path" "$package" >>"$BRAVE_OWNER_DB"
	make_fake "$command" 'printf "BROWSER EXECUTED: %s\n" "$0 $*" >>"$DOTFILES_TEST_CALL_LOG"
	exit 99'
}

add_brave_color_policy() {
	local content=${1-'{"BrowserThemeColor":"#123456","BrowserColorScheme":1}'} uid
	uid=$(id -u)
	printf '%s\n' "$content" >"$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json"
	chmod 0644 "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json"
	set_brave_metadata /etc/brave/policies/managed/color.json "$uid" "$(id -g)" 0644
}

add_brave_foreign_policy() {
	local name=$1 content=$2 uid=${3-0} gid=${4-0} mode=${5-0644}
	printf '%s\n' "$content" >"$FIXTURE_BRAVE_SYSTEM/policies/managed/$name"
	chmod "$mode" "$FIXTURE_BRAVE_SYSTEM/policies/managed/$name"
	set_brave_metadata "/etc/brave/policies/managed/$name" "$uid" "$gid" "$mode"
}

seed_brave_canaries() {
	mkdir -p "$BRAVE_CANARY_ROOT/profile/Default" "$BRAVE_CANARY_ROOT/themes" "$BRAVE_CANARY_ROOT/fonts" "$BRAVE_CANARY_ROOT/packages" \
		"$FIXTURE_HOME/.config" "$FIXTURE_OMARCHY"
	printf 'profile preferences\n' >"$BRAVE_CANARY_ROOT/profile/Default/Preferences"
	printf 'secure preferences\n' >"$BRAVE_CANARY_ROOT/profile/Default/Secure Preferences"
	printf 'local state\n' >"$BRAVE_CANARY_ROOT/profile/Local State"
	printf 'theme state\n' >"$BRAVE_CANARY_ROOT/themes/current"
	printf 'font state\n' >"$BRAVE_CANARY_ROOT/fonts/current"
	printf 'package state\n' >"$BRAVE_CANARY_ROOT/packages/current"
	printf 'brave flags\n' >"$FIXTURE_HOME/.config/brave-flags.conf"
	printf 'origin flags\n' >"$FIXTURE_HOME/.config/brave-origin-flags.conf"
	printf 'packaged Omarchy\n' >"$FIXTURE_OMARCHY/brave-sentinel"
}

snapshot_brave_canaries() {
	(
		cd -- "$FIXTURE_ROOT" || return 1
		find brave-canaries user/home/.config packaged-omarchy -type f -printf '%P|%m|%s|%T@\n' | sort
		find brave-canaries user/home/.config packaged-omarchy -type f -print0 | sort -z | xargs -0 sha256sum
	)
}

seed_active_brave_policy() {
	local source=${1-"$FIXTURE_REPO/brave/managed-policy.json"}
	local digest transaction timestamp state_root receipt
	digest=$(sha256sum "$source" | { read -r value _; printf '%s\n' "$value"; })
	transaction=20260823T120000Z-1000-deadbeef
	timestamp=2026-08-23T12:00:00Z
	state_root="$FIXTURE_STATE/dotfiles/brave-policy"
	mkdir -p "$state_root"
	chmod 0700 "$state_root"
	cp "$source" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	chmod 0644 "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	set_brave_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0644
	receipt=$(jq -cn --arg digest "$digest" --arg transaction "$transaction" --arg timestamp "$timestamp" \
		'{schema_version:1,kind:"active",target:"/etc/brave/policies/managed/dotfiles.json",source:"brave/managed-policy.json",deployed_digest:$digest,transaction_id:$transaction,activated_at:$timestamp,managed_directory_original:{present:true,uid:0,gid:0,mode:"0777"}}')
	printf '%s\n' "$receipt" >"$state_root/active.json"
	chmod 0600 "$state_root/active.json"
}

use_empty_package_catalog() {
	cat >"$FIXTURE_REPO/packages.json" <<'EOF'
{
	"packages": []
}
EOF
}

restricted_path_without_stow() {
	local restricted_bin=$FIXTURE_ROOT/restricted-bin command command_path
	mkdir -p "$restricted_bin"
	for command in bash basename cp date diff dirname env find grep head jq ln mktemp mv readlink rm sha256sum sort; do
		command_path=$(command -v "$command") || return 1
		ln -s "$command_path" "$restricted_bin/$command"
	done
	printf '%s:%s\n' "$FIXTURE_BIN" "$restricted_bin"
}

add_package() {
	local name=${1-demo}
	mkdir -p "$FIXTURE_REPO/config/$name/.config/$name"
	printf 'setting=true\n' >"$FIXTURE_REPO/config/$name/.config/$name/config"
	printf 'package documentation\n' >"$FIXTURE_REPO/$name.md"
	cat >"$FIXTURE_REPO/packages.json" <<EOF
{
	"packages": [{
		"name": "$name",
		"path": "config/$name",
		"description": "Test package",
		"dependencies": [],
		"arch_packages": [],
		"prerequisites": ["test-validator", "test-validator-two"],
		"validators": ["test-validator --check", "test-validator-two --check"],
		"documentation": "$name.md",
		"cleanup": ["Generated state remains in ~/.local/state/$name"]
	}]
}
EOF
	make_fake test-validator 'printf "validator %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake test-validator-two 'printf "validator-two %s|PWD=%s\n" "$*" "$PWD" >>"$DOTFILES_TEST_CALL_LOG"'
}

add_dependent_package() {
	local name=$1
	local dependency=$2
	mkdir -p "$FIXTURE_REPO/config/$name/.config/$name"
	printf 'setting=true\n' >"$FIXTURE_REPO/config/$name/.config/$name/config"
	jq --arg name "$name" --arg dependency "$dependency" '.packages += [{
		"name": $name,
		"path": ("config/" + $name),
		"description": "Dependent test package",
		"dependencies": [$dependency],
		"arch_packages": [],
		"prerequisites": [],
		"validators": [],
		"documentation": null,
		"cleanup": []
	}]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
}

set_package_arch_packages() {
	local package=$1
	shift
	local arch_packages
	arch_packages=$(jq -cn --args '$ARGS.positional' "$@")
	jq --arg package "$package" --argjson arch_packages "$arch_packages" \
		'(.packages[] | select(.name == $package).arch_packages) = $arch_packages' \
		"$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
}

set_installed_arch_packages() {
	: >"$ARCH_PACKAGE_STATE"
	if (($# > 0)); then
		printf '%s\n' "$@" >"$ARCH_PACKAGE_STATE"
	fi
}

make_applying_stow() {
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " != *" --simulate "* ]]; then
	package=${!#}
	mkdir -p "$HOME/.config"
	ln -s "$DOTFILES_TEST_REPO/config/$package/.config/$package" "$HOME/.config/$package"
fi'
}

make_fake() {
	local name=$1
	local body=$2

	{
		printf '#!/usr/bin/env bash\n'
		printf 'set -u\n'
		printf '%s\n' "$body"
	} >"$FIXTURE_BIN/$name"
	chmod +x "$FIXTURE_BIN/$name"
}

make_gum_responder() {
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == choose ]]; then
	shift
	delimiter=
	options=()
	while (( $# > 0 )); do
		case $1 in
			--header) shift 2 ;;
			--label-delimiter=*) delimiter=${1#*=}; shift ;;
			--*) shift ;;
			*) options+=("$1"); shift ;;
		esac
	done
	response=$(sed -n "1p" "$DOTFILES_TEST_GUM_RESPONSES")
	sed "1d" "$DOTFILES_TEST_GUM_RESPONSES" >"$DOTFILES_TEST_GUM_RESPONSES.next"
	mv "$DOTFILES_TEST_GUM_RESPONSES.next" "$DOTFILES_TEST_GUM_RESPONSES"
	[[ -n $response ]] || exit 0
	for option in "${options[@]}"; do
		value=$option
		if [[ -n $delimiter && $option == *"$delimiter"* ]]; then value=${option##*"$delimiter"}; fi
		if [[ $response == "$value" ]]; then printf "%s\n" "$value"; exit 0; fi
	done
	exit 65
fi
if [[ ${1-} == confirm ]]; then exit 0; fi
exit 64'
}

configure_cleanup_fakes() {
	local installed=$FIXTURE_ROOT/installed-packages
	local explicit=$FIXTURE_ROOT/explicit-packages
	local metadata=$FIXTURE_ROOT/package-metadata
	printf '%s\n' base bash chromium jq moonlight-qt optional-app yay omarchy >"$installed"
	printf '%s\n' base bash chromium jq moonlight-qt optional-app yay omarchy >"$explicit"
	printf '%s\n' \
		'Name            : chromium' \
		$'Description     : Chromium\t| web browser' \
		'' \
		'Name            : moonlight-qt' \
		'Description     : GameStream client, desktop' \
		'' \
		'Name            : optional-app' \
		'Description     : Optional desktop application' >"$metadata"
	make_fake yay 'printf "yay %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ $* == -Qqe ]]; then cat "$DOTFILES_TEST_EXPLICIT_PACKAGES"; exit 0; fi
if [[ $* == -Qi ]]; then
	[[ $DOTFILES_TEST_YAY_METADATA_FAILURE == false ]] || exit 72
	[[ ${LC_ALL-} == C ]] || exit 66
	cat "$DOTFILES_TEST_PACKAGE_METADATA"
	exit 0
fi
exit 64'
	make_fake pacman 'printf "pacman %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
case ${1-} in
	-Qqo)
		case ${2##*/} in
			bash) printf "bash\n" ;;
			jq) printf "jq\n" ;;
			find) printf "findutils\n" ;;
			grep) printf "grep\n" ;;
			sort|basename|mktemp|rm) printf "coreutils\n" ;;
			pacman) printf "pacman\n" ;;
			yay) printf "yay\n" ;;
			omarchy) printf "omarchy\n" ;;
			gum) printf "gum\n" ;;
		esac
		;;
	-Qq)
		if (( $# == 1 )) && [[ $DOTFILES_TEST_PACMAN_VERIFY_FAILURE == true ]]; then exit 74
		elif (( $# == 1 )); then cat "$DOTFILES_TEST_INSTALLED_PACKAGES"
		elif grep -Fxq -- "$2" "$DOTFILES_TEST_INSTALLED_PACKAGES"; then printf "%s\n" "$2"
		else exit 1
		fi
		;;
	*) exit 64 ;;
esac'
	make_fake omarchy 'printf "%s|HOME=%s|XDG_CONFIG_HOME=%s|XDG_STATE_HOME=%s|XDG_CACHE_HOME=%s\n" "$*" "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "%s\n" "${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"; exit 0; fi
if [[ ${1-} == pkg && ${2-} == present ]]; then
	shift 2
	for package in "$@"; do grep -Fxq -- "$package" "$DOTFILES_TEST_ARCH_PACKAGE_STATE" || exit 1; done
	if [[ $DOTFILES_TEST_ARCH_VERIFY_FAILURE == true && -e $DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER ]]; then exit 75; fi
	exit 0
fi
if [[ ${1-} == pkg && ${2-} == add ]]; then
	touch "$DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER"
	[[ $DOTFILES_TEST_ARCH_INSTALL_FAILURE == false ]] || exit 76
	for package in "${@:3}"; do grep -Fxq -- "$package" "$DOTFILES_TEST_ARCH_PACKAGE_STATE" || printf "%s\n" "$package" >>"$DOTFILES_TEST_ARCH_PACKAGE_STATE"; done
	exit 0
fi
if [[ ${1-} == webapp && ${2-} == remove ]]; then rm -f "$HOME/.local/share/applications/${*:3}.desktop"; exit 0; fi
if [[ ${1-} == tui && ${2-} == remove ]]; then rm -f "$HOME/.local/share/applications/${*:3}.desktop"; exit 0; fi
if [[ ${1-} == pkg && ${2-} == drop ]]; then
	for package in "${@:3}"; do grep -Fvx -- "$package" "$DOTFILES_TEST_INSTALLED_PACKAGES" >"$DOTFILES_TEST_INSTALLED_PACKAGES.next" || true; mv "$DOTFILES_TEST_INSTALLED_PACKAGES.next" "$DOTFILES_TEST_INSTALLED_PACKAGES"; done
	exit 0
fi
exit 64'
}

add_cleanup_launcher() {
	local name=$1
	local exec_line=$2
	mkdir -p "$FIXTURE_HOME/.local/share/applications"
	printf '[Desktop Entry]\nName=%s\nExec=%s\n' "$name" "$exec_line" >"$FIXTURE_HOME/.local/share/applications/$name.desktop"
}

run_in_sandbox() {
	local working_directory=$1
	local command_path=$2
	local outside_before
	shift 2
	outside_before=$(snapshot_outside_canaries)

	set +e
	COMMAND_OUTPUT=$(
		cd -- "$working_directory" &&
			printf '%b' "${DOTFILES_TEST_INPUT-}" |
			env -i \
				HOME="$FIXTURE_HOME" \
				XDG_DATA_HOME="${DOTFILES_TEST_XDG_DATA_HOME-}" \
				XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
				XDG_STATE_HOME="$FIXTURE_STATE" \
				XDG_CACHE_HOME="$FIXTURE_CACHE" \
				TMPDIR="$FIXTURE_TMP" \
				OMARCHY_PATH="$FIXTURE_OMARCHY" \
				PATH="$command_path" \
				DOTFILES_TEST_CALL_LOG="$CALL_LOG" \
				DOTFILES_TEST_REPO="$FIXTURE_REPO" \
				DOTFILES_TEST_FAKE_BIN="$FIXTURE_BIN" \
				DOTFILES_TEST_HOME="$FIXTURE_HOME" \
				DOTFILES_TEST_OMARCHY_VERSION="${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}" \
				DOTFILES_TEST_SKILL_COUNT_DRIFT="${DOTFILES_TEST_SKILL_COUNT_DRIFT:-false}" \
				DOTFILES_TEST_SKILL_INSTALL_FAILURE="${DOTFILES_TEST_SKILL_INSTALL_FAILURE:-false}" \
				DOTFILES_TEST_SKILL_VERIFY_FAILURE="${DOTFILES_TEST_SKILL_VERIFY_FAILURE:-false}" \
				DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE="${DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE:-false}" \
				DOTFILES_TEST_SKILL_UPDATE_COLLISION="${DOTFILES_TEST_SKILL_UPDATE_COLLISION:-false}" \
				DOTFILES_TEST_SKILL_UNRELATED_FAILURE="${DOTFILES_TEST_SKILL_UNRELATED_FAILURE:-none}" \
				DOTFILES_TEST_GUM_RESPONSES="${DOTFILES_TEST_GUM_RESPONSES-}" \
				DOTFILES_TEST_XDG_DATA_HOME="${DOTFILES_TEST_XDG_DATA_HOME-}" \
				DOTFILES_TEST_INSTALLED_PACKAGES="$FIXTURE_ROOT/installed-packages" \
				DOTFILES_TEST_EXPLICIT_PACKAGES="$FIXTURE_ROOT/explicit-packages" \
				DOTFILES_TEST_PACKAGE_METADATA="$FIXTURE_ROOT/package-metadata" \
				DOTFILES_TEST_ARCH_PACKAGE_STATE="$ARCH_PACKAGE_STATE" \
				DOTFILES_TEST_ARCH_PACKAGE_ADD_MARKER="$ARCH_PACKAGE_ADD_MARKER" \
				DOTFILES_TEST_ARCH_INSTALL_FAILURE="${DOTFILES_TEST_ARCH_INSTALL_FAILURE:-false}" \
				DOTFILES_TEST_ARCH_VERIFY_FAILURE="${DOTFILES_TEST_ARCH_VERIFY_FAILURE:-false}" \
				DOTFILES_TEST_FIND_COUNT="${DOTFILES_TEST_FIND_COUNT-}" \
				DOTFILES_TEST_PACMAN_VERIFY_FAILURE="${DOTFILES_TEST_PACMAN_VERIFY_FAILURE:-false}" \
				DOTFILES_TEST_YAY_METADATA_FAILURE="${DOTFILES_TEST_YAY_METADATA_FAILURE:-false}" \
				DOTFILES_TEST_REAL_NODE="$FIXTURE_REAL_NODE_DIR/$(basename -- "$HOST_NODE_REAL")" \
				DOTFILES_TEST_BRAVE_SYSTEM="$FIXTURE_BRAVE_SYSTEM" \
				DOTFILES_TEST_BRAVE_METADATA="$BRAVE_METADATA_ROOT" \
				DOTFILES_TEST_BRAVE_PACKAGES="$BRAVE_PACKAGE_DB" \
				DOTFILES_TEST_BRAVE_PROVIDERS="$BRAVE_PROVIDER_DB" \
				DOTFILES_TEST_BRAVE_OWNERS="$BRAVE_OWNER_DB" \
				DOTFILES_TEST_BRAVE_FAILURE_MARKERS="$BRAVE_FAILURE_MARKERS" \
				DOTFILES_TEST_BRAVE_UID="${DOTFILES_TEST_BRAVE_UID:-$(id -u)}" \
				DOTFILES_TEST_BRAVE_FAIL_BEFORE="${DOTFILES_TEST_BRAVE_FAIL_BEFORE-}" \
				DOTFILES_TEST_BRAVE_FAIL_AFTER="${DOTFILES_TEST_BRAVE_FAIL_AFTER-}" \
				DOTFILES_TEST_BRAVE_FAIL_RECEIPT="${DOTFILES_TEST_BRAVE_FAIL_RECEIPT-}" \
				DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE="${DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE-}" \
				DOTFILES_TEST_BRAVE_FAIL_BACKUP="${DOTFILES_TEST_BRAVE_FAIL_BACKUP:-false}" \
				DOTFILES_TEST_BRAVE_BACKUP_RACE="${DOTFILES_TEST_BRAVE_BACKUP_RACE:-false}" \
				DOTFILES_TEST_BRAVE_SENSITIVE="${DOTFILES_TEST_BRAVE_SENSITIVE:-$FIXTURE_ROOT/brave-sensitive}" \
				DOTFILES_TEST_BRAVE_FAIL_PREVIEW="${DOTFILES_TEST_BRAVE_FAIL_PREVIEW:-false}" \
				DOTFILES_TEST_BRAVE_CORRUPT_STAGE="${DOTFILES_TEST_BRAVE_CORRUPT_STAGE:-false}" \
				DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA="${DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA-}" \
				DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION="${DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION-}" \
				DOTFILES_TEST_BRAVE_STAGE_LINK_KIND="${DOTFILES_TEST_BRAVE_STAGE_LINK_KIND-}" \
				DOTFILES_TEST_BRAVE_STAGE_REFERENT="${DOTFILES_TEST_BRAVE_STAGE_REFERENT:-$FIXTURE_ROOT/brave-stage-referent}" \
				DOTFILES_TEST_BRAVE_RECEIPT_RACE="${DOTFILES_TEST_BRAVE_RECEIPT_RACE-}" \
				DOTFILES_TEST_BRAVE_RECEIPT_REFERENT="${DOTFILES_TEST_BRAVE_RECEIPT_REFERENT:-$FIXTURE_ROOT/brave-receipt-referent}" \
				DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT="${DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT-}" \
				DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER="${DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER-}" \
				DOTFILES_TEST_BRAVE_RENAME_FAILURE="${DOTFILES_TEST_BRAVE_RENAME_FAILURE-}" \
				DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE="${DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE-}" \
				DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER="${DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER-}" \
				DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER="${DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER:-false}" \
				DOTFILES_TEST_BRAVE_FALSE_SUCCESS="${DOTFILES_TEST_BRAVE_FALSE_SUCCESS-}" \
				DOTFILES_TEST_BRAVE_RACE="${DOTFILES_TEST_BRAVE_RACE-}" \
				DOTFILES_UI="${DOTFILES_UI:-bash}" \
				"$BWRAP" \
					--ro-bind / / \
					--dev-bind /dev /dev \
					--bind "$FIXTURE_ROOT" "$FIXTURE_ROOT" \
					--tmpfs /home \
					--tmpfs /usr/share/omarchy \
					"${BWRAP_EXTRA_ARGS[@]}" \
					-- "$@" 2>&1
	)
	COMMAND_STATUS=$?
	set -e
	if [[ $(snapshot_outside_canaries) != "$outside_before" ]]; then
		OUTSIDE_CANARY_CHANGED=true
	fi
}

run_dotfiles() {
	local working_directory=$1
	shift
	run_in_sandbox "$working_directory" "${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" \
		"$FIXTURE_REPO/bin/dotfiles" "$@"
}

run_operation() {
	local working_directory=$1 operation=$2
	shift 2
	run_in_sandbox "$working_directory" "${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" \
		bash -c '
			set -euo pipefail
			repository=$1
			operation=$2
			shift 2
			source "$repository/lib/dotfiles/core.sh"
			source "$repository/lib/dotfiles/packages.sh"
			source "$repository/lib/dotfiles/skills.sh"
			source "$repository/lib/dotfiles/cleanup.sh"
			source "$repository/lib/dotfiles/modem.sh"
			source "$repository/lib/dotfiles/brave.sh"
			source "$repository/lib/dotfiles/wizard.sh"
			"$operation" "$@"
		' bash "$FIXTURE_REPO" "$operation" "$@"
}

run_brave_operation() {
	local working_directory=$1 operation=$2
	shift 2
	run_in_sandbox "$working_directory" "${DOTFILES_TEST_PATH:-$FIXTURE_BIN:/usr/bin:/bin}" \
		bash -c '
			set -euo pipefail
			repository=$1
			operation=$2
			shift 2
			source "$repository/lib/dotfiles/core.sh"
			source "$repository/lib/dotfiles/brave.sh"

			brave_map_system_path() {
				case $1 in
					/etc/brave) printf "%s\n" "$DOTFILES_TEST_BRAVE_SYSTEM" ;;
					/etc/brave/*) printf "%s/%s\n" "$DOTFILES_TEST_BRAVE_SYSTEM" "${1#/etc/brave/}" ;;
					*) return 2 ;;
				esac
			}
			brave_test_metadata_key() {
				printf "%s" "$1" | sha256sum | { read -r digest _; printf "%s\n" "$digest"; }
			}
			brave_test_set_metadata() {
				local key
				key=$(brave_test_metadata_key "$1")
				printf "%s %s %s\n" "$2" "$3" "$4" >"$DOTFILES_TEST_BRAVE_METADATA/$key"
			}
			brave_test_remove_metadata() {
				local key
				key=$(brave_test_metadata_key "$1")
				rm -f -- "$DOTFILES_TEST_BRAVE_METADATA/$key"
			}
			brave_lstat() {
				local logical=$1 actual type mode uid=0 gid=0 key
				actual=$(brave_map_system_path "$logical") || return 2
				[[ -e $actual || -L $actual ]] || return 1
				type=$(stat -c %F -- "$actual") || return 2
				mode=$(stat -c %a -- "$actual") || return 2
				key=$(brave_test_metadata_key "$logical")
				if [[ -f $DOTFILES_TEST_BRAVE_METADATA/$key ]]; then
					read -r uid gid mode <"$DOTFILES_TEST_BRAVE_METADATA/$key"
				fi
				printf "%s|%s|%s|%s\n" "$type" "$uid" "$gid" "$mode"
			}
			brave_package_version() {
				local wanted=$1 package version
				while IFS="|" read -r package version; do
					[[ $package == "$wanted" ]] || continue
					printf "%s\n" "$version"
					return 0
				done <"$DOTFILES_TEST_BRAVE_PACKAGES"
				return 1
			}
			brave_resolve_provider() {
				local wanted=$1 command provider
				while IFS="|" read -r command provider; do
					[[ $command == "$wanted" ]] || continue
					printf "%s\n" "$provider"
					return 0
				done <"$DOTFILES_TEST_BRAVE_PROVIDERS"
				return 1
			}
			brave_provider_package() {
				local wanted=$1 provider package
				while IFS="|" read -r provider package; do
					[[ $provider == "$wanted" ]] || continue
					printf "%s\n" "$package"
					return 0
				done <"$DOTFILES_TEST_BRAVE_OWNERS"
				return 1
			}
			brave_effective_uid() { printf "%s\n" "$DOTFILES_TEST_BRAVE_UID"; }
			brave_omarchy_version() {
				[[ $DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER != true ]] || printf "recovery-order inspect-omarchy\n" >>"$DOTFILES_TEST_CALL_LOG"
				printf "%s\n" "$DOTFILES_TEST_OMARCHY_VERSION"
			}
			brave_confirm() {
				[[ $DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER != true ]] || printf "recovery-order confirmation %s\n" "$1" >>"$DOTFILES_TEST_CALL_LOG"
				wizard_confirm "$1"
			}
			brave_test_operation_with_context() {
				local requested=$1 outcome=0
				shift
				"$requested" "$@" || outcome=$?
				printf "Brave operation context: %s\n" "$BRAVE_OPERATION_CONTEXT"
				return "$outcome"
			}
			brave_create_state_root() {
				local root=$1 marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/state-root-race"
				if [[ -n $DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT && ! -e $marker ]]; then
					touch "$marker"
					ln -s "$DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT" "$root"
					return 1
				fi
				brave_create_state_root_impl "$root"
			}
			brave_atomic_write_receipt() {
				local kind=$1 marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/receipt-$1"
				if [[ $DOTFILES_TEST_BRAVE_FAIL_RECEIPT == "$kind" && ! -e $marker ]]; then
					touch "$marker"
					return 79
				fi
				brave_atomic_write_receipt_impl "$@"
			}
			brave_publish_receipt_temporary() {
				local temporary=$1 destination=$2 marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/receipt-destination-race"
				if [[ -n $DOTFILES_TEST_BRAVE_RECEIPT_RACE && ! -e $marker ]]; then
					touch "$marker"
					case $DOTFILES_TEST_BRAVE_RECEIPT_RACE in
						directory) mkdir "$destination" ;;
						symlink-directory) ln -s "$DOTFILES_TEST_BRAVE_RECEIPT_REFERENT" "$destination" ;;
						*) return 64 ;;
					esac
				fi
				brave_publish_receipt_temporary_impl "$temporary" "$destination"
			}
			brave_test_attempt_unprivileged_target_replacement() {
				local point=$1 metadata mode_value invoking_uid group allowed=false actual
				metadata=$(brave_lstat /etc/brave/policies/managed) || return 1
				brave_parse_metadata "$metadata" BRAVE_TEST_REPLACEMENT_PARENT || return 1
				mode_value=$(brave_mode_value "$BRAVE_TEST_REPLACEMENT_PARENT_MODE") || return 1
				invoking_uid=$(brave_effective_uid) || return 1
				if [[ $BRAVE_TEST_REPLACEMENT_PARENT_UID == "$invoking_uid" && $((mode_value & 0200)) -ne 0 ]]; then
					allowed=true
				elif (( (mode_value & 0020) != 0 )); then
					for group in $(brave_effective_groups); do
						[[ $group != "$BRAVE_TEST_REPLACEMENT_PARENT_GID" ]] || allowed=true
					done
				fi
				if (( (mode_value & 0002) != 0 )); then allowed=true; fi
				if [[ $allowed != true ]]; then
					printf "unprivileged-target-replacement blocked %s metadata=%s\n" "$point" "$metadata" >>"$DOTFILES_TEST_CALL_LOG"
					return 1
				fi
				actual=$(brave_map_system_path /etc/brave/policies/managed/dotfiles.json) || return 1
				printf "replacement created during owned finalization\n" >"$actual"
				chmod 0644 "$actual"
				brave_test_set_metadata /etc/brave/policies/managed/dotfiles.json "$invoking_uid" "$(id -g)" 0644
				printf "unprivileged-target-replacement created %s metadata=%s\n" "$point" "$metadata" >>"$DOTFILES_TEST_CALL_LOG"
			}
			brave_remove_state_file() {
				local name=${1##*/} marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/remove-${1##*/}"
				[[ $DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER != true ]] || printf "recovery-order remove-state %s\n" "$name" >>"$DOTFILES_TEST_CALL_LOG"
				if [[ $DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE == "$name" && ! -e $DOTFILES_TEST_BRAVE_FAILURE_MARKERS/state-remove-target-replacement ]]; then
					touch "$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/state-remove-target-replacement"
					brave_test_attempt_unprivileged_target_replacement "state-remove-$name" || true
				fi
				if [[ $DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE == "$name" && ! -e $marker ]]; then
					touch "$marker"
					return 80
				fi
				brave_remove_state_file_impl "$@"
			}
			brave_copy_backup() {
				local marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/backup"
				if [[ $DOTFILES_TEST_BRAVE_FAIL_BACKUP == true && ! -e $marker ]]; then
					touch "$marker"
					return 81
				fi
				if [[ $DOTFILES_TEST_BRAVE_BACKUP_RACE == true && $1 == "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/dotfiles.json" && ! -e $DOTFILES_TEST_BRAVE_FAILURE_MARKERS/backup-race ]]; then
					touch "$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/backup-race"
					rm -f -- "$1"
					ln -s "$DOTFILES_TEST_BRAVE_SENSITIVE" "$1"
				fi
				brave_copy_backup_impl "$@"
			}
			brave_copy_preview_snapshot() {
				[[ $DOTFILES_TEST_BRAVE_FAIL_PREVIEW != true ]] || return 82
				brave_copy_backup_impl "$@"
			}
			brave_test_race_once() {
				[[ -n $DOTFILES_TEST_BRAVE_RACE ]] || return 0
				local marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/race-$DOTFILES_TEST_BRAVE_RACE"
				[[ ! -e $marker ]] || return 0
				touch "$marker"
				case $DOTFILES_TEST_BRAVE_RACE in
					source) printf " \n" >>"$repository/brave/managed-policy.json" ;;
					consumers) printf "brave-bin|9:9.9.9-1\n" >"$DOTFILES_TEST_BRAVE_PACKAGES" ;;
					providers) printf "brave|$DOTFILES_TEST_FAKE_BIN/brave\n" >"$DOTFILES_TEST_BRAVE_PROVIDERS"; printf "%s|other-browser\n" "$DOTFILES_TEST_FAKE_BIN/brave" >"$DOTFILES_TEST_BRAVE_OWNERS" ;;
					receipts) [[ ! -f $XDG_STATE_HOME/dotfiles/brave-policy/active.json ]] || printf " \n" >>"$XDG_STATE_HOME/dotfiles/brave-policy/active.json" ;;
					pending) printf " \n" >>"$XDG_STATE_HOME/dotfiles/brave-policy/pending.json" ;;
					backup)
						local recovery_backup
						recovery_backup=$(jq -r ".prior_target.backup_path // .prior_active.backup_path" "$XDG_STATE_HOME/dotfiles/brave-policy/pending.json")
						printf " \n" >>"$recovery_backup"
						;;
					target) [[ ! -f $DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/dotfiles.json ]] || printf " \n" >>"$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/dotfiles.json" ;;
					paths) rm -rf "$DOTFILES_TEST_BRAVE_SYSTEM/policies"; ln -s "$DOTFILES_TEST_BRAVE_SYSTEM" "$DOTFILES_TEST_BRAVE_SYSTEM/policies" ;;
					metadata) brave_test_set_metadata /etc/brave/policies 0 0 0777 ;;
					foreign) printf "{\"RacePolicy\":true}\n" >"$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/race.json"; chmod 0644 "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/race.json"; brave_test_set_metadata /etc/brave/policies/managed/race.json 0 0 0644 ;;
				esac
			}
			brave_test_fail() {
				local phase=$1 operation=$2 configured marker
				[[ $phase == before ]] && configured=$DOTFILES_TEST_BRAVE_FAIL_BEFORE || configured=$DOTFILES_TEST_BRAVE_FAIL_AFTER
				[[ ,$configured, == *,$operation,* ]] || return 1
				marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/$phase-$operation"
				[[ ! -e $marker ]] || return 1
				touch "$marker"
				return 0
			}
			brave_test_seed_stage_link() {
				local operation=$1 stage=$2 marker="$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/stage-link-$1"
				[[ $DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION == "$operation" && ! -e $marker ]] || return 0
				touch "$marker"
				case $DOTFILES_TEST_BRAVE_STAGE_LINK_KIND in
					file|directory) ln -s "$DOTFILES_TEST_BRAVE_STAGE_REFERENT" "$stage" ;;
					*) return 64 ;;
				esac
			}
			brave_privileged_operation() {
				local operation=$1
				shift
				local transaction logical actual stage backup uid gid mode digest expected_identity temporary_mode
				printf "privileged %s" "$operation" >>"$DOTFILES_TEST_CALL_LOG"
				printf " %q" "$@" >>"$DOTFILES_TEST_CALL_LOG"
				printf "\n" >>"$DOTFILES_TEST_CALL_LOG"
				if brave_test_fail before "$operation"; then return 77; fi
				if [[ ,$DOTFILES_TEST_BRAVE_FALSE_SUCCESS, == *,$operation,* ]]; then
					printf "false-success %s\n" "$operation" >>"$DOTFILES_TEST_CALL_LOG"
					return 0
				fi
				case $operation in
					acquire)
						printf "/usr/bin/sudo -v\n" >>"$DOTFILES_TEST_CALL_LOG"
						brave_test_race_once
						;;
					create-managed)
						mkdir -p "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						chmod 0755 "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						brave_test_set_metadata /etc/brave/policies/managed 0 0 0755
						printf "/usr/bin/sudo /usr/bin/install -d -o root -g root -m 0755 -- /etc/brave/policies/managed\n" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					harden-managed)
						chmod 0755 "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						brave_test_set_metadata /etc/brave/policies/managed 0 0 0755
						printf "/usr/bin/sudo /usr/bin/chown 0:0 -- /etc/brave/policies/managed\n/usr/bin/sudo /usr/bin/chmod 0755 -- /etc/brave/policies/managed\n" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					write-stage)
						transaction=$1 logical="/etc/brave/policies/.dotfiles-$transaction.stage" actual=$(brave_map_system_path "$logical")
						brave_test_seed_stage_link write-stage "$actual" || return 1
						rm -f -- "$actual"
						cp "$repository/brave/managed-policy.json" "$actual"
						chmod 0644 "$actual"
						brave_test_set_metadata "$logical" 0 0 0644
						brave_validate_stage "$transaction" || return 1
						printf "brave_json emit-no-follow | /usr/bin/sudo /usr/bin/install -T -o root -g root -m 0644 -- /dev/stdin %s\n" "$logical" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					publish-stage)
						transaction=$1 expected_identity=$2 logical="/etc/brave/policies/.dotfiles-$transaction.stage" stage=$(brave_map_system_path "$logical") actual=$(brave_map_system_path /etc/brave/policies/managed/dotfiles.json)
						[[ $(brave_validate_stage_file_metadata "$transaction" 0 0 0644) == "$expected_identity" ]] || return 1
						printf "/usr/bin/sudo /usr/bin/mv --no-copy -fT -- %s /etc/brave/policies/managed/dotfiles.json\n" "$logical" >>"$DOTFILES_TEST_CALL_LOG"
						if [[ $DOTFILES_TEST_BRAVE_RENAME_FAILURE == publish-stage ]]; then
							printf "simulated cross-filesystem rename failure: publish-stage\n" >>"$DOTFILES_TEST_CALL_LOG"
							return 1
						fi
						/usr/bin/mv --no-copy -fT -- "$stage" "$actual"
						brave_test_remove_metadata "$logical"
						brave_test_set_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0644
						;;
					remove-target)
						rm -f "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed/dotfiles.json"
						brave_test_remove_metadata /etc/brave/policies/managed/dotfiles.json
						printf "/usr/bin/sudo /usr/bin/rm -f -- /etc/brave/policies/managed/dotfiles.json\n" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					remove-stage)
						transaction=$1 logical="/etc/brave/policies/.dotfiles-$transaction.stage" actual=$(brave_map_system_path "$logical")
						rm -f "$actual"
						brave_test_remove_metadata "$logical"
						printf "/usr/bin/sudo /usr/bin/rm -f -- %s\n" "$logical" >>"$DOTFILES_TEST_CALL_LOG"
						;;
				restore-target)
					transaction=$1 backup=$2 uid=$3 gid=$4 mode=$5 digest=$6
					temporary_mode=$(brave_mode_without_write_bits "$mode") || return 1
					logical="/etc/brave/policies/.dotfiles-$transaction.stage" stage=$(brave_map_system_path "$logical")
					brave_test_seed_stage_link restore-target "$stage" || return 1
					rm -f -- "$stage"
					cp "$backup" "$stage"
					chmod "$temporary_mode" "$stage"
					brave_test_set_metadata "$logical" "$uid" "$gid" "$temporary_mode"
					brave_validate_restore_stage "$transaction" "$backup" "$uid" "$gid" "$temporary_mode" "$digest" || return 1
					expected_identity=$BRAVE_VALIDATED_STAGE_IDENTITY
					[[ $(brave_validate_stage_file_metadata "$transaction" "$uid" "$gid" "$temporary_mode") == "$expected_identity" ]] || return 1
					actual=$(brave_map_system_path /etc/brave/policies/managed/dotfiles.json)
					printf "brave_json emit-no-follow | /usr/bin/sudo /usr/bin/install -T -o %s -g %s -m %s -- /dev/stdin %s\n/usr/bin/sudo /usr/bin/mv --no-copy -fT -- %s /etc/brave/policies/managed/dotfiles.json\n" "$uid" "$gid" "$temporary_mode" "$logical" "$logical" >>"$DOTFILES_TEST_CALL_LOG"
					if [[ $DOTFILES_TEST_BRAVE_RENAME_FAILURE == restore-target ]]; then
						printf "simulated cross-filesystem rename failure: restore-target\n" >>"$DOTFILES_TEST_CALL_LOG"
						return 1
					fi
					/usr/bin/mv --no-copy -fT -- "$stage" "$actual"
					brave_test_remove_metadata "$logical"
					brave_test_set_metadata /etc/brave/policies/managed/dotfiles.json "$uid" "$gid" "$temporary_mode"
					chmod "$mode" "$actual"
					brave_test_set_metadata /etc/brave/policies/managed/dotfiles.json "$uid" "$gid" "$mode"
					brave_validate_target_against_backup "$backup" "$uid" "$gid" "$mode" "$digest" || return 1
					printf "/usr/bin/sudo /usr/bin/chmod %s -- /etc/brave/policies/managed/dotfiles.json\n" "$mode" >>"$DOTFILES_TEST_CALL_LOG"
					;;
					restore-managed)
						uid=$1 gid=$2 mode=$3
						chmod "$mode" "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						brave_test_set_metadata /etc/brave/policies/managed "$uid" "$gid" "$mode"
						printf "/usr/bin/sudo /usr/bin/chown %s:%s -- /etc/brave/policies/managed\n/usr/bin/sudo /usr/bin/chmod %s -- /etc/brave/policies/managed\n" "$uid" "$gid" "$mode" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					remove-managed)
						rmdir "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
						brave_test_remove_metadata /etc/brave/policies/managed
						printf "/usr/bin/sudo /usr/bin/rmdir -- /etc/brave/policies/managed\n" >>"$DOTFILES_TEST_CALL_LOG"
						;;
					*) return 64 ;;
				esac
				if [[ $operation == write-stage && $DOTFILES_TEST_BRAVE_CORRUPT_STAGE == true ]]; then
					printf "corrupt\n" >>"$actual"
				fi
				if [[ $operation == write-stage && -n $DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA ]]; then
					case $DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA in
						owner) brave_test_set_metadata "$logical" 1000 1000 0644 ;;
						group) brave_test_set_metadata "$logical" 0 1000 0644 ;;
						mode) brave_test_set_metadata "$logical" 0 0 0666 ;;
						*) return 64 ;;
					esac
				fi
				if [[ $DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER == "$operation" && ! -e $DOTFILES_TEST_BRAVE_FAILURE_MARKERS/managed-replacement ]]; then
					touch "$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/managed-replacement"
					rmdir "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed" || return 1
					mkdir "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
					chmod 0755 "$DOTFILES_TEST_BRAVE_SYSTEM/policies/managed"
					brave_test_set_metadata /etc/brave/policies/managed 0 0 0755
				fi
				if [[ $DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER == "$operation" && ! -e $DOTFILES_TEST_BRAVE_FAILURE_MARKERS/target-replacement-after-operation ]]; then
					touch "$DOTFILES_TEST_BRAVE_FAILURE_MARKERS/target-replacement-after-operation"
					brave_test_attempt_unprivileged_target_replacement "after-$operation" || true
				fi
				if brave_test_fail after "$operation"; then return 78; fi
			}

			source "$repository/lib/dotfiles/wizard.sh"
			"$operation" "$@"
		' bash "$FIXTURE_REPO" "$operation" "$@"
}

configure_skill_fakes() {
	make_fake git 'printf "git %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == clone ]]; then
	destination=${!#}
	mkdir -p "$destination"
	case $* in
		*blader/humanizer*) printf "humanizer\n" >"$destination/.test-source" ;;
		*mattpocock/skills*) printf "matt\n" >"$destination/.test-source" ;;
	esac
fi'
	make_fake npx 'printf "npx %s|HOME=%s|STATE=%s|CACHE=%s|TELEMETRY=%s\n" "$*" "$HOME" "$XDG_STATE_HOME" "$npm_config_cache" "$DISABLE_TELEMETRY" >>"$DOTFILES_TEST_CALL_LOG"
source_root=${4-}
source_name=$(<"$source_root/.test-source")
target=$HOME/.agents/skills
mkdir -p "$target"
if [[ $source_name == humanizer ]]; then
	mkdir -p "$target/humanizer/references"
	printf "approved humanizer\n" >"$target/humanizer/SKILL.md"
	printf "support file\n" >"$target/humanizer/references/style.md"
else
	count=35
	if [[ $DOTFILES_TEST_SKILL_COUNT_DRIFT == true ]]; then count=34; fi
	for ((i = 1; i <= count; i++)); do
		name=$(printf "matt-skill-%02d" "$i")
		mkdir -p "$target/$name/assets"
		printf "approved %s\n" "$name" >"$target/$name/SKILL.md"
		printf "payload %s\n" "$name" >"$target/$name/assets/example.txt"
	done
	if [[ $HOME == "$DOTFILES_TEST_HOME" && $DOTFILES_TEST_SKILL_VERIFY_FAILURE == true ]]; then
		printf "corrupt global payload\n" >"$target/matt-skill-01/SKILL.md"
	fi
	if [[ $HOME == "$DOTFILES_TEST_HOME" && $DOTFILES_TEST_SKILL_INSTALL_FAILURE == true ]]; then
		printf "mutated before installer failure\n" >"$target/matt-skill-01/SKILL.md"
		exit 71
	fi
fi
if [[ $HOME == "$DOTFILES_TEST_HOME" ]]; then
	case $DOTFILES_TEST_SKILL_UNRELATED_FAILURE in
		modify) printf "installer damage\n" >"$target/private-skill" ;;
		delete) rm -rf "$target/private-skill" ;;
		add) printf "unexpected\n" >"$target/rogue-skill" ;;
		other-source) if [[ $source_name == matt ]]; then printf "installer damage\n" >"$target/humanizer/SKILL.md"; fi ;;
	esac
fi'
}

configure_skill_update_fakes() {
	configure_skill_fakes
	make_fake git 'printf "git %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
old_humanizer=523374dee72d67c7b2b5f858ea0094ffda49c3ac
old_matt=068b6e0c62393147daf03530149cdce209c93da8
new_matt=ffffffffffffffffffffffffffffffffffffffff
if [[ ${1-} == clone ]]; then
	destination=${!#}
	mkdir -p "$destination"
	case $* in
		*blader/humanizer*) printf "humanizer\n" >"$destination/.test-source"; revision=$old_humanizer ;;
		*mattpocock/skills*) printf "matt\n" >"$destination/.test-source"; revision=$new_matt ;;
	esac
	if [[ $DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE == true ]]; then
		[[ $(<"$destination/.test-source") == humanizer ]] && revision=$old_humanizer || revision=$old_matt
	fi
	printf "%s\n" "$revision" >"$destination/.test-revision"
	exit 0
fi
if [[ ${1-} == -C ]]; then
	checkout=$2
	command=$3
	case $command in
		checkout) printf "%s\n" "${6-}" >"$checkout/.test-revision" ;;
		rev-parse) cat "$checkout/.test-revision" ;;
		log) printf "fffffff Add and revise official skills\n" ;;
		diff) printf "diff --git a/skills/matt b/skills/matt\n+upstream source change\n" ;;
	esac
fi'
	make_fake npx 'printf "npx %s|HOME=%s|STATE=%s|CACHE=%s|TELEMETRY=%s\n" "$*" "$HOME" "$XDG_STATE_HOME" "$npm_config_cache" "$DISABLE_TELEMETRY" >>"$DOTFILES_TEST_CALL_LOG"
source_root=${4-}
source_name=$(<"$source_root/.test-source")
revision=$(<"$source_root/.test-revision")
target=$HOME/.agents/skills
mkdir -p "$target"
if [[ $source_name == humanizer ]]; then
	mkdir -p "$target/humanizer/references"
	printf "approved humanizer\n" >"$target/humanizer/SKILL.md"
	printf "support file\n" >"$target/humanizer/references/style.md"
else
	old_matt=068b6e0c62393147daf03530149cdce209c93da8
	if [[ $revision == "$old_matt" ]]; then
		names=$(seq -w 1 35)
	else
		names="$(seq -w 1 34) 36 37"
	fi
	for i in $names; do
		name=matt-skill-$i
		mkdir -p "$target/$name/assets"
		if [[ $revision != "$old_matt" && $i == 01 ]]; then
			printf "updated %s\n" "$name" >"$target/$name/SKILL.md"
		else
			printf "approved %s\n" "$name" >"$target/$name/SKILL.md"
		fi
		printf "payload %s\n" "$name" >"$target/$name/assets/example.txt"
	done
	if [[ $revision != "$old_matt" && $DOTFILES_TEST_SKILL_UPDATE_COLLISION == true ]]; then
		mkdir -p "$target/humanizer"
		printf "colliding matt humanizer\n" >"$target/humanizer/SKILL.md"
	fi
	if [[ $HOME == "$DOTFILES_TEST_HOME" && $revision != "$old_matt" && $DOTFILES_TEST_SKILL_VERIFY_FAILURE == true ]]; then
		printf "corrupt global payload\n" >"$target/matt-skill-01/SKILL.md"
	fi
	if [[ $HOME == "$DOTFILES_TEST_HOME" && $revision != "$old_matt" && $DOTFILES_TEST_SKILL_INSTALL_FAILURE == true ]]; then
		printf "mutated before installer failure\n" >"$target/matt-skill-02/SKILL.md"
		exit 71
	fi
fi
if [[ $HOME == "$DOTFILES_TEST_HOME" ]]; then
	case $DOTFILES_TEST_SKILL_UNRELATED_FAILURE in
		modify) printf "installer damage\n" >"$target/private-skill" ;;
		delete) rm -rf "$target/private-skill" ;;
		add) printf "unexpected\n" >"$target/rogue-skill" ;;
		other-source) if [[ $source_name == matt ]]; then printf "installer damage\n" >"$target/humanizer/SKILL.md"; fi ;;
	esac
fi'
}

seed_current_global_skills() {
	mkdir -p "$FIXTURE_HOME/.agents/skills/humanizer/references"
	printf 'approved humanizer\n' >"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md"
	printf 'support file\n' >"$FIXTURE_HOME/.agents/skills/humanizer/references/style.md"
	local i name
	for ((i = 1; i <= 35; i++)); do
		name=$(printf 'matt-skill-%02d' "$i")
		mkdir -p "$FIXTURE_HOME/.agents/skills/$name/assets"
		printf 'approved %s\n' "$name" >"$FIXTURE_HOME/.agents/skills/$name/SKILL.md"
		printf 'payload %s\n' "$name" >"$FIXTURE_HOME/.agents/skills/$name/assets/example.txt"
	done
}

global_skill_installer_calls() {
	awk -v home="HOME=$FIXTURE_HOME" '/^npx / && index($0, home) { count++ } END { print count + 0 }' "$CALL_LOG"
}

global_skill_installer_calls_for_source() {
	local source_index=$1
	awk -v home="HOME=$FIXTURE_HOME" -v source="/source-$source_index " \
		'/^npx / && index($0, home) && index($0, source) { count++ } END { print count + 0 }' "$CALL_LOG"
}

run_make() {
	local working_directory=$1
	run_in_sandbox "$working_directory" "$FIXTURE_BIN:/usr/bin:/bin" \
		make --no-print-directory -C "$FIXTURE_REPO"
}

run_dotfiles_without_real_user_or_omarchy_paths() {
	run_operation "$FIXTURE_ROOT" check
}

snapshot_isolated_paths() {
	local path
	for path in \
		"$FIXTURE_HOME/.agents/skills/sentinel" \
		"$FIXTURE_CONFIG/omarchy/sentinel" \
		"$FIXTURE_STATE/sentinel" \
		"$FIXTURE_CACHE/sentinel" \
		"$FIXTURE_OMARCHY/sentinel"; do
		printf '%s:' "$path"
		if [[ -e $path ]]; then
			sha256sum "$path"
		else
			printf 'missing\n'
		fi
	done
}

snapshot_outside_canaries() {
	(
		cd -- "$OUTSIDE_ROOT" || return 1
		find . -printf '%P|%y|%m|%s|%T@\n' | sort
		sha256sum user-config/sentinel global-skills/sentinel packaged-omarchy/sentinel
	)
}

run_test() {
	local name=$1
	local description=$2
	local test_failed=false

	TESTS_RUN=$((TESTS_RUN + 1))
	OUTSIDE_CANARY_CHANGED=false
	if ! "$name"; then
		test_failed=true
	fi
	if [[ $OUTSIDE_CANARY_CHANGED == true ]] || \
		{ [[ -n ${OUTSIDE_ROOT-} && -d $OUTSIDE_ROOT ]] && \
			[[ $(snapshot_outside_canaries) != "$OUTSIDE_SNAPSHOT" ]]; }; then
		printf '  paths outside the fixture roots changed during %s\n' "$description" >&2
		test_failed=true
	fi
	if [[ $test_failed == true ]]; then
		fail "$description"
	else
		pass "$description"
	fi
	if [[ -n ${FIXTURE_ROOT-} && -d $FIXTURE_ROOT ]]; then
		rm -rf "$FIXTURE_ROOT"
	fi
	if [[ -n ${OUTSIDE_ROOT-} && -d $OUTSIDE_ROOT ]]; then
		rm -rf "$OUTSIDE_ROOT"
	fi
}

finish_tests() {
	printf '1..%d\n' "$TESTS_RUN"
	return "$TESTS_FAILED"
}
