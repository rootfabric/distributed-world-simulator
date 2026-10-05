# V0-LIVE.3 R1 — Recovery as Product Behavior

**Status:** IMPLEMENTATION CANDIDATE — WINDOWS EXACT REPAIR REQUIRED  
**Base main:** `1f8a9debc4f8838569f818faa43bdadc0f23f965`  
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


## Current handoff — 2026-10-05

This section records the exact point where LIVE.3 work stopped and the required closure
sequence.

### Repository / PR state at handoff

```text
PR                         = #735
PR_STATE                   = OPEN / DRAFT / NOT MERGED
BRANCH                     = feature/v0-live3-recovery-product-r1
PRODUCT_CODE_HEAD          = 61c8022ff3497ea62ce51eafe70047287c76d53d
CURRENT_MAIN               = c25a6b26d83b937acd1eb4cd4d92e2b44b40c678
AHEAD_OF_MAIN              = 24 commits
BEHIND_MAIN                = 13 commits
MERGEABLE                  = true
FRESH_REVIEW               = PASS_PENDING_EXACT
```

`PRODUCT_CODE_HEAD` is the exact product candidate exercised by the failing Windows
run below. This handoff documentation commit is not itself a product-behavior change.

### Last exact Windows result

```text
RUN                         = 37214363455
JOB                         = 111471804852
JOB_NAME                    = LIVE3 exact Windows product recovery
RESULT                      = FAILURE
FAILED_STEP                 = Product reconnect and planned restart
```

The following exact-job steps passed on `61c8022...`:

- host and identity preflight;
- cold Godot import;
- LIVE3 launch contract;
- existing recovery regressions;
- LIVE2 compatibility focused regressions;
- final clean source and host;
- evidence upload.

The product runner itself stopped with:

```text
LIVE3_PRODUCT_RECOVERY=FAIL
LIVE3_PRODUCT_RECOVERY_FAILED:
Сбой вызова метода, так как [System.Object[]] не содержит метод "op_Multiply".
```

This supersedes the earlier `player.interact` / wrong-side-of-ore failure as the
current blocker. The current failure is in the PowerShell automation arithmetic added
for the canonical Earth resource target calculation; it does **not** establish a
product persistence/recovery failure. Conversely, LIVE.3 must not be declared PASS
until the repaired runner completes the full product sequence.

### How to finish LIVE.3

Use one bounded repair line; do not create another persistence owner, recovery path or
parallel LIVE.3 branch.

1. **Repair the Earth resource target resolver in the existing runner.**
   - Make every vector component an explicit scalar `[double]` before constructing
     PowerShell arrays.
   - Avoid arithmetic expressions adjacent to PowerShell comma/array construction;
     calculate `anchor_x/y/z`, `target_x/y/z`, `north_x/y/z` as scalar locals,
     then build the arrays.
   - Keep the signs/axes identical to `EarthResourceSpatialResolver`.
   - Add a deterministic resolver preflight proving finite scalar values and the
     canonical ore target on the expected negative-X side (approximately `x=-7.863 m`
     from the spawn tangent origin).
   - Re-run the PowerShell parser check before any product processes are launched.

2. **Run a narrow diagnostic smoke for the repaired runner.**
   - Prove the resolver returns scalar values (not `System.Object[]`).
   - Prove A approaches the canonical ore target, camera yaw/pitch are finite and
     `player.interact` advances ResourceMining generation.
   - Do not treat this smoke as the acceptance gate.

3. **Catch the LIVE.3 branch up to current `main`.**
   - The branch is currently 13 commits behind.
   - Integrate canonical `main` without folding unrelated ECO/FABRIC feature work
     beyond what is already merged to `main`.
   - Re-check bounded diff, canonical-owner rejection and mergeability.
   - If `main` moves again before freeze, repeat the drift check and use the final
     caught-up commit as the acceptance subject.

4. **Run the full Windows exact gate on the final caught-up candidate.**
   Required result for the *same commit/tree*:
   - LIVE3 source contract = SUCCESS;
   - host/identity preflight = SUCCESS;
   - cold import = SUCCESS;
   - launch contract = SUCCESS;
   - existing recovery regressions = SUCCESS;
   - LIVE2 compatibility = SUCCESS;
   - product reconnect + planned restart = SUCCESS;
   - final clean source/host = SUCCESS;
   - uploaded report has `outcome=PASS`.

   The product runner must prove the full contract, not merely mining:
   Item Graph mutation → mining → Construction → client-A restart → planned server
   restart → A/B reconnect → exact state recovery → post-restart gameplay continues.

5. **Fresh Review the final integrated diff.**
   The previous review is `PASS_PENDING_EXACT` against the old base and is not the
   final merge approval after `main` catch-up. Re-review ownership, recovery ordering,
   persistence-root semantics, Construction composition and automation-only evidence
   surfaces on the final candidate.

6. **Fresh Independent Verification on the exact final subject.**
   The verifier must independently reproduce the required gates and record:
   `PRODUCT_HEAD`, `PRODUCT_TREE`, Windows run/job IDs and `VERDICT=VERIFIED`.
   A verifier result for an earlier commit is not transferable.

7. **Human merge gate and closure.**
   - Convert PR #735 from draft only after exact Windows SUCCESS and independent
     verification.
   - Merge only if the PR is still mergeable and no new main drift invalidates the
     frozen subject.
   - Record the merge commit and resulting `main` HEAD.
   - Run the normal post-merge project-control/cleanliness check and mark LIVE.3
     complete.

### Final definition of done

LIVE.3 is complete only when all of the following describe the same final candidate:

```text
WINDOWS_EXACT               = SUCCESS
PRODUCT_RECOVERY_REPORT     = PASS
FRESH_REVIEW                = PASS
FRESH_INDEPENDENT_VERIFIER  = VERIFIED
PR_735                      = MERGED
MAIN                        = <merge result containing the verified tree>
```

Until then the correct state is **IMPLEMENTATION CANDIDATE / EXACT REPAIR REQUIRED**.
