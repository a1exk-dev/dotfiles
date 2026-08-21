#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly TMUX_STARTER_RELATIVE=.local/libexec/dotfiles/tmux-starter
readonly TMUX_CONFIG_RELATIVE=.config/tmux/tmux.conf

assert_excludes() {
	local haystack=$1
	local needle=$2
	local message=$3

	if [[ $haystack == *"$needle"* ]]; then
		printf '  %s\n  unexpected: %q\n  output:     %q\n' \
			"$message" "$needle" "$haystack" >&2
		return 1
	fi
}

start_isolated_tmux_config() {
	local start_directory=${1:-}

	new_fixture
	ISOLATED_TMUX_SOCKET=$FIXTURE_TMP/tmux-config.sock
	ISOLATED_TMUX_HOME=$FIXTURE_HOME/home.with.dot
	ISOLATED_TMUX_LOG=$FIXTURE_TMP/tmux-config.log
	ISOLATED_TMUX_CONFIG=$FIXTURE_REPO/config/tmux/$TMUX_CONFIG_RELATIVE
	mkdir -p "$ISOLATED_TMUX_HOME"
	if [[ -z $start_directory ]]; then
		start_directory=$ISOLATED_TMUX_HOME
	fi

	if ! env -u TMUX -u TMUX_PANE \
		HOME="$ISOLATED_TMUX_HOME" \
		XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
		tmux -S "$ISOLATED_TMUX_SOCKET" -f "$ISOLATED_TMUX_CONFIG" \
			new-session -d -s config-test -c "$start_directory" 'sleep 300' \
			>"$ISOLATED_TMUX_LOG" 2>&1; then
		printf '  isolated tmux failed to load %s:\n%s\n' \
			"$ISOLATED_TMUX_CONFIG" "$(<"$ISOLATED_TMUX_LOG")" >&2
		cleanup_isolated_tmux_config
		return 1
	fi
}

isolated_tmux() {
	env -u TMUX -u TMUX_PANE \
		HOME="$ISOLATED_TMUX_HOME" \
		XDG_CONFIG_HOME="$FIXTURE_CONFIG" \
		tmux -S "$ISOLATED_TMUX_SOCKET" "$@"
}

cleanup_isolated_tmux_config() {
	local status=0

	if [[ -n ${ISOLATED_TMUX_SOCKET-} && -S $ISOLATED_TMUX_SOCKET ]]; then
		if ! isolated_tmux kill-server >/dev/null 2>&1; then
			printf '  failed to stop isolated tmux socket %s\n' "$ISOLATED_TMUX_SOCKET" >&2
			status=1
		fi
	fi
	unset ISOLATED_TMUX_SOCKET ISOLATED_TMUX_HOME ISOLATED_TMUX_LOG ISOLATED_TMUX_CONFIG
	return "$status"
}

with_isolated_tmux_config() {
	local assertion_function=$1
	local start_directory=${2:-}
	local status=0

	start_isolated_tmux_config "$start_directory" || return 1
	"$assertion_function" || status=$?
	if ! cleanup_isolated_tmux_config && ((status == 0)); then
		status=1
	fi
	return "$status"
}

tmux_binding_details() {
	local table=$1
	local expected_key=$2
	local key note command repeat

	while IFS=$'\t' read -r key note command repeat; do
		if [[ $key == "$expected_key" ]]; then
			printf '%s\t%s\t%s\n' "$note" "$command" "$repeat"
			return 0
		fi
	done < <(isolated_tmux list-keys -T "$table" \
		-F $'#{key_string}\t#{key_note}\t#{key_command}\t#{key_repeat}')
	return 1
}

assert_tmux_binding() {
	local table=$1
	local key=$2
	local expected_note=$3
	local expected_command=$4
	local expected_repeat=${5:-0}
	local actual

	if ! actual=$(tmux_binding_details "$table" "$key"); then
		printf '  expected a %s-table binding for %q\n' "$table" "$key" >&2
		return 1
	fi
	assert_eq "$expected_note"$'\t'"$expected_command"$'\t'"$expected_repeat" "$actual" \
		"$table-table $key should retain its command, description, and repeat behavior"
}

