#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

seed_wallpaper_assignment() {
	local theme=$1 format=${2-PNG} extension=${3-png} color=${4-#2457a7}
	local image="$FIXTURE_REPO/wallpapers/inbox/$theme.$extension"
	make_wallpaper_image "$format" "$image" "$color" || return 1
	assign_wallpaper_fixture "$image" "$theme" "$extension"
}

test_first_apply_materializes_regular_files_and_clone_independent_receipt() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local installed missing installed_digest missing_digest installed_live missing_live receipt
	installed=$(seed_wallpaper_assignment catppuccin PNG png '#224466') || return 1
	missing=$(seed_wallpaper_assignment portable-missing JPEG jpg '#884422') || return 1
	installed_digest=${installed##*/} installed_digest=${installed_digest%%.*}
	missing_digest=${missing##*/} missing_digest=${missing_digest%%.*}
	installed_live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$installed_digest.png"
	missing_live="$FIXTURE_CONFIG/omarchy/backgrounds/portable-missing/$missing_digest.jpg"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'first wallpaper Apply should succeed' || return 1
	for live in "$installed_live" "$missing_live"; do
		[[ -f $live && ! -L $live ]] || { printf '  Apply did not materialize a regular live file: %s\n' "$live" >&2; return 1; }
	done
	assert_contains "$COMMAND_OUTPUT" 'portable-missing' 'Apply should report an assignment whose theme is locally missing' || return 1
	assert_contains "$COMMAND_OUTPUT" 'dormant' 'missing-theme report should explain dormant deployment' || return 1
	receipt="$FIXTURE_STATE/dotfiles/wallpapers/active.json"
	[[ -f $receipt && ! -L $receipt ]] || return 1
	assert_eq 600 "$(stat -c %a "$receipt")" 'active receipt should be private' || return 1
	assert_eq 700 "$(stat -c %a "${receipt%/*}")" 'wallpaper state root should be private' || return 1
	assert_eq 2 "$(jq '.targets | length' "$receipt")" 'receipt should own both assignments' || return 1
	if grep -Fq "$FIXTURE_REPO" "$receipt"; then
		printf '  active receipt contains clone-specific repository path\n' >&2
		return 1
	fi
	assert_eq "catppuccin/$installed_digest.png" "$(jq -r '.targets[0].path' "$receipt")" 'receipt targets should be sorted relative inventory'
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/backups" 'successful Apply should clean transaction backups'
}

test_exact_apply_noop_preserves_live_and_receipt_metadata_without_prompt() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live receipt before
	assignment=$(seed_wallpaper_assignment catppuccin WEBP webp) || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'fixture first Apply should succeed' || return 1
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.webp"
	receipt="$FIXTURE_STATE/dotfiles/wallpapers/active.json"
	before=$(stat -c '%n|%d|%i|%s|%y|%z' "$live" "$receipt")
	DOTFILES_TEST_INPUT='n\n' run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'exact Apply should skip without consuming confirmation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'exact no-op' 'exact Apply should report no-op preservation' || return 1
	assert_eq "$before" "$(stat -c '%n|%d|%i|%s|%y|%z' "$live" "$receipt")" 'exact no-op should preserve target and receipt metadata'
}

test_apply_adopts_exact_unowned_match_but_blocks_different_foreign_target() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live before
	assignment=$(seed_wallpaper_assignment catppuccin PNG png) || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	mkdir -p "${live%/*}"
	cp "$assignment" "$live"
	before=$(stat -c '%d|%i|%s|%y|%z' "$live")
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'exact unowned target should be adopted' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Adopt exact unowned target' 'adoption should be explicit in the plan' || return 1
	assert_eq "$before" "$(stat -c '%d|%i|%s|%y|%z' "$live")" 'adoption should not republish exact target' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png) || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	mkdir -p "${live%/*}"
	printf 'foreign bytes\n' >"$live"
	local foreign_before
	foreign_before=$(sha256sum "$live")
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'different unowned target should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unowned target conflict' 'foreign conflict should be explicit' || return 1
	assert_eq "$foreign_before" "$(sha256sum "$live")" 'conflict should not mutate foreign target' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/active.json" 'conflict should not infer ownership'
}

test_apply_converges_additions_and_stale_removals_while_preserving_unrelated_files() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	local first first_digest first_live second second_digest second_live unrelated
	first=$(seed_wallpaper_assignment one PNG png '#112233') || return 1
	first_digest=${first##*/} first_digest=${first_digest%%.*}
	first_live="$FIXTURE_CONFIG/omarchy/backgrounds/one/$first_digest.png"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'initial convergence fixture should apply' || return 1
	unrelated="$FIXTURE_CONFIG/omarchy/backgrounds/one/personal.jpg"
	printf 'personal background\n' >"$unrelated"
	rm "$first"
	second=$(seed_wallpaper_assignment two GIF gif '#667788') || return 1
	second_digest=${second##*/} second_digest=${second_digest%%.*}
	second_live="$FIXTURE_CONFIG/omarchy/backgrounds/two/$second_digest.gif"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'Apply should converge changed library assignments' || return 1
	assert_path_absent "$first_live" 'convergence should remove unchanged stale receipt target' || return 1
	[[ -f $second_live && ! -L $second_live ]] || return 1
	assert_eq 'personal background' "$(<"$unrelated")" 'convergence should preserve unrelated backgrounds' || return 1
	assert_eq "two/$second_digest.gif" "$(jq -r '.targets[0].path' "$FIXTURE_STATE/dotfiles/wallpapers/active.json")" 'receipt should converge to current inventory' || return 1
	assert_eq '["two"]' "$(jq -c '.created_directories' "$FIXTURE_STATE/dotfiles/wallpapers/active.json")" 'receipt should drop stale created-directory ownership' || return 1
	[[ -f $unrelated ]] || { printf '  created-directory cleanup removed unrelated content\n' >&2; return 1; }
}

test_apply_retains_unchanged_operation_created_directories_during_expansion() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	local first first_digest first_live first_identity second second_digest second_live
	first=$(seed_wallpaper_assignment one PNG png '#123456') || return 1
	first_digest=${first##*/} first_digest=${first_digest%%.*}
	first_live="$FIXTURE_CONFIG/omarchy/backgrounds/one/$first_digest.png"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'expansion fixture baseline should succeed' || return 1
	first_identity=$(stat -c '%d|%i|%s|%y|%z' "$first_live")
	second=$(seed_wallpaper_assignment two PNG png '#654321') || return 1
	second_digest=${second##*/} second_digest=${second_digest%%.*}
	second_live="$FIXTURE_CONFIG/omarchy/backgrounds/two/$second_digest.png"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'adding a theme should retain an unchanged operation-created sibling directory' || return 1
	assert_eq "$first_identity" "$(stat -c '%d|%i|%s|%y|%z' "$first_live")" 'expansion should preserve unchanged owned target identity' || return 1
	[[ -f $second_live ]] || { printf '  expansion did not publish the added theme target\n' >&2; return 1; }
	assert_eq '["one","two"]' "$(jq -c '.created_directories' "$FIXTURE_STATE/dotfiles/wallpapers/active.json")" 'expanded receipt should retain both created directories'
}

test_changed_owned_file_and_unsafe_live_parent_block_fail_closed() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live receipt_before
	assignment=$(seed_wallpaper_assignment catppuccin PNG png) || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	receipt_before=$(sha256sum "$FIXTURE_STATE/dotfiles/wallpapers/active.json")
	make_wallpaper_image PNG "$live" '#aa3355' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'changed receipt-owned target should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'receipt-owned target changed' 'owned drift should be explicit' || return 1
	assert_eq "$receipt_before" "$(sha256sum "$FIXTURE_STATE/dotfiles/wallpapers/active.json")" 'owned drift should preserve receipt' || return 1

	rm "$live"
	rm -rf "$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin"
	ln -s "$OUTSIDE_ROOT/user-config" "$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'symlink live parent should block Apply' || return 1
	assert_contains "$COMMAND_OUTPUT" 'real directory' 'unsafe parent should be explicit'
}

test_active_background_blocks_stale_apply_and_deployment_removal() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live active_link
	assignment=$(seed_wallpaper_assignment catppuccin JPEG jpg) || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.jpg"
	active_link="$FIXTURE_HOME/.local/state/omarchy/current/background"
	mkdir -p "${active_link%/*}"
	ln -s "$live" "$active_link"
	rm "$assignment"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'Apply should block deletion of active stale target' || return 1
	assert_contains "$COMMAND_OUTPUT" 'current active background' 'active deletion block should identify its reason' || return 1
	[[ -f $live ]] || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'deployment removal should block active target deletion' || return 1
	assert_contains "$COMMAND_OUTPUT" "$live" 'active deletion block should identify exact path' || return 1
	[[ -f $live ]] || return 1
}

test_source_independent_removal_preserves_unrelated_state_and_clears_receipt_last() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live unrelated
	assignment=$(seed_wallpaper_assignment catppuccin BMP bmp) || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.bmp"
	unrelated="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/personal.png"
	printf 'personal\n' >"$unrelated"
	rm -rf "$FIXTURE_REPO/wallpapers"
	run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'receipt-owned removal should not depend on current source' || return 1
	assert_path_absent "$live" 'removal should delete unchanged receipt-owned target' || return 1
	assert_eq personal "$(<"$unrelated")" 'removal should preserve unrelated live file' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/active.json" 'verified removal should clear active receipt' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'verified removal should clear pending evidence'
}

test_empty_library_skip_and_active_convergence_removal_are_exact() {
	new_fixture
	setup_wallpaper_fixture
	local before
	before=$(find "$FIXTURE_CONFIG" "$FIXTURE_STATE" -printf '%p|%y|%m|%s|%T@\n' | sort)
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'empty unowned library should be a successful skip' || return 1
	assert_contains "$COMMAND_OUTPUT" 'empty and no wallpaper deployment is active' 'empty skip should be explicit' || return 1
	assert_eq "$before" "$(find "$FIXTURE_CONFIG" "$FIXTURE_STATE" -printf '%p|%y|%m|%s|%T@\n' | sort)" 'empty skip should not create state or prompt' || return 1

	rmdir "$FIXTURE_CONFIG/omarchy/backgrounds"
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live
	assignment=$(seed_wallpaper_assignment catppuccin PNG png) || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	rm "$assignment"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'empty library with active receipt should remove stale deployment' || return 1
	assert_path_absent "$live" 'empty convergence should remove prior owned target' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/active.json" 'empty convergence should clear ownership receipt' || return 1
	assert_path_absent "$FIXTURE_CONFIG/omarchy/backgrounds" 'empty convergence should remove its now-empty operation-created live root'
}

test_malformed_or_insecure_receipt_blocks_without_live_mutation() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live before receipt
	assignment=$(seed_wallpaper_assignment catppuccin PNG png) || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	receipt="$FIXTURE_STATE/dotfiles/wallpapers/active.json"
	before=$(sha256sum "$live")
	printf '{"schema_version":1,"kind":"active","targets":"unsafe"}\n' >"$receipt"
	chmod 0600 "$receipt"
	run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'malformed active receipt should block removal' || return 1
	assert_contains "$COMMAND_OUTPUT" 'invalid active receipt' 'malformed receipt should be explicit' || return 1
	assert_eq "$before" "$(sha256sum "$live")" 'malformed receipt must not infer ownership or mutate live file' || return 1
	chmod 0644 "$receipt"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_deployment_state
	assert_eq 1 "$COMMAND_STATUS" 'insecure receipt mode should fail deployment validation' || return 1
	assert_contains "$COMMAND_OUTPUT" '0600' 'receipt mode validation should state required permission'
}

