# Brave

Brave is Chromium-based, so it supports Chrome Web Store extensions and Chromium policies. The installed snapshot is Brave `151.1.93.129` from the Arch package `brave-bin` `1:1.93.129-1`.

## Install

```sh
yay -S brave-bin
```

## Theme Deployment

Install the shared theme manager from the repository root:

```sh
stow --no-folding -t "$HOME" theme-tools
dotfiles-theme --dry-run install
dotfiles-theme install
```

The manager restows the Brave package with `--no-folding -R` and never uses `--adopt`. It creates both extension roots as real directories:

- `${XDG_DATA_HOME:-$HOME/.local/share}/brave/themes/current`
- `${XDG_DATA_HOME:-$HOME/.local/share}/brave/themes/everforest-hard`

In each directory, only `manifest.json` is bridged to the active bundle. Keeping both parents real lets Brave create `Cached Theme.pak` beside either manifest without writing cache data into this repository. No live Brave profile files are linked. See [Theme management](21-theme.md).

## Managed Policy

The source policy is `brave/policies/brave.json`. From the repository root, install it as a root-owned system policy:

```sh
sudo install -Dm644 brave/policies/brave.json /etc/brave/policies/managed/dotfiles.json
```

The policy is intentionally not Stowed into `/etc`: a managed system policy must be root-owned and must not remain user-writable through a link to this repository.

Restart Brave, then open `brave://policy` to verify the loaded settings. Installing a managed policy makes Brave display `Managed by your organization` even on a personal machine.

Remove the policy with:

```sh
sudo rm /etc/brave/policies/managed/dotfiles.json
```

Restart Brave again after removal.

## Policy-Backed Settings

| Setting | Current behavior |
| --- | --- |
| Background mode | Disabled; Brave does not keep background apps running after it closes. |
| Bookmark bar | Shown. |
| Brave AI Chat | Disabled, including Leo integrations controlled by this policy. |
| Brave P3A | Disabled; privacy-preserving product analytics are not sent. |
| Media Router | Enabled for casting media. |
| Metrics reporting | Disabled. |
| Home button | Hidden. |
| Spellcheck | Enabled. |
| Spellcheck language | `en-US`. |
| Managed extensions | AdGuard and Bitwarden are installed normally, so users can still disable them. |

## Theme

Brave supports themes from the Chrome Web Store. Chromium defines themes as special extensions that change browser appearance without JavaScript or HTML code. This repository's no-code, no-permission Manifest V3 theme applies the active palette to browser chrome and supported New Tab colors; it does not style website content.
Brave has no explicit theme hover key, so this theme uses Everforest Background 4 as the toolbar endpoint, placing Brave's derived toolbar-button and inactive-tab hover states near Background 2 and Background 1, respectively.

Activate the managed theme once:

1. Open `brave://extensions`.
2. Enable **Developer mode**.
3. Select **Load unpacked**.
4. Choose `${XDG_DATA_HOME:-$HOME/.local/share}/brave/themes/current`.

Existing installations loaded from the legacy `everforest-hard` directory continue to work through its compatibility bridge. Theme activation is stored in Brave's profile and is intentionally not Stowed. Reset the theme or remove the unpacked theme through Brave's UI.

The currently enabled branded New Tab backgrounds can obscure the theme's solid New Tab background. Disable branded backgrounds manually to see that color.

## UI Snapshot

`brave/ui-settings.json` is a sanitized, descriptive snapshot of the observed Brave `151.1.93.129` interface. It is documentation only, is not applied automatically, and deliberately does not use Chromium's live profile structure. These version-sensitive settings must be checked manually after setup and significant upgrades.

### Navigation and Toolbar

| Control | Observed state |
| --- | --- |
| Back | Visible (default) |
| Reload | Visible (default) |
| Forward | Visible |
| Add Bookmark | Visible (default) |
| Home | Hidden |
| Bookmark bar | Visible on all tabs |
| Tab Search | Visible and pinned to the horizontal tab strip |

Pinned toolbar actions, in order:

1. Chrome Labs
2. Send to your devices
3. Task Manager

Pinned extensions are AdGuard AdBlocker and Bitwarden Password Manager. Hidden browser buttons and actions are Sidebar, Leo, Wallet, Rewards, and Brave News.

VPN, Shields, Screenshot, and other contextual or absent controls are intentionally not inferred.

### Sidebar

The sidebar is set to never show. Its configured built-in items remain, in order: Brave Talk, Wallet, Bookmarks, and Reading List. Leo is hidden.

### Layout and Behavior

| Setting | Observed state |
| --- | --- |
| Tabs | Horizontal and non-compact |
| Address bar | Standard, narrow, centered layout; wide mode off |
| Window decorations | Native system decorations |
| Close-window confirmation | On |
| Rounded web content corners | On |
| Languages | `en-US`, `en` |
| Related Website Sets | Off |

### New Tabs

Homepage is the configured selector, and its target is New Tab Page. The effective new-tab mode is therefore Dashboard.

The following Dashboard choices are active:

| Active Dashboard preference | Current choice |
| --- | --- |
| Clock | On, 24-hour format |
| Branded backgrounds | On |
| News widget | Off |
| Rewards widget | Off |
| Shields stats widget | Off |
| Brave Talk widget | Off |
| Shortcuts | Off |
| Configured shortcut source | Top Sites, if shortcuts are enabled |

## Extensions

| Extension | Observed version | State | ID |
| --- | --- | --- | --- |
| AdGuard AdBlocker | `5.4.3.115` | Enabled | `bgnkhhnnamicmpeenaelnjfhikgbkllg` |
| Bitwarden Password Manager | `2026.7.0` | Enabled | `nngceckbapebfimnlniiiahkandclblb` |

The policy tracks extension IDs and installs current Chrome Web Store releases; it does not pin these observed snapshot versions. `normal_installed` keeps both extensions user-disableable.

## Privacy Boundary

Never commit or symlink Brave user-data or profile files. Excluded data includes account, sync, and profile IDs; history, tabs, and sessions; cookies, site storage, and permissions; bookmarks; passwords and logins; autofill and payment data; download paths and history; extension private storage; and caches and telemetry IDs. Live `Preferences`, `Local State`, and `Secure Preferences` files are intentionally not tracked. The UI snapshot contains only curated labels and states; no homepage URL is tracked.

Safe path references:

- Managed theme targets: `${XDG_DATA_HOME:-$HOME/.local/share}/brave/themes/current/manifest.json` and `${XDG_DATA_HOME:-$HOME/.local/share}/brave/themes/everforest-hard/manifest.json`
- Stable profile root: `$XDG_CONFIG_HOME/BraveSoftware/Brave-Browser/`, or `$HOME/.config/BraveSoftware/Brave-Browser/` when `XDG_CONFIG_HOME` is unset
- Managed Linux policy path: `/etc/brave/policies/managed/dotfiles.json`

## Sources

- [Brave Group Policy documentation](https://support.brave.com/hc/en-us/articles/360039248271-Group-Policy)
- [Brave extensions documentation](https://support.brave.com/hc/en-us/articles/360017909112-How-can-I-add-extensions-to-Brave)
- [Brave appearance customization](https://brave.com/whats-new/customize-appearance/)
- [Brave toolbar customization](https://support.brave.app/hc/en-us/articles/39269576876685-How-do-I-customize-the-toolbar-in-Brave)
- [Chrome theme documentation](https://developer.chrome.com/docs/extensions/develop/ui/themes)
