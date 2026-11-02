#!/usr/bin/env bash
#
# hermes-notify.sh -- send a signed run notification to the Hermes
# `matrix-notify` webhook (Matrix room). Used by both CI workflows.
#
# Usage: scripts/hermes-notify.sh <status>    # success|failure|cancelled
#
# Env:
#   HERMES_WEBHOOK_URL, HERMES_WEBHOOK_SECRET   required; skip cleanly if unset
#   WORKFLOW, EVENT_NAME, RUN_NUMBER, RUN_URL   run metadata
#   CHECK_RESULT                                optional, e.g. sops precheck
#   PR_NUMBER, PR_TITLE, PR_AUTHOR              optional, PR checks only
#
# The route verifies an HMAC-SHA256 signature over the exact JSON body, so the
# body is built with jq and signed as-is. Nothing here is secret-bearing.

set -euo pipefail

status="${1:?usage: hermes-notify.sh <status>}"

if [[ -z "${HERMES_WEBHOOK_URL:-}" || -z "${HERMES_WEBHOOK_SECRET:-}" ]]; then
  echo "HERMES_WEBHOOK_URL / HERMES_WEBHOOK_SECRET not configured; skipping notify." >&2
  exit 0
fi

body="$(jq -n \
  --arg workflow "${WORKFLOW:-}" \
  --arg status "$status" \
  --arg event "${EVENT_NAME:-}" \
  --arg url "${RUN_URL:-}" \
  --arg run_number "${RUN_NUMBER:-}" \
  --arg check_result "${CHECK_RESULT:-}" \
  --arg pr_number "${PR_NUMBER:-}" \
  --arg pr_title "${PR_TITLE:-}" \
  --arg pr_author "${PR_AUTHOR:-}" \
  '{
     workflow: $workflow,
     status: $status,
     event: $event,
     url: $url,
     run_number: ($run_number | tonumber? // $run_number)
   }
   + (if $check_result != "" then {check_sops: $check_result} else {} end)
   + (if $pr_number != "" then
        {pr: {number: ($pr_number | tonumber? // $pr_number), title: $pr_title, author: $pr_author}}
      else {} end)')"

signature="$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$HERMES_WEBHOOK_SECRET" -hex | awk '{print $NF}')"

curl -fsS -m 15 --retry 3 --retry-delay 5 -X POST "$HERMES_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: sha256=$signature" \
  -d "$body"
