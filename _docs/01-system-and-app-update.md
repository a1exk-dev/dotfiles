# System and App Updates

Starting point for keeping the system, apps, and firmware up to date.

## Initial Setup

Install base development tools and yay (AUR helper):

```sh
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay.git
cd yay && makepkg -si && cd .. && rm -rf yay
```

## Update System

Refresh and update:

```sh
yay -Syu
```

## COSMIC Theme (EverForest Dark Hard)

Theme source (download "EverForest"):
- https://cosmic-themes.org/?search=everforest&sort=popular&color=%23000000

Apply via GUI (upload a theme file).
1. Open COSMIC Settings.
2. Go to Appearance -> Themes.
3. Select the import or upload option.
4. Choose the EverForest (dark hard) theme file.
5. Apply the theme and confirm it is active.

## Virtual Console (vconsole)

TTY font and keyboard settings:

```sh
sudo cp vconsole.conf /etc/vconsole.conf
```
