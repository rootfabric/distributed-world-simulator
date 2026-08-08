# High-Resolution Detail Generator — независимый генератор сверхдетальной локальной геометрии

**Статус:** целевая архитектура отдельного параллельного направления.
**Parent architecture:** `PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`.
**Рекомендуемая будущая ветка:** `feature/gh0-high-resolution-detail-generator`.
**Ключевой принцип:** высокодетальная генерация уточняет локальное представление мира, но не получает право молча менять канонический procedural/Matter state.

---

## 1. Зачем выделять отдельный генератор

Сверхдетальный участок берега, скалы или пещеры имеет совсем другой computational profile, чем генерация долины или реки длиной 40 km.

Macro generator решает:

```text
где находится долина
где идёт река
где внешний изгиб
где возникает cliff
какая здесь geology
где находится cave feature
```

High-resolution generator решает:

```text
как конкретно разбита поверхность скалы
где лежат валуны
где видны трещины
как выглядит гравий
какие небольшие промоины есть на берегу
какие material masks нужны на масштабе сантиметров/дециметров
```

Смешивать эти две задачи в одном algorithm/backend не следует.

---

## 2. Организационная цель

После freeze `DetailPatchContext` high-resolution generator должен разрабатываться независимо от основной planetary ветки.

Он должен уметь работать в отдельной лаборатории на зафиксированном input fixture:

```text
DetailPatchContext fixture
        ↓
HighResolutionDetailGenerator
        ↓
DetailPatchArtifact
```

Для теста не требуется запускать:

- целую планету;
- 40 km river;
- network runtime;
- Matter persistence;
- full planetary streamer.

Это позволяет параллельно экспериментировать с algorithms, GPU compute, erosion-like detail, meshing и materials.

---

## 3. Stable input contract

### DetailPatchRequest

Минимально:

```text
patch_id
body_id
body_fixed_center
local_tangent_frame
bounds_local_m
target_resolution_m
max_geometric_error_m
visual_budget
collision_budget
volume_budget
material_budget
required_channels[]
```

### DetailPatchContext

Контекст должен быть полностью data-only и reproducible.

```text
world/body seed domain
provider manifest/version
patch identity
body-fixed transform
local tangent frame
base surface field handle/data
base volume field handle/data
feature envelopes
geology fields
hydrology fields
erosion/deposition fields
material ids/properties
semantic masks
existing canonical delta summary if applicable
```

Важно: generator не должен сам искать RiverFeature через SceneTree или читать active camera.

Всё необходимое приходит через contract.

---

## 4. Stable output contract

### DetailPatchArtifact

Выход является производным artifact и может содержать несколько независимых channels:

```text
geometry artifact
micro displacement field
normal/detail field
material masks
scatter descriptors
rock descriptors
collision candidates
volume refinement candidates
semantic anchors
statistics/provenance
```

Artifact обязан содержать provenance:

```text
patch_id
source_context_hash
generator_id
generator_version
settings_hash
output_hash
```

Если source context изменился, старый artifact считается stale.

---

## 5. Три класса detail

### A. Visual-only detail

Примеры:

```text
millimeter cracks
sand grain structure
micro normal
small color variation
tiny wetness streaks
```

Backend:

```text
normal/material/displacement texture
shader data
decals
micro mesh only where justified
```

Не участвует в gameplay collision и Matter.

### B. Physical local detail

Примеры:

```text
10–50 cm rocks
small ledges
small holes
roots/obstacles
walkable bank cuts
```

Может иметь simplified collision.

Но physical detail всё ещё не обязан становиться persistent Matter truth, если он детерминированно восстанавливается из baseline.

### C. Canonical volumetric detail

Примеры:

```text
проход в пещеру
отверстие, через которое проходит персонаж
тонкий rock bridge
полость, которую можно копать
существенный overhang
```

Такая деталь не должна существовать только в presentation artifact.

Она обязана быть:

```text
частью GeoVolume baseline
```

или быть явно promoted в:

```text
stable WorldFeature / canonical Matter representation
```

---

## 6. Promotion rule

Нужен явный boundary:

```text
DetailArtifact
      │
      ├── visual/collision only → stays derived
      │
      └── simulation/matter relevant
                    ↓
             PromotionRequest
                    ↓
          canonical provider/feature
```

High-resolution generator не может сам изменить authoritative Matter.

Это особенно важно для multiplayer/replay: canonical state не должен зависеть от того, какой GPU или quality profile был у конкретного клиента.

---

## 7. Resolution hierarchy

Рекомендуемые условные bands:

```text
HR0  100–20 m   structural refinement
HR1   20–5 m    large rocks / cuts / ledges
HR2    5–1 m    local physical detail
HR3    1–0.1 m  gravel / cracks / small geometry
HR4   <0.1 m    material/shader micro detail
```

Они не обязаны совпадать с planetary LOD levels.

Planetary LOD отвечает за spatial representation selection.

HR bands отвечают за local detail generation policy.

---

## 8. Nested deterministic domains

Чтобы detail не прыгал при изменении resolution, randomness строится иерархически.

Нельзя:

```text
seed = hash(camera_position, lod)
```

Нужно:

```text
patch_seed = hash(world_seed, patch_id, generator_domain)
cell_seed = hash(patch_seed, stable_local_cell_id)
feature_seed = hash(cell_seed, feature_class)
```

При повышении resolution:

- крупные валуны сохраняются;
- добавляются более мелкие;
- уже существующие patterns не переролливаются;
- соседние patches согласуют border ownership.

