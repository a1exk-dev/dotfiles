#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

HOST_TTFX=$(command -v ttfx)
HOST_SOCAT=$(command -v socat)

setup_mapping_fixture() {
	new_fixture || return 1
	MAPPING_PACKAGE=$FIXTURE_REPO/config/screensaver-effects
	MAPPING_SHIM=$MAPPING_PACKAGE/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/bin/ttfx
	MAPPING_SOURCE=$MAPPING_PACKAGE/.config/dotfiles/screensaver-effects.json
	MAPPING_ALLOWLIST=$FIXTURE_CONFIG/dotfiles/screensaver-effects.json
	MAPPING_ATTEMPT=$FIXTURE_RUNTIME/screensaver-attempt
	MAPPING_PROCESS_DIR=$MAPPING_ATTEMPT/dispatch-0
	MAPPING_ATTEMPT_ID=dotfiles-screensaver-test-0
	MAPPING_REAL_TTFX=$FIXTURE_BIN/real-ttfx
	mkdir -p "$FIXTURE_CONFIG/dotfiles" "$MAPPING_PROCESS_DIR"
	printf '[\n  "matrix"\n]\n' >"$MAPPING_SOURCE"
	ln -s "$MAPPING_SOURCE" "$MAPPING_ALLOWLIST"
	: >"$MAPPING_ATTEMPT/launch-attempt"
	printf '%s\n' "$MAPPING_ATTEMPT_ID" >"$MAPPING_PROCESS_DIR/identity"
	make_fake real-ttfx '
if [[ ${1-} == --version ]]; then printf "ttfx %s\n" "${DOTFILES_TEST_TTFX_VERSION:-0.3.2}"; exit 0; fi
if [[ ${1-} == --help ]]; then
cat <<"HELP"
Commands:
  beams  Beams
  matrix  Matrix
  help  Print help

Options:
HELP
exit 0
fi
	printf "%s\n" "$@" >"$DOTFILES_TEST_TTFX_ARGS"
	sleep 0.1'
	make_fake omarchy '
if [[ ${1-} == theme && ${2-} == color ]]; then
	case $3 in
		background) printf "#010203\n" ;;
		foreground) printf "#111111\n" ;;
		accent) printf "#222222\n" ;;
		muted) printf "#333333\n" ;;
		bright_foreground) printf "#eeeeee\n" ;;
		*) printf "#444444\n" ;;
	esac
else exit 64
fi'
}

run_stock_shim() {
	local args_file=$1 output_file=$2 status_file=$3
	shift 3
	set +e
	env -i \
		HOME="$FIXTURE_HOME" \
		XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
		XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" \
		DOTFILES_TEST_CALL_LOG="$CALL_LOG" \
		DOTFILES_TEST_TTFX_ARGS="$args_file" \
		DOTFILES_SCREENSAVER_REAL_TTFX="$MAPPING_REAL_TTFX" \
		DOTFILES_SCREENSAVER_ATTEMPT_DIR="$MAPPING_ATTEMPT" \
		DOTFILES_SCREENSAVER_PROCESS_DIR="$MAPPING_PROCESS_DIR" \
		DOTFILES_SCREENSAVER_ATTEMPT_ID="$MAPPING_ATTEMPT_ID" \
		"$@" \
		"$MAPPING_SHIM" \
			-i "$FIXTURE_HOME/.config/omarchy/branding/screensaver.txt" \
			--frame-rate 120 --canvas-width 0 --canvas-height 0 --reuse-canvas \
			--anchor-canvas c --anchor-text c --random-effect --no-eol --no-restore-cursor \
			>"$output_file" 2>&1
	printf '%s\n' "$?" >"$status_file"
	set -e
}

test_shim_replaces_only_the_stock_random_effect_with_the_mapped_effect() {
	setup_mapping_fixture || return 1
	local args=$FIXTURE_ROOT/ttfx-args output status
	local output_file=$FIXTURE_ROOT/output status_file=$FIXTURE_ROOT/status
	run_stock_shim "$args" "$output_file" "$status_file" env
	output=$(<"$output_file")
	status=$(<"$status_file")

	assert_eq 0 "$status" 'a mapped stock invocation should succeed' || return 1
	assert_eq '' "$output" 'a supported mapped invocation should not warn' || return 1
	assert_contains "$(<"$args")" $'--existing-color-handling\nignore\nmatrix\n--highlight-color\n#eeeeee' \
		'the shim should place mapped root arguments before the explicit Matrix effect' || return 1
	if [[ $(<"$args") == *'--random-effect'* ]]; then
		printf '  mapped invocation retained stock random selection\n' >&2
		return 1
	fi
}

