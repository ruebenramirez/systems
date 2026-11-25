#!/usr/bin/env python3
"""hermes-apply-model-pin.py -- apply the `model:` scope a flake capture declares
to a Hermes config that already exists on disk.

Why: the tmpfiles `C` rules in hermes-agent.nix seed a config only when it is
absent, so a value that changes in the flake never reaches a live profile. A
profile with no `model.default` does not fail -- Hermes quietly runs the
provider's first catalog model (rueb/systems#126: after #119 dropped the managed
pin, Henry answered in `z-ai/glm-5.3`). The capture is the source of truth for
the model scope, so apply it at activation: the seed's whole `model:` block
(default, provider, aliases, api_mode) replaces the live one, and a live file
already in sync is not rewritten. Everything outside the block -- comments,
ordering, quoting -- is left untouched.

Deletion is deliberate: a key that live carries and the capture does not is
dropped, so the capture stays the only place the model scope is edited. Capture a
live value into the flake first if it should stick.

Usage:
  hermes-apply-model-pin.py --seed <flake capture> --live <live config>
                            [--label henry] [--check]

Exit: 0 = live config matches the flake's model scope (already, or written now)
      1 = --check found the scope out of sync (nothing written)
      2 = bad input, unreadable file, or a write that failed

A live file that does not exist yet is not an error: the tmpfiles `C` rule
creates it from the same seed, model scope included. Stdlib only.
"""

import argparse
import os
import re
import sys

TOP_KEY = re.compile(r"^[A-Za-z_]")
BLOCK = "model"
DEFAULT_INDENT = 2


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


def is_content(line: str) -> bool:
    """A line that is real YAML: not blank, not a comment-only line."""
    text = strip_comment(line).strip()
    return bool(text) and not text.startswith("#")


def unquote(value: str):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value or None


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def block_span(lines, key):
    """(start, end) line indices of the top-level `key:` block, end exclusive;
    None when the file has no such block."""
    start = None
    for i, raw in enumerate(lines):
        if not TOP_KEY.match(raw):
            continue
        if raw.split(":", 1)[0] == key:
            start = i
        elif start is not None:
            return start, i
    return (start, len(lines)) if start is not None else None


def body_span(lines, span):
    """(first, last) real content line indices of the block at `span`. Blank and
    comment lines trailing the last child belong to what follows, not here."""
    start, end = span
    last = start + 1
    for i in range(start + 1, end):
        if is_content(lines[i]):
            last = i + 1
    return start + 1, last


def base_indent(lines, span):
    """Indent of the block's first real child; None for an empty block."""
    first, last = body_span(lines, span)
    for i in range(first, last):
        if is_content(lines[i]):
            return indent_of(strip_comment(lines[i]))
    return None


def scope(lines, span):
    """The block's children flattened to {(key, ...): value}: a scalar's value, or
    None for a nested block header (an empty scalar is None too)."""
    first, last = body_span(lines, span)
    out, stack = {}, []
    for i in range(first, last):
        if not is_content(lines[i]):
            continue
        line = strip_comment(lines[i])
        ind = indent_of(line)
        key, _, value = line.strip().partition(":")
        value = unquote(value)
        while stack and ind <= stack[-1][0]:
            stack.pop()
        path = tuple([k for _, k in stack] + [key])
        out[path] = value
        if value is None:
            stack.append((ind, key))
    return out


def content(lines, span):
    """Comparison form of a block: real lines, comment-stripped and unindented,
    so reindenting or recommenting a live file is not drift."""
    first, last = body_span(lines, span)
    return [strip_comment(lines[i]).strip()
            for i in range(first, last) if is_content(lines[i])]


def reindent(line: str, delta: int) -> str:
    if delta > 0:
        return " " * delta + line
    if delta < 0:
        return line[min(-delta, indent_of(line)):]
    return line


def diff(want, have):
    """One terse line per difference, in seed order."""
    paths = list(want) + [p for p in have if p not in want]
    out = []
    for path in paths:
        name = ".".join((BLOCK,) + path)
        w, h = want.get(path), have.get(path)
        w = w if w is not None else "(block)"
        h = h if h is not None else "(block)"
        if path in want and path in have:
            if want[path] != have[path]:
                out.append(f"{name}: {h} -> {w}")
        elif path in want:
            out.append(f"{name}: +{w}")
        else:
            out.append(f"{name}: -{h}")
    return out


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
                    help="declarative capture that carries the model scope")
    ap.add_argument("--live", required=True, help="live config to enforce")
    ap.add_argument("--label", default="live", help="name used in messages")
    ap.add_argument("--check", action="store_true",
                    help="report an out-of-sync model scope instead of writing it")
    args = ap.parse_args()

    try:
        with open(args.seed, encoding="utf-8") as fh:
            seed = fh.readlines()
    except OSError as e:
        print(f"error: cannot read seed {args.seed}: {e}", file=sys.stderr)
        return 2
    want_span = block_span(seed, BLOCK)
    want = scope(seed, want_span) if want_span else {}
    if not want.get(("default",)):
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

    have_span = block_span(lines, BLOCK)
    if have_span is not None and content(lines, have_span) == content(seed, want_span):
        print(f"{args.label}: {args.live} already matches the flake's model scope "
              f"({want[('default',)]} on "
              f"{want.get(('provider',)) or 'its own provider'})")
        return 0

    stale = diff(want, scope(lines, have_span) if have_span else {})
    if args.check:
        print(f"{args.label}: {args.live} is out of sync with the flake's model "
              "scope:", file=sys.stderr)
        for line in stale:
            print(f"  {line}", file=sys.stderr)
        return 1

    first, last = body_span(seed, want_span)
    seed_indent = base_indent(seed, want_span)
    live_indent = base_indent(lines, have_span) if have_span else None
    delta = ((live_indent if live_indent is not None else DEFAULT_INDENT)
             - (seed_indent if seed_indent is not None else DEFAULT_INDENT))
    new = []
    for raw in seed[first:last]:
        line = raw if raw.endswith("\n") else raw + "\n"
        new.append(reindent(line, delta))

    if have_span is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append(f"{BLOCK}:\n")
        lines.extend(new)
    else:
        a, b = body_span(lines, have_span)
        lines[a:b] = new

    try:
        write_atomic(args.live, lines, info)
    except OSError as e:
        print(f"error: cannot write {args.live}: {e}", file=sys.stderr)
        return 2
    print(f"{args.label}: applied the flake's model scope to {args.live}:")
    for line in stale:
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
