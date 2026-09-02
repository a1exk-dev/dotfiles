#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

assert_not_contains() {
	local value=$1 needle=$2 message=$3
	[[ $value != *"$needle"* ]] || { printf '  %s\n  unexpected: %s\n' "$message" "$needle" >&2; return 1; }
}

apply_policy() {
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
}

test_source_validation() {
	new_fixture
	run_power_policy_operation "$FIXTURE_ROOT" validate_power_policy_sources
	assert_eq 0 "$COMMAND_STATUS" 'canonical sources should validate' || return 1
	assert_contains "$COMMAND_OUTPUT" 'UPower source: valid' 'UPower validation should be reported' || return 1
	printf '[UPower]\nCriticalPowerAction=PowerOff\n' >"$FIXTURE_REPO/power-policy/upower.conf"
	run_power_policy_operation "$FIXTURE_ROOT" validate_power_policy_sources
	assert_eq 1 "$COMMAND_STATUS" 'changed canonical source should be rejected'
	assert_contains "$(<"$FIXTURE_REPO/lib/dotfiles/power-policy.sh")" 'LC_ALL=C stat -c' 'power-policy metadata inspection should force the C locale'
}

test_status_is_read_only_for_absent_active_conflict_pending_and_malformed_state() {
	new_fixture
	setup_power_policy_fixture
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 0 "$COMMAND_STATUS" 'absent policy status should be readable' || return 1
	assert_contains "$COMMAND_OUTPUT" 'UPower source: digest=' 'Status should report the canonical source digest' || return 1
	assert_contains "$COMMAND_OUTPUT" 'UPower service: current=disabled|inactive prior=absent' 'Status should report no prior service without lifecycle evidence' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Inhibit delay (us): 15000000' 'Status should report live logind inhibit delay' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy" 'Status must not create state' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged' 'Status must not acquire privilege' || return 1
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'Apply should establish active status' || return 1
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 0 "$COMMAND_STATUS" 'active policy status should be healthy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Required action: none; laptop power policy is exact and active.' 'status should recognize exact ownership' || return 1
	assert_contains "$COMMAND_OUTPUT" 'UPower service: current=enabled|active prior=disabled|inactive' 'Status should report the active receipt service original' || return 1
	printf '[UPower]\nCriticalPowerAction=PowerOff\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'managed drift should be a status conflict' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Apply is available to repair managed-target drift; Remove is blocked.' 'Status should route safe managed-target byte drift to Apply repair' || return 1
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'Apply should repair safe managed-target byte drift' || return 1
	cmp -s "$FIXTURE_REPO/power-policy/upower.conf" "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" || return 1
	rm -rf "$FIXTURE_STATE/dotfiles/laptop-power-policy"
	mkdir -p "$FIXTURE_STATE/dotfiles/laptop-power-policy"
	chmod 0700 "$FIXTURE_STATE/dotfiles/laptop-power-policy"
	printf '{"schema_version":1}\n' >"$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json"
	chmod 0600 "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'malformed pending receipt should fail closed'
	new_fixture
	setup_power_policy_fixture
	printf '[UPower]\nPercentageAction=7.0\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	set_power_policy_metadata /etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf 0 0 0644
	apply_policy
	local backup
	backup=$(jq -r '.targets[] | select(.name == "upower") | .original.backup_path' "$FIXTURE_STATE/dotfiles/laptop-power-policy/active.json")
	rm -f -- "$backup"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'missing active backup should invalidate Status' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Active receipt: invalid' 'Status must not call missing active evidence absent' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Pending receipt: absent' 'invalid active evidence must not mislabel an absent pending receipt' || return 1
	assert_contains "$COMMAND_OUTPUT" 'do not Apply or Remove' 'invalid lifecycle evidence should block ordinary operations' || return 1
	run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'missing active backup should block Apply' || return 1
	new_fixture
	setup_power_policy_fixture
	mkdir -p "$FIXTURE_STATE/dotfiles/laptop-power-policy"
	chmod 0700 "$FIXTURE_STATE/dotfiles/laptop-power-policy"
	printf '{"kind":"active","kind":"pending"}\n' >"$FIXTURE_STATE/dotfiles/laptop-power-policy/active.json"
	chmod 0600 "$FIXTURE_STATE/dotfiles/laptop-power-policy/active.json"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'duplicate receipt members should fail closed'
}

