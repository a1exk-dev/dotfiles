#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

assert_not_contains() {
	local haystack=$1 needle=$2 message=$3
	if [[ $haystack == *"$needle"* ]]; then
		printf '  %s\n  unexpected: %q\n  output:     %q\n' "$message" "$needle" "$haystack" >&2
		return 1
	fi
}

assert_path_absent() {
	local path=$1 message=$2
	if [[ -e $path || -L $path ]]; then
		printf '  %s\n  unexpected path: %s\n' "$message" "$path" >&2
		return 1
	fi
}

setup_supported_brave() {
	local package=${1-brave-bin}
	new_fixture
	setup_brave_fixture
	install_brave_consumer "$package"
}

set_brave_target_drift() {
	local drift=$1
	BRAVE_TEST_DRIFT_UID=0
	BRAVE_TEST_DRIFT_GID=0
	BRAVE_TEST_DRIFT_MODE=0644
	case $drift in
		content) printf 'receipt-owned content drift\n' >"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" ;;
		owner) BRAVE_TEST_DRIFT_UID=$(id -u) ;;
		group) BRAVE_TEST_DRIFT_GID=$(id -g) ;;
		mode) BRAVE_TEST_DRIFT_MODE=0655 ;;
		*) return 2 ;;
	esac
	chmod "$BRAVE_TEST_DRIFT_MODE" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	set_brave_metadata /etc/brave/policies/managed/dotfiles.json \
		"$BRAVE_TEST_DRIFT_UID" "$BRAVE_TEST_DRIFT_GID" "$BRAVE_TEST_DRIFT_MODE"
}

brave_target_metadata() {
	local key uid gid mode
	key=$(brave_metadata_key /etc/brave/policies/managed/dotfiles.json)
	read -r uid gid mode <"$BRAVE_METADATA_ROOT/$key"
	printf '%s %s %s\n' "$uid" "$gid" "$mode"
}

seed_pending_apply_receipt() {
	local state_root="$FIXTURE_STATE/dotfiles/brave-policy"
	local transaction=20260823T130000Z-1000-cafebabe digest pending
	digest=$(sha256sum "$FIXTURE_REPO/brave/managed-policy.json" | { read -r value _; printf '%s\n' "$value"; })
	mkdir -p "$state_root"
	chmod 0700 "$state_root"
	pending=$(jq -cn --arg transaction "$transaction" --arg digest "$digest" \
		'{schema_version:1,kind:"pending",operation:"apply",transaction_id:$transaction,created_at:"2026-08-23T13:00:00Z",target:"/etc/brave/policies/managed/dotfiles.json",prior_target:{present:false,digest:null,uid:null,gid:null,mode:null,backup_path:null},desired_digest:$digest,stage_path:("/etc/brave/policies/.dotfiles-"+$transaction+".stage"),managed_directory_original:{present:true,uid:0,gid:0,mode:"0755"},prior_active:{present:false,digest:null,backup_path:null}}')
	printf '%s\n' "$pending" >"$state_root/pending.json"
	chmod 0600 "$state_root/pending.json"
}

seed_recovery_receipt() {
	local state_root="$FIXTURE_STATE/dotfiles/brave-policy" pending recovery
	pending=$(<"$state_root/pending.json")
	recovery=$(jq -cn --argjson pending "$pending" \
		'{schema_version:1,kind:"recovery-required",transaction_id:$pending.transaction_id,created_at:"2026-08-23T13:01:00Z",failed_step:"test-interruption",pending:$pending}')
	printf '%s\n' "$recovery" >"$state_root/recovery-required.json"
	chmod 0600 "$state_root/recovery-required.json"
}

seed_pending_remove_receipt() {
	local state_root="$FIXTURE_STATE/dotfiles/brave-policy" transaction=20260823T140000Z-1000-acde1234
	local backup_root="$state_root/backups/$transaction" target_digest active_digest pending
	mkdir -p "$backup_root"
	chmod 0700 "$state_root" "$state_root/backups" "$backup_root"
	cp "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "$backup_root/dotfiles.json"
	cp "$state_root/active.json" "$backup_root/active.json"
	chmod 0600 "$backup_root/dotfiles.json" "$backup_root/active.json"
	target_digest=$(sha256sum "$backup_root/dotfiles.json" | { read -r value _; printf '%s\n' "$value"; })
	active_digest=$(sha256sum "$backup_root/active.json" | { read -r value _; printf '%s\n' "$value"; })
	pending=$(jq -cn --arg transaction "$transaction" --arg target_digest "$target_digest" --arg active_digest "$active_digest" \
		--arg target_backup "$backup_root/dotfiles.json" --arg active_backup "$backup_root/active.json" \
		'{schema_version:1,kind:"pending",operation:"remove",transaction_id:$transaction,created_at:"2026-08-23T14:00:00Z",target:"/etc/brave/policies/managed/dotfiles.json",prior_target:{present:true,digest:$target_digest,uid:0,gid:0,mode:"0644",backup_path:$target_backup},desired_digest:null,stage_path:null,managed_directory_original:{present:true,uid:0,gid:0,mode:"0755"},prior_active:{present:true,digest:$active_digest,backup_path:$active_backup}}')
	printf '%s\n' "$pending" >"$state_root/pending.json"
	chmod 0600 "$state_root/pending.json"
}

prepare_interrupted_restore_with_target_backup() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	printf 'receipt-owned prior drift\n' >"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	local drift_digest
	drift_digest=$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" | { read -r value _; printf '%s\n' "$value"; })
	jq -c --arg digest "$drift_digest" '.deployed_digest = $digest' "$FIXTURE_STATE/dotfiles/brave-policy/active.json" \
		>"$FIXTURE_STATE/dotfiles/brave-policy/active.next"
	mv "$FIXTURE_STATE/dotfiles/brave-policy/active.next" "$FIXTURE_STATE/dotfiles/brave-policy/active.json"
	chmod 0600 "$FIXTURE_STATE/dotfiles/brave-policy/active.json"
	DOTFILES_TEST_BRAVE_FAIL_AFTER=publish-stage DOTFILES_TEST_BRAVE_FAIL_BEFORE=restore-target DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'restore-race fixture should retain failed rollback state' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json && -f $FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json ]] || {
		printf '  restore-race fixture did not retain recovery receipts\n' >&2
		return 1
	}
}

prepare_state_only_interrupted_remove() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	local active="$FIXTURE_STATE/dotfiles/brave-policy/active.json"
	jq -c '.managed_directory_original = {present:true,uid:0,gid:0,mode:"0755"}' "$active" >"$active.next"
	mv "$active.next" "$active"
	chmod 0600 "$active"
	seed_pending_remove_receipt
	rm "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
}

brave_recovery_collision_snapshot() {
	local target="$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	local state="$FIXTURE_STATE/dotfiles/brave-policy"
	stat -c '%n|%d|%i|%u|%g|%a|%s|%y|%z' "$target" "$state/pending.json" "$state/recovery-required.json"
	sha256sum "$target" "$state/pending.json" "$state/recovery-required.json"
	brave_target_metadata
}

prepare_completed_interrupted_apply_cleanup() {
	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE=pending.json DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	if [[ $COMMAND_STATUS -ne 1 || ! -f $FIXTURE_STATE/dotfiles/brave-policy/active.json || \
		! -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json ]]; then
		printf '  could not prepare completed interrupted Apply cleanup\n' >&2
		return 1
	fi
	: >"$CALL_LOG"
}

brave_pending_cleanup_snapshot() {
	local target="$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	local state="$FIXTURE_STATE/dotfiles/brave-policy"
	stat -c '%n|%d|%i|%u|%g|%a|%s|%y|%z' "$target" "$state/active.json" "$state/pending.json"
	sha256sum "$target" "$state/active.json" "$state/pending.json"
	brave_target_metadata
}

brave_active_target_snapshot() {
	local target="$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	local active="$FIXTURE_STATE/dotfiles/brave-policy/active.json"
	stat -c '%n|%d|%i|%u|%g|%a|%s|%y|%z' "$target" "$active"
	sha256sum "$target" "$active"
	brave_target_metadata
}

assert_recovery_cleanup_order() {
	local expect_confirmation=$1 expect_removal=$2 message=$3 inspect_line confirmation_line removal_line calls
	calls=$(<"$CALL_LOG")
	inspect_line=$(awk '/^recovery-order inspect-omarchy$/ { print NR; exit }' "$CALL_LOG")
	confirmation_line=$(awk '/^recovery-order confirmation / { print NR; exit }' "$CALL_LOG")
	removal_line=$(awk '/^recovery-order remove-state pending.json$/ { print NR; exit }' "$CALL_LOG")
	if [[ -z $inspect_line ]]; then
		printf '  %s: Omarchy inspection was not logged\n' "$message" >&2
		return 1
	fi
	if [[ $expect_confirmation == true ]]; then
		if [[ -z $confirmation_line || $confirmation_line -le $inspect_line ]]; then
			printf '  %s: confirmation did not follow Omarchy inspection\n' "$message" >&2
			return 1
		fi
	elif [[ -n $confirmation_line ]]; then
		printf '  %s: matching automatic cleanup unexpectedly confirmed\n' "$message" >&2
		return 1
	fi
	if [[ $expect_removal == true ]]; then
		if [[ -z $removal_line || $removal_line -le $inspect_line || \
			( $expect_confirmation == true && $removal_line -le $confirmation_line ) ]]; then
			printf '  %s: pending receipt removal did not follow compatibility handling\n' "$message" >&2
			return 1
		fi
	elif [[ -n $removal_line ]]; then
		printf '  %s: declined recovery attempted pending receipt removal\n' "$message" >&2
		return 1
	fi
	assert_not_contains "$calls" 'privileged ' "$message should not use the privileged adapter" || return 1
	assert_not_contains "$calls" '/usr/bin/sudo' "$message should not request sudo"
}

test_public_interface_and_fixed_paths() {
	new_fixture
	run_brave_operation "$FIXTURE_ROOT" validate_brave_policy_source
	assert_eq 0 "$COMMAND_STATUS" 'public canonical validation should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'valid (11 top-level keys, 14 scalar leaves)' 'validation should report the exact shape' || return 1

	local function
	for function in validate_brave_policy_source brave_policy_status apply_brave_policy remove_brave_policy manage_brave_policy; do
		grep -Eq "^${function}[(][)]" "$FIXTURE_REPO/lib/dotfiles/brave.sh" || {
			printf '  missing public Brave function: %s\n' "$function" >&2
			return 1
		}
	done
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" "readonly BRAVE_POLICY_TARGET='/etc/brave/policies/managed/dotfiles.json'" 'production target should be literal and fixed' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" "readonly BRAVE_ROOT='/etc/brave'" 'production root should be literal and fixed' || return 1
	local outcome_contract
	for outcome_contract in \
		'BRAVE_OUTCOME_SUCCESS=0' \
		'BRAVE_OUTCOME_DECLINED=10' \
		'BRAVE_OUTCOME_UNAVAILABLE=11'; do
		assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" "readonly $outcome_contract" "public outcome should be named exactly: $outcome_contract" || return 1
	done
	assert_not_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'BRAVE_OUTCOME_RECOVERY_RERUN' 'recovery completion must not add a public outcome' || return 1
	assert_not_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'BRAVE_OUTCOME_RECOVERY_DECLINED' 'recovery decline must use public decline outcome 10' || return 1
	for outcome_contract in \
		'BRAVE_OPERATION_CONTEXT_ORDINARY=' \
		'BRAVE_OPERATION_CONTEXT_RECOVERY_COMPLETED=' \
		'BRAVE_OPERATION_CONTEXT_RECOVERY_DECLINED='; do
		assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" "readonly $outcome_contract" "operation context should be named: $outcome_contract" || return 1
	done
	assert_not_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'DOTFILES_TEST_' 'production module must not expose a test-root environment switch' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" '/usr/bin/sudo /usr/bin/install -T -o root -g root -m 0644 -- /dev/stdin "$stage"' 'production staging should install verified stdin through one fixed tool' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" '/usr/bin/sudo /usr/bin/install -T -o "$uid" -g "$gid" -m "$temporary_mode" -- /dev/stdin "$stage"' 'restore staging should install recorded ownership with a non-writable temporary mode' || return 1
	assert_eq 2 "$(grep -Fc '/usr/bin/sudo /usr/bin/mv --no-copy -fT -- "$stage" "$BRAVE_POLICY_TARGET"' "$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'both deployed-target publication paths should use fixed no-copy renames' || return 1
	assert_not_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" '/usr/bin/sudo /usr/bin/mv -fT -- "$stage" "$BRAVE_POLICY_TARGET"' 'deployed-target renames must not permit cross-filesystem copy fallback' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" '/usr/bin/sudo /usr/bin/chmod "$mode" -- "$BRAVE_POLICY_TARGET"' 'restore should set the recorded final mode only after atomic publication' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'Required action: make the receipt-owned target readable by the invoking user, then rerun.' 'unreadable-target guidance should state the required repair boundary' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'Run: /usr/bin/sudo /usr/bin/chmod 0644 -- %s' 'unreadable-target guidance should retain the fixed permission repair command' || return 1
	assert_not_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" '/usr/bin/tee' 'production staging must not use tee' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'mv -fT -- "$1" "$2"' 'receipt replacement should use no-directory atomic rename semantics' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'Unrelated root can mutate any path directly' 'stage safety should state the root trust boundary' || return 1
	assert_not_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" '/usr/bin/sudo bash' 'production privilege adapter must not invoke a root shell' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'flock --shared' 'status should use a shared flock' || return 1
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/brave.sh")" 'flock --exclusive' 'mutation should use an exclusive flock' || return 1
	"$HOST_NODE_REAL" -e '
		const fs = require("node:fs");
		for (const file of process.argv.slice(1)) {
			const text = fs.readFileSync(file, "utf8");
			if (text.includes("\r") || !text.endsWith("\n") || /^ +/m.test(text)) process.exit(1);
		}
	' "$FIXTURE_REPO/lib/dotfiles/brave-json.mjs" "$FIXTURE_REPO/brave/managed-policy.json" || {
		printf '  new Brave Node and policy files do not satisfy .editorconfig tab/LF/final-newline rules\n' >&2
		return 1
	}
}

