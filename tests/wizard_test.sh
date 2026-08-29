#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

configure_empty_modem_sysfs() {
	local fake_sysfs=$FIXTURE_ROOT/empty-sys
	mkdir -p "$fake_sysfs/bus/usb/devices" "$fake_sysfs/bus/pci/drivers/xhci_hcd"
	: >"$fake_sysfs/bus/pci/drivers/xhci_hcd/unbind"
	: >"$fake_sysfs/bus/pci/drivers/xhci_hcd/bind"
	BWRAP_EXTRA_ARGS=(--bind "$fake_sysfs" /sys)
	make_fake sudo 'printf "unexpected sudo call\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
	make_fake nmcli 'printf "unexpected nmcli call\n" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
}

stub_guided_brave_apply() {
	local outcome=$1
	local context=${2-BRAVE_OPERATION_CONTEXT_ORDINARY}
	printf '\napply_brave_policy() { BRAVE_OPERATION_CONTEXT=$%s; printf "Stub Brave apply outcome: %s; context: %%s\\n" "$BRAVE_OPERATION_CONTEXT"; return %s; }\n' \
		"$context" "$outcome" "$outcome" >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh"
	stub_guided_wallpaper_apply 0
}

stub_guided_wallpaper_apply() {
	local outcome=$1
	local context=${2-'$WALLPAPER_OPERATION_CONTEXT_ORDINARY'}
	local result=${3-Apply}
	printf '\napply_wallpapers() { WALLPAPER_OPERATION_CONTEXT=%s; printf "Stub wallpaper %s outcome: %s; context: %%s\\n" "$WALLPAPER_OPERATION_CONTEXT"; return %s; }\n' \
		"$context" "$result" "$outcome" "$outcome" >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh"
}

stub_wallpaper_operations() {
	cat >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh" <<'EOF'
manage_wallpapers() { printf 'Stub wallpaper manager\n'; }
apply_wallpapers() { printf 'Stub wallpaper apply\n'; }
remove_wallpapers() { printf 'Stub wallpaper removal\n'; }
EOF
}

stub_screensaver_effects_manager() {
	cat >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh" <<'EOF'
manage_screensaver_effects() { printf 'Stub screensaver effects manager\n'; }
EOF
}

stub_guided_phases_after_prerequisites() {
	cat >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh" <<'EOF'
install_skills() { printf 'Stub guided skills\n'; }
cleanup_applications() { printf 'Stub guided cleanup\n'; }
wizard_packages() { WIZARD_PACKAGES=(); }
apply_packages() { printf 'Stub guided Stow apply\n'; }
apply_wallpapers() { WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_ORDINARY; printf 'Stub guided wallpaper apply\n'; }
apply_brave_policy() { BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_ORDINARY; printf 'Stub guided Brave unavailable\n'; return "$BRAVE_OUTCOME_UNAVAILABLE"; }
EOF
}

test_top_level_menu_starts_with_guided_setup() {
	new_fixture
	run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'an empty menu choice should safely exit' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  1. Guided setup\n  2. Package status\n  3. Run structural checks\n  4. Apply Stow packages\n  5. Migrate existing target\n  6. Remove Stow package\n  7. Prepare prerequisites\n  8. Clean up Omarchy applications\n  9. Install pinned global skills\n  10. Update pinned global skills\n  11. Recover ZTE USB modem\n  12. Manage Brave policy\n  13. Manage Telegram theme\n  14. Manage wallpapers\n  15. Apply wallpapers\n  16. Remove deployed wallpapers\n  17. Manage screensaver effects\n  18. Exit' \
		'screensaver effects should be appended before Exit without renumbering existing actions' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No action selected.' 'no action should be selected by default'
}

test_entrypoint_sources_brave_before_wizard() {
	new_fixture
	local entrypoint brave_line wizard_line
	entrypoint=$(<"$FIXTURE_REPO/bin/dotfiles")
	assert_contains "$entrypoint" 'source "$DOTFILES_ENTRY_ROOT/lib/dotfiles/brave.sh"' \
		'the public entrypoint should source the Brave module' || return 1
	brave_line=$(awk '/^source .*lib\/dotfiles\/brave[.]sh"$/ { print NR; exit }' "$FIXTURE_REPO/bin/dotfiles")
	wizard_line=$(awk '/^source .*lib\/dotfiles\/wizard[.]sh"$/ { print NR; exit }' "$FIXTURE_REPO/bin/dotfiles")
	if [[ -z $brave_line || -z $wizard_line || $brave_line -ge $wizard_line ]]; then
		printf '  the Brave module must be sourced before interactive orchestration\n' >&2
		return 1
	fi
}

