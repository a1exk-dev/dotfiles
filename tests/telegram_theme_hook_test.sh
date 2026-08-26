#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

setup_telegram_hook_fixture() {
	new_fixture
	TELEGRAM_HOOK_SOURCE="$FIXTURE_REPO/config/telegram-theme/.config/omarchy/hooks/theme-set.d/telegram-theme"
	TELEGRAM_ACTIVE_ROOT="$FIXTURE_STATE/omarchy/current"
	TELEGRAM_MANIFEST="$TELEGRAM_ACTIVE_ROOT/theme/telegram-omarchy-theme.json"
	TELEGRAM_OUTPUT="$FIXTURE_STATE/dotfiles/telegram-theme/current.tdesktop-theme"
	TELEGRAM_STATUS="$FIXTURE_STATE/dotfiles/telegram-theme/status.json"
	mkdir -p "$TELEGRAM_ACTIVE_ROOT/theme" "$FIXTURE_HOME/.local/libexec/dotfiles" \
		"$FIXTURE_HOME/.local/share/TelegramDesktop/tdata"
	ln -s "$FIXTURE_REPO/config/telegram-theme/.local/libexec/dotfiles/telegram-theme" \
		"$FIXTURE_HOME/.local/libexec/dotfiles/telegram-theme"
	printf 'private Telegram canary\n' >"$FIXTURE_HOME/.local/share/TelegramDesktop/tdata/canary"
	TELEGRAM_TDATA_BEFORE=$(sha256sum "$FIXTURE_HOME/.local/share/TelegramDesktop/tdata/canary")
	make_fake pacman 'printf "pacman %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
case "$*" in
  "-Q omarchy") printf "omarchy 4.0.1-1\n" ;;
  "-Q telegram-desktop") printf "telegram-desktop 7.0.9-4\n" ;;
  *) exit 64 ;;
esac'
	make_fake omarchy-notification-send 'printf "notification %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake notify-send 'printf "notification %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	make_fake telegram-desktop 'printf "TELEGRAM EXECUTED: %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
	make_fake Telegram 'printf "TELEGRAM EXECUTED: %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"; exit 99'
}

run_telegram_hook() {
	local slug=$1
	run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" bash "$TELEGRAM_HOOK_SOURCE" "$slug"
}

start_telegram_hook_background() {
	local slug=$1 output=$2
	env -i HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" XDG_STATE_HOME="$FIXTURE_STATE" \
		XDG_CACHE_HOME="$FIXTURE_CACHE" XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" TMPDIR="$FIXTURE_TMP" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_TEST_CALL_LOG="$CALL_LOG" \
		DOTFILES_TEST_REAL_NODE="$HOST_NODE_REAL" \
		bash "$TELEGRAM_HOOK_SOURCE" "$slug" >"$output" 2>&1 &
	TELEGRAM_HOOK_PID=$!
}

assert_telegram_boundary_untouched() {
	assert_eq "$TELEGRAM_TDATA_BEFORE" "$(sha256sum "$FIXTURE_HOME/.local/share/TelegramDesktop/tdata/canary")" \
		'hook must not read through or modify Telegram private state' || return 1
	if [[ $(<"$CALL_LOG") == *'TELEGRAM EXECUTED:'* ]]; then
		printf '  hook launched or controlled Telegram\n' >&2
		return 1
	fi
	if [[ $(<"$CALL_LOG") == *'theme refresh'* || $(<"$CALL_LOG") == *'restart'* ]]; then
		printf '  hook recursively refreshed Omarchy or restarted a process\n' >&2
		return 1
	fi
}

test_hook_publishes_active_manifest_to_stable_xdg_state() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"

	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'supported current event should publish successfully' || return 1
	[[ -f $TELEGRAM_OUTPUT ]] || {
		printf '  hook did not publish the stable archive below XDG state\n' >&2
		return 1
	}
	"$HOST_NODE_REAL" "$SOURCE_REPO/tests/support/telegram_theme_assertions.mjs" "$TELEGRAM_OUTPUT" "$TELEGRAM_MANIFEST" >/dev/null || return 1
	jq -e '.schema_version == 1 and .status == "ok" and .slug == "everforest"' "$TELEGRAM_STATUS" >/dev/null || {
		printf '  hook did not record successful structured status\n' >&2
		return 1
	}
	assert_telegram_boundary_untouched
}

