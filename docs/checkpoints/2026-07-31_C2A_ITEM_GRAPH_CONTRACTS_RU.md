# Checkpoint C2A — Item Graph Contracts

**Дата:** 2026-07-31
**База:** `main @ 2879fdb7134032f645ffc5c98c0535aecfc09caf`
**Ветка:** `feature/c1-semantic-construction-kernel`
**Предыдущее принятое состояние:** C1 fix1 ACCEPTED
**Статус поставки:** IMPLEMENTED CANDIDATE

## Цель

Подготовить строительное ядро к будущей интеграции с canonical Item Graph, не изменяя runtime, контейнеры, persistence, transport или multiplayer command path.

## Принятое решение

C2 разделён:

- C2A — чистые contracts и sandbox atomicity;
- C2B — реальная интеграция после multiplayer gate.

C2A использует существующую предметную семантику `ATTACHMENT` для установленной детали. Резервирование материалов существует только внутри transaction plan до commit.

## Реализованные contracts

```text
planet_simulator.construction_item_projection.v1
planet_simulator.construction_item_mutation.v1
planet_simulator.construction_construct_mutation.v1
planet_simulator.construction_item_transaction_plan.v1
planet_simulator.c2a_construction_item_graph_state.v1
```

## Вертикальный сценарий

```text
5 деталей стола в container
+ stack крепежа quantity=8
    ↓ ASSEMBLE_CONSTRUCT
construct root item CREATE
5 item relations → ATTACHMENT
fasteners 8 → 4
ConstructSnapshot CREATE
    ↓
operational table capabilities сохранены
    ↓ DECONSTRUCT_CONSTRUCT
ConstructSnapshot DELETE
root item DELETE
5 item relations → salvage container
fasteners остаются quantity=4
```

## Проверенные свойства

- strict schemas и exact fields;
- совместимость проекции с `item_instance.v2`;
- JSON-safe payloads;
- canonical sorting;
- checksum plan;
- exact before-state preconditions;
- immutable item identity;
- последовательная item revision;
- root component consistency;
- part binding consistency;
- exact replay;
- operation ID conflict;
- stale plan rejection;
- retryable injected failure;
- отсутствие частичного commit;
- persistent replay после JSON round-trip.

## Локальная focused-проверка

```text
C2A Item Graph contracts:    PASS — 46 assertions
C2A Item Graph transactions: PASS — 91 assertions
Total:                       PASS — 2/2, 137 assertions
```

## Изоляция

C2A не подключён к:

- `item_registry.gd`;
- container registry;
- item transfer service;
- production Operation Ledger;
- M0 coordinator;
- gameplay runtime;
- network transport;
- UI.

`InMemoryConstructionItemGraphAdapter` является contract-test sandbox и не может использоваться как production store.

## Mapping на C2B

| C2A | C2B |
|---|---|
| item projection | canonical item aggregate snapshot adapter |
| item mutation | M0 aggregate mutation operation |
| construct mutation | Generic ConstructAggregate adapter operation |
| transaction plan | M0 MutationBatch builder |
| sandbox precondition equality | AggregatePrecondition revision/authority fencing |
| terminal operation map | canonical Operation Ledger |
| state invariant check | TransactionInvariantRegistry validators |

## Acceptance gate

Перед ACCEPTED требуется на полном checkout:

- focused C1 PASS;
- focused C2A PASS;
- network regression PASS;
- world regression со 103/103 tests PASS;
- `git diff --check` PASS.
