# SwayNC

Notification daemon and control center.

## Installation

```sh
sudo pacman -S --needed swaync
```

## Link config

```sh
stow --adopt -t "$HOME" swaync
```

## Reload config and style

```sh
swaync-client --reload-config
swaync-client --reload-css
```

If `config.json` was added after SwayNC already started, restart it once:

```sh
systemctl --user restart swaync.service
```

The config enables a native DND notification toggle, the MPRIS media player widget, and an icon-only quick-action button grid. Edit scripts in `~/.config/swaync/scripts/` to change app button behavior.
