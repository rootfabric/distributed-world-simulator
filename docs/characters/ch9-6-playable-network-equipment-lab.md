# CH9.6 — Playable Network Equipment Lab

## Purpose

CH9.6 closes the remaining playable composition gap after CH9.5. It does not add a new equipment model, transport, authority registry, persistence format or presentation truth.

The accepted pieces already exist independently:

- CH9.2: real Inventory UI -> character equipment slots -> real Quaternius presenter;
- CH9.3: server-authoritative equipment over the existing ITEM channel plus multiplayer replication;
- CH9.4: equipment-aware M6 durable recovery;
- CH9.5: persistent live ENet restart/reconnect/late-join composition and Item Graph driven presentation coordination.

The missing proof was one production-shaped playable path where the actual Inventory UI invokes the network-aware character equipment controller rather than a local ItemTransferService or a low-level test command.

## Composition

```text
CharacterEquipmentInventoryScreen
        |
        v
NetworkCharacterEquipmentGameplayController
        |
        v
Ch9NetworkItemCommandBridge
        |
        v
existing ITEM / ENet channel
        |
        v
CH9.5 persistent dedicated server
        |
        v
canonical server Item Graph
        |
        v
replicated / predicted canonical projection
        |
        v
replica Item Graph
        |
        v
ItemGraphEquipmentSource
        |
        v
CharacterEquipmentPresenter
        |
        v
Quaternius avatar
```

The canonical equipped relation remains `CONTAINER`. Movement snapshots remain equipment-ID free.

## Runtime

Scene:

`res://scenes/labs/character/quaternius_playable_network_equipment_lab.tscn`

Low-level launcher:

```powershell
.\PLAY_CH9_6_NETWORK_EQUIPMENT_LAB.ps1 -GodotPath $Godot -ResetState
```

`-ResetState` removes the CH9.6 lab persistence root before bootstrap. Without it, the fixed `user://ch9-6-playable-network-equipment-lab` state is intentionally reused so closing and reopening the lab demonstrates recovered equipment.

The lab embeds the accepted CH9.5 persistent dedicated server and a CH9.3 graphical ENet client for logical player `a`. After JOIN, the client canonical Item Graph is converted through the accepted CH9 equipment replica adapter. The resulting replica graph backs the existing component Inventory UI.

## Guided manual graphical acceptance

Use the operator runner instead of manually coordinating the two launches:

```powershell
.\ACCEPT_CH9_6_GRAPHICAL.ps1 -GodotPath $Godot
```

The runner launches each graphical generation in a separate child PowerShell process because `PLAY_CH9_6_NETWORK_EQUIPMENT_LAB.ps1` exits with the Godot process exit code. This prevents the first graphical run from terminating the acceptance controller.

The accepted runner lineage also fails closed before graphical questions unless the Godot executable and all required Quaternius asset families exist, performs an editor import/parse pass, and executes targeted CH9.6 presentation and real GUI unequip-route probes before opening the client.

Generation 1 is launched with `-ResetState`. Generation 2 is launched without reset. After each graphical process closes, the runner asks only for observations that cannot be inferred safely from automated output.

By default it writes local evidence to:

```text
artifacts/ch9-6-manual/ch9-6-graphical-acceptance-YYYYMMDD-HHMMSS.json
```

The evidence schema is:

```text
planet_simulator.ch9_6_manual_graphical_acceptance_evidence.v1
```

The runner reports one of two explicit decisions:

```text
OPERATOR_REPORTED_PASS
OPERATOR_REPORTED_FAIL
```

It never promotes CH9.6 by itself and never treats a zero process exit code as graphical acceptance.

## Manual graphical acceptance contract

Generation 1:

1. Wait until the HUD reports CH9.6 `READY` and the inventory opens.
2. Confirm helmet/backpack/upper/lower/feet are visibly distinguishable as inventory items.
3. Drag lower/upper/feet (and optionally helmet/backpack) from backpack to their equipment slots.
4. Verify the items appear on the real Quaternius character.
5. Close inventory with Tab and verify movement/jump/crouch still work with the equipped presentation.
6. Close the application normally so the embedded CH9.5 server commits its final checkpoint.
7. Explicitly answer the runner's generation-1 visual questions.

Generation 2:

1. The runner starts the lab again without `-ResetState`.
2. Do not perform a new equip operation at startup.
3. Verify the previously equipped items are already present in the equipment slots and on the character.
4. Drag one restored equipped item onto an ordinary backpack cell.
5. Verify the item returns to the backpack and the same wearable disappears from the character.
6. Close the application normally.
7. Explicitly answer the runner's recovery and unequip visual questions.

Manual PASS remains a Windows operator decision. Automated output alone is not graphical acceptance.

## Automated gate

`test_ch9_6_playable_network_equipment_ui.gd` instantiates the same graphical lab scene headlessly. It calls the actual Inventory screen preview/drop routes, verifies server canonical Item Graph convergence, replica graph state, real `CharacterEquipmentPresenter` visuals, bridge activity, no movement snapshot equipment UUID, shutdown checkpoint, fresh lab recovery, same canonical wearable identity, recovered UI slot binding and recovered real presentation.

