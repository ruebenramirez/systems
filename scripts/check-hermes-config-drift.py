#!/usr/bin/env python3
"""check-hermes-config-drift.py -- compare the live Hermes user config against
the declarative copy in nix/machines/hermes-vm-xps/services/hermes-config.yaml.

The declarative copy is the source of truth for the keys it declares: the model
scope is applied to live at activation (scripts/hermes-apply-model-pin.py) and
the rest is declared here, so a live-only change is meant to be declared
deliberately rather than mirrored blindly. This script normalizes both sides
(strip comments, blank lines, inline comments; drop volatile keys) and reports
the divergence for a nightly job.

Volatile keys dropped from both sides:
  _config_version                       bumped by hermes itself
  onboarding.seen.*                     UI state, not configuration
  any `secret:` key                     secrets must never land in git,
                                        regardless of value format

Usage:
  check-hermes-config-drift.py --live /opt/data/config.yaml --desired <file>
      exit 0 = no drift, 1 = drift (unified diff on stdout), 2 = bad input
  check-hermes-config-drift.py --live <file> --emit [--desired <file>]
      print the full desired-file content (header + normalized live config);
      with --desired the exit-3 guard below applies

Also runs per-profile: --live /opt/data/profiles/<name>/config.yaml --desired
the matching nix/machines/hermes-vm-xps/services/profiles/<name>/config.yaml
(--header-file to regenerate a profile's own header).

Deploy sequencing: after a rebuild drops/changes a managed model pin, seed the
live default-profile config BEFORE the next drift run
(`hermes config set model.default ... && hermes config set model.provider ...`,
or `scripts/hermes-apply-model-pin.py`), otherwise --emit regenerates the
desired file from an unseeded live config and silently reverts per-profile
pins. --emit refuses to emit whenever the live model pin is not the one the
desired file declares -- missing or merely different (exit 3) -- because that is
exactly the moment the flake must not be made to follow live.

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
# /opt/data/config.yaml (comments and default-only noise stripped). This file is
# the declarative source for the config: the tmpfiles C rule in hermes-agent.nix
# recovers a state dir from scratch with it, and the model scope is enforced on a
# live one. Declare changes here, never in the live file.
#
# The model scope is enforced from here: the hermes-model-pin unit writes this
# file's whole `model:` block (default, provider, aliases, api_mode) over the
# live config's at every activation, so a model or alias set anywhere else holds
# only until the next rebuild.
#
# Keys outside the model scope are not enforced yet; the drift check reports the
# divergence so the change gets declared here deliberately instead of mirrored.
#
# Managed-scope keys (dashboard.basic_auth, halogen provider) live in
# hermes-agent.nix and win on merge — do not add them here. model.default is
# NOT managed: a managed pin would override every profile's own default.
# This file is the default profile's seed (halogen); Henry's pin lives in
# ./profiles/henry/config.yaml.
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


def model_pin(lines):
    """The model.default / model.provider values pinned at top level.
    `lines` is normalize() output, so indentation survives and comments do not;
    four-space lines are nested keys (aliases), not the pin."""
    pin = {"default": None, "provider": None}
    in_model = False
    for line in lines:
        if TOP_KEY.match(line):
            in_model = line.split(":", 1)[0] == "model"
            continue
        if not in_model or line.startswith("    "):
            continue
        key, _, value = line.strip().partition(":")
        if key in pin:
            value = value.strip().strip('"').strip("'")
            pin[key] = value or None
    return pin


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", required=True, help="path to live config.yaml")
    ap.add_argument("--desired", help="path to the declarative copy")
    ap.add_argument("--emit", action="store_true",
                    help="print the normalized live config instead of checking")
    ap.add_argument("--header-file",
                    help="with --emit: file whose contents replace the built-in "
                         "header (use for profile configs)")
    args = ap.parse_args()

    try:
        live = normalize(args.live)
    except OSError as e:
        print(f"error: cannot read live config: {e}", file=sys.stderr)
        return 2

    if args.emit:
        if args.desired:
            # Guard: regenerating from a live config whose pin disagrees with
            # the flake (unseeded after a managed pin was dropped, or changed
            # from the dashboard) would silently rewrite the declared default to
            # whatever live happens to run.
            try:
                desired = normalize(args.desired)
            except OSError as e:
                print(f"error: cannot read desired config: {e}", file=sys.stderr)
                return 2
            want, have = model_pin(desired), model_pin(live)
            if want["default"] and want != have:
                print("error: live pins "
                      f"{have['default'] or '(no model.default)'} on "
                      f"{have['provider'] or '(no model.provider)'}, the desired "
                      f"file pins {want['default']} on {want['provider']}; --emit "
                      "would make the flake follow live. Seed the live config "
                      "first (scripts/hermes-apply-model-pin.py, or `hermes "
                      "config set model.default ...`), or change the desired "
                      "file deliberately.",
                      file=sys.stderr)
                return 3
        if args.header_file:
            try:
                with open(args.header_file, encoding="utf-8") as fh:
                    print(fh.read().rstrip("\n"))
            except OSError as e:
                print(f"error: cannot read header file: {e}", file=sys.stderr)
                return 2
        else:
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