test_deployment_failure_rolls_back_or_retains_recoverable_evidence() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	local first first_digest first_live second second_digest second_live
	first=$(seed_wallpaper_assignment one PNG png '#113355') || return 1
	first_digest=${first##*/} first_digest=${first_digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	first_live="$FIXTURE_CONFIG/omarchy/backgrounds/one/$first_digest.png"
	rm "$first"
	second=$(seed_wallpaper_assignment two PNG png '#557799') || return 1
	second_digest=${second##*/} second_digest=${second_digest%%.*}
	second_live="$FIXTURE_CONFIG/omarchy/backgrounds/two/$second_digest.png"
	DOTFILES_TEST_WALLPAPER_FAIL=state-active DOTFILES_TEST_WALLPAPER_FAIL_ROLLBACK=true \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'failed receipt publication plus failed rollback should fail Apply' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/wallpapers/pending.json && -f $FIXTURE_STATE/dotfiles/wallpapers/recovery-required.json ]] || {
		printf '  failed deployment rollback did not retain evidence\n' >&2
		return 1
	}
	[[ -d $FIXTURE_STATE/dotfiles/wallpapers/backups ]] || { printf '  interrupted deployment did not retain required backups\n' >&2; return 1; }
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'next Apply should recover verified prior deployment and stop' || return 1
	assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' 'deployment recovery should require separate rerun' || return 1
	[[ -f $first_live ]] || { printf '  deployment recovery did not restore stale prior target\n' >&2; return 1; }
	assert_path_absent "$second_live" 'deployment recovery should remove interrupted addition' || return 1
	assert_eq "one/$first_digest.png" "$(jq -r '.targets[0].path' "$FIXTURE_STATE/dotfiles/wallpapers/active.json")" 'deployment recovery should restore prior active receipt' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/backups" 'verified deployment recovery should clean transaction backups'
}

