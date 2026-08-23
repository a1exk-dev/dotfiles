[Back to README](../README.md)

# ZTE USB modem recovery

Use this guide for the ZTE modem that appears as `19d2:1225` in storage mode and `19d2:1405` in network mode. Linux uses `cdc_ether` for network mode, so NetworkManager treats the modem as Ethernet. ModemManager is not required.

## Recover the modem

Start the Dotfiles wizard:

```bash
make
```

Choose `Recover ZTE USB modem`.

To skip the menu, run:

```bash
./bin/dotfiles --action modem
```

The recovery action detects the modem and its xHCI controller. It does not depend on USB path `2-2` or PCI address `0000:c6:00.0`.

The action does not reset a modem that already has a network interface in mode `1405`. It returns success if NetworkManager says the interface is connected. If the interface exists but is disconnected, it stops and reports that NetworkManager or the modem connection needs attention.

For a stuck modem, the action shows the detected controller and asks for confirmation. It then:

1. Unbinds the xHCI controller.
2. Waits two seconds.
3. Binds the controller again.
4. Waits for the modem to enter mode `1405`.
5. Verifies that NetworkManager connects the new Ethernet interface.

The controller reset briefly disconnects every USB device on that controller. Disconnect external USB storage first. Do not reset a controller that provides storage used by the running system or a mounted filesystem.

The action installs no packages and changes no persistent configuration.

## Identify the known failure

Check NetworkManager and the recent kernel log:

```bash
nmcli -f DEVICE,TYPE,STATE,CONNECTION device status
journalctl -k -b --since "5 minutes ago" \
  --grep="usb|ZTE|cdc_ether" --case-sensitive=no --no-pager
```

The known failure contains:

```text
New USB device found, idVendor=19d2, idProduct=1405
can't set config #1, error -110
```

The modem can then return to `19d2:1225`. NetworkManager shows no new Ethernet interface because USB initialization failed.

Do not use this recovery procedure for a different device ID or error without checking the cause.

## Use it after an OS reinstall

Run the wizard action again after reinstalling the OS:

```bash
./bin/dotfiles --action modem
```

The action discovers the current USB path and PCI controller. Do not reuse an old PCI address in a manual command without checking it first.

Check that the new OS provides `cdc_ether`:

```bash
modinfo -F filename cdc_ether
```

## Manual fallback for this laptop

Use the manual command only if the wizard cannot run.

First confirm that `c6:00.0` is an xHCI USB controller:

```bash
lspci -nnk -s c6:00.0
```

The output must contain:

```text
Kernel driver in use: xhci_hcd
```

Reset the controller:

```bash
sudo sh -c '
printf "%s" "0000:c6:00.0" > /sys/bus/pci/drivers/xhci_hcd/unbind
sleep 2
printf "%s" "0000:c6:00.0" > /sys/bus/pci/drivers/xhci_hcd/bind
'
```

Wait about 10 seconds for NetworkManager to connect the modem.

## Verify internet access

Find the modem interface:

```bash
nmcli -f DEVICE,TYPE,STATE,CONNECTION device status
ip -brief address
```

On this laptop, the interface is `enp198s0f0u2`. Replace the name if it changed:

```bash
interface=enp198s0f0u2
ip route get 1.1.1.1
ping -I "$interface" -c 3 -W 3 1.1.1.1
resolvectl query --interface="$interface" example.com
curl --interface "$interface" \
  --connect-timeout 10 --max-time 20 \
  --silent --show-error --output /dev/null \
  --write-out "%{http_code}\n" \
  https://connectivitycheck.gstatic.com/generate_204
```

A working connection returns ping replies, a DNS answer, and HTTP status `204`. The interface-bound checks prevent Wi-Fi from producing a false result.
