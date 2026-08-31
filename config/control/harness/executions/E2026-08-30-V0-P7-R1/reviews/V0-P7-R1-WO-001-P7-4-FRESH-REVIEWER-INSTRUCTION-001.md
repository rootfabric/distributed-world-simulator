# V0 P7.4 — Fresh Independent Reviewer R1

Role: **fresh independent READ-ONLY Reviewer** for CRITICAL P7.4.

Do not modify runtime code, do not repair findings, do not act as Verifier, and do not merge any PR.

## Exact subject

```text
repository:
rootfabric/distributed-world-simulator

runtime PR:
#396

runtime branch:
feature/v0-p7-bounded-terrain-mutation

canonical main / P7.4 base:
0ad8c41f04b1d115da7de4a24a1c0390761c3ae1

HEAD:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef

runtime Project Control:
33374295322 = SUCCESS
```

Allowed verdicts only:

```text
PASS
FAIL
INSUFFICIENT_EVIDENCE
```

A PASS opens only the fresh independent Ubuntu Verifier. It does not authorize runtime merge.

## Exact six-file delta

Independently prove that
`0ad8c41f04b1d115da7de4a24a1c0390761c3ae1..9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292`
changes exactly:

```text
RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.ps1
RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.sh
scripts/runtime/networked_gameplay/networked_gameplay_service.gd
scripts/runtime/networked_gameplay/p7/p7_authoritative_item_graph_output_port.gd
scripts/runtime/networked_gameplay/p7/p7_persistence_restart_composition.gd
tests/runtime/test_v0_p7_4_persistence_restart_composition.gd
```

Expected Git stats:

```text
7 commits ahead
6 changed files
1030 additions
0 deletions
```

There must be no changes to:
- Matter contracts/foundation;
- MW4-MW10 foundation code;
- canonical Item Graph implementation;
- persistence repositories/schemas;
- network gateway/transports;
- authority foundation;
- architecture ownership.

The one canonical non-P7 runtime file change is explicitly authorized by:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-4-WORK-ORDER-AMENDMENT-001.v1.json
```

## Immutable exact review source

```text
validation PR:
#397

validation branch:
validation/v0-p7-4-exact-source-r1

carrier HEAD:
8e5520db6cae05a816740b00b387f273e757096b

source export run:
33374385318 = SUCCESS

carrier Project Control:
33374385340 = SUCCESS

artifact:
9751287742

artifact ZIP SHA-256:
71a833cb3b7f99133d81e309d2e22b329704fd4e5d3dbb2ee409b1ab94a99e9a

source tar SHA-256:
b422f8ba9dec229d53ea3e63325355d286bf96bb248376703047492cffbc147e

independently reconstructed TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef
```

## Read first

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-4-EVIDENCE-MAP-001.v1.json

config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-4-POST-BUILD-CRITIQUE-001.v1.json

config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-4-REVIEW-SOURCE-001.v1.json

config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-4-WORK-ORDER-AMENDMENT-001.v1.json

config/control/harness/v0-p7-matter-production-owner-map.v1.json

config/control/harness/v0-p7-matter-production-convergence-plan.v1.json

config/control/harness/executions/E2026-08-30-V0-P7-R1/work-orders/
V0-P7-R1-WO-001.v1.json
```

Treat all of them as evidence/claims, not as the verdict.

# Required review questions

## 1. Ownership and persistence boundaries

Verify that P7.4 introduces no new durable owner.

Required canonical owners must remain:

```text
Matter durability:
MW5_MATTER_STATE_COORDINATOR

Gameplay durability:
M6_AUTHORITATIVE_RECOVERY_COORDINATOR

Matter replay/provenance:
MW4_MATERIAL_RECEIVER_AND_JOURNAL

Spendable inventory:
CANONICAL_ITEM_GRAPH

Item delivery exactly-once:
CANONICAL_ITEM_GRAPH_REPLAY_LEDGER

Aggregate authoritative revision:
NETWORKED_GAMEPLAY_SERVICE
```

