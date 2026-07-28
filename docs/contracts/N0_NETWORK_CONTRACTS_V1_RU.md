# N0 Network Contracts v1

**Checkpoint:** `v16.4.0-foundation-n0`
**Protocol version:** `1`
**Transport:** только локальный JSON loopback; сетевые сокеты не входят в N0.

## 1. Назначение

N0 фиксирует переносимую границу между canonical simulation и будущим
транспортом. DTO не содержат Godot runtime objects и одинаково проверяются до и
после JSON round-trip.

Главный инвариант:

```text
canonical simulation ≠ presentation ≠ transport
```

## 2. Общие правила

Для всех versioned DTO действуют:

- точный набор обязательных полей;
- неизвестные поля отклоняются;
- строки и числа не преобразуются из других JSON-типов;
- integer должен быть целочисленным JSON number в диапазоне `±(2^53−1)`;
- `NaN`, `Infinity`, нестроковые ключи и Godot runtime objects запрещены;
- нормализация выполняет JSON round-trip и детерминированную сортировку ключей;
- fingerprints/checksums вычисляются по canonical payload;
- неизвестные schema/protocol version отклоняются fail closed.

Запрещённые runtime-значения:

```text
Node, Object, Resource, RID, Callable, Signal, NodePath
```

## 3. Command path

### `planet_simulator.network_command.v1`

Поля:

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

`operation_id` определяет доменную идемпотентность. `message_id` относится только
к конкретной доставке. Fingerprint не зависит от `message_id` и времени
транспортной отправки.

### `planet_simulator.network_command_result.v1`

Статусы:

```text
SUCCEEDED
REJECTED
RETRYABLE
```

`SUCCEEDED` и `REJECTED` являются терминальными для operation replay.
`RETRYABLE` не сохраняется как завершённая операция.

Некорректный результат handler-а превращается в терминальный:

```text
REJECTED / INVALID_HANDLER_RESULT / requires_snapshot=true
```

Это не позволяет повторной доставке повторить уже выполненную мутацию.

## 4. Entity snapshot и delta

### `planet_simulator.entity_snapshot_envelope.v1`

Поля:

```text
schema
protocol_version
snapshot_id
entity_id
entity_type
state_revision
authority_owner_id
authority_epoch
server_tick
spatial_ref
partition_address
physics_state
domain_components
checksum
```

`spatial_ref` проверяется по точной схеме `planet_simulator.spatial_ref.v1`.
Quaternion должен быть near-unit; `q` и `−q` канонизируются к одному
представлению и checksum.

Checksum вычисляется по всем полям кроме самого `checksum`.

### `planet_simulator.entity_delta_envelope.v1`

Delta содержит:

```text
delta_id
entity_id
entity_type
base_revision
result_revision
authority_owner_id
authority_epoch
server_tick
changed_fields
removed_fields
checksum
```

Изменения задаются каноническими путями внутри разрешённых корней:

```text
spatial_ref
partition_address
physics_state
domain_components
```

Примеры:

```text
physics_state.sleeping
domain_components.item.condition
```

Обязательные корни snapshot удалить нельзя. Пересекающиеся parent/child paths
отклоняются. Delta применяется только к строго валидному snapshot с совпадающими
`entity_id`, `entity_type`, `base_revision` и `authority_epoch`. После применения
пересчитывается checksum и результат повторно проходит строгую snapshot validation.

## 5. Authority contracts

### `planet_simulator.authority_lease.v1`

Lease фиксирует временное право записи для `ENTITY` или `REGION`:

```text
lease_id
subject_type
subject_id
owner_node_id
authority_epoch
issued_at_tick
renew_after_tick
expires_at_tick
state_revision_at_acquire
lease_token_hash
status
```

N0 реализует только контракт и проверки окна. Выдача/renew/revoke сервиса World
Directory относится к N3.

### `planet_simulator.authority_route.v1`

Route связывает entity/region с owner node, lease, endpoint и epoch. Для
`REGION` значения `subject_id` и `region_id` обязаны совпадать.

### Descriptors

```text
planet_simulator.simulation_node_descriptor.v1
planet_simulator.simulation_space_descriptor.v1
planet_simulator.authority_region_descriptor.v1
```

Simulation-server обязан объявить хотя бы одно space. `instance_id` node и всех
space descriptors должен совпадать. Region selector поддерживает:

```text
GLOBAL_SPACE
PARTITION_PREFIX
CHUNK_SET
```

## 6. Ghost и client route

### `planet_simulator.ghost_replica_state.v1`

Ghost всегда read-only, имеет source epoch, snapshot hash, interest scope и TTL.
Контракт не даёт ghost write authority.

### `planet_simulator.client_route.v1`

Client route содержит primary и необязательный secondary endpoint для будущего
make-before-break handoff. Primary и secondary node не могут совпадать.

## 7. Handoff

Контракты:

```text
planet_simulator.handoff_ticket.v1
planet_simulator.handoff_result.v1
planet_simulator.handoff_state_machine.v1
```

Состояния:

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

- commit разрешён только после `TARGET_PREPARED`;
- target epoch строго больше source epoch;
- transition revision монотонен;
- transition tick не движется назад;
- direct `EXPIRED` запрещён до `expires_at_tick`;
- prepared transition защищён source hash, candidate hash и prepared token;
- identity ticket нельзя изменить между prepare и commit;
- повтор terminal transition идемпотентен;
- abort/expire не меняют owner aggregate;
- commit aggregate повышает authority epoch и state revision ровно один раз.

`WorldEntityHandoffSession` принимает только canonical `WorldEntityAggregate` и
выполняет staged authority transfer с rollback при отказе machine commit.
Реальная передача между процессами относится к N4.

## 8. Loopback transports

### Command loopback

```text
CommandEnvelope
→ JSON
→ NetworkCommandGateway
→ handler
→ ResultEnvelope
→ JSON
```

Проверяются replay, operation conflict, stale epoch и invalid handler result.

### Replication loopback

```text
SnapshotEnvelope
→ JSON
→ local snapshot store
→ DeltaEnvelope
→ strict apply
→ new SnapshotEnvelope
```

Поддерживаются exact snapshot replay, snapshot revision conflict, stale epoch,
delta replay, delta ID conflict и snapshot-required rejection.

## 9. Kernel ports

Pure ports:

```text
EntityRegistryKernelPort
WorldRepositoryKernelPort
```

Порты:

- хранят только canonical snapshot;
- не содержат callback/Node/scene references;
- имеют строгий descriptor schema;
- регистрируются в `SimulationKernel` только после проверки schema/configured;
- подтверждаются настоящим process-level `simulation-server` тестом.

Repository port не выполняет callback flush. Он формирует versioned
`repository_flush_request.v1`, который позднее обработает orchestration layer.

## 10. Golden fixtures и runners

Canonical fixtures находятся в:

```text
config/network/fixtures/
```

Они покрывают command, snapshot, delta, endpoint, lease, route, space, node,
region, ghost, client route, handoff ticket и handoff results.

Запуск:

```powershell
.\RUN_NETWORK_CONTRACT_TESTS.ps1
```

Отчёт:

```text
artifacts/test-results/network-contract-summary.json
```

Полный regression:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

## 11. Не входит в N0

- ENet/WebSocket connection;
- удалённый bot client;
- snapshot streaming между процессами;
- World Directory service;
- lease renewal service;
- реальный authority handoff;
- client prediction;
- interest filtering runtime;
- Kubernetes, Agones, NATS.