test_shim_fails_closed_for_unexpected_private_path_invocations() {
	setup_mapping_fixture || return 1
	local args=$FIXTURE_ROOT/ttfx-args output status
	set +e
	output=$(env -i HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_TEST_TTFX_ARGS="$args" \
		DOTFILES_SCREENSAVER_REAL_TTFX="$MAPPING_REAL_TTFX" \
		DOTFILES_SCREENSAVER_ATTEMPT_DIR="$MAPPING_ATTEMPT" \
		DOTFILES_SCREENSAVER_PROCESS_DIR="$MAPPING_PROCESS_DIR" \
		DOTFILES_SCREENSAVER_ATTEMPT_ID="$MAPPING_ATTEMPT_ID" DOTFILES_SCREENSAVER_TEST=1 \
		"$MAPPING_SHIM" --random-effect 2>&1)
	status=$?
	set -e
	assert_eq 1 "$status" 'an unexpected private-path invocation should fail closed' || return 1
	assert_contains "$output" 'ttfx arguments did not match the audited Omarchy screensaver runner' \
		'the invocation failure should identify the rejected runner grammar' || return 1
	assert_path_absent "$args" 'an unexpected --random-effect invocation must not reach real ttfx'
}

test_shim_requires_the_deployed_allowlist_to_resolve_to_this_package_source() {
	setup_mapping_fixture || return 1
	local args=$FIXTURE_ROOT/ttfx-args foreign=$FIXTURE_ROOT/foreign-allowlist.json
	local regular_output=$FIXTURE_ROOT/regular-output regular_status=$FIXTURE_ROOT/regular-status
	local foreign_output=$FIXTURE_ROOT/foreign-output foreign_status=$FIXTURE_ROOT/foreign-status

	rm -- "$MAPPING_ALLOWLIST"
	printf '[\n  "matrix"\n]\n' >"$MAPPING_ALLOWLIST"
	run_stock_shim "$args" "$regular_output" "$regular_status" env DOTFILES_SCREENSAVER_TEST=1
	assert_eq 1 "$(<"$regular_status")" 'a regular deployed allowlist should fail closed' || return 1
	assert_contains "$(<"$regular_output")" 'deployed allowlist is not a Stow symlink' \
		'a regular deployed file must not become a second source of truth' || return 1
	assert_path_absent "$args" 'a regular deployed allowlist must not execute real ttfx' || return 1

	printf '[\n  "matrix"\n]\n' >"$foreign"
	rm -- "$MAPPING_ALLOWLIST"
	ln -s "$foreign" "$MAPPING_ALLOWLIST"
	run_stock_shim "$args" "$foreign_output" "$foreign_status" env DOTFILES_SCREENSAVER_TEST=1
	assert_eq 1 "$(<"$foreign_status")" 'a foreign deployed allowlist symlink should fail closed' || return 1
	assert_contains "$(<"$foreign_output")" 'deployed allowlist does not resolve to this package source' \
		'a foreign symlink must not replace the package-owned source' || return 1
	assert_path_absent "$args" 'a foreign deployed symlink must not execute real ttfx'
}

test_shim_accepts_only_the_explicit_foreground_preview_allowlist() {
	setup_mapping_fixture || return 1
	local args=$FIXTURE_ROOT/ttfx-args output_file=$FIXTURE_ROOT/output status_file=$FIXTURE_ROOT/status
	printf '[\n  "beams"\n]\n' >"$MAPPING_ATTEMPT/allowlist.json"
	run_stock_shim "$args" "$output_file" "$status_file" env \
		DOTFILES_SCREENSAVER_FOREGROUND=1 \
		DOTFILES_SCREENSAVER_PREVIEW_EFFECT=beams \
		DOTFILES_SCREENSAVER_ALLOWLIST="$MAPPING_ATTEMPT/allowlist.json"
	assert_eq 0 "$(<"$status_file")" 'the trusted foreground preview allowlist should execute' || return 1
	assert_contains "$(<"$args")" $'beams\n--beam-gradient-stops' \
		'the explicit preview should use its mapped effect'
}

