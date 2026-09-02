# V0 P7.6 — Fresh Independent Reviewer R1

Role: FRESH_INDEPENDENT_REVIEWER. Read-only review. Do not act as Implementer or Verifier.

## Frozen runtime subject

- runtime branch: `feature/v0-p7-bounded-terrain-mutation`
- runtime PR: `#466`
- HEAD: `5e3ecef5e0e27849a2180258fb3d00f3ad949eb2`
- TREE: `758863475efd093002ce39c7ce6a93e1f8d55520`
- activation/main base: `aca907022bf3a3239ae53ae0583c6aff8004da98`
- runtime Project Control: `33670387232 = SUCCESS`

Do not review a later branch head. Do not rebase or modify runtime.

## Exact delta to review

The frozen candidate is exactly 2 commits ahead of the activation base and changes exactly 4 files:

1. `scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd`
2. `scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd`
3. `tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd`
4. `tests/runtime/test_v0_p7_6_seam_multi_region_composition.gd`

Recorded delta: `+749/-13`.

No Matter contract, MW8/MW9/MW10 foundation, persistence, Item Graph, network protocol, or architecture-ownership file is changed.

## Mandatory control/evidence inputs

- Work Order `V0-P7-R1-WO-001.v1.json`
- P7.6 activation on canonical main `aca907022bf3a3239ae53ae0583c6aff8004da98`
- `V0-P7-R1-P7-6-EVIDENCE-MAP-001.v1.json`
- `V0-P7-R1-P7-6-LINUX-EXACT-RUNTIME-VALIDATION-001.v1.json`
- accepted P7.5 closure/reviewer/verifier evidence
- accepted SM1/MW8/MW9/MW10 contracts and ownership surfaces consumed by P7.6

The Ubuntu execution evidence is execution evidence only. It is NOT itself a Reviewer or Verifier verdict.

## Exact Linux evidence available to review

Canonical Godot:

- version: `4.7.1.stable.double.custom_build.a13da4feb`
- binary SHA256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`
- archive SHA256: `d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92`

Observed exact-head results:

- import: exit 0, no SCRIPT ERROR / Parse Error / Failed to load
- P7.1 authority gate: PASS, 88 assertions, 0 failures, exit 0
- P7.6 composition: PASS, 71 assertions, 0 failures, exit 0
- SM1 world mutations around handoff: PASS
- MW8 regional authority handoff: PASS, 98 assertions
- MW9 durable recovery: PASS, 203 assertions
- MW9 lock release retry: PASS, 12 assertions
- MW9 durable processes: PASS, 225 assertions
- MW9 race stress: PASS, 100 rounds in 13 batches
- MW10 transactions: PASS, 184 assertions
- MW10 processes: PASS, 51 assertions
- MW10 runner: PASS, 2/2 suites
- final tracked tree clean; HEAD/TREE unchanged

GitHub self-hosted Linux run `33670639963` was still queued when dispatch evidence was prepared and MUST NOT be treated as a PASS.

## Mandatory review questions

1. Confirm the exact HEAD/TREE and exact 4-file delta from `aca907022bf3a3239ae53ae0583c6aff8004da98`.
2. Confirm `p7_seam_multi_region_composition.gd` is a stateless routing adapter and owns no Matter truth, authority lease, handoff state, transaction journal, durability, replay ledger, Item Graph state, or network protocol.
3. Confirm actor seam crossing uses only the existing SM1/MW8/MW9 handoff executor and that no actor-seam path can invoke MW10 merely because a region boundary is crossed.
4. Confirm single-region Matter mutation delegates to the existing P7.1 -> MW4 path and cannot enter MW10.
5. Confirm supplying an MW10 plan for a single-region request is fail-closed.
6. Confirm true multi-region execution is entered only when one canonical MatterMutationRequest resolves to two or more authority regions.
7. Confirm multi-region execution requires a canonical existing MW10 plan and validates:
   - operation_id equality,
   - body_id equality,
   - exact participant region set equality.
8. Confirm P7.1 `authorize_product_intent()` extracts only product-level identity/tool/SM1/reach authorization and deliberately does NOT claim MW8/MW9 regional authority for all participants.
9. Confirm existing P7.1 `authorize_mutation()` still applies its prior MW8/MW9 regional/durable authority checks for the single-region path after the refactor.
10. Confirm MW10 reservation interlock prevents:
    - actor handoff into a reserved region,
    - single-region mutation against an MW10-reserved region.
11. Confirm no TOCTOU or bypass introduced by region classification/plan comparison permits a mismatched MW10 participant set.
12. Confirm deterministic normalized region ordering is compatible with the existing MW10 plan participant ordering contract.
13. Confirm execution result handling remains fail-closed for non-dictionary or unsuccessful downstream results.
14. Confirm no changed file violates `V0-P7-R1-WO-001` allowed/forbidden paths or stop conditions.
15. Confirm the P7.6 test actually terminates with exit 0 on PASS and no longer executes a later unconditional `quit(1)`.
16. Inspect sibling regressions for semantic coverage, especially SM1, MW8, MW9 durable/race, and MW10 reservation/transaction behavior.
17. Explicitly assess whether any missing test permits:
    - false MW10 invocation on an actor seam,
    - cross-region mutation without MW10,
    - a P7-private authority or transaction owner,
    - weakened single-region authority authorization.

## Reviewer output contract

Create exactly one durable review result JSON on a new result branch created from the exact reviewer-dispatch HEAD.

The result MUST use the canonical review type exactly:

```json
"review_type": "POST_BUILD_EXACT_HEAD_REVIEW"
```

Do not use a synonym, abbreviated form, or custom P7.6 review type.

Minimum required result fields:

- schema
- review_id
- work_order_id = `V0-P7-R1-WO-001`
- review_type = `POST_BUILD_EXACT_HEAD_REVIEW`
- actor/role proving FRESH_INDEPENDENT_REVIEWER
- exact runtime HEAD
- exact runtime TREE
- exact activation base
- exact reviewed file list
- evidence inputs inspected
- findings
- required_fixes
- verdict
- merge_authorized = false

Allowed verdicts are the repository's canonical review verdicts. PASS is valid only with zero blocking findings and `required_fixes=[]`.

Do not create or mutate authoritative event-ledger entries for this unmerged runtime subject.

Do not modify runtime files.

Do not dispatch Verifier until the Reviewer result itself has Project Control SUCCESS.

## Gate state after reviewer work

Even on Reviewer PASS:

- P7.6 is NOT COMPLETE
- Verifier remains required
- Human `RUNTIME_FEATURE_MERGE` remains closed
- runtime PR #466 must not be merged
