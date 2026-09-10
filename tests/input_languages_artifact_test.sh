#!/usr/bin/env bash

set -u

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly REPOSITORY_ROOT=$(cd -- "$TEST_ROOT/.." && pwd)
source "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh"

ARTIFACT_FIXTURE=

cleanup_artifact_fixture() {
	[[ -n $ARTIFACT_FIXTURE ]] || return 0
	chmod -R u+w -- "$ARTIFACT_FIXTURE" 2>/dev/null || true
	rm -rf -- "$ARTIFACT_FIXTURE"
}
trap cleanup_artifact_fixture EXIT

prepare_artifact_fixture() {
	[[ -z $ARTIFACT_FIXTURE ]] || return 0
	local initial
	initial=$(mktemp -d)
	ARTIFACT_FIXTURE="$initial path:%\$with\`tick and spaces"
	mv -- "$initial" "$ARTIFACT_FIXTURE"
	export HOME=$ARTIFACT_FIXTURE/home
	export XDG_CONFIG_HOME=$HOME/.config
	export XDG_DATA_HOME=$HOME/.local/share
	export XDG_STATE_HOME=$HOME/.local/state
	mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
	input_languages_set_paths
	INPUT_LANGUAGES_COMPILER=$(/usr/bin/c++ -dumpfullversion -dumpversion)
	INPUT_LANGUAGES_HEADER_HASH=$(input_languages_header_hash)
	input_languages_build_integration_artifact >/dev/null
}

complete_immutable_integration_artifact_is_published_inertly() {
	prepare_artifact_fixture || return 1
	local first_artifact=$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR first_build=$INPUT_LANGUAGES_INTEGRATION_BUILD_ID first_mtime
	first_mtime=$(stat -c %y -- "$first_artifact/build.json") || return 1
	input_languages_build_integration_artifact >/dev/null || return 1
	[[ $INPUT_LANGUAGES_INTEGRATION_BUILD_ID == "$first_build" && $INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR == "$first_artifact" &&
		$(stat -c %y -- "$first_artifact/build.json") == "$first_mtime" ]] || return 1
	input_languages_validate_integration_artifact_self "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" || return 1
	local entries
	entries=$(find "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort) || return 1
	[[ $entries == $'build.json\ncontracts\ndotfiles.keyboard-layout\ninput-languages-fcitx-helper\ninput-languages.so\nsystemd' ]] || return 1
	jq -e '
		.version == 1 and .integration == "dotfiles-input-languages-fcitx-v1" and
		(.source_id | test("^[0-9a-f]{64}$")) and (.build_id | test("^[0-9a-f]{64}$")) and
		(.dependencies | contains("fcitx-upstream=5.1.21")) and
		(.dependencies | contains("libsystemd=")) and (.dependencies | contains("libcrypto=")) and
		(.linker | startswith("GNU ld ")) and
		(.inventory | index("file|444|self|build.json"))
	' "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/build.json" >/dev/null || return 1
	[[ $(input_languages_systemd_exec_path '/tmp/input path:%$') == '/tmp/input path:%%$' ]] || return 1
	grep -Fq 'ExecStart=:"' "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/systemd/dotfiles-input-languages-fcitx.service" || return 1
	[[ ! -e $INPUT_LANGUAGES_POINTER && ! -e $INPUT_LANGUAGES_ACTIVE && ! -e $INPUT_LANGUAGES_PENDING &&
		! -e $INPUT_LANGUAGES_RECOVERY && ! -e $INPUT_LANGUAGES_CLEANUP && ! -e $XDG_CONFIG_HOME/systemd/user ]]
}

incomplete_or_changed_artifact_is_rejected_without_repair() {
	prepare_artifact_fixture || return 1
	local artifact=$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR backup=$ARTIFACT_FIXTURE/member.backup
	cp "$artifact/input-languages-fcitx-helper" "$backup"
	chmod u+w "$artifact"
	mv "$artifact/input-languages-fcitx-helper" "$ARTIFACT_FIXTURE/helper.missing"
	chmod a-w "$artifact"
	! input_languages_validate_integration_artifact_self "$artifact" || return 1
	chmod u+w "$artifact"
	mv "$ARTIFACT_FIXTURE/helper.missing" "$artifact/input-languages-fcitx-helper"
	chmod a-w "$artifact"
	chmod u+w "$artifact/input-languages-fcitx-helper"
	printf '\nchanged\n' >>"$artifact/input-languages-fcitx-helper"
	chmod a-w "$artifact/input-languages-fcitx-helper"
	! input_languages_validate_integration_artifact_self "$artifact" || return 1
	chmod u+w "$artifact/input-languages-fcitx-helper"
	cp "$backup" "$artifact/input-languages-fcitx-helper"
	chmod 555 "$artifact/input-languages-fcitx-helper"
	input_languages_validate_integration_artifact_self "$artifact"
}

internally_inconsistent_artifact_is_rejected() {
	prepare_artifact_fixture || return 1
	local artifact=$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR metadata contract service original changed
	metadata=$artifact/build.json
	contract=$artifact/contracts/fcitx.json
	service=$artifact/systemd/dotfiles-input-languages-fcitx.service
	original=$(<"$metadata")
	changed=$(jq '.protocol_identity = "foreign-protocol"' "$metadata") || return 1
	chmod u+w "$metadata"
	printf '%s\n' "$changed" >"$metadata"
	chmod 444 "$metadata"
	! input_languages_validate_integration_artifact_self "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" || return 1
	chmod u+w "$metadata"
	printf '%s\n' "$original" >"$metadata"
	chmod 444 "$metadata"
	original=$(<"$contract")
	changed=$(jq '.controller.members.SetCurrentIM.input = "o"' "$contract") || return 1
	chmod u+w "$contract"
	printf '%s\n' "$changed" >"$contract"
	chmod 444 "$contract"
	! input_languages_validate_integration_artifact_self "$artifact" || return 1
	chmod u+w "$contract"
	printf '%s\n' "$original" >"$contract"
	chmod 444 "$contract"
	original=$(<"$service")
	chmod u+w "$service"
	printf '%s\n' "${original/input-languages-fcitx-helper/foreign-helper}" >"$service"
	chmod 444 "$service"
	! input_languages_validate_integration_artifact_self "$artifact" || return 1
	chmod u+w "$service"
	printf '%s\n' "$original" >"$service"
	chmod 444 "$service"
	input_languages_validate_integration_artifact_self "$artifact"
}

stale_compatibility_is_rejected() {
	prepare_artifact_fixture || return 1
	local compatibility=$INPUT_LANGUAGES_HEADER_HASH
	INPUT_LANGUAGES_HEADER_HASH=stale-compatibility
	! input_languages_build_integration_artifact >/dev/null || return 1
	INPUT_LANGUAGES_HEADER_HASH=$compatibility
}

run_test complete_immutable_integration_artifact_is_published_inertly 'complete immutable integration artifact is published without live selection'
run_test incomplete_or_changed_artifact_is_rejected_without_repair 'incomplete and changed immutable integration artifacts are rejected without repair'
run_test internally_inconsistent_artifact_is_rejected 'internally inconsistent immutable integration artifacts are rejected'
run_test stale_compatibility_is_rejected 'stale compatibility input is rejected before artifact reuse or build'

finish_tests
