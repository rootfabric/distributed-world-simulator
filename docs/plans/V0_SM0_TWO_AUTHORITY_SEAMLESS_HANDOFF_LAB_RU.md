# V0-SM0 — Two-Authority Seamless Handoff Lab

**Status:** PLANNED / IMPLEMENTATION NOT STARTED  
**Branch:** `feature/sm0-two-authority-seamless-handoff-lab`  
**Exact product base:** `d66378b98b69756fab6c2a93b80b74db9ccd1980`  
**Base branch:** `feature/v0-playable-product-frontier`  
**Runtime-tested immutable ancestor:** `checkpoint/v0-playable-merge-ready-2026-08-15` -> `7f4177b32ce76191aecea60f2f8963c1b0ffd02e`  
**Checkpoint goal:** `V0-SM0-TWO-AUTHORITY-SEAMLESS-HANDOFF-LAB`

> SM0 is an isolated seamless-world research/product-integration lab. It must not replace or destabilize the normal single-server V0 path. All SM0 behavior is opt-in through a dedicated launcher/mode.

## 1. Observable result

One command starts:

```text
Dedicated Authority Server A
Dedicated Authority Server B
Graphical Client A
```

Both servers load the same Earth/world identity but own different adjacent Earth-fixed surface zones.

The client starts in Zone A, walks across the shared boundary into Zone B, and later walks back into Zone A.

The graphical client process and player identity do not restart or respawn as a new logical player during the transition.

Minimum visible scenario:

```text
server A owns zone A
server B owns zone B

client a -> server A ACTIVE
walk east
warm route to server B
cross boundary
player authority A -> B
client a -> server B ACTIVE
walk west
player authority B -> A
client a -> server A ACTIVE
```

The purpose is to prove the minimum technical basis of seamless multi-authority gameplay before introducing World Directory/NATS/JetStream/ghost replication at production scale.

## 2. Explicit non-goals

SM0 does NOT claim:

- global N3/N4/N5/N6 acceptance;
- production World Directory;
- NATS or JetStream requirement;
- dynamic zone split/merge;
- automatic load balancing;
- arbitrary many servers;
- cross-zone Construction;
- cross-zone world-item transaction;
- distributed Matter mutation;
- crash-tolerant consensus;
- invisible handoff under real WAN conditions;
- orbital/reference-frame handoff.

It is a two-server localhost lab that establishes the correct contracts and runtime seams.

## 3. Foundation rules

SM0 MUST preserve current V0 foundations.

```text
current V0 movement/prediction path wins
current Player identity wins
current Item Graph owner wins
current Construction owner wins
current ENet realtime semantics win
current Earth/world coordinates win
```

Historical branches are semantic donors only.

Primary semantic donor for authority transfer:

```text
feature/mw8-regional-authority-handoff
commit 2da7c91ad31fab887a4bcb9669e993958e339c48
```

Reuse the proven rules, not the Matter implementation:

```text
single active writer
freeze -> prepare -> commit
shadow prepare on target
abort/compensation before commit
authority epoch fencing
stable logical identity
replay-safe transfer ID
```

S0 spatial substrate already defines the required separation:

```text
spatial zone identity != authority owner
render origin != spatial identity
```

SM0 must not create a competing ChunkId/world-coordinate system.

## 4. Initial topology

Default localhost topology:

```text
Server A
  authority_id: authority/sm0/a
  zone_id:      zone/earth/sm0/west
  gameplay:     127.0.0.1:24580
  control:      127.0.0.1:24680
  directory:    LEADER (lab-only)

Server B
  authority_id: authority/sm0/b
  zone_id:      zone/earth/sm0/east
  gameplay:     127.0.0.1:24581
  control:      127.0.0.1:24681
  directory:    FOLLOWER/CLIENT

Graphical Client A
  logical_player_id: a
  active route:       Server A at spawn
  warm route:         Server B near boundary
```

Server A hosts the temporary lab directory/coordinator so the experiment still uses only two server processes. This is deliberately replaceable by future N3 World Directory.

The gameplay client must not know that Server A is directory leader. It receives transport-neutral route/ticket data from the active authority.

## 5. Zone geometry

SM0 uses two adjacent zones in the local Earth surface frame around the existing canonical MVP spawn.

Define one stable Earth-fixed lab frame:

```text
anchor = existing canonical Earth MVP spawn
axes   = local East / North / Up derived from Earth frame
```

Authority boundary:

```text
Zone A (west): east_offset_m < 0
Zone B (east): east_offset_m >= 0
```

Bounded lab extent for diagnostics:

