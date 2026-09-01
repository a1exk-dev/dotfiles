#!/usr/bin/env bash

# Keep repeated production wallpaper-file operations in one Node process. The
# server uses the same implementation as the normal CLI and only amortizes
# process startup across operation calls.
# Responses contain an ASCII status/byte-length header, then raw stdout and
# stderr frames, each followed by the fixed ASCII terminator.

readonly WALLPAPER_TEST_FAST_FRAME_TERMINATOR=F
WALLPAPER_TEST_FAST_JSON_QUOTE=''
WALLPAPER_TEST_FAST_SERVER_PID=''
WALLPAPER_TEST_FAST_SERVER_INPUT=''
WALLPAPER_TEST_FAST_SERVER_OUTPUT=''
WALLPAPER_TEST_FAST_SERVER_DIRECTORY=''
WALLPAPER_TEST_FAST_SERVER_STDERR=''

wallpaper_test_fast_json_quote() {
	local value=$1 quote='"' escaped_quote='\"' control_character control_escape octal code
	local LC_ALL=C
	value=${value//\\/\\\\}
	value=${value//"$quote"/$escaped_quote}
	for ((code = 1; code <= 31; code++)); do
		case $code in
			8) control_escape='\b' ;;
			9) control_escape='\t' ;;
			10) control_escape='\n' ;;
			12) control_escape='\f' ;;
			13) control_escape='\r' ;;
			*) printf -v control_escape '\\u%04x' "$code" ;;
		esac
		printf -v octal '\\%03o' "$code"
		printf -v control_character '%b' "$octal"
		value=${value//"$control_character"/$control_escape}
	done
	WALLPAPER_TEST_FAST_JSON_QUOTE="\"$value\""
}

wallpaper_test_fast_server_start() {
	local directory stderr_file node_command
	directory=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-wallpaper-files.XXXXXX") || return 1
	stderr_file="$directory/server.stderr"
	node_command=${WALLPAPER_TEST_FAST_NODE_COMMAND:-node}
	coproc WALLPAPER_TEST_FAST_SERVER {
		"$node_command" "$WALLPAPER_FILES_HELPER" --server 2>"$stderr_file"
	}
	WALLPAPER_TEST_FAST_SERVER_PID=$WALLPAPER_TEST_FAST_SERVER_PID
	WALLPAPER_TEST_FAST_SERVER_DIRECTORY=$directory
	WALLPAPER_TEST_FAST_SERVER_STDERR=$stderr_file
	WALLPAPER_TEST_FAST_SERVER_INPUT=${WALLPAPER_TEST_FAST_SERVER[1]}
	WALLPAPER_TEST_FAST_SERVER_OUTPUT=${WALLPAPER_TEST_FAST_SERVER[0]}
	if ! wallpaper_test_fast_server_probe; then
		wallpaper_test_fast_server_report_failure
		wallpaper_test_fast_server_stop
		return 1
	fi
}

wallpaper_test_fast_server_stop() {
	local pid=$WALLPAPER_TEST_FAST_SERVER_PID directory=$WALLPAPER_TEST_FAST_SERVER_DIRECTORY
	if [[ -n $WALLPAPER_TEST_FAST_SERVER_INPUT ]]; then
		eval "exec ${WALLPAPER_TEST_FAST_SERVER_INPUT}>&-" || true
		WALLPAPER_TEST_FAST_SERVER_INPUT=''
	fi
	if [[ -n $WALLPAPER_TEST_FAST_SERVER_OUTPUT ]]; then
		eval "exec ${WALLPAPER_TEST_FAST_SERVER_OUTPUT}<&-" || true
		WALLPAPER_TEST_FAST_SERVER_OUTPUT=''
	fi
	if [[ -n $pid ]]; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
		WALLPAPER_TEST_FAST_SERVER_PID=''
	fi
	if [[ -n $directory ]]; then rm -rf -- "$directory"; fi
	WALLPAPER_TEST_FAST_SERVER_DIRECTORY=''
	WALLPAPER_TEST_FAST_SERVER_STDERR=''
}

wallpaper_test_fast_server_report_failure() {
	local stderr_file=$WALLPAPER_TEST_FAST_SERVER_STDERR line

	printf 'Error: wallpaper file server failed; its request pipe was closed.\n' >&2
	if [[ -n $stderr_file && -s $stderr_file ]]; then
		while IFS= read -r line || [[ -n $line ]]; do
			printf '%s\n' "$line" >&2
		done <"$stderr_file"
	fi
}

