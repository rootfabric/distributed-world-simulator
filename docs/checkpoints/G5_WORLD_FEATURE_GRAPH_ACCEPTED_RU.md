# G5 — World Feature Graph + Spatial Feature Identity — ACCEPTED

**Дата приёмки:** 2026-08-08
**Ветка:** `feature/g5-world-feature-graph`
**Accepted candidate head:** `34be9d35e7f0a0e6c7a7c7c8bdd58b70c95413b4`
**Base:** `feature/g4-provider-composition-replacement @ 4d1fed8e4367e6c4ea276fcf6b9b57159de72014`
**Решение:** `ACCEPTED`

## Что принято

G5 фиксирует canonical World Feature Graph над representation cells и LOD.

```text
Feature != Chunk
Feature != SurfaceCell
LOD != Feature Identity
```

Приняты контракты:

```text
FeatureType
FeatureId
FeatureBounds
FeatureAnchor
FeatureRelation
FeatureQuery
WorldFeature
FeatureGraph
```

`FeatureId` детерминированно зависит от canonical procedural identity:

```text
body_id
feature_type
seed
generator_version
stable_key
```

и не зависит от cell/face/LOD/camera/renderer/query order.

## Критическая representation-проверка

Fixture `seam_fault` пересекает cube-sphere seam `PX/PZ` и проверяется на LOD 2/4/8/12.

На каждом уровне подтверждено:

```text
multiple SurfaceCellKey addresses  PASS
both PX and PZ faces               PASS
representation cell set changes    PASS
canonical FeatureId unchanged      PASS
graph manifest unchanged           PASS
```

Это закрепляет `SurfaceCellKey` как representation address, а `WorldFeature` как canonical world semantics.

## Surface-neutral semantics

Acceptance охватывает:

```text
surface fault
surface valley
river relation to valley
subsurface cave system
free-space floating island
```

Feature Graph не привязан только к radial surface и остаётся применим к пещерам, floating islands, астероидам и другим свободным spatial structures.

## Exact-engine focused evidence

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
cold editor import                 PASS
G5 World Feature Graph             PASS — 249 assertions
G5 feature/cell identity           PASS — 94 assertions
G5 visual lab headless             PASS — 4 features
```

## Real Windows full-checkout acceptance

User-provided run of:

```powershell
.\RUN_G5_FULL_ACCEPTANCE.ps1
```

completed with:

```text
full world/core regression         PASS
Breakpoint runtime :9081 noise     0
git diff hygiene/freeze            PASS
G5 full acceptance gate            PASS
```

The regression tail also confirms representative compatibility suites including inventory, unified runtime, NX2/NX5/NX6, MW0–MW10 and RL0–RL3.

Non-blocking log output observed during the green regression is classified precisely:

```text
persistence_roundtrip manifest mismatch
    intentional identity-rejection negative path; suite PASS

world_switch / world_boot_matrix manifest mismatch
    stale/incompatible user://worlds/moon-experiment-001 test-profile manifest;
    suites PASS and G5 does not modify persistence; cleanup/debt, not G5 blocker

NX5 conflicting/stale snapshot
    expected rejection warnings; suite PASS

MW7 ObjectDB/ResourceCache exit
    existing leak warning debt; suite PASS
```

No Breakpoint runtime `:9081` collision noise was observed.

## Architecture decision

G5 is accepted as the canonical feature identity foundation for subsequent geography stages.

Spatial query v0 intentionally remains correctness-first O(N) over `SPHERE` / `AABB` bounds. Future BVH/octree/spatial-hash indexes may optimize lookup without changing canonical identity, graph manifest semantics or query semantics.

## Base-branch note

After the accepted G5 code candidate was validated, `feature/g4-provider-composition-replacement` advanced by three documentation-only commits containing procedural asset research and the post-baseline detail plan. Those documents were carried forward into G5. They do not change G4/G5 runtime contracts or invalidate the exact accepted code candidate.

## Next

Blocking GEO stage is now:

```text
G6 — Hydrology / Fluid Surface v0
```

G6 must build river/fluid geography using stable G5 feature identity rather than chunk-local or LOD-local identities.
