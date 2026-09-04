#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

add_official_optional_application() {
	local id=${1-alpha} name=${2-Alpha} description=${3-'Official test application'} package=${4-$id} command=${5-$id}
	jq --arg id "$id" --arg name "$name" --arg description "$description" --arg package "$package" --arg command "$command" \
		'.applications += [{id:$id, name:$name, description:$description, package:$package, source:"official", command:$command, conflicts:[]}]' \
		"$FIXTURE_REPO/applications.json" >"$FIXTURE_REPO/applications.updated"
	mv "$FIXTURE_REPO/applications.updated" "$FIXTURE_REPO/applications.json"
}

make_bruno_command() {
	make_fake bruno 'exit 0'
}

stub_guided_non_application_phases() {
	cat >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh" <<'EOF'
setup_prerequisites() { printf 'Stub guided prerequisites\n'; }
install_skills() { printf 'Stub guided skills\n'; }
cleanup_applications() { printf 'Stub guided cleanup\n'; }
wizard_packages() { WIZARD_PACKAGES=(); }
apply_packages() { printf 'Stub guided Stow apply\n'; }
apply_wallpapers() { WALLPAPER_OPERATION_CONTEXT=$WALLPAPER_OPERATION_CONTEXT_ORDINARY; printf 'Stub guided wallpaper apply\n'; }
apply_brave_policy() { BRAVE_OPERATION_CONTEXT=$BRAVE_OPERATION_CONTEXT_ORDINARY; return "$BRAVE_OUTCOME_UNAVAILABLE"; }
apply_power_policy() { POWER_POLICY_OPERATION_CONTEXT=$POWER_POLICY_OPERATION_CONTEXT_ORDINARY; return 0; }
EOF
}

test_application_catalog_validation_is_strict() {
	new_fixture
	run_operation "$FIXTURE_ROOT" validate_application_catalog
	assert_eq 0 "$COMMAND_STATUS" 'the tracked optional application catalog should validate' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'catalog validation should not inspect package or user state' || return 1

	local filter expected
	while IFS='|' read -r filter expected; do
		new_fixture
		jq "$filter" "$FIXTURE_REPO/applications.json" >"$FIXTURE_REPO/applications.invalid"
		mv "$FIXTURE_REPO/applications.invalid" "$FIXTURE_REPO/applications.json"
		run_operation "$FIXTURE_ROOT" validate_application_catalog
		if [[ $COMMAND_STATUS -eq 0 ]]; then
			printf '  invalid application catalog was accepted: %s\n' "$filter" >&2
			return 1
		fi
		assert_contains "$COMMAND_OUTPUT" "$expected" "catalog rejection should identify $filter" || return 1
		assert_eq '' "$(<"$CALL_LOG")" 'rejected catalog data must not inspect packages or mutate state' || return 1
	done <<'EOF'
.unexpected = true|invalid optional application catalog
.applications[0].unexpected = true|invalid optional application metadata
del(.applications[0].description)|invalid optional application metadata
.applications[0].name = "   "|invalid optional application name or description
.applications[0].name = "Bruno\n"|invalid optional application name or description
.applications[0].description = "API client\n"|invalid optional application name or description
.applications[0].name = "Bru\u0001no"|invalid optional application name or description
.applications[0].description = "API\u0001 client"|invalid optional application name or description
.applications[0].id = "Bruno"|invalid optional application identifier
.applications[0].id = true|invalid optional application identifier
.applications[0].id = "bruno\n"|invalid optional application identifier
.applications[0].package = "bad/name"|invalid optional application package name
.applications[0].package = true|invalid optional application package name
.applications[0].package = "bruno-bin\n"|invalid optional application package name
.applications += [.applications[0]]|duplicate optional application identifier
.applications += [{id:"bruno-next", name:"Bruno next", description:"Duplicate package", package:"bruno-bin", source:"aur", command:"bruno-next", conflicts:[]}]|duplicate optional application package name
.applications += [{id:true, name:"Boolean identifier", description:"Mixed identifier collision", package:"boolean-identifier", source:"official", command:"boolean-identifier", conflicts:[]}, {id:"true", name:"String identifier", description:"Mixed identifier collision", package:"string-identifier", source:"official", command:"string-identifier", conflicts:[]}]|invalid optional application identifier
.applications += [{id:"boolean-package", name:"Boolean package", description:"Mixed package collision", package:true, source:"official", command:"boolean-package", conflicts:[]}, {id:"string-package", name:"String package", description:"Mixed package collision", package:"true", source:"official", command:"string-package", conflicts:[]}]|invalid optional application package name
.applications[0].source = "flatpak"|invalid optional application package source
.applications[0].command = "bad/name"|invalid optional application command
.applications[0].command = "bruno\n"|invalid optional application command
.applications[0].conflicts = ["bruno-bin"]|conflicts with itself
.applications[0].conflicts = ["bruno", "bruno"]|invalid optional application conflicts
.applications[0].conflicts = ["bruno\n"]|invalid optional application conflicts
.applications += [{id:"newline-id\n", name:"Newline identifier", description:"Collapsed identifier collision", package:"newline-identifier", source:"official", command:"newline-identifier", conflicts:[]}, {id:"newline-id", name:"Plain identifier", description:"Collapsed identifier collision", package:"plain-identifier", source:"official", command:"plain-identifier", conflicts:[]}]|invalid optional application identifier
EOF

	new_fixture
	printf '{"applications": [}\n' >"$FIXTURE_REPO/applications.json"
	run_operation "$FIXTURE_ROOT" validate_application_catalog
	assert_eq 1 "$COMMAND_STATUS" 'malformed application JSON should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'invalid optional application catalog' 'malformed JSON should name the catalog failure'
}

