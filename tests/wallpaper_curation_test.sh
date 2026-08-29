#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

test_inspect_reports_empty_invalid_intake_and_installed_theme_origins_read_only() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin" "$FIXTURE_WALLPAPER_THEMES/tokyo-night"
	mkdir "$FIXTURE_CONFIG/omarchy/themes/tokyo-night" "$FIXTURE_CONFIG/omarchy/themes/rose-pine"
	printf 'not an image\n' >"$FIXTURE_REPO/wallpapers/inbox/broken.png"
	local before
	before=$(find "$FIXTURE_REPO/wallpapers" -printf '%P|%y|%m|%s|%T@\n' | sort)
	run_wallpaper_operation "$FIXTURE_ROOT" inspect_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'Inspect should report invalid intake without treating it as a mutation failure' || return 1
	assert_contains "$COMMAND_OUTPUT" 'broken.png: invalid' 'Inspect should retain and explain invalid intake' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Catppuccin [catppuccin] (stock)' 'Inspect should show friendly and exact packaged theme names' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Rose Pine [rose-pine] (user)' 'Inspect should show friendly and exact user theme names' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Tokyo Night [tokyo-night] (stock + user overlay)' 'Inspect should deduplicate overlay slugs' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Managed wallpapers: 0' 'Inspect should report an empty valid library' || return 1
	assert_eq "$before" "$(find "$FIXTURE_REPO/wallpapers" -printf '%P|%y|%m|%s|%T@\n' | sort)" 'Inspect must be read-only'
}

test_gitkeep_is_not_an_intake_image_during_inspect_or_add_scan() {
	new_fixture
	setup_wallpaper_fixture
	local gitkeep="$FIXTURE_REPO/wallpapers/inbox/.gitkeep" before
	[[ -f $gitkeep && ! -L $gitkeep ]] || { printf '  fixture did not retain the Wallpaper inbox .gitkeep\n' >&2; return 1; }
	before=$(stat -c '%d|%i|%a|%s|%y|%z' "$gitkeep")
	run_wallpaper_operation "$FIXTURE_ROOT" wallpaper_intake_snapshot
	assert_eq 0 "$COMMAND_STATUS" 'intake snapshot should accept the tracked placeholder' || return 1
	assert_contains "$COMMAND_OUTPUT" '/.gitkeep|' '.gitkeep should remain part of stale-plan snapshots' || return 1
	DOTFILES_TEST_INPUT='2\n1\n5\n' run_wallpaper_operation "$FIXTURE_ROOT" manage_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'Inspect and Add should accept an inbox containing only .gitkeep' || return 1
	assert_contains "$COMMAND_OUTPUT" $'Wallpaper inbox:\n  empty' 'Inspect should report no Intake images for .gitkeep' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No valid Intake images are available' 'Add should find no Intake images for .gitkeep' || return 1
	if [[ $COMMAND_OUTPUT == *'.gitkeep'* ]]; then
		printf '  Inspect or Add exposed .gitkeep as an Intake image: %q\n' "$COMMAND_OUTPUT" >&2
		return 1
	fi
	assert_eq "$before" "$(stat -c '%d|%i|%a|%s|%y|%z' "$gitkeep")" '.gitkeep should remain unchanged'
}

test_add_assigns_exact_bytes_to_one_or_many_themes_then_deletes_intake() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin" "$FIXTURE_CONFIG/omarchy/themes/tokyo-night"
	local intake="$FIXTURE_REPO/wallpapers/inbox/blue.png" digest first second
	make_wallpaper_image PNG "$intake" || return 1
	digest=$(wallpaper_digest "$intake") || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin tokyo-night --yes
	assert_eq 0 "$COMMAND_STATUS" 'confirmed multi-theme Add should succeed' || return 1
	first="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.png"
	second="$FIXTURE_REPO/wallpapers/library/tokyo-night/$digest.png"
	for target in "$first" "$second"; do
		[[ -f $target && ! -L $target ]] || { printf '  missing regular assignment: %s\n' "$target" >&2; return 1; }
		assert_eq "$digest" "$(wallpaper_digest "$target")" 'Add should preserve exact bytes' || return 1
	done
	assert_path_absent "$intake" 'Add should delete intake only after every assignment verifies' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Live Omarchy backgrounds are unchanged' 'curation should preserve deployment separation' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'successful Add should clear pending evidence' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/backups" 'successful Add should clean transaction backups'
}

