#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly OPENCODE_MAIN_RELATIVE=.config/opencode/opencode.json
readonly OPENCODE_TUI_RELATIVE=.config/opencode/tui.json
readonly OPENCODE_VALIDATOR='bash lib/dotfiles/opencode-validator.sh "$HOME/.config/opencode/opencode.json" "$HOME/.config/opencode/tui.json"'

validator_call_value() {
	local wanted=$1 key value
	while IFS='=' read -r key value; do
		if [[ $key == "$wanted" ]]; then
			printf '%s\n' "$value"
			return 0
		fi
	done <"$OPENCODE_FAKE_CALL"
	return 1
}

configure_opencode_validator_fake() {
	OPENCODE_FAKE_CALL=$FIXTURE_ROOT/opencode-validator-call
	OPENCODE_FAKE_ROOT=$FIXTURE_ROOT/opencode-validator-root
	rm -f -- "$OPENCODE_FAKE_CALL" "$OPENCODE_FAKE_ROOT"
	make_fake opencode '
fixture_root=$(cd -- "$(dirname -- "$0")/.." && pwd -P) || exit 1
call=$fixture_root/opencode-validator-call
root_file=$fixture_root/opencode-validator-root
printf "opencode %s\n" "$*" >>"$fixture_root/external-calls"
validator_root=${HOME%/home}
shopt -s dotglob nullglob
home_entries=("$HOME"/*)
managed_entries=("$OPENCODE_TEST_MANAGED_CONFIG_DIR"/*)
config_entries=("$XDG_CONFIG_HOME/opencode"/*)
printf "%s\n" "$validator_root" >"$root_file"
{
	printf "ARGV="
	printf "%s|" "$@"
	printf "\n"
	printf "EXECUTABLE=%s\n" "$0"
	printf "PWD=%s\n" "$PWD"
	printf "HOME=%s\n" "$HOME"
	printf "PATH=%s\n" "$PATH"
	printf "TMPDIR=%s\n" "$TMPDIR"
	printf "XDG_CONFIG_HOME=%s\n" "$XDG_CONFIG_HOME"
	printf "XDG_DATA_HOME=%s\n" "$XDG_DATA_HOME"
	printf "XDG_STATE_HOME=%s\n" "$XDG_STATE_HOME"
	printf "XDG_CACHE_HOME=%s\n" "$XDG_CACHE_HOME"
	printf "OPENCODE_CONFIG=%s\n" "$OPENCODE_CONFIG"
	printf "OPENCODE_CONFIG_CONTENT=%s\n" "$OPENCODE_CONFIG_CONTENT"
	printf "OPENCODE_DB=%s\n" "$OPENCODE_DB"
	printf "OPENCODE_PURE=%s\n" "$OPENCODE_PURE"
	printf "OPENCODE_DISABLE_PROJECT_CONFIG=%s\n" "$OPENCODE_DISABLE_PROJECT_CONFIG"
	printf "OPENCODE_DISABLE_DEFAULT_PLUGINS=%s\n" "$OPENCODE_DISABLE_DEFAULT_PLUGINS"
	printf "OPENCODE_DISABLE_EXTERNAL_SKILLS=%s\n" "$OPENCODE_DISABLE_EXTERNAL_SKILLS"
	printf "OPENCODE_DISABLE_CLAUDE_CODE=%s\n" "$OPENCODE_DISABLE_CLAUDE_CODE"
	printf "OPENCODE_DISABLE_MODELS_FETCH=%s\n" "$OPENCODE_DISABLE_MODELS_FETCH"
	printf "OPENCODE_DISABLE_LSP_DOWNLOAD=%s\n" "$OPENCODE_DISABLE_LSP_DOWNLOAD"
	printf "OPENCODE_DISABLE_AUTOUPDATE=%s\n" "$OPENCODE_DISABLE_AUTOUPDATE"
	printf "OPENCODE_TEST_MANAGED_CONFIG_DIR=%s\n" "$OPENCODE_TEST_MANAGED_CONFIG_DIR"
	printf "HOSTILE_SENTINEL=%s\n" "${OPENCODE_HOSTILE_SENTINEL-unset}"
	printf "HOME_ENTRIES=%s\n" "${#home_entries[@]}"
	printf "MANAGED_ENTRIES=%s\n" "${#managed_entries[@]}"
	printf "CONFIG_ENTRIES=%s\n" "${#config_entries[@]}"
	printf "CONFIG_MODE=%s\n" "$(stat -c %a -- "$XDG_CONFIG_HOME/opencode")"
	printf "MANAGED_MODE=%s\n" "$(stat -c %a -- "$OPENCODE_TEST_MANAGED_CONFIG_DIR")"
} >"$call"
if [[ -f $fixture_root/opencode-validator-fail ]]; then
	printf "%s\n" "controlled OpenCode diagnostic" >&2
	exit 42
fi
printf "%s\n" "resolved config containing a secret"
'
}

snapshot_installed_opencode_canaries() {
	(
		cd -- "$FIXTURE_ROOT" || return 1
		find \
			relocated/dotfiles/opencode.json \
			relocated/dotfiles/.opencode \
			user/home \
			user/config \
			user/state \
			user/cache \
			opencode-hostile \
			tmp \
			-printf '%p|%y|%m|%s|%l\n' | LC_ALL=C sort
		find \
			relocated/dotfiles/opencode.json \
			relocated/dotfiles/.opencode \
			user/home \
			user/config \
			user/state \
			user/cache \
			opencode-hostile \
			tmp \
			-type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
	)
}

exercise_installed_opencode_validator() {
	new_fixture || return 1
	local installed_opencode installed_version controlled_opencode validator main tui canaries_before
	installed_opencode=$(readlink -f -- "$(command -v opencode)") || {
		printf '  installed OpenCode executable is unavailable\n' >&2
		return 1
	}
	if [[ $installed_opencode =~ /installs/opencode/([^/]+)/opencode$ ]]; then
		installed_version=${BASH_REMATCH[1]}
	else
		printf '  expected a Mise-managed OpenCode executable, found: %s\n' "$installed_opencode" >&2
		return 1
	fi
	if [[ ! $installed_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		printf '  Mise OpenCode install path has an invalid version: %s\n' "$installed_version" >&2
		return 1
	fi
	controlled_opencode=$FIXTURE_ROOT/native-opencode/bin/opencode
	validator=$FIXTURE_REPO/lib/dotfiles/opencode-validator.sh
	main=$FIXTURE_REPO/config/opencode/$OPENCODE_MAIN_RELATIVE
	tui=$FIXTURE_REPO/config/opencode/$OPENCODE_TUI_RELATIVE

	mkdir -p -- \
		"${controlled_opencode%/*}" \
		"$FIXTURE_REPO/.opencode/plugin" \
		"$FIXTURE_HOME/.config/opencode/plugins" \
		"$FIXTURE_HOME/.opencode/plugin" \
		"$FIXTURE_HOME/.agents/skills/private" \
		"$FIXTURE_HOME/.claude" \
		"$FIXTURE_CONFIG/opencode/plugin" \
		"$FIXTURE_STATE/opencode" \
		"$FIXTURE_CACHE/opencode" \
		"$FIXTURE_ROOT/opencode-hostile/config-dir" || return 1
	: >"$controlled_opencode" || return 1
	printf '%s\n' '{"plugin":["project-canary"],"lsp":true}' >"$FIXTURE_REPO/opencode.json" || return 1
	printf '%s\n' 'export default () => ({})' >"$FIXTURE_REPO/.opencode/plugin/project.js" || return 1
	printf '%s\n' '{"plugin":["global-canary"]}' >"$FIXTURE_HOME/.config/opencode/config.json" || return 1
	printf '%s\n' 'export default () => ({})' >"$FIXTURE_HOME/.config/opencode/plugins/global.js" || return 1
	printf '%s\n' '{"plugin":["dot-opencode-canary"]}' >"$FIXTURE_HOME/.opencode/opencode.json" || return 1
	printf '%s\n' 'export default () => ({})' >"$FIXTURE_HOME/.opencode/plugin/global.js" || return 1
	printf '%s\n' 'private skill canary' >"$FIXTURE_HOME/.agents/skills/private/SKILL.md" || return 1
	printf '%s\n' '{"permissions":"hostile"}' >"$FIXTURE_HOME/.claude/settings.json" || return 1
	printf '%s\n' '{"plugin":["xdg-canary"]}' >"$FIXTURE_CONFIG/opencode/opencode.json" || return 1
	printf '%s\n' 'export default () => ({})' >"$FIXTURE_CONFIG/opencode/plugin/xdg.js" || return 1
	printf '%s\n' 'state canary' >"$FIXTURE_STATE/opencode/sentinel" || return 1
	printf '%s\n' 'cache canary' >"$FIXTURE_CACHE/opencode/sentinel" || return 1
	printf '%s\n' '{"plugin":["custom-canary"]}' >"$FIXTURE_ROOT/opencode-hostile/custom.json" || return 1
	printf '%s\n' '{"plugin":["directory-canary"]}' >"$FIXTURE_ROOT/opencode-hostile/config-dir/opencode.json" || return 1
	printf '%s\n' 'database canary' >"$FIXTURE_ROOT/opencode-hostile/database" || return 1
	canaries_before=$(snapshot_installed_opencode_canaries) || return 1

	BWRAP_EXTRA_ARGS+=(
		--unshare-net
		--ro-bind "$installed_opencode" "$controlled_opencode"
	)
	run_in_sandbox "$FIXTURE_REPO" "${controlled_opencode%/*}:/usr/bin:/bin" \
		/usr/bin/env \
		OPENCODE_CONFIG="$FIXTURE_ROOT/opencode-hostile/custom.json" \
		OPENCODE_CONFIG_CONTENT='{"plugin":["inline-canary"]}' \
		OPENCODE_CONFIG_DIR="$FIXTURE_ROOT/opencode-hostile/config-dir" \
		OPENCODE_DB="$FIXTURE_ROOT/opencode-hostile/database" \
		OPENCODE_PURE=0 \
		OPENCODE_DISABLE_PROJECT_CONFIG=0 \
		OPENCODE_DISABLE_DEFAULT_PLUGINS=0 \
		OPENCODE_DISABLE_EXTERNAL_SKILLS=0 \
		OPENCODE_DISABLE_CLAUDE_CODE=0 \
		OPENCODE_DISABLE_MODELS_FETCH=0 \
		OPENCODE_DISABLE_LSP_DOWNLOAD=0 \
		OPENCODE_DISABLE_AUTOUPDATE=0 \
		bash -c '
			set -euo pipefail
			[[ $(command -v opencode) == "$1" ]]
			[[ ! -w $1 ]]
			shopt -s nullglob
			network_interfaces=()
			for interface_path in /proc/sys/net/ipv4/conf/*; do
				interface=${interface_path##*/}
				[[ $interface == all || $interface == default ]] || \
					network_interfaces+=("$interface")
			done
			[[ ${#network_interfaces[@]} -eq 1 ]]
			[[ ${network_interfaces[0]} == lo ]]
			version_root=$(mktemp -d "$TMPDIR/dotfiles-opencode-version.XXXXXX")
			cleanup_version_probe() {
				[[ -z ${version_root-} ]] || rm -rf -- "$version_root"
			}
			trap cleanup_version_probe EXIT
			mkdir -p -- \
				"$version_root/home" \
				"$version_root/work" \
				"$version_root/tmp" \
				"$version_root/config" \
				"$version_root/data" \
				"$version_root/state" \
				"$version_root/cache"
			reported_version=$(
				cd -- "$version_root/work"
				env -i \
					HOME="$version_root/home" \
					PATH=/usr/bin:/bin \
					TMPDIR="$version_root/tmp" \
					XDG_CONFIG_HOME="$version_root/config" \
					XDG_DATA_HOME="$version_root/data" \
					XDG_STATE_HOME="$version_root/state" \
					XDG_CACHE_HOME="$version_root/cache" \
					"$1" --version
			)
			[[ $reported_version == "$5" ]]
			cleanup_version_probe
			version_root=
			bash "$2" "$3" "$4"
		' bash "$controlled_opencode" "$validator" "$main" "$tui" "$installed_version"

	assert_eq 0 "$COMMAND_STATUS" \
		'the production validator should accept the tracked objects with the active Mise-managed OpenCode' || return 1
	assert_eq '' "$COMMAND_OUTPUT" \
		'installed OpenCode validation should be silent' || return 1
	assert_eq "$canaries_before" "$(snapshot_installed_opencode_canaries)" \
		'networkless native validation should not read through into or mutate hostile configuration and state' || return 1
	if compgen -G "$FIXTURE_TMP/dotfiles-opencode-validator.*" >/dev/null; then
		printf '  installed OpenCode validation left generated validator state\n' >&2
		return 1
	fi
}

assert_validator_rejects_before_launch() {
	local description=$1 main=$2 tui=$3
	rm -f -- "$OPENCODE_FAKE_CALL" "$OPENCODE_FAKE_ROOT"
	run_in_sandbox "$FIXTURE_REPO" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash "$FIXTURE_REPO/lib/dotfiles/opencode-validator.sh" "$main" "$tui"
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  validator accepted %s\n' "$description" >&2
		return 1
	fi
	if [[ -e $OPENCODE_FAKE_CALL || -e $OPENCODE_FAKE_ROOT ]]; then
		printf '  validator launched OpenCode for %s\n' "$description" >&2
		return 1
	fi
	if compgen -G "$FIXTURE_TMP/dotfiles-opencode-validator.*" >/dev/null; then
		printf '  validator left temporary state after rejecting %s\n' "$description" >&2
		return 1
	fi
}

snapshot_opencode_siblings() {
	(
		cd -- "$FIXTURE_HOME/.config/opencode" || return 1
		find . -mindepth 1 \
			! -path './opencode.json' \
			! -path './tui.json' \
			-printf '%P|%y|%m|%s\n' | LC_ALL=C sort
		find . -type f \
			! -path './opencode.json' \
			! -path './tui.json' \
			-print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
	)
}

assert_opencode_leaf_links() {
	local relative target source
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		target=$FIXTURE_HOME/$relative
		source=$FIXTURE_REPO/config/opencode/$relative
		if [[ ! -L $target ]]; then
			printf '  expected OpenCode leaf link is absent: %s\n' "$target" >&2
			return 1
		fi
		assert_eq "$(realpath -e -- "$source")" "$(realpath -e -- "$target")" \
			'OpenCode leaf should resolve to the active clone source' || return 1
	done
	if [[ ! -d $FIXTURE_HOME/.config/opencode || -L $FIXTURE_HOME/.config/opencode ]]; then
		printf '  OpenCode config parent should remain an ordinary directory\n' >&2
		return 1
	fi
}

assert_opencode_leaf_links_absent() {
	local relative target
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		target=$FIXTURE_HOME/$relative
		if [[ -e $target || -L $target ]]; then
			printf '  removed OpenCode leaf remains present: %s\n' "$target" >&2
			return 1
		fi
	done
}

extract_documented_bash_block() {
	local heading=$1 output=$2
	awk -v heading="$heading" '
		$0 == heading {
			heading_count++
			seeking = 1
			next
		}
		seeking && $0 ~ /^#{1,6} / {
			seeking = 0
		}
		seeking && $0 == "```bash" {
			fence_count++
			seeking = 0
			capturing = 1
			next
		}
		capturing && $0 == "```" {
			capturing = 0
			close_count++
			next
		}
		capturing { print }
		END {
			if (heading_count != 1 || fence_count != 1 || close_count != 1 || capturing) {
				exit 64
			}
		}
	' "$FIXTURE_REPO/docs/opencode.md" >"$output"
}

prepare_documented_opencode_scripts() {
	OPENCODE_MIGRATION_SCRIPT=$FIXTURE_ROOT/documented-opencode-migration.sh
	OPENCODE_MANUAL_RECOVERY_EXTRACT=$FIXTURE_ROOT/documented-opencode-manual-recovery.extracted.sh
	OPENCODE_MANUAL_RECOVERY_SCRIPT=$FIXTURE_ROOT/documented-opencode-manual-recovery.sh
	extract_documented_bash_block \
		'### Back up, apply, and recover as one pair' "$OPENCODE_MIGRATION_SCRIPT" || return 1
	extract_documented_bash_block \
		'## Recovery after an incomplete migration' "$OPENCODE_MANUAL_RECOVERY_EXTRACT" || return 1
	awk '
		$0 == "backup_root=/absolute/path/from-the-migration-output" {
			placeholder_count++
			print "backup_root=${DOTFILES_TEST_BACKUP_ROOT:?}"
			next
		}
		{ print }
		END { if (placeholder_count != 1) exit 64 }
	' "$OPENCODE_MANUAL_RECOVERY_EXTRACT" >"$OPENCODE_MANUAL_RECOVERY_SCRIPT" || return 1
	bash -n "$OPENCODE_MIGRATION_SCRIPT" || return 1
	bash -n "$OPENCODE_MANUAL_RECOVERY_SCRIPT"
}

configure_documented_command_loggers() {
	local command executable body
	for command in cp cmp mv readlink rm sha256sum stat sync; do
		executable=$(command -v "$command") || return 1
		printf -v body '%s\n' \
			"{ printf 'command|$command'; printf '|%s' \"\$@\"; printf '\\n'; } >>\"\$DOTFILES_TEST_DOC_EVENTS\"" \
			"exec $(printf '%q' "$executable") \"\$@\""
		make_fake "$command" "$body" || return 1
	done
}

configure_documented_opencode_commands() {
	make_fake git '
printf "git %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
printf "command|git" >>"$DOTFILES_TEST_DOC_EVENTS"
printf "|%s" "$@" >>"$DOTFILES_TEST_DOC_EVENTS"
printf "\n" >>"$DOTFILES_TEST_DOC_EVENTS"
if [[ $* == "rev-parse --show-toplevel" ]]; then
	if [[ $(<"$DOTFILES_TEST_DOC_SCENARIO_FILE") == manual-dangling-temp ]]; then
		pid=$PPID
		for _ in 1 2 3; do
			ln -s "$DOTFILES_TEST_REPO/missing-restore-temp" \
				"$HOME/.config/opencode/opencode.json.dotfiles-restore.$pid.0" 2>/dev/null || true
			parent=
			while read -r key value _; do
				if [[ $key == PPid: ]]; then parent=$value; break; fi
			done <"/proc/$pid/status"
			[[ -n $parent && $parent != 0 && $parent != "$pid" ]] || break
			pid=$parent
		done
	fi
	printf "%s\n" "$DOTFILES_TEST_REPO"
	exit 0
fi
exit 64
' || return 1
	make_fake make '
printf "make %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
printf "command|make\n" >>"$DOTFILES_TEST_DOC_EVENTS"
export DOTFILES_TEST_DOC_MIGRATION_PID=$PPID
source "$DOTFILES_TEST_REPO/lib/dotfiles/core.sh"
source "$DOTFILES_TEST_REPO/lib/dotfiles/packages.sh"
if [[ $(<"$DOTFILES_TEST_DOC_SCENARIO_FILE") == empty ]]; then
	apply_packages
else
	apply_packages opencode
fi
' || return 1
	make_fake stow '
printf "stow %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
printf "command|stow" >>"$DOTFILES_TEST_DOC_EVENTS"
printf "|%s" "$@" >>"$DOTFILES_TEST_DOC_EVENTS"
printf "\n" >>"$DOTFILES_TEST_DOC_EVENTS"
if [[ " $* " == *" --simulate "* ]]; then
	exit 0
fi
scenario=$(<"$DOTFILES_TEST_DOC_SCENARIO_FILE")
mkdir -p -- "$HOME/.config/opencode"
ln -s "$DOTFILES_TEST_REPO/config/opencode/.config/opencode/opencode.json" \
	"$HOME/.config/opencode/opencode.json"
case $scenario in
	apply-failure)
		printf "%s\n" "controlled partial apply failure" >&2
		exit 46
		;;
	signal)
		printf "%s\n" "controlled catchable migration interruption" >&2
		kill -TERM "$DOTFILES_TEST_DOC_MIGRATION_PID"
		exit 143
		;;
esac
ln -s "$DOTFILES_TEST_REPO/config/opencode/.config/opencode/tui.json" \
	"$HOME/.config/opencode/tui.json"
' || return 1
	configure_documented_command_loggers
}

