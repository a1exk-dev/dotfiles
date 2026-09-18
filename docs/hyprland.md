[Back to README](../README.md)

# Hyprland

The `hyprland` Stow package tracks the Hyprland configuration both machines share, and one profile for each machine.

These shared files link into `~/.config/hypr/`:

- `input.lua` sets `kb_layout = "us,ru"` with Omarchy's `grp:alts_toggle`. Left Alt + Right Alt switches the layout.
- `bindings.lua` holds the hotkeys that work on every machine, such as the Discord Ctrl+M mute toggle.
- `monitors.lua` loads the selected machine profile. It applies Omarchy's defaults when you select no profile.

These machine profiles link into `~/.config/dotfiles/hypr/`:

- `pc/monitors.lua` and `pc/bindings.lua`
- `laptop/monitors.lua` and `laptop/bindings.lua`

Applying the package does not change the active display or hotkey configuration. `Select Hyprland profile` does that. It points `~/.config/hypr/machine` at one profile directory and owns that link alone. You choose the machine. The action does not read the hostname.

The package does not own:

- Omarchy's packaged Hyprland defaults below `/usr/share/omarchy/`
- Hyprland, its plugins, and its runtime state
- The screen-sharing portal and its runtime configuration

See [Stow workflow](stow.md) for the shared Stow package lifecycle.

## Requirements

The package declares the `hyprland` Arch package and the `hyprctl` prerequisite.

## Apply

Start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages` and select `hyprland`. Then choose `Select Hyprland profile` and select `pc` or `laptop`. You can also run `bin/dotfiles --action hypr-profile`.

The action reports the current selection. It backs up an existing `~/.config/hypr/machine` below the XDG state backup tree, links the selected profile, reloads Hyprland, and makes sure the configuration parses.

Hyprland reads `GDK_SCALE` when it starts. A profile that changes `GDK_SCALE` needs a new session, not a reload.

## The pc profile

`pc/monitors.lua` configures a Gigabyte MO27Q2 on DP-1 at `2560x1440@240` with scale 1.25.

The profile sets this mode explicitly. The monitor's EDID gives `2560x1440@59.95` as its preferred timing and keeps the 240 Hz mode in a DisplayID extension block. Thus `mode = "preferred"` selects 60 Hz on a 240 Hz panel.

## The laptop profile

`laptop/monitors.lua` keeps Omarchy's defaults. Replace its `hl.monitor` call when you know the laptop's output name and modes. To list them, run `hyprctl monitors all` on that machine.
