# N0 — сетевые контракты без сокетов

# Статус реализации

**Принят:** `v16.4.0-foundation-n0`.

- [x] command/result/snapshot/delta envelopes;
- [x] exact schema and strict JSON typing;
- [x] canonical checksums/fingerprints;
- [x] AuthorityLease/AuthorityRoute;
- [x] node/space/region descriptors;
- [x] ghost and client route contracts;
- [x] handoff ticket/result/state machine;
- [x] exhaustive handoff transition matrix;
- [x] command and replication JSON loopback;
- [x] canonical golden fixtures;
- [x] mutation matrix and runtime-type lint;
- [x] strict kernel ports;
- [x] separate runner and JSON report.

N0 завершён. Следующий сетевой этап — N1 с реальным transport adapter и bot client.

## Цель

Создать стабильный versioned protocol/domain contract, который можно проверить
полностью локально до выбора transport и запуска нескольких процессов.

## 1. DTO

Добавить pure-domain типы:

```text
NetworkCommandEnvelope
NetworkCommandResultEnvelope
EntitySnapshotEnvelope
EntityDeltaEnvelope
AuthorityLease
AuthorityRoute
SimulationNodeDescriptor
SimulationSpaceDescriptor
AuthorityRegionDescriptor
GhostReplicaState
HandoffTicket
HandoffResult
ClientRoute
```

## 2. Command envelope

Обязательные поля:

```text
schema
protocol_version
message_id
operation_id
entity_id
command_type
payload
expected_revision
authority_epoch
client_tick
sent_at_monotonic_ms
```

Команда не содержит:

- `Node`;
- `NodePath`;
- `RID`;
- `Resource`;
- `Callable`;
- scene instance ID;
- render-local transform как единственную координатную истину.

## 3. Snapshot envelope

Минимальный состав:

```text
schema
protocol_version
snapshot_id
entity_id
entity_type
authority_owner_id
authority_epoch
state_revision
spatial_ref
partition_address
physics_state
domain_components
checksum
server_tick
```

## 4. Canonical serialization

Требования:

- сортировка ключей;
- full-precision числа;
- JSON-safe arrays;
- canonical hash;
- стабильные fixtures в репозитории;
- неизвестная schema/version отклоняется fail-closed.

## 5. Authority lease

Даже до реализации World Directory контракт должен содержать:

```text
lease_id
entity_or_region_id
owner_node_id
authority_epoch
issued_at_tick
expires_at_tick
renew_after_tick
state_revision_at_acquire
```

## 6. Handoff state machine

Pure-domain состояния:

```text
REQUESTED
PREPARING
FROZEN
SNAPSHOT_READY
TARGET_PREPARED
COMMITTED
ABORTED
EXPIRED
```

Инварианты:

- одновременно один authoritative owner;
- epoch увеличивается при commit;
- stale epoch не может мутировать aggregate;
- abort не меняет owner;
- commit без target prepared запрещён;
- повтор commit идемпотентен.

## 7. Local loopback

Определить интерфейс transport:

```text
CommandTransport
SnapshotTransport
```

Для N0 реализовать только:

```text
LocalLoopbackTransport
```

Domain service не должен знать, пришла команда локально или по сети.

## 8. Golden fixtures

Добавить fixtures минимум для:

- valid command;
- valid full snapshot;
- stale authority epoch;
- unsupported protocol version;
- valid lease;
- valid handoff ticket;
- aborted handoff;
- committed handoff.

## 9. Тесты

Обязательный набор:

1. canonical JSON round-trip;
2. deterministic payload hash;
3. duplicate message replay;
4. same operation ID with other payload conflict;
5. stale epoch rejection;
6. unsupported version rejection;
7. DTO runtime-type lint;
8. snapshot checksum round-trip;
9. legal handoff transitions;
10. illegal handoff transitions;
11. authority revision monotonicity;
12. loopback command result equality.

## 10. Runner

Добавить:

```text
RUN_NETWORK_CONTRACT_TESTS.ps1
```

И JSON report:

```text
artifacts/test-results/network-contract-summary.json
```

## 11. Критерий выхода N0

N0 принят, когда:

- все DTO versioned и документированы;
- fixtures проходят round-trip;
- contract lint не находит Godot runtime types;
- handoff state machine полностью покрыта тестами;
- old authority epoch отклоняется;
- offline command path может работать через loopback adapter;
- никакие сетевые сокеты ещё не требуются.