test_duplicate_add_reuses_identity_adds_only_missing_assignments_and_explicitly_cleans_intake() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin" "$FIXTURE_WALLPAPER_THEMES/gruvbox"
	local original="$FIXTURE_REPO/wallpapers/inbox/original.webp" duplicate="$FIXTURE_REPO/wallpapers/inbox/duplicate-any-name.bin"
	local digest existing before
	make_wallpaper_image WEBP "$original" || return 1
	digest=$(wallpaper_digest "$original") || return 1
	existing=$(assign_wallpaper_fixture "$original" catppuccin webp) || return 1
	cp "$original" "$duplicate"
	run_wallpaper_operation "$FIXTURE_ROOT" inspect_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'Inspect should recognize duplicate Intake bytes' || return 1
	assert_contains "$COMMAND_OUTPUT" 'duplicate=true' 'Inspect should report duplicate managed identity' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Existing Theme assignment: catppuccin' 'Inspect should report duplicate assignments' || return 1
	before=$(stat -c '%d|%i|%s|%y|%z' "$existing")
	run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$duplicate" catppuccin gruvbox --yes
	assert_eq 0 "$COMMAND_STATUS" 'duplicate Add should reuse the managed identity' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Duplicate managed identity: yes' 'Add preview should disclose duplicate reuse' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No-op assignment: catppuccin' 'Add preview should disclose existing assignment no-op' || return 1
	assert_eq "$before" "$(stat -c '%d|%i|%s|%y|%z' "$existing")" 'duplicate no-op assignment should preserve metadata' || return 1
	assert_eq "$digest" "$(wallpaper_digest "$FIXTURE_REPO/wallpapers/library/gruvbox/$digest.webp")" 'only missing assignment should be copied' || return 1
	assert_path_absent "$duplicate" 'confirmed duplicate cleanup should delete intake'
}

test_add_cancellation_invalid_theme_and_failure_preserve_intake_and_library() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local intake="$FIXTURE_REPO/wallpapers/inbox/candidate.jpg" digest target
	make_wallpaper_image JPEG "$intake" || return 1
	chmod 0600 "$intake"
	digest=$(wallpaper_digest "$intake") || return 1
	target="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.jpg"
	DOTFILES_TEST_INPUT='n\n' run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin
	assert_eq 0 "$COMMAND_STATUS" 'declined Add should be a successful cancellation' || return 1
	[[ -f $intake ]] || return 1
	assert_path_absent "$target" 'declined Add must not create an assignment' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" missing --yes
	assert_eq 1 "$COMMAND_STATUS" 'Add should reject a theme not currently installed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'not an installed theme slug' 'missing theme should be explicit' || return 1
	DOTFILES_TEST_WALLPAPER_FAIL=publish-after run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'publication failure should fail Add' || return 1
	[[ -f $intake ]] || { printf '  failed Add lost intake\n' >&2; return 1; }
	assert_eq 600 "$(stat -c %a "$intake")" 'failed Add rollback should restore the original Intake mode' || return 1
	assert_path_absent "$target" 'failed Add should roll back its new assignment' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'verified rollback should clear pending evidence'
}

