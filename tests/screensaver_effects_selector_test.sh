#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

HOST_SOCAT=$(command -v socat)

setup_selector_fixture() {
	new_fixture || return 1
	SELECTOR_ENV=()
	SELECTOR_PACKAGE=$FIXTURE_REPO/config/screensaver-effects
	SELECTOR_SOURCE=$SELECTOR_PACKAGE/.config/dotfiles/screensaver-effects.json
	SELECTOR=$SELECTOR_PACKAGE/.local/libexec/dotfiles/screensaver-effects-selector
	SELECTOR_ACTIONS=$FIXTURE_ROOT/selector-actions
	mkdir -p "$FIXTURE_CONFIG/dotfiles" "$FIXTURE_HOME/.config/dotfiles"
	ln -s "$SELECTOR_SOURCE" "$FIXTURE_CONFIG/dotfiles/screensaver-effects.json"

	make_fake ttfx '
case ${1-} in
	--version) printf "ttfx %s\n" "${DOTFILES_TEST_TTFX_VERSION:-0.3.2}" ;;
	--help) cat <<"HELP"
Terminal text effects

Usage: ttfx [OPTIONS] [COMMAND]

Commands:
  beams  Beams
  matrix  Matrix
  sweep  Sweep
HELP
		if [[ -n ${DOTFILES_TEST_TTFX_EXTRA_EFFECT:-} ]]; then
			printf "  %s  Added effect\n" "$DOTFILES_TEST_TTFX_EXTRA_EFFECT"
		fi
		cat <<"HELP"
  help  Print help

Options:
  -h, --help
HELP
		;;
	*) exit 64 ;;
esac'
	make_fake omarchy '
if [[ ${1-} == version ]]; then printf "4.0.1-1\n"
elif [[ ${1-} == theme && ${2-} == color ]]; then printf "#112233\n"
else exit 64
fi'
}

run_selector_fixture() {
	local status
	set +e
	COMMAND_OUTPUT=$(env -i \
		HOME="$FIXTURE_HOME" \
		XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
		XDG_STATE_HOME="$FIXTURE_STATE" \
		XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" \
		DOTFILES_SCREENSAVER_TEST=1 \
		DOTFILES_SCREENSAVER_TEST_ACTIONS="$SELECTOR_ACTIONS" \
		"${SELECTOR_ENV[@]}" \
		"$SELECTOR" 2>&1)
	status=$?
	set -e
	COMMAND_STATUS=$status
}

configure_preview_process_fakes() {
	make_fake ttfx '
case ${1-} in
	--version) printf "ttfx 0.3.2\n"; exit 0 ;;
	--help) printf "Commands:\n  beams  Beams\n  matrix  Matrix\n  sweep  Sweep\n  help  Print help\n\nOptions:\n"; exit 0 ;;
esac
printf "owned-effect|%s|%s|%s\n" "$DOTFILES_SCREENSAVER_ATTEMPT_ID" "$$" "$PPID" >>"$DOTFILES_TEST_CALL_LOG"
exec /usr/bin/sleep 30'
	make_fake pgrep 'exit 1'
	make_fake socat '
process_dir=
for _ in {1..250}; do
	for candidate in "$XDG_RUNTIME_DIR"/dotfiles-screensaver-preview.*/dispatch-0; do
		if [[ -f $candidate/identity ]]; then process_dir=$candidate; break 2; fi
	done
	sleep 0.02
done
[[ -n $process_dir ]] || exit 1
identity=$(<"$process_dir/identity")
for _ in {1..250}; do [[ -f $process_dir/effect.pid ]] && break; sleep 0.02; done
[[ -f $process_dir/effect.pid ]] || exit 1
printf "openwindow>>deadbeef,1,org.omarchy.screensaver,foreign-attempt\n"
if [[ $DOTFILES_TEST_PREVIEW_EVENTS == owned ]]; then
	printf "openwindow>>c0ffee,1,org.omarchy.screensaver,%s\n" "$identity"
fi'
	make_fake xdg-terminal-exec '[[ ${1-} == --print-id ]] && printf "Alacritty.desktop\n"'
	make_fake omarchy-hyprland-monitor-focused 'printf "eDP-1\n"'
	make_fake alacritty '
