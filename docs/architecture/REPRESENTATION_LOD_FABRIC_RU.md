# Representation LOD Fabric — обобщённые представления Matter и Construction

**Статус:** целевая сквозная архитектура; RL0–RL2, MW9 fix3 и MW10 accepted; RL3 implementation candidate.
**Принятая база Matter:** `v17.13.0-simulation-rl2-matter-multiresolution-meshing`.
**Связанные ветки:** Dynamic Matter Fabric MW0–MW8 и Construction C13/C18.
**ADR:** `docs/architecture/adr/ADR-018-representation-lod-fabric.md`.
**Главное правило:** mesh, impostor, collision proxy и summary не являются каноническим состоянием мира.

## 1. Задача

Изменённая порода или крупная конструкция должна быть заметна издалека, но клиент не должен получать и материализовать всю локальную детализацию.

Пример изменяемой породы:

```text
далеко      → body proxy с заметной крупной выемкой
средне      → macro-region meshes
ближе       → coarse volumetric regional mesh
рядом       → детальные MW3 bricks
у контакта  → детальные bricks + collision + interior
```

Пример станции из 10 000 частей:

```text
далеко      → один silhouette/impostor
средне      → несколько section proxies
ближе       → cluster meshes
внутри      → полные parts, devices, collision и interaction
```

Система не должна создавать две несовместимые LOD-архитектуры. Matter и Construction используют разные builders, но один lifecycle контрактов, selection, cache, invalidation и network manifests.

## 2. Что уже реализовано

### Matter

MW3 уже отделяет канонический `MatterBrickSnapshot` от производных `ArrayMesh`, collision и `Node3D`. Локальный streamer строит и удаляет meshes без изменения world state. MW7 доставляет только persistent bricks области интереса, а MW8 переносит authority между региональными серверами.

Реализованы RL1 summary pyramid, принятый RL2 с coarse SDF fields, LOD0–LOD2 meshes, content-addressed artifacts и cross-level skirt transitions, а также текущий RL3 candidate с representation-aware progressive network streaming. Пока отсутствуют:

- body-scale impostors;
- shared cache/background scheduler;
- production-world integration.

### Construction

Ветка C18 уже определяет activity levels и логические LOD tiers:

```text
DORMANT / SUMMARY / SIMULATED / PRESENTED
NONE / IMPOSTOR / SIMPLIFIED / FULL
```

Но текущий adapter выбирает tier и flags, а реальный HLOD backend — mesh clustering, merge, decimation и impostor generation — ещё не является доказанной production-реализацией.

## 3. Трёхслойная модель

```text
каноническое состояние
        ↓
иерархические summaries
        ↓
presentation artifacts
```

### 3.1. Каноническое состояние

Matter:

- sparse persistent bricks;
- SDF и material channels;
- state revisions;
- mutation journal;
- mass ledger.

Construction:

- `ConstructSnapshot`;
- parts и bonds;
- geometry parameters;
- damage, utilities и behavior state.

Каноническое состояние не заменяется объединённым mesh.

### 3.2. Summary hierarchy

RL1 реализует эту hierarchy внутри одного MW8 authority-region и хранит полный RL0 `RepresentationSourceRevision` frontier. Межрегиональная parent aggregation остаётся fenced до MW9/MW10. Подробный runtime-контракт: `RL1_MATTER_SUMMARY_PYRAMID_RU.md`.

Каждый summary node описывает область и зависимости:

- source identity и authority epoch;
- source revision/hash;
- dependency hash дочерних revisions;
- bounds;
- geometric error;
- occupancy/surface/material summary для Matter;
- bounds/mass/structure/capabilities для Construction;
- dirty/build generation.

### 3.3. Presentation artifacts

Artifacts являются content-addressed cache:

```text
DETAIL
SIMPLIFIED_MESH
MACRO_PROXY
IMPOSTOR
NONE
```

Artifact можно удалить, передать другому серверу, повторно скачать или перестроить. Его потеря не изменяет мир.

## 4. Иерархическая инвалидация

После mutation запрещено перестраивать всё тело.

```text
изменённый brick/part
    ↓ dirty
локальный cluster
    ↓ dirty
regional/section proxy
    ↓ dirty
body/construct proxy
```

Каждый parent хранит `dependency_hash`, вычисленный из отсортированных child source revisions. Изменение одного child инвалидирует только цепочку предков.

Старый artifact может временно оставаться видимым как `STALE`, пока строится новый. Однако canonical queries и close collision используют новую authoritative revision.

## 5. Screen-space selection

Выбор LOD не привязывается только к расстоянию. Базовый показатель:

```text
screen_error_px = geometric_error_m × projection_scale_px / distance_m
```

Selection учитывает одновременно:

- maximum screen error;
- maximum geometric error;
- collision requirement;
- interior requirement;
- bandwidth budget;
- preferred artifact kinds;
- точную source revision.

Среди подходящих вариантов выбирается самый грубый, чтобы не загружать лишнюю детализацию.

## 6. Matter representation pipeline

```text
persistent detail bricks
        ↓ deterministic aggregation
coarse SDF / occupancy / material summary
        ↓ meshing
regional mesh
        ↓ aggregation
macro proxy
        ↓ optional rasterization
impostor
```

### Дальняя поверхность

Для кратеров, траншей и насыпей допускается дешёвый deformation patch поверх procedural far surface:

- radial displacement;
- normal/depth map;
- changed-material mask.

Он не заменяет coarse volumetric mesh, потому что не умеет представлять тоннели, навесы, сквозные отверстия и изменение силуэта.

### Межуровневые границы

MW3 гарантирует seams только между bricks одного уровня. RL2 добавляет versioned transition representation `FINE_BOUNDARY_SKIRT_V1`:

- соседние requests балансируются до разницы не более одного LOD;
- fine boundary segments канонизируются и экструдируются в coarse scope;
- transition является отдельным content-addressed artifact;
- transition не участвует в collision;
- будущий Transvoxel-подобный backend может быть добавлен новым variant без изменения canonical Matter.

Подробный runtime-контракт: `RL2_MATTER_MULTIRESOLUTION_MESHING_RU.md`.

## 7. Construction HLOD pipeline

```text
parts
 ↓ spatial clusters
merged cluster meshes
 ↓ section aggregation
section proxies
 ↓ whole construct aggregation
construct proxy
 ↓ rasterization
impostor
```

Construction builder должен уметь:

- удалять внутренние невидимые грани;
- объединять одинаковые материалы;
- уменьшать vertices и draw calls;
- сохранять silhouette;
- создавать simplified collision;
- сохранять semantic anchors отдельно от mesh;
- локально перестраивать только затронутый cluster и его предков.

Matter и Construction не используют один mesher. Они используют общие contracts и scheduler boundaries.

## 8. Network integration

RL3 делает MW7 interest representation-aware, не меняя канонический MW7 replication stream. Adapter создаёт stream request с:

- точным `RepresentationSourceRevision`;
- ordered `LOD -> exact scope_id` chain;
- screen/geometric error budgets;
- collision/interior flags;
- client cache hashes и supported encodings;
- bandwidth, chunk, in-flight и memory budgets;
- request revision и cancellation generation.

Сервер сначала формирует immutable coarse-to-fine plan:

```text
manifest-only negotiation
        ↓
CACHE_HIT или TRANSFER на каждом stage
        ↓
content-addressed ordered chunks
        ↓
client verification and ACK
        ↓
progressive presentation
```

Cache advertisement не считается доказательством наличия bytes: stage активируется только после точного client ACK. Для transfer клиент проверяет chunk hash, порядок/offset, полный artifact hash и checksum manifest. Replacement request отменяет предыдущий stream того же observer, а RL0 invalidation немедленно снимает stale presentation. Cache bytes сохраняются как переиспользуемые производные данные.

RL3 не сохраняет presentation state, не делает artifact частью canonical Matter, не создаёт shared disk cache и не строит meshes.

Progressive loading:

```text
coarse artifact first
→ finer artifact when ready
→ atomic presentation swap
```

## 9. Authority handoff

MW8 переносит только canonical state и authority. LOD artifacts не входят в обязательный commit.

После handoff target может:

1. принять canonical state;
2. временно использовать старые content-addressed artifacts;
3. проверить source/dependency hashes;
4. перестроить stale cache в фоне;
5. опубликовать новые manifests.

Это сохраняет корректность handoff даже при полном отсутствии proxy cache.

## 10. Контракты RL0

RL0 вводит:

- `RepresentationSourceRevision`;
- `RepresentationKey`;
- `RepresentationDescriptor`;
- `RepresentationArtifactManifest`;
- `RepresentationInterestRequest`;
- `RepresentationCandidate`;
- `RepresentationDependencySet`;
- `RepresentationInvalidation`;
- `RepresentationCacheEntry`;
- deterministic `RepresentationSelector`.

Инварианты:

- source revision binding обязателен;
- artifacts content-addressed через SHA-256;
- LOD 0 — самый детальный, большее значение — более грубое;
- selector выбирает самый грубый допустимый candidate;
- canonical payload не содержит Godot objects;
- Matter и Construction используют одинаковый lifecycle, но разные builders;
- `NONE` не имеет artifact manifest;
- READY cache size обязан совпадать с manifest;
- handoff не делает artifact authoritative.

## 11. Дорожная карта RL

```text
RL0 Unified Representation Contracts
 ↓
RL1 Matter Summary Pyramid and Dirty Propagation
 ↓
RL2 Matter Multiresolution Meshing and Transitions
 ↓
RL3 Representation-aware Network Streaming
 ↓
RL4 Construction HLOD Backend
 ↓
RL5 Shared Cache and Background Build Scheduler
 ↓
RL6 Visual, Network and Scale Acceptance
```

RL0 и RL1 выполняются до промышленного persistence и до интеграции Луны. RL2–RL6 следуют после MW9/MW10, чтобы multiresolution artifacts строились поверх устойчивой distributed authority.

## 12. Критерии конечной приёмки

- крупная mutation астероида видна с дальней дистанции;
- мелкий тоннель не заставляет загружать внутренние detail bricks издалека;
- при приближении coarse proxy последовательно заменяется regional и detail meshes;
- между уровнями нет визуальных и физических щелей;
- изменение одного brick не перестраивает весь body proxy synchronously;
- станция из 10 000 частей издалека имеет bounded draw calls;
- изменение одной части перестраивает только cluster/section/construct ancestor chain;
- клиент не получает detail bytes вне error/capability budget;
- authority handoff не зависит от наличия cache;
- удаление всех artifacts не меняет canonical checksum.
