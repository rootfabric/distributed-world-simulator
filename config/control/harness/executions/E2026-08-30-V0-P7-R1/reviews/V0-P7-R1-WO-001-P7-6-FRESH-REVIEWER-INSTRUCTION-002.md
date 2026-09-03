# V0 P7.6 — Fresh Independent Reviewer R2

Role: FRESH_INDEPENDENT_REVIEWER. Read-only post-build review. Do not act as Implementer, Verifier, Director, or Human merge approver.

## Why R2 exists

Fresh Reviewer R1 correctly found blocking defects in the previous frozen subject `5e3ecef5e0e27849a2180258fb3d00f3ad949eb2`:

1. `_executor_result()` accepted a Dictionary without explicit `success=true`, violating fail-closed downstream-owner handling.
2. Mandatory negative coverage was missing for MW10 body mismatch, invalid resolver outputs, and malformed executor outputs.

The R1 control dispatch was also invalid because its evidence map did not conform to `distributed_world_simulator.harness_evidence_map.v1`. R1 PR #471 is closed/aborted and MUST NOT be used as the canonical reviewer source. R1 published no official review-result JSON.

R2 is a clean dispatch from canonical main with repaired runtime evidence and schema-valid control evidence.

## Frozen repaired runtime subject

- runtime branch: `feature/v0-p7-bounded-terrain-mutation`
- runtime PR: `#466`
- HEAD: `c2e056980eed4ae20849154b1dacc71af0ce8bdf`
- TREE: `2df40d13610b5a93cd1549d8c1bc89205026e1f5`
- activation/main base: `aca907022bf3a3239ae53ae0583c6aff8004da98`
- runtime Project Control: `33696913965 = SUCCESS`

Do not review a later runtime branch head. Do not rebase or mutate runtime.

## Exact runtime delta

From activation base to repaired subject:

- 4 commits
- exactly 4 files
- +847/-13

Files:

1. `scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd`
2. `scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd`
3. `tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd`
4. `tests/runtime/test_v0_p7_6_seam_multi_region_composition.gd`

No Matter contract, MW8/MW9/MW10 foundation, persistence, Item Graph, network protocol, or architecture-ownership file is changed.

## Mandatory evidence inputs

- Work Order `V0-P7-R1-WO-001.v1.json`
- `V0-P7-R1-P7-6-EVIDENCE-MAP-002.v1.json`
- `V0-P7-R1-P7-6-REPAIR-R1-LINUX-EXACT-RUNTIME-VALIDATION-002.v1.json`
- accepted P7.5 closure/reviewer/verifier evidence
- accepted SM1/MW8/MW9/MW10 ownership/contracts consumed by P7.6
- R1 aborted PR #471 only as historical repair context, never as accepted reviewer evidence

Linux execution evidence is supporting execution evidence only. It is not a Reviewer or Verifier verdict.

## Exact repaired Linux evidence

Canonical Godot:

- version: `4.7.1.stable.double.custom_build.a13da4feb`
- binary SHA256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

Fresh repaired-subject execution:

- import: exit 0, fatal scan 0
- P7.1: PASS, 88 assertions, 0 failures, exit 0
- P7.6: PASS, 106 assertions, 0 failures, exit 0
- SM1: PASS, 145 assertions
- MW8: PASS, 98 assertions
- MW9 durable recovery: PASS, 203 assertions
- MW9 lock release retry: PASS, 12 assertions
- MW9 durable processes: PASS, 225 assertions
- MW9 race stress: PASS, 100 rounds / 13 batches
- MW10 transactions: PASS, 184 assertions
- MW10 processes: PASS, 51 assertions
- MW10 runner: PASS, 2/2
- final HEAD/TREE unchanged
- tracked tree clean
- fatal scan: zero matches

New repair coverage explicitly exercised:

- Dictionary without `success` -> `P7_6_SINGLE_REGION_EXECUTOR_INVALID_RESULT`
- null executor result -> `P7_6_SINGLE_REGION_EXECUTOR_INVALID_RESULT`
- Array executor result -> `P7_6_SINGLE_REGION_EXECUTOR_INVALID_RESULT`
- null resolver -> `P7_6_MW8_REGION_RESOLUTION_INVALID_RESULT`
- Array resolver -> `P7_6_MW8_REGION_RESOLUTION_INVALID_RESULT`
- empty resolver -> `P7_6_MATTER_TARGET_OUTSIDE_AUTHORITY_REGIONS`
- MW10 body mismatch -> `P7_6_MW10_PLAN_BODY_MISMATCH`
- invalid cases do not reach inappropriate single-region/MW10 execution

