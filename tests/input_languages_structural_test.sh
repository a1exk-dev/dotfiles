#!/usr/bin/env bash

set -u

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly REPOSITORY_ROOT=$(cd -- "$TEST_ROOT/.." && pwd)

healthy_sources_validate() {
	bash "$REPOSITORY_ROOT/lib/dotfiles/input-languages-validator.sh" "$REPOSITORY_ROOT" >/dev/null
}

new_structural_fixture() {
	STRUCTURAL_FIXTURE=$(mktemp -d)
	mkdir -p "$STRUCTURAL_FIXTURE/config" "$STRUCTURAL_FIXTURE/plugins" "$STRUCTURAL_FIXTURE/lib/dotfiles" \
		"$STRUCTURAL_FIXTURE/omarchy/config/omarchy" "$STRUCTURAL_FIXTURE/omarchy/bin" "$STRUCTURAL_FIXTURE/omarchy/shell/plugins/bar/widgets" \
		"$STRUCTURAL_FIXTURE/omarchy/shell/services" "$STRUCTURAL_FIXTURE/omarchy/shell/Ui"
	cp -a "$REPOSITORY_ROOT/config/hyprland" "$STRUCTURAL_FIXTURE/config/"
	cp -a "$REPOSITORY_ROOT/plugins/input-languages" "$STRUCTURAL_FIXTURE/plugins/"
	cp -a /usr/share/omarchy/config/hypr "$STRUCTURAL_FIXTURE/omarchy/config/"
	cp /usr/share/omarchy/config/omarchy/shell.json "$STRUCTURAL_FIXTURE/omarchy/config/omarchy/"
	cp /usr/share/omarchy/bin/omarchy-bar /usr/share/omarchy/bin/omarchy-plugin-disable /usr/share/omarchy/bin/omarchy-plugin-enable /usr/share/omarchy/bin/omarchy-refresh-config \
		/usr/share/omarchy/bin/omarchy-refresh-hyprland "$STRUCTURAL_FIXTURE/omarchy/bin/"
	cp /usr/share/omarchy/shell/plugins/bar/Bar.qml "$STRUCTURAL_FIXTURE/omarchy/shell/plugins/bar/"
	cp /usr/share/omarchy/shell/Ui/PluginBarApi.qml "$STRUCTURAL_FIXTURE/omarchy/shell/Ui/"
	cp /usr/share/omarchy/shell/plugins/bar/widgets/KeyboardLayout.qml /usr/share/omarchy/shell/plugins/bar/widgets/KeyboardLayout.manifest.json \
		/usr/share/omarchy/shell/plugins/bar/widgets/KeyboardLayoutModel.js "$STRUCTURAL_FIXTURE/omarchy/shell/plugins/bar/widgets/"
	cp /usr/share/omarchy/shell/services/PluginRegistry.qml "$STRUCTURAL_FIXTURE/omarchy/shell/services/"
	cp /usr/share/omarchy/shell/shell.qml "$STRUCTURAL_FIXTURE/omarchy/shell/"
	cp "$REPOSITORY_ROOT/lib/dotfiles/input-languages-validator.sh" "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh" \
		"$REPOSITORY_ROOT/lib/dotfiles/input-languages-v3.sh" "$STRUCTURAL_FIXTURE/lib/dotfiles/"
}

fixture_validator_fails() {
	! bash "$STRUCTURAL_FIXTURE/lib/dotfiles/input-languages-validator.sh" "$STRUCTURAL_FIXTURE" "$STRUCTURAL_FIXTURE/omarchy" >/dev/null 2>&1
}

fixture_validator_reports() {
	local expected=$1 output status
	output=$(bash "$STRUCTURAL_FIXTURE/lib/dotfiles/input-languages-validator.sh" "$STRUCTURAL_FIXTURE" "$STRUCTURAL_FIXTURE/omarchy" 2>&1)
	status=$?
	((status != 0)) && [[ $output == *"$expected"* ]]
}

