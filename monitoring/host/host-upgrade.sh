#!/bin/bash
# Daily unattended package upgrade.
# Applies upgrades with conffile-safe defaults, never reboots, and logs everything.
# Reboot decisions stay with the operator: the log records REBOOT REQUIRED.
set -uo pipefail

LOG=/var/log/host-upgrade.log
LOCK=/run/host-upgrade.lock
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY="yes"

exec 9>"$LOCK" || exit 1
flock -n 9 || { echo "already running"; exit 0; }

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l          # list services needing restart, don't bounce them

run() {
  [ -n "$DRY" ] && { echo "  DRY: $*"; return 0; }
  "$@"
}

{
  echo "=== $(date -Is) upgrade start on $(hostname) ==="

  echo "  refreshing package lists"
  run apt-get -qq -o DPkg::Lock::Timeout=900 update || echo "  WARNING: apt update failed"

  pending=$(apt-get -s -o Dpkg::Options::=--force-confold dist-upgrade 2>/dev/null | grep -c '^Inst')
  echo "  packages pending: $pending"

  if [ "$pending" -gt 0 ]; then
    echo "  applying upgrades"
    run apt-get -y -q \
        -o DPkg::Lock::Timeout=900 \
        -o Dpkg::Options::=--force-confold \
        -o Dpkg::Options::=--force-confdef \
        dist-upgrade || echo "  WARNING: dist-upgrade returned non-zero"
    run apt-get -y -q -o DPkg::Lock::Timeout=900 autoremove --purge
    run apt-get -y -q -o DPkg::Lock::Timeout=900 autoclean
  fi

  if [ -f /var/run/reboot-required ]; then
    echo "  REBOOT REQUIRED: $(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null)"
  else
    echo "  no reboot required"
  fi

  # keep the log from growing forever
  if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG")" -gt 2000000 ]; then
    mv "$LOG" "$LOG.1"
  fi

  echo "=== $(date -Is) upgrade done ==="
} >> "$LOG" 2>&1