test_move_publishes_and_verifies_destination_before_source_removal() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/source" "$FIXTURE_WALLPAPER_THEMES/destination"
	local image="$FIXTURE_REPO/wallpapers/inbox/source.png" digest source destination
	make_wallpaper_image PNG "$image" || return 1
	digest=$(wallpaper_digest "$image") || return 1
	source=$(assign_wallpaper_fixture "$image" source png) || return 1
	destination="$FIXTURE_REPO/wallpapers/library/destination/$digest.png"
	DOTFILES_TEST_WALLPAPER_FAIL=publish-after run_wallpaper_operation "$FIXTURE_ROOT" move_wallpaper "$digest" source destination --yes
	assert_eq 1 "$COMMAND_STATUS" 'Move should fail when destination publication cannot verify' || return 1
	[[ -f $source ]] || { printf '  failed Move removed source before destination verified\n' >&2; return 1; }
	assert_path_absent "$destination" 'failed Move should roll back destination' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" move_wallpaper "$digest" source destination --yes
	assert_eq 0 "$COMMAND_STATUS" 'verified Move should succeed' || return 1
	assert_path_absent "$source" 'successful Move should remove source assignment' || return 1
	assert_eq "$digest" "$(wallpaper_digest "$destination")" 'successful Move should preserve identity'
}

test_remove_changes_one_assignment_and_strongly_confirms_final_identity_deletion() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/one" "$FIXTURE_WALLPAPER_THEMES/two"
	local image="$FIXTURE_REPO/wallpapers/inbox/source.gif" digest one two
	make_wallpaper_image GIF "$image" || return 1
	digest=$(wallpaper_digest "$image") || return 1
	one=$(assign_wallpaper_fixture "$image" one gif) || return 1
	two=$(assign_wallpaper_fixture "$image" two gif) || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpaper_assignment "$digest" one --yes
	assert_eq 0 "$COMMAND_STATUS" 'Remove should delete one assignment' || return 1
	assert_path_absent "$one" 'selected assignment should be removed' || return 1
	[[ -f $two ]] || return 1
	DOTFILES_TEST_INPUT='n\n' run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpaper_assignment "$digest" two
	assert_eq 0 "$COMMAND_STATUS" 'declining final-assignment deletion should cancel safely' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Managed wallpaper will cease to exist' 'final removal should disclose stronger consequence' || return 1
	[[ -f $two ]] || { printf '  declined final removal deleted assignment\n' >&2; return 1; }
	run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpaper_assignment "$digest" two --yes
	assert_eq 0 "$COMMAND_STATUS" 'confirmed final assignment removal should succeed' || return 1
	assert_path_absent "$two" 'final assignment should be removed'
}

test_failed_rollback_blocks_then_next_command_recovers_and_stops() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local intake="$FIXTURE_REPO/wallpapers/inbox/candidate.bmp" digest target
	make_wallpaper_image BMP "$intake" || return 1
	digest=$(wallpaper_digest "$intake") || return 1
	target="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.bmp"
	DOTFILES_TEST_WALLPAPER_FAIL=delete-after DOTFILES_TEST_WALLPAPER_FAIL_ROLLBACK=true \
		run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'failed rollback should fail the Add operation' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/wallpapers/pending.json && -f $FIXTURE_STATE/dotfiles/wallpapers/recovery-required.json ]] || {
		printf '  failed rollback did not retain recovery evidence\n' >&2
		return 1
	}
	[[ -d $FIXTURE_STATE/dotfiles/wallpapers/backups ]] || { printf '  interrupted curation did not retain required backups\n' >&2; return 1; }
	DOTFILES_TEST_OMARCHY_VERSION=5.0.0 DOTFILES_TEST_INPUT='n\n' \
		run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin
	assert_eq 1 "$COMMAND_STATUS" 'interactive recovery should require fresh mismatch consent' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recover the interrupted wallpaper transaction despite the Omarchy version mismatch?' \
		'recovery should identify the mismatched mutation decision' || return 1
	[[ -f $FIXTURE_STATE/dotfiles/wallpapers/pending.json && -f $FIXTURE_STATE/dotfiles/wallpapers/recovery-required.json ]] || {
		printf '  declined mismatch recovery removed retained evidence\n' >&2
		return 1
	}
	run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 0 "$COMMAND_STATUS" 'next command should recover a verified interrupted transaction' || return 1
	assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' 'recovery should stop before requested Add' || return 1
	[[ -f $intake ]] || { printf '  recovery did not restore intake\n' >&2; return 1; }
	assert_path_absent "$target" 'recovery should restore the prior absent assignment' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'successful recovery should clear pending evidence' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/backups" 'successful recovery should clean retained transaction backups'
}

