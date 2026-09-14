#!/usr/bin/env bash

set -euo pipefail
export PATH=/usr/bin:/bin
export LC_ALL=C

repository_root=${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}
package_root=$repository_root/config/hyprland/.config/hypr
plugin_root=$repository_root/plugins/input-languages
contract_root=$plugin_root/contracts
widget_root=$plugin_root/widget/dotfiles.keyboard-layout
omarchy_root=${2:-/usr/share/omarchy}
packaged_root=$omarchy_root/config/hypr
mode=${3:-full}
[[ $mode == full || $mode == --static-only ]] || { printf 'Error: unknown validator mode: %s\n' "$mode" >&2; exit 2; }
REPOSITORY_ROOT=$repository_root
source "$repository_root/lib/dotfiles/input-languages.sh"

expected=(
	.luarc.json
	autostart.lua
	bindings.lua
	hypridle.conf
	hyprland.lua
	hyprlock.conf
	hyprsunset.conf
	input.lua
	looknfeel.lua
	monitors.lua
	xdph.conf
)

for path in "$package_root" "$plugin_root" "$contract_root" "$widget_root" "$packaged_root"; do
	[[ -d $path && ! -L $path ]] || { printf 'Error: required Input Languages source directory is missing or unsafe: %s\n' "$path" >&2; exit 1; }
done