test_shim_fails_closed_and_emits_one_attempt_diagnostic() {
	setup_mapping_fixture || return 1
	local args=$FIXTURE_ROOT/ttfx-args output1=$FIXTURE_ROOT/output-1 output2=$FIXTURE_ROOT/output-2
	local status1=$FIXTURE_ROOT/status-1 status2=$FIXTURE_ROOT/status-2
	printf '[\n  "unknown"\n]\n' >"$MAPPING_ALLOWLIST"
	make_fake logger 'printf "log|%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake omarchy-notification-send 'printf "notify|%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	run_stock_shim "$args" "$output1" "$status1" env DOTFILES_SCREENSAVER_TEST=1
	run_stock_shim "$args" "$output2" "$status2" env DOTFILES_SCREENSAVER_TEST=1

	assert_eq 1 "$(<"$status1")" 'an unmapped allowlist entry should fail closed' || return 1
	assert_eq 1 "$(<"$status2")" 'a repeated process in the attempt should still fail closed' || return 1
	assert_path_absent "$args" 'fail-closed validation should not execute real ttfx' || return 1
	assert_contains "$(<"$MAPPING_ATTEMPT/failure")" 'allowlisted effect is unavailable or unmapped: unknown' \
		'the attempt failure should name the concrete invalid entry' || return 1
	assert_eq 2 "$(wc -l <"$CALL_LOG")" \
		'the attempt claim should permit one logger call and one notification call total'
}

test_shim_retains_the_process_identity_polled_by_the_stock_runner() {
	setup_mapping_fixture || return 1
	local output=$FIXTURE_ROOT/retained-output pid child comm= status attempt
	env -i \
		HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_TEST_TTFX_ARGS="$FIXTURE_ROOT/unused-args" \
		DOTFILES_SCREENSAVER_FOREGROUND=1 DOTFILES_SCREENSAVER_REAL_TTFX="$MAPPING_REAL_TTFX" \
		DOTFILES_SCREENSAVER_ATTEMPT_DIR="$MAPPING_ATTEMPT" \
		DOTFILES_SCREENSAVER_PROCESS_DIR="$MAPPING_PROCESS_DIR" \
		DOTFILES_SCREENSAVER_ATTEMPT_ID="$MAPPING_ATTEMPT_ID" \
		"$MAPPING_SHIM" --random-effect \
			>"$output" 2>&1 &
	pid=$!
	for attempt in {1..50}; do
		comm=$(ps -o comm= -p "$pid" 2>/dev/null || true)
		[[ $comm == ttfx ]] && break
		sleep 0.02
	done
	assert_eq ttfx "$comm" 'a retained failure must be visible to the stock runner as ttfx' || {
		kill -TERM "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
		return 1
	}
	child=$(pgrep -P "$pid" 2>/dev/null || true)
	kill -TERM "$pid"
	set +e
	wait "$pid"
	status=$?
	set -e
	assert_eq 0 "$status" 'stock dismissal signals should end retention successfully' || return 1
	if [[ -n $child ]] && kill -0 "$child" 2>/dev/null; then
		printf '  retained failure left child process %s behind\n' "$child" >&2
		kill -TERM "$child" 2>/dev/null || true
		return 1
	fi
	assert_contains "$(<"$output")" 'ttfx arguments did not match the audited Omarchy screensaver runner' \
		'the rejected invocation should retain a blank process after terminal launch'
}

