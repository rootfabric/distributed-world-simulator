# Checkpoint C5 — Capability and Affordance Compilation

**Дата:** 2026-07-31
**Статус:** ACCEPTED вместе с fix1 — EXTERNAL RECHECK REQUIRED
**Рекомендуемая ветка:** `feature/c5-capability-affordance-compilation`
**База:** принятый C4 fix1 поверх `C3 @ 4917f55`

## Цель этапа

C5 превращает семантическую и физическую структуру `ConstructSnapshot` в формальный интерфейс поведения, понятный gameplay systems и агентам.

```text
Authoritative ConstructSnapshot
        ↓ deterministic compiler
ConstructionBehaviorProfile
        ├── typed capabilities
        └── concrete affordances
                ↓ semantic query
        agent/gameplay action choice
```

Агент не должен знать имя prefab, сцену, display name или заранее написанный класс конкретного стола. Он запрашивает действие `PLACE_ITEM`, минимальную допустимую нагрузку и собственные возможности, после чего получает конкретный construct, part и exposed port.

## Архитектурная граница

`ConstructionBehaviorProfile` является **перестраиваемой производной проекцией**. Источником истины остаётся checksum-защищённый authoritative `ConstructSnapshot` из C1–C4.

Профиль закрепляет:

- `construct_id`;
- checksum authoritative snapshot;
- semantic revision;
- build state;
- C4 definition provenance, если она есть;
- deterministic compiler ID/version;
- список capability descriptors;
- список affordance descriptors;
- diagnostics;
- собственный checksum.

Потеря behavior store не теряет состояние мира: профиль можно детерминированно восстановить из текущего snapshot. Обратное направление запрещено — behavior profile не может переписать parts, bonds, Item Graph или authority revision.

## Новые контракты

```text
planet_simulator.construction_capability_descriptor.v1
planet_simulator.construction_affordance_descriptor.v1
planet_simulator.construction_behavior_profile.v1
planet_simulator.construction_behavior_profile_store.v1
planet_simulator.construction_affordance_query.v1
```

### CapabilityDescriptor

Capability описывает **что объект умеет** и чем это обеспечено:

```text
capability_kind
provider_part_ids
source_port_ids
properties
checksum
```

Provider parts обязательны. Affordance не может ссылаться на part или port вне связанного capability descriptor.

### AffordanceDescriptor

Affordance описывает **какое конкретное действие доступно**:

```text
action_kind
capability_id
target_part_id
target_port_id
actor_requirements
parameters
priority
checksum
```

Например:

```text
PLACE_ITEM
→ capability/place-items/port/work-surface
→ part/table/.../top
→ port/work-surface
→ requires MANIPULATE_ITEM
→ load_rating_kg = 125
```

## Компиляция C5 v1

Поддержаны capability kinds:

- `SUPPORT_SURFACE`;
- `PLACE_ITEMS`;
- `WORK_SURFACE`;
- `MOUNTING_SURFACE`;
- `CONTAINER`;
- `SEAT`;
- `CLIMBABLE`;
- `WORKSTATION`.

Поддержаны action kinds:

- `PLACE_ITEM`;
- `USE_WORK_SURFACE`;
- `MOUNT_ITEM`;
- `OPEN_CONTAINER`;
- `STORE_ITEM`;
- `TAKE_ITEM`;
- `SIT`;
- `CLIMB`;
- `USE_WORKSTATION`.

C4 exposed ports являются предпочтительным semantic target:

```text
SUPPORT_SURFACE → PLACE_ITEM / USE_WORK_SURFACE
MOUNT_POINT → MOUNT_ITEM
CONTAINER_ACCESS → OPEN_CONTAINER / STORE_ITEM / TAKE_ITEM
SEAT → SIT
CLIMB_POINT → CLIMB
WORKSTATION → USE_WORKSTATION
```

Для старых C1 constructs без C4 ports действует fallback: surface capability связывается с concrete part, имеющей роль `surface`. Это сохраняет совместимость и не требует превращать все ранее созданные объекты в CompositeDefinition.

C4 parameter values переносятся в properties. Контрольный table profile публикует `load_rating_kg` и `finish`, поэтому query может выбирать не просто любой стол, а, например, окрашенную поверхность с нагрузкой не менее 120 кг.

## Lifecycle и fail-closed правила

- `PARTIAL` construct получает валидный, но пустой behavior profile.
- `DAMAGED` construct немедленно теряет operational capabilities и affordances.
- одинаковый profile checksum является exact replay и не увеличивает generation.
- более старая construct revision отклоняется.
- другой snapshot при той же revision отклоняется как same-revision mutation.
- повреждённый persisted state отклоняется транзакционно.
- удаление профиля требует совпадения authoritative construct checksum.

## Semantic query и агент

`ConstructionAffordanceQuery` содержит:

- желаемые action kinds;
- capabilities актора;
- optional construct filter;
- minimum numeric properties;
- exact properties;
- требование concrete exposed port;
- limit;
- checksum.

Resolver:

1. проверяет profile и query contracts;
2. отбрасывает non-operational objects;
3. проверяет actor requirements;
4. проверяет property constraints;
5. сортирует по priority, затем `construct_id`, затем `affordance_id`;
6. возвращает concrete capability, part и port.

`ConstructionAffordanceAgent` является тонкой обёрткой над тем же resolver. В query и result нет prefab/display-name dependency.

## Контрольный vertical slice

1. Один C4 table BuildPlan исполняется через FOUNDATION → FRAME → COMMISSIONING.
2. C5 компилирует profile после каждой authoritative стадии.
3. FOUNDATION и FRAME имеют ноль operational behaviors.
4. После COMMISSIONING появляются 4 capabilities и 3 affordances.
5. Generic agent находит `PLACE_ITEM` по нагрузке 150 кг и concrete `port/work-surface`.
6. Два неизвестных parameterized table instances публикуются в обратном порядке.
7. Query `PLACE_ITEM + load_rating >= 120 + finish=painted` детерминированно выбирает подходящий construct без имени типа.
8. После damage profile обновляется и прежнее действие исчезает.
9. Новый пустой store восстанавливает тот же damaged profile из authoritative snapshot.
10. Расширенный fixture проверяет container, seat, climbable, workstation и mounting surface.

## Реализованные файлы

```text
scripts/construction/behavior/
├── construction_capability_descriptor.gd
├── construction_affordance_descriptor.gd
├── construction_behavior_profile.gd
├── construction_behavior_compiler.gd
├── construction_behavior_profile_store.gd
├── construction_behavior_persistence.gd
├── construction_affordance_query.gd
├── construction_affordance_resolver.gd
└── construction_affordance_agent.gd
```

Тесты:

```text
tests/construction/fixtures/c5_affordance_fixture.gd
tests/construction/test_c5_capability_affordance_contracts.gd
tests/construction/test_c5_capability_affordance_integration.gd
```

## Локальная проверка

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5 contracts:    PASS — 105 assertions
C5 integration:  PASS — 99 assertions
C5 total:        PASS — 204 assertions
Editor parse:    PASS
```

Ожидаемый полный world profile после добавления двух C5 tests:

```text
111/111 tests
114 steps
```

## Ограничения C5 v1

- C5 выбирает действие, но не исполняет gameplay command; execution endpoints относятся к следующим вертикалям.
- runtime UI каталога действий не входит в этап.
- network query endpoint не входит в этап.
- сложные оценки доступности, reachability, reservations и contention появятся в C6–C12.
- порт является semantic target; полноценная routing/connection topology расширяется в mobile/spatial constructs.
- profile store может сохраняться для быстрого запуска, но остаётся rebuildable cache.

## Acceptance gate

```text
RUN_C1_CONSTRUCTION_KERNEL_TESTS.ps1
RUN_C2A_CONSTRUCTION_ITEM_GRAPH_TESTS.ps1
RUN_C2B_AUTHORITATIVE_ITEM_GRAPH_TESTS.ps1
RUN_C3_BUILD_PLAN_TESTS.ps1
RUN_C4_COMPOSITE_DEFINITION_TESTS.ps1
RUN_C5_CAPABILITY_AFFORDANCE_TESTS.ps1
RUN_NETWORK_CONTRACT_TESTS.ps1
RUN_WORLD_REGRESSION_TESTS.ps1
main-scene CLI

git diff --check
```

После внешнего PASS C5 становится базой C6 — Mobile Construct, где capability/affordance layer должен описать робота при частичной потере колеса, питания, control link или sensor subsystem.


## C5 fix1 — корректный strict-schema negative test

Внешняя focused-проверка остановилась в contracts-профиле на одном negative-test. Production contract отработал корректно: запись через property syntax `unexpected.extra = true` создала ключ не того Variant-типа, и строгая JSON-проверка вернула `INVALID_FIELD_NAME` до проверки точного множества полей. Поэтому тест не достигал ветки, которую должен был проверять.

Fix1 в той же ветке `feature/c5-capability-affordance-compilation`:

- лишнее поле добавляется индексированием со строковым литералом: `unexpected["unexpected_field"] = true`;
- ожидаемый код остаётся `UNEXPECTED_FIELD`;
- production capability/affordance contracts и runtime-компилятор не изменялись.

Локальная повторная проверка:

```text
C5 contracts:     PASS — 105 assertions
C5 integration:   PASS — 99 assertions
C5 total:         PASS — 204 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
C3 compatibility: PASS — 194 assertions
C4 compatibility: PASS — 268 assertions
Editor parse:     PASS
```

C2B, network/runtime, полный world regression и main-scene CLI остаются обязательными для внешней приёмки C5 fix1.


## Внешняя приёмка fix1

```text
C1 66 / C2A 137 / C2B 258 / C3 194 / C4 268 assertions PASS
C5 contracts 105, integration 99, total 204 assertions PASS
Network N0–M4 PASS
World regression 111/111 tests, 114 steps PASS
Main-scene CLI 6/6 PASS
git diff --check PASS
```

C5 принят и является базой C6.