test_hook_hands_neutral_manifest_slug_to_current_event_without_mutating_active_state() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml active "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	local manifest_before
	manifest_before=$(sha256sum "$TELEGRAM_MANIFEST")

	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'current event should replace the neutral template slug at the generator handoff' || return 1
	[[ -s $TELEGRAM_OUTPUT ]] || {
		printf '  neutral-slug handoff did not publish the stable archive\n' >&2
		return 1
	}
	"$HOST_NODE_REAL" "$SOURCE_REPO/tests/support/telegram_theme_assertions.mjs" \
		"$TELEGRAM_OUTPUT" "$TELEGRAM_MANIFEST" >/dev/null || return 1
	jq -e '.schema_version == 1 and .status == "ok" and .slug == "everforest"' "$TELEGRAM_STATUS" >/dev/null || {
		printf '  neutral-slug handoff did not record the real event slug\n' >&2
		return 1
	}
	assert_eq "$manifest_before" "$(sha256sum "$TELEGRAM_MANIFEST")" \
		'hook handoff must leave the Omarchy-owned active manifest unchanged' || return 1
	assert_eq active "$(jq -r '.slug' "$TELEGRAM_MANIFEST")" \
		'active manifest should retain the template neutral slug' || return 1
	assert_telegram_boundary_untouched
}

test_hook_skips_stale_events_and_duplicate_publication() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$TELEGRAM_MANIFEST" || return 1
	printf 'tokyo-night\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook solitude
	assert_eq 0 "$COMMAND_STATUS" 'stale event should be a successful no-op' || return 1
	if [[ -e $TELEGRAM_OUTPUT ]]; then
		printf '  stale event published an archive\n' >&2
		return 1
	fi

	run_telegram_hook tokyo-night
	assert_eq 0 "$COMMAND_STATUS" 'current event should publish' || return 1
	local before_hash before_mtime
	before_hash=$(sha256sum "$TELEGRAM_OUTPUT")
	before_mtime=$(stat -c '%y' "$TELEGRAM_OUTPUT")
	sleep 0.05
	run_telegram_hook tokyo-night
	assert_eq 0 "$COMMAND_STATUS" 'duplicate current event should succeed' || return 1
	assert_eq "$before_hash" "$(sha256sum "$TELEGRAM_OUTPUT")" 'duplicate hook event should preserve bytes' || return 1
	assert_eq "$before_mtime" "$(stat -c '%y' "$TELEGRAM_OUTPUT")" 'duplicate hook event should preserve mtime' || return 1
	assert_telegram_boundary_untouched
}

test_hook_fails_closed_on_exact_package_version_mismatch() {
	local mismatch
	for mismatch in omarchy telegram; do
		setup_telegram_hook_fixture
		make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
		printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
		run_telegram_hook everforest
		assert_eq 0 "$COMMAND_STATUS" 'supported baseline should publish before mismatch injection' || return 1
		local before
		before=$(sha256sum "$TELEGRAM_OUTPUT")
		make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$TELEGRAM_MANIFEST" || return 1
		printf 'tokyo-night\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
		if [[ $mismatch == omarchy ]]; then
			make_fake pacman 'case "$*" in "-Q omarchy") printf "omarchy 4.0.2-1\n" ;; "-Q telegram-desktop") printf "telegram-desktop 7.0.9-4\n" ;; *) exit 64 ;; esac'
		else
			make_fake pacman 'case "$*" in "-Q omarchy") printf "omarchy 4.0.1-1\n" ;; "-Q telegram-desktop") printf "telegram-desktop 7.0.10-1\n" ;; *) exit 64 ;; esac'
		fi
		run_telegram_hook tokyo-night
		if [[ $COMMAND_STATUS -eq 0 ]]; then
			printf '  %s version mismatch unexpectedly succeeded\n' "$mismatch" >&2
			return 1
		fi
		assert_eq "$before" "$(sha256sum "$TELEGRAM_OUTPUT")" "$mismatch mismatch should preserve last-good archive" || return 1
		jq -e '.schema_version == 1 and .status == "error"' "$TELEGRAM_STATUS" >/dev/null || {
			printf '  %s mismatch did not record failure status\n' "$mismatch" >&2
			return 1
		}
		assert_contains "$COMMAND_OUTPUT$(<"$TELEGRAM_STATUS")" '4.0.1-1' 'compatibility error should name exact supported Omarchy package' || return 1
		assert_contains "$COMMAND_OUTPUT$(<"$TELEGRAM_STATUS")" '7.0.9-4' 'compatibility error should name exact supported Telegram package' || return 1
		assert_telegram_boundary_untouched || return 1
	done
}

