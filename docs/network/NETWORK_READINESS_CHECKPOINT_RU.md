# Checkpoint готовности PlanetSimulator к сетевому слою

**Дата ревизии:** 27 июля 2026 года
**Текущий проверенный checkpoint:** `v16.3.0-r2-inventory-ux`
**Фактическая сетевая стадия:** до `N0`

## 1. Проверенная база

Ревизия архива подтверждает:

- Godot `4.7.1 stable double custom build`;
- 34 обязательных headless test scripts;
- 5 runtime-миров;
- 133 global GDScript classes;
- единый Simulator Core;
- полный persistent Item Graph;
- revisions, operation ledger и payload fingerprint;
- gravity field и physics state;
- `SimulationClock`, `FrameGraph`, `SpatialRef`, `PartitionAddress v2`;
- `authority_owner_id` и `authority_epoch` в локальном entity domain.

Два тяжёлых Linux runtime-теста достигают `PASS`, но процесс может оставаться живым
из-за фонового terrain worker. Для multi-process network lab это считается
lifecycle-блокером, а не допустимым шумом.

## 2. Что уже готово для повторного использования

### Identity

```text
entity_id / item_id
universe_id
instance_id
space_id
frame_id
state_revision
authority_owner_id
authority_epoch
```

UUID не меняется при container/mount/world переходах и будущем handoff.

### Canonical coordinates

Сетевой слой должен передавать `SpatialRef`, а не `global_transform` как
единственную истину.

### Safe commands

Уже доступны:

```text
operation_id
payload_hash
expected_revision
result_revision
operation ledger
```

### Transactional state

Item Registry, Container Registry, Attachments и operation ledger сохраняются
единым fail-closed snapshot.

### Observability

Есть JSONL logging, runtime tests и JSON regression report.

## 3. Что существует только в документации

В коде пока отсутствуют:

- network command/snapshot envelopes;
- authority lease и route;
- handoff ticket/state machine;
- simulation-server/client roles;
- ENet adapter;
- Python process harness;
- World Directory;
- network tests.

Поэтому нельзя считать, что N0 уже начат или завершён.

## 4. Foundation barriers

### A. Server-safe runtime

- `--role=simulation-server`;
- kernel без UI и камеры;
- presentation отключаем;
- отдельный `user://`;
- JSONL `node_ready/node_stopped`;
- корректный exit code 0.

### B. Shutdown lifecycle

- запрет новых работ;
- cancel/await terrain workers;
- persistence flush;
- transport close;
- process exit.

### C. Unified WORLD aggregate

Нужна одна canonical spatial truth для Entity и WORLD Item.

### D. Monotonic revisions

Authority transfer увеличивает epoch и не обнуляет state revision.

### E. Formal lifecycle

```text
Dormant / Warm / Active / Unloading
```

### F. Portable snapshot

Snapshot не содержит `NodePath`, `RID`, `Resource`, `Callable` и scene instance ID.

## 5. Решение

Сетевую ветку можно начинать сейчас, но первым этапом является `N0`, а не ENet и
не authority handoff.

Foundation и N0 выполняются параллельно:

```text
v16.4 Foundation Gate
N0 Network Contracts
```

Подробности:

- `docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`;
- `docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md`;
- `docs/checkpoints/2026-07-27_V16_3_FOUNDATION_AND_NETWORK_CHECKPOINT_RU.md`.

## 6. После N0

1. N1 — один authoritative server и bot client.
2. N2 — local multi-process lab.
3. N3 — World Directory и leases.
4. N4 — handoff одного камня или маяка.
5. Затем player handoff, ghosts, child spaces и dynamic regions.

## 7. Что пока не начинать

- Kubernetes/Agones;
- NATS control plane;
- WAN player handoff;
- distributed collision;
- dynamic Earth split;
- distributed N-body.

## 8. Архитектурный принцип

```text
canonical simulation ≠ presentation ≠ transport
```

Offline mode собирает слои в одном процессе, но не нарушает эту границу.
