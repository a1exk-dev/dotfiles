# Stow workflow

This guide describes the planned Stow package model and setup wizard. The repository does not contain Stow packages or an implemented wizard yet.

A Stow package manages one application or tightly coupled configuration concern. Packages use lowercase names and live under `config/<name>/`. Their directory trees mirror target paths below the user's home directory.

Tracked files are edited inside this repository. GNU Stow links them into the home directory instead of copying them.

## Ownership

Prefer Omarchy-supported user overrides. Track a complete configuration only when an override cannot express the required behavior and the human has reviewed the replacement scope.

Packages target the user's home directory by default. Any system target or other location requires a separate decision.

When a package introduces machine-specific values, generated files, or sensitive data, stop and agree how to handle that concrete case before adding it.

## Package catalog

The root `packages.json` file is the source of package metadata. Each package entry records:

- Name and description
- Path below `config/`
- Prerequisites
- Package dependencies
- Validation commands
- Documentation link
- Cleanup notes

The wizard reads the catalog with `jq`.

When an applied package depends on another package, the wizard includes or blocks that dependency visibly. It blocks removal when another linked package still depends on the selected package and names every dependent.

## Wizard flow

Run `make` to open the planned interactive wizard. Gum renders the interface when available; plain Bash prompts provide the fallback.

No package is selected by default. Before changing files, the wizard:

1. Checks the detected Omarchy version against the supported version.
2. Checks required tools and selected-package prerequisites.
3. Resolves dependencies and reports conflicts.
4. Shows the complete plan.
5. Asks for confirmation.

A version mismatch produces a warning and requires confirmation. When GNU Stow is missing, the wizard explains the requirement and offers the Omarchy-supported installation command.

The shared `bin/dotfiles` engine provides `status`, `apply`, `remove`, `skills`, and `check` commands for agents and scripts.

If a package operation fails, the wizard stops, preserves earlier successful operations, and reports recovery steps.

## Conflicts and migration

Run a Stow dry run before applying a package. If a normal file already exists at a target path, stop and show the conflict without changing it.

After the human approves migration:

1. Save a timestamped backup below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/`.
2. Inspect the existing file for machine-specific or sensitive content.
3. Move the approved content into its Stow package.
4. Run the Stow dry run again.
5. Create the links.
6. Verify that every expected target points into the repository.

The migration flow does not use `stow --adopt`.

## Verification and removal

A package is ready only after:

- Its Stow dry run succeeds.
- Its expected links point into the package.
- Application-specific syntax, reload, or status checks pass when available.
- A removal dry run succeeds.

Removing a package unlinks its tracked files with Stow. The wizard reports generated files, application state, or backups that remain; it does not delete them automatically.

If the repository clone moves, remove or repair the old links and apply the packages again from the new path.

## Prerequisites and installers

Each package lists its required software in `packages.json` and its topic guide when one exists. Use an Omarchy-supported installation command when available.

A package may include a Bash installer when setup needs more than a documented command. The installer must:

- Resolve the repository without assuming a clone path.
- Preview its actions.
- Ask for confirmation.
- Run safely more than once.
- Verify the result.

When elevated privileges are required, call the supported Omarchy command and let Omarchy manage the prompt.
