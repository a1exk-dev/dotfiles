#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

configure_telegram_lifecycle_boundaries() {
	make_fake pacman 'printf "pacman %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
case "$*" in
  "-Q omarchy") printf "omarchy 4.0.1-1\n" ;;
  "-Q telegram-desktop") printf "telegram-desktop 7.0.9-4\n" ;;
  *) exit 64 ;;
esac'
	make_fake telegram-desktop 'printf "TELEGRAM EXECUTED: %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
	make_fake Telegram 'printf "TELEGRAM EXECUTED: %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
	mkdir -p "$FIXTURE_HOME/.local/share/TelegramDesktop/tdata"
	printf 'private Telegram state\n' >"$FIXTURE_HOME/.local/share/TelegramDesktop/tdata/canary"
	TELEGRAM_LIFECYCLE_TDATA=$(sha256sum "$FIXTURE_HOME/.local/share/TelegramDesktop/tdata/canary")
}

link_telegram_theme_fixture_package() {
	local source relative target
	FIXTURE_CONFIG="$FIXTURE_HOME/.config"
	mkdir -p "$FIXTURE_CONFIG"
	while IFS= read -r -d '' source; do
		relative=${source#"$FIXTURE_REPO/config/telegram-theme/"}
		target="$FIXTURE_HOME/$relative"
		mkdir -p "${target%/*}"
		ln -s "$source" "$target"
	done < <(find "$FIXTURE_REPO/config/telegram-theme" -type f -print0)
}

assert_lifecycle_did_not_control_telegram() {
	assert_eq "$TELEGRAM_LIFECYCLE_TDATA" "$(sha256sum "$FIXTURE_HOME/.local/share/TelegramDesktop/tdata/canary")" \
		'lifecycle operation must leave Telegram private state untouched' || return 1
	if [[ $(<"$CALL_LOG") == *'TELEGRAM EXECUTED:'* ]]; then
		printf '  lifecycle operation launched or controlled Telegram\n' >&2
		return 1
	fi
}

configure_telegram_setup_guard_probes() {
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
[[ ${1-} == confirm ]] && exit 0
exit 64'
}

assert_setup_rejected_before_confirmation_and_refresh() {
	local scenario=$1 expected_output=$2
	: >"$CALL_LOG"
	DOTFILES_UI=gum run_operation "$FIXTURE_ROOT" setup_telegram_theme
	assert_eq 1 "$COMMAND_STATUS" "$scenario should block Telegram theme setup" || return 1
	assert_contains "$COMMAND_OUTPUT" "$expected_output" "$scenario should report its failed setup boundary" || return 1
	if [[ $(<"$CALL_LOG") == *'gum confirm '* ]]; then
		printf '  %s reached setup confirmation\n' "$scenario" >&2
		return 1
	fi
	if [[ $(<"$CALL_LOG") == *'theme refresh'* ]]; then
		printf '  %s reached Omarchy theme refresh\n' "$scenario" >&2
		return 1
	fi
	assert_lifecycle_did_not_control_telegram
}

test_package_declares_owned_assets_requirements_and_cleanup() {
	new_fixture
	local package_root="$FIXTURE_REPO/config/telegram-theme"
	local template="$package_root/.config/omarchy/themed/telegram-omarchy-theme.json.tpl"
	local hook="$package_root/.config/omarchy/hooks/theme-set.d/telegram-theme"
	local helper="$package_root/.local/libexec/dotfiles/telegram-theme/generate.mjs"
	local baseline="$package_root/.local/libexec/dotfiles/telegram-theme/data/telegram-7.0.9-night.palette"
	for asset in "$template" "$hook" "$helper" "$baseline"; do
		[[ -f $asset ]] || {
			printf '  missing telegram-theme package asset: %s\n' "$asset" >&2
			return 1
		}
	done
	bash -n "$hook" || return 1
	"$HOST_NODE_REAL" --check "$helper" || return 1
	[[ -x $hook ]] || {
		printf '  installed theme-set hook should retain executable mode\n' >&2
		return 1
	}
	assert_contains "$(<"$template")" 'schema_version' 'rendered manifest template should declare schema version 1' || return 1
	assert_contains "$(<"$template")" '{{ mode' 'rendered manifest template should consume resolved Omarchy mode' || return 1
	local key
	for key in accent selection muted background dark_background darker_background lighter_background \
		foreground dark_foreground light_foreground bright_foreground red yellow green cyan blue magenta \
		bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta; do
		assert_contains "$(<"$template")" "{{ $key" "template should render common semantic color: $key" || return 1
	done

	local package
	package=$(jq -c '.packages[] | select(.name == "telegram-theme")' "$FIXTURE_REPO/packages.json")
	[[ -n $package ]] || {
		printf '  package catalog does not declare telegram-theme\n' >&2
		return 1
	}
	assert_eq 'config/telegram-theme' "$(jq -r '.path' <<<"$package")" 'catalog should point to the dedicated Stow package' || return 1
	assert_eq '["telegram-desktop","zip"]' "$(jq -c '.arch_packages' <<<"$package")" \
		'catalog should declare exact Telegram Desktop and system zip requirements' || return 1
	assert_eq '["node","flock"]' "$(jq -c '.prerequisites' <<<"$package")" \
		'catalog should declare Node and flock command prerequisites without Arch-owned zip' || return 1
	local cleanup
	cleanup=$(jq -r '.cleanup[]' <<<"$package")
	assert_contains "$cleanup" 'XDG' 'removal cleanup should retain generated XDG state' || return 1
	assert_contains "$cleanup" 'Telegram' 'removal cleanup should retain and explain Telegram-owned selection state' || return 1
	assert_contains "$cleanup" 'telegram-desktop' 'removal cleanup should retain the Telegram Arch package' || return 1
	assert_contains "$cleanup" 'zip' 'removal cleanup should retain the zip Arch package'
}

test_package_apply_and_remove_manage_only_stow_assets() {
	new_fixture
	configure_telegram_lifecycle_boundaries
	set_installed_arch_packages telegram-desktop zip
	rm "$FIXTURE_BIN/stow"
	jq '(.packages[] | select(.name == "telegram-theme").validators) = []' \
		"$FIXTURE_REPO/packages.json" >"$FIXTURE_REPO/packages.updated"
	mv "$FIXTURE_REPO/packages.updated" "$FIXTURE_REPO/packages.json"

	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages telegram-theme
	assert_eq 0 "$COMMAND_STATUS" 'approved telegram-theme package apply should succeed' || return 1
	local source relative target
	while IFS= read -r -d '' source; do
		relative=${source#"$FIXTURE_REPO/config/telegram-theme/"}
		target="$FIXTURE_HOME/$relative"
		assert_eq "$(readlink -f "$source")" "$(readlink -f "$target")" \
			"package apply should leaf-link $relative" || return 1
	done < <(find "$FIXTURE_REPO/config/telegram-theme" -type f -print0)

	mkdir -p "$FIXTURE_STATE/dotfiles/telegram-theme"
	printf 'retained archive\n' >"$FIXTURE_STATE/dotfiles/telegram-theme/current.tdesktop-theme"
	printf '{"schema_version":1,"status":"ok"}\n' >"$FIXTURE_STATE/dotfiles/telegram-theme/status.json"
	local retained_before
	retained_before=$(sha256sum "$FIXTURE_STATE/dotfiles/telegram-theme/current.tdesktop-theme" \
		"$FIXTURE_STATE/dotfiles/telegram-theme/status.json")
	run_operation "$FIXTURE_ROOT" remove_package telegram-theme --yes
	assert_eq 0 "$COMMAND_STATUS" 'approved telegram-theme package removal should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Cleanup notes (not deleted)' 'removal should report retained state' || return 1
	assert_eq "$retained_before" "$(sha256sum "$FIXTURE_STATE/dotfiles/telegram-theme/current.tdesktop-theme" \
		"$FIXTURE_STATE/dotfiles/telegram-theme/status.json")" 'removal should leave integration state intact' || return 1
	assert_eq $'telegram-desktop\nzip' "$(<"$ARCH_PACKAGE_STATE")" 'removal should retain declared Arch packages' || return 1
	while IFS= read -r -d '' source; do
		relative=${source#"$FIXTURE_REPO/config/telegram-theme/"}
		target="$FIXTURE_HOME/$relative"
		if [[ -e $target || -L $target ]]; then
			printf '  package removal left managed target: %s\n' "$target" >&2
			return 1
		fi
	done < <(find "$FIXTURE_REPO/config/telegram-theme" -type f -print0)
	assert_lifecycle_did_not_control_telegram
}

test_wizard_exposes_public_module_functions_action_and_manager_menu() {
	new_fixture
	local module="$FIXTURE_REPO/lib/dotfiles/telegram-theme.sh" function
	[[ -f $module ]] || {
		printf '  missing Telegram theme lifecycle module: %s\n' "$module" >&2
		return 1
	}
	for function in manage_telegram_theme telegram_theme_status setup_telegram_theme retry_telegram_theme; do
		grep -Eq "^${function}[(][)]" "$module" || {
			printf '  missing public Telegram theme function: %s\n' "$function" >&2
			return 1
		}
	done
	assert_contains "$(<"$FIXTURE_REPO/bin/dotfiles")" 'source "$DOTFILES_ENTRY_ROOT/lib/dotfiles/telegram-theme.sh"' \
		'entrypoint should source Telegram lifecycle before wizard orchestration' || return 1
	assert_contains "$(<"$FIXTURE_REPO/bin/dotfiles")" 'telegram-theme' 'entrypoint usage should expose the public action slug' || return 1

	DOTFILES_TEST_INPUT='4\n' run_dotfiles "$FIXTURE_ROOT" --action telegram-theme
	assert_eq 0 "$COMMAND_STATUS" 'Telegram public action should open its manager' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Manage Telegram theme' 'public action should dispatch to Telegram manager' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  1. Status\n  2. Setup / refresh\n  3. Retry\n  4. Back' \
		'manager should expose exactly the approved operation order'
}

test_telegram_status_reports_absent_and_failed_state_without_mutation() {
	new_fixture
	configure_telegram_lifecycle_boundaries
	local before
	before=$(snapshot_isolated_paths)
	run_operation "$FIXTURE_ROOT" telegram_theme_status
	assert_eq 0 "$COMMAND_STATUS" 'status should successfully report an unconfigured integration' || return 1
	assert_contains "$COMMAND_OUTPUT" 'not set up' 'absent status should explain that setup is pending' || return 1
	assert_eq "$before" "$(snapshot_isolated_paths)" 'status should be read-only' || return 1
	if [[ $(<"$CALL_LOG") == *'theme refresh'* || $(<"$CALL_LOG") == *'pkg add'* ]]; then
		printf '  status attempted a refresh or package mutation\n' >&2
		return 1
	fi

	mkdir -p "$FIXTURE_STATE/dotfiles/telegram-theme"
	printf '{"schema_version":1,"status":"error","slug":"solitude","message":"fixture generation failed"}\n' \
		>"$FIXTURE_STATE/dotfiles/telegram-theme/status.json"
	run_operation "$FIXTURE_ROOT" telegram_theme_status
	assert_eq 0 "$COMMAND_STATUS" 'status should report a persisted failure without failing inspection' || return 1
	assert_contains "$COMMAND_OUTPUT" 'solitude' 'status should identify the failed active slug' || return 1
	assert_contains "$COMMAND_OUTPUT" 'fixture generation failed' 'status should expose persisted diagnostics' || return 1
	assert_lifecycle_did_not_control_telegram
}

test_setup_requires_approval_before_public_theme_refresh() {
	new_fixture
	configure_telegram_lifecycle_boundaries
	link_telegram_theme_fixture_package
	make_fake omarchy 'printf "omarchy %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "4.0.1-1\n"; exit 0; fi
if [[ $* == "theme refresh" ]]; then exit 73; fi
exit 64'
	DOTFILES_TEST_INPUT='n\n' run_operation "$FIXTURE_ROOT" setup_telegram_theme
	assert_eq 0 "$COMMAND_STATUS" 'declining setup refresh should be a safe no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy theme refresh' 'setup should disclose the exact public bootstrap command' || return 1
	if [[ $(<"$CALL_LOG") == *'theme refresh'* ]]; then
		printf '  declined setup ran Omarchy theme refresh\n' >&2
		return 1
	fi

	: >"$CALL_LOG"
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" setup_telegram_theme
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  injected theme refresh failure unexpectedly completed setup\n' >&2
		return 1
	fi
	assert_eq 1 "$(awk '/^omarchy theme refresh$/ { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'approved setup should invoke one public Omarchy refresh' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Retry' 'failed setup should direct recovery to the Retry operation' || return 1
	assert_lifecycle_did_not_control_telegram
}

assert_setup_rejects_package_metadata_before_confirmation_and_refresh() {
	local scenario=$1 expected_detection=$2
	new_fixture
	configure_telegram_lifecycle_boundaries
	link_telegram_theme_fixture_package
	local scenario_file=$FIXTURE_ROOT/telegram-package-query-scenario
	make_fake pacman 'printf "pacman %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
scenario=$(<"${DOTFILES_TEST_CALL_LOG%/*}/telegram-package-query-scenario")
case "$scenario:$*" in
  "mismatched:-Q omarchy") printf "omarchy 4.0.0-1\n" ;;
  "unavailable:-Q omarchy") printf "omarchy 4.0.1-1\n" ;;
  "unavailable:-Q telegram-desktop") exit 1 ;;
  "malformed:-Q omarchy") printf "omarchy 4.0.1-1 unexpected\n" ;;
  "mismatched:-Q telegram-desktop"|"malformed:-Q telegram-desktop") printf "telegram-desktop 7.0.9-4\n" ;;
  *) exit 64 ;;
