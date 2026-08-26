#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly TELEGRAM_ASSERTIONS="$SOURCE_REPO/tests/support/telegram_theme_assertions.mjs"

# Provenance: independently extracted on 2026-08-26 from the human-approved v2
# prototype archives documented under .scratch/telegram-omarchy-theming. Each
# digest hashes all 586 ordered, lowercased `role:#hex\n` assignments, excluding
# comments and titles. The source prototype digests are:
#   solitude    631c80e3d6e0305e97e78bebe38c17fd5a6d3bf9bf55f2cd8087a2fcb2708933
#   tokyo-night db26aec309e85930cb0ccef1489fef9e4a4ad0ab1b14e420037154be0962a65e
#   everforest  7a5419383daf1a38412c1c67584ec48ac103288a8bf59740345587c82fabaf65
# Issue 07's later approved surface contract changes only Solitude msgInBg from
# #0c0e10 to the proven #101315 source fallback. Applying that one declared
# delta produces the complete deployable Solitude digest below. Runtime tests
# therefore need no ignored .scratch artifact.
declare -Ar TELEGRAM_APPROVED_ROLE_VALUE_SHA256=(
	[solitude]=394040e7987178d900a63c9c76b7e92fdef9da0d4212de9b56d2bc6f54683260
	[tokyo-night]=db26aec309e85930cb0ccef1489fef9e4a4ad0ab1b14e420037154be0962a65e
	[everforest]=7a5419383daf1a38412c1c67584ec48ac103288a8bf59740345587c82fabaf65
)

telegram_generator() {
	printf '%s\n' "$FIXTURE_REPO/config/telegram-theme/.local/libexec/dotfiles/telegram-theme/generate.mjs"
}

run_telegram_generator() {
	local manifest=$1 output=$2 status=$3 command_path=${4-/usr/bin:/bin}
	set +e
	COMMAND_OUTPUT=$(env -i HOME="$FIXTURE_HOME" PATH="$command_path" TMPDIR="$FIXTURE_TMP" \
		"$HOST_NODE_REAL" "$(telegram_generator)" --manifest "$manifest" --output "$output" --status "$status" 2>&1)
	COMMAND_STATUS=$?
	set -e
}

run_guarded_generator_with_readonly_directory() {
	local manifest=$1 output=$2 status=$3 failure_dir=$4
	local slug guard=$FIXTURE_ROOT/publication-guard generator_log=$FIXTURE_ROOT/guarded-generator.log
	local generator_pid guard_fd probe=$failure_dir/write-probe
	slug=$(jq -r '.slug' "$manifest") || return 1
	/usr/bin/mkfifo "$guard" || return 1
	env -i HOME="$FIXTURE_HOME" PATH=/usr/bin:/bin TMPDIR="$FIXTURE_TMP" \
		"$HOST_NODE_REAL" "$(telegram_generator)" --manifest "$manifest" --output "$output" \
		--status "$status" --guard "$slug:$guard" >"$generator_log" 2>&1 &
	generator_pid=$!
	# Opening the writer returns only after generation reaches the post-snapshot guard read.
	exec {guard_fd}>"$guard"
	chmod 0500 "$failure_dir"
	if touch "$probe" 2>/dev/null; then
		rm -f "$probe"
		printf '%s\n' "$slug" >&"$guard_fd"
		exec {guard_fd}>&-
		wait "$generator_pid" || true
		chmod 0700 "$failure_dir"
		printf '  could not make guarded publication directory read-only\n' >&2
		return 1
	fi
	printf '%s\n' "$slug" >&"$guard_fd"
	exec {guard_fd}>&-
	set +e
	wait "$generator_pid"
	COMMAND_STATUS=$?
	set -e
	chmod 0700 "$failure_dir"
	COMMAND_OUTPUT=$(<"$generator_log")
}

