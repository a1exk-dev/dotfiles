[Back to README](../README.md)

# Bash

The `bash` Stow package owns only `~/.bashrc`. The tracked file loads Omarchy's environment bootstrap and sources `/usr/share/omarchy/default/bash/rc`. Omarchy continues to provide its packaged aliases, functions, completion, tool initialization, and Starship initialization. The independent `starship` Stow package owns only `~/.config/starship.toml`; it does not initialize Starship, and neither package depends on the other.

The package does not manage `.bash_profile`, `~/.config/starship.toml`, terminal configuration, Omarchy configuration, themes, or generated theme state.

## Requirements

Selecting `bash` in `Guided setup` or `Apply Stow packages` installs the official Arch `thefuck` package through Omarchy when it is missing.

The `bash` package depends on the `tmux` Stow package. The complete plan links the complete tmux configuration and private starter and installs the official Arch `tmux`, `fzf`, and `less` packages when they are missing.

## Shortcuts

`vi` opens Neovim in interactive Bash shells.

`ll` lists all entries, including hidden files, with Omarchy's long `eza` format.

A bare `~` command changes to your home directory.

A bare `tmux` command opens the private session starter, which uses `Work` when a new-session name is empty. Tmux commands with arguments run `/usr/bin/tmux`. Omarchy's `t` alias attaches to an existing session or creates `Work`.

After a command fails, run `fuck` to review a suggested correction. The Fuck asks for confirmation before it runs the selected command.

## Reloading

Running `source ~/.bashrc` reloads the repository shortcuts without re-running Omarchy's packaged initialization. Start a new Bash shell to load updated Omarchy defaults.

## Apply

Start the Dotfiles wizard:

```bash
make
```

Choose `Apply Stow packages` and select `bash`. The wizard previews the operation, asks for confirmation, links the tracked `.bashrc`, and runs the package validators.

If a regular `~/.bashrc` already exists, the wizard reports a conflict and leaves the file unchanged. `Migrate existing target` cannot import it because `config/bash/.bashrc` already exists. Do not use `stow --adopt`.

See [Stow workflow](stow.md) for the shared apply and conflict-handling rules.

## Validation

Check Bash syntax with:

```bash
bash -n ~/.bashrc
```

Use `Package status` in the Dotfiles wizard to confirm that `bash` is linked.

## Omarchy writes

Routine Omarchy updates continue to work because `.bashrc` sources the packaged Bash defaults.

Some Omarchy commands, including `omarchy reinstall configs`, can follow the Stow link and change `config/bash/.bashrc`. Treat each change as a proposed Git change. Review the diff, compare it with the current packaged default, and run package validation before keeping it.

## Removal

Use `Remove Stow package` in the Dotfiles wizard. The wizard removes the home-directory link and keeps the tracked source. Any migration backup also remains. `~/.bashrc` is absent until you reapply the package or restore an exact migration backup.

Removing the Bash Stow package leaves the official Arch `thefuck` package installed.

See [Stow workflow](stow.md) for removal and recovery details.
