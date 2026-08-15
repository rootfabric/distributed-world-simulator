# SM0-H2.2 — Repair Map R1 — handoff motion-state drift

Status: `FIX_REQUIRED`

Observed from exact P1 operator log on `b9a4667c536287af3b182a589835eb57bd703556`:

- first A -> B crossing arrived at correct position `x=0.0`;
- `player_entity_id` stayed `player/a`;
- but target player reported `velocity.x=5.0` while manual movement step at the boundary was `0.25`.

## Root cause

`sm0_authority_server_node.gd::_activate_imported_player()` currently:

1. joins the player on the target;
2. computes the distance from target-local spawn/current position to the source handoff position;
3. calls ordinary `move_player(delta_x, delta_z)` to move the newly joined target record to that position.

Canonical `player_movement_service.gd::apply_delta()` defines the resulting velocity as exactly the movement delta. Therefore a fresh target player spawned at `x=-5` and imported at `x=0` receives `velocity.x=5`, even when the source handoff package contains the real velocity `0.25`.

The same mechanism can also derive orientation from the relocation delta instead of preserving the package orientation.

## Canonical owner

The player record remains owned by `NetworkedGameplayService` / `PlayerRegistry`. The fix must happen through that existing canonical owner, not by editing graphical presentation or by storing a second SM0 player record.

## Exact correction

Add a server-internal handoff-import operation on `NetworkedGameplayService` and expose it through the existing `MultiplayerGameplayAuthority` wrapper.

After target join, SM0 will call that operation instead of using ordinary movement as a relocation primitive.

The handoff-import operation must:

- validate configured service;
- validate current player ownership/session/ownership epoch;
- require the exact stable `player_entity_id`;
- accept trusted server-side handoff motion state only (`position`, `velocity`, `orientation_yaw`, `last_input_sequence`, `source_state_revision`);
- build a candidate from the canonical target player record, preserving target session and target ownership epoch;
- validate the resulting canonical player record with `PlayerSnapshot.validate_player_record`;
- upsert only through canonical `PlayerRegistry`;
- advance canonical service revision/tick;
- return the canonical imported player.

State-revision rule: target import is a new canonical mutation, so resulting `state_revision` is `max(target_record.state_revision, source_state_revision) + 1`. It must not go backwards.

No client/wire command is added; this is a server-internal authority operation used only by the handoff layer.

## Regression

Add focused SM0 test proving a fresh target import where:

- target current/spawn `x=-5`;
- source handoff position `x=0`;
- source velocity `x=0.25`;
- source yaw `PI/2`;
- source input sequence is nonzero.

After import assert:

- position exactly matches package position;
- velocity exactly matches package velocity and is not the relocation distance;
- yaw matches package yaw;
- last input sequence matches package sequence;
- player entity id remains `player/a`;
- target transport session and target ownership epoch remain the target-owned values;
- state revision is monotonic above both target pre-import and source revision.

Then rerun exact-Godot H2.2 persistence/recovery focused tests, because H2.2 persists the target state immediately after this import boundary.

## Sibling surfaces

Check but do not redesign:

- H1 transport fault handling;
- H2.1 crash-before-PREPARED;
- graphical/manual client;
- canonical movement semantics for ordinary `CLIENT_MOVE` — these must remain unchanged.
