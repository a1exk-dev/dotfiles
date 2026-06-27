#!/usr/bin/env bash
set -euo pipefail

DROPIN_DIR="${DROPIN_DIR:-/etc/systemd/logind.conf.d}"
DROPIN_FILE="${DROPIN_FILE:-$DROPIN_DIR/hibernate-on-lid.conf}"
HANDLE_LID_SWITCH="${HANDLE_LID_SWITCH:-hibernate}"
HANDLE_LID_SWITCH_EXTERNAL_POWER="${HANDLE_LID_SWITCH_EXTERNAL_POWER:-hibernate}"
HANDLE_LID_SWITCH_DOCKED="${HANDLE_LID_SWITCH_DOCKED:-ignore}"
RESTART_LOGIND="${RESTART_LOGIND:-0}"

tmp=""

log() {
  printf '[lid-hibernate] %s\n' "$*"
}

die() {
  printf '[lid-hibernate] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$tmp" ]; then
    rm -f -- "$tmp"
  fi
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

validate_action() {
  local name="$1"
  local value="$2"

  case "$value" in
    ignore | poweroff | reboot | halt | kexec | suspend | hibernate | hybrid-sleep | suspend-then-hibernate | lock)
      ;;
    *)
      die "$name has unsupported value: $value"
      ;;
  esac
}

write_dropin() {
  mkdir -p -- "$DROPIN_DIR"
  tmp="$(mktemp)"

  {
    printf '# Managed by dotfiles/_scripts/configure-lid-hibernate.sh\n'
    printf '[Login]\n'
    printf 'HandleLidSwitch=%s\n' "$HANDLE_LID_SWITCH"
    printf 'HandleLidSwitchExternalPower=%s\n' "$HANDLE_LID_SWITCH_EXTERNAL_POWER"
    printf 'HandleLidSwitchDocked=%s\n' "$HANDLE_LID_SWITCH_DOCKED"
  } >"$tmp"

  if [ -f "$DROPIN_FILE" ] && cmp -s -- "$tmp" "$DROPIN_FILE"; then
    log "lid policy already configured: $DROPIN_FILE"
    return
  fi

  if [ -f "$DROPIN_FILE" ]; then
    backup_file "$DROPIN_FILE"
  fi

  install -m 644 -o root -g root "$tmp" "$DROPIN_FILE"
  log "wrote lid policy: $DROPIN_FILE"
}

verify_config() {
  systemd-analyze cat-config systemd/logind.conf >/dev/null
  log "logind configuration parses successfully"
}

apply_now_if_requested() {
  case "$RESTART_LOGIND" in
    1 | yes | true)
      systemctl restart systemd-logind.service
      log "restarted systemd-logind.service"
      ;;
    *)
      log "policy will apply after reboot or after restarting systemd-logind.service"
      ;;
  esac
}

main() {
  trap cleanup EXIT

  need_root
  need_command cmp
  need_command cp
  need_command date
  need_command install
  need_command mktemp
  need_command systemctl
  need_command systemd-analyze

  validate_action HandleLidSwitch "$HANDLE_LID_SWITCH"
  validate_action HandleLidSwitchExternalPower "$HANDLE_LID_SWITCH_EXTERNAL_POWER"
  validate_action HandleLidSwitchDocked "$HANDLE_LID_SWITCH_DOCKED"

  write_dropin
  verify_config
  apply_now_if_requested
}

main "$@"