test_canonical_policy_rejects_every_shape_family() {
	new_fixture
	local source="$FIXTURE_REPO/brave/managed-policy.json" candidate="$FIXTURE_ROOT/candidate.json" key filter
	local -a keys=()
	mapfile -t keys < <(jq -r 'keys[]' "$source")
	for key in "${keys[@]}"; do
		jq --arg key "$key" 'del(.[$key])' "$source" >"$candidate"
		if "$HOST_NODE_REAL" "$FIXTURE_REPO/lib/dotfiles/brave-json.mjs" canonical "$candidate" >/dev/null; then
			printf '  canonical helper accepted missing key: %s\n' "$key" >&2
			return 1
		fi
	done
	local -a filters=(
		'.UnexpectedPolicy = true'
		'.BackgroundModeEnabled = true'
		'.BookmarkBarEnabled = false'
		'.BraveAIChatEnabled = true'
		'.BraveP3AEnabled = true'
		'.EnableMediaRouter = false'
		'.HomepageIsNewTabPage = false'
		'.MetricsReportingEnabled = true'
		'.ShowHomeButton = true'
		'.SpellcheckEnabled = false'
		'.SpellcheckLanguage = ["en"]'
		'.SpellcheckLanguage = ["en-US", "en"]'
		'.SpellcheckLanguage = "en-US"'
		'.ExtensionSettings.bgnkhhnnamicmpeenaelnjfhikgbkllg.installation_mode = "force_installed"'
		'.ExtensionSettings.bgnkhhnnamicmpeenaelnjfhikgbkllg.update_url = "https://example.test/crx"'
		'del(.ExtensionSettings.bgnkhhnnamicmpeenaelnjfhikgbkllg.update_url)'
		'.ExtensionSettings.bgnkhhnnamicmpeenaelnjfhikgbkllg.extra = true'
		'.ExtensionSettings.nngceckbapebfimnlniiiahkandclblb.installation_mode = "force_installed"'
		'del(.ExtensionSettings.nngceckbapebfimnlniiiahkandclblb.installation_mode)'
		'.ExtensionSettings.nngceckbapebfimnlniiiahkandclblb.update_url = "https://example.test/crx"'
		'del(.ExtensionSettings.nngceckbapebfimnlniiiahkandclblb.update_url)'
		'.ExtensionSettings.nngceckbapebfimnlniiiahkandclblb.installation_mode_extra = "normal_installed"'
		'.ExtensionSettings.nngceckbapebfimnlniiiahkandclblb.update_url_extra = "https://clients2.google.com/service/update2/crx"'
		'.ExtensionSettings.nngceckbapebfimnlniiiahkandclblb.extra = true'
		'.ExtensionSettings.badextension = .ExtensionSettings.bgnkhhnnamicmpeenaelnjfhikgbkllg'
		'del(.ExtensionSettings.bgnkhhnnamicmpeenaelnjfhikgbkllg)'
		'.ExtensionSettings = []'
	)
	for filter in "${filters[@]}"; do
		jq "$filter" "$source" >"$candidate"
		if "$HOST_NODE_REAL" "$FIXTURE_REPO/lib/dotfiles/brave-json.mjs" canonical "$candidate" >/dev/null; then
			printf '  canonical helper accepted mutation: %s\n' "$filter" >&2
			return 1
		fi
	done
	assert_eq true "$(jq -r '.HomepageIsNewTabPage' "$source")" 'eleventh-key amendment should be present and true' || return 1
	assert_eq 11 "$(jq 'keys | length' "$source")" 'canonical policy should have exactly eleven top-level keys' || return 1
	assert_eq 'normal_installed' "$(jq -r '.ExtensionSettings.bgnkhhnnamicmpeenaelnjfhikgbkllg.installation_mode' "$source")" 'AdGuard should remain normally installed' || return 1
	assert_eq 'normal_installed' "$(jq -r '.ExtensionSettings.nngceckbapebfimnlniiiahkandclblb.installation_mode' "$source")" 'Bitwarden should remain normally installed'
}

test_duplicate_aware_parser_covers_policy_foreign_and_receipts() {
	new_fixture
	local helper="$FIXTURE_REPO/lib/dotfiles/brave-json.mjs" candidate="$FIXTURE_ROOT/duplicate.json" output
	local json
	for json in \
		'{"same":1,"same":2}' \
		'{"outer":{"same":1,"same":2}}' \
		'{"same":1,"\u0073ame":2}' \
		'{"array":[{"same":1,"same":2}]}'; do
		printf '%s\n' "$json" >"$candidate"
		if output=$("$HOST_NODE_REAL" "$helper" inventory "$candidate"); then
			printf '  duplicate-aware inventory accepted: %s\n' "$json" >&2
			return 1
		fi
		assert_contains "$output" 'duplicate object member' 'duplicate rejection should be explicit' || return 1
	done
	setup_brave_fixture
	seed_active_brave_policy
	"$HOST_NODE_REAL" "$helper" receipt "$FIXTURE_STATE/dotfiles/brave-policy/active.json" active "$FIXTURE_STATE/dotfiles/brave-policy" >/dev/null || return 1
	jq '.extra = true' "$FIXTURE_STATE/dotfiles/brave-policy/active.json" >"$candidate"
	if "$HOST_NODE_REAL" "$helper" receipt "$candidate" active "$FIXTURE_STATE/dotfiles/brave-policy" >/dev/null; then
		printf '  receipt helper accepted an additional field\n' >&2
		return 1
	fi
	jq '.activated_at = "2026-99-99T25:61:61Z"' "$FIXTURE_STATE/dotfiles/brave-policy/active.json" >"$candidate"
	if "$HOST_NODE_REAL" "$helper" receipt "$candidate" active "$FIXTURE_STATE/dotfiles/brave-policy" >/dev/null; then
		printf '  receipt helper accepted an impossible timestamp\n' >&2
		return 1
	fi
	printf '{"schema_version":1,"schema_version":1}\n' >"$candidate"
	if "$HOST_NODE_REAL" "$helper" receipt "$candidate" active "$FIXTURE_STATE/dotfiles/brave-policy" >/dev/null; then
		printf '  receipt helper accepted duplicate members\n' >&2
		return 1
	fi
}

test_no_follow_helper_primitives_reject_symlink_inputs() {
	new_fixture
	local helper="$FIXTURE_REPO/lib/dotfiles/brave-json.mjs" left="$FIXTURE_ROOT/left" right="$FIXTURE_ROOT/right"
	local sensitive="$FIXTURE_ROOT/sensitive" link="$FIXTURE_ROOT/link" destination="$FIXTURE_ROOT/copy" output digest sensitive_before
	printf 'same bytes\n' >"$left"
	cp "$left" "$right"
	output=$("$HOST_NODE_REAL" "$helper" compare-no-follow "$left" "$right") || return 1
	assert_eq true "$(jq -r '.equal' <<<"$output")" 'no-follow comparison should accept equal regular files' || return 1
	printf 'different bytes\n' >"$right"
	output=$("$HOST_NODE_REAL" "$helper" compare-no-follow "$left" "$right") || return 1
	assert_eq false "$(jq -r '.equal' <<<"$output")" 'no-follow comparison should report unequal regular files' || return 1

	printf 'SENSITIVE-NO-FOLLOW-REFERENT\n' >"$sensitive"
	sensitive_before="$(stat -c '%a|%u|%g|%s|%y' "$sensitive")|$(sha256sum "$sensitive")"
	ln -s "$sensitive" "$link"
	digest=$(sha256sum "$sensitive")
	for operation in digest-no-follow compare-no-follow emit-no-follow copy-no-follow; do
		case $operation in
			compare-no-follow) output=$("$HOST_NODE_REAL" "$helper" "$operation" "$link" "$left" 2>&1) && return 1 ;;
			emit-no-follow) output=$("$HOST_NODE_REAL" "$helper" "$operation" "$link" "${digest%% *}" 2>&1) && return 1 ;;
			copy-no-follow) output=$("$HOST_NODE_REAL" "$helper" "$operation" "$link" "$destination" 2>&1) && return 1 ;;
			digest-no-follow) output=$("$HOST_NODE_REAL" "$helper" "$operation" "$link" 2>&1) && return 1 ;;
		esac
		assert_not_contains "$output" 'SENSITIVE-NO-FOLLOW-REFERENT' "$operation failure must not disclose referent bytes" || return 1
	done
	assert_path_absent "$destination" 'failed symlink-source copy should not create a destination' || return 1
	assert_eq "$sensitive_before" "$(stat -c '%a|%u|%g|%s|%y' "$sensitive")|$(sha256sum "$sensitive")" 'no-follow primitives must not mutate the symlink referent'
}

test_status_is_read_only_for_clean_absence() {
	new_fixture
	setup_brave_fixture
	run_brave_operation "$FIXTURE_ROOT" brave_policy_status
	assert_eq 0 "$COMMAND_STATUS" 'clean absent status should succeed without a browser' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Deployment state: cleanly absent.' 'status should classify clean absence' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Validated evidence baseline: Omarchy 4.0.0-1, Brave 1.93.136, Chromium 151.0.7922.137, package 1:1.93.136-1.' 'status should print the complete validated Omarchy, browser, and package baseline' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy major: 4.' 'status should report the supported major separately from evidence versions' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Available installers: omarchy install browser brave; omarchy install browser brave-origin' 'status should report both supported installers' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'status must request no privilege and execute no browser' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy" 'status must not create state merely to lock it'
}

test_no_browser_apply_returns_11_before_system_inspection() {
	new_fixture
	setup_brave_fixture
	rm -rf "$FIXTURE_BRAVE_SYSTEM"
	run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
	assert_eq 11 "$COMMAND_STATUS" 'no supported browser should return the typed prerequisite outcome' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: ordinary' 'unavailable apply should reset operation context to ordinary' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy install browser brave' 'no-browser result should report Browser installation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'omarchy install browser brave-origin' 'no-browser result should report Origin installation' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'no-browser result should not request privilege' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy" 'no-browser result should not create receipt state'
}

test_consumer_matrix_and_version_warning() {
	local package expected
	for package in brave-bin brave-origin-bin; do
		setup_supported_brave "$package"
		DOTFILES_TEST_INPUT='n\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		assert_eq 10 "$COMMAND_STATUS" "$package should reach the displayed plan" || return 1
		[[ $package == brave-bin ]] && expected='Brave Browser' || expected='Brave Origin'
		assert_contains "$COMMAND_OUTPUT" "$expected: installed package $package" 'single consumer should be identified by exact package' || return 1
		assert_not_contains "$(<"$CALL_LOG")" 'BROWSER EXECUTED' 'consumer inspection must never execute a browser' || return 1
	done

	new_fixture
	setup_brave_fixture
	install_brave_consumer brave-bin
	install_brave_consumer brave-origin-bin
	DOTFILES_TEST_INPUT='n\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 10 "$COMMAND_STATUS" 'both consumers should share one declined plan' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Both Brave Browser and Brave Origin consume this one byte-identical policy' 'both-consumer consequence should be explicit' || return 1

	setup_supported_brave brave-bin
	printf 'brave-bin|1:1.94.1-1\n' >"$BRAVE_PACKAGE_DB"
	DOTFILES_TEST_INPUT='n\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 10 "$COMMAND_STATUS" 'different package version should warn but still permit static planning' || return 1
	assert_contains "$COMMAND_OUTPUT" 'differs from validated baseline' 'version drift should produce a nonblocking warning'
}

test_unsupported_provider_matrix_blocks_before_mutation() {
	local variant provider
	for variant in missing other-package unowned shadowed; do
		setup_supported_brave brave-bin
		provider="$FIXTURE_BIN/brave"
		case $variant in
			missing) : >"$BRAVE_PROVIDER_DB" ;;
			other-package) printf '%s|chromium\n' "$provider" >"$BRAVE_OWNER_DB" ;;
			unowned) : >"$BRAVE_OWNER_DB" ;;
			shadowed)
				mkdir -p "$FIXTURE_HOME/bin"
				printf '#!/usr/bin/env bash\nexit 99\n' >"$FIXTURE_HOME/bin/brave"
				chmod +x "$FIXTURE_HOME/bin/brave"
				printf 'brave|%s\n' "$FIXTURE_HOME/bin/brave" >"$BRAVE_PROVIDER_DB"
				: >"$BRAVE_OWNER_DB"
				;;
		esac
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		if [[ $COMMAND_STATUS -eq 0 || $COMMAND_STATUS -eq 10 || $COMMAND_STATUS -eq 11 ]]; then
			printf '  unsupported provider variant was not blocked: %s (status %s)\n' "$variant" "$COMMAND_STATUS" >&2
			return 1
		fi
		assert_contains "$COMMAND_OUTPUT" "$([[ $variant == missing ]] && printf 'missing command' || printf 'unsupported')" "$variant provider should be diagnosed" || return 1
		assert_eq '' "$(<"$CALL_LOG")" "$variant provider should block before privilege or browser execution" || return 1
		assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "$variant provider should not deploy policy" || return 1
	done
}

test_status_classification_matrix() {
	local case_name
	for case_name in exact drift unowned stale malformed pending recovery; do
		new_fixture
		setup_brave_fixture
		install_brave_consumer brave-bin
		case $case_name in
			exact) seed_active_brave_policy ;;
			drift) seed_active_brave_policy; printf ' \n' >>"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" ;;
			unowned) cp "$FIXTURE_REPO/brave/managed-policy.json" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"; chmod 0644 "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"; set_brave_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0644 ;;
			stale) seed_active_brave_policy; rm "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" ;;
			malformed) seed_active_brave_policy; printf '{\n' >"$FIXTURE_STATE/dotfiles/brave-policy/active.json" ;;
			pending) seed_pending_apply_receipt ;;
			recovery) seed_pending_apply_receipt; seed_recovery_receipt ;;
		esac
		run_brave_operation "$FIXTURE_ROOT" brave_policy_status
		if [[ $case_name == exact ]]; then
			assert_eq 0 "$COMMAND_STATUS" 'exact active status should succeed' || return 1
			assert_contains "$COMMAND_OUTPUT" 'exact active deployment' 'exact active status should be explicit' || return 1
		else
			if [[ $COMMAND_STATUS -eq 0 ]]; then
				printf '  unhealthy status case succeeded: %s\n' "$case_name" >&2
				return 1
			fi
			case $case_name in
				drift) assert_contains "$COMMAND_OUTPUT" 'active-target drift' 'drift should be classified' || return 1 ;;
				unowned) assert_contains "$COMMAND_OUTPUT" 'unowned target collision' 'unowned target should be classified' || return 1 ;;
				stale) assert_contains "$COMMAND_OUTPUT" 'stale active receipt' 'stale receipt should be classified' || return 1 ;;
				malformed) assert_contains "$COMMAND_OUTPUT" 'invalid Brave active receipt' 'malformed receipt should be diagnosed' || return 1 ;;
				pending|recovery) assert_contains "$COMMAND_OUTPUT" 'reconcile the interrupted transaction' 'transaction state should route recovery' || return 1 ;;
			esac
		fi
		assert_not_contains "$(<"$CALL_LOG")" 'privileged ' 'status should never use the privileged adapter' || return 1
		assert_not_contains "$(<"$CALL_LOG")" 'BROWSER EXECUTED' 'status should never invoke a browser' || return 1
	done
}

