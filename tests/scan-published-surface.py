#!/usr/bin/env python3
"""Scan everything the npm tarball ships for operator identity.

A published file is read by strangers on their own machines, and a leak in one
cannot be recalled. The git-sync tripwire only ever covered a single rendered
template; this covers the whole `files` whitelist from package.json, which is
the exact surface `npm publish` uploads.

Prints "SHIPPED=<n>" then "CLEAN" or "LEAK <path:line> ...". Exit 1 on a leak.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# /Users/Shared is a real, generic macOS path the sandbox rules must name by
# hand. A glob or a shell/template placeholder is not an operator identity.
HOME_PATH = re.compile(r"/Users/(?!Shared\b|\*|__|\$|<)[A-Za-z0-9._-]+")
IDENTITY = re.compile(r"codewalnut", re.I)
# The repo/homepage/bugs URLs name the GitHub owner by necessity: that is the
# project's published address, not a machine or an employer.
ALLOWED_SUBSTRINGS = ("github.com/BenSheridanEdwards/SuperHermes",)


def shipped_files(repo: Path) -> list[Path]:
    manifest = json.loads((repo / "package.json").read_text())
    files: list[Path] = []
    for entry in manifest["files"]:
        target = repo / entry.rstrip("/")
        if target.is_dir():
            files += sorted(p for p in target.rglob("*") if p.is_file())
        elif target.is_file():
            files.append(target)
    return files


def main() -> int:
    repo = Path(sys.argv[1]).resolve()
    files = shipped_files(repo)
    hits: list[str] = []
    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        relative = path.relative_to(repo)
        for number, line in enumerate(text.splitlines(), 1):
            if any(allowed in line for allowed in ALLOWED_SUBSTRINGS):
                continue
            if HOME_PATH.search(line) or IDENTITY.search(line):
                hits.append(f"{relative}:{number}")
    print(f"SHIPPED={len(files)}")
    print("CLEAN" if not hits else "LEAK " + " ".join(hits[:12]))
    return 1 if hits else 0


if __name__ == "__main__":
    raise SystemExit(main())