Blocking if you find:
- P7-private filesystem/save format;
- P7-private replay or receipt ledger;
- second Item Graph;
- second Matter truth;
- hidden kg balance;
- new authority/network persistence owner.

## 2. Aggregate revision amendment

Review:

```text
scripts/runtime/networked_gameplay/networked_gameplay_service.gd
```

The final candidate is allowed only to:
- delegate `preflight_canonical_server_output(...)` to the existing canonical Item Graph;
- delegate `apply_canonical_server_output(...)` to the existing canonical Item Graph;
- call existing `_advance()` exactly once only when canonical apply succeeds and is not replay.

Prove:
- failed canonical output does not advance aggregate revision;
- canonical replay does not advance aggregate revision;
- successful fresh canonical output advances aggregate revision exactly once;
- no alternate P7.4 path calls Item Graph output directly and bypasses this wrapper;
- no new aggregate revision owner exists.

Explicitly inspect the original P7.4 defect:

```text
SAME_REVISION_AUTHORITATIVE_MUTATION
```

and confirm the final candidate fixes the root owner boundary rather than masking the assertion.

## 3. Restart composition order

Review:

```text
scripts/runtime/networked_gameplay/p7/p7_persistence_restart_composition.gd
```

Required sequence:

```text
MW5 restore
→ existing gameplay/M6 restore
→ locate persisted COMMITTED MW4 result
→ execute exact same MW4 request as replay
→ prove receiver/journal/batch-count unchanged
→ deliver through accepted P7.3 coordinator
→ prove Matter provenance still unchanged
```

Verify all failures are fail-closed and no partial P7-owned durable state is written.

## 4. Exact Matter replay

For the recovered operation verify:
- request validates with the existing MatterMutationRequest contract;
- journal result validates with the existing MatterMutationResult contract;
- status must be `COMMITTED`;
- `matter_service.execute(request)` must return the exact persisted result;
- receiver `content_hash()`, journal `content_hash()`, and batch count must remain unchanged by replay.

A replay that reconstructs an equivalent-but-different result is not sufficient.

## 5. First restart: fresh delivery

After MW5 + gameplay recovery, verify:
- the recovered committed batch was not previously delivered;
- accepted P7.3 coordinator is reused;
- canonical Item Graph changes once;
- canonical Item Graph replay ledger records the delivery;
- aggregate gameplay revision advances exactly +1;
- Matter receiver/journal remain unchanged;
- mass conservation remains the accepted P7.3 invariant;
- no P7.4 receipt is stored.

## 6. Second restart: replay

Verify persisted gameplay generation 2 restores:
- canonical inventory containing exactly one delivered output;
- canonical Item Graph replay ledger containing the original output operation;
- same delivery returns `replay=true`;
- Item Graph checksum is unchanged;
- aggregate gameplay revision is unchanged;
- Matter batch count stays exactly one.

Any second item, second batch, or +1 aggregate revision on replay is blocking.

## 7. Process restart evidence

Inspect:

```text
tests/runtime/test_v0_p7_4_persistence_restart_composition.gd
RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.sh
RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.ps1
```

The test must use three independent Godot processes:

```text
seed
recover-deliver
recover-replay
```

with the same persistent user-data root but fresh process memory.

Reported exact frozen-source results:

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

seed:
21/21 PASS

recover-deliver:
25/25 PASS

