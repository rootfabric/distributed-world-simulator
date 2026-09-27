# MVP5 R1 — канонический материал ровно один раз

## Durable continuation anchor

- Parent: `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`.
- Predicate: `MVP_EXACTLY_ONCE_MATERIAL_OUTPUT`.
- Branch: `feature/v0-mvp-playable-seamless-planet-r1`, parent PR #597.
- Start HEAD: `d78760738e8032b97de2a433382fc7ddafa17fbf`.
- Start TREE: `bb1be98bbfb7341ae5dce555e964e837278287f7`.
- Canonical main observed: `9e10e640ffc53f82195f1fd930ebafbbc85e482f`.
- Last closed leaf: MVP4, immutable event 0014. MVP1–MVP4 are not reopened.
- Starting Project Control: run `34831352727`, job `103935183597`: complete Harness discovery, standard PC0 and directional PC0 SUCCESS.
- User instruction: «реализуй MVP5: exactly-once material output».
- This document is a design/continuation record, not an implementation or independent PASS.

## Live Simulator Baseline binding

`V0-MVP-LIVE-SIMULATOR-BASELINE-R1` is now a mandatory refinement of the parent Work Order and applies to this MVP5 leaf. MVP5 must therefore prove all three baseline sub-gates on the same live two-client composition path used by the product scene:

```text
LIVE_TOOL_GATED_DIG_TO_CANONICAL_OUTPUT
OUTPUT_EXACTLY_ONCE_UNDER_REPLAY
NO_SECOND_ITEM_IDENTITY_FOR_DUPLICATE_OPERATION
```

A backend-only receipt PASS, synthetic Item Graph mutation, local HUD counter or test-owned inventory truth is not sufficient to close MVP5. The existing MVP5 graphical/native accounting evidence remains the implementation route; this binding does not expand MVP5 into MVP6 item lifecycle, seam carry, Construction or restart recovery. Those remain later mandatory leaves of the same whole-MVP live simulator baseline.

Binding sources:

- `docs/control/mvp-act0-r1/MVP_LIVE_SIMULATOR_BASELINE_R1_RU.md`
- `docs/control/mvp-act0-r1/mvp-live-simulator-baseline-r1.v1.json`
- parent Work Order `V0-MVP-R1-WO-001`

## Problem and existing behavior

MVP4 already commits through the existing MW4/MW6/P7 path and invokes `P7MatterMaterialDeliveryCoordinator`. Its response does not expose the canonical Item Graph output to clients, and the graphical gate proves terrain, not material accounting. Matter commit and Item Graph delivery are separate effects: an output-port error must not turn a retry into a second carve or a second item.

Canonical owners remain unchanged:

- MW4 excavation journal and material receiver own the committed mutation and immutable material batch.
- P7 material delivery policy maps supported geological matter to `item/ore`: floor kilograms, with explicit fractional residual in the immutable batch provenance.
- Existing canonical M4 Item Graph owns inventory and the server-output replay ledger.
- NetworkedGameplayService owns aggregate revision/tick.
- MVP5 owns only composition, authenticated routing and disposable read-only presentation.

## Selected design

Add a bounded subclass of the existing MVP4 bridge. Execute the inherited authenticated, attested prepared-dig path without replacing any owner. On success reconstruct the output receipt from the actual immutable batch, existing P7 conversion policy and the existing Item Graph replay lookup. Do not apply a second output merely to obtain a receipt. Distinguish Matter replay from whether this call actually changed the Item Graph revision: a retried Matter commit may be the first successful item delivery.

Expose a bounded material projection from the actual canonical graph snapshot. Include stable item ids, quantities, inventory locations, canonical revision/checksum and a deterministic digest. Never trust quantities or receipts supplied by clients. Both clients receive the same shared A/B projection through the existing authenticated gateway/backend links. No private balance, delivery database or new replay owner is permitted.

A factory hook in the MVP4 authority process permits the MVP5 subclass to use the same single native owner. Existing MVP4 behavior remains the default. The new graphical client retains MVP4 terrain-only captures and inserts a material-baseline barrier, an exact prepared-operation retry sequence, and material observation after both terrain observers converge. Its UI displays server-derived values, never increments local inventory optimistically.

Alternatives rejected: a second inventory/replay ledger; changing canonical P7/MW4/M4 to satisfy a test; treating a success log or changed HUD pixels as material proof; skipping failed output recovery; delivering the same batch twice just to fetch metadata.

## Bounded write scope and risk

Parent risk remains CRITICAL; no risk downgrade. Runtime changes stay under `scripts/runtime/networked_gameplay/mvp/**`. Tests use `tests/runtime/test_v0_mvp_*`, `tests/integration/test_v0_mvp_*` and `tests/fixtures/v0_mvp/**`; scenes stay under `scenes/labs/mvp/**`; launcher uses the already allowed `RUN_V0_MVP_*` prefix. Documentation/evidence stay in parent-authorized directories.

Director validation-scope amendment for this explicit MVP5 request: add exactly `.github/workflows/mvp5-material-output-validation.yml` to the parent Work Order before introducing that file. It is read-only checkout/testing/artifact publication, not a new Git transport or write authority. Existing MVP4/world-core validation is reusable without changing its assertions. No new general workflow wildcard is authorized.

Forbidden owners and old events remain untouched. In particular: no edits to `scripts/simulation/matter/**`, `scripts/network/**`, `m4/**`, `p7/**`, `sm1/**`, architecture, acceptance records or `project.godot`.

## Required falsifiers and validation

1. Real first dig: one committed batch, positive output, canonical item id and quantity, explicit residual and conserved mass.
2. Exact replay and late replay after another operation: no extra Matter mutation, item id, quantity, graph revision or tick.
3. Failure before item application after Matter commit: retry delivers the retained batch once, without carving again.
4. Item application succeeds but acknowledgment is lost: retry returns the same canonical output, without duplication.
5. Foreign actor/session, modified prepared bytes and frozen source: authorization still precedes write/replay.
6. Replay fingerprint conflict: the existing owner rejects altered payload for the same output operation.
7. Two distinct graphical clients and two native authorities plus gateway: same canonical material projection, preserved connection/identity/input and actual terrain-only changes.
8. Evidence-consumer negative controls reject inflated quantity, different output id, duplicate output, mismatched client projection, stale subject and fake PASS.
9. Run focused tests, unchanged MVP4/MVP3 regressions, Harness and both PC0 audits on the new exact subject; full world/core must remain an explicit run, never inferred from the predecessor.

Failure injection belongs only to a test-owned proxy around the real stateless output port. No remotely accessible debug/fault switch will be added. Mechanical tests are Implementer/CI evidence, not an independent verdict.

## Explicit non-goals

MVP6 item/construction persistence, MVP7 reconnect/restart, cross-region excavation, item-bearing seam handoff, Windows physical-keyboard/manual acceptance, whole-MVP acceptance, main merge and foundation changes are not claimed by MVP5 R1. The exact prepared request is retained for retries in the current session; process-restart recovery belongs to its later declared predicate.

## Recovery and next action

Next: implement the bounded receipt/projection adapters and test fixtures, publish one exact candidate, run the repository-owned Linux double-engine workflow, repair concrete failures, then request fresh independent review/verifier on the frozen subject. Parent remains `IN_PROGRESS` until its own acceptance gates are satisfied.

Known executor route constraint: container GitHub DNS was unavailable. Use the working GitHub connector for repository read/write and repository CI for execution; do not retry an ad-hoc clone or export repository code through Actions as a transport workaround. CI must use pinned double Godot SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.