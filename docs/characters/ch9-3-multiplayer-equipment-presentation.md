# CH9.3 — Multiplayer Equipment Presentation

## Goal

Replicate character equipment as canonical Item Graph state and drive character presentation on every client without adding equipment fields to movement snapshots.

## Canonical model

Equipment remains a normal canonical `CONTAINER` relation. Each logical player owns one fixed semantic slot container:

- `equipment/<logical_player_id>`
- slot 0: head
- slot 1: back
- slot 2: upper
- slot 3: lower
- slot 4: feet

The canonical container is marked `container_kind=CHARACTER_EQUIPMENT`, but equipped items still use the existing location kind:

```text
item.location.kind = CONTAINER
item.location.container_id = equipment/<player>
item.location.slot_index = N
```

No `EQUIPPED` Item relation is introduced.

## Authority

`Ch9EquipmentItemGraphService` extends the accepted M4 canonical multiplayer Item Graph service. It adds only:

- deterministic player equipment containers;
- sandbox wearable seed items;
- `equipment.equip`;
- `equipment.unequip`.

A player may mutate only items in that player's own inventory/equipment container. Equipment quantity is exactly one. Slot and wearable definition must match. One occupied slot may be replaced atomically by one incoming item in one server operation.

The equipment reference list is always rebuilt in semantic slot order, so the same final equipment state has the same canonical checksum regardless of equip order.

## Transport

CH9.3 deliberately reuses the accepted M3/NX item transport:

- command: reliable ordered `ITEM_COMMAND` on the ITEM channel;
- origin: authoritative `item_graph_delta` in `COMMAND_RESULT`;
- other clients: reliable ordered `ITEM_GRAPH_DELTA`;
- fallback/resync: `ITEM_GRAPH_SNAPSHOT`;
- late join: full `item_graph_snapshot` in `JOIN_ACK`.

No equipment Item IDs are added to `GAMEPLAY_SNAPSHOT`, `COMPACT_GAMEPLAY_SNAPSHOT`, movement input, prediction or reconciliation state.

`Ch9DedicatedServerRuntime` is a CH9.3 composition runtime over the accepted dedicated server. It swaps only the canonical item-graph service after transport setup; M3/NX transport, fixed tick, movement and replication remain inherited. Persistence is intentionally rejected by this composition runtime until CH9.4.

## Client projection

`NetworkCharacterEquipmentProjection` is presentation neutral. Given a replicated canonical Item Graph snapshot and logical player id, it builds the existing `CharacterEquipmentDomain.Snapshot` using the same semantic layout/profile IDs as CH7–CH9.2.

`Ch9EquipmentItemGraphReplicaAdapter` additionally preserves all player equipment containers when converting the canonical network graph into the production ItemRegistry/ContainerRegistry graph. This allows CH9.0 `ItemGraphEquipmentSource` to bind both local and remote character equipment from one replicated graph.

`NetworkCharacterEquipmentGameplayController` extends the CH9.2 controller. Offline/authority behavior stays unchanged. In replica mode, equip/unequip submit `equipment.*` commands to server authority, install the returned authoritative graph snapshot, then refresh character presentation.

## Presentation

The server has no rig, mesh, Skeleton3D, Quaternius, camera or UI dependency.

On a graphical client the replicated snapshot resolves through the existing presentation IDs:

- `wearable.helmet.mk1`
- `wearable.backpack.mk1`
- `wearable.layer.upper.peasant`
- `wearable.layer.lower.peasant`
- `wearable.layer.feet.peasant`

The accepted CH8 `CharacterEquipmentPresenter` remains the presentation owner.

## Focused acceptance

`RUN_CH9_3_MULTIPLAYER_EQUIPMENT_TESTS.ps1` gates:

1. editor import/parse;
2. CH9.0 source regression;
3. CH9.1 authority regression;
4. CH9.2 inventory/character regression;
5. direct server-authoritative equipment contract;
6. canonical delta convergence and permission isolation;
7. canonical network graph -> production Item Graph replica -> CH9.0 source projection;
8. replicated equipment -> accepted CH8 Quaternius presenter;
9. real ENet server + clients A/B equipment convergence;
10. late client C receives already-equipped A state from JOIN snapshot;
11. unequip convergence;
12. no equipment Item IDs in gameplay/movement snapshots.

Any `ERROR:`, `SCRIPT ERROR`, parse/compile error or FAIL marker rejects the runner even if Godot exits with code 0.

## Deferred

- CH9.4 equipment persistence/recovery/reconnect durability;
- general multi-item atomic replacement (for EVA-style multi-conflict outfits);
- replacing the existing generic remote capsule representation in the main gameplay scene with a production art character is a separate presentation integration concern; CH9.3 proves that replicated equipment state already drives the accepted character presenter when a compatible rig is bound.