esac'
	configure_telegram_setup_guard_probes

	printf '%s\n' "$scenario" >"$scenario_file"
	assert_setup_rejected_before_confirmation_and_refresh \
		"$scenario package metadata" 'unsupported or unverifiable package version' || return 1
	assert_contains "$COMMAND_OUTPUT" "Detected Telegram theme packages: $expected_detection" \
		"$scenario package metadata should report only verified package identities"
}

test_setup_rejects_mismatched_package_metadata_before_confirmation_and_refresh() {
	assert_setup_rejects_package_metadata_before_confirmation_and_refresh \
		mismatched 'omarchy 4.0.0-1; telegram-desktop 7.0.9-4'
}

test_setup_rejects_unavailable_package_metadata_before_confirmation_and_refresh() {
	assert_setup_rejects_package_metadata_before_confirmation_and_refresh \
		unavailable 'omarchy 4.0.1-1; telegram-desktop unavailable'
}

test_setup_rejects_malformed_package_metadata_before_confirmation_and_refresh() {
	assert_setup_rejects_package_metadata_before_confirmation_and_refresh \
		malformed 'omarchy unavailable; telegram-desktop 7.0.9-4'
}

assert_setup_rejects_missing_command_before_confirmation_and_refresh() {
	local command=$1 restricted_path
	new_fixture
	configure_telegram_lifecycle_boundaries
	link_telegram_theme_fixture_package
	configure_telegram_setup_guard_probes
	restricted_path=$(telegram_theme_test_path_without "$command") || return 1
	DOTFILES_TEST_PATH=$restricted_path \
		assert_setup_rejected_before_confirmation_and_refresh \
		"unavailable $command" "$command"
}