assert_hook_rejects_node_version_and_deduplicates_failure() {
	local scenario=$1 reported_version=$2 expected_diagnostic=$3
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" "$scenario Node.js fixture should seed a last-good publication" || return 1
	local before_hash before_mtime attempt fingerprint notification_count
	before_hash=$(sha256sum "$TELEGRAM_OUTPUT") || return 1
	before_mtime=$(stat -c '%y' "$TELEGRAM_OUTPUT") || return 1
	make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$TELEGRAM_MANIFEST" || return 1
	printf 'tokyo-night\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	make_fake node "if [[ \${1-} == --version ]]; then printf '%s\\n' '$reported_version'; exit 0; fi
printf 'unexpected generator execution: %s\\n' \"\$*\" >>\"\$DOTFILES_TEST_CALL_LOG\"
exec \"\$DOTFILES_TEST_REAL_NODE\" \"\$@\""
	: >"$CALL_LOG"

	for attempt in 1 2; do
		run_telegram_hook tokyo-night
		if [[ $COMMAND_STATUS -eq 0 ]]; then
			printf '  hook accepted %s Node.js on attempt %s\n' "$scenario" "$attempt" >&2
			return 1
		fi
		assert_eq "$before_hash" "$(sha256sum "$TELEGRAM_OUTPUT")" \
			"$scenario Node.js rejection should preserve last-good archive bytes" || return 1
		assert_eq "$before_mtime" "$(stat -c '%y' "$TELEGRAM_OUTPUT")" \
			"$scenario Node.js rejection should preserve last-good archive mtime" || return 1
		jq -e '.schema_version == 1 and .status == "error" and (.failure_fingerprint | type == "string" and length == 64)' \
			"$TELEGRAM_STATUS" >/dev/null || {
			printf '  %s Node.js rejection did not record a fingerprinted failure status\n' "$scenario" >&2
			return 1
		}
		assert_contains "$COMMAND_OUTPUT$(<"$TELEGRAM_STATUS")" '22.20.0' \
			"$scenario Node.js failure should name the minimum supported version" || return 1
		assert_contains "$COMMAND_OUTPUT$(<"$TELEGRAM_STATUS")" "$expected_diagnostic" \
			"$scenario Node.js failure should classify the rejected version" || return 1
		if [[ $attempt == 1 ]]; then
			fingerprint=$(jq -r '.failure_fingerprint' "$TELEGRAM_STATUS")
		else
			assert_eq "$fingerprint" "$(jq -r '.failure_fingerprint' "$TELEGRAM_STATUS")" \
				"repeated $scenario Node.js failure should retain its fingerprint" || return 1
		fi
	done
	if [[ $(<"$CALL_LOG") == *'unexpected generator execution:'* ]]; then
		printf '  %s Node.js rejection launched the generator\n' "$scenario" >&2
		return 1
	fi
	notification_count=$(awk '/^notification / { count++ } END { print count + 0 }' "$CALL_LOG")
	assert_eq 1 "$notification_count" "repeated $scenario Node.js failure should notify once" || return 1
	assert_telegram_boundary_untouched
}

test_hook_rejects_old_node_and_deduplicates_failure() {
	assert_hook_rejects_node_version_and_deduplicates_failure old v22.19.0 'Node.js 22.19.0 is below required version'
}

test_hook_rejects_malformed_node_and_deduplicates_failure() {
	assert_hook_rejects_node_version_and_deduplicates_failure malformed not-a-node-version 'Node.js version is unavailable or malformed'
}

test_hook_preserves_last_good_and_deduplicates_failure_notifications() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'last-good hook fixture should publish' || return 1
	local before notification_count
	before=$(sha256sum "$TELEGRAM_OUTPUT")
	jq 'del(.colors.foreground)' "$TELEGRAM_MANIFEST" >"$TELEGRAM_MANIFEST.invalid"
	mv "$TELEGRAM_MANIFEST.invalid" "$TELEGRAM_MANIFEST"

	run_telegram_hook everforest
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  invalid manifest hook event unexpectedly succeeded\n' >&2
		return 1
	fi
	run_telegram_hook everforest
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  repeated invalid manifest hook event unexpectedly succeeded\n' >&2
		return 1
	fi
	notification_count=$(awk '/^notification / { count++ } END { print count + 0 }' "$CALL_LOG")
	assert_eq 1 "$notification_count" 'identical failures should emit one notification' || return 1
	assert_eq "$before" "$(sha256sum "$TELEGRAM_OUTPUT")" 'repeated failures should preserve last-good output' || return 1

	jq '.colors.foreground = "not-a-color"' "$TELEGRAM_MANIFEST" >"$TELEGRAM_MANIFEST.changed"
	mv "$TELEGRAM_MANIFEST.changed" "$TELEGRAM_MANIFEST"
	run_telegram_hook everforest
	notification_count=$(awk '/^notification / { count++ } END { print count + 0 }' "$CALL_LOG")
	assert_eq 2 "$notification_count" 'changed failure fingerprint should emit a new notification' || return 1
	assert_eq "$before" "$(sha256sum "$TELEGRAM_OUTPUT")" 'changed failure should preserve last-good output' || return 1
	assert_telegram_boundary_untouched
}

