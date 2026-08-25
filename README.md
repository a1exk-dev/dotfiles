# Dotfiles

Portable dotfiles for Omarchy version 4. GNU Stow links tracked configuration into the user's home directory. The Dotfiles wizard manages prerequisites, pinned global agent skills, application cleanup, Stow packages, and the optional shared Brave configuration.

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

The integration tests require Bubblewrap (`bwrap`), GNU Stow, btop 1.4.7, tmux 3.7b, and Starship 1.26.0.

## Quick start

```bash
git clone https://github.com/a1exk-dev/dotfiles.git
cd dotfiles
make
```

Choose `Guided setup` to prepare prerequisites, install pinned global skills, clean up selected Omarchy applications, apply selected Stow packages, and optionally apply the shared Brave policy.

Choose `Recover ZTE USB modem` to inspect and, after confirmation, recover the known ZTE USB modem.

## Repository layout

- `bin/dotfiles`: Dotfiles wizard entry point
- `lib/dotfiles/`: wizard operation modules
- `brave/`: canonical source for the shared Brave managed policy
- `config/`: Stow packages
- `packages.json`: package catalog
- `cleanup.json`: application cleanup profile
- `skills.json`: pinned global skill sources
- `tests/`: integration tests

Run the test suite with:

```bash
make test
```

## Documentation

- [Stow workflow](docs/stow.md)
- [Shared Brave configuration](docs/brave.md)
- [Bash](docs/bash.md)
- [Starship](docs/starship.md)
- [Tmux](docs/tmux.md)
- [Ghostty](docs/ghostty.md)
- [btop](docs/btop.md)
- [ZTE USB modem recovery](docs/usb-modem.md)
- [Application cleanup](docs/cleanup.md)
- [Agent setup](docs/agent-setup.md)

Package-specific guides belong under `docs/` only when a package needs more detail.