test_apply_preflight_rejections() {
	local case_name file value expected=1
	while IFS='|' read -r case_name file value expected; do
		new_fixture
		setup_power_policy_fixture
		case $case_name in
			unsafe-target)
				printf '[UPower]\nCriticalPowerAction=PowerOff\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
				set_power_policy_metadata /etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf 0 0 0600
				;;
			bad-sleep) printf '%s\n' "$value" >"$POWER_POLICY_RUNTIME/sleep-lock" ;;
			*) printf '%s\n' "$value" >"$POWER_POLICY_RUNTIME/$file" ;;
		esac
		run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
		assert_eq "$expected" "$COMMAND_STATUS" "$case_name should reject Apply before mutation" || return 1
		assert_not_contains "$(<"$CALL_LOG")" 'privileged acquire' "$case_name should not acquire privilege" || return 1
	done <<'EOF'
unsupported|omarchy-version|3.9.0|1
battery|battery|no|11
hibernation|hibernation|no|11
can-hibernate|can-hibernate|no|1
bad-sleep|||1
unsafe-target|||1
unsafe-parent|target-parent-safe|unsafe|1
EOF
}

test_declined_apply_has_no_writes_or_privilege() {
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_INPUT='n\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 10 "$COMMAND_STATUS" 'declined Apply should have its named outcome' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: apply laptop power policy' 'decline should receive the complete plan' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy" 'decline must not create state' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged acquire' 'decline must not prompt for sudo'
}

test_clean_apply_and_exact_noop_with_service_repair() {
	new_fixture
	setup_power_policy_fixture
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'clean Apply should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Applied and verified laptop power policy.' 'Apply should verify completion' || return 1
	cmp -s "$FIXTURE_REPO/power-policy/upower.conf" "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" || return 1
	assert_eq 'enabled|active' "$(<"$POWER_POLICY_RUNTIME/upower-service")" 'Apply should enable and start UPower' || return 1
	: >"$CALL_LOG"
	run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'exact Apply should succeed without work' || return 1
	assert_contains "$COMMAND_OUTPUT" 'already exact and active' 'exact Apply should explain the no-op' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged' 'exact no-op should not use privilege' || return 1
	printf 'disabled|inactive\n' >"$POWER_POLICY_RUNTIME/upower-service"
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'ordinary service drift should be repaired' || return 1
	assert_eq 'enabled|active' "$(<"$POWER_POLICY_RUNTIME/upower-service")" 'repair should restore active UPower'
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'Remove should restore the first Apply service state' || return 1
	assert_eq 'disabled|inactive' "$(<"$POWER_POLICY_RUNTIME/upower-service")" 'active receipt must preserve disabled|inactive from the first Apply'
}

test_apply_backs_up_only_ordinary_root_owned_target() {
	new_fixture
	setup_power_policy_fixture
	local original=$'[UPower]\nPercentageAction=7.0\n'
	printf '%s' "$original" >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	set_power_policy_metadata /etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf 0 0 0644
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'root:root 0644 target should be backed up and replaced' || return 1
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'Remove should restore the backed-up original' || return 1
	assert_eq "${original%$'\n'}" "$(<"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf")" 'original bytes should return exactly'
	assert_eq 644 "$(stat -c %a "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf")" 'restored target should be root:root 0644 scoped'
}

test_empty_root_owned_target_is_canonical() {
	new_fixture
	setup_power_policy_fixture
	local target=$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf
	: >"$target"
	chmod 0644 "$target"
	set_power_policy_metadata /etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf 0 0 0644
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_stat_metadata "$target"
	assert_eq 0 "$COMMAND_STATUS" 'metadata helper should inspect an empty target' || return 1
	assert_contains "$COMMAND_OUTPUT" 'regular file|' 'metadata helper should normalize GNU stat empty-file wording' || return 1
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'empty root-owned target should be backed up and replaced' || return 1
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'Remove should restore an empty original target' || return 1
	[[ -f $target && ! -s $target ]] || return 1
}