## Mandatory R2 review questions

1. Verify exact repaired runtime HEAD/TREE and exact four-file +847/-13 delta from activation base.
2. Confirm the R1 fail-open defect is actually fixed: a downstream Dictionary without explicit `success=true` must fail closed.
3. Confirm null and non-Dictionary downstream executor results fail closed and cannot be promoted into P7.6 success.
4. Confirm new negative tests materially execute body mismatch, null/Array/empty resolver cases, and malformed executor cases.
5. Confirm test growth did not weaken or bypass production validation to make cases pass.
6. Confirm `authorize_product_intent()` remains product-level identity/tool/SM1/reach authorization only and claims no MW8/MW9 authority.
7. Confirm existing `authorize_mutation()` still performs the pre-existing MW8 regional and MW9 durable/fencing checks for single-region mutation after product-intent extraction.
8. Confirm P7.6 remains stateless and owns no canonical Matter, authority lease, handoff state, transaction journal, durability, replay, persistence, Item Graph, authority directory, or network protocol.
9. Confirm actor seam uses existing SM1/MW8/MW9 and cannot invoke MW10 merely because the actor crosses a region boundary.
10. Confirm actor handoff checks the existing MW10 reservation interlock before calling the handoff executor.
11. Confirm one-region Matter mutation routes only to the existing P7.1 -> MW4 execution path.
12. Confirm any non-empty MW10 plan for a one-region request is rejected fail-closed.
13. Confirm single-region mutation is rejected when its region is reserved by MW10.
14. Confirm multi-region routing is selected only by canonical target-brick region resolution, never by a caller-supplied multi-region flag.
15. Confirm MW10 is used only for one canonical MatterMutationRequest spanning two or more authority regions.
16. Confirm an existing canonical MW10 plan is mandatory for multi-region execution.
17. Confirm exact binding of:
    - request/plan `operation_id`
    - request/plan `body_id`
    - sorted exact participant region set
18. Confirm invalid operation/body/region binding never reaches the MW10 coordinator.
19. Confirm region classification and plan execution contain no P7.6-owned TOCTOU state and downstream request/context/plan values are safely duplicated where necessary.
20. Confirm downstream error results preserve their existing meaningful error code when present and otherwise use the P7.6 fallback invalid-result code.
21. Confirm P7.6 PASS branch terminates with process exit 0 and no later unconditional exit 1.
22. Confirm all four changed runtime/test files are authorized by the existing P7 Work Order and no stop condition is triggered.
23. Explicitly search for any remaining way to:
    - invoke MW10 for actor-only seam movement,
    - execute cross-region Matter outside MW10,
    - weaken single-region MW8/MW9 authority,
    - bypass reservation interlocks,
    - introduce a P7-private authority/transaction/durable owner,
    - convert malformed downstream results to success.

## Reviewer result contract

Publish an official result only if this R2 dispatch itself has Project Control SUCCESS.

Create exactly one durable review-result JSON on a new result branch created from the exact R2 dispatch HEAD.

The review type is mandatory and exact:

```json
"review_type": "POST_BUILD_EXACT_HEAD_REVIEW"
```

Do not use a synonym.

Minimum result content:

- schema
- review_id
- work_order_id = `V0-P7-R1-WO-001`
- `review_type = POST_BUILD_EXACT_HEAD_REVIEW`
- fresh independent reviewer actor/role
- repaired runtime HEAD
- repaired runtime TREE
- activation base
- exact reviewed file list
- evidence inputs
- explicit disposition of both Reviewer R1 blocking findings
- findings
- required_fixes
- verdict
- `merge_authorized = false`

PASS requires zero blocking findings and `required_fixes=[]`.

Do not mutate authoritative event-ledger entries for the unmerged runtime subject.

Do not modify runtime.

Do not act as Verifier.

## Gate after Reviewer R2

Even if PASS:

- P7.6 is NOT COMPLETE
- Reviewer-result Project Control must be SUCCESS
- Fresh Independent Verifier remains required
- Human RUNTIME_FEATURE_MERGE remains closed
- PR #466 must remain unmerged
