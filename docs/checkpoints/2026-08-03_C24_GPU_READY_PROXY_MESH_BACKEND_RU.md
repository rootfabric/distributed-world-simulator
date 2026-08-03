# C24 — GPU-Ready Proxy Mesh Backend and Runtime HLOD Acceptance

**Дата:** 2026-08-03
**База:** C23 Production Hardening, ACCEPTED
**Статус поставки:** ACCEPTED
**Ветка:** `feature/c24-gpu-ready-proxy-mesh-backend`
**Implementation head до acceptance-коммита:** `8623d0e5b4b6455fb4a75f2cc04c6cb5d3c38cb8`

## Причина этапа

C22 уже создавал content-addressed shell/section/interior artifacts с greedy quads и material batches, но graphical proof материализовывал каждый artifact как bounds-based `BoxMesh`. Это доказывало замену 10 000 child nodes, но не доказывало реальную геометрию compiled proxy.

C24 закрывает это ограничение без изменения authority:

```text
C22 JSON-safe artifact
→ strict quad validation
→ packed vertex/normal/UV/index buffers
→ one ArrayMesh surface per material batch
→ content-addressed shared GPU resource cache
→ C22 runtime replacement node
```

`ConstructSnapshot`, Item Graph, C9 damage, C17 authority epoch, C22 network packets и C23 production boundary остаются источниками истины и не изменяются.

## Реализация

### ArrayMesh backend

`ConstructionProxyArrayMeshBackend` компилирует:

- `GRID_QUAD` для осей X/Y/Z и направлений ±1;
- `FALLBACK_QUAD` для arbitrary axis-aligned bounds;
- четыре вершины, шесть индексов и две triangles на quad;
- outward winding и explicit normals;
- meter-scaled UV;
- отдельную `ArrayMesh` surface на каждый material batch;
- `StandardMaterial3D` resource с immutable material-key metadata.

Unknown fields, нулевые размеры, unsafe координаты и неподдерживаемые quad kinds fail closed до изменения SceneTree.

### Mesh descriptor

JSON-safe `ConstructionProxyMeshDescriptor` фиксирует:

- artifact/content identity;
- backend version;
- material surface list;
- vertex/index/triangle counts;
- bounds;
- estimated GPU bytes;
- deterministic mesh signature и checksum.

Descriptor не содержит `Resource`, `RID` или `Node` и пригоден для diagnostics/replay comparison.

### Shared bounded cache

`ConstructionProxyMeshCache`:

- адресует ресурс по C22 `content_hash`;
- возвращает один и тот же `ArrayMesh` для повторного LOD и разных клиентов;
- использует deterministic LRU для mesh resources и placeholder materials;
- ограничен entry и estimated-byte budgets;
- хранит hits/misses/evictions без unbounded labels;
- материализует одиночный ресурс крупнее byte-budget без удержания в кеше и учитывает это bounded-метрикой `oversized_bypasses`;
- не persist-ит Godot resources: после restart они лениво восстанавливаются из persisted C22 artifact cache.

Cache принадлежит `ConstructionProxyStreamingController`, а не отдельному client runtime. Поэтому несколько наблюдателей разделяют GPU resource, сохраняя независимые SceneTree nodes.

### Transactional runtime replacement

`ConstructionProxyRuntimeNode` сначала материализует и валидирует весь packet, затем заменяет presentation. Ошибка последнего artifact не удаляет предыдущий shell/section presentation.

Proxy `MeshInstance3D` содержит actual construct-local vertices и остаётся в локальном origin. Collision proxies и exact interactive C13 parts сохраняют прежние bounded правила C22.

## Focused acceptance

```text
contracts:      PASS — 80 assertions
integration:    PASS — 68 assertions
graphical:      PASS — 74 assertions
scale/soak:     PASS — 2 300 assertions
total:          PASS — 2 522 assertions
```

Scale/soak выполняет 128 переходов через четыре detail mode для fixture из 10 000 item-backed parts. Получено 14 уникальных mesh resources, 882 cache hits, 4 256 estimated GPU bytes активного working set и 0 evictions.

## Независимая приёмка

```text
C24 focused:      PASS — 2 522 assertions
C23 focused:      PASS — 4 187 assertions
C22 focused:      PASS —   191 assertions
C2B regression:   PASS —   258 assertions
C9 regression:    PASS —   204 assertions
Network N0–M4:    PASS — 54 tests, 55 steps
World regression: PASS — 156/156 tests, 159 steps
Main-scene CLI:   PASS — 6/6
Editor import:    PASS
Git diff check:   PASS
```

Новых блокирующих замечаний по authority, deterministic mesh materialization, shared cache, transactional replacement и 10 000-part scale/soak не обнаружено.

## Решение

```text
checkpoint: C24_GPU_READY_PROXY_MESH_BACKEND
decision:   ACCEPTED
branch:     feature/c24-gpu-ready-proxy-mesh-backend
frozen:     true
next:       integration/c24-nx6-mw10-rl3
```

Статус `IMPLEMENTED_CANDIDATE` в authoring validation JSON является историческим статусом до независимой приёмки и этим acceptance-коммитом заменён на `ACCEPTED` для выбора frozen head.

## Ограничения

- C24 материализует exact greedy surfaces, но не добавляет triangle decimation или baked impostor textures.
- Material library пока использует deterministic runtime materials; привязка к production asset catalog остаётся сменным presentation adapter.
- GPU bytes являются детерминированной оценкой packed buffers, а не driver-specific VRAM telemetry.
- Interior room graph по-прежнему приходит из semantic C7/C22 cells и portals.
