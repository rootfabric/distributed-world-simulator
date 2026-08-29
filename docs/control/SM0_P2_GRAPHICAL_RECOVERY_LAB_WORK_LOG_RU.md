# SM0-P2 — Graphical Recovery Lab work log

Статус: **WINDOWS GRAPHICAL FUNCTIONAL PASS / PERFORMANCE FINDING OPEN**.

Scope: branch-local experimental presentation/test surface. Никакой production/global/V0-S1 acceptance этим документом не объявляется.

## База

H4.3 exact runtime-tested SHA:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

H4.3 runtime evidence commit:

`db87444a06c24541ba3a10b3825918e9bd7c6d67`

H4.3 work log closed commit:

`0a007d428614e1e8084ff5df1cdbb1e1ed6c7bb2`

## P2 implementation dynamics

### Design

Commit:

`2b5b02acc54fad68b9de846e1029ab36bdcd9d40`

File:

`docs/control/SM0_P2_GRAPHICAL_RECOVERY_LAB_DESIGN_RU.md`

Defined presentation-only projection of the already-tested H4.3 same-transfer recovery chain.

### Graphical recovery projection

Commit:

`f62bb441befb7d06700b3d33ff45785712eb98ea`

File:

`scripts/runtime/seamless/sm0/sm0_graphical_recovery_lab.gd`

The scene inherits the P1 graphical handoff lab, therefore manual movement still uses `sm0_manual_client_node.gd` and authoritative client view state. Added presentation-only recovery HUD with:

- server A/B process state;
- durable phase and generation;
- source/target;
- exact transfer id;
- chain/outage status;
- large total-outage banner;
- world beacons for A/B online/recovering/down state.

The presentation JSON is read only by the graphical scene. Authority processes never consume it.

### Scene

Commit:

`8bd01db98f7699622acd6008653ef8b9c256f296`

File:

`scenes/testing/sm0_graphical_recovery_lab.tscn`

### Graphical recovery supervisor

Commit:

`62f3a3c2cd9dcd74a680f700bc6d4358f21de4e7`

File:

`RUN_V0_SM0_GRAPHICAL_RECOVERY_LAB.ps1`

Supervisor responsibilities:

- exact custom-double Godot version check for console and graphical binaries;
- clean-worktree guard and generated `.uid` cleanup;
- compile checks for P1/P2 graphical client plus H4.3 recovery-chain fault/server process;
- headless smoke of P2 scene;
- two authority startup using existing `h4-recovery-of-recovery-same-transfer-v1` and one recovery root;
- graphical manual client startup;
- durable H4.3 marker observation;
- visible pause at PREPARED / COMMITTED / ACTIVE;
- simultaneous A+B process kill with maximum 500 ms kill-request gap;
- visible zero-authority hold;
- target/source restore from same durable recovery files;
- exact transfer-id continuity checks COMMITTED and ACTIVE;
- terminal crossing count wait;
- automatic opposite-direction next chain until user closes window;
- `-Stop` / `-Restart` session lifecycle;
- optional `-RequireRecoveries N` local verification gate.

No production recovery node or canonical protocol contract is changed by P2.

## Static workflow

Project Control run #611 for commit `62f3a3c2cd9dcd74a680f700bc6d4358f21de4e7`: **SUCCESS**.

This is static/control evidence only.

## First Windows graphical runtime — functional result

Локальный runtime: 2026-08-16.

Exact tested implementation SHA:

`62f3a3c2cd9dcd74a680f700bc6d4358f21de4e7`

Exact Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

Graphical client PID:

`24952`