test_destination_no_follow_and_metadata_matrix() {
	local variant outside
	for variant in brave-symlink policies-symlink managed-symlink target-symlink brave-owner policies-mode managed-owner; do
		setup_supported_brave brave-bin
		outside="$FIXTURE_ROOT/outside-policy"
		mkdir -p "$outside"
		case $variant in
			brave-symlink) mv "$FIXTURE_BRAVE_SYSTEM" "$outside/brave-real"; ln -s "$outside/brave-real" "$FIXTURE_BRAVE_SYSTEM" ;;
			policies-symlink) mv "$FIXTURE_BRAVE_SYSTEM/policies" "$outside/policies-real"; ln -s "$outside/policies-real" "$FIXTURE_BRAVE_SYSTEM/policies" ;;
			managed-symlink) rmdir "$FIXTURE_BRAVE_SYSTEM/policies/managed"; ln -s "$outside" "$FIXTURE_BRAVE_SYSTEM/policies/managed" ;;
			target-symlink) printf 'outside\n' >"$outside/target"; ln -s "$outside/target" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" ;;
			brave-owner) set_brave_metadata /etc/brave 1000 1000 0755 ;;
			policies-mode) set_brave_metadata /etc/brave/policies 0 0 0777 ;;
			managed-owner) set_brave_metadata /etc/brave/policies/managed 1000 1000 0755 ;;
		esac
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		if [[ $COMMAND_STATUS -eq 0 || $COMMAND_STATUS -eq 10 ]]; then
			printf '  unsafe destination variant reached mutation approval: %s\n' "$variant" >&2
			return 1
		fi
		assert_eq '' "$(<"$CALL_LOG")" "$variant should block before privilege" || return 1
		if [[ $variant == target-symlink ]]; then
			assert_eq outside "$(<"$outside/target")" 'target symlink rejection should preserve its referent' || return 1
		fi
	done
}

test_receipt_owned_regular_target_drift_is_repairable_and_removable() {
	local operation drift
	for operation in apply_brave_policy remove_brave_policy; do
		for drift in content owner group mode; do
			setup_supported_brave brave-bin
			seed_active_brave_policy
			set_brave_target_drift "$drift"
			run_brave_operation "$FIXTURE_ROOT" brave_policy_status
			assert_eq 1 "$COMMAND_STATUS" "$drift target drift should be unhealthy before $operation" || return 1
			assert_contains "$COMMAND_OUTPUT" 'Deployment state: active-target drift.' "$drift target drift should be classified" || return 1
			assert_contains "$COMMAND_OUTPUT" 'Required action: Apply to repair or Remove to delete the receipt-owned target.' "$drift target drift should retain actionable guidance" || return 1
			DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" "$operation"
			assert_eq 0 "$COMMAND_STATUS" "$operation should accept receipt-owned regular $drift drift" || return 1
			if [[ $operation == apply_brave_policy ]]; then
				cmp -s "$FIXTURE_REPO/brave/managed-policy.json" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" || {
					printf '  apply did not repair %s drift to exact source bytes\n' "$drift" >&2
					return 1
				}
				assert_eq '0 0 0644' "$(brave_target_metadata)" "apply should repair $drift drift to root:root 0644" || return 1
			else
				assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "remove should delete receipt-owned regular $drift drift" || return 1
			fi
		done
	done
}

test_arbitrary_target_metadata_rolls_back_before_delete_and_after_publish() {
	local drift before_identity before_digest before_metadata snapshot temporary_mode actual_mode
	for drift in content owner group mode; do
		setup_supported_brave brave-bin
		seed_active_brave_policy
		set_brave_target_drift "$drift"
		chmod 0777 "$FIXTURE_BRAVE_SYSTEM/policies/managed"
		set_brave_metadata /etc/brave/policies/managed 0 0 0777
		before_identity=$(stat -c '%d:%i' "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")
		before_digest=$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")
		before_metadata=$(brave_target_metadata)
		DOTFILES_TEST_BRAVE_FAIL_AFTER=harden-managed DOTFILES_TEST_INPUT='y\n' \
			run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
		assert_eq 1 "$COMMAND_STATUS" "$drift pre-delete failure should fail remove" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' "$drift pre-delete failure should roll back directory metadata" || return 1
		assert_not_contains "$(<"$CALL_LOG")" 'privileged restore-target' "$drift pre-delete rollback should not rewrite an unchanged target" || return 1
		assert_eq "$before_identity" "$(stat -c '%d:%i' "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")" "$drift pre-delete rollback should preserve target inode" || return 1
		assert_eq "$before_digest" "$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")" "$drift pre-delete rollback should preserve target bytes" || return 1
		assert_eq "$before_metadata" "$(brave_target_metadata)" "$drift pre-delete rollback should preserve target metadata" || return 1
		assert_eq 777 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" "$drift pre-delete rollback should restore directory mode" || return 1

		setup_supported_brave brave-bin
		seed_active_brave_policy
		set_brave_target_drift "$drift"
		snapshot="$FIXTURE_ROOT/$drift-prior-target"
		cp "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "$snapshot"
		before_metadata=$(brave_target_metadata)
		printf -v temporary_mode '%04o' "$((8#$BRAVE_TEST_DRIFT_MODE & 07555))"
		DOTFILES_TEST_BRAVE_FAIL_AFTER=publish-stage DOTFILES_TEST_INPUT='y\n' \
			run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		assert_eq 1 "$COMMAND_STATUS" "$drift post-publication failure should fail apply" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' "$drift post-publication failure should restore prior state" || return 1
		cmp -s "$snapshot" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" || {
			printf '  %s post-publication rollback did not restore exact prior bytes\n' "$drift" >&2
			return 1
		}
		assert_eq "$before_metadata" "$(brave_target_metadata)" "$drift post-publication rollback should restore exact prior metadata" || return 1
		actual_mode=$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")
		assert_eq "${BRAVE_TEST_DRIFT_MODE#0}" "$actual_mode" "$drift post-publication rollback should apply the recorded final mode" || return 1
		assert_contains "$(<"$CALL_LOG")" "/usr/bin/sudo /usr/bin/install -T -o $BRAVE_TEST_DRIFT_UID -g $BRAVE_TEST_DRIFT_GID -m $temporary_mode -- /dev/stdin" "$drift rollback should stage with recorded ownership and non-writable temporary mode" || return 1
		assert_contains "$(<"$CALL_LOG")" '/usr/bin/sudo /usr/bin/mv --no-copy -fT -- /etc/brave/policies/.dotfiles-' "$drift rollback should restore through a no-copy atomic rename" || return 1
		assert_contains "$(<"$CALL_LOG")" "/usr/bin/sudo /usr/bin/chmod $BRAVE_TEST_DRIFT_MODE -- /etc/brave/policies/managed/dotfiles.json" "$drift rollback should set the recorded final mode after publication" || return 1
		if (( (8#$temporary_mode & 0222) != 0 )); then
			printf '  %s rollback temporary stage mode remained writable: %s\n' "$drift" "$temporary_mode" >&2
			return 1
		fi
	done
}

test_foreign_policy_safety_matrix() {
	local variant uid outside
	uid=$(id -u)
	for variant in canonical-collision foreign-collision duplicate malformed user-writable group-writable directory symlink color-collision; do
		setup_supported_brave brave-bin
		outside="$FIXTURE_ROOT/foreign-outside"
		printf 'outside foreign\n' >"$outside"
		case $variant in
			canonical-collision) add_brave_foreign_policy collision.json '{"BookmarkBarEnabled":false}' ;;
			foreign-collision) add_brave_foreign_policy one.json '{"ForeignKey":true}'; add_brave_foreign_policy two.json '{"ForeignKey":false}' ;;
			duplicate) add_brave_foreign_policy duplicate.json '{"Outer":{"Key":1,"Key":2}}' ;;
			malformed) add_brave_foreign_policy malformed.json '{' ;;
			user-writable) add_brave_foreign_policy writable.json '{"ForeignKey":true}' "$uid" "$(id -g)" 0644 ;;
			group-writable) add_brave_foreign_policy writable.json '{"ForeignKey":true}' 0 0 0664 ;;
			directory) mkdir "$FIXTURE_BRAVE_SYSTEM/policies/managed/directory.json" ;;
			symlink) ln -s "$outside" "$FIXTURE_BRAVE_SYSTEM/policies/managed/link.json" ;;
			color-collision) add_brave_color_policy '{"BookmarkBarEnabled":false}' ;;
		esac
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		if [[ $COMMAND_STATUS -eq 0 || $COMMAND_STATUS -eq 10 ]]; then
			printf '  unsafe foreign policy reached approval: %s\n' "$variant" >&2
			return 1
		fi
		assert_contains "$COMMAND_OUTPUT" 'Collision or foreign-policy safety error:' "$variant should produce a foreign-policy diagnostic" || return 1
		assert_eq '' "$(<"$CALL_LOG")" "$variant should block before privilege" || return 1
		assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "$variant should not deploy policy" || return 1
	done
}