test_shim_registers_ttfx_identity_before_real_binary_validation() {
	setup_mapping_fixture || return 1
	local output=$FIXTURE_ROOT/invalid-real-output pid comm= status attempt
	env -i \
		HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_SCREENSAVER_FOREGROUND=1 \
		DOTFILES_SCREENSAVER_REAL_TTFX="$FIXTURE_ROOT/missing-ttfx" \
		DOTFILES_SCREENSAVER_ATTEMPT_DIR="$MAPPING_ATTEMPT" \
		DOTFILES_SCREENSAVER_PROCESS_DIR="$MAPPING_PROCESS_DIR" \
		DOTFILES_SCREENSAVER_ATTEMPT_ID="$MAPPING_ATTEMPT_ID" \
		"$MAPPING_SHIM" \
			-i "$FIXTURE_HOME/.config/omarchy/branding/screensaver.txt" \
			--frame-rate 120 --canvas-width 0 --canvas-height 0 --reuse-canvas \
			--anchor-canvas c --anchor-text c --random-effect --no-eol --no-restore-cursor \
			>"$output" 2>&1 &
	pid=$!
	for attempt in {1..100}; do
		comm=$(ps -o comm= -p "$pid" 2>/dev/null || true)
		[[ $comm == ttfx ]] && break
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.01
	done
	assert_eq ttfx "$comm" 'real-binary validation must observe an already registered ttfx process' || {
		kill -TERM "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
		return 1
	}
	sleep 0.05
	if ! kill -0 "$pid" 2>/dev/null; then
		printf '  invalid real-binary validation exited instead of retaining ttfx\n' >&2
		return 1
	fi
	assert_contains "$(<"$MAPPING_PROCESS_DIR/shim.pid")" "$pid " \
		'the attempt state should register the retained shim PID before validation' || return 1
	kill -TERM "$pid"
	set +e
	wait "$pid"
	status=$?
	set -e
	assert_eq 0 "$status" 'attempt-scoped termination should dismiss the retained shim cleanly' || return 1
	assert_contains "$(<"$output")" 'real ttfx is not an executable absolute file' \
		'the retained process should report the real-binary validation failure' || return 1

	setup_mapping_fixture || return 1
	output=$FIXTURE_ROOT/recursive-real-output
	env -i \
		HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_SCREENSAVER_FOREGROUND=1 \
		DOTFILES_SCREENSAVER_REAL_TTFX="$MAPPING_SHIM" \
		DOTFILES_SCREENSAVER_ATTEMPT_DIR="$MAPPING_ATTEMPT" \
		DOTFILES_SCREENSAVER_PROCESS_DIR="$MAPPING_PROCESS_DIR" \
		DOTFILES_SCREENSAVER_ATTEMPT_ID="$MAPPING_ATTEMPT_ID" \
		"$MAPPING_SHIM" \
			-i "$FIXTURE_HOME/.config/omarchy/branding/screensaver.txt" \
			--frame-rate 120 --canvas-width 0 --canvas-height 0 --reuse-canvas \
			--anchor-canvas c --anchor-text c --random-effect --no-eol --no-restore-cursor \
			>"$output" 2>&1 &
	pid=$!
	comm=
	for attempt in {1..100}; do
		comm=$(ps -o comm= -p "$pid" 2>/dev/null || true)
		[[ $comm == ttfx ]] && break
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.01
	done
	assert_eq ttfx "$comm" 'recursive resolution must retain the registered ttfx process' || return 1
	sleep 0.05
	if ! kill -0 "$pid" 2>/dev/null; then
		printf '  recursive real-binary validation exited instead of retaining ttfx\n' >&2
		return 1
	fi
	kill -TERM "$pid"
	set +e
	wait "$pid"
	status=$?
	set -e
	assert_eq 0 "$status" 'recursive execution retention should dismiss cleanly' || return 1
	assert_contains "$(<"$output")" 'refusing recursive ttfx execution' \
		'the retained process should report recursive execution'
}

test_launcher_closes_only_windows_recorded_for_its_partial_attempt() {
	setup_mapping_fixture || return 1
	local launcher=$MAPPING_PACKAGE/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/launch-screensaver
	local socket_dir=$FIXTURE_RUNTIME/hypr/test-signature socket
	local listener unrelated_ttfx unrelated_screensaver status output failed=0
	local line role identity pid shim_pid first_identity=
	mkdir -p "$socket_dir" "$FIXTURE_OMARCHY/default/alacritty"
	: >"$FIXTURE_OMARCHY/default/alacritty/screensaver.toml"
	socket=$socket_dir/.socket2.sock
	"$HOST_SOCAT" "UNIX-LISTEN:$socket,fork" EXEC:/usr/bin/true >/dev/null 2>&1 &
	listener=$!
	for _ in {1..50}; do [[ -S $socket ]] && break; sleep 0.02; done
	if [[ ! -S $socket ]]; then
		kill "$listener" 2>/dev/null || true
		wait "$listener" 2>/dev/null || true
		printf '  could not create fixture Hyprland event socket\n' >&2
		return 1
	fi
	make_fake ttfx '
case ${1-} in
	--version) printf "ttfx 0.3.2\n"; exit 0 ;;
	--help) printf "Commands:\n  matrix  Matrix\n  help  Print help\n\nOptions:\n"; exit 0 ;;