setup_documented_opencode_fixture() {
	new_fixture || return 1
	configure_opencode_validator_fake || return 1
	local config_dir=$FIXTURE_HOME/.config/opencode
	local hostile=$FIXTURE_ROOT/opencode-hostile
	mkdir -p -- \
		"$config_dir/node_modules/generated" \
		"$config_dir/plugin" \
		"$config_dir/plugins" \
		"$FIXTURE_HOME/.opencode/plugin" \
		"$hostile/config-dir" || return 1
	cp --archive -- "$FIXTURE_REPO/config/opencode/$OPENCODE_MAIN_RELATIVE" \
		"$config_dir/opencode.json" || return 1
	cp --archive -- "$FIXTURE_REPO/config/opencode/$OPENCODE_TUI_RELATIVE" \
		"$config_dir/tui.json" || return 1
	chmod 0640 "$config_dir/opencode.json" || return 1
	chmod 0604 "$config_dir/tui.json" || return 1
	touch -d '2026-08-25 12:34:56.123456789 UTC' "$config_dir/opencode.json" || return 1
	touch -d '2026-08-25 12:35:57.987654321 UTC' "$config_dir/tui.json" || return 1
	OPENCODE_DOCUMENT_MAIN_METADATA=$(stat -c '%f:%u:%g:%s:%y' "$config_dir/opencode.json") || return 1
	OPENCODE_DOCUMENT_TUI_METADATA=$(stat -c '%f:%u:%g:%s:%y' "$config_dir/tui.json") || return 1
	printf '%s\n' '{"username":"config-json-canary"}' >"$config_dir/config.json" || return 1
	printf '%s\n' '{"username":"jsonc-canary"}' >"$config_dir/opencode.jsonc" || return 1
	printf '%s\n' '{"theme":"dark"}' >"$config_dir/tui.jsonc" || return 1
	printf '%s\n' 'export default () => ({})' >"$config_dir/plugin/server.js" || return 1
	printf '%s\n' 'export default () => ({})' >"$config_dir/plugins/tui.js" || return 1
	printf '%s\n' '{"username":"global-dot-opencode-canary"}' >"$FIXTURE_HOME/.opencode/opencode.json" || return 1
	printf '%s\n' 'export default () => ({})' >"$FIXTURE_HOME/.opencode/plugin/global.js" || return 1
	printf '%s\n' 'downloaded dependency' >"$config_dir/node_modules/generated/sentinel" || return 1
	printf '%s\n' '{"username":"hostile-custom"}' >"$hostile/custom.json" || return 1
	printf '%s\n' '{"theme":"dark"}' >"$hostile/tui.json" || return 1
	printf '%s\n' '{"username":"hostile-dir"}' >"$hostile/config-dir/opencode.json" || return 1
	printf '%s\n' 'unrelated recovery canary' >"$hostile/unrelated-target" || return 1
	ln -s "$hostile/unrelated-target" "$config_dir/unrelated-link" || return 1
	OPENCODE_MIGRATION_EVENTS=$FIXTURE_ROOT/opencode-document-events
	OPENCODE_MIGRATION_SCENARIO_FILE=$FIXTURE_ROOT/opencode-document-scenario
	OPENCODE_MIGRATION_HOSTILE=$hostile
	OPENCODE_MIGRATION_BACKUP_PARENT=$FIXTURE_STATE/dotfiles/backups/opencode
	: >"$OPENCODE_MIGRATION_EVENTS"
	printf '%s\n' success >"$OPENCODE_MIGRATION_SCENARIO_FILE"
	prepare_documented_opencode_scripts || return 1
	configure_documented_opencode_commands
}