test_setup_rejects_unavailable_node_before_confirmation_and_refresh() {
	assert_setup_rejects_missing_command_before_confirmation_and_refresh node
}

test_setup_rejects_unavailable_zip_before_confirmation_and_refresh() {
	assert_setup_rejects_missing_command_before_confirmation_and_refresh zip
}

assert_setup_rejects_node_version_before_confirmation_and_refresh() {
	local scenario=$1 reported_version=$2
	new_fixture
	configure_telegram_lifecycle_boundaries
	link_telegram_theme_fixture_package
	configure_telegram_setup_guard_probes
	make_fake node "if [[ \${1-} == --version ]]; then printf '%s\\n' '$reported_version'; exit 0; fi
printf 'unexpected node execution: %s\\n' \"\$*\" >>\"\$DOTFILES_TEST_CALL_LOG\"
exit 99"
	assert_setup_rejected_before_confirmation_and_refresh \
		"$scenario Node.js version" 'Node.js'
}

test_setup_rejects_old_node_before_confirmation_and_refresh() {
	assert_setup_rejects_node_version_before_confirmation_and_refresh old v22.19.0
}

test_setup_rejects_malformed_node_before_confirmation_and_refresh() {
	assert_setup_rejects_node_version_before_confirmation_and_refresh malformed not-a-node-version
}

