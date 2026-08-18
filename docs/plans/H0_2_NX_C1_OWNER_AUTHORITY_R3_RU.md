# H0.2 / NX.C1 — Owner Authority R3

## Identity

- Epoch: `E2026-08-13-H0-2-R3`
- Work Order: `H0-2-R3-NX-C1-WO-001`
- Branch: `feature/h0-2-nx-c1-owner-authority-r3`
- Exact base: `09714b6f2681e3b5cf3f2f9e28416cf9a7378304`
- Registry generation: `79`
- Architecture: `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`
- Risk: `HIGH`
- Exact source implementation head: `1814ca72c9569ea2aa7e3d1dd4a69eb790888908`
- Source state: `IMPLEMENTED`
- Runtime verification state: `PENDING_EXACT_GODOT_EXECUTION`

## Implemented capability

NX.C1 is implemented as an **opt-in realtime locomotion authorship profile**, not as a new owner of gameplay truth.

Supported modes:

- `SERVER_PREDICTED` — existing canonical default, unchanged;
- `OWNER_AUTHORITATIVE_VALIDATED` — the local deterministic movement controller authors realtime locomotion, while the server validates and only then accepts/relays the canonical player record.

New leaf components:

- `scripts/network/authority/movement_authority_profile.gd`;
- `scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd`;
- `scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd`;
- `scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd`.

No existing canonical M3/NX6 runtime file was rewritten to enable the feature.

## Authority boundary

Owner-authority is limited to realtime locomotion authorship.

The server still validates:

- active player connection;
- bound transport session;
- ownership epoch;
- monotonic input sequence;
- player-state schema;
- maximum velocity;
- maximum player/interaction displacement.

Only after those checks does the server update canonical player state.

Item Graph, inventory/container truth, persistence, Character ownership, Construction, Matter and cross-server authority remain with their canonical owners.

## Snapshot correction contract

Routine accepted snapshots do not rewind the local owner and therefore do not become a second local body writer.

An explicit rejected `PLAYER_STATE` arms exactly one canonical reconciliation on the next usable authoritative snapshot. After that correction, routine no-rewind behavior resumes.

This closes both failure modes:

- constant server rewind of valid local movement;
- permanent divergence after an invalid/rejected owner state.

## Dedicated-server readiness and recovery

The owner-runtime leaf blocks `ready_for_clients` while base setup is still using the default service. READY is emitted only after the owner validation service is installed.

When persistence is enabled, recovery/outbox adapters are rebound to the replacement service. The owner-authority leaf therefore does not bypass the existing durability/replay foundation.

## Item rollback contract

NX.C1 does **not** introduce another Item authority layer.

It reuses the canonical `PredictedItemInteractionJournal`:

- optimistic pickup/drop changes presentation only;
- authoritative snapshot remains unchanged;
- rejected pickup/drop at the same canonical revision restores presentation to authority;
- a partial predicted drop uses a temporary presentation item and removes it on rollback.

The focused partial-drop fixture uses the real sandbox beacon stack `3 -> 2 -> rollback -> 3`.

## Focused tests and runners

Added:

- `tests/network/test_nx_owner_movement_authority.gd`;
- `tests/network/test_nx_render_physics_separation.gd`;
- `tests/network/test_nx_owner_item_projection_rollback.gd`;
- `tests/network/test_nx_client_tick_robustness.gd`.

Focused runner also includes existing `tests/network/test_nx6_predicted_item_interactions.gd`.

Runners:

- `RUN_H0_2_NX_C1_TESTS.ps1`;
- `RUN_H0_2_NX_C1_TESTS.sh`.

## Source/control evidence

Project Control run `31690226579` on exact implementation head `1814ca72c9569ea2aa7e3d1dd4a69eb790888908`:

- pinned Harness dependency: PASS;
- architecture/ownership regressions: `64/64 PASS`;
- H0.2 machine regressions: `9/9 PASS`;
- standard PC0: `YELLOW / NON_RED`;
- directional PC0: `YELLOW / NON_RED`;
- `CH -> NX WATCH_HIT BLOCK` remains the expected revalidation gate before `NX SOURCE_ACCEPTED`.

The subsequent lifecycle state with Work Order=`IMPLEMENTED` was accepted by Project Control run `31690441709`.

## Explicitly not claimed yet

The following remain unaccepted until real exact-head Godot/runtime execution:

- `OWNER_AUTHORITY_FOCUSED_PASS`;
- `PHYSICS_PRESENTATION_SINGLE_WRITER_PASS`;
- `ITEM_ROLLBACK_PICKUP_DROP_PASS`;
- `CLIENT_TICK_FUZZ_PASS_IF_TOUCHED`;
- `FULL_WORLD_CORE_REGRESSION_PASS`;
- `TWO_CLIENT_PASS`;
- `IMPAIRED_NETWORK_PASS`;
- `RECONNECT_OWNERSHIP_EPOCH_PASS`;
- any tested head;
- post-build Reviewer/Verifier PASS;
- `H0_2_PASS`;
- `NX SOURCE_ACCEPTED`.

## Next gate

Run exact implementation head `1814ca72c9569ea2aa7e3d1dd4a69eb790888908` with the supplied Godot 4.7.1 stable double, starting with `RUN_H0_2_NX_C1_TESTS`, then execute full world/core, two-client, impaired-network and reconnect/ownership-epoch validation.

Only after exact runtime evidence may the Work Order enter `VERIFYING`, followed by post-build independent review, CH->NX directional revalidation and a possible `H0_2_PASS + NX SOURCE_ACCEPTED` proposal.

Runtime merge and H0.3 remain gated.

## Legacy evidence policy

Legacy runtime `464e1b8dd27fad8b4d477f6e76ca52a449893353` and acceptance record `538674d1f3f991c9e04d77b0ce0a4dfea24d9ce6` informed behavior/tests only. They were not merge bases and did not authorize importing the historical FIX6-FIX10 lineage.
