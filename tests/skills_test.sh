#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

test_skills_manifest_records_and_validates_approved_contract() {
	new_fixture
	configure_skill_fakes

	assert_eq '1.5.22' "$(jq -r '.installer.version' "$FIXTURE_REPO/skills.json")" 'manifest should pin the approved Skills CLI version' || return 1
	assert_eq '~/.agents/skills' "$(jq -r '.target' "$FIXTURE_REPO/skills.json")" 'manifest should declare the global user target' || return 1
	assert_eq '523374dee72d67c7b2b5f858ea0094ffda49c3ac' "$(jq -r '.sources[0].revision' "$FIXTURE_REPO/skills.json")" 'manifest should pin Humanizer evidence' || return 1
	assert_eq '068b6e0c62393147daf03530149cdce209c93da8' "$(jq -r '.sources[1].revision' "$FIXTURE_REPO/skills.json")" 'manifest should pin Matt Pocock evidence' || return 1

	local filter expected original
	original=$(<"$FIXTURE_REPO/skills.json")
	while IFS='|' read -r filter expected; do
		jq "$filter" <<<"$original" >"$FIXTURE_REPO/skills.json"
		run_operation "$FIXTURE_ROOT" install_skills
		if [[ $COMMAND_STATUS -eq 0 || $COMMAND_OUTPUT != *"$expected"* ]]; then
			printf '  invalid skill manifest was accepted: %s\n  output: %s\n' "$filter" "$COMMAND_OUTPUT" >&2
			return 1
		fi
	done <<'EOF'
.sources[0].revision = "abc"|full 40-character revision
.sources[0].url = "https://example.com/humanizer"|unsupported skill source URL
.sources[0].method = "copy"|official installation method
.sources[0].expectedSkills = 0|expected installable-skill count
.installer.version = "latest"|installer version
.target = "/tmp/skills"|global target
EOF
}

test_skills_preview_is_isolated_and_reports_every_comparison_state() {
	new_fixture
	configure_skill_fakes
	mkdir -p "$FIXTURE_HOME/.agents/skills/humanizer/references" "$FIXTURE_HOME/.agents/skills/matt-skill-01/assets"
	printf 'approved humanizer\n' >"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md"
	printf 'support file\n' >"$FIXTURE_HOME/.agents/skills/humanizer/references/style.md"
	printf 'locally changed\n' >"$FIXTURE_HOME/.agents/skills/matt-skill-01/SKILL.md"
	printf 'local payload\n' >"$FIXTURE_HOME/.agents/skills/matt-skill-01/assets/example.txt"
	ln -s /tmp/unexpected "$FIXTURE_HOME/.agents/skills/matt-skill-02"
	printf 'unrelated\n' >"$FIXTURE_HOME/.agents/skills/private-skill"

	run_operation "$FIXTURE_ROOT" install_skills

	assert_eq 2 "$COMMAND_STATUS" 'preview should stop for an explicit decision when changes or conflicts exist' || return 1
	assert_contains "$COMMAND_OUTPUT" 'UNCHANGED humanizer' 'matching official payload should be classified unchanged' || return 1
	assert_contains "$COMMAND_OUTPUT" 'CHANGE matt-skill-01' 'different official payload should be classified change' || return 1
	assert_contains "$COMMAND_OUTPUT" 'assets/example.txt' 'recursive differences should include supporting files' || return 1
	assert_contains "$COMMAND_OUTPUT" 'CONFLICT matt-skill-02: symbolic link -> /tmp/unexpected' 'unexpected links should report type and target' || return 1
	assert_contains "$COMMAND_OUTPUT" 'ADD matt-skill-03' 'absent official payload should be classified add' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Install pinned global skills in the Dotfiles wizard' 'preview should identify the wizard recovery action' || return 1
	assert_eq 'unrelated' "$(<"$FIXTURE_HOME/.agents/skills/private-skill")" 'preview should leave unrelated skills untouched' || return 1
	assert_eq 'locally changed' "$(<"$FIXTURE_HOME/.agents/skills/matt-skill-01/SKILL.md")" 'preview should not change the real global target' || return 1
	local calls
	calls=$(<"$CALL_LOG")
	assert_contains "$calls" 'skills@1.5.22 add' 'preview should invoke the pinned official installer' || return 1
	assert_contains "$calls" 'TELEMETRY=1' 'official installer telemetry should be disabled' || return 1
	if [[ $(global_skill_installer_calls) -ne 0 ]]; then
		printf '  unapproved preview must not invoke an installer in the real HOME\n' >&2
		return 1
	fi

	rm "$FIXTURE_HOME/.agents/skills/matt-skill-02"
	: >"$CALL_LOG"
	run_operation "$FIXTURE_ROOT" install_skills
	assert_eq 2 "$COMMAND_STATUS" 'an operation-level mutation plan should require explicit approval' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Decision required: review and approve the plan' 'the approval boundary should be actionable' || return 1
	if [[ $(global_skill_installer_calls) -ne 0 ]]; then
		printf '  a conflict-free unapproved plan must not invoke a global installer\n' >&2
		return 1
	fi
}