```text
East:  -100 m .. +100 m
North: -100 m .. +100 m
```

The boundary at `east_offset_m = 0` is canonical. Handoff prewarming uses a presentation/network band but does not overlap command authority.

Recommended warm band:

```text
within 10 m of boundary -> establish/verify target route
within  2 m            -> target must be prepared
cross canonical 0 m    -> commit authority handoff
```

A small hysteresis is allowed for route prewarming, never for canonical ownership. There must never be two authoritative writers for the player aggregate.

## 6. Identities and epochs

Stable across handoff:

```text
logical_player_id
player_entity_id
world_id
Earth canonical position
inventory identity references (when included)
```

Changes across successful handoff:

```text
active_authority_id: A -> B
authority_epoch:     N -> N+1
transport_session_id
active route
```

Forbidden:

```text
new player entity on every zone crossing
new logical player ID
teleport through a second spawn path
copy-and-delete without epoch fencing
simultaneous movement writes on A and B
```

## 7. SM0 contracts

Add transport-neutral DTO/contracts under a bounded SM0 namespace.

### 7.1 ZoneRoute

```text
schema
zone_id
world_id
frame_id
bounds/zone_rule
authority_id
gameplay_endpoint
control_endpoint
route_revision
checksum
```

### 7.2 PlayerHandoffTicket

```text
schema
transfer_id
logical_player_id
player_entity_id
source_zone_id
target_zone_id
source_authority_id
target_authority_id
source_authority_epoch
target_authority_epoch
directory_revision
target_gameplay_endpoint
expires_at_tick
package_checksum
checksum
```

### 7.3 PlayerHandoffPackage

Minimum SM0 state:

```text
transfer_id
logical_player_id
player_entity_id
source authority/epoch
target authority/epoch
canonical transform/position
velocity
movement mode / ground state
last_processed_input_sequence
player state revision
player-state checksum
bounded player-owned inventory fingerprint/snapshot if available without introducing a second Item Graph owner
package checksum
```

For the first executable slice, movement/player state is mandatory. Inventory transfer may be introduced in SM0.6 only after movement handoff is correct. Item/Construction mutation during the sub-second handoff window may be temporarily fenced rather than duplicated.

### 7.4 HandoffProof

Target prepare response:

```text
transfer_id
target_authority_id
target_authority_epoch
prepared_state_checksum
accepted_player_entity_id
prepared_at_tick
checksum
```

## 8. Handoff state machine

Canonical state machine:

```text
ACTIVE_SOURCE
    |
    | boundary warm-band entered
    v
TARGET_ROUTE_WARM
    |
    | source requests transfer / directory CAS
    v
SOURCE_FROZEN
    |
    | package exported
    v
TARGET_PREPARED_SHADOW
    |
    | proof validated
    v
DIRECTORY_COMMITTED
    |
    | source loses writer permission
    | target becomes active writer
    v
TARGET_ACTIVE
    |
    | client switches active route
    v
SOURCE_RETIRING_READ_ONLY
```

Failure before `DIRECTORY_COMMITTED`:

```text
target discards shadow state
source unfreezes
client remains on source
```

Failure after directory commit:

```text
source MUST NOT resume writing
client retries target activation using the same ticket
```

A transfer ID is replay-safe. Duplicate PREPARE/COMMIT/ACTIVATE with identical fingerprints returns the original result. Conflicting reuse fails closed.

## 9. Server-to-server synchronization

SM0 server synchronization has two responsibilities only:

1. route/directory health;
2. player handoff transfer.

Do not replicate the entire world between both servers.

At startup both servers verify:

```text
world_id
build_id
protocol_hash
zone manifest hash
server/authority identity
zone ownership
peer endpoint
```

Health heartbeat may be simple and localhost-oriented. The semantic layer must not depend on ENet channel numbers or socket IDs.

Expected control messages:

```text
AUTHORITY_HELLO
AUTHORITY_HEALTH
ZONE_DIRECTORY_SNAPSHOT
PLAYER_HANDOFF_PREPARE
PLAYER_HANDOFF_PREPARED
PLAYER_HANDOFF_COMMIT
PLAYER_HANDOFF_COMMITTED
PLAYER_HANDOFF_ABORT
PLAYER_HANDOFF_STATUS
```

The first adapter may use a second ENet boundary/port. Future B1/B2/N3 may replace this adapter without changing the DTO/state machine.

## 10. Client routing model

Do not create two full active player sessions.

The client needs:

```text
one active gameplay route
zero-or-one warm standby transport route
one local presentation/player body
one prediction history owner
```