test_later_effective_override_blocks_apply() {
	new_fixture
	setup_power_policy_fixture
	add_power_policy_drop_in upower 99-foreign.conf $'[UPower]\nCriticalPowerAction=PowerOff\n'
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'blocking precedence should make Status conflicting' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Required action: conflict detected' 'Status must not recommend Apply through blocking precedence' || return 1
	new_fixture
	setup_power_policy_fixture
	add_power_policy_drop_in upower 99-foreign.conf $'[UPower]\nCriticalPowerAction=PowerOff\n'
	run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'later effective override should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'later competing drop-in' 'conflict should name effective precedence' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged acquire' 'effective conflict should precede privilege'
	new_fixture
	setup_power_policy_fixture
	add_power_policy_drop_in upower 99-foreign.conf $'[UPower]\nCriticalPowerAction=PowerOff\n'
	add_power_policy_drop_in upower zz.conf $'[UPower]\nCriticalPowerAction=Hibernate\n'
	run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'invalid UPower drop-in names must not mask valid later overrides' || return 1
	new_fixture
	setup_power_policy_fixture
	add_power_policy_drop_in logind 99-delay.conf $'[Login]\nInhibitDelayMaxSec=22\n'
	printf '22000000\n' >"$POWER_POLICY_RUNTIME/inhibit-delay-us"
	printf '22000000\n' >"$POWER_POLICY_RUNTIME/configured-inhibit-delay-us"
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'later inhibit-delay configuration should be preserved by Apply' || return 1
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 0 "$COMMAND_STATUS" 'preserved inhibit delay should remain healthy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Inhibit delay (us): 22000000' 'Status should report the observed later inhibit delay'
	new_fixture
	setup_power_policy_fixture
	add_power_policy_drop_in logind 99-delay.conf $'[Login]\nInhibitDelayMaxSec=1min 30s\n'
	printf '90000000\n' >"$POWER_POLICY_RUNTIME/inhibit-delay-us"
	printf '90000000\n' >"$POWER_POLICY_RUNTIME/configured-inhibit-delay-us"
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'valid compound inhibit delay should not wedge Apply' || return 1
	assert_eq 90000000 "$(<"$POWER_POLICY_RUNTIME/inhibit-delay-us")" 'Apply should preserve the observed compound inhibit delay' || return 1
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'valid compound inhibit delay should not wedge Remove' || return 1
	assert_eq 90000000 "$(<"$POWER_POLICY_RUNTIME/inhibit-delay-us")" 'Remove should preserve the observed compound inhibit delay'
}

test_command_failures_roll_back() {
	local failure
	for failure in backup:upower stage:logind restart; do
		new_fixture
		setup_power_policy_fixture
		if [[ $failure == backup:upower ]]; then
			printf '[UPower]\nPercentageAction=7.0\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
			set_power_policy_metadata /etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf 0 0 0644
		fi
		DOTFILES_TEST_POWER_POLICY_FAIL_OPERATION=$failure DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
		assert_eq 1 "$COMMAND_STATUS" "$failure failure should fail Apply" || return 1
		if [[ $failure == backup:upower ]]; then
			assert_eq $'[UPower]\nPercentageAction=7.0' "$(<"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf")" 'backup failure should leave the original target untouched' || return 1
		else
			assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" "$failure rollback should restore UPower absence" || return 1
		fi
		assert_eq Sleep "$(<"$POWER_POLICY_RUNTIME/upower-critical-action")" "$failure rollback should restore stock UPower action" || return 1
		assert_eq 'suspend||ignore' "$(<"$POWER_POLICY_RUNTIME/logind-runtime")" "$failure rollback should restore stock lid tuple" || return 1
		assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json" "$failure with proven rollback should clear pending"
	done
}

test_apply_rolls_back_wrong_default_inhibit_delay() {
	new_fixture
	setup_power_policy_fixture
	printf '[Login]\n' >"$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf"
	printf '16000000\n' >"$POWER_POLICY_RUNTIME/restart-delay-us"
	apply_policy
	assert_eq 1 "$COMMAND_STATUS" 'changed default inhibit delay should fail Apply postconditions' || return 1
	assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" 'wrong default delay should roll back UPower' || return 1
	assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf.d/90-dotfiles-laptop-power.conf" 'wrong default delay should roll back logind' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json" 'proven rollback should clear pending evidence'
}

