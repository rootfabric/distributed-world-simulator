# CH9.5 — Live Equipment Runtime Composition

## Purpose

CH9.5 is the composition stage after accepted CH9.2–CH9.4. It does not add a new equipment model. It proves that the already accepted pieces operate together in one live runtime:

- CH9.2 inventory/equipment interaction model,
- CH9.3 server-authoritative `equipment.*` commands over the existing ITEM channel,
- CH9.3 canonical Item Graph replication and character-equipment projection,
- CH9.4 equipment-aware durable restore through existing M6 checkpoint/replay/recovery,
- CH8 derived `CharacterEquipmentPresenter` presentation.

The mandatory CH9.4 post-acceptance Project Control audit completed on registry generation 40 with `Overall=YELLOW` and `CH=YELLOW`. No critical Character dependency drift was present, so main registry generation 41 declares CH9.5 as the active Character frontier.

## Remaining gap closed by CH9.5

CH9.3 intentionally rejected a non-empty `persistence_root` in its dedicated server adapter. CH9.4 then proved equipment recovery at the gameplay-service/M6 level, but did not compose that recovery service into the live ENet dedicated runtime.

Likewise, CH9.3 proved that a replicated Item Graph can be projected and presented, but the live client runtime still required an explicit adapter that listens to `item_graph_updated` and applies the projection to bound character presenters.

CH9.5 closes exactly those two composition gaps.

## Runtime architecture

```text
Inventory / equipment command
        |
        v
existing ITEM reliable channel
        |
        v
Ch9PersistentEquipmentDedicatedServerRuntime
        |
        +-- accepted M3/NX transport + fixed tick
        +-- Ch9EquipmentRecoveryService
        +-- existing M6 repository/coordinator/authority adapter/outbox
        |
        v
canonical Item Graph
        |
        +--> COMMAND_RESULT authoritative delta to origin
        +--> ITEM_GRAPH_DELTA / full resync to other clients
        |
        v
M3 graphical client Item Graph replica
        |
        v
NetworkCharacterEquipmentPresentationCoordinator
        |
        v
NetworkCharacterEquipmentProjection
        |
        v
CharacterEquipmentDomain.Snapshot
        |
        v
bound CharacterEquipmentPresenter
```

## Persistent dedicated runtime

`ch9_5_persistent_dedicated_server_runtime.gd` extends the accepted CH9.3 dedicated runtime.

It deliberately does not modify M3 or M6 foundation files. Setup proceeds synchronously:

1. Bootstrap the accepted CH9.3 ENet transport with persistence temporarily disabled.
2. Replace the temporary gameplay service with `Ch9EquipmentRecoveryService` before SceneTree processing can handle live traffic.
3. Enable the requested existing M6 persistence root.
4. Invoke the inherited M6 recovery setup, now bound to the equipment-aware service.
5. If a checkpoint was recovered, rebuild only the inherited fixed-tick scheduler clock from the recovered server tick.
6. Continue using all inherited command persistence, replay outbox, replication and transport behavior.

No new checkpoint format, repository, recovery coordinator or replay ledger is introduced.

## Live presentation coordinator

`network_character_equipment_presentation_coordinator.gd` is presentation-only.

It:

- binds to an existing client runtime exposing `item_graph_updated` and `get_item_graph_snapshot`,
- keeps one projection instance per logical character,
- projects canonical Item Graph equipment for that character,
- applies the resulting `CharacterEquipmentDomain.Snapshot` to the bound presenter,
- tolerates binding a presenter before the corresponding player equipment container exists,
- relies on the accepted presenter fingerprint/idempotency behavior so repeated full snapshots do not create duplicate visuals,
- can unbind or clear presenters without mutating canonical state.

It explicitly owns none of Item truth, transport or persistence.

## Invariants

CH9.5 must preserve:

- one physical item = one canonical Item UUID,
- canonical equipment relation remains `CONTAINER`,
- server remains authoritative for equipment mutation,
- existing ITEM channel carries equipment commands/deltas,
- movement/gameplay snapshots contain no equipment Item IDs,
- persistence stores canonical gameplay/Item Graph state, never mesh/rig/presentation state,
- reconnect/late join reconstruct presentation from recovered canonical state,
- repeated snapshot delivery does not create duplicate presentation nodes,
- Character code does not become owner of Item identity, M6 durability, NX replication policy or authority foundations.

## Focused acceptance

`RUN_CH9_5_LIVE_EQUIPMENT_RUNTIME_TESTS.ps1` runs accepted parent regressions and two new gates.

### Presentation coordinator gate

Proves:

- player A and B can be bound independently,
- A equipment updates only A presentation,
- repeated identical canonical snapshots are idempotent,
- layered equipment composes,
- unequip removes presentation,
- coordinator reports presentation-only ownership.

### Persistent ENet recovery composition gate

Proves in one SceneTree using real ENet:

1. persistent dedicated server generation 1 starts,
2. clients A and B join and converge,
3. A equips a canonical wearable,
4. B receives the replicated Item Graph and presentation update,
5. the equipment command creates an M6 durable checkpoint,
6. server generation 1 stops,
7. a fresh server generation 2 starts from the same persistence root,
8. A reconnects and new client C late-joins,
9. both receive the same recovered Item UUID in the same equipment slot,
10. C immediately derives A presentation from recovered state,
11. a repeated full snapshot does not duplicate presentation,
12. A unequips after recovery,
13. C presentation follows the replicated delta,
14. the same Item UUID returns to inventory and is checkpointed again,
15. gameplay/movement snapshots remain equipment-ID-free.

## Deferred

CH9.5 does not introduce new equipment slots, new garment fitting strategies, new authority models, prediction semantics for equipment, cross-server migration, or new persistence infrastructure. Any later Character stage requires another Project Control audit after CH9.5 acceptance.
