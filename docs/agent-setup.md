# Agent setup

The Dotfiles wizard installs pinned global agent skills from the official Humanizer and Matt Pocock repositories. Each repository's official installer controls skill discovery and supporting files. This repository adds version tracking, difference review, confirmation, backup, verification, and recovery.

## Requirements

See the root [README](../README.md) for the global skill requirements.

The Skills CLI runs with `DISABLE_TELEMETRY=1`. Preview uses a temporary home directory, state directory, and npm cache. Global installation runs as the current user without `sudo`.

## Wizard actions

Start the Dotfiles wizard with:

```bash
make
```

`Guided setup` installs pinned global skills after prerequisite preparation. It runs this phase before application cleanup and Stow package application.

The standalone menu actions are:

- `Install pinned global skills`
- `Update pinned global skills`

These Make targets start the related preselected interactive action:

```bash
make skills
make skills-update
```

Both actions inspect the proposed changes and ask for confirmation before a mutation.

## Stored versions

The root `skills.json` file stores each source URL, approved full Git commit ID, official installation method, expected skill count, pinned Skills CLI version, and global target.

| Source | Revision | Expected skills |
| --- | --- | --- |
| `blader/humanizer` | `523374dee72d67c7b2b5f858ea0094ffda49c3ac` | 1 |
| `mattpocock/skills` | `068b6e0c62393147daf03530149cdce209c93da8` | 35 |

The pinned Skills CLI version is `1.5.22`. Skills install below `~/.agents/skills/`.

## Installation

Choose `Install pinned global skills` or run `make skills`.

The wizard checks out each stored revision and runs its official installer in an isolated preview environment. It reports these states:

| State | Meaning |
| --- | --- |
| `ADD` | The skill is not installed |
| `UNCHANGED` | Installed content matches the candidate |
| `CHANGE` | Installed files differ |
| `CONFLICT` | The target has an unexpected type or symbolic link |

A change includes a recursive diff. A conflict stops before global installation. The approved plan does not include unrelated global skills.

After confirmation, the wizard backs up every existing skill that a source installer can rewrite. It stores backups below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/skill-backups/<timestamp>/`.

The official installer installs the stored revision. The wizard compares the result with the approved preview and verifies that unrelated skills did not change.

If one source fails, the wizard restores the existing skills for that source, removes failed additions, and stops. Sources that completed earlier stay installed.

A declined plan makes no changes. If all manifest-owned skills match, the action succeeds without a global installation.

## Updates

Choose `Update pinned global skills` or run `make skills-update`.

The wizard compares stored revisions with upstream and shows:

- Commit summaries
- Source differences
- Candidate skill additions, removals, and file changes
- Differences from installed skills

Each skill must have one source. An ownership collision stops before approval.

After confirmation, the wizard backs up the old manifest and all affected global skills below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/skill-update-backups/<timestamp>/`. It updates `skills.json` and the affected global skill collections as one transaction.

An installation or verification failure restores the previous `skills.json` and all affected global skills. The update does not change unrelated skills.

Restart the agent or reload its skills after a successful installation or update.
