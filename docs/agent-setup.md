# Agent setup

The Dotfiles wizard installs pinned global agent skills from the official Humanizer and Matt Pocock repositories. Each repository's official installer controls skill discovery and supporting files. This repository adds version tracking, difference review, confirmation, backup, verification, and recovery.

## Requirements

See the root [README](../README.md) for the global skill requirements.

Skills CLI runs with `DISABLE_TELEMETRY=1`. Preview uses a temporary home, state directory, and npm cache. Global installation runs as the current user without `sudo`.

## Stored versions

The root `skills.json` file records each source URL, approved full Git commit ID, official installation method, expected skill count, pinned Skills CLI version, and global target.

| Source | Revision | Expected skills |
| --- | --- | --- |
| `blader/humanizer` | `523374dee72d67c7b2b5f858ea0094ffda49c3ac` | 1 |
| `mattpocock/skills` | `068b6e0c62393147daf03530149cdce209c93da8` | 35 |

The pinned Skills CLI version is `1.5.22`. Skills install under `~/.agents/skills/`.

## Commands

```bash
./bin/dotfiles skills
./bin/dotfiles skills --yes
make skills

./bin/dotfiles skills-update
./bin/dotfiles skills-update --yes
make skills-update
```

Run a command without `--yes` to inspect the proposed changes. If the plan contains a mutation, the command exits and asks for a decision. Review that output before rerunning with `--yes`.

Use `--allow-omarchy-mismatch` only after reviewing compatibility.

## Installation

The `skills` command checks out each stored revision and runs its official installer in an isolated preview environment. It classifies manifest-owned skills as:

| State | Meaning |
| --- | --- |
| `ADD` | The skill is not installed |
| `UNCHANGED` | Installed content matches the candidate |
| `CHANGE` | Installed files differ |
| `CONFLICT` | The target has an unexpected type or symbolic link |

A change includes a recursive diff. A conflict always stops before global installation. Unrelated global skills are not changed.

After approval, the command backs up every existing skill that a mutating source installer could rewrite. Backups are stored below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/skill-backups/<timestamp>/`.

The official installer then installs the stored revision. The command compares its output with the approved preview. If a source fails, the command restores all existing skills from that source, removes failed additions, and stops. Sources completed earlier in the run remain installed.

## Updates

`skills-update` compares stored revisions with upstream and shows:

- Commit summaries
- Source differences
- Candidate skill additions, removals, and file changes
- Differences from installed skills

The proposed collections must have unique skill ownership across all sources. A collision stops before approval.

After approval, the command backs up the old manifest and every affected global skill below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/skill-update-backups/<timestamp>/`. It updates the manifest and changed collections as one transaction.

An installation or verification failure restores the previous `skills.json` and every affected global skill. Unrelated skills are not changed.

Restart the agent or reload its skills after a successful installation or update.
