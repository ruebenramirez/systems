# shellcheck shell=bash
#
# Report every login-critical path that resolves into a pool mountpoint.
#
# The walk never lets the kernel resolve a path *into* a pool. `readlink` is
# only ever called on a prefix whose own ancestors were already proven to sit
# outside the pool roots, so a suspended pool cannot hang this check the way it
# hangs the login shell. `realpath`, `stat`, `test -e` and `cd` would all follow
# the intermediate symlinks into the dead pool and block in uninterruptible
# sleep, which is precisely the failure being looked for.
#
# Env:
#   ANCHOR_HOME   the user's home directory
#   ANCHOR_LINKS  space-separated paths, relative to ANCHOR_HOME, that the login
#                 shell reads before it can hand over a prompt
#   ANCHOR_POOL_ROOTS  space-separated mountpoints that must never appear in one

set -uo pipefail

violations=0

# scan PATH DEPTH -- print one line per symlink that lands inside a pool root.
# PATH is walked one component at a time; DEPTH bounds symlink cycles.
scan() {
  local path="$1" depth="$2"

  if [ "$depth" -gt 24 ]; then
    printf '%s: too many symlink hops to resolve\n' "$path"
    violations=$((violations + 1))
    return
  fi

  local -a comps=()
  IFS='/' read -r -a comps <<<"${path#/}"

  local n=${#comps[@]}
  local parent prefix comp target root
  case "$path" in
    /*) prefix="/" ;;
    *) prefix="" ;;
  esac

  local i=0
  while [ "$i" -lt "$n" ]; do
    comp="${comps[$i]}"
    i=$((i + 1))
    parent="$prefix"
    case "$comp" in
      "" | ".") continue ;;
      "..")
        # dirname of "/" is "/", so this cannot climb out of the root.
        prefix="$(dirname -- "$prefix")"
        continue
        ;;
    esac
    if [ "$prefix" = "/" ]; then
      prefix="/$comp"
    elif [ -z "$prefix" ] || [ "$prefix" = "." ]; then
      prefix="$comp"
    else
      prefix="$prefix/$comp"
    fi

    # Compare before touching. A lexical match needs no resolution, and
    # resolving a path that lies inside the pool is the thing that blocks.
    for root in $ANCHOR_POOL_ROOTS; do
      case "${prefix%/}" in
        "$root" | "$root"/*)
          printf '%s is inside %s\n' "$prefix" "$root"
          violations=$((violations + 1))
          return
          ;;
      esac
    done

    if ! target="$(readlink -- "$prefix" 2>/dev/null)"; then
      continue
    fi

    case "$target" in
      /*) ;;
      *)
        if [ "$parent" = "/" ]; then
          target="/$target"
        else
          target="$parent/$target"
        fi
        ;;
    esac

    for root in $ANCHOR_POOL_ROOTS; do
      case "${target%/}" in
        "$root" | "$root"/*)
          printf '%s -> %s (inside %s)\n' "$prefix" "$target" "$root"
          violations=$((violations + 1))
          # Stop here on purpose: descending would resolve inside the pool.
          return
          ;;
      esac
    done

    # Rejoin whatever was left of the original path onto the link target and
    # walk that instead, so an indirection anywhere along the path is followed.
    local rest="" j=$i
    while [ "$j" -lt "$n" ]; do
      if [ -n "${comps[$j]}" ]; then
        rest="$rest/${comps[$j]}"
      fi
      j=$((j + 1))
    done
    scan "$target$rest" $((depth + 1))
    return
  done
}

report="$(mktemp)"
trap 'rm -f "$report"' EXIT

for rel in $ANCHOR_LINKS; do
  scan "$ANCHOR_HOME/$rel" 0
done >"$report"

if [ "$violations" -eq 0 ]; then
  if [ -n "${ANCHOR_STATE_FILE:-}" ] && [ -f "$ANCHOR_STATE_FILE" ]; then
    rm -f -- "$ANCHOR_STATE_FILE"
    printf 'login shell is back off %s; alert state cleared\n' "$ANCHOR_POOL_ROOTS"
  fi
  printf 'no login-critical path resolves into %s\n' "$ANCHOR_POOL_ROOTS"
  exit 0
fi

{
  printf '%s login-critical path(s) resolve into a pool mountpoint:\n\n' "$violations"
  cat "$report"
  cat <<'DETAIL'

The login shell reads these before it can hand over a prompt, so when that pool
suspends every SSH session hangs after the last-login banner -- including the
session someone needs in order to run 'zpool clear'.

Move the checkout these symlinks point at onto the root pool, then re-run:
  systemctl start login-shell-anchor-migrate.service
DETAIL
} >&2

# Alert once per outage, not once per poll: a oneshot failing every 10 minutes
# would turn rueb.failureMail into a mail storm over a problem that takes a
# person to fix. Same contract as zpool-rescue.
if [ -n "${ANCHOR_ALERT_ONCE:-}" ] && [ -n "${ANCHOR_STATE_FILE:-}" ]; then
  if [ -f "$ANCHOR_STATE_FILE" ]; then
    printf 'already reported since %s; not paging again\n' "$(cat "$ANCHOR_STATE_FILE")" >&2
    exit 0
  fi
  date -Is >"$ANCHOR_STATE_FILE"
fi

exit 1
