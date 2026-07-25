# Waybar

Waybar status bar configuration.

## Installation

```sh
sudo pacman -S --needed waybar jq socat swaync noto-fonts-emoji
```

## Link config

```sh
stow --adopt -t "$HOME" waybar
```

## Custom widgets

- `jq` builds JSON for custom modules.
- `socat` listens to the Hyprland event socket for instant workspace updates; without it, the workspace widget falls back to polling once per second.
- `hyprctl` comes from Hyprland and is used by the workspace widget.
- `swaync-client` opens the notification center and reports notification mute state.

## Keyboard layout

The `hyprland/language` module displays the US or Russian flag. Click the flag to switch every connected keyboard to the next layout; `Super+Space` provides the same action. `noto-fonts-emoji` provides the flag glyphs.

## Network widget

The network icon uses Waybar's network module and opens `wlctl` on click. Wi-Fi control through `wlctl` requires NetworkManager with the WPA supplicant utilities installed:

```sh
sudo pacman -S --needed networkmanager wpa_supplicant
sudo systemctl enable --now NetworkManager
```

NetworkManager can start `wpa_supplicant` itself; the standalone `wpa_supplicant.service` usually does not need to be enabled.
