# Ghostty

The `ghostty` Stow package owns `~/.config/ghostty/config` and `~/.config/ghostty/tab-bar.css`. GNU Stow links them to the matching paths under `config/ghostty/` in this repository. The tracked main config replaces Omarchy's main Ghostty config because Omarchy has no separate user override for persistent opacity. See [Stow workflow](stow.md) for behavior shared by all packages.

The package does not track:

- Omarchy's generated palette at `~/.local/state/omarchy/current/theme/ghostty.conf`
- Ghostty application state or caches
- Migration backups
- Packaged Omarchy files below `/usr/share/omarchy/`

## Prerequisite

The package manages configuration only. If the `ghostty` command is missing, install Ghostty through Omarchy:

```bash
omarchy pkg add ghostty
```

The wizard checks this prerequisite before it applies or migrates the package.

## Theme and opacity

The tracked config contains:

```ini
config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"
background-opacity = 0.92
background-opacity-cells = false
```

The optional include loads the palette generated for the current Omarchy theme. Omarchy can regenerate that untracked file when the theme changes, so Ghostty follows the active colors without adding the palette to Git.

The base background is 92% opaque. Cells with an explicit background color remain fully opaque.

## Cursor and tabs

The main config enables cursor blinking and loads the tracked tab stylesheet:

```ini
cursor-style-blink = true
gtk-custom-css = tab-bar.css
```

`tab-bar.css` keeps tabs at least 24 pixels high and removes their top and bottom padding.

## Apply and validate

Start the wizard:

```bash
make
```

Choose `Apply Stow packages` and select `ghostty`. The wizard checks the prerequisite, simulates the Stow operation, links the config, and validates the active configuration. An existing regular `~/.config/ghostty/config` is a conflict and remains unchanged.

Choose `Run structural checks` to check the package catalog and layout. To validate the active config directly, run:

```bash
ghostty +validate-config --config-file="$HOME/.config/ghostty/config"
```

Ghostty reads the linked main config and its current optional Omarchy palette.

To apply config changes to current Ghostty windows, run:

```bash
omarchy restart terminal
```

## Migration and recovery

Ordinary apply does not overwrite an existing regular config. `Migrate existing target` can import it only while the package destination is empty. From `make`, choose that action, select `ghostty`, and enter `.config/ghostty/config`.

Before approval, inspect the file for credentials, account data, machine-specific values, and generated content. The wizard shows the complete plan and creates a timestamped backup below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/ghostty/` before moving the file. It then repeats the Stow simulation, links the config, and validates it. Migration does not use `stow --adopt` or overwrite an occupied package destination.

If migration fails after it creates the backup, keep the backup and follow the recovery commands printed by the wizard. Do not copy a backup over `~/.config/ghostty/config` while that path is a Stow symlink. The copy would overwrite the tracked source. Remove the link first, then restore the backup.

## Remove and reapply

From `make`, choose `Remove Stow package` and select `ghostty`. Removal unlinks both tracked files. The Omarchy palette, Ghostty state and caches, and migration backups remain untouched.

To restore both tracked files, choose `Apply Stow packages` and select `ghostty` again. Reapplication repeats the Stow simulation, link verification, and Ghostty validation.

## Omarchy updates

Because the live config is a symlink, `omarchy update` can write through it and change the tracked source. Treat the resulting Git diff as a proposed change:

1. Inspect the diff for `config/ghostty/.config/ghostty/config`.
2. Compare it with `/usr/share/omarchy/config/ghostty/config`. Use the packaged file only for comparison.
3. Decide which changes to keep.
4. Restore the optional palette include, opacity settings, cursor blinking, and stylesheet load if needed.
5. Run `ghostty +validate-config --config-file="$HOME/.config/ghostty/config"`.

Treat `omarchy refresh config ghostty/config` as an intentional replacement of the tracked source, not a local reset. Through the Stow symlink, it can overwrite the repository file with Omarchy's packaged default. Run it only when that replacement is intended. Then review the Git diff, restore the required settings, and validate Ghostty.

This package supports the Omarchy version named in the repository. When that version changes, compare the full tracked config with the new packaged Ghostty default. Then repeat structural checks, Stow simulation, link verification, active validation, removal, and reapplication.
