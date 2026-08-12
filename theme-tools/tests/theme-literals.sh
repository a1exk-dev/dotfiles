#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -P -- "$SCRIPT_DIR/../.." && pwd)
MANAGER=$REPO_ROOT/theme-tools/.local/bin/dotfiles-theme
FAILED=0

fail() {
	printf 'not ok - %s\n' "$*" >&2
	FAILED=1
}

required_artifacts=(
	'theme/everforest-hard/.config/hypr/colors.lua'
	'theme/everforest-hard/.config/hypr/hyprlock-colors.conf'
	'theme/everforest-hard/.config/hypr/playerctlock-colors.sh'
	'theme/everforest-hard/.config/opencode/themes/current.json'
	'theme/everforest-hard/.config/starship/palette.toml'
	'theme/everforest-hard/.config/swaync/theme.css'
	'theme/everforest-hard/.config/sysc-greet/themes/current.toml'
	'theme/everforest-hard/.config/tmux/theme.conf'
	'theme/everforest-hard/.config/waybar/theme.css'
	'theme/everforest-hard/.config/waybar/theme.json'
	'theme/everforest-hard/.config/waybar/theme.sh'
	'theme/everforest-hard/.config/wlogout/theme.css'
	'theme/everforest-hard/.config/zen/chrome/theme.css'
	'theme/everforest-hard/.config/zen/user.js'
	'theme/everforest-hard/.local/share/brave/themes/current/manifest.json'
	'starship/.config/starship/base.toml'
	'zen/profile/user.base.js'
	'zen/profile/chrome/userChrome.css'
)

for artifact in "${required_artifacts[@]}"; do
	[[ -f $REPO_ROOT/$artifact ]] || fail "missing required theme artifact: $artifact"
done

required_bridges=(
	"add_bridge \"\$ZEN_PROFILE\" 'chrome/userChrome.css' \"\$ZEN_USER_CHROME\""
	"add_bridge \"\$CONFIG_HOME\" 'ghostty/themes/current' \"\$current/.config/ghostty/themes/current\""
	"add_bridge \"\$CONFIG_HOME\" 'hypr/colors.lua' \"\$current/.config/hypr/colors.lua\""
	"add_bridge \"\$CONFIG_HOME\" 'hypr/colors/everforest-hard.lua' \"\$current/.config/hypr/colors.lua\""
	"add_bridge \"\$CONFIG_HOME\" 'waybar/colors.css' \"\$current/.config/waybar/theme.css\""
	"add_bridge \"\$CONFIG_HOME\" 'opencode/themes/everforest-hard.json' \"\$current/.config/opencode/themes/current.json\""
	"add_bridge \"\$DATA_HOME\" 'brave/themes/everforest-hard/manifest.json' \"\$current/.local/share/brave/themes/current/manifest.json\""
	"add_bridge \"\$CONFIG_HOME\" 'sysc-greet/themes/everforest-hard.toml' \"\$current/.config/sysc-greet/themes/current.toml\""
	"add_bridge \"\$CONFIG_HOME\" 'starship.toml' \"\$current/.config/starship.toml\""
)

for bridge in "${required_bridges[@]}"; do
	grep -Fq -- "$bridge" "$MANAGER" || fail "missing compatibility bridge: $bridge"
done

required_generators=(
	'.dotfiles-theme-name'
	'.config/starship.toml'
	'.config/zen/user.js'
	'.config/btop/themes/current.theme'
	'.config/ghostty/themes/current'
	'.config/nvim/theme.lua'
)

for generated in "${required_generators[@]}"; do
	grep -Fq -- "$generated" "$MANAGER" || fail "missing bundle generator: $generated"
done

if grep -Fq -- '.config/ghostty/theme.conf' "$MANAGER"; then
	fail 'obsolete Ghostty config fragment is still managed'
fi

runtime_roots=(
	'btop'
	'brave'
	'ghostty'
	'hyprland'
	'nvim'
	'opencode'
	'starship'
	'swaync'
	'sysc-greet'
	'tmux'
	'waybar'
	'wlogout'
	'zen'
	'zsh'
)