group_toggle_is_rejected() (
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	printf '\nkb_options = "grp:ctrl_shift_toggle"\n' >>"$STRUCTURAL_FIXTURE/config/hyprland/.config/hypr/input.lua"
	fixture_validator_fails
)

invalid_lua_is_rejected() (
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	printf '\nthis is not lua )\n' >>"$STRUCTURAL_FIXTURE/config/hyprland/.config/hypr/input.lua"
	fixture_validator_fails
)

later_keymap_override_is_rejected() (
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	printf '\nkb_layout = "us"\n' >>"$STRUCTURAL_FIXTURE/config/hyprland/.config/hypr/input.lua"
	fixture_validator_fails
)

unsafe_or_extra_owned_entries_are_rejected() (
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	ln -sf /tmp/not-owned "$STRUCTURAL_FIXTURE/config/hyprland/.config/hypr/input.lua"
	fixture_validator_fails || return 1
	rm -f "$STRUCTURAL_FIXTURE/config/hyprland/.config/hypr/input.lua"
	cp "$REPOSITORY_ROOT/config/hyprland/.config/hypr/input.lua" "$STRUCTURAL_FIXTURE/config/hyprland/.config/hypr/input.lua"
	printf 'extra\n' >"$STRUCTURAL_FIXTURE/config/hyprland/.config/hypr/extra.conf"
	fixture_validator_fails
)

manifest_and_packaged_baseline_drift_are_rejected() (
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	jq '.files["extra.lua"] = ("0" * 64)' "$STRUCTURAL_FIXTURE/plugins/input-languages/migration-baseline.json" >"$STRUCTURAL_FIXTURE/plugins/input-languages/migration-baseline.updated"
	mv "$STRUCTURAL_FIXTURE/plugins/input-languages/migration-baseline.updated" "$STRUCTURAL_FIXTURE/plugins/input-languages/migration-baseline.json"
	fixture_validator_fails || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/migration-baseline.json" "$STRUCTURAL_FIXTURE/plugins/input-languages/migration-baseline.json"
	printf '\n-- changed packaged seam\n' >>"$STRUCTURAL_FIXTURE/omarchy/config/hypr/input.lua"
	fixture_validator_fails
)

integration_seam_drift_is_rejected() (
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	printf '\n# changed command seam\n' >>"$STRUCTURAL_FIXTURE/omarchy/bin/omarchy-bar"
	fixture_validator_fails || return 1
	cp /usr/share/omarchy/bin/omarchy-bar "$STRUCTURAL_FIXTURE/omarchy/bin/omarchy-bar"
	printf '\n// changed bar placement seam\n' >>"$STRUCTURAL_FIXTURE/omarchy/shell/plugins/bar/Bar.qml"
	fixture_validator_fails || return 1
	cp /usr/share/omarchy/shell/plugins/bar/Bar.qml "$STRUCTURAL_FIXTURE/omarchy/shell/plugins/bar/Bar.qml"
	printf '\n// changed widget seam\n' >>"$STRUCTURAL_FIXTURE/omarchy/shell/plugins/bar/widgets/KeyboardLayout.qml"
	fixture_validator_fails
)

flag_widget_manifest_rendering_and_model_drift_are_rejected() (
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	jq '.omarchy.clonePaths = []' "$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/manifest.json" >"$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/manifest.updated"
	mv "$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/manifest.updated" "$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/manifest.json"
	fixture_validator_fails || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/widget/dotfiles.keyboard-layout/manifest.json" "$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/manifest.json"
	sed -i 's/width: 12/width: 13/' "$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/KeyboardLayout.qml"
	fixture_validator_fails || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/widget/dotfiles.keyboard-layout/KeyboardLayout.qml" "$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/KeyboardLayout.qml"
	sed -i 's/root[.]cycleLayout()/root.refresh()/' "$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/KeyboardLayout.qml"
	fixture_validator_fails || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/widget/dotfiles.keyboard-layout/KeyboardLayout.qml" "$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/KeyboardLayout.qml"
	printf '\n// changed model\n' >>"$STRUCTURAL_FIXTURE/plugins/input-languages/widget/dotfiles.keyboard-layout/KeyboardLayoutModel.js"
	fixture_validator_fails
)