assert_valid_telegram_archive() {
	local archive=$1 manifest=$2 summary
	if ! summary=$("$HOST_NODE_REAL" "$TELEGRAM_ASSERTIONS" "$archive" "$manifest" 2>&1); then
		printf '  generated archive validation failed: %s\n' "$summary" >&2
		return 1
	fi
	assert_eq 586 "$(jq -r '.roles' <<<"$summary")" 'archive should contain all pinned Telegram roles' || return 1
	assert_eq 50 "$(jq -r '.contrast_pairs' <<<"$summary")" 'archive should validate every declared contrast pair' || return 1
	assert_eq 7 "$(jq -r '.distinct_state_comparisons' <<<"$summary")" \
		'archive should preserve every declared Telegram section and state distinction' || return 1
	if ! jq -e '.minimum_contrast >= 4.5 and .primary_distance >= 0.025' <<<"$summary" >/dev/null; then
		printf '  generated archive did not satisfy contrast and primary-surface thresholds: %s\n' "$summary" >&2
		return 1
	fi
}

make_collapsed_dialog_state_archive() {
	local source=$1 output=$2 state=$3 work=$FIXTURE_ROOT/collapsed-$state
	rm -rf "$work"
	mkdir "$work"
	unzip -q "$source" -d "$work" || return 1
	"$HOST_NODE_REAL" - "$work/colors.tdesktop-theme" "$state" <<'NODE'
const { readFileSync, writeFileSync } = require('node:fs');

const [palettePath, state] = process.argv.slice(2);
const roles = state === 'read'
	? [
		'dialogsBg', 'dialogsNameFg', 'dialogsChatIconFg', 'dialogsDateFg',
		'dialogsTextFg', 'dialogsTextFgService', 'dialogsVerifiedIconBg',
		'dialogsVerifiedIconFg', 'dialogsSendingIconFg', 'dialogsSentIconFg',
	]
	: ['dialogsUnreadBg', 'dialogsUnreadBgMuted', 'dialogsUnreadFg'];
let palette = readFileSync(palettePath, 'utf8');
const assignments = new Map();
for (const line of palette.split(/\r?\n/)) {
	const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(#[0-9a-f]{6}(?:[0-9a-f]{2})?);$/);
	if (match) assignments.set(match[1], match[2]);
}
for (const normal of roles) {
	const over = `${normal}Over`;
	const value = assignments.get(normal);
	if (!value || !assignments.has(over)) throw new Error(`missing dialog fixture role: ${normal}/${over}`);
	palette = palette.replace(
		new RegExp(`^${over}:\\s*#[0-9a-f]{6}(?:[0-9a-f]{2})?;$`, 'm'),
		`${over}: ${value};`,
	);
}
writeFileSync(palettePath, palette);
NODE
	chmod 0644 "$work/colors.tdesktop-theme" "$work/background.png"
	TZ=UTC touch -d '2000-01-01 00:00:00 UTC' "$work/colors.tdesktop-theme" "$work/background.png"
	(
		cd "$work" || exit 1
		TZ=UTC zip -X -q -9 "$output" colors.tdesktop-theme background.png
	)
}

test_generator_cli_produces_deterministic_valid_archive() {
	new_fixture
	local manifest=$FIXTURE_ROOT/solitude.json first=$FIXTURE_ROOT/first.tdesktop-theme
	local second=$FIXTURE_ROOT/second.tdesktop-theme status=$FIXTURE_ROOT/status.json
	make_telegram_theme_manifest /usr/share/omarchy/themes/solitude/colors.toml solitude "$manifest" || return 1

	run_telegram_generator "$manifest" "$first" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'valid rendered manifest should generate an archive' || return 1
	assert_valid_telegram_archive "$first" "$manifest" || return 1
	jq -e '.schema_version == 1 and .status == "ok"' "$status" >/dev/null || {
		printf '  generator success status is not schema-versioned and successful\n' >&2
		return 1
	}

	run_telegram_generator "$manifest" "$second" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'an independent rebuild should succeed' || return 1
	assert_eq "$(sha256sum "$first" | cut -d' ' -f1)" "$(sha256sum "$second" | cut -d' ' -f1)" \
		'independent builds should be byte deterministic'
}

test_generator_accepts_every_stock_light_and_dark_palette() {
	new_fixture
	local directory slug manifest archive status count=0 light=0 dark=0 mode
	for directory in /usr/share/omarchy/themes/*; do
		slug=${directory##*/}
		manifest="$FIXTURE_ROOT/$slug.json"
		archive="$FIXTURE_ROOT/$slug.tdesktop-theme"
		status="$FIXTURE_ROOT/$slug.status.json"
		make_telegram_theme_manifest "$directory/colors.toml" "$slug" "$manifest" || return 1
		mode=$(jq -r '.mode' "$manifest")
		[[ $mode == light ]] && light=$((light + 1)) || dark=$((dark + 1))
		run_telegram_generator "$manifest" "$archive" "$status"
		if [[ $COMMAND_STATUS -ne 0 ]]; then
			printf '  stock theme failed generation: %s\n  output: %s\n' "$slug" "$COMMAND_OUTPUT" >&2
			return 1
		fi
		assert_valid_telegram_archive "$archive" "$manifest" || return 1
		count=$((count + 1))
	done
	assert_eq 22 "$count" 'the exact Omarchy 4.0.1 stock theme set should be covered' || return 1
	if ((light == 0 || dark == 0)); then
		printf '  stock coverage must include both light and dark themes\n' >&2
		return 1
	fi
}

