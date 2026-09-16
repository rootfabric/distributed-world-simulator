#!/usr/bin/env python3
"""Exact wrapper for the MVP6 -> NX dependency probe.

The registered NX branch contains one additional pre-verification GDScript
inference issue in test_nx_client_tick_robustness.gd.  This wrapper applies a
single temporary declaration-operator normalization to the detached probe copy:
`var candidate := reference + offset` -> `var candidate = reference + offset`.
It proves assertion count is unchanged and then delegates all baseline/candidate
execution and evidence binding to mvp6_nx_dependency_probe.py.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "mvp6_nx_dependency_probe.py"
spec = importlib.util.spec_from_file_location("mvp6_nx_dependency_probe", TARGET)
if spec is None or spec.loader is None:
    raise RuntimeError("NX_PROBE_MODULE_LOAD_FAILED")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

_original = probe.apply_parser_only_test_compatibility


def _patched_compatibility() -> list[dict]:
    records = list(_original())
    path = "tests/network/test_nx_client_tick_robustness.gd"
    target = probe.WORKTREE / path
    source = target.read_text(encoding="utf-8")
    before = "var candidate := reference + offset"
    after = "var candidate = reference + offset"
    if source.count(before) != 1 or after in source:
        raise RuntimeError("NX_CLIENT_TICK_DECLARATION_PATCH_PRECONDITION_FAILED")
    patched = source.replace(before, after)
    if patched.count("_assert(") != source.count("_assert("):
        raise RuntimeError("NX_CLIENT_TICK_ASSERTION_COUNT_CHANGED")
    changed = [(a, b) for a, b in zip(source.splitlines(), patched.splitlines()) if a != b]
    if changed != [(next(line for line in source.splitlines() if before in line), next(line for line in patched.splitlines() if after in line))]:
        raise RuntimeError("NX_CLIENT_TICK_UNEXPECTED_PATCH_SURFACE")
    if changed[0][0].replace(":=", "=") != changed[0][1]:
        raise RuntimeError("NX_CLIENT_TICK_NON_DECLARATION_CHANGE")
    target.write_text(patched, encoding="utf-8")
    records.append({
        "path": path,
        "change": "CANDIDATE_LOOP_VARIANT_DECLARATION_COLON_EQUALS_TO_EQUALS_ONLY",
        "changed_declarations": 1,
        "before_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "after_sha256": hashlib.sha256(patched.encode()).hexdigest(),
        "assertion_calls": source.count("_assert("),
    })
    return records


probe.apply_parser_only_test_compatibility = _patched_compatibility
raise SystemExit(probe.main())
