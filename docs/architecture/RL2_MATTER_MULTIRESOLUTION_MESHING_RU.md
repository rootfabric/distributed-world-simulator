# RL2 — Matter Multiresolution Meshing and Cross-level Transitions

## Статус и граница

```text
checkpoint: v17.13.0-simulation-rl2-matter-multiresolution-meshing
build_id:   rl2-matter-multiresolution-meshing-transitions
base:       v17.12.0-simulation-mw10-cross-region-matter-transactions (ACCEPTED)
branch:     feature/rl2-matter-multiresolution-meshing
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

RL2 превращает принятые RL1 summaries и точные `MatterBrickSnapshot` в content-addressed производные mesh artifacts. Канонический Matter, mass ledger, MW10 transaction protocol, MW9 authority directory и production worlds не меняются.

## 1. Пространственная модель LOD

RL2 не выполняет произвольную decimation уже готового детального mesh. Каждый уровень заново семплирует одну и ту же каноническую SDF-истину на более крупном spatial scope:

```text
LOD 0 / DETAIL
  one max-level brick scope
  1 MatterBrickSnapshot

LOD 1 / SIMPLIFIED_MESH
  one parent scope
  8 max-level MatterBrickSnapshot

LOD 2 / MACRO_PROXY
  one grandparent scope
  64 max-level MatterBrickSnapshot