test_unattended_apply_requires_explicit_omarchy_mismatch_override() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#446688') || return 1
	digest=$(wallpaper_digest "$assignment") || return 1
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	DOTFILES_TEST_OMARCHY_VERSION=5.0.0 run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'unattended Apply should reject a mismatched Omarchy version without override' || return 1
	assert_contains "$COMMAND_OUTPUT" 'requires --allow-omarchy-mismatch' 'mismatch failure should name the explicit override' || return 1
	assert_path_absent "$live" 'rejected mismatch should not publish live wallpaper state' || return 1
	DOTFILES_TEST_OMARCHY_VERSION=5.0.0 run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes --allow-omarchy-mismatch
	assert_eq 0 "$COMMAND_STATUS" 'explicit unattended mismatch override should permit verified Apply' || return 1
	[[ -f $live && ! -L $live ]] || { printf '  mismatch override did not publish a regular live file\n' >&2; return 1; }
	assert_contains "$COMMAND_OUTPUT" 'Explicit Omarchy mismatch override supplied' 'accepted mismatch should remain visible'
}

test_apply_rejects_indirect_state_and_live_parent_symlinks() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest escaped_state="$FIXTURE_ROOT/escaped-state" escaped_live="$FIXTURE_ROOT/escaped-live" live
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#335577') || return 1
	digest=$(wallpaper_digest "$assignment") || return 1
	live="$escaped_live/backgrounds/catppuccin/$digest.png"
	mkdir "$escaped_state"
	ln -s "$escaped_state" "$FIXTURE_STATE/dotfiles"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'Apply should reject an XDG state path with an indirect symlink' || return 1
	assert_contains "$COMMAND_OUTPUT" 'state path must not traverse symbolic links' 'unsafe state ancestry should be explicit' || return 1
	assert_path_absent "$escaped_state/wallpapers" 'unsafe state ancestry should not create external evidence' || return 1
	rm "$FIXTURE_STATE/dotfiles"
	rm -rf "$FIXTURE_CONFIG/omarchy"
	mkdir "$escaped_live"
	ln -s "$escaped_live" "$FIXTURE_CONFIG/omarchy"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'Apply should reject a live path with an indirect symlink' || return 1
	assert_contains "$COMMAND_OUTPUT" 'live wallpaper path must not traverse symbolic links' 'unsafe live ancestry should be explicit' || return 1
	assert_path_absent "$live" 'unsafe live ancestry should not publish an external target'
}

