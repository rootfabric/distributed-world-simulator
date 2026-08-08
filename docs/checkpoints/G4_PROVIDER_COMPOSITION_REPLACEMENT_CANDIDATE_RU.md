# G4 — Provider Composition / Replacement — candidate

**Дата:** 2026-08-08
**Ветка:** `feature/g4-provider-composition-replacement`
**Base:** `docs/universal-world-generation-roadmap-post-g3 @ 21d325ccaa60c43d9f0ffdf927f8e2a8b84e2b96`
**G3 accepted head:** `bc58f650ffb43775667bf0d07cb361a98a40d294`
**Статус:** `IMPLEMENTED CANDIDATE`

## Цель

Доказать новый post-G3 критерий Universal World Generation Fabric:

```text
world surface = recipe-driven provider graph
```

а не hardcoded planet class или один monolithic terrain provider.

## G4 composition chain

```text
BaseSurfaceProviderV1
   provides geo/base-surface-height-m
        |
        v
CasualMacroTerrainLayerProviderV1
        OR
AlternativeMacroTerrainProviderV1
   provides geo/macro-surface-height-m
        |
        v
CasualValleyModifierProviderV1
   provides geo/surface-height-m
```

`CasualMacroTerrainLayerProviderV1` является adapter вокруг принятого G3 `CasualMacroTerrainProviderV1`. Сам G3 provider не изменяется.

`CasualValleyModifierProviderV1` пока deliberately analytic: continuous great-circle valley carve. Его задача — доказать downstream modifier composition до появления настоящего `WorldFeature` в G5.

## Recipe-driven runtime

Добавлены generic:

```text
GeoProviderRegistry
GeoRecipeComposer
```

`GeoProviderRegistry` хранит provider factories по canonical provider id.

`GeoRecipeComposer`:

```text
PlanetRecipe
  -> descriptors in canonical order
  -> instantiate through registry
  -> GeoKernel.configure(...)
```

Он не импортирует concrete terrain providers и не знает о Earth/Moon/Asteroid/Floating Island, `SurfaceCellKey`, LOD, Mesh или Camera.

Конкретные surface factories собраны отдельно в `G4SurfaceProviderCatalog`.

## Replacement proof

Один registry заранее знает оба macro backend:

```text
CasualMacroTerrainLayerProviderV1
AlternativeMacroTerrainProviderV1
```

Caller остаётся тем же:

```text
composer.configure_kernel(kernel, definition, recipe, registry)
kernel.sample_surface(context, query[geo/surface-height-m])
```

Меняется только `PlanetRecipe`.

Repeated cycle:

```text
Casual -> Alternative -> Casual -> Alternative
```

Для каждого recipe повторно воспроизводятся тот же provider manifest hash и тот же exact 81-point geography profile; между разными recipes hash и geography различаются.

## Existing graph validation reused

G4 намеренно не переносит validation в новый monolith. `GeoKernel` уже проверяет:

```text
missing required field/capability
cycle
duplicate field ownership
non-deterministic provider
descriptor mismatch
```

G4 composer только создаёт implementations из recipe и передаёт graph существующему validator.

Дополнительно registry запрещает duplicate factory id, unregistered provider и factory, возвращающий descriptor, отличный от указанного в recipe.

## Exact-engine isolated evidence

Engine:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
```

Result:

```text
cold editor import:             PASS
G4 provider composition:        PASS — 232 assertions
G4 provider replacement:        PASS — 341 assertions
G4 visual lab headless:         PASS
G3 macro regression:            PASS — 14,275 assertions
G3 fly-in regression:           PASS — 99 assertions
```

## M5 graphical regression blocker closure

Во время full-checkout validation обнаружилась гонка только в M5 acceptance orchestration: первый клиент после совпадения checksum успевал выполнить graceful leave, `PLAYER_LEFT` менял authoritative player snapshot и второй клиент откатывался обратно в `READY_TO_CONVERGE`.

Harness-only fix:

```text
f39aba61913d10fc13ad82ac601ee5c867c00791
4581c012b4f4290f0f1d3466879aac95a1e1fd3f
```

Добавлен финальный двухфазный convergence barrier:

```text
CONVERGENCE_LOCKED
  -> FINAL_CONVERGENCE_LOCKED on both clients
  -> graceful leave
  -> COMPLETE