wallpaper_test_fast_server_probe() {
	local header stdout_length stderr_length total

	if ! printf '["__dotfiles_test_ready__"]\n' >&"$WALLPAPER_TEST_FAST_SERVER_INPUT"; then
		return 1
	fi
	if ! IFS= read -r header <&"$WALLPAPER_TEST_FAST_SERVER_OUTPUT"; then
		return 1
	fi
	local response_pattern='^status=(0|[1-9][0-9]*) stdout=(0|[1-9][0-9]*) stderr=(0|[1-9][0-9]*)$'
	[[ $header =~ $response_pattern ]] || return 1
	stdout_length=${BASH_REMATCH[2]}
	stderr_length=${BASH_REMATCH[3]}
	total=$((stdout_length + stderr_length + 2))
	dd iflag=fullblock bs=64K count="${total}B" status=none <&"$WALLPAPER_TEST_FAST_SERVER_OUTPUT" >/dev/null
}

wallpaper_test_fast_server_read_frame() {
	local length=$1 stream=$2 mode=${3-raw} terminator text
	local LC_ALL=C
	[[ $length =~ ^(0|[1-9][0-9]*)$ ]] || {
		printf 'Error: invalid wallpaper file server frame length.\n' >&2
		return 1
	}
	if [[ $length != 0 ]]; then
		if [[ $mode == text ]]; then
			if ! IFS= read -r -N "$length" text <&"$WALLPAPER_TEST_FAST_SERVER_OUTPUT"; then
				printf 'Error: wallpaper file server stopped while reading its %s frame.\n' "$stream" >&2
				return 1
			fi
			if [[ $stream == stdout ]]; then
				printf '%s' "$text"
			else
				printf '%s' "$text" >&2
			fi
		elif [[ $stream == stdout ]]; then
			# GNU dd's byte-count suffix and fullblock flag preserve raw bytes while
			# avoiding a text-valued Bash variable for the frame.
			dd iflag=fullblock bs=64K count="${length}B" status=none <&"$WALLPAPER_TEST_FAST_SERVER_OUTPUT" || {
				printf 'Error: wallpaper file server stopped while reading its %s frame.\n' "$stream" >&2
				return 1
			}
		else
			dd iflag=fullblock bs=64K count="${length}B" status=none <&"$WALLPAPER_TEST_FAST_SERVER_OUTPUT" >&2 || {
				printf 'Error: wallpaper file server stopped while reading its %s frame.\n' "$stream" >&2
				return 1
			}
		fi
	fi
	terminator=''
	# The terminator is deliberately ASCII: Bash can validate it without ever
	# storing the preceding binary frame in a shell variable.
	if ! IFS= read -r -N 1 terminator <&"$WALLPAPER_TEST_FAST_SERVER_OUTPUT"; then
		printf 'Error: wallpaper file server stopped while reading its %s frame.\n' "$stream" >&2
		return 1
	fi
	if [[ $terminator != "$WALLPAPER_TEST_FAST_FRAME_TERMINATOR" ]]; then
		printf 'Error: invalid wallpaper file server %s frame terminator.\n' "$stream" >&2
		return 1
	fi
}

wallpaper_test_fast_server_request() {
	local operation=$1 request='[' response status stdout_length stderr_length arg
	shift
	wallpaper_test_fast_json_quote "$operation"
	request+=$WALLPAPER_TEST_FAST_JSON_QUOTE
	for arg in "$@"; do
		request+=','
		wallpaper_test_fast_json_quote "$arg"
		request+=$WALLPAPER_TEST_FAST_JSON_QUOTE
	done
	request+=']'
	if ! printf '%s\n' "$request" >&"$WALLPAPER_TEST_FAST_SERVER_INPUT"; then
		printf 'Error: wallpaper file server stopped before accepting a request.\n' >&2
		wallpaper_test_fast_server_report_failure
		return 1
	fi
	if ! IFS= read -r response <&"$WALLPAPER_TEST_FAST_SERVER_OUTPUT"; then
		printf 'Error: wallpaper file server stopped without returning a response.\n' >&2
		wallpaper_test_fast_server_report_failure
		return 1
	fi
	local response_pattern='^status=(0|[1-9][0-9]*) stdout=(0|[1-9][0-9]*) stderr=(0|[1-9][0-9]*)$'
	if [[ ! $response =~ $response_pattern ]]; then
		printf 'Error: invalid wallpaper file server response header: %s\n' "$response" >&2
		return 1
	fi
	status=${BASH_REMATCH[1]} stdout_length=${BASH_REMATCH[2]} stderr_length=${BASH_REMATCH[3]}
	(( status <= 255 )) || {
		printf 'Error: invalid wallpaper file server status: %s\n' "$status" >&2
		return 1
	}
	local stdout_mode=raw
	[[ $operation == read ]] || stdout_mode=text
	wallpaper_test_fast_server_read_frame "$stdout_length" stdout "$stdout_mode" || return 1
	# Every production error is text. Keep it in a Bash variable so ordinary
	# requests do not spawn a dd process just to discard an empty or textual
	# stderr frame. The read operation remains raw because its stdout is a
	# lossless binary payload.
	wallpaper_test_fast_server_read_frame "$stderr_length" stderr text || return 1
	return "$status"
}

wallpaper_test_fast_files() {
	local operation=${1-}
	shift || true
	wallpaper_test_fast_server_request "$operation" "$@"
}