test_empty_and_unknown_application_selection_do_not_inspect_packages() {
	new_fixture
	run_operation "$FIXTURE_ROOT" install_optional_applications
	assert_eq 0 "$COMMAND_STATUS" 'an empty optional application selection should be a successful no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No optional applications selected; no changes made.' 'empty selection should report its no-op result' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'empty selection must not inspect packages, confirm, or mutate' || return 1

	new_fixture
	run_operation "$FIXTURE_ROOT" install_optional_applications missing-application
	assert_eq 1 "$COMMAND_STATUS" 'an unknown optional application should fail' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: unknown optional application selection: missing-application' 'unknown identifier should be named' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'unknown selection must stop before package inspection or mutation'
}

test_omarchy_probe_failure_stops_optional_application_installation() {
	new_fixture
	configure_optional_application_fakes
	stub_guided_non_application_phases
	make_fake omarchy 'printf "%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
	if [[ ${1-} == version ]]; then
		printf "Omarchy version probe failed\n" >&2
		exit 70
	fi
	printf "unexpected Omarchy command: %s\n" "$*" >&2
	exit 99'

	DOTFILES_TEST_INPUT='1\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'a failed Omarchy probe should stop the optional application operation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: optional application installation requires a successful Omarchy version probe.' \
		'the optional application operation should identify the unavailable version inspection' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: restore Omarchy version inspection, then choose Install optional applications in the Dotfiles wizard.' \
		'the optional application operation should provide recovery for the unavailable version inspection' || return 1
	assert_eq version "$(<"$CALL_LOG")" 'a failed Omarchy probe must stop before package inspection, confirmation, and mutation' || return 1

	new_fixture
	configure_optional_application_fakes
	DOTFILES_TEST_OMARCHY_VERSION=development DOTFILES_TEST_INPUT='y\nn\n' \
		run_operation "$FIXTURE_ROOT" install_optional_applications bruno

	assert_eq 1 "$COMMAND_STATUS" 'a nonempty named development version should follow the existing mismatch decision' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: development' \
		'a named nonnumeric version should remain a detected version rather than a failed probe' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Continue despite the Omarchy version mismatch?' \
		'a named nonnumeric version should retain the existing mismatch confirmation' || return 1
	if [[ $COMMAND_OUTPUT == *'requires a successful Omarchy version probe'* || $(<"$CALL_LOG") == *'pkg aur add bruno-bin'* ]]; then
		printf '  a nonempty named development version must not be treated as a failed probe or install after mismatch rejection\n' >&2
		return 1
	fi

	new_fixture
	configure_optional_application_fakes
	stub_guided_non_application_phases
	make_fake omarchy 'printf "%s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
	if [[ ${1-} == version ]]; then
		printf "4.0.0-1\n"
		printf "Omarchy version probe failed\n" >&2
		exit 70
	fi
	printf "unexpected Omarchy command: %s\n" "$*" >&2
	exit 99'

	DOTFILES_TEST_INPUT='1\n' run_operation "$FIXTURE_ROOT" guided_setup

	assert_eq 1 "$COMMAND_STATUS" 'a nonzero Omarchy probe with version-like output should stop the optional application operation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Error: optional application installation requires a successful Omarchy version probe.' \
		'the optional application operation should report the failed version-like probe' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: restore Omarchy version inspection, then choose Install optional applications in the Dotfiles wizard.' \
		'the optional application operation should provide recovery for the failed version-like probe' || return 1
	assert_eq version "$(<"$CALL_LOG")" 'a failed version-like probe must stop before package inspection, confirmation, and mutation' || return 1
	if [[ $COMMAND_OUTPUT == *'Supported Omarchy:'* || $COMMAND_OUTPUT == *'Detected Omarchy:'* ]]; then
		printf '  a strict optional application version probe must stop before version diagnostics\n' >&2
		return 1
	fi
}

