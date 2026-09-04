[Back to README](../README.md)

# Brave

The repository stores one managed policy for Brave Browser and Brave Origin at `brave/managed-policy.json`. The Dotfiles wizard copies the exact source bytes to `/etc/brave/policies/managed/dotfiles.json`. The deployed policy is a regular `root:root` file with mode `0644`.

Both supported products read the same system policy. You do not select a policy target. You must also complete the checklist in this guide for each persistent regular browser profile.

## Requirements

See the root [README](../README.md) for the wizard requirements and the complete Brave runtime tool list.

The supported browser packages are:

- `brave-bin` for Brave Browser
- `brave-origin-bin` for Brave Origin

The related `brave` or `brave-origin` command must belong to its supported package. Policy apply stops if a command is missing, shadowed in `PATH`, not owned by a package, or owned by another package. The wizard inspects these commands but never runs them.

Use one of these Omarchy commands to install a supported browser:

```bash
omarchy install browser brave
omarchy install browser brave-origin
```

You can install one product or both. The Dotfiles wizard does not install, update, or remove a browser package.

Run the wizard as a regular user. Apply, remove, and recovery reject a wizard process that runs as root. The wizard requests `sudo` only after you approve a plan that needs a system change.

Brave policy state requires a writable absolute `XDG_STATE_HOME`. If this variable is not set, the wizard uses `~/.local/state`.

## Ownership

The shared Brave configuration owns these paths and operations:

- `brave/managed-policy.json`
- `/etc/brave/policies/managed/dotfiles.json`
- Receipts and backups below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/brave-policy/`
- Policy status, apply, remove, rollback, and recovery
- The profile checklist, but not its results

The Brave policy is not a Stow package. It has no directory below `config/` and no entry in `packages.json`.

Omarchy continues to own these items:

- Browser installation and removal
- Files below `/usr/share/omarchy/`
- `~/.config/brave-flags.conf`
- `~/.config/brave-origin-flags.conf`
- `/etc/brave/policies/managed/color.json`
- `BrowserThemeColor` and `BrowserColorScheme`

The shared Brave configuration does not own profiles, browser data, credentials, accounts, Sync state, default-browser state, themes, GTK settings, Fontconfig settings, browser font settings, or checklist results.

## Start the wizard

Start the Dotfiles wizard:

```bash
make
```

Choose `Manage Brave policy`. The submenu has these choices:

- `Status`
- `Apply`
- `Remove`
- `Back`

`Guided setup` runs Brave policy apply as optional phase 7, after Wallpaper library deployment. Phase 7 skips successfully if no supported browser is installed or if you decline the policy plan. An exact active policy and a completed apply are successful results. An unsafe provider or path, a transaction failure, or recovery-required state stops Guided setup. Use `Manage Brave policy` to recover.

## Managed policy

The source policy has exactly eleven top-level keys.

| Policy | Managed result |
| --- | --- |
| `BackgroundModeEnabled` | Background mode is off. |
| `BookmarkBarEnabled` | The bookmark bar is visible on all tabs. |
| `BraveAIChatEnabled` | Leo is off in Brave Browser. Brave Origin can ignore this key because Leo is not available. |
| `BraveP3AEnabled` | Brave P3A reporting is off. |
| `EnableMediaRouter` | Cast and media routing are on. This setting does not control Send to your devices. |
| `ExtensionSettings` | Policy installs AdGuard AdBlocker and Bitwarden Password Manager from the Chrome Web Store update service. |
| `HomepageIsNewTabPage` | The managed homepage target is New Tab Page. |
| `MetricsReportingEnabled` | Chromium metrics reporting is off. |
| `ShowHomeButton` | The Home button is hidden. |
| `SpellcheckEnabled` | Spellcheck is on. |
| `SpellcheckLanguage` | The managed spellcheck language list contains only `en-US`. |

The extension entries use `normal_installed`. Policy lets you disable the extensions, but you cannot remove them while the policy is active. Policy does not pin their toolbar icons or set their relative order.

Both products receive the same policy bytes. Brave Origin can ignore `BraveAIChatEnabled` because Leo is not available. The policy source and the receipts contain no credentials, account identifiers, or profile data.

## Status

Choose `Status` before apply. Also use it after a browser installation, update, or removal, and after an unexpected policy change.

Status is read-only. It does not request privilege, create state, or run a browser.

Status reports:

- Source validity and digest
- Installed supported products and package versions
- Supported and unsupported command providers
- Active, pending, and recovery-required receipt state
- Target type, owner, mode, digest, and byte equality
- Managed-directory owner and mode
- Each foreign policy file and its top-level keys
- Key collisions and unsafe paths
- The required apply or remove action
- The trust limits for receipts and `color.json`

Status reports an exact active deployment as healthy. It reports a clean absent deployment as healthy when no supported browser is installed and the remaining policy paths are safe or absent. If a supported browser is installed and the required `/etc/brave` parents are missing, status reports policy-path drift.

Status reports these conditions as unhealthy:

- Invalid source policy
- Unsupported browser provider
- Unsafe system or state path
- Unowned `dotfiles.json`
- Policy collision
- Active-policy drift
- Receipt-owned target that the regular user cannot read
- Interrupted transaction
- Recovery-required state

The implementation baseline is Omarchy `4.0.0-1`, Brave `1.93.136`, Chromium `151.0.7922.137`, and package version `1:1.93.136-1`. The regular Brave Browser baseline came from source review. It was not installed or launched during that review. A different supported package version causes a warning but does not stop static validation. The warning does not add support for that version.

Status does not prove that a running browser loaded the policy. Use the browser checks in this guide after apply.

## Apply

Choose `Apply` from `Manage Brave policy`.

Apply detects installed products from exact package identities. One apply configures both products when both are installed. If neither product is installed, standalone apply reports the unmet requirement and prints both supported Omarchy installation commands. Guided setup treats this result as a successful optional skip.

Before it shows a plan, apply checks:

- The exact source policy
- Supported package identities and versions
- Command ownership
- Receipt and recovery state
- Each destination path component
- The current target and managed-directory metadata
- Each foreign policy file and top-level key
- The current Omarchy version

`/etc/brave` and `/etc/brave/policies` must already be real, root-owned, browser-traversable directories. They must not be user-writable. The managed directory can be absent. If it exists, it must be a real root-owned directory. Omarchy can create it with mode `0777`. Apply treats this mode as a repair condition. Another owner blocks apply.

Apply accepts a foreign policy only if it is a readable regular JSON object with no duplicate members. Its top-level keys must not overlap another policy file. A symbolic link, directory, special file, malformed JSON, duplicate member, writable unexpected file, or key collision blocks apply.

Apply keeps the bytes and metadata of each accepted foreign policy unchanged.

`color.json` is the only writable foreign-policy exception. It must be a regular file that belongs to the invoking user. The owner must be able to write it. The group and other users must not be able to write it. Its keys must not collide with the source policy. The wizard does not back up, write, restore, remove, generate, or adopt `color.json`.

A `dotfiles.json` file without a valid active receipt is unowned. Apply does not replace it. If a readable receipt-owned regular target has drifted, the plan shows the drift and offers a repair.

A receipt-owned regular target can be repaired or removed only when the invoking user can read it. If the target is unreadable, Status, Apply, Remove, and recovery stop before a plan, confirmation, backup, or `sudo`. Run:

```bash
/usr/bin/sudo /usr/bin/chmod 0644 -- /etc/brave/policies/managed/dotfiles.json
```

Then run the policy operation again.

The apply plan shows:

- Installed products and versions
- Baseline warnings
- Any Omarchy major-version mismatch
- Source and target digests
- The complete source-to-target change
- Each foreign policy file and its keys
- Managed-directory repair
- Backup and receipt paths
- Each privileged change
- The effect on both products when both are installed
- Extension behavior
- Browser reload or relaunch effects
- Receipt and `color.json` trust limits

One confirmation covers the full transaction and any displayed Omarchy mismatch. If you decline, the wizard does not request privilege, create a backup or receipt, or change a file.

After approval, the wizard requests privilege and checks the approved state again. It stops if the source, consumers, providers, receipts, paths, metadata, target, or foreign-policy inventory changed.

Privilege is limited to fixed system paths and fixed system tools. The wizard does not run a root shell, Node.js, `jq`, package commands, browser commands, or caller-provided paths through `sudo`.

Apply creates or hardens the managed directory as `root:root 0755`. It stages the approved bytes on the `/etc/brave/policies` file system, outside the managed directory. It sets the stage to `root:root 0644`, validates it, and atomically renames it to `dotfiles.json`. The rename cannot fall back to a cross-filesystem copy.

Before it activates the receipt, apply verifies the exact bytes, digest, JSON shape, owner, mode, managed-directory metadata, foreign-policy inventory, key set, and pending receipt.

If the active deployment is already exact, apply makes no change. It does not ask for confirmation or privilege and does not create a backup, pending receipt, or timestamp.

The wizard does not launch, reload, restart, close, or signal a browser. In `brave://policy`, use `Reload policies` when Brave needs a policy reload. You can also relaunch the browser yourself.

