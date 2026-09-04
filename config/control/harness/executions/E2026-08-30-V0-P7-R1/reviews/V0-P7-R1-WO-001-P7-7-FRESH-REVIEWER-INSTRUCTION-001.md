# V0 P7.7 — Fresh Independent Reviewer R1

Role: **FRESH_INDEPENDENT_REVIEWER**. Read-only post-build exact-head review. Do not act as Implementer, Verifier, Director, or Human runtime merge approver.

## Frozen runtime subject

Review exactly this subject and no later runtime head:

- runtime branch: `feature/v0-p7-bounded-terrain-mutation`
- runtime PR: `#487`
- HEAD: `9440df5d2596bcbd39b071a2b2f27d4fc74ce42d`
- TREE: `bfee0c4bb5b0a5cff1d056dcf4005e3446c0366d`
- runtime PR base: `3853082f412d696fcb4790003a748983ebc56d42`
- runtime Project Control: `33852376026 = SUCCESS`

Do not rebase, repair, amend, or mutate runtime.

## Exact runtime delta from PR base

`3853082f412d696fcb4790003a748983ebc56d42..9440df5d2596bcbd39b071a2b2f27d4fc74ce42d`

- 40 commits
- 25 files
- +5062 / -30

Exact changed files:

1. `RUN_V0_P7_5_TWO_CLIENT_CONVERGENCE_GATE.sh`
2. `RUN_V0_P7_7_GRAPHICAL_DIGGING_GATE.sh`
3. `config/matter/mw10-canonical-physical-output-durability.v1.json`
4. `config/matter/mw10-canonical-physical-output.v1.json`
5. `scenes/labs/p7/p7_7_digging_playground.tscn`
6. `scripts/runtime/networked_gameplay/p7/p7_digging_playground.gd`
7. `scripts/runtime/networked_gameplay/p7/p7_graphical_digging_slice.gd`
8. `scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd`
9. `scripts/simulation/matter/mutation/matter_excavation_service.gd`
10. `scripts/simulation/matter/transactions/distributed/matter_cross_region_physical_output.gd`
11. `scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_coordinator.gd`
12. `scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_record.gd`
13. `tests/matter/transactions/mw10_test_fixture.gd`
14. `tests/matter/transactions/test_mw10_canonical_physical_output.gd`
15. `tests/matter/transactions/test_mw10_cross_region_processes.gd`
16. `tests/matter/transactions/test_mw10_cross_region_transactions.gd`
17. `tests/matter/transactions/test_mw10_physical_output_durability.gd`
18. `tests/runtime/test_v0_p7_7_a_digging_playground.gd`
19. `tests/runtime/test_v0_p7_7_b_seam_near_single_region.gd`
20. `tests/runtime/test_v0_p7_7_c2_mw10_physical_output_delivery.gd`
21. `tests/runtime/test_v0_p7_7_c3_true_ab_end_to_end.gd`
22. `tests/runtime/test_v0_p7_7_d_mw10_reservation_conflict.gd`
23. `tests/runtime/test_v0_p7_7_e_actor_handoff_no_false_mw10.gd`
24. `tests/runtime/test_v0_p7_7_graphical_digging_slice.gd`
25. `tools/matter/mw10_cross_region_transaction_worker.gd`

The final three commits after the last A–H implementation subject change only repository-owned closure runners: add the P7.7 full gate and repair one stale expected P7.1 assertion summary in the nested P7.5 gate (`83 -> 88`). No product runtime file changes in that closure-runner delta.

## Mandatory evidence inputs

Read these accepted control inputs from canonical `main`:

- Work Order `V0-P7-R1-WO-001`
- `config/control/harness/v0-p7-7-formal-closure-frontier.v1.json`
- `config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/V0-P7-R1-P7-7-FORMAL-FULL-GATE-EXACT-RUNTIME-VALIDATION-001.v1.json`
- A through H P7.7 evidence records referenced by the formal full-gate evidence/frontier
- accepted P7.6 closure/reviewer/verifier evidence
- accepted P7.5 closure/reviewer/verifier evidence
- accepted P7.4 restart evidence
- existing MW4–MW10, SM1, RL2/RL3 and canonical Item Graph ownership contracts consumed by P7.7