test_interactive_apply_rejects_omarchy_version_change_after_confirmation() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#557799') || return 1
	digest=$(wallpaper_digest "$assignment") || return 1
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	DOTFILES_TEST_WALLPAPER_VERSION_CHANGES=true DOTFILES_TEST_INPUT='y\n' \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers
	assert_eq 1 "$COMMAND_STATUS" 'Apply should reject an Omarchy version change after confirmation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Omarchy version changed after wallpaper mutation approval' 'post-confirmation version drift should be explicit' || return 1
	assert_path_absent "$live" 'version drift should stop before live publication' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'version drift should stop before transaction publication'
}

test_apply_rejects_every_confirmed_fingerprint_replacement() {
	local race assignment digest live receipt parent active_link second
	for race in source receipt target parent active-link; do
		new_fixture
		setup_wallpaper_fixture
		mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
		assignment=$(seed_wallpaper_assignment one PNG png '#223344') || return 1
		digest=${assignment##*/} digest=${digest%%.*}
		live="$FIXTURE_CONFIG/omarchy/backgrounds/one/$digest.png"
		receipt="$FIXTURE_STATE/dotfiles/wallpapers/active.json"
		if [[ $race != source ]]; then
			run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
			assert_eq 0 "$COMMAND_STATUS" "$race race baseline Apply should succeed" || return 1
			second=$(seed_wallpaper_assignment two PNG png '#667788') || return 1
		fi
		case $race in
			source) DOTFILES_TEST_WALLPAPER_RACE=file DOTFILES_TEST_WALLPAPER_RACE_PATH=$assignment ;;
			receipt) DOTFILES_TEST_WALLPAPER_RACE=file DOTFILES_TEST_WALLPAPER_RACE_PATH=$receipt ;;
			target) DOTFILES_TEST_WALLPAPER_RACE=file DOTFILES_TEST_WALLPAPER_RACE_PATH=$live ;;
			parent) parent=${live%/*}; DOTFILES_TEST_WALLPAPER_RACE=directory DOTFILES_TEST_WALLPAPER_RACE_PATH=$parent ;;
			active-link)
				active_link="$FIXTURE_HOME/.local/state/omarchy/current/background"
				mkdir -p "${active_link%/*}"
				ln -s "$live" "$active_link"
				DOTFILES_TEST_WALLPAPER_RACE=symlink DOTFILES_TEST_WALLPAPER_RACE_PATH=$active_link
				;;
		esac
		export DOTFILES_TEST_WALLPAPER_RACE DOTFILES_TEST_WALLPAPER_RACE_PATH
		DOTFILES_TEST_INPUT='y\n' run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers
		unset DOTFILES_TEST_WALLPAPER_RACE DOTFILES_TEST_WALLPAPER_RACE_PATH
		assert_eq 1 "$COMMAND_STATUS" "Apply should reject confirmed $race identity replacement" || return 1
		assert_contains "$COMMAND_OUTPUT" 'confirmed wallpaper Apply plan changed before mutation' "$race replacement should be reported as stale" || return 1
		assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" "$race replacement should stop before pending publication" || return 1
	done
}

test_removal_rejects_confirmed_target_replacement() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#445566') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	DOTFILES_TEST_WALLPAPER_RACE=file DOTFILES_TEST_WALLPAPER_RACE_PATH=$live DOTFILES_TEST_INPUT='y\n' \
		run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpapers
	assert_eq 1 "$COMMAND_STATUS" 'deployment removal should reject confirmed target replacement' || return 1
	assert_contains "$COMMAND_OUTPUT" 'confirmed wallpaper removal plan changed before mutation' 'removal replacement should be reported as stale' || return 1
	[[ -f $live ]] || { printf '  stale removal mutated replacement target\n' >&2; return 1; }
}

test_relaxed_live_identity_adopts_and_removes_exact_hard_links_and_modes() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live external receipt receipt_link before
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#778899') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	mkdir -p "${live%/*}"
	external="$FIXTURE_ROOT/live-hard-link.png"
	cp "$assignment" "$external"
	ln "$external" "$live"
	chmod 0600 "$live"
	before=$(stat -c '%d|%i|%a|%h|%s|%y|%z' "$live")
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'exact regular hard-linked live target should be adopted regardless of mode' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Adopt exact unowned target' 'relaxed adoption should remain explicit' || return 1
	assert_eq "$before" "$(stat -c '%d|%i|%a|%h|%s|%y|%z' "$live")" 'adoption should preserve relaxed live metadata' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_deployment_state
	assert_eq 0 "$COMMAND_STATUS" 'receipt validation should accept safe digest-equal live mode and link count' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'receipt-owned relaxed exact target should remain an Apply no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'exact no-op' 'relaxed receipt-owned no-op should be explicit' || return 1
	assert_eq "$before" "$(stat -c '%d|%i|%a|%h|%s|%y|%z' "$live")" 'relaxed receipt-owned no-op should preserve live metadata' || return 1
	rm "$assignment"
	run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'receipt removal should accept safe digest-equal live mode and link count' || return 1
	assert_path_absent "$live" 'relaxed receipt removal should remove only the owned live pathname' || return 1
	[[ -f $external ]] || { printf '  relaxed receipt removal removed an external hard link\n' >&2; return 1; }
	assert_eq "$digest" "$(wallpaper_digest "$external")" 'relaxed receipt removal should preserve external sibling content' || return 1
	assert_eq 1 "$(stat -c %h "$external")" 'relaxed receipt removal should leave the external sibling as the sole link' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#778899') || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'strict receipt fixture Apply should succeed' || return 1
	receipt="$FIXTURE_STATE/dotfiles/wallpapers/active.json"
	receipt_link="$FIXTURE_ROOT/active-hard-link.json"
	ln "$receipt" "$receipt_link"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_deployment_state
	assert_eq 1 "$COMMAND_STATUS" 'hard-linked active receipt should fail state validation' || return 1
	assert_contains "$COMMAND_OUTPUT" '0600' 'hard-linked receipt should be rejected as insecure'
}

test_repository_source_drift_after_pending_rolls_back_add_and_adopt() {
	local assignment digest live replacement second second_digest second_live receipt receipt_before live_before

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#285078') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=file DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH=$assignment \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'repository source identity replacement after pending should fail add preparation' || return 1
	assert_path_absent "$live" 'source drift during add preparation must not publish a live target' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/active.json" 'source drift during add preparation must not publish a receipt' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'verified add preparation cleanup should clear pending evidence' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#285078') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	mkdir -p "${live%/*}"
	cp "$assignment" "$live"
	chmod 0600 "$live"
	DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=file DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH=$assignment \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'repository source identity replacement after pending should fail adoption' || return 1
	[[ -f $live && ! -L $live ]] || { printf '  failed adopt source revalidation removed the unowned exact live file\n' >&2; return 1; }
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/active.json" 'failed adopt source revalidation must not claim ownership' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'verified adopt preparation cleanup should clear pending evidence' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#285078') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	replacement="$FIXTURE_TMP/replacement.png"
	make_wallpaper_image PNG "$replacement" '#8a3048' || return 1
	DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE=$assignment DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE_REPLACEMENT=$replacement \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'repository source drift after receipt publication should fail final revalidation' || return 1
	assert_path_absent "$live" 'post-receipt source drift should roll back the added live target' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/active.json" 'post-receipt source drift should restore prior absent receipt state' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'verified post-receipt source rollback should clear pending evidence' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	assignment=$(seed_wallpaper_assignment one PNG png '#285078') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/one/$digest.png"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'unchanged-source drift fixture baseline should succeed' || return 1
	receipt="$FIXTURE_STATE/dotfiles/wallpapers/active.json"
	receipt_before=$(<"$receipt")
	live_before=$(stat -c '%d|%i|%a|%h|%s|%y|%z' "$live")
	second=$(seed_wallpaper_assignment two PNG png '#5f7891') || return 1
	second_digest=${second##*/} second_digest=${second_digest%%.*}
	second_live="$FIXTURE_CONFIG/omarchy/backgrounds/two/$second_digest.png"
	replacement="$FIXTURE_TMP/unchanged-source-replacement.png"
	make_wallpaper_image PNG "$replacement" '#9a4260' || return 1
	DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE=$assignment DOTFILES_TEST_WALLPAPER_SOURCE_AFTER_ACTIVE_REPLACEMENT=$replacement \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'unchanged observed source drift after receipt publication should fail Apply' || return 1
	assert_eq "$receipt_before" "$(<"$receipt")" 'unchanged observed source drift should restore the exact prior receipt content' || return 1
	assert_eq "$live_before" "$(stat -c '%d|%i|%a|%h|%s|%y|%z' "$live")" 'unchanged observed source drift should preserve the prior live target' || return 1
	assert_path_absent "$second_live" 'unchanged observed source drift should roll back the newly published live target' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'verified unchanged-source rollback should clear pending evidence'
}