test_public_action_installs_bruno_from_the_aur() {
	new_fixture
	configure_optional_application_fakes
	mkdir -p "$FIXTURE_CONFIG/bruno"
	printf 'application-owned Bruno state\n' >"$FIXTURE_CONFIG/bruno/bruno.db"
	local bruno_state_before
	bruno_state_before=$(sha256sum "$FIXTURE_CONFIG/bruno/bruno.db")
	DOTFILES_TEST_INPUT='1\ny\n' run_dotfiles "$FIXTURE_ROOT" --action applications

	assert_eq 0 "$COMMAND_STATUS" 'the optional-applications public action should install the selected application' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Bruno (bruno-bin, aur): pending' \
		'the complete plan should identify Bruno and its exact AUR package' || return 1
	assert_contains "$(<"$CALL_LOG")" 'pkg aur add bruno-bin' \
		"the selected AUR application should use Omarchy's AUR installation route" || return 1
	assert_eq "$bruno_state_before" "$(sha256sum "$FIXTURE_CONFIG/bruno/bruno.db")" \
		'the installer must leave Bruno application-owned state untouched'
}

test_selection_is_deduplicated_and_processed_in_catalog_order() {
	new_fixture
	add_official_optional_application alpha Alpha 'Official test application' alpha alpha
	configure_optional_application_fakes
	DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" install_optional_applications alpha bruno alpha

	assert_eq 0 "$COMMAND_STATUS" 'a deduplicated application selection should install successfully' || return 1
	assert_eq 1 "$(awk '/Bruno \(bruno-bin, aur\): pending/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'the AUR selection should appear once in the complete plan' || return 1
	assert_eq 1 "$(awk '/Alpha \(alpha, official\): pending/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'the official selection should appear once in the complete plan' || return 1
	assert_eq 1 "$(awk '/Install this complete optional application plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'the complete selected plan should require one ordinary confirmation' || return 1
	local aur_install official_install
	aur_install=$(awk '/^pkg aur add bruno-bin[|]/ { print NR; exit }' "$CALL_LOG")
	official_install=$(awk '/^pkg add alpha[|]/ { print NR; exit }' "$CALL_LOG")
	if [[ -z $aur_install || -z $official_install || $aur_install -ge $official_install ]]; then
		printf '  selected applications were not installed once in stable catalog order\n' >&2
		return 1
	fi
}

test_existing_installations_are_verified_without_confirmation_or_reinstallation() {
	new_fixture
	configure_optional_application_fakes
	set_installed_arch_packages bruno-bin
	make_bruno_command
	run_operation "$FIXTURE_ROOT" install_optional_applications bruno

	assert_eq 0 "$COMMAND_STATUS" 'a healthy exact Bruno installation should be a successful no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Bruno (bruno-bin, aur): installed' 'the plan should report the exact installed package' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Optional applications already installed and verified; no changes made.' \
		'healthy exact installations should report their no-op result' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg aur add bruno-bin'* || $COMMAND_OUTPUT == *'Install this complete optional application plan?'* ]]; then
		printf '  a healthy installed application must not be reinstalled or confirmed\n' >&2
		return 1
	fi
}

