# Журнал движения строительной линии

Этот файл является хронологическим журналом. Архитектурная карта находится в `CONSTRUCTION_MAP_RU.md`, подробный план — в `CONSTRUCTION_ROADMAP_RU.md`.

## 2026-07-31 — C0: архитектурная парадигма

**Статус:** ACCEPTED как направление линии.

Зафиксировано:

- стройка нового уровня вместо отдельного block editor;
- четыре опоры: semantic scale, composite items, facet compilation, capability-based behavior;
- граница Item Graph / ConstructAggregate;
- контрольные объекты: стол, робот, дом, сборщик, корабельная секция;
- необходимость авторитетной сетевой командной границы.

## 2026-07-31 — C1: Semantic Construction Kernel

**Статус:** ACCEPTED, delivery fix1.

База:

```text
main @ 2879fdb7134032f645ffc5c98c0535aecfc09caf
feature/c1-semantic-construction-kernel
```

Реализовано:

- `ConstructionPartRecord`;
- `ConstructionBondRecord`;
- `ConstructSnapshot`;
- `ConstructAggregate`;
- revision/replay fencing;
- capability compiler;
- стол как первый vertical slice;
- обязательное включение C1 в world regression.

Приёмка:

```text
Focused C1:       PASS — 66 assertions
Network N0–M4:    PASS
World regression: PASS — 101/101 tests, 104 steps
```

## 2026-07-31 — C2A: Item Graph Contracts

**Статус:** IMPLEMENTED CANDIDATE, ожидает внешней приёмки.

Архитектурное решение:

- C2 разделён на C2A и C2B;
- C2A остаётся полностью изолированным от runtime;
- установленная деталь использует существующую семантику `ATTACHMENT`;
- `assembly_id = construct_id`;
- `parent_item_id = construct root item`;
- `socket_id = part_id`;
- резервирование существует только в transaction plan до commit;
- C2A plan проектируется как будущий builder для M0 `MutationBatch`.

Реализовано:

- item projection, совместимая с `planet_simulator.item_instance.v2`;
- item mutation contracts;
- construct mutation contract;
- checksum-protected transaction plan;
- transaction planner сборки и разборки;
- adapter port;
- in-memory atomic adapter;
- exact replay, operation conflict, stale preconditions;
- retryable injected failure без частичного commit;
- JSON round-trip и persistent replay;
- сборка стола из пяти item-backed деталей;
- расход четырёх крепежей из stack 8;
- разборка с возвратом деталей и сохранением расхода крепежа.

Локальная проверка реализации:

```text
C2A contracts:    PASS — 46 assertions
C2A transactions: PASS — 91 assertions
Focused total:    PASS — 2/2 tests, 137 assertions
```

Полный regression должен быть повторно запущен на рабочем checkout перед присвоением `ACCEPTED`.

## Следующее движение

После приёмки C2A строительная линия остаётся изолированной до multiplayer gate. Разрешённые параллельные задачи:

- уточнение mapping C2A plan → M0 MutationBatch;
- проектирование C3 BuildPlan без runtime-подключения;
- подготовка контрактов CompositeDefinition;
- расширение тестовых сложных случаев.

Реальный Item Graph изменяется только на C2B.

## 2026-07-31 — C2A: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c2a-item-graph-contracts`
**Коммит:** `68cf8b2 feat(construction): add C2A Item Graph contracts`

```text
C1 compatibility:  PASS — 66 assertions
Focused C2A:       PASS — 137 assertions
Network N0–M4:     PASS
World regression:  PASS — 103/103 tests, 106 steps
```

C2A сохранён как изолированный контрактный слой и стал базой C2B.

## 2026-07-31 — C2B: Authoritative Item Graph Integration

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c2b-authoritative-item-graph-integration`
**База:** принятый C2A `68cf8b2`.

Реализовано:

- production adapter к `ItemRegistry`, `ContainerRegistry`, `ItemRelationshipValidator`, `ItemMassService`;
- общий `ItemOperationLedger` вместо отдельного construction ledger;
- `ConstructStore` для item-backed constructs;
- детерминированный перевод C2A plan в M0 `MutationBatch`;
- три авторитетных aggregate family: Item Graph, ledger, Construct;
- M0 adapter и transaction bridge;
- атомарная сборка и разборка стола;
- exact replay, operation conflict, terminal rejection и retryable failure;
- rollback локальной materialization после частичного применения;
- crash recovery после M0 commit;
- раздельные revisions внутреннего construct и M0 envelope;
- checksum-protected persistence и restart replay;
- отказ от загрузки persisted state, расходящегося с M0 authority.

Локальный focused-профиль реализации:

```text
C2B contracts:     PASS — 64 assertions
C2B integration:   PASS — 194 assertions
Focused C2B:       PASS — 258 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
```

Внешняя приёмка должна дополнительно подтвердить network regression и world regression с 105 тестами.

## 2026-07-31 — C2B: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c2b-authoritative-item-graph-integration`.
**База:** `feature/c2a-item-graph-contracts @ 68cf8b2`.
**Commit:** ещё не создан на момент начала C3.

