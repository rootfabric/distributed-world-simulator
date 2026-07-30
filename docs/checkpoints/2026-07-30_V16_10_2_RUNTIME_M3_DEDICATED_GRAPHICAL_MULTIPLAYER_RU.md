# Checkpoint v16.10.2 — M3 Dedicated Graphical Multiplayer

## Метаданные

```text
checkpoint: v16.10.2-runtime-m3-dedicated-graphical-multiplayer
build_id: m3-dedicated-two-graphical-clients
base: v16.10.1-runtime-m2-dedicated-graphical-client
branch: feature/m3-dedicated-graphical-multiplayer
status: candidate
```

## Реализовано

- один headless dedicated server на M1 `NetworkedGameplayService`;
- два одновременно подключённых ordinary graphical Godot clients;
- stable `player/a` и `player/b`, независимые sessions и ownership;
- local `LunarPlayer` и remote `RemotePlayerPresenter`;
- spawn/despawn и respawn удалённого игрока;
- authoritative transform/velocity/orientation replication;
- replicated flashlight state;
- render interpolation без input authority;
- disconnect A без остановки B;
- authoritative movement B во время отсутствия A;
- reconnect A к той же entity с ownership epoch `1 → 2`;
- convergence barrier server/A/B;
- изолированные user-data roots;
- graphical shutdown log checks.

## Acceptance

```text
A joins
→ B joins while A remains connected
→ A sees B and B sees A
→ both movements cross authority and are mutually observed
→ B observes A orientation and flashlight
→ A disconnects and B continues gameplay
→ A reconnects as the same player entity
→ B respawns A presenter
→ server, A and B converge to one checksum
→ all peers leave without stale server mappings
```

## Проверки кандидата

```text
Editor import:                         PASS
M3 graphical contracts:               63/63 PASS
M3 two-graphical-client process:       56/56 PASS
Focused M3 profile:                    18/18 scripts, 1180 assertions PASS
Network/runtime regression:            51/51 suites, 3989 assertions PASS
World regression:                      94/94 tests PASS
Main scene playground:                  6/6 PASS
ObjectDB/resource leak markers:         0
```

Полный network/world evidence собран по точным manifests. Focused 18 suites и оставшиеся 33 network suites запускались в изолированных process profiles; 43 domain/world suites дополнили network manifest до 94/94 world tests. `test_world_boot_matrix.gd` завершился отдельным чистым процессом с exit code 0.

## Следующий этап

`M4 — Canonical shared gameplay over ENet`: полный H1 Item Graph, inventory/hotbar, pickup/drop, stack/split, external containers, mount/detach и deterministic two-client contention.
