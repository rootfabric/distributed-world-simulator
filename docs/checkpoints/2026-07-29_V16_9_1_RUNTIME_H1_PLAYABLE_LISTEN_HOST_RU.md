# Checkpoint v16.9.1 — H1 Playable listen-host

**Build ID:** `h1-playable-listen-host`
**Base:** `v16.9.0-simulation-s1-distributed-compute-fix1`
**Branch:** `feature/h1-playable-listen-host`
**Status:** candidate

## Результат

Обычный запуск PlanetSimulator теперь использует `listen-host`. В одном процессе создаются отдельные embedded authority и graphical client, связанные только versioned command/result/snapshot/delta contracts.

Игровая вертикаль включает:

- authoritative player state;
- player movement через command boundary;
- inventory и hotbar replica;
- pickup/drop;
- stack/split/transfer;
- external container access;
- mount/detach/placement;
- authoritative Item Graph persistence;
- exact replay и collision fencing.

## Новые runtime-компоненты

```text
scripts/runtime/listen_host/
├── playable_state_codec.gd
├── playable_listen_host_authority.gd
├── playable_authority_gateway_adapter.gd
├── playable_item_command_bridge.gd
└── playable_client_session.gd
```

`ItemGameplayController` получил три явных режима:

```text
legacy     — явный offline/tools path
authority  — headless authoritative domain + persistence
replica    — graphical snapshot/delta projection без persistence
```

## Основные инварианты

- F5/default role — `listen-host`;
- UI не получает live authoritative Item Graph или полный `ListenHostRuntime`;
- authority находится вне graphical world tree;
- authority не создаёт presentation objects;
- player/item revisions и server tick монотонны;
- stale revision/epoch/session отклоняются;
- operation replay не создаёт вторую mutation;
- inaccessible container и distant world item отклоняются;
- после detach старые command bridge и client session инвалидированы;
- authoritative и client replica checksums совпадают после accepted delta;
- trusted `SimulatorApp` связывает authority store с `SimulationKernel` напрямую, не через graphical world;
- explicit `--role=offline` остаётся доступным.

## Тесты

```text
tests/runtime/test_h1_playable_listen_host_contracts.gd
tests/runtime/test_h1_playable_listen_host_integration.gd
RUN_H1_PLAYABLE_LISTEN_HOST_TESTS.ps1
RUN_H1_PLAYABLE_LISTEN_HOST_TESTS.sh
```

Локальная проверка на `Godot 4.7.1.stable.double.custom_build.a13da4feb`:

```text
Launch contracts:          39/39 PASS
H0 compatibility:          71/71 PASS
H1 contracts:              76/76 PASS
H1 integration:            32/32 PASS

Network profile:           39/39 suites PASS
Network assertions:      3168/3168 PASS

World tests:               82/82 PASS
World runner steps:        85/85 PASS
Main scene playground:       6/6 PASS
Main scene earth_moon H1:     8/8 PASS
```

Тяжёлые сценарии:

```text
Unified runtime boot:            PASS
World switch during generation: PASS
World boot matrix:              PASS
```

Runtime-роли:

```text
offline:            6 PASS, exit 0
listen-host:        6 PASS, exit 0
simulation-server:  6 PASS, exit 0
active presentation nodes on simulation-server: 0
```

Runtime descriptor печатается после загрузки мира и подтверждает:

```text
world_id:                       earth_moon
playable.attached:              true
client_session.configured:      true
direct_client_authority_access: false
direct_client_domain_access:    false
```

## Acceptance boundary

H1 считается принятым после независимого подтверждения:

```text
F5/default → listen-host
player and item operations cross DTO boundary
no direct client-authority/domain references
save/restart restores authoritative Item Graph
H0–S1 regression remains green
world regression and main scene pass
```

## Следующий этап

`H2 — Dedicated server + 1 graphical client`.
