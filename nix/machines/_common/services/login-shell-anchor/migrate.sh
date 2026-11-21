# shellcheck shell=bash
#
# Move the checkout the login shell's dotfiles come from off the data pool and
# onto the root pool, without changing a single path anyone types.
#
# The unit carries ConditionPathIsSymlink on ANCHOR_DIR, so this runs until the
# flip has happened and is a no-op afterwards -- no stamp file to go stale.
#
# Nothing is deleted. The pool keeps its copy of the checkout; it simply stops
# being the one the home directory points at.
#
# Env:
#   ANCHOR_HOME, ANCHOR_DIR, ANCHOR_POOL_DIR, ANCHOR_ENTRY
#   ANCHOR_CHECK  the check script to verify against, same env

set -euo pipefail

if [ ! -L "$ANCHOR_DIR" ]; then
  printf '%s is not a symlink; the login shell is already off the pool\n' "$ANCHOR_DIR"
  exit 0
fi

src="$ANCHOR_POOL_DIR/$ANCHOR_ENTRY"
if [ ! -d "$src/dotfiles" ]; then
  printf 'error: %s is missing or has no dotfiles/; refusing to move it\n' "$src" >&2
  exit 1
fi

new="$ANCHOR_DIR.new"
aside="$ANCHOR_DIR.pre-anchor"

rm -rf -- "$new"
mkdir -p -- "$new"

# Every sibling of the checkout stays reachable at exactly the path it has
# today, one symlink per entry into the share.
linked=0
while IFS= read -r entry; do
  name="${entry##*/}"
  if [ "$name" = "$ANCHOR_ENTRY" ]; then
    continue
  fi
  ln -s -- "$entry" "$new/$name"
  linked=$((linked + 1))
done < <(find "$ANCHOR_POOL_DIR" -mindepth 1 -maxdepth 1)

# The checkout itself is copied, not linked -- that is the entire point. -a keeps
# .git, .jj and any uncommitted work exactly as it was.
cp -a -- "$src" "$new/$ANCHOR_ENTRY"
sync

# Two renames within one dataset, so the window where the path does not exist is
# a couple of syscalls rather than a copy.
if [ -e "$aside" ] || [ -L "$aside" ]; then
  aside="$aside.$(date +%s)"
fi
mv -T -- "$ANCHOR_DIR" "$aside"
if ! mv -T -- "$new" "$ANCHOR_DIR"; then
  mv -T -- "$aside" "$ANCHOR_DIR"
  printf 'error: could not move %s into place; %s restored\n' "$ANCHOR_DIR" "$aside" >&2
  exit 1
fi

if ! "$ANCHOR_CHECK"; then
  rm -rf -- "$ANCHOR_DIR"
  mv -T -- "$aside" "$ANCHOR_DIR"
  printf 'error: %s still resolves into the pool after the move; %s restored\n' \
    "$ANCHOR_DIR" "$aside" >&2
  exit 1
fi

printf 'moved %s onto the root pool; %s sibling(s) relinked into %s\n' \
  "$ANCHOR_DIR/$ANCHOR_ENTRY" "$linked" "$ANCHOR_POOL_DIR"
printf 'the old copy at %s is now stale and nothing reads it on boot\n' "$src"
printf 'undo with: rm -rf -- %s && mv -T -- %s %s\n' "$ANCHOR_DIR" "$aside" "$ANCHOR_DIR"