run_documented_opencode_migration() {
	local scenario=$1 input=$2
	printf '%s\n' "$scenario" >"$OPENCODE_MIGRATION_SCENARIO_FILE"
	rm -f -- "$FIXTURE_ROOT/opencode-validator-fail"
	[[ $scenario != validator-failure ]] || touch "$FIXTURE_ROOT/opencode-validator-fail"
	DOTFILES_TEST_INPUT=$input run_in_sandbox "$FIXTURE_REPO" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/env \
		DOTFILES_TEST_DOC_EVENTS="$OPENCODE_MIGRATION_EVENTS" \
		DOTFILES_TEST_DOC_SCENARIO_FILE="$OPENCODE_MIGRATION_SCENARIO_FILE" \
		OPENCODE_CONFIG="$OPENCODE_MIGRATION_HOSTILE/custom.json" \
		OPENCODE_TUI_CONFIG="$OPENCODE_MIGRATION_HOSTILE/tui.json" \
		OPENCODE_CONFIG_CONTENT='{"plugin":["hostile-inline"]}' \
		OPENCODE_CONFIG_DIR="$OPENCODE_MIGRATION_HOSTILE/config-dir" \
		OPENCODE_DISABLE_PROJECT_CONFIG=0 \
		bash "$OPENCODE_MIGRATION_SCRIPT"
}

snapshot_opencode_migration_canaries() {
	(
		cd -- "$FIXTURE_ROOT" || return 1
		find \
			user/home/.config/opencode \
			user/home/.opencode \
			opencode-hostile \
			! -path 'user/home/.config/opencode/opencode.json' \
			! -path 'user/home/.config/opencode/tui.json' \
			-printf '%p|%y|%m|%s\n' | LC_ALL=C sort
		find \
			user/home/.config/opencode \
			user/home/.opencode \
			opencode-hostile \
			-type l \
			! -path 'user/home/.config/opencode/opencode.json' \
			! -path 'user/home/.config/opencode/tui.json' \
			-printf '%p|%l\n' | LC_ALL=C sort
		find \
			user/home/.config/opencode \
			user/home/.opencode \
			opencode-hostile \
			-type f \
			! -path 'user/home/.config/opencode/opencode.json' \
			! -path 'user/home/.config/opencode/tui.json' \
			-print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
	)
}

assert_opencode_migration_live_pair_matches_sources() {
	local relative target source
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		target=$FIXTURE_HOME/$relative
		source=$FIXTURE_REPO/config/opencode/$relative
		if [[ ! -f $target || -L $target ]]; then
			printf '  migration live input should be a regular file: %s\n' "$target" >&2
			return 1
		fi
		cmp -s -- "$target" "$source" || {
			printf '  migration live input should match its tracked source: %s\n' "$relative" >&2
			return 1
		}
	done
}

documented_event_index() {
	local needle=$1
	awk -v needle="$needle" 'index($0, needle) { print NR; exit }' "$OPENCODE_MIGRATION_EVENTS"
}

