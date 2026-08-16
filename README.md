# Dotfiles

This repository is for portable Omarchy Linux dotfiles. It targets Omarchy version 4 and will use GNU Stow to link tracked files into a user's home directory.

The setup wizard and Stow packages are planned but are not implemented yet.

## Requirements

The planned dotfile tooling requires:

- Omarchy Linux version 4
- Bash and GNU command-line tools
- Git
- GNU Stow
- make
- jq

Gum provides the interactive interface. The wizard will fall back to plain Bash prompts when Gum is unavailable.

Agent-assisted development also requires:

- Node.js 22.20.0 or newer
- npm and npx
- Network access to GitHub and the npm registry
- Write access to `~/.agents/skills/`
- A writable absolute `XDG_STATE_HOME`, or `~/.local/state`
- Enough temporary storage for source checkouts, comparisons, and backups

Restart the agent or reload its skills after installing or updating global skills.

## Quick start

Clone the repository:

```bash
git clone https://github.com/a1exk-dev/dotfiles.git
cd dotfiles
```

The repository does not yet contain installable Stow packages or the setup wizard. There is currently no command that changes your Omarchy configuration.

## Planned workflow

The planned `make` command will open an interactive wizard. The wizard will show package status, apply or remove selected Stow packages, and install approved prerequisites.

Before a change, it will check the Omarchy version and required tools, resolve package dependencies, report conflicts, show the complete plan, and ask for confirmation. No package will be selected by default.

Stow packages will live under `config/<name>/`. Package metadata will live in `packages.json`.

The wizard will also install the repository's pinned global agent skills. `make skills-update` will preview upstream differences, ask for approval, then update the manifest and installed skills as one recoverable operation.

See [Stow workflow](docs/stow.md) for the full design.

## Documentation

- [Stow workflow](docs/stow.md): package layout, safety, migration, verification, removal, and wizard behavior
- [Agent setup](docs/agent-setup.md): pinned skill sources, official installers, version comparison, backup, recovery, and updates

Package-specific guides will be added under `docs/` only when a package needs more detail.
