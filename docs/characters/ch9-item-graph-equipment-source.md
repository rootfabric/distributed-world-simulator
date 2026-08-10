# CH9.0 — Item Graph Equipment Source

Status: IMPLEMENTED CANDIDATE  
Branch: `feature/ch9-item-graph-equipment-source`  
Parent: `feature/ch8-layered-equipment`  
Global architecture: `GLOBAL-P0-2026-08-10-R2`

## Goal

Replace the laboratory equipment-state source with a production read-only projection from the canonical Item Graph while preserving the accepted character-presentation boundary.

```text
canonical ItemRegistry
+ canonical equipment ContainerState
            |
            v
ItemGraphEquipmentSource   READ ONLY
            |
            v
CharacterEquipmentDomain.Snapshot
            |
            v
CharacterEquipmentPresenter
            |
            v
rig-specific derived visuals
```

The adapter is intentionally not an equip/unequip service. Backpack -> equipment and equipment -> backpack mutations belong to CH9.1 and must use the existing authoritative Item/Container transaction path.

## Canonical representation

CH9.0 does not introduce an `EQUIPPED` Item relation.

Equipped items remain ordinary canonical Item Graph items with the existing relation:

```text
CONTAINER
  container_id = character equipment container
  slot_index   = semantic equipment slot
```

The equipment container is a normal `ContainerState`:

```text
storage_mode = SLOTS
owner_id     = character/world entity id
slot_rules   = accepted item definitions/tags
revision     = canonical equipment presentation revision source
```

This reuses production `ItemRegistry`, `ContainerRegistry`, `ItemRelations.CONTAINER`, item definitions and slot acceptance rules. No second item store or character-private inventory graph is created.

## Slot -> presentation profile mapping

The canonical container answers **which physical Item UUID occupies each equipment slot**.

A presentation configuration maps slots onto the existing character-equipment profiles:

```text
slot 0 -> equipment.helmet.mk1
slot 1 -> equipment.backpack.mk1
slot 2 -> equipment.layer.upper.peasant
slot 3 -> equipment.layer.lower.peasant
slot 4 -> equipment.layer.feet.peasant
```

The profile remains presentation/domain policy and is not serialized into movement snapshots or copied into Item identity.

Every mapped canonical equipment slot must be restricted by `accepted_tags` and/or `accepted_definition_ids`. A generic unrestricted container is rejected as an equipment source.

## Projection invariants

For every occupied mapped slot CH9.0 requires:

- Item UUID exists in production `ItemRegistry`;
- quantity is exactly 1;
- item relation is `CONTAINER`;
- relation `container_id` equals the configured equipment container;
- relation `slot_index` equals canonical slot assignment;
- item definition exists;
- the real `ContainerState` accepts that definition in the slot;
- mapped `CharacterEquipmentDomain.Profile` exists;
- the resulting profile does not violate layout/channel compatibility.

A failed refresh is fail-closed: the source exposes the error through `get_last_result()` and preserves the last valid presentation snapshot instead of projecting inconsistent Item Graph state.

## Revision semantics

`CharacterEquipmentDomain.Snapshot.revision` is derived from `equipment_container.revision`.

The source does not invent a parallel character-equipment revision. Canonical membership/slot mutations are expected to advance the existing container revision through the production item transaction path.

## Read-only ownership boundary

`ItemGraphEquipmentSource`:

```text
owns Item mutation       = false
owns container mutation  = false
owns network state       = false
owns persistence         = false
owns mesh/rig state      = false
```

It only projects canonical state into an already accepted presentation contract.

## CH9.0 tests

### Contract / live registry projection

`tests/characters/test_ch9_item_graph_equipment_source.gd`

Covers:

- production ItemRegistry + ContainerRegistry;
- five real global Item UUIDs;
- head/back/upper/lower/feet slot projection;
- exact state-fingerprint compatibility with `LabEquipmentSource`;
- canonical removal/reinsert projection;
- relation mismatch fail-closed behavior;
- slot-definition rejection;
- stacked equipped item rejection;
- owner mismatch rejection;
- read-only ownership report.

### Persistence-shape round trip

`tests/characters/test_ch9_item_graph_equipment_source_roundtrip.gd`

Covers:

- `ItemRegistry.to_dict/load_dict`;
- `ContainerRegistry.to_dict/load_dict`;
- JSON round trip converting integer dictionary keys to JSON object keys;
- stable equipment snapshot fingerprint;
- stable container revision;
- stable Item CONTAINER relations;
- rejection of unrestricted equipment slots.

### Runner

```powershell
.\RUN_CH9_ITEM_GRAPH_EQUIPMENT_SOURCE_TESTS.ps1 -GodotPath $Godot
```

The runner also executes the accepted CH7 equipment-domain and CH8 layered-equipment contract gates before CH9.0 tests.

## Deferred to CH9.1+

CH9.0 deliberately does not implement:

- backpack -> equipment transfer;
- atomic conflict replacement;
- equipment -> backpack transfer;
- UI drag/drop into equipment slots;
- server command endpoint;
- equipment replication;
- late join/reconnect;
- save/load integration beyond projection round-trip compatibility.

Planned continuation:

```text
CH9.0 Item Graph Equipment Source
    -> CH9.1 Authoritative Equip / Unequip Operations
    -> CH9.2 Inventory + Character graphical composition
    -> CH9.3 Multiplayer equipment presentation
    -> CH9.4 Persistence / late join / reconnect
```

## Current acceptance dependency

Development may proceed as a candidate, but formal CH9.0 acceptance remains blocked until the predecessor CH8 final regression gate is recorded and PC0 moves the Character active frontier in `main`.
