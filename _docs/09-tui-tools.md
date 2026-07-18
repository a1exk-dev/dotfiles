# TUI Tools

Additional terminal UI tools.

## Installation

```sh
yay -S btop lazygit lazydocker wlctl-bin bluetui
```

Stow the btop configuration from the repository root:

```sh
stow --adopt -t "$HOME" btop
```

## Wi-Fi Backend

`wlctl-bin` provides `wlctl`, a Wi-Fi TUI that uses NetworkManager.

Install the NetworkManager backend packages:

```sh
sudo pacman -S --needed networkmanager wpa_supplicant systemd-resolvconf
```

Enable NetworkManager and systemd-resolved:

```sh
sudo systemctl enable --now NetworkManager systemd-resolved
```

Only enable the standalone `wpa_supplicant` service if it is needed outside NetworkManager. NetworkManager can manage `wpa_supplicant` itself on most setups.

```sh
sudo systemctl enable --now wpa_supplicant
```

## Tools

- **btop** - Resource monitor configured with the built-in Everforest Dark Hard theme
- **lazygit** - Terminal UI for git
- **lazydocker** - Terminal UI for docker
- **wlctl** - Terminal UI for Wi-Fi using NetworkManager
- **bluetui** - Terminal UI for Bluetooth (bluetoothctl wrapper)
