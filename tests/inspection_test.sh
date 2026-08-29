#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

configure_brave_structural_canaries() {
	make_fake pacman 'printf "unexpected pacman call\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
	make_fake brave 'printf "unexpected brave call\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
	make_fake brave-origin 'printf "unexpected brave-origin call\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
	make_fake sudo 'printf "unexpected sudo call\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
}

stub_wallpaper_library_validator() {
	local outcome=${1-0}
	printf '\nvalidate_wallpaper_library() { printf "Stub Wallpaper library validation\\n"; if ((%s == 0)); then printf "Wallpaper library: valid\\n"; fi; return %s; }\n' \
		"$outcome" \
		"$outcome" >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh"
}

test_status_inspects_empty_relocated_clone() {
	new_fixture
	use_empty_package_catalog
	rm "$FIXTURE_BIN/stow"
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) run_operation "$FIXTURE_ROOT" status

	assert_eq 0 "$COMMAND_STATUS" 'status should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'status should report the supported major version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'status should report the detected version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'status should describe the empty catalog' || return 1

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq "version|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" "$calls" \
		'only the fake Omarchy command should observe the isolated user roots'
}

test_check_accepts_empty_catalog() {
	new_fixture
	use_empty_package_catalog
	rm "$FIXTURE_BIN/stow"
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) run_operation "$FIXTURE_HOME" check

	assert_eq 0 "$COMMAND_STATUS" 'check should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'check should report the supported major version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'check should report the detected version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid (0 packages)' 'check should accept the empty catalog' || return 1
	assert_contains "$COMMAND_OUTPUT" 'GNU Stow: unavailable (nonfatal until a package operation is selected)' \
		'check should report missing Stow without rejecting an empty catalog' || return 1

	local calls
	calls=$(<"$CALL_LOG")
	assert_eq "version|HOME=$FIXTURE_HOME|XDG_CONFIG_HOME=$FIXTURE_CONFIG|XDG_STATE_HOME=$FIXTURE_STATE|XDG_CACHE_HOME=$FIXTURE_CACHE" "$calls" \
		'check should use only the fake Omarchy command under isolated roots'
}

test_check_reports_imagemagick_and_validates_wallpaper_library() {
	new_fixture
	use_empty_package_catalog
	stub_wallpaper_library_validator
	local before_paths
	before_paths=$(snapshot_isolated_paths)

	run_operation "$FIXTURE_ROOT" check

	assert_eq 0 "$COMMAND_STATUS" 'a valid Wallpaper library should pass structural checks' || return 1
	assert_contains "$COMMAND_OUTPUT" 'ImageMagick: available (magick)' \
		'check should explicitly report the Wallpaper image prerequisite' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub Wallpaper library validation' \
		'check should invoke the focused Wallpaper library validator' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Wallpaper library: valid' \
		'check should report successful Wallpaper library validation' || return 1
	assert_eq 1 "$(awk '/^Stub Wallpaper library validation$/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'check should invoke Wallpaper library validation once' || return 1
	assert_eq "$before_paths" "$(snapshot_isolated_paths)" \
		'Wallpaper structural validation should not mutate isolated user paths'
}

test_check_rejects_missing_imagemagick_without_running_wallpaper_validator() {
	new_fixture
	use_empty_package_catalog
	stub_wallpaper_library_validator
	rm -f -- "$FIXTURE_BIN/magick"
	local check_path
	check_path=$(restricted_path_without_stow)

	DOTFILES_TEST_PATH=$check_path run_operation "$FIXTURE_ROOT" check

	assert_eq 1 "$COMMAND_STATUS" 'missing ImageMagick should fail structural checks' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: missing Wallpaper prerequisite: ImageMagick command magick' \
		'check should explicitly identify the missing Wallpaper prerequisite' || return 1
	if [[ $COMMAND_OUTPUT == *'Stub Wallpaper library validation'* || $COMMAND_OUTPUT == *'Wallpaper library: valid'* ]]; then
		printf '  check invoked or accepted Wallpaper validation without ImageMagick\n' >&2
		return 1
	fi
}

