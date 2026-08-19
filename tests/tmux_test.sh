#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly TMUX_STARTER_RELATIVE=.local/libexec/dotfiles/tmux-starter

configure_tmux_starter_fakes() {
	TMUX_SESSION_STATE=$FIXTURE_ROOT/tmux-sessions
	TMUX_LIST_MODE=$FIXTURE_ROOT/tmux-list-mode
	TMUX_PANE_MODE=$FIXTURE_ROOT/tmux-pane-mode
	TMUX_PANE_TTY=$FIXTURE_ROOT/tmux-pane-tty
	TMUX_NEW_STATUS=$FIXTURE_ROOT/tmux-new-status
	TMUX_KILL_STATUS=$FIXTURE_ROOT/tmux-kill-status
	TMUX_MUTATIONS=$FIXTURE_ROOT/tmux-mutations
	FZF_RESPONSES=$FIXTURE_ROOT/fzf-responses
	FZF_COUNTER=$FIXTURE_ROOT/fzf-counter
	TTY_MODE=$FIXTURE_ROOT/tty-mode
	CURRENT_TTY=$FIXTURE_ROOT/current-tty

	: >"$TMUX_SESSION_STATE"
	: >"$TMUX_MUTATIONS"
	: >"$FZF_RESPONSES"
	printf 'sessions\n' >"$TMUX_LIST_MODE"
	printf 'invalid\n' >"$TMUX_PANE_MODE"
	printf '/dev/pts/0\n' >"$TMUX_PANE_TTY"
	printf '0\n' >"$TMUX_NEW_STATUS"
	printf '0\n' >"$TMUX_KILL_STATUS"
	printf 'readable\n' >"$TTY_MODE"
	printf '/dev/pts/99\n' >"$CURRENT_TTY"

	make_fake exact-tmux '
root=${DOTFILES_TEST_CALL_LOG%/*}
state=$root/tmux-sessions
{
	printf "tmux"
	printf " [%q]" "$@"
	if [[ -v TMUX ]]; then printf " |TMUX=set"; else printf " |TMUX=unset"; fi
	if [[ -v TMUX_PANE ]]; then printf " |TMUX_PANE=set"; else printf " |TMUX_PANE=unset"; fi
	printf " |PWD=%q\n" "$PWD"
} >>"$DOTFILES_TEST_CALL_LOG"

socket=
if [[ ${1-} == -S ]]; then
	socket=${2-}
	shift 2
fi
command=${1-}
if (( $# > 0 )); then shift; fi

case $command in
	list-panes)
		if (( $# != 3 )) || [[ $1 != -a || $2 != -F || $3 != "#{pane_tty}" || -z $socket ]]; then
			printf "fake tmux protocol mismatch: list-panes\n" >&2
			exit 65
		fi
		if [[ $(<"$root/tmux-pane-mode") != valid ]]; then
			printf "fake tmux socket is unavailable\n" >&2
			exit 1
		fi
		cat "$root/tmux-pane-tty"
		;;
	list-sessions)
		expected_format=$(printf "#{session_id}\t#{session_name}\t#{session_windows}\t#{?session_attached,attached,detached}")
		if (( $# != 2 )) || [[ -n $socket || $1 != -F || $2 != "$expected_format" ]]; then
			printf "fake tmux protocol mismatch: list-sessions\n" >&2
			exit 65
		fi
		if [[ $(<"$root/tmux-list-mode") == no-server ]]; then
			printf "no server running on fake socket\n" >&2
			exit 1
		fi
		cat "$state"
		;;
	display-message)
		if (( $# != 4 )) || [[ -n $socket || $1 != -p || $2 != -t || $4 != "#{session_name}" ]]; then
			printf "fake tmux protocol mismatch: display-message\n" >&2
			exit 65
		fi
		target=$3
		while IFS=$'"'"'\t'"'"' read -r id name windows state_name; do
			if [[ $id == "$target" ]]; then
				printf "%s\n" "$name"
				exit 0
			fi
		done <"$state"
		printf "unknown fake tmux target: %s\n" "$target" >&2
		exit 1
		;;
	attach-session)
		{
			printf "attach"
			printf " [%q]" "$@"
			printf "\n"
		} >>"$root/tmux-mutations"
		;;
	new-session)
		status=$(<"$root/tmux-new-status")
		if (( status != 0 )); then
			printf "fake tmux rejected the session name\n" >&2
			exit "$status"
		fi
		{
			printf "new"
			printf " [%q]" "$@"
			printf "\n"
		} >>"$root/tmux-mutations"
		;;
	kill-session)
		status=$(<"$root/tmux-kill-status")
		if (( status != 0 )); then
			printf "fake kill failed with status %s\n" "$status" >&2
			exit "$status"
		fi
		target=
		while (( $# > 0 )); do
			case $1 in
				-t) target=${2-}; shift 2 ;;
				*) shift ;;
			esac
		done
		found=false
		: >"$state.next"
		while IFS=$'"'"'\t'"'"' read -r id name windows state_name; do
			if [[ $id == "$target" ]]; then
				found=true
				continue
			fi
			printf "%s\t%s\t%s\t%s\n" "$id" "$name" "$windows" "$state_name" >>"$state.next"
		done <"$state"
		if [[ $found != true ]]; then
			rm -f "$state.next"
			printf "unknown fake tmux target: %s\n" "$target" >&2
			exit 1
		fi
		mv "$state.next" "$state"
		printf "kill [%q]\n" "$target" >>"$root/tmux-mutations"
		;;
	*)
		printf "unexpected fake tmux command: %s\n" "$command" >&2
		exit 64
		;;
esac'

	make_fake exact-fzf '
root=${DOTFILES_TEST_CALL_LOG%/*}
{
	printf "fzf"
	printf " [%q]" "$@"
	if [[ -v FZF_DEFAULT_OPTS ]]; then printf " |FZF_DEFAULT_OPTS=set"; else printf " |FZF_DEFAULT_OPTS=unset"; fi
	if [[ -v FZF_DEFAULT_OPTS_FILE ]]; then printf " |FZF_DEFAULT_OPTS_FILE=set"; else printf " |FZF_DEFAULT_OPTS_FILE=unset"; fi
	printf "\n"
} >>"$DOTFILES_TEST_CALL_LOG"

expect=false
display_only=false
header=false
for argument in "$@"; do
	case $argument in
		--expect=ctrl-n,ctrl-x) expect=true ;;
		--with-nth=2..) display_only=true ;;
		--header=Enter*) header=true ;;
		--disabled|--no-input) touch "$root/fzf-forbidden-option" ;;
	esac
done
if [[ $expect == true && $display_only == true && $header == true ]]; then
	touch "$root/fzf-protocol-ok"
fi

mapfile -t rows
count=0
if [[ -s $root/fzf-counter ]]; then count=$(<"$root/fzf-counter"); fi
count=$((count + 1))
printf "%s\n" "$count" >"$root/fzf-counter"
: >"$root/fzf-input.$count"
for row in "${rows[@]}"; do
	printf "%s\n" "$row" >>"$root/fzf-input.$count"
done

mapfile -t responses <"$root/fzf-responses"
if (( ${#responses[@]} == 0 )); then
	printf "fake fzf has no queued response\n" >&2
	exit 70
fi
response=${responses[0]}
: >"$root/fzf-responses.next"
if (( ${#responses[@]} > 1 )); then
	printf "%s\n" "${responses[@]:1}" >"$root/fzf-responses.next"
fi
mv "$root/fzf-responses.next" "$root/fzf-responses"

case $response in
	enter:*)
		index=${response#*:}
		(( index >= 1 && index <= ${#rows[@]} )) || exit 71
		printf "\n%s\n" "${rows[index - 1]}"
		;;
	ctrl-n)
		printf "ctrl-n\n"
		;;
	ctrl-x:*)
		index=${response#*:}
		(( index >= 1 && index <= ${#rows[@]} )) || exit 71
		printf "ctrl-x\n%s\n" "${rows[index - 1]}"
		;;
	cancel) exit 130 ;;
	no-match) exit 1 ;;
	fail:*) exit "${response#*:}" ;;
	*)
		printf "unknown fake fzf response: %s\n" "$response" >&2
		exit 69
		;;
esac'

	make_fake exact-tty '
root=${DOTFILES_TEST_CALL_LOG%/*}
if [[ $(<"$root/tty-mode") != readable ]]; then exit 1; fi
printf "%s\n" "$(<"$root/current-tty")"'

	printf 'not executable\n' >"$FIXTURE_ROOT/non-executable-tmux"
	printf 'not executable\n' >"$FIXTURE_ROOT/non-executable-fzf"
	chmod 0644 "$FIXTURE_ROOT/non-executable-tmux" "$FIXTURE_ROOT/non-executable-fzf"
	bind_tmux_starter_tools "$FIXTURE_BIN/exact-tmux" "$FIXTURE_BIN/exact-fzf"
}

bind_tmux_starter_tools() {
	local tmux_executable=$1
	local fzf_executable=$2
	BWRAP_EXTRA_ARGS=(
		--ro-bind "$tmux_executable" /usr/bin/tmux
		--ro-bind "$fzf_executable" /usr/bin/fzf
		--ro-bind "$FIXTURE_BIN/exact-tty" /usr/bin/tty
	)
}

set_tmux_sessions() {
	: >"$TMUX_SESSION_STATE"
	while (( $# > 0 )); do
		if (( $# < 4 )); then
			printf '  tmux session fixture requires groups of four fields\n' >&2
			return 1
		fi
		printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$TMUX_SESSION_STATE"
		shift 4
	done
}

queue_fzf_responses() {
	printf '%s\n' "$@" >"$FZF_RESPONSES"
}

run_tmux_starter() {
	local working_directory=${1:-$FIXTURE_ROOT}
	run_in_sandbox "$working_directory" "$FIXTURE_BIN:/usr/bin:/bin" \
		"$FIXTURE_REPO/config/tmux/$TMUX_STARTER_RELATIVE"
}

run_tmux_starter_with_environment() {
	local tmux_value=$1
	local pane_value=$2
	local working_directory=${3:-$FIXTURE_ROOT}
	run_in_sandbox "$working_directory" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/env "TMUX=$tmux_value" "TMUX_PANE=$pane_value" \
		"$FIXTURE_REPO/config/tmux/$TMUX_STARTER_RELATIVE"
}

run_tmux_starter_with_tmux_only() {
	local tmux_value=$1
	local working_directory=${2:-$FIXTURE_ROOT}
	run_in_sandbox "$working_directory" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/env "TMUX=$tmux_value" \
		"$FIXTURE_REPO/config/tmux/$TMUX_STARTER_RELATIVE"
}

run_tmux_starter_with_hostile_fzf_defaults() {
	local working_directory=${1:-$FIXTURE_ROOT}
	printf '%s\n' '--print-query --multi --accept-nth=2 --read0 --print0' >"$FIXTURE_ROOT/hostile-fzf-options"
	run_in_sandbox "$working_directory" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/env \
			FZF_DEFAULT_OPTS='--print-query --multi --accept-nth=2 --read0 --print0' \
			FZF_DEFAULT_OPTS_FILE="$FIXTURE_ROOT/hostile-fzf-options" \
			"$FIXTURE_REPO/config/tmux/$TMUX_STARTER_RELATIVE"
}

assert_no_tmux_mutation() {
	assert_eq '' "$(<"$TMUX_MUTATIONS")" "$1"
}

assert_tmux_environment_was_cleared() {
	local line
	while IFS= read -r line; do
		[[ $line == tmux* ]] || continue
		if [[ $line != *'|TMUX=unset |TMUX_PANE=unset'* ]]; then
			printf '  tmux operation retained leaked environment: %s\n' "$line" >&2
			return 1
		fi
	done <"$CALL_LOG"
}

test_missing_exact_runtime_tools_fail_with_status_127() {
	new_fixture
	configure_tmux_starter_fakes
	bind_tmux_starter_tools "$FIXTURE_ROOT/non-executable-tmux" "$FIXTURE_BIN/exact-fzf"
	run_tmux_starter

	assert_eq 127 "$COMMAND_STATUS" 'a missing exact tmux executable should return command-not-found status' || return 1
	assert_contains "$COMMAND_OUTPUT" '/usr/bin/tmux' 'the missing tmux error should name the exact required path' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'missing tmux should stop before any runtime tool is invoked' || return 1

	new_fixture
	configure_tmux_starter_fakes
	bind_tmux_starter_tools "$FIXTURE_BIN/exact-tmux" "$FIXTURE_ROOT/non-executable-fzf"
	run_tmux_starter

	assert_eq 127 "$COMMAND_STATUS" 'a missing exact fzf executable should return command-not-found status' || return 1
	assert_contains "$COMMAND_OUTPUT" '/usr/bin/fzf' 'the missing fzf error should name the exact required path' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'missing fzf should stop before tmux is inspected'
}

test_real_pane_and_unreadable_tty_refuse_nesting() {
	new_fixture
	configure_tmux_starter_fakes
	printf 'valid\n' >"$TMUX_PANE_MODE"
	printf '/dev/pts/3\n/dev/pts/7\n' >"$TMUX_PANE_TTY"
	printf '/dev/pts/7\n' >"$CURRENT_TTY"
	run_tmux_starter_with_environment '/tmp/fake, tmux.sock,4321,0' '%7'

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  a starter invoked in a real pane should refuse to run\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'already running inside tmux' 'same-TTY refusal should be clear' || return 1
	assert_contains "$(<"$CALL_LOG")" '[-S] [/tmp/fake\,\ tmux.sock]' \
		'pane detection should preserve a comma-and-space socket path as one argument' || return 1
	assert_contains "$(<"$CALL_LOG")" '[list-panes] [-a] [-F] [\#\{pane_tty\}]' \
		'pane detection should request all pane TTYs with the exact format' || return 1
	assert_no_tmux_mutation 'inside-pane refusal should not mutate tmux sessions' || return 1
	assert_tmux_environment_was_cleared || return 1
	if [[ $(<"$CALL_LOG") == *'fzf '* ]]; then
		printf '  inside-pane refusal should not open fzf\n' >&2
		return 1
	fi

	new_fixture
	configure_tmux_starter_fakes
	printf 'valid\n' >"$TMUX_PANE_MODE"
	printf '/dev/pts/8\n' >"$TMUX_PANE_TTY"
	printf 'unreadable\n' >"$TTY_MODE"
	run_tmux_starter_with_environment '/tmp/fake.sock,4321,0' '%8'

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  a valid pane with an unreadable current TTY should refuse to run\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'cannot determine the current TTY' 'conservative refusal should explain the unreadable TTY' || return 1
	assert_no_tmux_mutation 'unreadable-TTY refusal should not mutate tmux sessions' || return 1

	new_fixture
	configure_tmux_starter_fakes
	printf 'valid\n' >"$TMUX_PANE_MODE"
	printf '/dev/pts/17\n' >"$TMUX_PANE_TTY"
	printf '/dev/pts/17\n' >"$CURRENT_TTY"
	run_tmux_starter_with_tmux_only '/tmp/missing-pane.sock,4321,0'

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  a matching pane must refuse even when TMUX_PANE is absent\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'already running inside tmux' \
		'missing TMUX_PANE should not bypass matching-TTY refusal' || return 1
	assert_tmux_environment_was_cleared || return 1

	new_fixture
	configure_tmux_starter_fakes
	printf 'valid\n' >"$TMUX_PANE_MODE"
	printf '/dev/pts/18\n' >"$TMUX_PANE_TTY"
	printf '/dev/pts/18\n' >"$CURRENT_TTY"
	run_tmux_starter_with_environment '/tmp/malformed-pane.sock,4321,0' 'not-a-pane'

	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  a matching pane must refuse even when TMUX_PANE is malformed\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'already running inside tmux' \
		'malformed TMUX_PANE should not bypass matching-TTY refusal' || return 1
	assert_tmux_environment_was_cleared
}

test_leaked_and_invalid_tmux_environment_is_cleared() {
	new_fixture
	configure_tmux_starter_fakes
	printf 'valid\n' >"$TMUX_PANE_MODE"
	printf '/dev/pts/9\n' >"$TMUX_PANE_TTY"
	printf '/dev/pts/10\n' >"$CURRENT_TTY"
	queue_fzf_responses cancel
	run_tmux_starter_with_environment '/tmp/fake.sock,4321,0' '%9'

	assert_eq 0 "$COMMAND_STATUS" 'a pane from another TTY should be treated as leaked environment' || return 1
	assert_tmux_environment_was_cleared || return 1
	assert_contains "$(<"$CALL_LOG")" '[list-sessions]' 'leaked environment should still reach the outside-tmux menu' || return 1
	assert_no_tmux_mutation 'cancelling after leaked-environment cleanup should not mutate tmux' || return 1

	new_fixture
	configure_tmux_starter_fakes
	printf 'invalid\n' >"$TMUX_PANE_MODE"
	queue_fzf_responses cancel
	run_tmux_starter_with_environment '/tmp/fake.sock,4321,0' '%404'

	assert_eq 0 "$COMMAND_STATUS" 'an invalid pane reference should be cleared and ignored' || return 1
	assert_tmux_environment_was_cleared || return 1
	assert_no_tmux_mutation 'invalid leaked state followed by cancel should not mutate tmux'
}

test_empty_starter_keeps_ctrl_n_available_and_placeholder_non_actionable() {
	new_fixture
	configure_tmux_starter_fakes
	printf 'no-server\n' >"$TMUX_LIST_MODE"
	queue_fzf_responses ctrl-n
	DOTFILES_TEST_INPUT='\n' run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'Ctrl-N should create from a no-server screen' || return 1
	assert_eq $'-\tNo tmux sessions are running' "$(<"$FIXTURE_ROOT/fzf-input.1")" \
		'the no-server screen should contain one non-actionable placeholder' || return 1
	assert_eq 'new [-A] [-s] [Work]' "$(<"$TMUX_MUTATIONS")" \
		'empty input should atomically attach or create Work without mutating an existing session path' || return 1
	assert_contains "$(<"$CALL_LOG")" "tmux [new-session] [-A] [-s] [Work] |TMUX=unset |TMUX_PANE=unset |PWD=$FIXTURE_ROOT" \
		'tmux itself should inherit the caller PWD for genuinely new sessions' || return 1
	[[ -e $FIXTURE_ROOT/fzf-protocol-ok ]] || {
		printf '  fzf should receive the approved keys, header, and hidden-ID display contract\n' >&2
		return 1
	}
	[[ ! -e $FIXTURE_ROOT/fzf-forbidden-option ]] || {
		printf '  the session menu should retain fuzzy input and search\n' >&2
		return 1
	}

	new_fixture
	configure_tmux_starter_fakes
	set_tmux_sessions
	queue_fzf_responses ctrl-n
	DOTFILES_TEST_INPUT='Zero work\n' run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'Ctrl-N should also create from a running server with zero sessions' || return 1
	assert_eq 'new [-A] [-s] [Zero\ work]' "$(<"$TMUX_MUTATIONS")" \
		'the zero-session placeholder should leave Ctrl-N actionable' || return 1

	new_fixture
	configure_tmux_starter_fakes
	set_tmux_sessions
	queue_fzf_responses enter:1
	run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'Enter on the zero-session placeholder should be a safe no-op' || return 1
	assert_no_tmux_mutation 'the placeholder must never become a tmux operation target'
}

test_fzf_cancel_no_match_and_unexpected_failures_use_distinct_statuses() {
	local response expected
	while IFS='|' read -r response expected; do
		new_fixture
		configure_tmux_starter_fakes
		set_tmux_sessions '$1' Work 1 detached
		queue_fzf_responses "$response"
		run_tmux_starter

		assert_eq "$expected" "$COMMAND_STATUS" "fzf response $response should produce the approved status" || return 1
		assert_no_tmux_mutation "fzf response $response should not mutate tmux" || return 1
	done <<'EOF'
cancel|0
no-match|0
fail:42|42
EOF
}

test_hostile_fzf_defaults_cannot_change_attach_or_control_output() {
	new_fixture
	configure_tmux_starter_fakes
	set_tmux_sessions '$15' 'Hostile defaults target' 2 detached
	queue_fzf_responses enter:1
	run_tmux_starter_with_hostile_fzf_defaults

	assert_eq 0 "$COMMAND_STATUS" 'hostile fzf defaults should not change Enter parsing' || return 1
	assert_eq 'attach [-t] [\$15]' "$(<"$TMUX_MUTATIONS")" \
		'hostile fzf defaults should not change the exact attach target' || return 1
	assert_contains "$(<"$CALL_LOG")" '|FZF_DEFAULT_OPTS=unset |FZF_DEFAULT_OPTS_FILE=unset' \
		'the exact fzf process should receive neither ambient defaults variable' || return 1

	new_fixture
	configure_tmux_starter_fakes
	local working_directory="$FIXTURE_ROOT/hostile defaults work"
	mkdir -p "$working_directory"
	queue_fzf_responses ctrl-n
	DOTFILES_TEST_INPUT='Controlled name\n' run_tmux_starter_with_hostile_fzf_defaults "$working_directory"

	assert_eq 0 "$COMMAND_STATUS" 'hostile fzf defaults should not change Ctrl-N parsing' || return 1
	assert_eq 'new [-A] [-s] [Controlled\ name]' "$(<"$TMUX_MUTATIONS")" \
		'hostile fzf defaults should preserve the exact Ctrl-N name' || return 1
	assert_contains "$(<"$CALL_LOG")" '|FZF_DEFAULT_OPTS=unset |FZF_DEFAULT_OPTS_FILE=unset' \
		'Ctrl-N fzf invocation should also clear both defaults variables'
}

test_session_rows_are_unique_informative_and_attach_by_exact_id() {
	new_fixture
	configure_tmux_starter_fakes
	set_tmux_sessions '$41' Work 1 detached
	queue_fzf_responses enter:1
	run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'Enter should open the only listed session' || return 1
	assert_eq $'$41\tWork\t1 window\tdetached' "$(<"$FIXTURE_ROOT/fzf-input.1")" \
		'a one-session row should retain hidden ID and show name, window count, and state' || return 1
	assert_eq 'attach [-t] [\$41]' "$(<"$TMUX_MUTATIONS")" 'Enter should attach the exact hidden session ID' || return 1

	new_fixture
	configure_tmux_starter_fakes
	local dangerous_name="Team alpha; touch $FIXTURE_ROOT/name-was-evaluated"
	set_tmux_sessions \
		'$51' 'First' 2 attached \
		'$77' "$dangerous_name" 3 detached \
		'$99' 'Last' 1 attached
	queue_fzf_responses enter:2
	run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'Enter should open the selected row from many sessions' || return 1
	assert_eq 3 "$(awk 'END { print NR + 0 }' "$FIXTURE_ROOT/fzf-input.1")" 'each session should appear exactly once' || return 1
	assert_eq 1 "$(awk -F '\t' -v id='$77' '$1 == id { count++ } END { print count + 0 }' "$FIXTURE_ROOT/fzf-input.1")" \
		'the selected session ID should occur in exactly one row' || return 1
	assert_contains "$(<"$FIXTURE_ROOT/fzf-input.1")" $'$77\t'"$dangerous_name"$'\t3 windows\tdetached' \
		'names with spaces and shell syntax should remain display data' || return 1
	assert_eq 'attach [-t] [\$77]' "$(<"$TMUX_MUTATIONS")" 'selection should attach by ID rather than reparsed name' || return 1
	if [[ -e $FIXTURE_ROOT/name-was-evaluated ]]; then
		printf '  a session name was evaluated as shell code\n' >&2
		return 1
	fi
}

test_ctrl_n_uses_atomic_default_custom_and_existing_names_with_pwd() {
	new_fixture
	configure_tmux_starter_fakes
	local working_directory="$FIXTURE_ROOT/work area"
	mkdir -p "$working_directory"
	queue_fzf_responses ctrl-n
	DOTFILES_TEST_INPUT='\n' run_tmux_starter "$working_directory"

	assert_eq 0 "$COMMAND_STATUS" 'empty Ctrl-N input should use the default name' || return 1
	local expected_pwd
	printf -v expected_pwd '%q' "$working_directory"
	assert_eq 'new [-A] [-s] [Work]' "$(<"$TMUX_MUTATIONS")" \
		'the default name should use one race-safe operation without -c' || return 1
	assert_contains "$(<"$CALL_LOG")" "tmux [new-session] [-A] [-s] [Work] |TMUX=unset |TMUX_PANE=unset |PWD=$expected_pwd" \
		'the new-session process should inherit the exact caller PWD' || return 1

	new_fixture
	configure_tmux_starter_fakes
	working_directory="$FIXTURE_ROOT/another work area"
	mkdir -p "$working_directory"
	local custom_name="Team alpha; touch $FIXTURE_ROOT/custom-name-was-evaluated"
	queue_fzf_responses ctrl-n
	DOTFILES_TEST_INPUT="$custom_name\n" run_tmux_starter "$working_directory"

	assert_eq 0 "$COMMAND_STATUS" 'a custom Ctrl-N name should be passed to tmux' || return 1
	local expected_name
	printf -v expected_name '%q' "$custom_name"
	printf -v expected_pwd '%q' "$working_directory"
	assert_eq "new [-A] [-s] [$expected_name]" "$(<"$TMUX_MUTATIONS")" \
		'custom names with spaces and shell syntax should remain one exact argument' || return 1
	assert_contains "$(<"$CALL_LOG")" "tmux [new-session] [-A] [-s] [$expected_name] |TMUX=unset |TMUX_PANE=unset |PWD=$expected_pwd" \
		'custom-name creation should inherit PWD without passing path-changing -c' || return 1
	if [[ -e $FIXTURE_ROOT/custom-name-was-evaluated ]]; then
		printf '  a custom session name was evaluated as shell code\n' >&2
		return 1
	fi

	new_fixture
	configure_tmux_starter_fakes
	set_tmux_sessions '$12' 'Existing team' 2 detached
	queue_fzf_responses ctrl-n
	DOTFILES_TEST_INPUT='Existing team\n' run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'an existing name should use the same attach-or-create operation' || return 1
	assert_eq 'new [-A] [-s] [Existing\ team]' "$(<"$TMUX_MUTATIONS")" \
		'existing names should use atomic new-session -A without -c or a precheck' || return 1
	assert_contains "$(<"$CALL_LOG")" "tmux [new-session] [-A] [-s] [Existing\\ team] |TMUX=unset |TMUX_PANE=unset |PWD=$FIXTURE_ROOT" \
		'existing-session attach should run from caller PWD without requesting a session path change' || return 1
	if [[ $(<"$CALL_LOG") == *'[has-session]'* ]]; then
		printf '  Ctrl-N must not perform a race-prone has-session precheck\n' >&2
		return 1
	fi

	new_fixture
	configure_tmux_starter_fakes
	queue_fzf_responses ctrl-n
	DOTFILES_TEST_INPUT='' run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'EOF at the session-name prompt should cancel safely' || return 1
	assert_no_tmux_mutation 'EOF at the session-name prompt should not create or attach a session' || return 1

	new_fixture
	configure_tmux_starter_fakes
	printf '34\n' >"$TMUX_NEW_STATUS"
	queue_fzf_responses ctrl-n
	DOTFILES_TEST_INPUT='invalid.name\n' run_tmux_starter

	assert_eq 34 "$COMMAND_STATUS" 'tmux should own invalid-name rejection status' || return 1
	assert_contains "$COMMAND_OUTPUT" 'fake tmux rejected the session name' \
		'tmux invalid-name diagnostics should remain visible' || return 1
	assert_no_tmux_mutation 'a rejected session name should not create or attach a session'
}

test_ctrl_x_decline_and_confirm_use_exact_id_and_refresh() {
	new_fixture
	configure_tmux_starter_fakes
	set_tmux_sessions '$21' Work 1 attached '$88' 'Team alpha' 4 detached
	queue_fzf_responses ctrl-x:2 cancel
	DOTFILES_TEST_INPUT='n\n' run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'declining a kill should return to the menu' || return 1
	assert_contains "$COMMAND_OUTPUT" "Kill session 'Team alpha'? [y/N] " 'kill confirmation should resolve and show the exact name' || return 1
	assert_no_tmux_mutation 'declining kill should leave every session unchanged' || return 1
	assert_eq 2 "$(<"$FZF_COUNTER")" 'declining kill should refresh the menu' || return 1
	assert_eq 2 "$(awk 'END { print NR + 0 }' "$FIXTURE_ROOT/fzf-input.2")" 'decline refresh should retain both sessions' || return 1

	new_fixture
	configure_tmux_starter_fakes
	set_tmux_sessions '$21' Work 1 attached '$88' 'Team alpha' 4 detached
	queue_fzf_responses ctrl-x:2 cancel
	DOTFILES_TEST_INPUT='YeS\n' run_tmux_starter

	assert_eq 0 "$COMMAND_STATUS" 'case-insensitive yes should confirm a kill' || return 1
	assert_contains "$COMMAND_OUTPUT" "Kill session 'Team alpha'? [y/N] " 'confirmed kill should prompt with the selected name' || return 1
	assert_contains "$(<"$CALL_LOG")" '[display-message] [-p] [-t] [\$88]' \
		'kill confirmation should resolve the display name from the exact ID' || return 1
	assert_eq 'kill [\$88]' "$(<"$TMUX_MUTATIONS")" 'confirmed kill should target the exact hidden ID' || return 1
	assert_eq 2 "$(<"$FZF_COUNTER")" 'successful kill should refresh the menu' || return 1
	assert_eq $'$21\tWork\t1 window\tattached' "$(<"$FIXTURE_ROOT/fzf-input.2")" \
		'the refreshed menu should omit only the killed session'
}

test_ctrl_x_failure_is_visible_nonzero_and_does_not_refresh() {
	new_fixture
	configure_tmux_starter_fakes
	set_tmux_sessions '$31' 'Failure target' 2 detached
	printf '37\n' >"$TMUX_KILL_STATUS"
	queue_fzf_responses ctrl-x:1
	DOTFILES_TEST_INPUT='y\n' run_tmux_starter

	assert_eq 37 "$COMMAND_STATUS" 'tmux kill failure should propagate a nonzero status' || return 1
	assert_contains "$COMMAND_OUTPUT" 'fake kill failed with status 37' 'tmux kill diagnostics should remain visible' || return 1
	assert_eq 1 "$(<"$FZF_COUNTER")" 'failed kill should stop instead of refreshing' || return 1
	assert_eq $'$31\tFailure target\t2\tdetached' "$(<"$TMUX_SESSION_STATE")" \
		'failed kill should preserve the selected session' || return 1
	assert_no_tmux_mutation 'a failed kill should not be recorded as successful'
}

set -e
run_test test_missing_exact_runtime_tools_fail_with_status_127 \
	'missing exact runtime tools fail with status 127'
run_test test_real_pane_and_unreadable_tty_refuse_nesting \
	'real pane and unreadable TTY refuse nesting'
run_test test_leaked_and_invalid_tmux_environment_is_cleared \
	'leaked and invalid tmux environment is cleared'
run_test test_empty_starter_keeps_ctrl_n_available_and_placeholder_non_actionable \
	'empty starter keeps Ctrl-N available and its placeholder non-actionable'
run_test test_fzf_cancel_no_match_and_unexpected_failures_use_distinct_statuses \
	'fzf cancel, no-match, and unexpected failures use distinct statuses'
run_test test_hostile_fzf_defaults_cannot_change_attach_or_control_output \
	'hostile fzf defaults cannot change attach or control output'
run_test test_session_rows_are_unique_informative_and_attach_by_exact_id \
	'session rows are unique and informative and attach by exact ID'
run_test test_ctrl_n_uses_atomic_default_custom_and_existing_names_with_pwd \
	'Ctrl-N uses atomic default, custom, and existing names with PWD'
run_test test_ctrl_x_decline_and_confirm_use_exact_id_and_refresh \
	'Ctrl-X decline and confirmation use exact ID and refresh'
run_test test_ctrl_x_failure_is_visible_nonzero_and_does_not_refresh \
	'Ctrl-X failure is visible and nonzero and does not refresh'
finish_tests
