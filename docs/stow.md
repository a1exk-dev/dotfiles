# Stow workflow

A Stow package manages one application or one closely related configuration concern. Packages use lowercase names and live under `config/<name>/`. Each package directory has the same relative paths as its targets below the user's home directory.

GNU Stow links tracked files into the home directory. It does not copy them.

Package operations disable Stow directory folding when they create links. New parent paths stay as ordinary directories, and each tracked file gets its own link. A link created by an older version can stay folded until you remove and reapply its package.

## Start the Dotfiles wizard

```bash
make
```

The Dotfiles wizard has these Stow actions:

- `Guided setup`
- `Package status`
- `Run structural checks`
- `Apply Stow packages`
- `Migrate existing target`
- `Remove Stow package`
- `Prepare prerequisites`

The wizard uses Gum when it is available. Otherwise, it uses Bash prompts.

## Guided setup

`Guided setup` runs these phases in order:

1. Prerequisite preparation
2. Pinned global skill installation
3. Application cleanup
4. Stow package application

Prerequisite preparation verifies GNU Stow and the Node.js tools required by pinned global skills. If tools are missing, the wizard shows one plan and asks for confirmation. This guide covers the Stow phase. See [Application cleanup](cleanup.md) and [Agent setup](agent-setup.md) for the other guided phases.

```text
omarchy pkg add stow
omarchy install dev-env node
```

Omarchy manages privilege prompts. The wizard verifies the tools after installation.

The Stow phase shows one package multi-select screen. No package is selected by default. An empty selection skips the Stow phase. An operational failure stops guided setup and names the standalone wizard action to use for recovery.

## Ownership

Prefer Omarchy-supported user overrides. Track a complete configuration only when an override cannot express the required behavior and a human has reviewed the replacement scope.

Packages target the user's home directory. A system target or another location requires a separate decision.

Stop before adding machine-specific values, generated files, or sensitive data. Decide how to handle the concrete case first.

## Package status

Choose `Package status` to inspect all packages in the package catalog. The wizard reports each package as linked, absent, conflicting, or invalid.

This action does not require GNU Stow.

## Structural checks

Choose `Run structural checks` to validate:

- The package catalog and package directories
- Package documentation links
- Package dependencies
- Package prerequisites and validator executables
- Package-specific Arch requirements
- The application cleanup profile
- The skill manifest and required global skill commands
- GNU Stow availability

This action does not require GNU Stow. It requires npx to validate the global skill tooling.

## Apply Stow packages

Choose `Apply Stow packages`. The wizard shows one multi-select screen with no packages selected by default.

For a nonempty selection, the wizard:

1. Validates the package catalog.
2. Reports the supported and detected Omarchy versions.
3. Checks GNU Stow.
4. Resolves package dependencies.
5. Checks package prerequisites, validator executables, and Arch package requirements.
6. Simulates all Stow operations.
7. Shows the complete plan in dependency order, including missing Arch packages.
8. Asks for confirmation.
9. Installs and verifies missing Arch packages.
10. If it installed an Arch package, repeats all Stow simulations.
11. Applies and verifies each package in dependency order.

The plan identifies selected packages and required dependencies. Existing normal files cause a conflict. The wizard does not replace them and does not use `stow --adopt`.

Package-specific Arch requirements are part of the Stow plan and use the same confirmation. The wizard installs missing packages with `omarchy pkg add`, verifies them, and repeats the Stow simulation before it changes links.

An empty selection or a declined plan makes no changes.

## Migrate an existing target

Choose `Migrate existing target`, select a package, and enter the `Home-relative target path`.

Migration accepts one existing regular file below the user's home directory. Inspect the file for credentials, account data, machine-specific values, and generated content before approval.

The wizard:

1. Confirms that the target resolves inside the user's home directory.
2. Confirms that the package destination resolves inside the selected package.
3. Resolves dependencies and checks prerequisites, validators, Arch package requirements, and GNU Stow.
4. Simulates the selected package and all required dependencies.
5. Shows the complete migration plan, including missing Arch packages, and asks for approval.
6. Asks if the file was inspected for sensitive and machine-specific content.
7. Installs and verifies missing Arch packages.
8. If it installed an Arch package, repeats the Stow simulation for the selected package and all required dependencies.
9. Applies required dependency packages before it changes the selected target.
10. Checks the selected target, package destination, and path containment again.
11. Creates a timestamped backup below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<package>/`.
12. Moves the approved file into the selected package without replacing package content.
13. Simulates the selected package again.
14. Applies the selected package and verifies its links and validators.

Migration installs and verifies missing Arch packages before it applies dependency links, creates a backup, or moves the selected target. If installation fails, the selected target stays unchanged.

Migration does not use `stow --adopt`. If a failure occurs after the backup or move, the wizard prints the backup path and recovery commands. A dependency failure can leave an earlier dependency linked, but it leaves the selected migration target unchanged and does not create its backup.

## Remove a Stow package

Choose `Remove Stow package` and select one package.

The wizard blocks removal when another linked package depends on the selected package. It names each dependent package.

For an allowed removal, the wizard:

1. Simulates the unlink operation.
2. Shows the package links and cleanup notes.
3. Asks for confirmation.
4. Unlinks the package.
5. Verifies that all managed targets are gone.

Removing a Stow package leaves its Arch packages installed. The cleanup notes list the retained packages.

Removal does not delete generated files, application state, migration backups, or other paths in the package cleanup notes.

## Package catalog

The root `packages.json` file stores each package's:

- Name and description
- Path below `config/`
- Prerequisites
- Arch packages installed through Omarchy
- Dependencies
- Validation commands
- Optional documentation link
- Cleanup notes

The wizard applies dependencies before dependent packages. A linked dependent blocks removal of a package that it requires.

## Verification and recovery

An Omarchy version mismatch requires separate confirmation before a mutation.

Successful application or migration means that each expected target points to its tracked source, each validator passes, and each declared Arch package is installed. Successful removal means that all managed targets are unlinked.

A package batch stops on the first failed package. Packages that passed verification earlier in the batch stay applied. Follow the printed recovery instructions. Then run `make` and choose the named standalone action.

If the repository moves, repair or remove links from the old path and apply the affected packages again.

## Package-specific installers

A package may include a Bash installer when setup needs more than a documented command. The installer must resolve the repository without assuming a clone path, preview its actions, request confirmation, tolerate repeated execution, and verify the result.

When elevated privileges are required, call the supported Omarchy command and let Omarchy manage the prompt.
