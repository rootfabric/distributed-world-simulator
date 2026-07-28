# Checkpoint v16.4.0 — Foundation Gate + N0

**Версия:** `v16.4.0-foundation-n0`
**Build ID:** `foundation-n0-contracts-handoff-kernel-ports`
**Дата:** 27 июля 2026 года

## Решение

Foundation Gate и N0 считаются завершёнными. Проект имеет server-safe lifecycle,
canonical WORLD aggregate, presentation-free kernel boundary и полный набор
versioned сетевых контрактов без открытия сокетов.

Следующий network checkpoint — N1: один authoritative server, реальный transport
adapter и bot client.

## Закрытая Foundation-часть

- runtime roles: offline/client/simulation-server/bot-client;
- graceful lifecycle и terrain worker drain;
- terminal fail-closed fence после shutdown failure;
- изолированный process `user://`;
- `SimulationKernel`/`PresentationHost` boundary;
- canonical `WorldEntityAggregate`;
- Item Graph v2 и транзакционная migration;
- Entity/Chunk Lifecycle;
- `CanonicalStatePort`;
- строгие `EntityRegistryKernelPort` и `WorldRepositoryKernelPort`;
- process-level simulation-server подтверждает оба kernel port и ноль активных
  presentation nodes.

Старые world runtime scenes ещё могут конструировать локальные presentation
adapters, которые server policy отключает. Их физическое исключение из
конструирования остаётся cleanup-задачей и не нарушает текущий acceptance:
активных UI/камер/input на server role нет.

## Закрытая N0-часть

Реализованы:

```text
NetworkCommandEnvelope
NetworkCommandResultEnvelope
EntitySnapshotEnvelope
EntityDeltaEnvelope
NetworkEndpoint
AuthorityLease
AuthorityRoute
SimulationNodeDescriptor
SimulationSpaceDescriptor
AuthorityRegionDescriptor
GhostReplicaState
ClientRoute
HandoffTicket
HandoffResult
HandoffStateMachine
```

Дополнительно:

- canonical JSON и safe-integer lint на любой глубине;
- strict SpatialRef и canonical quaternion;
- snapshot/delta checksums;
- nested delta paths и protected metadata;
- command replay и operation conflict;
- snapshot/delta loopback replay;
- stale revision/epoch fencing;
- exhaustive handoff transition matrix;
- canonical golden fixtures;
- mutation matrix обязательных полей и JSON-типов;
- JSON summary отдельного network runner.

## Главные инварианты

```text
canonical simulation ≠ presentation ≠ transport
one authoritative owner per entity/region
state_revision never decreases
authority_epoch only increases
DTO contains no Godot runtime objects
same operation/delta replay does not repeat mutation
```

## Acceptance

Обязательные проверки:

- editor import/parse;
- полный N0 contract profile;
- Part 3 aggregate profile;
- lifecycle/process profile;
- все `test_*.gd` полного regression runner;
- playground main-scene regression;
- simulation-server process lifecycle;
- fixture/hash stability;
- manifest coverage;
- `git diff --check` и ZIP overlay verification.

Фактические результаты конкретной поставки записываются в
`foundation-n0-final-linux-double-validation.json` и
`artifacts/test-results/network-contract-summary.json`.

## Следующие этапы

### N1

- ENet adapter;
- один authoritative simulation-server;
- один bot-client;
- initial snapshot;
- удалённая item command;
- checksum equality;
- reconnect без смены UUID.

### R3.1 параллельно

- foundation/construction aggregate;
- solar panel;
- battery;
- charging dock;
- simple power graph;
- все мутации только через command gateway.

### После N1

```text
N2 multi-process lab
→ N3 World Directory и lease service
→ N4 реальный object handoff
```
