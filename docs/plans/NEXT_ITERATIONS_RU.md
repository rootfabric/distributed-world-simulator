# Ближайшие итерации после A0 Distributed Runtime Architecture

## Текущая точка

```text
documentation checkpoint: v16.7.1-architecture-a0-distributed-runtime
runtime base: v16.7.0-repository-r3.1-authoritative-recovery
```

R3.1 принят: authoritative snapshot, ledger, command/replay dedup и crash recovery подтверждены. A0 фиксирует следующий фундамент перед World Directory.

## Следующий кодовый этап — H0 listen-host

```text
branch: feature/h0-listen-host-runtime
proposed checkpoint: v16.8.0-runtime-h0-listen-host
```

H0 реализует:

- отдельный `ClientRuntime`;
- `ClientReplicaStore` для текущего item snapshot/delta;
- `ClientCommandGateway`;
- `HostRuntime` composition root;
- loopback transport pair;
- сериализационную/deep-copy boundary;
- тест запрета прямого UI → server domain доступа;
- opt-in запуск одним F5.

Главный acceptance:

```text
одна item-команда
→ listen-host loopback
→ separate ENet server/client
→ одинаковый final authoritative/client checksum
```

## После H0

```text
A1 Generic Aggregate Foundation
→ S0 Spatial Simulation Substrate
→ T1 Multi-peer Transport v2
→ B0 Message-bus Contracts
→ M0 Aggregate Transactions + Outbox
→ S1 Distributed Compute Contracts
```

Только после этого начинаются:

```text
B1 NATS Core
B2 JetStream/outbox
P0 Population Field
D1 Remote Worker MVP
N3 World Directory
```

## Правило фокуса

Пока foundation checkpoint не принят:

- не начинать следующую foundation-ветку;
- не добавлять растения или worker runtime напрямую в item aggregate;
- не подключать NATS из domain-кода;
- не строить Directory вокруг текущего single-item route;
- не переводить обычный F5 на host без ClientReplicaStore boundary.

Подробный план: [`DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md).
