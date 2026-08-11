# CH9.6 — Playable Network Equipment Lab

## Purpose

CH9.6 closes the remaining playable composition gap after CH9.5. It does not add a new equipment model, transport, authority registry, persistence format or presentation truth.

The accepted pieces already exist independently:

- CH9.2: real Inventory UI -> character equipment slots -> real Quaternius presenter;
- CH9.3: server-authoritative equipment over the existing ITEM channel plus multiplayer replication;
- CH9.4: equipment-aware M6 durable recovery;
- CH9.5: persistent live ENet restart/reconnect/late-join composition and Item Graph driven presentation coordination.

The missing proof is one production-shaped playable path where the actual Inventory UI invokes the network-aware character equipment controller rather than a local ItemTransferService or a low-level test command.

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

The runner deliberately launches each graphical generation in a separate child PowerShell process because `PLAY_CH9_6_NETWORK_EQUIPMENT_LAB.ps1` exits with the Godot process exit code. This prevents the first graphical run from terminating the acceptance controller.

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
2. Drag lower/upper/feet (and optionally helmet/backpack) from backpack to their equipment slots.
3. Verify the items appear on the real Quaternius character.
4. Close inventory with Tab and verify movement/jump/crouch still work with the equipped presentation.
5. Close the application normally so the embedded CH9.5 server commits its final checkpoint.
6. Explicitly answer the runner's generation-1 visual questions.

Generation 2:

1. The runner starts the lab again without `-ResetState`.
2. Do not perform a new equip operation at startup.
3. Verify the previously equipped items are already present in the equipment slots and on the character.
4. Drag one restored equipped item back to the backpack.
5. Verify the same item disappears from the character.
6. Close the application normally.
7. Explicitly answer the runner's recovery and unequip visual questions.

Manual PASS must be reported by the Windows operator. The assistant must not infer graphical PASS from automated output.

## Automated gate

`test_ch9_6_playable_network_equipment_ui.gd` instantiates the same graphical lab scene headlessly. It calls the actual Inventory screen preview/drop routes, verifies server canonical Item Graph convergence, replica graph state, real `CharacterEquipmentPresenter` visuals, bridge activity, no movement snapshot equipment UUID, shutdown checkpoint, fresh lab recovery, same canonical wearable identity, recovered UI slot binding and recovered real presentation.

Runner:

```powershell
.\RUN_CH9_6_PLAYABLE_NETWORK_EQUIPMENT_TESTS.ps1 -GodotPath $Godot
```

The exact Windows automated candidate already passed:

```text
CH9.2 Inventory UI routes                 PASS 16
CH9.3 real ENet equipment replication     PASS 20
CH9.4 reconnect/recovery                  PASS 53
CH9.5 persistent ENet recovery            PASS 41
CH9.6 playable network equipment UI       PASS 22
```

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

CH9.6 can be accepted only when:

- editor import is clean on exact Windows Godot 4.7.1 double;
- CH9.2 UI route regression passes;
- CH9.3 real ENet regression passes;
- CH9.4 reconnect/recovery regression passes;
- CH9.5 persistent ENet regression passes;
- CH9.6 playable UI network test passes;
- `ACCEPT_CH9_6_GRAPHICAL.ps1` records `OPERATOR_REPORTED_PASS` on the same implementation lineage;
- manual graphical evidence is preserved;
- post-acceptance PC0 audit is performed before any later CH stage.
