# CONTROL-MVP8 Evidence Ledger R1 — immutable legacy Evidence Map quarantine

**Control repair, not FABRIC runtime.** Narrow branch: `repair/control-mvp8-legacy-evidence-map-quarantine-r1`, based on canonical `main` HEAD `aac301b9a9a89e027f6d99864437eb750a4202ca`.
**State:** IMPLEMENTER_CANDIDATE; independent control verification and human main merge required. No change to `main`, PR #784, #800, #818 or physical model.

## Root cause / RED

The one-time recorded `MVP8-EVIDENCE-MAP-90BC1026-R1.v1.json` in
`E2026-09-09-V0-MVP-R1/evidence/` wrongly claims the canonical
`distributed_world_simulator.harness_evidence_map.v1` schema.
Its preliminary stage labels violate the immutable
`config/control/harness/evidence-map.schema.v1.json`:
- `focused_validation=PASS_TWO_EXACT_RUNS` (schema permits PASS/FAIL/NOT_REQUIRED);
- `full_regression=PENDING` (schema permits PASS/FAIL/NOT_REQUIRED);
- `pc0=PENDING` and `directional_pc0=PENDING` (schema permits NON_RED/RED/NOT_RUN);
- `review_verdict=PASS_READY_FOR_FRESH_REVIEW` (schema permits PASS/FAIL/INSUFFICIENT_EVIDENCE).

The file was added exactly once (`918672b63af4fc938465ad726c6290a0be6a2402`),
is still present with immutable Git blob `9d6d6c676fdca3501ec35b8962c8dca36eaccfd7`,
and describes a historical **pre-final** stage (90bc1026), not the
eventual reviewed/accepted MVP8 conclusion (`dc6e7fff`). A naive rewrite
to `PASS` would invent evidence; widening enums would weaken the schema.

## Correct repair

Use the existing `scripts/harness/state_builder.py::_select_authoritative_evidence_paths` path,
already introduced for P7 evidence-ledger reconciliation, instead of changing
the historical record, schema, harness kernel, checkpoint catalog or product.
New per-epoch `evidence-ledger-reconciliation.v1.json`:
- exact full repository-relative path and exact Git blob pin for ONE pre-final MVP8 file;
- mandatory original single-add-commit, immutable byte identity and schema-name-misuse proof;
- wildcard/duplicate/path escape restrictions, no schema weakening;
- all future unlisted evidence maps still load and validate normally;
- genuine previously valid `MVP7-EVIDENCE-MAP-AD48B24D-R1.v1.json` remains in the canonical evidence selection.
The invalid record remains reachable as historical evidence and can never be
reinterpreted as a canonical PASS claim.

## Acceptance: no false-green

- Show original historic record is **still invalid under canonical schema**.
- Show selected canonical Evidence Map set can be validated after quarantining exactly that file.
- Tampered SHA/path/missing quarantine must be rejected, not treated as an empty set.
- `CONTROL_DEVELOPMENT.ps1 -Status` is executed from this canonical-main-derived branch. The preliminary MVP8 evidence-map `SCHEMA_INVALID` must no longer be the first error. **A separate next gate is still RED**, so overall Status cannot be reported as PASS.
  - Linux `python -m harness.cli status --root .` and Windows `CONTROL_DEVELOPMENT.ps1 -Status` each reproduced `EXIT 5 / EXECUTION_STATE_INVALID / EVENT_SUBJECT_NOT_ANCESTOR:E2026-09-09-V0-MVP-R1-V0-MVP-R1-WO-001-0050-MVP8-REPAIR-R2-INDEPENDENT-REVIEWER-PASS`.
  - The event `0050` points to an independently created reviewer branch `review/v0-mvp8-dc6e7fff-r1`, which is not an ancestor of main. This provenance failure is enforced by `scripts/harness/state_builder.py` and **must not** be hidden by removing or rewriting the reviewer evidence.
  - CI validates the exact follow-on error as a distinct fail-closed diagnostic: `CONTROL_MVP8_EVIDENCE_SCHEMA_RECOVERED=PASS` and `CONTROL_FULL_STATUS=BLOCKED_EVENT_SUBJECT_NOT_ANCESTOR`. These markers are NOT `PC0_NON_RED`.
- Run all existing Harness regressions plus focused tests; compare Windows and
  Linux; pin `jsonschema==4.22.0`.
- Prove `main` has not moved/been written, scope narrow, historical blob unchanged.
- Independent Reviewer/Verifier on frozen control HEAD before requesting merge
  into canonical main; only HUMAN may authorize direct merge.

## Separate potential blocker

`WORK_ORDER_CHECKPOINT_NOT_CANONICAL` reported from an older FABRIC research
worktree is a **different control-plane basis**: its historical checkpoint catalog
did not declare the latest V0 checkpoint. Canonical main *does* declare
`V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`. This repair does not
falsely make old research worktree a replacement for main: call control
from canonical main or an explicitly main-derived control candidate.
If status on this new main-derived branch fails for another exact reason,
report it with logs and prepare a separate narrow repair rather than masking it.

**Scoped evidence-repair verdict:** `SCHEMA_GATE_RECOVERED / FULL_HARNESS_STATUS_BLOCKED_ON_INDEPENDENT_EVENT_PROVENANCE` until separately repaired. This branch must never be called `CONTROL_TOOLING_RESTORED` or `PC0_NON_RED` based on schema tests alone.

**Follow-on work:** require a *separately authorized and reviewed* narrow event-provenance repair. A historic reviewer-pass event is meaningful; a permissive exemption from ancestry checking or bulk deletion/relabeling of canonical event history would be outside this repair scope. First review the provenance rules and all later events, then decide a strictly proven, append-only reconciliation or proper canonicalized evidence rebind, without fabricated acceptance.