Local attached-Godot execution evidence is supporting execution evidence only. It is not a Reviewer or Verifier verdict.

## Formal full-gate evidence already available

Canonical Godot:

- version: `4.7.1.stable.double.custom_build.a13da4feb`
- binary SHA256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

Exact frozen full gate:

- source export workflow: `33852447179 = SUCCESS`
- source export artifact: `9928848799`
- artifact digest: `sha256:4941039de1fcb24ecd944e8e0c8861086e6d1d6e41c187fbaa35a37c5b2b0894`
- source-export control Project Control: `33852447087 = SUCCESS`
- repository runner: `RUN_V0_P7_7_GRAPHICAL_DIGGING_GATE.sh`
- exit: `0`
- final banner: `V0-P7.7 GRAPHICAL DIGGING GATE GREEN`
- nested banner: `V0-P7.5 TWO CLIENT CONVERGENCE GATE GREEN`
- exact HEAD/TREE banners match the frozen subject
- total executed assertions: `2032`
- failures: `0`
- recursive logs: `32`
- fatal scan: `0`
- tracked checkout clean before and after

Direct formal-gate stages include P7.7 graphical/A/B/C0/C1/C2/C3/D/E, P7.6, MW10 transaction/recovery and MW4. Nested P7.5 full gate includes two-client convergence, M7, P7.4 restart/replay, P7.3/P7.2/P7.1, P5 reconnect/mining, MW6/MW7 including reconnect-replay-snapshot, RL2 and RL3.

## Mandatory Reviewer questions

1. Verify the exact runtime HEAD/TREE and exact 40-commit / 25-file delta from PR base.
2. Verify every changed production file is necessary to the P7.7 acceptance boundary or to the owner-level MW10/MW4 extension required by true A+B execution; identify any unrelated scope creep.
3. Confirm `p7_graphical_digging_slice.gd` remains a stateless composition adapter and owns no terrain, Matter, Item Graph, authority, transaction, replay, persistence, aim, or network truth.
4. Confirm `p7_digging_playground.gd` and the lab scene are noncanonical observation/interaction surfaces only and cannot become a second world-state owner.
5. Confirm A single-region excavation still routes only through existing P7.1 -> MW4 and does not invoke MW10.
6. Confirm B seam-near but single-region classification does not falsely invoke MW10.
7. Confirm true A+B classification is derived from canonical target brick regions, not a caller-supplied multi-region flag.
8. Confirm C3 executes two real regional MW4 mutations against one shared canonical Matter store under MW10, rather than fixture-only or P7-private mutation.
9. Review optional `target_scope_root` in `matter_excavation_service.gd`: default MW4 behavior must remain unchanged; regional scoping must accept only descendants of the canonical region root and must not create a second store or mutation contract.
10. Review `matter_cross_region_physical_output.gd`: confirm physical output is bound to canonical participant/plan identity, participant-local Matter requests are validated, target bricks cannot escape participant region root, and real `MatterMutationResult` / `MatterMaterialBatch` provenance is retained.
11. Confirm no physical batch is fabricated from mass ledger totals. Full physical fields must originate from canonical Matter mutation output.
12. Review MW10 transaction record v2 durability: participant physical outputs and terminal envelope must survive restart/recovery; legacy v1 record read compatibility must remain intact.
13. Confirm checkpoint, receipt and operation-result schemas were not silently widened or broken by C1 durability work.
14. Confirm missing required physical output on non-empty external mass output fails closed before the durable commit frontier advances.
15. Confirm exact replay returns the same durable physical output and cannot recommit an already journaled participant.
16. Confirm P7.3 cross-region delivery iterates immutable canonical participant batches in deterministic region order and synthesizes no aggregate thermodynamic batch.
17. Confirm exactly-once ownership remains the canonical Item Graph replay ledger; P7.7 introduces no private delivery receipt store.
18. Confirm a retry after partial delivery cannot duplicate already delivered participant batches and can retry the undelivered participant safely.
19. Confirm the same batch cannot be redirected to another logical player without the canonical Item Graph rejecting the operation.
20. Confirm visible A+B hole/changed-brick projection is derived from canonical regional `MatterMutationResult` values in the MW10 physical-output envelope, not from client-private geometry truth.
21. Confirm D reservation conflicts fail closed: B-only MW4 path is blocked while B is reserved by an active A+B transaction; a second A+B transaction is blocked before prepare/commit; no material or visual success leaks.
22. Confirm E actor A->B handoff uses existing SM1/MW8/MW9 route with `mw10_invoked=false`; subsequent B-only dig uses MW4 with MW10 still zero.
23. Confirm F material accounting and exactly-once semantics are truly covered by canonical P7.3/Item Graph behavior, not by a test-only counter.
24. Confirm G two-client convergence consumes unchanged existing MW6/MW7/M7/RL3 owners and adds no client-private terrain or inventory truth.
25. Confirm H replay/reconnect/restart composition is consistent with existing C1/C2/C3, P7.4 and MW7 reconnect owners and creates no second hole, second regional Matter commit, second Matter batch or second Item Graph delivery.
26. Confirm no P7-private persistence, replay ledger, transaction owner, authority directory, network protocol, Item Graph, or terrain store exists anywhere in the delta.
27. Confirm MW10 is not invoked by actor seam movement alone and cannot be bypassed for a true cross-region Matter request.
28. Confirm owner errors are fail-closed and meaningful downstream error codes are not converted into P7 success.
29. Confirm tests do not weaken production validation or rely on permissive mocks where the acceptance claims real owner behavior.
30. Confirm the final repository-owned P7.7 gate itself is strict: exact Godot identity, exact HEAD, exact TREE, clean tracked checkout, fatal scan and full P7.5 subgate.
31. Confirm the nested P7.5 gate repair `83 -> 88` only synchronizes the expected summary with the already-current P7.1 exact test and does not weaken a predicate or skip a stage.
32. Explicitly search for any path that could:
    - invoke MW10 for actor-only handoff,
    - execute true A+B outside MW10,
    - mutate canonical Matter from a client/visual adapter,
    - synthesize physical material fields from insufficient data,
    - duplicate material on replay/restart,
    - expose physical output before terminal commit,
    - bypass reservation interlocks,
    - introduce a second canonical terrain/inventory/persistence/replay owner.

