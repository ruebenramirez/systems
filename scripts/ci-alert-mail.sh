#!/usr/bin/env bash
#
# ci-alert-mail.sh -- mail a CI failure report with per-machine results.
#
# Only run on a real failure (not a cancellation). Transport is msmtp, installed
# and configured on the runner by ci-alert-mail.nix.
#
# Env:
#   RECIPIENT                 default r3v2@rueb.dev
#   WORKFLOW, TRIGGER, BRANCH, SHA, ACTOR, REQUESTED, RUN_URL, RESULT
#   RUN_LOG                   nup-fleet deploy log (optional)
#   NUP_FLEET_SUMMARY         nup-fleet SUMMARY line (optional)

set -uo pipefail

recipient="${RECIPIENT:-r3v2@rueb.dev}"

if ! command -v msmtp >/dev/null 2>&1; then
  echo "::warning title=Alert mail not sent::msmtp is not on PATH on $(hostname)"
  exit 0
fi

{
  printf 'From: root@rueb.dev\n'
  printf 'To: %s\n' "$recipient"
  printf 'Subject: [CI FAIL] %s (%s) on %s\n' \
    "${GITHUB_REPOSITORY:-systems}" "${TRIGGER:-unknown}" "$(hostname)"
  printf 'Date: %s\n' "$(date -R)"
  printf 'Content-Type: text/plain; charset=utf-8\n\n'
  printf 'Workflow:  %s\n' "${WORKFLOW:-}"
  printf 'Trigger:   %s\n' "${TRIGGER:-}"
  printf 'Actor:     %s\n' "${ACTOR:-}"
  printf 'Branch:    %s @ %s\n' "${BRANCH:-}" "${SHA:-}"
  printf 'Machines:  %s\n' "${REQUESTED:-whole fleet}"
  printf 'Run:       %s\n' "${RUN_URL:-}"
  printf 'Host:      %s\n' "$(hostname)"
  printf 'Result:    %s\n' "${RESULT:-failure}"
  if [[ -n "${NUP_FLEET_SUMMARY:-}" && -r "$NUP_FLEET_SUMMARY" ]]; then
    printf 'Summary:   %s\n' "$(grep '^SUMMARY ' "$NUP_FLEET_SUMMARY" | tail -n1)"
  fi
  if [[ -n "${RUN_LOG:-}" && -r "$RUN_LOG" ]]; then
    printf '\n--- per-machine results ---\n'
    grep -E '^(✓|✗|Skipping|Failed machines|All [0-9]+ machine|SUMMARY )' "$RUN_LOG" \
      || printf '(no per-machine lines found)\n'
    printf '\n--- last 120 lines ---\n'
    tail -n 120 "$RUN_LOG"
  fi
} | msmtp "$recipient" \
  || echo "::warning title=Alert mail not sent::msmtp could not submit to the mail server"