while (($# > 0)); do
	if [[ $1 == -e ]]; then shift; exec "$@"; fi
	shift
done
exit 64'
	make_fake omarchy-screensaver '
trap '\''printf "runner-trap|%s|%s\n" "$DOTFILES_SCREENSAVER_ATTEMPT_ID" "$$" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'\'' HUP INT QUIT TERM
printf "owned-runner|%s|%s\n" "$DOTFILES_SCREENSAVER_ATTEMPT_ID" "$$" >>"$DOTFILES_TEST_CALL_LOG"
while :; do
	ttfx -i "$HOME/.config/omarchy/branding/screensaver.txt" \
		--frame-rate 120 --canvas-width 0 --canvas-height 0 --reuse-canvas \
		--anchor-canvas c --anchor-text c --random-effect --no-eol --no-restore-cursor &
	wait "$!" || true
done'
	make_fake hyprctl '
printf "hyprctl|%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == dispatch && ${2-} == hl.dsp.exec_cmd* ]]; then exit 1; fi
if [[ ${1-} == dispatch && ${2-} == exec ]]; then
	bash -c "${6-}" >/dev/null 2>&1 &
	exit 0
fi
exit 0'
}

start_preview_event_socket() {
	local socket_dir=$FIXTURE_RUNTIME/hypr/test-signature socket
	mkdir -p "$socket_dir"
	socket=$socket_dir/.socket2.sock
	"$HOST_SOCAT" "UNIX-LISTEN:$socket,fork" EXEC:/usr/bin/true >/dev/null 2>&1 &
	PREVIEW_SOCKET_LISTENER=$!
	for _ in {1..50}; do [[ -S $socket ]] && return 0; sleep 0.02; done
	kill "$PREVIEW_SOCKET_LISTENER" 2>/dev/null || true
	wait "$PREVIEW_SOCKET_LISTENER" 2>/dev/null || true
	printf '  could not create fixture Hyprland event socket\n' >&2
	return 1
}

test_selector_saves_canonical_source_and_preserves_the_deployed_symlink() {
	setup_selector_fixture || return 1
	printf 'change beams matrix\nsave\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture

	assert_eq 0 "$COMMAND_STATUS" 'a valid changed selection should save' || return 1
	assert_eq $'[\n  "beams",\n  "matrix"\n]' "$(<"$SELECTOR_SOURCE")" \
		'the selector should save two-space lexical JSON with one final newline' || return 1
	assert_eq 644 "$(stat -c %a -- "$SELECTOR_SOURCE")" \
		'the atomic save should preserve the tracked source mode' || return 1
	if [[ ! -L $FIXTURE_CONFIG/dotfiles/screensaver-effects.json ]]; then
		printf '  selector replaced the deployed Stow leaf\n' >&2
		return 1
	fi
	assert_eq "$SELECTOR_SOURCE" "$(readlink -f -- "$FIXTURE_CONFIG/dotfiles/screensaver-effects.json")" \
		'the deployed leaf should still resolve to the repository source'
}

test_selector_noop_and_empty_pending_do_not_rewrite_the_source() {
	setup_selector_fixture || return 1
	local original_inode original_hash
	original_inode=$(stat -c %i -- "$SELECTOR_SOURCE")
	original_hash=$(sha256sum "$SELECTOR_SOURCE")
	printf 'save\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'an unchanged Save should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No changes; tracked source was not rewritten.' \
		'an unchanged Save should report its no-op' || return 1
	assert_eq "$original_inode" "$(stat -c %i -- "$SELECTOR_SOURCE")" \
		'an unchanged Save should preserve the source inode' || return 1

	printf 'change\nsave\ncancel\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'Cancel should remain available after an empty Save attempt' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Save unavailable: select at least one mapped effect' \
		'an empty pending set should not be savable' || return 1
	assert_eq "$original_hash" "$(sha256sum "$SELECTOR_SOURCE")" \
		'an empty pending set should not rewrite the tracked source'
}

test_selector_acknowledges_partial_changes_and_previews_without_losing_pending_state() {
	setup_selector_fixture || return 1
	SELECTOR_ENV=(DOTFILES_SCREENSAVER_TEST_PARTIAL_RESPONSE=no)
	printf 'change beams sweep\npreview sweep\nsave\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'declining Partial actions should leave valid Full changes savable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Partial additions declined and excluded from pending selection.' \
		'new Partial effects should require one aggregate acknowledgement' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Partial preview declined; pending selection is unchanged.' \
		'each Partial preview should require its own acknowledgement' || return 1
	assert_eq $'[\n  "beams"\n]' "$(<"$SELECTOR_SOURCE")" \
		'declined Partial effects should not enter the saved allowlist'
}

test_selector_keeps_pending_changes_after_preview_failure() {
	setup_selector_fixture || return 1
	SELECTOR_ENV=(DOTFILES_SCREENSAVER_TEST_PREVIEW=fail)
	printf 'change beams matrix\npreview matrix\nsave\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'a foreground preview failure should return to the manager' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Preview failed: controlled test failure; pending selection is unchanged.' \
		'preview failure should be reported in the foreground' || return 1
	assert_eq $'[\n  "beams",\n  "matrix"\n]' "$(<"$SELECTOR_SOURCE")" \
		'pending changes should remain available to Save after preview failure'
}

test_selector_repairs_invalid_entries_and_warns_without_version_lockout() {
	setup_selector_fixture || return 1
	printf '[\n  "missing"\n]\n' >"$SELECTOR_SOURCE"
	SELECTOR_ENV=(DOTFILES_TEST_TTFX_VERSION=0.4.0 DOTFILES_TEST_TTFX_EXTRA_EFFECT=novel)
	printf 'save\nchange matrix novel\nchange matrix\nsave\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'repair should remain available on an untested ttfx version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Warning: ttfx version mismatch' \
		'an untested ttfx version should be an informational warning' || return 1
	assert_contains "$COMMAND_OUTPUT" 'REPAIR MODE' \
		'an existing unavailable entry should be shown explicitly' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Change rejected: novel is Unavailable or Unmapped.' \
		'a newly discovered Unmapped effect should remain excluded' || return 1
	assert_eq $'[\n  "matrix"\n]' "$(<"$SELECTOR_SOURCE")" \
		'explicit repair should publish a valid mapped allowlist'
}

test_selector_supports_gum_and_bash_multiselect_paths() {
	setup_selector_fixture || return 1
	make_fake gum 'if [[ ${1-} == choose && ${2-} == --no-limit ]]; then printf "beams\nmatrix\n"; exit 0; fi; exit 64'
	SELECTOR_ENV=(DOTFILES_SCREENSAVER_TEST_PICKER=gum)
	printf 'change\nsave\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'the Gum multiselect path should save its choices' || return 1
	assert_eq $'[\n  "beams",\n  "matrix"\n]' "$(<"$SELECTOR_SOURCE")" \
		'the Gum choices should become the canonical allowlist' || return 1

	setup_selector_fixture || return 1
	SELECTOR_ENV=(DOTFILES_SCREENSAVER_TEST_PICKER=bash DOTFILES_SCREENSAVER_TEST_BASH_SELECTION='1 2')
	printf 'change\nsave\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'the numbered Bash multiselect path should save its choices' || return 1
	assert_eq $'[\n  "beams",\n  "matrix"\n]' "$(<"$SELECTOR_SOURCE")" \
		'the numbered Bash choices should become the canonical allowlist'
}

test_selector_rejects_regular_and_foreign_deployed_leaves_and_public_non_tty_use() {
	setup_selector_fixture || return 1
	rm -- "$FIXTURE_CONFIG/dotfiles/screensaver-effects.json"
	printf 'foreign\n' >"$FIXTURE_CONFIG/dotfiles/screensaver-effects.json"
	local original_hash
	original_hash=$(sha256sum "$SELECTOR_SOURCE")
	printf 'change beams\nsave\ncancel\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'the manager should permit Cancel after leaf validation fails' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Save failed: deployed leaf is not a symlink' \
		'a foreign deployed leaf should block Save' || return 1
	assert_eq "$original_hash" "$(sha256sum "$SELECTOR_SOURCE")" \
		'a blocked Save should preserve the tracked source' || return 1

	setup_selector_fixture || return 1
	local foreign=$FIXTURE_ROOT/foreign-allowlist.json
	printf '[\n  "matrix"\n]\n' >"$foreign"
	rm -- "$FIXTURE_CONFIG/dotfiles/screensaver-effects.json"
	ln -s "$foreign" "$FIXTURE_CONFIG/dotfiles/screensaver-effects.json"
	original_hash=$(sha256sum "$SELECTOR_SOURCE")
	printf 'change beams\nsave\ncancel\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'the manager should permit Cancel after foreign-link validation fails' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Save failed: deployed leaf does not resolve to the tracked source' \
		'a foreign deployed symlink should block Save' || return 1
	assert_eq "$original_hash" "$(sha256sum "$SELECTOR_SOURCE")" \
		'a foreign-link rejection should preserve the tracked source' || return 1

	set +e
	COMMAND_OUTPUT=$(env -i HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" "$SELECTOR" 2>&1)
	COMMAND_STATUS=$?
	set -e
	assert_eq 2 "$COMMAND_STATUS" 'public non-TTY use should fail' || return 1
	assert_contains "$COMMAND_OUTPUT" 'stdin and stdout must be terminals' \
		'public non-TTY rejection should explain the required route'
}

test_preview_cleanup_closes_only_its_recorded_window_and_preserves_unrelated_processes() {
	setup_selector_fixture || return 1
	local unrelated_ttfx unrelated_screensaver failed=0 role identity pid shim_pid
	start_preview_event_socket || return 1
	configure_preview_process_fakes
	cp /usr/bin/sleep "$FIXTURE_ROOT/ttfx"
	"$FIXTURE_ROOT/ttfx" 30 &
	unrelated_ttfx=$!
	bash -c 'exec -a org.omarchy.screensaver /usr/bin/sleep 30' &
	unrelated_screensaver=$!
	SELECTOR_ENV=(
		DOTFILES_SCREENSAVER_TEST_PREVIEW_LIFECYCLE=1
		DOTFILES_TEST_PREVIEW_EVENTS=owned
		DOTFILES_TEST_CALL_LOG="$CALL_LOG"
		HYPRLAND_INSTANCE_SIGNATURE=test-signature
		OMARCHY_PATH="$FIXTURE_OMARCHY"
	)
	printf 'preview matrix\ncancel\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'a scoped preview cleanup failure should return to Cancel' || failed=1
	assert_contains "$COMMAND_OUTPUT" 'event stream ended before dismissal' \
		'the focused preview should wait for its recorded close event' || failed=1
	assert_contains "$(<"$CALL_LOG")" 'dispatch closewindow address:0xc0ffee' \
		'preview cleanup should close the exact recorded preview window' || failed=1
	if [[ $(<"$CALL_LOG") == *'address:0xdeadbeef'* ]]; then
		printf '  preview cleanup targeted a foreign same-class event address\n' >&2
		failed=1
	fi
	while IFS='|' read -r role identity pid shim_pid; do
		case $role in
		owned-runner)
			if kill -0 "$pid" 2>/dev/null; then
				printf '  failed preview left its owned runner alive\n' >&2
				failed=1
			fi
			;;
		owned-effect)
			if kill -0 "$pid" 2>/dev/null || kill -0 "$shim_pid" 2>/dev/null; then
				printf '  failed preview left its owned shim/effect tree alive\n' >&2
				failed=1
			fi
			;;
		runner-trap)
			printf '  failed preview invoked the stock runner signal trap\n' >&2
			failed=1
			;;
		esac
	done <"$CALL_LOG"
	if ! kill -0 "$unrelated_ttfx" 2>/dev/null; then
		printf '  preview cleanup killed an unrelated ttfx process\n' >&2
		failed=1
	fi
	if ! kill -0 "$unrelated_screensaver" 2>/dev/null; then
		printf '  preview cleanup killed an unrelated screensaver process\n' >&2
		failed=1
	fi
	kill "$unrelated_ttfx" "$unrelated_screensaver" "$PREVIEW_SOCKET_LISTENER" 2>/dev/null || true
	wait "$unrelated_ttfx" "$unrelated_screensaver" "$PREVIEW_SOCKET_LISTENER" 2>/dev/null || true
	return "$failed"
}

