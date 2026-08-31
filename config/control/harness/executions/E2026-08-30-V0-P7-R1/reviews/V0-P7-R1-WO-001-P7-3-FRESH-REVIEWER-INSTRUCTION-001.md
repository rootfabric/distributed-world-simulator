# V0 P7.3 — Fresh Independent Reviewer R1

Role: **fresh independent READ-ONLY Reviewer** for CRITICAL P7.3.

Do not modify runtime code, do not repair findings, do not run as Verifier, and do not merge any PR.

## Exact subject

```text
repo:
/home/yurig/distributed-world-simulator

runtime PR:
#373

runtime branch:
feature/v0-p7-bounded-terrain-mutation

canonical main before P7.3:
8ae419bb4c726a3c616e84dd11047d9b91a8cb7d

HEAD:
b4b11a69ef921c59b28208685cf26509c3b81907

TREE:
99dea175fda7bacce936b15d30d9e25fa9e4af00

runtime Project Control:
33360078991 = SUCCESS
```

Allowed verdicts only:

```text
PASS
FAIL
INSUFFICIENT_EVIDENCE
```

A PASS opens only fresh independent Verifier. It does not authorize runtime merge.

## Exact six-file delta

Independently prove `8ae419bb4c726a3c616e84dd11047d9b91a8cb7d..b4b11a69ef921c59b28208685cf26509c3b81907` changes exactly:

```text
RUN_V0_P7_3_MATERIAL_BATCH_ITEM_GRAPH_GATE.ps1
RUN_V0_P7_3_MATERIAL_BATCH_ITEM_GRAPH_GATE.sh
scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd
scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_policy.gd
scripts/runtime/networked_gameplay/p7/p7_matter_material_item_graph_adapter.gd
tests/runtime/test_v0_p7_3_material_batch_to_item_graph.gd
```

There must be no changes to:
- Matter contracts/foundation;
- MW4-MW10 foundation code;
- canonical Item Graph implementation;
- persistence/network/authority foundations;
- architecture ownership.

## Immutable exact review source

```text
validation PR:
#375

validation branch:
validation/v0-p7-3-review-source-r1

carrier HEAD:
5bfb31c5c4940a365385717d756ed15a62737bd0

source export run:
33363652803 = SUCCESS

carrier Project Control:
33363652835 = SUCCESS

artifact:
9747515061

artifact name:
p7-3-review-source-b4b11a69ef92

artifact ZIP SHA-256:
b6f2be94c8dbe371468ccfbee0064dcf354007b8ae0b4db6ac1176b37e008853

source tar SHA-256:
f5cb57e6d953b6f9dcf3d4cc0014e2c3759e9b461d5bcf638a2dcc0681ed1f98

independently reconstructed TREE:
99dea175fda7bacce936b15d30d9e25fa9e4af00
```

## Read first

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-3-EVIDENCE-MAP-001.v1.json

config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-3-POST-BUILD-CRITIQUE-001.v1.json

config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-3-REVIEW-SOURCE-001.v1.json

config/control/harness/v0-p7-matter-production-owner-map.v1.json

config/control/harness/v0-p7-matter-production-convergence-plan.v1.json

config/control/harness/executions/E2026-08-30-V0-P7-R1/work-orders/
V0-P7-R1-WO-001.v1.json
```

Treat these as evidence/claims, not as the verdict.

# Required review questions

## 1. Canonical ownership

Verify:
- `MatterMaterialBatch` remains immutable physical extraction provenance;
- canonical spendable inventory remains only the existing Item Graph;
- P7.3 adds no resource inventory, delivery receipt ledger, persistence owner, or replay store;
- the new adapter/coordinator contain no canonical balances.

A new hidden kg balance or receipt truth is blocking.

## 2. Explicit conversion policy

Review:

```text
scripts/runtime/networked_gameplay/p7/
p7_matter_material_delivery_policy.gd
```

The selected R1 product policy is intentionally explicit:

```text
supported lunar geological Matter
        ↓
generic existing item/ore

1.0 kg represented mass
        =
1 canonical item/ore quantity unit
```

Supported material IDs are bounded to:

```text
matter/regolith-loose
matter/regolith-compacted
matter/fractured-basalt
matter/basalt
```

Undeclared materials must fail closed.

Judge whether mapping supported lunar geological composition to the existing generic V0 `item/ore` definition is acceptable for current V0 semantics.

Do not assume Item Graph itself stores kilograms: this is an explicit P7 product conversion policy.

If this mapping is semantically unacceptable, return FAIL with the required explicit alternative; do not silently invent another mapping.

## 3. Mass conservation

For every accepted batch verify:

```text
represented_mass_kg =
    output_quantity * 1 kg

0 <= residual_mass_kg < 1 kg

total_mass_kg =
    represented_mass_kg
  + residual_mass_kg
