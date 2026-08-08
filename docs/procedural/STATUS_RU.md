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
G4 Provider Composition / Replacement  ACCEPTED
G5 World Feature Graph                 NEXT — UNBLOCKED
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

Canonical G4 acceptance record:

```text
docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_ACCEPTED_RU.md
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

## G4 accepted implementation

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
full world/core regression         PASS
Breakpoint :9081 collision noise   0
```

Repeated replacement cycle:

```text
Casual → Alternative → Casual → Alternative
```

For the same recipe, manifest hash and exact 81-point geography profile reproduce. Different recipes produce different provenance and terrain while downstream continues to query only `geo/surface-height-m`.

## M5 regression blocker

The M5 graphical convergence/shutdown race found during real checkout validation is closed.

Harness stabilization commits:

```text
f39aba61913d10fc13ad82ac601ee5c867c00791
4581c012b4f4290f0f1d3466879aac95a1e1fd3f
```

Real Windows exact-engine evidence:

```text
M5 graphical multiplayer           PASS — 92 assertions, 0 failures
M5 focused aggregate               PASS — 15/15
server joins                       3
server graceful leaves             3
server stale peers                 0
A/B final checksum convergence     PASS
A reconnect completion             PASS
B completion                       PASS
client ObjectDB/resource leaks     0
client MCP port collisions         0
```

The fix changes only M5 acceptance orchestration: clients freeze the same final convergence pair before either graceful leave can mutate the authoritative player snapshot. Production gameplay/network authority semantics remain unchanged.

Because this historical acceptance driver lives under `scripts/runtime/networked_gameplay/m5`, `RUN_G4_FULL_ACCEPTANCE.ps1` allowlists exactly that one harness path while preserving the freeze for every other production runtime/network/Matter/world path.

## G4 full gate closure

The real Windows wrapper reached the final hygiene stage with all functional suites green. Its only failure was Markdown trailing whitespace in three docs. Those spaces were removed with docs-only commits.

The changed-file set against `docs/universal-world-generation-roadmap-post-g3` confirms:

```text
frozen G0-G3 architecture paths unchanged    PASS
production world scenes unchanged            PASS
production network/Matter paths unchanged    PASS
only allowlisted M5 acceptance driver changed PASS
```

Architecture Review A confirms:

```text
replacement requires recipe/config only      PASS
no world-type special case in GeoRecipeComposer PASS
final semantic caller field stable           PASS
provider graph/provenance deterministic       PASS
```

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

## Next after G4

Blocking main track:

```text
G5 — World Feature Graph
```

Parallel tracks now allowed by the roadmap:

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
