# Dotfiles

Portable dotfiles for Omarchy version 4. GNU Stow links tracked configuration into the user's home directory. The Dotfiles wizard manages prerequisites, pinned global agent skills, application cleanup, Stow packages, repository wallpapers, the optional shared Brave configuration, Telegram Desktop's optional Omarchy theme integration, and selective active-theme Omarchy screensaver effects.

## Requirements

The core wizard requires:

- Omarchy Linux version 4
- Bash and GNU command-line tools
- Git
- jq
- make

Application cleanup also requires `pacman`, `yay`, `find`, `grep`, `sort`, `basename`, `mktemp`, `rm`, and `omarchy`.

USB modem recovery requires `sudo`, `nmcli`, `readlink`, Linux sysfs, and an xHCI controller with bind and unbind controls.

Stow package application, migration, and removal require GNU Stow. The wizard can install it through Omarchy after confirmation. Migration also requires a writable absolute `XDG_STATE_HOME`, or the default `~/.local/state`, for backups.

The `opencode` Stow package owns complete global OpenCode runtime and TUI settings. It requires OpenCode installed through Omarchy 4's Mise flow, but it does not install or update OpenCode.

The `telegram-theme` Stow package supports exactly Omarchy `4.0.1-1` and Telegram Desktop `7.0.9-4`. It requires Node.js 22.20.0 or newer, `zip`, `flock`, and writable absolute XDG state and runtime directories. The package plan installs `telegram-desktop` and `zip` through Omarchy after confirmation.

The `screensaver-effects` Stow package was verified with Omarchy `4.0.1-1` and `ttfx 0.3.2-1`. Version mismatches produce warnings, but source, command, ownership, mapping, and lifecycle failures block the operation. The package requires Node.js 22.20.0 or newer, `omarchy`, `omarchy-shell`, `xdg-terminal-exec`, `hyprctl`, `omarchy-screensaver`, `omarchy-toggle-enabled`, and `omarchy-hyprland-monitor-focused`. Its package plan installs `ttfx`, `jq`, and `socat` through Omarchy after confirmation. Gum is optional.

Screensaver activation, removal, migration, and recovery require a writable absolute `XDG_STATE_HOME`, or the default `~/.local/state`. Launch and preview require a normal Omarchy Hyprland session, a writable absolute `XDG_RUNTIME_DIR`, and Alacritty, Ghostty, Foot, or Kitty as the active terminal.

Wallpaper curation and deployment require ImageMagick through the `magick` command. The wizard can install ImageMagick with `omarchy pkg add imagemagick` after confirmation. Apply, removal, and recovery require a writable absolute `XDG_STATE_HOME`, or the default `~/.local/state`, for receipts and transaction evidence.

Some Stow packages need Arch packages. Apply and migration plans list anything missing. After confirmation, the wizard installs and verifies those packages through Omarchy before it changes Stow links.

Pinned global skill installation and updates also require:

- Node.js 22.20.0 or newer
- npm and npx
- Network access to GitHub and the npm registry
- Write access to `~/.agents/skills/`
- A writable absolute `XDG_STATE_HOME`, or the default `~/.local/state`
- Temporary storage for source checkouts, previews, and backups

Skill updates also require write access to `skills.json`.

The wizard can install the Node.js toolchain through Omarchy after confirmation.

Brave policy management requires `chmod`, `chown`, `date`, `diff`, `find`, `flock`, `id`, `install`, `jq`, `mkdir`, `mktemp`, `mv`, Node.js 22.20.0 or newer through `node`, `omarchy`, `pacman`, `readlink`, `rm`, `rmdir`, `stat`, and `sudo`. The privileged adapter requires `/usr/bin/chmod`, `/usr/bin/chown`, `/usr/bin/install`, `/usr/bin/mv`, `/usr/bin/rm`, `/usr/bin/rmdir`, and `/usr/bin/sudo` at those fixed paths.

Applying the policy also requires `brave-bin` and its package-owned `brave` command, or `brave-origin-bin` and its package-owned `brave-origin` command. Apply, remove, and recovery require a writable absolute `XDG_STATE_HOME`, or the default `~/.local/state`, for receipts and backups. Remove does not require an installed browser. The wizard reports the supported Omarchy browser installation commands but does not install or remove a browser.

Gum is optional. The wizard uses Bash prompts when Gum is not available.

The integration tests require Bubblewrap (`bwrap`), GNU Stow, ImageMagick, btop 1.4.7, tmux 3.7b, Starship 1.26.0, OpenCode 1.18.23, the Omarchy 4.0.1 stock themes, `ttfx` 0.3.2, `socat`, `zip`, `unzip`, and `inotifywait`.

## Quick start

```bash
git clone https://github.com/a1exk-dev/dotfiles.git
cd dotfiles
make
```

Choose `Guided setup` to prepare prerequisites, install pinned global skills, clean up selected Omarchy applications, apply selected Stow packages, deploy the Wallpaper library, and optionally apply the shared Brave policy.

Choose `Recover ZTE USB modem` to inspect and, after confirmation, recover the known ZTE USB modem.

Choose `Manage Telegram theme` to inspect status, run the approved bootstrap refresh, or retry generation.

Choose `Apply Stow packages` and select `screensaver-effects` to link and activate the selective screensaver integration. After activation, run `make screensaver-effects` to change the tracked allowlist or preview an installed mapped effect. The manager requires terminal input and output.

Place candidate images in `wallpapers/inbox/`, then choose `Manage wallpapers` or run `make wallpapers`. The manager validates each Intake image, adds its Theme assignments under `wallpapers/library/`, and creates one Git commit for new assignment paths. The commit subject is `Add managed wallpaper <digest-prefix>`. If every assignment is already in Git, Add removes the duplicate Intake image without creating an empty commit. Choose `Apply wallpapers` to deploy the library as regular Omarchy background files. Choose `Remove deployed wallpapers` to remove unchanged receipt-owned copies.

## Repository layout

- `bin/dotfiles`: Dotfiles wizard entry point
- `lib/dotfiles/`: wizard operation modules
- `brave/`: canonical source for the shared Brave managed policy
- `config/`: Stow packages
- `config/opencode/`: complete global OpenCode runtime and TUI settings
- `config/telegram-theme/`: Telegram Desktop theme generator and Omarchy integration assets
- `config/screensaver-effects/`: tracked allowlist, Omarchy plugin clones, launcher, runtime shim, and selector
- `wallpapers/inbox/`: ignored Intake images awaiting review
- `wallpapers/library/`: tracked Managed wallpapers grouped by Theme assignment
- `packages.json`: package catalog
- `cleanup.json`: application cleanup profile
- `skills.json`: pinned global skill sources
- `tests/`: integration tests

Run the test suite with:

```bash
make test
```

Run the focused OpenCode tests with:

```bash
bash tests/opencode_test.sh
```

## Documentation

- [Stow workflow](docs/stow.md)
- [Shared Brave configuration](docs/brave.md)
- [Bash](docs/bash.md)
- [Starship](docs/starship.md)
- [Tmux](docs/tmux.md)
- [Ghostty](docs/ghostty.md)
- [btop](docs/btop.md)
- [OpenCode](docs/opencode.md)
- [Telegram Desktop theme integration](docs/telegram-theme.md)
- [Selective screensaver effects](docs/screensaver-effects.md)
- [ZTE USB modem recovery](docs/usb-modem.md)
- [Application cleanup](docs/cleanup.md)
- [Agent setup](docs/agent-setup.md)

Package-specific guides belong under `docs/` only when a package needs more detail.