---

## 9. Border ownership

High-resolution patches не должны независимо генерировать разные камни/трещины на общей границе.

Нужен stable ownership rule:

```text
feature anchor belongs to canonical local cell
```

Patch может материализовать feature, если её bounds пересекают patch, но identity/seed принадлежит anchor cell.

Для field outputs применяется deterministic border sampling.

---

## 10. Пример: высокодетальный речной берег

GeoKernel передаёт:

```text
river_distance
river_side
flow_direction
erosion
deposition
slope
rock_hardness
soil_depth
moisture
CliffFeature envelope
```

HR generator создаёт:

```text
outer cliff:
- крупные fracture planes
- ledges
- detached-looking rock forms
- talus anchors
- wet streak masks

inner bank:
- gravel bars
- small channels
- sediment ripples
- drift/debris anchors
```

Алгоритм может стать очень сложным, но RiverProvider ничего о нём не знает.

---

## 11. Пример: cave interior

GeoVolume уже определяет существование cavity.

HR generator только уточняет presentation:

```text
wall roughness
small recesses
fracture detail
loose stones
wetness/mineral masks
small collision detail within budget
```

Он не имеет права закрыть или открыть основной cave passage, если это изменяет topology canonical volume.

---

## 12. Parallel lab

Рекомендуемая отдельная сцена:

```text
high_resolution_detail_lab
```

Размеры fixture:

```text
20×20 m
100×100 m
500×500 m stress case
```

Fixture types:

```text
river_inner_bank
river_outer_cliff
rocky_slope
cave_entrance
cave_interior
flat_gravel_plain
```

Каждый fixture хранит immutable `DetailPatchContext` snapshot и expected semantic hashes.

---

## 13. High-resolution roadmap

### GH0 — Contract + fixture harness

- `DetailPatchRequest`;
- `DetailPatchContext`;
- `DetailPatchArtifact`;
- fixture serialization;
- deterministic hash;
- no visual complexity yet.

Gate:

```text
same fixture → byte/canonical-equivalent descriptors
```

### GH1 — Structural 100 m patch

Простые:

```text
large rock anchors
bank cuts
ledge descriptors
```

Без сантиметровой детализации.

### GH2 — Decimeter physical detail

Добавить:

```text
rocks
small holes
small steps
gravel clusters
```

Проверить collision budget.

### GH3 — Material micro detail

Добавить:

```text
normal maps
roughness variation
wetness
sediment masks
micro displacement
```

### GH4 — Volumetric refinement adapter

Доказать корректное различие:

```text
derived detail
vs
canonical volume refinement
```

Добавить explicit promotion proposal/result contract, но не прямую Matter mutation.

### GH5 — Performance budgets

Проверить:

```text
2 m target
0.5 m target
0.1 m target
0.02 m visual target
```

Собрать:

```text
generation ms
peak RAM
artifact bytes
triangle count
collision count
cache hit latency
```

### GH6 — Main Geo composition

Подключить к `procedural_planet_lab` через тот же `IDetailProvider` contract.

Gate:

> основной GeoKernel не изменяется ради подключения high-resolution backend.

---

## 14. CPU/GPU freedom

Contract специально не определяет implementation backend.

Допустимы:

```text
CPU deterministic generator
GPU compute generator
native GDExtension
hybrid precompute + runtime
```

Но canonical semantic output, где он требуется, должен быть hardware-independent либо иметь строго определённый deterministic path.

GPU-only floating behavior нельзя использовать как единственный источник authoritative topology.

---

## 15. Relation to representation cache

High-resolution artifact — обычный content-addressed representation artifact.

```text
source_context_hash
+
generator/settings hash
→ artifact hash
```

Его можно:

- кешировать на disk;
- пересылать как optimization;
- перестраивать локально;
- удалять при memory pressure.

Его отсутствие не удаляет мир.

---

## 16. Acceptance invariants

High-resolution направление считается архитектурно корректным, если:

```text
[PASS] работает на recorded fixture без планеты
[PASS] не читает camera/SceneTree как источник canonical randomness
[PASS] same context даёт same semantic output
[PASS] соседние patches не создают seam ownership conflicts
[PASS] повышение detail добавляет detail, а не переролливает крупные формы
[PASS] visual detail отделён от canonical volume
[PASS] generator можно выключить полностью
[PASS] выключение HR не меняет gameplay world identity
[PASS] backend можно заменить без изменения GeoKernel
[PASS] cache invalidates on source/version change
```

---

## 17. Долгосрочный запас сложности

После GH6 можно независимо исследовать:

```text
fracture grammars
rock stratification
local hydraulic erosion approximation
sediment microstructure
aeolian detail
ice fracture detail
lava/weathering detail
procedural roots/ground interaction
GPU virtual displacement
nanite-like local clustering ideas
ML-assisted artifact synthesis as visual-only backend
```

Ни одно из этих исследований не должно требовать смены планетарной геодезии, FeatureGraph или базовой hydrology architecture.

---

## 18. Главный критерий

Идеальный результат выглядит так:

```text
30 km altitude
→ GeoKernel показывает valley/river/cliff

500 m
→ regional/local representation уточняет cliff

50 m
→ HighResolution backend добавляет rock structure

5 m
→ появляются physical rocks, ledges, gravel

0.5 m
→ material/micro geometry refinement

centimeters
→ visual micro detail
```

При этом на всех масштабах это **одно и то же место**, определённое одним seed, одним FeatureGraph и одним набором canonical fields.
