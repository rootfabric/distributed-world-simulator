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