test_entrypoint_sources_wallpapers_before_wizard() {
	new_fixture
	local entrypoint wallpaper_line wizard_line
	entrypoint=$(<"$FIXTURE_REPO/bin/dotfiles")
	assert_contains "$entrypoint" 'source "$DOTFILES_ENTRY_ROOT/lib/dotfiles/wallpapers.sh"' \
		'the public entrypoint should source the Wallpaper module' || return 1
	wallpaper_line=$(awk '/^source .*lib\/dotfiles\/wallpapers[.]sh"$/ { print NR; exit }' "$FIXTURE_REPO/bin/dotfiles")
	wizard_line=$(awk '/^source .*lib\/dotfiles\/wizard[.]sh"$/ { print NR; exit }' "$FIXTURE_REPO/bin/dotfiles")
	if [[ -z $wallpaper_line || -z $wizard_line || $wallpaper_line -ge $wizard_line ]]; then
		printf '  the Wallpaper module must be sourced before interactive orchestration\n' >&2
		return 1
	fi
}

test_legacy_and_invalid_entry_forms_are_rejected() {
	new_fixture
	run_dotfiles "$FIXTURE_ROOT" status
	assert_eq 2 "$COMMAND_STATUS" 'a removed public route should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Usage: bin/dotfiles [--action' 'invalid entry use should explain the supported interface' || return 1
	assert_contains "$COMMAND_OUTPUT" 'telegram-theme|wallpapers|wallpapers-apply|wallpapers-remove|screensaver-effects|screensaver-effects-migrate>]' \
		'usage should advertise every wallpaper and screensaver public action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'wallpapers-apply: deploy the Wallpaper library' \
		'usage should distinguish deployment Apply from curation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'wallpapers-remove: remove receipt-owned deployed wallpapers' \
		'usage should identify the standalone deployment recovery route' || return 1
	assert_contains "$COMMAND_OUTPUT" 'screensaver-effects: manage and preview the deployed effect allowlist' \
		'usage should identify the public screensaver manager route' || return 1
	assert_contains "$COMMAND_OUTPUT" 'screensaver-effects-migrate: migrate competing Omarchy idle or Indicators clones' \
		'usage should identify the dedicated screensaver migration route' || return 1
	run_dotfiles "$FIXTURE_ROOT" --arbitrary
	assert_eq 2 "$COMMAND_STATUS" 'arbitrary flags should be rejected' || return 1
	run_dotfiles "$FIXTURE_ROOT" --action unknown
	assert_eq 2 "$COMMAND_STATUS" 'an unknown preselected action should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unknown wizard action: unknown' 'unknown action output should name the invalid value'
}

test_public_action_preselection_dispatches() {
	new_fixture
	use_empty_package_catalog
	run_dotfiles "$FIXTURE_ROOT" --action status
	assert_eq 0 "$COMMAND_STATUS" 'a valid public preselection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'public preselection should dispatch to the selected operation'
}

test_modem_public_action_preselection_dispatches() {
	new_fixture
	configure_empty_modem_sysfs
	run_dotfiles "$FIXTURE_ROOT" --action modem

	assert_eq 1 "$COMMAND_STATUS" 'the modem preselection should dispatch to its discovery failure' || return 1
	if [[ $COMMAND_OUTPUT == *'unknown wizard action'* || $COMMAND_OUTPUT == *'Usage: bin/dotfiles'* ]]; then
		printf '  the public modem action was rejected instead of dispatched\n' >&2
		return 1
	fi
	assert_eq '' "$(<"$CALL_LOG")" 'empty fake sysfs discovery should not invoke privileged or network tools'
}

test_modem_menu_selection_dispatches() {
	new_fixture
	configure_empty_modem_sysfs
	DOTFILES_TEST_INPUT='11\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'menu item 11 should dispatch to modem discovery' || return 1
	if [[ $COMMAND_OUTPUT == *'No action selected.'* ]]; then
		printf '  modem menu selection exited instead of dispatching\n' >&2
		return 1
	fi
	assert_eq '' "$(<"$CALL_LOG")" 'empty fake sysfs menu discovery should not invoke privileged or network tools'
}

test_brave_public_action_preselection_dispatches() {
	new_fixture
	DOTFILES_TEST_INPUT='4\n' run_dotfiles "$FIXTURE_ROOT" --action brave

	assert_eq 0 "$COMMAND_STATUS" 'the Brave preselection should open its management menu' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Manage Brave policy' 'the public Brave action should dispatch to the shared manager' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  1. Status\n  2. Apply\n  3. Remove\n  4. Back' \
		'the Brave manager should expose only the approved policy operations'
}

test_wallpaper_manager_public_action_preselection_dispatches() {
	new_fixture
	stub_wallpaper_operations
	run_dotfiles "$FIXTURE_ROOT" --action wallpapers

	assert_eq 0 "$COMMAND_STATUS" 'the wallpaper manager preselection should dispatch successfully' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper manager' \
		'the public wallpaper action should call the curation manager'
}

test_wallpaper_deployment_public_action_preselections_dispatch() {
	new_fixture
	stub_wallpaper_operations
	run_dotfiles "$FIXTURE_ROOT" --action wallpapers-apply
	assert_eq 0 "$COMMAND_STATUS" 'the wallpaper Apply preselection should dispatch successfully' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper apply' \
		'the public wallpaper Apply action should call the deployment Apply operation' || return 1

	run_dotfiles "$FIXTURE_ROOT" --action wallpapers-remove
	assert_eq 0 "$COMMAND_STATUS" 'the wallpaper removal preselection should dispatch successfully' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper removal' \
		'the public wallpaper removal action should call the deployment removal operation'
}