test_manager_adds_one_intake_inspects_details_and_defers_deployment_on_exit() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local intake="$FIXTURE_REPO/wallpapers/inbox/manager.png" digest assignment live
	make_wallpaper_image PNG "$intake" || return 1
	digest=$(wallpaper_digest "$intake") || return 1
	assignment="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.png"
	live="$FIXTURE_CONFIG/omarchy/backgrounds/catppuccin/$digest.png"
	DOTFILES_TEST_INPUT='1\n1\n1\n1\ny\n2\n5\n2\n' run_wallpaper_operation "$FIXTURE_ROOT" manage_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'manager Add, Inspect, and Back flow should succeed' || return 1
	[[ -f $assignment && ! -L $assignment ]] || { printf '  manager did not create the selected assignment\n' >&2; return 1; }
	assert_path_absent "$intake" 'manager Add should delete verified intake' || return 1
	assert_path_absent "$live" 'deferring exit-time Apply should leave live backgrounds unchanged' || return 1
	assert_contains "$COMMAND_OUTPUT" "SHA-256: $digest" 'manager Inspect should show the full managed identity' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Theme assignment: catppuccin' 'manager Inspect should show each assignment' || return 1
	assert_contains "$COMMAND_OUTPUT" 'choose Apply wallpapers in the Dotfiles wizard' 'deferring deployment should print the standalone route'
}

test_manager_routes_move_and_final_assignment_remove_then_defers_deployment() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/source" "$FIXTURE_WALLPAPER_THEMES/destination"
	local image="$FIXTURE_REPO/wallpapers/inbox/source.bmp" digest source destination
	make_wallpaper_image BMP "$image" || return 1
	digest=$(wallpaper_digest "$image") || return 1
	source=$(assign_wallpaper_fixture "$image" source bmp) || return 1
	destination="$FIXTURE_REPO/wallpapers/library/destination/$digest.bmp"
	DOTFILES_TEST_INPUT='3\n1\n1\ny\n4\n1\ny\n5\n2\n' run_wallpaper_operation "$FIXTURE_ROOT" manage_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'manager Move and Remove flow should succeed' || return 1
	assert_path_absent "$source" 'manager Move should remove its source assignment' || return 1
	assert_path_absent "$destination" 'manager final Remove should delete the moved assignment' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: Move one Theme assignment' 'manager should route Move through its callable operation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Managed wallpaper will cease to exist' 'manager should retain strong final-removal confirmation'
}

test_curation_rejects_repository_parent_symlinks_and_unsafe_source_themes() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local image="$FIXTURE_REPO/wallpapers/inbox/source.png" digest assignment escaped="$FIXTURE_ROOT/escaped-wallpapers"
	make_wallpaper_image PNG "$image" || return 1
	digest=$(wallpaper_digest "$image") || return 1
	assignment=$(assign_wallpaper_fixture "$image" catppuccin png) || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpaper_assignment "$digest" '../../escaped' --yes
	assert_eq 1 "$COMMAND_STATUS" 'Remove should reject a path-bearing source theme' || return 1
	[[ -f $assignment ]] || { printf '  unsafe source theme removed a valid assignment\n' >&2; return 1; }
	rm -rf "$FIXTURE_REPO/wallpapers"
	mkdir -p "$escaped/inbox" "$escaped/library"
	ln -s "$escaped" "$FIXTURE_REPO/wallpapers"
	image="$FIXTURE_REPO/wallpapers/inbox/escaped.png"
	make_wallpaper_image PNG "$image" || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$image" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'Add should reject an Intake path reached through a repository parent symlink' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Add requires a direct regular Intake file' 'unsafe Intake ancestry should fail before planning' || return 1
	[[ -f $escaped/inbox/escaped.png ]] || { printf '  rejected parent symlink Add deleted escaped intake\n' >&2; return 1; }
	assert_path_absent "$escaped/library/catppuccin" 'rejected parent symlink Add should not mutate the escaped library'
}