esac
printf "owned-effect|%s|%s|%s\n" "$DOTFILES_SCREENSAVER_ATTEMPT_ID" "$$" "$PPID" >>"$DOTFILES_TEST_CALL_LOG"
exec /usr/bin/sleep 30'
	make_fake pgrep 'exit 1'
	make_fake socat '
for index in 0 1; do
	process_dir=
	for _ in {1..250}; do
		for candidate in "$XDG_RUNTIME_DIR"/dotfiles-screensaver.*/dispatch-$index; do
			if [[ -f $candidate/identity ]]; then process_dir=$candidate; break 2; fi
		done
		sleep 0.02
	done
	[[ -n $process_dir ]] || exit 1
	identity=$(<"$process_dir/identity")
	for _ in {1..250}; do [[ -f $process_dir/effect.pid ]] && break; sleep 0.02; done
	[[ -f $process_dir/effect.pid ]] || exit 1
	if ((index == 0)); then
		printf "openwindow>>deadbeef,1,org.omarchy.screensaver,foreign-attempt\n"
		printf "openwindow>>abc123,1,org.omarchy.screensaver,%s\n" "$identity"
	else
		printf "openwindow>>facefeed,1,org.omarchy.screensaver,foreign-attempt\n"
	fi
done'
	make_fake xdg-terminal-exec '[[ ${1-} == --print-id ]] && printf "Alacritty.desktop\n"'
	make_fake omarchy-hyprland-monitor-focused 'printf "eDP-1\n"'
	make_fake omarchy-toggle-enabled 'exit 1'
	make_fake logger 'exit 0'
	make_fake omarchy-notification-send 'exit 0'
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
if [[ ${1-} == monitors && ${2-} == -j ]]; then
	printf '\''[{"name":"eDP-1"},{"name":"DP-1"}]\n'\''
	exit 0
fi
if [[ ${1-} == dispatch && ${2-} == hl.dsp.exec_cmd* ]]; then
	exit 1
fi
if [[ ${1-} == dispatch && ${2-} == exec ]]; then
	bash -c "${6-}" >/dev/null 2>&1 &
	exit 0
fi
exit 0'
	cp /usr/bin/sleep "$FIXTURE_ROOT/ttfx"
	"$FIXTURE_ROOT/ttfx" 30 &
	unrelated_ttfx=$!
	bash -c 'exec -a org.omarchy.screensaver /usr/bin/sleep 30' &
	unrelated_screensaver=$!
	set +e
	output=$(env -i \
		HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" \
		OMARCHY_PATH="$FIXTURE_OMARCHY" HYPRLAND_INSTANCE_SIGNATURE=test-signature \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_TEST_CALL_LOG="$CALL_LOG" \
		DOTFILES_TEST_TTFX_ARGS="$FIXTURE_ROOT/owned-effect-args" "$launcher" force 2>&1)
	status=$?
	set -e
	assert_eq 1 "$status" 'a second-monitor map failure should fail the launch attempt' || failed=1
	assert_contains "$output" 'screensaver window did not map on DP-1' \
		'the partial failure should identify the monitor that did not map' || failed=1
	assert_contains "$(<"$CALL_LOG")" 'dispatch closewindow address:0xabc123' \
		'partial cleanup should close the exact recorded attempt window' || failed=1
	if [[ $(<"$CALL_LOG") == *'address:0xdeadbeef'* || $(<"$CALL_LOG") == *'address:0xfacefeed'* ]]; then
		printf '  partial cleanup targeted a foreign same-class event address\n' >&2
		failed=1
	fi
	while IFS='|' read -r role identity pid shim_pid; do
		case $role in
		owned-runner)
			[[ -n $first_identity ]] || first_identity=$identity
			if kill -0 "$pid" 2>/dev/null; then
				printf '  timed-out owned runner %s survived cleanup\n' "$pid" >&2
				failed=1
			fi
			;;
		owned-effect)
			if kill -0 "$pid" 2>/dev/null || kill -0 "$shim_pid" 2>/dev/null; then
				printf '  timed-out owned shim/effect tree survived cleanup\n' >&2
				failed=1
			fi
			;;
		runner-trap)
			printf '  timeout cleanup invoked the stock runner signal trap\n' >&2
			failed=1
			;;
		esac
	done <"$CALL_LOG"
	if [[ -z $first_identity ]]; then
		printf '  no attempt-owned runner was started\n' >&2
		failed=1
	else
		assert_contains "$(<"$CALL_LOG")" "--class=org.omarchy.screensaver --title $first_identity" \
			'the dispatch should preserve the stock class and carry its unpredictable identity' || failed=1
	fi
	if ! kill -0 "$unrelated_ttfx" 2>/dev/null; then
		printf '  partial cleanup killed an unrelated ttfx process\n' >&2
		failed=1
	fi
	if ! kill -0 "$unrelated_screensaver" 2>/dev/null; then
		printf '  partial cleanup killed an unrelated screensaver process\n' >&2
		failed=1
	fi
	kill "$unrelated_ttfx" "$unrelated_screensaver" "$listener" 2>/dev/null || true
	wait "$unrelated_ttfx" "$unrelated_screensaver" "$listener" 2>/dev/null || true
	return "$failed"
}