test_wallpaper_inbox_is_ignored_without_ignoring_library() {
	if ! git -C "$SOURCE_REPO" check-ignore --no-index --quiet -- wallpapers/inbox/candidate.png; then
		printf '  Wallpaper inbox candidates should be ignored\n' >&2
		return 1
	fi
	if [[ ! -f $SOURCE_REPO/wallpapers/inbox/.gitkeep ]]; then
		printf '  Wallpaper inbox should be retained by .gitkeep\n' >&2
		return 1
	fi
	if git -C "$SOURCE_REPO" check-ignore --no-index --quiet -- wallpapers/inbox/.gitkeep; then
		printf '  Wallpaper inbox .gitkeep should remain trackable\n' >&2
		return 1
	fi
	if git -C "$SOURCE_REPO" check-ignore --no-index --quiet -- wallpapers/library/theme/managed.png; then
		printf '  Wallpaper library assignments should remain trackable\n' >&2
		return 1
	fi
}

test_check_rejects_invalid_wallpaper_library_without_mutation() {
	new_fixture
	use_empty_package_catalog
	setup_wallpaper_fixture
	mkdir "$FIXTURE_REPO/wallpapers/library/.unsafe"
	local before
	before=$(snapshot_isolated_paths)

	run_dotfiles "$FIXTURE_ROOT" --action check

	assert_eq 1 "$COMMAND_STATUS" 'an invalid Wallpaper library should fail structural checks' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: invalid Wallpaper library: unsafe theme slug: .unsafe' \
		'check should preserve the focused Wallpaper library rejection reason' || return 1
	if [[ $COMMAND_OUTPUT == *'Wallpaper library: valid'* ]]; then
		printf '  check reported an invalid Wallpaper library as valid\n' >&2
		return 1
	fi
	assert_eq "$before" "$(snapshot_isolated_paths)" \
		'rejected Wallpaper library validation should not mutate isolated user paths'
}

test_check_validates_brave_source_without_browser_or_deployment() {
	new_fixture
	use_empty_package_catalog
	configure_brave_structural_canaries
	rm "$FIXTURE_BIN/stow"
	BWRAP_EXTRA_ARGS+=(--tmpfs /etc)
	local source=$FIXTURE_REPO/brave/managed-policy.json
	local before_source before_paths
	before_source=$(sha256sum "$source")
	before_paths=$(snapshot_isolated_paths)

	DOTFILES_TEST_PATH=$(restricted_path_without_stow) run_operation "$FIXTURE_ROOT" check

	assert_eq 0 "$COMMAND_STATUS" 'canonical Brave source should pass structural checks' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Brave policy source: valid' \
		'structural checks should report canonical Brave source validation' || return 1
	assert_eq "$before_source" "$(sha256sum "$source")" 'Brave source validation should not rewrite its input' || return 1
	assert_eq "$before_paths" "$(snapshot_isolated_paths)" \
		'Brave source validation should not mutate user or Omarchy fixture paths' || return 1
	if [[ $(<"$CALL_LOG") == *'unexpected '* ]]; then
		printf '  structural Brave validation inspected a browser, package provider, or privilege command\n' >&2
		return 1
	fi
}

test_check_rejects_noncanonical_brave_source_without_browser_or_deployment() {
	new_fixture
	use_empty_package_catalog
	configure_brave_structural_canaries
	rm "$FIXTURE_BIN/stow"
	BWRAP_EXTRA_ARGS+=(--tmpfs /etc)
	local source=$FIXTURE_REPO/brave/managed-policy.json
	jq '.ShowHomeButton = true' "$source" >"$source.invalid"
	mv "$source.invalid" "$source"
	local before_source
	before_source=$(sha256sum "$source")

	DOTFILES_TEST_PATH=$(restricted_path_without_stow) run_operation "$FIXTURE_ROOT" check

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  structural checks accepted a changed canonical Brave value\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Error: invalid Brave policy source:' \
		'structural checks should report why the canonical Brave source was rejected' || return 1
	if [[ $COMMAND_OUTPUT == *'Brave policy source: valid'* ]]; then
		printf '  structural checks reported a rejected Brave source as valid\n' >&2
		return 1
	fi
	assert_eq "$before_source" "$(sha256sum "$source")" 'rejected Brave source validation should not rewrite its input' || return 1
	if [[ $(<"$CALL_LOG") == *'unexpected '* ]]; then
		printf '  rejected Brave source validation inspected a browser, package provider, or privilege command\n' >&2
		return 1
	fi
}

