# greetd + sysc-greet

greetd is a lightweight login manager with sysc-greet (TUI greeter with ASCII art and themes).

## Installation

Install greetd and sysc-greet for Hyprland:

```sh
sudo pacman -S greetd
yay -S sysc-greet-hyprland
```

## Post-install

Create greeter user:

```sh
sudo useradd -M -G video -s /usr/bin/nologin greeter
sudo mkdir -p /var/cache/sysc-greet /var/lib/greeter/Pictures/wallpapers
sudo chown -R greeter:greeter /var/cache/sysc-greet /var/lib/greeter
sudo chmod 755 /var/lib/greeter
```

## Link config

Link greetd config:

```sh
sudo mkdir -p /etc/greetd
sudo ln -sf ~/Projects/dotfiles/greetd/config.toml /etc/greetd/config.toml
```

Link the ASCII layout and install the shared theme manager:

```sh
mkdir -p ~/.config/sysc-greet/ascii_configs
ln -sf ~/Projects/dotfiles/sysc-greet/ascii_configs/hyprland.conf ~/.config/sysc-greet/ascii_configs/hyprland.conf
stow --no-folding -t "$HOME" theme-tools
dotfiles-theme install
dotfiles-theme sync-greeter
```

In the greeter's theme menu, select the custom theme named `current` once. Use `sysc-greet --test` to preview the configuration. Later `sync-greeter` runs use `sudo -u greeter` to atomically update the selected file without root destination writes, preference or cache edits, or a greetd restart. See [Theme management](21-theme.md).

## Enable greetd

```sh
sudo systemctl enable greetd
sudo systemctl start greetd
```

## Test configuration

Test sysc-greet without restarting:

```sh
sysc-greet --test
```

## Reboot to test
