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

Link Everforest theme:

```sh
mkdir -p ~/.config/sysc-greet/themes ~/.config/sysc-greet/ascii_configs
ln -sf ~/Projects/dotfiles/sysc-greet/themes/everforest-hard.toml ~/.config/sysc-greet/themes/everforest-hard.toml
ln -sf ~/Projects/dotfiles/sysc-greet/ascii_configs/hyprland.conf ~/.config/sysc-greet/ascii_configs/hyprland.conf
```

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