test_all_terminal_forms_carry_attempt_identity_without_changing_the_stock_class() {
	setup_mapping_fixture || return 1
	local launcher selector launcher_source selector_source
	launcher=$MAPPING_PACKAGE/.local/share/dotfiles/screensaver-effects/plugins/dotfiles.idle/launch-screensaver
	selector=$MAPPING_PACKAGE/.local/libexec/dotfiles/screensaver-effects-selector
	launcher_source=$(<"$launcher")
	selector_source=$(<"$selector")
	assert_contains "$launcher_source" $'hypr_exec alacritty --class=org.omarchy.screensaver \\\n\t\t\t--title "$dispatch_id"' 'Alacritty launcher should carry the identity with the stock class' || return 1
	assert_contains "$launcher_source" $'hypr_exec ghostty --class=org.omarchy.screensaver \\\n\t\t\t--title="$dispatch_id"' 'Ghostty launcher should carry the identity with the stock class' || return 1
	assert_contains "$launcher_source" $'hypr_exec foot --app-id=org.omarchy.screensaver \\\n\t\t\t--title="$dispatch_id"' 'Foot launcher should carry the identity with the stock class' || return 1
	assert_contains "$launcher_source" 'hypr_exec kitty --class=org.omarchy.screensaver --title "$dispatch_id"' 'Kitty launcher should carry the identity with the stock class' || return 1
	assert_contains "$selector_source" 'alacritty --class=org.omarchy.screensaver --title "$preview_identity"' 'Alacritty preview should carry the identity' || return 1
	assert_contains "$selector_source" 'ghostty --class=org.omarchy.screensaver --title="$preview_identity"' 'Ghostty preview should carry the identity' || return 1
	assert_contains "$selector_source" 'foot --app-id=org.omarchy.screensaver --title="$preview_identity"' 'Foot preview should carry the identity' || return 1
	assert_contains "$selector_source" 'kitty --class=org.omarchy.screensaver --title "$preview_identity"' 'Kitty preview should carry the identity'
}

test_shim_warns_and_continues_for_mapped_effects_on_an_untested_version() {
	setup_mapping_fixture || return 1
	local args=$FIXTURE_ROOT/ttfx-args output_file=$FIXTURE_ROOT/output status_file=$FIXTURE_ROOT/status
	run_stock_shim "$args" "$output_file" "$status_file" env DOTFILES_TEST_TTFX_VERSION=0.4.0
	assert_eq 0 "$(<"$status_file")" 'version drift alone should not block mapped execution' || return 1
	assert_contains "$(<"$output_file")" 'Warning: supported ttfx CLI 0.3.2; detected ttfx 0.4.0.' \
		'version drift should remain visible' || return 1
	assert_contains "$(<"$args")" $'matrix\n--highlight-color' \
		'a previously mapped discovered effect should still execute'
}

test_shim_reads_and_selects_the_complete_allowlist_for_each_effect_process() {
	setup_mapping_fixture || return 1
	local args=$FIXTURE_ROOT/ttfx-args output_file=$FIXTURE_ROOT/output status_file=$FIXTURE_ROOT/status
	printf '[\n  "beams",\n  "matrix"\n]\n' >"$MAPPING_ALLOWLIST"
	run_stock_shim "$args" "$output_file" "$status_file" env DOTFILES_SCREENSAVER_TEST=1 DOTFILES_SCREENSAVER_TEST_INDEX=0
	assert_eq 0 "$(<"$status_file")" 'a valid multi-effect allowlist should execute' || return 1
	assert_contains "$(<"$args")" $'beams\n--beam-gradient-stops' \
		'the selected allowlist member should receive its own mapped arguments' || return 1

	printf '[\n  "matrix"\n]\n' >"$MAPPING_ALLOWLIST"
	run_stock_shim "$args" "$output_file" "$status_file" env DOTFILES_SCREENSAVER_TEST=1 DOTFILES_SCREENSAVER_TEST_INDEX=0
	assert_eq 0 "$(<"$status_file")" 'a valid changed allowlist should apply to the next process' || return 1
	assert_contains "$(<"$args")" $'matrix\n--highlight-color' \
		'the next process should reread the changed complete allowlist'
}

