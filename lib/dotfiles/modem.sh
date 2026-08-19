readonly MODEM_XHCI_DRIVER=/sys/bus/pci/drivers/xhci_hcd
readonly MODEM_XHCI_UNBIND=/sys/bus/pci/drivers/xhci_hcd/unbind
readonly MODEM_XHCI_BIND=/sys/bus/pci/drivers/xhci_hcd/bind
readonly MODEM_VERIFY_TIMEOUT_SECONDS=30

MODEM_USB_PATH=''
MODEM_USB_PRODUCT=''
MODEM_CONTROLLER_BDF=''
MODEM_NMCLI_STATE=''
MODEM_NMCLI_STATUS=0
declare -a MODEM_INTERFACES=()

modem_recovery_hint() {
	printf 'Recovery: rerun the Dotfiles wizard and choose Recover ZTE USB modem.\n' >&2
}

modem_preflight() {
	local runtime missing=false
	for runtime in readlink sudo sh sleep nmcli; do
		if ! command -v "$runtime" >/dev/null 2>&1; then
			printf 'Error: missing modem recovery runtime command: %s\n' "$runtime" >&2
			missing=true
		fi
	done
	if [[ $missing == true ]]; then
		modem_recovery_hint
		return 1
	fi
}

modem_read_attribute() {
	local attribute=$1 value=''
	[[ -r $attribute ]] || return 1
	if ! IFS= read -r value <"$attribute"; then
		[[ -n $value ]] || return 1
	fi
	printf '%s\n' "$value"
}

modem_detect_usb_device() {
	local candidate vendor product canonical
	local -a matches=() products=()
	for candidate in /sys/bus/usb/devices/*; do
		[[ -e $candidate ]] || continue
		vendor=$(modem_read_attribute "$candidate/idVendor" 2>/dev/null) || continue
		product=$(modem_read_attribute "$candidate/idProduct" 2>/dev/null) || continue
		if [[ $vendor == 19d2 && ( $product == 1225 || $product == 1405 ) ]]; then
			matches+=("$candidate")
			products+=("$product")
		fi
	done

	if ((${#matches[@]} != 1)); then
		printf 'Error: expected exactly one ZTE USB modem (19d2:1225 or 19d2:1405); found %d.\n' "${#matches[@]}" >&2
		modem_recovery_hint
		return 1
	fi
	if ! canonical=$(readlink -f -- "${matches[0]}") || [[ ! -d $canonical || $canonical != /sys/devices/* ]]; then
		printf 'Error: could not resolve a canonical /sys/devices path for ZTE USB modem %s.\n' "${matches[0]}" >&2
		modem_recovery_hint
		return 1
	fi

	MODEM_USB_PATH=$canonical
	MODEM_USB_PRODUCT=${products[0]}
}

modem_resolve_xhci_controller() {
	local current=$MODEM_USB_PATH driver bdf
	MODEM_CONTROLLER_BDF=''
	while [[ $current == /sys/devices/* ]]; do
		if [[ -L $current/driver ]] && driver=$(readlink -f -- "$current/driver" 2>/dev/null) && [[ $driver == "$MODEM_XHCI_DRIVER" ]]; then
			bdf=${current##*/}
			if [[ ! $bdf =~ ^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\.[0-7]$ ]]; then
				printf 'Error: invalid xHCI controller PCI BDF: %s\n' "$bdf" >&2
				modem_recovery_hint
				return 1
			fi
			MODEM_CONTROLLER_BDF=$bdf
			return 0
		fi
		current=${current%/*}
	done

	printf 'Error: no PCI ancestor bound to xhci_hcd was found for %s.\n' "$MODEM_USB_PATH" >&2
	modem_recovery_hint
	return 1
}

modem_validate_reset_endpoints() {
	local driver endpoint canonical
	if [[ ! -d $MODEM_XHCI_DRIVER || -L $MODEM_XHCI_DRIVER ]] || \
		! driver=$(readlink -f -- "$MODEM_XHCI_DRIVER") || [[ $driver != "$MODEM_XHCI_DRIVER" ]]; then
		printf 'Error: invalid fixed xHCI driver path: %s\n' "$MODEM_XHCI_DRIVER" >&2
		modem_recovery_hint
		return 1
	fi
	for endpoint in "$MODEM_XHCI_UNBIND" "$MODEM_XHCI_BIND"; do
		if [[ ! -f $endpoint || -L $endpoint ]] || \
			! canonical=$(readlink -f -- "$endpoint") || [[ $canonical != "$endpoint" ]]; then
			printf 'Error: invalid fixed xHCI reset endpoint: %s\n' "$endpoint" >&2
			modem_recovery_hint
			return 1
		fi
	done
}

modem_reset_controller() {
	sudo sh -c '
controller=$1
unbind_endpoint=$2
bind_endpoint=$3
printf "%s\n" "$controller" >"$unbind_endpoint" || exit 1
sleep_status=0
sleep 2 || sleep_status=$?
printf "%s\n" "$controller" >"$bind_endpoint" || exit 1
exit "$sleep_status"
' modem-reset "$MODEM_CONTROLLER_BDF" "$MODEM_XHCI_UNBIND" "$MODEM_XHCI_BIND"
}

modem_collect_interfaces() {
	local usb_path=$1 network_path interface existing duplicate
	MODEM_INTERFACES=()
	for network_path in "$usb_path"/*/net/*; do
		[[ -e $network_path ]] || continue
		interface=${network_path##*/}
		duplicate=false
		for existing in "${MODEM_INTERFACES[@]}"; do
			if [[ $existing == "$interface" ]]; then
				duplicate=true
				break
			fi
		done
		[[ $duplicate == true ]] || MODEM_INTERFACES+=("$interface")
	done
}

