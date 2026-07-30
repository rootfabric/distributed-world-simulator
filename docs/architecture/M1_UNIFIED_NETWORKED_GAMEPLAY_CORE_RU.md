# M1 — Unified Networked Gameplay Core

**Checkpoint:** `v16.10.0-runtime-m1-unified-networked-gameplay-core`  
**Build ID:** `m1-unified-networked-gameplay-core`  
**База:** принятый `v16.9.5-roadmap-single-server-multiplayer-first`  
**Статус:** candidate

## Цель

M1 закрывает `A2-D01` и `A2-D02`: H1, H2 и H3 больше не содержат независимые authority-модели gameplay. Их публичные API сохранены как compatibility adapters, а каноническая логика размещена в одном `NetworkedGameplayService`.

```text
NetworkedGameplayService
├── PlayerRegistry
├── PlayerOwnershipService
├── PlayerMovementService
├── ItemGraphService
├── ContainerInteractionService
├── MountInteractionService
├── CommandResultRouter
└── ReplicationPublisher
```

## Профили и топологии

Один сервис поддерживает два production-профиля:

- `CANONICAL_PLAYABLE` — H1 Item Graph, inventory, containers, mount/detach и player movement;
- `MULTIPLAYER_CORE` — H2/H3 ownership, movement, replication, permissions и contention fixture.

Топология не входит в каноническое состояние:

```text
listen-host → LOOPBACK adapter
H2/H3 tests → ENET adapter
```

Одинаковая последовательность join, movement, contention, leave и reconnect даёт идентичный canonical JSON и checksum для LOOPBACK и ENET.

## Общие wire contracts

В `scripts/runtime/networked_gameplay/contracts` выделены независимые validators:

- `PlayerJoinCommand`;
- `PlayerLeaveCommand`;
- `PlayerInputCommand`;
- `PlayerOwnershipSnapshot`;
- `PlayerStateSnapshot`;
- `PlayerStateDelta`;
- `ItemCommand`;
- `ItemGraphSnapshot`;
- `ItemGraphDelta`;
- `CommandResult`.

Контракты versioned, JSON-safe, exact-field и checksum-bound. Они не загружают H1/H2/H3 authority-классы, `Node` или `SceneTree`.

## Compatibility boundary

- `PlayableListenHostAuthority` делегирует `NetworkedGameplayService/CANONICAL_PLAYABLE`;
- `PlayerOwnershipRegistry` делегирует `PlayerOwnershipService`;
- `MultiplayerGameplayAuthority` делегирует `NetworkedGameplayService/MULTIPLAYER_CORE`;
- H2/H3 replica stores валидируют DTO через общие contracts, а не через authority implementation.

Client/UI capability boundary не изменён: прямые authority, repository, registry и domain references не экспортируются.

## Граница M1

M1 не заявляет закрытие следующих этапов:

- graphical dedicated client — M2;
- два graphical clients и remote presentation — M3;
- полный canonical Item Graph contention по ENet — M4;
- graphical process acceptance — M5;
- dedicated crash/restart recovery — M6.

`MULTIPLAYER_CORE` сохраняет H3 shared-item fixture только для обратной совместимости. Канонический H1 Item Graph уже включён в общую composition root, но его полный dedicated multiplayer путь является M4.