recover-replay:
17/17 PASS
```

Reviewer may inspect/run read-only targeted checks, but does not replace Verifier execution.

## 8. Seed-fixture realism — explicit acceptance question

The P7.4 seed intentionally does **not** re-run full excavation geometry. It builds the smallest valid committed MW5 state through existing public canonical MW4 contracts, receiver and journal.

This is documented in the test itself.

The same canonical P7.4 runner separately includes the real P7.3:
`LunarMatterBubble -> MW4 -> MatterMaterialBatch -> canonical Item Graph`
behavioral regression.

Judge whether this separation is sufficient for the P7.4 persistence/restart stage.

Return FAIL if P7.4 itself must seed through a full real excavation execution. State the minimal required change and why the current contract-built committed state can hide a restart defect.

Do not silently ignore this question.

## 9. Known execution gaps

The Implementer exact-source evidence freshly records:

```text
P7.3                         116/116
P7.2 seam                     50/50
P7.1 authority                83/83
P7.1 Tool→MW4                 30/30
P5                            36/36
P3 resource domain            79/79
P3 aggregate recovery         33/33
M6 recovery contracts        126/126
```

The following are **not** to be inherited as fresh PASS from the Implementer container:

```text
P7.2 bubble
MW4
MW6
M6 recovery processes
```

The M6 recovery-process rerun exceeded the 180-second container execution window. This is not assertion RED, but incomplete execution is not PASS.

Do not convert any of those into PASS.

A Reviewer PASS may still leave them for the fresh Ubuntu Verifier.

## 10. Full Verifier gate requirement

If Reviewer verdict is PASS, the next actor must use a brand-new detached Ubuntu worktree at exact runtime HEAD and exact double Godot, perform fresh import, then run the complete canonical P7.4 gate.

The gate includes:
- all three restart phases;
- P7.3;
- P7.2 bubble + seam;
- P7.1 authority + Tool→MW4;
- P5;
- P3 resource + aggregate recovery;
- M6 recovery contracts + recovery processes;
- MW4;
- MW5;
- MW6;
- fatal-log scan;
- tracked-clean fence;
- exact HEAD/TREE freshness.

Reviewer must not pre-authorize merge.

# Verdict criteria

## PASS

Only if all are true:
- exact HEAD/TREE verified;
- six-file delta exact;
- Work Order amendment compliance exact;
- no owner/foundation expansion;
- restored MW4 replay is exact and mutation-free;
- first restart delivers exactly once;
- aggregate revision advances exactly once on fresh delivery;
- second restart is canonical replay with no revision advance;
- no hidden P7 durability/receipt state exists;
- process restart evidence is structurally valid;
- seed-fixture boundary is explicitly judged acceptable;
- known execution gaps remain delegated to Verifier;
- no blocking finding remains.

## FAIL

Use for a concrete correctness/architecture defect. Include:
- file/function;
- violated invariant;
- why blocking;
- minimal required fix.

Do not repair it.

## INSUFFICIENT_EVIDENCE

Use when a required P7.4 claim cannot be established from exact source/evidence without guessing.

# Durable result

Create exactly:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/reviews/
V0-P7-R1-WO-001-P7-4-FINAL-REVIEW-001.v1.json
```

Required identity:

```text
schema:
distributed_world_simulator.harness_review_result.v1

review_id:
V0-P7-R1-WO-001-P7-4-FINAL-REVIEW-001

review_type:
POST_BUILD_EXACT_HEAD_SUBSTEP_REVIEW

work_order_id:
V0-P7-R1-WO-001

risk_class:
CRITICAL

reviewed_head_sha:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

reviewed_tree_sha:
1efad34a075af63169c48dd5055c2537c8d7e6ef

reviewer:
INDEPENDENT_REVIEWER_P7_4_FRESH_EXACT_SOURCE_R1
```

Include:
- verdict;
- required_fixes;
- rank_up_moves;
- evidence_gaps;
- findings;
- checked_items;
- risk_assessment;
- summary.

Recommended result branch:

```text
control/v0-p7-4-fresh-reviewer-result-r1
```

Base it on the exact current head of:

```text
control/v0-p7-4-fresh-reviewer-dispatch-r1
```

Only the FINAL-REVIEW-001 JSON may be added by the Reviewer result branch.

At PASS, finish exactly:

```text
P7.4 Reviewer R1 PASS opens fresh independent Ubuntu Verifier only.
No merge authorization.
```
