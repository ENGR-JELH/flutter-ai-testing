#!/usr/bin/env python3
"""Checks the test keys in a Flutter app (flutter-ai-testing). Read-only.

Fails (exit 1) when a key string looks like contact data: keys show up in
agent output and docs, so they must never carry personal data.
Warns when the same literal key appears more than once in one file; that is
fine only when the sites are in mutually exclusive branches (check by hand).

Run from inside the app:  python3 <scripts-dir>/check_test_keys.py
"""
import collections
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from keyscan import KeyScanner, app_root  # noqa: E402

CONTACT = re.compile(r"@|\d{3}[-. ]?\d{3}[-. ]?\d{4}")


def main():
    scanner = KeyScanner(app_root())
    total = problems = 0
    for path in scanner.files():
        items = list(scanner.keys_in(path))
        total += len(items)
        rel = path.relative_to(scanner.root)
        counts = collections.Counter(key for key, _ in items)
        for key, count in counts.items():
            if count > 1 and "$" not in key and "(" not in key and "<" not in key:
                lines = [i + 1 for k, i in items if k == key]
                print(f"WARN  {rel}: '{key}' used {count}x at lines {lines} (check the branches are exclusive)")
        for key, index in items:
            if CONTACT.search(key):
                print(f"FAIL  {rel}:{index + 1}: key looks like contact data")
                problems += 1
    print(f"keys: {total}, problems: {problems}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
