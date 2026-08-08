# Universal World Generation Fabric — status ledger

**Program foundation:** G0–G3 Procedural Planetary Generation  
**Post-G3 roadmap:** `docs/universal-world-generation-roadmap-post-g3`  
**Current implementation branch:** `feature/g4-provider-composition-replacement`

## Current state

```text
G0 Contracts Freeze                    ACCEPTED
G1 Geodesy + Body Shape                BASELINE
G2 Planetary Surface Cells + LOD       ACCEPTED
G3 Mega Casual Macro Surface           ACCEPTED
G4 Provider Composition / Replacement  IMPLEMENTED CANDIDATE
G5 World Feature Graph                 NEXT AFTER G4 ACCEPTED
```

G4 base:

```text
docs/universal-world-generation-roadmap-post-g3
21d325ccaa60c43d9f0ffdf927f8e2a8b84e2b96
```

G3 accepted head:

```text
bc58f650ffb43775667bf0d07cb361a98a40d294
```

## Strategy after G3

The project now follows the Universal World Generation Fabric roadmap:

```text
new world
  != new engine special-case

new world
  = recipe + providers + features + environment + detail backends
```

Canonical post-G3 documents:

```text
docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md
docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md
docs/procedural/NEXT_AFTER_G3_UNIVERSAL_WORLD_GENERATION_RU.md
```

## G4 implementation

Generic composition runtime:

```text
GeoProviderRegistry
GeoRecipeComposer
```

Surface proof graph:

```text
BaseSurfaceProviderV1
        ↓
CasualMacroTerrainLayerProviderV1
        OR
AlternativeMacroTerrainProviderV1
        ↓
CasualValleyModifierProviderV1
        ↓
geo/surface-height-m
```

The accepted G3 `CasualMacroTerrainProviderV1` is not rewritten. G4 wraps it as a composition layer.

Replacement is recipe-driven. One registry knows both macro providers; caller, `GeoKernel`, G2 addressing/LOD and final query field stay unchanged.

## Exact-engine evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
cold editor import                 PASS
G4 provider composition            PASS — 232 assertions
G4 repeated provider replacement   PASS — 341 assertions
G4 visual lab headless             PASS
G3 macro regression                PASS — 14,275 assertions
G3 fly-in regression               PASS — 99 assertions
```

Repeated replacement cycle:

```text
Casual → Alternative → Casual → Alternative
```

For the same recipe, manifest hash and exact 81-point geography profile reproduce. Different recipes produce different provenance and terrain while downstream continues to query only `geo/surface-height-m`.

## G4 visual lab

```text
res://scenes/labs/procedural/g4_provider_replacement_lab.tscn
```

```text
M     swap Casual / Alternative recipe
W/S   altitude
A/D   longitude
Q/E   latitude
```

## G4 full gate

```powershell
.\RUN_G4_FULL_ACCEPTANCE.ps1
```

Required before acceptance:

```text
G3 dependency focused PASS
G4 focused PASS
full world/core regression PASS
Breakpoint :9081 current-run audit PASS
git diff --check vs post-G3 docs base PASS
frozen G0-G3 architecture paths unchanged
production/runtime/network/Matter paths unchanged
```

Until this real-checkout gate is green, G4 remains `IMPLEMENTED CANDIDATE`.

## Next after G4

Blocking main track:

```text
G5 — World Feature Graph
```

After G4 acceptance the roadmap also allows parallel:

```text
GR0 — Surface Representation Lab
GE0 — Environment Field Contracts
```

## Invariants

```text
Generator != Renderer
LOD != World State
Feature != Chunk
recipe != planet class
provider graph != world-type switch
canonical truth != representation
procedural baseline + sparse authoritative mutations = current world truth
```