Log directory:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0GraphicalRecoveryLab\logs\20260816-104845`

Пользователь визуально подтвердил движение, смену состояния/цвета authority beacons и repeated sector crossings. До момента наблюдения успешно завершены четыре recovery chain в одном graphical client process:

1. A -> B, transfer `handoff/sm0/a/2/1`, crossing #1, directory epoch 2, player `player/a`.
2. B -> A, transfer `handoff/sm0/b/3/1`, crossing #2, directory epoch 3, player `player/a`.
3. A -> B, transfer `handoff/sm0/a/4/2`, crossing #3, directory epoch 4, player `player/a`.
4. B -> A, transfer `handoff/sm0/b/5/2`, crossing #4, directory epoch 5, player `player/a`.

Observed `SM0_CROSSING_COMPLETED` positions remained close to the x=0 authority boundary and state was transferred rather than respawned:

- crossing #1: x ~= `0.0303`, z ~= `-1.7803`;
- crossing #2: x ~= `-0.2197`, z ~= `0.7197`;
- crossing #3: x ~= `0.1036`, z ~= `1.4571`;
- crossing #4: x ~= `-0.1893`, z ~= `1.4571`.

Directory epochs progressed contiguously 1 -> 2 -> 3 -> 4 -> 5 and `player_entity_id` remained `player/a`.

### Handoff latency observed

Client route-switch -> crossing-complete time increased across the observed chains:

- #1: 18037 -> 24503 ms = about 6.47 s;
- #2: 34612 -> 41369 ms = about 6.76 s;
- #3: 71117 -> 78238 ms = about 7.12 s;
- #4: 93655 -> 101267 ms = about 7.61 s.

Most of this latency is intentional P2 presentation/fault orchestration. Default supervisor holds each of three durable phases for 850 ms and each of three total-outage windows for 1100 ms, giving 5.85 s of deliberate delay per crossing before restart/restore overhead.

### Performance finding — progressive movement stutter

The user also observed that after several sector crossings ordinary movement becomes slower and visibly jerky.

This is consistent with the exact current SM0 durability composition and is not explained by identity replacement or incorrect directory routing.

In recovery mode `sm0_authority_server_node_active_recovery.gd` requires every successful `MOVE_ACK` to persist an `ACTIVE_OWNER` recovery snapshot before the ACK is sent. The snapshot path exports full canonical gameplay state plus full gameplay replay state, validates/checksums them, serializes JSON, flushes the file, closes it and atomically renames it.

The graphical/manual client permits only one outstanding movement request and starts the next move only after the previous ACK is cleared; nominal move cadence is 50 ms. Therefore synchronous recovery persistence is directly on the input/ACK critical path.

The recovery generation values in this run demonstrate that ordinary movement is producing many durable generations. By chain 3 the source A snapshot shown in the graphical HUD reached generation ~78; chain 4 target A reached PREPARED generation 79 and subsequent COMMITTED/ACTIVE generations 80/81. This is not three snapshots per handoff only: movement between handoffs is continuously advancing ACTIVE_OWNER durability generations.

A second accumulation effect exists in the current snapshot format: `gameplay_replay_state` exports the service operation ledger. SM0 manual movement uses `MOVEMENT_DELTA`, which is treated as durable replay input by `NetworkedGameplayService`, so movement operations accumulate in the replay ledger. Each later recovery snapshot therefore serializes/validates an increasingly large replay state. In addition, authority restart enumerates and sorts all historical `recovery-*.json` files before restoring the newest valid snapshot.

This explains both symptoms:

- several-second boundary crossing in P2 is primarily intentional H4.3/P2 crash visualization;
- progressively slower/jerkier movement after repeated chains is a real performance limitation of the conservative per-MOVE write-before-ACK snapshot implementation plus accumulating recovery/replay history.

The existing H2.4 design explicitly classifies the implementation as intentionally conservative and leaves WAL/group-commit throughput optimization for later. ACK durability semantics must remain unchanged by any repair.

### Presentation defect

The outage HUD currently shows `Outage: 0/3` while inside `Stop-P2AuthorityPair`, because that helper writes the outage status with literal outage index 0. This is a presentation bug only; the three actual durable stages and process kills are still being executed correctly.

## Runtime verdict

Functional transfer/recovery observed so far: **PASS as branch-local graphical evidence**.

Smooth-movement/performance verdict: **OPEN FINDING**.

Do not interpret the several-second P2 transfer as normal healthy seamless-handoff latency: P2 intentionally kills both authority processes three times per crossing. Do not interpret the progressive movement stutter as expected production behavior either; it exposes a bounded SM0 persistence-throughput problem that should be optimized without weakening write-before-ACK durability.

## Next repair target

P2.1 should separate correctness evidence from movement throughput and repair the accumulation path in this order:

1. add explicit persistence/restore timing and snapshot-size telemetry so active MOVE cost is measurable;
2. retain write-before-ACK semantics;
3. compact/prune historical recovery snapshot files after a newer generation is safely durable;
4. design bounded movement replay recovery so old MOVEMENT_DELTA operation results do not grow without limit while the exact durable last-input retry remains recoverable;
5. rerun focused H2.4/H2.5/H3/H4 recovery gates before judging graphical smoothness.

P2 graphical runtime evidence should be finalized only after the graphical session exits cleanly and the performance finding is either explicitly scoped or repaired.