#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly STARSHIP_SOURCE_RELATIVE=config/starship/.config/starship.toml
readonly STARSHIP_SELECTED_FEATURE_BYTES=792
readonly STARSHIP_SELECTED_FEATURE_SHA256=5804ce81055a31fbcdbec6e678977f8783e1c4135ce4cb9e1bbb3eafeebb7b04
readonly STARSHIP_SUCCESS_PROMPT=$'\n\\[\033[1;36m\\]/fixture/project\\[\033[0m\\] \\[\033[1;36m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_FAILURE_PROMPT=$'\n\\[\033[1;36m\\]/fixture/project\\[\033[0m\\] \\[\033[1;36m\\]\342\234\227\\[\033[0m\\] '
readonly STARSHIP_DEEP_PROMPT=$'\n\\[\033[1;36m\\]\342\200\246/beta/gamma\\[\033[0m\\] \\[\033[1;36m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_READ_ONLY_PROMPT=$'\n\\[\033[1;36m\\]/fixture/readonly\\[\033[0m\\]\\[\033[31m\\]\360\237\224\222\\[\033[0m\\] \\[\033[1;36m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_CLEAN_GIT_PROMPT=$'\n\\[\033[3;36m\\]baseline\\[\033[0m\\] \\[\033[1;36m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_MODIFIED_GIT_PROMPT=$'\n\\[\033[3;36m\\]baseline\\[\033[0m\\] \\[\033[36m\\]\356\251\2611 \\[\033[1m\\]\342\235\257\\[\033[0m\\] '
readonly STARSHIP_UNTRACKED_GIT_PROMPT=$'\n\\[\033[3;36m\\]baseline\\[\033[0m\\] \\[\033[36m\\]?1 \\[\033[1m\\]\342\235\257\\[\033[0m\\] '

setup_starship_runtime() {
	new_fixture || return 1
	STARSHIP_FIXTURE_CONFIG=$FIXTURE_REPO/$STARSHIP_SOURCE_RELATIVE
	STARSHIP_RUNTIME=$FIXTURE_ROOT/starship-runtime
	mkdir -p \
		"$STARSHIP_RUNTIME/home" \
		"$STARSHIP_RUNTIME/project" \
		"$STARSHIP_RUNTIME/deep/alpha/beta/gamma" \
		"$STARSHIP_RUNTIME/readonly" || return 1
	chmod 0555 "$STARSHIP_RUNTIME/readonly" || return 1
	BWRAP_EXTRA_ARGS+=(--bind "$STARSHIP_RUNTIME" /mnt)
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

setup_starship_git_runtime() {
	setup_starship_runtime || return 1
	STARSHIP_GIT_REPO=$STARSHIP_RUNTIME/repository
	STARSHIP_GIT_REMOTE=$STARSHIP_RUNTIME/remote.git
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

run_starship() {
	run_in_sandbox "$STARSHIP_RUNTIME" "/usr/bin:/bin" bash -c '
		set -u
		config=$1
		shift
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
				PATH=/usr/bin:/bin \
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
				starship "$@"
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
	' bash "$STARSHIP_FIXTURE_CONFIG" "$@"
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
	assert_render_cache_removed || return 1

	render_prompt /mnt/deep/alpha/beta/gamma /fixture/deep/alpha/beta/gamma 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled deep-path prompt should render' || return 1
	assert_eq "$STARSHIP_DEEP_PROMPT" "$COMMAND_OUTPUT" \
		'the deep path should retain two-component truncation and exact styling' || return 1
	assert_render_cache_removed || return 1

	render_prompt /mnt/readonly /fixture/readonly 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled read-only prompt should render' || return 1
	assert_eq "$STARSHIP_READ_ONLY_PROMPT" "$COMMAND_OUTPUT" \
		'the read-only path should retain its exact indicator and styling' || return 1
	assert_render_cache_removed
}

test_git_prompts_retain_clean_modified_and_untracked_behavior() {
	setup_starship_git_runtime || return 1
	assert_eq origin/baseline "$(fixture_git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')" \
		'the controlled Git branch should have a fixed upstream' || return 1
	render_prompt /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled clean Git prompt should render' || return 1
	assert_eq "$STARSHIP_CLEAN_GIT_PROMPT" "$COMMAND_OUTPUT" \
		'the clean Git prompt should retain exact branch and character bytes' || return 1
	assert_render_cache_removed || return 1

	printf 'modified\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	assert_eq ' M tracked.txt' "$(fixture_git status --short)" \
		'the modified fixture should contain one controlled worktree change' || return 1
	render_prompt /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled modified Git prompt should render' || return 1
	assert_eq "$STARSHIP_MODIFIED_GIT_PROMPT" "$COMMAND_OUTPUT" \
		'the modified Git prompt should retain its exact glyph and styling' || return 1
	assert_render_cache_removed || return 1

	printf 'baseline\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	printf 'untracked\n' >"$STARSHIP_GIT_REPO/untracked.txt" || return 1
	assert_eq '?? untracked.txt' "$(fixture_git status --short)" \
		'the untracked fixture should contain one controlled untracked file' || return 1
	render_prompt /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the controlled untracked Git prompt should render' || return 1
	assert_eq "$STARSHIP_UNTRACKED_GIT_PROMPT" "$COMMAND_OUTPUT" \
		'the untracked Git prompt should retain its exact marker and styling' || return 1
	assert_render_cache_removed
}

test_conflicted_git_module_renders_one_and_multiple_file_counts() {
	setup_starship_git_runtime || return 1
	create_conflicted_git_state 1 || return 1
	assert_eq 'UU conflicted1.txt' "$(fixture_git status --short)" \
		'the one-conflict fixture should contain exactly one unmerged file' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the one-conflict Git status module should render' || return 1
	assert_eq $'\033[36m\356\256\2531 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact one-file conflict count' || return 1
	assert_render_cache_removed || return 1

	setup_starship_git_runtime || return 1
	create_conflicted_git_state 2 || return 1
	assert_eq $'UU conflicted1.txt\nUU conflicted2.txt' "$(fixture_git status --short)" \
		'the multi-conflict fixture should contain exactly two unmerged files' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq 0 "$COMMAND_STATUS" 'the multi-conflict Git status module should render' || return 1
	assert_eq $'\033[36m\356\256\2532 \033[0m' "$COMMAND_OUTPUT" \
		'the Git status module should render the exact multi-file conflict count' || return 1
	assert_render_cache_removed
}

test_focused_modules_render_exact_selected_configuration_output() {
	setup_starship_git_runtime || return 1
	render_module directory /mnt/deep/alpha/beta/gamma /fixture/deep/alpha/beta/gamma 0
	assert_eq $'\033[1;36m\342\200\246/beta/gamma\033[0m ' "$COMMAND_OUTPUT" \
		'the directory module should retain exact deep-path bytes' || return 1
	assert_render_cache_removed || return 1

	render_module git_branch /mnt/repository /fixture/project 0
	assert_eq $'\033[3;36mbaseline\033[0m ' "$COMMAND_OUTPUT" \
		'the Git branch module should retain exact baseline bytes' || return 1
	assert_render_cache_removed || return 1

	render_module git_status /mnt/repository /fixture/project 0
	assert_eq '' "$COMMAND_OUTPUT" 'the clean Git status module should remain hidden' || return 1
	assert_render_cache_removed || return 1

	printf 'modified\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq $'\033[36m\356\251\2611 \033[0m' "$COMMAND_OUTPUT" \
		'the modified Git status module should render the exact one-file count' || return 1
	assert_render_cache_removed || return 1
	printf 'modified\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	assert_eq $' M tracked.txt\n M tracked2.txt' "$(fixture_git status --short)" \
		'the multi-modified fixture should contain exactly two worktree changes' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq $'\033[36m\356\251\2612 \033[0m' "$COMMAND_OUTPUT" \
		'the modified Git status module should render the exact multi-file count' || return 1
	assert_render_cache_removed || return 1

	printf 'baseline\n' >"$STARSHIP_GIT_REPO/tracked.txt" || return 1
	printf 'baseline\n' >"$STARSHIP_GIT_REPO/tracked2.txt" || return 1
	printf 'untracked\n' >"$STARSHIP_GIT_REPO/untracked.txt" || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq $'\033[36m?1 \033[0m' "$COMMAND_OUTPUT" \
		'the untracked Git status module should render the exact one-file count' || return 1
	assert_render_cache_removed || return 1
	printf 'untracked\n' >"$STARSHIP_GIT_REPO/untracked2.txt" || return 1
	assert_eq $'?? untracked.txt\n?? untracked2.txt' "$(fixture_git status --short)" \
		'the multi-untracked fixture should contain exactly two untracked files' || return 1
	render_module git_status /mnt/repository /fixture/project 0
	assert_eq $'\033[36m?2 \033[0m' "$COMMAND_OUTPUT" \
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
	run_test test_git_prompts_retain_clean_modified_and_untracked_behavior \
		'Git prompts retain clean, modified, and untracked behavior'
	run_test test_conflicted_git_module_renders_one_and_multiple_file_counts \
		'conflicted Git module renders one- and multi-file counts'
	run_test test_focused_modules_render_exact_selected_configuration_output \
		'focused modules render exact selected-configuration output'
fi
finish_tests
