"""Make tools/world_packs importable for asset_fetch tests."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLS = str(ROOT / "tools" / "world_packs")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