install_archive_publication_failure_helper() {
	local helper_root="$FIXTURE_HOME/.local/libexec/dotfiles/telegram-theme"
	rm "$helper_root"
	mkdir -p "$helper_root"
	cat >"$helper_root/generate.mjs" <<'EOF'
#!/usr/bin/env node
import { linkSync, renameSync, writeFileSync } from 'node:fs';
const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
	if (value.startsWith('--')) pairs.push([value, all[index + 1]]);
	return pairs;
}, []));
const backup = `${args['--status']}.last-good`;
const success = `${args['--status']}.success`;
linkSync(args['--status'], backup);
writeFileSync(success, JSON.stringify({
	schema_version: 1,
	status: 'ok',
	slug: 'everforest',
	archive_sha256: 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
}) + '\n');
renameSync(success, args['--status']);
renameSync(backup, args['--status']);
process.stderr.write('Current archive publication failed after exact status rollback.\n');
process.exitCode = 73;
EOF
	chmod +x "$helper_root/generate.mjs"
}

install_status_digest_probe_helper() {
	local mode=$1 helper_root="$FIXTURE_HOME/.local/libexec/dotfiles/telegram-theme"
	rm "$helper_root"
	mkdir -p "$helper_root"
	cat >"$helper_root/generate.mjs" <<EOF
#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
	if (value.startsWith('--')) pairs.push([value, all[index + 1]]);
	return pairs;
}, []));
const digest = '$mode' === 'valid'
	? createHash('sha256').update(readFileSync(args['--output'])).digest('hex')
	: 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
writeFileSync(args['--status'], JSON.stringify({
	schema_version: 1,
	status: 'ok',
	slug: 'everforest',
	changed: true,
	archive_sha256: digest,
}) + '\n');
EOF
	chmod +x "$helper_root/generate.mjs"
}

test_hook_replaces_restored_prior_error_with_current_publication_failure() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'restored-status fixture should seed a stable archive' || return 1
	local before_archive prior_fingerprint first_fingerprint expected_fingerprint canonical attempt notification_count
	before_archive="$(stat -c '%d:%i:%f:%s:%y' "$TELEGRAM_OUTPUT")|$(sha256sum "$TELEGRAM_OUTPUT")"
	prior_fingerprint=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
	jq -n --arg fingerprint "$prior_fingerprint" \
		'{schema_version:1,status:"error",slug:"everforest",stage:"generator",message:"Stale prior diagnostic.",failure_fingerprint:$fingerprint}' \
		>"$TELEGRAM_STATUS"
	install_archive_publication_failure_helper
	: >"$CALL_LOG"

	for attempt in 1 2; do
		run_telegram_hook everforest
		assert_eq 73 "$COMMAND_STATUS" "archive publication failure attempt $attempt should retain generator status" || return 1
		assert_eq "$before_archive" "$(stat -c '%d:%i:%f:%s:%y' "$TELEGRAM_OUTPUT")|$(sha256sum "$TELEGRAM_OUTPUT")" \
			'archive publication failure should preserve prior archive identity, metadata, and bytes' || return 1
		jq -e '.schema_version == 1 and .status == "error" and .stage == "generator" and
			(.message | contains("Current archive publication failed after exact status rollback.")) and
			(.failure_fingerprint | type == "string" and length == 64)' "$TELEGRAM_STATUS" >/dev/null || {
			printf '  hook retained a stale prior diagnostic instead of recording the current archive publication failure\n' >&2
			return 1
		}
		if [[ $(<"$TELEGRAM_STATUS") == *'Stale prior diagnostic.'* ]]; then
			printf '  current generator failure status still contains the stale prior diagnostic\n' >&2
			return 1
		fi
		canonical=$(jq -cS --arg slug everforest \
			'.slug = $slug | del(.failure_fingerprint, .created_at, .generated_at, .timestamp, .updated_at)' \
			"$TELEGRAM_STATUS") || return 1
		read -r expected_fingerprint _ < <(printf '%s' "$canonical" | sha256sum) || return 1
		assert_eq "$expected_fingerprint" "$(jq -r '.failure_fingerprint' "$TELEGRAM_STATUS")" \
			'archive publication failure should fingerprint the current diagnostic' || return 1
		if [[ $attempt == 1 ]]; then
			first_fingerprint=$expected_fingerprint
			[[ $first_fingerprint != "$prior_fingerprint" ]] || {
				printf '  current archive publication failure retained the stale prior fingerprint\n' >&2
				return 1
			}
		else
			assert_eq "$first_fingerprint" "$expected_fingerprint" \
				'repeated current archive publication failure should retain its fingerprint' || return 1
		fi
	done
	notification_count=$(awk '/^notification / { count++ } END { print count + 0 }' "$CALL_LOG")
	assert_eq 1 "$notification_count" 'repeated current archive publication failure should notify once' || return 1
	assert_telegram_boundary_untouched
}

