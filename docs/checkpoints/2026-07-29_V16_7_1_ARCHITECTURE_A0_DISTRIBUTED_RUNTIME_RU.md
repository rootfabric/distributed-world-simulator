# Checkpoint v16.7.1 — A0 Distributed Runtime Architecture

**Тип:** документационный архитектурный checkpoint
**Runtime-код:** без изменений
**Runtime-база:** `v16.7.0-repository-r3.1-authoritative-recovery`
**Ветка:** `feature/a0-distributed-runtime-architecture`

## 1. Причина checkpoint

После принятия N0, N1, N2 и R3.1 проект имеет надёжный первый authoritative item vertical slice. Перед реализацией World Directory проведена ревизия трёх целевых требований:

1. self-host и разработка без выделенного сервера;
2. сложные объекты, population fields, parts и distributed compute workers;
3. сменяемая межсерверная передача, включая возможность NATS/JetStream.

Ревизия показала, что фундамент совместим с этими требованиями, но N3 нельзя строить непосредственно поверх текущей узкой item/single-peer модели.

## 2. Зафиксированные решения

- обычный локальный gameplay должен эволюционировать в `listen-host`;
- client и server разделяются DTO/replica boundary даже в одном процессе;
- `offline` остаётся tools/diagnostics режимом;
- `WorldEntityAggregate` остаётся item-backed;
- вводится generic aggregate contract и отдельные aggregate snapshots;
- SimulationCell не равна authority boundary;
- logical objects могут состоять из shards;
- worker не является authority и возвращает MutationProposal;
- materialization/detach требуют multi-aggregate transaction;
- replication, request/reply, events, jobs и bulk transfer имеют разные ports;
- NATS является adapter, а не domain dependency;
- authoritative commit позднее включает atomic outbox;
- N3 переносится после H0/A1/S0/T1/B0 foundations.

## 3. Новая foundation-последовательность

```text
A0 architecture
→ H0 listen-host
→ A1 generic aggregate foundation
→ S0 spatial simulation substrate
→ T1 multi-peer transport v2
→ B0 message-bus contracts
→ M0 multi-aggregate transactions/outbox
→ S1 distributed compute contracts
```

После этого:

```text
Infrastructure: B1 NATS Core → B2 JetStream/outbox → N3 Directory
Simulation:     P0 Population Field → D1 worker MVP
```

Далее ветки сходятся на N4 generic authority handoff.

## 4. Почему это укрепляет проект

Новый порядок сначала отвечает на вопросы:

- где проходит client/server boundary;
- что является authoritative aggregate;
- как aggregate адресуется в пространстве;
- как transport semantics отделяются от adapter;
- как атомарно менять несколько aggregates;
- как worker предлагает расчёт без прямой записи.

Только после этого Directory получает устойчивые сущности маршрутизации: node, service, aggregate kind, shard, lease, endpoint и bus route.

## 5. Что не меняется

Сохраняются:

- N0 DTO invariants;
- current EntitySnapshot/Delta v1;
- ENet vertical slice;
- reconnect/replay;
- N2 harness;
- R3.1 persistence/recovery;
- item domain и inventory;
- canonical SpatialRef и PartitionAddress.

Новые слои расширяют, а не заменяют принятую базу.

## 6. Документы checkpoint

- [`../architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md`](../architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md);
- [`../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md);
- [`../architecture/adr/ADR-007-runtime-topology-and-listen-host.md`](../architecture/adr/ADR-007-runtime-topology-and-listen-host.md);
- [`../architecture/adr/ADR-008-generic-aggregate-boundary.md`](../architecture/adr/ADR-008-generic-aggregate-boundary.md);
- [`../architecture/adr/ADR-009-transport-families-and-message-bus.md`](../architecture/adr/ADR-009-transport-families-and-message-bus.md);
- [`../architecture/adr/ADR-010-authority-compute-separation.md`](../architecture/adr/ADR-010-authority-compute-separation.md).

## 7. Acceptance A0

```text
runtime files changed: 0
roadmap JSON parse: PASS
Markdown links: PASS
git diff --check: PASS
UTF-8/LF: PASS
next branch: feature/h0-listen-host-runtime
```

## 8. Следующий checkpoint

```text
H0 — listen-host runtime
proposed checkpoint: v16.8.0-runtime-h0-listen-host
branch: feature/h0-listen-host-runtime
```

Первый H0 gate должен доказать одинаковый final checksum для одной item-команды через loopback host и отдельные ENet processes.
