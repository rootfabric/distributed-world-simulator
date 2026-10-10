#!/usr/bin/env python3
"""Run the accepted A9 fidelity contract against repo-local namespace paths.

Some self-hosted Python environments expose an unrelated regular top-level
package named "scripts". The historical A9 test imports
scripts.research.ecology.v2 as a PEP 420 namespace, so that foreign package can
shadow the repository directory. This launcher binds only the four expected
repo-local namespace packages, then executes the unchanged A9 contract.
"""
from __future__ import annotations

from pathlib import Path
import runpy
import sys
import types

ROOT = Path(__file__).resolve().parents[3]
NAMESPACES = {
    "scripts": ROOT / "scripts",
    "scripts.research": ROOT / "scripts" / "research",
    "scripts.research.ecology": ROOT / "scripts" / "research" / "ecology",
    "scripts.research.ecology.v2": ROOT / "scripts" / "research" / "ecology" / "v2",
}

for name, path in NAMESPACES.items():
    if not path.is_dir():
        raise SystemExit(f"A9_NAMESPACE_PATH_MISSING:{name}:{path}")
    module = types.ModuleType(name)
    module.__path__ = [str(path)]
    module.__package__ = name
    sys.modules[name] = module

target = ROOT / "validation" / "ecology" / "evo_arch2_a9" / "test_fidelity.py"
if not target.is_file():
    raise SystemExit("A9_TEST_MISSING")
runpy.run_path(str(target), run_name="__main__")