Подтверждено пользователем:

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C2B:             PASS — 258 assertions
Network/runtime: PASS
World regression: PASS
Main-scene CLI:  PASS — 6/6
Static checks:   PASS
```

Проверенная поставка C2B:

```text
31 files
SHA-256: 960D14B3D120EFF2BCBAD04BD15FA161E759C07348548E67E147C65B52B7787E
```

C2B принят как единственная authorititative граница реального расхода материалов, attach/detach и изменения ConstructAggregate.

## 2026-07-31 — C3: BuildPlan and Ghost Construction

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c3-build-plan-and-ghost`.
**База:** принятый C2B в `feature/c2b-authoritative-item-graph-integration`.

Архитектурные решения:

- BuildPlan является immutable execution-plan конкретной стройки;
- reusable blueprint/definition separation отложена до C4;
- BuildPlan хранит exact source item projections и exact material allocations;
- каждая стадия детерминированно восстанавливает одинаковый C2A transaction checksum;
- ghost не входит в Item Graph и не имеет массы/capabilities;
- после первой стадии физическим является partial construct, а ghost остаётся projection прогресса;
- progress ghost является recoverable projection и не сильнее C2B construct/ledger;
- partial stage snapshots принудительно не публикуют operational capabilities;
- stage execution всегда проходит через C2B-compatible `apply_plan()`;
- crash после authoritative stage commit восстанавливается через construct checksum и shared operation result;
- divergence между BuildPlan и authoritative construct отклоняется явно.

Реализовано:

- `ConstructionBuildStage`;
- `ConstructionBuildPlan`;
- `ConstructionGhostState`;
- `ConstructionBuildPlanStore`;
- `ConstructionStageSnapshotBuilder`;
- `ConstructionStageTransactionPlanner`;
- `ConstructionBuildProcess`;
- `ConstructionBuildPlanPersistence`;
- минимальный `ConstructionBuilderAgent`;
- новая C2A command `ADVANCE_CONSTRUCTION_STAGE`;
- operation-result lookup в C2A sandbox adapter и C2B production adapter;
- трёхстадийный стол: FOUNDATION → FRAME → COMMISSIONING;
- exact replay, capability gate, crash reconciliation, persistence и divergence guard.

Локальный focused-профиль реализации:

```text
C3 contracts:    PASS — 80 assertions
C3 integration:  PASS — 106 assertions
Focused C3:      PASS — 2/2, 186 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
```

Полный C2B/network/world regression должен быть повторно запущен на основном checkout перед присвоением C3 статуса `ACCEPTED`.

## 2026-07-31 — C3 review fix1: canonical preconditions

**Статус:** BLOCKER FIXED LOCALLY, EXTERNAL RECHECK REQUIRED.
**Ветка:** `feature/c3-build-plan-and-ghost`.
**Base полного checkout:** `C2B @ d5c9187`.

Внешняя проверка первоначального C3 остановила focused integration на FRAME: сохранённый FOUNDATION snapshot и новый raw before-snapshot были семантически равны, но отличались числовыми Variant-типами после canonicalization. Прямое сравнение словарей выдавало `CONSTRUCT_PRECONDITION_MISMATCH`.

Fix1:

- raw Dictionary equality заменено на `UtilsScript.canonical_json(...)` для construct preconditions;
- такое же исправление применено к item preconditions;
- добавлен regression, принудительно меняющий `state_revision` и item `revision` между `int` и `float`;
- C3 integration увеличен с 106 до 114 assertions.

Локальная повторная проверка:

```text
C1:            PASS — 66 assertions
C2A:           PASS — 137 assertions
C3 contracts:  PASS — 80 assertions
C3 integration: PASS — 114 assertions
C3 total:      PASS — 194 assertions
Editor parse:  PASS
```

C2B, network/runtime, world regression и main-scene CLI остаются обязательными для внешней приёмки fix1.


## 2026-07-31 — C3 fix1: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c3-build-plan-and-ghost`.
**База:** `C2B @ d5c9187`.

```text
C1:               PASS — 66 assertions
C2A:              PASS — 137 assertions
C2B:              PASS — 258 assertions
C3 contracts:     PASS — 80 assertions
C3 integration:   PASS — 114 assertions
C3 total:         PASS — 194 assertions
Network N0–M4:    PASS
World regression: PASS — 107/107 tests, 110 steps
```

Reviewed delivery: 42 files, SHA-256 `2296f48f0f31c8d4feb9290e0973d27dd4b4f85ed9c7f29361f28156b82ac256`. C3 стал базой C4.