test_screensaver_effects_public_action_and_make_target_dispatch() {
	new_fixture
	stub_screensaver_effects_manager
	run_dotfiles "$FIXTURE_ROOT" --action screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'the screensaver effects preselection should dispatch successfully' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub screensaver effects manager' \
		'the public screensaver action should call the manager' || return 1

	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		make --no-print-directory -C "$FIXTURE_REPO" screensaver-effects
	assert_eq 0 "$COMMAND_STATUS" 'make screensaver-effects should dispatch successfully' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub screensaver effects manager' \
		'make screensaver-effects should route through the public action'
}

test_default_make_menu_dispatches_telegram_theme_management() {
	new_fixture
	DOTFILES_TEST_INPUT='13\n4\n' run_make "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'default make menu item 13 should open and leave Telegram theme management' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Manage Telegram theme' \
		'the main Bash menu should dispatch its Telegram theme action' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  1. Status\n  2. Setup / refresh\n  3. Retry\n  4. Back' \
		'the dispatched Telegram manager should expose its supported operations'
}

test_status_and_check_standalone_actions() {
	new_fixture
	use_empty_package_catalog
	DOTFILES_TEST_INPUT='2\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone status should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'standalone status should reach the package engine' || return 1
	DOTFILES_TEST_INPUT='3\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone checks should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Package catalog: valid' 'standalone checks should reach the structural engine'
}

test_bash_apply_standalone_uses_one_multiselect_and_dependency_order() {
	new_fixture
	add_package base
	add_dependent_package app base
	make_applying_stow
	DOTFILES_TEST_INPUT='4\n2\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'standalone Bash apply should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" $'Plan: apply packages in dependency order:\n  1. base (required by selection)\n  2. app (selected)' 'apply should resolve and show the complete dependency plan' || return 1
	assert_eq 1 "$(awk '/Apply this complete Stow plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" 'apply should confirm the complete plan once' || return 1
	local base_apply app_apply
	base_apply=$(awk '/^stow --no-folding --verbose=2 .* base$/ { print NR; exit }' "$CALL_LOG")
	app_apply=$(awk '/^stow --no-folding --verbose=2 .* app$/ { print NR; exit }' "$CALL_LOG")
	[[ -n $base_apply && -n $app_apply && $base_apply -lt $app_apply ]]
}

test_gum_apply_has_no_default_selection() {
	new_fixture
	add_package
	make_applying_stow
	local responses=$FIXTURE_ROOT/gum-responses
	printf 'Apply Stow packages\n\n' >"$responses"
	make_gum_responder
	DOTFILES_UI=gum DOTFILES_TEST_GUM_RESPONSES=$responses run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'an empty Gum package selection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No Stow packages selected; no changes made.' 'Gum should default to no Stow packages' || return 1
	assert_contains "$(<"$CALL_LOG")" 'gum choose --no-limit --header Choose Stow packages (none selected by default)' 'Gum should provide the multi-select screen'
}

test_migrate_and_remove_standalone_actions() {
	new_fixture
	add_package
	rm "$FIXTURE_REPO/config/demo/.config/demo/config"
	mkdir -p "$FIXTURE_HOME/.config/demo"
	printf 'approved\n' >"$FIXTURE_HOME/.config/demo/config"
	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " != *" --simulate "* ]]; then
	mkdir -p "$HOME/.config/demo"
	ln -s "$DOTFILES_TEST_REPO/config/demo/.config/demo/config" "$HOME/.config/demo/config"
fi'
	DOTFILES_TEST_INPUT='5\n2\n.config/demo/config\ny\ny\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone migration should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migrated and verified package: demo' 'migration should reach its internal engine' || return 1

	make_fake stow 'printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ " $* " == *" --delete "* && " $* " != *" --simulate "* ]]; then rm -rf "$HOME/.config/demo"; fi'
	DOTFILES_TEST_INPUT='6\n2\ny\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone removal should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified package: demo' 'removal should reach its internal engine'
}

test_prerequisites_verify_existing_imagemagick_without_installation() {
	new_fixture
	run_operation "$FIXTURE_ROOT" setup_prerequisites

	assert_eq 0 "$COMMAND_STATUS" 'available ImageMagick should satisfy prerequisite preparation without approval' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Prerequisites verified: GNU Stow, ImageMagick (magick), Node.js 22.20.0, npm, and npx.' \
		'the no-op success output should include ImageMagick command availability' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg add imagemagick'* ]]; then
		printf '  prerequisite no-op attempted to reinstall available ImageMagick\n' >&2
		return 1
	fi
}

