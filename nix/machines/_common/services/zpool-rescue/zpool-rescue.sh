#!/usr/bin/env bash
# Resume a ZFS pool that OpenZFS suspended after transient device I/O failure.
#
# Why a poller and not a ZEDLET: OpenZFS has no event class for a pool suspend
# (see the class list in zpool-events(8)), so ZED never learns it happened. The
# Nov 2026 tank outage sat unrecovered for 19 hours for exactly this reason --
# the USB hub re-enumerated within 3 seconds and nothing acted.
#
# This script must never reboot or power-cycle the host. Tasks blocked on a
# suspended pool are in uninterruptible sleep and survive SIGKILL, so shutdown
# stalls forever waiting on the unmounts; that is what forced a physical power
# button press last time.

set -uo pipefail

zpool_cmd=${ZPOOL:-zpool}
pools=${RESCUE_POOLS:-tank}
probe_dir=${RESCUE_PROBE_DIR:-/tank}
usb_devices=${RESCUE_USB_RESET_DEVICES:-}
confirm_sleep=${RESCUE_CONFIRM_SLEEP:-5}
clear_wait=${RESCUE_CLEAR_WAIT:-25}
state_dir=${RESCUE_STATE_DIR:-/run/zpool-rescue}

mkdir -p "$state_dir" /run/lock
exec 9>/run/lock/zpool-rescue.lock
flock -n 9 || { echo "zpool-rescue: previous run still active"; exit 0; }

log() { printf '%s zpool-rescue: %s\n' "$(date -Is)" "$*"; }

# timeout: zpool list against a suspended pool has a history of blocking
# (openzfs/zfs#3461); a wedged poll would hold the flock until the unit timeout.
health() { timeout 10 "$zpool_cmd" list -H -o name,health 2>/dev/null | awk -v p="$1" '$1==p{print $2}'; }

# Device paths the pool was actually built on. -P keeps them as full /dev paths.
vdev_paths() { "$zpool_cmd" status -P "$1" 2>/dev/null | grep -oE '/dev/[^[:space:]]+' | sort -u; }

missing_paths() {
  local p out=""
  for p in $(vdev_paths "$1"); do [ -e "$p" ] || out="$out$p"$'\n'; done
  printf '%s' "$out"
}

# A pool can report ONLINE while still wedged, so prove I/O actually works.
# systemd-run takes no positional unit name: the unit name goes in -u, and
# everything after -- is the command. A touch stuck in D-state survives
# SIGKILL, so neither `timeout` nor the scope's TimeoutStopSec can reap it --
# the scope job stays "exiting" and systemd-run blocks on it. The backstop
# that actually fires is the unit's TimeoutStartSec killing the whole cgroup.
write_probe() {
  local f="$probe_dir/.zfs-rescue-probe.$$" out rc=0
  out=$(systemd-run --scope --quiet -u "zpool-rescue-probe-$$" \
    -p TimeoutStopSec=20s -- touch "$f" 2>&1) || rc=$?
  # A probe that could not run must be distinguishable from one that failed.
  [ -n "$out" ] && log "write probe (rc=$rc): $out"
  [ "$rc" -eq 0 ] && rm -f "$f"
  return "$rc"
}

# Last resort, opt-in only: deauthorize then reauthorize the hub so the kernel
# re-enumerates the whole tree. Only ever attempted while the pool is already
# suspended, i.e. there is no live I/O left to lose.
usb_reset() {
  local d
  [ -n "$usb_devices" ] || return 1
  for d in $usb_devices; do
    [ -w "/sys/bus/usb/devices/$d/authorized" ] || { log "usb: $d has no writable authorized knob"; continue; }
    log "usb: deauthorizing $d"
    echo 0 > "/sys/bus/usb/devices/$d/authorized" 2>/dev/null
    sleep 3
    echo 1 > "/sys/bus/usb/devices/$d/authorized" 2>/dev/null
  done
  sleep 8
}

resume_attempt() {
  local pool=$1 waited=0
  timeout 30 "$zpool_cmd" clear "$pool" 2>&1 | sed 's/^/  zpool clear: /'
  while [ "$waited" -lt "$clear_wait" ]; do
    [ "$(health "$pool")" = "ONLINE" ] && break
    sleep 2; waited=$((waited + 2))
  done
  if [ "$(health "$pool")" != "ONLINE" ]; then
    log "pool=$pool still $(health "$pool") after clear; trying zpool reopen"
    timeout 30 "$zpool_cmd" reopen "$pool" 2>&1 | sed 's/^/  zpool reopen: /'
    sleep 5
  fi
  [ "$(health "$pool")" = "ONLINE" ] || return 1
  write_probe || { log "pool=$pool ONLINE but write probe failed"; return 1; }
  return 0
}

rescue_pool() {
  local pool=$1 st missing
  st=$(health "$pool")
  case "$st" in
    # libzfs zpool_get_state_str() prints UPPERCASE; a lowercase match never
    # fires and the watchdog silently no-ops forever.
    SUSPENDED) ;;
    ONLINE) return 0 ;;
    *) log "pool=$pool health=$st -- not acting on this state"; return 0 ;;
  esac

  log "pool=$pool SUSPENDED; re-checking in ${confirm_sleep}s"
  sleep "$confirm_sleep"
  [ "$(health "$pool")" = "SUSPENDED" ] || { log "pool=$pool recovered on its own"; return 0; }

  if resume_attempt "$pool"; then
    log "pool=$pool RESUMED and writable"
    return 0
  fi

  missing=$(missing_paths "$pool")
  if [ -n "$missing" ]; then
    log "devices still missing:"; printf '%s' "$missing" | sed 's/^/  /'
    if [ -n "$usb_devices" ]; then
      usb_reset
      missing=$(missing_paths "$pool")
      [ -n "$missing" ] && { log "devices still absent after usb reset"; return 1; }
      resume_attempt "$pool" && { log "pool=$pool RESUMED after usb reset"; return 0; }
    fi
    return 1
  fi

  log "devices present but pool did not resume"
  return 1
}

# Alert state is per pool: one pool's recovery must not clear another pool's
# alerted flag.
new_alert=0
for p in $pools; do
  if rescue_pool "$p"; then
    rm -f "$state_dir/state-$p"
    continue
  fi
  sf="$state_dir/state-$p"
  # Fail loudly exactly once per outage: a oneshot failing every 30s would
  # turn rueb.failureMail into a mail storm.
  if [ "$(cat "$sf" 2>/dev/null)" != "alerted" ]; then
    echo alerted > "$sf"
    log "pool=$p UNRECOVERABLE -- manual intervention required (do not reboot; see header)"
    new_alert=1
  else
    log "pool=$p still unrecovered; alert already sent"
  fi
done

exit "$new_alert"
