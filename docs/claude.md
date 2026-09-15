[Back to README](../README.md)

# Claude Code

The `claude` Stow package keeps Claude Code user settings in the Dotfiles repository. It links one file:

- `~/.claude/settings.json`, linked to `config/claude/.claude/settings.json`

Stow links the file with `--no-folding`. `~/.claude/` stays an ordinary local directory.

## Requirements

- Omarchy 4.0.
- Claude Code 2.1, version 2.1.270 or later, installed through Mise. The package does not install or update Claude Code.
- Node.js 18 or later as `node` on `PATH`. The claude-hud status line runs with it.

Apply checks the Claude Code version:

- 2.1.270 or later in the 2.1 series: apply continues.
- Earlier than 2.1.270: apply stops. Update Claude Code through Mise, then apply again.
- A different minor series, such as 2.2: apply shows a warning and continues. Before you rely on the package, compare the tracked settings with the defaults of the new Claude Code version.
- No `claude` command: apply stops in the plan phase.

## Tracked settings

`settings.json` contains attribution, model, per-model effort, voice, `skipDangerousModePermissionPrompt`, and the Omarchy theme (`custom:omarchy`). It also declares the claude-hud plugin marketplace (`jarrodwatts/claude-hud`), enables `claude-hud@claude-hud`, and sets the claude-hud status line. The status line runs `node` from `PATH`, so it contains no home path and no Node.js version.

The file contains no credentials. Stop before you add a credential or token to it.

`keybindings.json` and a global `CLAUDE.md` are not in the package. Add each one as a leaf link only when you have a first key binding or a first global instruction to keep.

## What restores itself

The first time you start `claude` interactively in a trusted folder, Claude Code installs the declared claude-hud plugin. The package and the wizard do not install plugins.

The Dotfiles wizard installs global skills from `skills.json`. The package does not track skills.

## What stays local

The package does not track `hooks/`, `agents/`, `commands/`, `skills/`, `plugins/`, `themes/`, credentials, history, transcripts, jobs, or caches. Plugins and skills own their content. Omarchy owns `~/.claude/themes/omarchy.json`.

## Changes through the link

Claude Code writes `settings.json` through the link, so each change appears as a Git diff in the repository. Review the diff, then commit it or run `git restore`.

You do not need `omarchy-theme-set-claude --activate`, because the package already sets `theme`. If the command runs, it replaces the link with a regular file. To recover:

1. Copy the changes you want to keep into `config/claude/.claude/settings.json`.
2. Delete `~/.claude/settings.json`.
3. Start `make`, choose `Apply Stow packages`, and select `claude`.

## Removal

Start `make`, choose `Remove Stow package`, and select `claude`. Removal deletes only the link, so `~/.claude/settings.json` is absent until you apply the package again. Claude Code, its state, installed plugins, and skill links stay in place.