test_check_propagates_brave_failure_from_conditional_context() {
	new_fixture
	use_empty_package_catalog
	configure_brave_structural_canaries
	rm "$FIXTURE_BIN/stow"
	BWRAP_EXTRA_ARGS+=(--tmpfs /etc)
	local source=$FIXTURE_REPO/brave/managed-policy.json
	jq '.ShowHomeButton = true' "$source" >"$source.invalid"
	mv "$source.invalid" "$source"
	printf '%s\n' \
		'' \
		'check_from_errexit_disabled_context() {' \
		'  local outcome' \
		'  if check; then' \
		'    outcome=0' \
		'  else' \
		'    outcome=$?' \
		'  fi' \
		'  return "$outcome"' \
		'}' >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh"

	DOTFILES_TEST_PATH=$(restricted_path_without_stow) run_operation "$FIXTURE_ROOT" check_from_errexit_disabled_context

	assert_eq 1 "$COMMAND_STATUS" 'check should propagate Brave validation failure from an if condition' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: invalid Brave policy source:' \
		'the conditional check should report the rejected Brave source' || return 1
	assert_contains "$COMMAND_OUTPUT" 'GNU Stow: unavailable (nonfatal until a package operation is selected)' \
		'the conditional check should continue useful diagnostics after Brave validation fails' || return 1
}

test_brave_focused_suite_is_registered_once() {
	new_fixture
	if [[ ! -f $SOURCE_REPO/tests/brave_test.sh ]]; then
		printf '  registered focused Brave suite is missing: %s\n' "$SOURCE_REPO/tests/brave_test.sh" >&2
		return 1
	fi
	local registrations
	registrations=$(awk '$1 == "brave_test.sh" { count++ } END { print count + 0 }' "$SOURCE_REPO/tests/run.sh")
	assert_eq 1 "$registrations" 'the focused Brave suite should be registered exactly once'
}

test_check_rejects_missing_declared_package_prerequisite() {
	new_fixture
	add_package
	rm "$FIXTURE_BIN/test-validator"
	run_operation "$FIXTURE_ROOT" check

	assert_eq 1 "$COMMAND_STATUS" 'check should fail when a declared package prerequisite is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing package prerequisite for demo: test-validator' \
		'check should identify the package and unavailable command' || return 1
}

test_check_rejects_missing_validator_executable() {
	new_fixture
	add_package
	jq '.packages[0].validators = ["missing-validator --check"]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
	run_operation "$FIXTURE_ROOT" check

	assert_eq 1 "$COMMAND_STATUS" 'check should fail when a validator executable is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing validator executable for demo: missing-validator --check' \
		'check should identify the package and complete validator command' || return 1
	if [[ $(<"$CALL_LOG") == *'missing-validator'* ]]; then
		printf '  structural check must not execute validator commands\n' >&2
		return 1
	fi
}

test_check_rejects_missing_core_and_global_skill_commands() {
	new_fixture
	local check_bin=$FIXTURE_ROOT/check-bin command
	mkdir -p "$check_bin"
	for command in bash dirname jq find git diff; do
		ln -s "$(command -v "$command")" "$check_bin/$command"
	done
	ln -s "$FIXTURE_BIN/node" "$check_bin/node"
	ln -s "$FIXTURE_BIN/omarchy" "$check_bin/omarchy"

	DOTFILES_TEST_PATH=$check_bin run_operation "$FIXTURE_ROOT" check
	assert_eq 1 "$COMMAND_STATUS" 'check should fail before inspection when a core command is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: missing core inspection command: readlink' \
		'check should identify the missing core command' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'missing core commands should stop before Omarchy inspection' || return 1

	ln -s "$(command -v readlink)" "$check_bin/readlink"
	DOTFILES_TEST_PATH=$check_bin run_operation "$FIXTURE_ROOT" check
	assert_eq 1 "$COMMAND_STATUS" 'check should fail when a global-skill prerequisite is unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: missing global skill prerequisite: npx' \
		'check should identify the missing global-skill command'
}

test_status_warns_about_version_mismatch_without_mutation() {
	new_fixture
	mkdir -p "$FIXTURE_HOME/.agents/skills" "$FIXTURE_CONFIG/omarchy"
	printf 'user config\n' >"$FIXTURE_CONFIG/omarchy/sentinel"
	printf 'global skill\n' >"$FIXTURE_HOME/.agents/skills/sentinel"
	printf 'state\n' >"$FIXTURE_STATE/sentinel"
	printf 'cache\n' >"$FIXTURE_CACHE/sentinel"
	printf 'packaged config\n' >"$FIXTURE_OMARCHY/sentinel"
	local before
	before=$(snapshot_isolated_paths)

	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 run_operation "$FIXTURE_CONFIG" status

	assert_eq 0 "$COMMAND_STATUS" 'a mismatch should not fail inspection' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'status should preserve the detected version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: detected Omarchy does not match supported version 4' \
		'status should make the mismatch explicit' || return 1
	assert_eq "$before" "$(snapshot_isolated_paths)" \
		'inspection should not mutate user config, global skills, state, cache, or packaged Omarchy fixtures'
}