## Reviewer execution boundary

Reviewer may run focused static or canonical-double-Godot smoke to corroborate findings, but must not treat inherited implementer execution as a Reviewer verdict. Reviewer is not the fresh Linux Verifier and need not re-run the entire 2032-assertion gate unless useful for review.

Do not modify runtime to make review pass. Any required runtime fix must be returned as a finding to Implementer/control.

## Reviewer result contract

Publish an official result only if this dispatch itself has Project Control SUCCESS.

Create exactly one durable result JSON on a **new result branch created from the exact dispatch HEAD**.

Required exact review type:

```json
"review_type": "POST_BUILD_EXACT_HEAD_REVIEW"
```

Minimum result content:

- `schema = distributed_world_simulator.harness_review_result.v1`
- unique review_id
- `review_type = POST_BUILD_EXACT_HEAD_REVIEW`
- `work_order_id = V0-P7-R1-WO-001`
- risk class `CRITICAL`
- fresh independent reviewer identity/role
- `reviewed_head_sha = 9440df5d2596bcbd39b071a2b2f27d4fc74ce42d`
- `reviewed_tree_sha = bfee0c4bb5b0a5cff1d056dcf4005e3446c0366d`
- reviewer dispatch HEAD
- runtime PR #487
- exact diff/file classification
- mandatory evidence inputs
- checked items/dispositions
- findings
- evidence gaps
- required_fixes
- risk assessment
- verdict
- `merge_authorized = false`

PASS requires zero blocking findings and exactly `required_fixes=[]`.

## Gate after Reviewer

Even on PASS:

- P7.7 is **NOT COMPLETE_MERGED**
- Reviewer result Project Control must be SUCCESS
- Fresh Independent Linux Verifier is still mandatory
- Human `RUNTIME_FEATURE_MERGE` remains closed
- runtime PR #487 must remain unmerged
- Reviewer must not create Human approval