test_skills_approved_install_backs_up_replaces_and_verifies() {
	new_fixture
	configure_skill_fakes
	mkdir -p "$FIXTURE_HOME/.agents/skills/humanizer"
	printf 'local humanizer\n' >"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md"
	printf 'unrelated\n' >"$FIXTURE_HOME/.agents/skills/private-skill"

	run_operation "$FIXTURE_ROOT" install_skills --yes

	assert_eq 0 "$COMMAND_STATUS" 'approved pinned skill installation should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup created:' 'a changed skill should expose its XDG-state backup path' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Verified: humanizer:' 'successful replacement should print its verification path' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Verified: matt-skill-35:' 'every discovered official skill should be verified' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Restart the agent or reload its skills' 'success should remind the user to reload skills' || return 1
	assert_eq 'approved humanizer' "$(<"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md")" 'approved official payload should replace changed content' || return 1
	assert_eq 'support file' "$(<"$FIXTURE_HOME/.agents/skills/humanizer/references/style.md")" 'official supporting files should be retained' || return 1
	assert_eq 'unrelated' "$(<"$FIXTURE_HOME/.agents/skills/private-skill")" 'approved installation should leave unrelated skills untouched' || return 1
	local -a backups=("$FIXTURE_STATE"/dotfiles/skill-backups/*/humanizer/SKILL.md)
	assert_eq 1 "${#backups[@]}" 'changed skill should have one timestamped backup' || return 1
	assert_eq 'local humanizer' "$(<"${backups[0]}")" 'backup should preserve replaced payload' || return 1
}

test_skills_expected_count_drift_stops_before_global_install() {
	new_fixture
	configure_skill_fakes
	DOTFILES_TEST_SKILL_COUNT_DRIFT=true run_operation "$FIXTURE_ROOT" install_skills --yes

	assert_eq 1 "$COMMAND_STATUS" 'official discovery count drift should fail before approval is applied' || return 1
	assert_contains "$COMMAND_OUTPUT" 'expected 35 installable skills, discovered 34' 'count drift should identify expected and actual discovery' || return 1
	if [[ $(global_skill_installer_calls) -ne 0 ]]; then
		printf '  count drift must stop before global installer invocation\n' >&2
		return 1
	fi
}

test_skills_failed_replacement_restores_and_preserves_earlier_success() {
	new_fixture
	configure_skill_fakes
	mkdir -p "$FIXTURE_HOME/.agents/skills/matt-skill-01/assets"
	printf 'local matt\n' >"$FIXTURE_HOME/.agents/skills/matt-skill-01/SKILL.md"
	printf 'local payload\n' >"$FIXTURE_HOME/.agents/skills/matt-skill-01/assets/example.txt"
	DOTFILES_TEST_SKILL_VERIFY_FAILURE=true run_operation "$FIXTURE_ROOT" install_skills --yes

	assert_eq 1 "$COMMAND_STATUS" 'verification mismatch should fail the skill batch' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Verified: humanizer:' 'earlier collection success should be retained and reported' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Verification failed: matt-skill-01:' 'failed exact comparison should name its path' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Restored: matt-skill-01 from' 'failed replacement should report restoration evidence' || return 1
	assert_eq 'local matt' "$(<"$FIXTURE_HOME/.agents/skills/matt-skill-01/SKILL.md")" 'failed changed payload should be restored from backup' || return 1
	assert_eq 'local payload' "$(<"$FIXTURE_HOME/.agents/skills/matt-skill-01/assets/example.txt")" 'failed supporting files should also be restored' || return 1
	assert_eq 'approved humanizer' "$(<"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md")" 'earlier successful collection should remain installed' || return 1
	if [[ -e $FIXTURE_HOME/.agents/skills/matt-skill-02 ]]; then
		printf '  failed collection additions should be removed during bounded recovery\n' >&2
		return 1
	fi
}

test_skills_installer_failure_restores_unchanged_and_changed_source_skills() {
	new_fixture
	configure_skill_fakes
	mkdir -p "$FIXTURE_HOME/.agents/skills/matt-skill-01/assets" "$FIXTURE_HOME/.agents/skills/matt-skill-02/assets"
	printf 'approved matt-skill-01\n' >"$FIXTURE_HOME/.agents/skills/matt-skill-01/SKILL.md"
	printf 'payload matt-skill-01\n' >"$FIXTURE_HOME/.agents/skills/matt-skill-01/assets/example.txt"
	printf 'local changed matt\n' >"$FIXTURE_HOME/.agents/skills/matt-skill-02/SKILL.md"
	printf 'local changed payload\n' >"$FIXTURE_HOME/.agents/skills/matt-skill-02/assets/example.txt"
	local unchanged_before changed_before
	unchanged_before=$(sha256sum "$FIXTURE_HOME/.agents/skills/matt-skill-01/SKILL.md" "$FIXTURE_HOME/.agents/skills/matt-skill-01/assets/example.txt")
	changed_before=$(sha256sum "$FIXTURE_HOME/.agents/skills/matt-skill-02/SKILL.md" "$FIXTURE_HOME/.agents/skills/matt-skill-02/assets/example.txt")

	DOTFILES_TEST_SKILL_INSTALL_FAILURE=true run_operation "$FIXTURE_ROOT" install_skills --yes

	assert_eq 1 "$COMMAND_STATUS" 'official installer failure should fail the current source' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Backup created:'" $FIXTURE_STATE" 'every potentially rewritten existing skill should expose backup evidence' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Restored: matt-skill-01 from' 'an originally unchanged skill mutated before failure should be restored' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Restored: matt-skill-02 from' 'an originally changed skill should also be restored' || return 1
	assert_eq "$unchanged_before" "$(sha256sum "$FIXTURE_HOME/.agents/skills/matt-skill-01/SKILL.md" "$FIXTURE_HOME/.agents/skills/matt-skill-01/assets/example.txt")" 'unchanged source skill should be restored exactly' || return 1
	assert_eq "$changed_before" "$(sha256sum "$FIXTURE_HOME/.agents/skills/matt-skill-02/SKILL.md" "$FIXTURE_HOME/.agents/skills/matt-skill-02/assets/example.txt")" 'changed source skill should be restored exactly' || return 1
	assert_eq 'approved humanizer' "$(<"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md")" 'earlier successful source should remain installed' || return 1
	if [[ -e $FIXTURE_HOME/.agents/skills/matt-skill-03 ]]; then
		printf '  source rollback should remove every failed ADD skill\n' >&2
		return 1
	fi
	local -a unchanged_backups=("$FIXTURE_STATE"/dotfiles/skill-backups/*/matt-skill-01/SKILL.md)
	assert_eq 1 "${#unchanged_backups[@]}" 'originally unchanged source skill should be backed up before installer invocation' || return 1
}

