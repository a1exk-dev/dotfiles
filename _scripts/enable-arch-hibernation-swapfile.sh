#!/usr/bin/env bash
set -euo pipefail

SWAPFILE="${SWAPFILE:-/swapfile}"
SWAP_SIZE="${SWAP_SIZE:-}"
BOOT_ENTRY="${BOOT_ENTRY:-/boot/loader/entries/2026-03-09_23-22-57_linux.conf}"
MKINITCPIO_CONF="${MKINITCPIO_CONF:-/etc/mkinitcpio.conf}"
FSTAB="${FSTAB:-/etc/fstab}"

log() {
  printf '[hibernate-setup] %s\n' "$*"
}

die() {
  printf '[hibernate-setup] ERROR: %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [ "${EUID}" -ne 0 ]; then
    die "run as root, for example: sudo $0"
  fi
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

backup_file() {
  local file="$1"
  local backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"

  cp -a -- "$file" "$backup"
  log "backup: $backup"
}

default_swap_size() {
  local mem_kib size_gib

  mem_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  [ -n "$mem_kib" ] || die "could not read MemTotal from /proc/meminfo"

  # Round RAM up to GiB and add 8 GiB of margin.
  size_gib=$(( (mem_kib + 1048576 - 1) / 1048576 + 8 ))
  printf '%sG\n' "$size_gib"
}

find_largest_swap_partition() {
  lsblk -b -rpno NAME,TYPE,FSTYPE,SIZE | awk '
    $2 == "part" && $3 == "swap" {
      if ($4 > max) {
        max = $4
        name = $1
      }
    }
    END {
      if (name != "") print name
    }
  '
}

swap_partition_is_active() {
  local partition="$1"

  swapon --noheadings --show=NAME | awk -v partition="$partition" '$1 == partition { found = 1 } END { exit !found }'
}

swapfile_is_active() {
  swapon --noheadings --show=NAME | awk -v file="$SWAPFILE" '$1 == file { found = 1 } END { exit !found }'
}

swapfile_has_swap_signature() {
  blkid -p -o value -s TYPE -- "$SWAPFILE" 2>/dev/null | awk '$1 == "swap" { found = 1 } END { exit !found }'
}

ensure_swap_partition() {
  local partition="$1"
  local size_bytes size_human uuid

  uuid="$(blkid -s UUID -o value -- "$partition")"
  [ -n "$uuid" ] || die "swap partition has no UUID: $partition"

  size_bytes="$(lsblk -b -dnro SIZE -- "$partition")"
  size_human="$(numfmt --to=iec --suffix=B "$size_bytes")"

  log "using existing swap partition: $partition ($size_human, UUID=$uuid)"

  if swap_partition_is_active "$partition"; then
    log "swap partition is already active"
  else
    swapon "$partition"
    log "swap partition activated"
  fi

  HIBERNATE_TARGET_TYPE="partition"
  HIBERNATE_TARGET="$partition"
}

ensure_arch_system() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "${ID:-}" = "arch" ] || die "this script is intended for Arch Linux, found ID=${ID:-unknown}"
  fi

  [ -r /sys/power/state ] || die "/sys/power/state is not readable"
  awk '{ for (i = 1; i <= NF; i++) if ($i == "disk") found = 1 } END { exit !found }' /sys/power/state \
    || die "kernel does not advertise hibernation support in /sys/power/state"

  [ -f "$BOOT_ENTRY" ] || die "systemd-boot entry not found: $BOOT_ENTRY"
  [ -f "$MKINITCPIO_CONF" ] || die "mkinitcpio config not found: $MKINITCPIO_CONF"
  [ -f "$FSTAB" ] || die "fstab not found: $FSTAB"
}

ensure_root_filesystem() {
  local source fstype uuid

  source="$(findmnt -no SOURCE /)"
  fstype="$(findmnt -no FSTYPE /)"
  uuid="$(findmnt -no UUID /)"

  log "root filesystem: $source ($fstype, UUID=$uuid)"

  [ "$fstype" = "ext4" ] || die "this local script expects ext4 root, found $fstype"
  [ -n "$uuid" ] || die "root filesystem UUID is empty"
}

