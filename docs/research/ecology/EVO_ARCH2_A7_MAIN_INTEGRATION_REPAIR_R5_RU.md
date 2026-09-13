# EVO ARCH2 A7 — Integration Repair R5

Дата: 2026-09-13. Parent Work Order: `EVO-ARCH2-A7-MAIN-INTEGRATION-20260913-R1`. Risk: HIGH.

## Exact recovery anchor до исправления

- Branch: `integration/eco-evo-arch2-a7-main-r1`, PR #617.
- Last inspected implementation: `e35ac07582c36b75d3cd05bdc8b66d8dbe84c681`.
- TREE: `5afda121c0cba32e8637a4d6cc5cf4cfe127025c`.
- Canonical main/base: `7dfc68ab5a1e90254a1b7039807f275b5da04eef`.
- Accepted research A7: `8eccf6304078bec3a3ccaa5860c5aab6ee311209`, tree `24e876b7377cb3e1e521f08ff9766331fe4e895a`.
- Last completed durable predicate: R4 source published; Project Control run 34744922632 succeeded, but exact-head independent review found two P1 defects. This is NOT integration acceptance.
- Known failures: verifier requires jsonschema 4.25.1 while main-owned Harness requires 4.22.0; lineage guard checks immediate parents only.
- Next action: implement R5 guards and regression tests, align Work Order and validation orchestration, freeze new exact HEAD/TREE, execute exact Linux verification and fresh independent review.
- Recovery route: GitHub connector for reads/writes; existing `validation/eco-arch2-a7-main-integration-r1` repository-owned CI for execution. Do not bootstrap network-restricted container clones or use Actions as Git transport.
- Stop before: main merge, A8 dispatch, production promotion. No independent PASS or MISSION_COMPLETE is asserted here.

## Repair Map / Design Brief

### R5-01 — canonical Harness dependency

Finding: PR #617 discussion `3999074189` on exact `e35ac075...`.

Owner: main-owned `scripts/harness/requirements.txt` and `scripts/harness/contracts.py`. Both require exactly `jsonschema==4.22.0`. R4 prose incorrectly claimed 4.25.1 was canonical. That historical statement is superseded by this correction; main's dependency contract must not be changed to accommodate the integration verifier.

Entry/callers/siblings: integration `verify.py` environment guard, the same interpreter's full Harness discovery, Work Order predicate, static/exact CI Python bootstrap and summary assertions.

Root cause: integration-local pin was guessed independently of the canonical dependency contract. A single environment cannot satisfy both version guards.

Fix: use canonical 4.22.0, mechanically compare the verifier pin with the requirements file, reject missing/wrong dependencies, and install canonical requirements only in a disposable CI environment. Run the complete Harness discovery with the same interpreter, with no skips or filtered modules.

Negative controls: 4.25.1, absent distribution, missing/ambiguous/conflicting canonical requirements. Positive control: canonical 4.22.0 plus full Harness suite. No production ecology or main-owned Harness implementation changes.

### R5-02 — whole-ancestry exclusion

Finding: PR #617 discussion `3999074192` on exact `e35ac075...`; prior defect was not fully fixed by immediate-parent inspection.

Owner: integration verifier's provenance fence. The accepted source is transfer evidence, not a permitted research-history parent at any depth.

Entry/callers/siblings: exact CLI, accepted ref HEAD/TREE binding, base-main ancestry, static CI and repeat verification.

Fix: after verifying the accepted object exists, use `git merge-base --is-ancestor ACCEPTED_A7 HEAD` and accept ONLY exit 1. Exit 0 rejects research ancestry; any other exit rejects an indeterminate graph. Reject shallow history, disable Git replace objects for verifier Git commands, and preserve the base-main ancestor check. Do not confuse an absent object or command failure with proof of non-ancestry.

Tests: real temporary Git histories through the same production guard, including clean convergence, direct/distant research ancestor, merge-side ancestor, HEAD equal to research, absent object, unrelated base, shallow history and replacement-object masking. Preserve exact accepted subtree/blob checks and the one previously authorized Harness test modification.

### R5-03 — sibling fail-closed control result

Inspection found `health != RED` would accept missing/unknown health. Within the same integration verifier require an explicit GREEN or YELLOW result, keeping YELLOW visible. This does not waive existing ECO findings or infer global GREEN.

## Scope and evidence

Allowed: existing integration verifier, a focused regression test in `validation/ecology/evo_arch2_a7_main_integration/`, this repair document and existing integration Work Order. CI orchestration changes stay on the existing validation branch, not in the runtime PR. Prior R1–R4 records remain historical.

Unchanged: accepted A0–A7 runtime/test/scene/protocol bytes; `scripts/harness/requirements.txt`, `scripts/harness/contracts.py`, registry/catalog/scheduler, production/network/simulation, project.godot. The already authorized `tests/harness/test_v0_mvp_act0.py` repair is retained byte-exact.

Required evidence: focused negative/positive guards; exact source and transfer identities; cold Godot import; all A0–A7 suites and A5 repair oracles; A6/A7 cross-process restart; mandatory graphical capture; full Harness discovery; explicit non-RED standard/directional reports; final clean HEAD/TREE; fresh independent exact-head review. Source research acceptance is not evidence of integration success.

Post-build critique must examine duplicate pin authority, guard bypasses and preservation of all previous gates. Append execution/review evidence separately after freezing the tested source, so later evidence publication does not make review stale.
