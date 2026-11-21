#!/usr/bin/env python3
"""Check whether a local patch is already applied in an Android project tree.

`patch -R --dry-run` is the usual test, but patches that touch the same lines
cannot be checked that way: e.g. audio 0003 (voice routes, 2026-11-21) changed
hunks of 0002 (mixer routes), so reverse-applying 0002 fails even though it is
in the tree and a forward apply would fail too. Fall back to checking that
every non-empty line the patch adds is present in its target file.

    patch-applied.py PROJECT_DIR PATCH_FILE

Exit 0 if the patch is present, 1 if not (or if a target file is missing).
"""
import pathlib
import sys


def targets(text):
    path = None
    added = []
    for line in text.splitlines():
        if line.startswith("+++ "):
            path = line[4:].split("\t")[0].strip()
            if path.startswith("b/"):
                path = path[2:]
            continue
        if line.startswith("+") and not line.startswith("+++") and path:
            value = line[1:]
            if value.strip():
                added.append((path, value))
    return added


def main():
    project = pathlib.Path(sys.argv[1])
    patch = pathlib.Path(sys.argv[2]).read_text(errors="replace")
    checks = targets(patch)
    if not checks:
        return 1
    cache = {}
    for name, line in checks:
        if name not in cache:
            path = project / name
            cache[name] = path.read_text(errors="replace") if path.is_file() else None
        if cache[name] is None or line not in cache[name]:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
