# Checkpoint v16.8.1 — A1 Generic Aggregate Foundation

**Build ID:** `a1-generic-aggregate-foundation`
**Base:** `v16.8.0-runtime-h0-listen-host`
**Branch:** `feature/a1-generic-aggregate-foundation`
**Status:** candidate

## Реализовано

- `DynamicTypeReference`;
- `AggregateIdentity`;
- `AggregateAuthorityState`;
- `AggregateSpatialScope`;
- `AggregateDescriptor`;
- `AggregateSnapshotEnvelope`;
- `AggregateDeltaEnvelope`;
- `AggregateAdapterPort`;
- `AggregateAdapterRegistry`;
- `GenericAggregateStore`;
- `WorldItemAggregateAdapter`;
- item-backed compatibility vertical;
- non-item EnvironmentCell vertical.

## Архитектурный результат

Текущий `WorldEntityAggregate` сохранён специализированным item-backed aggregate. Общие aggregate invariants вынесены в отдельные контракты и adapters.

```text
WorldEntityAggregate
→ WorldItemAggregateAdapter
→ AggregateSnapshotEnvelope
→ canonical boundary
→ GenericAggregateStore
→ AggregateDeltaEnvelope
```

Non-item fixture доказывает:

```text
EnvironmentCell
→ CELL scope
→ generic snapshot/delta
→ replica
```

без item, physics и point-position requirements.

## Проверенный candidate

```text
A1 contracts:             67/67 PASS
A1 integration:           83/83 PASS
Network profile:          27/27 suites, 2286/2286 assertions
World test scripts:       70/70 PASS
Equivalent runner steps:  73/73 PASS
Main scene offline:        6 PASS, 0 FAIL
Main scene listen-host:    6 PASS, 0 FAIL
Simulation-server:              PASS
```

Дополнительно подтверждено:

- `EntitySnapshotEnvelope v1` не изменён;
- валидация текущего `WorldEntityAggregate` не изменена;
- неизвестный `aggregate_kind` не принимается без adapter;
- каждый зарегистрированный adapter проверяет точную state schema;
- generic store не хранит прямые ссылки на authority/domain objects;
- `git diff --check` проходит.

## Fix1 — fixture discovery в world regression

Windows-проверка выявила, что автоматический discovery `test_*.gd` ошибочно считал вспомогательные A1-скрипты из `tests/simulation/fixtures/` самостоятельными SceneTree-тестами.

Исправлено общим правилом:

```text
любой tests/**/fixtures/test_*.gd
→ остаётся доступным через preload
→ не входит в standalone world-test discovery
→ не обязан присутствовать в явном runner manifest
```

Проверено:

```text
declared standalone tests: 70
discovered standalone tests: 70
excluded fixture scripts:    2
coverage mismatches:          0
```

Полный world manifest после исправления:

```text
70/70 Godot test scripts PASS
73/73 equivalent runner steps PASS
Main scene: 6 PASS, 0 FAIL
```

## Следующий checkpoint

`v16.8.2-simulation-s0-spatial-substrate` в ветке `feature/s0-spatial-simulation-substrate`.
