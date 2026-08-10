# G7.3 Cross-Cell / Cross-LOD Invariance — ACCEPTED

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-10-R2`
**Branch:** `feature/g7-semantic-field-fabric`
**Tested head:** `910899a906e684d6793cd74ba898d68c457a37b4`
**Engine:** `Godot 4.7.1.stable.double.custom_build.a13da4feb`

## Решение

```text
G7.3 Cross-Cell / Cross-LOD Invariance: ACCEPTED
```

Windows evidence:

```text
G7.3 Cross-Cell / Cross-LOD Invariance: PASS (122 assertions)
G7.3 FULL ACCEPTANCE: PASS
Global revision: GLOBAL-P0-2026-08-10-R2
Active GLOBAL-P0 main alignment: PASS
Canonical GLOBAL roadmap byte-match to main: PASS
G7.2 ACCEPTED ancestor: PASS
G7.3 invariance scope: PASS
Cross-cell / cross-LOD semantic invariance: PASS
World/core regression: PASS
Working tree: CLEAN
main_scene_cli_all: 6 PASS / 0 FAIL
```

## Доказанные инварианты

```text
same world point + same canonical SemanticFieldQuery
    -> same query checksum
    -> same SemanticFieldBundle checksum
    -> same SemanticFieldCompositionReceipt checksum
    -> same per-field sample checksum
    -> same provenance checksum
```

Это доказано при representation LOD:

```text
2, 4, 8, 12
```

При этом `SurfaceCellKey` и representation resolution реально меняются.

Также подтверждено:

```text
SemanticFieldQuery has no SurfaceCellKey / LOD
query field order does not alter canonical result
one river spans multiple representation cells
PX/PZ seam preserves semantic behavior
G5 FeatureId remains stable across cells
G6 FluidRegionId remains stable across cells
river-distance-m remains zero on accepted centerline across seam
```

## Harness fixes

Три acceptance-harness исправления не меняли semantic/runtime код:

```text
Fix1 — canonical R2 Markdown hard-break hygiene
Fix2 — safe stale Microsoft/ transient cleanup
Fix3 — PowerShell ${Phase}: parser correction
```

## P0

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
FeatureId != SurfaceCellKey
FluidRegionId != SurfaceCellKey
representation density != canonical identity
G7.3 != scheduler/cache
G7.3 != authority/interest
G7.3 != persistence/network
```

## Следующий checkpoint

```text
G7.4 — Semantic Field Lab
```

G7.4 является derived visual/debug presentation поверх accepted G7 semantics и не получает canonical ownership.
