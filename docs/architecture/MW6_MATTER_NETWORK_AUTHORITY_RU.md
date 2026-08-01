# MW6 — сетевой авторитет и репликация matter mutations

## Статус

```text
checkpoint: v17.6.0-simulation-mw6-matter-network-replication
base: v17.5.0-simulation-mw5-matter-persistence / fix7 (ACCEPTED)
branch: feature/mw6-matter-network-replication
scope: isolated asteroid matter track
production Moon changed: false
world catalog changed: false
```

## Цель

MW6 переносит принятые транзакции MW4 и durable state MW5 через уже существующую single-server network boundary проекта. Сервер остаётся единственным владельцем канонического `MatterExcavationService`; клиент способен только сформировать команду и поддерживать replica store.

MW6 не создаёт второй gameplay transport. Команды используют принятые `NetworkCommandEnvelope`, `NetworkCommandGateway` и loopback/ENet-compatible command path. Репликация использует принятый `ReplicationEnvelope` и `ReplicationTransportPort`.

## Инварианты авторитета

1. Только сервер вызывает `MatterExcavationService.execute()`.
2. Peer привязан к `client_id`, `session_id` и `actor_id`.
3. `request.actor_id` обязан совпадать с actor binding активной сессии.
4. `authority_epoch` проверяется gateway и matter authority.
5. Brick revisions остаются каноническим optimistic-concurrency fence MW4.
6. Exact replay не создаёт второй delta и не повышает stream sequence.
7. Новый terminal journal outcome реплицируется даже при `REJECTED`, чтобы client journal и state hash не расходились.

## Exact wire payload

Matter DTO нельзя помещать в обычный decimal JSON: Godot не гарантирует побитовый binary64 roundtrip. Поэтому request, result, brick snapshots, store state и journal state передаются строкой:

```text
planet_simulator.matter_persistence_transport.v1
ieee754-binary64-le-hex
```

Внешний network envelope содержит только строки, JSON-safe integers и checksums. Таким образом MW6 повторно использует доказанный MW5 transport, не меняя checksum-domain MW0–MW4.

## Поток команды

```text
MatterMutationRequest
→ exact binary64 transport String
→ NetworkCommandEnvelope(command_type=MATTER_MUTATION)
→ NetworkCommandGateway
→ MatterAuthoritativeServer actor/epoch/session checks
→ MatterExcavationService.execute()
→ authoritative journal/store commit
→ command result + replication delta
```

Domain result `REJECTED` считается успешно обработанной командой и возвращается в command-result payload. Ошибки ownership, stale session, stale authority epoch и route mismatch являются сетевым отказом.

## Репликационный stream

Каждый новый journal record получает монотонный `stream_sequence`.

`MatterReplicationDelta` содержит:

- previous/target stream sequence;
- exact request/result transport;
- полные snapshots только реально изменённых bricks;
- base и target replica state hashes.

Клиент применяет delta атомарно:

1. проверяет sequence и base state hash;
2. проверяет exact DTO contracts;
3. атомарно записывает brick snapshots;
4. записывает request/result в replica journal;
5. проверяет target state hash;
6. при любом отказе восстанавливает store и journal из backup state;
7. инвалидирует только изменённые MW3 presenters.

## Persistent-only policy

Процедурные bricks revision `0` по сети не передаются. Клиент генерирует их тем же MW1 generator при отсутствии persistent snapshot.

Полный state snapshot содержит MW5 `MatterSparseBrickStore.export_persistence_state()` и `MatterMutationJournal.export_persistence_state()`. Эти состояния уже исключают revision-0 bricks.

## Bootstrap после MW5 recovery

При конфигурации authoritative server начальный `stream_sequence` берётся из размера уже восстановленного mutation journal, а не обнуляется. Replay log после restart пуст, поэтому клиент с более старым sequence получает full persistent snapshot. Это сохраняет durable journal/store state без изобретения несуществующей delta-истории.

## Reconnect

Клиент сообщает:

```text
known_stream_sequence
known_state_hash
```

Сервер выбирает один из режимов:

- `CURRENT` — состояние уже совпадает;
- `DELTA_REPLAY` — replay log содержит непрерывную цепочку, а base hash совпадает;
- `FULL_SNAPSHOT` — sequence отсутствует, вытеснен или hash не совпадает.

Delta с пропуском sequence или неверным base hash не применяется частично: replica выставляет `requires_resync`.

## Acknowledgement

После применения клиент отправляет checksum-protected ack с sequence и state hash. Сервер принимает только hash, известный для этого sequence, и не принимает откат acknowledgement.

## Граница этапа

MW6 не добавляет:

- cross-server authority handoff;
- NATS gameplay transport;
- interest management по дальним planetary regions;
- binary delta compression snapshot channels;
- production Moon integration;
- client-side prediction бурения;
- distributed transaction между matter и production Item Graph.

Эти задачи требуют отдельных checkpoints после принятия single-server authority path.

## Focused acceptance

Runner:

```text
RUN_MW6_MATTER_NETWORK_TESTS.ps1
RUN_MW6_MATTER_NETWORK_TESTS.sh
```

Проверяются:

- bootstrap из непустого MW5 journal/store;
- actor spoofing и stale authority epoch;
- репликация terminal rejected outcome без brick mutation;
- authoritative commit и broadcast двум replicas;
- exact command replay без второго delta;
- operation fingerprint conflict;
- selective presenter invalidation;
- positive и forged ack sequence/hash fence;
- reconnect через contiguous delta replay;
- full snapshot при вытесненном replay log;
- отсутствие revision-0 bricks в snapshot;
- base-hash mismatch и sequence gap без частичного применения.


## Fix1: A3/M6 snapshot-resync boundary

Независимая проверка исходного MW6 подтвердила focused-профиль `130 assertions PASS`, но два запуска полного A3 завершились в process-level M6 с `MULTIPLAYER_DELTA_BASE_MISMATCH`. MW6 matter-код не менял M6, однако новый checkpoint нельзя принимать при нестабильной обязательной regression-матрице.

M3/M6 после каждого gameplay delta отправляет полный authoritative snapshot. Поэтому replica различает:

1. `target_revision == current_revision` и checksum совпадает — exact replay;
2. `target_revision < current_revision` — delta уже полностью перекрыт более новым authoritative snapshot, считается `superseded replay` и не меняет состояние;
3. `target_revision == current_revision`, но checksum отличается — `MULTIPLAYER_SAME_REVISION_MUTATION`;
4. `target_revision > current_revision`, но `base_revision != current_revision` — настоящий gap, generic replica отклоняет его как `MULTIPLAYER_DELTA_BASE_MISMATCH`.

Graphical M3/M6 client обрабатывает четвёртый случай как bounded transport resync: не применяет delta, отмечает `pending_replica_resync` и ожидает следующий полный snapshot. Только успешно валидированный snapshot снимает pending-флаг, увеличивает `snapshot_resyncs` и очищает transient error. Другие ошибки delta остаются fail-closed.

Это не является произвольным игнорированием gap: protocol-specific client полагается на уже существующую обязательную отправку полного snapshot после gameplay delta. Generic replica store продолжает отклонять future gap, что покрыто contract-тестом.

### Наблюдаемость

Replica/client reports дополнены:

- `superseded_deltas`;
- `pending_replica_resync`;
- `delta_base_mismatches`;
- `snapshot_resyncs`.

Process-level M6 acceptance теперь требует, чтобы оба recovered clients завершили работу без sticky `MULTIPLAYER_DELTA_BASE_MISMATCH` и без незавершённого snapshot resync.
