# Checkpoint готовности PlanetSimulator к сетевому слою

**Дата ревизии:** 28 июля 2026 года
**Текущий проверенный checkpoint:** `v16.5.0-network-n1-snapshot`
**Фактическая сетевая стадия:** N1.0 принят; N1.1 ENet handshake + initial snapshot реализован как candidate

## 1. Проверенная база

Ревизия архива подтверждает:

- Godot `4.7.1 stable double custom build`;
- 58 обязательных headless test script;
- 5 runtime-миров;
- 185 импортированных GDScript UID-записей;
- единый Simulator Core;
- полный persistent Item Graph;
- revisions, operation ledger и payload fingerprint;
- gravity field и physics state;
- `SimulationClock`, `FrameGraph`, `SpatialRef`, `PartitionAddress v2`;
- `authority_owner_id` и `authority_epoch` в локальном entity domain.

Lifecycle-блокер закрыт fail-closed: terminal `FAILED` и release fence запрещают обычную загрузку нового мира; `unified_runtime_boot`, `world_boot_matrix` и переключение мира при активной генерации завершают Godot после drain worker-а. Отдельный Python process test запускает `simulation-server` с изолированным профилем и проверяет последовательность `node_ready → node_draining → node_stopped`.

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

## 3. Состояние N0

N0 завершён. Реализованы command/result/snapshot/delta envelopes, canonical
checksums, AuthorityLease/Route, node/space/region descriptors, ghost/client
routes, handoff ticket/result/state machine, golden fixtures, mutation matrix и
JSON loopback для command и replication paths.

Fix1 закрывает post-review обходы: owner не меняется при прежнем epoch,
`state_revision` и `server_tick` не откатываются, delta path не теряет пустые
сегменты, а kernel принимает только точные port scripts с валидным descriptor и
повторно проверенным внутренним snapshot.

В N1.1 уже добавлены:

- настоящий ENet adapter за общим transport port;
- отдельный headless bot-client;
- handshake protocol/capability/contract-version negotiation;
- initial snapshot streaming и checksum acknowledgement между процессами.

До следующих подэтапов намеренно отсутствуют:

- удалённая authoritative item command — N1.2;
- reconnect и replay — N1.3;
- World Directory и lease renewal — N3;
- cross-server handoff — N4.

World Directory и исполняемый lease service относятся к N3; реальный handoff
между процессами — к N4.

## 4. Foundation barriers

### A. Server-safe runtime

Выполнено в `v16.3.2`: server role, lifecycle и process isolation. В `v16.3.3` добавлены pure `SimulationKernel`, optional `PresentationHost` и recursive boundary validation. World runtime scenes пока ещё содержат локальные presentation adapters.

### B. Shutdown lifecycle

Выполнено для текущего локального runtime: command fencing, запрет новых terrain requests, stale/cancel fence, ожидание worker, persistence flush и process exit. N1.1 ENet session выполняет drain/stop; общий application lifecycle будет связан с transport shutdown на N1.3.

### C. Unified WORLD aggregate

Выполнено для WORLD-items в `v16.3.3`: relation хранит `entity_id`, а `SpatialRef`, physics state, authority и lifecycle принадлежат `WorldEntityAggregate`. Общий EntityRegistry остаётся отдельным store, но в `v16.4.0` подключён к `SimulationKernel` через строгий read-only `EntityRegistryKernelPort`; repository подключён через `WorldRepositoryKernelPort`.

### D. Monotonic revisions

Authority transfer увеличивает epoch и не обнуляет state revision.

### E. Formal lifecycle

Выполнено в `v16.3.3` для Entity aggregate, Chunk и Zone runtime:

```text
Dormant / Warm / Active / Unloading
```

### F. Portable snapshot

Snapshot не содержит `NodePath`, `RID`, `Resource`, `Callable` и scene instance ID.

## 5. Решение

Сетевой фундамент N0 и transport boundary N1.0 приняты. N1.1 доказал handshake и initial snapshot. Следующий этап — N1.2: одна удалённая authoritative `item.move_to_container` с checksum equality.

Foundation Gate и N0 завершены в принятом исправленном checkpoint:

```text
v16.4.0-foundation-n0-fix1
```

Подробности:

- `docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`;
- `docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md`;
- `docs/checkpoints/2026-07-27_V16_4_0_FOUNDATION_N0_RU.md`.
- `docs/checkpoints/2026-07-28_V16_4_0_FOUNDATION_N0_FIX1_RU.md`.

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
