#!/usr/bin/env bash

set -u

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly REPOSITORY_ROOT=$(cd -- "$TEST_ROOT/.." && pwd)

plugin_behavior_harness_passes() {
	make --no-print-directory -C "$REPOSITORY_ROOT/plugins/input-languages" test >/dev/null
}

exact_stack_plugin_compiles() {
	make --no-print-directory -C "$REPOSITORY_ROOT/plugins/input-languages" check >/dev/null
}

flag_widget_model_matches_stock() {
	node "$REPOSITORY_ROOT/plugins/input-languages/tests/keyboard-layout-model-test.cjs" \
		"$REPOSITORY_ROOT/plugins/input-languages/widget/dotfiles.keyboard-layout/KeyboardLayoutModel.js" \
		/usr/share/omarchy/shell/plugins/bar/widgets/KeyboardLayoutModel.js
}

run_test plugin_behavior_harness_passes 'plugin behavior harness passes'
run_test exact_stack_plugin_compiles 'exact-stack plugin compiles and exports its API'
run_test flag_widget_model_matches_stock 'flag widget model preserves stock behavior'

finish_tests
