# CH9.1 — Authoritative Equipment Operations

## Goal

Connect the accepted CH9.0 read-only Item Graph equipment projection to real canonical item transfers without creating a second equipment mutation system.

```text
backpack/container Item
        |
        | existing ItemTransferService
        v
entity-owned equipment ContainerState
        |
        v
ItemGraphEquipmentSource
        |
        v
CharacterEquipmentDomain.Snapshot
        |
        v
CharacterEquipmentPresenter
```

## Ownership

CH9.1 does **not** own Item Graph state, operation durability, network replication or persistence.

Canonical mutation owner remains:

```text
ItemTransferService
  + ItemRegistry
  + ContainerRegistry
  + ItemOperationLedger
```

`CharacterEquipmentOperationService` is a character-domain facade that validates the desired equipment result and delegates the actual mutation to existing item primitives.

## Canonical equipment representation

No new `EQUIPPED` item relation is introduced.

An equipped item remains:

```text
relation.kind = CONTAINER
relation.container_id = entity equipment container
relation.slot_index = canonical equipment slot
```

The same physical Item UUID moves between inventory/backpack and equipment.

## Supported operations

### Strict equip

```text
item in normal container
  -> plan candidate against current equipment snapshot
  -> require empty physical equipment slot
  -> require no CH8 semantic channel conflicts
  -> ItemTransferService.move_item(...)
  -> refresh ItemGraphEquipmentSource
```

### Unequip

```text
item in equipment container
  -> ItemTransferService.move_item(... target container ...)
  -> refresh ItemGraphEquipmentSource
```

### One-for-one replacement

When exactly one equipped item must leave the same physical equipment slot, CH9.1 uses the already atomic `ItemTransferService.swap_items` operation.

```text
incoming item in backpack slot X
old item in equipment slot Y
        |
        | swap_items
        v
incoming item -> equipment slot Y
old item      -> backpack slot X
```

The transfer service snapshots both item relations and both container memberships, validates both final targets/capacities, and restores the snapshot on failure.

## Multi-item replacement policy

A profile such as an EVA suit can occupy several semantic channels simultaneously and may conflict with multiple currently equipped items.

Example:

```text
upper + lower + feet
        ^   ^     ^
        |   |     |
        +---EVA---+
```

CH9.1 deliberately does **not** implement this by chaining several `move_item` calls. That would allow partial canonical commits.

Instead planning returns:

```text
MULTI_ITEM_TRANSACTION_REQUIRED
```

and execution fails before changing Item Graph state.

A later implementation may support this only through an existing/shared multi-item transaction boundary. Character presentation must not invent a private transaction coordinator.

## Pre-commit validation

`ItemGraphEquipmentSource.plan_candidate()` is read-only. It validates:

- real Item exists;
- quantity is exactly one;
- real equipment slot accepts the ItemDefinition;
- slot has a registered character equipment profile;
- CH8 layout/tag/capability/channel rules;
- optional modeled removal of a proposed replacement item.

This allows CH9.1 to know the resulting semantic equipment state before canonical transfer.

## Revision / operation semantics

The facade passes caller operation IDs and expected item revisions directly to `ItemTransferService`.

Therefore the existing item Operation Ledger remains the only operation ledger for the mutation.

No character-specific replay ledger is introduced.

Desired-state retries are additionally safe at the facade: if equip/unequip/replacement has already reached the requested canonical relation, the facade returns a no-change success rather than reversing the state.

## Post-commit projection gate

Every successful transfer is followed by `ItemGraphEquipmentSource.refresh()`.

The projected snapshot must agree with the canonical relation:

- equip/replacement -> item is present in equipment snapshot;
- unequip -> item is absent.

A mismatch returns `POST_COMMIT_PROJECTION_FAILED` and explicitly reports that canonical mutation already committed. This is an observability error, not a rollback attempt by presentation code.

## Tests

```text
res://tests/characters/test_ch9_1_authoritative_equipment_operations.gd
res://tests/characters/test_ch9_1_multi_conflict_guard.gd
```

Runner:

```powershell
.\RUN_CH9_1_AUTHORITATIVE_EQUIPMENT_OPERATIONS_TESTS.ps1 -GodotPath $Godot
```

The first gate proves strict equip, unequip, atomic one-item replacement, revision rejection, slot rejection, UUID conservation, graph consistency and desired-state retries.

The second gate proves a multi-conflict EVA candidate is planned but cannot mutate through CH9.1 until a shared multi-item transaction primitive exists.

## Non-goals

CH9.1 does not yet add:

- inventory UI equipment slots;
- graphical inventory-to-character composition;
- multiplayer replication acceptance;
- persistence/late join/reconnect acceptance;
- multi-item atomic replacement;
- cloth or garment fit optimization.

Those remain later CH9 stages.
