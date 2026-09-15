#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly SYSTEM24_TEMPLATE=$SOURCE_REPO/config/discord-system24/.config/omarchy/themed/discord-system24.css.tpl
readonly SYSTEM24_IMPORT="@import url('https://refact0r.github.io/system24/build/system24.css');"
readonly SYSTEM24_FONT_PLACEHOLDER=__OMARCHY_FONT__
readonly OMARCHY_TEMPLATE_RENDERER=/usr/share/omarchy/bin/omarchy-theme-set-templates
readonly -a SYSTEM24_MAPPED_COLORS=(
	text-0 text-1 text-2 text-3 text-4 text-5
	bg-1 bg-2 bg-3 bg-4
	hover active active-2 button-border
	accent-1 accent-2 accent-3 accent-4 accent-5
	red-1 red-2 red-3 red-4 red-5
	green-1 green-2 green-3 green-4 green-5
	blue-1 blue-2 blue-3 blue-4 blue-5
	yellow-1 yellow-2 yellow-3 yellow-4 yellow-5
	purple-1 purple-2 purple-3 purple-4 purple-5
)

# Renders the template through Omarchy's installed renderer against one stock
# theme's colors.toml and prints the output path.
render_system24_template() {
	local theme=$1
	local home=$FIXTURE_ROOT/render-$theme/home
	local next_theme=$home/.local/state/omarchy/current/next-theme

	mkdir -p "$home/.config/omarchy/themed" "$next_theme" "$FIXTURE_ROOT/render-$theme/omarchy" || return 1
	cp "$SYSTEM24_TEMPLATE" "$home/.config/omarchy/themed/" || return 1
	cp "/usr/share/omarchy/themes/$theme/colors.toml" "$next_theme/colors.toml" || return 1
	env -i HOME="$home" OMARCHY_PATH="$FIXTURE_ROOT/render-$theme/omarchy" \
		PATH=/usr/share/omarchy/bin:/usr/bin LC_ALL=C \
		bash "$OMARCHY_TEMPLATE_RENDERER" >&2 || return 1
	[[ -f $next_theme/discord-system24.css ]] || return 1
	printf '%s\n' "$next_theme/discord-system24.css"
}

# Prints the declarations of every top-level block whose selector is $2.
css_block_declarations() {
	awk -v selector="$2" '
		$0 ~ "^" selector " *\\{" { inside = 1; next }
		inside && /^\}/ { inside = 0; next }
		inside && /:/ { sub(/^[ \t]+/, ""); print }
	' "$1"
}

assert_valid_system24_color() {
	local name=$1 value=$2 channel

	if [[ $value =~ ^#[0-9a-fA-F]{6}$ ]]; then
		return 0
	fi
	if [[ $value =~ ^rgba\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3}),\ (0?\.[0-9]+|1(\.0+)?)\)$ ]]; then
		for channel in "${BASH_REMATCH[@]:1:3}"; do
			((10#$channel <= 255)) || {
				printf '  --%s has an rgba() channel above 255: %s\n' "$name" "$value" >&2
				return 1
			}
		done
		return 0
	fi
	printf '  --%s should be hex or valid rgba(), got %s\n' "$name" "$value" >&2
	return 1
}

assert_rendered_system24_theme() {
	local theme=$1 rendered root name value

	rendered=$(render_system24_template "$theme") || {
		printf '  %s: omarchy-theme-set-templates should render discord-system24.css\n' "$theme" >&2
		return 1
	}
	assert_eq "$SYSTEM24_IMPORT" "$(head -n 1 "$rendered")" \
		"$theme: the system24 @import should be the first line" || return 1
	if grep -q '{{' "$rendered"; then
		printf '  %s: the rendered file should have no leftover {{\n' "$theme" >&2
		return 1
	fi
	root=$(css_block_declarations "$rendered" ':root')
	for name in "${SYSTEM24_MAPPED_COLORS[@]}"; do
		value=$(sed -n "s/^--$name: \(.*\);$/\1/p" <<<"$root")
		[[ -n $value ]] || {
			printf '  %s: :root should map --%s\n' "$theme" "$name" >&2
			return 1
		}
		assert_valid_system24_color "$name" "$value" || return 1
	done
	assert_contains "$root" "color-scheme: $(env -i PATH=/usr/share/omarchy/bin:/usr/bin LC_ALL=C omarchy-theme-color --file "/usr/share/omarchy/themes/$theme/colors.toml" mode);" \
		"$theme: mode should set color-scheme"
}

test_template_renders_against_a_stock_dark_theme() {
	new_fixture || return 1
	assert_rendered_system24_theme catppuccin
}

test_template_renders_against_a_stock_light_theme() {
	new_fixture || return 1
	assert_rendered_system24_theme catppuccin-latte
}

test_template_body_sets_only_pfp_decor_and_the_font_placeholder() {
	local expected
	expected=$(printf '%s\n' \
		"--font: '$SYSTEM24_FONT_PLACEHOLDER';" \
		"--code-font: '$SYSTEM24_FONT_PLACEHOLDER';" \
		'--remove-pfp-decor: on;')

	assert_eq "$expected" "$(css_block_declarations "$SYSTEM24_TEMPLATE" body)" \
		'body should set only the font variables and --remove-pfp-decor, leaving every other system24 option at upstream' || return 1
	assert_eq 1 "$(grep -c '^body *{' "$SYSTEM24_TEMPLATE")" 'the template should have one body block' || return 1
	assert_eq 2 "$(grep -o "$SYSTEM24_FONT_PLACEHOLDER" "$SYSTEM24_TEMPLATE" | wc -l)" \
		'the font placeholder should appear only in --font and --code-font'
}

test_template_overrides_only_variables_after_the_import() {
	local selectors

	selectors=$(grep -E '^[^ \t/*}].*\{' "$SYSTEM24_TEMPLATE" | sed 's/ *{.*//')
	assert_eq $':root\nbody' "$selectors" 'the template should hold only a :root and a body block' || return 1
	assert_eq 1 "$(grep -c '^@import' "$SYSTEM24_TEMPLATE")" 'the template should import only system24'
}

run_test test_template_renders_against_a_stock_dark_theme 'system24 template renders against a stock dark theme'
run_test test_template_renders_against_a_stock_light_theme 'system24 template renders against a stock light theme'
run_test test_template_body_sets_only_pfp_decor_and_the_font_placeholder 'system24 template body sets only pfp decorations and the font placeholder'
run_test test_template_overrides_only_variables_after_the_import 'system24 template overrides only variables after the import'
finish_tests
