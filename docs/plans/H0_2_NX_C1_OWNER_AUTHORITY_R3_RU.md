# H0.2 / NX.C1 — Owner Authority R3

## Identity

- Epoch: `E2026-08-13-H0-2-R3`
- Work Order: `H0-2-R3-NX-C1-WO-001`
- Branch: `feature/h0-2-nx-c1-owner-authority-r3`
- Exact base: `09714b6f2681e3b5cf3f2f9e28416cf9a7378304`
- Registry generation: `79`
- Architecture: `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`
- Risk: `HIGH`

## Pre-dispatch boundary

The branch may contain only control/evidence/planning records before explicit Director dispatch. Production/runtime mutation is forbidden until an exact-head `PRE_BUILD_DESIGN_AUTHORIZATION` review returns `PASS` and the append-only ledger records `DISPATCHED`.

Exactly one autonomous runtime worker is permitted after dispatch.

Project Control must install `scripts/harness/requirements.txt` before contract-dependent regressions. The canonical pin is not bypassed or relaxed.

## Minimal runtime target

1. Add a bounded `MovementAuthorityProfile` with `SERVER_PREDICTED` and `OWNER_AUTHORITATIVE_VALIDATED` realtime locomotion modes.
2. Add owner-movement server validation for owner/session/epoch/playable-state identity, bounded plausibility and Godot `Basis(-Z) <-> yaw` round-trip.
3. Keep the local deterministic physics controller as the sole local body writer; accepted ordinary snapshots must not rewind the local owner.
4. Reuse current-main remote snapshot/interpolation behavior instead of importing the legacy FIX ladder.
5. Preserve canonical server Item Graph ownership while making same-revision optimistic pickup/drop rejection visible to the client presentation rollback path.

## Explicitly forbidden

- No wholesale legacy M7/FIX6-FIX10 cherry-pick.
- No FIX7 `_process()` writer to `CharacterBody3D` transform or velocity.
- No `network_protocol_manifest.gd` change under this HIGH Work Order.
- No architecture ownership/global identity/new foundation change.
- No cross-server authority change.
- No transfer of Item Graph, Character, Construction, Matter or persistence ownership into NX.
- No runtime merge and no H0.3 implementation.

If any forbidden capability becomes necessary, stop and replan/reclassify rather than widening scope silently.

## Validation ladder

Before implementation:

- canonical schema/semantic validation of epoch, Work Order and immutable event ledger with the repository-pinned Harness dependency;
- Project Control standard + directional NON_RED;
- exact-head HIGH pre-build independent review PASS;
- explicit Director dispatch.

After implementation, before H0.2/NX acceptance:

- focused owner-authority tests;
- physics/render single-writer test;
- same-revision item pickup/drop rollback test;
- client-tick duplicate/backward/huge-jump fuzz if touched;
- full world/core regression;
- two-client process validation;
- impaired-network validation;
- reconnect/ownership-epoch validation;
- post-build critique;
- exact-head Evidence Map and independent Reviewer/Verifier evidence;
- standard/directional PC0 NON_RED;
- mandatory fresh CH->NX directional dependency revalidation;
- recovery drill;
- draft PR and final `H0_2_PASS + NX SOURCE_ACCEPTED` proposal.

## Legacy evidence policy

Legacy runtime `464e1b8dd27fad8b4d477f6e76ca52a449893353` and acceptance record `538674d1f3f991c9e04d77b0ce0a4dfea24d9ce6` may inform behavior and tests. They are not merge bases and do not authorize importing the historical FIX lineage.

## Superseded attempts

- R1 was a planning probe created before the planning-branch/runtime-mutation semantic split was canonicalized. It is not authorization.
- R2 was cancelled before dispatch after Project Control correctly exposed the missing pinned Harness dependency setup. PR #95 was closed without merge and without runtime/domain mutation.

Only this R3 epoch is active authority for the H0.2 dispatch sequence.