test_generator_matches_approved_visual_role_mapping() {
	new_fixture
	local slug manifest archive status summary actual expected
	for slug in solitude tokyo-night everforest; do
		manifest="$FIXTURE_ROOT/$slug.json"
		archive="$FIXTURE_ROOT/$slug.tdesktop-theme"
		status="$FIXTURE_ROOT/$slug.status.json"
		make_telegram_theme_manifest "/usr/share/omarchy/themes/$slug/colors.toml" "$slug" "$manifest" || return 1
		run_telegram_generator "$manifest" "$archive" "$status"
		assert_eq 0 "$COMMAND_STATUS" "$slug approved mapping should generate through the public CLI" || return 1
		if ! summary=$("$HOST_NODE_REAL" "$TELEGRAM_ASSERTIONS" "$archive" "$manifest" 2>&1); then
			printf '  %s approved mapping archive validation failed: %s\n' "$slug" "$summary" >&2
			return 1
		fi
		actual=$(jq -r '.role_value_sha256' <<<"$summary")
		expected=${TELEGRAM_APPROVED_ROLE_VALUE_SHA256[$slug]}
		assert_eq "$expected" "$actual" \
			"$slug should preserve the complete approved v2 role/value mapping" || return 1
	done
}

test_independent_assertions_reject_fully_collapsed_dialog_rows() {
	new_fixture
	local manifest=$FIXTURE_ROOT/custom-collapse.json archive=$FIXTURE_ROOT/custom-collapse.tdesktop-theme
	local status=$FIXTURE_ROOT/custom-collapse.status.json state collapsed diagnostic expected
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml custom-collapse "$manifest" || return 1
	run_telegram_generator "$manifest" "$archive" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'custom collapse fixture should begin with a valid approved archive' || return 1
	assert_valid_telegram_archive "$archive" "$manifest" || return 1
	for state in read unread; do
		collapsed=$FIXTURE_ROOT/collapsed-$state.tdesktop-theme
		make_collapsed_dialog_state_archive "$archive" "$collapsed" "$state" || return 1
		if diagnostic=$("$HOST_NODE_REAL" "$TELEGRAM_ASSERTIONS" "$collapsed" "$manifest" 2>&1); then
			printf '  independent assertions accepted a fully collapsed dialog %s-row fixture\n' "$state" >&2
			return 1
		fi
		[[ $state == read ]] && expected='dialogs read-row normal/hover' || expected='dialogs unread normal/hover'
		assert_contains "$diagnostic" "$expected" \
			"collapsed dialog $state-row fixture should fail its complete composite state" || return 1
	done
}

