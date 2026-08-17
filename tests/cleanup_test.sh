#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

test_cleanup_manifest_has_agreed_defaults() {
	new_fixture
	local expected='{"packages":["chromium","moonlight-qt"],"web_apps":["Basecamp","Discord","Figma","Fizzy","GitHub","Google Contacts","Google Messages","Google Photos","HEY","X","YouTube","Zoom"],"tuis":[]}'
	assert_eq "$expected" "$(jq -c . "$FIXTURE_REPO/cleanup.json")" 'cleanup profile should contain exactly the agreed defaults'
}

test_check_rejects_invalid_cleanup_profiles() {
	local filter expected
	while IFS='|' read -r filter expected; do
		new_fixture
		jq "$filter" "$FIXTURE_REPO/cleanup.json" >"$FIXTURE_REPO/cleanup.invalid"
		mv "$FIXTURE_REPO/cleanup.invalid" "$FIXTURE_REPO/cleanup.json"
		run_dotfiles "$FIXTURE_ROOT" check
		if [[ $COMMAND_STATUS -eq 0 || $COMMAND_OUTPUT != *"$expected"* ]]; then
			printf '  invalid cleanup profile was accepted: %s\n  output: %s\n' "$filter" "$COMMAND_OUTPUT" >&2
			return 1
		fi
	done <<'EOF'
.packages = "moonlight-qt"|invalid cleanup manifest
.packages += ["moonlight-qt"]|duplicate cleanup package
.web_apps += ["bad/name"]|invalid cleanup web app name
.tuis += [""]|invalid cleanup TUI name
.packages = ["bash"]|protected cleanup package
EOF
}

test_fallback_cleanup_selects_each_discovered_type_for_one_run() {
	new_fixture
	configure_cleanup_fakes
	add_cleanup_launcher Discord 'omarchy-launch-webapp https://discord.com'
	add_cleanup_launcher 'Extra App' 'omarchy-webapp-handler https://example.test'
	add_cleanup_launcher LazyGit 'xdg-terminal-exec --app-id=TUI.lazygit -e lazygit'
	add_cleanup_launcher Ordinary '/usr/bin/ordinary'

	DOTFILES_TEST_INPUT='9\n3\n2\n1\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'confirmed fallback cleanup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Unavailable cleanup defaults:' 'cleanup should report profile entries absent from discovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: application cleanup' 'cleanup should show one grouped plan' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  Web apps:\n    Extra App' 'plan should contain the one-run web app addition' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  TUIs:\n    LazyGit' 'plan should contain the one-run TUI addition' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  Packages:\n    optional-app' 'plan should reflect deselection of the installed package default' || return 1
	assert_contains "$(<"$CALL_LOG")" 'webapp remove Extra App|' 'web app removal should delegate to the public Omarchy route' || return 1
	assert_contains "$(<"$CALL_LOG")" 'tui remove LazyGit|' 'TUI removal should delegate to the public Omarchy route' || return 1
	assert_contains "$(<"$CALL_LOG")" 'pkg drop optional-app|' 'package removal should delegate to the public Omarchy route' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg drop base'* || $(<"$CALL_LOG") == *'pkg drop bash'* || $(<"$CALL_LOG") == *'pkg drop jq'* ]]; then
		printf '  protected packages must not be selectable\n' >&2
		return 1
	fi
}

test_cleanup_uses_home_local_launcher_directory_when_xdg_data_home_differs() {
	new_fixture
	configure_cleanup_fakes
	local custom_data=$FIXTURE_ROOT/custom-data
	add_cleanup_launcher Discord 'omarchy-launch-webapp https://discord.com'
	mkdir -p "$custom_data/applications"
	printf '[Desktop Entry]\nName=Extra App\nExec=omarchy-launch-webapp https://example.test\n' >"$custom_data/applications/Extra App.desktop"

	DOTFILES_TEST_XDG_DATA_HOME=$custom_data DOTFILES_TEST_INPUT='9\n0\n1\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'cleanup should use Omarchy HOME-local launcher discovery' || return 1
	assert_contains "$COMMAND_OUTPUT" $'  Web apps:\n    Discord' 'HOME-local Omarchy launcher should be selected' || return 1
	if [[ $COMMAND_OUTPUT == *'Extra App'* ]]; then
		printf '  custom XDG_DATA_HOME launcher must not be discovered\n' >&2
		return 1
	fi
	[[ ! -e "$FIXTURE_HOME/.local/share/applications/Discord.desktop" ]] || {
		printf '  selected HOME-local launcher should be removed\n' >&2
		return 1
	}
	[[ -e "$custom_data/applications/Extra App.desktop" ]] || {
		printf '  custom XDG_DATA_HOME launcher should remain untouched\n' >&2
		return 1
	}
}