test_check_rejects_malformed_catalog_without_mutation() {
	new_fixture
	mkdir -p "$FIXTURE_HOME/.agents/skills" "$FIXTURE_CONFIG/omarchy"
	printf 'user config\n' >"$FIXTURE_CONFIG/omarchy/sentinel"
	printf 'global skill\n' >"$FIXTURE_HOME/.agents/skills/sentinel"
	printf 'state\n' >"$FIXTURE_STATE/sentinel"
	printf 'cache\n' >"$FIXTURE_CACHE/sentinel"
	printf 'packaged config\n' >"$FIXTURE_OMARCHY/sentinel"
	printf '{"packages": [}\n' >"$FIXTURE_REPO/packages.json"
	local before_paths before_catalog
	before_paths=$(snapshot_isolated_paths)
	before_catalog=$(sha256sum "$FIXTURE_REPO/packages.json")

	run_operation "$FIXTURE_ROOT" check

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  malformed catalog should fail check\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" "Error: invalid package catalog: $FIXTURE_REPO/packages.json" \
		'check should identify the rejected catalog' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'catalog rejection should happen before external commands run' || return 1
	assert_eq "$before_catalog" "$(sha256sum "$FIXTURE_REPO/packages.json")" \
		'check should not rewrite a malformed catalog' || return 1
	assert_eq "$before_paths" "$(snapshot_isolated_paths)" \
		'catalog rejection should not mutate isolated user or Omarchy paths'
}

test_status_reports_nonempty_package_states_and_metadata() {
	new_fixture
	add_package linked
	add_dependent_package absent linked
	add_dependent_package invalid linked
	add_dependent_package conflicting linked
	mkdir -p "$FIXTURE_HOME/.config"
	ln -s "$FIXTURE_REPO/config/linked/.config/linked" "$FIXTURE_HOME/.config/linked"
	mkdir -p "$FIXTURE_HOME/.config/invalid"
	ln -s /tmp/not-the-package "$FIXTURE_HOME/.config/invalid/config"
	mkdir -p "$FIXTURE_HOME/.config/conflicting"
	printf 'keep me\n' >"$FIXTURE_HOME/.config/conflicting/config"

	run_operation "$FIXTURE_ROOT" status

	assert_eq 0 "$COMMAND_STATUS" 'status should inspect a nonempty catalog' || return 1
	assert_contains "$COMMAND_OUTPUT" 'linked: linked - Test package' 'status should report a fully linked package and description' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Documentation: linked.md' 'status should report package documentation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'absent: absent - Dependent test package' 'status should report an absent package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'invalid: invalid - Dependent test package' 'status should report an incorrect symbolic link as invalid' || return 1
	assert_contains "$COMMAND_OUTPUT" 'conflicting: conflicting - Dependent test package' 'status should report a normal target conflict' || return 1
}

test_inspection_cannot_access_real_user_or_omarchy_paths() {
	new_fixture
	use_empty_package_catalog
	run_dotfiles_without_real_user_or_omarchy_paths

	assert_eq 0 "$COMMAND_STATUS" 'check should work with real user and Omarchy paths masked' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid (0 packages)' \
		'check should depend only on the temporary clone and fake commands'
}

test_check_validates_complete_package_metadata() {
	new_fixture
	add_package
	run_operation "$FIXTURE_ROOT" check

	assert_eq 0 "$COMMAND_STATUS" 'complete package metadata should pass check' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid (1 packages)' \
		'check should count the validated package'
}

