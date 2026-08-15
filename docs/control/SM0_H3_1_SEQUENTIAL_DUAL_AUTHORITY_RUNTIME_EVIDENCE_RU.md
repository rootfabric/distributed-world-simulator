# SM0-H3.1 — последовательные crash обеих authority в одной клиентской сессии

Дата: 2026-08-15

Статус: **BRANCH-LOCAL RUNTIME-TESTED PASS**

Это не global acceptance seamless server handoff и не разрешение на перенос SERVER_HANDOFF в V0-S1.

## Exact tested implementation HEAD

`59a035364be3a23289d2b85fbcafa3c4804cfaa7`

Branch:

`feature/sm0-two-authority-seamless-handoff-lab`

Godot:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Windows worktree:

`C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab`

Runner:

`RUN_V0_SM0_SEQUENTIAL_DUAL_OWNER_CRASH_ACCEPTANCE.ps1`

## Default runtime evidence

Command:

```powershell
.\RUN_V0_SM0_SEQUENTIAL_DUAL_OWNER_CRASH_ACCEPTANCE.ps1 -Restart
```

Observed result:

- same client PID: `24480`;
- first active owner crash: A `23952 -> 13956`;
- A durable boundary: generation `2`, input sequence `1`, x `-4.5`;
- A ownership rebound: `1 -> 2`;
- crossing #1: `A -> B`;
- second active owner crash: B `10700 -> 14028`;
- B durable boundary: generation `3`, input sequence `12`, x `0.5`;
- B ownership rebound: `1 -> 2`;
- handoffs: `2 / 2`;
- final directory epoch: `3`;
- identity changes: `0`;
- structured log analysis: PASS;
- event count: `98`.

## Final runtime evidence

Command:

```powershell
.\RUN_V0_SM0_SEQUENTIAL_DUAL_OWNER_CRASH_ACCEPTANCE.ps1 -Final -Restart
```

Observed result:

- same client PID: `1924` for the entire crash chain;
- first crash: A `3416 -> 24964`;
- A durable boundary: generation `2`, input sequence `1`, x `-4.5`;
- A ownership rebound: `1 -> 2`;
- crossing #1: `A -> B`;
- second crash: B `21104 -> 7884`;
- B durable boundary: generation `3`, input sequence `12`, x `0.5`;
- B ownership rebound: `1 -> 2`;
- handoffs: `6 / 6`;
- final directory epoch: `7`;
- identity changes: `0`;
- structured log analysis: PASS;
- event count: `190`.

Final log root reported by the runner:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH31\logs\20260815-202046`

Final summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH31\logs\20260815-202046\h31-summary.json`

## What H3.1 proves

Within this experimental two-authority localhost lab, one continuous client process can survive:

1. an active-owner crash on A after canonical movement was durably persisted and before MOVE_ACK;
2. exact durable replay/rebind on restarted A without applying movement twice;
3. a real A -> B handoff;
4. a second active-owner crash on B while B is the current owner inside EAST;
5. exact durable replay/rebind on restarted B without applying movement twice;
6. continued handoff operation after both recoveries.

The exact logical player identity remains `player/a`; no identity change was observed.

## Scope limits

H3.1 does **not** prove:

- simultaneous loss of both authority processes;
- crash of both authorities during the same handoff transaction;
- recovery from host/power loss or storage loss;
- fsync/power-failure durability guarantees beyond the current snapshot implementation;
- physical two-host/network-partition behavior;
- production-ready HA or consensus;
- performance suitability of per-ACK snapshot persistence;
- global V0 acceptance.

These remain later hardening frontiers.
