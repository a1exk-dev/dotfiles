# Arch Hibernation With Disk Swap

Enable suspend-to-disk on Arch Linux when the hibernation target is a disk-backed swap partition or swap file.

This guide assumes:

- If a swap file is used, it is on the root filesystem, not under `/home`, `/root`, or `/run/user`.
- The system uses Arch's default `systemd` userspace sleep commands.
- The system uses `mkinitcpio`, which is Arch's default initramfs generator.
- Commands are run from an installed system, not the live ISO.

## Important Notes

Hibernation needs one disk-backed swap area large enough to hold the hibernation image. It cannot hibernate to zram.

For a swap partition, the kernel needs one boot parameter:

- `resume=` points to the swap partition.

For a swap file, the kernel needs two boot parameters:

- `resume=` points to the block device or filesystem containing the swap file.
- `resume_offset=` points to the physical start offset of the swap file.

On UEFI systems with a systemd-based initramfs, systemd can store the hibernation target in the `HibernateLocation` EFI variable. This document still configures explicit kernel parameters because they are predictable and work for disk swap setups.

If the system uses `linux-hardened` or kernel lockdown, hibernation may not be available.

## Automated Setup for This System

This repo includes a helper script for this machine's current Arch setup:

- Root filesystem: ext4 on the main NVMe disk.
- Existing swap partition: `/dev/nvme0n1p2`.
- Boot loader: systemd-boot.
- Boot entry: `/boot/loader/entries/2026-03-09_23-22-57_linux.conf`.
- Initramfs: mkinitcpio with busybox hooks.

Run it from the dotfiles repo root:

```sh
sudo _scripts/enable-arch-hibernation-swapfile.sh
```

The script prefers the largest existing disk swap partition. On this system, that means it uses `/dev/nvme0n1p2` directly and configures `resume=UUID=...` without creating `/swapfile`.

If no swap partition exists, the script creates `/swapfile` on the root filesystem. The default fallback size is installed RAM rounded up to GiB plus 8 GiB. It then adds the file to `/etc/fstab` and configures both `resume=...` and `resume_offset=...`.

In both modes, the script adds the `resume` mkinitcpio hook, updates the systemd-boot entry, runs `mkinitcpio -P`, and launches `_scripts/configure-lid-hibernate.sh` at the end.

It does not reboot or hibernate automatically. After it finishes, reboot:

```sh
sudo reboot
```

After booting again, test manually:

```sh
sudo systemctl hibernate
```

Optional overrides:

```sh
sudo SWAPFILE=/swapfile SWAP_SIZE=36G BOOT_ENTRY=/boot/loader/entries/2026-03-09_23-22-57_linux.conf _scripts/enable-arch-hibernation-swapfile.sh
```

`SWAP_SIZE` is only used when the script has to create a fallback swap file.

## Lid Close Hibernation

The lid helper configures systemd-logind so closing the laptop lid triggers hibernation:

```sh
sudo _scripts/configure-lid-hibernate.sh
```

It writes this drop-in:

```ini
# /etc/systemd/logind.conf.d/hibernate-on-lid.conf
[Login]
HandleLidSwitch=hibernate
HandleLidSwitchExternalPower=hibernate
HandleLidSwitchDocked=ignore
```

The main hibernation setup script runs this automatically. The lid helper does not restart `systemd-logind` by default because that can disrupt the current graphical session. The policy applies after reboot.

To apply it immediately instead, run:

```sh
sudo RESTART_LOGIND=1 _scripts/configure-lid-hibernate.sh
```

Optional lid policy overrides:

```sh
sudo HANDLE_LID_SWITCH=hibernate HANDLE_LID_SWITCH_EXTERNAL_POWER=hibernate HANDLE_LID_SWITCH_DOCKED=hibernate _scripts/configure-lid-hibernate.sh
```

Lid-open wake from hibernation is firmware-dependent. Linux can configure lid close to hibernate, but waking from S4/powered-off hibernation on lid open usually requires firmware support such as a BIOS/UEFI "power on lid open" option. If the firmware does not support it, press the power button to resume.

## Inspect the System

Check whether the kernel exposes hibernation support:

```sh
cat /sys/power/state
cat /sys/power/disk
```

`/sys/power/state` should include `disk`.

Check the root filesystem and current swap devices:

```sh
findmnt -no SOURCE,FSTYPE,UUID,OPTIONS /
swapon --show --output=NAME,TYPE,SIZE,USED,PRIO
free -h
```

Check whether zram is active:

```sh
swapon --show --output=NAME,TYPE | grep -i zram || true
```

zram can stay enabled for normal swap usage, but hibernation must target a real disk swap partition or swap file.

## Choose Swap Size and Path

Use a swap file at `/swapfile` unless there is a specific reason to use another path.

Choose a size at least as large as RAM, plus some margin. Example for a 32 GiB swap file:

```sh
SWAPFILE=/swapfile
SWAP_SIZE=32G
```

Check that the target does not already exist:

```sh
sudo test ! -e "$SWAPFILE"
```

If that command fails, inspect the existing file before replacing it:

```sh
ls -lh "$SWAPFILE"
swapon --show --output=NAME,TYPE,SIZE,USED,PRIO
```