test_setup_rejects_unavailable_flock_before_confirmation_and_refresh() {
	assert_setup_rejects_missing_command_before_confirmation_and_refresh flock
}

assert_setup_rejects_invalid_xdg_path_before_confirmation_and_refresh() {
	local variable=$1 condition=$2 rejected_path
	new_fixture
	configure_telegram_lifecycle_boundaries
	link_telegram_theme_fixture_package
	configure_telegram_setup_guard_probes
	if [[ $condition == relative ]]; then
		rejected_path="relative-${variable,,}"
	else
		rejected_path="$FIXTURE_ROOT/unwritable-${variable,,}"
		mkdir "$rejected_path"
		chmod 0500 "$rejected_path"
	fi
	if [[ $variable == XDG_STATE_HOME ]]; then
		FIXTURE_STATE=$rejected_path
	else
		FIXTURE_RUNTIME=$rejected_path
	fi
	assert_setup_rejected_before_confirmation_and_refresh \
		"$condition $variable" "$variable"
}

test_setup_rejects_relative_state_home_before_confirmation_and_refresh() {
	assert_setup_rejects_invalid_xdg_path_before_confirmation_and_refresh XDG_STATE_HOME relative
}

test_setup_rejects_unwritable_state_home_before_confirmation_and_refresh() {
	assert_setup_rejects_invalid_xdg_path_before_confirmation_and_refresh XDG_STATE_HOME unwritable
}