test_preview_map_timeout_stops_only_its_owned_process_tree() {
	setup_selector_fixture || return 1
	local unrelated_ttfx unrelated_screensaver failed=0 role identity pid shim_pid owned_count=0
	start_preview_event_socket || return 1
	configure_preview_process_fakes
	cp /usr/bin/sleep "$FIXTURE_ROOT/ttfx"
	"$FIXTURE_ROOT/ttfx" 30 &
	unrelated_ttfx=$!
	bash -c 'exec -a org.omarchy.screensaver /usr/bin/sleep 30' &
	unrelated_screensaver=$!
	SELECTOR_ENV=(
		DOTFILES_SCREENSAVER_TEST_PREVIEW_LIFECYCLE=1
		DOTFILES_TEST_PREVIEW_EVENTS=timeout
		DOTFILES_TEST_CALL_LOG="$CALL_LOG"
		HYPRLAND_INSTANCE_SIGNATURE=test-signature
		OMARCHY_PATH="$FIXTURE_OMARCHY"
	)
	printf 'preview matrix\ncancel\n' >"$SELECTOR_ACTIONS"
	run_selector_fixture
	assert_eq 0 "$COMMAND_STATUS" 'a preview map timeout should return to Cancel' || failed=1
	assert_contains "$COMMAND_OUTPUT" 'screensaver did not map' \
		'the preview should reject a foreign same-class window as a map timeout' || failed=1
	if [[ $(<"$CALL_LOG") == *'dispatch closewindow address:0xdeadbeef'* ]]; then
		printf '  map-timeout cleanup closed a foreign same-class window\n' >&2
		failed=1
	fi
	while IFS='|' read -r role identity pid shim_pid; do
		case $role in
		owned-runner)
			owned_count=$((owned_count + 1))
			if kill -0 "$pid" 2>/dev/null; then
				printf '  map-timeout runner %s survived cleanup\n' "$pid" >&2
				failed=1
			fi
			;;
		owned-effect)
			if kill -0 "$pid" 2>/dev/null || kill -0 "$shim_pid" 2>/dev/null; then
				printf '  map-timeout shim/effect tree survived cleanup\n' >&2
				failed=1
			fi
			;;
		runner-trap)
			printf '  map-timeout cleanup invoked the stock runner signal trap\n' >&2
			failed=1
			;;
		esac
	done <"$CALL_LOG"
	assert_eq 1 "$owned_count" 'the map-timeout fixture should start one attempt-owned runner' || failed=1
	if ! kill -0 "$unrelated_ttfx" 2>/dev/null || ! kill -0 "$unrelated_screensaver" 2>/dev/null; then
		printf '  map-timeout cleanup killed an unrelated process\n' >&2
		failed=1
	fi
	kill "$unrelated_ttfx" "$unrelated_screensaver" "$PREVIEW_SOCKET_LISTENER" 2>/dev/null || true
	wait "$unrelated_ttfx" "$unrelated_screensaver" "$PREVIEW_SOCKET_LISTENER" 2>/dev/null || true
	return "$failed"
}

