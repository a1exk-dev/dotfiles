#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly STARSHIP_SOURCE_RELATIVE=config/starship/.config/starship.toml
readonly STARSHIP_SELECTED_FEATURE_BYTES=3203
readonly STARSHIP_SELECTED_FEATURE_SHA256=d6e2aa02b4dd42062e2930255182d819a0495b948a5ff65c36ecc873eabe20f2
readonly STARSHIP_SUCCESS_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /fixture/project \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_FAILURE_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /fixture/project \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\234\227\\[\033[0m\\] '
readonly STARSHIP_DEEP_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] \342\200\246/beta/gamma \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_READ_ONLY_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /fixture/readonly\\[\033[0m\\]\\[\033[44;31m\\]\360\237\224\222\\[\033[1;30m\\] \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_CLEAN_GIT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[45;30m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_MODIFIED_GIT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[45;30m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\\[\033[45;30m\\]\356\251\2611 \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_UNTRACKED_GIT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[45;30m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\\[\033[45;30m\\]?1 \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_LANGUAGE_POLYGLOT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /fixture/project \\[\033[0m\\]\\[\033[46;30m\\] \356\230\236 v13.2.1 \356\236\250 v1.80.1 \356\230\247 v1.23.4 \356\234\230 v22.12.0 \356\230\210 v8.3.14 \356\211\226 v21.0.4 \356\230\264 v2.0.21 \356\230\237 9.10.1 \356\230\206 v3.13.1 \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_ENVIRONMENT_CONTEXT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[46;30m\\] \356\230\206 v3.13.1 \\[\033[42m\\] \357\214\210 remote-builder \360\237\205\222 research \360\237\247\232 v0.41.4 \\[\033[45m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_PIXI_ENVIRONMENT_CONTEXT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[46;30m\\] \356\230\206 v3.13.1 \\[\033[42m\\] \357\214\210 remote-builder \360\237\247\232 v0.41.4 dev \\[\033[45m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_ENVIRONMENT_ONLY_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /environment \\[\033[0m\\]\\[\033[42;30m\\] \357\214\210 remote-builder \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_LANGUAGE_ENVIRONMENT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /language-environment \\[\033[0m\\]\\[\033[46;30m\\] \356\234\230 v22.12.0 \\[\033[42m\\] \357\214\210 remote-builder \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_LANGUAGE_GIT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /language-git \\[\033[0m\\]\\[\033[46;30m\\] \356\234\230 v22.12.0 \\[\033[45m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_ENVIRONMENT_GIT_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /all-groups \\[\033[0m\\]\\[\033[42;30m\\] \357\214\210 remote-builder \\[\033[45m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_ALL_GROUPS_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /all-groups \\[\033[0m\\]\\[\033[46;30m\\] \356\234\230 v22.12.0 \\[\033[42m\\] \357\214\210 remote-builder \\[\033[45m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\\[\033[45;30m\\]?1 \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_ALL_GROUPS_FAILURE_PROMPT=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /all-groups \\[\033[0m\\]\\[\033[46;30m\\] \356\234\230 v22.12.0 \\[\033[42m\\] \357\214\210 remote-builder \\[\033[45m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\\[\033[45;30m\\]?1 \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\234\227\\[\033[0m\\] '
readonly -a STARSHIP_DIRECTORY_COMPONENTS=(Documents Downloads Music Pictures Projects)
readonly -a STARSHIP_DIRECTORY_GLYPHS=('󰈙' '' '󰝚' '' '')
readonly -a STARSHIP_LANGUAGE_MODULES=(c rust golang nodejs php java kotlin haskell python)
readonly -a STARSHIP_LANGUAGE_OUTPUTS=(
	$'\033[46;30m\356\230\236 v13.2.1 \033[0m'
	$'\033[46;30m\356\236\250 v1.80.1 \033[0m'
	$'\033[46;30m\356\230\247 v1.23.4 \033[0m'
	$'\033[46;30m\356\234\230 v22.12.0 \033[0m'
	$'\033[46;30m\356\230\210 v8.3.14 \033[0m'
	$'\033[46;30m\356\211\226 v21.0.4 \033[0m'
	$'\033[46;30m\356\230\264 v2.0.21 \033[0m'
	$'\033[46;30m\356\230\237 9.10.1 \033[0m'
	$'\033[46;30m\356\230\206 v3.13.1 \033[0m'
)
readonly -a STARSHIP_LANGUAGE_VERSION_CALLS=(
	'cc <--version>'
	'rustc <--version>'
	'go <version>'
	'node <--version>'
	'php <-nr> <echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;>'
	'java <-Xinternalversion>'
	'kotlin <-version>'
	'ghc <--numeric-version>'
	'python <--version>'
)

setup_starship_runtime() {
	new_fixture || return 1
	STARSHIP_FIXTURE_CONFIG=$FIXTURE_REPO/$STARSHIP_SOURCE_RELATIVE
	STARSHIP_RUNTIME=$FIXTURE_ROOT/starship-runtime
	STARSHIP_RUNTIME_PATH=/usr/bin:/bin
	STARSHIP_COMMAND_PATH=$STARSHIP_RUNTIME_PATH
	STARSHIP_RUNTIME_CALL_LOG=
	STARSHIP_RUNTIME_ENV=()
	mkdir -p \
		"$STARSHIP_RUNTIME/home" \
		"$STARSHIP_RUNTIME/project" \
		"$STARSHIP_RUNTIME/deep/alpha/beta/gamma" \
		"$STARSHIP_RUNTIME/readonly" || return 1
	chmod 0555 "$STARSHIP_RUNTIME/readonly" || return 1
	BWRAP_EXTRA_ARGS+=(--bind "$STARSHIP_RUNTIME" /mnt)
}

setup_starship_directory_runtime() {
	setup_starship_runtime || return 1
	STARSHIP_DIRECTORY_ROOT=$STARSHIP_RUNTIME/home
	local component
	for component in "${STARSHIP_DIRECTORY_COMPONENTS[@]}" MyDocuments DocumentsArchive; do
		mkdir -p "$STARSHIP_DIRECTORY_ROOT/$component/child" || return 1
	done
	for component in "${STARSHIP_DIRECTORY_COMPONENTS[@]}"; do
		mkdir -p \
			"$STARSHIP_DIRECTORY_ROOT/repeated/$component/hidden/$component/child" \
			"$STARSHIP_DIRECTORY_ROOT/repeated/$component/$component" || return 1
	done
	mkdir -p \
		"$STARSHIP_DIRECTORY_ROOT/Documents/readonly" \
		"$STARSHIP_DIRECTORY_ROOT/Projects/repository/child" \
		"$STARSHIP_DIRECTORY_ROOT/Workspace/repository" || return 1
	chmod 0555 "$STARSHIP_DIRECTORY_ROOT/Documents/readonly" || return 1
}

setup_starship_controlled_tool_runtime() {
	setup_starship_runtime || return 1
	STARSHIP_LANGUAGE_ROOT=$STARSHIP_RUNTIME/languages
	STARSHIP_ENVIRONMENT_ROOT=$STARSHIP_RUNTIME/environments
	STARSHIP_TOOL_BIN=$STARSHIP_RUNTIME/tool-bin
	STARSHIP_TOOL_CALL_LOG=$STARSHIP_RUNTIME/tool-calls
	STARSHIP_RUNTIME_PATH=/mnt/tool-bin:/usr/bin:/bin
	STARSHIP_COMMAND_PATH=$STARSHIP_RUNTIME_PATH
	STARSHIP_RUNTIME_CALL_LOG=/mnt/tool-calls
	mkdir -p "$STARSHIP_LANGUAGE_ROOT" "$STARSHIP_ENVIRONMENT_ROOT" "$STARSHIP_TOOL_BIN" || return 1
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	cat >"$STARSHIP_TOOL_BIN/fake-starship-tool" <<'EOF' || return 1
#!/usr/bin/env bash

set -u

tool=${0##*/}
if [[ -n ${DOTFILES_TEST_STARSHIP_TOOL_CALL_LOG-} ]]; then
	invocation=$tool
	for arg in "$@"; do
		invocation+=" <$arg>"
	done
	printf '%s\n' "$invocation" >>"$DOTFILES_TEST_STARSHIP_TOOL_CALL_LOG"
fi

invalid_args() {
	printf 'unexpected %s arguments\n' "$tool" >&2
	exit 64
}

case $tool in
	cc)
		[[ $# -eq 1 && $1 == --version ]] || invalid_args
		printf '%s\n' \
			'cc (GCC) 13.2.1 20230801' \
			'Copyright (C) 2023 Free Software Foundation, Inc.'
		;;
	rustup)
		[[ $# -eq 1 && $1 == default ]] || invalid_args
		exit 1
		;;
	rustc)
		[[ $# -eq 1 && $1 == --version ]] || invalid_args
		printf '%s\n' 'rustc 1.80.1 (3f5fd8dd4 2024-08-06)'
		;;
	go)
		[[ $# -eq 1 && $1 == version ]] || invalid_args
		printf '%s\n' 'go version go1.23.4 linux/amd64'
		;;
	node)
		[[ $# -eq 1 && $1 == --version ]] || invalid_args
		printf '%s\n' 'v22.12.0'
		;;
	php)
		[[ $# -eq 2 && $1 == -nr ]] || invalid_args
		[[ $2 == 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;' ]] || invalid_args
		printf '%s' '8.3.14'
		;;
	java)
		[[ $# -eq 1 && $1 == -Xinternalversion ]] || invalid_args
		printf '%s\n' 'OpenJDK 64-Bit Server VM (21.0.4+7) for linux-amd64 JRE (21.0.4+7), built on Jul 16 2024 00:00:00 by "fixture" with gcc 13.2.1'
		;;
	kotlin)
		[[ $# -eq 1 && $1 == -version ]] || invalid_args
		printf '%s\n' 'Kotlin version 2.0.21-release-482 (JRE 21.0.4+7)'
		;;
	ghc)
		[[ $# -eq 1 && $1 == --numeric-version ]] || invalid_args
		printf '%s\n' '9.10.1'
		;;
	python)
		[[ $# -eq 1 && $1 == --version ]] || invalid_args
		printf '%s\n' 'Python 3.13.1'
		;;
	pixi)
		[[ $# -eq 1 && $1 == --version ]] || invalid_args
		printf '%s\n' 'pixi 0.41.4'
		;;
	docker | conda)
		printf 'unexpected Starship %s command invocation\n' "$tool" >&2
		exit 64
		;;
	c++)
		[[ $# -eq 1 && $1 == --version ]] || invalid_args
		printf '%s\n' \
			'c++ (GCC) 14.2.1 20240801' \
			'Copyright (C) 2024 Free Software Foundation, Inc.'
		;;
	*)
		printf 'unexpected fake tool name: %s\n' "$tool" >&2
		exit 64
		;;
esac
EOF
	chmod 0755 "$STARSHIP_TOOL_BIN/fake-starship-tool" || return 1
	local tool
	for tool in cc rustup rustc go node php java kotlin ghc python pixi docker conda 'c++'; do
		ln -s fake-starship-tool "$STARSHIP_TOOL_BIN/$tool" || return 1
	done
}

setup_starship_language_runtime() {
	setup_starship_controlled_tool_runtime
}

create_starship_language_marker() {
	local module=$1 project=$2
	mkdir -p "$project" || return 1
	case $module in
		c) printf 'int main(void) { return 0; }\n' >"$project/main.c" || return 1 ;;
		rust) printf '[package]\nname = "fixture"\nversion = "0.0.0"\n' >"$project/Cargo.toml" || return 1 ;;
		golang) printf 'module example.invalid/fixture\n' >"$project/go.mod" || return 1 ;;
		nodejs) printf '{}\n' >"$project/package.json" || return 1 ;;
		php) printf '{}\n' >"$project/composer.json" || return 1 ;;
		java) printf 'final class Main {}\n' >"$project/Main.java" || return 1 ;;
		kotlin) printf 'fun main() = Unit\n' >"$project/Main.kt" || return 1 ;;
		haskell) printf 'packages: .\n' >"$project/cabal.project" || return 1 ;;
		python) printf '[project]\nname = "fixture"\nversion = "0.0.0"\n' >"$project/pyproject.toml" || return 1 ;;
		cpp) printf 'int main() { return 0; }\n' >"$project/main.cpp" || return 1 ;;
		*) printf 'unknown language marker: %s\n' "$module" >&2; return 1 ;;
	esac
}

assert_starship_call_logged() {
	local expected=$1
	if ! grep -Fqx -- "$expected" "$STARSHIP_TOOL_CALL_LOG"; then
		printf '  missing controlled Starship tool call: %s\n' "$expected" >&2
		return 1
	fi
}

fixture_git() {
	env -i \
		HOME="$FIXTURE_HOME" \
		PATH=/usr/bin:/bin \
		LANG=C \
		LC_ALL=C \
		TZ=UTC \
		GIT_CONFIG_NOSYSTEM=1 \
		GIT_CONFIG_GLOBAL=/dev/null \
		GIT_AUTHOR_DATE=2000-01-01T00:00:00Z \
		GIT_COMMITTER_DATE=2000-01-01T00:00:00Z \
		git -C "$STARSHIP_GIT_REPO" "$@"
}

setup_starship_git_repository() {
	local repository=${1:-$STARSHIP_RUNTIME/repository}
	local remote=${2:-$STARSHIP_RUNTIME/remote.git}
	STARSHIP_GIT_REPO=$repository
	STARSHIP_GIT_REMOTE=$remote
	mkdir -p "$STARSHIP_GIT_REPO" || return 1
	printf 'baseline\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	printf 'baseline\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	printf 'baseline\n' >"$STARSHIP_GIT_REPO/conflicted1.txt" || return 1
	printf 'baseline\n' >"$STARSHIP_GIT_REPO/conflicted2.txt" || return 1
	env -i HOME="$FIXTURE_HOME" PATH=/usr/bin:/bin LANG=C LC_ALL=C TZ=UTC \
		GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
		git init --bare --initial-branch=baseline "$STARSHIP_GIT_REMOTE" >/dev/null 2>&1 || return 1
	fixture_git init --initial-branch=baseline >/dev/null 2>&1 || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid add \
		tracked.txt tracked2.txt conflicted1.txt conflicted2.txt || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		commit -m baseline >/dev/null 2>&1 || return 1
	fixture_git remote add origin "$STARSHIP_GIT_REMOTE" || return 1
	fixture_git push --set-upstream origin baseline >/dev/null 2>&1 || return 1
}

setup_starship_git_runtime() {
	setup_starship_runtime || return 1
	setup_starship_git_repository
}

create_fixture_git_commit() {
	local label=$1

	printf '%s\n' "$label" >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	fixture_git add -- tracked.txt || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		commit -m "$label" >/dev/null 2>&1 || return 1
}

assert_git_upstream_distance() {
	local expected=$1 upstream remote distance

	upstream=$(fixture_git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}') || return 1
	assert_eq origin/baseline "$upstream" \
		'the controlled Git branch should have a real configured upstream' || return 1
	remote=$(fixture_git remote get-url origin) || return 1
	assert_eq "$STARSHIP_GIT_REMOTE" "$remote" \
		'the controlled upstream should use only the local bare fixture remote' || return 1
	distance=$(fixture_git rev-list --left-right --count 'HEAD...@{upstream}') || return 1
	assert_eq "$expected" "$distance" \
		'the controlled branch should have the exact asserted upstream distance' || return 1
}

create_conflicted_git_state() {
	local count=$1 index merge_status=0 path
	local -a paths=()

	for ((index = 1; index <= count; index++)); do
		path=conflicted${index}.txt
		paths+=("$path")
	done

	fixture_git switch --create conflict-side >/dev/null 2>&1 || return 1
	for path in "${paths[@]}"; do
		printf 'conflict side\n' >"$STARSHIP_GIT_REPO/$path" || return 1
	done
	fixture_git add -- "${paths[@]}" || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		commit -m conflict-side >/dev/null 2>&1 || return 1

	fixture_git switch baseline >/dev/null 2>&1 || return 1
	for path in "${paths[@]}"; do
		printf 'baseline side\n' >"$STARSHIP_GIT_REPO/$path" || return 1
	done
	fixture_git add -- "${paths[@]}" || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		commit -m baseline-side >/dev/null 2>&1 || return 1
	fixture_git push origin baseline >/dev/null 2>&1 || return 1

	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		merge --no-edit conflict-side >/dev/null 2>&1 || merge_status=$?
	if ((merge_status != 1)); then
		printf '  expected Git conflict status 1, got %d\n' "$merge_status" >&2
		return 1
	fi
}

create_git_stash() {
	local label=$1

	printf 'stashed %s\n' "$label" >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		stash push --message "$label" -- tracked.txt >/dev/null 2>&1 || return 1
}

git_stash_count() {
	local stash_list entry count=0

	stash_list=$(fixture_git stash list --format='%gd') || return 1
	if [[ -n $stash_list ]]; then
		while IFS= read -r entry; do
			count=$((count + 1))
		done <<<"$stash_list"
	fi
	printf '%d\n' "$count" || return 1
}

run_starship() {
	run_in_sandbox "$STARSHIP_RUNTIME" "$STARSHIP_RUNTIME_PATH" bash -c '
		set -u
		config=$1
		starship_path=$2
		tool_call_log=$3
		runtime_env_count=$4
		shift 4
		runtime_env=()
		for ((index = 0; index < runtime_env_count; index++)); do
			runtime_env+=("$1")
			shift
		done
		work=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-starship-render.XXXXXX") || exit 1
		cleanup() { rm -rf -- "$work"; }
		trap cleanup EXIT
		trap "exit 1" HUP INT TERM
		mkdir -p -- "$work/cache" || exit 1
		status=0
		(
			cd /mnt || exit 1
			env -i \
				HOME=/mnt/home \
				USER=fixture \
				SHELL=/usr/bin/bash \
				PATH="$starship_path" \
				LANG=C \
				LC_ALL=C \
				TZ=UTC \
				TERM=xterm-256color \
				STARSHIP_SHELL=bash \
				STARSHIP_CONFIG="$config" \
				STARSHIP_CACHE="$work/cache" \
				STARSHIP_SESSION_KEY=dotfiles-starship-render \
				GIT_CONFIG_NOSYSTEM=1 \
				GIT_CONFIG_GLOBAL=/dev/null \
				"${runtime_env[@]}" \
				DOTFILES_TEST_STARSHIP_TOOL_CALL_LOG="$tool_call_log" \
				/usr/bin/starship "$@"
		) >"$work/stdout" 2>"$work/stderr" || status=$?
		if ((status != 0)); then
			cat -- "$work/stderr" >&2
			exit "$status"
		fi
		if [[ -s $work/stderr ]]; then
			cat -- "$work/stderr" >&2
			exit 1
		fi
		cat -- "$work/stdout"
	' bash "$STARSHIP_FIXTURE_CONFIG" "$STARSHIP_COMMAND_PATH" \
		"$STARSHIP_RUNTIME_CALL_LOG" "${#STARSHIP_RUNTIME_ENV[@]}" "${STARSHIP_RUNTIME_ENV[@]}" "$@"
}

render_with_context() {
	local physical_path=$1 logical_path=$2 status=$3
	shift 3
	run_starship "$@" \
		--path "$physical_path" \
		--logical-path "$logical_path" \
		--status "$status" \
		--pipestatus 0 \
		--cmd-duration 0 \
		--jobs 0 \
		--terminal-width 80 \
		--keymap viins \
		--shlvl 1
}

render_prompt() {
	local physical_path=$1 logical_path=$2 status=$3
	render_with_context "$physical_path" "$logical_path" "$status" prompt
}

render_module() {
	local module=$1 physical_path=$2 logical_path=$3 status=$4
	render_with_context "$physical_path" "$logical_path" "$status" module "$module"
}

parse_starship_ansi_line() {
	local line=$1 remaining parameters code character
	local fg=default bg=default bold=0 italic=0 index=0
	local sgr_pattern=$'^\033\\[([0-9;]*)m'
	local -a codes=()
	STARSHIP_CELL_CHARACTERS=()
	STARSHIP_CELL_FOREGROUNDS=()
	STARSHIP_CELL_BACKGROUNDS=()
	STARSHIP_CELL_BOLD=()
	STARSHIP_CELL_ITALIC=()

	while ((index < ${#line})); do
		if [[ ${line:index:2} == '\[' || ${line:index:2} == '\]' ]]; then
			index=$((index + 2))
			continue
		fi
		remaining=${line:index}
		if [[ $remaining =~ $sgr_pattern ]]; then
			parameters=${BASH_REMATCH[1]}
			if [[ -z $parameters ]]; then
				codes=(0)
			else
				IFS=';' read -r -a codes <<<"$parameters"
			fi
			for code in "${codes[@]}"; do
				case $code in
					0) fg=default; bg=default; bold=0; italic=0 ;;
					1) bold=1 ;;
					3) italic=1 ;;
					22) bold=0 ;;
					23) italic=0 ;;
					39) fg=default ;;
					49) bg=default ;;
					*)
						if ((code >= 30 && code <= 37)); then
							fg=$code
						elif ((code >= 40 && code <= 47)); then
							bg=$code
						else
							printf '  unsupported Starship SGR code: %s\n' "$code" >&2
							return 1
						fi
						;;
				esac
			done
			index=$((index + ${#BASH_REMATCH[0]}))
			continue
		fi

		character=${line:index:1}
		STARSHIP_CELL_CHARACTERS+=("$character")
		STARSHIP_CELL_FOREGROUNDS+=("$fg")
		STARSHIP_CELL_BACKGROUNDS+=("$bg")
		STARSHIP_CELL_BOLD+=("$bold")
		STARSHIP_CELL_ITALIC+=("$italic")
		index=$((index + 1))
	done
}

assert_starship_prompt_cells() {
	local LC_ALL=C.UTF-8
	local expected_runs=$1 expected_character=$2 expect_lock=$3 description=$4
	local prompt first_line second_line first_text= second_text= actual_runs= run_text= lock_count=0
	local background previous_background= character foreground bold italic index non_space

	if [[ $COMMAND_OUTPUT != $'\n'* ]]; then
		printf '  %s should retain the leading blank line\n' "$description" >&2
		return 1
	fi
	prompt=${COMMAND_OUTPUT#$'\n'}
	if [[ $prompt != *$'\n'* ]]; then
		printf '  %s should contain two prompt lines\n' "$description" >&2
		return 1
	fi
	first_line=${prompt%%$'\n'*}
	second_line=${prompt#*$'\n'}
	if [[ $second_line == *$'\n'* ]]; then
		printf '  %s should contain exactly two prompt lines\n' "$description" >&2
		return 1
	fi

	parse_starship_ansi_line "$first_line" || return 1
	for character in "${STARSHIP_CELL_CHARACTERS[@]}"; do
		first_text+=$character
	done
	assert_eq '┌─' "${first_text:0:2}" \
		"$description should start with the exact square first-line frame" || return 1
	for index in 0 1; do
		assert_eq 36 "${STARSHIP_CELL_FOREGROUNDS[index]}" \
			"$description first-line frame cell should be cyan" || return 1
		assert_eq default "${STARSHIP_CELL_BACKGROUNDS[index]}" \
			"$description first-line frame cell should use the default background" || return 1
	done

	for ((index = 2; index < ${#STARSHIP_CELL_CHARACTERS[@]}; index++)); do
		character=${STARSHIP_CELL_CHARACTERS[index]}
		foreground=${STARSHIP_CELL_FOREGROUNDS[index]}
		background=${STARSHIP_CELL_BACKGROUNDS[index]}
		bold=${STARSHIP_CELL_BOLD[index]}
		italic=${STARSHIP_CELL_ITALIC[index]}
		case $background in
			44 | 46 | 42 | 45) ;;
			*)
				printf '  %s printed first-line cell %q on background %s\n' \
					"$description" "$character" "$background" >&2
				return 1
				;;
		esac
		if [[ $character == '🔒' ]]; then
			lock_count=$((lock_count + 1))
			assert_eq 31 "$foreground" \
				"$description read-only lock should be red" || return 1
			assert_eq 44 "$background" \
				"$description read-only lock should stay on blue" || return 1
		else
			assert_eq 30 "$foreground" \
				"$description content and padding cells should use black text" || return 1
			if [[ $background == 44 ]]; then
				assert_eq 1 "$bold" \
					"$description directory cells should remain bold" || return 1
			fi
			if [[ $character == '' ]]; then
				assert_eq 1 "$italic" \
					"$description Git branch should remain italic" || return 1
			fi
		fi
		if [[ $background != "$previous_background" ]]; then
			if [[ -n $previous_background ]]; then
				assert_eq ' ' "${run_text:0:1}" \
					"$description background run should start with conditional padding" || return 1
				assert_eq ' ' "${run_text: -1}" \
					"$description background run should end with styled module padding" || return 1
				non_space=${run_text// /}
				[[ -n $non_space ]] || {
					printf '  %s emitted an orphan background %s run\n' \
						"$description" "$previous_background" >&2
					return 1
				}
			fi
			actual_runs+="${actual_runs:+,}$background"
			previous_background=$background
			run_text=
		fi
		run_text+=$character
	done
	if [[ -n $previous_background ]]; then
		assert_eq ' ' "${run_text:0:1}" \
			"$description final background run should start with conditional padding" || return 1
		assert_eq ' ' "${run_text: -1}" \
			"$description final background run should end with styled module padding" || return 1
		non_space=${run_text// /}
		[[ -n $non_space ]] || {
			printf '  %s emitted an orphan final background %s run\n' \
				"$description" "$previous_background" >&2
			return 1
		}
	fi
	assert_eq "$expected_runs" "$actual_runs" \
		"$description should render exactly the selected nonempty background groups" || return 1
	if [[ $expect_lock == true ]]; then
		assert_eq 1 "$lock_count" "$description should render one read-only lock" || return 1
	else
		assert_eq 0 "$lock_count" "$description should not render a read-only lock" || return 1
	fi

	parse_starship_ansi_line "$second_line" || return 1
	for character in "${STARSHIP_CELL_CHARACTERS[@]}"; do
		second_text+=$character
	done
	assert_eq "└─$expected_character " "$second_text" \
		"$description should retain the exact square second-line frame and status shape" || return 1
	for index in 0 1; do
		assert_eq 36 "${STARSHIP_CELL_FOREGROUNDS[index]}" \
			"$description second-line frame cell should be cyan" || return 1
		assert_eq default "${STARSHIP_CELL_BACKGROUNDS[index]}" \
			"$description second-line frame cell should use the default background" || return 1
	done
	assert_eq 36 "${STARSHIP_CELL_FOREGROUNDS[2]}" \
		"$description status character should be cyan" || return 1
	assert_eq 1 "${STARSHIP_CELL_BOLD[2]}" \
		"$description status character should remain bold" || return 1
	assert_eq default "${STARSHIP_CELL_BACKGROUNDS[2]}" \
		"$description status character should use the default background" || return 1
	assert_eq default "${STARSHIP_CELL_BACKGROUNDS[3]}" \
		"$description input padding should use the default background"
}

assert_render_cache_removed() {
	if compgen -G "$FIXTURE_TMP/dotfiles-starship-render.*" >/dev/null; then
		printf '  Starship render should remove its fresh cache root\n' >&2
		return 1
	fi
}

test_installed_starship_version_matches_the_omarchy_baseline() {
	new_fixture || return 1
	run_in_sandbox "$FIXTURE_ROOT" "/usr/bin:/bin" starship --version

	assert_eq 0 "$COMMAND_STATUS" 'the installed Starship binary should report its version' || return 1
	assert_contains "$COMMAND_OUTPUT" $'starship 1.26.0\ntag:v1.26.0' \
		'the focused baseline suite should use Starship 1.26.0'
}

test_tracked_starship_source_has_the_selected_feature_identity() {
	new_fixture || return 1
	local source=$FIXTURE_REPO/$STARSHIP_SOURCE_RELATIVE
	if [[ ! -f $source || -L $source ]]; then
		printf '  blocked by deliberately absent %s; complete the approved live migration first\n' \
			"$STARSHIP_SOURCE_RELATIVE" >&2
		return 1
	fi
	assert_eq "$STARSHIP_SELECTED_FEATURE_BYTES" "$(wc -c <"$source")" \
		'the selected-feature Starship source should retain its approved byte count' || return 1
	assert_eq "$STARSHIP_SELECTED_FEATURE_SHA256" "$(sha256sum "$source" | cut -d ' ' -f 1)" \
		'the selected-feature Starship source should retain its approved digest'
}

test_real_starship_accepts_the_tracked_config_without_diagnostics() {
	setup_starship_runtime || return 1
	run_starship print-config

	assert_eq 0 "$COMMAND_STATUS" 'real Starship should load the complete tracked config' || return 1
	assert_contains "$COMMAND_OUTPUT" 'command_timeout = 200' \
		'the computed config should retain the baseline command timeout' || return 1
	assert_render_cache_removed
}

test_non_repository_prompts_retain_success_failure_deep_and_read_only_behavior() {
	setup_starship_runtime || return 1
	render_prompt /mnt/project /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled success prompt should render' || return 1
	assert_eq "$STARSHIP_SUCCESS_PROMPT" "$COMMAND_OUTPUT" \
		'the non-repository success prompt should retain exact raw bytes' || return 1
	assert_starship_prompt_cells 44 '❯' false 'the directory-only success prompt' || return 1
	assert_render_cache_removed || return 1
	local first_success=$COMMAND_OUTPUT

	render_prompt /mnt/project /fixture/project 0
	assert_eq "$first_success" "$COMMAND_OUTPUT" \
		'repeated success prompts should be byte-for-byte deterministic' || return 1
	assert_render_cache_removed || return 1

	render_prompt /mnt/project /fixture/project 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled failure prompt should render' || return 1
	assert_eq "$STARSHIP_FAILURE_PROMPT" "$COMMAND_OUTPUT" \
		'the non-repository failure prompt should retain the exact error character' || return 1
	assert_starship_prompt_cells 44 '✗' false 'the directory-only failure prompt' || return 1
	assert_render_cache_removed || return 1

	render_prompt /mnt/deep/alpha/beta/gamma /fixture/deep/alpha/beta/gamma 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled deep-path prompt should render' || return 1
	assert_eq "$STARSHIP_DEEP_PROMPT" "$COMMAND_OUTPUT" \
		'the deep path should retain two-component truncation and exact styling' || return 1
	assert_starship_prompt_cells 44 '❯' false 'the deep-path prompt' || return 1
	assert_render_cache_removed || return 1

	render_prompt /mnt/readonly /fixture/readonly 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled read-only prompt should render' || return 1
	assert_eq "$STARSHIP_READ_ONLY_PROMPT" "$COMMAND_OUTPUT" \
		'the read-only path should retain its exact indicator and styling' || return 1
	assert_starship_prompt_cells 44 '❯' true 'the read-only prompt' || return 1
	assert_render_cache_removed
}

test_directory_context_icons_render_exact_components_and_boundaries() {
	setup_starship_directory_runtime || return 1
	local component display_path expected_module expected_prompt glyph index near_match physical_path

	for index in "${!STARSHIP_DIRECTORY_COMPONENTS[@]}"; do
		component=${STARSHIP_DIRECTORY_COMPONENTS[index]}
		glyph=${STARSHIP_DIRECTORY_GLYPHS[index]}
		physical_path=/mnt/home/$component/child
		if [[ $component == Projects ]]; then
			display_path="$glyph/child"
		else
			display_path=$'\342\200\246/'"$glyph/child"
		fi
		expected_module=$'\033[1;44;30m '"$display_path"$' \033[0m'
		expected_prompt=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] '"$display_path"$' \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '

		render_module directory "$physical_path" "$physical_path" 0
		assert_eq 0 "$COMMAND_STATUS" "the controlled $component directory module should render" || return 1
		assert_eq "$expected_module" "$COMMAND_OUTPUT" \
			"the complete $component component should render its exact tight-spaced icon bytes" || return 1
		assert_render_cache_removed || return 1

		render_prompt "$physical_path" "$physical_path" 0
		assert_eq 0 "$COMMAND_STATUS" "the controlled $component prompt should render" || return 1
		assert_eq "$expected_prompt" "$COMMAND_OUTPUT" \
			"the complete $component component should retain exact full-prompt composition" || return 1
		assert_starship_prompt_cells 44 '❯' false \
			"the complete $component component prompt" || return 1
		assert_render_cache_removed || return 1

		physical_path=/mnt/home/repeated/$component/hidden/$component/child
		expected_module=$'\033[1;44;30m \342\200\246/'"$glyph"$'/child \033[0m'
		render_module directory "$physical_path" "$physical_path" 0
		assert_eq 0 "$COMMAND_STATUS" "the controlled hidden-repeat $component path should render" || return 1
		assert_eq "$expected_module" "$COMMAND_OUTPUT" \
			"an earlier hidden $component component should not consume the visible replacement" || return 1
		assert_render_cache_removed || return 1

		physical_path=/mnt/home/repeated/$component/$component
		expected_module=$'\033[1;44;30m \342\200\246/'"$glyph/$glyph"$' \033[0m'
		render_module directory "$physical_path" "$physical_path" 0
		assert_eq 0 "$COMMAND_STATUS" "the controlled adjacent-repeat $component path should render" || return 1
		assert_eq "$expected_module" "$COMMAND_OUTPUT" \
			"both adjacent visible $component components should render their exact glyphs" || return 1
		assert_render_cache_removed || return 1
	done

	for near_match in MyDocuments DocumentsArchive; do
		physical_path=/mnt/home/$near_match/child
		expected_module=$'\033[1;44;30m \342\200\246/'"$near_match"$'/child \033[0m'
		expected_prompt=$'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] \342\200\246/'"$near_match"$'/child \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] '

		render_module directory "$physical_path" "$physical_path" 0
		assert_eq 0 "$COMMAND_STATUS" "the controlled $near_match directory module should render" || return 1
		assert_eq "$expected_module" "$COMMAND_OUTPUT" \
			"the near-match $near_match component should remain literal" || return 1
		assert_render_cache_removed || return 1

		render_prompt "$physical_path" "$physical_path" 0
		assert_eq 0 "$COMMAND_STATUS" "the controlled $near_match prompt should render" || return 1
		assert_eq "$expected_prompt" "$COMMAND_OUTPUT" \
			"the near-match $near_match prompt should remain byte-for-byte literal" || return 1
		assert_starship_prompt_cells 44 '❯' false \
			"the near-match $near_match prompt" || return 1
		assert_render_cache_removed || return 1
	done
}

test_directory_context_repositories_and_read_only_path_render_exact_output() {
	setup_starship_directory_runtime || return 1
	local branch git_status

	setup_starship_git_repository \
		"$STARSHIP_DIRECTORY_ROOT/Projects/repository" \
		"$STARSHIP_RUNTIME/projects-remote.git" || return 1
	branch=$(fixture_git branch --show-current) || return 1
	assert_eq baseline "$branch" \
		'the Projects-hosted fixture should use the controlled baseline branch' || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq '' "$git_status" \
		'the Projects-hosted fixture should start as a clean real Git repository' || return 1

	setup_starship_git_repository \
		"$STARSHIP_DIRECTORY_ROOT/Workspace/repository" \
		"$STARSHIP_RUNTIME/workspace-remote.git" || return 1
	branch=$(fixture_git branch --show-current) || return 1
	assert_eq baseline "$branch" \
		'the nonmatching-parent fixture should use the controlled baseline branch' || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq '' "$git_status" \
		'the nonmatching-parent fixture should start as a clean real Git repository' || return 1

	render_module directory \
		/mnt/home/Projects/repository \
		/mnt/home/Projects/repository 0
	assert_eq 0 "$COMMAND_STATUS" 'the Projects-hosted repository directory module should render' || return 1
	assert_eq $'\033[1;44;30m /repository \033[0m' "$COMMAND_OUTPUT" \
		'the repository should render one tight-spaced Projects icon before its bold root' || return 1
	assert_render_cache_removed || return 1

	render_prompt \
		/mnt/home/Projects/repository \
		/mnt/home/Projects/repository 0
	assert_eq 0 "$COMMAND_STATUS" 'the Projects-hosted repository prompt should render' || return 1
	assert_eq $'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] /repository \\[\033[0m\\]\\[\033[45;30m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] ' \
		"$COMMAND_OUTPUT" \
		'the Projects-hosted repository should retain exact directory, Git, frame, and character composition' || return 1
	assert_starship_prompt_cells 44,45 '❯' false \
		'the Projects-hosted repository prompt' || return 1
	assert_render_cache_removed || return 1

	render_module directory \
		/mnt/home/Projects/repository/child \
		/mnt/home/Projects/repository/child 0
	assert_eq 0 "$COMMAND_STATUS" 'the Projects-hosted repository child directory module should render' || return 1
	assert_eq $'\033[1;44;30m \342\200\246/repository/child \033[0m' "$COMMAND_OUTPUT" \
		'the repository child should retain exactly two components and the truncation marker' || return 1
	assert_render_cache_removed || return 1

	render_prompt \
		/mnt/home/Projects/repository/child \
		/mnt/home/Projects/repository/child 0
	assert_eq 0 "$COMMAND_STATUS" 'the Projects-hosted repository child prompt should render' || return 1
	assert_eq $'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] \342\200\246/repository/child \\[\033[0m\\]\\[\033[45;30m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] ' \
		"$COMMAND_OUTPUT" \
		'the repository child should retain exact truncated directory and full-prompt composition' || return 1
	assert_starship_prompt_cells 44,45 '❯' false \
		'the Projects-hosted repository child prompt' || return 1
	assert_render_cache_removed || return 1

	render_module directory \
		/mnt/home/Workspace/repository \
		/mnt/home/Workspace/repository 0
	assert_eq 0 "$COMMAND_STATUS" 'the nonmatching-parent repository directory module should render' || return 1
	assert_eq $'\033[1;44;30m \342\200\246/Workspace/repository \033[0m' "$COMMAND_OUTPUT" \
		'the nonmatching repository parent should remain literal beside its bold root' || return 1
	assert_render_cache_removed || return 1

	render_prompt \
		/mnt/home/Workspace/repository \
		/mnt/home/Workspace/repository 0
	assert_eq 0 "$COMMAND_STATUS" 'the nonmatching-parent repository prompt should render' || return 1
	assert_eq $'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] \342\200\246/Workspace/repository \\[\033[0m\\]\\[\033[45;30m\\] \\[\033[3m\\]\357\220\230 baseline \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] ' \
		"$COMMAND_OUTPUT" \
		'the nonmatching repository parent should remain literal in the full prompt' || return 1
	assert_starship_prompt_cells 44,45 '❯' false \
		'the nonmatching-parent repository prompt' || return 1
	assert_render_cache_removed || return 1

	render_module directory \
		/mnt/home/Documents/readonly \
		/mnt/home/Documents/readonly 0
	assert_eq 0 "$COMMAND_STATUS" 'the selected read-only directory module should render' || return 1
	assert_eq $'\033[1;44;30m \342\200\246/󰈙/readonly\033[0m\033[44;31m\360\237\224\222\033[1;30m \033[0m' \
		"$COMMAND_OUTPUT" \
		'the selected read-only path should retain its exact icon, depth, and red lock bytes' || return 1
	assert_render_cache_removed || return 1

	render_prompt \
		/mnt/home/Documents/readonly \
		/mnt/home/Documents/readonly 0
	assert_eq 0 "$COMMAND_STATUS" 'the selected read-only prompt should render' || return 1
	assert_eq $'\n\\[\033[36m\\]\342\224\214\342\224\200\\[\033[1;44;30m\\] \342\200\246/󰈙/readonly\\[\033[0m\\]\\[\033[44;31m\\]\360\237\224\222\\[\033[1;30m\\] \\[\033[0m\\]\n\\[\033[36m\\]\342\224\224\342\224\200\\[\033[1m\\]\342\235\257\\[\033[0m\\] ' \
		"$COMMAND_OUTPUT" \
		'the selected read-only path should retain its red lock in the full prompt' || return 1
	assert_starship_prompt_cells 44 '❯' true 'the selected read-only prompt' || return 1
	assert_render_cache_removed
}

test_language_modules_render_exact_controlled_versions() {
	setup_starship_language_runtime || return 1
	local index module project
	for index in "${!STARSHIP_LANGUAGE_MODULES[@]}"; do
		module=${STARSHIP_LANGUAGE_MODULES[index]}
		project=$STARSHIP_LANGUAGE_ROOT/$module
		create_starship_language_marker "$module" "$project" || return 1
		: >"$STARSHIP_TOOL_CALL_LOG" || return 1
		render_module "$module" "/mnt/languages/$module" /fixture/project 0 || return 1
		assert_eq 0 "$COMMAND_STATUS" "the controlled $module module should render" || return 1
		assert_eq "${STARSHIP_LANGUAGE_OUTPUTS[index]}" "$COMMAND_OUTPUT" \
			"the controlled $module module should render exact selected bytes" || return 1
		assert_starship_call_logged "${STARSHIP_LANGUAGE_VERSION_CALLS[index]}" || return 1
		if [[ $module == rust ]]; then
			assert_starship_call_logged 'rustup <default>' || return 1
		fi
		assert_render_cache_removed || return 1
	done
}

test_polyglot_prompt_renders_languages_in_selected_order() {
	setup_starship_language_runtime || return 1
	local module project=$STARSHIP_LANGUAGE_ROOT/polyglot expected_call
	for module in "${STARSHIP_LANGUAGE_MODULES[@]}"; do
		create_starship_language_marker "$module" "$project" || return 1
	done
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt /mnt/languages/polyglot /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled polyglot prompt should render' || return 1
	assert_eq "$STARSHIP_LANGUAGE_POLYGLOT_PROMPT" "$COMMAND_OUTPUT" \
		'the polyglot prompt should render exact C-to-Python bytes before Git context' || return 1
	assert_starship_prompt_cells 44,46 '❯' false 'the polyglot language-group prompt' || return 1
	for expected_call in "${STARSHIP_LANGUAGE_VERSION_CALLS[@]}" 'rustup <default>'; do
		assert_starship_call_logged "$expected_call" || return 1
	done
	assert_eq 10 "$(wc -l <"$STARSHIP_TOOL_CALL_LOG")" \
		'the polyglot render should make each controlled tool call exactly once' || return 1
	assert_render_cache_removed || return 1
}

test_language_detection_preserves_empty_and_disabled_cpp_prompts() {
	setup_starship_language_runtime || return 1
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt /mnt/project /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the no-language prompt should render' || return 1
	assert_eq "$STARSHIP_SUCCESS_PROMPT" "$COMMAND_OUTPUT" \
		'the no-language prompt should retain its exact square-segment bytes' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the no-language prompt should not invoke controlled language tools' || return 1
	assert_render_cache_removed || return 1

	local cpp_project=$STARSHIP_LANGUAGE_ROOT/cpp
	create_starship_language_marker cpp "$cpp_project" || return 1
	run_in_sandbox "$STARSHIP_RUNTIME" "$STARSHIP_RUNTIME_PATH" \
		/mnt/tool-bin/c++ --version
	assert_eq 0 "$COMMAND_STATUS" 'the controlled C++ compiler should be executable' || return 1
	assert_eq $'c++ (GCC) 14.2.1 20240801\nCopyright (C) 2024 Free Software Foundation, Inc.' \
		"$COMMAND_OUTPUT" 'the controlled C++ compiler should return its parser-valid version' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the direct C++ availability check should not contaminate the Starship call log' || return 1

	render_module cpp /mnt/languages/cpp /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the disabled C++ module check should complete' || return 1
	assert_eq '' "$COMMAND_OUTPUT" 'the disabled C++ module should remain exactly empty' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the disabled C++ module should not invoke the controlled C++ compiler' || return 1
	assert_render_cache_removed || return 1

	render_prompt /mnt/languages/cpp /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the C++-only prompt should render' || return 1
	assert_eq "$STARSHIP_SUCCESS_PROMPT" "$COMMAND_OUTPUT" \
		'the C++-only prompt should retain exact no-language bytes' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the C++-only prompt should not invoke the controlled C++ compiler' || return 1
	assert_render_cache_removed || return 1
}

test_environment_context_modules_render_and_suppress_exact_states() {
	setup_starship_controlled_tool_runtime || return 1
	local docker_project=$STARSHIP_ENVIRONMENT_ROOT/docker
	local conda_project=$STARSHIP_ENVIRONMENT_ROOT/conda
	mkdir -p "$docker_project" "$conda_project" || return 1
	printf 'FROM scratch\n' >"$docker_project/Dockerfile" || return 1

	STARSHIP_RUNTIME_ENV=(DOCKER_CONTEXT=remote-builder)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module docker_context /mnt/environments/docker /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled non-default Docker context should render' || return 1
	assert_eq $'\033[42;30m\357\214\210 remote-builder \033[0m' "$COMMAND_OUTPUT" \
		'the Docker context should render the exact selected symbol, context, and style' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the Docker context module should not invoke Docker or another controlled tool' || return 1
	assert_render_cache_removed || return 1

	STARSHIP_RUNTIME_ENV=(DOCKER_CONTEXT=default)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module docker_context /mnt/environments/docker /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled default Docker context check should complete' || return 1
	assert_eq '' "$COMMAND_OUTPUT" 'the default Docker context should remain suppressed' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the suppressed Docker context should not invoke Docker or another controlled tool' || return 1
	assert_render_cache_removed || return 1

	STARSHIP_RUNTIME_ENV=(CONDA_DEFAULT_ENV=research)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module conda /mnt/environments/conda /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled non-base Conda environment should render' || return 1
	assert_eq $'\033[42;30m\360\237\205\222 research \033[0m' "$COMMAND_OUTPUT" \
		'the Conda environment should render the exact selected symbol, name, and style' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the Conda module should not invoke Conda or another controlled tool' || return 1
	assert_render_cache_removed || return 1

	STARSHIP_RUNTIME_ENV=(CONDA_DEFAULT_ENV=base)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module conda /mnt/environments/conda /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled base Conda environment check should complete' || return 1
	assert_eq '' "$COMMAND_OUTPUT" 'the base Conda environment should remain suppressed' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the suppressed base environment should not invoke Conda or another controlled tool' || return 1
	assert_render_cache_removed || return 1

	STARSHIP_RUNTIME_ENV=(CONDA_DEFAULT_ENV=research PIXI_ENVIRONMENT_NAME=dev)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module conda /mnt/environments/conda /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled Conda-under-Pixi check should complete' || return 1
	assert_eq '' "$COMMAND_OUTPUT" 'Conda should remain suppressed under an active Pixi environment' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the suppressed Conda-under-Pixi state should not invoke a controlled tool' || return 1
	assert_render_cache_removed || return 1

	STARSHIP_RUNTIME_ENV=()
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt /mnt/project /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the no-environment prompt should render' || return 1
	assert_eq "$STARSHIP_SUCCESS_PROMPT" "$COMMAND_OUTPUT" \
		'the no-environment prompt should retain its exact square-segment bytes' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the no-environment prompt should not invoke any controlled tool' || return 1
	assert_render_cache_removed || return 1
}

test_pixi_module_renders_markers_environment_and_missing_binary() {
	setup_starship_controlled_tool_runtime || return 1
	local toml_project=$STARSHIP_ENVIRONMENT_ROOT/pixi-toml
	local lock_project=$STARSHIP_ENVIRONMENT_ROOT/pixi-lock
	mkdir -p "$toml_project" "$lock_project" || return 1
	printf '[project]\nname = "fixture"\n' >"$toml_project/pixi.toml" || return 1
	printf '# controlled lock marker\n' >"$lock_project/pixi.lock" || return 1

	STARSHIP_RUNTIME_ENV=()
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module pixi /mnt/environments/pixi-toml /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled pixi.toml project should render' || return 1
	assert_eq $'\033[42;30m\360\237\247\232 v0.41.4 \033[0m' "$COMMAND_OUTPUT" \
		'the pixi.toml project should render the exact selected version-only output' || return 1
	assert_eq 'pixi <--version>' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the pixi.toml project should invoke exactly pixi --version once' || return 1
	assert_render_cache_removed || return 1

	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module pixi /mnt/environments/pixi-lock /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled pixi.lock project should render' || return 1
	assert_eq $'\033[42;30m\360\237\247\232 v0.41.4 \033[0m' "$COMMAND_OUTPUT" \
		'the pixi.lock project should render the exact selected version-only output' || return 1
	assert_eq 'pixi <--version>' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the pixi.lock project should invoke exactly pixi --version once' || return 1
	assert_render_cache_removed || return 1

	STARSHIP_RUNTIME_ENV=(PIXI_ENVIRONMENT_NAME=dev)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module pixi /mnt/project /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled active Pixi environment should render' || return 1
	assert_eq $'\033[42;30m\360\237\247\232 v0.41.4 dev \033[0m' "$COMMAND_OUTPUT" \
		'the active Pixi environment should render the exact selected version and name' || return 1
	assert_eq 'pixi <--version>' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the active Pixi environment should invoke exactly pixi --version once' || return 1
	assert_render_cache_removed || return 1

	STARSHIP_RUNTIME_ENV=()
	rm -- "$STARSHIP_TOOL_BIN/pixi" || return 1
	STARSHIP_COMMAND_PATH=/mnt/tool-bin
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_module pixi /mnt/environments/pixi-toml /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the controlled Pixi marker without a binary should render' || return 1
	assert_eq $'\033[42;30m\360\237\247\232 \033[0m' "$COMMAND_OUTPUT" \
		'the Pixi marker without a binary should retain the exact selected symbol-only output' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the missing Pixi binary should produce no controlled command call' || return 1
	assert_render_cache_removed || return 1
}

test_environment_context_prompts_render_exact_order_and_pixi_suppression() {
	setup_starship_controlled_tool_runtime || return 1
	setup_starship_git_repository || return 1
	create_starship_language_marker python "$STARSHIP_GIT_REPO" || return 1
	printf 'FROM scratch\n' >"$STARSHIP_GIT_REPO/Dockerfile" || return 1
	printf '[project]\nname = "fixture"\n' >"$STARSHIP_GIT_REPO/pixi.toml" || return 1
	fixture_git add -- Dockerfile pixi.toml pyproject.toml || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		commit -m environment-contexts >/dev/null 2>&1 || return 1
	fixture_git push origin baseline >/dev/null 2>&1 || return 1
	assert_eq '' "$(fixture_git status --short)" \
		'the combined environment fixture should be clean after committing every marker' || return 1
	assert_git_upstream_distance $'0\t0' || return 1

	STARSHIP_RUNTIME_ENV=(DOCKER_CONTEXT=remote-builder CONDA_DEFAULT_ENV=research)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt /mnt/repository /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the combined environment-context prompt should render' || return 1
	assert_eq "$STARSHIP_ENVIRONMENT_CONTEXT_PROMPT" "$COMMAND_OUTPUT" \
		'the combined prompt should render Python, Docker, Conda, Pixi, and Git in exact order' || return 1
	assert_starship_prompt_cells 46,42,45 '❯' false \
		'the combined language, environment, and Git prompt' || return 1
	assert_starship_call_logged 'python <--version>' || return 1
	assert_starship_call_logged 'pixi <--version>' || return 1
	assert_eq 2 "$(wc -l <"$STARSHIP_TOOL_CALL_LOG")" \
		'the combined prompt should invoke exactly Python and Pixi once without relying on call order' || return 1
	assert_render_cache_removed || return 1

	STARSHIP_RUNTIME_ENV=(
		DOCKER_CONTEXT=remote-builder
		CONDA_DEFAULT_ENV=research
		PIXI_ENVIRONMENT_NAME=dev
	)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt /mnt/repository /fixture/project 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the combined active-Pixi prompt should render' || return 1
	assert_eq "$STARSHIP_PIXI_ENVIRONMENT_CONTEXT_PROMPT" "$COMMAND_OUTPUT" \
		'the active-Pixi prompt should suppress Conda while preserving language, Docker, Pixi, and Git order' || return 1
	assert_starship_prompt_cells 46,42,45 '❯' false \
		'the active-Pixi language, environment, and Git prompt' || return 1
	assert_starship_call_logged 'python <--version>' || return 1
	assert_starship_call_logged 'pixi <--version>' || return 1
	assert_eq 2 "$(wc -l <"$STARSHIP_TOOL_CALL_LOG")" \
		'the active-Pixi prompt should invoke exactly Python and Pixi once without relying on call order' || return 1
	assert_render_cache_removed || return 1
}

test_square_segments_render_exact_optional_skipped_and_all_group_cells() {
	setup_starship_controlled_tool_runtime || return 1
	local environment_project=$STARSHIP_RUNTIME/home/Projects/environment
	local language_environment_project=$STARSHIP_RUNTIME/home/Projects/language-environment
	local prompt_status git_status
	mkdir -p "$environment_project" "$language_environment_project" || return 1
	printf 'FROM scratch\n' >"$environment_project/Dockerfile" || return 1
	printf 'FROM scratch\n' >"$language_environment_project/Dockerfile" || return 1
	create_starship_language_marker nodejs "$language_environment_project" || return 1

	STARSHIP_RUNTIME_ENV=(DOCKER_CONTEXT=remote-builder)
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt /mnt/home/Projects/environment /mnt/home/Projects/environment 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the environment-only square prompt should render' || return 1
	assert_eq "$STARSHIP_ENVIRONMENT_ONLY_PROMPT" "$COMMAND_OUTPUT" \
		'the environment-only prompt should render exact blue and green group bytes' || return 1
	assert_starship_prompt_cells 44,42 '❯' false 'the environment-only square prompt' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the environment-only render should not invoke Docker or another controlled tool' || return 1
	assert_render_cache_removed || return 1

	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt \
		/mnt/home/Projects/language-environment \
		/mnt/home/Projects/language-environment 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the language-and-environment square prompt should render' || return 1
	assert_eq "$STARSHIP_LANGUAGE_ENVIRONMENT_PROMPT" "$COMMAND_OUTPUT" \
		'the prompt without Git should render exact blue, cyan, and green group bytes' || return 1
	assert_starship_prompt_cells 44,46,42 '❯' false \
		'the language-and-environment square prompt' || return 1
	assert_eq 'node <--version>' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the prompt without Git should invoke exactly the selected Node.js tool' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_repository \
		"$STARSHIP_RUNTIME/home/Projects/language-git" \
		"$STARSHIP_RUNTIME/language-git-remote.git" || return 1
	create_starship_language_marker nodejs "$STARSHIP_GIT_REPO" || return 1
	fixture_git add -- package.json || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		commit -m language-marker >/dev/null 2>&1 || return 1
	fixture_git push origin baseline >/dev/null 2>&1 || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq '' "$git_status" \
		'the language-and-Git fixture should be clean after committing its marker' || return 1
	assert_git_upstream_distance $'0\t0' || return 1
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt /mnt/home/Projects/language-git /mnt/home/Projects/language-git 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the language-and-Git square prompt should render' || return 1
	assert_eq "$STARSHIP_LANGUAGE_GIT_PROMPT" "$COMMAND_OUTPUT" \
		'the prompt without environments should render exact blue, cyan, and purple group bytes' || return 1
	assert_starship_prompt_cells 44,46,45 '❯' false \
		'the language-and-Git square prompt' || return 1
	assert_eq 'node <--version>' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the prompt without environments should invoke exactly the selected Node.js tool' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_repository \
		"$STARSHIP_RUNTIME/home/Projects/all-groups" \
		"$STARSHIP_RUNTIME/all-groups-remote.git" || return 1
	printf 'FROM scratch\n' >"$STARSHIP_GIT_REPO/Dockerfile" || return 1
	fixture_git add -- Dockerfile || return 1
	fixture_git -c user.name=Fixture -c user.email=fixture@example.invalid \
		commit -m environment-marker >/dev/null 2>&1 || return 1
	fixture_git push origin baseline >/dev/null 2>&1 || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq '' "$git_status" \
		'the environment-and-Git fixture should be clean after committing its marker' || return 1
	assert_git_upstream_distance $'0\t0' || return 1
	: >"$STARSHIP_TOOL_CALL_LOG" || return 1
	render_prompt /mnt/home/Projects/all-groups /mnt/home/Projects/all-groups 0 || return 1
	assert_eq 0 "$COMMAND_STATUS" 'the environment-and-Git square prompt should render' || return 1
	assert_eq "$STARSHIP_ENVIRONMENT_GIT_PROMPT" "$COMMAND_OUTPUT" \
		'the prompt without languages should render exact blue, green, and purple group bytes' || return 1
	assert_starship_prompt_cells 44,42,45 '❯' false \
		'the environment-and-Git square prompt' || return 1
	assert_eq '' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
		'the prompt without languages should not invoke Docker or another controlled tool' || return 1
	assert_render_cache_removed || return 1

	create_starship_language_marker nodejs "$STARSHIP_GIT_REPO" || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq '?? package.json' "$git_status" \
		'the all-group fixture should contain one controlled untracked language marker' || return 1
	for prompt_status in 0 1; do
		: >"$STARSHIP_TOOL_CALL_LOG" || return 1
		render_prompt /mnt/home/Projects/all-groups /mnt/home/Projects/all-groups "$prompt_status" || return 1
		assert_eq 0 "$COMMAND_STATUS" 'the complete four-group square prompt should render' || return 1
		if ((prompt_status == 0)); then
			assert_eq "$STARSHIP_ALL_GROUPS_PROMPT" "$COMMAND_OUTPUT" \
				'the complete success prompt should render exact four-group bytes' || return 1
			assert_starship_prompt_cells 44,46,42,45 '❯' false \
				'the complete success square prompt' || return 1
		else
			assert_eq "$STARSHIP_ALL_GROUPS_FAILURE_PROMPT" "$COMMAND_OUTPUT" \
				'the complete failure prompt should retain all four groups and exact failure bytes' || return 1
			assert_starship_prompt_cells 44,46,42,45 '✗' false \
				'the complete failure square prompt' || return 1
		fi
		assert_eq 'node <--version>' "$(<"$STARSHIP_TOOL_CALL_LOG")" \
			'the complete prompt should invoke exactly the selected Node.js tool' || return 1
		assert_render_cache_removed || return 1
	done
}

test_git_prompts_retain_clean_modified_and_untracked_behavior() {
	setup_starship_git_runtime || return 1
	assert_eq origin/baseline "$(fixture_git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')" \
		'the controlled Git branch should have a fixed upstream' || return 1
	render_prompt /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled clean Git prompt should render' || return 1
	assert_eq "$STARSHIP_CLEAN_GIT_PROMPT" "$COMMAND_OUTPUT" \
		'the clean Git prompt should retain exact branch and character bytes' || return 1
	assert_starship_prompt_cells 45 '❯' false 'the clean Git-only prompt' || return 1
	assert_render_cache_removed || return 1

	printf 'modified\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	assert_eq ' M tracked.txt' "$(fixture_git status --short)" \
		'the modified fixture should contain one controlled worktree change' || return 1
	render_prompt /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled modified Git prompt should render' || return 1
	assert_eq "$STARSHIP_MODIFIED_GIT_PROMPT" "$COMMAND_OUTPUT" \
		'the modified Git prompt should retain its exact glyph and styling' || return 1
	assert_starship_prompt_cells 45 '❯' false 'the modified Git-only prompt' || return 1
	assert_render_cache_removed || return 1

	printf 'baseline\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	printf 'untracked\n' >"$STARSHIP_GIT_REPO/untracked.txt" || return 1
	assert_eq '?? untracked.txt' "$(fixture_git status --short)" \
		'the untracked fixture should contain one controlled untracked file' || return 1
	render_prompt /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled untracked Git prompt should render' || return 1
	assert_eq "$STARSHIP_UNTRACKED_GIT_PROMPT" "$COMMAND_OUTPUT" \
		'the untracked Git prompt should retain its exact marker and styling' || return 1
	assert_starship_prompt_cells 45 '❯' false 'the untracked Git-only prompt' || return 1
	assert_render_cache_removed
}

test_git_upstream_counts_render_synchronized_ahead_behind_diverged_and_mixed_states() {
	local base git_status index_paths worktree_paths

	setup_starship_git_runtime || return 1
	assert_git_upstream_distance $'0\t0' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the synchronized Git status module should render' || return 1
	assert_eq '' "$COMMAND_OUTPUT" \
		'the synchronized Git status module should remain exactly empty' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	create_fixture_git_commit ahead-one || return 1
	assert_git_upstream_distance $'1\t0' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the ahead Git status module should render' || return 1
	assert_eq $'\033[45;30m\342\207\2411 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact ahead count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	base=$(fixture_git rev-parse HEAD) || return 1
	create_fixture_git_commit behind-one || return 1
	create_fixture_git_commit behind-two || return 1
	fixture_git push origin baseline >/dev/null 2>&1 || return 1
	fixture_git reset --hard "$base" >/dev/null 2>&1 || return 1
	assert_git_upstream_distance $'0\t2' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the behind Git status module should render' || return 1
	assert_eq $'\033[45;30m\342\207\2432 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact nontrivial behind count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	base=$(fixture_git rev-parse HEAD) || return 1
	create_fixture_git_commit diverged-upstream-one || return 1
	create_fixture_git_commit diverged-upstream-two || return 1
	fixture_git push origin baseline >/dev/null 2>&1 || return 1
	fixture_git reset --hard "$base" >/dev/null 2>&1 || return 1
	create_fixture_git_commit diverged-local || return 1
	assert_git_upstream_distance $'1\t2' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the diverged Git status module should render' || return 1
	assert_eq $'\033[45;30m\342\207\225\342\207\2411\342\207\2432 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render independent ahead and behind counts' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	create_fixture_git_commit mixed-ahead || return 1
	printf 'modified\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq ' M tracked2.txt' "$git_status" \
		'the mixed fixture should contain one controlled worktree modification' || return 1
	index_paths=$(fixture_git diff --cached --name-only) || return 1
	assert_eq '' "$index_paths" 'the mixed fixture index should remain clean' || return 1
	worktree_paths=$(fixture_git diff --name-only) || return 1
	assert_eq tracked2.txt "$worktree_paths" \
		'the mixed fixture should modify exactly one tracked worktree file' || return 1
	assert_git_upstream_distance $'1\t0' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the mixed Git status module should render' || return 1
	assert_eq $'\033[45;30m\356\251\2611 \342\207\2411 \033[0m' "$COMMAND_OUTPUT" \
		'the mixed Git status module should render modified before ahead with exact bytes' || return 1
	assert_render_cache_removed || return 1
}

test_conflicted_git_module_renders_one_and_multiple_file_counts() {
	setup_starship_git_runtime || return 1
	create_conflicted_git_state 1 || return 1
	assert_eq 'UU conflicted1.txt' "$(fixture_git status --short)" \
		'the one-conflict fixture should contain exactly one unmerged file' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the one-conflict Git status module should render' || return 1
	assert_eq $'\033[45;30m\356\256\2531 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact one-file conflict count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	create_conflicted_git_state 2 || return 1
	assert_eq $'UU conflicted1.txt\nUU conflicted2.txt' "$(fixture_git status --short)" \
		'the multi-conflict fixture should contain exactly two unmerged files' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the multi-conflict Git status module should render' || return 1
	assert_eq $'\033[45;30m\356\256\2532 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact multi-file conflict count' || return 1
	assert_render_cache_removed
}

test_staged_git_module_renders_one_multiple_and_mixed_states() {
	local git_status

	setup_starship_git_runtime || return 1
	printf 'staged\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	fixture_git add -- tracked.txt || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq 'M  tracked.txt' "$git_status" \
		'the one-staged fixture should contain exactly one index change' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the one-staged Git status module should render' || return 1
	assert_eq $'\033[45;30m+1 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact one-file staged count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	printf 'staged\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	printf 'staged\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	fixture_git add -- tracked.txt tracked2.txt || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq $'M  tracked.txt\nM  tracked2.txt' "$git_status" \
		'the multi-staged fixture should contain exactly two index changes' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the multi-staged Git status module should render' || return 1
	assert_eq $'\033[45;30m+2 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact multi-file staged count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	printf 'staged\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	fixture_git add -- tracked.txt || return 1
	printf 'modified\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq $'M  tracked.txt\n M tracked2.txt' "$git_status" \
		'the mixed fixture should contain one index and one worktree change' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the mixed Git status module should render' || return 1
	assert_eq $'\033[45;30m\356\251\2611 +1 \033[0m' "$COMMAND_OUTPUT" \
		'the mixed Git status module should render modified before staged with exact bytes' || return 1
	assert_render_cache_removed
}

test_deleted_git_module_renders_one_multiple_and_mixed_states() {
	local git_status

	setup_starship_git_runtime || return 1
	rm -- "$STARSHIP_GIT_REPO/tracked.txt" || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq ' D tracked.txt' "$git_status" \
		'the one-deleted fixture should contain exactly one unstaged deletion' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the one-deleted Git status module should render' || return 1
	assert_eq $'\033[45;30m\342\234\2301 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact one-file deleted count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	rm -- "$STARSHIP_GIT_REPO/tracked.txt" "$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq $' D tracked.txt\n D tracked2.txt' "$git_status" \
		'the multi-deleted fixture should contain exactly two unstaged deletions' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the multi-deleted Git status module should render' || return 1
	assert_eq $'\033[45;30m\342\234\2302 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact multi-file deleted count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	rm -- "$STARSHIP_GIT_REPO/tracked.txt" || return 1
	printf 'staged\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	fixture_git add -- tracked2.txt || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq $' D tracked.txt\nM  tracked2.txt' "$git_status" \
		'the mixed fixture should contain one unstaged deletion and one staged modification' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the mixed deleted and staged Git status module should render' || return 1
	assert_eq $'\033[45;30m\342\234\2301 +1 \033[0m' "$COMMAND_OUTPUT" \
		'the mixed Git status module should render deleted before staged with exact bytes' || return 1
	assert_render_cache_removed
}

test_renamed_git_module_renders_one_multiple_and_mixed_states() {
	local git_status

	setup_starship_git_runtime || return 1
	fixture_git mv -- tracked.txt renamed.txt || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq 'R  tracked.txt -> renamed.txt' "$git_status" \
		'the one-renamed fixture should contain exactly one detected staged rename' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the one-renamed Git status module should render' || return 1
	assert_eq $'\033[45;30m\302\2731 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact one-file renamed count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	fixture_git mv -- tracked.txt renamed.txt || return 1
	fixture_git mv -- tracked2.txt renamed2.txt || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq $'R  tracked.txt -> renamed.txt\nR  tracked2.txt -> renamed2.txt' "$git_status" \
		'the multi-renamed fixture should contain exactly two detected staged renames' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the multi-renamed Git status module should render' || return 1
	assert_eq $'\033[45;30m\302\2732 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact multi-file renamed count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	fixture_git mv -- tracked.txt renamed.txt || return 1
	rm -- "$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	git_status=$(fixture_git status --short) || return 1
	assert_eq $'R  tracked.txt -> renamed.txt\n D tracked2.txt' "$git_status" \
		'the mixed fixture should contain one detected rename and one unstaged deletion' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the mixed renamed and deleted Git status module should render' || return 1
	assert_eq $'\033[45;30m\342\234\2301 \302\2731 \033[0m' "$COMMAND_OUTPUT" \
		'the mixed Git status module should render deleted before renamed with exact bytes' || return 1
	assert_render_cache_removed
}

test_stashed_git_module_renders_presence_for_one_multiple_and_mixed_states() {
	local git_status stash_count

	setup_starship_git_runtime || return 1
	create_git_stash one || return 1
	stash_count=$(git_stash_count) || return 1
	assert_eq 1 "$stash_count" \
		'the one-stash fixture should contain exactly one real Git stash' || return 1
	git_status=$(fixture_git status --porcelain=v1) || return 1
	assert_eq '' "$git_status" \
		'the one-stash fixture should have no index or worktree changes' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the one-stash Git status module should render' || return 1
	assert_eq $'\033[45;30m\\$ \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact one-stash presence marker' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	create_git_stash one || return 1
	create_git_stash two || return 1
	stash_count=$(git_stash_count) || return 1
	assert_eq 2 "$stash_count" \
		'the multi-stash fixture should contain exactly two real Git stashes' || return 1
	git_status=$(fixture_git status --porcelain=v1) || return 1
	assert_eq '' "$git_status" \
		'the multi-stash fixture should have no index or worktree changes' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the multi-stash Git status module should render' || return 1
	assert_eq $'\033[45;30m\\$ \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should still render exactly one stash presence marker' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	create_git_stash one || return 1
	fixture_git mv -- tracked.txt renamed.txt || return 1
	stash_count=$(git_stash_count) || return 1
	assert_eq 1 "$stash_count" \
		'the mixed fixture should contain exactly one real Git stash' || return 1
	git_status=$(fixture_git status --porcelain=v1) || return 1
	assert_eq 'R  tracked.txt -> renamed.txt' "$git_status" \
		'the mixed fixture should contain exactly one detected staged rename' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the mixed stashed and renamed Git status module should render' || return 1
	assert_eq $'\033[45;30m\\$ \302\2731 \033[0m' "$COMMAND_OUTPUT" \
		'the mixed Git status module should render stash presence before renamed with exact bytes' || return 1
	assert_render_cache_removed || return 1
}

test_focused_modules_render_exact_selected_configuration_output() {
	setup_starship_git_runtime || return 1
	render_module directory /mnt/deep/alpha/beta/gamma /fixture/deep/alpha/beta/gamma 0
	assert_eq $'\033[1;44;30m \342\200\246/beta/gamma \033[0m' "$COMMAND_OUTPUT" \
		'the directory module should retain exact deep-path bytes' || return 1
	assert_render_cache_removed || return 1

	render_module git_branch /mnt/repository /fixture/project 0
	assert_eq $'\033[3;45;30m\357\220\230 baseline \033[0m' "$COMMAND_OUTPUT" \
		'the Git branch module should render the exact icon, separator, and italic purple-block bytes' || return 1
	assert_render_cache_removed || return 1

	render_module git_status /mnt/repository /fixture/project 0
	assert_eq '' "$COMMAND_OUTPUT" 'the clean Git status module should remain hidden' || return 1
	assert_render_cache_removed || return 1

	printf 'modified\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq $'\033[45;30m\356\251\2611 \033[0m' "$COMMAND_OUTPUT" \
		'the modified Git status module should render the exact one-file count' || return 1
	assert_render_cache_removed || return 1
	printf 'modified\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	assert_eq $' M tracked.txt\n M tracked2.txt' "$(fixture_git status --short)" \
		'the multi-modified fixture should contain exactly two worktree changes' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq $'\033[45;30m\356\251\2612 \033[0m' "$COMMAND_OUTPUT" \
		'the modified Git status module should render the exact multi-file count' || return 1
	assert_render_cache_removed || return 1

	printf 'baseline\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	printf 'baseline\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	printf 'untracked\n' >"$STARSHIP_GIT_REPO/untracked.txt" || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq $'\033[45;30m?1 \033[0m' "$COMMAND_OUTPUT" \
		'the untracked Git status module should render the exact one-file count' || return 1
	assert_render_cache_removed || return 1
	printf 'untracked\n' >"$STARSHIP_GIT_REPO/untracked2.txt" || return 1
	assert_eq $'?? untracked.txt\n?? untracked2.txt' "$(fixture_git status --short)" \
		'the multi-untracked fixture should contain exactly two untracked files' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq $'\033[45;30m?2 \033[0m' "$COMMAND_OUTPUT" \
		'the untracked Git status module should render the exact multi-file count' || return 1
	assert_render_cache_removed || return 1

	render_module character /mnt/project /fixture/project 1
	assert_eq $'\033[1;36m\342\234\227\033[0m ' "$COMMAND_OUTPUT" \
		'the character module should retain exact failure bytes' || return 1
	assert_render_cache_removed
}

set -e
run_test test_installed_starship_version_matches_the_omarchy_baseline \
	'installed Starship version matches the Omarchy baseline'
run_test test_tracked_starship_source_has_the_selected_feature_identity \
	'tracked Starship source has the selected-feature identity'
if [[ -f $SOURCE_REPO/$STARSHIP_SOURCE_RELATIVE && ! -L $SOURCE_REPO/$STARSHIP_SOURCE_RELATIVE ]]; then
	run_test test_real_starship_accepts_the_tracked_config_without_diagnostics \
		'real Starship accepts the tracked config without diagnostics'
	run_test test_non_repository_prompts_retain_success_failure_deep_and_read_only_behavior \
		'non-repository prompts retain success, failure, deep-path, and read-only behavior'
	run_test test_directory_context_icons_render_exact_components_and_boundaries \
		'directory-context icons render exact components and preserve boundaries'
	run_test test_directory_context_repositories_and_read_only_path_render_exact_output \
		'directory-context repositories and selected read-only path render exact output'
	run_test test_language_modules_render_exact_controlled_versions \
		'language modules render exact controlled versions'
	run_test test_polyglot_prompt_renders_languages_in_selected_order \
		'polyglot prompt renders languages in selected order'
	run_test test_language_detection_preserves_empty_and_disabled_cpp_prompts \
		'language detection preserves empty and disabled C++ prompts'
	run_test test_environment_context_modules_render_and_suppress_exact_states \
		'environment-context modules render and suppress exact controlled states'
	run_test test_pixi_module_renders_markers_environment_and_missing_binary \
		'Pixi module renders markers, active environment, and missing-binary state'
	run_test test_environment_context_prompts_render_exact_order_and_pixi_suppression \
		'environment-context prompts render exact order and active-Pixi suppression'
	run_test test_square_segments_render_exact_optional_skipped_and_all_group_cells \
		'square segments render exact optional, skipped-middle, and all-group cells'
	run_test test_git_prompts_retain_clean_modified_and_untracked_behavior \
		'Git prompts retain clean, modified, and untracked behavior'
	run_test test_git_upstream_counts_render_synchronized_ahead_behind_diverged_and_mixed_states \
		'Git upstream counts render synchronized, ahead, behind, diverged, and mixed states'
	run_test test_conflicted_git_module_renders_one_and_multiple_file_counts \
		'conflicted Git module renders one- and multi-file counts'
	run_test test_staged_git_module_renders_one_multiple_and_mixed_states \
		'staged Git module renders one-file, multi-file, and mixed states'
	run_test test_deleted_git_module_renders_one_multiple_and_mixed_states \
		'deleted Git module renders one-file, multi-file, and mixed states'
	run_test test_renamed_git_module_renders_one_multiple_and_mixed_states \
		'renamed Git module renders one-file, multi-file, and mixed states'
	run_test test_stashed_git_module_renders_presence_for_one_multiple_and_mixed_states \
		'stashed Git module renders one-stash, multi-stash, and mixed states'
	run_test test_focused_modules_render_exact_selected_configuration_output \
		'focused modules render exact selected-configuration output'
fi
finish_tests
