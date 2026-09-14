#!/usr/bin/env bash

# Places Omarchy Shell bar widgets where this repository wants them. Omarchy owns
# shell.json and rewrites it atomically, so the repository applies the layout
# through Omarchy's bar command instead of linking the file.

apply_shell_layout() {
	local shell_config=$HOME/.config/omarchy/shell.json first_right
	printf 'Plan: move omarchy.keyboard-layout to the start of the right bar section, before omarchy.tray.\n'
	if ! wizard_confirm 'Apply this Shell layout?'; then
		printf 'No changes made.\n'
		return 0
	fi
	if ! omarchy bar move omarchy.keyboard-layout --section right --index 0; then
		printf 'Error: Omarchy could not move omarchy.keyboard-layout.\n' >&2
		printf 'Recovery: make sure omarchy-shell is running, then choose Apply Shell layout in the Dotfiles wizard.\n' >&2
		return 1
	fi
	first_right=$(jq -r '.bar.layout.right[0].id // empty' "$shell_config" 2>/dev/null) || first_right=''
	if [[ $first_right != omarchy.keyboard-layout ]]; then
		printf 'Error: omarchy.keyboard-layout is not first in the right bar section of %s.\n' "$shell_config" >&2
		printf 'Recovery: inspect the bar layout, then choose Apply Shell layout in the Dotfiles wizard.\n' >&2
		return 1
	fi
	printf 'Shell layout applied and verified.\n'
}
