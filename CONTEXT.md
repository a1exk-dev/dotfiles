# Canonical Context

## Dotfiles repository

Portable Omarchy dotfiles for the current supported Omarchy version, deployed with GNU Stow. The repository is the source of truth for configuration files, scripts, hooks, themes, and required assets. It excludes live application state and complements Omarchy rather than owning general operating-system or package provisioning, with explicit bootstrap exceptions for repository prerequisites and required agent skills. The current target is Omarchy version 4.

## Stow package

A lowercase-named deployment unit under `config/<name>/` for one application or tightly coupled configuration concern. Its directory tree mirrors target paths under the user's home directory, and GNU Stow deploys it through symlinks instead of copying its files. Users edit the source inside the repository.

## Dotfiles wizard

The intended human interface for repository setup and operations. Guided setup runs prerequisite preparation, pinned global agent-skill installation, application cleanup, and Stow package application. Standalone actions provide each operation separately. Public routes provide the same operations to Make targets, agents, scripts, and tests.

## Application cleanup profile

The root `cleanup.json` file that contains saved selection defaults for removable Arch packages, Omarchy web apps, and Omarchy TUI launchers. Available defaults start selected during application cleanup. A selection change applies only to the current run. The profile does not record installed state and does not continuously suppress applications.

## Package catalog

The root `packages.json` file containing package descriptions, prerequisites, dependencies, validation, documentation, and cleanup notes consumed by the dotfiles wizard through `jq`.

## Skill manifest

The root `skills.json` file containing exact source revisions, each repository's official installation method, expected collection sizes, and installation requirements for global agent skills placed under `~/.agents/skills/`.
