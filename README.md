# Dotfiles

Portable dotfiles for Omarchy version 4. GNU Stow links tracked configuration into the user's home directory. The Dotfiles wizard manages prerequisites, application cleanup, Stow packages, and pinned global agent skills.

## Requirements

The core wizard requires:

- Omarchy Linux version 4
- Bash and GNU command-line tools
- Git
- jq
- make

Application cleanup also requires `pacman`, `yay`, `find`, `grep`, `sort`, `basename`, `mktemp`, `rm`, and `omarchy`.

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

Gum is optional. The wizard uses Bash prompts when Gum is not available.

The integration tests require Bubblewrap (`bwrap`).

## Quick start

```bash
git clone https://github.com/a1exk-dev/dotfiles.git
cd dotfiles
make
```

Choose `Guided setup` to prepare prerequisites, install pinned global skills, clean up selected Omarchy applications, and apply selected Stow packages.

## Repository layout

- `bin/dotfiles`: Dotfiles wizard entry point
- `lib/dotfiles/`: wizard operation modules
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
- [Bash](docs/bash.md)
- [Ghostty](docs/ghostty.md)
- [Application cleanup](docs/cleanup.md)
- [Agent setup](docs/agent-setup.md)

Package-specific guides belong under `docs/` only when a package needs more detail.