Additional hardening probes on the accepted lineage include:

- `test_ch9_6_wearable_inventory_presentation.gd` — prevents canonical wearables from becoming visually empty/inoperable UI cells;
- `test_ch9_6_graphical_unequip_route.gd` — covers the real GUI `preview -> drop -> equipment.unequip -> canonical backpack -> removed presentation` path that the original direct-handler focused test did not exercise.

Runner:

```powershell
.\RUN_CH9_6_PLAYABLE_NETWORK_EQUIPMENT_TESTS.ps1 -GodotPath $Godot
```

The exact Windows automated baseline passed:

```text
CH9.2 Inventory UI routes                 PASS 16
CH9.3 real ENet equipment replication     PASS 20
CH9.4 reconnect/recovery                  PASS 53
CH9.5 persistent ENet recovery            PASS 41
CH9.6 playable network equipment UI       PASS 22
```

During graphical hardening, the wearable inventory presentation probe also reported `PASS (31 assertions)` before the interactive client was opened.

## Graphical defects closed during acceptance

The manual pass exposed several issues that automated composition alone did not reveal:

- graphical acceptance initially asked questions even when the Godot client had not opened; the runner now fails closed;
- a fresh worktree could lack required Quaternius assets; the runner now checks base characters, animation library and modular outfits explicitly;
- full Quaternius archives contain irrelevant FBX/Unity exports with missing texture references; CH9.6 now treats those diagnostics as non-authoritative and validates the required Godot-friendly glTF runtime path directly;
- network-replica wearable definitions initially lost their icon metadata, making real canonical wearables appear as empty dark inventory cells; visible metadata is now restored and regression-tested;
- equipped-item drag back to backpack was rejected at GUI preview before the valid `equipment.unequip` handler could run; equipment-aware preview now routes the real graphical reverse path and a dedicated regression covers it.

## Accepted checkpoint

CH9.6 is `FOCUSED_ACCEPTED` on implementation head:

```text
e547ba52a440e72cc02c6bbe449edaf160bae7ab
```

The Windows operator explicitly accepted the graphical stage after the interactive fixes were exercised. The project conversation did not include the generated local evidence JSON path or the runner's literal `OPERATOR_REPORTED_PASS` console line, so repository documentation does not fabricate those values; the validation file records the operator declaration and that evidence limitation explicitly.

## Post-acceptance Project Control

The mandatory canonical audit was run from main:

```text
main head:            be6ea2a8636a9242fc808aea377d9144ef9bc9eb
registry generation:  69
base Overall:         YELLOW
CH:                   YELLOW
Directional Overall: YELLOW
Directional finding: YELLOW CH -> NX WATCH_HIT BLOCK: 2 path(s)
Combined:             YELLOW
```

Both canonical Project Control auditors completed successfully. CH is non-RED, so the CH9.6 post-acceptance control gate is satisfied.

The directional CH->NX watch remains visible and is not erased by acceptance. It is a convergence signal for future Character/Network work, not a reason to reopen the already accepted CH9.6 slice.

## Frozen state

The canonical main frontier doctrine requires:

```text
manual PASS -> CH9.6 ACCEPTED -> post-acceptance PC0 -> freeze slice
```

That sequence is now complete for CH9.6.

Do not create CH9.7 from the old stacked lineage. Future Character runtime work must wait until canonical `main` explicitly declares the next Character frontier and dispatches it from the then-current project epoch/base.

## Non-blocking interaction follow-ups

These do not reopen CH9.6 and are not CH9.6 acceptance blockers:

- direct `equipment -> hotbar` currently remains intentionally unsupported by the CH9.6 unequip preview. The correct future implementation is one atomic authority operation, not client-side `unequip` followed by a second independent hotbar mutation;
- `backpack -> hotbar` foundation already exists, but occupied-slot replacement UX/semantics should be hardened separately.

## Invariants

- one physical wearable = one canonical server Item UUID;
- equipped relation remains `CONTAINER` with equipment slot index;
- Inventory UI never mutates canonical equipment locally in replica mode;
- server authority remains canonical Item Graph;
- equipment commands use the existing ITEM channel;
- M6 remains persistence/recovery owner;
- client Item Graph is a replica/projection only;
- character meshes and wearable presentation stay client-only;
- movement/gameplay snapshots contain no equipment Item IDs;
- restart/reconnect rebuild presentation from canonical recovered state;
- CH9.6 owns no global foundation.

## Exit gate

CH9.6 exit requirements are complete:

- editor import on exact Windows Godot 4.7.1 double;
- CH9.2 UI route regression;
- CH9.3 real ENet regression;
- CH9.4 reconnect/recovery regression;
- CH9.5 persistent ENet regression;
- CH9.6 playable UI network test;
- explicit Windows operator graphical acceptance on the accepted implementation lineage;
- an honest evidence record without inferred graphical observations;
- post-acceptance canonical PC0 with CH non-RED.

Current disposition: `FOCUSED_ACCEPTED_POST_PC0_NON_RED_FROZEN`.