test_user_theme_symlink_discovery_accepts_external_directory_targets_as_metadata() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/tokyo-night"
	mkdir "$FIXTURE_CONFIG/omarchy/themes/custom-source" "$FIXTURE_ROOT/external-theme"
	ln -s custom-source "$FIXTURE_CONFIG/omarchy/themes/linked-theme"
	ln -s custom-source "$FIXTURE_CONFIG/omarchy/themes/tokyo-night"
	run_wallpaper_operation "$FIXTURE_ROOT" inspect_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'safe direct user theme symlinks should be eligible' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Linked Theme [linked-theme] (user)' 'safe user symlink should expose friendly name, exact slug, and origin' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Tokyo Night [tokyo-night] (stock + user overlay)' 'safe symlink overlay should deduplicate with packaged origin' || return 1
	rm "$FIXTURE_CONFIG/omarchy/themes/linked-theme"
	ln -s "$FIXTURE_ROOT/external-theme" "$FIXTURE_CONFIG/omarchy/themes/linked-theme"
	run_wallpaper_operation "$FIXTURE_ROOT" inspect_wallpapers
	assert_eq 0 "$COMMAND_STATUS" 'direct user theme symlink to an external directory should be eligible' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Linked Theme [linked-theme] (user)' 'external user theme link should remain selection-only metadata' || return 1
	local intake="$FIXTURE_REPO/wallpapers/inbox/external.png"
	make_wallpaper_image PNG "$intake" || return 1
	DOTFILES_TEST_WALLPAPER_RACE=directory DOTFILES_TEST_WALLPAPER_RACE_PATH="$FIXTURE_ROOT/external-theme" DOTFILES_TEST_INPUT='y\n' \
		run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" linked-theme
	assert_eq 1 "$COMMAND_STATUS" 'resolved external theme replacement after confirmation should stale the selection plan' || return 1
	assert_contains "$COMMAND_OUTPUT" 'confirmed wallpaper Add plan is stale' 'resolved theme identity replacement should be explicit' || return 1
	rm "$FIXTURE_CONFIG/omarchy/themes/linked-theme"
	printf 'not a directory\n' >"$FIXTURE_ROOT/external-theme-file"
	ln -s "$FIXTURE_ROOT/external-theme-file" "$FIXTURE_CONFIG/omarchy/themes/linked-theme"
	run_wallpaper_operation "$FIXTURE_ROOT" inspect_wallpapers
	assert_eq 1 "$COMMAND_STATUS" 'user theme symlink to a non-directory should fail discovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unsafe user theme symlink' 'non-directory user theme rejection should be explicit' || return 1
	rm "$FIXTURE_CONFIG/omarchy/themes/linked-theme"
	ln -s missing-theme "$FIXTURE_CONFIG/omarchy/themes/linked-theme"
	run_wallpaper_operation "$FIXTURE_ROOT" inspect_wallpapers
	assert_eq 1 "$COMMAND_STATUS" 'broken user theme symlink should fail discovery' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unsafe user theme symlink' 'broken user theme rejection should be explicit'
}