test_interrupted_apply_recovers_only_the_prior_state() {
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_POWER_POLICY_INTERRUPT='publish:upower' DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 88 "$COMMAND_STATUS" 'adapter interruption should end after a real publish' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json ]] || return 1
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'interrupted first Apply should require recovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'UPower service: current=disabled|inactive prior=disabled|inactive' 'Status should show pending first-Apply rollback service prior' || return 1
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'next invocation should recover' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovered interrupted laptop power-policy transaction' 'recovery should stop ordinary Apply' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json" 'recovery should clear proven pending evidence' || return 1
	assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" 'recovery should restore prior absence'
	assert_eq Sleep "$(<"$POWER_POLICY_RUNTIME/upower-critical-action")" 'recovery should restore the stock UPower action' || return 1
	assert_eq 'suspend||ignore' "$(<"$POWER_POLICY_RUNTIME/logind-runtime")" 'recovery should restore the stock lid tuple'
}

test_pending_backup_blocks_recovery_before_privilege() {
	new_fixture
	setup_power_policy_fixture
	printf '[UPower]\nPercentageAction=7.0\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	set_power_policy_metadata /etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf 0 0 0644
	DOTFILES_TEST_POWER_POLICY_INTERRUPT='publish:upower' DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 88 "$COMMAND_STATUS" 'interrupted Apply should retain pending rollback evidence' || return 1
	local backup
	backup=$(jq -r '.targets[] | select(.name == "upower") | .prior.backup_path' "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json")
	printf 'changed\n' >"$backup"
	: >"$CALL_LOG"
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'changed pending rollback backup should block recovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'invalid pending receipt or backup' 'pending backup failure should be explicit' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged acquire' 'invalid pending backup must block recovery before privilege'
}

test_prepared_pending_recovers_without_system_mutation() {
	new_fixture
	setup_power_policy_fixture
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_test_write_prepared_pending
	assert_eq 0 "$COMMAND_STATUS" 'normal transaction builder should write a prepared pending receipt' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json ]] || return 1
	: >"$CALL_LOG"
	run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'public Apply should complete prepared recovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovered prepared laptop power-policy transaction' 'prepared recovery should report completion' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json" 'prepared recovery should clean pending evidence' || return 1
	assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" 'prepared recovery should not mutate UPower' || return 1
	assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf.d/90-dotfiles-laptop-power.conf" 'prepared recovery should not mutate logind' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged' 'prepared recovery should not acquire privilege or reload services'
}

test_terminal_receipt_cleanup_recovery() {
	new_fixture
	setup_power_policy_fixture
	make_fake rm '
for argument in "$@"; do
		if [[ $argument == */laptop-power-policy/pending.json ]]; then
			kill -KILL "$PPID"
			exit 0
		fi
done
exec /usr/bin/rm "$@"'
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	[[ $COMMAND_STATUS -ne 0 ]] || { printf '  Apply should stop after active publication when pending cleanup exits\n' >&2; return 1; }
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/active.json && -f $FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json ]] || return 1
	rm "$FIXTURE_BIN/rm"
	: >"$CALL_LOG"
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'public Apply should complete terminal Apply recovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Completed Apply recovery' 'terminal Apply recovery should report receipt cleanup' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json" 'terminal Apply recovery should only remove pending evidence' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/active.json ]] || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged' 'terminal Apply recovery should not mutate the system' || return 1
	new_fixture
	setup_power_policy_fixture
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'Apply should establish ownership before terminal Remove recovery' || return 1
	make_fake rm '
for argument in "$@"; do
		if [[ $argument == */laptop-power-policy/pending.json ]]; then
			kill -KILL "$PPID"
			exit 0
		fi
done
exec /usr/bin/rm "$@"'
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	[[ $COMMAND_STATUS -ne 0 ]] || { printf '  Remove should stop after active cleanup when pending cleanup exits\n' >&2; return 1; }
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/active.json" 'terminal Remove state should have no active receipt' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json ]] || return 1
	rm "$FIXTURE_BIN/rm"
	: >"$CALL_LOG"
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'public Remove should complete terminal Remove recovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Completed Remove recovery' 'terminal Remove recovery should report receipt cleanup' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json" 'terminal Remove recovery should remove pending evidence'
	assert_not_contains "$(<"$CALL_LOG")" 'privileged' 'terminal Remove recovery should not mutate the system'
}