test_generator_accepts_valid_custom_light_and_dark_manifests() {
	new_fixture
	local mode source manifest archive status
	for mode in light dark; do
		[[ $mode == light ]] && source=/usr/share/omarchy/themes/flexoki-light/colors.toml || source=/usr/share/omarchy/themes/everforest/colors.toml
		manifest="$FIXTURE_ROOT/custom-$mode.json"
		archive="$FIXTURE_ROOT/custom-$mode.tdesktop-theme"
		status="$FIXTURE_ROOT/custom-$mode.status.json"
		make_telegram_theme_manifest "$source" "custom-$mode" "$manifest" || return 1
		run_telegram_generator "$manifest" "$archive" "$status"
		assert_eq 0 "$COMMAND_STATUS" "valid custom $mode manifest should generate" || return 1
		assert_valid_telegram_archive "$archive" "$manifest" || return 1
	done
}

test_generator_rejects_invalid_manifest_shapes_without_output() {
	new_fixture
	local valid=$FIXTURE_ROOT/valid.json manifest=$FIXTURE_ROOT/invalid.json
	local output=$FIXTURE_ROOT/current.tdesktop-theme status=$FIXTURE_ROOT/status.json filter
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml custom "$valid" || return 1
	while IFS= read -r filter; do
		jq "$filter" "$valid" >"$manifest"
		rm -f -- "$output" "$status"
		run_telegram_generator "$manifest" "$output" "$status"
		if [[ $COMMAND_STATUS -eq 0 || -e $output ]]; then
			printf '  invalid manifest produced output: %s\n' "$filter" >&2
			return 1
		fi
		jq -e '.schema_version == 1 and .status == "error" and (.message | type == "string" and length > 0)' "$status" >/dev/null || {
			printf '  invalid manifest did not produce structured failure status: %s\n' "$filter" >&2
			return 1
		}
	done <<'EOF'
.schema_version = 2
del(.mode)
del(.colors.foreground)
.colors.accent = "accent"
.colors.unknown = "#123456"
EOF
}

test_generator_uses_source_only_primary_surface_fallback() {
	new_fixture
	local manifest=$FIXTURE_ROOT/solitude.json archive=$FIXTURE_ROOT/solitude.tdesktop-theme
	local status=$FIXTURE_ROOT/status.json summary
	make_telegram_theme_manifest /usr/share/omarchy/themes/solitude/colors.toml solitude "$manifest" || return 1
	run_telegram_generator "$manifest" "$archive" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'Solitude should succeed through source-surface fallback' || return 1
	summary=$("$HOST_NODE_REAL" "$TELEGRAM_ASSERTIONS" "$archive" "$manifest") || return 1
	assert_eq '#101315' "$(jq -r '.primary_surface' <<<"$summary")" \
		'Solitude should choose the proven background fallback instead of inventing a color' || return 1
	if ! jq -e '.primary_distance >= 0.041 and .primary_distance < 0.042' <<<"$summary" >/dev/null; then
		printf '  Solitude fallback did not reproduce the proven 0.0416 OKLab separation: %s\n' "$summary" >&2
		return 1
	fi
}

test_generator_rejects_palette_without_source_surface_fallback() {
	new_fixture
	local manifest=$FIXTURE_ROOT/invalid-surfaces.json output=$FIXTURE_ROOT/output.tdesktop-theme
	local status=$FIXTURE_ROOT/status.json
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml custom-invalid "$manifest" || return 1
	jq '.colors.background = .colors.darker_background |
		.colors.dark_background = .colors.darker_background |
		.colors.selection = .colors.darker_background |
		.colors.muted = .colors.darker_background' "$manifest" >"$manifest.next"
	mv "$manifest.next" "$manifest"
	run_telegram_generator "$manifest" "$output" "$status"
	if [[ $COMMAND_STATUS -eq 0 || -e $output ]]; then
		printf '  generator published a palette with no source-only primary-surface fallback\n' >&2
		return 1
	fi
	assert_contains "$COMMAND_OUTPUT$(<"$status")" '0.025' 'surface failure should identify the required separation threshold'
}

