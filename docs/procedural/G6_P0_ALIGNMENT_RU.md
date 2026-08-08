# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g6-hydrology-fluid-surface-v0`
**Current stage:** `G6 FULL ACCEPTANCE — IMPLEMENTED CANDIDATE / BLOCKED BY SHARED MW10 BASELINE`
**Next after acceptance:** `G7 Semantic Field Fabric`

## Canonical boundary

```text
G5 WorldFeature / FeatureId
        ↓
G6.1 canonical fluid geography
        ↓
G6.3 read-only WaterSurfaceQuery resolver
        ↓
G6.4 derived presentation
```

Required invariants remain:

```text
FeatureId != SurfaceCellKey
FluidRegionId != SurfaceCellKey
LOD != fluid identity
terrain mesh != canonical G3 height field
renderer != authority
renderer != persistence
G5 River FeatureId remains semantic owner
```

G6.4 uses accepted G2/G3 only in representation. The diagnostic Fix4 recipe increases G3 octave count without changing accepted G3 provider code. River-valley carving, erosion and terrain-bank coupling remain deferred to G8 Geomorphology.

## Full acceptance gate

`RUN_G6_FULL_ACCEPTANCE.ps1` requires:

```text
GLOBAL config == main == G5
current G5 ancestor of G6
accepted MW10 shared-baseline blobs in G5 and G6
git diff --check
G6.0-G6.4 focused chain
MW10 lock-release retry fault injection
full world/core regression
clean worktree
```

Current blocker: PR #43 has not yet been integrated into `feature/g5-world-feature-graph`; G6 must not privately absorb that Matter fix.

## Assistant runtime

Project-provided Linux double Godot is verified:

```text
4.7.1.stable.double.custom_build.a13da4feb
headless GDScript smoke: PASS
```

The assistant execution-container still lacks a full repository checkout, so project-level G6 runtime suites are not claimed as run there.

## Merge / composition status

```text
[PASS] GLOBAL-P0-2026-08-08-R1 config alignment
[PASS] Feature != SurfaceCell
[PASS] FluidRegion != SurfaceCell / AuthorityRegion / InterestRegion
[PASS] G6.1 Windows acceptance — 74 assertions
[PASS] G6.2 Windows continuity acceptance — 86 assertions
[PASS] G6.3 Windows runtime query acceptance — 79 assertions
[PASS] G6.4 Fix4 manual graphical observation
[PASS] assistant Linux double Godot engine smoke
[BLOCKED] shared MW10 baseline integration via PR #43
[PENDING] G6 full Windows acceptance after G5 resync
```