test_locked_state_root_replacement_fails_before_final_path_mutation() {
	local assignment digest live intake target state_root replaced_root

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#365778') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	state_root="$FIXTURE_STATE/dotfiles/wallpapers"
	replaced_root="$state_root.wallpaper-race-replacement"
	DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE=after-lock run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'state-root replacement after lock should fail before pending publication' || return 1
	assert_contains "$COMMAND_OUTPUT" 'locked wallpaper state root pathname changed' 'pre-pending state-root replacement should report the pinned identity failure' || return 1
	assert_path_absent "$live" 'pre-pending state-root replacement must not publish a live target' || return 1
	assert_path_absent "$state_root/pending.json" 'pre-pending state-root replacement must not continue on replacement state' || return 1
	assert_path_absent "$replaced_root/pending.json" 'pre-pending state-root replacement should occur before transaction evidence' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	intake="$FIXTURE_REPO/wallpapers/inbox/state-root-race.png"
	make_wallpaper_image PNG "$intake" '#365778' || return 1
	digest=$(wallpaper_digest "$intake") || return 1
	target="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.png"
	state_root="$FIXTURE_STATE/dotfiles/wallpapers"
	replaced_root="$state_root.wallpaper-race-replacement"
	DOTFILES_TEST_WALLPAPER_STATE_ROOT_RACE=after-pending run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'state-root replacement after pending should fail before repository mutation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'locked wallpaper state root pathname changed' 'post-pending state-root replacement should report the pinned identity failure' || return 1
	assert_path_absent "$target" 'post-pending state-root replacement must not publish a repository target' || return 1
	[[ -f $intake ]] || { printf '  post-pending state-root replacement removed Intake\n' >&2; return 1; }
	assert_path_absent "$state_root/pending.json" 'post-pending state-root replacement must not continue on replacement state' || return 1
	[[ -f $replaced_root/pending.json ]] || { printf '  post-pending state-root replacement erased evidence from the locked directory\n' >&2; return 1; }
}

