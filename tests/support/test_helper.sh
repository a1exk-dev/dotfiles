#!/usr/bin/env bash

set -u

SOURCE_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
BWRAP=$(command -v bwrap)
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

	mkdir -p "$FIXTURE_REPO/bin" "$FIXTURE_REPO/lib/dotfiles" "$FIXTURE_HOME" "$FIXTURE_CONFIG" \
		"$FIXTURE_STATE" "$FIXTURE_CACHE" "$FIXTURE_TMP" "$FIXTURE_BIN" "$FIXTURE_OMARCHY" \
		"$OUTSIDE_ROOT/user-config" "$OUTSIDE_ROOT/global-skills" "$OUTSIDE_ROOT/packaged-omarchy"
	printf 'outside user configuration\n' >"$OUTSIDE_ROOT/user-config/sentinel"
	printf 'outside global skill\n' >"$OUTSIDE_ROOT/global-skills/sentinel"
	printf 'outside packaged Omarchy\n' >"$OUTSIDE_ROOT/packaged-omarchy/sentinel"
	OUTSIDE_SNAPSHOT=$(snapshot_outside_canaries)
	: >"$CALL_LOG"
	printf 'thefuck\n' >"$ARCH_PACKAGE_STATE"
	cp "$SOURCE_REPO/bin/dotfiles" "$FIXTURE_REPO/bin/dotfiles"
	cp "$SOURCE_REPO/lib/dotfiles/"*.sh "$FIXTURE_REPO/lib/dotfiles/"
	cp "$SOURCE_REPO/packages.json" "$FIXTURE_REPO/packages.json"
	cp "$SOURCE_REPO/cleanup.json" "$FIXTURE_REPO/cleanup.json"
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
	make_fake node 'printf "v%s\n" "${DOTFILES_TEST_NODE_VERSION:-22.20.0}"'
	make_fake npm 'exit 0'
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
