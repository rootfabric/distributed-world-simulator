# G5 — World Feature Graph + Spatial Feature Identity — candidate

**Дата:** 2026-08-08
**Ветка:** `feature/g5-world-feature-graph`
**Base:** `feature/g4-provider-composition-replacement @ 4d1fed8e4367e6c4ea276fcf6b9b57159de72014`
**Статус:** `IMPLEMENTED CANDIDATE`

## Цель

G5 вводит canonical identity и graph для пространственных особенностей мира, которые существуют независимо от representation cells, LOD и renderer.

Главный invariant:

```text
Feature != Chunk
Feature != SurfaceCell
LOD != Feature Identity
```

Одна река, долина, разлом, пещерная система или floating island может пересекать любое количество cells и уровней детализации, но остаётся одной canonical feature.

## Контракты

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

Schemas:

```text
planet_simulator.feature_bounds.v1
planet_simulator.feature_anchor.v1
planet_simulator.feature_relation.v1
planet_simulator.feature_query.v1
planet_simulator.world_feature.v1
planet_simulator.feature_graph_manifest.v1
```

## Feature identity

`FeatureId` детерминированно выводится только из canonical procedural identity:

```text
body_id
feature_type
seed
generator_version
stable_key
```

Результат:

```text
world-feature/<type>/<sha256>
```

В identity намеренно отсутствуют:

```text
SurfaceCellKey
face
LOD
x / y
camera
query order
renderer
streaming state
```

Изменение representation не может создать новую feature.

`generator_version` является частью identity: изменение генератора, способное изменить canonical feature population, создаёт новую procedural identity вместо скрытого переопределения старой.

## WorldFeature

Canonical DTO хранит:

```text
feature_id
body_id
feature_type
seed
generator_version
stable_key
frame_id
bounds
anchors[]
parent_feature_id optional
relations[]
attributes
checksum
```

Anchors и relations canonicalized/sorted перед checksum.

Feature graph surface-neutral. G5 acceptance содержит:

```text
surface fault
surface valley
river related to valley
subsurface cave system
free-space floating island
```

То есть feature не обязана лежать на radial surface.

## Bounds and spatial query v0

G5 фиксирует correctness-first broad phase:

```text
SPHERE
AABB
```

`FeatureQuery` задаёт body/frame, center/radius и optional feature type filter.

`FeatureGraph.query()` в v0 проходит canonical feature set O(N). Это сознательно не является performance architecture.

Позже можно добавить:

```text
BVH
octree
spatial hash
hierarchical feature index
server interest index
```

без изменения `FeatureId`, `WorldFeature`, query semantics или graph manifest semantics.

## Graph semantics

`FeatureGraph`:

```text
configure(body_id, frame_id)
add_feature(...)
seal()
query(...)
get_feature(...)
children_of(...)
related_features(...)
```

`seal()`:

```text
sorts feature IDs canonically
validates parent targets
validates relation targets
rejects parent cycles
computes deterministic graph manifest hash
```

Insertion order не влияет на manifest hash.

## Relations and hierarchy

G5 разделяет два понятия:

```text
parent_feature_id
    structural hierarchy

FeatureRelation
    semantic directed relation
```

Acceptance пример:

```text
River
  parent -> Valley
  relation feature-relation/flows-through -> Valley
```

G6 сможет поверх этого ввести river/channel/fluid semantics, не меняя базовый graph contract.

## Critical representation gate

Fixture `seam_fault` проходит через cube-sphere seam `PX/PZ`.

Проверяются LOD:

```text
2
4
8
12
```

На каждом уровне:

```text
feature spans multiple SurfaceCellKey values
feature touches both PX and PZ faces
cell set changes with LOD
FeatureId remains identical
graph manifest remains identical
```

Это прямое доказательство:

```text
SurfaceCellKey = representation address
WorldFeature = canonical world semantics
```

## Renderer / runtime boundary

Core G5 запрещает зависимости от:

```text
Node / SceneTree
MeshInstance3D / ArrayMesh / ImmediateMesh
RenderingServer
SurfaceCellKey
SurfaceLodSelector
Camera3D
MultiplayerPeer
RandomNumberGenerator / rand*
GeoKernel.new()
```

Visualization живёт только в lab.

## Exact-engine isolated evidence

Engine:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
```

Result:

```text
cold editor import                 PASS
G5 World Feature Graph             PASS — 249 assertions
G5 feature/cell identity           PASS — 94 assertions
G5 visual lab headless             PASS — 4 features
```

Lab manifest prefix в isolated run:

```text
99a8465b3b54
```

Focused wrapper:

```powershell
.\RUN_G5_WORLD_FEATURE_GRAPH_TESTS.ps1
```

## Visual lab

```text
res://scenes/labs/procedural/g5_world_feature_graph_lab.tscn
```

Lab показывает fault, valley, river relation и subsurface cave на одной схематичной body representation.

Controls:

```text
A / D   rotate
Space   pause/resume
```

Lab — presentation proof, не источник canonical semantics.

## Full checkout gate

```powershell
.\RUN_G5_FULL_ACCEPTANCE.ps1
```

Required before acceptance:

```text
G4 accepted dependency focused PASS
G5 focused PASS
full world/core regression PASS
Breakpoint :9081 current-run audit PASS
git diff --check vs G4 accepted branch PASS
frozen G0-G4 architecture paths unchanged
production/runtime/network/Matter/world paths unchanged
```

До реального Windows full-checkout прогона G5 остаётся `IMPLEMENTED CANDIDATE`.

## Следующий blocking stage

После G5 acceptance:

```text
G6 — Hydrology / Fluid Surface v0
```

G6 должен использовать G5 feature identity для `RiverFeature`, а не создавать river identity из chunks/cells.