test_generator_is_mtime_idempotent_and_preserves_last_good_on_failures() {
	new_fixture
	local manifest=$FIXTURE_ROOT/everforest.json output=$FIXTURE_ROOT/current.tdesktop-theme
	local status=$FIXTURE_ROOT/status.json before_hash before_mtime fake_bin=$FIXTURE_ROOT/zip-failure-bin
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest "$manifest" || return 1
	run_telegram_generator "$manifest" "$output" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'last-good fixture generation should succeed' || return 1
	before_hash=$(sha256sum "$output")
	before_mtime=$(stat -c '%y' "$output")
	sleep 0.05
	run_telegram_generator "$manifest" "$output" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'identical regeneration should succeed' || return 1
	assert_eq "$before_hash" "$(sha256sum "$output")" 'identical generation should preserve bytes' || return 1
	assert_eq "$before_mtime" "$(stat -c '%y' "$output")" 'identical generation should preserve mtime' || return 1

	jq 'del(.colors.foreground)' "$manifest" >"$manifest.invalid"
	run_telegram_generator "$manifest.invalid" "$output" "$status"
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  invalid generation unexpectedly succeeded\n' >&2
		return 1
	fi
	assert_eq "$before_hash" "$(sha256sum "$output")" 'validation failure should preserve last-good bytes' || return 1
	assert_eq "$before_mtime" "$(stat -c '%y' "$output")" 'validation failure should preserve last-good mtime' || return 1

	mkdir -p "$fake_bin"
	printf '#!/usr/bin/env bash\nexit 73\n' >"$fake_bin/zip"
	chmod +x "$fake_bin/zip"
	run_telegram_generator "$manifest" "$output" "$status" "$fake_bin:/usr/bin:/bin"
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  injected zip failure unexpectedly succeeded\n' >&2
		return 1
	fi
	assert_eq "$before_hash" "$(sha256sum "$output")" 'packaging failure should preserve last-good bytes' || return 1
	assert_eq "$before_mtime" "$(stat -c '%y' "$output")" 'packaging failure should preserve last-good mtime'
}