test_installed_application_with_missing_command_fails_verification() {
	new_fixture
	configure_optional_application_fakes
	set_installed_arch_packages bruno-bin
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) run_operation "$FIXTURE_ROOT" install_optional_applications bruno

	assert_eq 1 "$COMMAND_STATUS" 'an installed package without its declared command should fail verification' || return 1
	assert_contains "$COMMAND_OUTPUT" 'expected command is unavailable: bruno' 'the unavailable command should be explicit' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: resolve the reported issue, then choose Install optional applications in the Dotfiles wizard.' \
		'the verification failure should name the standalone recovery action' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg aur add bruno-bin'* || $COMMAND_OUTPUT == *'Install this complete optional application plan?'* ]]; then
		printf '  an installed application with a missing command must not be reinstalled or confirmed\n' >&2
		return 1
	fi
}

test_initial_verification_failure_reports_every_selected_application() {
	new_fixture
	jq '.applications = [
		{id:"alpha", name:"Alpha", description:"Earlier pending test application", package:"alpha", source:"official", command:"alpha", conflicts:[]},
		{id:"healthy-between", name:"Healthy Between", description:"Healthy installed test application", package:"healthy-between", source:"official", command:"healthy-between", conflicts:[]},
		.applications[0],
		{id:"healthy-after", name:"Healthy After", description:"Healthy installed test application", package:"healthy-after", source:"official", command:"healthy-after", conflicts:[]},
		{id:"omega", name:"Omega", description:"Later pending test application", package:"omega", source:"official", command:"omega", conflicts:[]}
	]' "$FIXTURE_REPO/applications.json" >"$FIXTURE_REPO/applications.updated"
	mv "$FIXTURE_REPO/applications.updated" "$FIXTURE_REPO/applications.json"
	configure_optional_application_fakes
	set_installed_arch_packages healthy-between bruno-bin healthy-after
	make_fake healthy-between 'exit 0'
	make_fake healthy-after 'exit 0'
	local package_state_before
	package_state_before=$(sha256sum "$ARCH_PACKAGE_STATE")
	DOTFILES_TEST_PATH=$(restricted_path_without_stow) \
		run_operation "$FIXTURE_ROOT" install_optional_applications omega healthy-after bruno alpha healthy-between

	assert_eq 1 "$COMMAND_STATUS" 'an unavailable command on an installed application should stop before mutation' || return 1
	local completed incomplete
	completed=${COMMAND_OUTPUT#*$'Completed applications:\n'}
	completed=${completed%%$'\nIncomplete applications:'*}
	incomplete=${COMMAND_OUTPUT#*$'Incomplete applications:\n'}
	incomplete=${incomplete%%$'\nRecovery:'*}
	assert_eq $'  Healthy Between (healthy-between)\n  Healthy After (healthy-after)' "$completed" \
		'every healthy exact selected application should be reported as completed' || return 1
	assert_eq $'  Alpha (alpha)\n  Bruno (bruno-bin)\n  Omega (omega)' "$incomplete" \
		'every selected application not completed before the initial verification failure should be incomplete in catalog order' || return 1
	assert_eq "$package_state_before" "$(sha256sum "$ARCH_PACKAGE_STATE")" \
		'initial verification failure must leave package state unchanged' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg add '* || $(<"$CALL_LOG") == *'pkg aur add '* || $COMMAND_OUTPUT == *'Install this complete optional application plan?'* ]]; then
		printf '  initial verification failure must stop before confirmation and package mutation\n' >&2
		return 1
	fi
}

test_conflicts_and_declined_plans_stop_before_mutation() {
	new_fixture
	configure_optional_application_fakes
	set_installed_arch_packages bruno
	run_operation "$FIXTURE_ROOT" install_optional_applications bruno

	assert_eq 1 "$COMMAND_STATUS" 'an installed declared conflict should block the optional application plan' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Conflict: Bruno (bruno-bin) cannot install because conflicting package bruno is installed.' \
		'conflict output should name the selected application and exact installed conflict' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg aur add bruno-bin'* || $COMMAND_OUTPUT == *'Install this complete optional application plan?'* ]]; then
		printf '  a declared conflict must stop before confirmation and mutation\n' >&2
		return 1
	fi

	new_fixture
	configure_optional_application_fakes
	DOTFILES_TEST_INPUT='n\n' run_operation "$FIXTURE_ROOT" install_optional_applications bruno
	assert_eq 0 "$COMMAND_STATUS" 'declining an optional application plan should be a successful skip' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No changes made.' 'declined plan should report no mutation' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg aur add bruno-bin'* ]]; then
		printf '  a declined optional application plan must not mutate package state\n' >&2
		return 1
	fi
}

