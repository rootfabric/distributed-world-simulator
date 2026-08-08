# G6.1 — CasualRiverProviderV1 — ACCEPTED

**Дата:** 2026-08-08
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Tested head:** `b8f36d17dc8ba138e6b215968aa0e651eec9ccd1`
**Dependency:** `G6.0 Fluid Contracts — ACCEPTED after P0 sync`
**Решение:** `ACCEPTED`

## Что принято

G6.1 вводит deterministic `CasualRiverProviderV1`, который компилирует уже существующую G5 river semantic identity в принятые G6.0 fluid geography contracts:

```text
G5 WorldFeature(feature-type/river)
        + optional linked valley
        ↓
CasualRiverProviderV1
        ↓
FluidRegionId
RiverSpline
RiverChannelProfile
FluidSurfaceDescriptor
```

Канонический semantic owner остаётся G5 `FeatureId`. Provider не создаёт второй `WorldFeature`, не пишет в `FeatureGraph` и не владеет authority, persistence, network transport или renderer state.

## Exact Windows evidence

Пользователь выполнил приёмочный прогон из clean synced worktree на:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
branch head: b8f36d17dc8ba138e6b215968aa0e651eec9ccd1
working tree: clean
git diff --check 116c1ec...HEAD: PASS
```

Focused runner:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_1_CASUAL_RIVER_PROVIDER_TESTS.ps1
```

Observed result:

```text
G5 World Feature Graph: PASS (249 assertions)
G5 feature/cell identity: PASS (94 assertions)
G6.0 fluid contracts: PASS (169 assertions)
G6.0 fluid contracts focused gate passed.
G6.1 CasualRiverProviderV1: PASS (74 assertions)
G6.1 CasualRiverProviderV1 focused gate passed.
```

No editor import failure was observed. Breakpoint MCP enabled/listened on `127.0.0.1:9080` during editor import and disabled normally afterward.

## Accepted invariants

```text
G5 River FeatureId remains semantic owner
FluidRegionId != SurfaceCell
FluidRegionId != LOD
RiverSpline.spline_id != LOD/camera/query order
geometry revision may change checksum without rerolling identity
linked valley may influence geometry without owning river identity
provider is deterministic and versioned
provider has no renderer/SceneTree dependency
provider has no runtime RNG dependency
provider has no network/authority/persistence ownership
```

The focused suite also covers repeated compile determinism, unrelated-call order independence, geometry changes without semantic identity reroll, valley influence, explicit non-water fluid projection, invalid-source rejection, and source-boundary checks.

## Scope discipline

G6.1 acceptance does not imply acceptance of later runtime/presentation stages. Deliberately deferred:

```text
G6.2 cross-cell / cross-LOD continuity
G6.3 runtime WaterSurfaceQuery resolver
G6.4 casual visual river lab
full CFD / erosion / sediment transport
authoritative Matter/fluid mutation
```

The full world/core regression remains reserved for the composed G6.1–G6.4 final G6 acceptance unless an intermediate stage modifies shared accepted runtime/contracts.

## Next

```text
G6.2 — Cross-Cell / Cross-LOD River Continuity
```

G6.2 must prove that one canonical river crosses changing G2 cube-sphere representation cells/faces and multiple LOD levels while retaining stable:

```text
G5 FeatureId
FluidRegionId
RiverSpline.spline_id
RiverChannelProfile.profile_id
canonical provider result identity
```

`SurfaceCellKey` may be used only as representation addressing for the continuity proof; it must not become river/fluid identity.