Near the boundary the client may connect and complete compatibility handshake with the target server, but target MUST NOT spawn an authoritative player from a normal JOIN.

Required target-side standby mode:

```text
transport connected
compatibility verified
handoff ticket can be accepted
no player entity created
no input authority
```

On committed handoff:

```text
source freezes/acks last processed input sequence
target imports exact player state
client activates target with ticket
prediction reconciler rebases to committed target state
remaining buffered input is replayed once
target becomes the only input recipient
source route becomes read-only/closed
```

The same graphical process/window/camera stays alive.

## 11. Implementation stages

### SM0.0 — Branch/base lock — DONE by plan creation

- branch from exact current V0 product frontier;
- no recovery branch ancestry;
- record exact base SHA;
- preserve normal V0 launcher behavior.

### SM0.1 — Pure contracts + two-zone directory

Implement and test:

```text
Sm0ZoneManifest
Sm0ZoneRoute
Sm0AuthorityDirectory
Sm0PlayerHandoffTicket
Sm0PlayerHandoffPackage
Sm0HandoffProof
```

Acceptance:

- exact two-zone topology validates;
- no gap/ambiguous canonical boundary;
- unknown authority/zone rejected;
- stale directory revision rejected;
- target epoch must be > source epoch;
- checksum mutation rejected.

No graphical runtime changes yet.

### SM0.2 — Two server processes + control synchronization

Add a dedicated launcher:

```text
RUN_V0_SM0_SEAMLESS.ps1
```

It starts Server A and Server B with distinct gameplay/control ports and waits for:

```text
SM0_SERVER_READY A
SM0_SERVER_READY B
SM0_PEER_SYNCED A<->B
SM0_DIRECTORY_READY
```

Normal `RUN_V0_MVP.ps1` remains untouched semantically.

Acceptance:

- both servers stay alive;
- both agree on zone manifest/directory checksum;
- heartbeat/peer disconnect is visible and fail-closed;
- no graphical client required yet.

### SM0.3 — Player authority export/import gate

Add a bounded adapter around current `NetworkedGameplayService` / M3 server runtime.

Required operations:

```text
freeze_player_for_handoff()
export_player_handoff_package()
prepare_imported_player_shadow()
commit_imported_player_authority()
abort_imported_player_shadow()
retire_source_player_authority()
```

Do not fork movement code.

Acceptance in headless process test:

- player starts active only on A;
- PREPARE creates no active writer on B;
- source rejects movement while frozen;
- commit increments authority epoch;
- after commit A rejects player mutation;
- B accepts movement;
- identity/transform/velocity preserved;
- abort before commit restores A;
- duplicate commit is idempotent;
- stale source epoch is rejected.

### SM0.4 — Client dual-route / standby connection

Add a `Sm0SeamlessClientRouter` around the existing M3/NX4 client runtime.

Required changes to current M3 client should be minimal and opt-in:

- configurable `ACTIVE` vs `STANDBY` join mode;
- standby performs transport + compatibility handshake without normal JOIN;
- activation consumes a valid handoff ticket;
- prediction history is rebased, not recreated from a new spawn.

Acceptance:

- one graphical client can keep A active while B route is warm;
- target standby has no player entity;
- invalid/stale ticket rejected;
- closing standby route does not affect active gameplay.

### SM0.5 — Automatic boundary detection and one-way A -> B handoff

Server/source uses canonical Earth-fixed position to detect target zone.

Sequence:

```text
spawn 20 m inside Zone A
walk toward boundary
warm B within 10 m
prepare within 2 m
cross 0 m
commit A -> B
continue walking in Zone B
```

Acceptance:

- same client PID/window;
- same logical/player entity IDs;
- authority epoch +1;
- no duplicate player on either server;
- no authoritative position rollback across boundary;
- no manual reconnect command;
- no reconnect/spawn screen;
- both servers remain healthy.

Initial localhost transition budget:

```text
handoff control duration < 500 ms
canonical position discontinuity < 0.50 m
no input loss beyond bounded handoff freeze
```

The budget is diagnostic for SM0, not a production SLA.

### SM0.6 — Reverse B -> A + player inventory continuity

Add reverse route and repeatability.

Then include the player-owned inventory/hotbar state using the existing Item Graph truth. Do not invent a second inventory store.

Acceptance:

```text
A -> B -> A
same player identity
same bounded inventory fingerprint
no duplicate item IDs
no lost item quantity
```

Construction remains zone-owned; cross-zone constructs are not required.

### SM0.7 — Fault matrix + repeated crossings

Mandatory failures:

```text
target unavailable before prepare
peer link lost during prepare
target rejects package checksum
client loses standby route
source receives stale movement after commit
duplicate PREPARE
duplicate COMMIT
duplicate ACTIVATE
expired handoff ticket
attempt to activate wrong player identity
```

Required behavior:

- before commit -> abort and source resumes;
- after commit -> source never resumes writer authority;
- retries converge on target;
- no split-brain;
- no duplicate player entity.

Repeat:

```text
20 automated A <-> B crossings
```

No persistent error code, no increasing pending operations, no duplicate identity, no process restart.

## 12. Proposed source layout

Prefer additive SM0 files:

```text
scripts/runtime/seamless/sm0/
  sm0_zone_manifest.gd
  sm0_zone_route.gd
  sm0_authority_directory.gd
  sm0_player_handoff_contract.gd
  sm0_handoff_coordinator.gd
  sm0_server_control_link.gd
  sm0_player_authority_adapter.gd
  sm0_seamless_client_router.gd

tests/runtime/seamless/sm0/
  test_sm0_zone_directory.gd
  test_sm0_handoff_contracts.gd
  test_sm0_player_authority_handoff.gd
  test_sm0_two_server_process.gd
  test_sm0_graphical_boundary_crossing.gd

RUN_V0_SM0_SEAMLESS.ps1
config/seamless/sm0-two-authority-handoff-lab.v1.json
```

Expected bounded modifications to existing files:

```text
scripts/runtime/launch_options.gd
scripts/app/simulator_app.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd
scripts/runtime/networked_gameplay/networked_gameplay_service.gd
```

Any broader replacement of current network/movement/Item Graph foundations requires stopping and re-scoping the lab.

## 13. Launch contract

Target developer command:

```powershell
.\RUN_V0_SM0_SEAMLESS.ps1 -Restart
```

Expected output:

```text
[SM0] Server A READY  gameplay 24580 control 24680 zone west
[SM0] Server B READY  gameplay 24581 control 24681 zone east
[SM0] Authority peers synchronized
[SM0] Directory revision 1 / checksum ...
[SM0] Client a started -> ACTIVE A / WARM B available
```

Session state must record both server PIDs and client PID so `-Stop` is deterministic.

## 14. Telemetry required before graphical acceptance

Per handoff:

```text
transfer_id
player_entity_id
source_zone
target_zone
source_epoch
target_epoch
state
prepare_ms
commit_ms
client_switch_ms
total_handoff_ms
last_source_input_sequence
first_target_input_sequence
position_gap_m
source_active_writer_count
target_active_writer_count
```

Invariant telemetry:

```text
source_active_writer_count + target_active_writer_count <= 1
```

During ACTIVE steady state exactly one must be `1`.

## 15. Final SM0 checkpoint acceptance

SM0 is complete only when all are true:

```text
[ ] branch still descends from the recorded V0 product base
[ ] normal single-server V0 launcher remains green
[ ] two independent dedicated server processes launch
[ ] two static Earth-fixed zones have distinct owners
[ ] servers validate each other's build/protocol/zone manifest
[ ] one graphical client launches once
[ ] client crosses A -> B without process restart
[ ] client crosses B -> A without process restart
[ ] logical_player_id unchanged
[ ] player_entity_id unchanged
[ ] authority_epoch increments on each handoff
[ ] never two active player writers
[ ] target standby never creates a second player
[ ] canonical transform/velocity continuity within lab budget
[ ] NX4 movement resumes on target
[ ] bounded player inventory fingerprint survives round trip
[ ] duplicate/stale transfer messages are replay-safe/fail-closed
[ ] pre-commit failure safely aborts to source
[ ] post-commit retry cannot reactivate source
[ ] 20 automated crossings PASS
[ ] clean shutdown of client + both servers
[ ] no unexpected ERROR / persistent last_error_code
[ ] git tree remains clean after launcher/preflight
```

## 16. What comes after SM0

Do not turn SM0 directly into production N5.

Recommended continuation:

```text
SM0 two-authority player handoff lab
  -> SM1 border ghosts / overlap interest
  -> SM2 stateful world-items/containers across zone boundary
  -> SM3 handoff recovery after source/target process failure
  -> B1/B2 server-service transport integration
  -> N3 durable World Directory / leases
  -> N4 generic aggregate handoff
  -> N5 production seamless player handoff
  -> N6 ghosts + interest budgets
```

Later, the same authority/route contracts can be applied to:

```text
surface zone A -> surface zone B
surface -> orbital space
planet -> deep-space region
station interior -> exterior space
```

The SM0 success criterion is not scale. It is proving that changing the server process does not change the identity of the player or the continuity of the canonical world.