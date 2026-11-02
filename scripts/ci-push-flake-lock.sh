#!/usr/bin/env bash
#
# ci-push-flake-lock.sh -- persist a moved flake.lock to the protected branch.
#
# A deploy is best-effort: some machines may be unreachable while others are
# updated. The repo should still record the lock those machines are running on,
# so this pushes whenever at least one machine was updated -- the CI job itself
# stays red if any machine failed.
#
# Env:
#   CI_FLAKELOCK_PUSH   bot token used to push (master is protected)
#   BRANCH              branch to push to (e.g. github.ref_name)
#   NUP_FLEET_SUMMARY   path to nup-fleet's `SUMMARY updated=N ...` line
#
# Skips (exit 0) when nothing changed or no machine was updated.

set -euo pipefail

summary="${NUP_FLEET_SUMMARY:-}"
updated=0
if [[ -n "$summary" && -r "$summary" ]]; then
  line="$(grep '^SUMMARY ' "$summary" | tail -n1 || true)"
  if [[ "$line" =~ updated=([0-9]+) ]]; then
    updated="${BASH_REMATCH[1]}"
  fi
fi

if [[ "$updated" -lt 1 ]]; then
  echo "no machine was updated; not persisting flake.lock."
  exit 0
fi

if git diff --quiet -- flake.lock; then
  echo "flake.lock unchanged; nothing to commit."
  exit 0
fi

: "${CI_FLAKELOCK_PUSH:?CI_FLAKELOCK_PUSH is not set}"
: "${BRANCH:?BRANCH is not set}"

git config user.name  "forgejo-ci-runner-vm"
git config user.email "forgejo-ci-runner-vm@code.rueb.dev"
git add flake.lock
git commit -m "nix flake update (nightly fleet upgrade via CI)"

# master is protected and the Actions task token cannot push to it; the push
# goes out as the CI bot. `-c` outranks the blanked checkout extraheader.
header="Authorization: token $CI_FLAKELOCK_PUSH"
git -c "http.https://code.rueb.dev/.extraheader=$header" pull --rebase origin "$BRANCH"
git -c "http.https://code.rueb.dev/.extraheader=$header" push origin "HEAD:refs/heads/$BRANCH"