test_mutating_recovery_preflight_blocks_invalid_or_changed_inputs() {
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_POWER_POLICY_INTERRUPT='publish:upower' DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 88 "$COMMAND_STATUS" 'interrupted Apply should create a mutating recovery case' || return 1
	ln -s ../UPower.conf "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/99-foreign.conf"
	: >"$CALL_LOG"
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'unreadable foreign configuration should block recovery preflight' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged acquire' 'invalid recovery configuration should block before privilege' || return 1
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_POWER_POLICY_INTERRUPT='publish:upower' DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 88 "$COMMAND_STATUS" 'interrupted Apply should retain recovery evidence' || return 1
	: >"$CALL_LOG"
	DOTFILES_TEST_POWER_POLICY_MUTATE_AFTER_ACQUIRE=foreign-upower DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'changed recovery inputs after confirmation should block rollback mutation' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json ]] || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged remove' 'changed recovery inputs should stop before target rollback'
}

test_status_routes_active_pending_and_ineligible_states_truthfully() {
	new_fixture
	setup_power_policy_fixture
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'Apply should establish active evidence for source-independent Status routing' || return 1
	rm "$FIXTURE_REPO/power-policy/upower.conf"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'missing source with active ownership should be nonhealthy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'UPower source: invalid' 'Status should inspect and identify the invalid source independently' || return 1
	assert_contains "$COMMAND_OUTPUT" 'logind source: digest=' 'Status should still inspect the valid canonical source' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Remove remains available' 'active ownership should keep Remove available when Apply source validation fails' || return 1
	new_fixture
	setup_power_policy_fixture
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'Apply should establish active evidence before absent-target Status repair' || return 1
	rm "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'absent active target should require repair' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Apply is available to repair managed-target drift; Remove is blocked.' 'Status should route an absent receipt-owned target to Apply repair' || return 1
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'Apply should repair an absent receipt-owned target' || return 1
	cmp -s "$FIXTURE_REPO/power-policy/upower.conf" "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" || return 1
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_POWER_POLICY_INTERRUPT='publish:upower' DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 88 "$COMMAND_STATUS" 'interrupted Apply should create pending recovery evidence' || return 1
	rm "$FIXTURE_REPO/power-policy/upower.conf"
	printf 'no\n' >"$POWER_POLICY_RUNTIME/hibernation"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'pending recovery Status should be nonhealthy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'recovery is available' 'pending recovery should outrank source and hibernation Apply eligibility' || return 1
	new_fixture
	setup_power_policy_fixture
	printf 'no\n' >"$POWER_POLICY_RUNTIME/hibernation"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'missing hibernation should make receiptless Status nonhealthy' || return 1
	assert_contains "$COMMAND_OUTPUT" 'laptop prerequisites are ineligible' 'receiptless Status should distinguish unavailable hibernation from a conflict' || return 1
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_POWER_POLICY_INTERRUPT='publish:upower' DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 88 "$COMMAND_STATUS" 'interrupted Apply should create a pending drift case' || return 1
	printf '[UPower]\nCriticalPowerAction=PowerOff\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'unrecognized pending target drift should be conflicting' || return 1
	assert_contains "$COMMAND_OUTPUT" 'pending recovery is blocked' 'Status should not offer recovery for an unrecognized pending target state'
}

test_trailing_state_home_apply_then_remove() {
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_XDG_STATE_HOME="$FIXTURE_STATE/" DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'trailing state-home slash should not block Apply' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/active.json ]] || return 1
	DOTFILES_TEST_XDG_STATE_HOME="$FIXTURE_STATE/" DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'trailing state-home slash should not block Remove' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/active.json" 'Remove should use the normalized state path'
}