ensure_swapfile() {
  local parent size_bytes available_bytes count_mib

  parent="$(dirname -- "$SWAPFILE")"
  [ -d "$parent" ] || die "swapfile parent directory does not exist: $parent"

  if [ -z "$SWAP_SIZE" ]; then
    SWAP_SIZE="$(default_swap_size)"
  fi

  log "swap file: $SWAPFILE"
  log "swap size: $SWAP_SIZE"

  if [ -e "$SWAPFILE" ]; then
    swapfile_has_swap_signature || die "$SWAPFILE exists but does not look like a swap file"
    log "existing swap file detected"
  else
    size_bytes="$(numfmt --from=iec "$SWAP_SIZE")"
    available_bytes="$(df --output=avail -B1 "$parent" | awk 'NR == 2 {print $1}')"
    [ "$available_bytes" -gt "$size_bytes" ] || die "not enough free space under $parent for $SWAP_SIZE"

    log "creating swap file"
    if ! fallocate -l "$SWAP_SIZE" "$SWAPFILE"; then
      log "fallocate failed, falling back to dd"
      count_mib=$(( (size_bytes + 1048576 - 1) / 1048576 ))
      dd if=/dev/zero of="$SWAPFILE" bs=1M count="$count_mib" status=progress
    fi

    chmod 600 "$SWAPFILE"
    mkswap -U clear "$SWAPFILE"
  fi

  chmod 600 "$SWAPFILE"

  if swapfile_is_active; then
    log "swap file is already active"
  else
    swapon "$SWAPFILE"
    log "swap file activated"
  fi

  HIBERNATE_TARGET_TYPE="swapfile"
  HIBERNATE_TARGET="$SWAPFILE"
}

ensure_hibernate_target() {
  local partition

  partition="$(find_largest_swap_partition)"
  if [ -n "$partition" ]; then
    ensure_swap_partition "$partition"
    return
  fi

  log "no swap partition found; falling back to a swap file sized RAM plus 8 GiB"
  ensure_swapfile
  ensure_fstab
}

ensure_fstab() {
  if awk -v file="$SWAPFILE" '$1 == file && $3 == "swap" { found = 1 } END { exit !found }' "$FSTAB"; then
    log "fstab already contains $SWAPFILE"
    return
  fi

  backup_file "$FSTAB"
  printf '%s none swap defaults 0 0\n' "$SWAPFILE" >>"$FSTAB"
  log "added swap file to $FSTAB"

  findmnt --verify --verbose >/dev/null
  log "fstab verification passed"
}

calculate_resume_values() {
  case "${HIBERNATE_TARGET_TYPE:-}" in
    partition)
      RESUME_UUID="$(blkid -s UUID -o value -- "$HIBERNATE_TARGET")"
      [ -n "$RESUME_UUID" ] || die "could not determine UUID for $HIBERNATE_TARGET"
      RESUME_OFFSET=""
      log "resume=UUID=$RESUME_UUID"
      ;;
    swapfile)
      RESUME_UUID="$(findmnt -no UUID -T "$SWAPFILE")"
      [ -n "$RESUME_UUID" ] || die "could not determine filesystem UUID for $SWAPFILE"

      RESUME_OFFSET="$(filefrag -v "$SWAPFILE" | awk '$1 == "0:" { sub(/\.\.$/, "", $4); print $4; exit }')"
      [ -n "$RESUME_OFFSET" ] || die "could not determine resume_offset for $SWAPFILE"
      case "$RESUME_OFFSET" in
        *[!0-9]*) die "resume_offset is not numeric: $RESUME_OFFSET" ;;
      esac

      log "resume=UUID=$RESUME_UUID"
      log "resume_offset=$RESUME_OFFSET"
      ;;
    *)
      die "hibernate target was not selected"
      ;;
  esac
}

