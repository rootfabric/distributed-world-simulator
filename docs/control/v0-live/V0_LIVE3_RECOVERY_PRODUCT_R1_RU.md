# V0-LIVE.3 R1 — Recovery as Product Behavior

**Status:** IMPLEMENTATION CANDIDATE  
**Base main:** `894f7033b16cefcf78e40d660bdbaf0c9b061afe`  
**Branch:** `feature/v0-live3-recovery-product-r1`

## Goal

LIVE.3 converts already accepted recovery foundations into the normal `--network-mvp`
product lifecycle.

The user-visible contract is:

```text
server + client A + client B
        ↓
canonical gameplay mutations
        ↓
close A
        ↓
launch fresh A with same logical identity
        ↓
current canonical state restored
        ↓
planned/quiescent server shutdown
        ↓
A/B remain alive and enter reconnect
        ↓
fresh server process on the same persistence slot
        ↓
same world state / same player identities
        ↓
gameplay continues
```

R1 does **not** claim arbitrary power-loss recovery during an in-flight write.

## Existing owners reused

LIVE.3 creates no new canonical store.

```text
player / movement / Item Graph / equipment / resource state
    → existing M6 authoritative recovery repository

Construction
    → existing V0-P4 canonical Item Graph bridge
    → existing M0 Construction transaction repository

client reconnect
    → existing M3 graphical client reconnect state machine
```

The product persistence root is one lifecycle namespace. Construction derives:

```text
<persistence-root>/v0-p4-construction-m0
```

No second Item Graph, resource store or Construction owner is introduced.

## Product launch contract

A normal dedicated server launched with `--network-mvp` now resolves a stable recovery
root.

Priority:

1. explicit `--persistence-root=<path>`;
2. legacy `--m6-persistence-root=<path>` for compatibility;
3. stable default under `user://v0-live/recovery/<world>/<instance-slot>`.

Clients never own a persistence root. An explicit `--persistence-root` on a
`game-client` launch is rejected.

The historical `_m6_mode` remains a test/acceptance selector. LIVE.3 persistence is
orthogonal to it; normal `--network-mvp` continues to select the accepted M3 product
runtime.

## Planned shutdown semantics

The existing dedicated runtime `stop()` already performs a final durable checkpoint
before transport/service shutdown and fails closed if that checkpoint cannot be
committed.

LIVE.3 R1 relies on that existing behavior. It does not add a second shutdown path.

## Product recovery evidence surface

The existing opt-in loopback automation state gains read-only fingerprints of client
replicas:

- logical/player identity and ownership epoch;
- local authoritative player record;
- gameplay revision/checksum;
- Item Graph revision/checksum;
- ResourceMining generation/checksum;
- Construction generation/bundle checksum;
- stable per-construct checksums.

These are test/diagnostic projections only. They do not own or mutate canonical state.

## Exact process acceptance

`tools/live3/run_live3_product_recovery.ps1` uses real product processes:

1. cold-imports the Godot project unless told to reuse an already imported checkout;
2. starts dedicated server #1 with an isolated explicit persistence root;
3. starts GUI A and B;
4. waits for both to become `CONNECTED`;
5. mutates canonical Item Graph through hotbar selection;
6. walks A to the real Earth resource node, equips the mining tool and mines through
   normal `player.interact`;
7. consumes the mined ore through normal `construction.build.next`;
8. proves both clients converge;
9. closes A and launches a fresh A with the same logical identity;
10. proves B remained connected and A recovered the same canonical fingerprints;
11. waits for server #1 to perform its own planned shutdown;
12. proves both clients observe the outage without being killed;
13. starts server #2 with the same world identity and persistence root;
14. proves Item Graph, resource state, construct state, player entity IDs and player
    positions recover;
15. moves A again and proves B receives fresh canonical remote samples.

The runner fails on foreign Godot processes, script/parse/compile errors, state
divergence, missing recovery evidence, leaked identity, or failure to continue gameplay.

## Acceptance gates

R1 requires:

- exact launch-option contract;
- cold import;
- existing M6 recovery regressions;
- existing ResourceMining recovery regression;
- existing Construction restart/quiescent recovery regressions;
- real Windows product process recovery runner;
- LIVE.2 focused regression compatibility;
- tracked-clean final source;
- Fresh Review;
- Fresh Independent Verifier;
- human merge gate.

## Non-goals

- crash/power-loss exactly between filesystem writes;
- distributed multi-authority restart;
- service discovery / public Internet reconnect;
- account authentication;
- new persistence database;
- UX0 host/join menu.

Those remain later work.
