# Firefox

## Layout
- `firefox/profile/` - Files stowed into the active Firefox profile.
- `firefox/backup/` - Backup copies (e.g. `prefs.js`).
- `firefox/scripts/` - Helper scripts.

## Order
1) Install Textfox: `firefox/scripts/install-textfox.sh`
2) Restore settings: `firefox/scripts/stow-firefox-profile.sh`

## Scripts
- `firefox/scripts/firefox-active-profile-path.sh` - prints the active Firefox profile path.
- `firefox/scripts/backup-firefox-prefs.sh` - backs up `prefs.js` to `firefox/backup/prefs.js`.
- `firefox/scripts/restore-firefox-prefs.sh` - restores `prefs.js` from `firefox/backup/prefs.js`.
- `firefox/scripts/stow-firefox-profile.sh` - restores prefs, then stows `firefox/profile/` into the active profile.
- `firefox/scripts/sync-firefox-profile.sh` - backs up prefs, then stows profile.
- `firefox/scripts/install-textfox.sh` - installs Textfox into the active profile.

## Textfox
- The installer clones the repo into a temp dir and cleans up afterward.
- By default it installs `user.js`; set `TEXTFOX_INSTALL_USER_JS=0` to skip it.