```

Количество lattice cells на сторону остаётся равным `brick_interior_resolution`. Поэтому при переходе на следующий LOD мировой шаг SDF удваивается, а geometric error растёт детерминированно.

```text
geometric_error_m = sample_spacing_m × sqrt(3) / 2
```

Максимальный уровень текущего checkpoint — LOD 2. Более крупные body proxies и impostors остаются последующими этапами.

## 2. Exact source binding

`MatterMeshingSourceSet` связывает build с:

- полным RL0 `RepresentationSourceRevision`;
- checksum RL1 summary;
- authority epoch и revision summary;
- target cell/scope;
- полным канонически отсортированным набором leaf snapshots;
- hash набора snapshot descriptors;
- ожидаемым количеством 1/8/64 источников.

Нельзя построить artifact из:

- неполного набора дочерних bricks;
- повторённого cell;
- другой authority epoch;
- другой summary revision;
- snapshot с другой state revision или checksum;
- summary, не соответствующей целевому spatial scope.

## 3. Multiresolution field

`MatterMultiresolutionFieldBuilder` строит JSON-safe data field:

- exact bounds target scope;
- фиксированную lattice resolution;
- signed-distance samples;
- dominant-material vertex colors;
- source-set и field hashes;
- `RepresentationKey` нужного artifact kind.

На общей границе нескольких source bricks одна и та же мировая lattice-точка может иметь несколько witnesses. Все witnesses обязаны иметь одинаковые SDF и color с жёстким tolerance. Несогласованная граница fail-closed отклоняет весь build.

Это правило не даёт скрыть seam за счёт выбора «первого пришедшего» brick.

## 4. Mesher

Используется детерминированный `FREUDENTHAL_MARCHING_TETRAHEDRA`:

- куб делится на шесть tetrahedra;
- edge vertices переиспользуются по каноническому ключу sample-edge;
- normal вычисляется из центральной/односторонней SDF gradient;
- winding согласуется с outward gradient;
- geometry hash использует квантованные позиции, normals, colors и indices;
- replay при перестановке входных snapshots даёт те же field, vertices, indices и content hash.

Результат `MatterMultiresolutionMeshData` бывает:

```text
EMPTY
READY
```

Artifact manifest использует `content_hash` как `artifact_hash` и хранит bounds, byte estimate, geometric error и capabilities.

## 5. Same-level seams

Два соседних artifacts одного LOD должны иметь одинаковую boundary topology на общей плоскости. `MatterMeshBoundary`:

- определяет shared face;
- извлекает boundary segments;
- канонизирует ориентацию segment endpoints;
- вычисляет segment hash.

Так как соседние поля получают exact shared samples, одинаковый mesher строит одинаковый набор граничных отрезков.

## 6. Cross-level transitions

Текущий backend — `FINE_BOUNDARY_SKIRT_V1`.

Для соседней пары `fine LOD N` и `coarse LOD N+1` builder:

1. находит общую face;
2. извлекает канонические boundary segments fine mesh;
3. экструдирует каждый segment в сторону coarse region;
4. создаёт двухстороннюю четырёхтреугольную ленту;
5. связывает transition с exact fine/coarse representation keys;
6. вычисляет content hash и отдельный artifact manifest.

Глубина:

```text
skirt_depth_m = max(coarse.sample_spacing_m, coarse.geometric_error_m)
```

Transition хранится и материализуется отдельно от canonical surface mesh. Он не collision-capable. Collision остаётся только на согласованном detail artifact.

Это доказанный crack-covering backend, но не Transvoxel и не topological zipper. RL2 намеренно фиксирует стратегию как versioned artifact, чтобы будущий transition-cell backend можно было добавить новым variant без изменения Matter state.

## 7. LOD balancing

Transition разрешён только для соседних LOD:

```text
abs(lod_a - lod_b) <= 1
```

`MatterLodNeighborhoodBalancer` принимает unordered desired plan и детерминированно уточняет более грубые face-adjacent cells, пока разница не станет не больше единицы. Он никогда не огрубляет более детальный запрос.

Прямая пара LOD0 ↔ LOD2 отклоняется.

## 8. Invalidation и rebuild scope

`MatterMeshingInvalidationResolver` проецирует RL0 invalidation на representation keys:

- exact source domain/id;
- authority/revision monotonicity;
- affected scopes;
- каноническая дедупликация stale keys;
- deterministic stale-key hash.

После изменения одного brick RL1 помечает его ancestor chain. RL2 перестраивает только mesh artifacts этих scopes. Остальные ветви и их content-addressed artifacts остаются пригодными.

RL2 не добавляет background scheduler: orchestration build queue остаётся границей RL5.

## 9. Godot presentation boundary

Чистые simulation contracts не содержат `ArrayMesh`, `Node3D`, `RID` или physics resources.

`MatterRepresentationMeshResourceFactory` находится в world/presentation слое и умеет:

- создать `ArrayMesh` из surface или transition artifact;
- создать `ConcavePolygonShape3D` только из surface mesh data;
- создать presenter с отдельными `Surface`, `Collision` и `Transition_*` nodes;
- применить two-sided material к transition skirt;
- корректно перевести origin transition относительно origin fine mesh.

Потеря или удаление этих Godot resources не меняет canonical state.

## 9.1. Capability fences artifact manifest

RL2 не позволяет presentation artifact заявлять возможности, которых у него нет:

- collision допускается только для `DETAIL`;
- `MACRO_PROXY` не может заявлять внутреннюю геометрию;
- cross-level transition не является collision- или interior-artifact;
- цвет неизвестного материала детерминированно выводится из SHA-256 canonical material ID, а не из runtime-dependent hash.

Runner отдельно отклоняет вывод с `SCRIPT ERROR` или parse error, даже если процесс завершился кодом `0` и успел напечатать PASS-маркер.

## 10. Что RL2 не реализует

- representation-aware network streaming — RL3;
- shared memory/disk cache и background scheduler — RL5;
- body-scale impostor textures;
- Transvoxel transition cells;
- simplified collision для LOD1/LOD2;
- Construction HLOD — RL4;
- изменения production Moon или world catalog;
- межсерверный geometry builder service;
- автоматическую визуальную интеграцию в asteroid lab scene.

## 11. Acceptance invariants

Checkpoint принимается, если доказано:

- 1/8/64 exact source coverage;
- LOD spacing и geometric error растут ×2;
- same-level boundary segment hashes совпадают;
- LOD0↔LOD2 без balancing отклоняется;
- fine/coarse transition покрывает всю fine boundary;
- transition source/key/color tampering отклоняется;
- reordered source snapshots дают byte-equivalent geometry;
- real fixed-seed asteroid даёт READY LOD0 и LOD1 meshes;
- actual Godot `ArrayMesh`, collision и presenter создаются;
- RL1/RL0 и mutable-world regressions остаются зелёными.