```

Production gameplay/network authority semantics не менялись.

Реальный Windows multi-process прогон на exact engine после fix:

```text
M5 graphical acceptance contracts:      PASS — 80 assertions
M5 preparation:                         PASS — 65 assertions
M5 graphical multiplayer:               PASS — 92 assertions, 0 failures
M4 canonical shared gameplay:           PASS — 26 assertions
M4 networked playground extension:      PASS — 23 assertions
M4 graphical shared gameplay:           PASS — 22 assertions
M3 graphical multiplayer contracts:     PASS — 77 assertions
Inventory interaction profiles:         PASS — 86 assertions
7 Days inventory interface:             PASS — 140 assertions
Item stack transfers:                   PASS — 74 assertions
Inventory UI-I0:                        PASS — 44 assertions
Inventory UI-I1:                        PASS — 73 assertions
Inventory UI-I2:                        PASS — 55 assertions
A2 networked gameplay audit:            PASS — 170 assertions
Post-A2 roadmap audit:                  PASS — 138 assertions
M5 focused aggregate:                   PASS — 15/15
```

Critical multi-process evidence:

```text
A reconnect convergence                 PASS
B convergence                           PASS
identical player + Item Graph checksums PASS
A reconnect completed                   PASS
B completed                             PASS
server joins                            3
server graceful leaves                  3
stale peers                             0
client ObjectDB leaks                   0
client resource leaks                   0
client MCP port collisions              0
```

Поскольку historical test orchestration расположен в `scripts/runtime/networked_gameplay/m5`, G4 full gate разрешает ровно один этот acceptance-harness path. Любые другие изменения `scripts/runtime/*`, `scripts/network/*`, Matter или production world scenes остаются запрещены.

## Visual lab

```text
res://scenes/labs/procedural/g4_provider_replacement_lab.tscn
```

Controls:

```text
M     swap Casual / Alternative recipe
W/S   altitude
A/D   longitude
Q/E   latitude
```

Renderer всегда запрашивает только `geo/surface-height-m`. При `M` заменяется recipe/kernel composition; mesh caller и G2 LOD code не меняются.

## Architecture freeze

G4 full runner запрещает изменения:

```text
GeoKernel
SurfaceCellKey
CubeSphereAddressing
SurfaceLodSelector
accepted G3 CasualMacroTerrainProviderV1
```

а также production runtime/network/Matter/world scenes. Единственное точечное исключение — уже отдельно проверенный M5 graphical acceptance driver, который является test orchestration, а не production authority path.

## Full checkout gate

```powershell
.\RUN_G4_FULL_ACCEPTANCE.ps1
```

Required:

```text
G3 focused dependency PASS
G4 focused PASS
world/core regression PASS
Breakpoint :9081 current-run audit PASS
git diff --check PASS
architecture freeze PASS
production/runtime/network/Matter freeze PASS
```

M5 focused blocker закрыт реальным Windows multi-process прогоном. До подтверждения полного `RUN_G4_FULL_ACCEPTANCE.ps1` G4 остаётся `IMPLEMENTED CANDIDATE`.

## Architecture Review A

После green G4 нужно отдельно подтвердить:

```text
replacement requires recipe/config only
no world-type special case in GeoKernel
final semantic caller field stable
provider graph/provenance deterministic
```

Только после этого основной blocking track переходит в `G5 — World Feature Graph`.

Одновременно разрешается открыть параллельные:

```text
GR0 — Surface Representation Lab
GE0 — Environment Field Contracts
```
