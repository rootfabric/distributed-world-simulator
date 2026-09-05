#!/usr/bin/env python3
"""Fail on every fatal Godot import marker; no historical-error exemptions."""
from __future__ import annotations

import argparse
import re
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", args.log.read_text(encoding="utf-8"))
    failures = [line for line in text.splitlines() if re.search(
        r"SCRIPT ERROR|ERROR:|Parse Error|Invalid call|Assertion failed|Segmentation fault", line)]
    if failures:
        raise SystemExit("Fatal Godot import failure:\n" + "\n".join(failures))
    if "Godot Engine v4.7.1.stable.double.custom_build.a13da4feb" not in text:
        raise SystemExit("Canonical Godot import banner missing")
    print("B06_IMPORT_STATUS=CLEAN")
    print("B06_IMPORT_FATAL_COUNT=0")


if __name__ == "__main__":
    main()