test_remove_is_source_independent_and_restores_service() {
	new_fixture
	setup_power_policy_fixture
	printf 'enabled|active\n' >"$POWER_POLICY_RUNTIME/upower-service"
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'Apply should establish ownership' || return 1
	rm "$FIXTURE_REPO/power-policy/upower.conf" "$FIXTURE_REPO/power-policy/logind.conf"
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'Remove should not need current canonical sources' || return 1
	assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" 'Remove should restore original absence' || return 1
	assert_eq 'enabled|active' "$(<"$POWER_POLICY_RUNTIME/upower-service")" 'Remove should restore service state' || return 1
	assert_eq Sleep "$(<"$POWER_POLICY_RUNTIME/upower-critical-action")" 'raw Auto fallback should restore to native Sleep' || return 1
	assert_eq 'suspend||ignore' "$(<"$POWER_POLICY_RUNTIME/logind-runtime")" 'Remove should restore packaged logind defaults instead of stale managed lid values' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/active.json" 'Remove should clear active receipt'
}

test_remove_no_receipt_noop_and_managed_drift_conflict() {
	new_fixture
	setup_power_policy_fixture
	run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'receiptless absence should be a no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'nothing to remove' 'no-op should be clear' || return 1
	apply_policy
	printf '[UPower]\nCriticalPowerAction=PowerOff\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'changed managed target should block Remove' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Remove is blocked' 'drift should be explicit'
}

test_interrupted_remove_recovers_the_active_deployment() {
	new_fixture
	setup_power_policy_fixture
	apply_policy
	DOTFILES_TEST_POWER_POLICY_INTERRUPT='remove:upower' DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 88 "$COMMAND_STATUS" 'adapter interruption should end after target removal' || return 1
	run_power_policy_operation "$FIXTURE_ROOT" power_policy_status
	assert_eq 1 "$COMMAND_STATUS" 'interrupted Remove should require recovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'UPower service: current=enabled|active prior=enabled|active' 'Status should show pending Remove rollback service prior' || return 1
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'next Remove should recover the active deployment only' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovered interrupted laptop power-policy transaction' 'recovery should require a later Remove run' || return 1
	cmp -s "$FIXTURE_REPO/power-policy/upower.conf" "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" || return 1
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/active.json ]]
}

test_lock_and_revalidation_refuse_mutation() {
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_POWER_POLICY_MUTATE_AFTER_ACQUIRE=source DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'post-sudo source drift should refuse Apply' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy" 'revalidation failure should not create state' || return 1
	assert_contains "$(<"$CALL_LOG")" 'lock exclusive' 'Apply should acquire the single lock'
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_POWER_POLICY_MUTATE_AFTER_ACQUIRE=foreign-upower DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'post-confirmation foreign drop-in should refuse Apply' || return 1
	assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf" 'foreign conflict must stop before managed target mutation' || return 1
	new_fixture
	setup_power_policy_fixture
	DOTFILES_TEST_POWER_POLICY_MUTATE_AFTER_ACQUIRE=delay DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'post-confirmation inhibit-delay change should refuse the approved Apply snapshot' || return 1
	assert_path_absent "$FIXTURE_POWER_POLICY_SYSTEM/systemd/logind.conf.d/90-dotfiles-laptop-power.conf" 'changed inhibit delay must stop before managed target mutation' || return 1
	new_fixture
	setup_power_policy_fixture
	printf '[UPower]\nPercentageAction=7.0\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	set_power_policy_metadata /etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf 0 0 0644
	apply_policy
	assert_eq 0 "$COMMAND_STATUS" 'Apply should create active backup evidence' || return 1
	: >"$CALL_LOG"
	DOTFILES_TEST_POWER_POLICY_MUTATE_AFTER_ACQUIRE=backup DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" remove_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'changed original backup after confirmation should refuse Remove' || return 1
	assert_contains "$(<"$CALL_LOG")" 'privileged acquire' 'Remove should acquire privilege before its final recheck' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged backup upower' 'changed backup must stop before fixed target mutation'
}

