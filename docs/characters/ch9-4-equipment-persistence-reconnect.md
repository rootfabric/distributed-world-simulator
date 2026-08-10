# CH9.4 — Equipment Persistence / Late Reconnect

## Goal

Carry the CH9.3 server-authoritative equipment state through the already accepted M6 durability and recovery machinery. CH9.4 does not create a character save file, a second replay ledger, or a new recovery coordinator.

## Canonical rule

Equipment remains ordinary Item Graph truth:

```text
Item UUID
  relation.kind = CONTAINER
  container_id = equipment/<logical_player_id>
  slot_index = head/back/upper/lower/feet
```

The durable source remains `NetworkedGameplayService.export_durable_state()` -> canonical multiplayer Item Graph durable state -> M6 authoritative checkpoint.

## Gap closed by CH9.4

The generic recovery path reconstructs `CanonicalMultiplayerItemGraph`. That preserves bytes but loses the CH9.3 equipment-aware command implementation after restart. CH9.4 adds `Ch9EquipmentRecoveryService`, which:

1. runs the accepted base transactional durable restore;
2. validates equipment container/slot semantics;
3. restores an equipment-aware `Ch9EquipmentItemGraphService` from the exact same durable Item Graph snapshot;
4. checks that the canonical Item Graph checksum is byte-equivalent to the durable snapshot;
5. leaves M6 replay/outbox restoration to the existing M6 components.

No transport, movement, prediction, rig or presentation state enters persistence.

## Required recovery invariants

- one physical item -> one canonical Item UUID;
- equipment container ID and owner entity survive restart;
- equipment slot map and canonical `slots` reference order agree;
- item `location.container_id` and `location.slot_index` agree with the equipment slot map;
- wearable definition matches its semantic slot;
- quantity remains exactly one;
- corrupted but checksum-valid equipment state is rejected before restore;
- recovered service still accepts `equipment.equip` and `equipment.unequip`;
- old committed equipment operation IDs remain replay-idempotent;
- transient transport sessions do not survive restart;
- reconnect advances ownership epoch without changing equipment;
- late join observes recovered equipment through the unchanged Item Graph snapshot path;
- successive checkpoint/recovery cycles do not duplicate Item UUIDs.

## Reused foundations

CH9.4 directly composes:

- `authoritative_recovery_repository.gd`;
- `authoritative_recovery_coordinator.gd`;
- `m6_dedicated_gameplay_authority_adapter.gd`;
- `m6_durable_replay_outbox.gd`;
- canonical multiplayer Item Graph durable/replay state;
- CH9.3 equipment authority and projection;
- CH8 character equipment presentation (regression only).

## Focused acceptance

Run:

```powershell
.\RUN_CH9_4_EQUIPMENT_PERSISTENCE_TESTS.ps1 -GodotPath $Godot
```

The gate includes the accepted CH9.3 authority/replica/presentation/real-ENet regressions plus:

- durable equipment service round-trip;
- semantic corruption rejection with recomputed checksums;
- M6 atomic checkpoint persistence;
- server-service restart and M6 recovery;
- replay/outbox recovery;
- reconnect with a new ownership epoch;
- late-join projection of recovered equipment;
- post-recovery equipment mutation;
- second checkpoint and second recovery cycle.

Windows acceptance is required before CH9.4 is marked accepted.