test_selected_pending_application_conflicts_stop_before_mutation() {
	new_fixture
	jq '.applications = [
		{id:"alpha", name:"Alpha", description:"Official test application", package:"alpha", source:"official", command:"alpha", conflicts:["beta"]},
		{id:"beta", name:"Beta", description:"Official test application", package:"beta", source:"official", command:"beta", conflicts:[]}
	]' "$FIXTURE_REPO/applications.json" >"$FIXTURE_REPO/applications.updated"
	mv "$FIXTURE_REPO/applications.updated" "$FIXTURE_REPO/applications.json"
	configure_optional_application_fakes
	local package_state_before
	package_state_before=$(sha256sum "$ARCH_PACKAGE_STATE")

	run_operation "$FIXTURE_ROOT" install_optional_applications beta alpha

	assert_eq 1 "$COMMAND_STATUS" 'a declared conflict between pending selected applications should block the complete plan' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Conflict: Alpha (alpha) cannot install because its declared conflicting package beta is selected for Beta (beta).' \
		'the selected conflict should name both applications and their exact packages' || return 1
	assert_eq "$package_state_before" "$(sha256sum "$ARCH_PACKAGE_STATE")" \
		'a selected pending conflict must leave package state unchanged' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg add '* || $(<"$CALL_LOG") == *'pkg aur add '* || $COMMAND_OUTPUT == *'Install this complete optional application plan?'* ]]; then
		printf '  a selected pending conflict must stop before confirmation and package mutation\n' >&2
		return 1
	fi
}

test_mismatch_and_post_install_failures_are_bounded_and_recoverable() {
	new_fixture
	configure_optional_application_fakes
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\nn\n' run_operation "$FIXTURE_ROOT" install_optional_applications bruno

	assert_eq 1 "$COMMAND_STATUS" 'declining the supported-version decision should stop the operation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Supported Omarchy: 4' 'mismatch preflight should report the supported version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Detected Omarchy: 5.1.0' 'mismatch preflight should report the detected version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Continue despite the Omarchy version mismatch?' 'mismatch should require the established second decision' || return 1
	if [[ $(<"$CALL_LOG") == *'pkg aur add bruno-bin'* ]]; then
		printf '  declined version mismatch must stop before installation\n' >&2
		return 1
	fi

	new_fixture
	configure_optional_application_fakes
	DOTFILES_TEST_OMARCHY_VERSION=5.1.0 DOTFILES_TEST_INPUT='y\ny\n' run_operation "$FIXTURE_ROOT" install_optional_applications bruno
	assert_eq 0 "$COMMAND_STATUS" 'accepting the established mismatch decision should permit installation' || return 1
	assert_eq 1 "$(awk '/Install this complete optional application plan[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'the mismatch path should retain one ordinary installation confirmation' || return 1
	assert_eq 1 "$(awk '/Continue despite the Omarchy version mismatch[?]/ { count++ } END { print count + 0 }' <<<"$COMMAND_OUTPUT")" \
		'the mismatch path should retain one distinct compatibility decision' || return 1

	local failure expected
	while IFS='|' read -r failure expected; do
		new_fixture
		configure_optional_application_fakes
		case $failure in
			install) DOTFILES_TEST_APPLICATION_INSTALL_FAILURE=bruno-bin ;;
			exact) DOTFILES_TEST_APPLICATION_EXACT_VERIFY_FAILURE=bruno-bin ;;
			command) DOTFILES_TEST_APPLICATION_COMMAND_VERIFY_FAILURE=bruno-bin ;;
		esac
		if [[ $failure == command ]]; then
			DOTFILES_TEST_PATH=$(restricted_path_without_stow) DOTFILES_TEST_INPUT='y\n' \
				run_operation "$FIXTURE_ROOT" install_optional_applications bruno
		else
			DOTFILES_TEST_INPUT='y\n' run_operation "$FIXTURE_ROOT" install_optional_applications bruno
		fi
		unset DOTFILES_TEST_APPLICATION_INSTALL_FAILURE DOTFILES_TEST_APPLICATION_EXACT_VERIFY_FAILURE DOTFILES_TEST_APPLICATION_COMMAND_VERIFY_FAILURE
		assert_eq 1 "$COMMAND_STATUS" "$failure failure should fail installation" || return 1
		assert_contains "$COMMAND_OUTPUT" "$expected" "$failure failure should be visible" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Incomplete applications:' "$failure failure should report bounded recovery work" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Install optional applications in the Dotfiles wizard.' "$failure recovery should name the standalone action" || return 1
	done <<'EOF'