test_apply_preview_publish_preservation_and_idempotence() {
	setup_supported_brave brave-bin
	add_brave_color_policy
	add_brave_foreign_policy enterprise.json '{"ForeignPolicy":"keep"}' 0 0 0444
	seed_brave_canaries
	chmod 0777 "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	set_brave_metadata /etc/brave/policies/managed 0 0 0777
	local color_before foreign_before canaries_before packages_before active_before calls_before backup_count_before
	color_before="$(stat -c '%a|%s|%Y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")"
	foreign_before="$(stat -c '%a|%s|%Y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/enterprise.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/enterprise.json")"
	canaries_before=$(snapshot_brave_canaries)
	packages_before=$(sha256sum "$BRAVE_PACKAGE_DB" "$BRAVE_PROVIDER_DB" "$BRAVE_OWNER_DB")

	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'confirmed apply should publish and verify' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Complete source-to-target change:' 'preview should contain the full source-to-target diff' || return 1
	assert_contains "$COMMAND_OUTPUT" 'enterprise.json:' 'preview should inventory every foreign filename and key set' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Transaction backup paths:' 'preview should disclose backup paths' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Privileged effects after confirmation:' 'preview should disclose every privileged effect class' || return 1
	assert_contains "$COMMAND_OUTPUT" 'user-owned lifecycle evidence' 'preview should disclose receipt trust limits' || return 1
	assert_contains "$COMMAND_OUTPUT" 'AdGuard and Bitwarden become required but disableable' 'preview should disclose extension behavior' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Not changed: color.json, other foreign policy, packages, profiles' 'preview should disclose preservation boundaries' || return 1
	assert_eq 1 "$(awk '/Apply this complete Brave policy plan/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" 'apply should ask exactly once' || return 1
	cmp -s "$FIXTURE_REPO/brave/managed-policy.json" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" || {
		printf '  target bytes differ from canonical source\n' >&2
		return 1
	}
	assert_eq 755 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'apply should harden managed directory' || return 1
	assert_eq 600 "$(stat -c %a "$FIXTURE_STATE/dotfiles/brave-policy/active.json")" 'active receipt should be 0600' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'successful apply should clear pending receipt' || return 1
	"$HOST_NODE_REAL" "$FIXTURE_REPO/lib/dotfiles/brave-json.mjs" receipt "$FIXTURE_STATE/dotfiles/brave-policy/active.json" active "$FIXTURE_STATE/dotfiles/brave-policy" >/dev/null || return 1
	assert_eq "$color_before" "$(stat -c '%a|%s|%Y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")" 'apply should preserve color.json bytes and metadata' || return 1
	assert_eq "$foreign_before" "$(stat -c '%a|%s|%Y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/enterprise.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/enterprise.json")" 'apply should preserve disjoint foreign policy bytes and metadata' || return 1
	assert_eq "$canaries_before" "$(snapshot_brave_canaries)" 'apply should preserve profile, flags, themes, fonts, and packaged Omarchy canaries' || return 1
	assert_eq "$packages_before" "$(sha256sum "$BRAVE_PACKAGE_DB" "$BRAVE_PROVIDER_DB" "$BRAVE_OWNER_DB")" 'apply should preserve package/provider metadata fixtures' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'BROWSER EXECUTED' 'apply should never execute a browser' || return 1
	assert_contains "$(<"$CALL_LOG")" '/usr/bin/sudo /usr/bin/install -T -o root -g root -m 0644 -- /dev/stdin /etc/brave/policies/.dotfiles-' 'stage should install verified stdin to a fixed policy-filesystem path' || return 1
	assert_contains "$(<"$CALL_LOG")" '/usr/bin/sudo /usr/bin/mv --no-copy -fT -- /etc/brave/policies/.dotfiles-' 'publication should be an atomic fixed no-copy rename' || return 1
	assert_not_contains "$(<"$CALL_LOG")" "/usr/bin/sudo $FIXTURE_REPO" 'sudo must not receive the repository path' || return 1

	active_before="$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")|$(stat -c %Y "$FIXTURE_STATE/dotfiles/brave-policy/active.json")"
	calls_before=$(<"$CALL_LOG")
	local -a backup_dirs=("$FIXTURE_STATE"/dotfiles/brave-policy/backups/*)
	backup_count_before=${#backup_dirs[@]}
	run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'exact active apply should be an idempotent success' || return 1
	assert_contains "$COMMAND_OUTPUT" 'no confirmation, privilege, backup, or receipt change is needed' 'idempotence should be explicit' || return 1
	assert_not_contains "$COMMAND_OUTPUT" '[y/N]' 'idempotent apply should not confirm' || return 1
	assert_eq "$active_before" "$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")|$(stat -c %Y "$FIXTURE_STATE/dotfiles/brave-policy/active.json")" 'idempotence should preserve active receipt bytes and timestamp' || return 1
	assert_eq "$calls_before" "$(<"$CALL_LOG")" 'idempotence should make no additional privilege calls' || return 1
	local -a backup_dirs_after=("$FIXTURE_STATE"/dotfiles/brave-policy/backups/*)
	assert_eq "$backup_count_before" "${#backup_dirs_after[@]}" 'idempotence should not add a backup transaction'
}

test_apply_decline_gum_root_and_mismatch_confirmation() {
	setup_supported_brave brave-bin
	add_brave_color_policy
	local before
	before=$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")
	DOTFILES_TEST_INPUT='n\n' run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
	assert_eq 10 "$COMMAND_STATUS" 'Bash decline should return typed outcome 10' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: ordinary' 'ordinary decline should retain ordinary operation context' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'Bash decline should request no privilege' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy" 'Bash decline should create no state' || return 1
	assert_eq "$before" "$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")" 'Bash decline should preserve color policy' || return 1

	setup_supported_brave brave-bin
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == confirm ]]; then exit 1; fi
exit 64'
	DOTFILES_UI=gum run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 10 "$COMMAND_STATUS" 'Gum decline should return typed outcome 10' || return 1
	assert_eq 1 "$(awk '/^gum confirm / { count++ } END { print count + 0 }' "$CALL_LOG")" 'Gum apply should ask one confirmation' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged ' 'Gum decline should happen before privilege' || return 1

	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_UID=0 run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'root mutation should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'must run as the invoking user, not root' 'root rejection should be explicit' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'root rejection should precede privilege and browser inspection' || return 1

	setup_supported_brave brave-bin
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'one complete confirmation should include Omarchy mismatch consent' || return 1
	assert_contains "$COMMAND_OUTPUT" 'requires consent to continue despite the Omarchy major-version mismatch' 'mismatch should be inside the complete plan' || return 1
	assert_eq 1 "$(awk '/\[y\/N\]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" 'mismatched apply should still use one confirmation'
}

test_apply_rechecks_all_confirmed_state_families() {
	local race
	for race in source consumers providers receipts target paths metadata foreign; do
		setup_supported_brave brave-bin
		seed_active_brave_policy
		printf ' \n' >>"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
		DOTFILES_TEST_BRAVE_RACE=$race DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		if [[ $COMMAND_STATUS -eq 0 ]]; then
			printf '  TOCTOU race was accepted: %s\n' "$race" >&2
			return 1
		fi
		assert_contains "$COMMAND_OUTPUT" 'confirmed Brave plan is stale' "$race race should invalidate the confirmed plan" || return 1
		assert_contains "$(<"$CALL_LOG")" 'privileged acquire' "$race race should occur only after delayed privilege acquisition" || return 1
		assert_not_contains "$(<"$CALL_LOG")" 'privileged write-stage' "$race race should stop before staging" || return 1
		assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" "$race race should not leave a pending transaction" || return 1
	done
}

test_backup_pending_and_stage_failures_precede_or_rollback_mutation() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	printf 'prior drift\n' >"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	local prior_target prior_active
	prior_target=$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")
	prior_active=$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")
	DOTFILES_TEST_BRAVE_FAIL_BACKUP=true DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'backup failure should fail apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'failed before system mutation' 'backup failure should identify the safe boundary' || return 1
	assert_eq "$prior_target" "$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")" 'backup failure should preserve prior target' || return 1
	assert_eq "$prior_active" "$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")" 'backup failure should preserve prior active receipt' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged write-stage' 'backup failure should precede staging' || return 1

	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_FAIL_RECEIPT=pending DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'pending receipt failure should fail apply' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'pending receipt failure should precede system policy mutation' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged write-stage' 'pending receipt failure should precede staging' || return 1

	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_CORRUPT_STAGE=true DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'corrupt stage should fail apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'stage failed byte, metadata, digest, or policy validation' 'stage validation failure should be explicit' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' 'corrupt stage should trigger verified rollback' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'stage rollback should restore prior target absence' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'verified stage rollback should clear pending state' || return 1
	local -a stages=("$FIXTURE_BRAVE_SYSTEM"/policies/.dotfiles-*.stage)
	if [[ -e ${stages[0]} || -L ${stages[0]} ]]; then
		printf '  corrupt transaction stage remained after rollback\n' >&2
		return 1
	fi

	local metadata_drift
	for metadata_drift in owner group mode; do
		setup_supported_brave brave-bin
		DOTFILES_TEST_BRAVE_CORRUPT_STAGE_METADATA=$metadata_drift DOTFILES_TEST_INPUT='y\n' \
			run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		assert_eq 1 "$COMMAND_STATUS" "$metadata_drift stage drift should fail apply" || return 1
		assert_contains "$COMMAND_OUTPUT" 'stage failed byte, metadata, digest, or policy validation' "$metadata_drift stage drift should fail exact metadata validation" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' "$metadata_drift stage drift should trigger verified rollback" || return 1
		assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "$metadata_drift stage rollback should restore target absence" || return 1
		assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" "$metadata_drift stage rollback should clear pending state" || return 1
	done
}

test_failures_after_publication_restore_prior_state() {
	local failure
	for failure in publish active-receipt; do
		setup_supported_brave brave-bin
		seed_active_brave_policy
		if [[ $failure == publish ]]; then
			jq . "$FIXTURE_STATE/dotfiles/brave-policy/active.json" >"$FIXTURE_STATE/dotfiles/brave-policy/active.pretty"
			mv "$FIXTURE_STATE/dotfiles/brave-policy/active.pretty" "$FIXTURE_STATE/dotfiles/brave-policy/active.json"
			chmod 0600 "$FIXTURE_STATE/dotfiles/brave-policy/active.json"
		fi
		printf 'receipt-owned drift\n' >"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
		local target_before active_before
		target_before=$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")
		active_before=$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")
		if [[ $failure == publish ]]; then
			DOTFILES_TEST_BRAVE_FAIL_AFTER=publish-stage DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		else
			DOTFILES_TEST_BRAVE_FAIL_RECEIPT=active DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		fi
		assert_eq 1 "$COMMAND_STATUS" "$failure failure should fail apply" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' "$failure failure should verify rollback" || return 1
		assert_eq "$target_before" "$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")" "$failure rollback should restore exact prior target bytes" || return 1
		assert_eq "$active_before" "$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")" "$failure rollback should restore exact prior active receipt" || return 1
		assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" "$failure rollback should clear pending state" || return 1
	done
}

test_rollback_failure_records_recovery_and_reconciles_only() {
	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_FAIL_AFTER=publish-stage DOTFILES_TEST_BRAVE_FAIL_BEFORE=remove-target DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'failed rollback should fail apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'rollback failed' 'failed rollback should be reported' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json && -f $FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json ]] || {
		printf '  rollback failure did not retain pending and recovery-required receipts\n' >&2
		return 1
	}
	[[ -f $FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json ]] || {
		printf '  rollback failure fixture should retain the partially published target\n' >&2
		return 1
	}

	DOTFILES_TEST_BRAVE_FAIL_AFTER=publish-stage DOTFILES_TEST_BRAVE_FAIL_BEFORE=remove-target DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'restored prior state should return completed outcome 0' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: recovery-completed' 'restored prior state should expose completed recovery context in the same shell' || return 1
	assert_contains "$COMMAND_OUTPUT" 'restored and verified; rerun the requested operation' 'recovery should stop after restoring prior state' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'recovery should restore prior target absence' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'successful recovery should clear pending state' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json" 'successful recovery should clear recovery-required state' || return 1
	assert_not_contains "$COMMAND_OUTPUT" 'Applied and verified shared Brave policy' 'recovery run must not continue into ordinary apply'
}

test_interrupted_apply_completion_is_idempotently_reconciled() {
	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE=pending.json DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'pending cleanup failure should report incomplete apply' || return 1
	[[ -f $FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json && -f $FIXTURE_STATE/dotfiles/brave-policy/active.json && -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json ]] || {
		printf '  interrupted apply completion state was not retained\n' >&2
		return 1
	}
	local active_before
	active_before=$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")
	DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE=pending.json run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'rerun should finish an already-published apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: ordinary' 'already-complete requested apply should remain ordinary success' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Interrupted apply completion reconciled.' 'completion reconciliation should be explicit' || return 1
	assert_not_contains "$COMMAND_OUTPUT" '[y/N]' 'safe interrupted apply completion should not require another confirmation' || return 1
	assert_eq "$active_before" "$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")" 'completion reconciliation should preserve active receipt' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'completion reconciliation should clear pending state'
}

test_remove_noop_unowned_and_stale_receipt_behaviors() {
	new_fixture
	setup_brave_fixture
	run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'absent target without receipt should be an exact remove no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'nothing to remove' 'remove no-op should be explicit' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'remove no-op should request no privilege' || return 1

	new_fixture
	setup_brave_fixture
	cp "$FIXTURE_REPO/brave/managed-policy.json" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	chmod 0644 "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	set_brave_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0644
	run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'target without receipt should block removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'never removed as repository-owned policy' 'unowned target should be preserved explicitly' || return 1
	[[ -f $FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json ]] || return 1

	new_fixture
	setup_brave_fixture
	seed_active_brave_policy
	rm -rf "$FIXTURE_BRAVE_SYSTEM"
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'stale receipt should be clearable after external browser tree removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'without recreating /etc/brave or policy' 'stale cleanup should promise and report no recreation' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM" 'stale receipt cleanup must not recreate removed system tree' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" 'stale receipt cleanup should clear active ownership' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged ' 'stale receipt cleanup should not request needless privilege'
}

test_safe_remove_restores_color_only_directory_and_preserves_canaries() {
	setup_supported_brave brave-bin
	add_brave_color_policy
	seed_brave_canaries
	seed_active_brave_policy
	local color_before canaries_before package_before
	color_before="$(stat -c '%a|%s|%Y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")"
	canaries_before=$(snapshot_brave_canaries)
	package_before=$(sha256sum "$BRAVE_PACKAGE_DB" "$BRAVE_PROVIDER_DB" "$BRAVE_OWNER_DB")
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'safe receipt-owned removal should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Managed-directory original metadata restored: 0:0 0777' 'color-only removal should restore first-deployment metadata' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Extensions may remain but are now removable' 'removal should report delayed extension effects' || return 1
	assert_contains "$COMMAND_OUTPUT" 'color.json may keep the managed indicator visible' 'removal should report retained managed indicator behavior' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'safe removal should remove only dotfiles.json' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" 'safe removal should clear active receipt' || return 1
	assert_eq 777 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'safe color-only removal should restore original 0777 mode' || return 1
	assert_eq "$color_before" "$(stat -c '%a|%s|%Y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")" 'remove should preserve color policy bytes and metadata' || return 1
	assert_eq "$canaries_before" "$(snapshot_brave_canaries)" 'remove should preserve profile, flags, themes, fonts, and Omarchy canaries' || return 1
	assert_eq "$package_before" "$(sha256sum "$BRAVE_PACKAGE_DB" "$BRAVE_PROVIDER_DB" "$BRAVE_OWNER_DB")" 'remove should preserve package/provider state' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'BROWSER EXECUTED' 'remove should never execute a browser'
}

test_remove_ignores_source_provider_and_foreign_errors_but_retains_hardening() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	add_brave_foreign_policy broken.json '{'
	local foreign_before
	foreign_before="$(stat -c '%a|%s|%Y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")"
	rm "$FIXTURE_REPO/brave/managed-policy.json"
	: >"$BRAVE_PACKAGE_DB"
	printf 'brave|%s\n' "$FIXTURE_BIN/brave" >"$BRAVE_PROVIDER_DB"
	printf '%s|other-browser\n' "$FIXTURE_BIN/brave" >"$BRAVE_OWNER_DB"
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'receipt-owned removal should not be stranded by source, provider, or foreign JSON errors' || return 1
	assert_contains "$COMMAND_OUTPUT" 'canonical source is unavailable or invalid' 'remove should report but not depend on source validity' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unsupported provider' 'remove should report unsupported providers' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Managed-directory hardening retained' 'unsafe foreign policy should prevent metadata loosening' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'receipt-owned target should still be deleted' || return 1
	assert_eq 755 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'foreign error should retain root 0755 hardening' || return 1
	assert_eq "$foreign_before" "$(stat -c '%a|%s|%Y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")" 'remove should preserve malformed foreign file exactly' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'BROWSER EXECUTED' 'unsupported browser provider should be inspected but never executed'
}

test_remove_originally_absent_directory_and_receipt_clear_rerun() {
	setup_supported_brave brave-origin-bin
	rmdir "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	rm -f "$BRAVE_METADATA_ROOT/$(brave_metadata_key /etc/brave/policies/managed)"
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'managed-absent apply fixture should succeed' || return 1
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'remove should succeed for an originally absent managed directory' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed" 'originally absent empty managed directory should be removed' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE=active.json DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'active receipt clear failure should report incomplete removal' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'receipt clear failure must not reinstall removed target' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/brave-policy/active.json && -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json ]] || {
		printf '  receipt-clear failure should retain safely rerunnable stale state\n' >&2
		return 1
	}
	DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE=active.json DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'rerun should reconcile receipt-clear failure' || return 1
	assert_contains "$COMMAND_OUTPUT" 'without recreating the policy' 'rerun should finish removal monotonically' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'rerun must not reinstall target' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" 'rerun should clear stale active receipt' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'rerun should clear pending receipt'
}

test_remove_blocks_special_target_and_malformed_receipt() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	rm "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	printf 'outside\n' >"$FIXTURE_ROOT/outside-target"
	ln -s "$FIXTURE_ROOT/outside-target" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'receipt-owned symlink target should block removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'removal requires a no-follow regular file' 'special target rejection should be explicit' || return 1
	assert_eq outside "$(<"$FIXTURE_ROOT/outside-target")" 'special target rejection should preserve symlink referent' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'special target should block before privilege' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	rm "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	printf '{\n' >"$FIXTURE_STATE/dotfiles/brave-policy/active.json"
	run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'malformed receipt should not be treated as no ownership' || return 1
	assert_contains "$COMMAND_OUTPUT" 'invalid Brave receipt state blocks removal' 'malformed state should explicitly block removal'
}

test_manage_submenu_back_and_public_argument_rejection() {
	new_fixture
	setup_brave_fixture
	DOTFILES_TEST_INPUT='4\n' run_brave_operation "$FIXTURE_ROOT" manage_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'Back should leave the Brave submenu successfully' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Manage Brave policy' 'submenu should expose its own title' || return 1
	assert_contains "$COMMAND_OUTPUT" '1. Status' 'submenu should expose Status' || return 1
	assert_contains "$COMMAND_OUTPUT" '2. Apply' 'submenu should expose Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" '3. Remove' 'submenu should expose Remove' || return 1
	local operation
	for operation in validate_brave_policy_source brave_policy_status apply_brave_policy remove_brave_policy manage_brave_policy; do
		run_brave_operation "$FIXTURE_ROOT" "$operation" /tmp/override
		assert_eq 2 "$COMMAND_STATUS" "$operation should reject path or target arguments" || return 1
	done
}

test_state_and_backup_no_follow_safety() {
	setup_supported_brave brave-bin
	local absolute_state=$FIXTURE_STATE
	FIXTURE_STATE=relative-state
	run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	FIXTURE_STATE=$absolute_state
	assert_eq 1 "$COMMAND_STATUS" 'relative XDG state home should block apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'requires an absolute XDG state home' 'relative state rejection should be explicit' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'relative state should block before inspection or privilege' || return 1

	setup_supported_brave brave-bin
	mkdir -p "$FIXTURE_STATE/dotfiles" "$FIXTURE_ROOT/outside-state"
	ln -s "$FIXTURE_ROOT/outside-state" "$FIXTURE_STATE/dotfiles/brave-policy"
	run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'symlinked Brave state directory should block apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'must be a real invoking-user-owned 0700 directory' 'state symlink should be diagnosed' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'state symlink should block before privilege' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	printf 'drift\n' >"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	mkdir -p "$FIXTURE_ROOT/outside-backups"
	ln -s "$FIXTURE_ROOT/outside-backups" "$FIXTURE_STATE/dotfiles/brave-policy/backups"
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'symlinked backup root should fail after confirmation but before system mutation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'backup root must be a real directory' 'backup no-follow failure should be explicit' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged write-stage' 'unsafe backup root should precede staging' || return 1
	assert_eq '' "$(find "$FIXTURE_ROOT/outside-backups" -mindepth 1 -print -quit)" 'unsafe backup root should not write through the symlink'
}

test_state_root_creation_race_rejects_symlink_without_chmodding_referent() {
	setup_supported_brave brave-bin
	local referent="$FIXTURE_ROOT/state-root-race-referent" before
	mkdir "$referent"
	chmod 0777 "$referent"
	before=$(stat -c '%a|%u|%g|%y' "$referent")
	DOTFILES_TEST_BRAVE_STATE_ROOT_RACE_REFERENT=$referent DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'state-root symlink race should block apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'state directory failed its safety check without metadata repair' 'state-root race should fail no-follow validation' || return 1
	[[ -L $FIXTURE_STATE/dotfiles/brave-policy ]] || {
		printf '  state-root race did not leave the injected symlink for inspection\n' >&2
		return 1
	}
	assert_eq "$before" "$(stat -c '%a|%u|%g|%y' "$referent")" 'state-root race must not chmod the symlink referent' || return 1
	assert_contains "$(<"$CALL_LOG")" 'privileged acquire' 'state-root race may occur after delayed credential acquisition' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged write-stage' 'state-root race should block before system mutation'
}

test_interrupted_remove_rejects_symlinked_transaction_backup_parent() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	seed_pending_remove_receipt
	local transaction backup_parent referent referent_before active_before pending_before
	transaction=$(jq -r '.transaction_id' "$FIXTURE_STATE/dotfiles/brave-policy/pending.json")
	backup_parent="$FIXTURE_STATE/dotfiles/brave-policy/backups/$transaction"
	referent="$FIXTURE_ROOT/transaction-backup-referent"
	mv "$backup_parent" "$referent"
	ln -s "$referent" "$backup_parent"
	rm "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	referent_before="$(stat -c '%a|%u|%g|%y' "$referent")|$(sha256sum "$referent/dotfiles.json" "$referent/active.json")"
	active_before=$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")
	pending_before=$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/pending.json")
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'interrupted remove should reject a symlinked transaction backup parent' || return 1
	assert_not_contains "$COMMAND_OUTPUT" '[y/N]' 'unsafe transaction backup parent should block before confirmation' || return 1
	assert_eq "$referent_before" "$(stat -c '%a|%u|%g|%y' "$referent")|$(sha256sum "$referent/dotfiles.json" "$referent/active.json")" 'backup-parent rejection must preserve referent metadata and bytes' || return 1
	assert_eq "$active_before" "$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")" 'backup-parent rejection should retain active receipt' || return 1
	assert_eq "$pending_before" "$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/pending.json")" 'backup-parent rejection should retain pending receipt' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'backup-parent rejection should request no privilege'
}

test_interrupted_remove_with_intact_prior_state_only_clears_pending() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	seed_pending_remove_receipt
	local target_before active_before
	target_before=$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")
	active_before=$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")
	run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'intact interrupted remove cleanup should return completed outcome 0' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: recovery-completed' 'intact interrupted remove cleanup should expose completed recovery context' || return 1
	assert_contains "$COMMAND_OUTPUT" 'had not mutated system state; pending state was cleared' 'intact pending remove should be classified' || return 1
	assert_eq "$target_before" "$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")" 'intact reconciliation should retain target' || return 1
	assert_eq "$active_before" "$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/active.json")" 'intact reconciliation should retain active receipt' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'intact reconciliation should clear only pending state' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'intact interrupted remove should need no privilege'
}

test_partial_system_mutations_roll_back_or_reconcile_monotonically() {
	setup_supported_brave brave-bin
	rmdir "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	rm -f "$BRAVE_METADATA_ROOT/$(brave_metadata_key /etc/brave/policies/managed)"
	DOTFILES_TEST_BRAVE_FAIL_AFTER=create-managed DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'failure after managed-directory creation should fail apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' 'created directory should be rolled back and verified' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed" 'rollback should remove a managed directory that was originally absent' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	chmod 0777 "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	set_brave_metadata /etc/brave/policies/managed 0 0 0777
	DOTFILES_TEST_BRAVE_FAIL_AFTER=harden-managed DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'failure after hardening should fail remove' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' 'hardening failure should restore and verify pre-transaction state' || return 1
	assert_eq 777 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'hardening rollback should restore pre-transaction directory mode' || return 1
	[[ -f $FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json ]] || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	DOTFILES_TEST_BRAVE_FAIL_AFTER=remove-target DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'failure after target deletion should leave interrupted remove state' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'post-delete failure should not reinstall target' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json ]] || {
		printf '  post-delete failure should retain pending receipt\n' >&2
		return 1
	}
	DOTFILES_TEST_BRAVE_FAIL_AFTER=remove-target DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'rerun should finish interrupted deletion without reinstalling' || return 1
	assert_contains "$COMMAND_OUTPUT" 'without recreating the policy' 'interrupted deletion should reconcile monotonically' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'reconciliation must not reinstall deleted target'
}

test_same_metadata_managed_directory_replacement_fails_and_rolls_back() {
	setup_supported_brave brave-bin
	chmod 0777 "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	set_brave_metadata /etc/brave/policies/managed 0 0 0777
	local original_identity
	original_identity=$(stat -c '%d:%i' "$FIXTURE_BRAVE_SYSTEM/policies/managed")
	DOTFILES_TEST_BRAVE_REPLACE_MANAGED_AFTER=harden-managed DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'same-metadata managed-directory replacement should fail apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'confirmed Brave state changed while securing the managed directory' 'managed-directory replacement should fail identity reinspection' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' 'managed-directory replacement should execute verified rollback' || return 1
	[[ $(stat -c '%d:%i' "$FIXTURE_BRAVE_SYSTEM/policies/managed") != "$original_identity" ]] || {
		printf '  managed-directory replacement seam did not change directory identity\n' >&2
		return 1
	}
	assert_eq 777 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'replacement rollback should restore original managed-directory mode' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'replacement rollback should restore target absence' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'verified replacement rollback should clear pending state'
}

test_target_backup_symlink_race_reads_and_retains_no_referent_bytes() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	printf 'receipt-owned drift\n' >"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	chmod 0777 "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	set_brave_metadata /etc/brave/policies/managed 0 0 0777
	local sensitive="$FIXTURE_ROOT/brave-sensitive" sensitive_before
	printf 'DO-NOT-BACK-UP-SENSITIVE-CONTENT\n' >"$sensitive"
	chmod 0640 "$sensitive"
	sensitive_before="$(stat -c '%a|%u|%g|%s|%y' "$sensitive")|$(sha256sum "$sensitive")"

	DOTFILES_TEST_BRAVE_BACKUP_RACE=true DOTFILES_TEST_BRAVE_SENSITIVE=$sensitive DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'target-to-symlink race should fail backup preparation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'no-follow Brave target backup verification failed' 'raced target should fail the no-follow copy primitive' || return 1
	[[ -L $FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json ]] || {
		printf '  backup race fixture did not leave the raced target symlink\n' >&2
		return 1
	}
	assert_eq "$sensitive_before" "$(stat -c '%a|%u|%g|%s|%y' "$sensitive")|$(sha256sum "$sensitive")" 'no-follow backup must not read through or chmod the symlink referent' || return 1
	if grep -R -Fq 'DO-NOT-BACK-UP-SENSITIVE-CONTENT' "$FIXTURE_STATE"; then
		printf '  sensitive referent bytes were retained below Brave state\n' >&2
		return 1
	fi
	assert_eq '' "$(find "$FIXTURE_STATE" -path '*/backups/*/dotfiles.json' -print -quit)" 'failed no-follow copy should retain no target backup' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'backup race should precede pending receipt publication' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged write-stage' 'backup race should precede system staging'
}

test_removal_finalization_rejects_false_success_operations() {
	setup_supported_brave brave-bin
	add_brave_color_policy
	seed_active_brave_policy
	local color_before
	color_before=$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")
	DOTFILES_TEST_BRAVE_FALSE_SUCCESS=restore-managed DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'false-success metadata restoration should fail removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'managed-directory metadata postcondition failed' 'metadata false success should fail explicit inspection' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'metadata postcondition failure must not reinstall target' || return 1
	assert_eq 755 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'false-success restoration should leave detectable incorrect metadata' || return 1
	assert_eq "$color_before" "$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/color.json")" 'metadata verification should preserve foreign color policy' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/brave-policy/active.json && -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json && -f $FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json ]] || {
		printf '  metadata postcondition failure should retain complete recovery state\n' >&2
		return 1
	}

	setup_supported_brave brave-origin-bin
	rmdir "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	rm -f "$BRAVE_METADATA_ROOT/$(brave_metadata_key /etc/brave/policies/managed)"
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'originally absent managed-directory fixture should apply' || return 1
	DOTFILES_TEST_BRAVE_FALSE_SUCCESS=remove-managed DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'false-success directory removal should fail removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'originally absent empty Brave managed directory remains' 'directory false success should fail absence verification' || return 1
	[[ -d $FIXTURE_BRAVE_SYSTEM/policies/managed ]] || return 1
	[[ -f $FIXTURE_STATE/dotfiles/brave-policy/active.json && -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json && -f $FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json ]] || {
		printf '  directory postcondition failure should retain complete recovery state\n' >&2
		return 1
	}

	setup_supported_brave brave-bin
	seed_active_brave_policy
	add_brave_foreign_policy broken.json '{'
	local broken_before
	broken_before="$(stat -c '%a|%s|%y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")"
	rm "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	chmod 0777 "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	set_brave_metadata /etc/brave/policies/managed 0 0 0777
	DOTFILES_TEST_BRAVE_FALSE_SUCCESS=harden-managed DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'false-success retained hardening should fail stale removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'managed-directory metadata postcondition failed' 'hardening false success should fail explicit inspection' || return 1
	assert_eq 777 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'false-success hardening should leave detectable unsafe metadata' || return 1
	assert_eq "$broken_before" "$(stat -c '%a|%s|%y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")" 'hardening postcondition failure should preserve malformed foreign content' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/brave-policy/active.json && -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json && -f $FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json ]] || {
		printf '  hardening postcondition failure should retain complete recovery state\n' >&2
		return 1
	}
}

test_ordinary_stale_removal_finalizes_directory_safely() {
	setup_supported_brave brave-bin
	add_brave_color_policy
	seed_active_brave_policy
	rm "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'ordinary stale removal should complete safe metadata restoration' || return 1
	assert_eq 777 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'stale color-only removal should restore original managed-directory mode' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Managed-directory original metadata restored: 0:0 0777' 'stale removal should report verified restoration' || return 1
	assert_contains "$(<"$CALL_LOG")" 'privileged restore-managed 0 0 0777' 'stale restoration should acquire narrowly scoped system privilege' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" 'verified stale restoration should clear active receipt' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	add_brave_foreign_policy broken.json '{'
	local foreign_before
	foreign_before="$(stat -c '%a|%s|%y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")"
	rm "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	chmod 0777 "$FIXTURE_BRAVE_SYSTEM/policies/managed"
	set_brave_metadata /etc/brave/policies/managed 0 0 0777
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'stale removal with unsafe foreign policy should retain hardening' || return 1
	assert_eq 755 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'stale foreign-policy removal should verify retained root 0755 hardening' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Managed-directory hardening retained' 'stale retained hardening should be reported' || return 1
	assert_eq "$foreign_before" "$(stat -c '%a|%s|%y' "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")|$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/broken.json")" 'stale finalization should preserve foreign bytes and metadata' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" 'verified retained hardening should clear active receipt'
}

test_mutating_recovery_shows_omarchy_mismatch_before_one_confirmation() {
	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE=pending.json DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'fixture should retain completed apply pending cleanup' || return 1
	local transaction stage_logical stage
	transaction=$(jq -r '.transaction_id' "$FIXTURE_STATE/dotfiles/brave-policy/pending.json")
	stage_logical="/etc/brave/policies/.dotfiles-$transaction.stage"
	stage="$FIXTURE_BRAVE_SYSTEM/policies/.dotfiles-$transaction.stage"
	cp "$FIXTURE_REPO/brave/managed-policy.json" "$stage"
	chmod 0644 "$stage"
	set_brave_metadata "$stage_logical" 0 0 0644
	: >"$CALL_LOG"
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='n\n' run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
	assert_eq 10 "$COMMAND_STATUS" 'declined stage recovery mismatch should return public decline outcome 10' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: recovery-declined' 'declined stage recovery should expose recovery-declined context' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'stage recovery should show supported Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'stage recovery should show detected Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'consent to recover despite the Omarchy mismatch' 'stage recovery confirmation should include mismatch consent' || return 1
	assert_eq 1 "$(awk '/\[y\/N\]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" 'stage recovery should ask exactly once' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'declined stage recovery should request no privilege' || return 1
	[[ -f $stage && -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json ]] || return 1
	DOTFILES_TEST_BRAVE_RACE=target DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'target race during accepted stage recovery should fail before cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'completed apply state changed before interrupted stage cleanup' 'stage recovery should report its post-privilege recheck failure' || return 1
	[[ -f $stage && -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json && -f $FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json ]] || {
		printf '  raced stage recovery should retain stage and complete recovery evidence\n' >&2
		return 1
	}

	setup_supported_brave brave-bin
	seed_active_brave_policy
	DOTFILES_TEST_BRAVE_FAIL_AFTER=remove-target DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'fixture should retain interrupted remove after target deletion' || return 1
	: >"$CALL_LOG"
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='n\n' run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context remove_brave_policy
	assert_eq 10 "$COMMAND_STATUS" 'declined metadata recovery mismatch should return public decline outcome 10' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: recovery-declined' 'declined metadata recovery should expose recovery-declined context' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'metadata recovery should show supported Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'metadata recovery should show detected Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'consent to recover despite the Omarchy mismatch' 'metadata recovery should include mismatch consent' || return 1
	assert_eq 1 "$(awk '/\[y\/N\]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" 'metadata recovery should ask exactly once' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'declined metadata recovery should request no privilege' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'declined metadata recovery must not reinstall policy'
}

test_state_only_interrupted_remove_displays_omarchy_without_privilege() {
	local version state active pending state_before
	for version in 4.0.0-1 5.1.0; do
		prepare_state_only_interrupted_remove
		state="$FIXTURE_STATE/dotfiles/brave-policy"
		active="$state/active.json"
		pending="$state/pending.json"
		state_before="$(stat -c '%n|%d|%i|%u|%g|%a|%s|%y|%z' "$active" "$pending")|$(sha256sum "$active" "$pending")"
		: >"$CALL_LOG"
		DOTFILES_TEST_OMARCHY_VERSION=$version DOTFILES_TEST_INPUT='n\n' \
			run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context remove_brave_policy
		assert_eq 10 "$COMMAND_STATUS" "$version state-only remove recovery decline should return outcome 10" || return 1
		assert_contains "$COMMAND_OUTPUT" 'context: recovery-declined' "$version state-only recovery should expose declined context" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' "$version state-only recovery should display supported Omarchy" || return 1
		assert_contains "$COMMAND_OUTPUT" "Detected Omarchy: $version" "$version state-only recovery should display detected Omarchy" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Complete this displayed Brave recovery plan, including any displayed Omarchy mismatch?' "$version state-only recovery confirmation should cover displayed Omarchy context" || return 1
		assert_eq 1 "$(awk '/\[y\/N\]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" "$version state-only recovery should ask exactly once" || return 1
		if [[ $version == 5.1.0 ]]; then
			assert_contains "$COMMAND_OUTPUT" 'consent to recover despite the Omarchy mismatch' 'mismatched state-only recovery should require explicit mismatch consent' || return 1
		else
			assert_not_contains "$COMMAND_OUTPUT" 'consent to recover despite the Omarchy mismatch' 'matching state-only recovery should not report a mismatch' || return 1
		fi
		assert_eq '' "$(<"$CALL_LOG")" "$version declined state-only recovery should request no privilege" || return 1
		assert_eq "$state_before" "$(stat -c '%n|%d|%i|%u|%g|%a|%s|%y|%z' "$active" "$pending")|$(sha256sum "$active" "$pending")" "$version decline should preserve active and pending receipt bytes, identity, and metadata" || return 1
		assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "$version decline should keep the removed target absent" || return 1
	done

	prepare_state_only_interrupted_remove
	: >"$CALL_LOG"
	DOTFILES_TEST_OMARCHY_VERSION=4.0.0-1 DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'accepted matching state-only remove recovery should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'accepted state-only recovery should display supported Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'accepted state-only recovery should display detected Omarchy' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'accepted state-only recovery should not request sudo' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'accepted state-only recovery must not recreate policy' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" 'accepted state-only recovery should clear active ownership' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'accepted state-only recovery should clear pending state'
}

test_automatic_recovery_cleanup_checks_omarchy_before_receipt_mutation() {
	local before

	prepare_completed_interrupted_apply_cleanup || return 1
	before=$(brave_active_target_snapshot)
	DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER=true DOTFILES_TEST_OMARCHY_VERSION=4.0.0-1 \
		run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'matching completed Apply cleanup should remain automatic' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'matching completed Apply cleanup should display supported Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'matching completed Apply cleanup should display detected Omarchy' || return 1
	assert_not_contains "$COMMAND_OUTPUT" '[y/N]' 'matching completed Apply cleanup should not add confirmation' || return 1
	assert_recovery_cleanup_order false true 'matching completed Apply cleanup' || return 1
	assert_eq "$before" "$(brave_active_target_snapshot)" 'matching completed Apply cleanup should preserve active target state' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'matching completed Apply cleanup should clear pending state' || return 1

	prepare_completed_interrupted_apply_cleanup || return 1
	before=$(brave_pending_cleanup_snapshot)
	DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER=true DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='n\n' \
		run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
	assert_eq 10 "$COMMAND_STATUS" 'mismatched completed Apply cleanup decline should return outcome 10' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: recovery-declined' 'mismatched completed Apply decline should expose recovery context' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'mismatched completed Apply cleanup should display detected Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'consent to recover despite the Omarchy mismatch' 'mismatched completed Apply cleanup should display mismatch consent' || return 1
	assert_contains "$COMMAND_OUTPUT" 'including any displayed Omarchy mismatch?' 'mismatched completed Apply prompt should include mismatch consent' || return 1
	assert_recovery_cleanup_order true false 'declined mismatched completed Apply cleanup' || return 1
	assert_eq "$before" "$(brave_pending_cleanup_snapshot)" 'declined mismatched completed Apply cleanup should preserve all state' || return 1

	prepare_completed_interrupted_apply_cleanup || return 1
	before=$(brave_active_target_snapshot)
	DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER=true DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'accepted mismatched completed Apply cleanup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'consent to recover despite the Omarchy mismatch' 'accepted completed Apply cleanup should display mismatch consent' || return 1
	assert_recovery_cleanup_order true true 'accepted mismatched completed Apply cleanup' || return 1
	assert_eq "$before" "$(brave_active_target_snapshot)" 'accepted mismatched completed Apply cleanup should preserve active target state' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'accepted mismatched completed Apply cleanup should clear pending state' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	seed_pending_remove_receipt
	before=$(brave_active_target_snapshot)
	: >"$CALL_LOG"
	DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER=true DOTFILES_TEST_OMARCHY_VERSION=4.0.0-1 \
		run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'matching intact Remove cleanup should remain automatic' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'matching intact Remove cleanup should display supported Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 4.0.0-1' 'matching intact Remove cleanup should display detected Omarchy' || return 1
	assert_not_contains "$COMMAND_OUTPUT" '[y/N]' 'matching intact Remove cleanup should not add confirmation' || return 1
	assert_recovery_cleanup_order false true 'matching intact Remove cleanup' || return 1
	assert_eq "$before" "$(brave_active_target_snapshot)" 'matching intact Remove cleanup should preserve active target state' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'matching intact Remove cleanup should clear pending state' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	seed_pending_remove_receipt
	before=$(brave_pending_cleanup_snapshot)
	: >"$CALL_LOG"
	DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER=true DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='n\n' \
		run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context remove_brave_policy
	assert_eq 10 "$COMMAND_STATUS" 'mismatched intact Remove cleanup decline should return outcome 10' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: recovery-declined' 'mismatched intact Remove decline should expose recovery context' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'mismatched intact Remove cleanup should display detected Omarchy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'consent to recover despite the Omarchy mismatch' 'mismatched intact Remove cleanup should display mismatch consent' || return 1
	assert_contains "$COMMAND_OUTPUT" 'including any displayed Omarchy mismatch?' 'mismatched intact Remove prompt should include mismatch consent' || return 1
	assert_recovery_cleanup_order true false 'declined mismatched intact Remove cleanup' || return 1
	assert_eq "$before" "$(brave_pending_cleanup_snapshot)" 'declined mismatched intact Remove cleanup should preserve all state' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	seed_pending_remove_receipt
	before=$(brave_active_target_snapshot)
	: >"$CALL_LOG"
	DOTFILES_TEST_BRAVE_LOG_RECOVERY_ORDER=true DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'accepted mismatched intact Remove cleanup should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'consent to recover despite the Omarchy mismatch' 'accepted intact Remove cleanup should display mismatch consent' || return 1
	assert_recovery_cleanup_order true true 'accepted mismatched intact Remove cleanup' || return 1
	assert_eq "$before" "$(brave_active_target_snapshot)" 'accepted mismatched intact Remove cleanup should preserve active target state' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'accepted mismatched intact Remove cleanup should clear pending state'
}

test_status_distinguishes_installed_consumer_parent_drift() {
	setup_supported_brave brave-bin
	rm -rf "$FIXTURE_BRAVE_SYSTEM"
	run_brave_operation "$FIXTURE_ROOT" brave_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'installed consumer with missing policy parents should make status unhealthy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'installed-consumer policy path drift' 'installed-consumer parent loss should not be called clean absence' || return 1
	assert_not_contains "$COMMAND_OUTPUT" 'Deployment state: cleanly absent.' 'installed-consumer parent drift must not report clean absence' || return 1

	new_fixture
	setup_brave_fixture
	rm -rf "$FIXTURE_BRAVE_SYSTEM"
	run_brave_operation "$FIXTURE_ROOT" brave_policy_status
	assert_eq 0 "$COMMAND_STATUS" 'missing parents after final browser uninstall should remain clean absence' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Deployment state: cleanly absent.' 'no-consumer parent absence should remain healthy'
}

test_single_install_staging_replaces_links_without_touching_referents() {
	local kind referent before
	for kind in file directory; do
		setup_supported_brave brave-bin
		referent="$FIXTURE_ROOT/write-stage-$kind-referent"
		if [[ $kind == file ]]; then
			printf 'write-stage file referent must remain unchanged\n' >"$referent"
			chmod 0640 "$referent"
			before="$(stat -c '%a|%u|%g|%s|%y' "$referent")|$(sha256sum "$referent")"
		else
			mkdir "$referent"
			printf 'write-stage directory referent sentinel\n' >"$referent/sentinel"
			before="$(stat -c '%a|%u|%g|%y' "$referent")|$(sha256sum "$referent/sentinel")"
		fi
		DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION=write-stage DOTFILES_TEST_BRAVE_STAGE_LINK_KIND=$kind \
			DOTFILES_TEST_BRAVE_STAGE_REFERENT=$referent DOTFILES_TEST_INPUT='y\n' \
			run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		assert_eq 0 "$COMMAND_STATUS" "apply should replace a pre-existing $kind stage symlink during fixed install" || return 1
		if [[ $kind == file ]]; then
			assert_eq "$before" "$(stat -c '%a|%u|%g|%s|%y' "$referent")|$(sha256sum "$referent")" 'write-stage must not change a file symlink referent' || return 1
		else
			assert_eq "$before" "$(stat -c '%a|%u|%g|%y' "$referent")|$(sha256sum "$referent/sentinel")" 'write-stage must not change a directory symlink referent' || return 1
		fi
		assert_contains "$(<"$CALL_LOG")" '/usr/bin/sudo /usr/bin/install -T -o root -g root -m 0644 -- /dev/stdin' 'stage bytes and metadata should be created by one fixed install' || return 1
	done

	for kind in file directory; do
		prepare_interrupted_restore_with_target_backup || return 1
		referent="$FIXTURE_ROOT/restore-stage-$kind-referent"
		if [[ $kind == file ]]; then
			printf 'restore-stage file referent must remain unchanged\n' >"$referent"
			chmod 0640 "$referent"
			before="$(stat -c '%a|%u|%g|%s|%y' "$referent")|$(sha256sum "$referent")"
		else
			mkdir "$referent"
			printf 'restore-stage directory referent sentinel\n' >"$referent/sentinel"
			before="$(stat -c '%a|%u|%g|%y' "$referent")|$(sha256sum "$referent/sentinel")"
		fi
		: >"$CALL_LOG"
		DOTFILES_TEST_BRAVE_STAGE_LINK_OPERATION=restore-target DOTFILES_TEST_BRAVE_STAGE_LINK_KIND=$kind \
			DOTFILES_TEST_BRAVE_STAGE_REFERENT=$referent DOTFILES_TEST_INPUT='y\n' \
			run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
		assert_eq 0 "$COMMAND_STATUS" "restore through a replaced $kind stage link should complete recovery successfully" || return 1
		assert_contains "$COMMAND_OUTPUT" 'context: recovery-completed' 'restore through a replaced stage link should expose completed recovery context' || return 1
		if [[ $kind == file ]]; then
			assert_eq "$before" "$(stat -c '%a|%u|%g|%s|%y' "$referent")|$(sha256sum "$referent")" 'restore-target must not change a file symlink referent' || return 1
		else
			assert_eq "$before" "$(stat -c '%a|%u|%g|%y' "$referent")|$(sha256sum "$referent/sentinel")" 'restore-target must not change a directory symlink referent' || return 1
		fi
		assert_contains "$(<"$CALL_LOG")" 'privileged restore-target' 'recovery fixture should exercise restore-target staging' || return 1
	done
}

test_receipt_publication_is_atomic_and_directory_safe() {
	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_RECEIPT_RACE=directory DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'receipt destination directory should fail atomic publication' || return 1
	[[ -d $FIXTURE_STATE/dotfiles/brave-policy/pending.json && ! -L $FIXTURE_STATE/dotfiles/brave-policy/pending.json ]] || {
		printf '  receipt directory race was not retained as a blocking directory\n' >&2
		return 1
	}
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'receipt directory race must precede system staging' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged write-stage' 'receipt directory race should not reach stage creation' || return 1

	setup_supported_brave brave-bin
	local referent="$FIXTURE_ROOT/receipt-directory-referent" before
	mkdir "$referent"
	printf 'receipt referent sentinel\n' >"$referent/sentinel"
	before="$(stat -c '%a|%u|%g|%y' "$referent")|$(sha256sum "$referent/sentinel")"
	DOTFILES_TEST_BRAVE_RECEIPT_RACE=symlink-directory DOTFILES_TEST_BRAVE_RECEIPT_REFERENT=$referent DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'mv -fT should replace a receipt symlink without following its directory referent' || return 1
	assert_eq "$before" "$(stat -c '%a|%u|%g|%y' "$referent")|$(sha256sum "$referent/sentinel")" 'receipt publication must preserve a symlinked directory referent' || return 1
	"$HOST_NODE_REAL" "$FIXTURE_REPO/lib/dotfiles/brave-json.mjs" receipt \
		"$FIXTURE_STATE/dotfiles/brave-policy/active.json" active "$FIXTURE_STATE/dotfiles/brave-policy" >/dev/null
}

test_incomplete_apply_preview_blocks_confirmation_and_mutation() {
	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_FAIL_PREVIEW=true DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'preview snapshot failure should fail apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'complete Brave source-to-target preview failed' 'preview failure should explain why confirmation is unavailable' || return 1
	assert_not_contains "$COMMAND_OUTPUT" '[y/N]' 'incomplete preview must not reach confirmation' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged ' 'incomplete preview must not request privilege' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy" 'incomplete preview must not create transaction state' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'incomplete preview must not publish policy'
}

test_interrupted_restore_rechecks_every_confirmed_state_family() {
	local race
	for race in pending target paths foreign backup; do
		prepare_interrupted_restore_with_target_backup || return 1
		: >"$CALL_LOG"
		DOTFILES_TEST_BRAVE_RACE=$race DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
		assert_eq 1 "$COMMAND_STATUS" "$race recovery race should abort" || return 1
		assert_contains "$COMMAND_OUTPUT" 'state or backup changed after confirmation; no restore mutation was attempted' "$race recovery race should report the pre-restore TOCTOU failure" || return 1
		assert_not_contains "$(<"$CALL_LOG")" 'privileged restore-target' "$race recovery race must precede target restoration" || return 1
		[[ -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json && -f $FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json ]] || {
			printf '  %s recovery race did not retain complete recovery evidence\n' "$race" >&2
			return 1
		}
	done
}

test_recovery_outcomes_are_caller_aware() {
	setup_supported_brave brave-bin
	DOTFILES_TEST_BRAVE_FAIL_STATE_REMOVE=pending.json DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'completed-apply fixture should retain pending state' || return 1
	run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'completed apply cleanup from Remove should return completed outcome 0' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: recovery-completed' 'completed apply cleanup from Remove should expose recovery context' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'cross-context apply cleanup should clear pending state' || return 1
	[[ -f $FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json ]] || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	DOTFILES_TEST_BRAVE_FAIL_AFTER=remove-target DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'completed-remove fixture should retain pending state' || return 1
	DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" brave_test_operation_with_context apply_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'completed remove cleanup from Apply should return completed outcome 0' || return 1
	assert_contains "$COMMAND_OUTPUT" 'context: recovery-completed' 'completed remove cleanup from Apply should expose recovery context' || return 1
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'cross-context remove cleanup must not reinstall policy' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'cross-context remove cleanup should clear pending state'
}

test_cross_filesystem_publish_failure_preserves_target_and_cleans_transaction() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	local target="$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" state="$FIXTURE_STATE/dotfiles/brave-policy"
	local target_before active_before
	printf 'receipt-owned bytes before cross-filesystem publication\n' >"$target"
	chmod 0644 "$target"
	set_brave_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0644
	target_before="$(stat -c '%d|%i|%a|%s|%y|%z' "$target")|$(sha256sum "$target")"
	active_before=$(sha256sum "$state/active.json")

	DOTFILES_TEST_BRAVE_RENAME_FAILURE=publish-stage DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" apply_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'a cross-filesystem publish rename should fail Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Rollback verified.' 'failed no-copy publication should verify rollback' || return 1
	assert_contains "$(<"$CALL_LOG")" '/usr/bin/sudo /usr/bin/mv --no-copy -fT -- /etc/brave/policies/.dotfiles-' 'the attempted publication should use fixed no-copy rename arguments' || return 1
	assert_contains "$(<"$CALL_LOG")" 'simulated cross-filesystem rename failure: publish-stage' 'the adapter should exercise the EXDEV-style failure seam' || return 1
	assert_eq "$target_before" "$(stat -c '%d|%i|%a|%s|%y|%z' "$target")|$(sha256sum "$target")" 'failed no-copy publication must preserve target inode, metadata, and bytes' || return 1
	assert_eq "$active_before" "$(sha256sum "$state/active.json")" 'failed no-copy publication should preserve active ownership bytes' || return 1
	assert_path_absent "$state/pending.json" 'failed no-copy publication should clear pending state' || return 1
	assert_path_absent "$state/recovery-required.json" 'verified no-copy rollback should leave no recovery receipt' || return 1
	local -a stages=("$FIXTURE_BRAVE_SYSTEM"/policies/.dotfiles-*.stage)
	if [[ -e ${stages[0]} || -L ${stages[0]} ]]; then
		printf '  failed no-copy publication left a transaction stage\n' >&2
		return 1
	fi
}

test_empty_regular_target_is_statused_repaired_and_removed_as_regular() {
	local operation
	for operation in apply_brave_policy remove_brave_policy; do
		setup_supported_brave brave-bin
		seed_active_brave_policy
		: >"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
		chmod 0644 "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
		set_brave_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0644

		run_brave_operation "$FIXTURE_ROOT" brave_policy_status
		assert_eq 1 "$COMMAND_STATUS" "empty receipt-owned target should be unhealthy before $operation" || return 1
		assert_contains "$COMMAND_OUTPUT" 'target: type=regular file owner=0:0 mode=0644' 'GNU stat empty-file metadata should normalize to the canonical regular-file type' || return 1
		assert_not_contains "$COMMAND_OUTPUT" 'regular empty file' 'empty-file implementation wording must not escape the metadata boundary' || return 1
		assert_contains "$COMMAND_OUTPUT" 'Deployment state: active-target drift.' 'empty regular target should remain ordinary repairable drift' || return 1

		DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" "$operation"
		assert_eq 0 "$COMMAND_STATUS" "$operation should accept an empty receipt-owned regular target" || return 1
		if [[ $operation == apply_brave_policy ]]; then
			cmp -s "$FIXTURE_REPO/brave/managed-policy.json" "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" || {
				printf '  Apply did not replace the empty regular target with canonical bytes\n' >&2
				return 1
			}
		else
			assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'Remove should delete the empty receipt-owned regular target' || return 1
		fi
	done
}

test_unreadable_receipt_owned_target_blocks_status_apply_and_remove() {
	local operation target state target_before active_before
	for operation in brave_policy_status apply_brave_policy remove_brave_policy; do
		setup_supported_brave brave-bin
		seed_active_brave_policy
		target="$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
		state="$FIXTURE_STATE/dotfiles/brave-policy"
		chmod 0000 "$target"
		set_brave_metadata /etc/brave/policies/managed/dotfiles.json 0 0 0000
		target_before=$(stat -c '%d|%i|%a|%s|%y|%z' "$target")
		active_before=$(sha256sum "$state/active.json")

		DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" "$operation"
		assert_eq 1 "$COMMAND_STATUS" "$operation should block an unreadable receipt-owned target" || return 1
		assert_contains "$COMMAND_OUTPUT" 'unreadable by the invoking user' "$operation should classify the target as unavailable rather than repairable" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Run: /usr/bin/sudo /usr/bin/chmod 0644 -- /etc/brave/policies/managed/dotfiles.json' "$operation should print the concrete permission repair command" || return 1
		assert_not_contains "$COMMAND_OUTPUT" '[y/N]' "$operation must block before confirmation" || return 1
		assert_not_contains "$COMMAND_OUTPUT" 'Plan:' "$operation must not preview a mutating plan for unreadable target bytes" || return 1
		assert_eq '' "$(<"$CALL_LOG")" "$operation must not request privilege or execute a browser" || return 1
		assert_eq "$target_before" "$(stat -c '%d|%i|%a|%s|%y|%z' "$target")" "$operation must not mutate unreadable target metadata or identity" || return 1
		assert_eq "$active_before" "$(sha256sum "$state/active.json")" "$operation must preserve active ownership state" || return 1
		assert_path_absent "$state/pending.json" "$operation must not create pending state" || return 1
		assert_path_absent "$state/recovery-required.json" "$operation must not create recovery state" || return 1
		assert_path_absent "$state/backups" "$operation must not create a backup from unreadable bytes" || return 1
		chmod 0644 "$target"
		cmp -s "$FIXTURE_REPO/brave/managed-policy.json" "$target" || {
			printf '  %s changed unreadable target bytes\n' "$operation" >&2
			return 1
		}
	done
}

test_remove_clears_state_while_hardened_and_rejects_final_replacement() {
	setup_supported_brave brave-bin
	seed_active_brave_policy
	DOTFILES_TEST_BRAVE_REPLACE_TARGET_ON_STATE_REMOVE=active.json DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 0 "$COMMAND_STATUS" 'Remove should succeed when the former race-point replacement is blocked by hardening' || return 1
	assert_contains "$(<"$CALL_LOG")" 'unprivileged-target-replacement blocked state-remove-active.json metadata=directory|0|0|0755' 'active ownership should be cleared while the managed directory is still hardened' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'unprivileged-target-replacement created state-remove-active.json' 'the former race point must not permit target replacement' || return 1
	local blocked_line restore_line
	blocked_line=$(awk '/unprivileged-target-replacement blocked state-remove-active.json/ { print NR; exit }' "$CALL_LOG")
	restore_line=$(awk '/^privileged restore-managed / { print NR; exit }' "$CALL_LOG")
	if [[ -z $blocked_line || -z $restore_line || $blocked_line -ge $restore_line ]]; then
		printf '  receipt clearing did not precede managed-directory metadata restoration\n' >&2
		return 1
	fi
	assert_path_absent "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" 'successful Remove should finish with no replacement target' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" 'successful Remove should clear active state before metadata restoration' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'successful Remove should clear transaction state before metadata restoration' || return 1
	assert_eq 777 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'successful Remove should still restore approved original metadata last' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER=restore-managed DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'Remove must fail if a replacement appears after user-writable metadata is restored' || return 1
	assert_contains "$(<"$CALL_LOG")" 'unprivileged-target-replacement created after-restore-managed metadata=directory|0|0|0777' 'the final-inspection seam should inject a permitted unprivileged replacement' || return 1
	assert_contains "$COMMAND_OUTPUT" 'removal finalization changed the target or foreign inventory' 'final inspection should diagnose the replacement' || return 1
	assert_not_contains "$COMMAND_OUTPUT" 'Removed and verified shared Brave policy' 'Remove must not report success with a finalization-time replacement' || return 1
	assert_eq 'replacement created during owned finalization' "$(<"$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")" 'failed finalization should preserve rather than blindly delete the raced replacement' || return 1
	assert_eq 755 "$(stat -c %a "$FIXTURE_BRAVE_SYSTEM/policies/managed")" 'failed finalization should re-harden the managed directory before retaining recovery state' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/brave-policy/pending.json && -f $FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json ]] || {
		printf '  raced final inspection did not retain pending recovery evidence\n' >&2
		return 1
	}
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" 'post-restoration replacement recovery should not recreate active ownership' || return 1
	local collision_before requested unreadable_before target_digest
	collision_before=$(brave_recovery_collision_snapshot)
	: >"$CALL_LOG"
	run_brave_operation "$FIXTURE_ROOT" brave_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'Status should report a readable pending-only Remove target as unowned' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Deployment state: interrupted-remove unowned target collision' 'Status should classify the pending-only Remove collision explicitly' || return 1
	assert_contains "$COMMAND_OUTPUT" 'preserve or move the unowned target manually' 'Status should print manual collision guidance' || return 1
	assert_not_contains "$COMMAND_OUTPUT" 'reconcile the interrupted transaction' 'Status should not reduce an unowned collision to generic pending recovery' || return 1
	assert_not_contains "$COMMAND_OUTPUT" '/usr/bin/chmod 0644' 'Status should not print a receipt-owned permission repair for an unowned target' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'unowned collision Status should request no privilege' || return 1
	assert_eq "$collision_before" "$(brave_recovery_collision_snapshot)" 'Status must preserve readable collision target and recovery evidence' || return 1
	for requested in apply_brave_policy remove_brave_policy; do
		: >"$CALL_LOG"
		DOTFILES_TEST_INPUT='y\n' run_brave_operation "$FIXTURE_ROOT" "$requested"
		assert_eq 1 "$COMMAND_STATUS" "$requested recovery should block an unowned replacement" || return 1
		assert_contains "$COMMAND_OUTPUT" 'interrupted Brave removal found an unowned target collision' "$requested recovery should classify the replacement as unowned" || return 1
		assert_contains "$COMMAND_OUTPUT" 'pending.json is recovery evidence and does not claim target ownership without a valid active.json' "$requested recovery should reject pending-only ownership" || return 1
		assert_contains "$COMMAND_OUTPUT" 'preserve or move the unowned target manually' "$requested recovery should print manual collision guidance" || return 1
		assert_not_contains "$COMMAND_OUTPUT" 'Recovery plan:' "$requested recovery should block before planning" || return 1
		assert_not_contains "$COMMAND_OUTPUT" '[y/N]' "$requested recovery should block before confirmation" || return 1
		assert_eq '' "$(<"$CALL_LOG")" "$requested recovery should request no privilege" || return 1
		assert_eq "$collision_before" "$(brave_recovery_collision_snapshot)" "$requested recovery must preserve target and recovery evidence bytes, identity, and metadata" || return 1
		assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/active.json" "$requested recovery must not recreate active ownership" || return 1
	done
	target_digest=$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")
	chmod 0000 "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	set_brave_metadata /etc/brave/policies/managed/dotfiles.json "$(id -u)" "$(id -g)" 0000
	unreadable_before="$(stat -c '%n|%d|%i|%u|%g|%a|%s|%y|%z' "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" "$FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json")|$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" "$FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json")|$(brave_target_metadata)"
	: >"$CALL_LOG"
	run_brave_operation "$FIXTURE_ROOT" brave_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'Status should report an unreadable pending-only Remove target as unowned' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Deployment state: interrupted-remove unowned target collision' 'unreadable pending-only Remove target should retain unowned classification' || return 1
	assert_contains "$COMMAND_OUTPUT" 'preserve or move the unowned target manually' 'unreadable unowned target should retain manual collision guidance' || return 1
	assert_not_contains "$COMMAND_OUTPUT" 'receipt-owned target unavailable' 'unreadable pending-only Remove target must not be classified as receipt-owned drift' || return 1
	assert_not_contains "$COMMAND_OUTPUT" '/usr/bin/chmod 0644' 'unreadable unowned target must not print the receipt-owned chmod repair' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'unreadable unowned collision Status should request no privilege' || return 1
	assert_eq "$unreadable_before" "$(stat -c '%n|%d|%i|%u|%g|%a|%s|%y|%z' "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json" "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" "$FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json")|$(sha256sum "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" "$FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json")|$(brave_target_metadata)" 'Status must preserve unreadable collision target and recovery evidence' || return 1
	chmod 0644 "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json"
	assert_eq "$target_digest" "$(sha256sum "$FIXTURE_BRAVE_SYSTEM/policies/managed/dotfiles.json")" 'unreadable collision Status must preserve target bytes' || return 1

	setup_supported_brave brave-bin
	seed_active_brave_policy
	DOTFILES_TEST_BRAVE_REPLACE_TARGET_AFTER=restore-managed DOTFILES_TEST_BRAVE_FALSE_SUCCESS=harden-managed DOTFILES_TEST_INPUT='y\n' \
		run_brave_operation "$FIXTURE_ROOT" remove_brave_policy
	assert_eq 1 "$COMMAND_STATUS" 'Remove should still fail if raced-finalization re-hardening cannot be verified' || return 1
	assert_contains "$COMMAND_OUTPUT" 'could not retain a coherent pending receipt for Brave removal recovery' 'failed recovery reconstruction should report its manual-repair boundary' || return 1
	assert_not_contains "$COMMAND_OUTPUT" 'Removed and verified shared Brave policy' 'failed re-hardening must not permit Remove success' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/pending.json" 'failed pending reconstruction should leave no false pending receipt' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/brave-policy/recovery-required.json" 'failed pending reconstruction must not leave an orphan recovery receipt' || return 1
}

test_brave_documentation_contract_and_relative_links() {
	new_fixture
	local guide="$FIXTURE_REPO/docs/brave.md" text link destination file_part base resolved link_count=0 id i
	local -a expected_ids=(S01 S02 S03) actual_ids=() documents=("$FIXTURE_REPO/README.md" "$FIXTURE_REPO/docs/stow.md" "$guide")
	[[ -f $guide ]] || { printf '  missing tracked Brave guide\n' >&2; return 1; }
	for ((i = 1; i <= 35; i++)); do printf -v id 'U%02d' "$i"; expected_ids+=("$id"); done
	mapfile -t actual_ids < <(awk -F'|' '/^\| [SU][0-9][0-9] \|/ { value=$2; gsub(/^ +| +$/, "", value); print value }' "$guide")
	assert_eq 38 "${#actual_ids[@]}" 'Brave guide should contain exactly 38 checklist rows' || return 1
	assert_eq "${expected_ids[*]}" "${actual_ids[*]}" 'Brave checklist rows should appear exactly once in approved source order' || return 1
	text=$(<"$guide")
	local -a clauses=(
		'`Unavailable` only when the row states an approved product reduction'
		'Chrome Labs is unavailable. Before Sync, pin Task Manager. If Send to your devices is already available without a Sync change, place it before Task Manager.'
		'After policy installs both extensions, pin AdGuard to the left of Bitwarden.'
		'Browser hides Sidebar, Wallet, Rewards, and News when they are available. Policy disables Leo. Origin hides Sidebar. Leo, Wallet, Rewards, and News are unavailable in Origin.'
		'Browser keeps supported items in this relative order: Talk, Wallet, Bookmarks, Reading List. Origin keeps Bookmarks, then Reading List.'
		'Policy disables Leo in Browser. Leo is unavailable in Origin.'
		'Backgrounds use ordinary Brave artwork. Sponsored images are off in Browser and unavailable in Origin. This is not theme management.'
		'News widget is off in Browser and unavailable in Origin.'
		'Rewards widget is off in Browser and unavailable in Origin.'
		'Talk widget is off in Browser and unavailable in Origin.'
		'Most visited is selected as the current meaning of Top Sites before shortcuts are hidden.'
		'Accepted languages are ordered `en-US`, then `en`.'
		'1. Set the new-tab selector to Homepage.'
		'2. Verify that policy manages the target as New Tab Page.'
		'3. Verify that a new tab shows Dashboard.'
		'4. Verify that Dashboard controls are active.'
		'Do not replace this sequence with the direct Dashboard selector.'
		'The wizard writes each receipt through a sibling temporary file and an atomic rename.'
		'A receipt-owned regular target can be repaired or removed only when the invoking user can read it. If the target is unreadable, Status, Apply, Remove, and recovery stop before a plan, confirmation, backup, or `sudo`.'
		'/usr/bin/sudo /usr/bin/chmod 0644 -- /etc/brave/policies/managed/dotfiles.json'
		'One confirmation covers the full transaction and any displayed Omarchy mismatch.'
		'One confirmation covers the full remove plan and any displayed Omarchy mismatch. The wizard backs up a receipt-owned regular target, removes only `dotfiles.json`, and verifies that it is absent. It clears active ownership while the managed directory is still hardened, performs any safe metadata restoration, and inspects the final target and directory state before reporting success.'
		'Only the related recovery attempt can run. The wizard does not continue with a normal operation in the same run.'
		'Recovery and stale-state cleanup do not recreate `/etc/brave` or a removed policy only to repair user state.'
		'Do not read, compare, copy, or edit these files or data stores:'
		'Do not use browser automation, developer tools, `brave://flags`, Reset settings, command-line preference overrides, an importer, or running-process command lines.'
	)
	for link in "${clauses[@]}"; do assert_contains "$text" "$link" 'Brave guide is missing an approved order, reduction, route, lifecycle, or privacy clause' || return 1; done
	for base in "${documents[@]}"; do
		while IFS= read -r link; do
			destination=${link#*](}
			destination=${destination%)}
			case $destination in http://*|https://*|mailto:*|'#'*) continue ;; esac
			file_part=${destination%%#*}
			resolved=$(readlink -m -- "$(dirname -- "$base")/$file_part") || return 1
			case $resolved in "$FIXTURE_REPO"/*) ;; *) printf '  relative documentation link escapes the repository: %s\n' "$destination" >&2; return 1 ;; esac
			[[ -f $resolved ]] || { printf '  broken relative documentation link: %s -> %s\n' "$destination" "$resolved" >&2; return 1; }
			link_count=$((link_count + 1))
		done < <(grep -oE '\[[^][]+\]\([^()]+\)' "$base" || true)
	done
	((link_count > 0)) || { printf '  documentation link audit found no relative links\n' >&2; return 1; }
}

set -e
run_test test_public_interface_and_fixed_paths 'Brave public interface and production paths are fixed'
run_test test_canonical_policy_rejects_every_shape_family 'canonical policy rejects missing, changed, extra, and mistyped values'
run_test test_duplicate_aware_parser_covers_policy_foreign_and_receipts 'duplicate-aware parser covers canonical, foreign, and receipt JSON'
run_test test_no_follow_helper_primitives_reject_symlink_inputs 'no-follow helper primitives reject symlink inputs without disclosure'
run_test test_status_is_read_only_for_clean_absence 'status is read-only for clean absence'
run_test test_no_browser_apply_returns_11_before_system_inspection 'no-browser apply returns typed outcome 11 without mutation'
run_test test_consumer_matrix_and_version_warning 'consumer matrix and package baseline warning are reported'
run_test test_unsupported_provider_matrix_blocks_before_mutation 'unsupported provider matrix blocks apply before mutation'
run_test test_status_classification_matrix 'status classifies exact, drifted, unowned, stale, malformed, pending, and recovery states'
run_test test_destination_no_follow_and_metadata_matrix 'destination no-follow and metadata safety matrix blocks apply'
run_test test_receipt_owned_regular_target_drift_is_repairable_and_removable 'receipt-owned regular content and metadata drift are repairable and removable'
run_test test_arbitrary_target_metadata_rolls_back_before_delete_and_after_publish 'arbitrary target metadata rolls back safely before deletion and after publication'
run_test test_foreign_policy_safety_matrix 'foreign policy collision, parser, type, and write-safety matrix blocks apply'
run_test test_apply_preview_publish_preservation_and_idempotence 'apply previews, publishes atomically, preserves canaries, and is idempotent'
run_test test_apply_decline_gum_root_and_mismatch_confirmation 'decline, Gum, root, and mismatch confirmation outcomes are safe'
run_test test_apply_rechecks_all_confirmed_state_families 'apply rechecks every confirmed state family after privilege acquisition'
run_test test_backup_pending_and_stage_failures_precede_or_rollback_mutation 'backup, pending, and stage failures preserve or roll back state'
run_test test_single_install_staging_replaces_links_without_touching_referents 'single-install apply and restore staging preserve file and directory link referents'
run_test test_receipt_publication_is_atomic_and_directory_safe 'receipt publication is atomic and directory-safe'
run_test test_incomplete_apply_preview_blocks_confirmation_and_mutation 'incomplete apply preview blocks confirmation and mutation'
run_test test_failures_after_publication_restore_prior_state 'post-publication failures restore prior target and receipt state'
run_test test_rollback_failure_records_recovery_and_reconciles_only 'rollback failure records recovery and recovery does not continue ordinary apply'
run_test test_interrupted_restore_rechecks_every_confirmed_state_family 'interrupted restore rechecks receipts, paths, foreign policy, target, and backups'
run_test test_interrupted_apply_completion_is_idempotently_reconciled 'interrupted apply completion reconciles idempotently'
run_test test_remove_noop_unowned_and_stale_receipt_behaviors 'remove handles no-op, unowned target, and stale receipt safely'
run_test test_safe_remove_restores_color_only_directory_and_preserves_canaries 'safe remove restores metadata and preserves all canaries'
run_test test_remove_ignores_source_provider_and_foreign_errors_but_retains_hardening 'remove survives source, provider, and foreign errors while retaining hardening'
run_test test_remove_originally_absent_directory_and_receipt_clear_rerun 'remove handles originally absent directory and receipt-clear rerun'
run_test test_remove_blocks_special_target_and_malformed_receipt 'remove blocks special targets and malformed receipts'
run_test test_manage_submenu_back_and_public_argument_rejection 'manage submenu and public argument rejection are exact'
run_test test_state_and_backup_no_follow_safety 'state and backup roots enforce absolute protected no-follow paths'
run_test test_state_root_creation_race_rejects_symlink_without_chmodding_referent 'state-root creation race rejects symlink without chmodding its referent'
run_test test_interrupted_remove_rejects_symlinked_transaction_backup_parent 'interrupted remove rejects a symlinked transaction backup parent'
run_test test_interrupted_remove_with_intact_prior_state_only_clears_pending 'intact interrupted remove clears only pending state'
run_test test_partial_system_mutations_roll_back_or_reconcile_monotonically 'partial system mutations roll back or reconcile monotonically'
run_test test_same_metadata_managed_directory_replacement_fails_and_rolls_back 'same-metadata managed-directory replacement fails and rolls back'
run_test test_target_backup_symlink_race_reads_and_retains_no_referent_bytes 'target backup symlink race reads and retains no referent bytes'
run_test test_removal_finalization_rejects_false_success_operations 'removal finalization rejects false-success privileged operations'
run_test test_ordinary_stale_removal_finalizes_directory_safely 'ordinary stale removal restores safely or retains hardening'
run_test test_mutating_recovery_shows_omarchy_mismatch_before_one_confirmation 'mutating recovery shows Omarchy mismatch before one confirmation'
run_test test_state_only_interrupted_remove_displays_omarchy_without_privilege 'state-only interrupted Remove displays Omarchy context without privilege'
run_test test_automatic_recovery_cleanup_checks_omarchy_before_receipt_mutation 'automatic recovery cleanup checks Omarchy before receipt mutation'
run_test test_recovery_outcomes_are_caller_aware 'recovery outcomes are exact and caller-aware'
run_test test_status_distinguishes_installed_consumer_parent_drift 'status distinguishes installed-consumer parent drift from final-browser absence'
run_test test_cross_filesystem_publish_failure_preserves_target_and_cleans_transaction 'cross-filesystem no-copy publication failure preserves target and cleans transaction state'
run_test test_empty_regular_target_is_statused_repaired_and_removed_as_regular 'empty regular target is statused, repaired, and removed as a regular file'
run_test test_unreadable_receipt_owned_target_blocks_status_apply_and_remove 'unreadable receipt-owned target blocks status, Apply, and Remove without mutation'
run_test test_remove_clears_state_while_hardened_and_rejects_final_replacement 'Remove clears state under hardening and rejects finalization-time replacement'
run_test test_brave_documentation_contract_and_relative_links 'Brave documentation contract and relative links are structurally complete'
finish_tests
