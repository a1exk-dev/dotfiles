# Dotfiles

Portable dotfiles for Omarchy version 4. GNU Stow links tracked configuration into the user's home directory. The Dotfiles wizard manages Stow packages, prerequisites, and pinned global agent skills.

## Requirements

Status, checks, and package management require:

- Omarchy Linux version 4
- Bash and GNU command-line tools
- Git
- jq
- make

The structural check also requires npx because it validates the global skill tooling.

GNU Stow is required when applying, migrating, or removing packages. The wizard can install it with `omarchy-pkg-add stow` after confirmation.

Gum is optional. The wizard uses plain Bash prompts when Gum is unavailable.

Global agent-skill installation also requires:

- Node.js 22.20.0 or newer
- npm and npx
- Network access to GitHub and the npm registry
- Write access to `~/.agents/skills/`
- A writable absolute `XDG_STATE_HOME`, or `~/.local/state`
- Temporary storage for source checkouts, previews, and backups

## Quick start

```bash
git clone https://github.com/a1exk-dev/dotfiles.git
cd dotfiles
./bin/dotfiles status
./bin/dotfiles check
make
```

The package catalog is currently empty, so there are no configuration packages to apply. Status, structural checks, prerequisite setup, and global skill management are available. Running `make` opens the interactive wizard with no action or package selected.

Before a mutation, the command engine checks the Omarchy version and required tools, calculates dependencies and conflicts, shows the plan, and requests confirmation. An Omarchy version mismatch requires separate approval.

## Repository layout

`bin/dotfiles` is the command interface. It loads internal modules from `lib/dotfiles/` for shared behavior, package operations, global skills, and the interactive wizard.

Integration tests are grouped by behavior under `tests/` and share one isolated fixture harness. Run the full suite with:

```bash
make test
```

Running the integration tests requires Bubblewrap (`bwrap`).

## Documentation

- [Stow workflow](docs/stow.md): package layout, commands, safety, migration, verification, and removal
- [Agent setup](docs/agent-setup.md): pinned skill sources, preview, backup, recovery, and updates

Package-specific guides belong under `docs/` only when a package needs more detail.