test_prerequisite_standalone_installs_complete_plan_with_supported_flows() {
	new_fixture
	mv "$FIXTURE_BIN/stow" "$FIXTURE_BIN/installed-stow"
	mv "$FIXTURE_BIN/magick" "$FIXTURE_BIN/installed-magick"
	mv "$FIXTURE_BIN/node" "$FIXTURE_BIN/installed-node"
	mv "$FIXTURE_BIN/npm" "$FIXTURE_BIN/installed-npm"
	mv "$FIXTURE_BIN/npx" "$FIXTURE_BIN/installed-npx"
	make_fake omarchy 'printf "%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "4.0.0-1\n"; exit 0; fi
if [[ $* == "pkg add stow" ]]; then mv "$DOTFILES_TEST_FAKE_BIN/installed-stow" "$DOTFILES_TEST_FAKE_BIN/stow"; exit 0; fi
if [[ $* == "pkg add imagemagick" ]]; then mv "$DOTFILES_TEST_FAKE_BIN/installed-magick" "$DOTFILES_TEST_FAKE_BIN/magick"; exit 0; fi
if [[ $* == "install dev-env node" ]]; then
	mv "$DOTFILES_TEST_FAKE_BIN/installed-node" "$DOTFILES_TEST_FAKE_BIN/node"
	mv "$DOTFILES_TEST_FAKE_BIN/installed-npm" "$DOTFILES_TEST_FAKE_BIN/npm"
	mv "$DOTFILES_TEST_FAKE_BIN/installed-npx" "$DOTFILES_TEST_FAKE_BIN/npx"
	exit 0
fi
exit 64'
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='7\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'confirmed prerequisite preparation should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy pkg add stow' 'the Stow plan should name the supported Omarchy flow' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy pkg add imagemagick' 'the ImageMagick plan should name the supported Omarchy flow' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy install dev-env node' 'the Node plan should name the supported Omarchy flow' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Node.js 22.20.0' 'the existing documented Node threshold should be enforced' || return 1
	assert_eq 1 "$(awk '/Apply this complete prerequisite plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'the complete Stow, ImageMagick, and Node plan should be confirmed once' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Prerequisites installed and verified: GNU Stow, ImageMagick (magick), Node.js 22.20.0, npm, and npx.' \
		'all installed tools should be verified and reported'
}

test_prerequisites_upgrade_old_node() {
	new_fixture
	make_fake node 'printf "v20.0.0\n"'
	make_fake updated-node 'printf "v22.20.0\n"'
	make_fake omarchy 'printf "%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "4.0.0-1\n"; exit 0; fi
if [[ $* == "install dev-env node" ]]; then mv "$DOTFILES_TEST_FAKE_BIN/updated-node" "$DOTFILES_TEST_FAKE_BIN/node"; exit 0; fi
exit 64'
	DOTFILES_TEST_INPUT='7\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'old Node.js should be upgraded and verified' || return 1
	assert_contains "$(<"$CALL_LOG")" 'install dev-env node' 'old Node.js should use the supported Omarchy installer' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Prerequisites installed and verified: GNU Stow, ImageMagick (magick), Node.js 22.20.0' \
		'the upgraded Node.js version and available ImageMagick command should be verified'
}

test_prerequisites_reject_missing_core_tool() {
	new_fixture
	local restricted_bin=$FIXTURE_ROOT/restricted-bin command
	mkdir -p "$restricted_bin"
	for command in bash dirname env jq find readlink git sort head node npm npx stow omarchy; do
		if [[ -x $FIXTURE_BIN/$command ]]; then
			ln -s "$FIXTURE_BIN/$command" "$restricted_bin/$command"
		elif command -v "$command" >/dev/null 2>&1; then
			ln -s "$(command -v "$command")" "$restricted_bin/$command"
		fi
	done
	DOTFILES_TEST_PATH=$restricted_bin DOTFILES_TEST_INPUT='7\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'a missing core tool should stop prerequisite preparation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: missing core prerequisite command: diff' 'the unavailable core tool should be named' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Prepare prerequisites in the Dotfiles wizard' 'core-tool recovery should name the wizard action'
}

test_cleanup_skills_and_update_standalone_actions() {
	new_fixture
	configure_cleanup_fakes
	DOTFILES_TEST_INPUT='8\n0\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone cleanup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No cleanup items selected' 'cleanup should remain independently reachable' || return 1

	new_fixture
	configure_skill_fakes
	seed_current_global_skills
	DOTFILES_TEST_INPUT='9\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone pinned skill installation should succeed when current' || return 1
	assert_contains "$COMMAND_OUTPUT" 'All manifest-owned skills already match' 'skill installation should remain independently reachable' || return 1

	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE=true DOTFILES_TEST_INPUT='10\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'standalone skill update should succeed when current' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No upstream skill updates are available.' 'skill update should remain independently reachable'
}