assert_tmux_binding_absent() {
	local table=$1
	local key=$2
	local message=$3
	local actual

	if actual=$(tmux_binding_details "$table" "$key"); then
		printf '  %s\n  unexpected %s-table %q binding: %q\n' \
			"$message" "$table" "$key" "$actual" >&2
		return 1
	fi
}

tmux_option() {
	local scope=$1
	local option=$2

	case $scope in
		global) isolated_tmux show-options -gqv "$option" ;;
		server) isolated_tmux show-options -sqv "$option" ;;
		window) isolated_tmux show-options -gwqv "$option" ;;
		*) printf 'unknown tmux option scope: %s\n' "$scope" >&2; return 64 ;;
	esac
}

assert_tmux_config_uses_shared_fixture_paths() {
	local path

	if [[ -z ${FIXTURE_ROOT-} ]]; then
		printf '  config tests should allocate through new_fixture\n' >&2
		return 1
	fi
	for path in \
		"$ISOLATED_TMUX_SOCKET" \
		"$ISOLATED_TMUX_HOME" \
		"$ISOLATED_TMUX_LOG" \
		"$ISOLATED_TMUX_CONFIG"; do
		if [[ $path != "$FIXTURE_ROOT/"* ]]; then
			printf '  config-test path escaped the shared fixture root: %s\n' "$path" >&2
			return 1
		fi
	done
}

