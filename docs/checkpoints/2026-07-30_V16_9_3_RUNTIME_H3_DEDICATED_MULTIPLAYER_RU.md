# Checkpoint v16.9.3 — H3 dedicated multiplayer

```text
checkpoint: v16.9.3-runtime-h3-dedicated-multiplayer
build_id: h3-dedicated-two-client-gameplay
base checkpoint: v16.9.2-runtime-h2-host-client-ownership
base repository commit: main @ 0513be0
branch: feature/h3-dedicated-multiplayer
status: accepted
```

## Реализовано

- отдельный headless dedicated server;
- два одновременных ENet client process;
- stable player identities и независимый ownership;
- replicated movement обоих игроков;
- targeted command results и region-wide gameplay deltas;
- отдельные inventories и permission fencing;
- authoritative contention за общий world item;
- disconnect A без остановки B или listener;
- reconnect A без второй player entity;
- ownership epoch `1 → 2`;
- одинаковый финальный checksum authority, client A и client B.

## Focused acceptance

```text
H3 contracts: 50 assertions
H3 three-process ENet scenario: 33 assertions
```

## Regression gate

```text
H2 ownership: 23 + 12 assertions
H1/H0 compatibility: 218 assertions
T1 transport: 121 + 20 assertions
Network/runtime: 39/39 suites, 3168 assertions
World: 82/82 tests
Main scene CLI: 6/6 PASS
Editor import: PASS
```

## Acceptance criteria

- ровно две stable player entities;
- оба клиента видят движение другого игрока;
- contention имеет ровно один success и один `ITEM_ALREADY_CLAIMED`;
- shared item существует ровно в одном inventory;
- B продолжает mutation после ухода A;
- A reconnect сохраняет `player/a` и увеличивает epoch;
- listener остаётся `LISTENING`;
- финальные checksums совпадают;
- H2/H1/T1/network/world regressions зелёные.

После независимого принятия H3 следующий этап — `A2 Networked Gameplay Architecture audit/freeze`.
