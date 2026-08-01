# C18 — Streaming, LOD and Dormant Constructs

**Статус:** IMPLEMENTED CANDIDATE
**База:** C17 focused candidate поверх принятого C16 `a4376cd`
**Рекомендуемая ветка:** `feature/c18-streaming-lod-dormant-constructs`

> C17 на момент сборки C18 ещё ожидает полный C2B/C9/Network/world gate. Поэтому C18 является отдельным overlay-кандидатом и не переводит C17 в ACCEPTED.

## Цель

Сделать возможным хранение и обслуживание очень большого количества конструкций без постоянной загрузки всех derived profiles, physics bodies и mesh.

```text
authoritative construct source
        ↓
interest samples + authority mode + budgets
        ↓
DORMANT / SUMMARY / SIMULATED / PRESENTED
        ↓
LOD NONE / IMPOSTOR / SIMPLIFIED / FULL
```

Authoritative `ConstructSnapshot`, item identities, C8 queues и operation IDs не удаляются при streaming eviction.

## Activity levels

### DORMANT

Хранятся:

- construct ID;
- authority epoch;
- snapshot revision/checksum;
- pending fabrication job IDs;
- pending operation IDs;
- scheduler cursor и checksums.

Не хранятся:

- C13 SceneTree;
- compact summary;
- активная локальная simulation projection.

### SUMMARY

Дополнительно компилируется компактное описание:

- bounds и масса;
- capability kinds;
- C14 structural state/utilization;
- C15 utility statuses;
- количество pending jobs/operations.

### SIMULATED

Owner server выполняет low-frequency catch-up. Read-only C17 replica не получает write-capable simulation, даже если находится рядом с observer.

### PRESENTED

C13 runtime projection lazy-восстанавливается в SceneTree. Presentation можно удалить и повторно построить без изменения authoritative checksum.

## Interest и hysteresis

`ConstructionInterestSample` содержит observer, расстояние, visible/selected/interacting flags, priority boost и tick.

Приоритет:

```text
interacting
→ selected
→ visible
→ explicit boost
→ distance
→ construct ID
```

При удалении observer применяется distance hysteresis. Переход в `DORMANT` задерживается на `dormant_after_ticks`, чтобы конструкция не thrash-илась на границе interest area.

## Budget allocation

Политика задаёт три независимых бюджета:

- summary bytes;
- simulation units;
- presentation bytes.

Кандидаты сортируются детерминированно по interest score и construct ID. При нехватке бюджета выполняется понижение:

```text
PRESENTED → SIMULATED/SUMMARY
SIMULATED → SUMMARY
SUMMARY   → DORMANT
```

`minimum_level` является pin. Если pinned construct не помещается в бюджет, reconcile отклоняется до изменения derived state.

## LOD

C18 вводит строгий `ConstructionLodProfile`:

```text
FULL       — full presentation, collision и animation/process enabled
SIMPLIFIED — reduced-detail contract, collision остаётся включённым
IMPOSTOR   — summary representation без C13 physics tree
NONE       — presentation отсутствует
```

LOD tier хранится в activity record и применяется к C13 runtime node через presentation-only adapter. Godot nodes не сериализуются в C18 DTO.

## Deterministic catch-up

`ConstructionCatchUpPlan` разбивает пропущенное время на фиксированные интервалы и ограничивает работу `maximum_catch_up_steps` за reconcile.

```text
last simulated tick
→ deterministic interval steps
→ bounded work
→ new scheduler frontier
```

Если backlog больше лимита, plan получает `truncated=true`; оставшаяся часть догоняется следующими reconcile. Pending C8 jobs и operation IDs передаются simulation driver без изменения.

## C17 authority boundary

- `OWNER` может выполнять SIMULATED-domain work;
- `READ_ONLY` может хранить SUMMARY и PRESENTED projection;
- read-only server не вызывает authoritative simulation driver;
- authority epoch rollback отклоняется;
- migration/takeover обновляет streaming source и fence-ит старую эпоху.

## Persistence и recovery

Сохраняются:

- activity records;
- compact summaries;
- policy checksum;
- reconcile terminal operations;
- scheduler cursors;
- pending job/operation identities.

Не сохраняются:

- C13 runtime nodes;
- Mesh/Shape/RID;
- observer input.

После restart authoritative sources повторно прикрепляются по construct checksum и authority epoch, затем presentation lazy-восстанавливается при следующем interest reconcile.

## Проверенный vertical slice

Четыре owner-конструкции конкурируют за ограниченные budgets:

```text
A → PRESENTED / FULL
B → SIMULATED
C → SUMMARY / IMPOSTOR
D → DORMANT / NONE
```

Проверено:

1. exact reconcile replay не выполняет второй catch-up или SceneTree rebuild;
2. другой input в том же tick отклоняется;
3. удаление observer сначала переводит конструкцию в grace SUMMARY, затем DORMANT;
4. дальняя dormant-конструкция lazy-восстанавливается сразу до PRESENTED;
5. большой backlog обрабатывается bounded catch-up планом;
6. fabrication jobs и pending operations переживают eviction;
7. read-only C17 replica может PRESENTED, но не симулируется локально;
8. persistence не сохраняет SceneTree, но rebuild возвращает presentation;
9. authority epoch update превращает бывшего owner в read-only source;
10. pinned budget failure не меняет tick, generation или runtime nodes.

## Focused acceptance

```text
C18 contracts:    PASS — 51 assertions
C18 integration:  PASS — 84 assertions
C18 total:        PASS — 135 assertions
Editor parse:     PASS
Headless SceneTree: PASS
```

Локально повторно пройдены C1–C8 и C10–C17. Суммарный локальный профиль вместе с C18: `2933 assertions, PASS`.

Ожидаемый полный world profile после добавления двух тестов:

```text
137/137 tests
140 steps
```

## Ограничения vertical slice

- реальная генерация decimated mesh/impostor texture относится к дальнейшей оптимизации C13 presentation backend;
- C18 выбирает и применяет LOD contract, но не вводит GPU mesh-cluster pipeline;
- C15/C8 catch-up вызывается через driver boundary; production scheduler должен подключить реальные tick adapters;
- distributed interest routing между несколькими C17 owner servers пока не transport-оптимизирован;
- global scale/soak acceptance относится к C21.