test_false_success_state_and_target_operations_remain_recoverable() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	local first first_digest first_live second second_digest second_live
	first=$(seed_wallpaper_assignment one PNG png '#112244') || return 1
	first_digest=${first##*/} first_digest=${first_digest%%.*}
	DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS=state-active-write run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'false-success active receipt publication should fail Apply' || return 1
	assert_path_absent "$FIXTURE_CONFIG/omarchy/backgrounds/one/$first_digest.png" 'failed receipt publication should roll back live publication' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'baseline Apply after verified rollback should succeed' || return 1
	first_live="$FIXTURE_CONFIG/omarchy/backgrounds/one/$first_digest.png"
	rm "$first"
	second=$(seed_wallpaper_assignment two PNG png '#6688aa') || return 1
	second_digest=${second##*/} second_digest=${second_digest%%.*}
	second_live="$FIXTURE_CONFIG/omarchy/backgrounds/two/$second_digest.png"
	DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS=live-delete run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'false-success stale target deletion should fail convergence' || return 1
	[[ -f $first_live ]] || { printf '  false-success target deletion lost prior live file\n' >&2; return 1; }
	assert_path_absent "$second_live" 'failed convergence should roll back its addition' || return 1
	DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS=state-pending.json-delete run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'false-success pending evidence deletion should not report success' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/wallpapers/pending.json ]] || { printf '  pending false-success fixture did not retain evidence\n' >&2; return 1; }
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'next Apply should recover after false-success pending cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' 'recovery should stop before ordinary Apply' || return 1
	DOTFILES_TEST_WALLPAPER_FALSE_SUCCESS=state-active.json-delete run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'false-success active receipt deletion should fail removal' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/wallpapers/active.json ]] || { printf '  false-success receipt removal lost ownership evidence\n' >&2; return 1; }
}

test_partial_publication_rolls_back_mode_and_cleans_backups() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local assignment digest live
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#336699') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	DOTFILES_TEST_WALLPAPER_FAIL=live-publish-after run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'failure after live publication should fail Apply' || return 1
	assert_path_absent "$live" 'ordinary rollback should remove partially published target' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'verified ordinary rollback should clear pending evidence' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/backups" 'verified ordinary rollback should clean transaction backups'
}

