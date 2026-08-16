# TradingView

TradingView's strict Snap is based on `core20` and uses the older `gnome-3-28-1804` desktop runtime. On current Arch and Hyprland, its bundled GNOME/Mesa stack fails when it uses native Wayland. The verified workaround is to run it through XWayland with `--ozone-platform=x11`.

## Install

On Arch, install Snapd from the AUR, enable its socket, install XWayland, and install TradingView:

```sh
yay -S snapd
sudo systemctl enable --now snapd.socket
sudo pacman -S xorg-xwayland
sudo snap install tradingview
```

Log out and back in after installing Snapd so its environment is available to desktop launchers. On other distributions, use the distribution's Snapd and XWayland installation instructions.

## Stow

From the repository root, preview and apply the desktop override:

```sh
stow -n -v --no-folding -t "$HOME" tradingview
stow --no-folding -t "$HOME" tradingview
update-desktop-database "$HOME/.local/share/applications"
```

The database update registers the `tradingview://` login callback declared by the desktop override. The matching `tradingview_tradingview.desktop` filename makes the user entry override the generated Snap entry without modifying `/var/lib/snapd`. Both the override and the zsh function add `--ozone-platform=x11`: a bare `tradingview` command works in a fresh zsh, and the TradingView entry in Wofi's drun mode uses the same workaround. Extra terminal arguments and desktop `%U` URLs are preserved.

## Verify

```sh
zsh -n zsh/.zshrc
desktop-file-validate tradingview/.local/share/applications/tradingview_tradingview.desktop
zsh -lic 'whence -w tradingview; functions tradingview'
readlink -f "$HOME/.local/share/applications/tradingview_tradingview.desktop"
gio mime x-scheme-handler/tradingview
gtk-launch tradingview_tradingview
```

After launching, `hyprctl clients` should show a mapped TradingView window with XWayland enabled. Quit and relaunch TradingView after changing the desktop override; an already-running Electron process may reuse its existing window.
