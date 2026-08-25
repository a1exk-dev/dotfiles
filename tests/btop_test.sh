#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly BTOP_CONFIG_RELATIVE=config/btop/.config/btop/btop.conf
readonly BTOP_EXPECTED_VERSION=1.4.7
readonly BTOP_EXPECTED_KEY_COUNT=88

assert_btop_target_version() {
	run_in_sandbox "$FIXTURE_ROOT" /usr/bin:/bin /usr/bin/btop --version
	assert_eq 0 "$COMMAND_STATUS" 'the installed btop binary should report its version' || return 1

	local version_line=${COMMAND_OUTPUT%%$'\n'*}
	if [[ $version_line != 'btop version:'* || ! $version_line =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
		printf '  could not parse the installed btop version from: %q\n' "$version_line" >&2
		return 1
	fi
	assert_eq "$BTOP_EXPECTED_VERSION" "${BASH_REMATCH[1]}" \
		'the focused config suite should use the supported btop version'
}

parse_btop_config() {
	local source=$1 values_name=$2
	local line key value
	local -n values=$values_name
	values=()

	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]]; then
			continue
		fi
		if [[ ! $line =~ ^[[:space:]]*([a-z][a-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
			printf '  unrecognized btop config line in %s: %q\n' "$source" "$line" >&2
			return 1
		fi
		key=${BASH_REMATCH[1]}
		value=${BASH_REMATCH[2]}
		while [[ $value == *[[:space:]] ]]; do
			value=${value%?}
		done
		if [[ ${values[$key]+present} ]]; then
			printf '  duplicate btop config key in %s: %s\n' "$source" "$key" >&2
			return 1
		fi
		values[$key]=$value
	done <"$source"
}

sorted_btop_keys() {
	local values_name=$1
	local -n values=$values_name
	printf '%s\n' "${!values[@]}" | LC_ALL=C sort
}

snapshot_btop_user_sentinels() {
	local path
	for path in \
		"$FIXTURE_HOME/.config/btop/sentinel" \
		"$FIXTURE_CONFIG/btop/sentinel" \
		"$FIXTURE_STATE/btop/sentinel" \
		"$FIXTURE_CACHE/btop/sentinel"; do
		printf '%s|' "$path"
		sha256sum "$path"
	done
}

test_installed_btop_version_matches_the_config_baseline() {
	new_fixture || return 1
	assert_btop_target_version
}

test_btop_catalog_and_stow_package_have_the_approved_boundary() {
	new_fixture || return 1
	local catalog=$FIXTURE_REPO/packages.json
	local package_root=$FIXTURE_REPO/config/btop
	local expected_tree actual_tree owners validators config_validator sensor_validator

	assert_eq '["bash","tmux","ghostty","starship","btop"]' \
		"$(jq -c '[.packages[].name]' "$catalog")" \
		'btop should be appended without changing existing wizard package numbers' || return 1
	assert_eq 1 "$(jq '[.packages[] | select(.name == "btop")] | length' "$catalog")" \
		'the catalog should declare btop exactly once' || return 1
	assert_eq config/btop "$(jq -r '.packages[] | select(.name == "btop") | .path' "$catalog")" \
		'btop should use its independent Stow package directory' || return 1
	assert_eq '["btop"]' "$(jq -c '.packages[] | select(.name == "btop") | .arch_packages' "$catalog")" \
		'btop should declare exactly its official Arch package' || return 1
	assert_eq '[]' "$(jq -c '.packages[] | select(.name == "btop") | .dependencies' "$catalog")" \
		'btop should have no Stow dependencies' || return 1
	assert_eq '[]' "$(jq -c '.packages[] | select(.name == "btop") | .prerequisites' "$catalog")" \
		'btop should have no command prerequisites' || return 1
	assert_eq docs/btop.md "$(jq -r '.packages[] | select(.name == "btop") | .documentation' "$catalog")" \
		'btop should reference its package guide' || return 1
	validators=$(jq -c '.packages[] | select(.name == "btop") | .validators' "$catalog")
	assert_eq 2 "$(jq 'length' <<<"$validators")" \
		'btop should declare separate config and machine-sensor validators' || return 1
	config_validator=$(jq -r '.[0]' <<<"$validators")
	sensor_validator=$(jq -r '.[1]' <<<"$validators")
	assert_eq bash "${config_validator%% *}" \
		'the btop config validator should be shell-fronted for package preflight' || return 1
	assert_contains "$config_validator" 'config=$HOME/.config/btop/btop.conf' \
		'the config validator should inspect the active Stow target' || return 1
	assert_contains "$config_validator" 'cpu_sensor = \"thermal1/acpitz\"' \
		'the config validator should retain the selected sensor setting' || return 1
	assert_eq bash "${sensor_validator%% *}" \
		'the btop sensor validator should be shell-fronted for package preflight' || return 1
	assert_contains "$sensor_validator" 'zone=/sys/class/thermal/thermal_zone1' \
		'the sensor validator should inspect only the selected thermal zone' || return 1
	assert_contains "$sensor_validator" 'for file in device/path type temp' \
		'the sensor validator should require identity, type, and numeric temperature inputs' || return 1
	assert_contains "$sensor_validator" '[[ $identity == "\\_TZ_.THRM" ]]' \
		'the sensor validator should require the selected ACPI THRM identity' || return 1
	assert_contains "$sensor_validator" '[[ $type == acpitz ]]' \
		'the sensor validator should require the selected acpitz type' || return 1
	assert_contains "$sensor_validator" '[[ $temp =~ ^-?[0-9]+$ ]]' \
		'the sensor validator should reject a nonnumeric temperature without testing live hardware' || return 1
	expected_tree=$'.config/btop/btop.conf|f\n.config/btop|d\n.config|d'
	actual_tree=$(cd -- "$package_root" && find . -mindepth 1 -printf '%P|%y\n' | LC_ALL=C sort)
	assert_eq "$expected_tree" "$actual_tree" \
		'the btop package should own only its complete config leaf and parent directories' || return 1
	owners=$(cd -- "$FIXTURE_REPO/config" && find . -path '*/.config/btop' -printf '%P|%y\n' | LC_ALL=C sort)
	assert_eq 'btop/.config/btop|d' "$owners" \
		'no other Stow package should overlap the btop config directory' || return 1
	if [[ ! -f $FIXTURE_REPO/docs/btop.md || -L $FIXTURE_REPO/docs/btop.md ]]; then
		printf '  btop package documentation should be a regular file: %s\n' "$FIXTURE_REPO/docs/btop.md" >&2
		return 1
	fi
}

test_tracked_btop_config_matches_147_defaults_except_approved_values() {
	new_fixture || return 1
	assert_btop_target_version || return 1

	local tracked_source=$FIXTURE_REPO/$BTOP_CONFIG_RELATIVE
	local default_source=$FIXTURE_ROOT/btop-1.4.7-default.conf
	local header before_sentinels key
	local -A defaults=() tracked=()
	mkdir -p \
		"$FIXTURE_HOME/.config/btop" \
		"$FIXTURE_CONFIG/btop" \
		"$FIXTURE_STATE/btop" \
		"$FIXTURE_CACHE/btop" || return 1
	printf 'home config sentinel\n' >"$FIXTURE_HOME/.config/btop/sentinel" || return 1
	printf 'XDG config sentinel\n' >"$FIXTURE_CONFIG/btop/sentinel" || return 1
	printf 'state sentinel\n' >"$FIXTURE_STATE/btop/sentinel" || return 1
	printf 'cache sentinel\n' >"$FIXTURE_CACHE/btop/sentinel" || return 1
	before_sentinels=$(snapshot_btop_user_sentinels) || return 1
	BWRAP_EXTRA_ARGS+=(--tmpfs /sys)

	run_in_sandbox "$FIXTURE_ROOT" /usr/bin:/bin /usr/bin/btop --default-config
	assert_eq 0 "$COMMAND_STATUS" 'btop should expose its compiled defaults read-only' || return 1
	assert_eq "$before_sentinels" "$(snapshot_btop_user_sentinels)" \
		'printing compiled defaults should not mutate isolated btop user sentinel files' || return 1
	printf '%s\n' "$COMMAND_OUTPUT" >"$default_source" || return 1

	if [[ ! -f $tracked_source || -L $tracked_source ]]; then
		printf '  tracked btop config should be a regular file: %s\n' "$tracked_source" >&2
		return 1
	fi
	IFS= read -r header <"$tracked_source" || return 1
	assert_eq '#? Config file for btop v.1.4.7' "$header" \
		'the complete tracked config should identify its btop baseline' || return 1

	parse_btop_config "$default_source" defaults || return 1
	parse_btop_config "$tracked_source" tracked || return 1
	assert_eq "$BTOP_EXPECTED_KEY_COUNT" "${#defaults[@]}" \
		'btop 1.4.7 compiled defaults should expose the expected recognized key count' || return 1
	assert_eq "$BTOP_EXPECTED_KEY_COUNT" "${#tracked[@]}" \
		'the tracked full replacement should contain every recognized key exactly once' || return 1
	assert_eq "$(sorted_btop_keys defaults)" "$(sorted_btop_keys tracked)" \
		'the tracked config should contain only and all btop 1.4.7 recognized keys' || return 1

	for key in "${!defaults[@]}"; do
		case $key in
			color_theme)
				assert_eq '"Default"' "${defaults[$key]}" \
					'the compiled color theme baseline should remain explicit' || return 1
				assert_eq '"current"' "${tracked[$key]}" \
					'the tracked config should preserve the Omarchy current-theme integration' || return 1
				;;
			vim_keys)
				assert_eq false "${defaults[$key]}" \
					'the compiled Vim-key baseline should remain explicit' || return 1
				assert_eq true "${tracked[$key]}" \
					'the tracked config should preserve the Omarchy Vim-key setting' || return 1
				;;
			cpu_sensor)
				assert_eq '"Auto"' "${defaults[$key]}" \
					'the compiled CPU sensor baseline should remain explicit' || return 1
				assert_eq '"thermal1/acpitz"' "${tracked[$key]}" \
					'the tracked config should select the approved CPU sensor' || return 1
				;;
			shown_gpus)
				assert_eq '"nvidia amd intel apple"' "${defaults[$key]}" \
					'the compiled GPU vendor baseline should remain explicit' || return 1
				assert_eq '"nvidia amd intel"' "${tracked[$key]}" \
					'the tracked config should preserve the Omarchy GPU vendor setting' || return 1
				;;
			*)
				assert_eq "${defaults[$key]}" "${tracked[$key]}" \
					"btop key $key should match the 1.4.7 compiled default" || return 1
				;;
		esac
	done
	assert_eq '"cpu mem net proc"' "${tracked[shown_boxes]}" \
		'the tracked config should show all four approved boxes' || return 1
	assert_eq true "${tracked[save_config_on_exit]}" \
		'the tracked config should save settings on clean exit'
}

set -e
run_test test_installed_btop_version_matches_the_config_baseline \
	'installed btop version matches the config baseline'
run_test test_btop_catalog_and_stow_package_have_the_approved_boundary \
	'btop catalog and Stow package have the approved boundary'
run_test test_tracked_btop_config_matches_147_defaults_except_approved_values \
	'tracked btop config matches 1.4.7 defaults except approved values'
finish_tests