test_catalog_declares_package_specific_arch_requirements() {
	new_fixture

	assert_eq 'Complete Omarchy-based tmux configuration and private session starter' \
		"$(jq -r '.packages[] | select(.name == "tmux") | .description' "$FIXTURE_REPO/packages.json")" \
		'tmux should describe both owned targets' || return 1
	assert_eq '["thefuck"]' "$(jq -c '.packages[] | select(.name == "bash") | .arch_packages' "$FIXTURE_REPO/packages.json")" \
		'Bash should declare exactly its required Arch package' || return 1
	assert_eq '["tmux"]' "$(jq -c '.packages[] | select(.name == "bash") | .dependencies' "$FIXTURE_REPO/packages.json")" \
		'Bash should declare the tmux Stow package dependency' || return 1
	assert_eq '["tmux","fzf","less"]' "$(jq -c '.packages[] | select(.name == "tmux") | .arch_packages' "$FIXTURE_REPO/packages.json")" \
		'tmux should declare exactly its official Arch requirements' || return 1
	assert_eq '[]' "$(jq -c '.packages[] | select(.name == "tmux") | .dependencies' "$FIXTURE_REPO/packages.json")" \
		'tmux should have no Stow dependencies' || return 1
	assert_eq '[]' "$(jq -c '.packages[] | select(.name == "tmux") | .prerequisites' "$FIXTURE_REPO/packages.json")" \
		'tmux should have no command prerequisites' || return 1
	assert_eq 'docs/tmux.md' "$(jq -r '.packages[] | select(.name == "tmux") | .documentation' "$FIXTURE_REPO/packages.json")" \
		'tmux should reference its package guide' || return 1
	assert_eq '[]' "$(jq -c '.packages[] | select(.name == "ghostty") | .arch_packages' "$FIXTURE_REPO/packages.json")" \
		'Ghostty should declare no Arch packages' || return 1
	assert_eq 'Complete Omarchy-based Starship prompt configuration' \
		"$(jq -r '.packages[] | select(.name == "starship") | .description' "$FIXTURE_REPO/packages.json")" \
		'Starship should describe its complete prompt configuration' || return 1
	assert_eq 'config/starship' "$(jq -r '.packages[] | select(.name == "starship") | .path' "$FIXTURE_REPO/packages.json")" \
		'Starship should use its independent package directory' || return 1
	assert_eq '[]' "$(jq -c '.packages[] | select(.name == "starship") | .dependencies' "$FIXTURE_REPO/packages.json")" \
		'Starship should have no Stow dependencies' || return 1
	assert_eq '["starship"]' "$(jq -c '.packages[] | select(.name == "starship") | .arch_packages' "$FIXTURE_REPO/packages.json")" \
		'Starship should declare exactly its official Arch package' || return 1
	assert_eq '[]' "$(jq -c '.packages[] | select(.name == "starship") | .prerequisites' "$FIXTURE_REPO/packages.json")" \
		'Starship should have no command prerequisites' || return 1
	assert_eq 'docs/starship.md' "$(jq -r '.packages[] | select(.name == "starship") | .documentation' "$FIXTURE_REPO/packages.json")" \
		'Starship should reference its package guide' || return 1
	assert_eq '["bash","starship"]' \
		"$(jq -c '[.packages[] | select(.name == "bash" or .name == "starship") | .name]' "$FIXTURE_REPO/packages.json")" \
		'Bash and Starship should remain separate catalog selections' || return 1
	if grep -q 'STARSHIP_CONFIG' "$FIXTURE_REPO/config/bash/.bashrc"; then
		printf '  Bash configuration must not set STARSHIP_CONFIG\n' >&2
		return 1
	fi
	assert_contains "$(jq -r '.packages[] | select(.name == "bash") | .cleanup[]' "$FIXTURE_REPO/packages.json")" \
		'thefuck remains installed' 'Bash cleanup should disclose retained Arch package state' || return 1
	local tmux_cleanup
	tmux_cleanup=$(jq -r '.packages[] | select(.name == "tmux") | .cleanup[]' "$FIXTURE_REPO/packages.json")
	assert_contains "$tmux_cleanup" 'Arch packages tmux, fzf, and less remain installed' \
		'tmux cleanup should disclose every retained Arch package' || return 1
	assert_contains "$tmux_cleanup" 'server, sessions, panes, logs, and other runtime state are not removed' \
		'tmux cleanup should disclose all retained runtime state' || return 1
	assert_contains "$tmux_cleanup" 'omarchy refresh tmux' \
		'tmux cleanup should report the explicit Omarchy baseline restoration command' || return 1
	assert_contains "$tmux_cleanup" 'restore the Omarchy baseline' \
		'tmux cleanup should explain the restoration command' || return 1
	assert_eq '["Removing this package leaves ~/.config/starship.toml absent","Arch package starship remains installed","Starship cache and state are not removed","Migration backups remain under the Dotfiles XDG state backup tree","Optional post-removal baseline restoration command (reported only, not run): omarchy refresh config starship.toml"]' \
		"$(jq -c '.packages[] | select(.name == "starship") | .cleanup' "$FIXTURE_REPO/packages.json")" \
		'Starship cleanup should disclose every retained item and report-only restoration command'
}

