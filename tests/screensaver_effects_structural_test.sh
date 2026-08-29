#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

HOST_TTFX=$(command -v ttfx)

setup_structural_fixture() {
	new_fixture || return 1
	STRUCTURAL_REPO=$FIXTURE_ROOT/structural-repo
	STRUCTURAL_OMARCHY_ROOT=
	mkdir -p "$STRUCTURAL_REPO/config" "$FIXTURE_CONFIG/dotfiles"
	cp -a "$SOURCE_REPO/config/screensaver-effects" "$STRUCTURAL_REPO/config/screensaver-effects"
}

setup_structural_omarchy_fixture() {
	local path destination
	local -a paths=(
		shell/plugins/services/idle
		shell/plugins/bar/widgets/Indicators.manifest.json
		shell/plugins/bar/widgets/Indicators.qml
		shell/plugins/bar/indicators
		shell/services/PluginRegistry.qml
		shell/shell.qml
		shell/plugins/menu/Menu.qml
		bin/omarchy-plugin-clone
		bin/omarchy-plugin-enable
		bin/omarchy-plugin-disable
		bin/omarchy-plugin-remove
		bin/omarchy-plugin-catalog
		bin/omarchy-plugin-list
		bin/omarchy-launch-screensaver
		bin/omarchy-screensaver
		bin/omarchy-theme-color
		default/alacritty/screensaver.toml
		default/ghostty/screensaver
		default/foot/screensaver.ini
		default/omarchy/omarchy-menu.jsonc
		default/hypr/apps/system.lua
	)
	STRUCTURAL_OMARCHY_ROOT=$FIXTURE_ROOT/structural-omarchy
	mkdir -p "$STRUCTURAL_OMARCHY_ROOT"
	for path in "${paths[@]}"; do
		destination=$STRUCTURAL_OMARCHY_ROOT/$path
		mkdir -p "${destination%/*}"
		cp -a "/usr/share/omarchy/$path" "$destination"
	done
}

