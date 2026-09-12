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
		([.package_identity,.library_identity,.generated_files_identity,.inventory_identity] | all(type == "string" and length > 0)) and
		(.dependencies | contains("fcitx-upstream=5.1.21")) and
		(.dependencies | contains("libsystemd=")) and (.dependencies | contains("libcrypto=")) and
		(.linker | startswith("GNU ld ")) and
		(.inventory | index("file|444|self|build.json"))
	' "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/build.json" >/dev/null || return 1
	[[ $(input_languages_systemd_exec_path '/tmp/input path:%$') == '/tmp/input path:%%$' ]] || return 1
	grep -Fxq 'Environment=XDG_RUNTIME_DIR=%t' "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/systemd/dotfiles-input-languages-fcitx.service" || return 1
	grep -Fq 'ExecStart=:"' "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/systemd/dotfiles-input-languages-fcitx.service" || return 1
	[[ ! -e $INPUT_LANGUAGES_POINTER && ! -e $INPUT_LANGUAGES_ACTIVE && ! -e $INPUT_LANGUAGES_PENDING &&
		! -e $INPUT_LANGUAGES_RECOVERY && ! -e $INPUT_LANGUAGES_CLEANUP && ! -e $XDG_CONFIG_HOME/systemd/user ]]
}

all_explicit_inputs_change_the_build_identity() {
	local baseline changed index inputs
	local -a identities=(
		integration runtime unit health protocol controller package compiler linker library source generated_files inventory compatibility
	)
	inputs=$(jq -cn '$ARGS.named' \
		--arg integration integration --arg runtime runtime --arg unit unit --arg health health --arg protocol protocol --arg controller controller \
		--arg package package --arg compiler compiler --arg linker linker --arg library library --arg source source --arg generated_files generated \
		--arg inventory inventory --arg compatibility compatibility) || return 1
	baseline=$(input_languages_integration_build_identity "$inputs") || return 1
	for index in "${!identities[@]}"; do
		changed=$(input_languages_integration_build_identity "$(jq --arg field "${identities[$index]}" '.[$field] += "-changed"' <<<"$inputs")") || return 1
		[[ $changed != "$baseline" ]] || return 1
	done
}

generated_identity_tracks_renderer_and_ignores_ambient_pkg_config() (
	local source_inventory generated_before generated_after library_before library_after
	source_inventory=$(input_languages_integration_source_inventory_from "$INPUT_LANGUAGES_PLUGIN_SOURCE" "$INPUT_LANGUAGES_SOURCE") || return 1
	generated_before=$(input_languages_integration_generated_files_identity "$source_inventory") || return 1
	input_languages_render_integration_service() { printf 'changed renderer\n'; }
	generated_after=$(input_languages_integration_generated_files_identity "$source_inventory") || return 1
	[[ $generated_after != "$generated_before" ]] || return 1
	library_before=$(input_languages_integration_library_identity) || return 1
	PKG_CONFIG_PATH=/foreign/pkgconfig PKG_CONFIG_LIBDIR=/foreign/lib/pkgconfig library_after=$(input_languages_integration_library_identity) || return 1
	[[ $library_after == "$library_before" ]]
)

explicit_identity_tampering_is_rejected() {
	prepare_artifact_fixture || return 1
	local artifact=$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR metadata=$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR/build.json original field changed
	original=$(<"$metadata")
	for field in integration runtime_identity unit_identity health_identity protocol_identity controller_identity package_identity compiler linker library_identity source_id generated_files_identity inventory_identity; do
		changed=$(jq --arg field "$field" '.[$field] = "foreign-identity"' <<<"$original") || return 1
		chmod u+w "$metadata"
		printf '%s\n' "$changed" >"$metadata"
		chmod 444 "$metadata"
		! input_languages_validate_integration_artifact_self "$artifact" || return 1
	done
	chmod u+w "$metadata"
	printf '%s\n' "$original" >"$metadata"
	chmod 444 "$metadata"
	input_languages_validate_integration_artifact_self "$artifact"
}

version_3_receipt_projects_and_matches_complete_artifact_identity() {
	prepare_artifact_fixture || return 1
	local artifact receipt field
	artifact=$(input_languages_v3_integration_artifact "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR") || return 1
	jq -e '
		(keys | sort) == (["source_id","build_id","artifact","artifact_sha256","helper_sha256","widget_sha256","protocol_identity","controller_identity","health_identity","unit_identity","runtime_identity","integration_identity","package_identity","compiler_identity","linker_identity","library_identity","generated_files_identity","inventory_identity","compatibility_hash","compiler_warning","dependencies","inventory"] | sort)
	' <<<"$artifact" >/dev/null || return 1
	input_languages_v3_build_inputs_match "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" || return 1
	for field in runtime_identity integration_identity unit_identity health_identity protocol_identity controller_identity package_identity compiler_identity linker_identity library_identity source_id generated_files_identity inventory_identity; do
		receipt=$(jq --arg field "$field" '.[$field] = "foreign-identity"' <<<"$artifact") || return 1
		! input_languages_v3_integration_artifact_matches "$receipt" "$INPUT_LANGUAGES_INTEGRATION_ARTIFACT_DIR" || return 1
	done
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
	printf '%s\n' "${original/Environment=XDG_RUNTIME_DIR=%t/Environment=XDG_RUNTIME_DIR=\/tmp}" >"$service"
	chmod 444 "$service"
	! input_languages_validate_integration_artifact_self "$artifact" || return 1
	chmod u+w "$service"
	printf '%s\n' "$original" >"$service"
	chmod 444 "$service"
	input_languages_validate_integration_artifact_self "$artifact" || return 1
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
run_test all_explicit_inputs_change_the_build_identity 'all explicit artifact inputs participate in rebuild identity'
run_test generated_identity_tracks_renderer_and_ignores_ambient_pkg_config 'generated and library identities match the exact build environment'
run_test incomplete_or_changed_artifact_is_rejected_without_repair 'incomplete and changed immutable integration artifacts are rejected without repair'
run_test internally_inconsistent_artifact_is_rejected 'internally inconsistent immutable integration artifacts are rejected'
run_test explicit_identity_tampering_is_rejected 'all explicit immutable artifact identities are validated'
run_test version_3_receipt_projects_and_matches_complete_artifact_identity 'version 3 receipts project and match the complete artifact identity'
run_test stale_compatibility_is_rejected 'stale compatibility input is rejected before artifact reuse or build'

finish_tests