## State, backups, and trust

The wizard stores policy state below:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/brave-policy/
```

The state directory belongs to the invoking user and has mode `0700`. Receipt files have mode `0600`. The wizard writes each receipt through a sibling temporary file and an atomic rename.

The receipt files are:

- `active.json`, which records the active target, digest, transaction, activation time, and original managed-directory metadata
- `pending.json`, which records an incomplete transaction and its recovery data but does not claim ownership
- `recovery-required.json`, which records a failed recovery step and blocks normal mutation

Transaction backups are below `backups/<transaction-id>/`. The wizard backs up only an existing receipt-owned `dotfiles.json` and the prior active receipt. It does not back up `color.json` or another foreign policy. It keeps transaction backups after success, remove, rollback, or failure.

Receipts use a repository-relative source identity. You can move the repository without losing the ability to remove the deployed policy.

Receipts are user-owned lifecycle evidence. They are not administrator-grade proof. A receipt can authorize a change only to the fixed `dotfiles.json` path. The wizard still shows a complete plan, asks for confirmation, checks the current paths, and requests privilege.

The complete policy set has another trust limit. The invoking user can change an accepted user-owned `color.json` after apply and can add an overlapping key. Status and apply detect current collisions. They cannot prevent a later change. The repository protects its root-owned policy file but does not take ownership of Omarchy's color policy.

## Profile checklist

Complete this checklist after the shared policy is active and verified. Complete it once for each persistent regular profile in each installed product. Do not use it for guest or private sessions.

Complete the checklist before you join Brave Sync. If a profile already uses Sync, do not disconnect or reset it. Complete the checklist once against its current state. Accept later changes from Sync. The repository does not monitor or restore them. Do not enable Sync only to make a toolbar action available.

Complete the checklist for each new or migrated profile. Complete it again for profiles in the other Brave product.

Before you start:

1. Open About and note the current product and version.
2. Open `brave://policy`.
3. Use `Reload policies` only if Brave needs it.
4. Confirm that the source policy values appear without errors.
5. Open `brave://management` and confirm the managed state.
6. Check each applicable row through supported visible controls.

Check the visible state in each existing profile. Do not assume that a default value is active.

Use only these temporary result words during the check:

- `Confirmed` when the visible result is already correct
- `Set` when you correct an available control
- `Managed` when policy supplies the result
- `Unavailable` only when the row states an approved product reduction

An unexpected unavailable control is a compatibility failure. Do not add a replacement or enable a removed feature. Do not store a completed checklist, screenshot, policy export, profile name, account identifier, or Sync identifier.

In the table, Browser means Brave Browser. Origin means Brave Origin.

