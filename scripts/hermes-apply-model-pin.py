#!/usr/bin/env python3
"""hermes-apply-model-pin.py -- re-assert the model pin a flake seed declares
into a Hermes config that already exists on disk.

Why: the tmpfiles `C` rules in hermes-agent.nix seed a config only when it is
absent, so a pin that changes in the flake never reaches a live profile. A
profile with no `model.default` does not fail -- Hermes quietly runs the
provider's first catalog model (rueb/systems#126: after #119 dropped the
managed pin, Henry answered in `z-ai/glm-5.3`). This closes that window at
activation: read the intended `model.default` / `model.provider` back out of
the declarative capture and upsert them into the live file, leaving every other
line -- comments, ordering, quoting -- untouched.

The seed file is the only source of the pin; nothing is duplicated on the
command line, so the flake capture and the enforced value cannot disagree.

Usage:
  hermes-apply-model-pin.py --seed <flake capture> --live <live config>
                            [--label henry] [--check]

Exit: 0 = live config carries the pin (already, or written now)
      1 = --check found the pin out of sync (nothing written)
      2 = bad input, unreadable file, or a write that failed

A live file that does not exist yet is not an error: the tmpfiles `C` rule
creates it from the same seed, pin included. Stdlib only.
"""

import argparse
import os
import re
import sys

TOP_KEY = re.compile(r"^[A-Za-z_]")
PIN_KEYS = ("default", "provider")


def strip_comment(line: str) -> str:
    """Drop a trailing inline comment; a `#` inside quotes or glued to a
    token (a banner line, a URL fragment) is not a comment."""
    quote = None
    for i, c in enumerate(line):
        if quote:
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "#" and i > 0 and line[i - 1] in " \t":
            return line[:i].rstrip()
    return line.rstrip()


def unquote(value: str):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value or None


def model_pin(lines):
    """The `default`/`provider` values declared under the top-level `model:`
    block, as a dict; a key that is absent or empty maps to None."""
    pin = dict.fromkeys(PIN_KEYS)
    want_indent = child_indent(lines)
    in_model = False
    for raw in lines:
        line = strip_comment(raw)
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if TOP_KEY.match(line):
            in_model = line.split(":", 1)[0] == "model"
            continue
        if not in_model:
            continue
        indent = len(line) - len(line.lstrip())
        key, _, value = line.strip().partition(":")
        if indent == want_indent and key in PIN_KEYS:
            pin[key] = unquote(value)
    return pin


def child_indent(lines):
    """Indent of the first real child of the `model:` block (2 for a Hermes
    config, but do not hard-code it)."""
    in_model = False
    for raw in lines:
        line = strip_comment(raw)
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if TOP_KEY.match(line):
            in_model = line.split(":", 1)[0] == "model"
            continue
        if in_model:
            return len(line) - len(line.lstrip())
    return 2


def model_block(lines):
    """(start, end) line indices of the top-level `model:` block, end
    exclusive; None when the file has no such block."""
    start = None
    for i, raw in enumerate(lines):
        if not TOP_KEY.match(raw):
            continue
        if raw.split(":", 1)[0] == "model":
            start = i
        elif start is not None:
            return start, i
    return (start, len(lines)) if start is not None else None


def upsert(lines, key, value, indent):
    """Set `key: value` among the direct children of `model:`, in place if it
    is already there (comment kept) or appended at the end of the block."""
    start, end = model_block(lines)
    for i in range(start + 1, end):
        line = lines[i]
        if line.lstrip().startswith("#"):
            continue
        if (len(line) - len(line.lstrip())) != indent:
            continue
        if line.strip().partition(":")[0] != key:
            continue
        lead = line[:len(line) - len(line.lstrip())]
        code = strip_comment(line)
        # Whatever trailed the value on the original line (spacing + inline
        # comment) goes back verbatim; only the value changes.
        comment = line[len(code):].rstrip("\n") if line.rstrip("\n") != code else ""
        lines[i] = f"{lead}{key}: {value}{comment}\n"
        return
    at = end
    # Keep the block's trailing banner/blank lines with the section after it.
    while at > start + 1 and (not lines[at - 1].strip()
                              or lines[at - 1].lstrip().startswith("#")):
        at -= 1
    lines.insert(at, f"{' ' * indent}{key}: {value}\n")


def write_atomic(path, lines, info):
    tmp = path + ".hermes-pin.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.writelines(lines)
    os.chmod(tmp, info.st_mode)
    os.chown(tmp, info.st_uid, info.st_gid)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", required=True,
                    help="declarative capture that carries the intended pin")
    ap.add_argument("--live", required=True, help="live config to enforce")
    ap.add_argument("--label", default="live", help="name used in messages")
    ap.add_argument("--check", action="store_true",
                    help="report an out-of-sync pin instead of writing it")
    args = ap.parse_args()

    try:
        with open(args.seed, encoding="utf-8") as fh:
            want = model_pin(fh.readlines())
    except OSError as e:
        print(f"error: cannot read seed {args.seed}: {e}", file=sys.stderr)
        return 2
    if not want["default"]:
        print(f"error: seed {args.seed} declares no model.default; nothing to "
              "enforce (a pin-less seed would let the provider catalog decide)",
              file=sys.stderr)
        return 2

    try:
        os.stat(args.live)
    except FileNotFoundError:
        print(f"{args.label}: {args.live} does not exist yet; the tmpfiles seed "
              "creates it from the same capture")
        return 0
    except OSError as e:
        print(f"error: cannot stat {args.live}: {e}", file=sys.stderr)
        return 2

    try:
        info = os.stat(args.live)
        with open(args.live, encoding="utf-8") as fh:
            lines = fh.readlines()
    except (OSError, UnicodeDecodeError) as e:
        print(f"error: cannot read {args.live}: {e}", file=sys.stderr)
        return 2

    have = model_pin(lines)
    stale = {k: v for k, v in want.items() if v and have.get(k) != v}
    if not stale:
        print(f"{args.label}: {args.live} already pins "
              f"{want['default']} on {want['provider'] or 'its own provider'}")
        return 0

    report = ", ".join(
        f"model.{k} {have.get(k) or '(unset)'} -> {stale[k]}" for k in PIN_KEYS
        if k in stale)
    if args.check:
        print(f"{args.label}: {args.live} is missing the flake's pin: {report}",
              file=sys.stderr)
        return 1

    if model_block(lines) is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.extend(["model:\n"] +
                     [f"  {k}: {stale[k]}\n" for k in PIN_KEYS if k in stale])
    else:
        indent = child_indent(lines)
        for k in PIN_KEYS:
            if k in stale:
                upsert(lines, k, stale[k], indent)
    try:
        write_atomic(args.live, lines, info)
    except OSError as e:
        print(f"error: cannot write {args.live}: {e}", file=sys.stderr)
        return 2
    print(f"{args.label}: pinned {args.live}: {report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