contract_bundle_is_complete() {
	healthy_sources_validate
}

contract_inventory_and_syntax_drift_are_rejected() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local contracts=$STRUCTURAL_FIXTURE/plugins/input-languages/contracts
	rm "$contracts/authority.json"
	fixture_validator_reports 'contract inventory is not exact' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/authority.json" "$contracts/authority.json"
	printf '{}\n' >"$contracts/extra.json"
	fixture_validator_reports 'contract inventory is not exact' || return 1
	rm "$contracts/extra.json"
	rm "$contracts/authority.json"
	ln -s "$REPOSITORY_ROOT/plugins/input-languages/contracts/authority.json" "$contracts/authority.json"
	fixture_validator_reports 'contract must be a regular file' || return 1
	rm "$contracts/authority.json"
	printf '{\n' >"$contracts/authority.json"
	fixture_validator_reports 'malformed Fcitx integration contract'
)

contract_shape_and_identity_drift_are_rejected() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local contracts=$STRUCTURAL_FIXTURE/plugins/input-languages/contracts
	jq '.unexpected = true' "$contracts/authority.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/authority.json"
	fixture_validator_reports 'frozen Fcitx integration contract changed: authority.json' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/authority.json" "$contracts/authority.json"
	jq '.integration = "foreign"' "$contracts/protocol.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/protocol.json"
	fixture_validator_reports 'contract identity disagrees: protocol.json' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/protocol.json" "$contracts/protocol.json"
	jq 'del(.frames.HELLO.fields[0])' "$contracts/protocol.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/protocol.json"
	fixture_validator_reports 'private protocol frame schema or fixed constants changed'
)

contract_constants_and_compatibility_drift_are_rejected() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local contracts=$STRUCTURAL_FIXTURE/plugins/input-languages/contracts
	sed -i 's/src\/fcitx-controller.cpp //' "$STRUCTURAL_FIXTURE/lib/dotfiles/input-languages.sh"
	fixture_validator_reports 'integration source identity inventory is not exact' || return 1
	cp "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh" "$STRUCTURAL_FIXTURE/lib/dotfiles/input-languages.sh"
	jq '.transport.maximum_packet_bytes = 1025' "$contracts/protocol.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/protocol.json"
	fixture_validator_reports 'private protocol frame schema or fixed constants changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/protocol.json" "$contracts/protocol.json"
	jq '.compatibility.upstream_version = "5.1.21"' "$contracts/fcitx.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/fcitx.json"
	fixture_validator_reports 'compatibility, Controller shape, managed group, or delivery constants changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/fcitx.json" "$contracts/fcitx.json"
	jq '.controller.members.SetCurrentIM.input = "o"' "$contracts/fcitx.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/fcitx.json"
	fixture_validator_reports 'compatibility, Controller shape, managed group, or delivery constants changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/fcitx.json" "$contracts/fcitx.json"
	jq 'del(.compatibility_gates.narrow_restoration_members[-1])' "$contracts/fcitx.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/fcitx.json"
	fixture_validator_reports 'compatibility, Controller shape, managed group, or delivery constants changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/fcitx.json" "$contracts/fcitx.json"
	jq '.managed_group.items |= reverse' "$contracts/fcitx.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/fcitx.json"
	fixture_validator_reports 'compatibility, Controller shape, managed group, or delivery constants changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/fcitx.json" "$contracts/fcitx.json"
	jq '.service.restart_seconds = 3' "$contracts/systemd.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/systemd.json"
	fixture_validator_reports 'helper systemd contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/systemd.json" "$contracts/systemd.json"
	jq 'del(.snapshot_fields.direct_xkb_health)' "$contracts/health.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/health.json"
	fixture_validator_reports 'health schema, outcome mapping, or classification constants changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/health.json" "$contracts/health.json"
	jq 'del(.objects.widget_ownership)' "$contracts/evidence-v3.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/evidence-v3.json"
	fixture_validator_reports 'version-3 evidence schema or version-2 ancestry contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/evidence-v3.json" "$contracts/evidence-v3.json"
	jq 'del(.version_2.exact_keys.active[-1])' "$contracts/evidence-v3.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/evidence-v3.json"
	fixture_validator_reports 'version-3 evidence schema or version-2 ancestry contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/contracts/evidence-v3.json" "$contracts/evidence-v3.json"
	jq '.fixtures[2].backend = "x11"' "$contracts/active-fixtures.json" >"$contracts/changed.json"
	mv "$contracts/changed.json" "$contracts/active-fixtures.json"
	fixture_validator_reports 'active fixture contract changed'
)