test_stale_created_directory_cleanup_removes_only_empty_owned_directories() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	local first second first_digest old_directory receipt
	first=$(seed_wallpaper_assignment one PNG png '#111133') || return 1
	first_digest=${first##*/} first_digest=${first_digest%%.*}
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	old_directory="$FIXTURE_CONFIG/omarchy/backgrounds/one"
	[[ -d $old_directory ]] || return 1
	rm "$first"
	second=$(seed_wallpaper_assignment two PNG png '#333355') || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'stale created-directory convergence should succeed' || return 1
	assert_path_absent "$old_directory" 'stale operation-created directory should be removed once empty' || return 1
	receipt="$FIXTURE_STATE/dotfiles/wallpapers/active.json"
	assert_eq '["two"]' "$(jq -c '.created_directories' "$receipt")" 'new receipt should retain only relevant created directories'
}

test_receipts_require_strict_timestamps_and_sorted_generated_arrays() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	seed_wallpaper_assignment one PNG png '#112233' >/dev/null || return 1
	seed_wallpaper_assignment two PNG png '#445566' >/dev/null || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	local receipt="$FIXTURE_STATE/dotfiles/wallpapers/active.json" replacement="$FIXTURE_TMP/active.json"
	jq '.activated_at = "not-a-timestamp"' "$receipt" >"$replacement" && mv "$replacement" "$receipt"
	chmod 0600 "$receipt"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_deployment_state
	assert_eq 1 "$COMMAND_STATUS" 'malformed receipt timestamp should fail strict validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'invalid active receipt' 'timestamp rejection should classify receipt as invalid'
}

test_deployment_sigterm_recovers_before_and_after_live_and_active_publication() {
	local seam expected_status
	for seam in live-before live-after live-after-kill active-before active-after; do
		new_fixture
		setup_wallpaper_fixture
		mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
		local assignment digest live
		assignment=$(seed_wallpaper_assignment catppuccin PNG png '#224466') || return 1
		digest=${assignment##*/} digest=${digest%%.*}
		live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
		DOTFILES_TEST_WALLPAPER_SIGNAL=$seam run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
		expected_status=143; [[ $seam != live-after-kill ]] || expected_status=137
		assert_eq "$expected_status" "$COMMAND_STATUS" "$seam should terminate the actual deployment process" || return 1
		[[ -f $FIXTURE_STATE/dotfiles/wallpapers/pending.json ]] || { printf '  interrupted deployment lost pending evidence\n' >&2; return 1; }
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
		assert_eq 0 "$COMMAND_STATUS" "$seam recovery should succeed" || return 1
		assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' "$seam recovery should stop before ordinary Apply" || return 1
		assert_path_absent "$live" "$seam recovery should restore prior absent live target" || return 1
		assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/active.json" "$seam recovery should restore prior absent receipt" || return 1
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
		assert_eq 0 "$COMMAND_STATUS" "$seam ordinary rerun should succeed" || return 1
	done
}

test_post_pending_active_adoption_owned_and_parent_replacements_fail_closed() {
	local assignment digest live parent active_link second

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#446688') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	parent=${live%/*}
	mkdir -p "$parent"
	cp "$assignment" "$live"
	DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=file DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH=$live \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'exact-byte adopted target replacement after pending should fail' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/active.json" 'failed adoption must not publish ownership' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#446688') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	parent=${live%/*}
	mkdir -p "$parent"
	cp "$assignment" "$live"
	DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=parent DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH=$parent \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'real parent replacement after pending should fail' || return 1
	assert_path_absent "$live" 'parent replacement must not receive a live publication' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#446688') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'owned replacement fixture baseline should succeed' || return 1
	second=$(seed_wallpaper_assignment catppuccin PNG png '#6688aa') || return 1
	DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=file DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH=$live \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'unchanged owned target replacement after pending should fail finalization' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	assignment=$(seed_wallpaper_assignment catppuccin PNG png '#446688') || return 1
	digest=${assignment##*/} digest=${digest%%.*}
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'active-link replacement fixture baseline should succeed' || return 1
	active_link="$FIXTURE_HOME/.local/state/omarchy/current/background"
	mkdir -p "${active_link%/*}"
	ln -s "$FIXTURE_ROOT/unrelated-background" "$active_link"
	DOTFILES_TEST_WALLPAPER_POST_PENDING_RACE=active-link DOTFILES_TEST_WALLPAPER_POST_PENDING_PATH=$active_link \
		DOTFILES_TEST_WALLPAPER_POST_PENDING_REPLACEMENT=$live run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpapers --yes
	assert_eq 1 "$COMMAND_STATUS" 'active background switch after pending should block last-boundary deletion' || return 1
	[[ -f $live ]] || { printf '  active-link race deleted the selected live target\n' >&2; return 1; }
}

test_completion_interruption_resumes_cleanup_without_orphan_inference() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	local first second
	first=$(seed_wallpaper_assignment one PNG png '#112233') || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'completion fixture baseline should succeed' || return 1
	rm "$first"
	second=$(seed_wallpaper_assignment two PNG png '#445566') || return 1
	DOTFILES_TEST_WALLPAPER_SIGNAL=cleanup-backup-entry run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 143 "$COMMAND_STATUS" 'cleanup boundary should terminate the actual process' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/wallpapers/pending.json ]] || { printf '  completion interruption lost pending route\n' >&2; return 1; }
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'completion recovery should resume cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' 'completion recovery should stop before ordinary Apply' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'completion recovery should clear pending last' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/backups" 'completion recovery should clear remaining backups' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'post-cleanup ordinary rerun should succeed' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	first=$(seed_wallpaper_assignment one PNG png '#112233') || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'rollback cleanup fixture baseline should succeed' || return 1
	rm "$first"
	second=$(seed_wallpaper_assignment two PNG png '#445566') || return 1
	DOTFILES_TEST_WALLPAPER_FAIL=state-active DOTFILES_TEST_WALLPAPER_SIGNAL=cleanup-backup-entry \
		run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 143 "$COMMAND_STATUS" 'rollback cleanup boundary should terminate the actual process' || return 1
	assert_eq rolled_back "$(jq -r '.phase' "$FIXTURE_STATE/dotfiles/wallpapers/pending.json")" 'rollback cleanup should retain an explicit durable route' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" apply_wallpapers --yes
	assert_eq 0 "$COMMAND_STATUS" 'rolled-back transaction recovery should resume cleanup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' 'rollback cleanup recovery should stop before ordinary Apply' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'rollback cleanup should remove pending last' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/backups" 'rollback cleanup should remove remaining backups'
}