test_curation_sigterm_before_and_after_assignment_visibility_recovers_and_stops() {
	local seam
	for seam in curation-before curation-after; do
		new_fixture
		setup_wallpaper_fixture
		mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
		local intake="$FIXTURE_REPO/wallpapers/inbox/$seam.png" digest target
		make_wallpaper_image PNG "$intake" '#335577' || return 1
		digest=$(wallpaper_digest "$intake") || return 1
		target="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.png"
		DOTFILES_TEST_WALLPAPER_SIGNAL=$seam run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
		assert_eq 143 "$COMMAND_STATUS" "$seam should terminate the actual curation process" || return 1
		[[ -f $FIXTURE_STATE/dotfiles/wallpapers/pending.json ]] || { printf '  interrupted curation lost pending evidence\n' >&2; return 1; }
		run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
		assert_eq 0 "$COMMAND_STATUS" "$seam recovery should succeed" || return 1
		assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' "$seam recovery should stop before ordinary work" || return 1
		[[ -f $intake ]] || { printf '  interrupted curation did not restore Intake\n' >&2; return 1; }
		assert_path_absent "$target" 'interrupted curation should remove only its staged or published assignment' || return 1
		run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
		assert_eq 0 "$COMMAND_STATUS" "$seam ordinary rerun should succeed" || return 1
		[[ -f $target ]] || return 1
	done
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local intake="$FIXTURE_REPO/wallpapers/inbox/rollback-cleanup.png" digest target
	make_wallpaper_image PNG "$intake" '#335577' || return 1
	digest=$(wallpaper_digest "$intake") || return 1
	target="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.png"
	DOTFILES_TEST_WALLPAPER_FAIL=publish-after DOTFILES_TEST_WALLPAPER_SIGNAL=cleanup-backup-entry \
		run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 143 "$COMMAND_STATUS" 'curation rollback cleanup should terminate the actual process' || return 1
	assert_eq rolled_back "$(jq -r '.phase' "$FIXTURE_STATE/dotfiles/wallpapers/pending.json")" 'curation rollback should retain an explicit cleanup route' || return 1
	[[ -f $intake ]] || return 1
	assert_path_absent "$target" 'curation should restore prior state before durable rollback cleanup' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 0 "$COMMAND_STATUS" 'curation rollback cleanup recovery should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' 'curation rollback cleanup recovery should stop before Add'
}

test_pending_publication_failure_precedes_all_transaction_resources() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local intake="$FIXTURE_REPO/wallpapers/inbox/pending-failure.png" digest target
	make_wallpaper_image PNG "$intake" '#264c73' || return 1
	digest=$(wallpaper_digest "$intake") || return 1
	target="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.png"
	DOTFILES_TEST_WALLPAPER_FAIL=state-pending run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'pending publication failure should fail Add' || return 1
	[[ -f $intake ]] || { printf '  pending publication failure lost Intake\n' >&2; return 1; }
	assert_path_absent "$target" 'pending publication failure must precede repository target creation' || return 1
	assert_path_absent "$FIXTURE_REPO/wallpapers/library/catppuccin" 'pending publication failure must precede repository directory preparation' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/pending.json" 'failed pending publication must not leave pending evidence' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/wallpapers/backups" 'failed pending publication must not create backup resources'
}

