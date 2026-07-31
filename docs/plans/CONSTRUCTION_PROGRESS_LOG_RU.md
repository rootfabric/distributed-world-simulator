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