test_guided_setup_orders_and_skips_nonessential_phases() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 11
	DOTFILES_TEST_INPUT='1\n0\n\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'guided setup should continue across empty nonessential selections' || return 1
	local prerequisites skills cleanup stow wallpapers brave
	prerequisites=$(awk '/Guided phase 1:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	skills=$(awk '/Guided phase 2:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	cleanup=$(awk '/Guided phase 3:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	stow=$(awk '/Guided phase 4:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	wallpapers=$(awk '/Guided phase 5:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	brave=$(awk '/Guided phase 6:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
	if [[ -z $prerequisites || -z $skills || -z $cleanup || -z $stow || -z $wallpapers || -z $brave || \
		$prerequisites -ge $skills || $skills -ge $cleanup || $cleanup -ge $stow || $stow -ge $wallpapers || \
		$wallpapers -ge $brave ]]; then
		printf '  guided phases did not run in the required order\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'No cleanup items selected' 'empty cleanup should continue' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No Stow packages selected' 'empty Stow selection should continue' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper Apply outcome: 0' \
		'Guided setup should use the public wallpaper Apply operation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided phase 6 skipped: no supported Brave browser is installed.' \
		'an unavailable browser should skip the new optional phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' 'all skipped nonessential phases should complete the guide'
}

test_guided_wallpaper_ordinary_success_continues_to_brave() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 0
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 0 "$COMMAND_STATUS" 'ordinary wallpaper Apply success should complete Guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper Apply outcome: 0; context: ordinary' \
		'Guided setup should inspect the ordinary Wallpaper operation context' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided phase 6: optional Brave policy' \
		'ordinary wallpaper success should continue to Brave' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub Brave apply outcome: 0' \
		'ordinary wallpaper success should invoke Brave Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' \
		'ordinary wallpaper success should complete Guided setup'
}

test_guided_wallpaper_ordinary_skips_continue_to_brave() {
	local result
	for result in 'declined plan' 'exact no-op'; do
		new_fixture
		configure_cleanup_fakes
		configure_skill_fakes
		seed_current_global_skills
		stub_guided_brave_apply 0
		stub_guided_wallpaper_apply 0 '$WALLPAPER_OPERATION_CONTEXT_ORDINARY' "$result"
		DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

		assert_eq 0 "$COMMAND_STATUS" "ordinary wallpaper $result should complete Guided setup" || return 1
		assert_contains "$COMMAND_OUTPUT" "Stub wallpaper $result outcome: 0; context: ordinary" \
			"Guided setup should preserve the ordinary wallpaper $result outcome" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Stub Brave apply outcome: 0' \
			"ordinary wallpaper $result should continue to Brave" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' \
			"ordinary wallpaper $result should complete Guided setup" || return 1
	done
}

test_guided_wallpaper_recovery_completed_stops_before_brave() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 0
	stub_guided_wallpaper_apply 0 '$WALLPAPER_OPERATION_CONTEXT_RECOVERY_COMPLETED'
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'completed wallpaper recovery should require an ordinary Apply rerun' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper Apply outcome: 0; context: recovery-completed' \
		'Guided setup should inspect successful recovery context' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply wallpapers in the Dotfiles wizard.' \
		'completed wallpaper recovery should name the standalone rerun route' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 6:'* || $COMMAND_OUTPUT == *'Stub Brave apply outcome:'* || \
		$COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  Guided setup continued after Wallpaper recovery completed\n' >&2
		return 1
	fi
}

test_guided_wallpaper_unknown_context_stops_before_brave() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 0
	stub_guided_wallpaper_apply 0 unexpected-context
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'unknown wallpaper context should fail closed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper Apply outcome: 0; context: unexpected-context' \
		'Guided setup should preserve the unexpected context for diagnosis' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply wallpapers in the Dotfiles wizard.' \
		'unknown wallpaper context should name the standalone rerun route' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 6:'* || $COMMAND_OUTPUT == *'Stub Brave apply outcome:'* || \
		$COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  Guided setup continued after an unknown Wallpaper operation context\n' >&2
		return 1
	fi
}

test_guided_brave_phase_maps_success() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 0
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 0 "$COMMAND_STATUS" 'a successful Brave apply should complete Guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided phase 6: optional Brave policy' 'Guided setup should announce phase six' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub Brave apply outcome: 0' 'phase six should call apply_brave_policy' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 6 skipped:'* ]]; then
		printf '  a successful Brave apply was reported as skipped\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' 'successful phase six should complete Guided setup'
}

test_guided_brave_phase_maps_decline_to_skip() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 10
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 0 "$COMMAND_STATUS" 'Brave outcome 10 should be a successful optional skip' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub Brave apply outcome: 10' 'phase six should preserve the decline outcome' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided phase 6 skipped: Brave policy plan declined.' \
		'Guided setup should explain the declined optional phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' 'a declined optional phase should complete Guided setup'
}

test_guided_brave_phase_maps_unavailable_to_skip() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 11
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 0 "$COMMAND_STATUS" 'Brave outcome 11 should be a successful optional skip' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub Brave apply outcome: 11' 'phase six should preserve the unavailable outcome' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided phase 6 skipped: no supported Brave browser is installed.' \
		'Guided setup should explain the unavailable optional phase' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' 'an unavailable optional phase should complete Guided setup'
}