test_generator_does_not_publish_before_success_status_is_persisted() {
	local prior manifest output status output_dir status_dir events watcher watcher_status
	local before_output before_status event name saw_stable_event
	for prior in present absent; do
		new_fixture
		manifest=$FIXTURE_ROOT/changed.json
		output_dir=$FIXTURE_ROOT/output
		status_dir=$FIXTURE_ROOT/status
		output=$output_dir/current.tdesktop-theme
		status=$status_dir/status.json
		events=$FIXTURE_ROOT/status-failure-events
		mkdir "$output_dir" "$status_dir"
		make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest \
			"$FIXTURE_ROOT/prior.json" || return 1
		run_telegram_generator "$FIXTURE_ROOT/prior.json" "$output" "$status"
		assert_eq 0 "$COMMAND_STATUS" 'transaction fixture should seed exact last-good archive and status' || return 1
		if [[ $prior == absent ]]; then
			rm "$output"
		else
			before_output="$(stat -c '%d:%i:%f:%s:%y' "$output")|$(sha256sum "$output")"
		fi
		before_status="$(stat -c '%d:%i:%f:%s:%y' "$status")|$(sha256sum "$status")"
		make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$manifest" || return 1
		inotifywait --quiet --monitor --event moved_from --event moved_to --format '%e|%f' \
			"$output_dir" >"$events" 2>&1 &
		watcher=$!
		sleep 0.05

		run_guarded_generator_with_readonly_directory "$manifest" "$output" "$status" "$status_dir" || return 1
		local generation_status=$COMMAND_STATUS generation_output=$COMMAND_OUTPUT
		sleep 0.05
		watcher_status=0
		kill "$watcher" 2>/dev/null || true
		wait "$watcher" || watcher_status=$?
		[[ $watcher_status == 0 || $watcher_status == 143 ]] || {
			printf '  status-failure publication observer failed with status %s: %s\n' \
				"$watcher_status" "$(<"$events")" >&2
			return 1
		}
		if [[ $generation_status -eq 0 ]]; then
			printf '  generator reported success when the success status directory was read-only (%s prior output)\n' \
				"$prior" >&2
			return 1
		fi
		saw_stable_event=0
		while IFS='|' read -r event name; do
			if [[ $name == current.tdesktop-theme && ($event == *MOVED_FROM* || $event == *MOVED_TO*) ]]; then
				saw_stable_event=1
			fi
		done <"$events"
		if ((saw_stable_event)); then
			printf '  success-status persistence failure exposed an output publication event (%s prior output):\n%s\n' \
				"$prior" "$(<"$events")" >&2
			return 1
		fi
		assert_eq "$before_status" "$(stat -c '%d:%i:%f:%s:%y' "$status")|$(sha256sum "$status")" \
			'success-status persistence failure should preserve prior status identity, metadata, and bytes' || return 1
		if [[ $prior == present ]]; then
			assert_eq "$before_output" "$(stat -c '%d:%i:%f:%s:%y' "$output")|$(sha256sum "$output")" \
				'success-status persistence failure should preserve prior output identity, metadata, and bytes' || return 1
		elif [[ -e $output || -L $output ]]; then
			printf '  success-status persistence failure published an archive without prior output\n' >&2
			return 1
		fi
		assert_contains "$generation_output" 'telegram theme' \
			'success-status persistence failure should remain a reported generator failure' || return 1
	done
}

test_generator_rolls_status_back_when_archive_rename_fails() {
	new_fixture
	local output_dir=$FIXTURE_ROOT/output status_dir=$FIXTURE_ROOT/status
	local output=$output_dir/current.tdesktop-theme status=$status_dir/status.json
	local manifest=$FIXTURE_ROOT/changed.json events=$FIXTURE_ROOT/archive-failure-events
	local watcher watcher_status=0 before_output before_status event name
	local output_events=0 status_renames=0
	mkdir "$output_dir" "$status_dir"
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest \
		"$FIXTURE_ROOT/prior.json" || return 1
	run_telegram_generator "$FIXTURE_ROOT/prior.json" "$output" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'archive-rename failure fixture should seed exact last-good files' || return 1
	before_output="$(stat -c '%d:%i:%f:%s:%y' "$output")|$(sha256sum "$output")"
	before_status="$(stat -c '%d:%i:%f:%s:%y' "$status")|$(sha256sum "$status")"
	make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$manifest" || return 1

	inotifywait --quiet --monitor --event moved_from --event moved_to --format '%e|%f' \
		"$output_dir" "$status_dir" >"$events" 2>&1 &
	watcher=$!
	sleep 0.05
	run_guarded_generator_with_readonly_directory "$manifest" "$output" "$status" "$output_dir" || return 1
	local generation_status=$COMMAND_STATUS
	sleep 0.05
	kill "$watcher" 2>/dev/null || true
	wait "$watcher" || watcher_status=$?
	[[ $watcher_status == 0 || $watcher_status == 143 ]] || {
		printf '  archive-failure publication observer failed with status %s: %s\n' \
			"$watcher_status" "$(<"$events")" >&2
		return 1
	}
	if [[ $generation_status -eq 0 ]]; then
		printf '  generator reported success when the stable archive could not be renamed\n' >&2
		return 1
	fi
	while IFS='|' read -r event name; do
		if [[ $name == current.tdesktop-theme && ($event == *MOVED_FROM* || $event == *MOVED_TO*) ]]; then
			output_events=$((output_events + 1))
		elif [[ $name == status.json && $event == *MOVED_TO* ]]; then
			status_renames=$((status_renames + 1))
		fi
	done <"$events"
	assert_eq 0 "$output_events" 'archive rename failure should not move the stable output path' || return 1
	assert_eq 2 "$status_renames" 'archive rename failure should expose success status then atomically restore prior status' || return 1
	assert_eq "$before_output" "$(stat -c '%d:%i:%f:%s:%y' "$output")|$(sha256sum "$output")" \
		'archive rename failure should preserve prior output identity, metadata, and bytes' || return 1
	assert_eq "$before_status" "$(stat -c '%d:%i:%f:%s:%y' "$status")|$(sha256sum "$status")" \
		'archive rename failure should restore prior status identity, metadata, and bytes'
}

