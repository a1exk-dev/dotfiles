#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly MODEM_USB_PATH=7-2.4
readonly MODEM_BDF=0000:42:00.3
readonly MODEM_INTERFACE=wwan-test0
readonly SANDBOX_XHCI_UNBIND=/sys/bus/pci/drivers/xhci_hcd/unbind
readonly SANDBOX_XHCI_BIND=/sys/bus/pci/drivers/xhci_hcd/bind

configure_modem_fixture() {
	MODEM_SYSFS=$FIXTURE_ROOT/sys
	XHCI_UNBIND=$MODEM_SYSFS/bus/pci/drivers/xhci_hcd/unbind
	XHCI_BIND=$MODEM_SYSFS/bus/pci/drivers/xhci_hcd/bind
	NMCLI_CALL_COUNT=$FIXTURE_ROOT/nmcli-call-count
	mkdir -p "$MODEM_SYSFS/bus/usb/devices" "$MODEM_SYSFS/bus/pci/drivers/xhci_hcd" \
		"$MODEM_SYSFS/devices" "$MODEM_SYSFS/class/net"
	printf 'untouched-unbind\n' >"$XHCI_UNBIND"
	printf 'untouched-bind\n' >"$XHCI_BIND"
	printf '0\n' >"$NMCLI_CALL_COUNT"
	BWRAP_EXTRA_ARGS=(--bind "$MODEM_SYSFS" /sys)

	make_fake sleep '
{
	printf "sleep"
	for argument in "$@"; do printf " [%q]" "$argument"; done
	printf "\n"
} >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${DOTFILES_TEST_IN_SUDO-false} == true && ${1-} == 2 ]]; then
	[[ $(</sys/bus/pci/drivers/xhci_hcd/unbind) =~ ^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\.[0-7]$ ]] || exit 78
	fixture_root=${DOTFILES_TEST_CALL_LOG%/*}
	if [[ -e $fixture_root/bind-failure ]]; then
		[[ -d /sys/bus/pci/drivers/xhci_hcd/bind ]] || exit 79
	else
		[[ $(</sys/bus/pci/drivers/xhci_hcd/bind) == untouched-bind ]] || exit 79
	fi
fi'
	make_fake sudo '
{
	printf "sudo"
	for argument in "$@"; do printf " [%q]" "$argument"; done
	printf "\n"
} >>"$DOTFILES_TEST_CALL_LOG"
fixture_root=${DOTFILES_TEST_CALL_LOG%/*}
[[ ! -e $fixture_root/sudo-failure ]] || exit 73
if [[ -e $fixture_root/bind-failure ]]; then
	rm -f /sys/bus/pci/drivers/xhci_hcd/bind
	mkdir /sys/bus/pci/drivers/xhci_hcd/bind
fi
DOTFILES_TEST_IN_SUDO=true "$@"
command_status=$?
((command_status == 0)) || exit "$command_status"
[[ ! -e $fixture_root/skip-modem-reenumeration ]] || exit 0
for device in /sys/bus/usb/devices/*; do
	[[ ${device##*/} != *:* && -f $device/idVendor && -f $device/idProduct ]] || continue
	[[ $(<"$device/idVendor") == 19d2 ]] || continue
	product=$(<"$device/idProduct")
	[[ $product == 1225 || $product == 1405 ]] || continue
	physical_path=${device##*/}
	canonical_device=$(readlink -f -- "$device")
	interface_device=$canonical_device/$physical_path:1.0
	printf "1405\n" >"$device/idProduct"
	mkdir -p "$interface_device/net/wwan-test0"
	ln -s "../../../${interface_device#/sys/}" "/sys/bus/usb/devices/$physical_path:1.0"
done'
	make_fake nmcli '
{
	printf "nmcli"
	for argument in "$@"; do printf " [%q]" "$argument"; done
	printf "\n"
} >>"$DOTFILES_TEST_CALL_LOG"
fixture_root=${DOTFILES_TEST_CALL_LOG%/*}
call_count=$(<"$fixture_root/nmcli-call-count")
call_count=$((call_count + 1))
printf "%s\n" "$call_count" >"$fixture_root/nmcli-call-count"
if [[ -e $fixture_root/nmcli-disconnected ]]; then
	state=disconnected
	state_number=30
elif [[ -e $fixture_root/nmcli-connect-after ]]; then
	connect_after=$(<"$fixture_root/nmcli-connect-after")
	if ((call_count >= connect_after)); then
		state=connected
		state_number=100
	elif ((call_count == 1)); then
		state=connecting
		state_number=40
	else
		state=disconnected
		state_number=30
	fi
else
	state=connected
	state_number=100
fi
if [[ " $* " == *" device status "* || " $* " == *" dev status "* ]]; then
	printf "wwan-test0:%s\n" "$state"
else
	printf "%s (%s)\n" "$state_number" "$state"
fi'
}

add_pci_usb_device() {
	local usb_path=$1 vendor=$2 product=$3 bdf=$4 driver=$5
	local controller=$MODEM_SYSFS/devices/pci0000:00/$bdf
	local device=$controller/usb7/$usb_path
	mkdir -p "$device" "$MODEM_SYSFS/bus/pci/drivers/$driver"
	if [[ ! -e $controller/driver && ! -L $controller/driver ]]; then
		ln -s "../../../bus/pci/drivers/$driver" "$controller/driver"
	fi
	printf '%s\n' "$vendor" >"$device/idVendor"
	printf '%s\n' "$product" >"$device/idProduct"
	ln -s "../../../devices/pci0000:00/$bdf/usb7/$usb_path" \
		"$MODEM_SYSFS/bus/usb/devices/$usb_path"
}

add_pci_usb_interface() {
	local usb_path=$1 bdf=$2 interface=${3:-$MODEM_INTERFACE}
	local interface_device=$MODEM_SYSFS/devices/pci0000:00/$bdf/usb7/$usb_path/$usb_path:1.0
	mkdir -p "$interface_device/net/$interface"
	ln -s "../../../devices/pci0000:00/$bdf/usb7/$usb_path/$usb_path:1.0" \
		"$MODEM_SYSFS/bus/usb/devices/$usb_path:1.0"
}

add_non_pci_usb_device() {
	local usb_path=$1 vendor=$2 product=$3
	local controller=$MODEM_SYSFS/devices/platform/test-controller
	local device=$controller/usb7/$usb_path
	mkdir -p "$device"
	ln -s ../../../bus/pci/drivers/xhci_hcd "$controller/driver"
	printf '%s\n' "$vendor" >"$device/idVendor"
	printf '%s\n' "$product" >"$device/idProduct"
	ln -s "../../../devices/platform/test-controller/usb7/$usb_path" \
		"$MODEM_SYSFS/bus/usb/devices/$usb_path"
}

run_modem_action() {
	run_dotfiles "$FIXTURE_ROOT" --action modem
}

logged_call_count() {
	local executable=$1
	awk -v executable="$executable" '$1 == executable { count++ } END { print count + 0 }' "$CALL_LOG"
}

logged_sleep_count() {
	local seconds=$1
	awk -v argument="[$seconds]" '$1 == "sleep" && $2 == argument { count++ } END { print count + 0 }' "$CALL_LOG"
}

confirmation_count() {
	awk -F '\\[y/N\\]' '{ count += NF - 1 } END { print count + 0 }' <<<"$1"
}

assert_no_privileged_modem_mutation() {
	assert_eq untouched-unbind "$(<"$XHCI_UNBIND")" 'xHCI unbind must remain untouched' || return 1
	assert_eq untouched-bind "$(<"$XHCI_BIND")" 'xHCI bind must remain untouched' || return 1
	assert_eq 0 "$(logged_call_count sudo)" 'sudo must not run before valid discovery and confirmation'
}

assert_complete_modem_plan() {
	local output=$1 lower_output=${1,,}
	assert_contains "$output" "$MODEM_USB_PATH" 'the plan should name the detected physical USB path' || return 1
	assert_contains "$output" 19d2 'the plan should name the detected vendor ID' || return 1
	assert_contains "$output" 1225 'the plan should name the detected product ID' || return 1
	assert_contains "$output" "$MODEM_BDF" 'the plan should name the detected xHCI controller BDF' || return 1
	if [[ $lower_output != *'sleep 2'* && $lower_output != *'2 second'* && \
		$lower_output != *'2-second'* && $lower_output != *'two-second'* ]]; then
		printf '  the plan should disclose the two-second reset delay\n' >&2
		return 1
	fi
	assert_contains "$output" 1405 'the plan should name the required post-reset product ID' || return 1
	assert_contains "$lower_output" network 'the plan should disclose network-interface verification' || return 1
	assert_contains "$lower_output" nmcli 'the plan should disclose connected-state verification'
}

test_zero_matching_devices_stops_before_privilege() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device 7-1 19d2 9999 0000:42:00.1 xhci_hcd
	add_pci_usb_device 7-2 1234 1225 0000:42:00.2 xhci_hcd
	run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'zero matching ZTE devices should fail discovery' || return 1
	assert_contains "${COMMAND_OUTPUT,,}" zte 'zero-match output should identify the expected device' || return 1
	assert_no_privileged_modem_mutation || return 1
	assert_eq 9999 "$(<"$MODEM_SYSFS/bus/usb/devices/7-1/idProduct")" 'discovery must not alter a nonmatching ZTE product' || return 1
	assert_eq 1225 "$(<"$MODEM_SYSFS/bus/usb/devices/7-2/idProduct")" 'discovery must not alter another vendor'
}

test_multiple_matching_devices_stop_before_privilege() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device 7-1 19d2 1225 0000:42:00.1 xhci_hcd
	add_pci_usb_device 7-2 19d2 1405 0000:42:00.2 xhci_hcd
	run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'multiple matching ZTE devices should fail discovery' || return 1
	assert_contains "${COMMAND_OUTPUT,,}" zte 'multiple-match output should identify the ambiguous device type' || return 1
	assert_no_privileged_modem_mutation || return 1
	assert_eq 1225 "$(<"$MODEM_SYSFS/bus/usb/devices/7-1/idProduct")" 'ambiguous discovery must leave the first device unchanged' || return 1
	assert_eq 1405 "$(<"$MODEM_SYSFS/bus/usb/devices/7-2/idProduct")" 'ambiguous discovery must leave the second device unchanged'
}

test_invalid_pci_ancestry_stops_before_privilege() {
	new_fixture
	configure_modem_fixture
	add_non_pci_usb_device "$MODEM_USB_PATH" 19d2 1225
	run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'a matching device without a PCI controller ancestor should fail' || return 1
	assert_contains "${COMMAND_OUTPUT,,}" xhci 'invalid ownership output should identify the required controller type' || return 1
	assert_no_privileged_modem_mutation || return 1
	assert_eq 1225 "$(<"$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH/idProduct")" 'invalid ancestry must leave the modem unchanged'
}

test_non_xhci_controller_stops_before_privilege() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1225 "$MODEM_BDF" ehci-pci
	run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'a matching device owned by a non-xHCI controller should fail' || return 1
	assert_contains "${COMMAND_OUTPUT,,}" xhci 'non-xHCI ownership output should identify the required driver' || return 1
	assert_no_privileged_modem_mutation || return 1
	assert_eq 1225 "$(<"$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH/idProduct")" 'non-xHCI ownership must leave the modem unchanged'
}

test_confirmation_decline_preserves_the_complete_plan_boundary() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1225 "$MODEM_BDF" xhci_hcd
	DOTFILES_TEST_INPUT='n\n' run_modem_action

	assert_eq 0 "$COMMAND_STATUS" 'declining the reset should be a safe no-op' || return 1
	assert_complete_modem_plan "$COMMAND_OUTPUT" || return 1
	assert_eq 1 "$(confirmation_count "$COMMAND_OUTPUT")" \
		'the complete modem plan should have one confirmation boundary' || return 1
	assert_no_privileged_modem_mutation || return 1
	assert_eq 1225 "$(<"$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH/idProduct")" 'declining must leave the modem product unchanged'
}

test_initialized_connected_modem_skips_reset() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1405 "$MODEM_BDF" xhci_hcd
	add_pci_usb_interface "$MODEM_USB_PATH" "$MODEM_BDF"
	run_modem_action

	assert_eq 0 "$COMMAND_STATUS" 'an initialized and connected modem should succeed without a reset' || return 1
	assert_eq 0 "$(confirmation_count "$COMMAND_OUTPUT")" 'an already connected modem should not request reset confirmation' || return 1
	assert_no_privileged_modem_mutation || return 1
	assert_eq 1 "$(logged_call_count nmcli)" 'the initialized interface should be checked once through nmcli' || return 1
	assert_eq 0 "$(logged_call_count sleep)" 'an already connected modem should not wait for reset or verification' || return 1
	assert_contains "${COMMAND_OUTPUT,,}" 'already connected' 'success should explain that the modem is already connected' || return 1
	assert_contains "$COMMAND_OUTPUT" "$MODEM_INTERFACE" 'already-connected success should name the interface'
}

test_initialized_disconnected_modem_stops_without_reset() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1405 "$MODEM_BDF" xhci_hcd
	add_pci_usb_interface "$MODEM_USB_PATH" "$MODEM_BDF"
	: >"$FIXTURE_ROOT/nmcli-disconnected"
	run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'an initialized but disconnected modem should require NetworkManager attention' || return 1
	assert_eq 0 "$(confirmation_count "$COMMAND_OUTPUT")" 'an initialized modem should not request reset confirmation' || return 1
	assert_no_privileged_modem_mutation || return 1
	assert_eq 1 "$(logged_call_count nmcli)" 'the initialized interface should be checked once through nmcli' || return 1
	assert_eq 0 "$(logged_call_count sleep)" 'an initialized modem should not enter reset verification polling' || return 1
	assert_contains "${COMMAND_OUTPUT,,}" initialized 'failure should explain that USB mode is initialized' || return 1
	assert_contains "${COMMAND_OUTPUT,,}" networkmanager 'failure should direct attention to NetworkManager'
}

test_initialized_modem_without_interface_remains_reset_eligible() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1405 "$MODEM_BDF" xhci_hcd
	DOTFILES_TEST_INPUT='n\n' run_modem_action

	assert_eq 0 "$COMMAND_STATUS" 'declining reset for an interface-less 1405 modem should be a safe no-op' || return 1
	assert_eq 1 "$(confirmation_count "$COMMAND_OUTPUT")" 'a 1405 modem without an interface should remain eligible for reset' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Plan: recover ZTE USB modem' 'the stuck 1405 path should reach the reset plan' || return 1
	assert_eq 0 "$(logged_call_count nmcli)" 'an absent interface should not be queried through nmcli' || return 1
	assert_no_privileged_modem_mutation || return 1
	assert_eq 1405 "$(<"$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH/idProduct")" 'declining reset should leave the initialized USB mode unchanged'
}

test_success_resets_the_detected_controller_and_verifies_connection() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1225 "$MODEM_BDF" xhci_hcd
	add_pci_usb_device 3-9 1234 1225 0000:03:00.0 xhci_hcd
	DOTFILES_TEST_INPUT='y\n' run_modem_action

	local calls sudo_call canonical_device interface_device parent_sibling bus_interface
	calls=$(<"$CALL_LOG")
	sudo_call=$(awk '$1 == "sudo" { print; exit }' "$CALL_LOG")
	canonical_device=$MODEM_SYSFS/devices/pci0000:00/$MODEM_BDF/usb7/$MODEM_USB_PATH
	interface_device=$canonical_device/$MODEM_USB_PATH:1.0
	parent_sibling=${canonical_device%/*}/$MODEM_USB_PATH:1.0
	bus_interface=$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH:1.0
	assert_eq 0 "$COMMAND_STATUS" 'a confirmed reset with connected re-enumeration should succeed' || return 1
	assert_eq 1 "$(logged_call_count sudo)" 'the complete reset should use one sudo boundary' || return 1
	assert_contains "$sudo_call" '[sh] [-c]' 'the privileged reset should use sudo sh -c' || return 1
	assert_contains "$sudo_call" "[$SANDBOX_XHCI_UNBIND]" 'the fixed xHCI unbind endpoint should be a positional value' || return 1
	assert_contains "$sudo_call" "[$MODEM_BDF]" 'the detected controller BDF should be a positional value' || return 1
	assert_contains "$sudo_call" "[$SANDBOX_XHCI_BIND]" 'the fixed xHCI bind endpoint should be a positional value' || return 1
	assert_contains "$calls" 'sleep [2]' 'the privileged reset should wait exactly two seconds between endpoints' || return 1
	assert_eq "$MODEM_BDF" "$(<"$XHCI_UNBIND")" 'unbind should receive exactly the detected controller BDF' || return 1
	assert_eq "$MODEM_BDF" "$(<"$XHCI_BIND")" 'bind should receive exactly the detected controller BDF' || return 1
	assert_eq 1405 "$(<"$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH/idProduct")" 'the same physical USB path should re-enumerate as product 1405' || return 1
	[[ -d $interface_device/net/$MODEM_INTERFACE ]] || {
		printf '  the canonical USB device child did not expose the fixture network interface\n' >&2
		return 1
	}
	[[ -L $bus_interface ]] || {
		printf '  the USB bus interface entry is not a sysfs symlink\n' >&2
		return 1
	}
	assert_eq "../../../devices/pci0000:00/$MODEM_BDF/usb7/$MODEM_USB_PATH/$MODEM_USB_PATH:1.0" "$(readlink "$bus_interface")" \
		'the USB bus interface entry should resolve to the canonical device child' || return 1
	if [[ -e $parent_sibling ]]; then
		printf '  the fixture created an incorrect interface beside the canonical USB device\n' >&2
		return 1
	fi
	assert_eq 1 "$(logged_call_count nmcli)" 'connected state should be verified once through nmcli' || return 1
	assert_contains "$calls" "$MODEM_INTERFACE" 'nmcli should inspect the discovered network interface' || return 1
	assert_contains "$COMMAND_OUTPUT" "$MODEM_INTERFACE" 'success should name the connected network interface' || return 1
	assert_eq 1225 "$(<"$MODEM_SYSFS/bus/usb/devices/3-9/idProduct")" 'reset simulation must not alter an unrelated USB path'
}

test_nmcli_transient_states_are_polled_until_connected() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1225 "$MODEM_BDF" xhci_hcd
	printf '3\n' >"$FIXTURE_ROOT/nmcli-connect-after"
	DOTFILES_TEST_INPUT='y\n' run_modem_action

	assert_eq 0 "$COMMAND_STATUS" 'a modem that connects within the verification deadline should succeed' || return 1
	assert_eq 3 "$(<"$NMCLI_CALL_COUNT")" 'nmcli should be polled through connecting, disconnected, and connected states' || return 1
	assert_eq 3 "$(logged_call_count nmcli)" 'each state transition should use a distinct nmcli query' || return 1
	assert_eq 2 "$(logged_sleep_count 1)" 'transient nmcli states should wait between connection polls' || return 1
	assert_contains "$COMMAND_OUTPUT" "$MODEM_INTERFACE" 'eventual connection success should name the network interface'
}

test_sudo_failure_does_not_mutate_or_report_success() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1225 "$MODEM_BDF" xhci_hcd
	: >"$FIXTURE_ROOT/sudo-failure"
	DOTFILES_TEST_INPUT='y\n' run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'a failed privileged reset should fail the action' || return 1
	assert_eq 1 "$(logged_call_count sudo)" 'the failed reset should make only its one planned sudo call' || return 1
	assert_eq 0 "$(logged_call_count sleep)" 'sudo failure should stop before the reset delay' || return 1
	assert_eq 0 "$(logged_call_count nmcli)" 'sudo failure should stop before connection verification' || return 1
	assert_eq untouched-unbind "$(<"$XHCI_UNBIND")" 'sudo failure should leave unbind untouched' || return 1
	assert_eq untouched-bind "$(<"$XHCI_BIND")" 'sudo failure should leave bind untouched' || return 1
	assert_eq 1225 "$(<"$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH/idProduct")" 'sudo failure should not simulate re-enumeration'
}

test_failed_rebind_advises_reboot_recovery() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1225 "$MODEM_BDF" xhci_hcd
	: >"$FIXTURE_ROOT/bind-failure"
	DOTFILES_TEST_INPUT='y\n' run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'a failed controller rebind should fail modem recovery' || return 1
	assert_eq "$MODEM_BDF" "$(<"$XHCI_UNBIND")" 'the partial reset should prove that unbind succeeded' || return 1
	[[ -d $XHCI_BIND ]] || {
		printf '  the bind endpoint fixture did not force the rebind failure\n' >&2
		return 1
	}
	assert_eq 0 "$(logged_call_count nmcli)" 'a failed rebind should stop before modem verification' || return 1
	assert_contains "${COMMAND_OUTPUT,,}" reboot 'partial reset failure should advise reboot recovery'
}

test_missing_post_reset_reenumeration_fails_verification() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1225 "$MODEM_BDF" xhci_hcd
	: >"$FIXTURE_ROOT/skip-modem-reenumeration"
	DOTFILES_TEST_INPUT='y\n' run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'missing product and interface re-enumeration should fail verification' || return 1
	assert_eq "$MODEM_BDF" "$(<"$XHCI_UNBIND")" 'post-reset failure should occur after the exact unbind' || return 1
	assert_eq "$MODEM_BDF" "$(<"$XHCI_BIND")" 'post-reset failure should occur after the exact bind' || return 1
	assert_eq 1225 "$(<"$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH/idProduct")" 'failed re-enumeration should remain at the original product' || return 1
	assert_eq 0 "$(logged_call_count nmcli)" 'nmcli should not run before product and interface verification succeeds'
}

test_disconnected_nmcli_state_times_out_after_bounded_polling() {
	new_fixture
	configure_modem_fixture
	add_pci_usb_device "$MODEM_USB_PATH" 19d2 1225 "$MODEM_BDF" xhci_hcd
	: >"$FIXTURE_ROOT/nmcli-disconnected"
	DOTFILES_TEST_INPUT='y\n' run_modem_action

	assert_eq 1 "$COMMAND_STATUS" 'a persistently disconnected nmcli state should fail post-reset verification' || return 1
	assert_eq 1405 "$(<"$MODEM_SYSFS/bus/usb/devices/$MODEM_USB_PATH/idProduct")" 'nmcli failure should happen after re-enumeration as product 1405' || return 1
	assert_eq 31 "$(<"$NMCLI_CALL_COUNT")" 'nmcli should be queried at every point in the 30-second verification window' || return 1
	assert_eq 31 "$(logged_call_count nmcli)" 'the bounded polling loop should issue 31 nmcli checks including time zero' || return 1
	assert_eq 30 "$(logged_sleep_count 1)" 'the bounded polling loop should use fast fixture sleeps for the full deadline' || return 1
	assert_contains "$(<"$CALL_LOG")" "$MODEM_INTERFACE" 'disconnected verification should query the discovered interface' || return 1
	if [[ ${COMMAND_OUTPUT,,} == *'recovered and connected'* ]]; then
		printf '  disconnected verification reported modem recovery success\n' >&2
		return 1
	fi
}

set -e
run_test test_zero_matching_devices_stops_before_privilege 'zero matching devices stop before privilege'
run_test test_multiple_matching_devices_stop_before_privilege 'multiple matching devices stop before privilege'
run_test test_invalid_pci_ancestry_stops_before_privilege 'invalid PCI ancestry stops before privilege'
run_test test_non_xhci_controller_stops_before_privilege 'non-xHCI ownership stops before privilege'
run_test test_confirmation_decline_preserves_the_complete_plan_boundary 'confirmation decline preserves the complete plan boundary'
run_test test_initialized_connected_modem_skips_reset 'initialized connected modem skips reset'
run_test test_initialized_disconnected_modem_stops_without_reset 'initialized disconnected modem stops without reset'
run_test test_initialized_modem_without_interface_remains_reset_eligible 'initialized modem without interface remains reset eligible'
run_test test_success_resets_the_detected_controller_and_verifies_connection 'successful reset uses the detected xHCI controller and verifies connection'
run_test test_nmcli_transient_states_are_polled_until_connected 'transient nmcli states are polled until connected'
run_test test_sudo_failure_does_not_mutate_or_report_success 'sudo failure does not mutate or report success'
run_test test_failed_rebind_advises_reboot_recovery 'failed rebind advises reboot recovery'
run_test test_missing_post_reset_reenumeration_fails_verification 'missing post-reset re-enumeration fails verification'
run_test test_disconnected_nmcli_state_times_out_after_bounded_polling 'disconnected nmcli state times out after bounded polling'
finish_tests