modem_interface_connected() {
	local interface=$1
	MODEM_NMCLI_STATE=''
	MODEM_NMCLI_STATUS=0
	if MODEM_NMCLI_STATE=$(LC_ALL=C nmcli -g GENERAL.STATE device show "$interface" 2>&1); then
		:
	else
		MODEM_NMCLI_STATUS=$?
		return 2
	fi
	[[ $MODEM_NMCLI_STATE =~ ^100([[:space:]]|\(|$) ]]
}

modem_guard_initialized_product() {
	modem_collect_interfaces "$MODEM_USB_PATH"
	((${#MODEM_INTERFACES[@]} > 0)) || return 1

	local interface connection_status
	if ((${#MODEM_INTERFACES[@]} == 1)); then
		interface=${MODEM_INTERFACES[0]}
		if modem_interface_connected "$interface"; then
			printf 'ZTE USB modem is already connected on interface %s; no controller reset needed.\n' "$interface"
			return 0
		else
			connection_status=$?
		fi

		printf 'Error: ZTE USB modem mode 19d2:1405 is already initialized on interface %s; the USB controller will not be reset.\n' "$interface" >&2
		if ((connection_status == 2)); then
			printf 'nmcli could not report the interface state (exit %d): %s\n' "$MODEM_NMCLI_STATUS" "${MODEM_NMCLI_STATE:-no diagnostic output}" >&2
		else
			printf 'nmcli reports interface %s is not connected: %s\n' "$interface" "${MODEM_NMCLI_STATE:-empty state}" >&2
		fi
	else
		printf 'Error: ZTE USB modem mode 19d2:1405 is already initialized with multiple network interfaces; the USB controller will not be reset.\n' >&2
		for interface in "${MODEM_INTERFACES[@]}"; do
			if modem_interface_connected "$interface"; then
				printf '  %s: nmcli reports %s\n' "$interface" "$MODEM_NMCLI_STATE" >&2
			else
				connection_status=$?
				if ((connection_status == 2)); then
					printf '  %s: nmcli query failed (exit %d): %s\n' "$interface" "$MODEM_NMCLI_STATUS" "${MODEM_NMCLI_STATE:-no diagnostic output}" >&2
				else
					printf '  %s: nmcli reports %s\n' "$interface" "${MODEM_NMCLI_STATE:-empty state}" >&2
				fi
			fi
		done
	fi
	printf 'Recovery: troubleshoot NetworkManager or modem connectivity; USB network mode is already initialized.\n' >&2
	return 2
}

modem_verify_recovery() {
	local elapsed vendor product interface connection_status
	local diagnostic="USB path $MODEM_USB_PATH has not reappeared."
	for ((elapsed = 0; elapsed <= MODEM_VERIFY_TIMEOUT_SECONDS; elapsed++)); do
		vendor=$(modem_read_attribute "$MODEM_USB_PATH/idVendor" 2>/dev/null) || vendor=''
		product=$(modem_read_attribute "$MODEM_USB_PATH/idProduct" 2>/dev/null) || product=''
		if [[ $vendor == 19d2 && $product == 1405 ]]; then
			modem_collect_interfaces "$MODEM_USB_PATH"
			if ((${#MODEM_INTERFACES[@]} == 0)); then
				diagnostic="USB modem 19d2:1405 has no sysfs network interface at $MODEM_USB_PATH."
			elif ((${#MODEM_INTERFACES[@]} > 1)); then
				diagnostic="USB modem 19d2:1405 has multiple sysfs network interfaces: ${MODEM_INTERFACES[*]}."
			else
				interface=${MODEM_INTERFACES[0]}
				if modem_interface_connected "$interface"; then
					printf 'ZTE USB modem recovered and connected on interface %s.\n' "$interface"
					return 0
				else
					connection_status=$?
					if ((connection_status == 2)); then
						diagnostic="nmcli could not report the state of interface $interface (exit $MODEM_NMCLI_STATUS): ${MODEM_NMCLI_STATE:-no diagnostic output}."
					else
						diagnostic="nmcli reports interface $interface is not connected yet: ${MODEM_NMCLI_STATE:-empty state}."
					fi
				fi
			fi
		elif [[ -n $vendor || -n $product ]]; then
			diagnostic="USB path $MODEM_USB_PATH reports ${vendor:-unknown}:${product:-unknown}, not 19d2:1405."
		else
			diagnostic="USB path $MODEM_USB_PATH is not currently available."
		fi

		if ((elapsed < MODEM_VERIFY_TIMEOUT_SECONDS)); then
			if ! sleep 1; then
				printf 'Error: modem recovery verification could not wait for the device.\n' >&2
				modem_recovery_hint
				return 1
			fi
		fi
	done
	printf 'Error: ZTE USB modem recovery verification timed out after %d seconds.\n' "$MODEM_VERIFY_TIMEOUT_SECONDS" >&2
	printf 'Verification: %s\n' "$diagnostic" >&2
	modem_recovery_hint
	return 1
}

recover_zte_usb_modem() {
	local initialized_status
	modem_preflight || return 1
	modem_detect_usb_device || return 1
	if [[ $MODEM_USB_PRODUCT == 1405 ]]; then
		if modem_guard_initialized_product; then
			return 0
		else
			initialized_status=$?
		fi
		((initialized_status == 1)) || return 1
	fi
	modem_resolve_xhci_controller || return 1
	modem_validate_reset_endpoints || return 1

	printf 'Plan: recover ZTE USB modem\n'
	printf '  USB device: 19d2:%s\n' "$MODEM_USB_PRODUCT"
	printf '  USB sysfs path: %s\n' "$MODEM_USB_PATH"
	printf '  xHCI controller: %s\n' "$MODEM_CONTROLLER_BDF"
	printf '  Reset: unbind the controller, wait 2 seconds, then bind it again.\n'
	printf '  Verify: the same USB path reports 19d2:1405, exposes a network interface, and nmcli reports it connected.\n'
	printf '  Warning: every USB device on this controller will briefly disconnect.\n'
	if ! wizard_confirm 'Reset this xHCI controller to recover the ZTE USB modem?'; then
		printf 'No changes made.\n'
		return 0
	fi

	if ! modem_reset_controller; then
		printf 'Error: failed to reset xHCI controller %s for ZTE USB modem recovery.\n' "$MODEM_CONTROLLER_BDF" >&2
		printf 'Recovery: reboot if xHCI controller %s did not rebind; otherwise rerun the Dotfiles wizard and choose Recover ZTE USB modem.\n' "$MODEM_CONTROLLER_BDF" >&2
		return 1
	fi
	modem_verify_recovery
}