test_generator_rejects_output_symlink_without_mutating_referent_or_status() {
	new_fixture
	local manifest=$FIXTURE_ROOT/tokyo-night.json output=$FIXTURE_ROOT/current.tdesktop-theme
	local referent=$FIXTURE_ROOT/foreign-archive status=$FIXTURE_ROOT/status.json prior_output=$FIXTURE_ROOT/prior.tdesktop-theme
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest \
		"$FIXTURE_ROOT/prior.json" || return 1
	run_telegram_generator "$FIXTURE_ROOT/prior.json" "$prior_output" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'symlink rejection fixture should seed an exact prior status' || return 1
	printf 'foreign archive referent\n' >"$referent"
	ln -s "$referent" "$output"
	local link_before referent_hash referent_mtime status_hash status_mtime
	link_before=$(readlink "$output") || return 1
	referent_hash=$(sha256sum "$referent") || return 1
	referent_mtime=$(stat -c '%y' "$referent") || return 1
	status_hash=$(sha256sum "$status") || return 1
	status_mtime=$(stat -c '%y' "$status") || return 1
	make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night "$manifest" || return 1
	sleep 0.05

	run_telegram_generator "$manifest" "$output" "$status"
	if [[ $COMMAND_STATUS -eq 0 ]]; then
		printf '  generator accepted a symlink at the stable output path\n' >&2
		return 1
	fi
	if [[ ! -L $output ]]; then
		printf '  output symlink rejection replaced the stable symlink\n' >&2
		return 1
	fi
	assert_eq "$link_before" "$(readlink "$output")" 'output symlink rejection should preserve its exact link text' || return 1
	assert_eq "$referent_hash" "$(sha256sum "$referent")" 'output symlink rejection should preserve referent bytes' || return 1
	assert_eq "$referent_mtime" "$(stat -c '%y' "$referent")" 'output symlink rejection should preserve referent mtime' || return 1
	assert_eq "$status_hash" "$(sha256sum "$status")" 'output symlink rejection should roll status bytes back exactly' || return 1
	assert_eq "$status_mtime" "$(stat -c '%y' "$status")" 'output symlink rejection should roll status mtime back exactly'
}

