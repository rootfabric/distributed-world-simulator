# A2 — зафиксированная архитектура сетевого gameplay

**Checkpoint:** `v16.9.4-architecture-a2-networked-gameplay`
**Build ID:** `a2-networked-gameplay-audit-freeze`
**База доказательств:** принятые H1, H2 и H3
**Статус решения:** `FROZEN_WITH_GATES`

## 1. Назначение

A2 не добавляет игровую функцию. Он отделяет то, что действительно доказано H1–H3, от целевой архитектуры, которую нельзя размывать при добавлении NATS, нескольких authorities и handoff.

Единственный допустимый семантический путь:

```text
input / UI intent
→ client command gateway
→ versioned command DTO
→ authority command handler
→ authoritative mutation
→ targeted command result
→ snapshot / delta
→ client replica store
→ presentation
```

Runtime topology меняет только placement и transport adapter. Она не должна менять identity, permission, replay или mutation semantics.

## 2. Что доказано

### H1 — graphical listen-host

Доказан фактический игровой путь для player state и Item Graph: inventory, containers, pickup/drop, stack/split, mount/placement и persistence проходят через embedded authority и replica-only client capability.

### H2 — отдельный ENet client и ownership

Доказаны stable logical player identity, неизменный `player_entity_id`, смена transport session, `ownership_epoch` и replay-safe join/leave/rejoin.

### H3 — два одновременных клиента

Доказаны dedicated authority, две независимые ENet sessions, authoritative movement, targeted results, region-wide deltas, permission fencing, contention, disconnect одного peer без остановки другого и reconnect без второй player entity.

## 3. Identity model

Разные идентичности нельзя объединять:

| Identity | Срок жизни | Назначение |
|---|---|---|
| `logical_player_id` | долгий | логический игрок |
| `player_entity_id` | долгий | canonical entity `player/<logical_player_id>` |
| `transport_session_id` | одно соединение | ephemeral transport identity |
| `ownership_epoch` | одна join-generation | защита от старой player session |
| `authority_owner_id` | authority runtime | текущий writer |
| `authority_epoch` | authority generation | защита от старого authority |
| `route_generation` | transport route | смена peer route, не ownership |

Transport session никогда не становится player identity. Spatial identity также не определяет authority ownership.

## 4. Command ownership и permissions

Каждая player mutation должна быть связана с:

```text
logical_player_id
transport_session_id
ownership_epoch
operation_id
payload_fingerprint
```

Authority обязан:

- отклонить stale session и stale ownership epoch;
- запретить игроку менять inventory другого игрока;
- вернуть прежний result при exact replay;
- отклонить тот же operation ID с иным fingerprint;
- не подтверждать каноническую mutation до commit;
- не экспортировать live aggregate/repository/registry reference клиенту.

## 5. Movement replication

Клиент отправляет intent, а не канонический transform. Authority проверяет ownership, input sequence, конечность и bounds движения. Принятая mutation увеличивает revision/tick и выпускает delta.

Политика A2:

- canonical client prediction отсутствует;
- authority snapshot/delta всегда побеждает;
- interpolation допустима только в presentation;
- correction не может изменять operation ledger или canonical identity;
- `last_input_sequence` монотонен внутри ownership generation.

## 6. Inventory и contention

Authority является единственным serializer contested mutations. Результат борьбы за один stable item:

```text
one success
one deterministic rejection
world + inventories contain exactly one item identity
```

H1 доказал полный Item Graph command path. H3 доказал contention на уменьшенном shared-item fixture. До N3 этот fixture должен быть заменён canonical H1 gameplay service, а не развит как отдельный домен.

## 7. Reconnect и replay

При reconnect:

- `logical_player_id` сохраняется;
- `player_entity_id` сохраняется;
- transport session меняется;
- `ownership_epoch` растёт;
- старая session теряет право записи;
- exact command replay не повторяет mutation;
- disconnect одного peer не останавливает listener или других peers.

R3.1/H1 доказывают persistence, но dedicated H2/H3 fixtures пока не доказывают crash/restart recovery ownership/gameplay state. Это обязательный gate перед N3.

## 8. Peer mapping и relevance

Authority registry является единственным источником mapping:

```text
one active transport session → at most one logical player
one logical player → at most one active transport session
```

Текущая relevance-модель ограничена одной server region. Command results targeted, gameplay deltas рассылаются всем peers тестовой region. Distance interest, ghosts, overlap и bandwidth priority не определены и относятся к N6.

## 9. Client capability boundary

Клиенту разрешены только:

- отправка versioned commands;
- получение targeted results;
- приём validated snapshots/deltas;
- чтение deep-copied replica state.

Запрещены live authority object, aggregate registry, repository write port, `Node`/`SceneTree` через DTO и локальное создание authority графическим клиентом.

H2/H3 replica stores используют authority/registry scripts как validators. Live authority reference отсутствует, но code coupling должен быть устранён выделением shared contract validators до N3.

## 10. Итог аудита

Целевой semantic pipeline и invariants заморожены. При этом реализации H1, H2 и H3 ещё не являются одной production service implementation:

- `PlayableListenHostAuthority`;
- `PlayerOwnershipRegistry`;
- `MultiplayerGameplayAuthority`.

Два клиента H3 — headless protocol clients, а contention использует reduced fixture. Поэтому A2 разрешает B1 только как adapter-only этап поверх B0, но блокирует multi-authority N3–N6 до закрытия `A2-D01…A2-D04`.

## 11. Правила B1

B1 может добавлять NATS Core adapters для discovery, heartbeat, health/load и request/reply. Он не может:

- вводить новый gameplay command model;
- вызывать NATS напрямую из gameplay/domain;
- хранить subject/channel/broker ID в canonical state;
- использовать broker delivery как authority ownership;
- обходить B0 semantic ports.

In-memory и NATS adapters обязаны давать одинаковые B0 results и DTO checksums.

## 12. Change control

Identity, ownership, permissions, movement, replay, contention, peer mapping и client capability boundary считаются frozen contracts. Breaking change требует нового architecture checkpoint, новой schema version и migration plan.

## 12. Post-A2 delivery order

После независимой приёмки A2 target остаётся `FROZEN_WITH_GATES`, но основной delivery order уточнён: `M1–M6 → A3 → B1/B2 → N3–N6`. B1 по-прежнему архитектурно допустим как adapter, однако не является ближайшим приоритетом. A2-D01/D02 закрывает M1, A2-D03 — M3–M5, A2-D04 — M6.

## M1 closure update

Candidate `v16.10.0-runtime-m1-unified-networked-gameplay-core` свёл H1/H2/H3 к общей composition root и вынес validators из authority implementations. `A2-D01` и `A2-D02` отмечены closed by M1. `A2-D03` и `A2-D04` остаются открыты до M3–M6.
