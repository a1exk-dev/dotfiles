# OpenCode

OpenCode console configuration and desktop notifications.

## Link Config

From the repository root:

```sh
stow --adopt -t "$HOME" opencode
```

## Notifications

The global plugin at `~/.config/opencode/plugins/notifications.js` sends desktop notifications through `notify-send` when:

- OpenCode asks a question
- OpenCode requests permission
- An operation finishes and its top-level session becomes idle

Ensure `notify-send` is installed and a notification daemon is running. Quit and restart OpenCode after changing plugins because they are loaded only at startup.
