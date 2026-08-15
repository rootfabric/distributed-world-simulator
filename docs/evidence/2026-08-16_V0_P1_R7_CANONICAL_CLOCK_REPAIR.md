# V0-P1 R7 — Canonical Clock / Rejection Purity Repair

Exact repair base:

`bf24bb7cbea6fcf3aa48e341ce634f7be4146bef`

Repair branch:

`fix/v0-p1-canonical-clock-purity`

## Cross-review finding

P2 review showed that P1 could leave a newly picked/split INVENTORY item without `location.slot_index`, then lazily repair that representation from `ensure_player()` or transfer/swap normalization before a command that ultimately rejected. That allowed canonical representation/checksum mutation without the corresponding revision/tick publication.

## Repair invariant

- existing-player `ensure_player()` is mutation-free;
- first player materialization may normalize starter compatibility state, but that change is published by the same materialization revision/tick advance;
- successful pickup and split assign `slot_index` before the successful command is published;
- rejection-capable transfer/swap preflight does not normalize canonical state;
- rejected commands preserve canonical revision, tick and checksum;
- P2 remains responsible for pure snapshot/export and explicit durable legacy migration.

## Focused regression

`tests/runtime/test_v0_p1_canonical_clock_purity.gd` runs through a test-only pure serializer so the regression cannot be falsely GREEN because P1 `create_snapshot()` performs compatibility normalization.

Covered sequences:

1. existing-player ensure on deliberately slotless compatibility state is mutation-free;
2. pickup publishes slot identity before a pure snapshot, then duplicate pickup rejection preserves revision/tick/checksum;
3. split publishes slot identity before a pure snapshot, then invalid split rejection preserves revision/tick/checksum;
4. invalid inventory transfer cannot normalize slotless compatibility state before rejection.

This repair does not introduce a new Item Graph owner, client authority, P3 resource behavior, or a new persistence owner.