assert_retained_omarchy_baseline() {
	local scope option expected actual table key note command repeat

	assert_tmux_config_uses_shared_fixture_paths || return 1
	while IFS=$'\t' read -r scope option expected; do
		if [[ $expected == '<empty>' ]]; then
			expected=
		fi
		expected=${expected//__SPACE__/$' '}
		actual=$(tmux_option "$scope" "$option") || return 1
		assert_eq "$expected" "$actual" \
			"$scope option $option should retain the Omarchy 4 value" || return 1
	done <<'EOF'
global	default-terminal	tmux-256color
global	mouse	on
global	base-index	1
window	pane-base-index	1
global	renumber-windows	on
global	history-limit	50000
server	escape-time	10
global	focus-events	on
global	set-clipboard	on
global	allow-passthrough	on
window	aggressive-resize	on
global	detach-on-destroy	off
global	extended-keys	on
global	extended-keys-format	csi-u
window	mode-keys	vi
global	status-position	top
global	status-interval	5
global	status-left-length	30
global	status-right-length	50
global	window-status-separator	<empty>
window	automatic-rename	on
global	set-titles	on
global	set-titles-string	#h:#W
global	status-style	bg=default,fg=default
global	status-left	#[fg=black,bg=blue,bold] #S #[bg=default]__SPACE__
global	window-status-format	#[fg=brightblack] #I:#W__SPACE__
global	window-status-current-format	#[fg=blue,bold] #I:#W__SPACE__
global	pane-border-style	fg=brightblack
global	pane-active-border-style	fg=blue
global	message-style	bg=default,fg=blue
global	message-command-style	bg=default,fg=blue
global	mode-style	bg=blue,fg=black
window	clock-mode-colour	blue
EOF

	actual=$(tmux_option global terminal-overrides) || return 1
	assert_contains "$actual" '*:RGB' \
		'Omarchy RGB terminal capability should remain enabled' || return 1
	actual=$(tmux_option global terminal-features) || return 1
	assert_contains "$actual" 'xterm-kitty:extkeys' \
		'Omarchy Kitty extended-key capability should remain enabled' || return 1
	assert_contains "$actual" '*:clipboard' \
		'Omarchy direct terminal clipboard capability should remain enabled' || return 1

	while IFS=$'\t' read -r table key note command repeat; do
		command=${command//__HOME__/$ISOLATED_TMUX_HOME}
		assert_tmux_binding "$table" "$key" "$note" "$command" "$repeat" || return 1
	done <<'EOF'
prefix	q	Reload configuration	source-file __HOME__/.config/tmux/tmux.conf \; display-message "Configuration reloaded"	0
prefix	?	Show Tmux keybindings	display-popup -E -T "Tmux keybindings" -h "70%" -w "80%" "omarchy-menu-tmux-keybindings --print | less -R"	0
copy-mode-vi	v	Begin selection	send-keys -X begin-selection	0
copy-mode-vi	y	Copy selection	send-keys -X copy-selection-and-cancel	0
root	M-Enter	Split pane vertically	split-window -v -c "#{pane_current_path}"	0
root	M-S-Enter	Split pane horizontally	split-window -h -c "#{pane_current_path}"	0
root	M-Escape	Kill pane	kill-pane	0
prefix	h	Split pane vertically	split-window -v -c "#{pane_current_path}"	0
prefix	v	Split pane horizontally	split-window -h -c "#{pane_current_path}"	0
prefix	x	Kill pane	kill-pane	0
root	C-M-Left	Focus pane left	select-pane -L	0
root	C-M-Right	Focus pane right	select-pane -R	0
root	C-M-Up	Focus pane up	select-pane -U	0
root	C-M-Down	Focus pane down	select-pane -D	0
root	C-M-S-Left	Resize pane left	resize-pane -L 5	0
root	C-M-S-Down	Resize pane down	resize-pane -D 5	0
root	C-M-S-Up	Resize pane up	resize-pane -U 5	0
root	C-M-S-Right	Resize pane right	resize-pane -R 5	0
prefix	r	Rename window	command-prompt -I "#W" "rename-window -- '%%'"	0
prefix	c	Create window	new-window -c "#{pane_current_path}"	0
prefix	k	Kill window	kill-window	0
root	M-1	Switch to window 1	select-window -t 1	0
root	M-2	Switch to window 2	select-window -t 2	0
root	M-3	Switch to window 3	select-window -t 3	0
root	M-4	Switch to window 4	select-window -t 4	0
root	M-5	Switch to window 5	select-window -t 5	0
root	M-6	Switch to window 6	select-window -t 6	0
root	M-7	Switch to window 7	select-window -t 7	0
root	M-8	Switch to window 8	select-window -t 8	0
root	M-9	Switch to window 9	select-window -t 9	0
root	M-Left	Previous window	select-window -t -1	0
root	M-Right	Next window	select-window -t +1	0
root	M-S-Left	Move window left	swap-window -t -1 \; select-window -t -1	0
root	M-S-Right	Move window right	swap-window -t +1 \; select-window -t +1	0
prefix	R	Rename session	command-prompt -I "#S" "rename-session -- '%%'"	0
prefix	C	Create session	new-session -c "#{pane_current_path}"	0
prefix	K	Kill session	kill-session	0
prefix	P	Previous session	switch-client -p	0
prefix	N	Next session	switch-client -n	0
root	M-Up	Previous session	switch-client -p	0
root	M-Down	Next session	switch-client -n	0
EOF
}

test_complete_config_retains_the_omarchy_baseline() {
	with_isolated_tmux_config assert_retained_omarchy_baseline
}

assert_approved_tmux_prefixes() {
	local primary secondary

	primary=$(tmux_option global prefix) || return 1
	secondary=$(tmux_option global prefix2) || return 1
	assert_eq C-a "$primary" 'C-a should be the primary tmux prefix' || return 1
	assert_eq C-Space "$secondary" 'C-Space should be the secondary tmux prefix' || return 1
	assert_tmux_binding prefix C-a 'Send prefix' send-prefix 0
}

test_config_uses_only_the_approved_prefixes() {
	with_isolated_tmux_config assert_approved_tmux_prefixes
}

assert_approved_split_bindings() {
	assert_tmux_binding prefix % 'Split pane horizontally' \
		'split-window -h -c "#{pane_current_path}"' 0 || return 1
	assert_tmux_binding prefix '|' 'Split pane horizontally' \
		'split-window -h -c "#{pane_current_path}"' 0 || return 1
	assert_tmux_binding prefix '"' 'Split pane vertically' \
		'split-window -v -c "#{pane_current_path}"' 0
}

test_config_splits_in_the_current_pane_directory() {
	with_isolated_tmux_config assert_approved_split_bindings
}

assert_approved_root_pane_focus_bindings() {
	assert_tmux_binding root M-h 'Focus pane left' 'select-pane -L' 0 || return 1
	assert_tmux_binding root M-j 'Focus pane down' 'select-pane -D' 0 || return 1
	assert_tmux_binding root M-k 'Focus pane up' 'select-pane -U' 0 || return 1
	assert_tmux_binding root M-l 'Focus pane right' 'select-pane -R' 0
}

test_config_adds_vim_style_root_pane_focus() {
	with_isolated_tmux_config assert_approved_root_pane_focus_bindings
}

wait_for_command_based_window_name() {
	local attempt actual

	for ((attempt = 0; attempt < 40; attempt++)); do
		actual=$(isolated_tmux display-message -p -t config-test:1 \
			'#{pane_current_command}|#{window_name}') || return 1
		if [[ $actual == 'sleep|sleep' ]]; then
			return 0
		fi
		sleep 0.05
	done
	printf '  automatic window name did not follow pane command; last value: %q\n' "$actual" >&2
	return 1
}

assert_approved_window_and_session_names() {
	local format host title session_name

	format=$(tmux_option window automatic-rename-format) || return 1
	assert_eq '#{pane_current_command}' "$format" \
		'automatic window names should use exactly pane_current_command' || return 1
	isolated_tmux respawn-pane -k -t config-test:1 /bin/bash || return 1
	isolated_tmux send-keys -t config-test:1 'sleep 300' Enter || return 1
	wait_for_command_based_window_name || return 1

	host=$(isolated_tmux display-message -p '#h') || return 1
	title=$(isolated_tmux display-message -p '#{E:set-titles-string}') || return 1
	assert_eq "$host:sleep" "$title" \
		'the expanded outer title should remain short-host:command-window' || return 1

	isolated_tmux new-session -d -s 0 'sleep 300' || return 1
	session_name=$(isolated_tmux display-message -p -t '=0:' '#S') || return 1
	assert_eq 0 "$session_name" 'a session named 0 should not be renamed to main'
}

test_config_names_windows_by_command_without_renaming_sessions() {
	with_isolated_tmux_config assert_approved_window_and_session_names
}

assert_approved_status_structure_and_home_path() {
	local status status_right expanded short_path window_format

	status=$(tmux_option global status) || return 1
	assert_eq on "$status" 'the native status bar should occupy one line' || return 1
	status=$(tmux_option global status-position) || return 1
	assert_eq top "$status" 'the native status bar should remain at the top' || return 1

	window_format=$(tmux_option global window-status-format) || return 1
	assert_contains "$window_format" '#I:#W' \
		'the native window-list slot should use normal index and window name fields' || return 1
	status_right=$(tmux_option global status-right) || return 1
	assert_contains "$status_right" '#{?pane_in_mode,COPY ,}' \
		'the right status should retain the COPY indicator' || return 1
	assert_contains "$status_right" '#{?client_prefix,PREFIX ,}' \
		'the right status should retain the PREFIX indicator' || return 1
	assert_contains "$status_right" '#{?window_zoomed_flag,ZOOM ,}' \
		'the right status should retain the ZOOM indicator' || return 1
	assert_contains "$status_right" '/.../:' \
		'the right status should use native marked suffix trimming' || return 1
	assert_contains "$status_right" '#{HOME}' \
		'the right status should compare against the tmux HOME environment' || return 1
	assert_contains "$status_right" 'pane_current_path' \
		'the right status should derive its value from the active pane path' || return 1
	assert_excludes "$status_right" '#h' \
		'the right status should omit the hostname' || return 1
	assert_excludes "$status_right" '#{pane_title}' \
		'the right status should omit the pane title' || return 1
	assert_excludes "$status_right" '#{W:' \
		'the right status should not embed a replacement window loop' || return 1
	assert_excludes "$status_right" '#(' \
		'the right status should not launch a shell subprocess' || return 1

	short_path=$ISOLATED_TMUX_HOME/work/repo
	mkdir -p "$short_path"
	isolated_tmux respawn-pane -k -t config-test:1 -c "$short_path" 'sleep 300' || return 1
	expanded=$(isolated_tmux display-message -p -t config-test:1 '#{E:status-right}') || return 1
	assert_eq '#[fg=blue]#[fg=brightblack]~/work/repo ' "$expanded" \
		'the expanded status should abbreviate the active pane home path'
}

test_config_keeps_native_status_with_abbreviated_active_path() {
	with_isolated_tmux_config assert_approved_status_structure_and_home_path
}

assert_status_path_uses_a_marked_32_column_suffix() {
	local long_path expanded path_field status_style_prefix

	long_path=$ISOLATED_TMUX_HOME/discarded-prefix/dev-workspace/project/subdir
	mkdir -p "$long_path"
	isolated_tmux respawn-pane -k -t config-test:1 -c "$long_path" 'sleep 300' || return 1
	expanded=$(isolated_tmux display-message -p -t config-test:1 '#{E:status-right}') || return 1
	assert_eq '#[fg=blue]#[fg=brightblack].../dev-workspace/project/subdir ' "$expanded" \
		'the expanded status should mark a left-trimmed path and preserve its suffix' || return 1
	status_style_prefix='#[fg=blue]#[fg=brightblack]'
	path_field=${expanded#"$status_style_prefix"}
	path_field=${path_field% }
	assert_eq 32 "${#path_field}" \
		'the marked path field should remain within its full 32-column budget'
}

test_status_path_uses_a_marked_32_column_suffix() {
	with_isolated_tmux_config assert_status_path_uses_a_marked_32_column_suffix
}

assert_status_path_respects_the_32_column_boundary() {
	local width component expected path expanded path_field status_style_prefix

	status_style_prefix='#[fg=blue]#[fg=brightblack]'
	while IFS=$'\t' read -r width component expected; do
		path=$ISOLATED_TMUX_HOME/$component
		mkdir -p "$path"
		isolated_tmux respawn-pane -k -t config-test:1 -c "$path" 'sleep 300' || return 1
		expanded=$(isolated_tmux display-message -p -t config-test:1 '#{E:status-right}') || return 1
		path_field=${expanded#"$status_style_prefix"}
		path_field=${path_field% }
		assert_eq "$expected" "$path_field" \
			"a normalized path of display width $width should respect the 32-column boundary" || return 1
	done <<'EOF'
29	abcdefghijklmnopqrstuvwxyz0	~/abcdefghijklmnopqrstuvwxyz0
30	abcdefghijklmnopqrstuvwxyz01	~/abcdefghijklmnopqrstuvwxyz01
31	abcdefghijklmnopqrstuvwxyz012	~/abcdefghijklmnopqrstuvwxyz012
32	abcdefghijklmnopqrstuvwxyz0123	~/abcdefghijklmnopqrstuvwxyz0123
33	abcdefghijklmnopqrstuvwxyz01234	...cdefghijklmnopqrstuvwxyz01234
EOF
}

test_status_path_respects_the_32_column_boundary() {
	with_isolated_tmux_config assert_status_path_respects_the_32_column_boundary
}

assert_status_abbreviates_only_an_exact_home_prefix() {
	local outside_home expanded

	isolated_tmux respawn-pane -k -t config-test:1 -c "$ISOLATED_TMUX_HOME" 'sleep 300' || return 1
	expanded=$(isolated_tmux display-message -p -t config-test:1 '#{E:status-right}') || return 1
	assert_eq '#[fg=blue]#[fg=brightblack]~ ' "$expanded" \
		'an active pane at HOME should abbreviate to exactly a tilde' || return 1

	outside_home=$FIXTURE_HOME/homeXwithXdot/project
	mkdir -p "$outside_home"
	isolated_tmux respawn-pane -k -t config-test:1 -c "$outside_home" 'sleep 300' || return 1
	expanded=$(isolated_tmux display-message -p -t config-test:1 '#{E:status-right}') || return 1
	assert_excludes "$expanded" '~' \
		'a regex lookalike outside HOME should not be abbreviated' || return 1
	assert_contains "$expanded" '/homeXwithXdot/project ' \
		'an outside-home path should retain its real suffix after trimming'
}

test_status_abbreviates_only_an_exact_home_prefix() {
	with_isolated_tmux_config assert_status_abbreviates_only_an_exact_home_prefix
}

assert_approved_archived_behavior_is_absent() {
	local config lower_config forbidden

	assert_tmux_binding prefix l 'Select the previously current window' last-window 0 || return 1
	assert_tmux_binding prefix - 'Delete the most recent paste buffer' delete-buffer 0 || return 1
	assert_tmux_binding_absent prefix j \
		'archived prefix j pane focus should remain rejected' || return 1
	assert_tmux_binding_absent prefix S \
		'archived named-session prompt should remain rejected' || return 1
	assert_tmux_binding_absent prefix X \
		'archived confirmed session kill should remain rejected' || return 1

	config=$(<"$ISOLATED_TMUX_CONFIG")
	lower_config=${config,,}
	for forbidden in tpm tmux-resurrect tmux-continuum snapshot '@plugin' '.tmux/plugins'; do
		assert_excludes "$lower_config" "$forbidden" \
			"complete config should omit persistence artifact $forbidden" || return 1
	done
	assert_excludes "$config" '@ef_' \
		'complete config should omit archived Everforest variables' || return 1
	assert_excludes "$config" '#{pane_title}' \
		'complete config should omit pane-title status content' || return 1
	assert_excludes "$config" '#{W:' \
		'complete config should omit an embedded window loop' || return 1
	assert_excludes "$config" '#(' \
		'complete config should omit shell-backed format jobs' || return 1
	if [[ $config =~ (fg|bg)=\#[[:xdigit:]]{6} ]]; then
		printf '  complete config contains a hard-coded RGB style: %s\n' \
			"${BASH_REMATCH[0]}" >&2
		return 1
	fi
	if LC_ALL=C grep -q '[^[:print:][:space:]]' "$ISOLATED_TMUX_CONFIG"; then
		printf '  complete config should contain no icon or other non-ASCII glyphs\n' >&2
		return 1
	fi
}

test_config_omits_rejected_archived_behavior() {
	with_isolated_tmux_config assert_approved_archived_behavior_is_absent
}

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
run_test test_complete_config_retains_the_omarchy_baseline \
	'complete config retains the Omarchy 4 baseline'
run_test test_config_uses_only_the_approved_prefixes \
	'config uses only the approved prefixes'
run_test test_config_splits_in_the_current_pane_directory \
	'config splits in the current pane directory'
run_test test_config_adds_vim_style_root_pane_focus \
	'config adds Vim-style root pane focus'
run_test test_config_names_windows_by_command_without_renaming_sessions \
	'config names windows by command without renaming sessions'
run_test test_config_keeps_native_status_with_abbreviated_active_path \
	'config keeps native status with abbreviated active path'
run_test test_status_path_uses_a_marked_32_column_suffix \
	'status path uses a marked 32-column suffix'
run_test test_status_path_respects_the_32_column_boundary \
	'status path respects the 32-column boundary'
run_test test_status_abbreviates_only_an_exact_home_prefix \
	'status abbreviates only an exact home prefix'
run_test test_config_omits_rejected_archived_behavior \
	'config omits rejected archived behavior'
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