| ID | Required result in Browser and Origin unless noted |
| --- | --- |
| S01 | Record the archive's `Brave 151.1.93.129` version as provenance. Observe the current product and version in About. |
| S02 | Identify the archive as a curated description, not a browser schema. |
| S03 | State that the UI snapshot has no importer or automatic profile application. |
| U01 | Back is visible. |
| U02 | Reload is visible. |
| U03 | Forward is visible. Its enabled state can depend on navigation history. |
| U04 | Add Bookmark is visible. |
| U05 | Home is hidden by `ShowHomeButton: false`. Do not add a manual toggle. |
| U06 | The bookmark bar is visible on all tabs through `BookmarkBarEnabled: true`. |
| U07 | With horizontal tabs, Tab Search is visible on the horizontal tab strip. |
| U08 | Chrome Labs is unavailable. Before Sync, pin Task Manager. If Send to your devices is already available without a Sync change, place it before Task Manager. |
| U09 | After policy installs both extensions, pin AdGuard to the left of Bitwarden. |
| U10 | Browser hides Sidebar, Wallet, Rewards, and News when they are available. Policy disables Leo. Origin hides Sidebar. Leo, Wallet, Rewards, and News are unavailable in Origin. |
| U11 | Sidebar display is Never show. |
| U12 | Browser keeps supported items in this relative order: Talk, Wallet, Bookmarks, Reading List. Origin keeps Bookmarks, then Reading List. Talk and Wallet are unavailable in Origin. |
| U13 | Policy disables Leo in Browser. Leo is unavailable in Origin. |
| U14 | Tabs are horizontal. |
| U15 | Compact horizontal tabs are off. |
| U16 | The derived address bar is standard, narrow, and centered. |
| U17 | Wide address bar is off. |
| U18 | Use system title bar and borders is on. This setting changes window decoration only. |
| U19 | Warn before closing window is on. |
| U20 | Rounded web-content corners are on. |
| U21 | A new tab shows Dashboard. |
| U22 | The new-tab selector is Homepage. |
| U23 | `HomepageIsNewTabPage: true` manages the target as New Tab Page. Do not add a manual toggle. |
| U24 | Dashboard controls are active. |
| U25 | Dashboard clock is on. |
| U26 | Clock format is 24-hour. |
| U27 | Backgrounds use ordinary Brave artwork. Sponsored images are off in Browser and unavailable in Origin. This is not theme management. |
| U28 | News widget is off in Browser and unavailable in Origin. |
| U29 | Rewards widget is off in Browser and unavailable in Origin. |
| U30 | Shields stats are off. |
| U31 | Talk widget is off in Browser and unavailable in Origin. |
| U32 | Shortcuts are off. |
| U33 | Most visited is selected as the current meaning of Top Sites before shortcuts are hidden. |
| U34 | Accepted languages are ordered `en-US`, then `en`. This order is separate from the managed spellcheck language. |
| U35 | Related Website Sets is off through Brave's supported privacy behavior. |

The table uses source order, not task order. Confirm horizontal tabs before you place Tab Search. Select Most visited before you hide shortcuts.

Use this exact sequence for new tabs:

1. Set the new-tab selector to Homepage.
2. Verify that policy manages the target as New Tab Page.
3. Verify that a new tab shows Dashboard.
4. Verify that Dashboard controls are active.

Do not replace this sequence with the direct Dashboard selector.

Keep the relative order of each available array member. Do not use flags or enable an unavailable feature to replace a missing member.

## Safe browser verification

Use only these visible browser surfaces:

- About
- `brave://policy`
- `brave://management`
- Supported Settings pages
- Toolbar customization
- Sidebar customization
- New Tab Page controls
- Languages
- Supported privacy controls

You can reload policy or relaunch the browser when Brave requires it.

Do not read, compare, copy, or edit these files or data stores:

- `Preferences`
- `Secure Preferences`
- `Local State`
- Browser databases
- Extension-private data

