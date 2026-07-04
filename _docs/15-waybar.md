# Waybar

Waybar status bar configuration.

## Installation

```sh
sudo pacman -S --needed waybar jq socat swaync
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
