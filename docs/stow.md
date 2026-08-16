# Stow workflow

A Stow package manages one application or a tightly coupled configuration concern. Packages use lowercase names and live under `config/<name>/`. Their directory trees mirror target paths below the user's home directory.

Tracked files stay in this repository. GNU Stow links them into the home directory instead of copying them. The package catalog is currently empty.

## Commands

```bash
make
./bin/dotfiles status
./bin/dotfiles check
./bin/dotfiles prerequisites --yes
./bin/dotfiles apply <package> --yes
./bin/dotfiles migrate <package> <home-relative-path> --yes --inspection-approved
./bin/dotfiles remove <package> --yes
```

`status` and `check` do not require GNU Stow. `check` validates the package catalog, package directories, documentation links, dependency graph, skill manifest, and required external commands.

Use `--allow-omarchy-mismatch` only after reviewing compatibility. Add `--install-stow` to approve installation through `omarchy-pkg-add stow`. After GNU Stow is verified, rerun the apply command so it can simulate and show the complete package plan.

## Ownership

Prefer Omarchy-supported user overrides. Track a complete configuration only when an override cannot express the required behavior and a human has reviewed the replacement scope.

Packages target the user's home directory. A system target or another location requires a separate decision.

Stop before adding machine-specific values, generated files, or sensitive data. Decide how to handle the concrete case first.

## Package catalog

The root `packages.json` file stores each package's:

- Name and description
- Path below `config/`
- Prerequisites
- Package dependencies
- Validation commands
- Optional documentation link
- Cleanup notes

Dependencies are applied before dependents. Removal stops when a linked package depends on the selected package and names each dependent.

## Safety

Before a package mutation, the command engine:

1. Validates the catalog and inspects the Omarchy version.
2. Checks required tools and package prerequisites.
3. Resolves dependencies and simulates the Stow operation.
4. Shows the complete plan.
5. Requests confirmation.
6. Applies the change and verifies the result.

A version mismatch produces a warning and requires separate confirmation. Existing normal files are reported as conflicts and are not replaced. The engine never uses `stow --adopt`.

A failed package stops the batch. Packages verified earlier in the batch remain applied, and the command prints recovery steps.

## Migration

Inspect the candidate for sensitive or machine-specific content before passing `--inspection-approved`.

Migration:

1. Reports the existing file and its package destination.
2. Simulates the package's existing tracked files and stops if another target conflicts.
3. Stores a timestamped backup below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<package>/`.
4. Moves the approved file into the Stow package without replacing existing package content.
5. Repeats the Stow simulation.
6. Applies the package and verifies its links and validators.

## Verification and recovery

Successful apply or migration means every expected target resolves to its repository source and every declared validator passes.

Removal simulates the unlink operation, removes tracked links, and verifies that managed targets are gone. It reports cleanup notes but does not delete generated files, application state, or backups.

Follow the recovery command printed after a failure. Migration backups remain in the XDG state directory. For partial links, use the printed `stow --delete` command before restoring a backup or retrying.

If the repository moves, remove or repair links created from the old location and apply the packages again.

## Package-specific installers

A package may include a Bash installer when setup needs more than a documented command. The installer must resolve the repository without assuming a clone path, preview its actions, request confirmation, tolerate repeated execution, and verify the result.

When elevated privileges are required, call the supported Omarchy command and let Omarchy manage the prompt.