test_hook_rejects_success_status_digest_mismatch() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'digest mismatch fixture should seed a stable archive' || return 1
	local before_archive notification_count
	before_archive="$(stat -c '%d:%i:%f:%s:%y' "$TELEGRAM_OUTPUT")|$(sha256sum "$TELEGRAM_OUTPUT")"
	install_status_digest_probe_helper mismatch
	: >"$CALL_LOG"

	run_telegram_hook everforest
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  hook accepted success status whose archive digest did not match stable output\n' >&2
		return 1
	fi
	assert_eq "$before_archive" "$(stat -c '%d:%i:%f:%s:%y' "$TELEGRAM_OUTPUT")|$(sha256sum "$TELEGRAM_OUTPUT")" \
		'digest mismatch verification should preserve stable archive identity, metadata, and bytes' || return 1
	jq -e '.schema_version == 1 and .status == "error" and .stage == "verification" and
		(.failure_fingerprint | type == "string" and length == 64)' "$TELEGRAM_STATUS" >/dev/null || {
		printf '  archive digest mismatch did not record a fingerprinted verification failure\n' >&2
		return 1
	}
	notification_count=$(awk '/^notification / { count++ } END { print count + 0 }' "$CALL_LOG")
	assert_eq 1 "$notification_count" 'archive digest mismatch should notify once' || return 1
	assert_telegram_boundary_untouched
}

test_hook_accepts_success_status_with_valid_archive_digest() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'valid digest fixture should seed a stable archive' || return 1
	local before_archive digest
	before_archive="$(stat -c '%d:%i:%f:%s:%y' "$TELEGRAM_OUTPUT")|$(sha256sum "$TELEGRAM_OUTPUT")"
	digest=$(sha256sum "$TELEGRAM_OUTPUT" | cut -d' ' -f1)
	install_status_digest_probe_helper valid
	: >"$CALL_LOG"

	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'hook should accept success status with matching stable archive digest' || return 1
	assert_eq "$before_archive" "$(stat -c '%d:%i:%f:%s:%y' "$TELEGRAM_OUTPUT")|$(sha256sum "$TELEGRAM_OUTPUT")" \
		'valid digest verification should leave stable archive unchanged' || return 1
	jq -e --arg digest "$digest" \
		'.schema_version == 1 and .status == "ok" and .slug == "everforest" and .archive_sha256 == $digest' \
		"$TELEGRAM_STATUS" >/dev/null || {
		printf '  valid digest fixture did not retain matching successful status\n' >&2
		return 1
	}
	assert_eq 0 "$(awk '/^notification / { count++ } END { print count + 0 }' "$CALL_LOG")" \
		'valid archive digest should not notify' || return 1
	assert_telegram_boundary_untouched
}

install_concurrency_probe_helper() {
	local helper_root="$FIXTURE_HOME/.local/libexec/dotfiles/telegram-theme"
	rm "$helper_root"
	mkdir -p "$helper_root"
	cat >"$helper_root/generate.mjs" <<EOF
#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
	if (value.startsWith('--')) pairs.push([value, all[index + 1]]);
	return pairs;
}, []));
try {
	mkdirSync('$FIXTURE_ROOT/helper-busy');
} catch {
	writeFileSync('$FIXTURE_ROOT/helper-overlap', 'overlap\n', { flag: 'a' });
}
writeFileSync('$FIXTURE_ROOT/helper-calls', 'call\n', { flag: 'a' });
await new Promise((resolve) => setTimeout(resolve, 150));
copyFileSync('$FIXTURE_ROOT/seed.tdesktop-theme', args['--output']);
const archiveSha256 = createHash('sha256').update(readFileSync(args['--output'])).digest('hex');
writeFileSync(args['--status'], JSON.stringify({
	schema_version: 1,
	status: 'ok',
	slug: 'everforest',
	archive_sha256: archiveSha256,
}) + '\n');
rmSync('$FIXTURE_ROOT/helper-busy', { recursive: true, force: true });
EOF
	chmod +x "$helper_root/generate.mjs"
}

run_two_hooks_concurrently() {
	local first_status=0 second_status=0
	env -i HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" XDG_STATE_HOME="$FIXTURE_STATE" \
		XDG_CACHE_HOME="$FIXTURE_CACHE" XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" TMPDIR="$FIXTURE_TMP" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_TEST_CALL_LOG="$CALL_LOG" \
		DOTFILES_TEST_REAL_NODE="$HOST_NODE_REAL" \
		bash "$TELEGRAM_HOOK_SOURCE" everforest >"$FIXTURE_ROOT/first-hook-output" 2>&1 &
	local first=$!
	sleep 0.02
	env -i HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" XDG_STATE_HOME="$FIXTURE_STATE" \
		XDG_CACHE_HOME="$FIXTURE_CACHE" XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" TMPDIR="$FIXTURE_TMP" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_TEST_CALL_LOG="$CALL_LOG" \
		DOTFILES_TEST_REAL_NODE="$HOST_NODE_REAL" \
		bash "$TELEGRAM_HOOK_SOURCE" everforest >"$FIXTURE_ROOT/second-hook-output" 2>&1 &
	local second=$!
	wait "$first" || first_status=$?
	wait "$second" || second_status=$?
	assert_eq 0 "$first_status" 'first concurrent hook should succeed' || return 1
	assert_eq 0 "$second_status" 'second concurrent hook should succeed'
}

