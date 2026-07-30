# M2 — Dedicated server + один графический клиент

**Checkpoint:** `v16.10.1-runtime-m2-dedicated-graphical-client`
**Build ID:** `m2-dedicated-graphical-client`
**База:** принятый `v16.10.0-runtime-m1-unified-networked-gameplay-core`
**Статус:** candidate

## Цель

M2 переводит единый M1 gameplay core в первую настоящую production-топологию без embedded authority:

```text
Process 1: Godot --headless --role=dedicated-server
Process 2: обычный Godot window --role=game-client
```

Оба процесса загружают обычную `main.tscn`. Dedicated создаёт authoritative `NetworkedGameplayService`, graphical client создаёт только transport, command gateway, replica store и presentation.

## Composition

```text
DedicatedGameplayServerRuntime
├─ ENet NetworkTransportBoundaryV2
├─ NetworkedGameplayService / CANONICAL_PLAYABLE
├─ join/leave ownership routing
├─ authoritative PlayerInputCommand
└─ canonical PlayerState + ItemGraph snapshot/delta

GraphicalGameClientRuntime
├─ ENet NetworkTransportBoundaryV2
├─ EnetCommandTransportAdapter
├─ ClientRuntime / ClientReplicaStore
├─ PlayableClientSession
├─ PlayableItemCommandBridge
└─ LunarPlayer presentation + local input
```

Graphical runtime не загружает `NetworkedGameplayService` и не получает ссылки на authority или domain aggregates.

## Роль game-client

`game-client` включает presentation и local input, но не является authoritative. `LunarPlayer` работает в `network_replica_mode`:

- локальный `CharacterBody3D` не интегрирует собственную authoritative физику;
- камера, HUD и input остаются активными;
- input преобразуется в ограниченный `PlayerInputCommand` относительно последнего authoritative snapshot;
- correction приходит через replica snapshot/delta;
- inventory и hotbar читаются только из Item Graph replica.

Отдельная canonical interaction-position исключает смешивание локального render origin и server-domain координат.

## Join и reconnect

Logical identity: `local-astronaut`. Stable entity: `player/local-astronaut`.

```text
первый graphical process  → ownership_epoch 1
graceful leave            → server остаётся LISTENING
второй graphical process  → та же entity, ownership_epoch 2
```

Operation ID движения включает PID graphical процесса и sequence. Новый transport session после reconnect не конфликтует с replay ledger предыдущего процесса.

## Автоматическая graphical acceptance

`test_m2_dedicated_graphical_processes.gd` запускает:

1. headless dedicated server;
2. настоящий graphical client phase 1;
3. graceful disconnect;
4. второй настоящий graphical client phase 2 против того же server.

На Linux используется X11 virtual display и `gl_compatibility`/llvmpipe. Клиент не получает `--headless`. На Windows и macOS запускается обычное graphical окно. Server и оба client process используют разные user-data каталоги.

Проверяются:

- активный non-headless DisplayServer;
- настоящий `LunarPlayer` и активная Camera3D;
- stable entity и ownership epoch `1 → 2`;
- authoritative movement без rejection;
- replica inventory и hotbar;
- сохранение player state при reconnect;
- convergence player и Item Graph checksums;
- отсутствие pending ENet messages;
- listener остаётся активным после disconnect;
- отсутствие authority/domain references у клиента.

## Граница M2

M2 доказывает одного настоящего graphical игрока и reconnect. Он не включает:

- два одновременно открытых graphical client;
- `RemotePlayerPresenter`, spawn/despawn и interpolation второго игрока;
- shared two-player Item Graph contention;
- dedicated crash/restart persistence.

Эти границы закрываются M3, M4/M5 и M6 соответственно.
