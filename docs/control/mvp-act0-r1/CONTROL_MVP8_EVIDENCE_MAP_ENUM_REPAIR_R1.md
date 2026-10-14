# CONTROL-R1 — MVP8 Evidence Map Enum Repair

**Work Order:** `CONTROL-MVP8-EVIDENCE-MAP-ENUM-R1`  
**Class:** historical main-owned control-data/schema compatibility, control-only  
**Parent exact main:** `e98a489b591bb29025ffb69a6dbbf1c87b3b1542`  
**Original historical evidence-map blob:** `9d6d6c676fdca3501ec35b8962c8dca36eaccfd7`  
**Historical frozen product HEAD:** `90bc1026f0f5749492107191233330f87c8c70df`  
**Historical frozen product TREE:** `4b6f2d48f7ef8d9c441ae89d2cbb02c730ef7f71`

## Problem and scope

The already tracked `MVP8-EVIDENCE-MAP-90BC1026-R1.v1.json` contained five prose/transition statuses outside `config/control/harness/evidence-map.schema.v1.json`. `check-consistency` / `CONTROL_DEVELOPMENT.ps1` failed `CONTRACT_OR_DEPENDENCY_INVALID` before completing the normal mission control route. The evidence-map schema is **not changed**. This work order edits only five enum **values** in one historical map and adds a small read-only schema/provenance falsifier. No game code, checkpoint authority, work-order active state, schema allowlist, event log, PC0 mechanism or product acceptance is changed.

## Exact replacement and independent later evidence (all frozen to 90bc1026)

| Map field | Previous invalid | Corrected | Exact same-subject receipt |
|---|---|---|---|
| `focused_validation` | `PASS_TWO_EXACT_RUNS` | `PASS` | `evidence/MVP8-IMPLEMENTER-EXACT-EVIDENCE-90BC1026-R1.v1.json`: 2 Linux exact attempts 20/20 |
| `full_regression` | `PENDING` | `PASS` | `evidence/MVP8-FULL-WORLD-CORE-90BC1026-R1.v1.json`: 349/349 regression tests, 0 failed steps |
| `pc0` | `PENDING` | `NON_RED` | `evidence/MVP8-PC0-90BC1026-R1.v1.json`: standard YELLOW/non-red |
| `directional_pc0` | `PENDING` | `NON_RED` | Same exact R1 PC0 record: directional YELLOW/non-red |
| `review_verdict` | `PASS_READY_FOR_FRESH_REVIEW` | `PASS` | `verifications/MVP8-INDEPENDENT-REVIEW-90BC1026-R1.v1.json`: independent Reviewer PASS |

All receipt paths in this table are relative to `config/control/harness/executions/E2026-09-09-V0-MVP-R1/`.

**Provenance and time semantics:** the original evidence-map was written **before** these subsequent same-subject receipt records. This narrow normalization reflects the later accumulated control evidence at canonical main, not knowledge available when the original map was first authored. The original source blob SHA is pinned above. Existing narrative `remaining_risks`, `evidence_gaps` and `rank_up_moves` are left untouched as historical task notes, even where later receipts closed a gap.

**Important limit:** the R1 independent **Verifier** record (`verifications/MVP8-INDEPENDENT-VERIFICATION-90BC1026-R1.v1.json`) explicitly says `EVIDENCE_GAP`, **not** VERIFIED. Later final R2 MVP8 closure used a **different** frozen product HEAD (`dc6e7fff...`). Mapping `review_verdict=PASS` is about the R1 reviewer only; `full_regression=PASS` is about the later R1 Linux regression receipt, not an invented Windows verifier PASS. This repair DOES NOT promote MVP8 or NET-SMOOTH into acceptance.

## Verify independent, before any merge

1. Fresh detached worktree at exact repair commit. Confirm main and PR #762/#763/#764 unchanged.
2. Confirm only five enum values changed from the pinned historical main blob, plus tests and this Work Order doc.
3. `python -m unittest tests.harness.test_mvp8_evidence_map_enum_repair -v`: strict JSON Schema Draft2020-12, R1 receipt subject/head/tree, verifier gap, and original-token negative controls.
4. `PYTHONPATH=scripts python -m harness.control_candidate_validation`.
5. `PYTHONPATH=scripts python -m harness.cli check-consistency --candidate` and `python -m unittest discover -s tests/harness -p 'test_*.py' -v`. **Caveat:** candidate control route may load canonical `origin/main` rather than the branch's repaired local snapshot; if so do not claim PASS or silently change main. Record exact authority boundary and execute schema negative controls locally; prepare the explicit human-controlled merge/catch-up gate.
6. Run PC0 and directional PC0 only against the correct recorded authority boundary; preserve unrelated existing RED/YELLOW facts.

## Stop / handoff

Report `CONTROL_SCHEMA_SOURCE_FIXED` only when the new map validates and all exact evidence mappings are proven; `CONTROL_RUNTIME_RESTORED` requires a genuine control-path pass at the applicable authoritative main boundary. Any other schema failures must be reported independently. **Draft PR only; no auto-merge.**

After control recovery, resume separate NET-SMOOTH R3C design/implementation. R3B runtime remains `NARROW_VERIFIED / PERFORMANCE_FAIL`: baseline client freezes 2–4.4s, synchronous LEAVE/durable writes, and reconnect JOIN backpressure are not repaired by this Work Order.
