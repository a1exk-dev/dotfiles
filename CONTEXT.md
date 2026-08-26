# Canonical Context

## Dotfiles repository

Portable Omarchy dotfiles for the current supported Omarchy version, deployed with GNU Stow. The repository is the source of truth for configuration files, scripts, hooks, themes, and required assets. It excludes live application state and complements Omarchy rather than owning general operating-system package provisioning. The wizard delegates explicit repository prerequisites and package-specific Arch requirements to Omarchy. The current target is Omarchy version 4.

## Stow package

A lowercase-named deployment unit under `config/<name>/` for one application or tightly coupled configuration concern. Its directory tree mirrors target paths under the user's home directory, and GNU Stow deploys it through symlinks instead of copying its files. Users edit the source inside the repository.

## Dotfiles wizard

The intended human interface for repository setup and operations. Guided setup runs prerequisite preparation, pinned global agent-skill installation, application cleanup, and Stow package application, then optionally applies the Shared Brave configuration as phase five. Standalone actions provide each operation separately. Public routes provide the same operations to Make targets, agents, scripts, and tests.

## Shared Brave configuration

One repository-owned managed-policy intent for Brave Browser and Brave Origin. Both products consume the same system policy, while browser profiles, Omarchy-owned launch flags and color policy, theme state, and font settings remain outside this boundary. Product differences belong to installed-consumer detection and manual guidance rather than duplicated policy sources.

## Application cleanup profile

The root `cleanup.json` file that contains saved selection defaults for removable Arch packages, Omarchy web apps, and Omarchy TUI launchers. Available defaults start selected during application cleanup. A selection change applies only to the current run. The profile does not record installed state and does not continuously suppress applications.

## Package catalog

`packages.json` is the package catalog. Each entry declares a Stow package's description, command prerequisites, Arch package requirements, Stow dependencies, validators, documentation, and cleanup notes.

## Skill manifest

The root `skills.json` file containing exact source revisions, each repository's official installation method, expected collection sizes, and installation requirements for global agent skills placed under `~/.agents/skills/`.

## Telegram theme integration

A dedicated `telegram-theme` Stow package that adapts the active Omarchy semantic colors to Telegram Desktop's native theming. The repository owns the color mapping and integration lifecycle; generated output is integration-owned, regenerable local state; Telegram owns saved theme and account state. The visual promise is Omarchy colors and clear native sections within Telegram's native structure, rather than structural TUI styling.
