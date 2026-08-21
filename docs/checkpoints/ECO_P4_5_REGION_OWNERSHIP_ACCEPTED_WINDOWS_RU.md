# ECO P4.5 — Region Ownership / Server Handoff — ACCEPTED WINDOWS FULL CHAIN

Статус: `ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN`.

Parent P4.4: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2` — ACCEPTED.

## Canonical identities

```text
aggregate_hash=c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419
source_ownership_hash=f89f476285a40fdf0fe0f79557001f536fff4df2c8da9085cd5ecffce314d1de
handoff_hash=3d9e94ffddc7f9cf3f6e765c08b620a2bf3436b751fbadcedb694fe5c9e2624c
target_ownership_hash=b7d0edb5c943dbe0f1ba62066dd94c5a5d84eff82177897174ba37f984b734c4
parent_p4_4=4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2
```

## Evidence

Exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

Committed Windows runner: `RUN_ECO_P4_5_TESTS.ps1`.

- direct committed P4.4 parent regression: PASS, 52 assertions;
- P4.5 A: PASS, 60 assertions;
- P4.5 fresh process B: PASS, 60 assertions;
- A/B semantic output byte-identical;
- all frozen ownership/handoff identities exact.

## Accepted contract

P4.5 owns deterministic ecology-region authority identity only. `ownership_epoch` is the fencing token; accepted handoff increments it exactly once. Snapshot mutation requires the exact current owner/epoch/ownership hash/snapshot hash. Prepared handoffs are bound to the exact source ownership state, so replay and stale packages fail closed.

P4.5 does not authorize distributed consensus, lease timeout policy, network transport, client mutation authority or P4.7 scheduler policy.

P4.6 canonical full-chain gate is now open.
