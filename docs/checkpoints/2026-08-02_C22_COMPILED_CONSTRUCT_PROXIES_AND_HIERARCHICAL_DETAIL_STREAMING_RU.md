# C22 — Compiled Construct Proxies and Hierarchical Detail Streaming

**Дата:** 2026-08-02
**База:** C21 Large-Scale Construction Acceptance, ACCEPTED
**Статус поставки:** IMPLEMENTED CANDIDATE
**Рекомендуемая ветка:** `feature/c22-compiled-construct-proxies-hlod-streaming`

## Задача

Крупный корабль, база или станция остаётся одним authoritative `ConstructAggregate` и одним item-backed предметом, даже если содержит тысячи частей. C22 отделяет канонический состав от передаваемого и отображаемого уровня детализации.

```text
authoritative large construct
→ item identities, parts, bonds, damage, utilities, inventories

compiled derived presentation
→ distant station shell
→ section HLOD
→ bounded local exterior
→ interior cell
→ exact interactive local parts
```

Дальний клиент не получает 10 000 дочерних item identities и не создаёт 10 000 runtime nodes. Он получает root identity, transform, bounds, summary и один content-addressed shell artifact.

## Authority boundary

C22 строится поверх C2B/C9/C13/C14/C17/C18 и соблюдает следующие границы:

- `ConstructSnapshot` и Item Graph остаются источником истины;
- proxy artifact, manifest, mesh batch и runtime node являются удаляемыми derived projections;
- proxy не получает собственную item identity;
- C17 read-only server может компилировать proxy из checksum-pinned snapshot, но не может менять construct;
- C9 damage изменяет authoritative snapshot, после чего C22 инвалидирует только затронутые sections и при необходимости общий shell;
- полный C13 exact descriptor создаётся только для интерактивных частей выбранной локальной области.

Последний пункт является обязательной оптимизацией. Компиляция точного C13 runtime для всех дочерних частей до создания дальнего shell сама бы воспроизводила проблему, которую должен решать C22.

## Stable section topology

Construct разбивается на стабильную spatial grid topology. В acceptance fixture используется размер section 5 м.

```text
20 × 10 × 50 unit blocks
= 10 000 authoritative parts
= 80 stable sections
```

Topology хранит:

- `part_id → section_id` index;
- bounds каждой секции;
- число частей;
- checksum;
- semantic interior cells и portal graph отдельно от exterior sections.

## Surface extraction и greedy meshing

Для unit-aligned box parts C22 строит occupancy map и удаляет внутренние грани глобально, включая границы между соседними sections.

Acceptance fixture:

```text
raw faces:              60 000
exposed faces:           3 400
internal faces removed: 56 600
```

Оставшиеся грани группируются по plane, normal и material. Greedy mesher объединяет соседние faces в крупные quads и material batches.

## Proxy artifacts

Поддержаны типы:

- `SHELL` — общий station/ship-level HLOD;
- `SECTION` — HLOD отдельной spatial section;
- `INTERIOR` — proxy semantic interior cell.

Каждый artifact содержит bounds, material batches, greedy quads, source provenance и `content_hash`. Artifact ID выводится из content hash.

Source revision и authority epoch закрепляются manifest, но не входят в geometric content hash. Поэтому неизменившиеся section bytes могут переиспользоваться после нового construct revision.

## Content-addressed cache

Cache:

- публикует artifact идемпотентно;
- принимает одинаковый geometric content из разных source revisions;
- сохраняет terminal operation results;
- экспортируется и восстанавливается;
- не хранит SceneTree objects.

Для fixture с 10 000 parts компилируется 83 artifact:

```text
1 shell
80 section proxies
2 interior proxies
```

## Detail modes

```text
DISTANT_SHELL
→ один shell artifact
→ exact parts = 0

SECTION_HLOD
→ ограниченный набор ближайших/видимых section artifacts
→ exact parts = 0

LOCAL_EXTERIOR
→ bounded nearby sections
→ exact descriptors только для разрешённых interactive parts

INTERIOR_CELL
→ selected interior artifact
→ portal-neighbor context
→ exact interactive parts текущей cell
```

Переходы определяются distance policy, selected interior cell, visible sections и bandwidth budget.

## Network packet

Far packet содержит:

- construct/root item identity;
- source revision/checksum;
- authority epoch;
- world transform;
- bounds и compact summary;
- один shell artifact payload;
- `suppressed_part_count = 10 000`;
- пустой список exact child descriptors.

Manifest и packet не публикуют массив всех дочерних item IDs. Near packet получает только выбранные artifacts и bounded exact interactive descriptors.

## Runtime replacement

`ConstructionProxyRuntimeNode` создаёт presentation для текущего packet и полностью удаляет предыдущий уровень детализации.

Ключевой инвариант:

```text
shell не рисуется поверх 10 000 child nodes;
shell заменяет их presentation.
```

Graphical acceptance подтверждает:

- far: 1 proxy `MeshInstance3D`, 0 exact part nodes;
- section mode: не более 12 proxy meshes, соответствующие bounded `StaticBody3D/CollisionShape3D`, 0 exact parts;
- local mode: bounded node count;
- interior: 8 exact interactive parts и ограниченный proxy context.

## Incremental rebuild

После boundary damage одного part:

- authoritative part identity сохраняется;
- меняется source revision/checksum;
- invalidated: shell + 1 section;
- reused: 79 section artifacts;
- cache добавляет только новые geometric artifacts.

Dirty section list и invalidation plan checksum-pinned. Полный cache не сбрасывается.

## Persistence и restart

Сохраняются:

- manifests;
- content-addressed artifacts;
- source checksums и authority epochs;
- controller generation;
- terminal cache operations.

Не сохраняются Godot `Node`, `Mesh`, `Shape3D` или `RID`.

После restart дальний shell можно передать сразу из cache. Для local exact detail authoritative source/topology должен быть reattached с тем же source checksum и authority epoch.

## Focused acceptance

```text
contracts:    29 assertions
integration:  52 assertions
graphical:    35 assertions
scale/soak:   75 assertions
total:       191 assertions
```

Scale/soak использует реальный 10 000-part construct и 64 чередующихся far/section/local/interior interest transitions. Проверяются bounded payloads, deterministic artifact selection, cache stability и отсутствие раскрытия всех child parts.

## Ограничения vertical slice

- Runtime graphical proof использует bounds-based `BoxMesh` для materialized artifact node. Artifact DTO уже содержит greedy quads/material batches; production `ArrayMesh` backend и GPU-ready packed buffers можно развить внутри C22/C23 без изменения authority contracts.
- LOD simplification backend представлен shell/section hierarchy и greedy topology. Triangle decimation и baked impostor textures являются сменными presentation backends.
- Interior topology задаётся semantic C7-style cells/portals; автоматическая генерация room graph из arbitrary geometry не входит в этот slice.
- Network acceptance проверяет packet contracts и suppression. Полный Network N0–M4 остаётся обязательным внешним gate.

## Ожидаемый полный gate

```text
C22 focused:      PASS — 191 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
C17–C21:          PASS
Network N0–M4:    PASS
World regression: PASS — 148/148 тестов, 151 шаг
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

## Следующий этап

Production Hardening переносится на **C23**: schema migrations, backward-compatible saves, rolling upgrades, observability, security, fuzzing, corruption recovery, chaos и release runbooks.