test_all_tracked_mappings_match_the_supported_real_ttfx_grammar() {
	setup_mapping_fixture || return 1
	local before after effect status token key
	local -a mapped=()
	declare -A colors=(
		[background]='#101315' [foreground]='#cacccc' [accent]='#798186'
		[muted]='#4b4e55' [bright_foreground]='#a5aeb4' [red]='#565d60'
		[bright_red]='#de6145' [bright_yellow]='#c9c2b4' [yellow]='#d9dbdc'
		[green]='#9fa5a9' [blue]='#798186' [bright_blue]='#5d6367'
		[magenta]='#aeaeae' [orange]='#d9dbdc' [darker_background]='#080a0b'
		[dark_background]='#0c0e10'
	)
	before=$(pgrep -a -x ttfx 2>/dev/null || true)
	DOTFILES_SCREENSAVER_SOURCE_ONLY=1 source "$MAPPING_SHIM"
	while IFS=$'\t' read -r effect status; do
		screensaver_mapping "$effect" || return 1
		mapped=()
		for token in "${SCREENSAVER_MAP_ARGS[@]}"; do
			if [[ $token == @FINAL ]]; then
				mapped+=(--final-gradient-stops "${colors[accent]}" "${colors[foreground]}" "${colors[bright_foreground]}")
			elif [[ $token == @* ]]; then
				key=${token#@}
				mapped+=("${colors[$key]}")
			else
				mapped+=("$token")
			fi
		done
		if ! printf 'OMARCHY\n' | "$HOST_TTFX" \
			--terminal-background-color "${colors[background]}" --existing-color-handling ignore \
			--seed 11 --parity-dump --max-frames 1 --canvas-width 40 --canvas-height 12 \
			--ignore-terminal-dimensions "$effect" "${mapped[@]}" >/dev/null 2>&1; then
			printf '  mapped grammar failed for %s (%s)\n' "$effect" "$status" >&2
			return 1
		fi
	done < <(screensaver_mapping_catalog)
	after=$(pgrep -a -x ttfx 2>/dev/null || true)
	assert_eq "$before" "$after" 'bounded grammar probes should leave no ttfx process behind'
}

set -e
run_test test_shim_replaces_only_the_stock_random_effect_with_the_mapped_effect \
	'shim replaces only the stock random effect with the mapped effect'
run_test test_shim_fails_closed_for_unexpected_private_path_invocations \
	'shim fails closed for unexpected private-path invocations'
run_test test_shim_requires_the_deployed_allowlist_to_resolve_to_this_package_source \
	'shim requires the deployed Stow link to resolve to this package source'
run_test test_shim_accepts_only_the_explicit_foreground_preview_allowlist \
	'shim accepts the explicit trusted foreground preview allowlist'
run_test test_shim_fails_closed_and_emits_one_attempt_diagnostic \
	'shim fails closed with one diagnostic per launch attempt'
run_test test_shim_retains_the_process_identity_polled_by_the_stock_runner \
	'shim retains the ttfx process identity polled by the stock runner'
run_test test_shim_registers_ttfx_identity_before_real_binary_validation \
	'shim registers ttfx identity before real-binary validation'
run_test test_launcher_closes_only_windows_recorded_for_its_partial_attempt \
	'launcher cleanup closes only windows recorded for its partial attempt'
run_test test_all_terminal_forms_carry_attempt_identity_without_changing_the_stock_class \
	'all terminal forms carry attempt identity while preserving the stock class'
run_test test_shim_warns_and_continues_for_mapped_effects_on_an_untested_version \
	'shim treats version drift as warning-only for mapped effects'
run_test test_shim_reads_and_selects_the_complete_allowlist_for_each_effect_process \
	'shim rereads and selects the complete allowlist for every effect process'
run_test test_all_tracked_mappings_match_the_supported_real_ttfx_grammar \
	'all tracked mappings match supported real ttfx grammar'
finish_tests