run_structural_validator() {
	local status
	set +e
	COMMAND_OUTPUT=$(env -i \
		HOME="$FIXTURE_HOME" \
		XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
		XDG_STATE_HOME="$FIXTURE_STATE" \
		XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" \
		PATH="${STRUCTURAL_PATH:-/usr/bin:/bin}" \
		DOTFILES_REPOSITORY_ROOT="$STRUCTURAL_REPO" \
		DOTFILES_SCREENSAVER_TEST_OMARCHY_ROOT="${STRUCTURAL_OMARCHY_ROOT:-/usr/share/omarchy}" \
		bash "$SOURCE_REPO/lib/dotfiles/screensaver-effects-validator.sh" 2>&1)
	status=$?
	set -e
	COMMAND_STATUS=$status
}

test_structural_validator_accepts_the_tracked_package_without_a_live_leaf() {
	setup_structural_fixture || return 1
	run_structural_validator
	assert_eq 0 "$COMMAND_STATUS" 'the tracked package should pass structural validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4.0.1-1' \
		'the validator should report the supported Omarchy baseline' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported ttfx package/CLI: 0.3.2-1 / 0.3.2' \
		'the validator should report both supported ttfx versions'
}

test_structural_validator_rejects_inventory_mode_and_source_drift() {
	setup_structural_fixture || return 1
	printf 'generated state\n' >"$STRUCTURAL_REPO/config/screensaver-effects/generated-state"
	chmod 0644 "$STRUCTURAL_REPO/config/screensaver-effects/.local/libexec/dotfiles/screensaver-effects-selector"
	printf '\n# drift\n' >>"$STRUCTURAL_REPO/config/screensaver-effects/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml"
	run_structural_validator
	assert_eq 1 "$COMMAND_STATUS" 'package drift should fail structural validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unexpected package inventory path: generated-state' \
		'unexpected generated state should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'package mode drift at .local/libexec/dotfiles/screensaver-effects-selector' \
		'executable mode drift should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'reviewed package source drift at .local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/Service.qml' \
		'a reviewed clone patch should be hash-stable'
}

test_structural_validator_rejects_invalid_configuration_and_foreign_live_leaf() {
	setup_structural_fixture || return 1
	printf '["matrix", "matrix"]\n' >"$STRUCTURAL_REPO/config/screensaver-effects/.config/dotfiles/screensaver-effects.json"
	printf 'foreign\n' >"$FIXTURE_CONFIG/dotfiles/screensaver-effects.json"
	run_structural_validator
	assert_eq 1 "$COMMAND_STATUS" 'invalid configuration and ownership should fail validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'tracked allowlist must be a nonempty array of unique lowercase effect names' \
		'the complete strict allowlist schema should be enforced' || return 1
	assert_contains "$COMMAND_OUTPUT" 'deployed allowlist leaf is not a Stow symlink' \
		'a foreign live leaf should be reported without replacement'
}

test_structural_validator_reports_complete_clone_surface_inventory_drift() {
	setup_structural_fixture || return 1
	setup_structural_omarchy_fixture || return 1
	printf 'unexpected clone source\n' >"$STRUCTURAL_OMARCHY_ROOT/shell/plugins/services/idle/Unexpected.qml"
	rm "$STRUCTURAL_OMARCHY_ROOT/shell/plugins/bar/indicators/Dictation.qml"
	run_structural_validator
	assert_eq 1 "$COMMAND_STATUS" 'clone inventory drift should fail on the supported Omarchy baseline' || return 1
	assert_contains "$COMMAND_OUTPUT" \
		"ERROR: supported Omarchy clone surface difference: unexpected path: $STRUCTURAL_OMARCHY_ROOT/shell/plugins/services/idle/Unexpected.qml" \
		'an added clone-surface file should be reported as an error' || return 1
	assert_contains "$COMMAND_OUTPUT" \
		"ERROR: supported Omarchy clone surface difference: missing path: $STRUCTURAL_OMARCHY_ROOT/shell/plugins/bar/indicators/Dictation.qml" \
		'a removed clone-surface file should be reported as an error' || return 1

	make_fake omarchy 'if [[ ${1-} == version ]]; then printf "9.0.0-1\n"; else exit 64; fi'
	STRUCTURAL_PATH=$FIXTURE_BIN:/usr/bin:/bin
	run_structural_validator
	assert_eq 0 "$COMMAND_STATUS" 'clone inventory drift should warn on an Omarchy version mismatch' || return 1
	assert_contains "$COMMAND_OUTPUT" \
		"Warning: detected Omarchy clone surface differs from the supported baseline: unexpected path: $STRUCTURAL_OMARCHY_ROOT/shell/plugins/services/idle/Unexpected.qml" \
		'an added clone-surface file should be reported as a warning on version mismatch' || return 1
	assert_contains "$COMMAND_OUTPUT" \
		"Warning: detected Omarchy clone surface differs from the supported baseline: missing path: $STRUCTURAL_OMARCHY_ROOT/shell/plugins/bar/indicators/Dictation.qml" \
		'a removed clone-surface file should be reported as a warning on version mismatch'
}

test_structural_validator_treats_detected_version_drift_as_warning_only() {
	setup_structural_fixture || return 1
	make_fake omarchy 'if [[ ${1-} == version ]]; then printf "9.0.0-1\n"; else exit 64; fi'
	# The fake ttfx needs only a fixed path to the read-only host binary.
	printf '#!/usr/bin/env bash\nset -u\nif [[ ${1-} == --version ]]; then printf "ttfx 0.4.0\\n"; else exec %q "$@"; fi\n' \
		"$HOST_TTFX" >"$FIXTURE_BIN/ttfx"
	chmod 0755 "$FIXTURE_BIN/ttfx"
	STRUCTURAL_PATH=$FIXTURE_BIN:/usr/bin:/bin
	run_structural_validator
	assert_eq 0 "$COMMAND_STATUS" 'version drift alone should not fail structural validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: supported Omarchy is 4.0.1-1' \
		'Omarchy drift should be visible' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: supported ttfx package/CLI is 0.3.2-1 / 0.3.2' \
		'ttfx drift should be visible' || return 1
	assert_contains "$COMMAND_OUTPUT" 'structural validation passed' \
		'warning-only compatibility should still complete validation'
}

set -e
run_test test_structural_validator_accepts_the_tracked_package_without_a_live_leaf \
	'structural validator accepts the tracked package without a live leaf'
run_test test_structural_validator_rejects_inventory_mode_and_source_drift \
	'structural validator rejects package inventory, mode, and source drift'
run_test test_structural_validator_rejects_invalid_configuration_and_foreign_live_leaf \
	'structural validator rejects invalid configuration and foreign live leaves'
run_test test_structural_validator_reports_complete_clone_surface_inventory_drift \
	'structural validator reports complete clone-surface inventory drift'
run_test test_structural_validator_treats_detected_version_drift_as_warning_only \
	'structural validator treats detected version drift as warning-only'
finish_tests