test_catalog_declares_strict_isolated_starship_validation() {
	new_fixture
	local validators config_validator
	validators=$(jq -c '.packages[] | select(.name == "starship") | .validators' "$FIXTURE_REPO/packages.json")

	assert_eq 1 "$(jq 'length' <<<"$validators")" \
		'Starship should have one config validator' || return 1
	config_validator=$(jq -r '.[0]' <<<"$validators")
	assert_eq bash "${config_validator%% *}" \
		'the Starship validator should be shell-fronted for pre-installation preflight' || return 1
	assert_contains "$config_validator" 'mktemp -d "${TMPDIR:-/tmp}/dotfiles-starship-validator.XXXXXX"' \
		'the Starship validator should allocate a fresh work directory' || return 1
	assert_contains "$config_validator" 'export STARSHIP_CONFIG=$HOME/.config/starship.toml' \
		'the Starship validator should inspect the active linked config' || return 1
	assert_contains "$config_validator" 'export STARSHIP_CACHE=$work/cache' \
		'the Starship validator should use an isolated cache' || return 1
	assert_contains "$config_validator" 'export STARSHIP_SESSION_KEY=dotfiles-starship-validation' \
		'the Starship validator should use the fixed validation session key' || return 1
	assert_contains "$config_validator" 'if ! starship print-config >/dev/null 2>"$diagnostics"' \
		'the Starship validator should fail a nonzero print-config command' || return 1
	assert_contains "$config_validator" 'if [[ -s $diagnostics ]]' \
		'the Starship validator should reject any stderr byte' || return 1
	assert_contains "$config_validator" 'trap cleanup EXIT' \
		'the Starship validator should clean up on shell exit' || return 1
	assert_contains "$config_validator" 'rm -rf -- "$work"' \
		'the Starship validator should remove its isolated work directory'
}