test_guided_brave_phase_stops_after_completed_recovery() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 0 BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'completed Brave recovery should stop Guided setup with a normal failure' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub Brave apply outcome: 0; context: recovery-completed' \
		'phase six should inspect completed recovery context after a successful public outcome' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Manage Brave policy in the Dotfiles wizard.' \
		'completed recovery should direct the user to the standalone Brave action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 6 skipped:'* ]]; then
		printf '  Guided setup reported completed Brave recovery as an optional skip\n' >&2
		return 1
	fi
	if [[ $COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  Guided setup completed after Brave recovery required an ordinary-operation rerun\n' >&2
		return 1
	fi
}

test_guided_brave_phase_stops_when_recovery_is_declined() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 10 BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'declined Brave recovery should stop Guided setup with a normal failure' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub Brave apply outcome: 10; context: recovery-declined' \
		'phase six should inspect declined recovery context after a declined public outcome' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Manage Brave policy in the Dotfiles wizard.' \
		'declined recovery should direct the user to the standalone Brave action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 6 skipped:'* ]]; then
		printf '  Guided setup reported declined Brave recovery as an optional skip\n' >&2
		return 1
	fi
	if [[ $COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  Guided setup completed after Brave recovery was declined\n' >&2
		return 1
	fi
}

test_guided_brave_phase_stops_on_operational_failure() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 73
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 73 "$COMMAND_STATUS" 'an untyped Brave failure should stop with its original outcome' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub Brave apply outcome: 73' 'phase six should preserve the operational failure' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Manage Brave policy in the Dotfiles wizard.' \
		'phase-six failure recovery should name the standalone Brave action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  Guided setup completed after a Brave operational failure\n' >&2
		return 1
	fi
}

test_guided_setup_phase_four_uses_arch_aware_apply_flow() {
	new_fixture
	add_package
	set_package_arch_packages demo demo-runtime
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	make_applying_stow
	stub_guided_brave_apply 11
	DOTFILES_TEST_INPUT='1\n0\n1\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'guided setup should apply a package with a missing Arch requirement' || return 1
	assert_contains "$COMMAND_OUTPUT" 'demo-runtime (required by demo): will install' \
		'guided phase 4 should show the same Arch requirement plan as standalone apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Arch packages installed and verified: demo-runtime' \
		'guided phase 4 should use the shared installation and verification path' || return 1
	assert_eq 1 "$(awk '/Apply this complete Stow plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'guided phase 4 should keep one complete Stow-plan confirmation' || return 1
	assert_eq 2 "$(awk '/^stow --no-folding --simulate .* demo$/ { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'guided phase 4 should repeat simulation after installing a requirement' || return 1
	assert_eq 1 "$(awk '/^pkg add demo-runtime[|]/ { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'guided phase 4 should install the missing requirement once' || return 1
	assert_eq "$FIXTURE_REPO/config/demo/.config/demo/config" "$(readlink -f "$FIXTURE_HOME/.config/demo/config")" \
		'guided phase 4 should finish through the normal verified Stow apply'
}

test_guided_wallpaper_failure_stops_before_brave_with_recovery() {
	new_fixture
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	stub_guided_brave_apply 0
	stub_guided_wallpaper_apply 73
	DOTFILES_TEST_INPUT='0\n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 73 "$COMMAND_STATUS" 'a wallpaper operational failure should retain its public status' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper Apply outcome: 73' \
		'Guided setup should call the shared wallpaper Apply operation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: ordinary' \
		'operational failure should retain its ordinary Wallpaper operation context' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply wallpapers in the Dotfiles wizard.' \
		'wallpaper failure should name its standalone recovery action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 6:'* || $COMMAND_OUTPUT == *'Stub Brave apply outcome:'* || \
		$COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  Guided setup continued after wallpaper deployment failed\n' >&2
		return 1
	fi
}

test_guided_setup_installs_missing_imagemagick_through_omarchy() {
	new_fixture
	mv "$FIXTURE_BIN/magick" "$FIXTURE_BIN/installed-magick"
	stub_guided_phases_after_prerequisites
	make_fake omarchy 'printf "%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "4.0.0-1\n"; exit 0; fi
if [[ $* == "pkg add imagemagick" ]]; then mv "$DOTFILES_TEST_FAKE_BIN/installed-magick" "$DOTFILES_TEST_FAKE_BIN/magick"; exit 0; fi
exit 64'
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 0 "$COMMAND_STATUS" 'guided setup should install and verify missing ImageMagick' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: install ImageMagick with omarchy pkg add imagemagick.' \
		'guided setup should include ImageMagick in its complete prerequisite plan' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Prerequisites installed and verified: GNU Stow, ImageMagick (magick), Node.js 22.20.0, npm, and npx.' \
		'guided setup should report verified ImageMagick after installation' || return 1
	assert_eq 1 "$(awk '$0 == "pkg add imagemagick" { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'guided setup should invoke the exact Omarchy ImageMagick package flow once' || return 1
	assert_eq 1 "$(awk '/Apply this complete prerequisite plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'guided setup should confirm the complete prerequisite plan once' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided phase 2: pinned global skills installation' \
		'guided setup should continue only after ImageMagick verification' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' 'guided setup should complete after verified installation'
}