contract_changes_preserve_direct_source_identity() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local before after contract=$STRUCTURAL_FIXTURE/plugins/input-languages/contracts/authority.json
	before=$(bash -c 'source "$1"; input_languages_source_identity_from "$2/plugins/input-languages" "$2/config/hyprland/.config/hypr"' \
		_ "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh" "$STRUCTURAL_FIXTURE")
	jq '.identity = "changed-contract-only"' "$contract" >"$contract.changed"
	mv "$contract.changed" "$contract"
	after=$(bash -c 'source "$1"; input_languages_source_identity_from "$2/plugins/input-languages" "$2/config/hyprland/.config/hypr"' \
		_ "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh" "$STRUCTURAL_FIXTURE")
	[[ $before == "$after" ]]
)

follower_changes_preserve_selectable_plugin_source_identity() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local before after follower=$STRUCTURAL_FIXTURE/plugins/input-languages/src/fcitx-follower.cpp
	before=$(bash -c 'source "$1"; input_languages_source_identity_from "$2/plugins/input-languages" "$2/config/hyprland/.config/hypr"' \
		_ "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh" "$STRUCTURAL_FIXTURE")
	printf '\n// changed follower\n' >>"$follower"
	after=$(bash -c 'source "$1"; input_languages_source_identity_from "$2/plugins/input-languages" "$2/config/hyprland/.config/hypr"' \
		_ "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh" "$STRUCTURAL_FIXTURE")
	[[ $before == "$after" ]]
)