test_skills_requires_distinct_omarchy_mismatch_approval_before_mutation() {
	new_fixture
	configure_skill_fakes
	mkdir -p "$FIXTURE_HOME/.agents/skills/humanizer"
	printf 'local humanizer\n' >"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md"
	local before
	before=$(sha256sum "$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md")

	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 run_operation "$FIXTURE_ROOT" install_skills --yes

	assert_eq 1 "$COMMAND_STATUS" 'Omarchy mismatch should reject skill mutation without distinct approval' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'skill planning should report the supported Omarchy version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'skill planning should report the detected Omarchy version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Install pinned global skills' 'mismatch rejection should provide the distinct wizard action' || return 1
	assert_eq "$before" "$(sha256sum "$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md")" 'mismatch rejection should preserve global skill content' || return 1
	if [[ -d $FIXTURE_STATE/dotfiles/skill-backups || $(global_skill_installer_calls) -ne 0 ]]; then
		printf '  mismatch rejection must happen before backup and global installer mutation\n' >&2
		return 1
	fi

	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 run_operation "$FIXTURE_ROOT" install_skills --yes --allow-omarchy-mismatch
	assert_eq 0 "$COMMAND_STATUS" 'distinct mismatch approval should permit verified skill installation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Approval: Omarchy mismatch accepted by --allow-omarchy-mismatch' 'approved mismatch should be explicit before mutation' || return 1
	assert_eq 'approved humanizer' "$(<"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md")" 'approved mismatch should complete official installation' || return 1
}