test_hook_serializes_concurrent_events_with_runtime_lock() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'concurrency seed archive should publish' || return 1
	cp "$TELEGRAM_OUTPUT" "$FIXTURE_ROOT/seed.tdesktop-theme"
	install_concurrency_probe_helper
	rm -f "$FIXTURE_ROOT/helper-calls" "$FIXTURE_ROOT/helper-overlap"
	run_two_hooks_concurrently || return 1
	assert_eq 2 "$(awk 'END { print NR + 0 }' "$FIXTURE_ROOT/helper-calls")" 'both current events should reach the helper' || return 1
	if [[ -e $FIXTURE_ROOT/helper-overlap ]]; then
		printf '  concurrent helpers overlapped instead of using the XDG runtime lock\n' >&2
		return 1
	fi
	if [[ ! -d $FIXTURE_RUNTIME ]]; then
		printf '  runtime lock operation did not use the isolated XDG runtime root\n' >&2
		return 1
	fi
	assert_telegram_boundary_untouched
}

test_hook_discards_generation_when_active_theme_changes_during_packaging() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'stale-race fixture should publish a last-good archive and status' || return 1
	local before_hashes before_mtimes
	before_hashes=$(sha256sum "$TELEGRAM_OUTPUT" "$TELEGRAM_STATUS") || return 1
	before_mtimes=$(stat -c '%n|%y' "$TELEGRAM_OUTPUT" "$TELEGRAM_STATUS") || return 1

	make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$TELEGRAM_MANIFEST" || return 1
	printf 'tokyo-night\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	make_fake zip 'marker="${DOTFILES_TEST_CALL_LOG%/*}/slow-zip-started"
release="${DOTFILES_TEST_CALL_LOG%/*}/slow-zip-release"
: >"$marker"
while [[ ! -e $release ]]; do sleep 0.01; done
exec /usr/bin/zip "$@"'

	local hook_output=$FIXTURE_ROOT/stale-race-hook-output hook_pid hook_status=0 attempt
	env -i HOME="$FIXTURE_HOME" XDG_CONFIG_HOME="$FIXTURE_CONFIG" XDG_STATE_HOME="$FIXTURE_STATE" \
		XDG_CACHE_HOME="$FIXTURE_CACHE" XDG_RUNTIME_DIR="$FIXTURE_RUNTIME" TMPDIR="$FIXTURE_TMP" \
		PATH="$FIXTURE_BIN:/usr/bin:/bin" DOTFILES_TEST_CALL_LOG="$CALL_LOG" \
		DOTFILES_TEST_REAL_NODE="$HOST_NODE_REAL" \
		bash "$TELEGRAM_HOOK_SOURCE" tokyo-night >"$hook_output" 2>&1 &
	hook_pid=$!
	for ((attempt = 0; attempt < 500; attempt += 1)); do
		[[ -e $FIXTURE_ROOT/slow-zip-started ]] && break
		sleep 0.01
	done
	if [[ ! -e $FIXTURE_ROOT/slow-zip-started ]]; then
		touch "$FIXTURE_ROOT/slow-zip-release"
		wait "$hook_pid" || true
		printf '  stale-race hook did not reach the controlled packaging seam: %s\n' "$(<"$hook_output")" >&2
		return 1
	fi
	printf 'solitude\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	touch "$FIXTURE_ROOT/slow-zip-release"
	wait "$hook_pid" || hook_status=$?

	assert_eq 0 "$hook_status" 'a theme that becomes stale during generation should be a successful no-op' || return 1
	assert_eq "$before_hashes" "$(sha256sum "$TELEGRAM_OUTPUT" "$TELEGRAM_STATUS")" \
		'stale in-flight generation should preserve stable archive and status bytes' || return 1
	assert_eq "$before_mtimes" "$(stat -c '%n|%y' "$TELEGRAM_OUTPUT" "$TELEGRAM_STATUS")" \
		'stale in-flight generation should preserve stable archive and status mtimes' || return 1
	assert_telegram_boundary_untouched
}

test_hook_holds_shared_omarchy_lock_through_final_publication() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'shared-lock fixture should seed a stable publication' || return 1
	make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$TELEGRAM_MANIFEST" || return 1
	printf 'tokyo-night\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	make_fake zip 'marker="${DOTFILES_TEST_CALL_LOG%/*}/shared-lock-zip-started"
