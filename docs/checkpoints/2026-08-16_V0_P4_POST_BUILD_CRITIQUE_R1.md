# V0-P4 post-build critique

Subject: `feature/v0-p4-construction-real-resources`

Closure integration head at critique preparation: `b21f6658fb57e30b9a47e1275038f224fc89de4f`

Status: **READY FOR FRESH INDEPENDENT REVIEW / NOT SELF-ACCEPTED**

## What P4 achieved

P4 closes the first real V0 economy loop without introducing a second resource ledger or a second Item Graph. Ore produced by the live P3 mining authority is placed in the same canonical M4 Item Graph used by multiplayer gameplay. A server-authoritative Construction request deterministically selects the requesting player's eligible ore, binds the allocation to the frozen M4 snapshot, atomically consumes/deletes the ore with Construction progression, publishes canonical Item Graph + Construction changes, and reconstructs the same state for a reconnecting client.

The final demonstrated loop is:

`real ENet join -> mine canonical ore -> build foundation -> mine -> build shell -> mine -> build roof -> OPERATIONAL -> canonical LEAVE -> reconnect -> exact ResourceMining / Item Graph / Construction convergence`.

The Earth outpost bounded recipe consumes the whole canonical node: `2 + 4 + 2 = 8 ore`.

## Decisions that were correct

1. **Reuse the existing transaction machinery.** `ConstructionBuildProcess`, `ConstructionStageTransactionPlanner`, `AuthoritativeConstructionItemGraphAdapter` and M0 were reused rather than creating a second transaction owner.
2. **Keep M4 canonical.** P4 holds the same live M4 object identity; ore is not copied into Construction state.
3. **Deterministic allocation.** Material allocation is derived from canonical inventory in `(slot_index, item_id)` order and excludes foreign-player/hotbar-only stacks.
4. **Fail before mutation on ambiguity.** Snapshot/TOCTOU mismatch, insufficient resource, operation-id conflict and unsupported unsafe fault modes reject before canonical mutation.
5. **Do not convert post-commit publication failure into gameplay rejection.** Once commit succeeds, publication derivation failure falls back to authoritative Item Graph and/or Construction snapshots.
6. **Prove behavior over real ENet.** Two concurrent clients and a leave/reconnect cycle were validated as OS processes, not only in-memory mocks.
7. **Keep prior test debt separate.** The world/core baseline repair was isolated in PR #122, independently reviewed, then merged into P4 closure.

## Defects found during implementation

### P4.1 exact exhaustion

The existing BuildPlan rejected consuming exactly the source stack quantity, and the stage planner could not represent exact exhaustion. The repair changed exact exhaustion into `DELETE + CONSUME_MATERIAL` while preserving over-consume rejection.

### P4.3 initial authoritative mismatch

The first generic transaction-port candidate passed its in-memory seam but failed against the real `AuthoritativeConstructionItemGraphAdapter` with `INVALID_ITEM_SPATIAL_REF`. This exposed that the bridge-local Construction root projection needed the existing canonical world spatial relation. The initial candidate was explicitly superseded rather than silently rewritten.

### P4.5 publication gap

The live Construction path originally published a Construction event but no canonical Item Graph delta after ore consumption. A remote client could therefore observe the new structure while temporarily retaining stale ore. P4.5 unified post-commit publication and snapshot fallback.

### Regression-control debt

The historical world runner curated 202 tests while 34 later standalone tests were absent. Several static tests also assumed leaf-script implementation despite the project's layered inheritance architecture. A separate repair made coverage fail-closed and restored the full baseline to 236/236 + main-scene PASS.

## Residual architectural limitations

These are not P4 blockers, but they should constrain future work.

1. **P4 is a bounded single-resource MVP.** It proves canonical ore consumption, not a general recipe/crafting economy.
2. **The cross-owner atomic boundary is deliberately narrow.** P4 safely supports the validated M4 + Construction/M0 sequence and rejects unsafe post-M0 fault modes. It is not a general distributed transaction framework.
3. **Publication fallback can be heavier.** Full snapshots are correct but more expensive than deltas; later scaling work may need better recovery bandwidth accounting.
4. **Construction reconnect is convergence-oriented.** P4 proves final canonical reconstruction; it does not introduce an independent client-side speculative Construction authority.
5. **Network authority remains SERVER_PREDICTED.** P4 intentionally does not change NX transport, prediction or reconciliation foundations.
6. **The accepted product base is still the P3.1 line.** PR #117 remains excluded from P4 ancestry.
7. **The full suite is now dynamically complete, but runtime cost is substantial.** Future CI design may shard the 236-test world/core gate while preserving the same fail-closed discovery rule.

## Governance critique

The generation-80 dispatch model prevented a second autonomous runtime worker and forced the prior regression debt into a separate repair lane. This separation was useful. However, several older static acceptance tests had drifted away from inheritance-based production composition. Future control work should prefer semantic script ancestry/component contracts over brittle source-text matching.

The implementation history also demonstrates why exact-head testing matters: generic P4.3 tests were insufficient until the real authoritative adapter was exercised, and local Godot runs caught strict GDScript typing and process-fixture errors before publication.

## Evidence quality

Strengths:

- exact runtime SHAs are retained for P4.1-P4.6;
- real project Godot 4.7.1 double was used locally;
- exact committed blobs were matched to locally executed bytes for the P4 runtime slices;
- Project Control is GREEN on each important runtime/evidence boundary;
- P4.6 uses real ENet clients and reconnect;
- full world/core regression is 236/236 plus main-scene PASS;
- the independently reviewed repair candidate and its merge commit have identical trees (`files=[]`).

Remaining evidence dependency:

- final P4 Reviewer and Verifier must independently inspect the exact closure HEAD and may not rely only on this implementer-authored critique/map.

## Recommended next action

Do not add more P4 runtime features unless a reviewer finds a concrete blocker. The implementation is at the closure boundary. Record the closure predicates, obtain a fresh independent P4 Reviewer PASS, then a fresh independent Verifier PASS on the exact final head. Only after those gates and fresh PC0/overlap/human-attention checks should Director propose the V0-P4 checkpoint.

P5 must not start before P4 is formally accepted.
