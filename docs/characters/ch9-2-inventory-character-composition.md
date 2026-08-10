# CH9.2 — Inventory + Character Composition

Status: IMPLEMENTED CANDIDATE  
Branch: `feature/ch9-2-inventory-character-composition`

## Goal

Connect the production Item/Container domain, the existing component Inventory UI and the accepted CH7/CH8 character-equipment presenter without introducing a second equipment truth.

```text
Inventory UI
    ↓ intent
CharacterEquipmentGameplayController
    ↓ semantic plan
CharacterEquipmentOperationService (CH9.1)
    ↓ canonical mutation
ItemTransferService
    ↓
ItemRegistry + equipment ContainerState
    ↓ read-only projection
ItemGraphEquipmentSource (CH9.0)
    ↓
CharacterEquipmentDomain.Snapshot
    ↓
CharacterEquipmentPresenter (CH7/CH8)
```

## Canonical state

Equipped items remain ordinary physical Item UUIDs with the existing `CONTAINER` relation. The character owns one slotted equipment container.

CH9.2 does not add `EQUIPPED`, does not add a second equipment registry and does not put equipment IDs into movement snapshots.

## UI

`CharacterEquipmentInventoryScreen` composes one additional `InventoryContainerPanel` with the existing component inventory screen. The five initial slots are:

1. head
2. back
3. upper
4. lower
5. feet

The panel is a view of the real equipment `ContainerState`; it is not a presentation-only slot model.

Dropping an item into this panel calls the CH9.1 operation facade. The panel preview also uses CH8 semantic candidate planning, so UI drop validation cannot bypass character equipment channels.

Dragging an equipped item back to a normal container calls CH9.1 `unequip_to_container`.

## Replacement policy

- empty equipment slot -> `ItemTransferService.move_item`;
- exactly one replaceable equipped item -> `ItemTransferService.swap_items`;
- replacement of more than one canonical item -> fail closed with `MULTI_ITEM_TRANSACTION_REQUIRED` before mutation.

The old item from a one-for-one replacement returns to the incoming item's previous canonical container relation.

## Presentation

After successful canonical mutation:

1. `ItemGraphEquipmentSource.refresh()`;
2. `CharacterEquipmentPresenter.apply_snapshot()`;
3. CH8 body suppression/topology coordinators consume the same snapshot;
4. normal item presentation/UI refresh follows.

The accepted CH8 body-visible inflated garment mode therefore remains a derived presentation choice. Base body/collision/gameplay identity are unchanged.

## Graphical lab

Scene:

`res://scenes/labs/character/quaternius_item_graph_equipment_lab.tscn`

Launcher:

```powershell
.\PLAY_CH9_2_INVENTORY_CHARACTER_LAB.ps1 -GodotPath $Godot
```

The launcher retains CH8 garment inflation tuning. Default CH9.2 visual values are deliberately conservative-to-large because the current prototype prioritizes no skin penetration:

```text
upper 0.032 m
lower 0.042 m
feet  0.040 m
scale 1.25
```

They remain presentation-only and tunable from PowerShell.

The inventory opens at startup. Drag wearable items from backpack into the equipment panel. `Tab` closes/opens inventory so movement, jump and crouch can be checked after equipping.

`U/L/K/H/B` equipment mutations are intentionally disabled in this lab. They would re-introduce the laboratory equipment source as competing truth.

## Automated gates

```powershell
.\RUN_CH9_2_INVENTORY_CHARACTER_COMPOSITION_TESTS.ps1 -GodotPath $Godot
```

Focused tests prove:

- production Item UUIDs start in the backpack;
- equipment is a real slotted ContainerState;
- UI panel renders the canonical slots;
- real equip advances item revision and moves the same UUID into equipment;
- ItemGraphEquipmentSource projects that state;
- CH8 presenter creates the corresponding visual;
- UI one-for-one replacement uses canonical swap semantics;
- unequip returns the same UUID to backpack and removes the visual;
- Item Graph remains valid;
- network equipment mutation remains disabled until CH9.3.

## Deferred

CH9.2 does not implement network equipment commands. Replica/network mutation returns an explicit deferred error; CH9.3 owns server-authoritative equipment command/replication composition.

Persistence/late join/reconnect acceptance remains CH9.4.