release="${DOTFILES_TEST_CALL_LOG%/*}/shared-lock-zip-release"
: >"$marker"
while [[ ! -e $release ]]; do sleep 0.01; done
exec /usr/bin/zip "$@"'
	local hook_output=$FIXTURE_ROOT/shared-lock-hook-output hook_status=0 promoter_status=0 attempt
	start_telegram_hook_background tokyo-night "$hook_output"
	local hook_pid=$TELEGRAM_HOOK_PID
	for ((attempt = 0; attempt < 500; attempt += 1)); do
		[[ -e $FIXTURE_ROOT/shared-lock-zip-started ]] && break
		sleep 0.01
	done
	if [[ ! -e $FIXTURE_ROOT/shared-lock-zip-started ]]; then
		touch "$FIXTURE_ROOT/shared-lock-zip-release"
		wait "$hook_pid" || true
		printf '  shared-lock hook did not reach final packaging: %s\n' "$(<"$hook_output")" >&2
		return 1
	fi
	local lock_probe=blocked
	if (
		exec 8>"$FIXTURE_RUNTIME/omarchy-theme-set.lock"
		flock --exclusive --nonblock 8
	); then
		lock_probe=acquired
	fi
	assert_eq blocked "$lock_probe" \
		'final publication should already hold the Omarchy lock against an exclusive promoter' || {
		touch "$FIXTURE_ROOT/shared-lock-zip-release"
		wait "$hook_pid" || true
		return 1
	}
	(
		: >"$FIXTURE_ROOT/promoter-attempting"
		exec 9>"$FIXTURE_RUNTIME/omarchy-theme-set.lock"
		flock --exclusive 9
		: >"$FIXTURE_ROOT/promoter-acquired"
		printf 'solitude\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	) &
	local promoter_pid=$!
	for ((attempt = 0; attempt < 200; attempt += 1)); do
		[[ -e $FIXTURE_ROOT/promoter-attempting ]] && break
		sleep 0.01
	done
	touch "$FIXTURE_ROOT/shared-lock-zip-release"
	wait "$hook_pid" || hook_status=$?
	wait "$promoter_pid" || promoter_status=$?
	assert_eq 0 "$hook_status" "shared-lock hook should complete without deadlock: $(<"$hook_output")" || return 1
	assert_eq 0 "$promoter_status" 'queued Omarchy promoter should complete after hook publication' || return 1
	[[ -e $FIXTURE_ROOT/promoter-acquired ]] || {
		printf '  queued Omarchy promoter never acquired the shared lock file\n' >&2
		return 1
	}
	assert_eq solitude "$(<"$TELEGRAM_ACTIVE_ROOT/theme.name")" 'queued promoter should update the active slug after publication' || return 1
	jq -e '.schema_version == 1 and .status == "ok" and .slug == "tokyo-night"' "$TELEGRAM_STATUS" >/dev/null || {
		printf '  protected final publication did not commit the pre-promoter theme\n' >&2
		return 1
	}
	assert_telegram_boundary_untouched
}

test_hook_waits_for_omarchy_promoter_then_skips_stale_event() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	run_telegram_hook everforest
	assert_eq 0 "$COMMAND_STATUS" 'promoter-first fixture should seed a stable publication' || return 1
	local before_hashes before_mtimes
	before_hashes=$(sha256sum "$TELEGRAM_OUTPUT" "$TELEGRAM_STATUS") || return 1
	before_mtimes=$(stat -c '%n|%y' "$TELEGRAM_OUTPUT" "$TELEGRAM_STATUS") || return 1
	make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$TELEGRAM_MANIFEST" || return 1
	printf 'tokyo-night\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	make_fake zip 'marker="${DOTFILES_TEST_CALL_LOG%/*}/promoter-first-zip-started"
