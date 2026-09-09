[Back to README](../README.md)

# Portable input languages

## Scope

The `hyprland` package configures US English first and default Russian second for desktop applications that use the Hyprland XKB keymap. A lifecycle-owned clone of the stock keyboard-layout widget shows the current language as a compact monochrome flag in the bar's foreground color.

Omarchy runs Fcitx for XCompose support. Text fields captured by Fcitx use Fcitx's own input state, so this setup does not switch them. It also does not change the console keymap, system locale, display language, captured virtual machines, remote desktops, or applications that bypass the compositor keymap.

## Requirements

Apply supports Omarchy `4.0.2` or newer within version 4. The running Hyprland ABI must match the installed headers exactly. The compiler family and major version must match the compiler used for Hyprland.

The lifecycle requires:

- A running Hyprland session
- GNU Stow
- GCC and Make
- pkgconf and binutils
- Lua through `luac`
- `xkbcli`
- `jq`, `flock`, `file`, `diff`, and standard GNU tools
- Stock Omarchy refresh, plugin, bar, Shell, and keyboard-layout widget seams
- `XDG_CONFIG_HOME` unset or exactly `$HOME/.config`
- Writable absolute `XDG_DATA_HOME` and `XDG_STATE_HOME`, or the defaults below `~/.local/`
- No symbolic-link components in the `HOME`, XDG, repository source, or lifecycle paths
- Existing lifecycle-owned data, artifact, and state directories owned by the invoking user with mode `0700`

The package catalog declares `hyprland`, `gcc`, `make`, `pkgconf`, `binutils`, and `lua` as official Arch requirements. The wizard installs missing requirements through `omarchy pkg add` after confirmation. Remove retains these packages.

Gum is optional. The manager uses Bash prompts when Gum is unavailable.

## Input behavior

Press bare Left Ctrl and Left Shift in either order. The first release switches between US and Russian. The chord is canceled if another non-modifier key participates. Normal key events continue to applications and compositor shortcuts.

Physical typing keyboards are devices that libinput marks with `ID_INPUT_KEYBOARD=1`. They share one canonical language. A newly connected physical keyboard joins the current language instead of resetting the existing seat.

Virtual and pseudo-keyboards do not participate in chord detection or determine the canonical language. The stock-derived flag widget keeps the stock device-selection and click behavior. Clicking it applies the requested layout to all physical typing keyboards and restores the excluded source.

## Ownership

The Stow package owns these 11 leaves below `~/.config/hypr/`:

- `.luarc.json`
- `autostart.lua`
- `bindings.lua`
- `hypridle.conf`
- `hyprland.lua`
- `hyprlock.conf`
- `hyprsunset.conf`
- `input.lua`
- `looknfeel.lua`
- `monitors.lua`
- `xdph.conf`

The lifecycle stores immutable plugin artifacts and the active Lua pointer below `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/input-languages/`.