test_setup_rejects_relative_runtime_dir_before_confirmation_and_refresh() {
	assert_setup_rejects_invalid_xdg_path_before_confirmation_and_refresh XDG_RUNTIME_DIR relative
}

test_setup_rejects_unwritable_runtime_dir_before_confirmation_and_refresh() {
	assert_setup_rejects_invalid_xdg_path_before_confirmation_and_refresh XDG_RUNTIME_DIR unwritable
}

assert_setup_rejects_invalid_baseline_link_before_confirmation_and_refresh() {
	local condition=$1
	new_fixture
	configure_telegram_lifecycle_boundaries
	link_telegram_theme_fixture_package
	configure_telegram_setup_guard_probes
	local target="$FIXTURE_HOME/.local/libexec/dotfiles/telegram-theme/data/telegram-7.0.9-night.palette"
	rm "$target"
	if [[ $condition == wrong ]]; then
		printf 'wrong pinned baseline\n' >"$FIXTURE_ROOT/wrong-telegram-baseline.palette"
		ln -s "$FIXTURE_ROOT/wrong-telegram-baseline.palette" "$target"
	fi
	assert_setup_rejected_before_confirmation_and_refresh \
		"$condition pinned baseline link" 'telegram-7.0.9-night.palette'
}

test_setup_rejects_missing_baseline_link_before_confirmation_and_refresh() {
	assert_setup_rejects_invalid_baseline_link_before_confirmation_and_refresh missing
}