test_guided_setup_stops_on_imagemagick_install_failure_with_action_recovery() {
	new_fixture
	mv "$FIXTURE_BIN/magick" "$FIXTURE_BIN/installed-magick"
	make_fake omarchy 'if [[ ${1-} == version ]]; then printf "4.0.0-1\n"; exit 0; fi
if [[ $* == "pkg add imagemagick" ]]; then exit 73; fi
exit 64'
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'a prerequisite operation failure should stop guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'ImageMagick installation failed.' 'the ImageMagick installation failure should be visible' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Prepare prerequisites in the Dotfiles wizard.' 'recovery should name a wizard action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 2:'* ]]; then
		printf '  guided setup continued after an operational failure\n' >&2
		return 1
	fi
}

test_guided_setup_stops_when_missing_imagemagick_is_declined() {
	new_fixture
	mv "$FIXTURE_BIN/magick" "$FIXTURE_BIN/installed-magick"
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='n\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'declining required prerequisites should stop guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: install ImageMagick with omarchy pkg add imagemagick.' \
		'the declined complete plan should identify missing ImageMagick' || return 1
	assert_contains "$COMMAND_OUTPUT" 'required prerequisites remain unsatisfied' 'guided setup should distinguish decline from success' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Prepare prerequisites in the Dotfiles wizard.' 'decline recovery should name the prerequisite action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 2:'* ]]; then
		printf '  guided setup continued to skills after prerequisite decline\n' >&2
		return 1
	fi
}

test_guided_setup_stops_when_imagemagick_remains_unavailable_after_installation() {
	new_fixture
	mv "$FIXTURE_BIN/magick" "$FIXTURE_BIN/installed-magick"
	make_fake omarchy 'printf "%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "4.0.0-1\n"; exit 0; fi
if [[ $* == "pkg add imagemagick" ]]; then exit 0; fi
exit 64'
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'guided setup should fail when installed ImageMagick remains unavailable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'ImageMagick command magick is still unavailable after installation.' \
		'post-install command verification should identify unavailable magick' || return 1
	assert_eq 1 "$(awk '$0 == "pkg add imagemagick" { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'post-install verification failure should follow one exact Omarchy installation call' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Prepare prerequisites in the Dotfiles wizard.' \
		'post-install verification recovery should name the standalone action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 2:'* ]]; then
		printf '  guided setup continued after ImageMagick post-install verification failed\n' >&2
		return 1
	fi
}

test_guided_bash_stow_selection_failure_reports_recovery() {
	new_fixture
	add_package
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	DOTFILES_TEST_INPUT='1\n0\n99\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'an invalid Bash Stow selection should stop guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: invalid Stow package selection: 99' 'the invalid Bash selection should be identified' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply Stow packages in the Dotfiles wizard.' 'Bash selection recovery should name the standalone action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  guided setup completed after an invalid Stow selection\n' >&2
		return 1
	fi
}

test_guided_gum_stow_cancel_reports_recovery() {
	new_fixture
	add_package
	configure_cleanup_fakes
	configure_skill_fakes
	seed_current_global_skills
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == choose && $* == *"Choose an action"* ]]; then printf "Guided setup\n"; exit 0; fi
if [[ ${1-} == choose && $* == *"Choose Stow packages"* ]]; then exit 75; fi
if [[ ${1-} == choose ]]; then exit 0; fi
if [[ ${1-} == confirm ]]; then exit 0; fi
exit 64'
	DOTFILES_UI=gum run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'a Gum Stow cancellation should stop guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Apply Stow packages in the Dotfiles wizard.' 'Gum cancellation recovery should name the standalone action'
}

test_make_targets_launch_expected_wizard_actions() {
	new_fixture
	use_empty_package_catalog
	DOTFILES_TEST_INPUT='2\n' run_make "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'default Make target should open the menu' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Packages: none' 'default Make should delegate to the selected menu action' || return 1

	configure_skill_fakes
	seed_current_global_skills
	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" make --no-print-directory -C "$FIXTURE_REPO" skills
	assert_eq 0 "$COMMAND_STATUS" 'make skills should launch its preselected action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'All manifest-owned skills already match' 'make skills should not require top-level menu selection' || return 1

	configure_skill_update_fakes
	DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE=true run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" make --no-print-directory -C "$FIXTURE_REPO" skills-update
	assert_eq 0 "$COMMAND_STATUS" 'make skills-update should launch its preselected action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No upstream skill updates are available.' 'make skills-update should not require top-level menu selection'
}

test_make_wallpapers_launches_curation_manager() {
	new_fixture
	stub_wallpaper_operations
	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		make --no-print-directory -C "$FIXTURE_REPO" wallpapers

	assert_eq 0 "$COMMAND_STATUS" 'make wallpapers should launch its preselected action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Stub wallpaper manager' \
		'make wallpapers should route through the public wallpaper action'
}

