# Checkpoint v16.10.1 — M2 Dedicated Graphical Client

## Метаданные

```text
checkpoint: v16.10.1-runtime-m2-dedicated-graphical-client
build_id: m2-dedicated-graphical-client
base: v16.10.0-runtime-m1-unified-networked-gameplay-core
branch: feature/m2-dedicated-graphical-client
status: candidate
```

## Реализовано

- роли `dedicated-server` и `game-client` в общем launch/runtime wiring;
- headless dedicated authority на едином M1 `NetworkedGameplayService`;
- обычный graphical Godot client без embedded authority;
- ENet join/leave и ownership handshake;
- stable `player/local-astronaut` identity;
- initial player и Item Graph synchronization;
- authoritative movement и replica correction;
- replica inventory/hotbar;
- graceful disconnect и reconnect к той же entity;
- ownership epoch `1 → 2`;
- отдельные process-scoped operation IDs;
- automated real graphical process acceptance через X11/renderer;
- отдельные user-data каталоги server/client phase 1/client phase 2.
- сетевой `playground` с authoritative spawn `(0, 1.2, 6.0)`, replica
  inventory и тем же ENet gameplay path.

## Acceptance

```text
dedicated starts headless and reaches READY
→ graphical client starts without --headless
→ active LunarPlayer camera exists
→ join assigns stable identity
→ movement crosses authority and returns through replica
→ inventory/hotbar use replica state
→ client leaves
→ server remains LISTENING
→ second graphical process reconnects
→ same entity and committed state are restored
→ ownership epoch advances
```

## Не входит

M3 остаётся необходимым для двух одновременных graphical clients, remote player presentation и interpolation. M4/M5 закрывают общий canonical Item Graph contention, M6 — dedicated crash/restart recovery.

## Проверки кандидата

```text
Editor import:                    PASS
M2 graphical client contracts:   96/96 PASS
M2 graphical process acceptance: 82/82 PASS
Focused M2 profile:               16/16 scripts, 1064 assertions PASS
Network/runtime regression:       49/49 suites, 3858 assertions PASS
World regression:                 92/92 tests PASS
Main scene playground:            6/6 PASS
```

`test_m2_dedicated_graphical_processes.gd` запускает lunar reconnect-профиль,
а затем отдельную пару headless dedicated + graphical client для
`playground`. Demo-клиент подтверждает authoritative spawn, движение и
replica inventory в раздельных user-data каталогах.

Общий focused/world runner в поставочном окружении может упираться во внешний лимит длительности одного процесса. Все составляющие exact manifests выполнены отдельно теми же test scripts; `test_world_boot_matrix.gd` завершился `exit 0`, а `main_scene_cli_all` — `6/6 PASS`.