install|optional application installation failed for Bruno: bruno-bin
exact|optional application package verification failed for Bruno: bruno-bin
command|optional application command verification failed for Bruno: bruno
EOF

	new_fixture
	jq '.applications = [
		{id:"healthy-before", name:"Healthy Before", description:"Healthy installed test application", package:"healthy-before", source:"official", command:"healthy-before", conflicts:[]},
		{id:"alpha", name:"Alpha", description:"Official test application", package:"alpha", source:"official", command:"alpha", conflicts:[]},
		.applications[0],
		{id:"healthy-after", name:"Healthy After", description:"Healthy installed test application", package:"healthy-after", source:"official", command:"healthy-after", conflicts:[]},
		{id:"omega", name:"Omega", description:"Later official test application", package:"omega", source:"official", command:"omega", conflicts:[]}
	]' \
		"$FIXTURE_REPO/applications.json" >"$FIXTURE_REPO/applications.updated"
	mv "$FIXTURE_REPO/applications.updated" "$FIXTURE_REPO/applications.json"
	configure_optional_application_fakes
	set_installed_arch_packages healthy-before healthy-after
	make_fake healthy-before 'exit 0'
	make_fake healthy-after 'exit 0'
	DOTFILES_TEST_APPLICATION_INSTALL_FAILURE=bruno-bin DOTFILES_TEST_INPUT='y\n' \
		run_operation "$FIXTURE_ROOT" install_optional_applications omega healthy-after bruno alpha healthy-before
	unset DOTFILES_TEST_APPLICATION_INSTALL_FAILURE
	assert_eq 1 "$COMMAND_STATUS" 'a later failed application should stop the complete plan' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Completed applications:' 'partial failure should report completed work' || return 1
	assert_contains "$COMMAND_OUTPUT" '  Healthy Before (healthy-before)' 'healthy installed selections before a failure should be reported as completed' || return 1
	assert_contains "$COMMAND_OUTPUT" '  Alpha (alpha)' 'earlier verified installation should be retained and reported' || return 1
	assert_contains "$COMMAND_OUTPUT" '  Healthy After (healthy-after)' 'healthy installed selections after a failure should be reported as completed' || return 1
	local incomplete
	incomplete=${COMMAND_OUTPUT#*$'Incomplete applications:\n'}
	assert_contains "$incomplete" '  Bruno (bruno-bin)' 'the failed pending application should be incomplete' || return 1
	assert_contains "$incomplete" '  Omega (omega)' 'a later unattempted pending application should be incomplete' || return 1
	if [[ $incomplete == *'Healthy Before'* || $incomplete == *'Healthy After'* || $incomplete == *'Alpha'* ]]; then
		printf '  completed optional applications must not be reported as incomplete\n' >&2
		return 1
	fi
	if [[ $(<"$CALL_LOG") != *'pkg add alpha'* || $(<"$CALL_LOG") != *'pkg aur add bruno-bin'* ]]; then
		printf '  the partial failure fixture did not execute the expected stable installation sequence\n' >&2
		return 1
	fi
	if [[ $(<"$CALL_LOG") == *'pkg add omega'* ]]; then
		printf '  an installation failure must stop before later catalog applications\n' >&2
		return 1
	fi
}