set -e
run_test test_top_level_menu_starts_with_guided_setup 'top-level menu starts with guided setup'
run_test test_entrypoint_sources_brave_before_wizard 'entrypoint sources Brave before wizard orchestration'
run_test test_entrypoint_sources_wallpapers_before_wizard 'entrypoint sources Wallpapers before wizard orchestration'
run_test test_legacy_and_invalid_entry_forms_are_rejected 'legacy and invalid entry forms are rejected'
run_test test_public_action_preselection_dispatches 'public action preselection dispatches'
run_test test_modem_public_action_preselection_dispatches 'modem public action preselection dispatches'
run_test test_modem_menu_selection_dispatches 'modem menu selection dispatches'
run_test test_brave_public_action_preselection_dispatches 'Brave public action preselection dispatches'
run_test test_wallpaper_manager_public_action_preselection_dispatches 'wallpaper manager public action preselection dispatches'
run_test test_wallpaper_deployment_public_action_preselections_dispatch 'wallpaper deployment public action preselections dispatch'
run_test test_screensaver_effects_public_action_and_make_target_dispatch 'screensaver effects public action and Make target dispatch'
run_test test_default_make_menu_dispatches_telegram_theme_management 'default Make menu dispatches Telegram theme management'
run_test test_status_and_check_standalone_actions 'status and checks remain standalone actions'
run_test test_bash_apply_standalone_uses_one_multiselect_and_dependency_order 'Bash apply resolves a multi-selection in dependency order'
run_test test_gum_apply_has_no_default_selection 'Gum apply has no default selection'
run_test test_migrate_and_remove_standalone_actions 'migration and removal remain standalone actions'
run_test test_prerequisites_verify_existing_imagemagick_without_installation 'prerequisites verify existing ImageMagick without installation'
run_test test_prerequisite_standalone_installs_complete_plan_with_supported_flows 'prerequisites install and verify one complete plan through Omarchy'
run_test test_prerequisites_upgrade_old_node 'prerequisites upgrade an old Node.js through Omarchy'
run_test test_prerequisites_reject_missing_core_tool 'prerequisites reject a missing core tool with wizard recovery'
run_test test_cleanup_skills_and_update_standalone_actions 'cleanup and skill operations remain standalone actions'
run_test test_guided_setup_orders_and_skips_nonessential_phases 'guided setup orders and skips nonessential phases'
run_test test_guided_wallpaper_ordinary_success_continues_to_brave 'guided ordinary wallpaper success continues to Brave'
run_test test_guided_wallpaper_ordinary_skips_continue_to_brave 'guided ordinary wallpaper skips continue to Brave'
run_test test_guided_wallpaper_recovery_completed_stops_before_brave 'guided completed wallpaper recovery stops before Brave'
run_test test_guided_wallpaper_unknown_context_stops_before_brave 'guided unknown wallpaper context stops before Brave'
run_test test_guided_brave_phase_maps_success 'guided Brave phase maps successful apply'
run_test test_guided_brave_phase_maps_decline_to_skip 'guided Brave phase maps decline to an optional skip'
run_test test_guided_brave_phase_maps_unavailable_to_skip 'guided Brave phase maps browser unavailability to an optional skip'
run_test test_guided_brave_phase_stops_after_completed_recovery 'guided Brave phase stops after completed recovery requires a rerun'
run_test test_guided_brave_phase_stops_when_recovery_is_declined 'guided Brave phase stops when recovery is declined'
run_test test_guided_brave_phase_stops_on_operational_failure 'guided Brave phase stops on operational failure with recovery'
run_test test_guided_setup_phase_four_uses_arch_aware_apply_flow 'guided setup phase 4 uses the Arch-aware apply flow'
run_test test_guided_wallpaper_failure_stops_before_brave_with_recovery 'guided wallpaper failure stops before Brave with recovery'
run_test test_guided_setup_installs_missing_imagemagick_through_omarchy 'guided setup installs missing ImageMagick through Omarchy'
run_test test_guided_setup_stops_on_imagemagick_install_failure_with_action_recovery 'guided setup stops on ImageMagick installation failure with wizard recovery'
run_test test_guided_setup_stops_when_missing_imagemagick_is_declined 'guided setup stops when missing ImageMagick is declined'
run_test test_guided_setup_stops_when_imagemagick_remains_unavailable_after_installation 'guided setup stops when ImageMagick remains unavailable after installation'
run_test test_guided_bash_stow_selection_failure_reports_recovery 'guided Bash Stow selection failure reports recovery'
run_test test_guided_gum_stow_cancel_reports_recovery 'guided Gum Stow cancellation reports recovery'
run_test test_make_targets_launch_expected_wizard_actions 'Make targets launch expected wizard actions'
run_test test_make_wallpapers_launches_curation_manager 'Make wallpapers launches the curation manager'
finish_tests