test_preparing_intent_without_identity_retains_evidence_and_substituted_resources() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local intake="$FIXTURE_REPO/wallpapers/inbox/preparing.png" digest target pending recovery stage substitute_identity directory_mode
	make_wallpaper_image PNG "$intake" '#315d82' || return 1
	digest=$(wallpaper_digest "$intake") || return 1
	target="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.png"
	DOTFILES_TEST_WALLPAPER_SIGNAL=preparing-stage-created run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 143 "$COMMAND_STATUS" 'stage creation interruption should terminate during preparing' || return 1
	pending="$FIXTURE_STATE/dotfiles/wallpapers/pending.json"
	recovery="$FIXTURE_STATE/dotfiles/wallpapers/recovery-required.json"
	assert_eq preparing "$(jq -r '.phase' "$pending")" 'interrupted preparation should retain a valid preparing phase' || return 1
	assert_eq null "$(jq -r '.changes[] | select(.desired.present) | .desired.stage_identity' "$pending")" 'stage identity should remain unknown at the interrupted boundary' || return 1
	stage=$(jq -r '.changes[] | select(.desired.present) | .desired.stage_path' "$pending")
	[[ -f $stage && ! -L $stage ]] || { printf '  predeclared stage was not retained at the interrupted boundary\n' >&2; return 1; }
	assert_path_absent "$recovery" 'process interruption should precede recovery-required publication' || return 1
	cp --preserve=mode,timestamps -- "$stage" "$FIXTURE_TMP/substitute-stage"
	mv -fT -- "$FIXTURE_TMP/substitute-stage" "$stage"
	substitute_identity=$(stat -c '%d|%i|%a|%s' "$stage")
	run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'intent-only stage must keep future ordinary mutation blocked' || return 1
	assert_contains "$COMMAND_OUTPUT" 'ordinary wallpaper mutation remains blocked' 'blocked preparing recovery should be explicit' || return 1
	[[ -f $intake ]] || return 1
	assert_path_absent "$target" 'preparing recovery must preserve the prior absent assignment' || return 1
	assert_eq "$substitute_identity" "$(stat -c '%d|%i|%a|%s' "$stage")" 'intent-only cleanup must not delete or replace a substituted stage' || return 1
	[[ -f $pending && -f $recovery ]] || { printf '  blocked stage cleanup erased transaction evidence\n' >&2; return 1; }

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	intake="$FIXTURE_REPO/wallpapers/inbox/preparing-directory.png"
	make_wallpaper_image PNG "$intake" '#315d82' || return 1
	DOTFILES_TEST_WALLPAPER_PREPARATION_FAIL=directory-created run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'directory creation failure should fail closed during preparing' || return 1
	pending="$FIXTURE_STATE/dotfiles/wallpapers/pending.json"
	recovery="$FIXTURE_STATE/dotfiles/wallpapers/recovery-required.json"
	[[ -f $pending && -f $recovery ]] || { printf '  failed begin transaction erased pending or recovery-required evidence\n' >&2; return 1; }
	local directory=''
	while IFS= read -r target; do
		if [[ -d $target && ! -L $target ]]; then directory=$target; break; fi
	done < <(jq -r '.parents[] | select(.created and .identity == null) | .path' "$pending")
	[[ -n $directory ]] || { printf '  failed directory boundary did not retain its intent-only directory\n' >&2; return 1; }
	directory_mode=$(stat -c %a "$directory")
	mv -T -- "$directory" "$FIXTURE_TMP/original-created-directory"
	mkdir -m "$directory_mode" -- "$directory"
	substitute_identity=$(stat -c '%d|%i|%a' "$directory")
	run_wallpaper_operation "$FIXTURE_ROOT" add_wallpaper "$intake" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'intent-only directory must keep future ordinary mutation blocked' || return 1
	assert_eq "$substitute_identity" "$(stat -c '%d|%i|%a' "$directory")" 'intent-only cleanup must not delete a substituted directory' || return 1
	[[ -f $pending && -f $recovery ]] || { printf '  blocked directory cleanup erased transaction evidence\n' >&2; return 1; }
}