set -e
run_test test_selector_saves_canonical_source_and_preserves_the_deployed_symlink \
	'selector saves canonical source and preserves the deployed symlink'
run_test test_selector_noop_and_empty_pending_do_not_rewrite_the_source \
	'selector keeps no-op and empty pending saves source-preserving'
run_test test_selector_acknowledges_partial_changes_and_previews_without_losing_pending_state \
	'selector requires Partial acknowledgements without losing pending state'
run_test test_selector_keeps_pending_changes_after_preview_failure \
	'selector keeps pending changes after preview failure'
run_test test_selector_repairs_invalid_entries_and_warns_without_version_lockout \
	'selector repairs invalid entries and treats version drift as warning-only'
run_test test_selector_supports_gum_and_bash_multiselect_paths \
	'selector supports Gum and Bash multiselect paths'
run_test test_selector_rejects_regular_and_foreign_deployed_leaves_and_public_non_tty_use \
	'selector rejects regular and foreign deployed leaves and public non-TTY use'
run_test test_preview_cleanup_closes_only_its_recorded_window_and_preserves_unrelated_processes \
	'preview cleanup targets only its recorded window and preserves unrelated processes'
run_test test_preview_map_timeout_stops_only_its_owned_process_tree \
	'preview map timeout stops only its attempt-owned process tree'
finish_tests
