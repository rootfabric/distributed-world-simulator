# H3 — dedicated host и два клиента

## Checkpoint

```text
v16.9.3-runtime-h3-dedicated-multiplayer
base: v16.9.2-runtime-h2-host-client-ownership
branch: feature/h3-dedicated-multiplayer
status: accepted
```

## Цель

H3 доказывает минимальный реальный multiplayer-контур в трёх отдельных Godot-процессах:

```text
headless dedicated authority
├─ ENet client A
└─ ENet client B
```

Оба клиента используют один и тот же versioned gameplay protocol. Клиент не получает ссылок на authority, aggregate, `Node`, `SceneTree` или repository port.

## Реализованный путь

```text
JOIN
→ authoritative Player Ownership
→ initial gameplay snapshot
→ movement command
→ targeted command result
→ gameplay delta всем peers региона
→ contention за общий item
→ один commit / один deterministic rejection
→ leave клиента A
→ клиент B продолжает mutation
→ reconnect клиента A
→ та же player entity, новый ownership epoch
→ одинаковый финальный checksum у authority, A и B
```

## Authoritative модель

`MultiplayerGameplayAuthority` хранит:

- stable logical player и `player/<id>` identity;
- текущую transport session и ownership epoch;
- authoritative position, velocity и input sequence;
- отдельный inventory каждого игрока;
- один общий world item для contention-сценария;
- monotonic revision и server tick;
- operation ledger для exact replay и replay conflict;
- canonical snapshot и delta с checksum.

Каждая mutation требует совпадения:

```text
logical_player_id
transport_session_id
ownership_epoch
operation_id + payload fingerprint
```

## Реплика клиента

`MultiplayerGameplayReplicaStore` принимает только validated snapshot/delta. Он отклоняет:

- authority owner/epoch mismatch;
- revision rollback;
- same-revision mutation;
- delta base mismatch;
- повреждённый checksum;
- неизвестный event type;
- неожиданные поля player state;
- duplicate player identity или transport session;
- некорректную структуру shared item.

## Contention

Клиенты A и B одновременно отправляют pickup одного `item/shared/beacon/1`.

Authority сериализует команды:

```text
первый принятый command → SUCCEEDED
второй command → ITEM_ALREADY_CLAIMED
```

После завершения:

- world item недоступен;
- item присутствует ровно в одном inventory;
- оба клиента видят одинакового победителя;
- финальные checksums authority/A/B совпадают.

## Disconnect и reconnect

Клиент A выполняет explicit leave и открывает новую ENet transport session. Player entity не создаётся повторно:

```text
player_entity_id: player/a → player/a
ownership_epoch: 1 → 2
```

Пока A отсутствует, B выполняет вторую movement mutation. Listener остаётся в `LISTENING` и не зависит от lifecycle одного peer.

## Проверки

Focused H3:

```text
test_h3_multiplayer_gameplay_contracts.gd
test_h3_dedicated_multiplayer_processes.gd
```

Профиль `RUN_H3_DEDICATED_MULTIPLAYER_TESTS` также запускает H2, H1/H0 и T1 regression.

## Ограничения checkpoint

H3 доказывает gameplay semantics, ownership, replication и contention в одной server region. Он пока не добавляет:

- production authentication;
- client prediction и interpolation реальной graphical сцены;
- несколько authority servers;
- World Directory и cross-server handoff;
- глобальный interest management;
- NATS/JetStream transport adapters.

Следующий обязательный этап после принятия H3 — `A2 Networked Gameplay Architecture`, без добавления нового gameplay-кода.