test_curation_deletion_uses_quarantine_and_rejects_replacement() {
	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	local image="$FIXTURE_REPO/wallpapers/inbox/source.png" replacement="$FIXTURE_TMP/replacement.png" digest source quarantine pending
	make_wallpaper_image PNG "$image" '#406080' || return 1
	make_wallpaper_image PNG "$replacement" '#a04060' || return 1
	digest=$(wallpaper_digest "$image") || return 1
	source=$(assign_wallpaper_fixture "$image" catppuccin png) || return 1
	DOTFILES_TEST_WALLPAPER_DELETE_RACE_PATH=$source DOTFILES_TEST_WALLPAPER_DELETE_RACE_REPLACEMENT=$replacement \
		run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpaper_assignment "$digest" catppuccin --yes
	assert_eq 1 "$COMMAND_STATUS" 'replacement at the deletion boundary should fail closed' || return 1
	assert_eq "$(wallpaper_digest "$replacement")" "$(wallpaper_digest "$source")" 'replacement must remain at the final pathname' || return 1
	pending="$FIXTURE_STATE/dotfiles/wallpapers/pending.json"
	quarantine=$(jq -r '.changes[0].quarantine_path' "$pending")
	assert_path_absent "$quarantine" 'failed expected-identity removal must not quarantine the replacement' || return 1

	new_fixture
	setup_wallpaper_fixture
	mkdir "$FIXTURE_WALLPAPER_THEMES/catppuccin"
	image="$FIXTURE_REPO/wallpapers/inbox/source.png"
	make_wallpaper_image PNG "$image" '#406080' || return 1
	digest=$(wallpaper_digest "$image") || return 1
	source=$(assign_wallpaper_fixture "$image" catppuccin png) || return 1
	DOTFILES_TEST_WALLPAPER_SIGNAL=curation-delete-after run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpaper_assignment "$digest" catppuccin --yes
	assert_eq 143 "$COMMAND_STATUS" 'interruption after deletion quarantine should terminate the process' || return 1
	pending="$FIXTURE_STATE/dotfiles/wallpapers/pending.json"
	quarantine=$(jq -r '.changes[0].quarantine_path' "$pending")
	assert_path_absent "$source" 'quarantine move should leave the final pathname absent' || return 1
	[[ -f $quarantine && ! -L $quarantine ]] || { printf '  interrupted deletion did not retain its quarantine\n' >&2; return 1; }
	run_wallpaper_operation "$FIXTURE_ROOT" remove_wallpaper_assignment "$digest" catppuccin --yes
	assert_eq 0 "$COMMAND_STATUS" 'next command should restore a quarantined deletion and stop' || return 1
	assert_contains "$COMMAND_OUTPUT" 'recovered and verified; rerun' 'quarantine recovery should be explicit' || return 1
	[[ -f $source && ! -L $source ]] || { printf '  quarantine recovery did not restore the prior assignment\n' >&2; return 1; }
	assert_path_absent "$quarantine" 'quarantine recovery should consume the exact quarantine'
}

run_test test_inspect_reports_empty_invalid_intake_and_installed_theme_origins_read_only 'Inspect reports coherent curation state without mutation'
run_test test_gitkeep_is_not_an_intake_image_during_inspect_or_add_scan '.gitkeep is not treated as an Intake image'
run_test test_add_assigns_exact_bytes_to_one_or_many_themes_then_deletes_intake 'Add materializes exact-byte assignments before intake deletion'
run_test test_duplicate_add_reuses_identity_adds_only_missing_assignments_and_explicitly_cleans_intake 'Add reuses duplicate managed identity'
run_test test_add_cancellation_invalid_theme_and_failure_preserve_intake_and_library 'Add preserves intake and prior library on cancellation or failure'
run_test test_move_publishes_and_verifies_destination_before_source_removal 'Move verifies its destination before source removal'
run_test test_remove_changes_one_assignment_and_strongly_confirms_final_identity_deletion 'Remove handles one and final assignments explicitly'
run_test test_failed_rollback_blocks_then_next_command_recovers_and_stops 'curation interruption recovers prior assignments and intake before new work'
run_test test_manager_adds_one_intake_inspects_details_and_defers_deployment_on_exit 'manager curates one image and offers separate deployment on exit'
run_test test_manager_routes_move_and_final_assignment_remove_then_defers_deployment 'manager routes Move and final assignment Remove safely'
run_test test_curation_rejects_repository_parent_symlinks_and_unsafe_source_themes 'curation rejects path traversal and indirect repository links'
run_test test_user_theme_symlink_discovery_accepts_external_directory_targets_as_metadata 'user theme symlinks are discovered without path escape'
run_test test_curation_sigterm_before_and_after_assignment_visibility_recovers_and_stops 'curation process interruption recovers staged and visible assignments'
run_test test_pending_publication_failure_precedes_all_transaction_resources 'pending publication failure leaves no transaction preparation side effects'
run_test test_preparing_intent_without_identity_retains_evidence_and_substituted_resources 'preparing intent without identity retains evidence and substituted resources'
run_test test_curation_deletion_uses_quarantine_and_rejects_replacement 'curation deletion quarantines expected identity and preserves replacements'
finish_tests