assert_documented_migration_preparation_order() {
	local target_main=$FIXTURE_HOME/$OPENCODE_MAIN_RELATIVE
	local target_tui=$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE
	local backup_root removal index requirement
	local -a backup_roots=()
	mapfile -t backup_roots < <(find "$OPENCODE_MIGRATION_BACKUP_PARENT" \
		-mindepth 1 -maxdepth 1 -type d -printf '%p\n' | LC_ALL=C sort)
	assert_eq 1 "${#backup_roots[@]}" \
		'preparation-order audit requires the single paired backup tree' || return 1
	backup_root=${backup_roots[0]}
	removal=$(documented_event_index "command|rm|--|$target_main|$target_tui")
	if [[ -z $removal ]]; then
		printf '  documented migration did not remove the pair in one operation\n' >&2
		return 1
	fi
	for requirement in \
		"command|cp|--archive|--|$target_main|$backup_root/$OPENCODE_MAIN_RELATIVE" \
		"command|cp|--archive|--|$target_tui|$backup_root/$OPENCODE_TUI_RELATIVE" \
		"command|cmp|-s|--|$target_main|$backup_root/$OPENCODE_MAIN_RELATIVE" \
		"command|cmp|-s|--|$target_tui|$backup_root/$OPENCODE_TUI_RELATIVE" \
		"command|stat|-c|%f:%u:%g:%s:%y|--|$backup_root/$OPENCODE_MAIN_RELATIVE" \
		"command|stat|-c|%f:%u:%g:%s:%y|--|$backup_root/$OPENCODE_TUI_RELATIVE" \
		"command|sha256sum|--|$backup_root/$OPENCODE_MAIN_RELATIVE" \
		"command|sha256sum|--|$backup_root/$OPENCODE_TUI_RELATIVE" \
		"command|mv|--no-clobber|--no-target-directory|--|$backup_root/.SHA256SUMS.tmp|$backup_root/SHA256SUMS" \
		"command|sync|--file-system|--|$backup_root" \
		'command|sha256sum|--check|--strict|--quiet|--|SHA256SUMS'; do
		index=$(documented_event_index "$requirement")
		if [[ -z $index || $index -ge $removal ]]; then
			printf '  required backup verification did not precede pair removal: %s\n' "$requirement" >&2
			return 1
		fi
	done
}

