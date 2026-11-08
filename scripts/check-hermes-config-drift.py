#!/usr/bin/env python3
"""check-hermes-config-drift.py -- compare the live Hermes user config against
the declarative copy in nix/machines/hermes-vm-xps/services/hermes-config.yaml.

The live file (/opt/data/config.yaml) is the source of truth: Hermes rewrites
it from the dashboard and on version bumps. This script normalizes both sides
(strip comments, blank lines, inline comments; drop volatile keys) and reports
the diff, so a nightly job can open a PR when the live config drifts.

Volatile keys dropped from both sides:
  _config_version                       bumped by hermes itself
  onboarding.seen.*                     UI state, not configuration
  any `secret:` key                     secrets must never land in git,
                                        regardless of value format

Usage:
  check-hermes-config-drift.py --live /opt/data/config.yaml --desired <file>
      exit 0 = no drift, 1 = drift (unified diff on stdout), 2 = bad input
  check-hermes-config-drift.py --live <file> --emit
      print the full desired-file content (header + normalized live config)

Stdlib only; runs inside the Hermes container and on any host.
"""

import argparse
import difflib
import re
import sys

DROP_TOP = {"_config_version", "onboarding"}
# Strip any `secret:` key and its whole subtree regardless of value shape:
# gating on a hex pattern would leak a rotated non-hex or block-scalar secret
# into --emit output and git history.
SECRET_KEY = re.compile(r"^\s*secret:")
TOP_KEY = re.compile(r"^[A-Za-z_]")

# Emitted by --emit ahead of the body so regeneration never drops the
# guardrail notes from the desired file. Keep in sync with the header of
# nix/machines/hermes-vm-xps/services/hermes-config.yaml.
HEADER = """\
# Hermes user-scope config for hermes-vm-xps, captured from the live
# /opt/data/config.yaml (comments and default-only noise stripped). Installed at
# /var/lib/hermes/config.yaml on first boot by the tmpfiles C rule in
# hermes-agent.nix (copy-if-absent, never overwrite); after that the live file
# is the source of truth and scripts/check-hermes-config-drift.py is meant to
# keep this copy in sync via nightly PRs.
#
# Managed-scope keys (dashboard.basic_auth, model default/provider, halogen
# provider) live in hermes-agent.nix and win on merge — do not add them here.
# No secret may appear in this file: platforms.webhook.extra.secret lives only
# in the live config until the sops migration lands, and this checker strips
# any secret: key."""


def strip_line(line: str):
    """Return the line with inline comments removed, or None if it vanishes."""
    s = line.rstrip()
    stripped = s.lstrip()
    if not stripped or stripped.startswith("#"):
        return None
    out = []
    quote = None
    for i, c in enumerate(s):
        if quote:
            out.append(c)
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
            out.append(c)
        elif c == "#" and i > 0 and s[i - 1] in " \t":
            break
        else:
            out.append(c)
    result = "".join(out).rstrip()
    return result if result.strip() else None


def normalize(path: str):
    lines = []
    # Indent of the key whose subtree is being skipped; None when not skipping.
    skip_indent = None
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = strip_line(raw)
            if line is None:
                continue
            indent = len(line) - len(line.lstrip())
            if TOP_KEY.match(line):
                skip_indent = None
                if line.split(":", 1)[0] in DROP_TOP:
                    skip_indent = 0  # subtree skipped by indent below
                    continue  # drop the key line itself
            if skip_indent is not None:
                if indent > skip_indent:
                    continue
                skip_indent = None  # sibling or shallower key ends the subtree
            if SECRET_KEY.match(line):
                # drop the key and everything nested under it (block scalars,
                # nested maps) — a value-shape test would leak them
                skip_indent = indent
                continue
            lines.append(line)
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", required=True, help="path to live config.yaml")
    ap.add_argument("--desired", help="path to the declarative copy")
    ap.add_argument("--emit", action="store_true",
                    help="print the normalized live config instead of checking")
    args = ap.parse_args()

    try:
        live = normalize(args.live)
    except OSError as e:
        print(f"error: cannot read live config: {e}", file=sys.stderr)
        return 2

    if args.emit:
        print(HEADER)
        print("\n".join(live))
        return 0

    if not args.desired:
        print("error: --desired is required unless --emit", file=sys.stderr)
        return 2

    try:
        desired = normalize(args.desired)
    except OSError as e:
        print(f"error: cannot read desired config: {e}", file=sys.stderr)
        return 2

    if live == desired:
        print("no drift")
        return 0

    diff = difflib.unified_diff(desired, live,
                                fromfile="desired (nix)", tofile="live")
    print("\n".join(diff))
    return 1


if __name__ == "__main__":
    sys.exit(main())
