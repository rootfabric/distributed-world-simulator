# RL1 — Matter Summary Pyramid and Dirty Propagation

## Статус

```text
checkpoint: v17.10.0-simulation-rl1-matter-summary-pyramid
build_id:   rl1-matter-summary-pyramid-dirty-propagation
base:       v17.9.0-simulation-rl0-representation-contracts-fix1
branch:     feature/rl1-matter-summary-pyramid
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

RL1 добавляет первый реальный производный слой между каноническими `MatterBrickSnapshot` и будущими RL2 meshes. Summary не является состоянием вещества: его можно удалить, перестроить, перенести как cache или признать stale без изменения массы, geometry channels, mutation journal и authority.

## 1. Региональная граница

Один `MatterSummaryPyramid` обслуживает один MW8 authority-region:

```text
(region_root_address, body_id, RepresentationSourceRevision)
```

Pyramid хранит полный региональный `RepresentationSourceRevision` frontier (`authority_epoch`, номер revision, `source_hash`, `dependency_hash`, checksum) и не смешивает summaries разных authority epochs. Mutation распространяет dirty-state от изменённой ячейки к `region_root_address`. Handoff переводит весь загруженный subtree региона на новую epoch. Межрегиональная агрегация и proxy, требующие согласованного distributed frontier, остаются заблокированы до MW9/MW10.

## 2. Summary node

`MatterSummaryNode` хранит:

- точный `body_id`, `cell_address`, `scope_id` и cell bounds;
- `authority_epoch`, `summary_revision`, `build_generation`;
- число прямых детей, leaf bricks и samples;
- minimum/maximum signed distance;
- minimum/maximum occupancy;
- occupied и surface sample counts;
- признаки matter, vacuum и surface;
- отсортированные material occupancy weights;
- minimum/maximum descendant revision;
- immediate `dependency_hash`;
- transitive `descendant_revision_hash`;
- checksum.

`summary_revision` является frontier, до которого summary построен, и не может быть меньше максимальной descendant revision. Повтор того же checksum на той же revision идемпотентен. Другой checksum на той же revision отклоняется как same-revision mutation.

## 3. Leaf summary

`MatterSummaryBuilder.from_brick_snapshot()` читает только канонические snapshot channels:

```text
signed_distance_m
occupancy_ratio
palette + palette_indices
state_revision
snapshot checksum
```

Материальный вес вычисляется детерминированно:

```text
occupancy_weight(material) =
    Σ sample.occupancy_ratio × composition.mass_fraction(material)
```

Это не масса и не volume integral. Это дешёвая summary-мера присутствия материала, пригодная для LOD planning и последующей coarse SDF/material aggregation. Точная масса остаётся в канонических MW0–MW5 механизмах.

Leaf dependency связывается с точными:

```text
snapshot_id
authority_epoch
state_revision
snapshot checksum
```

## 4. Parent summary

Parent строится только из прямых octree-детей. Builder:

- канонически сортирует детей по `cell_id`;
- запрещает duplicate child;
- запрещает non-direct child;
- запрещает смешение body и authority epoch;
- суммирует counts и material weights;
- объединяет min/max SDF и occupancy;
- вычисляет RL0 `RepresentationDependencySet` по immediate children;
- вычисляет transitive descendant hash по child summary hashes.

Порядок прихода детей не влияет на результат.

## 5. Dirty propagation

### Mutation

```text
changed leaf
  → direct parent
  → ...
  → authority region root
```

Соседние branches не инвалидируются. Старый summary остаётся доступен через `get_summary()` как stale данные, но `get_ready_summary()` не возвращает dirty node.

### Handoff

Handoff инвалидирует:

- все загруженные summaries внутри региона;
- все отсутствующие промежуточные ancestors между ними и region root;
- сам region root.

После атомарной постановки задач pyramid принимает новый source frontier, а при handoff — также новую authority epoch. Если очередь не вместила весь набор, epoch и dirty-state не изменяются.

## 6. Bounded rebuild queue

`MatterSummaryRebuildQueue` имеет фиксированную capacity и атомарный batch enqueue. При переполнении не добавляется ни одна задача.

Порядок обработки:

```text
более глубокий level первым
→ меньшая enqueue revision
→ canonical cell_id
```

Это обеспечивает leaf-to-root rebuild. Повторные события одной ячейки coalesce:

- previous source frontier обязан точно совпадать с текущим frontier pyramid;
- frontier не может откатываться или повторно использоваться;
- dirty bounds объединяются;
- ранняя enqueue revision сохраняется для fairness;
- authority epoch advance допускается только без revision rollback.

## 7. Persistence manifest

`MatterSummaryPersistenceManifest` не делает summary каноническим. Он описывает content-addressed blobs:

```text
summary/<summary SHA-256>
```

Manifest хранит полный RL0 `RepresentationSourceRevision`, а каждая entry содержит полный `cell_address`, scope, authority epoch, локальную summary/build revision, dependency и descendant hashes. Поэтому неизменённый дочерний summary старой revision может безопасно сосуществовать с перестроенными ancestors новой revision, оставаясь частью доказанного ready-набора текущего frontier. Validator доказывает:

- принадлежность body и authority-region;
- точное соответствие `cell_id`, `summary_id`, `scope_id` и level;
- canonical sorting и uniqueness;
- наличие region root;
- content-addressed storage key;
- checksum всего manifest.

Dirty nodes и root старой authority epoch не экспортируются как готовый persistence manifest.

## 8. Граница этапа

RL1 не создаёт:

- coarse SDF samples;
- ArrayMesh, collision, transition cells;
- сетевую доставку summary/artifacts;
- durable authority directory;
- cross-region transaction;
- background worker threads;
- Construction HLOD;
- изменения production Moon или world catalog.

Следующий этап общей дорожной карты — MW9 durable distributed handoff and crash recovery. RL2 начнёт meshing только после MW9/MW10.