release="${DOTFILES_TEST_CALL_LOG%/*}/promoter-first-zip-release"
: >"$marker"
while [[ ! -e $release ]]; do sleep 0.01; done
exec /usr/bin/zip "$@"'
	local omarchy_lock_fd
	exec {omarchy_lock_fd}>"$FIXTURE_RUNTIME/omarchy-theme-set.lock"
	flock --exclusive "$omarchy_lock_fd"
	local hook_output=$FIXTURE_ROOT/promoter-first-hook-output hook_status=0
	start_telegram_hook_background tokyo-night "$hook_output"
	local hook_pid=$TELEGRAM_HOOK_PID
	sleep 0.1
	local reached_packaging_while_locked=false
	[[ ! -e $FIXTURE_ROOT/promoter-first-zip-started ]] || reached_packaging_while_locked=true
	printf 'solitude\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	flock --unlock "$omarchy_lock_fd"
	exec {omarchy_lock_fd}>&-
	touch "$FIXTURE_ROOT/promoter-first-zip-release"
	wait "$hook_pid" || hook_status=$?
	assert_eq false "$reached_packaging_while_locked" \
		'hook should not enter generation while an Omarchy promoter owns the shared lock' || return 1
	assert_eq 0 "$hook_status" "event made stale by the lock owner should complete without deadlock: $(<"$hook_output")" || return 1
	assert_eq "$before_hashes" "$(sha256sum "$TELEGRAM_OUTPUT" "$TELEGRAM_STATUS")" \
		'promoter-first stale no-op should preserve archive and status bytes' || return 1
	assert_eq "$before_mtimes" "$(stat -c '%n|%y' "$TELEGRAM_OUTPUT" "$TELEGRAM_STATUS")" \
		'promoter-first stale no-op should preserve archive and status mtimes' || return 1
	assert_telegram_boundary_untouched
}

test_hook_final_verification_rejects_output_symlink() {
	setup_telegram_hook_fixture
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$TELEGRAM_MANIFEST" || return 1
	printf 'everforest\n' >"$TELEGRAM_ACTIVE_ROOT/theme.name"
	local helper_root="$FIXTURE_HOME/.local/libexec/dotfiles/telegram-theme"
	rm "$helper_root"
	mkdir -p "$helper_root"
	cat >"$helper_root/generate.mjs" <<EOF
#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { rmSync, symlinkSync, writeFileSync } from 'node:fs';
const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
	if (value.startsWith('--')) pairs.push([value, all[index + 1]]);
	return pairs;
}, []));
const referent = '$FIXTURE_ROOT/symlink-output-referent';
const bytes = Buffer.from('symlink output referent\\n');
writeFileSync(referent, bytes);
rmSync(args['--output'], { force: true });
symlinkSync(referent, args['--output']);
writeFileSync(args['--status'], JSON.stringify({
	schema_version: 1,
	status: 'ok',
	slug: 'everforest',
	archive_sha256: createHash('sha256').update(bytes).digest('hex'),
}) + '\\n');
EOF
	chmod +x "$helper_root/generate.mjs"

	run_telegram_hook everforest
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  hook final verification accepted a symlink at the stable output path\n' >&2
		return 1
	fi
	if [[ ! -L $TELEGRAM_OUTPUT ]]; then
		printf '  symlink verification fixture did not retain its controlled output symlink\n' >&2
		return 1
	fi
	assert_eq 'symlink output referent' "$(<"$FIXTURE_ROOT/symlink-output-referent")" \
		'hook verification should not mutate the output symlink referent' || return 1
	jq -e '.schema_version == 1 and .status == "error" and .stage == "verification"' "$TELEGRAM_STATUS" >/dev/null || {
		printf '  output symlink rejection did not record a verification failure\n' >&2
		return 1
	}
	assert_telegram_boundary_untouched
}

set -e
run_test test_hook_publishes_active_manifest_to_stable_xdg_state 'hook publishes the active manifest to stable XDG state'
run_test test_hook_hands_neutral_manifest_slug_to_current_event_without_mutating_active_state 'hook hands the neutral manifest slug to the current event without mutating active state'
run_test test_hook_skips_stale_events_and_duplicate_publication 'hook skips stale and duplicate publication events'
run_test test_hook_fails_closed_on_exact_package_version_mismatch 'hook fails closed on exact package version mismatch'
run_test test_hook_rejects_old_node_and_deduplicates_failure 'hook rejects old Node.js and deduplicates failure'
run_test test_hook_rejects_malformed_node_and_deduplicates_failure 'hook rejects malformed Node.js and deduplicates failure'
run_test test_hook_preserves_last_good_and_deduplicates_failure_notifications 'hook preserves last-good output and deduplicates failure notifications'
run_test test_hook_replaces_restored_prior_error_with_current_publication_failure 'hook replaces restored prior error with current publication failure'
run_test test_hook_rejects_success_status_digest_mismatch 'hook rejects success status digest mismatch'
run_test test_hook_accepts_success_status_with_valid_archive_digest 'hook accepts success status with valid archive digest'
run_test test_hook_serializes_concurrent_events_with_runtime_lock 'hook serializes concurrent events with an XDG runtime lock'
run_test test_hook_discards_generation_when_active_theme_changes_during_packaging 'hook discards generation when active theme changes during packaging'
run_test test_hook_holds_shared_omarchy_lock_through_final_publication 'hook holds shared Omarchy lock through final publication'
run_test test_hook_waits_for_omarchy_promoter_then_skips_stale_event 'hook waits for Omarchy promoter then skips stale event'
run_test test_hook_final_verification_rejects_output_symlink 'hook final verification rejects output symlink'
finish_tests