test_setup_rejects_wrong_baseline_link_before_confirmation_and_refresh() {
	assert_setup_rejects_invalid_baseline_link_before_confirmation_and_refresh wrong
}

test_publication_verification_rejects_archive_status_digest_mismatch() {
	new_fixture
	local root=$FIXTURE_STATE/dotfiles/telegram-theme archive=$FIXTURE_STATE/dotfiles/telegram-theme/current.tdesktop-theme
	local status=$FIXTURE_STATE/dotfiles/telegram-theme/status.json digest
	mkdir -p "$root" "$FIXTURE_STATE/omarchy/current"
	printf 'verified archive fixture\n' >"$archive"
	printf 'everforest\n' >"$FIXTURE_STATE/omarchy/current/theme.name"
	digest=$(sha256sum "$archive")
	digest=${digest%% *}
	jq -n --arg digest "$digest" \
		'{schema_version:1,status:"ok",slug:"everforest",archive_sha256:$digest}' >"$status"
	run_operation "$FIXTURE_ROOT" telegram_theme_verify_publication
	assert_eq 0 "$COMMAND_STATUS" 'publication verification should accept its matching recorded archive digest' || return 1
	jq '.archive_sha256 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
		"$status" >"$status.changed"
	mv "$status.changed" "$status"
	run_operation "$FIXTURE_ROOT" telegram_theme_verify_publication
	assert_eq 1 "$COMMAND_STATUS" 'publication verification should reject an archive/status SHA-256 mismatch'
}

test_setup_and_retry_require_linked_stow_package_assets() {
	new_fixture
	configure_telegram_lifecycle_boundaries
	run_operation "$FIXTURE_ROOT" setup_telegram_theme
	assert_eq 1 "$COMMAND_STATUS" 'setup should reject an unlinked telegram-theme package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Apply Stow packages' 'setup rejection should direct package linking' || return 1
	if [[ $(<"$CALL_LOG") == *'theme refresh'* ]]; then
		printf '  unlinked setup reached Omarchy refresh\n' >&2
		return 1
	fi

	: >"$CALL_LOG"
	run_operation "$FIXTURE_ROOT" retry_telegram_theme
	assert_eq 1 "$COMMAND_STATUS" 'retry should reject an unlinked telegram-theme package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Apply Stow packages' 'retry rejection should direct package linking' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'unlinked retry should stop before external operations' || return 1
	assert_lifecycle_did_not_control_telegram
}

test_retry_reuses_promoted_active_slug_without_refresh() {
	new_fixture
	configure_telegram_lifecycle_boundaries
	link_telegram_theme_fixture_package
	mkdir -p "$FIXTURE_STATE/omarchy/current/theme"
	printf 'everforest\n' >"$FIXTURE_STATE/omarchy/current/theme.name"
	local manifest="$FIXTURE_STATE/omarchy/current/theme/telegram-omarchy-theme.json"
	local output="$FIXTURE_STATE/dotfiles/telegram-theme/current.tdesktop-theme"
	local status="$FIXTURE_STATE/dotfiles/telegram-theme/status.json"
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$manifest" || return 1
	local manifest_before
	manifest_before=$(sha256sum "$manifest")
	run_operation "$FIXTURE_ROOT" retry_telegram_theme
	assert_eq 0 "$COMMAND_STATUS" 'retry should dispatch the promoted active slug through the linked installed hook' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Retrying Telegram theme generation for active Omarchy theme: everforest' \
		'retry should reuse the exact active slug' || return 1
	[[ -s $output ]] || {
		printf '  retry did not publish the stable archive\n' >&2
		return 1
	}
	jq -e '.schema_version == 1 and .status == "ok" and .slug == "everforest"' "$status" >/dev/null || {
		printf '  retry did not record successful status for the active slug\n' >&2
		return 1
	}
	"$HOST_NODE_REAL" "$SOURCE_REPO/tests/support/telegram_theme_assertions.mjs" "$output" "$manifest" >/dev/null || return 1
	assert_eq "$manifest_before" "$(sha256sum "$manifest")" 'retry should not modify the promoted manifest' || return 1
	if [[ $(<"$CALL_LOG") == *'theme refresh'* ]]; then
		printf '  retry invoked Omarchy refresh instead of reusing the promoted manifest\n' >&2
		return 1
	fi
	assert_lifecycle_did_not_control_telegram
}