test_catalog_declares_isolated_tmux_config_validation() {
	new_fixture
	local validators config_validator validator_without_isolated_tmux
	validators=$(jq -c '.packages[] | select(.name == "tmux") | .validators' "$FIXTURE_REPO/packages.json")

	assert_eq 3 "$(jq 'length' <<<"$validators")" \
		'tmux should retain both starter checks and add one complete-config validator' || return 1
	assert_eq 'sh -n "$HOME/.local/libexec/dotfiles/tmux-starter"' "$(jq -r '.[0]' <<<"$validators")" \
		'tmux should retain starter syntax validation' || return 1
	assert_eq 'sh -c '\''test -x "$HOME/.local/libexec/dotfiles/tmux-starter"'\''' "$(jq -r '.[1]' <<<"$validators")" \
		'tmux should retain starter executable validation' || return 1

	config_validator=$(jq -r '.[2]' <<<"$validators")
	assert_eq bash "${config_validator%% *}" \
		'the config validator should remain preflight-safe before tmux is installed' || return 1
	assert_contains "$config_validator" 'mktemp -d' \
		'the config validator should allocate a unique socket directory' || return 1
	assert_contains "$config_validator" 'trap cleanup EXIT' \
		'the config validator should always clean up on shell exit' || return 1
	assert_contains "$config_validator" 'tmux -S "$socket" -f /dev/null new-session -d -s dotfiles-validator \; source-file "$HOME/.config/tmux/tmux.conf"' \
		'the config validator should explicitly source the linked complete config through its isolated socket' || return 1
	assert_contains "$config_validator" 'tmux -S "$socket" kill-server' \
		'the config validator should stop only its isolated server' || return 1
	assert_contains "$config_validator" 'rm -rf -- "$socket_dir"' \
		'the config validator should remove its isolated socket directory' || return 1
	validator_without_isolated_tmux=${config_validator//'tmux -S "$socket"'/}
	if [[ $validator_without_isolated_tmux == *'tmux '* ]]; then
		printf '  every tmux validator invocation must name the isolated socket\n' >&2
		return 1
	fi
}

test_check_accepts_tmux_validator_before_tmux_is_installed() {
	new_fixture
	ln -s "$(command -v sh)" "$FIXTURE_BIN/sh"
	make_fake ghostty 'exit 0'
	local command_path
	command_path=$(restricted_path_without_stow)
	if PATH=$command_path command -v tmux >/dev/null 2>&1; then
		printf '  tmux must be absent from the structural-check PATH for this preflight test\n' >&2
		return 1
	fi

	DOTFILES_TEST_PATH=$command_path run_operation "$FIXTURE_ROOT" check

	assert_eq 0 "$COMMAND_STATUS" \
		'check should accept the shell-fronted tmux validator before its declared Arch package is installed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid (7 packages)' \
		'preflight should still inspect the complete real catalog'
}

test_check_accepts_starship_validator_before_starship_is_installed() {
	new_fixture
	ln -s "$(command -v sh)" "$FIXTURE_BIN/sh"
	make_fake ghostty 'exit 0'
	set_installed_arch_packages thefuck tmux fzf less btop
	local command_path
	command_path=$(restricted_path_without_stow)
	if PATH=$command_path command -v starship >/dev/null 2>&1; then
		printf '  Starship must be absent from the structural-check PATH for this preflight test\n' >&2
		return 1
	fi

	DOTFILES_TEST_PATH=$command_path run_operation "$FIXTURE_ROOT" check

	assert_eq 1 "$COMMAND_STATUS" \
		'the missing declared Arch package should remain the only Starship pre-installation blocker' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing declared Arch package for starship: starship' \
		'preflight should report the not-yet-installed Arch package' || return 1
	if [[ $COMMAND_OUTPUT == *'Missing validator executable for starship:'* ]]; then
		printf '  the shell-fronted validator must pass executable preflight before Starship is installed\n' >&2
		return 1
	fi
}

test_check_rejects_invalid_arch_package_metadata() {
	local jq_filter
	while IFS= read -r jq_filter; do
		new_fixture
		add_package
		jq "$jq_filter" "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.invalid"
		mv "$FIXTURE_REPO/packages.invalid" "$FIXTURE_REPO/packages.json"
		run_operation "$FIXTURE_ROOT" check
		if [[ $COMMAND_STATUS -eq 0 || $COMMAND_OUTPUT != *'invalid Arch packages for package demo'* ]]; then
			printf '  invalid Arch package metadata was accepted: %s\n  output: %s\n' "$jq_filter" "$COMMAND_OUTPUT" >&2
			return 1
		fi
		rm -rf "$FIXTURE_ROOT"
	done <<'EOF'
del(.packages[0].arch_packages)
.packages[0].arch_packages = "demo-runtime"
.packages[0].arch_packages = ["Not-Lower"]
.packages[0].arch_packages = ["bad/name"]
.packages[0].arch_packages = ["demo-runtime", "demo-runtime"]
EOF
}

test_check_reports_missing_declared_arch_package_without_mutation() {
	new_fixture
	add_package
	set_package_arch_packages demo demo-runtime
	set_installed_arch_packages
	run_operation "$FIXTURE_ROOT" check

	assert_eq 1 "$COMMAND_STATUS" 'check should fail when a declared Arch package is missing' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Missing declared Arch package for demo: demo-runtime' \
		'check should identify the owner and missing Arch package' || return 1
	assert_eq '' "$(<"$ARCH_PACKAGE_STATE")" 'check should not install a missing Arch package' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg add'* ]]; then
		printf '  structural check must not call the Arch package installer\n' >&2
		return 1
	fi
}

test_check_rejects_each_invalid_package_metadata_field() {
	local jq_filter expected
	while IFS='|' read -r jq_filter expected; do
		new_fixture
		add_package
		jq "$jq_filter" "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.invalid"
		mv "$FIXTURE_REPO/packages.invalid" "$FIXTURE_REPO/packages.json"
		run_operation "$FIXTURE_ROOT" check
		if [[ $COMMAND_STATUS -eq 0 || $COMMAND_OUTPUT != *"$expected"* ]]; then
			printf '  invalid metadata was accepted: %s\n  output: %s\n' "$jq_filter" "$COMMAND_OUTPUT" >&2
			return 1
		fi
		rm -rf "$FIXTURE_ROOT"
	done <<'EOF'
.packages[0].name = "Not-Lower"|package name
.packages[0].path = "config/elsewhere"|package path
.packages[0].description = ""|description
del(.packages[0].dependencies)|dependencies
.packages[0].dependencies = [""]|dependencies
.packages[0].prerequisites = [""]|prerequisites
.packages[0].validators = [""]|validators
.packages[0].documentation = 42|documentation
.packages[0].documentation = "missing.md"|documentation
.packages[0].cleanup = [""]|cleanup
EOF
}

test_check_rejects_missing_dependency_and_cycle() {
	new_fixture
	add_package base
	mkdir -p "$FIXTURE_REPO/config/app"
	jq '.packages += [{
		"name": "app",
		"path": "config/app",
		"description": "Dependent package",
		"dependencies": ["missing"],
		"arch_packages": [],
		"prerequisites": [],
		"validators": [],
		"documentation": null,
		"cleanup": []
	}]' "$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"

	run_operation "$FIXTURE_ROOT" check
	assert_eq 1 "$COMMAND_STATUS" 'a missing dependency reference should fail check' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: package app depends on missing package: missing' \
		'missing dependency output should name both packages' || return 1

	jq '(.packages[] | select(.name == "app").dependencies) = ["base"] |
		(.packages[] | select(.name == "base").dependencies) = ["app"]' \
		"$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"
	run_operation "$FIXTURE_ROOT" check
	assert_eq 1 "$COMMAND_STATUS" 'a dependency cycle should fail check' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: package dependency cycle detected:' \
		'cycle output should explain the graph error' || return 1
	assert_contains "$COMMAND_OUTPUT" 'base' 'cycle output should name a cycle member' || return 1
	assert_contains "$COMMAND_OUTPUT" 'app' 'cycle output should name every cycle member' || return 1
}