## 2026-07-31 — C4: CompositeDefinition

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c4-composite-definition`.
**База:** принятый C3 fix1.

Архитектурные решения:

- definition хранит semantic slots, topology и requirements, но не concrete instance IDs;
- завершённый C3 construct можно повысить в reusable definition;
- новый экземпляр создаётся deterministic late binding реальных item projections;
- concrete binding сохраняется в отдельном immutable instantiation record;
- definition versioning последовательное и replay-safe;
- C4 компилирует обычный C3 BuildPlan и не меняет authoritative execution path;
- partial/final constructs сохраняют pinned definition provenance;
- typed parameters валидируются, нормализуются и pin-ятся в instantiation;
- exposed ports связываются semantic slot → concrete part и появляются только после установки части;
- material bindings обязаны точно совпадать с allocations конкретного BuildPlan;
- cosmetic/incompatible parts и недостаточные materials fail closed.

Локальный focused-профиль:

```text
C4 contracts:      PASS — 112 assertions
C4 integration:    PASS — 152 assertions
Focused C4 total:  PASS — 264 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
C3 compatibility: PASS — 194 assertions
Editor parse:      PASS
```

Полный C2B/network/world/main-scene профиль должен быть повторён на полном checkout перед присвоением C4 статуса `ACCEPTED`.


## 2026-07-31 — C4 fix1: canonical provenance comparison

**Статус:** BLOCKER FIXED LOCALLY, EXTERNAL RECHECK REQUIRED.
**Ветка:** `feature/c4-composite-definition`.
**Base полного checkout:** `C3 @ 4917f55`.

Внешний focused C4 подтвердил contracts `112 assertions`, но integration завершился с 5 ошибками. Причина была не в потере provenance: C2A in-memory adapter канонизировал JSON DTO и мог преобразовать целочисленные `float` в `int`. Тесты сравнивали `composite_parameters` и `composite_exposed_ports` raw-оператором `==`, поэтому семантически одинаковые данные считались различными.

Fix1:

- parameters и exposed ports сравниваются через `NetworkContractUtils.canonical_json`;
- contract comparison параметров приведён к той же семантике;
- добавлен regression для `100.0 ↔ 100` и `0.0 ↔ 0`;
- production schema и execution path C4 не изменялись.

Локальная повторная проверка:

```text
C1:             PASS — 66 assertions
C2A:            PASS — 137 assertions
C3:             PASS — 194 assertions
C4 contracts:   PASS — 112 assertions
C4 integration: PASS — 156 assertions
C4 total:       PASS — 268 assertions
Editor parse:   PASS
```

C2B, network/runtime, полный world regression и main-scene CLI остаются обязательными для внешней приёмки C4 fix1.


## 2026-07-31 — C4 fix1: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c4-composite-definition`.

```text
C4 contracts:     PASS — 112 assertions
C4 integration:   PASS — 156 assertions
C4 total:         PASS — 268 assertions
C1/C2A/C2B/C3:    PASS
Network N0–M4:    PASS
World regression: PASS — 109/109 tests, 112 steps
git diff --check: PASS
```

C4 fix1 SHA-256: `d6c03e2a9b2b34c879f45a392741ccddc01cf35fb5822ff8ec1e986bd0a0cb67`. C4 стал принятой базой C5.

## 2026-07-31 — C5: Capability and Affordance Compilation

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c5-capability-affordance-compilation`.
**База:** принятый C4 fix1.

Архитектурные решения:

- authoritative source остаётся `ConstructSnapshot`;
- behavior profile является checksum-pinned rebuildable projection;
- capability описывает semantic ability и concrete provider parts/ports;
- affordance описывает concrete action, target, actor requirements и properties;
- partial/damaged constructs публикуют пустой behavior profile;
- C4 parameters (`load_rating_kg`, `finish`) становятся query constraints;
- agent/resolver не зависят от prefab/display name;
- одинаковые queries сортируются priority → construct ID → affordance ID;
- stale и same-revision conflicts fail closed;
- persisted cache загружается транзакционно и может быть полностью rebuilt.

Реализовано:

- `ConstructionCapabilityDescriptor`;
- `ConstructionAffordanceDescriptor`;
- `ConstructionBehaviorProfile`;
- `ConstructionBehaviorCompiler`;
- `ConstructionBehaviorProfileStore`;
- `ConstructionBehaviorPersistence`;
- `ConstructionAffordanceQuery`;
- `ConstructionAffordanceResolver`;
- `ConstructionAffordanceAgent`;
- support/container/seat/climb/workstation/mounting vertical behaviors;
- C4 staged table integration и damage invalidation.

Локальный focused/compatibility профиль:

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

Полный C2B/network/world/main-scene профиль должен быть выполнен на полном checkout. Ожидаемый world profile: `111/111 tests`, `114 steps`.


## 2026-07-31 — C5 fix1: strict-schema negative-test

**Статус:** BLOCKER FIXED LOCALLY, EXTERNAL RECHECK REQUIRED.
**Ветка:** `feature/c5-capability-affordance-compilation`.

Внешняя focused-проверка C5 остановилась на одном contracts-тесте: fixture добавлял поле через property syntax, поэтому ключ получал невалидный для JSON DTO тип и contract закономерно возвращал `INVALID_FIELD_NAME`. Тест должен был проверять другую ветку — корректный строковый неизвестный ключ и ответ `UNEXPECTED_FIELD`.

Fix1:

- negative-test использует `unexpected["unexpected_field"] = true`;
- ожидание остаётся `UNEXPECTED_FIELD`;
- production behavior contracts и compiler не изменены.

Локальный профиль после fix1:

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

Полный C2B/network/world/main-scene профиль требуется повторить на полном checkout.
