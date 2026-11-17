#!/usr/bin/env bash
#
# ci-refresh-flake-chart.sh -- regenerate the README commit-volume chart and
# open a PR when the data changed.
#
# Env:
#   CI_FLAKELOCK_PUSH   bot token used to push the branch and open the PR
#   REPO                owner/repo (e.g. github.repository)
#   RUN_URL             this run's URL, linked from the PR body
#   BASE                base branch (default master)
#
# The chart header embeds the head hash, so the file text changes on every
# commit; only the data lines are compared. Skips (exit 0) when they are
# unchanged, restoring the working tree so a no-op run touches nothing.

set -euo pipefail

MMD="docs/system-flake-commit-volume.mmd"
SVG="docs/system-flake-commit-volume.svg"
BRANCH="ci/flake-chart-refresh"
BASE="${BASE:-master}"
API="https://code.rueb.dev/api/v1/repos/${REPO:?REPO is not set}"

old_mmd="$(mktemp)"
trap 'rm -f "$old_mmd"' EXIT
cp "$MMD" "$old_mmd"

scripts/generate-system-flake-chart.sh --render

# The header lines (%% ...) carry the head hash and window text; they move on
# every commit even when the counts do not.
if diff -q <(grep -v '^%%' "$MMD") <(grep -v '^%%' "$old_mmd") >/dev/null; then
  git checkout -- "$MMD" "$SVG"
  echo "chart data unchanged; nothing to propose."
  exit 0
fi

: "${CI_FLAKELOCK_PUSH:?CI_FLAKELOCK_PUSH is not set}"

git config user.name  "forgejo-ci-runner-vm"
git config user.email "forgejo-ci-runner-vm@code.rueb.dev"
git add "$MMD" "$SVG"
git commit -m "docs: refresh flake commit volume chart"

# master is protected and the Actions task token cannot push; the push goes
# out as the CI bot. `-c` outranks the blanked checkout extraheader.
header="Authorization: token $CI_FLAKE...PUSH"
git -c "http.https://code.rueb.dev/.extraheader=$header" push --force origin "HEAD:refs/heads/$BRANCH"

auth=(-H "Authorization: token $CI_FLAKE...PUSH" -H "Content-Type: application/json")

# The branch is fixed and force-pushed, so a still-open PR is updated by the
# push above; only create one when there is none.
existing="$(curl -fsS "${auth[@]}" "$API/pulls?state=open&limit=50" \
  | jq -r --arg b "$BRANCH" '[.[] | select(.head.ref == $b)] | first | .number // empty')"
if [[ -n "$existing" ]]; then
  echo "updated existing PR #${existing}."
  exit 0
fi

body="$(cat <<EOF
## What

Regenerates \`$MMD\` and \`$SVG\` with \`scripts/generate-system-flake-chart.sh --render\` from the current \`$BASE\` history.

## Why

The chart is a headline graphic in the README and goes stale silently; the weekly workflow that opened this PR keeps it current with no manual step.

## How

Produced by \`.forgejo/workflows/flake-chart-refresh.yaml\` (\`scripts/ci-refresh-flake-chart.sh\`); the run is at ${RUN_URL:-this workflow}.
EOF
)"

payload="$(jq -n --arg head "$BRANCH" --arg base "$BASE" --arg title "docs: refresh flake commit volume chart" --arg body "$body" \
  '{head: $head, base: $base, title: $title, body: $body}')"

pr_number="$(curl -fsS "${auth[@]}" -X POST "$API/pulls" -d "$payload" | jq -r .number)"
echo "opened PR #${pr_number}."