set -e
run_test test_status_inspects_empty_relocated_clone 'status inspects an empty relocated clone'
run_test test_check_accepts_empty_catalog 'check accepts an empty package catalog'
run_test test_check_reports_imagemagick_and_validates_wallpaper_library 'check reports ImageMagick and validates the Wallpaper library'
run_test test_check_rejects_missing_imagemagick_without_running_wallpaper_validator 'check rejects missing ImageMagick without running the Wallpaper validator'
run_test test_wallpaper_inbox_is_ignored_without_ignoring_library 'Wallpaper inbox is ignored without ignoring the library'
run_test test_check_rejects_invalid_wallpaper_library_without_mutation 'check rejects an invalid Wallpaper library without mutation'
run_test test_check_validates_brave_source_without_browser_or_deployment 'check validates Brave source without a browser or deployment'
run_test test_check_rejects_noncanonical_brave_source_without_browser_or_deployment 'check rejects noncanonical Brave source without a browser or deployment'
run_test test_check_propagates_brave_failure_from_conditional_context 'check propagates Brave failure from an errexit-disabled conditional context'
run_test test_brave_focused_suite_is_registered_once 'focused Brave suite is registered once'
run_test test_check_rejects_missing_declared_package_prerequisite 'check rejects missing declared package prerequisite'
run_test test_check_rejects_missing_validator_executable 'check rejects missing validator executable'
run_test test_check_rejects_missing_core_and_global_skill_commands 'check rejects missing core and global skill commands'
run_test test_status_warns_about_version_mismatch_without_mutation 'status warns about mismatch without mutation'
run_test test_check_rejects_malformed_catalog_without_mutation 'check rejects malformed catalog without mutation'
run_test test_status_reports_nonempty_package_states_and_metadata 'status reports nonempty package states and metadata'
run_test test_inspection_cannot_access_real_user_or_omarchy_paths 'inspection cannot access real user or Omarchy paths'
run_test test_check_validates_complete_package_metadata 'check validates complete package metadata'
run_test test_catalog_declares_package_specific_arch_requirements 'catalog declares package-specific Arch requirements'
run_test test_catalog_declares_strict_isolated_starship_validation 'catalog declares strict isolated Starship validation'
run_test test_catalog_declares_isolated_tmux_config_validation 'catalog declares isolated tmux config validation'
run_test test_check_accepts_tmux_validator_before_tmux_is_installed 'check accepts the tmux validator before tmux is installed'
run_test test_check_accepts_starship_validator_before_starship_is_installed 'check accepts the Starship validator before Starship is installed'
run_test test_check_rejects_invalid_arch_package_metadata 'check rejects invalid Arch package metadata'
run_test test_check_reports_missing_declared_arch_package_without_mutation 'check reports a missing declared Arch package without mutation'
run_test test_check_rejects_each_invalid_package_metadata_field 'check rejects invalid package metadata fields'
run_test test_check_rejects_missing_dependency_and_cycle 'check rejects missing dependencies and cycles'
finish_tests
