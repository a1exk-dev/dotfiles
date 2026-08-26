#!/usr/bin/env bash

set -u

readonly TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SUITES=(
	inspection_test.sh
	bash_test.sh
	starship_test.sh
	btop_test.sh
	opencode_test.sh
	tmux_test.sh
	packages_test.sh
	skills_test.sh
	cleanup_test.sh
	modem_test.sh
	brave_test.sh
	telegram_theme_generator_test.sh
	telegram_theme_hook_test.sh
	telegram_theme_lifecycle_test.sh
	wizard_test.sh
)

failed=false
for suite in "${SUITES[@]}"; do
	printf '# %s\n' "$suite"
	if ! bash "$TEST_ROOT/$suite"; then
		failed=true
	fi
done

[[ $failed == false ]]