run_test test_first_apply_materializes_regular_files_and_clone_independent_receipt 'first Apply materializes regular clone-independent wallpaper deployment'
run_test test_exact_apply_noop_preserves_live_and_receipt_metadata_without_prompt 'exact Apply no-op preserves every owned metadata timestamp'
run_test test_apply_adopts_exact_unowned_match_but_blocks_different_foreign_target 'Apply adopts only exact unowned matches'
run_test test_apply_converges_additions_and_stale_removals_while_preserving_unrelated_files 'Apply converges receipt ownership and preserves unrelated backgrounds'
run_test test_apply_retains_unchanged_operation_created_directories_during_expansion 'Apply retains unchanged operation-created directories during expansion'
run_test test_changed_owned_file_and_unsafe_live_parent_block_fail_closed 'Apply fails closed on owned drift and unsafe parents'
run_test test_active_background_blocks_stale_apply_and_deployment_removal 'active background blocks every planned owned deletion'
run_test test_source_independent_removal_preserves_unrelated_state_and_clears_receipt_last 'deployment removal is source-independent and receipt-bounded'
run_test test_empty_library_skip_and_active_convergence_removal_are_exact 'empty library handles unowned skip and stale convergence safely'
run_test test_malformed_or_insecure_receipt_blocks_without_live_mutation 'malformed deployment evidence blocks ownership inference'
run_test test_deployment_failure_rolls_back_or_retains_recoverable_evidence 'deployment failure retains evidence until verified recovery'
run_test test_unattended_apply_requires_explicit_omarchy_mismatch_override 'unattended Apply requires explicit Omarchy mismatch consent'
run_test test_apply_rejects_indirect_state_and_live_parent_symlinks 'Apply rejects indirect state and live parent links'
run_test test_interactive_apply_rejects_omarchy_version_change_after_confirmation 'Apply rechecks Omarchy after confirmation'
run_test test_apply_rejects_every_confirmed_fingerprint_replacement 'Apply rejects source, receipt, target, parent, and active-link replacement after confirmation'
run_test test_removal_rejects_confirmed_target_replacement 'removal rejects target replacement after confirmation'
run_test test_relaxed_live_identity_adopts_and_removes_exact_hard_links_and_modes 'deployment relaxes exact safe live modes and hard-link counts only'
run_test test_false_success_state_and_target_operations_remain_recoverable 'false-success filesystem operations cannot report lifecycle success'
run_test test_partial_publication_rolls_back_mode_and_cleans_backups 'partial live publication rolls back and cleans evidence'
run_test test_stale_created_directory_cleanup_removes_only_empty_owned_directories 'stale created-directory ownership converges safely'
run_test test_receipts_require_strict_timestamps_and_sorted_generated_arrays 'deployment receipts enforce strict generated fields'
run_test test_deployment_sigterm_recovers_before_and_after_live_and_active_publication 'deployment process interruption recovers every publication boundary'
run_test test_post_pending_active_adoption_owned_and_parent_replacements_fail_closed 'post-pending parent and target replacements fail closed'
run_test test_completion_interruption_resumes_cleanup_without_orphan_inference 'transaction completion interruption resumes strict cleanup'
run_test test_repository_source_drift_after_pending_rolls_back_add_and_adopt 'deployment revalidates changed and unchanged desired sources around receipt publication'
run_test test_locked_state_root_replacement_fails_before_final_path_mutation 'locked state-root replacement fails before live or repository mutation'
finish_tests
