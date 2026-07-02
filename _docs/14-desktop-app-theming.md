# Desktop App Theming

Tools and commands for theming GTK, Qt5, and Qt6 applications on a Wayland desktop.

## Tool Map

- `nwg-look` - GTK settings editor for wlroots compositors such as Hyprland.
- `lxappearance` - GTK theme/icon/font selector, useful fallback for GTK2/GTK3 apps.
- `xsettingsd` - exposes GTK-style XSETTINGS to X11/Xwayland applications.
- `qt5ct` - Qt5 theme, icon, font, and palette configuration tool.
- `qt6ct` - Qt6 theme, icon, font, and palette configuration tool.
- `kvantum` - SVG style engine and manager for Qt6.
- `kvantum-qt5` - Kvantum style engine support for Qt5.

## Install Tools

Install the core theming tools on Arch:

```sh
sudo pacman -S --needed nwg-look lxappearance xsettingsd qt5ct qt6ct qt5-wayland qt6-wayland kvantum kvantum-qt5
```

Optional common theme packages:

```sh
sudo pacman -S --needed papirus-icon-theme materia-gtk-theme breeze-gtk
```

Install additional GTK, icon, cursor, and Kvantum themes as needed from the Arch repositories, AUR, or upstream theme releases.

## Theme Locations

User-installed themes usually go here:

```sh
~/.local/share/themes
~/.local/share/icons
~/.themes
~/.icons
```

System-wide themes usually go here:

```sh
/usr/share/themes
/usr/share/icons
```

Prefer `~/.local/share/themes` and `~/.local/share/icons` for manually downloaded themes.

## GTK Apps

Use `nwg-look` first on Hyprland:

```sh
nwg-look
```

Use `lxappearance` if a GTK2/GTK3 app does not follow the expected settings:

```sh
lxappearance
```

GTK settings usually land in these files:

```sh
~/.config/gtk-3.0/settings.ini
~/.config/gtk-4.0/settings.ini
~/.gtkrc-2.0
```

Check the current GNOME interface settings used by many GTK apps:

```sh
gsettings get org.gnome.desktop.interface gtk-theme
gsettings get org.gnome.desktop.interface icon-theme
gsettings get org.gnome.desktop.interface cursor-theme
gsettings get org.gnome.desktop.interface color-scheme
```

Set GTK theme values manually if needed:

```sh
gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
```

Avoid setting `GTK_THEME` globally unless an app needs a forced override. It can make GTK4/libadwaita apps behave inconsistently.

## Xwayland GTK Settings

Some X11/Xwayland apps read XSETTINGS instead of Wayland desktop settings. Use `xsettingsd` for those cases.

Create a minimal config:

```sh
cat > ~/.xsettingsd <<'EOF'
Net/ThemeName "Materia-dark"
Net/IconThemeName "Papirus-Dark"
Gtk/CursorThemeName "Adwaita"
Gtk/FontName "Sans 10"
EOF
```

Start it manually:

```sh
xsettingsd
```

Autostart it from Hyprland if needed:

```ini
exec-once = xsettingsd
```

## Qt5 and Qt6 Apps

Install both `qt5ct` and `qt6ct` if both Qt5 and Qt6 apps are used.

Run the configuration tools:

```sh
qt5ct
qt6ct
```

Qt settings usually land in these files:

```sh
~/.config/qt5ct/qt5ct.conf
~/.config/qt6ct/qt6ct.conf
```

Qt apps need `QT_QPA_PLATFORMTHEME` to choose the platform theme plugin:

```sh
QT_QPA_PLATFORMTHEME=qt5ct qt5ct
QT_QPA_PLATFORMTHEME=qt6ct qt6ct
```

The `QT_QPA_PLATFORMTHEME` variable is shared by Qt5 and Qt6. Pick the best default for the apps used most often, then override individual apps if needed.

Example for a Qt6 default:

```sh
QT_QPA_PLATFORMTHEME=qt6ct dolphin
```

Example for a Qt5 override:

```sh
QT_QPA_PLATFORMTHEME=qt5ct keepassxc
```

If using KDE Plasma settings instead of `qt5ct` or `qt6ct`, use `QT_QPA_PLATFORMTHEME=kde` instead.

## Kvantum

Kvantum provides a Qt style engine. It is usually the best option for making Qt apps visually match GTK themes.

Open Kvantum Manager:

```sh
kvantummanager
```

Choose or install a Kvantum theme in the manager.

Then open `qt5ct` and `qt6ct`, set the widget style to `Kvantum`, and save.

Kvantum settings usually land in:

```sh
~/.config/Kvantum/kvantum.kvconfig
~/.config/Kvantum/<theme-name>/<theme-name>.kvconfig
```

To force Kvantum for Qt apps, set:

```sh
QT_STYLE_OVERRIDE=kvantum
```

## Hyprland Environment

For Hyprland, export Qt environment variables from the Hyprland config.

Example using `qt6ct` as the default platform theme and Kvantum as the Qt style:

```ini
env = QT_QPA_PLATFORM,wayland;xcb
env = QT_QPA_PLATFORMTHEME,qt6ct
env = QT_STYLE_OVERRIDE,kvantum
```

If most Qt apps are Qt5, use this instead:

```ini
env = QT_QPA_PLATFORM,wayland;xcb
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_STYLE_OVERRIDE,kvantum
```

After changing Hyprland environment variables, log out and back in so newly launched apps inherit them.

For user services and D-Bus activated apps, import the variables into the user systemd and D-Bus environment:

```sh
systemctl --user import-environment QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE XCURSOR_THEME XCURSOR_SIZE
dbus-update-activation-environment --systemd QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE XCURSOR_THEME XCURSOR_SIZE
```

## Verification

Check environment variables:

```sh
printenv | grep -E '^(GTK|QT|XCURSOR)_'
```

Check GTK settings:

```sh
gsettings get org.gnome.desktop.interface gtk-theme
gsettings get org.gnome.desktop.interface icon-theme
gsettings get org.gnome.desktop.interface color-scheme
```

Check Qt tools:

```sh
qt5ct
qt6ct
kvantummanager
```

Launch one Qt app with explicit settings to test overrides:

```sh
QT_QPA_PLATFORMTHEME=qt6ct QT_STYLE_OVERRIDE=kvantum dolphin
```

Launch one GTK app with a temporary forced theme only for testing:

```sh
GTK_THEME=Materia-dark gtk4-demo
```

If `gtk4-demo` is missing, install GTK demo packages or test with another GTK app.

## Troubleshooting

If Qt apps ignore `qt5ct` or `qt6ct`, check `QT_QPA_PLATFORMTHEME`:

```sh
printenv QT_QPA_PLATFORMTHEME
```

If a Qt5 app ignores a `qt6ct` default, launch it with a Qt5 override:

```sh
QT_QPA_PLATFORMTHEME=qt5ct app-name
```

If a Qt6 app ignores a `qt5ct` default, launch it with a Qt6 override:

```sh
QT_QPA_PLATFORMTHEME=qt6ct app-name
```

If Qt apps ignore Kvantum, confirm `QT_STYLE_OVERRIDE` and select `Kvantum` inside `qt5ct` or `qt6ct`:

```sh
printenv QT_STYLE_OVERRIDE
kvantummanager
```

If GTK4/libadwaita apps ignore the GTK theme, that can be expected. Many libadwaita apps intentionally limit external theme control. Prefer matching icons, cursor, font, dark mode, and accent colors where possible.