test_cleanup_empty_selection_is_a_no_op() {
	new_fixture
	configure_cleanup_fakes
	DOTFILES_TEST_INPUT='9\n0\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'empty cleanup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No cleanup items selected; no changes made.' 'empty cleanup should explain its no-op result' || return 1
	if [[ $(<"$CALL_LOG") == *'webapp remove '* || $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  empty cleanup must not invoke mutation commands\n' >&2
		return 1
	fi
}

test_cleanup_hides_critical_packages() {
	new_fixture
	configure_cleanup_fakes
	printf '%s\n' base base-devel filesystem glibc amd-ucode intel-ucode linux linux-firmware linux-hardened linux-lts linux-zen networkmanager systemd sudo bash pacman omarchy yay optional-app >"$FIXTURE_ROOT/explicit-packages"
	cp "$FIXTURE_ROOT/explicit-packages" "$FIXTURE_ROOT/installed-packages"
	DOTFILES_TEST_INPUT='9\n0\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'cleanup with protected package fixtures should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" '1. [ ] optional-app' 'an ordinary explicit package should remain selectable' || return 1
	local protected
	for protected in base base-devel filesystem glibc amd-ucode intel-ucode linux linux-firmware linux-hardened linux-lts linux-zen networkmanager systemd sudo bash pacman omarchy yay; do
		if [[ $COMMAND_OUTPUT == *'] '"$protected"* ]]; then
			printf '  critical package appeared as a selection: %s\n' "$protected" >&2
			return 1
		fi
	done
}

test_cleanup_hides_runtime_provider_packages() {
	new_fixture
	configure_cleanup_fakes
	printf '%s\n' coreutils findutils grep jq gum optional-app >"$FIXTURE_ROOT/explicit-packages"
	cp "$FIXTURE_ROOT/explicit-packages" "$FIXTURE_ROOT/installed-packages"
	DOTFILES_TEST_INPUT='9\n0\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'cleanup with runtime provider fixtures should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" '1. [ ] optional-app' 'an ordinary package should remain selectable beside runtime providers' || return 1
	local protected
	for protected in coreutils findutils grep jq gum; do
		if [[ $COMMAND_OUTPUT == *'] '"$protected"* ]]; then
			printf '  runtime provider appeared as a selection: %s\n' "$protected" >&2
			return 1
		fi
	done
}

test_cleanup_decline_makes_no_mutation() {
	new_fixture
	configure_cleanup_fakes
	DOTFILES_TEST_INPUT='9\n1\nn\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'declining a nonempty cleanup plan should succeed without changes' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: application cleanup' 'decline should happen after the complete plan' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No changes made.' 'decline should report the no-op result' || return 1
	if [[ $(<"$CALL_LOG") == *'webapp remove '* || $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  declined cleanup must not invoke mutation commands\n' >&2
		return 1
	fi
}

test_cleanup_uses_one_plan_confirmation() {
	new_fixture
	configure_cleanup_fakes
	local responses=$FIXTURE_ROOT/gum-responses
	printf 'Clean up Omarchy applications\nmoonlight-qt\n' >"$responses"
	make_gum_responder
	DOTFILES_UI=gum DOTFILES_TEST_GUM_RESPONSES=$responses run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'confirmed cleanup should succeed' || return 1
	assert_eq 1 "$(awk '/^gum confirm Apply this complete cleanup plan[?]$/ { count++ } END { print count + 0 }' "$CALL_LOG")" 'normal cleanup should request exactly one plan confirmation'
}

test_cleanup_propagates_gum_selection_failure_before_mutation() {
	new_fixture
	configure_cleanup_fakes
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == choose && $* == *"Choose an action"* ]]; then printf "Clean up Omarchy applications\n"; exit 0; fi
if [[ ${1-} == choose ]]; then exit 75; fi
if [[ ${1-} == confirm ]]; then exit 0; fi
exit 64'

	DOTFILES_UI=gum run_dotfiles "$FIXTURE_ROOT"

	assert_eq 75 "$COMMAND_STATUS" 'Gum selection failure should propagate its status' || return 1
	if [[ $(<"$CALL_LOG") == *'webapp remove '* || $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  Gum selection failure must stop before mutation\n' >&2
		return 1
	fi
}

test_cleanup_accepts_successful_empty_gum_selection() {
	new_fixture
	configure_cleanup_fakes
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == choose && $* == *"Choose an action"* ]]; then printf "Clean up Omarchy applications\n"; exit 0; fi
if [[ ${1-} == choose ]]; then exit 0; fi
if [[ ${1-} == confirm ]]; then exit 0; fi
exit 64'

	DOTFILES_UI=gum run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'successful empty Gum selection should be a valid no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No cleanup items selected; no changes made.' 'successful empty Gum selection should report no-op' || return 1
	if [[ $(<"$CALL_LOG") == *'webapp remove '* || $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  successful empty Gum selection must not mutate\n' >&2
		return 1
	fi
}

test_cleanup_declines_omarchy_mismatch_before_mutation() {
	new_fixture
	configure_cleanup_fakes
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='9\n1\ny\nn\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'declined Omarchy mismatch should stop cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'cleanup should report supported Omarchy before mismatch approval' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'cleanup should report detected Omarchy before mismatch approval' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Continue despite the Omarchy version mismatch? [y/N]' 'cleanup should require distinct mismatch approval' || return 1
	if [[ $(<"$CALL_LOG") == *'webapp remove '* || $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  declined mismatch must stop before mutation\n' >&2
		return 1
	fi
}

test_cleanup_accepts_omarchy_mismatch_before_mutation() {
	new_fixture
	configure_cleanup_fakes
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='9\n1\ny\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'accepted Omarchy mismatch should permit cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'accepted mismatch should report supported Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'accepted mismatch should report detected Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified package: chromium' 'accepted mismatch should complete cleanup' || return 1
	assert_eq 1 "$(awk '/Apply this complete cleanup plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" 'accepted mismatch should retain one normal plan confirmation' || return 1
	assert_eq 1 "$(awk '/Continue despite the Omarchy version mismatch[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" 'accepted mismatch should require one distinct mismatch confirmation'
}

test_cleanup_package_delegation_failure_stops_later_packages() {
	new_fixture
	configure_cleanup_fakes
	printf '%s\n' alpha beta gamma >"$FIXTURE_ROOT/explicit-packages"
	cp "$FIXTURE_ROOT/explicit-packages" "$FIXTURE_ROOT/installed-packages"
	make_fake omarchy 'printf "%s|HOME=%s|XDG_CONFIG_HOME=%s|XDG_STATE_HOME=%s|XDG_CACHE_HOME=%s\n" "$*" "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "%s\n" "${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"; exit 0; fi
if [[ ${1-} == pkg && ${2-} == drop && ${3-} == alpha ]]; then grep -Fvx alpha "$DOTFILES_TEST_INSTALLED_PACKAGES" >"$DOTFILES_TEST_INSTALLED_PACKAGES.next"; mv "$DOTFILES_TEST_INSTALLED_PACKAGES.next" "$DOTFILES_TEST_INSTALLED_PACKAGES"; exit 0; fi
if [[ ${1-} == pkg && ${2-} == drop && ${3-} == beta ]]; then exit 73; fi
exit 64'
	DOTFILES_TEST_INPUT='9\n1,2,3\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'package delegation failure should fail cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified package: alpha' 'an earlier package success should be preserved' || return 1
	assert_contains "$(<"$CALL_LOG")" 'pkg drop beta|' 'cleanup should attempt the failing package' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg drop gamma|' ]]; then
		printf '  package command failure must stop later packages\n' >&2
		return 1
	fi
	grep -Fxq beta "$FIXTURE_ROOT/installed-packages" && grep -Fxq gamma "$FIXTURE_ROOT/installed-packages"
}

test_cleanup_package_verification_failure_stops_later_packages() {
	new_fixture
	configure_cleanup_fakes
	printf '%s\n' alpha beta >"$FIXTURE_ROOT/explicit-packages"
	cp "$FIXTURE_ROOT/explicit-packages" "$FIXTURE_ROOT/installed-packages"
	make_fake omarchy 'printf "%s|HOME=%s|XDG_CONFIG_HOME=%s|XDG_STATE_HOME=%s|XDG_CACHE_HOME=%s\n" "$*" "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "%s\n" "${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"; exit 0; fi
if [[ ${1-} == pkg && ${2-} == drop ]]; then exit 0; fi
exit 64'
	DOTFILES_TEST_INPUT='9\n1,2\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'package absence-verification failure should fail cleanup' || return 1
	assert_contains "$(<"$CALL_LOG")" 'pkg drop alpha|' 'cleanup should delegate the first package' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg drop beta|' ]]; then
		printf '  package verification failure must stop later packages\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Package: alpha' 'failure report should include the package that remained installed'
}

test_cleanup_pacman_verification_query_failure_stops_later_packages() {
	new_fixture
	configure_cleanup_fakes
	printf '%s\n' alpha beta >"$FIXTURE_ROOT/explicit-packages"
	cp "$FIXTURE_ROOT/explicit-packages" "$FIXTURE_ROOT/installed-packages"
	DOTFILES_TEST_PACMAN_VERIFY_FAILURE=true DOTFILES_TEST_INPUT='9\n1,2\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'pacman verification-query failure should fail cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: could not query installed packages while verifying alpha.' 'cleanup should distinguish query failure from package absence' || return 1
	assert_contains "$(<"$CALL_LOG")" 'pkg drop alpha|' 'cleanup should delegate the first selected package' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg drop beta|' ]]; then
		printf '  pacman verification-query failure must stop later packages\n' >&2
		return 1
	fi
}

test_cleanup_launcher_discovery_propagates_find_failure() {
	new_fixture
	configure_cleanup_fakes
	mkdir -p "$FIXTURE_HOME/.local/share/applications"
	make_fake find 'printf "find %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exit 72'
	DOTFILES_TEST_INPUT='9\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'launcher discovery find failure should fail cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: could not discover Omarchy web app launchers.' 'cleanup should report launcher discovery failure' || return 1
	if [[ $(<"$CALL_LOG") == *'webapp remove '* || $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  launcher discovery failure must stop before mutation\n' >&2
		return 1
	fi
	assert_eq '' "$(/usr/bin/find "$FIXTURE_TMP" -mindepth 1 -print -quit)" 'discovery failure should clean temporary files'
}

test_cleanup_launcher_verification_propagates_find_failure() {
	new_fixture
	configure_cleanup_fakes
	add_cleanup_launcher Discord 'omarchy-launch-webapp https://discord.com'
	local find_count=$FIXTURE_ROOT/find-count
	printf '0\n' >"$find_count"
	make_fake find 'count=$(<"$DOTFILES_TEST_FIND_COUNT")
count=$((count + 1))
printf "%s\n" "$count" >"$DOTFILES_TEST_FIND_COUNT"
printf "find %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if (( count == 3 )); then exit 72; fi
exec /usr/bin/find "$@"'
	DOTFILES_TEST_FIND_COUNT=$find_count DOTFILES_TEST_INPUT='9\n1\n1\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'post-removal find failure should fail cleanup verification' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: could not inspect Omarchy launchers while verifying Discord.' 'cleanup should report verification discovery failure' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  launcher verification failure must stop later package mutation\n' >&2
		return 1
	fi
	assert_eq '' "$(/usr/bin/find "$FIXTURE_TMP" -mindepth 1 -print -quit)" 'verification failure should clean temporary files'
}

test_cleanup_rerun_with_absent_defaults_is_a_no_op() {
	new_fixture
	configure_cleanup_fakes
	: >"$FIXTURE_ROOT/explicit-packages"
	: >"$FIXTURE_ROOT/installed-packages"
	local profile_before
	profile_before=$(sha256sum "$FIXTURE_REPO/cleanup.json")

	DOTFILES_TEST_INPUT='9\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'first cleanup with absent defaults should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Unavailable cleanup defaults:' 'first cleanup should report absent defaults' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No cleanup items selected; no changes made.' 'first cleanup should be a no-op' || return 1
	DOTFILES_TEST_INPUT='9\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'repeated cleanup with absent defaults should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Unavailable cleanup defaults:' 'repeated cleanup should continue reporting absent defaults' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No cleanup items selected; no changes made.' 'repeated cleanup should remain a no-op' || return 1
	assert_eq "$profile_before" "$(sha256sum "$FIXTURE_REPO/cleanup.json")" 'rerun should not rewrite or suppress profile defaults' || return 1
	if [[ $(<"$CALL_LOG") == *'webapp remove '* || $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  absent defaults must not be restored or passed to mutation commands\n' >&2
		return 1
	fi
}

test_cleanup_stops_when_package_discovery_fails() {
	new_fixture
	configure_cleanup_fakes
	make_fake yay 'printf "yay %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
exit 72'
	DOTFILES_TEST_INPUT='9\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'failed explicit-package discovery should fail cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: could not discover explicitly installed packages with yay -Qqe.' 'cleanup should identify its failed discovery source' || return 1
	if [[ $(<"$CALL_LOG") == *'webapp remove '* || $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  discovery failure must stop before mutation\n' >&2
		return 1
	fi
}

test_gum_cleanup_preselects_installed_defaults_and_allows_overrides() {
	new_fixture
	configure_cleanup_fakes
	add_cleanup_launcher Discord 'omarchy-launch-webapp https://discord.com'
	add_cleanup_launcher 'Extra App' 'omarchy-webapp-handler https://example.test'
	add_cleanup_launcher LazyGit '$TERMINAL --title=lazygit -e lazygit'
	local responses=$FIXTURE_ROOT/gum-responses
	printf 'Clean up Omarchy applications\noptional-app\nExtra App\nLazyGit\n' >"$responses"
	make_gum_responder

	DOTFILES_UI=gum DOTFILES_TEST_GUM_RESPONSES=$responses run_dotfiles "$FIXTURE_ROOT"

	assert_eq 0 "$COMMAND_STATUS" 'Gum cleanup should succeed' || return 1
	local calls
	calls=$(<"$CALL_LOG")
	assert_contains "$calls" '--selected=chromium,moonlight-qt' 'Gum should preselect both installed package defaults' || return 1
	assert_contains "$calls" '--selected=Discord' 'Gum should preselect the installed web app default' || return 1
	assert_contains "$calls" 'pkg drop optional-app|' 'Gum selection should permit a one-run package override'
}

test_cleanup_stops_on_first_failure_and_reports_recovery() {
	new_fixture
	configure_cleanup_fakes
	add_cleanup_launcher Discord 'omarchy-launch-webapp https://discord.com'
	add_cleanup_launcher LazyGit 'xdg-terminal-exec --app-id=TUI.lazygit -e lazygit'
	make_fake omarchy 'printf "%s|HOME=%s|XDG_CONFIG_HOME=%s|XDG_STATE_HOME=%s|XDG_CACHE_HOME=%s\n" "$*" "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "%s\n" "${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"; exit 0; fi
if [[ ${1-} == webapp && ${2-} == remove ]]; then exit 73; fi
exit 64'

	DOTFILES_TEST_INPUT='9\n1\n1\n1\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'delegated cleanup failure should fail the action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Cleanup incomplete items:' 'failure should report unfinished work' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: rerun the Dotfiles wizard and choose Clean up Omarchy applications.' 'failure should provide wizard-based recovery' || return 1
	if [[ $(<"$CALL_LOG") == *'tui remove '* || $(<"$CALL_LOG") == *'pkg drop '* ]]; then
		printf '  cleanup must stop before later groups after the first failure\n' >&2
		return 1
	fi
}

test_cleanup_preserves_success_before_later_verification_failure() {
	new_fixture
	configure_cleanup_fakes
	add_cleanup_launcher 'Another App' 'omarchy-launch-webapp https://another.test'
	add_cleanup_launcher Discord 'omarchy-launch-webapp https://discord.com'
	make_fake omarchy 'printf "%s|HOME=%s|XDG_CONFIG_HOME=%s|XDG_STATE_HOME=%s|XDG_CACHE_HOME=%s\n" "$*" "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == version ]]; then printf "%s\n" "${DOTFILES_TEST_OMARCHY_VERSION:-4.0.0-1}"; exit 0; fi
if [[ ${1-} == webapp && ${2-} == remove && ${*:3} == "Another App" ]]; then rm -f "$HOME/.local/share/applications/Another App.desktop"; exit 0; fi
if [[ ${1-} == webapp && ${2-} == remove ]]; then exit 0; fi
exit 64'

	DOTFILES_TEST_INPUT='9\n0\n1,2\ny\n' run_dotfiles "$FIXTURE_ROOT"

	assert_eq 1 "$COMMAND_STATUS" 'remaining launcher after delegated success should fail verification' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified web app: Another App' 'cleanup should preserve and report the earlier success' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Web app: Discord' 'cleanup should report the item that failed absence verification' || return 1
	[[ ! -e "$FIXTURE_HOME/.local/share/applications/Another App.desktop" ]] || {
		printf '  earlier successful removal should remain applied\n' >&2
		return 1
	}
	[[ -e "$FIXTURE_HOME/.local/share/applications/Discord.desktop" ]] || {
		printf '  verification fixture should retain the failed launcher\n' >&2
		return 1
	}
}

set -e
run_test test_cleanup_manifest_has_agreed_defaults 'cleanup manifest has agreed defaults'
run_test test_check_rejects_invalid_cleanup_profiles 'check rejects invalid cleanup profiles'
run_test test_fallback_cleanup_selects_each_discovered_type_for_one_run 'fallback cleanup discovers, overrides, delegates, and verifies'
run_test test_cleanup_uses_home_local_launcher_directory_when_xdg_data_home_differs 'cleanup uses HOME-local launcher directory despite XDG_DATA_HOME'
run_test test_cleanup_empty_selection_is_a_no_op 'cleanup empty selection is a no-op'
run_test test_cleanup_hides_critical_packages 'cleanup hides critical packages'
run_test test_cleanup_hides_runtime_provider_packages 'cleanup hides runtime provider packages'
run_test test_cleanup_decline_makes_no_mutation 'cleanup decline makes no mutation'
run_test test_cleanup_uses_one_plan_confirmation 'cleanup uses one plan confirmation'
run_test test_cleanup_propagates_gum_selection_failure_before_mutation 'cleanup propagates Gum selection failure before mutation'
run_test test_cleanup_accepts_successful_empty_gum_selection 'cleanup accepts successful empty Gum selection'
run_test test_cleanup_declines_omarchy_mismatch_before_mutation 'cleanup declines Omarchy mismatch before mutation'
run_test test_cleanup_accepts_omarchy_mismatch_before_mutation 'cleanup accepts Omarchy mismatch before mutation'
run_test test_cleanup_package_delegation_failure_stops_later_packages 'package delegation failure stops later packages'
run_test test_cleanup_package_verification_failure_stops_later_packages 'package verification failure stops later packages'
run_test test_cleanup_pacman_verification_query_failure_stops_later_packages 'pacman verification-query failure stops later packages'
run_test test_cleanup_launcher_discovery_propagates_find_failure 'launcher discovery propagates find failure'
run_test test_cleanup_launcher_verification_propagates_find_failure 'launcher verification propagates find failure'
run_test test_cleanup_rerun_with_absent_defaults_is_a_no_op 'cleanup rerun with absent defaults is a no-op'
run_test test_cleanup_stops_when_package_discovery_fails 'cleanup stops when package discovery fails'
run_test test_gum_cleanup_preselects_installed_defaults_and_allows_overrides 'Gum cleanup preselects defaults and allows overrides'
run_test test_cleanup_stops_on_first_failure_and_reports_recovery 'cleanup stops on first failure and reports recovery'
run_test test_cleanup_preserves_success_before_later_verification_failure 'cleanup preserves success before later verification failure'
finish_tests