test_path_safety_rejects_state_and_fixed_parent_symlinks() {
	new_fixture
	setup_power_policy_fixture
	mkdir -p "$FIXTURE_ROOT/state-target"
	mkdir -p "$FIXTURE_STATE/dotfiles"
	rm -rf "$FIXTURE_STATE/dotfiles"
	ln -s "$FIXTURE_ROOT/state-target" "$FIXTURE_STATE/dotfiles"
	run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'symlinked state component should block Apply' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged acquire' 'unsafe state path should stop before privilege' || return 1
	new_fixture
	setup_power_policy_fixture
	mv "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d" "$FIXTURE_POWER_POLICY_SYSTEM/UPower/real-dropins"
	ln -s real-dropins "$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d"
	run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'symlinked fixed target parent should block Apply' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged acquire' 'unsafe fixed parent should stop before privilege' || return 1
	new_fixture
	setup_power_policy_fixture
	mkdir -p "$FIXTURE_STATE/dotfiles/laptop-power-policy" "$FIXTURE_ROOT/backup-target"
	chmod 0700 "$FIXTURE_STATE/dotfiles/laptop-power-policy"
	ln -s "$FIXTURE_ROOT/backup-target" "$FIXTURE_STATE/dotfiles/laptop-power-policy/backups"
	apply_policy
	assert_eq 1 "$COMMAND_STATUS" 'symlinked backup directory should block Apply' || return 1
	assert_not_contains "$(<"$CALL_LOG")" 'privileged backup' 'unsafe backup path should stop before target mutation'
}

test_failed_rollback_retains_pending_then_recovers() {
	new_fixture
	setup_power_policy_fixture
	printf '[UPower]\nPercentageAction=7.0\n' >"$FIXTURE_POWER_POLICY_SYSTEM/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf"
	set_power_policy_metadata /etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf 0 0 0644
	DOTFILES_TEST_POWER_POLICY_FAIL_OPERATION='publish:logind,restore:upower' DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 1 "$COMMAND_STATUS" 'failed rollback should fail Apply' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json ]] || return 1
	assert_contains "$COMMAND_OUTPUT" 'pending.json and transaction backups are retained' 'failed rollback should name retained recovery evidence' || return 1
	DOTFILES_TEST_INPUT='y\n' run_power_policy_operation "$FIXTURE_ROOT" apply_power_policy
	assert_eq 0 "$COMMAND_STATUS" 'pending recovery should succeed when dependency works' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/laptop-power-policy/pending.json" 'completed recovery should clean pending evidence'
}

set -e
run_test test_source_validation 'source validation'
run_test test_status_is_read_only_for_absent_active_conflict_pending_and_malformed_state 'read-only Status states'
run_test test_apply_preflight_rejections 'Apply preflight rejection table'
run_test test_declined_apply_has_no_writes_or_privilege 'declined Apply has no writes or privilege'
run_test test_clean_apply_and_exact_noop_with_service_repair 'clean Apply, exact no-op, and service repair'
run_test test_apply_backs_up_only_ordinary_root_owned_target 'ordinary root-owned target backup and restoration'
run_test test_empty_root_owned_target_is_canonical 'empty root-owned target backup and restoration'
run_test test_later_effective_override_blocks_apply 'later override conflict'
run_test test_command_failures_roll_back 'backup, stage, and service failures roll back'
run_test test_apply_rolls_back_wrong_default_inhibit_delay 'default inhibit-delay postcondition rollback'
run_test test_interrupted_apply_recovers_only_the_prior_state 'interrupted Apply recovery'
run_test test_pending_backup_blocks_recovery_before_privilege 'pending backup recovery validation'
run_test test_prepared_pending_recovers_without_system_mutation 'prepared pending recovery'
run_test test_terminal_receipt_cleanup_recovery 'terminal receipt cleanup recovery'
run_test test_mutating_recovery_preflight_blocks_invalid_or_changed_inputs 'mutating recovery preflight'
run_test test_status_routes_active_pending_and_ineligible_states_truthfully 'truthful Status routing'
run_test test_remove_is_source_independent_and_restores_service 'source-independent Remove restoration'
run_test test_remove_no_receipt_noop_and_managed_drift_conflict 'Remove no-op and drift conflict'
run_test test_interrupted_remove_recovers_the_active_deployment 'interrupted Remove recovery'
run_test test_lock_and_revalidation_refuse_mutation 'lock and revalidation refusal'
run_test test_path_safety_rejects_state_and_fixed_parent_symlinks 'state and fixed-parent path safety'
run_test test_failed_rollback_retains_pending_then_recovers 'failed rollback pending recovery'
run_test test_trailing_state_home_apply_then_remove 'trailing state-home normalization'
finish_tests