test_gum_and_bash_pickers_start_empty_and_public_routes_dispatch() {
	new_fixture
	configure_optional_application_fakes
	DOTFILES_TEST_INPUT='\n' run_dotfiles "$FIXTURE_ROOT" --action applications
	assert_eq 0 "$COMMAND_STATUS" 'an empty Bash picker selection should succeed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Choose optional applications (none selected by default)' 'the Bash picker should state its empty default' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No optional applications selected; no changes made.' 'the Bash picker should pass an empty selection to the operation' || return 1
	assert_eq '' "$(<"$CALL_LOG")" 'an empty picker selection should not inspect packages or mutate' || return 1

	new_fixture
	configure_optional_application_fakes
	local empty_responses=$FIXTURE_ROOT/gum-empty-responses
	printf '\n' >"$empty_responses"
	make_gum_responder
	DOTFILES_UI=gum DOTFILES_TEST_GUM_RESPONSES=$empty_responses run_dotfiles "$FIXTURE_ROOT" --action applications
	assert_eq 0 "$COMMAND_STATUS" 'an empty Gum picker selection should be a successful no-op' || return 1
	assert_contains "$COMMAND_OUTPUT" 'No optional applications selected; no changes made.' \
		'an empty Gum picker selection should reach the shared no-op operation' || return 1
	if [[ $(<"$CALL_LOG") == *'version|'* || $(<"$CALL_LOG") == *'pkg '* ]]; then
		printf '  an empty Gum picker selection must not inspect packages or mutate\n' >&2
		return 1
	fi

	new_fixture
	configure_optional_application_fakes
	local responses=$FIXTURE_ROOT/gum-responses
	printf 'bruno\n' >"$responses"
	make_gum_responder
	DOTFILES_UI=gum DOTFILES_TEST_GUM_RESPONSES=$responses run_dotfiles "$FIXTURE_ROOT" --action applications
	assert_eq 0 "$COMMAND_STATUS" 'the Gum picker should dispatch the selected application to the shared operation' || return 1
	assert_contains "$(<"$CALL_LOG")" 'gum choose --no-limit --header Choose optional applications (none selected by default)' \
		'the Gum picker should be a multi-select with the explicit empty default' || return 1
	if [[ $(<"$CALL_LOG") == *'--selected='* ]]; then
		printf '  the optional application Gum picker must not preselect applications\n' >&2
		return 1
	fi

	new_fixture
	configure_optional_application_fakes
	make_fake gum 'printf "gum %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"; exit 75'
	DOTFILES_UI=gum run_dotfiles "$FIXTURE_ROOT" --action applications
	assert_eq 75 "$COMMAND_STATUS" 'a failed Gum application selection should preserve its failure status' || return 1
	if [[ $(<"$CALL_LOG") == *'version|'* || $(<"$CALL_LOG") == *'pkg '* ]]; then
		printf '  a failed Gum picker selection must stop before package inspection and mutation\n' >&2
		return 1
	fi

	new_fixture
	configure_optional_application_fakes
	DOTFILES_TEST_INPUT='1\ny\n' run_in_sandbox "$FIXTURE_ROOT" "$FIXTURE_BIN:/usr/bin:/bin" \
		make --no-print-directory -C "$FIXTURE_REPO" applications
	assert_eq 0 "$COMMAND_STATUS" 'make applications should invoke the public optional application action' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Installed and verified optional application: Bruno (bruno-bin)' \
		'the Make target should reuse the shared verified application operation' || return 1

	new_fixture
	configure_optional_application_fakes
	DOTFILES_TEST_INPUT='9\n1\ny\n' run_dotfiles "$FIXTURE_ROOT"
	assert_eq 0 "$COMMAND_STATUS" 'the top-level menu action should dispatch to optional application installation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Install optional applications' 'the top-level menu should expose the standalone optional application action'
}

