# G4 — Provider Composition / Replacement — ACCEPTED

**Дата:** 2026-08-08
**Ветка:** `feature/g4-provider-composition-replacement`
**Base:** `docs/universal-world-generation-roadmap-post-g3 @ 21d325ccaa60c43d9f0ffdf927f8e2a8b84e2b96`
**G3 accepted head:** `bc58f650ffb43775667bf0d07cb361a98a40d294`
**Decision:** `ACCEPTED`

## Acceptance evidence

Пользователь выполнил реальный Windows full-checkout gate на exact double-precision engine:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
```

Подтверждено:

```text
G3 dependency focused gate              PASS
G4 provider composition / replacement   PASS
full world/core regression              PASS
Breakpoint runtime :9081 collision      0
git diff hygiene                        PASS after docs-only whitespace cleanup
G0-G3 frozen architecture paths         PASS
production/runtime/network/Matter freeze PASS
Architecture Review A                   PASS
```

Полный regression дошёл до финала и подтвердил, в частности:

```text
Persistent world integration            PASS
Terrain streaming contract              PASS
Item domain / inventory suites          PASS
Unified planetary runtime / boot        PASS
World switch during generation          PASS
World boot matrix                        PASS
NX2 / NX5 / NX6                          PASS
MW0-MW10                                 PASS
RL0-RL3                                  PASS
main scene CLI                           6/6 PASS
```

Негативные `World manifest identity mismatch`, `CONFLICTING_REMOTE_SNAPSHOT_TICK` и `STALE_REMOTE_AUTHORITY_EPOCH` относятся к проверяемым rejection/error paths; соответствующие suites завершились `PASS`.

MW7 по-прежнему печатает существующий exit cleanup debt (`ObjectDB` / `ResourceCache` warnings), но сам MW7 suite завершился `PASS` и G4 production semantics его не меняют.

## Hygiene closure

Первый полный wrapper остановился только на `git diff --check` из-за Markdown trailing whitespace в:

```text
docs/checkpoints/G3_CASUAL_MACRO_SURFACE_ACCEPTED_RU.md
docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_CANDIDATE_RU.md
docs/procedural/STATUS_RU.md
```

Это был docs-only blocker. Все перечисленные trailing spaces удалены отдельными docs-only commits; функциональный regression повторно не требуется.

## Architecture freeze reconstruction

Changed-file set против post-G3 base не содержит изменений в frozen paths:

```text
scripts/simulation/procedural/geo_kernel.gd
scripts/simulation/procedural/contracts/surface_cell_key.gd
scripts/simulation/procedural/surface/cube_sphere_addressing.gd
scripts/simulation/procedural/surface/surface_lod_selector.gd
scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd
```

Из исторического `scripts/runtime/*` изменён только явно allowlisted acceptance harness:

```text
scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_driver.gd
```

Других production runtime/network/Matter/world-scene изменений в G4 diff нет.

## Architecture Review A

Generic composition boundary подтверждён:

```text
GeoRecipeComposer
  recipe descriptors
      -> GeoProviderRegistry.instantiate(...)
      -> GeoKernel.configure(...)
```

`GeoRecipeComposer` не знает concrete world types, terrain backends, LOD или renderer classes.

Concrete provider factories изолированы в:

```text
G4SurfaceProviderCatalog
```

Replacement остаётся recipe/config-driven:

```text
Casual -> Alternative -> Casual -> Alternative
```

При этом downstream semantic caller остаётся:

```text
geo/surface-height-m
```

Для одинакового recipe воспроизводятся provider manifest hash и geography profile; между разными recipes меняются provenance/geography, а generic caller и kernel boundary остаются прежними.

## Decision

```text
G4 Provider Composition / Replacement  ACCEPTED
Architecture Review A                  PASS
Blocking GEO track                     UNBLOCKED FOR G5
```

Следующий blocking stage:

```text
G5 — World Feature Graph
```

Параллельно roadmap разрешает:

```text
GR0 — Surface Representation Lab
GE0 — Environment Field Contracts
```