assert_documented_opencode_backup() {
	local relative backup_root timestamp digest expected_manifest actual_manifest expected_metadata
	local -a backup_roots=()
	mapfile -t backup_roots < <(find "$OPENCODE_MIGRATION_BACKUP_PARENT" \
		-mindepth 1 -maxdepth 1 -type d -printf '%p\n' | LC_ALL=C sort)
	assert_eq 1 "${#backup_roots[@]}" \
		'documented migration should retain exactly one timestamped backup tree' || return 1
	backup_root=${backup_roots[0]}
	timestamp=${backup_root##*/}
	if [[ ! $timestamp =~ ^[0-9]{8}T[0-9]{6}\.[0-9]{9}Z$ ]]; then
		printf '  documented migration backup should use a nanosecond UTC timestamp: %s\n' "$timestamp" >&2
		return 1
	fi
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		if [[ ! -f $backup_root/$relative || -L $backup_root/$relative ]]; then
			printf '  documented migration backup should be a regular file: %s\n' "$backup_root/$relative" >&2
			return 1
		fi
		cmp -s -- "$backup_root/$relative" "$FIXTURE_REPO/config/opencode/$relative" || {
			printf '  documented migration backup should retain exact source bytes: %s\n' "$relative" >&2
			return 1
		}
		if [[ $relative == "$OPENCODE_MAIN_RELATIVE" ]]; then
			expected_metadata=$OPENCODE_DOCUMENT_MAIN_METADATA
		else
			expected_metadata=$OPENCODE_DOCUMENT_TUI_METADATA
		fi
		assert_eq "$expected_metadata" "$(stat -c '%f:%u:%g:%s:%y' "$backup_root/$relative")" \
			'documented migration should preserve complete compared backup metadata' || return 1
	done
	digest=$(sha256sum "$backup_root/$OPENCODE_MAIN_RELATIVE")
	expected_manifest="${digest%% *}  $OPENCODE_MAIN_RELATIVE"
	digest=$(sha256sum "$backup_root/$OPENCODE_TUI_RELATIVE")
	expected_manifest+=$'\n'"${digest%% *}  $OPENCODE_TUI_RELATIVE"
	actual_manifest=$(<"$backup_root/SHA256SUMS") || return 1
	assert_eq "$expected_manifest" "$actual_manifest" \
		'the retained manifest should contain exactly the ordered managed pair' || return 1
	(cd -- "$backup_root" && sha256sum --check --strict --quiet -- SHA256SUMS) || {
		printf '  retained documented migration manifest did not validate\n' >&2
		return 1
	}
	OPENCODE_DOCUMENT_BACKUP_ROOT=$backup_root
}

assert_documented_pair_recovered_from_backup() {
	assert_documented_opencode_backup || return 1
	local relative
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		if [[ ! -f $FIXTURE_HOME/$relative || -L $FIXTURE_HOME/$relative ]]; then
			printf '  documented recovery should restore an unmanaged regular file: %s\n' "$relative" >&2
			return 1
		fi
		cmp -s -- "$FIXTURE_HOME/$relative" "$OPENCODE_DOCUMENT_BACKUP_ROOT/$relative" || {
			printf '  documented recovery should restore exact paired backup bytes: %s\n' "$relative" >&2
			return 1
		}
	done
	if [[ ! -L $FIXTURE_HOME/.config/opencode/unrelated-link ]] || \
		[[ $(readlink -- "$FIXTURE_HOME/.config/opencode/unrelated-link") != "$OPENCODE_MIGRATION_HOSTILE/unrelated-target" ]]; then
		printf '  documented recovery should preserve the unrelated sibling link\n' >&2
		return 1
	fi
}

exercise_incomplete_documented_opencode_migration() {
	local scenario=$1 input=$2 expected_output=$3 expected_status=${4-1}
	setup_documented_opencode_fixture || return 1
	local canaries_before
	canaries_before=$(snapshot_opencode_migration_canaries) || return 1

	run_documented_opencode_migration "$scenario" "$input"
	assert_eq "$expected_status" "$COMMAND_STATUS" \
		"documented $scenario migration should preserve its failure status" || return 1
	assert_contains "$COMMAND_OUTPUT" "$expected_output" \
		"documented $scenario migration should reach its controlled incomplete Apply result" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Restored both files from:' \
		"documented $scenario migration should run automatic paired recovery" || return 1
	assert_documented_migration_preparation_order || return 1
	assert_documented_pair_recovered_from_backup || return 1
	assert_eq "$canaries_before" "$(snapshot_opencode_migration_canaries)" \
		"documented $scenario recovery should preserve competing and unrelated paths"
}

setup_documented_manual_recovery_fixture() {
	setup_documented_opencode_fixture || return 1
	local relative digest
	OPENCODE_DOCUMENT_BACKUP_ROOT=$OPENCODE_MIGRATION_BACKUP_PARENT/20260825T123456.123456789Z
	mkdir -p -- "$OPENCODE_DOCUMENT_BACKUP_ROOT/.config/opencode" || return 1
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		cp --archive -- "$FIXTURE_HOME/$relative" "$OPENCODE_DOCUMENT_BACKUP_ROOT/$relative" || return 1
	done
	digest=$(sha256sum "$OPENCODE_DOCUMENT_BACKUP_ROOT/$OPENCODE_MAIN_RELATIVE") || return 1
	printf '%s  %s\n' "${digest%% *}" "$OPENCODE_MAIN_RELATIVE" \
		>"$OPENCODE_DOCUMENT_BACKUP_ROOT/SHA256SUMS" || return 1
	digest=$(sha256sum "$OPENCODE_DOCUMENT_BACKUP_ROOT/$OPENCODE_TUI_RELATIVE") || return 1
	printf '%s  %s\n' "${digest%% *}" "$OPENCODE_TUI_RELATIVE" \
		>>"$OPENCODE_DOCUMENT_BACKUP_ROOT/SHA256SUMS" || return 1
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		rm -- "$FIXTURE_HOME/$relative" || return 1
		ln -s "$FIXTURE_REPO/config/opencode/$relative" "$FIXTURE_HOME/$relative" || return 1
	done
	: >"$OPENCODE_MIGRATION_EVENTS"
}

snapshot_opencode_managed_pair() {
	local relative target
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		target=$FIXTURE_HOME/$relative
		if [[ -L $target ]]; then
			printf '%s|link|%s\n' "$relative" "$(readlink -- "$target")"
		elif [[ -f $target ]]; then
			printf '%s|file|%s|%s\n' "$relative" \
				"$(stat -c '%f:%u:%g:%s:%y' "$target")" "$(sha256sum "$target")"
		elif [[ -e $target ]]; then
			printf '%s|other|%s\n' "$relative" "$(stat -c %F "$target")"
		else
			printf '%s|absent\n' "$relative"
		fi
	done
}

run_documented_manual_recovery() {
	local collision=${1-none}
	printf '%s\n' "manual-$collision" >"$OPENCODE_MIGRATION_SCENARIO_FILE"
	run_in_sandbox "$FIXTURE_REPO" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/env \
		DOTFILES_TEST_BACKUP_ROOT="$OPENCODE_DOCUMENT_BACKUP_ROOT" \
		DOTFILES_TEST_DOC_EVENTS="$OPENCODE_MIGRATION_EVENTS" \
		DOTFILES_TEST_DOC_SCENARIO_FILE="$OPENCODE_MIGRATION_SCENARIO_FILE" \
		bash "$OPENCODE_MANUAL_RECOVERY_SCRIPT"
}

assert_documented_manual_recovery_complete() {
	local relative
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		if [[ ! -f $FIXTURE_HOME/$relative || -L $FIXTURE_HOME/$relative ]] ||
			! cmp -s -- "$FIXTURE_HOME/$relative" "$OPENCODE_DOCUMENT_BACKUP_ROOT/$relative"; then
			printf '  manual recovery did not restore the exact regular pair: %s\n' "$relative" >&2
			return 1
		fi
	done
	if compgen -G "$FIXTURE_HOME/.config/opencode/*.dotfiles-restore.*" >/dev/null; then
		printf '  manual recovery left a restore temporary behind\n' >&2
		return 1
	fi
}

setup_already_moved_opencode_fixture() {
	new_fixture || return 1
	configure_opencode_validator_fake || return 1
	local config_dir=$FIXTURE_HOME/.config/opencode
	mkdir -p -- "$config_dir/generated" || return 1
	printf '%s\n' 'unrelated sibling' >"$config_dir/generated/sentinel" || return 1
	rm -- "$FIXTURE_BIN/stow" || return 1
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages opencode
	assert_eq 0 "$COMMAND_STATUS" 'moved-clone setup should apply the package from the old clone' || return 1
	OPENCODE_MOVED_SIBLINGS=$(snapshot_opencode_siblings) || return 1
	OPENCODE_OLD_REPO=$(readlink -f -- "$FIXTURE_REPO") || return 1
	local moved_repo=$FIXTURE_ROOT/already-moved/dotfiles
	mkdir -p -- "${moved_repo%/*}" || return 1
	mv -- "$FIXTURE_REPO" "$moved_repo" || return 1
	FIXTURE_REPO=$moved_repo
	OPENCODE_MOVED_EVENTS=$FIXTURE_ROOT/opencode-moved-events
	: >"$OPENCODE_MOVED_EVENTS"
}

assert_old_opencode_links_are_dangling() {
	local relative target expected stored resolved
	for relative in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		target=$FIXTURE_HOME/$relative
		expected=$(readlink -m -- "$OPENCODE_OLD_REPO/config/opencode/$relative") || return 1
		if [[ ! -L $target || -e $target ]]; then
			printf '  expected an old-clone dangling managed link: %s\n' "$target" >&2
			return 1
		fi
		stored=$(readlink -- "$target") || return 1
		if [[ $stored == /* ]]; then
			resolved=$(readlink -m -- "$stored") || return 1
		else
			resolved=$(readlink -m -- "${target%/*}/$stored") || return 1
		fi
		assert_eq "$expected" "$resolved" \
			'the stored dangling referent should identify its matching old-clone package source' || return 1
	done
}

run_already_moved_opencode_recovery() {
	DOTFILES_TEST_INPUT='y\n' run_in_sandbox "$FIXTURE_REPO" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/env DOTFILES_TEST_MOVED_EVENTS="$OPENCODE_MOVED_EVENTS" \
		bash -c '
			set -euo pipefail
			old_repo=$1
			new_repo=$2
			targets=(
				"$HOME/.config/opencode/opencode.json"
				"$HOME/.config/opencode/tui.json"
			)
			relatives=(
				.config/opencode/opencode.json
				.config/opencode/tui.json
			)
			for i in 0 1; do
				[[ -L ${targets[$i]} ]]
				stored=$(readlink -- "${targets[$i]}")
				if [[ $stored == /* ]]; then
					resolved=$(readlink -m -- "$stored")
				else
					resolved=$(readlink -m -- "${targets[$i]%/*}/$stored")
				fi
				expected=$(readlink -m -- "$old_repo/config/opencode/${relatives[$i]}")
				[[ $resolved == "$expected" ]]
				printf "verified|%s|%s\n" "${relatives[$i]}" "$resolved" \
					>>"$DOTFILES_TEST_MOVED_EVENTS"
			done
			rm -- "${targets[0]}" "${targets[1]}"
			printf "removed|pair\n" >>"$DOTFILES_TEST_MOVED_EVENTS"
			source "$new_repo/lib/dotfiles/core.sh"
			source "$new_repo/lib/dotfiles/packages.sh"
			apply_packages opencode
		' bash "$OPENCODE_OLD_REPO" "$FIXTURE_REPO"
}

exercise_already_moved_opencode_clone() {
	setup_already_moved_opencode_fixture || return 1
	assert_old_opencode_links_are_dangling || return 1
	local pair_before
	pair_before=$(snapshot_opencode_managed_pair) || return 1

	run_in_sandbox "$FIXTURE_REPO" "$FIXTURE_BIN:/usr/bin:/bin" \
		stow --no-folding --simulate --verbose=2 \
			--dir "$FIXTURE_REPO/config" --target "$FIXTURE_HOME" opencode
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  new-clone Stow simulation silently accepted old dangling links\n' >&2
		return 1
	fi
	assert_eq "$pair_before" "$(snapshot_opencode_managed_pair)" \
		'new-clone simulation should not change either dangling link' || return 1
	run_in_sandbox "$FIXTURE_REPO" "$FIXTURE_BIN:/usr/bin:/bin" \
		stow --no-folding --restow --simulate --verbose=2 \
			--dir "$FIXTURE_REPO/config" --target "$FIXTURE_HOME" opencode
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  new-clone Stow restow simulation silently accepted old dangling links\n' >&2
		return 1
	fi
	assert_eq "$pair_before" "$(snapshot_opencode_managed_pair)" \
		'new-clone restow simulation should not change either dangling link' || return 1

	run_already_moved_opencode_recovery
	assert_eq 0 "$COMMAND_STATUS" 'verified old-clone pair recovery should reapply from the moved clone' || return 1
	local expected_events
	expected_events=$(printf 'verified|%s|%s\nverified|%s|%s\nremoved|pair' \
		"$OPENCODE_MAIN_RELATIVE" "$(readlink -m -- "$OPENCODE_OLD_REPO/config/opencode/$OPENCODE_MAIN_RELATIVE")" \
		"$OPENCODE_TUI_RELATIVE" "$(readlink -m -- "$OPENCODE_OLD_REPO/config/opencode/$OPENCODE_TUI_RELATIVE")") || return 1
	assert_eq "$expected_events" "$(<"$OPENCODE_MOVED_EVENTS")" \
		'both old stored referents should be verified before the pair is removed' || return 1
	assert_opencode_leaf_links || return 1
	assert_eq "$OPENCODE_MOVED_SIBLINGS" "$(snapshot_opencode_siblings)" \
		'already-moved clone recovery should preserve unrelated siblings' || return 1

	setup_already_moved_opencode_fixture || return 1
	local main_before tui_before foreign=$FIXTURE_ROOT/foreign-old-clone-source
	rm -- "$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE" || return 1
	ln -s "$foreign" "$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE" || return 1
	main_before=$(readlink -- "$FIXTURE_HOME/$OPENCODE_MAIN_RELATIVE") || return 1
	tui_before=$(readlink -- "$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE") || return 1
	run_already_moved_opencode_recovery
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  mismatched old-clone managed link should block pair recovery\n' >&2
		return 1
	fi
	assert_eq "$main_before" "$(readlink -- "$FIXTURE_HOME/$OPENCODE_MAIN_RELATIVE")" \
		'mismatch rejection should preserve the first verified dangling link' || return 1
	assert_eq "$tui_before" "$(readlink -- "$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE")" \
		'mismatch rejection should preserve the mismatched dangling link' || return 1
	if [[ $(<"$OPENCODE_MOVED_EVENTS") == *'removed|'* ]]; then
		printf '  mismatch rejection removed a link before verifying the complete pair\n' >&2
		return 1
	fi
	assert_eq "$OPENCODE_MOVED_SIBLINGS" "$(snapshot_opencode_siblings)" \
		'mismatched moved-clone recovery should preserve unrelated siblings'
}

test_opencode_package_matches_the_native_configuration_contract() {
	new_fixture || return 1
	local package_root=$FIXTURE_REPO/config/opencode
	local expected_tree actual_tree

	expected_tree=$'.config/opencode/opencode.json|f\n.config/opencode/tui.json|f\n.config/opencode|d\n.config|d'
	actual_tree=$(cd -- "$package_root" && find . -mindepth 1 -printf '%P|%y\n' | LC_ALL=C sort) || return 1
	assert_eq "$expected_tree" "$actual_tree" \
		'the OpenCode package should own exactly two settings leaves and their parent directories' || return 1

	jq -e '
		type == "object" and
		(keys_unsorted == ["$schema", "autoupdate"]) and
		. == {"$schema":"https://opencode.ai/config.json","autoupdate":false}
	' "$package_root/$OPENCODE_MAIN_RELATIVE" >/dev/null || {
		printf '  opencode.json should be the exact approved object in key order\n' >&2
		return 1
	}
	jq -e '
		type == "object" and
		(keys_unsorted == ["$schema", "theme"]) and
		. == {"$schema":"https://opencode.ai/tui.json","theme":"system"}
	' "$package_root/$OPENCODE_TUI_RELATIVE" >/dev/null || {
		printf '  tui.json should be the exact approved object in key order\n' >&2
		return 1
	}

	jq -e --arg validator "$OPENCODE_VALIDATOR" '
		[.packages[] | select(.name == "opencode")] == [{
			"name": "opencode",
			"path": "config/opencode",
			"description": "Complete global OpenCode runtime and TUI settings",
			"dependencies": [],
			"arch_packages": [],
			"prerequisites": ["opencode"],
			"validators": [$validator],
			"documentation": "docs/opencode.md",
			"cleanup": [
				"Removing this package leaves ~/.config/opencode/opencode.json and ~/.config/opencode/tui.json absent",
				"The Mise-managed OpenCode executable and Omarchy wrapper remain installed",
				"Generated OpenCode config siblings, credentials, XDG data, state, caches, plugins, downloaded tools, themes, and language servers are not removed",
				"Migration backups remain under the Dotfiles XDG state backup tree",
				"Restart OpenCode after removal or reapplication"
			]
		}] and
		(.packages[] | select(.name == "opencode") | keys_unsorted) == [
			"name", "path", "description", "dependencies", "arch_packages",
			"prerequisites", "validators", "documentation", "cleanup"
		]
	' "$FIXTURE_REPO/packages.json" >/dev/null || {
		printf '  the opencode catalog entry should match the exact native configuration contract\n' >&2
		return 1
	}
}

test_validator_launches_opencode_with_the_isolated_native_config_contract() {
	new_fixture || return 1
	configure_opencode_validator_fake || return 1
	local validator=$FIXTURE_REPO/lib/dotfiles/opencode-validator.sh
	local main=$FIXTURE_REPO/config/opencode/$OPENCODE_MAIN_RELATIVE
	local tui=$FIXTURE_REPO/config/opencode/$OPENCODE_TUI_RELATIVE
	local project_canary=$FIXTURE_REPO/opencode.json
	local skill_canary=$FIXTURE_HOME/.agents/skills/private/SKILL.md
	local canaries_before validator_root key value mode

	mkdir -p -- "$(dirname -- "$skill_canary")" || return 1
	printf '%s\n' '{"plugin":["project-canary"],"lsp":true}' >"$project_canary" || return 1
	printf '%s\n' 'private skill canary' >"$skill_canary" || return 1
	canaries_before=$(sha256sum "$project_canary" "$skill_canary") || return 1

	run_in_sandbox "$FIXTURE_REPO" "$FIXTURE_BIN:/usr/bin:/bin" \
		/usr/bin/env \
		OPENCODE_CONFIG=/hostile/config.json \
		OPENCODE_CONFIG_CONTENT='{"lsp":true}' \
		OPENCODE_DB="$FIXTURE_ROOT/hostile.db" \
		OPENCODE_PURE=0 \
		OPENCODE_DISABLE_PROJECT_CONFIG=0 \
		OPENCODE_DISABLE_DEFAULT_PLUGINS=0 \
		OPENCODE_DISABLE_EXTERNAL_SKILLS=0 \
		OPENCODE_DISABLE_CLAUDE_CODE=0 \
		OPENCODE_DISABLE_MODELS_FETCH=0 \
		OPENCODE_DISABLE_LSP_DOWNLOAD=0 \
		OPENCODE_DISABLE_AUTOUPDATE=0 \
		OPENCODE_TEST_MANAGED_CONFIG_DIR="$FIXTURE_ROOT/hostile-managed" \
		OPENCODE_HOSTILE_SENTINEL=must-not-leak \
		bash "$validator" "$main" "$tui"

	assert_eq 0 "$COMMAND_STATUS" 'the exact tracked objects should pass native OpenCode validation' || return 1
	assert_eq '' "$COMMAND_OUTPUT" 'successful validation should suppress resolved config output' || return 1
	if [[ ! -f $OPENCODE_FAKE_CALL || ! -f $OPENCODE_FAKE_ROOT ]]; then
		printf '  the validator should launch the resolved controlled OpenCode executable\n' >&2
		return 1
	fi
	assert_eq '--pure|debug|config|' "$(validator_call_value ARGV)" \
		'the validator should invoke only the pure debug-config command' || return 1
	assert_eq "$(realpath -e -- "$FIXTURE_BIN/opencode")" "$(validator_call_value EXECUTABLE)" \
		'the validator should resolve the executable before replacing PATH and HOME' || return 1
	assert_eq /usr/bin:/bin "$(validator_call_value PATH)" \
		'the native process should not inherit the executable-discovery path' || return 1
	assert_eq "$main" "$(validator_call_value OPENCODE_CONFIG)" \
		'the isolated process should validate the resolved main candidate' || return 1

	while IFS='|' read -r key value; do
		assert_eq "$value" "$(validator_call_value "$key")" \
			"the validator should force $key to its safe value" || return 1
	done <<'EOF'
OPENCODE_CONFIG_CONTENT|{"lsp":false}
OPENCODE_DB|:memory:
OPENCODE_PURE|1
OPENCODE_DISABLE_PROJECT_CONFIG|1
OPENCODE_DISABLE_DEFAULT_PLUGINS|1
OPENCODE_DISABLE_EXTERNAL_SKILLS|1
OPENCODE_DISABLE_CLAUDE_CODE|1
OPENCODE_DISABLE_MODELS_FETCH|1
OPENCODE_DISABLE_LSP_DOWNLOAD|1
OPENCODE_DISABLE_AUTOUPDATE|1
HOSTILE_SENTINEL|unset
HOME_ENTRIES|0
MANAGED_ENTRIES|0
CONFIG_ENTRIES|0
EOF

	validator_root=$(<"$OPENCODE_FAKE_ROOT") || return 1
	case $validator_root in
		"$FIXTURE_TMP"/dotfiles-opencode-validator.*) ;;
		*)
			printf '  validator temporary root escaped isolated TMPDIR: %s\n' "$validator_root" >&2
			return 1
			;;
	esac
	assert_eq "$validator_root/home" "$(validator_call_value HOME)" \
		'the native process should receive an empty synthetic HOME' || return 1
	assert_eq "$validator_root/work" "$(validator_call_value PWD)" \
		'the native process should run from a neutral temporary directory' || return 1
	assert_eq "$validator_root/tmp" "$(validator_call_value TMPDIR)" \
		'the native process should use its isolated temporary directory' || return 1
	while read -r key; do
		value=$(validator_call_value "$key") || return 1
		case $value in
			"$validator_root"/*) ;;
			*)
				printf '  %s escaped the validator root: %s\n' "$key" "$value" >&2
				return 1
				;;
		esac
	done <<'EOF'
XDG_CONFIG_HOME
XDG_DATA_HOME
XDG_STATE_HOME
XDG_CACHE_HOME
OPENCODE_TEST_MANAGED_CONFIG_DIR
EOF
	for key in CONFIG_MODE MANAGED_MODE; do
		mode=$(validator_call_value "$key") || return 1
		if (( (8#$mode & 0222) != 0 )); then
			printf '  %s should have no write bits: %s\n' "$key" "$mode" >&2
			return 1
		fi
	done
	if [[ -e $validator_root ]]; then
		printf '  validator temporary root should be removed after success: %s\n' "$validator_root" >&2
		return 1
	fi
	assert_eq "$canaries_before" "$(sha256sum "$project_canary" "$skill_canary")" \
		'project config and external skill canaries should remain untouched'
}

test_validator_rejects_nonexact_objects_before_launching_opencode() {
	new_fixture || return 1
	configure_opencode_validator_fake || return 1
	local candidates=$FIXTURE_ROOT/opencode-candidates
	local approved_main=$FIXTURE_REPO/config/opencode/$OPENCODE_MAIN_RELATIVE
	local approved_tui=$FIXTURE_REPO/config/opencode/$OPENCODE_TUI_RELATIVE
	local main=$candidates/opencode.json tui=$candidates/tui.json
	mkdir -p -- "$candidates" || return 1
	cp -- "$approved_main" "$main" || return 1
	cp -- "$approved_tui" "$tui" || return 1

	printf '%s\n' '{' >"$main" || return 1
	assert_validator_rejects_before_launch 'malformed main JSON' "$main" "$tui" || return 1
	cp -- "$approved_main" "$main" || return 1
	printf '%s\n' '{' >"$tui" || return 1
	assert_validator_rejects_before_launch 'malformed TUI JSON' "$main" "$tui" || return 1

	cp -- "$approved_tui" "$tui" || return 1
	jq '.plugin = ["external-plugin"]' "$approved_main" >"$main" || return 1
	assert_validator_rejects_before_launch 'a main external plugin declaration' "$main" "$tui" || return 1
	jq '.lsp = false' "$approved_main" >"$main" || return 1
	assert_validator_rejects_before_launch 'a global LSP policy' "$main" "$tui" || return 1
	jq 'del(.autoupdate)' "$approved_main" >"$main" || return 1
	assert_validator_rejects_before_launch 'a missing main key' "$main" "$tui" || return 1

	cp -- "$approved_main" "$main" || return 1
	jq '.plugin = ["external-plugin"]' "$approved_tui" >"$tui" || return 1
	assert_validator_rejects_before_launch 'a TUI external plugin declaration' "$main" "$tui" || return 1
	jq '.theme = "dark"' "$approved_tui" >"$tui" || return 1
	assert_validator_rejects_before_launch 'a substituted TUI value' "$main" "$tui" || return 1
	assert_validator_rejects_before_launch 'swapped main and TUI inputs' "$approved_tui" "$approved_main"
}

test_validator_cleans_up_and_preserves_only_diagnostics_on_native_failure() {
	new_fixture || return 1
	configure_opencode_validator_fake || return 1
	local main=$FIXTURE_REPO/config/opencode/$OPENCODE_MAIN_RELATIVE
	local tui=$FIXTURE_REPO/config/opencode/$OPENCODE_TUI_RELATIVE
	local validator_root
	touch "$FIXTURE_ROOT/opencode-validator-fail" || return 1

	run_in_sandbox "$FIXTURE_REPO" "$FIXTURE_BIN:/usr/bin:/bin" \
		bash "$FIXTURE_REPO/lib/dotfiles/opencode-validator.sh" "$main" "$tui"
	assert_eq 42 "$COMMAND_STATUS" 'native OpenCode failure status should propagate' || return 1
	assert_contains "$COMMAND_OUTPUT" 'controlled OpenCode diagnostic' \
		'native OpenCode diagnostics should remain visible' || return 1
	if [[ $COMMAND_OUTPUT == *'resolved config containing a secret'* ]]; then
		printf '  failed native validation should not expose resolved config stdout\n' >&2
		return 1
	fi
	if [[ ! -f $OPENCODE_FAKE_ROOT ]]; then
		printf '  controlled native failure should record its validator root\n' >&2
		return 1
	fi
	validator_root=$(<"$OPENCODE_FAKE_ROOT") || return 1
	if [[ -e $validator_root ]]; then
		printf '  validator temporary root should be removed after native failure: %s\n' "$validator_root" >&2
		return 1
	fi
}

test_public_package_lifecycle_preserves_siblings_and_supports_relocation() {
	new_fixture || return 1
	configure_opencode_validator_fake || return 1
	local config_dir=$FIXTURE_HOME/.config/opencode
	local siblings_before relocated_repo old_repo
	mkdir -p -- \
		"$config_dir/node_modules/generated" \
		"$config_dir/themes" \
		"$config_dir/plugins" || return 1
	printf '%s\n' 'node_modules' >"$config_dir/.gitignore" || return 1
	printf '%s\n' '{"private":true}' >"$config_dir/package.json" || return 1
	printf '%s\n' '{"lockfileVersion":3}' >"$config_dir/package-lock.json" || return 1
	printf '%s\n' 'generated bun lock' >"$config_dir/bun.lock" || return 1
	printf '%s\n' 'migration backup' >"$config_dir/opencode.json.tui-migration.bak" || return 1
	printf '%s\n' 'downloaded dependency' >"$config_dir/node_modules/generated/sentinel" || return 1
	printf '%s\n' '{"generated":true}' >"$config_dir/themes/generated.json" || return 1
	printf '%s\n' 'export default () => ({})' >"$config_dir/plugins/local.js" || return 1
	if [[ ! -f $FIXTURE_REPO/docs/opencode.md ]]; then
		printf '%s\n' 'OpenCode fixture documentation' >"$FIXTURE_REPO/docs/opencode.md" || return 1
	fi
	rm -- "$FIXTURE_BIN/stow" || return 1
	siblings_before=$(snapshot_opencode_siblings) || return 1

	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages opencode
	assert_eq 0 "$COMMAND_STATUS" 'public OpenCode apply should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Applied and verified package: opencode' \
		'public apply should include validator-backed verification' || return 1
	if [[ $COMMAND_OUTPUT == *'resolved config containing a secret'* ]]; then
		printf '  public apply exposed resolved OpenCode config output\n' >&2
		return 1
	fi
	assert_opencode_leaf_links || return 1
	assert_eq "$siblings_before" "$(snapshot_opencode_siblings)" \
		'first apply should preserve every excluded OpenCode sibling' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg add'* || $(<"$CALL_LOG") == *'pkg drop'* ]]; then
		printf '  OpenCode Stow lifecycle should not install or remove an Arch package\n' >&2
		return 1
	fi

	run_operation "$FIXTURE_ROOT" remove_package opencode --yes
	assert_eq 0 "$COMMAND_STATUS" 'public OpenCode removal should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Removed and verified package: opencode' \
		'public removal should verify both managed leaves are absent' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Generated OpenCode config siblings, credentials, XDG data, state, caches, plugins, downloaded tools, themes, and language servers are not removed' \
		'public removal should report retained OpenCode state' || return 1
	assert_opencode_leaf_links_absent || return 1
	assert_eq "$siblings_before" "$(snapshot_opencode_siblings)" \
		'removal should preserve every excluded OpenCode sibling' || return 1

	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages opencode
	assert_eq 0 "$COMMAND_STATUS" 'public OpenCode reapplication should succeed' || return 1
	assert_opencode_leaf_links || return 1
	assert_eq "$siblings_before" "$(snapshot_opencode_siblings)" \
		'reapplication should relink around every retained sibling' || return 1

	run_operation "$FIXTURE_ROOT" remove_package opencode --yes
	assert_eq 0 "$COMMAND_STATUS" 'OpenCode should unlink cleanly before clone relocation' || return 1
	assert_opencode_leaf_links_absent || return 1
	old_repo=$FIXTURE_REPO
	relocated_repo=$FIXTURE_ROOT/moved-clone/dotfiles
	mkdir -p -- "$(dirname -- "$relocated_repo")" || return 1
	mv -- "$old_repo" "$relocated_repo" || return 1
	FIXTURE_REPO=$relocated_repo

	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" apply_packages opencode
	assert_eq 0 "$COMMAND_STATUS" 'public OpenCode apply should succeed from the relocated clone' || return 1
	assert_opencode_leaf_links || return 1
	assert_eq "$FIXTURE_REPO/config/opencode/$OPENCODE_MAIN_RELATIVE" \
		"$(validator_call_value OPENCODE_CONFIG)" \
		'the relocated validator should resolve the main config from the active clone' || return 1
	assert_eq "$siblings_before" "$(snapshot_opencode_siblings)" \
		'relocation should preserve every excluded OpenCode sibling'
}

test_documented_migration_verifies_the_pair_before_normal_public_apply() {
	setup_documented_opencode_fixture || return 1
	local canaries_before
	canaries_before=$(snapshot_opencode_migration_canaries) || return 1

	assert_opencode_migration_live_pair_matches_sources || return 1
	run_documented_opencode_migration success 'MIGRATE\ny\n'
	assert_eq 0 "$COMMAND_STATUS" 'documented OpenCode migration should complete through normal public Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Applied and verified package: opencode' \
		'documented migration should use the validator-backed public Apply path' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Migration complete; retained verified backup:' \
		'documented migration should report completion only after its final validator' || return 1
	assert_documented_migration_preparation_order || return 1
	assert_documented_opencode_backup || return 1
	assert_opencode_leaf_links || return 1
	assert_eq 2 "$(awk '$1 == "opencode" { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'documented success should run the production validator during public Apply and after its link audit' || return 1
	assert_eq "$canaries_before" "$(snapshot_opencode_migration_canaries)" \
		'documented migration should preserve generated siblings and competing configuration layers'
}

test_documented_migration_rejects_nonmatching_nonregular_and_uncontained_inputs() {
	local live_tui source_tui before config_dir escaped package_root escaped_package
	setup_documented_opencode_fixture || return 1
	live_tui=$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE
	source_tui=$FIXTURE_REPO/config/opencode/$OPENCODE_TUI_RELATIVE
	printf '%s\n' 'local unapproved value' >>"$live_tui" || return 1
	before=$(snapshot_opencode_managed_pair) || return 1
	run_documented_opencode_migration success 'MIGRATE\ny\n'
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  byte-mismatched live pair should be rejected\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Managed target differs from the approved tracked source:' \
		'byte mismatch should fail the pair gate' || return 1
	assert_eq "$before" "$(snapshot_opencode_managed_pair)" \
		'byte mismatch rejection should preserve both live files' || return 1
	if [[ -d $OPENCODE_MIGRATION_BACKUP_PARENT || $(<"$CALL_LOG") == *'make '* ]]; then
		printf '  byte mismatch should stop before backup, removal, and public Apply\n' >&2
		return 1
	fi

	setup_documented_opencode_fixture || return 1
	live_tui=$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE
	source_tui=$FIXTURE_REPO/config/opencode/$OPENCODE_TUI_RELATIVE
	rm -- "$live_tui" || return 1
	ln -s "$source_tui" "$live_tui" || return 1
	before=$(snapshot_opencode_managed_pair) || return 1
	run_documented_opencode_migration success 'MIGRATE\ny\n'
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  symlinked live pair member should be rejected\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Expected the managed target to be a regular file:' \
		'nonregular input should fail the regular-file gate' || return 1
	assert_eq "$before" "$(snapshot_opencode_managed_pair)" \
		'nonregular rejection should preserve the complete original pair' || return 1
	if [[ -d $OPENCODE_MIGRATION_BACKUP_PARENT || $(<"$CALL_LOG") == *'make '* ]]; then
		printf '  nonregular input should stop before backup, removal, and public Apply\n' >&2
		return 1
	fi

	setup_documented_opencode_fixture || return 1
	config_dir=$FIXTURE_HOME/.config/opencode
	escaped=$FIXTURE_ROOT/uncontained-opencode-config
	mv -- "$config_dir" "$escaped" || return 1
	ln -s "$escaped" "$config_dir" || return 1
	before=$(snapshot_opencode_managed_pair) || return 1
	run_documented_opencode_migration success 'MIGRATE\ny\n'
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  config parent resolving outside HOME should be rejected\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Expected an ordinary OpenCode config directory below HOME:' \
		'canonical HOME containment should reject a linked config parent' || return 1
	assert_eq "$before" "$(snapshot_opencode_managed_pair)" \
		'HOME containment rejection should preserve both inputs' || return 1

	setup_documented_opencode_fixture || return 1
	package_root=$FIXTURE_REPO/config/opencode
	escaped_package=$FIXTURE_ROOT/uncontained-opencode-package
	mv -- "$package_root" "$escaped_package" || return 1
	ln -s "$escaped_package" "$package_root" || return 1
	before=$(snapshot_opencode_managed_pair) || return 1
	run_documented_opencode_migration success 'MIGRATE\ny\n'
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  package root resolving outside the canonical package should be rejected\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Expected the canonical OpenCode package:' \
		'canonical package containment should reject a linked package root' || return 1
	assert_eq "$before" "$(snapshot_opencode_managed_pair)" \
		'package containment rejection should preserve both inputs'
}

test_documented_migration_recovers_after_apply_failures_decline_and_empty_selection() {
	exercise_incomplete_documented_opencode_migration \
		validator-failure 'MIGRATE\ny\n' 'Validator failed for opencode' || return 1
	exercise_incomplete_documented_opencode_migration \
		apply-failure 'MIGRATE\ny\n' 'controlled partial apply failure' || return 1
	exercise_incomplete_documented_opencode_migration \
		decline 'MIGRATE\nn\n' 'No changes made.' || return 1
	exercise_incomplete_documented_opencode_migration \
		empty 'MIGRATE\n' 'No Stow packages selected; no changes made.'
}

test_documented_migration_signal_trap_recovers_the_pair_after_interruption() {
	exercise_incomplete_documented_opencode_migration \
		signal 'MIGRATE\ny\n' 'controlled catchable migration interruption' 143
}

test_installed_opencode_validates_in_a_networkless_sandbox() {
	exercise_installed_opencode_validator
}

test_documented_migration_and_manual_recovery_blocks_are_executable() {
	new_fixture || return 1
	prepare_documented_opencode_scripts || return 1
	assert_contains "$(<"$OPENCODE_MIGRATION_SCRIPT")" \
		"trap 'exit 143' TERM" \
		'the extracted migration block should include its catchable interruption trap' || return 1
	assert_contains "$(<"$OPENCODE_MIGRATION_SCRIPT")" \
		'if ! verify_manifest "$backup_root"; then' \
		'the extracted migration block should include manifest verification' || return 1
	assert_contains "$(<"$OPENCODE_MANUAL_RECOVERY_EXTRACT")" \
		'backup_root=/absolute/path/from-the-migration-output' \
		'the extracted manual block should retain its documented human placeholder' || return 1
	assert_contains "$(<"$OPENCODE_MANUAL_RECOVERY_SCRIPT")" \
		'backup_root=${DOTFILES_TEST_BACKUP_ROOT:?}' \
		'the executable manual block should adapt only its human-supplied backup path'
}

test_documented_manual_recovery_validates_the_pair_and_rejects_collisions() {
	local canaries_before pair_before relative target manifest foreign_manifest variant member
	setup_documented_manual_recovery_fixture || return 1
	canaries_before=$(snapshot_opencode_migration_canaries) || return 1
	run_documented_manual_recovery
	assert_eq 0 "$COMMAND_STATUS" 'the documented manual block should restore a valid paired backup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Restored both managed targets as regular files from:' \
		'the documented manual block should report a complete restore' || return 1
	assert_documented_manual_recovery_complete || return 1
	assert_eq "$canaries_before" "$(snapshot_opencode_migration_canaries)" \
		'manual recovery should preserve generated and competing siblings' || return 1

	for variant in tampered malformed symlink; do
		setup_documented_manual_recovery_fixture || return 1
		manifest=$OPENCODE_DOCUMENT_BACKUP_ROOT/SHA256SUMS
		case $variant in
			tampered) printf '%s\n' 'tampered backup' >>"$OPENCODE_DOCUMENT_BACKUP_ROOT/$OPENCODE_TUI_RELATIVE" ;;
			malformed) printf '%s\n' 'unexpected third manifest entry' >>"$manifest" ;;
			symlink)
				foreign_manifest=$FIXTURE_ROOT/foreign-manifest
				mv -- "$manifest" "$foreign_manifest" || return 1
				ln -s "$foreign_manifest" "$manifest" || return 1
				;;
		esac
		pair_before=$(snapshot_opencode_managed_pair) || return 1
		run_documented_manual_recovery
		if [[ $COMMAND_STATUS -eq 0 ]]; then
			printf '  manual recovery accepted a %s manifest/backup fixture\n' "$variant" >&2
			return 1
		fi
		assert_contains "$COMMAND_OUTPUT" 'Required checksum manifest is missing, linked, malformed, or invalid:' \
			"manual recovery should diagnose the $variant manifest/backup fixture" || return 1
		assert_eq "$pair_before" "$(snapshot_opencode_managed_pair)" \
			"manual recovery should reject $variant backup state before removing either link" || return 1
	done

	for member in "$OPENCODE_MAIN_RELATIVE" "$OPENCODE_TUI_RELATIVE"; do
		setup_documented_manual_recovery_fixture || return 1
		target=$FIXTURE_HOME/$member
		rm -- "$target" || return 1
		cp --archive -- "$OPENCODE_DOCUMENT_BACKUP_ROOT/$member" "$target" || return 1
		run_documented_manual_recovery
		assert_eq 0 "$COMMAND_STATUS" \
			'manual recovery should accept either member when already restored from the pair' || return 1
		assert_contains "$COMMAND_OUTPUT" "Already restored from the paired backup: $target" \
			'manual recovery should identify the already-restored member' || return 1
		assert_documented_manual_recovery_complete || return 1
	done

	setup_documented_manual_recovery_fixture || return 1
	target=$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE
	rm -- "$target" || return 1
	printf '%s\n' 'foreign regular collision' >"$target" || return 1
	pair_before=$(snapshot_opencode_managed_pair) || return 1
	run_documented_manual_recovery
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  manual recovery replaced a foreign regular target\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT" 'Refusing to replace an unexpected path:' \
		'manual recovery should diagnose a regular target collision' || return 1
	assert_eq "$pair_before" "$(snapshot_opencode_managed_pair)" \
		'regular collision rejection should preserve both managed targets' || return 1

	setup_documented_manual_recovery_fixture || return 1
	target=$FIXTURE_HOME/$OPENCODE_TUI_RELATIVE
	rm -- "$target" || return 1
	ln -s "$OPENCODE_MIGRATION_HOSTILE/unrelated-target" "$target" || return 1
	pair_before=$(snapshot_opencode_managed_pair) || return 1
	run_documented_manual_recovery
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  manual recovery replaced a foreign symlink target\n' >&2
		return 1
	fi
	assert_eq "$pair_before" "$(snapshot_opencode_managed_pair)" \
		'foreign symlink rejection should preserve both managed targets' || return 1

	setup_documented_manual_recovery_fixture || return 1
	pair_before=$(snapshot_opencode_managed_pair) || return 1
	run_documented_manual_recovery dangling-temp
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  manual recovery ignored a dangling restore-temp collision\n' >&2
		return 1
	fi
	assert_eq "$pair_before" "$(snapshot_opencode_managed_pair)" \
		'dangling restore-temp collision should be detected before either managed link is removed' || return 1
	if ! compgen -G "$FIXTURE_HOME/.config/opencode/*.dotfiles-restore.*" >/dev/null; then
		printf '  dangling restore-temp collision fixture was not retained\n' >&2
		return 1
	fi
}

test_already_moved_clone_recovery_verifies_the_pair_before_relinking() {
	exercise_already_moved_opencode_clone
}

set -e
run_test test_opencode_package_matches_the_native_configuration_contract \
	'OpenCode package matches the native configuration contract'
run_test test_validator_launches_opencode_with_the_isolated_native_config_contract \
	'validator launches OpenCode with the isolated native config contract'
run_test test_validator_rejects_nonexact_objects_before_launching_opencode \
	'validator rejects nonexact objects before launching OpenCode'
run_test test_validator_cleans_up_and_preserves_only_diagnostics_on_native_failure \
	'validator cleans up and preserves only diagnostics on native failure'
run_test test_public_package_lifecycle_preserves_siblings_and_supports_relocation \
	'public package lifecycle preserves siblings and supports relocation'
run_test test_documented_migration_verifies_the_pair_before_normal_public_apply \
	'documented migration verifies the pair before normal public Apply'
run_test test_documented_migration_rejects_nonmatching_nonregular_and_uncontained_inputs \
	'documented migration rejects nonmatching, nonregular, and uncontained inputs'
run_test test_documented_migration_recovers_after_apply_failures_decline_and_empty_selection \
	'documented migration recovers after Apply failures, decline, and empty selection'
run_test test_documented_migration_signal_trap_recovers_the_pair_after_interruption \
	'documented migration signal trap recovers the pair after interruption'
run_test test_installed_opencode_validates_in_a_networkless_sandbox \
	'installed OpenCode validates in a networkless sandbox'
run_test test_documented_migration_and_manual_recovery_blocks_are_executable \
	'documented migration and manual recovery blocks are executable'
run_test test_documented_manual_recovery_validates_the_pair_and_rejects_collisions \
	'documented manual recovery validates the pair and rejects collisions'
run_test test_already_moved_clone_recovery_verifies_the_pair_before_relinking \
	'already-moved clone recovery verifies the pair before relinking'
finish_tests
