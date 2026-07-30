# M4 — Canonical shared gameplay over ENet

Checkpoint: `v16.10.3-domain-m4-canonical-shared-gameplay`.

M4 добавляет к принятой M3-топологии отдельный authoritative Item Graph channel. Player state и Item Graph имеют независимые revision/checksum, но обрабатываются одной composition root `NetworkedGameplayService`.

## Путь команды

```text
graphical client
→ ITEM_COMMAND / ENet
→ M3DedicatedServerRuntime
→ NetworkedGameplayService
→ CanonicalMultiplayerItemGraphService
→ targeted COMMAND_RESULT
→ ITEM_GRAPH_SNAPSHOT всем подключённым клиентам
```

Клиент хранит только JSON-safe replica snapshot и не получает ссылок на authority или domain objects.

## Поддержанные операции

- pickup/drop;
- stack/split;
- hotbar selection;
- external container open/close и перенос;
- mount/detach;
- permission probe;
- replay-safe operation ID.

## Contention

Два клиента конкурируют за `item/shared/beacon/1`. Первый authoritative command получает `SUCCEEDED`, второй — `ITEM_ALREADY_CLAIMED`. Во всех snapshots остаётся ровно одна item identity.

## Граница

M4 доказывает canonical shared gameplay через два graphical Godot protocol process. M5 должен поднять действия до полностью UI-driven game-window acceptance, используя реальные inventory widgets и interaction input.