mapfile -t actual < <(find "$package_root" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
if ((${#actual[@]} != ${#expected[@]})); then
	printf 'Error: the Hyprland package must contain exactly the reviewed 11-file tree.\n' >&2
	printf 'Expected count: %d\nActual: %s\n' "${#expected[@]}" "${actual[*]}" >&2
	exit 1
fi
for name in "${expected[@]}"; do
	[[ -f $package_root/$name && ! -L $package_root/$name ]] || { printf 'Error: Hyprland source is not a regular file: %s\n' "$name" >&2; exit 1; }
done
if command -v luac >/dev/null 2>&1; then
	for name in "$package_root"/*.lua; do
		luac -p "$name" || { printf 'Error: invalid Hyprland Lua syntax: %s\n' "${name##*/}" >&2; exit 1; }
	done
elif [[ $mode == full ]]; then
	printf 'Error: luac is required for complete Input Languages validation.\n' >&2
	exit 1
fi

jq -e '.workspace.library == ["/usr/share/hypr/stubs"] and .diagnostics.globals == ["hl", "o"]' "$package_root/.luarc.json" >/dev/null
mapfile -t keymap_settings < <(grep -E '^[[:space:]]*kb_(layout|variant|options)[[:space:]]*=' "$package_root/input.lua")
expected_keymap_settings=(
	'    kb_layout = "us,ru",'
	'    kb_variant = ",",'
	'    kb_options = "compose:caps,shift:both_capslock_cancel",'
)
if ((${#keymap_settings[@]} != ${#expected_keymap_settings[@]})) || [[ $(printf '%s\n' "${keymap_settings[@]}") != "$(printf '%s\n' "${expected_keymap_settings[@]}")" ]]; then
	printf 'Error: input.lua must configure exactly the approved US/Russian keymap and options once.\n' >&2
	exit 1
fi

for name in .luarc.json autostart.lua bindings.lua hyprland.lua hyprsunset.conf input.lua looknfeel.lua monitors.lua xdph.conf; do
	expected_hash=$(jq -r --arg name "$name" '.files[$name] // empty' "$plugin_root/migration-baseline.json")
	packaged_hash=$(sha256sum "$packaged_root/$name")
	if [[ ${packaged_hash%% *} != "$expected_hash" ]]; then
		printf 'Error: current packaged Hyprland default differs from the reviewed baseline: %s\n' "$name" >&2
		exit 1
	fi
done
for name in .luarc.json autostart.lua bindings.lua hyprsunset.conf looknfeel.lua monitors.lua xdph.conf; do
	cmp -s "$package_root/$name" "$packaged_root/$name" || {
		printf 'Error: unmodified reviewed Hyprland source differs from its packaged baseline: %s\n' "$name" >&2
		exit 1
	}
done

grep -Fq 'active-artifact.lua' "$package_root/hyprland.lua"
grep -Fq 'hl.plugin.load(artifact)' "$package_root/hyprland.lua"

for source in Makefile integration.mk migration-baseline.json include/input-language-model.hpp include/input-language-health.hpp include/fcitx-follower.hpp \
		src/input-language-model.cpp src/input-language-health.cpp src/fcitx-follower.cpp \
		src/integration-artifact-identity.cpp \
		src/plugin.cpp tests/input-language-model-test.cpp tests/input-language-health-test.cpp tests/fcitx-follower-test.cpp \
		tests/input-language-integration-test.cpp \
	tests/keyboard-layout-model-test.cjs widget/dotfiles.keyboard-layout/manifest.json widget/dotfiles.keyboard-layout/KeyboardLayout.qml \
	widget/dotfiles.keyboard-layout/KeyboardLayoutModel.js; do
	[[ -f $plugin_root/$source && ! -L $plugin_root/$source ]] || { printf 'Error: plugin source is missing or unsafe: %s\n' "$source" >&2; exit 1; }
done
for source in include/fcitx-controller-cli.hpp include/fcitx-controller.hpp src/fcitx-controller-cli.cpp src/fcitx-controller.cpp src/fcitx-sd-bus-transport.cpp tests/fcitx-controller-test.cpp; do
	[[ -f $plugin_root/$source && ! -L $plugin_root/$source ]] || {
		printf 'Error: Controller adapter source is missing or unsafe: %s\n' "$source" >&2
		exit 1
	}
done
for source in include/fcitx-protocol.hpp include/fcitx-helper.hpp src/fcitx-protocol.cpp src/fcitx-helper.cpp src/fcitx-helper-main.cpp \
		tests/fcitx-helper-test.cpp systemd/dotfiles-input-languages-fcitx.socket systemd/dotfiles-input-languages-fcitx.service; do
	[[ -f $plugin_root/$source && ! -L $plugin_root/$source ]] || {
		printf 'Error: Fcitx helper source is missing or unsafe: %s\n' "$source" >&2
		exit 1
	}
done
	expected_integration_identity_sources=(
	integration.mk migration-baseline.json
	include/fcitx-controller-cli.hpp include/fcitx-controller.hpp include/fcitx-follower.hpp include/fcitx-helper.hpp include/fcitx-protocol.hpp include/input-language-health.hpp include/input-language-model.hpp
	src/fcitx-controller-cli.cpp src/fcitx-controller.cpp src/fcitx-follower.cpp src/fcitx-helper-main.cpp src/fcitx-helper.cpp src/fcitx-protocol.cpp
	src/fcitx-sd-bus-transport.cpp src/input-language-health.cpp src/input-language-model.cpp src/integration-artifact-identity.cpp src/plugin.cpp
)
[[ $(printf '%s\n' "${INPUT_LANGUAGES_INTEGRATION_SOURCE_FILES[@]}") == "$(printf '%s\n' "${expected_integration_identity_sources[@]}")" ]] || {
	printf 'Error: integration source identity inventory is not exact.\n' >&2
	exit 1
}
grep -Fq "CALL_TIMEOUT_USEC = 1'000'000" "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq 'sd_bus_call_async' "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq 'sd_bus_attach_event' "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq 'sd_bus_message_set_auto_start' "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq 'O_RDONLY | O_CLOEXEC | O_NOFOLLOW' "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq '(before.st_mode & 07777) == 0600' "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq 'fstatat(AT_FDCWD, profilePath.c_str(), &pathIdentity, AT_SYMLINK_NOFOLLOW)' "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq 'EVP_sha256()' "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq 'ownerIsSupervised(owner)' "$plugin_root/src/fcitx-sd-bus-transport.cpp" || {
	printf 'Error: Controller adapter fixed transport contract changed.\n' >&2
	exit 1
}
grep -Fq 'm_impl->evidence.uniqueOwner = owner' "$plugin_root/src/fcitx-sd-bus-transport.cpp" &&
	grep -Fq 'MAX_PACKET_BYTES = 1024' "$plugin_root/include/fcitx-protocol.hpp" &&
	grep -Fq 'HEADER_BYTES = 12' "$plugin_root/include/fcitx-protocol.hpp" &&
	grep -Fq 'SO_PEERCRED' "$plugin_root/src/fcitx-helper.cpp" &&
	grep -Fq 'credentials.uid == geteuid()' "$plugin_root/src/fcitx-helper.cpp" &&
	grep -Fq 'O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC' "$plugin_root/src/fcitx-helper.cpp" &&
	grep -Fq 'fstatat(parentFd, "fcitx.sock", &socketStatus, AT_SYMLINK_NOFOLLOW)' "$plugin_root/src/fcitx-helper.cpp" &&
	grep -Fq 'listenerOwnsPath(path, listenerStatus)' "$plugin_root/src/fcitx-helper.cpp" &&
	grep -Fq 'socketStatus.st_dev == socketStatusAfter.st_dev && socketStatus.st_ino == socketStatusAfter.st_ino' "$plugin_root/src/fcitx-helper.cpp" &&
	grep -Fq 'SOCK_NONBLOCK | SOCK_CLOEXEC' "$plugin_root/src/fcitx-helper.cpp" &&
	grep -Fq 'MSG_TRUNC' "$plugin_root/src/fcitx-helper.cpp" &&
	grep -Fq 'installedFcitxUpstreamVersion()' "$plugin_root/src/fcitx-helper-main.cpp" &&
	grep -Fq 'ControllerWorker' "$plugin_root/src/fcitx-helper.cpp" || {
	printf 'Error: Fcitx helper fixed protocol, authentication, or worker contract changed.\n' >&2
	exit 1
}
grep -Fq 'pkg-config --cflags --libs libsystemd libcrypto' "$plugin_root/Makefile" &&
	grep -Fq 'HELPER_PACKAGES := libsystemd libcrypto' "$plugin_root/integration.mk" &&
	! grep -Eq 'Fcitx5(Core|Utils)|-lfcitx' "$plugin_root/Makefile" "$plugin_root/integration.mk" "$plugin_root/src/fcitx-sd-bus-transport.cpp" \
		"$plugin_root/src/fcitx-helper.cpp" "$plugin_root/src/fcitx-helper-main.cpp" || {
	printf 'Error: Controller adapter must use libsystemd without Fcitx ABI linkage.\n' >&2
	exit 1
}
grep -Fq 'SOCK_SEQPACKET | SOCK_NONBLOCK | SOCK_CLOEXEC' "$plugin_root/src/fcitx-follower.cpp" &&
	grep -Fq 'MSG_DONTWAIT | MSG_TRUNC' "$plugin_root/src/fcitx-follower.cpp" &&
	grep -Fq 'SO_PEERCRED' "$plugin_root/src/fcitx-follower.cpp" &&
	grep -Fq 'credentials.uid != geteuid()' "$plugin_root/src/fcitx-follower.cpp" &&
	grep -Fq -- '-DINPUT_LANGUAGES_FCITX_COORDINATION' "$plugin_root/Makefile" &&
	grep -Fq -- '-DINPUT_LANGUAGES_FCITX_COORDINATION' "$plugin_root/integration.mk" &&
	! grep -Eq '(^|[^[:alnum:]_])(fork|exec[lvpe]*|system|posix_spawn|sd_bus)[[:space:]_(]' \
		"$plugin_root/include/fcitx-follower.hpp" "$plugin_root/src/fcitx-follower.cpp" || {
	printf 'Error: Fcitx follower mailbox, wake, IPC, or plugin coordination contract changed.\n' >&2
	exit 1
}
socket_unit=$plugin_root/systemd/dotfiles-input-languages-fcitx.socket
service_unit=$plugin_root/systemd/dotfiles-input-languages-fcitx.service
for setting in \
	'ListenSequentialPacket=%t/dotfiles-input-languages/fcitx.sock' 'DirectoryMode=0700' 'SocketMode=0600' \
	'RemoveOnStop=yes' 'WantedBy=graphical-session.target'; do
	[[ $(grep -Fxc "$setting" "$socket_unit") == 1 ]] || { printf 'Error: Fcitx helper socket unit contract changed: %s\n' "$setting" >&2; exit 1; }
done
for setting in 'StartLimitIntervalSec=30s' 'StartLimitBurst=5' 'Type=simple' \
	'Environment=XDG_RUNTIME_DIR=%t' 'ExecStart="@ARTIFACT_DIR@/input-languages-fcitx-helper"' 'Restart=on-failure' 'RestartSec=2s'; do
	[[ $(grep -Fxc "$setting" "$service_unit") == 1 ]] || { printf 'Error: Fcitx helper service unit contract changed: %s\n' "$setting" >&2; exit 1; }
done
! grep -Eq '(^|/)(fcitx5|systemctl|omarchy)([[:space:]]|$)' "$service_unit" || {
	printf 'Error: Fcitx helper unit must not control Fcitx or another service.\n' >&2
	exit 1
}
! grep -Eq '(^|[^[:alnum:]_])(fork|exec[lvpe]*|system|posix_spawn)[[:space:]]*[(]' \
	"$plugin_root/src/fcitx-helper.cpp" "$plugin_root/src/fcitx-helper-main.cpp" || {
	printf 'Error: Fcitx helper must not fork, execute, or control another process.\n' >&2
	exit 1
}
! grep -R -Fq '.config/fcitx5/profile' "$plugin_root/include/fcitx-controller.hpp" "$plugin_root/src/fcitx-controller.cpp" \
	"$plugin_root/src/fcitx-sd-bus-transport.cpp" || {
	printf 'Error: Controller adapter must not write or own raw Fcitx profile bytes.\n' >&2
	exit 1
}
jq -e '.version == 1 and (.files | keys | sort) == ([".luarc.json","autostart.lua","bindings.lua","hypridle.conf","hyprland.lua","hyprlock.conf","hyprsunset.conf","input.lua","looknfeel.lua","monitors.lua","xdph.conf"] | sort) and all(.files[]; test("^[0-9a-f]{64}$"))' "$plugin_root/migration-baseline.json" >/dev/null
jq -e '(.seams | keys | sort) == (["bin/omarchy-bar","bin/omarchy-plugin-disable","bin/omarchy-plugin-enable","bin/omarchy-refresh-config","bin/omarchy-refresh-hyprland","config/omarchy/shell.json","shell/Ui/PluginBarApi.qml","shell/plugins/bar/Bar.qml","shell/plugins/bar/widgets/KeyboardLayout.manifest.json","shell/plugins/bar/widgets/KeyboardLayout.qml","shell/plugins/bar/widgets/KeyboardLayoutModel.js","shell/services/PluginRegistry.qml","shell/shell.qml"] | sort) and all(.seams[]; test("^[0-9a-f]{64}$"))' "$plugin_root/migration-baseline.json" >/dev/null

contract_files=(
	active-fixtures.json
	authority.json
	evidence-v3.json
	fcitx.json
	health.json
	manifest.json
	protocol.json
	systemd.json
)
mapfile -t contract_entries < <(find "$contract_root" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
[[ $(printf '%s\n' "${contract_entries[@]}") == "$(printf '%s\n' "${contract_files[@]}")" ]] || {
	printf 'Error: Fcitx integration contract inventory is not exact.\n' >&2
	exit 1
}
for source in "${contract_files[@]}"; do
	contract=$contract_root/$source
	[[ -f $contract && ! -L $contract ]] || {
		printf 'Error: Fcitx integration contract must be a regular file: %s\n' "$source" >&2
		exit 1
	}
	jq -e 'type == "object"' "$contract" >/dev/null || { printf 'Error: malformed Fcitx integration contract: %s\n' "$source" >&2; exit 1; }
done
jq -e --argjson files "$(printf '%s\n' "${contract_files[@]}" | jq -Rsc 'split("\n")[:-1]')" '
	(keys | sort) == (["version","integration","files","contracts"] | sort) and
	.version == 1 and .integration == "dotfiles-input-languages-fcitx-v1" and .files == $files and
	.contracts == {
		authority:"dotfiles-input-languages-authority-v1",
		evidence:"dotfiles-input-languages-evidence-v3",
		fcitx:"dotfiles-input-languages-fcitx-controller-v1",
		fixtures:"dotfiles-input-languages-active-fixtures-v1",
		health:"dotfiles-input-languages-health-v1",
		protocol:"dotfiles-input-languages-fcitx-seqpacket-v1",
		systemd:"dotfiles-input-languages-fcitx-systemd-v1"
	}
' "$contract_root/manifest.json" >/dev/null || { printf 'Error: Fcitx integration manifest shape or identity changed.\n' >&2; exit 1; }
integration=$(jq -r .integration "$contract_root/manifest.json")
for source in authority.json evidence-v3.json fcitx.json health.json protocol.json systemd.json active-fixtures.json; do
	[[ $(jq -r .integration "$contract_root/$source") == "$integration" ]] || {
		printf 'Error: Fcitx integration contract identity disagrees: %s\n' "$source" >&2
		exit 1
	}
done
for mapping in authority:authority.json evidence:evidence-v3.json fcitx:fcitx.json fixtures:active-fixtures.json health:health.json protocol:protocol.json systemd:systemd.json; do
	key=${mapping%%:*}
	source=${mapping#*:}
	[[ $(jq -r --arg key "$key" '.contracts[$key]' "$contract_root/manifest.json") == "$(jq -r .identity "$contract_root/$source")" ]] || {
		printf 'Error: Fcitx integration contract member identity disagrees: %s\n' "$source" >&2
		exit 1
	}
done
protocol_identity=$(jq -r .identity "$contract_root/protocol.json")
[[ $(jq -r .protocol "$contract_root/health.json") == "$protocol_identity" && $(jq -r .protocol "$contract_root/systemd.json") == "$protocol_identity" ]] || {
	printf 'Error: Fcitx protocol identity disagrees across contracts.\n' >&2
	exit 1
}
jq -e --slurpfile authority "$contract_root/authority.json" '
	.compatibility.upstream_version == "5.1.22" and .compatibility.arch_release_suffix_is_semantic == false and
	.compatibility.transport_library == "libsystemd" and .compatibility.bus_api == "sd-bus" and .compatibility.event_api == "sd-event" and
	.controller.well_known_name == "org.fcitx.Fcitx5" and .controller.object_path == "/controller" and .controller.interface == "org.fcitx.Fcitx.Controller1" and
	.controller.members == {
		AddInputMethodGroup:{type:"method",input:"s",output:""},
		AvailableInputMethods:{type:"method",input:"",output:"a(ssssssb)"},
		CurrentInputMethod:{type:"method",input:"",output:"s"},
		CurrentInputMethodGroup:{type:"method",input:"",output:"s"},
		DebugInfo:{type:"method",input:"",output:"s"},
		FullInputMethodGroupInfo:{type:"method",input:"s",output:"sssa{sv}a(sssssssbsa{sv})"},
		GetAddonsV2:{type:"method",input:"",output:"a(sssibbbasas)"},
		InputMethodGroupInfo:{type:"method",input:"s",output:"sa(ss)"},
		InputMethodGroups:{type:"method",input:"",output:"as"},
		InputMethodGroupsChanged:{type:"signal",input:"",output:""},
		RemoveInputMethodGroup:{type:"method",input:"s",output:""},
		Save:{type:"method",input:"",output:""},
		SetCurrentIM:{type:"method",input:"s",output:""},
		SetInputMethodGroupInfo:{type:"method",input:"ssa(ss)",output:""},
		SwitchInputMethodGroup:{type:"method",input:"s",output:""}
	} and
	.compatibility_gates.changed_apply_members == (.controller.members | keys) and
	.compatibility_gates.narrow_restoration_members == ["AddInputMethodGroup","CurrentInputMethod","CurrentInputMethodGroup","FullInputMethodGroupInfo","InputMethodGroups","RemoveInputMethodGroup","Save","SetCurrentIM","SetInputMethodGroupInfo","SwitchInputMethodGroup"] and
	.compatibility_gates.narrow_restoration_requires == ["exact-listed-signatures","supported-group-semantics","supervised-unique-owner","safe-profile-and-owned-paths","valid-version-3-receipt-and-restoration-anchors"] and
	.managed_group == {name:"Dotfiles Input Languages",default_layout:"us",default_im_allowed:["","keyboard-us","keyboard-ru"],items:[{method:"keyboard-us",layout_override:""},{method:"keyboard-ru",layout_override:""}],existing_name_policy:"collision",mutation_seam:"Controller1-followed-by-Save"} and
	[.managed_group.items[].method] == [$authority[0].languages[].fcitx_method] and
	.delivery.poll_seconds == 1 and .delivery.call_deadline_seconds == 1 and .delivery.repair_retry_seconds == [1,2,4,8]
' "$contract_root/fcitx.json" >/dev/null || { printf 'Error: Fcitx compatibility, Controller shape, managed group, or delivery constants changed.\n' >&2; exit 1; }
jq -e '
	.transport.maximum_packet_bytes == 1024 and .connection_retry_milliseconds == [100,200,400,800,1600,2000] and
	.wire.enums.managed_group_state == {unknown:0,exact:1,missing:2,foreign:3} and
	.wire.enums.owner_state == {absent:0,present:1,competing:2} and
	.wire.enums.retry_phase == {none:0,poll:1,read:2,write:3,"read-before-retry":4,backoff:5} and
	.wire.enums.outcome == {pending:0,converged:1,"idle-no-context":2,drift:3,unavailable:4,disconnected:5,"timeout-indeterminate":6,"method-error":7,"configuration-conflict":8,"unsupported-interface":9,"protocol-error":10,"helper-failed":11} and
	[.frames.HELLO.fields[].name] == ["protocol_identity","build_id","source_id","authority_session","language","generation"] and
	[.frames.READY.fields[].name] == ["protocol_identity","build_id","source_id","authority_session"] and
	[.frames.TARGET.fields[].name] == ["authority_session","language","generation"] and
	[.frames.STATE.fields[].name] == ["protocol_identity","build_id","authority_session","report_sequence","accepted_generation","acknowledged_generation","owner_state","unique_owner","owner_epoch","managed_group_state","current_group","observed_method","outcome","retry_phase","diagnostic"] and
	[.frames.HEARTBEAT.fields[].name] == ["authority_session","report_sequence"] and
	(.wire.scalars as $scalars | all(.frames[].fields[]; .scalar as $scalar | $scalars[$scalar] != null))
' "$contract_root/protocol.json" >/dev/null || { printf 'Error: Fcitx private protocol frame schema or fixed constants changed.\n' >&2; exit 1; }
jq -e '
	.snapshot_keys == ["healthy","direct_xkb_health","build_id","source_id","compatibility_hash","canonical_group","physical_keyboards","excluded_keyboards","authority_session","canonical_language","canonical_generation","physical_groups","physical_synchronized","helper_connection","helper_build_id","protocol_identity","offered_generation","accepted_generation","acknowledged_generation","report_sequence","report_age_milliseconds","coalesced_targets","fcitx_owner_state","fcitx_unique_owner","fcitx_owner_epoch","managed_group_state","current_group","observed_method","retry_phase","outcome","diagnostic","report_stale"] and
	(.snapshot_fields | keys | sort) == (.snapshot_keys | sort) and (.snapshot_fields | has("indicator_state") | not) and
	.snapshot_fields.physical_groups == {type:"array",items_ref:"evidence-v3.objects.device_group",unique_by:"device"} and
	.snapshot_fields.report_stale == {type:"boolean"} and .snapshot_fields.diagnostic.maximum_utf8_bytes == 96 and
	.snapshot_fields.canonical_generation.minimum == 1 and .snapshot_fields.offered_generation.minimum == 1 and
	.snapshot_fields.accepted_generation.minimum == 1 and .snapshot_fields.acknowledged_generation.minimum == 1 and .snapshot_fields.report_sequence.minimum == 1 and
	(.helper_outcomes | length) == 12 and (.outcome_runtime_state | keys | sort) == (.helper_outcomes | sort) and
	.runtime_states == ["converged","pending","unavailable","stale","conflicting"] and
	.heartbeat_maximum_interval_seconds == 1 and .maximum_fresh_report_age_seconds == 3 and
	.classification.precedence == ["recovery-required","conflict","uninstalled","healthy","degraded"] and
	.classification["idle-no-context_runtime"] == "pending" and .classification["healthy_requires"] == "converged" and
	.cross_field_relationships == {canonical_language_matches_group:true,physical_keyboard_names_equal_group_devices:true,
		healthy_equals_direct_xkb_health_and_physical_synchronized:true,physical_synchronized_requires_nonempty_groups_at_canonical_group:true,
		offered_generation_equals_canonical_generation:true,connected_requires_matching_helper_build:true,
		disconnected_failed_or_incompatible_requires_null_helper_build:true,report_sequence_age_and_stale_are_jointly_present:true,
		owner_present_or_competing_requires_alias_and_positive_epoch:true,owner_absent_requires_null_alias:true,
		acknowledgement_requires_current_generation_present_owner_exact_managed_current_group_converged_nonempty_matching_method_fresh_report:true}
' "$contract_root/health.json" >/dev/null || { printf 'Error: Fcitx health schema, outcome mapping, or classification constants changed.\n' >&2; exit 1; }
jq -e '
	. as $root |
	.version == 3 and .version_2.immutable and
	(.objects | keys | sort) == (["active","addon_state","device_group","direct_ancestry","expected_state","fcitx_group","fcitx_item","fcitx_semantic_snapshot","helper_edge","helper_ownership","hyprland_ownership","integration_artifact","integration_cleanup","managed_group","operation_start","pending","profile_diagnostic","profile_evidence","recovery_required","remove_cleanup","restoration","runtime_edge","runtime_identity","service_snapshot","widget_ownership"] | sort) and
	all(.objects[]; (.keys | sort) == (((.references // {}) + (.constants // {}) + (.enums // {})) | keys | sort)) and
	all(.objects[].references[]; . as $ref | ($root.types | has($ref)) or ($root.objects | has($ref))) and
	.version_2.exact_keys.active == ["version","operation","transaction_id","backup_transaction_id","source_id","build_id","artifact","artifact_sha256","widget_sha256","compatibility_hash","compiler","compiler_warning","dependencies","backup","backup_digest","backup_existed","widget_source","widget_section","widget_index","widget_entry","prior_stock_present","prior_stock_section","prior_stock_index","prior_stock_entry"] and
	.objects.active.constants == {version:3,operation:"active"} and .objects.pending.constants.version == 3 and .objects.pending.enums.operation == ["apply","remove"] and
	.types["input-group"] == {type:"integer",enum:[0,1]} and .objects.device_group == {keys:["device","group"],references:{device:"string",group:"input-group"}} and
	.types["semantic-rollback-phase"] == {type:"string",enum:["authority-quiesced","direct-restored","fcitx-semantic-delta-reversed","helper-state-restored","operation-start-language-restored","verified"]} and
	.objects.recovery_required.references.failed_phase == "semantic-rollback-phase" and
	.objects.recovery_required.constants == {version:3,state:"recovery-required"} and .objects.remove_cleanup.constants == {version:3,state:"remove-cleanup"} and
	.raw_profile_restoration_allowed == false and .active_receipt_publish_order == "last"
' "$contract_root/evidence-v3.json" >/dev/null || { printf 'Error: Fcitx version-3 evidence schema or version-2 ancestry contract changed.\n' >&2; exit 1; }
jq -e '.service.environment == "XDG_RUNTIME_DIR=%t" and .service.restart == "on-failure" and .service.restart_seconds == 2 and .service.start_limit_interval_seconds == 30 and .service.start_limit_burst == 5 and .service.starts_or_restarts_fcitx == false' "$contract_root/systemd.json" >/dev/null || { printf 'Error: Fcitx helper systemd contract changed.\n' >&2; exit 1; }
jq -e '[.fixtures[].id] == ["ghostty-fcitx-wayland","brave-fcitx-wayland","dotfiles-direct-wayland","dotfiles-direct-xwayland"] and [.fixtures[].backend] == ["wayland","wayland","wayland","x11"] and [.fixtures[2:][].route] == ["direct-compositor-xkb","direct-xwayland-xkb"] and [.fixtures[2:][].fcitx_frontend] == [null,null]' "$contract_root/active-fixtures.json" >/dev/null || { printf 'Error: Input Languages active fixture contract changed.\n' >&2; exit 1; }
protocol_header=$plugin_root/include/fcitx-protocol.hpp
protocol_outcome_enum=$(sed -n '/^enum class Outcome : uint8_t {$/,/^};$/p' "$protocol_header" | tr -d '[:space:]')
grep -Fq "MAGIC = $(jq -r '.wire.header[] | select(.name == "magic").value' "$contract_root/protocol.json")" "$protocol_header" &&
	grep -Fq "VERSION = $(jq -r '.wire.header[] | select(.name == "protocol_version").value' "$contract_root/protocol.json")" "$protocol_header" &&
	grep -Fq "HEADER_BYTES = $(jq -r .wire.header_bytes "$contract_root/protocol.json")" "$protocol_header" &&
	grep -Fq "MAX_PACKET_BYTES = $(jq -r .transport.maximum_packet_bytes "$contract_root/protocol.json")" "$protocol_header" &&
	grep -Fq "MAX_TEXT_BYTES = $(jq -r '.wire.scalars.text | capture("maximum-(?<bytes>[0-9]+)-bytes").bytes' "$contract_root/protocol.json")" "$protocol_header" &&
	grep -Fq "IDENTITY = \"$protocol_identity\"" "$protocol_header" &&
	grep -Fq 'enum class FrameType : uint16_t { Hello = 1, Ready = 2, Target = 3, State = 4, Heartbeat = 5 };' "$protocol_header" &&
	grep -Fq 'enum class Language : uint8_t { Us = 0, Russian = 1 };' "$protocol_header" &&
	grep -Fq 'enum class OwnerState : uint8_t { Absent = 0, Present = 1, Competing = 2 };' "$protocol_header" &&
	grep -Fq 'enum class ManagedGroupState : uint8_t { Unknown = 0, Exact = 1, Missing = 2, Foreign = 3 };' "$protocol_header" &&
	grep -Fq 'enum class RetryPhase : uint8_t { None = 0, Poll = 1, Read = 2, Write = 3, ReadBeforeRetry = 4, Backoff = 5 };' "$protocol_header" &&
	[[ $protocol_outcome_enum == 'enumclassOutcome:uint8_t{Pending=0,Converged=1,IdleNoContext=2,Drift=3,Unavailable=4,Disconnected=5,TimeoutIndeterminate=6,MethodError=7,ConfigurationConflict=8,UnsupportedInterface=9,ProtocolError=10,HelperFailed=11,};' ]] &&
	grep -Fq 'std::chrono::milliseconds(100), std::chrono::milliseconds(200), std::chrono::milliseconds(400),' "$plugin_root/include/fcitx-follower.hpp" &&
	grep -Fq 'std::chrono::milliseconds(800), std::chrono::milliseconds(1600), std::chrono::milliseconds(2000)};' "$plugin_root/include/fcitx-follower.hpp" || {
	printf 'Error: compiled Fcitx protocol constants disagree with protocol.json.\n' >&2
	exit 1
}
controller_header=$plugin_root/include/fcitx-controller.hpp
controller_source=$plugin_root/src/fcitx-sd-bus-transport.cpp
grep -Fq "SUPPORTED_UPSTREAM_VERSION = \"$(jq -r .compatibility.upstream_version "$contract_root/fcitx.json")\"" "$controller_header" &&
	grep -Fq "MANAGED_GROUP_NAME = \"$(jq -r .managed_group.name "$contract_root/fcitx.json")\"" "$controller_header" &&
	grep -Fq "US_METHOD = \"$(jq -r '.managed_group.items[0].method' "$contract_root/fcitx.json")\"" "$controller_header" &&
	grep -Fq "RUSSIAN_METHOD = \"$(jq -r '.managed_group.items[1].method' "$contract_root/fcitx.json")\"" "$controller_header" &&
	grep -Fq "FCITX_NAME = \"$(jq -r .controller.well_known_name "$contract_root/fcitx.json")\"" "$controller_source" &&
	grep -Fq "CONTROLLER_PATH = \"$(jq -r .controller.object_path "$contract_root/fcitx.json")\"" "$controller_source" &&
	grep -Fq "CONTROLLER_INTERFACE = \"$(jq -r .controller.interface "$contract_root/fcitx.json")\"" "$controller_source" || {
	printf 'Error: compiled Fcitx Controller constants disagree with fcitx.json.\n' >&2
	exit 1
}
expected_controller_members=$(jq -r '.controller.members | to_entries[] | [.key,.value.type,.value.input,.value.output] | join("|")' "$contract_root/fcitx.json")
actual_controller_members=$(sed -nE 's/.*ExpectedMember\{"([^"]*)", "([^"]*)", "([^"]*)", "([^"]*)"\}.*/\1|\2|\3|\4/p' "$controller_source")
[[ $actual_controller_members == "$expected_controller_members" ]] || {
	printf 'Error: compiled Fcitx Controller members disagree with fcitx.json.\n' >&2
	exit 1
}
for source in "${contract_files[@]}"; do
	contract=$contract_root/$source
	actual_hash=$(sha256sum "$contract")
	[[ ${actual_hash%% *} == "$(input_languages_integration_contract_expected_digest "$source")" ]] || {
		printf 'Error: frozen Fcitx integration contract changed: %s\n' "$source" >&2
		exit 1
	}
done

mapfile -t widget_entries < <(find "$widget_root" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
[[ $(printf '%s\n' "${widget_entries[@]}") == $'KeyboardLayout.qml\nKeyboardLayoutModel.js\nmanifest.json' ]] || {
	printf 'Error: flag keyboard-layout clone inventory is not exact.\n' >&2
	exit 1
}
[[ $(stat -c %a "$widget_root") == 755 ]] || { printf 'Error: canonical flag-widget directory mode must be 0755.\n' >&2; exit 1; }
for source in "${widget_entries[@]}"; do
	[[ -f $widget_root/$source && ! -L $widget_root/$source && $(stat -c %a "$widget_root/$source") == 644 ]] || {
		printf 'Error: canonical flag-widget file must be a regular 0644 file: %s\n' "$source" >&2
		exit 1
	}
done
jq -e '
	(keys | sort) == (["schemaVersion","id","name","version","author","description","kinds","entryPoints","barWidget","omarchy"] | sort) and
	.schemaVersion == 1 and .id == "dotfiles.keyboard-layout" and .name == "Flag keyboard layout" and .version == "1.0.0" and .author == "Dotfiles" and
	.description == "Current US or Russian keyboard layout as a flag, click cycles" and .kinds == ["bar-widget"] and
	.entryPoints == {barWidget:"KeyboardLayout.qml"} and
	.barWidget == {displayName:"Flag keyboard layout",description:"Current US or Russian keyboard layout as a flag, click cycles",category:"Compositor",allowMultiple:false} and
	.omarchy == {clonedFrom:"omarchy.keyboard-layout"}
' "$widget_root/manifest.json" >/dev/null
grep -Fq 'moduleName: "dotfiles.keyboard-layout"' "$widget_root/KeyboardLayout.qml"
grep -Fq 'readonly property bool themedFlagVisible: root.layoutFull === "English (US)" || root.layoutFull === "Russian"' "$widget_root/KeyboardLayout.qml"
grep -Fq 'fixedWidth: themedFlagVisible ? Style.bar.iconSlot : -1' "$widget_root/KeyboardLayout.qml"
grep -Fq $'\t\t\twidth: 12' "$widget_root/KeyboardLayout.qml"
grep -Fq $'\t\t\theight: 8' "$widget_root/KeyboardLayout.qml"
grep -Fq 'visible: root.layoutFull === "English (US)"' "$widget_root/KeyboardLayout.qml"
grep -Fq 'visible: root.layoutFull === "Russian"' "$widget_root/KeyboardLayout.qml"
stock_widget_root=$omarchy_root/shell/plugins/bar/widgets
if ! cmp -s \
	<(sed -E '/^[[:space:]]*WidgetButton \{$/,$d; s/^[[:space:]]*//; s/moduleName: "omarchy[.]keyboard-layout"/moduleName: "dotfiles.keyboard-layout"/' "$stock_widget_root/KeyboardLayout.qml" | grep -v '^[[:space:]]*$') \
	<(sed -E '/^[[:space:]]*WidgetButton \{$/,$d; s/^[[:space:]]*//' "$widget_root/KeyboardLayout.qml" | grep -v '^[[:space:]]*$'); then
	printf 'Error: flag widget behavior before its themed rendering block drifted from stock.\n' >&2
	exit 1
fi
widget_button_behavior() {
	sed -n '/^[[:space:]]*WidgetButton {/,/^[[:space:]]*Item {/p' "$1" |
		grep -E '^[[:space:]]*(id: button|anchors[.]fill: parent|bar: root[.]bar|fontSize: Style[.]font[.]caption|horizontalMargin: 6|tooltipText: root[.]layoutFull|onPressed: function[(][)] \{ root[.]cycleLayout[(][)] \})[[:space:]]*$' |
		sed -E 's/^[[:space:]]*//'
}
if ! cmp -s <(widget_button_behavior "$stock_widget_root/KeyboardLayout.qml") <(widget_button_behavior "$widget_root/KeyboardLayout.qml"); then
	printf 'Error: flag widget button behavior drifted from stock.\n' >&2
	exit 1
fi
if ! cmp -s \
	<(sed -E 's/^[[:space:]]*//' "$stock_widget_root/KeyboardLayoutModel.js" | grep -v '^[[:space:]]*$') \
	<(sed -E 's/^[[:space:]]*//' "$widget_root/KeyboardLayoutModel.js" | grep -v '^[[:space:]]*$'); then
	printf 'Error: flag widget model drifted from stock.\n' >&2
	exit 1
fi

while IFS=$'\t' read -r seam expected_hash; do
	[[ -f $omarchy_root/$seam ]] || { printf 'Error: required Omarchy integration seam is missing: %s\n' "$seam" >&2; exit 1; }
	actual_hash=$(sha256sum "$omarchy_root/$seam")
	[[ ${actual_hash%% *} == "$expected_hash" ]] || { printf 'Error: Omarchy integration seam changed and requires review: %s\n' "$seam" >&2; exit 1; }
done < <(jq -r '.seams | to_entries[] | [.key,.value] | @tsv' "$plugin_root/migration-baseline.json")

defaults_line=$(grep -n 'require("default.hypr.omarchy")' "$package_root/hyprland.lua" | cut -d: -f1)
input_line=$(grep -n 'require("hypr.input")' "$package_root/hyprland.lua" | cut -d: -f1)
plugin_line=$(grep -n 'hl.plugin.load(artifact)' "$package_root/hyprland.lua" | cut -d: -f1)
[[ $defaults_line =~ ^[0-9]+$ && $input_line =~ ^[0-9]+$ && $plugin_line =~ ^[0-9]+$ && $defaults_line -lt $input_line && $input_line -lt $plugin_line ]] || {
	printf 'Error: Hyprland defaults, input override, and immutable plugin load are not in the required order.\n' >&2
	exit 1
}

grep -Fq "choice=\$(wizard_choose_repeating 'Settings' 'Input Languages' Back)" "$repository_root/lib/dotfiles/wizard.sh"
grep -Fq "choice=\$(wizard_choose_repeating 'Input Languages' Status Apply Remove Back)" "$repository_root/lib/dotfiles/input-languages.sh"
grep -Fq "choice=\$(wizard_choose_repeating 'Input Languages result' 'Return to Input Languages' Status)" "$repository_root/lib/dotfiles/input-languages.sh"
grep -Fq "labels+=('Manage screensaver effects' 'Manage laptop power policy' 'Settings' 'Exit')" "$repository_root/lib/dotfiles/wizard.sh"

hash_check_line=$(grep -n '!InputLanguages::compatibilityMatches' "$plugin_root/src/plugin.cpp" | cut -d: -f1)
internals_line=$(grep -n 'std::make_unique<InputLanguagePlugin>' "$plugin_root/src/plugin.cpp" | cut -d: -f1)
[[ $hash_check_line =~ ^[0-9]+$ && $internals_line =~ ^[0-9]+$ && $hash_check_line -lt $internals_line ]] || {
	printf 'Error: the plugin must reject the complete compatibility hash before constructing its Hyprland adapter.\n' >&2
	exit 1
}
grep -Fq 'm_dispatchers.find(std::string(RESET_DISPATCHER))' "$plugin_root/src/plugin.cpp" || {
	printf 'Error: the HyprCtl reset adapter must invoke the dedicated plugin dispatcher.\n' >&2
	exit 1
}

if command -v xkbcli >/dev/null 2>&1; then
	xkbcli compile-keymap --layout us,ru --variant ',' --options compose:caps,shift:both_capslock_cancel >/dev/null
elif [[ $mode == full ]]; then
	printf 'Error: xkbcli is required for complete Input Languages validation.\n' >&2
	exit 1
fi
if [[ $mode == full ]]; then
	make --no-print-directory -C "$plugin_root" test >/dev/null
	make --no-print-directory -C "$plugin_root" check >/dev/null
fi

printf 'Input Languages sources: valid\n'