```

within the declared numerical tolerance.

Check specifically:
- no round-up;
- no silent fractional mass deletion;
- no negative residual;
- sub-1kg batch becomes `RESIDUAL_ONLY`, not one free item;
- residual remains immutable Matter batch provenance and is not a second spendable inventory.

## 4. Exactly-once ownership

Review:

```text
p7_matter_material_item_graph_adapter.gd
```

The adapter must use only existing:

```text
preflight_server_output(...)
apply_server_output(...)
```

The canonical Item Graph replay ledger must remain the only exactly-once owner.

Verify deterministic identity:
- output operation ID derives from immutable batch identity;
- server-output source fingerprint includes **the full MatterMaterialBatch checksum**, not a prefix.

Verify:
- same exact batch replay does not create a second item;
- same batch ID with changed physical contents fails with Item Graph replay conflict;
- same batch redirected to another player fails with replay conflict;
- no P7 replay Dictionary/store is introduced.

## 5. Provenance and committed-Matter boundary

Review:

```text
p7_matter_material_delivery_coordinator.gd
```

It must accept only:
- valid canonical MatterMutationRequest;
- valid canonical MatterMutationResult;
- exact same operation ID;
- `status == COMMITTED`;
- exactly one created aggregate/batch;
- batch retrieved from existing MW4 material receiver;
- batch source operation matching the request;
- batch mass matching result removed mass;
- actor identity resolving through existing `player/<logical_player_id>` convention.

No fabricated batch supplied directly by client/product code may bypass the MW4 receiver boundary.

## 6. Failure and retry

Check behavioral tests for the actual cross-domain failure:

```text
Matter already COMMITTED
        ↓
Item Graph inventory full
        ↓
CONTAINER_FULL
```

Required invariants:
- Item Graph unchanged;
- existing MW4 receiver batch unchanged;
- no rollback of committed Matter by P7.3;
- same immutable batch remains available for later retry;
- later successful delivery changes Item Graph once;
- subsequent retry is exact replay.

Judge whether this is sufficient for P7.3. P7.4 separately owns restart/recovery persistence proof.

## 7. Stage boundary / production caller

Current P7.3 does **not** wire the coordinator into the final graphical/two-client app path.

This is explicit, not hidden.

Roadmap assigns:
- P7.3 = conversion boundary + conservation/exactly-once;
- P7.4 = persistence/restart;
- P7.5 = two-client convergence;
- P7.7 = graphical digging/material/inventory slice.

Review whether the real MW4-batch → canonical Item Graph focused composition is sufficient to close P7.3 as a staged boundary.

If you conclude a live production caller is mandatory for P7.3 itself, this is a blocking finding. State exactly where the caller must live without modifying Matter/M4 foundation ownership.

## 8. Tests must be behavioral

Inspect:

```text
tests/runtime/test_v0_p7_3_material_batch_to_item_graph.gd
```

Required coverage includes:
- 12.75 kg → 12 item units + 0.75 kg residual;
- sub-unit residual-only behavior;
- unsupported material rejection;
- canonical Item Graph first delivery/replay;
- full batch-checksum conflict;
- cross-player conflict;
- full inventory failure;
- real LunarMatterBubble/MW4 committed batch;
- receiver persistence state unchanged by failed/successful/replayed Item Graph delivery.

Reject source-text/contains-style tautological tests if present.

## 9. Implementer execution evidence

Reported exact-double Implementer results:

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

P7.3 focused          PASS 116/116
P7.2 seam             PASS 50/50
P7.1 authority        PASS 83/83
P7.1 Tool→MW4         PASS 30/30
P5 mining             PASS 36/36
P3 resource domain    PASS 79/79
MW4                   PASS 187
MW5                   PASS 142
MW6                   PASS 130

Project Control:
33360078991 = SUCCESS
```

Important limitation:

```text
A fresh standalone P7.2 bubble run was NOT claimed by the Implementer
because that process hung during shutdown in the Implementer container.
```

P7.2 production files are unchanged in the six-file P7.3 delta. The fresh independent Verifier must nevertheless execute the entire canonical P7.3 gate, including P7.2 bubble, before merge.

Reviewer does not need to substitute for Verifier execution.

# Verdict criteria

## PASS

Only if all are true:
- exact HEAD/TREE verified;
- six-file scope exact;
- no owner/foundation expansion;
- conversion policy is explicit and acceptable for current V0 generic ore;
- mass conservation/residual accounting is sound;
- exactly-once remains exclusively canonical Item Graph-owned;
- full immutable batch checksum participates in replay fingerprint;
- failure/retry boundary preserves both canonical owners;
- no hidden P7 state;
- tests are behavioral;
- stage-boundary deferral to P7.4/P7.5/P7.7 is acceptable;
- no blocking finding remains.

## FAIL

Use for a concrete correctness/architecture defect. Include:
- file/function;
- violated invariant;
- why blocking;
- minimal required fix.

## INSUFFICIENT_EVIDENCE

Use when an important claim cannot be established from exact source/evidence without guessing.

# Durable result

Create exactly:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/reviews/
V0-P7-R1-WO-001-P7-3-FINAL-REVIEW-001.v1.json
```

Required identity:

```text
schema:
distributed_world_simulator.harness_review_result.v1

review_id:
V0-P7-R1-WO-001-P7-3-FINAL-REVIEW-001

review_type:
POST_BUILD_EXACT_HEAD_SUBSTEP_REVIEW

work_order_id:
V0-P7-R1-WO-001

risk_class:
CRITICAL

reviewed_head_sha:
b4b11a69ef921c59b28208685cf26509c3b81907

reviewed_tree_sha:
99dea175fda7bacce936b15d30d9e25fa9e4af00

reviewer:
INDEPENDENT_REVIEWER_P7_3_FRESH_EXACT_SOURCE_R1
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
control/v0-p7-3-fresh-reviewer-result-r1
```

Base it on the exact current head of:

```text
control/v0-p7-3-fresh-reviewer-dispatch-r1
```

Only the FINAL-REVIEW-001 JSON may be added.

Push the branch. If `gh` is unavailable, pushed branch + commit SHA are sufficient durable evidence.

At PASS, finish:

```text
P7.3 Reviewer R1 PASS opens fresh independent Verifier only.
No merge authorization.
```