test_skills_skips_unchanged_only_source_when_another_source_mutates() {
	new_fixture
	configure_skill_fakes
	mkdir -p "$FIXTURE_HOME/.agents/skills/humanizer/references"
	printf 'approved humanizer\n' >"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md"
	printf 'support file\n' >"$FIXTURE_HOME/.agents/skills/humanizer/references/style.md"
	touch -d '2001-01-01 00:00:00 UTC' "$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md" "$FIXTURE_HOME/.agents/skills/humanizer/references/style.md"
	local before
	before=$(stat -c '%n|%s|%Y|%a' "$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md" "$FIXTURE_HOME/.agents/skills/humanizer/references/style.md")

	run_operation "$FIXTURE_ROOT" install_skills --yes

	assert_eq 0 "$COMMAND_STATUS" 'a later mutating source should install successfully' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Source unchanged: humanizer (official global installer skipped)' 'plan execution should report the skipped unchanged-only source' || return 1
	assert_eq 0 "$(global_skill_installer_calls_for_source 0)" 'unchanged-only source should not invoke its global official installer' || return 1
	assert_eq 1 "$(global_skill_installer_calls_for_source 1)" 'mutating source should invoke its global official installer once' || return 1
	assert_eq "$before" "$(stat -c '%n|%s|%Y|%a' "$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md" "$FIXTURE_HOME/.agents/skills/humanizer/references/style.md")" 'unchanged-only source files should not be rewritten or touched' || return 1
	local -a humanizer_backups=("$FIXTURE_STATE"/dotfiles/skill-backups/*/humanizer)
	if [[ -e ${humanizer_backups[0]} ]]; then
		printf '  skipped unchanged-only source should not be backed up\n' >&2
		return 1
	fi
}

test_skills_restores_unrelated_installer_damage() {
	local failure
	for failure in modify delete add; do
		new_fixture
		configure_skill_fakes
		mkdir -p "$FIXTURE_HOME/.agents/skills"
		printf 'private original\n' >"$FIXTURE_HOME/.agents/skills/private-skill"

		DOTFILES_TEST_SKILL_UNRELATED_FAILURE=$failure run_operation "$FIXTURE_ROOT" install_skills --yes

		assert_eq 1 "$COMMAND_STATUS" "$failure of an unrelated skill should fail initial installation" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Safety verification failed:' "$failure should identify the unrelated safety violation" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Restored unrelated global skills from' "$failure should report unrelated recovery evidence" || return 1
		assert_eq 'private original' "$(<"$FIXTURE_HOME/.agents/skills/private-skill")" "$failure should restore unrelated content exactly" || return 1
		if [[ -e $FIXTURE_HOME/.agents/skills/rogue-skill || -e $FIXTURE_HOME/.agents/skills/humanizer ]]; then
			printf '  %s should remove unexpected and failed-source additions\n' "$failure" >&2
			return 1
		fi
		rm -rf "$FIXTURE_ROOT"
	done
}

test_skills_protects_other_manifest_source_during_install() {
	new_fixture
	configure_skill_fakes
	mkdir -p "$FIXTURE_HOME/.agents/skills/humanizer/references"
	printf 'approved humanizer\n' >"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md"
	printf 'support file\n' >"$FIXTURE_HOME/.agents/skills/humanizer/references/style.md"

	DOTFILES_TEST_SKILL_UNRELATED_FAILURE=other-source run_operation "$FIXTURE_ROOT" install_skills --yes

	assert_eq 1 "$COMMAND_STATUS" 'a source installer changing another manifest source should fail' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Safety verification failed:' 'cross-source damage should fail the unrelated safety boundary' || return 1
	assert_eq 'approved humanizer' "$(<"$FIXTURE_HOME/.agents/skills/humanizer/SKILL.md")" 'the other manifest source should be restored exactly' || return 1
	if [[ -e $FIXTURE_HOME/.agents/skills/matt-skill-01 ]]; then
		printf '  failed source additions should be removed after cross-source damage\n' >&2
		return 1
	fi
}

test_skills_update_no_change_is_read_only() {
	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	local manifest_before
	manifest_before=$(<"$FIXTURE_REPO/skills.json")
	cp -a "$FIXTURE_HOME/.agents/skills" "$FIXTURE_ROOT/skills-before"

	DOTFILES_TEST_SKILL_UPDATE_NO_CHANGE=true run_operation "$FIXTURE_ROOT" update_skills

	assert_eq 0 "$COMMAND_STATUS" 'an update with no upstream revision changes should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No upstream skill updates are available.' 'no-change output should be explicit' || return 1
	assert_eq "$manifest_before" "$(<"$FIXTURE_REPO/skills.json")" 'no-change discovery should preserve the exact manifest' || return 1
	diff -r "$FIXTURE_ROOT/skills-before" "$FIXTURE_HOME/.agents/skills" >/dev/null || {
		printf '  no-change discovery should preserve every global skill\n' >&2
		return 1
	}
	if [[ -d $FIXTURE_STATE/dotfiles/skill-update-backups || $(global_skill_installer_calls) -ne 0 ]]; then
		printf '  no-change discovery must not back up or globally install skills\n' >&2
		return 1
	fi
}

test_skills_update_preview_reports_complete_plan_without_mutation() {
	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	printf 'unrelated\n' >"$FIXTURE_HOME/.agents/skills/private-skill"
	local manifest_before
	manifest_before=$(<"$FIXTURE_REPO/skills.json")
	cp -a "$FIXTURE_HOME/.agents/skills" "$FIXTURE_ROOT/skills-before"

	run_operation "$FIXTURE_ROOT" update_skills

	assert_eq 2 "$COMMAND_STATUS" 'an operation-level update plan should require explicit approval' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Source update: matt-pocock-skills' 'preview should name the changed source' || return 1
	assert_contains "$COMMAND_OUTPUT" 'fffffff Add and revise official skills' 'preview should include upstream commit summaries' || return 1
	assert_contains "$COMMAND_OUTPUT" '+upstream source change' 'preview should include the source diff' || return 1
	assert_contains "$COMMAND_OUTPUT" 'CANDIDATE CHANGE matt-skill-01' 'preview should classify changed installer output' || return 1
	assert_contains "$COMMAND_OUTPUT" 'CANDIDATE REMOVE matt-skill-35' 'preview should classify removed installer output' || return 1
	assert_contains "$COMMAND_OUTPUT" 'CANDIDATE ADD matt-skill-36' 'preview should classify added installer output' || return 1
	assert_contains "$COMMAND_OUTPUT" 'INSTALLED CHANGE matt-skill-01' 'preview should compare proposed output with installed skills' || return 1
	assert_contains "$COMMAND_OUTPUT" 'INSTALLED REMOVE matt-skill-35' 'preview should show installed skills removed by the update' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Decision required: review and approve the complete plan' 'preview should expose the approval boundary' || return 1
	assert_eq "$manifest_before" "$(<"$FIXTURE_REPO/skills.json")" 'declined update should preserve the exact manifest' || return 1
	diff -r "$FIXTURE_ROOT/skills-before" "$FIXTURE_HOME/.agents/skills" >/dev/null || {
		printf '  declined update should preserve every global skill\n' >&2
		return 1
	}
	if [[ -d $FIXTURE_STATE/dotfiles/skill-update-backups || $(global_skill_installer_calls) -ne 0 ]]; then
		printf '  declined update must not back up or globally install skills\n' >&2
		return 1
	fi
}

test_skills_update_rejects_ownership_collision_with_unchanged_source() {
	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	local manifest_before
	manifest_before=$(<"$FIXTURE_REPO/skills.json")
	cp -a "$FIXTURE_HOME/.agents/skills" "$FIXTURE_ROOT/skills-before"

	DOTFILES_TEST_SKILL_UPDATE_COLLISION=true run_operation "$FIXTURE_ROOT" update_skills --yes

	assert_eq 1 "$COMMAND_STATUS" 'a proposed name owned by an unchanged source should reject the update' || return 1
	assert_contains "$COMMAND_OUTPUT" 'proposed official skill name is owned by multiple sources: humanizer' 'collision output should identify the contested skill' || return 1
	assert_contains "$COMMAND_OUTPUT" 'humanizer and matt-pocock-skills' 'collision output should identify both proposed owners' || return 1
	assert_eq "$manifest_before" "$(<"$FIXTURE_REPO/skills.json")" 'ownership rejection should preserve the exact manifest' || return 1
	diff -r "$FIXTURE_ROOT/skills-before" "$FIXTURE_HOME/.agents/skills" >/dev/null || {
		printf '  ownership rejection should preserve every global skill\n' >&2
		return 1
	}
	if [[ -d $FIXTURE_STATE/dotfiles/skill-update-backups || $(global_skill_installer_calls) -ne 0 ]]; then
		printf '  ownership rejection must precede backups and global installation\n' >&2
		return 1
	fi
}

test_skills_update_applies_membership_and_count_atomically() {
	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	printf 'unrelated\n' >"$FIXTURE_HOME/.agents/skills/private-skill"

	run_operation "$FIXTURE_ROOT" update_skills --yes

	assert_eq 0 "$COMMAND_STATUS" 'an approved update should succeed' || return 1
	assert_eq 'ffffffffffffffffffffffffffffffffffffffff' "$(jq -r '.sources[1].revision' "$FIXTURE_REPO/skills.json")" 'approved revision should be stored' || return 1
	assert_eq 36 "$(jq '.sources[1].expectedSkills' "$FIXTURE_REPO/skills.json")" 'approved discovery count should be stored' || return 1
	assert_eq 'updated matt-skill-01' "$(<"$FIXTURE_HOME/.agents/skills/matt-skill-01/SKILL.md")" 'changed candidate should be installed' || return 1
	[[ ! -e $FIXTURE_HOME/.agents/skills/matt-skill-35 ]] || {
		printf '  removed candidate should be absent after update\n' >&2
		return 1
	}
	assert_eq 'approved matt-skill-37' "$(<"$FIXTURE_HOME/.agents/skills/matt-skill-37/SKILL.md")" 'new candidate should be installed' || return 1
	assert_eq 'unrelated' "$(<"$FIXTURE_HOME/.agents/skills/private-skill")" 'unrelated global skills should remain untouched' || return 1
	local -a manifest_backups=("$FIXTURE_STATE"/dotfiles/skill-update-backups/*/skills.json)
	local -a removed_backups=("$FIXTURE_STATE"/dotfiles/skill-update-backups/*/skills/matt-skill-35/SKILL.md)
	assert_eq 1 "${#manifest_backups[@]}" 'the old manifest should be preserved before mutation' || return 1
	assert_eq 1 "${#removed_backups[@]}" 'every affected existing skill, including removals, should be preserved' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Verified collection: matt-pocock-skills (36 skills)' 'success should report exact collection verification' || return 1
	assert_eq 0 "$(global_skill_installer_calls_for_source 0)" 'an unchanged source should never invoke its global official installer' || return 1
	assert_eq 1 "$(global_skill_installer_calls_for_source 1)" 'the official installer should apply the approved checkout once' || return 1
}

test_skills_update_requires_distinct_omarchy_mismatch_approval() {
	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	local manifest_before
	manifest_before=$(<"$FIXTURE_REPO/skills.json")
	cp -a "$FIXTURE_HOME/.agents/skills" "$FIXTURE_ROOT/skills-before"

	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 run_operation "$FIXTURE_ROOT" update_skills --yes

	assert_eq 1 "$COMMAND_STATUS" 'approved update plan should still require mismatch approval' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Update pinned global skills' 'mismatch output should identify the distinct wizard action' || return 1
	assert_eq "$manifest_before" "$(<"$FIXTURE_REPO/skills.json")" 'mismatch rejection should preserve the manifest' || return 1
	diff -r "$FIXTURE_ROOT/skills-before" "$FIXTURE_HOME/.agents/skills" >/dev/null || return 1
	if [[ -d $FIXTURE_STATE/dotfiles/skill-update-backups || $(global_skill_installer_calls) -ne 0 ]]; then
		printf '  mismatch rejection must precede transactional backup and installation\n' >&2
		return 1
	fi

	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 run_operation "$FIXTURE_ROOT" update_skills --yes --allow-omarchy-mismatch
	assert_eq 0 "$COMMAND_STATUS" 'distinct mismatch approval should permit the complete update' || return 1
}

assert_failed_skills_update_rolls_back_completely() {
	local failure_name=$1
	assert_eq 1 "$COMMAND_STATUS" "$failure_name should fail the update transaction" || return 1
	assert_eq "$MANIFEST_BEFORE" "$(<"$FIXTURE_REPO/skills.json")" "$failure_name should restore the exact old manifest" || return 1
	diff -r "$FIXTURE_ROOT/skills-before" "$FIXTURE_HOME/.agents/skills" >/dev/null || {
		printf '  %s should restore every changed, unchanged, and removed member and remove additions\n' "$failure_name" >&2
		return 1
	}
	assert_contains "$COMMAND_OUTPUT" 'Rolled back manifest and all affected global skills.' "$failure_name should report complete rollback" || return 1
}

test_skills_update_install_failure_rolls_back_complete_transaction() {
	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	MANIFEST_BEFORE=$(<"$FIXTURE_REPO/skills.json")
	cp -a "$FIXTURE_HOME/.agents/skills" "$FIXTURE_ROOT/skills-before"

	DOTFILES_TEST_SKILL_INSTALL_FAILURE=true run_operation "$FIXTURE_ROOT" update_skills --yes

	assert_contains "$COMMAND_OUTPUT" 'official global installer failed' 'installer failure should identify its cause' || return 1
	assert_failed_skills_update_rolls_back_completely 'installer failure'
}

test_skills_update_verification_failure_rolls_back_complete_transaction() {
	new_fixture
	configure_skill_update_fakes
	seed_current_global_skills
	MANIFEST_BEFORE=$(<"$FIXTURE_REPO/skills.json")
	cp -a "$FIXTURE_HOME/.agents/skills" "$FIXTURE_ROOT/skills-before"

	DOTFILES_TEST_SKILL_VERIFY_FAILURE=true run_operation "$FIXTURE_ROOT" update_skills --yes

	assert_contains "$COMMAND_OUTPUT" 'Verification failed: matt-skill-01' 'verification failure should identify the mismatched skill' || return 1
	assert_failed_skills_update_rolls_back_completely 'verification failure'
}

test_skills_update_restores_unrelated_installer_damage() {
	local failure
	for failure in modify delete add other-source; do
		new_fixture
		configure_skill_update_fakes
		seed_current_global_skills
		printf 'private original\n' >"$FIXTURE_HOME/.agents/skills/private-skill"
		MANIFEST_BEFORE=$(<"$FIXTURE_REPO/skills.json")
		cp -a "$FIXTURE_HOME/.agents/skills" "$FIXTURE_ROOT/skills-before"

		DOTFILES_TEST_SKILL_UNRELATED_FAILURE=$failure run_operation "$FIXTURE_ROOT" update_skills --yes

		assert_contains "$COMMAND_OUTPUT" 'Safety verification failed:' "$failure should identify the unrelated update safety violation" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Restored unrelated global skills from' "$failure should report unrelated update recovery evidence" || return 1
		assert_failed_skills_update_rolls_back_completely "$failure of an unrelated skill" || return 1
		rm -rf "$FIXTURE_ROOT"
	done
}

set -e
run_test test_skills_manifest_records_and_validates_approved_contract 'skills manifest records and validates the approved contract'
run_test test_skills_preview_is_isolated_and_reports_every_comparison_state 'skills preview is isolated and reports every comparison state'
run_test test_skills_approved_install_backs_up_replaces_and_verifies 'skills approved install backs up, replaces, and verifies'
run_test test_skills_expected_count_drift_stops_before_global_install 'skills expected-count drift stops before global installation'
run_test test_skills_failed_replacement_restores_and_preserves_earlier_success 'skills failed replacement restores and preserves earlier success'
run_test test_skills_installer_failure_restores_unchanged_and_changed_source_skills 'skills installer failure restores unchanged and changed source skills'
run_test test_skills_requires_distinct_omarchy_mismatch_approval_before_mutation 'skills requires distinct Omarchy mismatch approval before mutation'
run_test test_skills_skips_unchanged_only_source_when_another_source_mutates 'skills skips unchanged-only source when another source mutates'
run_test test_skills_restores_unrelated_installer_damage 'skills restores unrelated installer modification, deletion, and addition'
run_test test_skills_protects_other_manifest_source_during_install 'skills protects another manifest source during per-source installation'
run_test test_skills_update_no_change_is_read_only 'skills update no-change discovery is read-only'
run_test test_skills_update_preview_reports_complete_plan_without_mutation 'skills update preview reports the complete plan without mutation'
run_test test_skills_update_rejects_ownership_collision_with_unchanged_source 'skills update rejects ownership collision with an unchanged source'
run_test test_skills_update_applies_membership_and_count_atomically 'skills update applies membership and count atomically'
run_test test_skills_update_requires_distinct_omarchy_mismatch_approval 'skills update requires distinct Omarchy mismatch approval'
run_test test_skills_update_install_failure_rolls_back_complete_transaction 'skills update installer failure rolls back the complete transaction'
run_test test_skills_update_verification_failure_rolls_back_complete_transaction 'skills update verification failure rolls back the complete transaction'
run_test test_skills_update_restores_unrelated_installer_damage 'skills update restores unrelated installer modification, deletion, and addition'
finish_tests
