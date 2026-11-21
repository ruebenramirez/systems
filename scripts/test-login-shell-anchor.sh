#!/usr/bin/env bash
# Fixture run for the login-shell-anchor scripts: builds the tank-backed layout
# the 2026-11-19 outage produced, checks it, migrates it, checks it again.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(mktemp -d)"
trap 'chmod -R u+rwX "$root" 2>/dev/null; rm -rf "$root"' EXIT

fail=0
expect() { # expect <label> <want: 0|1> <got: 0|1>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s (want rc %s, got rc %s)\n' "$1" "$2" "$3"
    fail=1
  fi
}

# --- the layout as it was during the outage -----------------------------------
mkdir -p "$root/zroot/home/.config"
mkdir -p "$root/tank/Shares/rueb/code/systems/dotfiles/.config/fish/conf.d"
mkdir -p "$root/tank/Shares/rueb/code/systems/dotfiles/bin"
mkdir -p "$root/tank/Shares/rueb/code/ansible"
: > "$root/tank/Shares/rueb/code/systems/dotfiles/.config/fish/config.fish"
: > "$root/tank/Shares/rueb/code/systems/dotfiles/.config/fish/conf.d/sops.fish"
: > "$root/tank/Shares/rueb/code/systems/dotfiles/bin/nup-fleet"
ln -s "$root/tank/Shares/rueb/code/" "$root/zroot/home/code"
ln -s "$root/zroot/home/code/systems/dotfiles/.config/fish/" "$root/zroot/home/.config/fish"
ln -s "$root/zroot/home/code/systems/dotfiles/bin/" "$root/zroot/home/bin"

export ANCHOR_HOME="$root/zroot/home"
export ANCHOR_DIR="$root/zroot/home/code"
export ANCHOR_POOL_DIR="$root/tank/Shares/rueb/code"
export ANCHOR_ENTRY=systems
export ANCHOR_LINKS=".config/fish bin"
export ANCHOR_POOL_ROOTS="$root/tank"

echo "== 1. the broken layout is reported"
out="$(bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh" 2>&1)"; rc=$?
expect "check flags the tank-backed layout" 1 "$rc"
printf '%s\n' "$out" | sed 's/^/     | /'

echo "== 2. a pool that cannot be traversed does not stop the check"
# readlink inside the pool would fail here; the walk must never get that far.
chmod 000 "$root/tank/Shares/rueb/code/systems"
out2="$(bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh" 2>&1)"; rc2=$?
chmod u+rwx "$root/tank/Shares/rueb/code/systems"
expect "check still reports with the pool unreadable" 1 "$rc2"
printf '%s\n' "$out2" | sed 's/^/     | /'

echo "== 3. migrate flips it"
cat > "$root/check-wrapper" <<WRAP
#!/bin/sh
exec bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh" "\$@"
WRAP
chmod +x "$root/check-wrapper"
export ANCHOR_CHECK="$root/check-wrapper"
bash "$here/../nix/machines/_common/services/login-shell-anchor/migrate.sh"; rc3=$?
expect "migrate succeeds" 0 "$rc3"

echo "== 4. the migrated layout passes"
bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh"; rc4=$?
expect "check passes after the move" 0 "$rc4"

echo "== 5. the layout still resolves, and the checkout is real"
[ -f "$root/zroot/home/.config/fish/config.fish" ] \
  && [ -f "$root/zroot/home/bin/nup-fleet" ] \
  && [ -d "$root/zroot/home/code/systems/dotfiles" ] \
  && [ -L "$root/zroot/home/code/ansible" ] \
  && [ ! -L "$root/zroot/home/code/systems" ]
expect "dotfiles, bin and siblings all resolve off the pool" 0 "$?"

echo "== 6. migrate is a no-op the second time"
bash "$here/../nix/machines/_common/services/login-shell-anchor/migrate.sh"; rc6=$?
expect "second migrate is a no-op" 0 "$rc6"

echo "== 7. a symlink added later is caught again"
ln -s "$root/tank/Shares/rueb/code/systems/dotfiles/.config/fish" "$root/zroot/home/.config/oops"
ANCHOR_LINKS=".config/fish bin .config/oops" \
  bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh"; rc7=$?
expect "a new tank-backed path is caught" 1 "$rc7"

echo "== 8. a relative symlink into the pool is caught"
ln -s ../../tank/Shares/rueb/code/systems "$root/zroot/home/rel"
ANCHOR_LINKS="rel" bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh"; rc8=$?
expect "relative symlink chain is followed" 1 "$rc8"

echo "== 9. a symlink cycle terminates"
ln -s "$root/zroot/home/cyc" "$root/zroot/home/cyc2"
ln -s "$root/zroot/home/cyc2" "$root/zroot/home/cyc"
ANCHOR_LINKS="cyc" bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh"; rc9=$?
expect "cycle terminates and fails closed" 1 "$rc9"

echo "== 10. the alert fires once per outage, then clears"
ln -s "$root/tank/Shares/rueb/code/systems" "$root/zroot/home/bad"
export ANCHOR_STATE_FILE="$root/state"
ANCHOR_LINKS="bad" ANCHOR_ALERT_ONCE=1 \
  bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh" 2>/dev/null; rc10a=$?
ANCHOR_LINKS="bad" ANCHOR_ALERT_ONCE=1 \
  bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh" 2>/dev/null; rc10b=$?
expect "first failure pages" 1 "$rc10a"
expect "second failure stays quiet until recovery" 0 "$rc10b"
rm -f "$root/zroot/home/bad"
ANCHOR_LINKS="bin" ANCHOR_ALERT_ONCE=1 \
  bash "$here/../nix/machines/_common/services/login-shell-anchor/check.sh" >/dev/null; rc10c=$?
expect "recovery succeeds" 0 "$rc10c"
[ ! -f "$ANCHOR_STATE_FILE" ]
expect "state file cleared on recovery" 0 "$?"
unset ANCHOR_STATE_FILE ANCHOR_ALERT_ONCE

echo
[ "$fail" = 0 ] && echo "all fixture checks passed" || echo "fixture checks FAILED"
exit "$fail"
