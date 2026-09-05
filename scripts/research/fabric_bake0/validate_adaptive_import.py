#!/usr/bin/env python3
"""Attribute inherited ECO BOM scene failures; reject every new import failure."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

BASE = "1e8e74d6afafad294ddf10d68cb37efacc3ef3a1"
SCENES = {
    "eco_evo4_b3_plasticity_preview_lab", "eco_evo4_b6_region_lab",
    "eco_evo5_b2_agents_plot_lab", "eco_evo5_probe2_tree_lab",
    "eco_evo5_t51_creature_lab", "eco_evo5_terrain_fly_lab",
}


def main() -> None:
    text = Path(sys.argv[1]).read_text(encoding="utf-8")
    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text)
    seen: set[str] = set()
    for line in text.splitlines():
        if not re.search(r"SCRIPT ERROR|ERROR:|Parse Error|Invalid call|Assertion failed|Segmentation fault", line):
            continue
        match = re.fullmatch(r"ERROR: res://(scenes/labs/ecology/([a-z0-9_]+)\.tscn):1 - Parse Error: Expected '\['\.", line)
        if not match or match[2] not in SCENES:
            raise ValueError("Unattributed import failure: " + line)
        path = match[1]
        original = subprocess.check_output(["git", "show", f"{BASE}:{path}"])
        if not original.startswith(b"\xef\xbb\xbf") or Path(path).read_bytes() != original:
            raise ValueError("Inherited ECO parse attribution no longer exact: " + path)
        seen.add(path)
    print("B06_IMPORT_STATUS=" + ("BASELINE_ECO_SCENE_ERRORS_ATTRIBUTED" if seen else "CLEAN"))
    print("B06_IMPORT_BASELINE_ERROR_FILES=" + str(len(seen)))
    for path in sorted(seen):
        print("B06_IMPORT_UNCHANGED_BASELINE=" + path)


if __name__ == "__main__":
    main()
