[Back to README](../README.md)

# Laptop power policy

## Scope

This optional policy configures native UPower to hibernate at the selected display battery's action level of exactly 5% and below while it is discharging. It also configures logind lid handling.

## Requirements

The manager supports Omarchy 4 and requires UPower through `upower.service`, logind, the system D-Bus, the Omarchy sleep-lock service, Node.js, `jq`, `flock`, `stat`, `date`, `mkdir`, `mktemp`, `mv`, `rm`, `systemctl`, `systemd-inhibit`, `busctl`, `sudo`, and fixed `/usr/bin` system tools. Apply also requires a built-in battery reported by `omarchy-battery-present`, working hibernation reported by `omarchy-hibernation-available`, and logind `CanHibernate=yes`. Each exact target must be absent or a `root:root 0644` regular file. Remove and recovery do not require current canonical sources, battery eligibility, working hibernation, or `CanHibernate=yes`.

Run the manager as a regular user. Apply, remove, and recovery require a writable absolute `XDG_STATE_HOME`, or the default `~/.local/state`, and a safe root-owned `/run/lock` directory. The manager does not provision or repair hibernation, swap, resume, initramfs, or bootloader configuration.

## Ownership

The repository owns these two sources and their exact deployed targets:

| Source | Target |
| --- | --- |
| `power-policy/upower.conf` | `/etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf` |
| `power-policy/logind.conf` | `/etc/systemd/logind.conf.d/90-dotfiles-laptop-power.conf` |

Both targets are regular `root:root` files with mode `0644`. Lifecycle evidence and retained backups are stored below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/laptop-power-policy/`.

This policy is outside Stow and `packages.json`. It does not own the main UPower or logind configuration, foreign drop-ins, Omarchy package files or power behavior, Omarchy's 10% warning, the Omarchy sleep-lock service, or files below `/usr/share/omarchy/`.

## Policy behavior

| Condition | Native action |
| --- | --- |
| Selected display battery is discharging at 5% or below | After UPower's fixed 20-second cancelable delay, hibernate. |
| Undocked lid close on battery power | Hibernate. |
| Undocked lid close on external power | Suspend. |
| Docked lid close with an enabled external display | Ignore the lid close. |

UPower selects the display battery and provides its state. The policy does not inspect `BAT*` paths, count or aggregate batteries, handle UPS devices separately, or add an external-power veto. Omarchy's independent 10% warning remains unchanged.

## Start the wizard

Run:

```bash
make
```

Choose `Manage laptop power policy`. Its choices are `Status`, `Apply`, `Remove`, and `Back`.

Guided setup calls Apply as optional phase 8 after optional Brave policy phase 7. Battery or hibernation ineligibility and an ordinary declined plan are successful skips. An exact active policy or a completed Apply succeeds. An unsafe path, unsupported Omarchy version, failed logind capability, transaction failure, or recovery outcome stops Guided setup and directs you to `Manage laptop power policy`.

## Status

`Status` is read-only. It does not request privilege, create lifecycle state, activate services, or mutate files or services.

It reports source validity, Omarchy compatibility and eligibility, current service and sleep-lock state, active or pending lifecycle evidence, target state, and the required action. It evaluates effective UPower and logind configuration and runtime values when classifying the result.

## Apply

Apply completes preflight for sources, compatibility, eligibility, receipts, safe paths, targets, competing drop-ins, effective configuration, UPower state, logind capability, and sleep-lock state. It accepts an exact target only when it is absent or a `root:root 0644` regular file, and backs up an accepted existing file before replacement. Other target metadata blocks Apply. Competing drop-ins remain in place, but a later setting that prevents the required policy blocks Apply.

One preview and confirmation cover the complete transaction. After `sudo` approval, the manager revalidates the approved snapshot, writes a pending receipt, stages both sources on their target file systems, and atomically publishes both targets. It enables and starts UPower, reloads logind without restarting it, then restarts UPower. Complete verification checks target bytes and metadata, effective policy, service state, critical action, eligibility, and sleep-lock state before it writes the active receipt.

An exact active policy is a no-op. It does not request confirmation or privilege, rewrite state, create backups, reload logind, or restart UPower.

## State and backups

The state root is a real invoking-user-owned `0700` directory. Receipts and backup files are regular `0600` files. `active.json` records the active deployment, first-Apply target state, and prior UPower service state. `pending.json` records an incomplete Apply or Remove and is the recovery signal. There is no separate recovery receipt.

Transaction backups remain under `backups/<transaction-id>/` after success, rollback, removal, or failure. Receipts are user-owned lifecycle evidence, not administrator-grade authority. Status and Apply inspect current canonical sources. Every mutation inspects current state, fixed paths, targets, foreign drop-ins, services, and effective policy. Remove and recovery use receipts and retained backups and do not require current canonical sources.

## Remove

Remove does not require current canonical sources, battery eligibility, or working hibernation. It requires a valid active receipt and safe current paths. A receipt-owned target whose bytes or metadata changed after Apply blocks removal.

After preview and confirmation, Remove restores each pre-first-Apply target's bytes or absence and the prior UPower enabled and active states. It reloads logind, restores the UPower service state, and verifies the current foreign effective state before clearing active ownership. No receipt and no target is a no-op.

Remove retains repository sources, transaction backups, installed packages, hibernation provisioning, foreign drop-ins, and unrelated files.

## Failure and recovery

A failure before system mutation clears pending state. A later failure rolls back from `pending.json` and verifies the prior targets, UPower service state, effective policy, and active receipt. If rollback cannot be proved, `pending.json` remains and blocks ordinary mutation. The next Apply or Remove offers recovery. Recovery usually restores the pre-operation state. If Apply or Remove had already completed verification and only pending cleanup was interrupted, recovery keeps the completed state and removes the pending receipt. Recovery then stops, so the requested operation must be run again. Retained transaction backups remain available. Run `make` and choose `Manage laptop power policy` for the standalone recovery route.

## Native fallback behavior

The policy adds no custom battery monitor, retry process, timer, notification, or fallback action. Logind can suspend when hibernation is unavailable during a lid close. UPower can use its native fallback chain, including orderly power-off, when critical-battery hibernation is unavailable. A failed accepted transition causes no second action; use the system journal for diagnosis.

Connecting external power or recovering above the action threshold can cancel UPower's 20-second delay.

## Verification

Run structural checks to validate the exact canonical sources without requiring a battery, deployed policy, active service, privilege, or lifecycle-state mutation. Run read-only Status checks before any transition.

Supervised transition checks require passing automated and read-only checks, saved work, a comfortably charged battery, and explicit confirmation before each transition. Test battery lid hibernation and external-power lid suspend. Test docked ignore when an external display is available. Record the power and docked state, effective values, successful resume, secured session, and relevant journal entries. Never drain, wait for, or force a 5% battery transition. If the docked test is unavailable, retain effective-configuration evidence.
