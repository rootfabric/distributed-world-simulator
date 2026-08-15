# V0-P1 R7 — Canonical Clock / Rejection Purity Repair

Exact repair base:

`bf24bb7cbea6fcf3aa48e341ce634f7be4146bef`

Repair branch:

`fix/v0-p1-canonical-clock-purity`

## Cross-review findings

The P2 review showed that P1 could leave a newly picked/split INVENTORY item without `location.slot_index`, then lazily repair that representation from `ensure_player()` or transfer/swap normalization before a command that ultimately rejected. That allowed canonical representation/checksum mutation without the corresponding revision/tick publication.

The first independent R7 review then found the same class of defect through hotbar displacement: `inventory.assign_hotbar` could replace a slotless hotbar item with another item and leave the displaced item as ordinary INVENTORY without `slot_index`, relying on P1 `create_snapshot()` normalization to repair it.

A related preflight risk existed for `item.transfer -> hotbar`: if an occupied hotbar slot required displacement but the backpack was full, source mutation could occur before assignment failure unless displacement capacity was checked first.

## Repair invariant

- existing-player `ensure_player()` is mutation-free;
- first player materialization may normalize starter compatibility state, but that change is published by the same materialization revision/tick advance;
- successful pickup, split and detach assign ordinary-inventory `slot_index` before the successful command is published;
- ordinary inventory transfer assigns `slot_index` inside the successful mutation;
- hotbar-assigned items may remain intentionally slotless while they are present in a hotbar;
- replacing an occupied hotbar slot assigns the displaced item a canonical free backpack `slot_index` before success publication;
- assigning an ordinary backpack item to hotbar releases its former backpack slot atomically, allowing the displaced hotbar item to reuse that slot;
- hotbar displacement capacity is preflighted before any WORLD-to-inventory source mutation;
- rejection-capable transfer/swap/hotbar preflight does not normalize or otherwise mutate canonical state;
- rejected commands preserve canonical revision, tick and checksum;
- P2 remains responsible for pure snapshot/export and explicit durable legacy migration.

## Focused regression

`tests/runtime/test_v0_p1_canonical_clock_purity.gd` runs through a test-only pure serializer so the regression cannot be falsely GREEN because P1 `create_snapshot()` performs compatibility normalization.

Covered sequences include:

1. existing-player ensure on deliberately slotless compatibility state is mutation-free;
2. pickup publishes slot identity before a pure snapshot, then duplicate pickup rejection preserves revision/tick/checksum;
3. split publishes slot identity before a pure snapshot, then invalid split rejection preserves revision/tick/checksum;
4. detach publishes slot identity before a pure snapshot;
5. invalid inventory transfer cannot normalize slotless compatibility state before rejection;
6. invalid hotbar index is rejected before source mutation;
7. successful `inventory.assign_hotbar` replacement gives the displaced hotbar item a canonical backpack slot before the pure success snapshot;
8. full-backpack `WORLD -> occupied hotbar` rejects before moving the WORLD source and preserves revision/tick/checksum.

The focused runner requires the exact expected zero-failure assertion summary and separately rejects parser/compile/startup errors.

This repair does not introduce a new Item Graph owner, client authority, P3 resource behavior, network authority change, or a new persistence owner.