test_guided_setup_places_the_shared_operation_after_cleanup() {
	local outcome input expected_status
	while IFS='|' read -r outcome input expected_status; do
		new_fixture
		configure_optional_application_fakes
		stub_guided_non_application_phases
		case $outcome in
			healthy)
				set_installed_arch_packages bruno-bin
				make_bruno_command
				;;
		esac
		DOTFILES_TEST_INPUT="$input" run_operation "$FIXTURE_ROOT" guided_setup
		assert_eq "$expected_status" "$COMMAND_STATUS" "$outcome Guided application outcome should have its expected status" || return 1
		local cleanup applications stow
		cleanup=$(awk '/Guided phase 3:/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
		applications=$(awk '/Guided phase 4: optional application installation/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
		stow=$(awk '/Guided phase 5: Stow application/ { print NR; exit }' <<<"$COMMAND_OUTPUT")
		if [[ -z $cleanup || -z $applications || -z $stow || $cleanup -ge $applications || $applications -ge $stow ]]; then
			printf '  Guided setup did not place %s optional applications after cleanup and before Stow\n' "$outcome" >&2
			return 1
		fi
		assert_contains "$COMMAND_OUTPUT" 'Guided setup complete.' "$outcome optional application result should continue Guided setup"
	done <<'EOF'
empty|\n|0
declined|1\nn\n|0
healthy|1\n|0
success|1\ny\n|0
EOF

	new_fixture
	configure_optional_application_fakes
	stub_guided_non_application_phases
	DOTFILES_TEST_APPLICATION_INSTALL_FAILURE=bruno-bin DOTFILES_TEST_INPUT='1\ny\n' run_operation "$FIXTURE_ROOT" guided_setup
	unset DOTFILES_TEST_APPLICATION_INSTALL_FAILURE
	assert_eq 1 "$COMMAND_STATUS" 'an optional application failure should stop Guided setup' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Install optional applications in the Dotfiles wizard.' \
		'Guided failure should name the standalone recovery action' || return 1
	if [[ $COMMAND_OUTPUT == *'Guided phase 5: Stow application'* || $COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
		printf '  Guided setup continued after optional application installation failed\n' >&2
		return 1
	fi

	local failure input
	for failure in catalog selection conflict; do
		new_fixture
		configure_optional_application_fakes
		stub_guided_non_application_phases
		case $failure in
			catalog)
				jq '.unexpected = true' "$FIXTURE_REPO/applications.json" >"$FIXTURE_REPO/applications.invalid"
				mv "$FIXTURE_REPO/applications.invalid" "$FIXTURE_REPO/applications.json"
				input=''
				;;
			selection) input='99\n' ;;
			conflict)
				set_installed_arch_packages bruno
				input='1\n'
				;;
		esac
		DOTFILES_TEST_INPUT="$input" run_operation "$FIXTURE_ROOT" guided_setup
		assert_eq 1 "$COMMAND_STATUS" "$failure application preflight failure should stop Guided setup" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Recovery: choose Install optional applications in the Dotfiles wizard.' \
			"$failure application preflight failure should name the standalone recovery action" || return 1
		if [[ $COMMAND_OUTPUT == *'Guided phase 5: Stow application'* || $COMMAND_OUTPUT == *'Guided setup complete.'* ]]; then
			printf '  Guided setup continued after %s optional application preflight failure\n' "$failure" >&2
			return 1
		fi
	done
}

set -e
run_test test_application_catalog_validation_is_strict 'optional application catalog validation is strict'
run_test test_empty_and_unknown_application_selection_do_not_inspect_packages 'empty and unknown application selections stop before package inspection'
run_test test_omarchy_probe_failure_stops_optional_application_installation 'Omarchy probe failure stops optional application installation'
run_test test_public_action_installs_bruno_from_the_aur 'public action installs Bruno from the AUR'
run_test test_selection_is_deduplicated_and_processed_in_catalog_order 'application selections are deduplicated and use catalog order'
run_test test_existing_installations_are_verified_without_confirmation_or_reinstallation 'existing applications are verified without confirmation or reinstallation'
run_test test_installed_application_with_missing_command_fails_verification 'installed applications with missing commands fail verification'
run_test test_initial_verification_failure_reports_every_selected_application 'initial verification failure reports every selected application'
run_test test_conflicts_and_declined_plans_stop_before_mutation 'conflicts and declined plans stop before optional application mutation'
run_test test_selected_pending_application_conflicts_stop_before_mutation 'selected pending application conflicts stop before mutation'
run_test test_mismatch_and_post_install_failures_are_bounded_and_recoverable 'mismatch and post-install failures are bounded and recoverable'
run_test test_gum_and_bash_pickers_start_empty_and_public_routes_dispatch 'Gum and Bash pickers start empty and public routes dispatch'
run_test test_guided_setup_places_the_shared_operation_after_cleanup 'Guided setup places the shared operation after cleanup'
finish_tests