## Create the Swap File

First identify the filesystem that will contain the swap file:

```sh
SWAP_PARENT="$(dirname "$SWAPFILE")"
findmnt -no FSTYPE -T "$SWAP_PARENT"
```

### ext4, XFS, F2FS, or Other Non-Btrfs Filesystems

Create, secure, format, and enable the swap file:

```sh
sudo fallocate -l "$SWAP_SIZE" "$SWAPFILE"
sudo chmod 600 "$SWAPFILE"
sudo mkswap -U clear "$SWAPFILE"
sudo swapon "$SWAPFILE"
```

If `fallocate` fails, use `dd` instead. Replace `32768` with the size in MiB:

```sh
sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=32768 status=progress
sudo chmod 600 "$SWAPFILE"
sudo mkswap -U clear "$SWAPFILE"
sudo swapon "$SWAPFILE"
```

### Btrfs Root Filesystem

For Btrfs, use the Btrfs-aware swap-file command. Do not create a normal copy-on-write file with `fallocate`.

```sh
sudo btrfs filesystem mkswapfile --size "$SWAP_SIZE" --uuid clear "$SWAPFILE"
sudo swapon "$SWAPFILE"
```

If the system uses Btrfs snapshots, prefer keeping the swap file out of snapshots. One common layout is a dedicated `/swap` subvolume with `/swap/swapfile` as the swap file. That layout is optional and must match the existing Btrfs subvolume design.

Verify that swap is active:

```sh
swapon --show --output=NAME,TYPE,SIZE,USED,PRIO
free -h
```

## Persist Swap File in fstab

Add the swap file to `/etc/fstab`:

```sh
grep -qE "^[[:space:]]*$SWAPFILE[[:space:]]+none[[:space:]]+swap" /etc/fstab || printf '%s none swap defaults 0 0\n' "$SWAPFILE" | sudo tee -a /etc/fstab
```

Verify the `fstab` syntax:

```sh
sudo findmnt --verify --verbose
```

## Get the Resume Parameters

If using a swap partition, `resume=` should identify the swap partition and no `resume_offset=` is needed:

```sh
SWAP_PARTITION=/dev/nvme0n1p2
RESUME_UUID="$(blkid -s UUID -o value "$SWAP_PARTITION")"
printf 'resume=UUID=%s\n' "$RESUME_UUID"
```

If using a swap file, `resume=` should identify the filesystem or mapped block device containing the swap file.

Get the UUID of the filesystem containing the swap file:

```sh
RESUME_UUID="$(findmnt -no UUID -T "$SWAPFILE")"
printf 'resume=UUID=%s\n' "$RESUME_UUID"
```

If that prints an empty UUID, inspect the mount source and use a stable persistent device name manually:

```sh
findmnt -no SOURCE,FSTYPE,UUID -T "$SWAPFILE"
lsblk -f
```

Get the swap-file offset.

For non-Btrfs filesystems:

```sh
SWAP_OFFSET="$(sudo filefrag -v "$SWAPFILE" | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')"
printf 'resume_offset=%s\n' "$SWAP_OFFSET"
```

For Btrfs:

```sh
SWAP_OFFSET="$(sudo btrfs inspect-internal map-swapfile -r "$SWAPFILE")"
printf 'resume_offset=%s\n' "$SWAP_OFFSET"
```

Print the final swap-file kernel parameters:

```sh
printf 'resume=UUID=%s resume_offset=%s\n' "$RESUME_UUID" "$SWAP_OFFSET"
```

Keep the output. It must be added to the boot loader kernel command line.

## Configure the Initramfs

Check which mkinitcpio hooks are active:

```sh
grep '^HOOKS=' /etc/mkinitcpio.conf
```

If the `HOOKS` line contains `systemd`, no resume hook is required.

If the system uses a busybox-based initramfs with `base` and `udev`, add the `resume` hook after `udev`. The current Arch example places it after `filesystems` and before `fsck`:

```sh
sudoedit /etc/mkinitcpio.conf
```

Example busybox hook order:

```sh
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems resume fsck)
```

If root is encrypted, on LVM, or on another stacked device, place `resume` after the hook that unlocks or activates the mapped device.

Regenerate all initramfs images:

```sh
sudo mkinitcpio -P
```

## Configure the Boot Loader

Add the exact values from the `printf 'resume=UUID=...'` command to the kernel command line. If using a swap partition, omit `resume_offset=`.

### systemd-boot

List boot entries:

```sh
sudo find /boot/loader/entries -maxdepth 1 -type f -name '*.conf' -print
```

Edit the Arch entry:

```sh
sudoedit /boot/loader/entries/arch.conf
```

Append the resume parameters to the `options` line:

```sh
options root=UUID=<root-uuid> rw resume=UUID=<resume-uuid> resume_offset=<swap-offset>
```

For a swap partition, use only:

```sh
options root=UUID=<root-uuid> rw resume=UUID=<resume-uuid>
```

If there are multiple Arch entries, update each entry that should resume from hibernation.

### GRUB

Back up the GRUB defaults file:

```sh
sudo cp /etc/default/grub /etc/default/grub.bak
```

Edit the kernel command line:

```sh
sudoedit /etc/default/grub
```

Add the resume parameters inside `GRUB_CMDLINE_LINUX_DEFAULT` or `GRUB_CMDLINE_LINUX`:

```sh
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash resume=UUID=<resume-uuid> resume_offset=<swap-offset>"
```

For a swap partition, omit `resume_offset=`:

```sh
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash resume=UUID=<resume-uuid>"
```

Regenerate the GRUB config:

```sh
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Unified Kernel Image or kernel-install

If the system uses `/etc/kernel/cmdline`, edit it and append the resume parameters:

```sh
sudoedit /etc/kernel/cmdline
```

Then rebuild the kernel images using the command used by the system. Common Arch commands are:

```sh
sudo mkinitcpio -P
sudo kernel-install add "$(uname -r)" "/usr/lib/modules/$(uname -r)/vmlinuz"
```

Use the system's existing UKI build command if it already has one.

## Reboot and Verify Parameters

Reboot after updating the boot loader:

```sh
sudo reboot
```

After booting again, verify that the kernel received the parameters:

```sh
cat /proc/cmdline
```

Verify the active resume settings:

```sh
cat /sys/power/resume
cat /sys/power/resume_offset
swapon --show --output=NAME,TYPE,SIZE,USED,PRIO
```

For a swap file, the resume offset should match the `SWAP_OFFSET` value. For a swap partition, `resume_offset` should be unset or `0`.

## Test Hibernation

Close important work before testing. Then run:

```sh
sudo systemctl hibernate
```

The machine should write memory to disk swap and power off. Power it back on normally. It should resume the previous session instead of doing a clean boot.

Check hibernation logs after resume:

```sh
journalctl -b -u systemd-hibernate-resume.service --no-pager
journalctl -b -1 -u systemd-hibernate.service --no-pager
journalctl -b -k | grep -iE 'hibernat|resume|PM:'
```

## Optional: Suspend Then Hibernate

`suspend-then-hibernate` first suspends to RAM, then wakes and hibernates after a delay.

Create a systemd sleep override:

```sh
sudo mkdir -p /etc/systemd/sleep.conf.d
sudo tee /etc/systemd/sleep.conf.d/suspend-then-hibernate.conf >/dev/null <<'EOF'
[Sleep]
AllowSuspendThenHibernate=yes
HibernateDelaySec=2h
EOF
```

Test it:

```sh
systemctl suspend-then-hibernate
```

## Troubleshooting

If `systemctl hibernate` says hibernation is not supported, check kernel support and logind decisions:

```sh
cat /sys/power/state
cat /sys/power/disk
journalctl -b -u systemd-logind --no-pager | grep -i hibernat
```

If the system powers off but does not resume, re-check the kernel parameters:

```sh
cat /proc/cmdline
swapon --show --output=NAME,TYPE,SIZE,USED,PRIO
blkid -s UUID -o value /dev/nvme0n1p2
```

For a swap file, also check the backing filesystem and offset:

```sh
findmnt -no SOURCE,FSTYPE,UUID -T "$SWAPFILE"
printf 'resume=UUID=%s resume_offset=%s\n' "$RESUME_UUID" "$SWAP_OFFSET"
```

If using a swap file and the offset is wrong, recalculate it and update the boot loader:

```sh
findmnt -no FSTYPE -T "$SWAPFILE"
sudo filefrag -v "$SWAPFILE" | awk '$1=="0:" {print substr($4, 1, length($4)-2)}'
sudo btrfs inspect-internal map-swapfile -r "$SWAPFILE"
```

Use only the offset command that matches the filesystem.

If the system says there is not enough swap, check free swap space:

```sh
swapon --show --output=NAME,TYPE,SIZE,USED,PRIO
free -h
journalctl -b -k | grep -iE 'not enough|hibernat|swap'
```

If a stale manual resume target blocks hibernation, clear it until the next reboot:

```sh
echo 0:0 | sudo tee /sys/power/resume
echo 0 | sudo tee /sys/power/resume_offset
```

If hibernation immediately wakes the machine again, inspect wake-related logs:

```sh
journalctl -b -u systemd-hibernate.service --no-pager
journalctl -b -k | grep -iE 'wakeup|hibernat|PM:'
```

## Remove the Setup

If using an existing swap partition, do not remove the partition. Remove only the hibernation kernel parameter from the boot loader.

If using a fallback swap file, disable and remove it:

```sh
sudo swapoff "$SWAPFILE"
sudo rm -f "$SWAPFILE"
```

Remove the swap file line from `/etc/fstab`:

```sh
sudoedit /etc/fstab
```

Remove `resume=...` and, if present, `resume_offset=...` from the boot loader kernel command line. Regenerate boot loader files if needed, and rebuild initramfs if the `resume` hook was added:

```sh
sudo mkinitcpio -P
```

Reboot:

```sh
sudo reboot
```

## References

- ArchWiki: https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate
- ArchWiki: https://wiki.archlinux.org/title/Swap
- ArchWiki: https://wiki.archlinux.org/title/Btrfs#Swap_file
