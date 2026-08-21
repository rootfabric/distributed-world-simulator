# SM0 H3.4 — dual-authority outage after durable target commit decision

Date: 2026-08-15

Track: experimental SM0 two-authority seamless handoff lab

Classification: BRANCH-LOCAL HARDENING DESIGN. Not global/project acceptance. `SERVER_HANDOFF` remains outside the V0-S1 accepted boundary.

## Goal

Prove the next transaction failure boundary after H3.3:

- source A has already durably retired transfer `T`;
- target B has accepted COMMIT and durably persisted `TARGET_COMMITTED(T)`;
- source A has not yet observed a successful `PLAYER_HANDOFF_COMMITTED` response;
- client has not yet completed the crossing;
- both authority processes are then lost before either one is restarted;
- the same client process remains alive;
- after restart, B restores the already-decided target commit, A restores the retired source viewpoint and retries the exact COMMIT, and the same transaction converges without re-import, second writer, identity change or second commit decision.

## Exact failure boundary

Before forced outage the same transfer `T` must satisfy all of the following:

A durable viewpoint:

- recovery phase `SOURCE_RETIRED`;
- source metadata stage `COMMIT_SENT`;
- durable directory points to B;
- source canonical player is retired/non-writer;
- `target_committed == false` because the successful COMMITTED acknowledgement has not been observed;
- client redirect is intentionally withheld so crossing cannot complete before the outage.

B durable viewpoint:

- recovery phase `TARGET_COMMITTED`;
- durable directory points to B;
- committed transfer map contains exact `T`;
- target is the unique canonical writer;
- successful `PLAYER_HANDOFF_COMMITTED` acknowledgement is intentionally withheld after persistence.

Client viewpoint:

- zero `SM0_CROSSING_COMPLETED` events before outage;
- same client process remains alive through the zero-authority interval.

## Fault profile

`h3-commit-decision-dual-outage-v1`

Test-only behavior:

- on A, allow PREPARE and COMMIT normally but suppress `HANDOFF_REDIRECT` until the forced outage;
- on B, process COMMIT normally, persist `TARGET_COMMITTED(T)` through the established recovery path, then suppress the successful `PLAYER_HANDOFF_COMMITTED` response;
- emit an explicit crash-boundary event only after target commit persistence is proven;
- no production/non-fault behavior changes.

## Recovery expectation

Restart order is target first, then source.

B must:

1. restore exact `TARGET_COMMITTED(T)` generation;
2. restore committed transfer metadata and canonical target-owned directory;
3. remain the only target writer;
4. accept A's replayed exact COMMIT as an idempotent committed-transfer replay;
5. return successful COMMITTED without creating another target import/commit decision.

A must:

1. restore exact `SOURCE_RETIRED(T)` generation as non-writer;
2. immediately resume the exact COMMIT and client redirect;
3. accept B's successful committed replay;
4. complete source tracking only after target commit and client redirect acknowledgement are both observed.

Client must:

1. keep the same process identity through outage;
2. activate B for the same `player/a` and transfer `T`;
3. complete crossing #1 only after recovery;
4. continue subsequent A <-> B handoffs;
5. finish with identity changes `0` and monotonic directory epoch.

## Fail-closed assertions

H3.4 must fail if any of the following occurs:

- crossing completes before the forced outage;
- B lacks a durable `TARGET_COMMITTED(T)` snapshot at the boundary;
- A lacks the corresponding `SOURCE_RETIRED(T)` snapshot;
- source has already observed target commit before outage;
- old A or B process remains alive when restart begins;
- client exits during the zero-authority interval;
- restored A becomes writer;
- restored B loses the committed transfer;
- replayed COMMIT causes a second `SM0_TARGET_AUTHORITY_COMMITTED` event after restart;
- target recovery regresses to `TARGET_PREPARED`;
- any `SM0_INVARIANT_VIOLATION` occurs;
- player identity changes;
- final handoff count or final directory epoch is wrong.

## Non-goals

H3.4 does not prove:

- quorum/consensus or network-partition safety;
- conflicting independent writes on multiple hosts;
- durable media correctness under disk corruption/power loss;
- arbitrary multiple concurrent transfers;
- global V0 acceptance.

No new recovery phase is expected for H3.4. The test exists to prove composition of already established `SOURCE_RETIRED` and `TARGET_COMMITTED` durability across a total outage in the commit-decision observation window.