# Match canonical palette values, not generic validators, variable references, or opacity-only settings.
hex_colors='d3c6aa|e67e80|dbbc7f|a7c080|7fbbb3|d699b6|83c092|e69875|7a8478|859289|9da9a0|1e2326|272e33|2e383c|374145|414b50|495156|4f5b58|493b40|45443c|3c4841|384b55|463f48|4c3743'
rgb_colors='211[[:space:]]*,[[:space:]]*198[[:space:]]*,[[:space:]]*170|230[[:space:]]*,[[:space:]]*126[[:space:]]*,[[:space:]]*128|219[[:space:]]*,[[:space:]]*188[[:space:]]*,[[:space:]]*127|167[[:space:]]*,[[:space:]]*192[[:space:]]*,[[:space:]]*128|127[[:space:]]*,[[:space:]]*187[[:space:]]*,[[:space:]]*179|214[[:space:]]*,[[:space:]]*153[[:space:]]*,[[:space:]]*182|131[[:space:]]*,[[:space:]]*192[[:space:]]*,[[:space:]]*146|230[[:space:]]*,[[:space:]]*152[[:space:]]*,[[:space:]]*117|122[[:space:]]*,[[:space:]]*132[[:space:]]*,[[:space:]]*120|133[[:space:]]*,[[:space:]]*146[[:space:]]*,[[:space:]]*137|157[[:space:]]*,[[:space:]]*169[[:space:]]*,[[:space:]]*160|30[[:space:]]*,[[:space:]]*35[[:space:]]*,[[:space:]]*38|39[[:space:]]*,[[:space:]]*46[[:space:]]*,[[:space:]]*51|46[[:space:]]*,[[:space:]]*56[[:space:]]*,[[:space:]]*60|55[[:space:]]*,[[:space:]]*65[[:space:]]*,[[:space:]]*69|65[[:space:]]*,[[:space:]]*75[[:space:]]*,[[:space:]]*80|73[[:space:]]*,[[:space:]]*81[[:space:]]*,[[:space:]]*86|79[[:space:]]*,[[:space:]]*91[[:space:]]*,[[:space:]]*88|73[[:space:]]*,[[:space:]]*59[[:space:]]*,[[:space:]]*64|69[[:space:]]*,[[:space:]]*68[[:space:]]*,[[:space:]]*60|60[[:space:]]*,[[:space:]]*72[[:space:]]*,[[:space:]]*65|56[[:space:]]*,[[:space:]]*75[[:space:]]*,[[:space:]]*85|70[[:space:]]*,[[:space:]]*63[[:space:]]*,[[:space:]]*72|76[[:space:]]*,[[:space:]]*55[[:space:]]*,[[:space:]]*67'
hex_pattern="#{1,2}(${hex_colors})([[:xdigit:]]{2})?([^[:xdigit:]]|$)"
packed_pattern="(rgb|rgba)[[:space:]]*\\([[:space:]]*(${hex_colors})([[:xdigit:]]{2})?[[:space:]]*\\)"
function_pattern="(rgb|rgba)[[:space:]]*\\([[:space:]]*(${rgb_colors})[[:space:]]*(,|\\))"
array_pattern="\\[[[:space:]]*(${rgb_colors})[[:space:]]*\\]"

is_runtime_text() {
	case $1 in
		*.conf | *.css | *.ini | *.js | *.json | *.jsonc | *.lua | *.sh | *.svg | *.toml | *.xml | */.tmux.conf | */.zshrc | */ghostty/.config/ghostty/config)
			return 0
			;;
	esac
	return 1
}

for root in "${runtime_roots[@]}"; do
	[[ -d $REPO_ROOT/$root ]] || {
		fail "missing migrated app root: $root"
		continue
	}
	while IFS= read -r -d '' file; do
		is_runtime_text "$file" || continue
		if matches=$(LC_ALL=C grep -Ein \
			-e "$hex_pattern" \
			-e "$packed_pattern" \
			-e "$function_pattern" \
			-e "$array_pattern" \
			-- "$file" 2>/dev/null); then
			printf 'concrete Everforest literal: %s\n%s\n' "${file#"$REPO_ROOT"/}" "$matches" >&2
			FAILED=1
		else
			grep_status=$?
			((grep_status == 1)) || fail "could not audit runtime file: ${file#"$REPO_ROOT"/}"
		fi
	done < <(find "$REPO_ROOT/$root" -type f -print0)
done

((FAILED == 0)) || exit 1
printf 'theme literal audit passed\n'
