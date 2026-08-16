# Agent setup

This guide describes the planned global installation of the agent skills used for development. The installer and `skills.json` do not exist yet.

Skills will install under `~/.agents/skills/` from two pinned sources:

- `https://github.com/blader/humanizer`
- `https://github.com/mattpocock/skills`

Each source repository's official installer controls skill discovery and supporting files. This repository adds version tracking, difference review, confirmation, backup, and recovery.

## Stored versions

The planned root `skills.json` file will store:

- The source repository URL
- The approved full Git commit ID
- The source's official installation method
- The expected number of installable skills
- The pinned Skills CLI version
- The global target path

Initial approved versions:

| Source | Revision | Expected skills |
| --- | --- | --- |
| `blader/humanizer` | `523374dee72d67c7b2b5f858ea0094ffda49c3ac` | 1 |
| `mattpocock/skills` | `068b6e0c62393147daf03530149cdce209c93da8` | 35 |

The initial Skills CLI version is `1.5.22`.

Normal installation uses the stored revisions. If upstream or installed content differs, the installer shows the difference and asks what to do.

## Preview

Official installers run in an isolated temporary environment before any global change. Preview classifies each result:

| State | Meaning | Action |
| --- | --- | --- |
| `ADD` | The skill is not installed | Include it in the proposed plan |
| `UNCHANGED` | Installed content matches | Make no change |
| `CHANGE` | Installed files differ | Show a recursive diff and stop |
| `CONFLICT` | The target has an unexpected type or link | Show its type and target, then stop |

Unrelated global skills are left alone. A preview cannot write to the real `~/.agents/skills/`.

## Installation and recovery

After approval:

1. Back up each changed global skill below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/skill-backups/<UTC timestamp>/`.
2. Run the source repository's official installer for the stored revision.
3. Compare the installed result with the approved preview.
4. Restore a failed replacement from backup and stop.
5. Keep successful installations completed earlier in the run.

New skills need no backup. Unchanged skills receive no write. The installer prints every backup path and verification result.

## Updates

`make skills-update` will compare the stored revisions with current upstream revisions. It will show commit summaries, source differences, and installed-skill differences before asking for approval.

After approval, the command will:

1. Preserve the old `skills.json` and affected global skills.
2. Write the approved revisions to `skills.json`.
3. Run the official installers.
4. Verify the global result against the new manifest.

If any step fails, the command restores both the old manifest and global skill backups. The update is complete only when `skills.json` and the installed collections match.

## Safety

The development requirements are listed in the root README.

Skills CLI runs set `DISABLE_TELEMETRY=1`. Preview uses temporary home, state, and npm cache directories. Global installation runs as the current user and does not use `sudo`.

Review changed skill files before approval because installed skills run with the agent's permissions. Restart the agent or reload its skills after installation.
