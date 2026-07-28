# Дорожная карта сетевой и распределённой архитектуры PlanetSimulator

Текущий документационный checkpoint:

```text
v16.7.1-architecture-a0-distributed-runtime
branch: feature/a0-distributed-runtime-architecture
runtime base: v16.7.0-repository-r3.1-authoritative-recovery
```

R3.1 функционально принят. Перед N3 выполнена архитектурная ревизия self-host, сложных aggregates, distributed compute и transport-independent server messaging. Решение: сначала укрепить runtime/aggregate/data-plane foundations, затем строить World Directory и handoff.

## Основные документы

1. [`docs/checkpoints/2026-07-29_V16_7_1_ARCHITECTURE_A0_DISTRIBUTED_RUNTIME_RU.md`](docs/checkpoints/2026-07-29_V16_7_1_ARCHITECTURE_A0_DISTRIBUTED_RUNTIME_RU.md) — текущий A0 checkpoint.
2. [`docs/architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md`](docs/architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md) — целевая архитектура runtime, aggregates, workers и transports.
3. [`docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md) — точная последовательность H0 → A1 → S0 → T1 → B0 → M0 → S1.
4. [`docs/persistence/R3_1_AUTHORITATIVE_RECOVERY_RU.md`](docs/persistence/R3_1_AUTHORITATIVE_RECOVERY_RU.md) — принятый authoritative recovery foundation.
5. [`docs/testing/N2_PROCESS_HARNESS_RU.md`](docs/testing/N2_PROCESS_HARNESS_RU.md) — multi-process test infrastructure.
6. [`docs/contracts/N0_NETWORK_CONTRACTS_V1_RU.md`](docs/contracts/N0_NETWORK_CONTRACTS_V1_RU.md) — принятые сетевые invariants.
7. [`docs/network/NETWORK_TEST_MATRIX_RU.md`](docs/network/NETWORK_TEST_MATRIX_RU.md) — test gates.
8. [`docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md`](docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md) — границы ownership между tracks.

## Принятая база

```text
N0   network contracts                         accepted
N1   ENet snapshot/command/reconnect           accepted
N2   multi-process harness                     accepted
R3.1 authoritative persistence/recovery        accepted
A0   distributed runtime architecture          current candidate
```

## Скорректированная foundation-линия

```text
A0  architecture decisions
 ↓
H0  listen-host + ClientReplicaStore
 ↓
A1  generic aggregate contracts
 ↓
S0  spatial cells/scopes/shards
 ↓
T1  multi-peer transport v2
 ↓
B0  transport-independent bus ports
 ↓
M0  multi-aggregate transactions + outbox
 ↓
S1  simulation jobs + mutation proposals
```

После foundation:

```text
B1 NATS Core
→ B2 JetStream/outbox
→ N3 World Directory

P0 Population Field
→ D1 remote vegetation worker MVP
```

Обе линии сходятся перед N4 generic authority handoff.

## Главные инварианты

```text
canonical simulation ≠ presentation ≠ transport
client replica ≠ server aggregate
authority ownership ≠ compute assignment
spatial location ≠ authority route
transport semantics ≠ transport adapter
```

## Self-host решение

Основной будущий локальный режим:

```text
listen-host
├── embedded Region Authority
├── loopback DTO boundary
└── embedded ClientRuntime + replica + presentation
```

Для реалистичной локальной проверки:

```text
local-dedicated
├── headless server process
└── graphical client process over ENet localhost
```

## Transport policy

Отдельные ports:

```text
ReplicationTransportPort
ServiceRequestReplyPort
EventStreamPort
JobQueuePort
BulkTransferPort
```

ENet, loopback, NATS и другие технологии реализуют adapters. Domain-код не знает subjects, sockets или broker IDs.

## Машиночитаемый план

- [`config/network/network-roadmap.v1.json`](config/network/network-roadmap.v1.json)

## Следующий кодовый этап

```text
H0 — listen-host runtime
branch: feature/h0-listen-host-runtime
proposed checkpoint: v16.8.0-runtime-h0-listen-host
```