integration_source_identity_covers_complete_artifact_sources() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local before after source_path fixture_path
	before=$(bash -c 'source "$1"; input_languages_integration_source_identity_from "$2/plugins/input-languages" "$2/config/hyprland/.config/hypr"' \
		_ "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh" "$STRUCTURAL_FIXTURE")
	while IFS= read -r source_path; do
		case $source_path in
			plugin/*) fixture_path=plugins/input-languages/${source_path#plugin/} ;;
			contracts/*) fixture_path=plugins/input-languages/$source_path ;;
			systemd/*) fixture_path=plugins/input-languages/$source_path ;;
			widget/*) fixture_path=plugins/input-languages/widget/dotfiles.keyboard-layout/${source_path#widget/} ;;
			config/*) fixture_path=config/hyprland/.config/hypr/${source_path#config/} ;;
			*) return 1 ;;
		esac
		printf '\nartifact identity change\n' >>"$STRUCTURAL_FIXTURE/$fixture_path"
		after=$(bash -c 'source "$1"; input_languages_integration_source_identity_from "$2/plugins/input-languages" "$2/config/hyprland/.config/hypr"' \
			_ "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh" "$STRUCTURAL_FIXTURE")
		[[ $before != "$after" ]] || return 1
		cp "$REPOSITORY_ROOT/$fixture_path" "$STRUCTURAL_FIXTURE/$fixture_path"
	done < <(bash -c 'source "$1"; input_languages_integration_expected_source_paths' _ "$REPOSITORY_ROOT/lib/dotfiles/input-languages.sh")
)

controller_adapter_source_contract_is_enforced() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local plugin=$STRUCTURAL_FIXTURE/plugins/input-languages
	rm "$plugin/include/fcitx-controller.hpp"
	fixture_validator_reports 'Controller adapter source is missing or unsafe' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/include/fcitx-controller.hpp" "$plugin/include/fcitx-controller.hpp"
	sed -i "s/CALL_TIMEOUT_USEC = 1'000'000/CALL_TIMEOUT_USEC = 2'000'000/" "$plugin/src/fcitx-sd-bus-transport.cpp"
	fixture_validator_reports 'Controller adapter fixed transport contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/src/fcitx-sd-bus-transport.cpp" "$plugin/src/fcitx-sd-bus-transport.cpp"
	sed -i 's/O_RDONLY | O_CLOEXEC | O_NOFOLLOW/O_RDONLY | O_CLOEXEC/' "$plugin/src/fcitx-sd-bus-transport.cpp"
	fixture_validator_reports 'Controller adapter fixed transport contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/src/fcitx-sd-bus-transport.cpp" "$plugin/src/fcitx-sd-bus-transport.cpp"
	sed -i 's/ExpectedMember{"SetCurrentIM", "method", "s", ""}/ExpectedMember{"SetCurrentIM", "method", "o", ""}/' "$plugin/src/fcitx-sd-bus-transport.cpp"
	fixture_validator_reports 'compiled Fcitx Controller members disagree with fcitx.json' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/src/fcitx-sd-bus-transport.cpp" "$plugin/src/fcitx-sd-bus-transport.cpp"
	sed -i 's/pkg-config --cflags --libs libsystemd libcrypto/pkg-config --cflags --libs Fcitx5Core/' "$plugin/Makefile"
	fixture_validator_reports 'Controller adapter must use libsystemd without Fcitx ABI linkage'
)

helper_source_and_unit_contract_is_enforced() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local plugin=$STRUCTURAL_FIXTURE/plugins/input-languages
	rm "$plugin/include/fcitx-protocol.hpp"
	fixture_validator_reports 'Fcitx helper source is missing or unsafe' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/include/fcitx-protocol.hpp" "$plugin/include/fcitx-protocol.hpp"
	sed -i 's/MAX_PACKET_BYTES = 1024/MAX_PACKET_BYTES = 2048/' "$plugin/include/fcitx-protocol.hpp"
	fixture_validator_reports 'helper fixed protocol, authentication, or worker contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/include/fcitx-protocol.hpp" "$plugin/include/fcitx-protocol.hpp"
	sed -i 's/dotfiles-input-languages-fcitx-seqpacket-v1/foreign-protocol/' "$plugin/include/fcitx-protocol.hpp"
	fixture_validator_reports 'compiled Fcitx protocol constants disagree with protocol.json' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/include/fcitx-protocol.hpp" "$plugin/include/fcitx-protocol.hpp"
	sed -i 's/HelperFailed = 11/HelperFailed = 12/' "$plugin/include/fcitx-protocol.hpp"
	fixture_validator_reports 'compiled Fcitx protocol constants disagree with protocol.json' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/include/fcitx-protocol.hpp" "$plugin/include/fcitx-protocol.hpp"
	sed -i 's/milliseconds(2000)}/milliseconds(2001)}/' "$plugin/include/fcitx-follower.hpp"
	fixture_validator_reports 'compiled Fcitx protocol constants disagree with protocol.json' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/include/fcitx-follower.hpp" "$plugin/include/fcitx-follower.hpp"
	sed -i 's/installedFcitxUpstreamVersion()/SUPPORTED_UPSTREAM_VERSION/' "$plugin/src/fcitx-helper-main.cpp"
	fixture_validator_reports 'helper fixed protocol, authentication, or worker contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/src/fcitx-helper-main.cpp" "$plugin/src/fcitx-helper-main.cpp"
	sed -i 's/SocketMode=0600/SocketMode=0660/' "$plugin/systemd/dotfiles-input-languages-fcitx.socket"
	fixture_validator_reports 'helper socket unit contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/systemd/dotfiles-input-languages-fcitx.socket" "$plugin/systemd/dotfiles-input-languages-fcitx.socket"
	sed -i 's/Environment=XDG_RUNTIME_DIR=%t/Environment=XDG_RUNTIME_DIR=\/tmp/' "$plugin/systemd/dotfiles-input-languages-fcitx.service"
	fixture_validator_reports 'helper service unit contract changed' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/systemd/dotfiles-input-languages-fcitx.service" "$plugin/systemd/dotfiles-input-languages-fcitx.service"
	sed -i 's/RestartSec=2s/RestartSec=3s/' "$plugin/systemd/dotfiles-input-languages-fcitx.service"
	fixture_validator_reports 'helper service unit contract changed'
)

follower_source_contract_is_enforced() (
	set -e
	new_structural_fixture
	trap 'rm -rf -- "$STRUCTURAL_FIXTURE"' EXIT
	local plugin=$STRUCTURAL_FIXTURE/plugins/input-languages
	rm "$plugin/include/fcitx-follower.hpp"
	fixture_validator_reports 'plugin source is missing or unsafe' || return 1
	cp "$REPOSITORY_ROOT/plugins/input-languages/include/fcitx-follower.hpp" "$plugin/include/fcitx-follower.hpp"
	sed -i 's/SO_PEERCRED/SO_TYPE/' "$plugin/src/fcitx-follower.cpp"
	fixture_validator_reports 'Fcitx follower mailbox, wake, IPC, or plugin coordination contract changed'
)

recovery_evidence_uses_semantic_rollback_phases() (
	jq -e '
		.types["semantic-rollback-phase"] == {type:"string",enum:["authority-quiesced","direct-restored","fcitx-semantic-delta-reversed","helper-state-restored","operation-start-language-restored","verified"]} and
		.objects.recovery_required.references.failed_phase == "semantic-rollback-phase"
	' "$REPOSITORY_ROOT/plugins/input-languages/contracts/evidence-v3.json" >/dev/null
)

run_test healthy_sources_validate 'complete Input Languages sources validate'
run_test group_toggle_is_rejected 'XKB group-toggle options are rejected'
run_test invalid_lua_is_rejected 'invalid Hyprland Lua syntax is rejected'
run_test later_keymap_override_is_rejected 'later effective keymap overrides are rejected'
run_test unsafe_or_extra_owned_entries_are_rejected 'unsafe and extra owned tree entries are rejected'
run_test manifest_and_packaged_baseline_drift_are_rejected 'manifest and packaged baseline drift are rejected'
run_test integration_seam_drift_is_rejected 'Omarchy command and stock widget seam drift is rejected'
run_test flag_widget_manifest_rendering_and_model_drift_are_rejected 'flag-widget manifest, themed rendering, and model drift are rejected'
run_test contract_bundle_is_complete 'Fcitx integration contract bundle is complete and valid'
run_test contract_inventory_and_syntax_drift_are_rejected 'contract inventory and JSON syntax drift are rejected'
run_test contract_shape_and_identity_drift_are_rejected 'contract shape and shared identity drift are rejected'
run_test contract_constants_and_compatibility_drift_are_rejected 'contract constants and compatibility drift are rejected'
run_test contract_changes_preserve_direct_source_identity 'contract-only changes preserve direct-XKB source identity'
run_test follower_changes_preserve_selectable_plugin_source_identity 'follower changes stay outside selectable plugin source identity'
run_test integration_source_identity_covers_complete_artifact_sources 'integration source identity covers the complete artifact sources'
run_test controller_adapter_source_contract_is_enforced 'Controller adapter source and transport contract are enforced'
run_test helper_source_and_unit_contract_is_enforced 'helper protocol, source, and systemd unit contracts are enforced'
run_test follower_source_contract_is_enforced 'follower mailbox, wake, IPC, and plugin coordination are enforced'
run_test recovery_evidence_uses_semantic_rollback_phases 'recovery evidence uses the six semantic rollback phases'

finish_tests
