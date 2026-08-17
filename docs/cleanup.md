# Application cleanup

The Dotfiles wizard can remove selected Arch packages, Omarchy web apps, and Omarchy TUI launchers. Cleanup is phase 3 of `Guided setup`. It is also available as the standalone `Clean up Omarchy applications` action.

Start the Dotfiles wizard with:

```bash
make
```

## Application cleanup profile

The root `cleanup.json` file is the application cleanup profile. It has separate default lists for packages, web apps, and TUIs.

The package defaults are:

- `chromium`
- `moonlight-qt`

The web app defaults are:

- `Basecamp`
- `Discord`
- `Figma`
- `Fizzy`
- `GitHub`
- `Google Contacts`
- `Google Messages`
- `Google Photos`
- `HEY`
- `X`
- `YouTube`
- `Zoom`

The TUI default list is empty.

The application cleanup profile contains selection defaults. It is not a list of installed applications. A selection change applies only to the current run. The wizard does not write that change to `cleanup.json`.

`Run structural checks` validates the profile structure, entry types, unique names, naming rules, and protected-package exclusions.

## Discovery and selection

Cleanup discovers:

- Explicitly installed package names from `yay -Qqe`
- Omarchy web app launchers below `~/.local/share/applications`
- Omarchy TUI launchers below `~/.local/share/applications`

The wizard shows these multi-select screens:

- `Packages to remove`
- `Web apps to remove`
- `TUIs to remove`

An installed profile default starts selected. Other discovered items are available for selection. You can clear a selected default or add another item for the current run.

The wizard reports profile defaults that are not available on the machine under `Unavailable cleanup defaults`. It does not add them to the plan, and their absence does not cause a failure.

An empty final selection succeeds and makes no changes.

## Protected packages

The wizard does not show protected packages in the package selection. It also rejects a protected package in `cleanup.json`.

Protected categories include:

- Base operating system packages
- Kernels, firmware, networking, and service management
- Privilege, shell, and package management packages
- Omarchy packages
- Packages that provide commands needed by the active cleanup run

The protected set includes at least `base`, `linux`, `sudo`, `bash`, `omarchy`, and `yay`. The wizard also protects the installed providers of its runtime commands. These commands include `bash`, `jq`, `find`, `grep`, `sort`, `basename`, `mktemp`, `rm`, `pacman`, `yay`, and `omarchy`. It also protects the Gum provider when the run uses Gum.

This protection prevents cleanup from removing a package that it needs for discovery, selection, removal, or verification.

## Plan and removal

For a nonempty selection, the wizard shows one plan with these groups:

- Web apps
- TUIs
- Packages

It asks for one confirmation for the complete cleanup plan. An Omarchy version mismatch requires a separate confirmation.

The wizard removes web apps first, then TUIs, then packages. It delegates each removal to Omarchy:

```text
omarchy webapp remove <name>
omarchy tui remove <name>
omarchy pkg drop <name>
```

The wizard does not change files below `/usr/share/omarchy/`. Omarchy manages package removal and privilege prompts.

After each command, the wizard verifies that the selected launcher or package is absent. It does not start the next item until this verification passes.

## Failure and rerun

Cleanup stops on the first removal or verification failure. Removals that passed verification earlier in the run stay complete. The failure report lists the failed item and all items that were not processed.

Run `make` again and choose `Clean up Omarchy applications` to retry. The wizard discovers the current machine state again. It reports already absent profile defaults as unavailable and does not send them to an Omarchy removal command.

You can rerun cleanup after a partial failure, an Omarchy update, or an application refresh. Cleanup does not prevent Omarchy from installing or restoring an application later. It does not use Omarchy's global preinstall opt-out.