test_generator_atomically_persists_status_before_replacing_stable_archive() {
	new_fixture
	local output=$FIXTURE_ROOT/current.tdesktop-theme status=$FIXTURE_ROOT/status.json
	local events=$FIXTURE_ROOT/publication-events watcher watcher_status=0 event name
	local saw_status_rename=0 output_renames=0
	make_telegram_theme_manifest /usr/share/omarchy/themes/everforest/colors.toml everforest \
		"$FIXTURE_ROOT/prior.json" || return 1
	run_telegram_generator "$FIXTURE_ROOT/prior.json" "$output" "$status"
	assert_eq 0 "$COMMAND_STATUS" 'atomic replacement fixture should seed a stable archive' || return 1
	make_telegram_theme_manifest /usr/share/omarchy/themes/tokyo-night/colors.toml tokyo-night \
		"$FIXTURE_ROOT/changed.json" || return 1

	inotifywait --quiet --monitor --event create --event modify --event close_write \
		--event moved_from --event moved_to --format '%e|%f' \
		"$FIXTURE_ROOT" >"$events" 2>&1 &
	watcher=$!
	sleep 0.05
	run_telegram_generator "$FIXTURE_ROOT/changed.json" "$output" "$status"
	local generation_status=$COMMAND_STATUS generation_output=$COMMAND_OUTPUT
	sleep 0.05
	kill "$watcher" 2>/dev/null || true
	wait "$watcher" || watcher_status=$?
	[[ $watcher_status == 0 || $watcher_status == 143 ]] || {
		printf '  inotify publication observer failed with status %s: %s\n' "$watcher_status" "$(<"$events")" >&2
		return 1
	}
	assert_eq 0 "$generation_status" "changed generation should succeed: $generation_output" || return 1
	while IFS='|' read -r event name; do
		if [[ $name == status.json ]]; then
			if [[ $event == *MODIFY* || $event == *CLOSE_WRITE* || $event == *CREATE* ]]; then
				printf '  success status was modified in place instead of atomically renamed:\n%s\n' "$(<"$events")" >&2
				return 1
			fi
			[[ $event == *MOVED_TO* ]] && saw_status_rename=1
		elif [[ $name == current.tdesktop-theme ]]; then
			if [[ $event == *MOVED_FROM* ]]; then
				printf '  stable archive was moved away before replacement; publication events:\n%s\n' "$(<"$events")" >&2
				return 1
			fi
			if [[ $event == *MOVED_TO* ]]; then
				if ((saw_status_rename == 0)); then
					printf '  changed stable archive was published before its atomic success status:\n%s\n' "$(<"$events")" >&2
					return 1
				fi
				output_renames=$((output_renames + 1))
			fi
		fi
	done <"$events"
	assert_eq 1 "$saw_status_rename" 'changed generation should atomically rename success status into place' || return 1
	assert_eq 1 "$output_renames" 'changed generation should directly replace the stable archive exactly once' || return 1
	jq -e --arg digest "$(sha256sum "$output" | cut -d' ' -f1)" \
		'.status == "ok" and .changed == true and .archive_sha256 == $digest' "$status" >/dev/null || {
		printf '  success status does not describe the changed stable archive\n' >&2
		return 1
	}
	assert_valid_telegram_archive "$output" "$FIXTURE_ROOT/changed.json"
}

set -e
run_test test_generator_cli_produces_deterministic_valid_archive 'generator CLI produces a deterministic validated archive'
run_test test_generator_accepts_every_stock_light_and_dark_palette 'generator accepts every stock light and dark Omarchy 4.0.1 palette'
run_test test_generator_matches_approved_visual_role_mapping 'generator preserves the approved visual role mapping'
run_test test_independent_assertions_reject_fully_collapsed_dialog_rows 'independent assertions reject fully collapsed dialog rows'
run_test test_generator_accepts_valid_custom_light_and_dark_manifests 'generator accepts valid custom light and dark manifests'
run_test test_generator_rejects_invalid_manifest_shapes_without_output 'generator rejects invalid manifest shapes without output'
run_test test_generator_uses_source_only_primary_surface_fallback 'generator uses the proven source-only primary-surface fallback'
run_test test_generator_rejects_palette_without_source_surface_fallback 'generator rejects palettes without a source-only surface fallback'
run_test test_generator_is_mtime_idempotent_and_preserves_last_good_on_failures 'generator is mtime-idempotent and preserves last-good output on failures'
run_test test_generator_does_not_publish_before_success_status_is_persisted 'generator does not publish before success status is persisted'
run_test test_generator_rolls_status_back_when_archive_rename_fails 'generator rolls status back when stable archive rename fails'
run_test test_generator_rejects_output_symlink_without_mutating_referent_or_status 'generator rejects output symlink without mutating referent or status'
run_test test_generator_atomically_persists_status_before_replacing_stable_archive 'generator atomically persists status before directly replacing the stable archive'
finish_tests