ensure_mkinitcpio_resume_hook() {
  local hooks_line hooks_content hook inserted new_line tmp
  local new_hooks=()

  hooks_line="$(awk '/^HOOKS=\(/ { print; exit }' "$MKINITCPIO_CONF")"
  [ -n "$hooks_line" ] || die "could not find active HOOKS line in $MKINITCPIO_CONF"

  if printf '%s\n' "$hooks_line" | awk '/(^|[ (])systemd([ )]|$)/ { found = 1 } END { exit !found }'; then
    log "systemd initramfs hook detected; resume hook is not needed"
    return
  fi

  if printf '%s\n' "$hooks_line" | awk '/(^|[ (])resume([ )]|$)/ { found = 1 } END { exit !found }'; then
    log "mkinitcpio resume hook already present"
    return
  fi

  hooks_content="${hooks_line#HOOKS=(}"
  hooks_content="${hooks_content%)}"
  inserted=0

  for hook in $hooks_content; do
    if [ "$hook" = "fsck" ] && [ "$inserted" -eq 0 ]; then
      new_hooks+=(resume)
      inserted=1
    fi
    new_hooks+=("$hook")
  done

  if [ "$inserted" -eq 0 ]; then
    new_hooks+=(resume)
  fi

  new_line="HOOKS=(${new_hooks[*]})"
  tmp="$(mktemp)"

  backup_file "$MKINITCPIO_CONF"
  awk -v old="$hooks_line" -v new="$new_line" '
    !done && $0 == old { print new; done = 1; next }
    { print }
  ' "$MKINITCPIO_CONF" >"$tmp"
  install -m 644 -o root -g root "$tmp" "$MKINITCPIO_CONF"
  rm -f "$tmp"

  log "updated mkinitcpio hooks: $new_line"
}

update_systemd_boot_entry() {
  local tmp resume_arg offset_arg updated

  resume_arg="resume=UUID=$RESUME_UUID"
  offset_arg=""
  if [ -n "$RESUME_OFFSET" ]; then
    offset_arg="resume_offset=$RESUME_OFFSET"
  fi
  tmp="$(mktemp)"
  updated=0

  backup_file "$BOOT_ENTRY"

  while IFS= read -r line; do
    if [ "${line#options }" != "$line" ]; then
      read -r -a parts <<<"$line"
      new_parts=()

      for part in "${parts[@]:1}"; do
        case "$part" in
          resume=*|resume_offset=*) ;;
          *) new_parts+=("$part") ;;
        esac
      done

      if [ -n "$offset_arg" ]; then
        printf 'options %s %s %s\n' "${new_parts[*]}" "$resume_arg" "$offset_arg" >>"$tmp"
      else
        printf 'options %s %s\n' "${new_parts[*]}" "$resume_arg" >>"$tmp"
      fi
      updated=1
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$BOOT_ENTRY"

  [ "$updated" -eq 1 ] || die "no options line found in $BOOT_ENTRY"

  install -m 644 -o root -g root "$tmp" "$BOOT_ENTRY"
  rm -f "$tmp"

  log "updated boot entry: $BOOT_ENTRY"
}

rebuild_initramfs() {
  mkinitcpio -P
  log "rebuilt initramfs images"
}

print_summary() {
  printf '\n'
  log "configuration complete"
  log "hibernate target: $HIBERNATE_TARGET_TYPE $HIBERNATE_TARGET"
  if [ -n "$RESUME_OFFSET" ]; then
    log "kernel parameters: resume=UUID=$RESUME_UUID resume_offset=$RESUME_OFFSET"
  else
    log "kernel parameters: resume=UUID=$RESUME_UUID"
  fi
  log "reboot next: sudo reboot"
  log "after reboot, test manually: sudo systemctl hibernate"
}

main() {
  need_root
  need_command awk
  need_command blkid
  need_command cp
  need_command date
  need_command df
  need_command fallocate
  need_command filefrag
  need_command findmnt
  need_command install
  need_command lsblk
  need_command mkinitcpio
  need_command mkswap
  need_command numfmt
  need_command swapon

  ensure_arch_system
  ensure_root_filesystem
  ensure_hibernate_target
  calculate_resume_values
  ensure_mkinitcpio_resume_hook
  update_systemd_boot_entry
  rebuild_initramfs
  print_summary
}

main "$@"