Receipts, complete pre-Apply backups, archived evidence, and failure diagnostics remain below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/input-languages/`.

The lifecycle owns the immutable `dotfiles.keyboard-layout` clone and publishes it through one directory link. The flag is stored at `right[0]`. Omarchy pins `omarchy.tray` ahead of that position, so the visible order is system tray, language flag, then the other right-side controls. Apply replaces the exact stock keyboard-layout entry with the clone and moves an older receipt-owned flag to this position without changing unrelated Shell state. Remove deletes only the unchanged clone entry and link, then restores the prior stock entry and position, or its prior absence. The lifecycle does not own the complete `~/.config/omarchy/shell.json`.

## Start the manager

Run:

```bash
make
```

Choose `Settings`, then `Input Languages`. The choices are `Status`, `Apply`, `Remove`, and `Back`.

You can open the same manager directly:

```bash
make input-languages
```

Each result remains visible until you return to Input Languages or open Status.

## Status

Status is read-only. It reports:

- Omarchy support
- Complete-tree ownership
- Source, artifact, compiler, dependency, and ABI identity
- Active, pending, and recovery-required evidence
- Plugin health and canonical language
- Physical and excluded keyboards
- Flag indicator presence, Shell health, and active language
- The required next action

Status also warns that Omarchy Hyprland refresh commands can write through Stow links into repository sources. Review Git changes after a refresh.

## Apply

Apply accepts an absent live tree or the reviewed complete migration baseline. Unknown entries, changed baseline files, unsafe links, ordinary Stow conflicts, unsupported versions, incompatible build inputs, invalid evidence, and changed Omarchy seams block before mutation.

One plan and default-No confirmation cover the complete operation. Apply:

1. Validates all sources, integration seams, build inputs, paths, and lifecycle evidence.
2. Installs and verifies missing declared Arch requirements through Omarchy.
3. Creates and verifies a complete backup of the prior Hyprland tree, including file and directory metadata.
4. Builds an immutable exact-stack plugin artifact and records its identity.
5. Publishes pending evidence before changing the live setup.
6. Pauses Hyprland autoreload, changes the active artifact pointer, and links the complete package.
7. Publishes the stock-derived flag clone at `right[0]`, immediately after the Shell-pinned `omarchy.tray` and before the other right-side controls.
8. Reloads Hyprland once and verifies configuration, plugin, keyboard, Shell, and indicator health.
9. Resets a changed setup to US and publishes the active receipt.

An exact repeated Apply is a no-op. It does not install packages, create a backup, build, relink, rewrite lifecycle state, reload Hyprland, change the flag widget, or reset the active language.

## Remove

A clean uninstalled setup is a no-op. Mutating Remove requires a valid active receipt, exact active pointer, complete linked tree, verified pre-Apply backup, and unchanged lifecycle-owned widget entry.

Before confirmation, Remove displays the actual difference between the backup and current repository source. Later source edits are not merged into the restored tree.

Remove unloads the plugin, removes the receipt-owned artifact and pointer, unlinks the complete package, restores the exact pre-Apply tree as regular files, restores directory metadata, removes only an unchanged lifecycle-added widget, reloads Hyprland once, verifies plugin absence, and archives lifecycle evidence.

Receipt-backed Remove remains available on an unsupported later Omarchy version when current state and evidence are safe. Remove retains repository sources, Arch packages, original backups, archived evidence, and diagnostics.

## Failure and recovery

Pending evidence is published before the first live mutation. A later failure restores and verifies the prior tree, artifact pointer, plugin, widget entry, autoreload setting, and canonical language.

If rollback cannot be proved, the lifecycle records `recovery-required` and retains pending evidence, artifacts, backups, and diagnostics. Ordinary Apply and Remove remain blocked. Open the manager again and review Status before approving recovery.

Recovery stops after it restores or verifies the interrupted transaction. Run the requested Apply or Remove operation again after recovery completes.

## Manual verification

After Apply:

1. Open Status and confirm that it reports `Overall: healthy`, the exact build and compatibility identity, at least one physical keyboard, and a healthy flag indicator.
2. Confirm that the text-free monochrome US flag uses the current bar foreground color and appears immediately after the system tray, before the other right-side controls.
3. Test application input in a client that is not captured by an input method. On stock Omarchy, you can temporarily stop Fcitx with `systemctl --user stop omarchy-fcitx5.service`, run the direct XKB checks, and restore it with `systemctl --user start omarchy-fcitx5.service`.
4. Type in a normal Wayland application and confirm US input.
5. Press bare Left Ctrl and Left Shift, release either key first, and confirm Russian input. Test both press orders.
6. Repeat the chord with another non-modifier key and confirm that the language does not change.
7. Click the flag widget and confirm that the physical keyboard and displayed flag change together.
8. Confirm US and Russian input in a normal XWayland application.
9. Run `hyprctl reload`, open Status, and confirm that the active language and loaded plugin instance are preserved.
10. Run Apply again and confirm an exact no-op that preserves the active language.
11. Run Remove and confirm that the plugin is absent, the stock widget is restored, and the complete prior Hyprland tree was restored as regular files.

## Initial verification record

Verified on Omarchy `4.0.2-1` and Hyprland `0.56.2` with ABI `efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.14_hu_0.14_hg_0.5_hc_0.1_hlg_0.6`. The plugin used GCC `16.2.1`; Hyprland used GCC `16.1.1`. Both chord orders, third-key cancellation, widget clicking, Wayland and XWayland direct XKB input, reload preservation, exact Apply no-op, Remove restoration, and reapply passed. Fcitx-managed Ghostty and Brave fields remained English, as documented by the input-method boundary.

Automated tests cover two physical keyboards, hotplug, and unplug. A second real keyboard is optional for manual verification.
