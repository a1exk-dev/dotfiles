# SwayNC

Notification daemon and control center.

## Installation

```sh
sudo pacman -S --needed swaync
```

## Link config

```sh
stow --no-folding -t "$HOME" theme-tools
dotfiles-theme install
```

The manager restows SwayNC and loads palette definitions from the active bundle. A theme change runs `swaync-client --reload-css --skip-wait`; it never restarts SwayNC. See [Theme management](21-theme.md).

## Reload config and style

```sh
swaync-client --reload-config
swaync-client --reload-css
```

If `config.json` itself was added after SwayNC already started, restart it once manually:

```sh
systemctl --user restart swaync.service
```

The config enables a native DND notification toggle, the MPRIS media player widget, and an icon-only quick-action button grid. Edit scripts in `~/.config/swaync/scripts/` to change app button behavior.
