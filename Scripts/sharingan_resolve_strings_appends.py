#!/usr/bin/env python3
"""Resolve the routine upstream-merge conflicts in Sharingan's Localizable.strings catalogs.

Upstream CodexBar and Sharingan both append new keys at the end of every catalog, so a merge leaves one
conflict hunk per file where both sides only ADDED lines. This script resolves exactly those hunks (diff3
style, empty base) by keeping ours first and then theirs, and leaves every other hunk untouched for a human.

With --rebrand it also replaces the app name "CodexBar" with "Sharingan" in the VALUES of keys that the
resolved hunks brought in from upstream, matching the Phase 0 rebrand rules: keys are never changed, and
lowercase `codexbar` (CLI, paths, URL schemes) is left alone.

Usage: Scripts/sharingan_resolve_strings_appends.py [--rebrand] FILE...
Exit: 0 when every given file is conflict-free afterwards, 1 when hunks remain, 2 on bad input.
"""

import re
import sys

ENTRY = re.compile(r'^(\s*"(?:[^"\\]|\\.)*"\s*=\s*")((?:[^"\\]|\\.)*)("\s*;\s*)$')
KEY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=')
APP_NAME = re.compile(r"\bCodexBar\b")


def rebrand(line: str) -> str:
    match = ENTRY.match(line.rstrip("\n"))
    if not match:
        return line
    head, value, tail = match.groups()
    newline = "\n" if line.endswith("\n") else ""
    return head + APP_NAME.sub("Sharingan", value) + tail + newline


def resolve(path: str, do_rebrand: bool) -> int:
    with open(path, encoding="utf-8") as handle:
        lines = handle.readlines()
    out, remaining, i = [], 0, 0
    while i < len(lines):
        if not lines[i].startswith("<<<<<<< "):
            out.append(lines[i])
            i += 1
            continue
        ours, base, theirs, section, j = [], [], [], "ours", i + 1
        saw_base = False
        while j < len(lines) and not lines[j].startswith(">>>>>>> "):
            if lines[j].startswith("||||||| "):
                section, saw_base = "base", True
            elif lines[j].startswith("=======") and lines[j].rstrip("\n") == "=======":
                section = "theirs"
            elif section == "ours":
                ours.append(lines[j])
            elif section == "base":
                base.append(lines[j])
            else:
                theirs.append(lines[j])
            j += 1
        if j >= len(lines):
            print(f"{path}: unterminated conflict at line {i + 1}", file=sys.stderr)
            return 2
        if saw_base and not any(line.strip() for line in base):
            out.extend(ours)
            if ours and not ours[-1].endswith("\n"):
                out.append("\n")
            out.extend(rebrand(line) if do_rebrand else line for line in theirs)
        else:
            out.extend(lines[i:j + 1])
            remaining += 1
        i = j + 1
    # Unresolved hunks hold both versions of a line, so only check for duplicates once none remain.
    keys = [m.group(1) for m in (KEY.match(line) for line in out) if m] if not remaining else []
    seen: set[str] = set()
    duplicates = sorted({key for key in keys if key in seen or seen.add(key)})
    with open(path, "w", encoding="utf-8") as handle:
        handle.writelines(out)
    for key in duplicates:
        print(f"{path}: duplicate key after merge: {key}", file=sys.stderr)
    if remaining:
        print(f"{path}: {remaining} conflict hunk(s) need a human", file=sys.stderr)
    return 1 if remaining or duplicates else 0


def main(argv: list[str]) -> int:
    do_rebrand = "--rebrand" in argv
    files = [arg for arg in argv if arg != "--rebrand"]
    if not files:
        print(__doc__.strip().splitlines()[-2], file=sys.stderr)
        return 2
    return max(resolve(path, do_rebrand) for path in files)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
