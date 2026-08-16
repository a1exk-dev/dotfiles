# Waybar

Waybar status bar configuration.

## Installation

```sh
sudo pacman -S --needed waybar jq socat swaync noto-fonts-emoji pipewire geoclue psmisc dbus v4l-utils
```

## Link config

```sh
stow --no-folding -t "$HOME" theme-tools
dotfiles-theme install
```

The manager restows Waybar, supplies its CSS, JSON, and widget color environment from the active bundle, and keeps the old `colors.css` path bridged. `dotfiles-theme set everforest-hard` sends `SIGUSR2` only to exact current-user Waybar PIDs. See [Theme management](21-theme.md).

## Custom widgets

- `jq` builds JSON for custom modules.
- `socat` listens to the Hyprland event socket for instant workspace updates; without it, the workspace widget falls back to polling once per second.
- `hyprctl` comes from Hyprland and is used by the workspace widget.
- `swaync-client` opens the notification center and reports notification mute state.

## Keyboard layout

The `hyprland/language` module displays the US or Russian flag. Click the flag to switch every connected keyboard to the next layout; `Super+Space` provides the same action. `noto-fonts-emoji` provides the flag glyphs.

## Privacy widget

The privacy widget always displays microphone, camera, and location indicators. Grey means inactive, red means active, and orange means a detector is unavailable.

- `pw-dump` and `pw-mon` detect active PipeWire microphone and camera streams.
- `fuser`, provided by `psmisc`, detects applications that open ALSA capture or V4L2 devices directly; `v4l2-ctl` filters out metadata and virtual video nodes.
- `busctl` reads GeoClue's global location-in-use state, and `dbus-monitor` watches for changes.

The tooltip identifies microphone and camera applications and PIDs when available. GeoClue intentionally hides client identities from other processes, so active location use cannot be attributed to an application. Denied device opens and location providers that bypass GeoClue are outside the widget's detection scope.

## Network widget

The network icon uses Waybar's network module and opens `wlctl` on click. Wi-Fi control through `wlctl` requires NetworkManager with the WPA supplicant utilities installed:

```sh
sudo pacman -S --needed networkmanager wpa_supplicant
sudo systemctl enable --now NetworkManager
```

NetworkManager can start `wpa_supplicant` itself; the standalone `wpa_supplicant.service` usually does not need to be enabled.