Do not use browser automation, developer tools, `brave://flags`, Reset settings, command-line preference overrides, an importer, or running-process command lines.

Do not load, replace, reset, remove, or verify a browser theme. Do not change browser font settings, GTK settings, Fontconfig settings, Omarchy launch flags, or page-font controls. The system title-bar choice changes window decoration only.

## Product changes and browser updates

The policy has no product-specific apply, remove, or switch operation. Both products read the same policy path.

To change products:

1. Install the destination product through Omarchy.
2. Choose `Status` or `Apply` in `Manage Brave policy`.
3. Complete the checklist for each destination profile.
4. Remove the source product separately if you no longer need it.

One policy apply affects both products when both are installed.

A browser installation or reinstall can change the managed directory to mode `0777`. Status reports this drift. Apply offers a confirmed repair. Removal of the final Brave product can remove `/etc/brave`. Apply the policy again after you install a supported product.

If a browser update changes the validated version or an affected Settings surface, check these items again:

- Policy status
- Visible labels
- Control availability
- Setting meaning
- Approved product reductions
- Renamed mappings
- Each affected checklist row

This compatibility check does not reverse later changes that you accepted from Sync.

## Remove

Choose `Remove` from `Manage Brave policy`.

Remove does not require an installed browser or a valid current source policy. It uses the active receipt, the fixed target path, and a new path check. It reports an unsupported browser provider but does not let that provider block removal of a receipt-owned target.

If no receipt and no target exist, remove makes no change. If a target exists without a receipt, the wizard treats it as unowned and does not remove it. If an active receipt exists but the target is missing, confirmed remove clears the stale receipt without recreating `/etc/brave` or the policy.

The remove plan shows:

- Target drift
- Backup paths
- Managed-directory restoration or retained hardening
- Extension behavior
- Delayed browser effects
- Foreign policy
- Any Omarchy major-version mismatch

One confirmation covers the full remove plan and any displayed Omarchy mismatch. The wizard backs up a receipt-owned regular target, removes only `dotfiles.json`, and verifies that it is absent. It clears active ownership while the managed directory is still hardened, performs any safe metadata restoration, and inspects the final target and directory state before reporting success.

A foreign JSON error, key collision, or later foreign file does not block removal of a separate receipt-owned regular target after the directory is secure. A symbolic-link target, special target, unreadable receipt-owned target, unsafe parent path, or invalid receipt blocks remove.

The wizard restores the original managed-directory metadata only when no foreign policy remains except a valid `color.json`. If the directory was originally absent, the wizard removes it only when it is empty. In all other cases, the wizard keeps `root:root 0755` and reports the retained hardening.

Remove does not change these items:

- `brave/managed-policy.json`
- Transaction backups
- Browser packages
- Profiles and browser data
- Manual checklist choices
- Installed extensions
- Omarchy flag files
- Themes and fonts
- `color.json` or other foreign policy

Extensions can remain installed after policy removal, but you can then remove them. Policy effects can remain until you reload policy or relaunch the browser. Omarchy's `color.json` can keep the managed indicator visible.

The wizard does not launch, reload, restart, close, or signal a browser during remove.

## Failure and recovery

A failure before a system change removes the pending receipt and leaves the system unchanged. A later failure tries to restore the exact previous target, managed-directory metadata, and active receipt. The wizard verifies the restored state and keeps the transaction backup.

Each new Apply or Remove first checks for an interrupted transaction. If the requested operation already reached all postconditions, recovery completes the remaining receipt or stage cleanup. Otherwise, the wizard shows a plan to restore the previous state. After a successful restoration, run the requested operation again.

If rollback or verification fails, the wizard keeps `pending.json`, writes `recovery-required.json`, and reports the failed step and backup path. Normal Apply and Remove remain blocked. Only the related recovery attempt can run. The wizard does not continue with a normal operation in the same run.

Recovery and stale-state cleanup do not recreate `/etc/brave` or a removed policy only to repair user state.

Start `make`, choose `Manage Brave policy`, and follow the reported recovery action.