test_focused_telegram_suites_are_registered_once() {
	new_fixture
	local suite registrations
	for suite in telegram_theme_generator_test.sh telegram_theme_hook_test.sh telegram_theme_lifecycle_test.sh; do
		[[ -f $SOURCE_REPO/tests/$suite ]] || return 1
		registrations=$(awk -v suite="$suite" '$1 == suite { count++ } END { print count + 0 }' "$SOURCE_REPO/tests/run.sh")
		assert_eq 1 "$registrations" "$suite should be registered exactly once" || return 1
	done
}

set -e
run_test test_package_declares_owned_assets_requirements_and_cleanup 'package declares owned assets, requirements, and conservative cleanup'
run_test test_package_apply_and_remove_manage_only_stow_assets 'package apply and removal manage only tracked Stow assets'
run_test test_wizard_exposes_public_module_functions_action_and_manager_menu 'wizard exposes Telegram public functions, action, and manager menu'
run_test test_telegram_status_reports_absent_and_failed_state_without_mutation 'Telegram status reports absent and failed state without mutation'
run_test test_setup_requires_approval_before_public_theme_refresh 'setup requires approval before public Omarchy theme refresh'
run_test test_setup_rejects_mismatched_package_metadata_before_confirmation_and_refresh 'setup rejects mismatched package metadata before confirmation and refresh'
run_test test_setup_rejects_unavailable_package_metadata_before_confirmation_and_refresh 'setup rejects unavailable package metadata before confirmation and refresh'
run_test test_setup_rejects_malformed_package_metadata_before_confirmation_and_refresh 'setup rejects malformed package metadata before confirmation and refresh'
run_test test_setup_rejects_unavailable_node_before_confirmation_and_refresh 'setup rejects unavailable node before confirmation and refresh'
run_test test_setup_rejects_unavailable_zip_before_confirmation_and_refresh 'setup rejects unavailable zip before confirmation and refresh'
run_test test_setup_rejects_old_node_before_confirmation_and_refresh 'setup rejects old Node.js before confirmation and refresh'
run_test test_setup_rejects_malformed_node_before_confirmation_and_refresh 'setup rejects malformed Node.js before confirmation and refresh'
run_test test_setup_rejects_unavailable_flock_before_confirmation_and_refresh 'setup requires flock before confirmation and refresh'
run_test test_setup_rejects_relative_state_home_before_confirmation_and_refresh 'setup rejects relative XDG state home before confirmation and refresh'
run_test test_setup_rejects_unwritable_state_home_before_confirmation_and_refresh 'setup rejects unwritable XDG state home before confirmation and refresh'
run_test test_setup_rejects_relative_runtime_dir_before_confirmation_and_refresh 'setup rejects relative XDG runtime directory before confirmation and refresh'
run_test test_setup_rejects_unwritable_runtime_dir_before_confirmation_and_refresh 'setup rejects unwritable XDG runtime directory before confirmation and refresh'
run_test test_setup_rejects_missing_baseline_link_before_confirmation_and_refresh 'setup rejects a missing pinned baseline link before confirmation and refresh'
run_test test_setup_rejects_wrong_baseline_link_before_confirmation_and_refresh 'setup rejects a wrong pinned baseline link before confirmation and refresh'
run_test test_publication_verification_rejects_archive_status_digest_mismatch 'publication verification rejects archive and status digest mismatch'
run_test test_setup_and_retry_require_linked_stow_package_assets 'setup and retry require linked telegram-theme Stow package assets'
run_test test_retry_reuses_promoted_active_slug_without_refresh 'retry reuses the promoted active slug without refresh'
run_test test_focused_telegram_suites_are_registered_once 'focused Telegram suites are registered once'
finish_tests
