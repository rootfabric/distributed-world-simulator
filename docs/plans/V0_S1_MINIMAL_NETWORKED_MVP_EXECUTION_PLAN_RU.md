# V0-S1 — Networked Planetary Outpost / Integration Execution Plan

**Status:** ACTIVE INTEGRATION CANDIDATE  
**Date:** 2026-08-14  
**Repository:** `rootfabric/distributed-world-simulator`  
**Working line:** `feature/v0-s1-networked-planetary-outpost-mvp`  
**Activation base:** `6c4931f9c44db374b4eb3ab08b51fe1268dce569`

Companion roadmap:

```text
docs/plans/V0_INTEGRATION_CHECKPOINT_ROADMAP_RU.md
```

## 1. Цель

V0-S1 больше не рассматривается как одноразовый минимальный demo.
Он является первым executable integration slice будущего глобального V0
checkpoint.

Текущий целевой сценарий:

```text
dedicated server
  -> procedural Earth
  -> two graphical clients
  -> two playable characters
  -> mutual movement visibility
  -> canonical inventory / hotbar
  -> network pickup / move / drop / container interaction
  -> canonical Construction outpost
  -> C22/C24 representation + collision on both clients
  -> reconnect to same live world
  -> 30 minute soak
```

V0 является composition consumer. Он не получает private authority или private
persistence для Item, Character, Construction или Terrain.

## 2. Текущий executable baseline

Операторски подтверждено:

```text
server boots
two clients join
players spawn рядом
A sees B
B sees A
movement is visible in both directions
```

Current known deferred problem:

```text
V0-NET-001 — visible network/presentation jitter
```

До завершения core convergence V0-NET-001 не смешивается с Inventory или
Construction work. Protocol/authority/reconciliation fixes остаются NX-owned.

## 3. Integration boundary

Canonical runtime owners переиспользуются:

```text
procedural Earth runtime
M3/NX network runtime
M4 canonical Item Graph
M5 network inventory bridge/shell
Construction multiplayer gateway/replica
C22/C24 construction representation
existing persistence/reconnect contracts
```

Запрещено создавать:

```text
V0 Item Graph
V0 movement authority
V0 Construction truth
V0 terrain truth
V0 ownership epoch policy
V0 persistence format
```

## 4. Последовательность implementation checkpoints

### V0-B0 — Bootable Two-Client Baseline

Сохранить работающий server + A + B runtime как regression floor.

Required:

```text
server boot
A/B join same world
mutual visibility
movement
spectator presentation-only behavior
```

### V0-I1 — Inventory Convergence

Заменить временное text-only MVP inventory уже существующим M5 network
inventory stack:

```text
M3GraphicalClientRuntime
  -> item_graph_updated
  -> M5InventoryUiBridge
  -> M5NetworkedInventoryShell
  -> shared ContainerPanel / HotbarPanel / interaction profile
```

V0-I1 implementation scope:

```text
reuse M5NetworkedInventoryShell
reuse M5InventoryUiBridge
keep canonical server M4 Item Graph
Tab opens/closes graphical inventory
hotbar remains visible in gameplay
hotbar slots 1..8 use network inventory action
G drops the selected canonical hotbar item through Item command path
movement input stops while inventory is open
report exposes V0-I1 convergence state
```

Non-goal of V0-I1:

```text
network smoothing
new inventory authority
full visual polish parity with InventoryScreen toolbar/search/sort
```

Presentation-only parity can follow as `V0-I1P` after functional two-client PASS.

### V0-I2 — World Interaction Convergence

Reuse existing raycast / `world_interactable` / `E` / external container flow.

Acceptance:

```text
pickup
inventory
hotbar
open container
transfer
world drop
second-client canonical convergence
```

### V0-C1 — Outpost Build Flow

Reuse `MvpEarthOutpostAuthority` and existing Construction multiplayer contracts.

Minimum outpost:

```text
foundation
4 walls
roof
```

### V0-C2 — C22/C24 Presentation

For each canonical construct revision:

```text
Construction bundle
-> runtime projection request
-> C22/C24 compile/present
-> same visual/collision result on A and B
```

### V0-C3 — Inventory/Construction Resource Binding

Build requirements consume/transfer real canonical gameplay Item state through
existing domain boundaries. No second material inventory.

### V0-R1 — Reconnect

B disconnects and rejoins the same live server world while A remains online.
B must converge to current Item and Construction state.

### V0-A1 — End-to-End Acceptance

Target runner:

```text
RUN_V0_S1_NETWORKED_PLANETARY_OUTPOST_TESTS.ps1/.sh
tests/runtime/test_v0_s1_networked_planetary_outpost.gd
```

Scenario:

```text
server boot
planet ready
A join
B join
movement
inventory/hotbar
world item/container loop
construction
cross-client collision/representation
reconnect
30 minute soak
```

## 5. V0-I1 exact implementation decision

V0-I1 does **not** introduce a new adapter to imitate the old local
`ItemGameplayController`.

The repository already contains a network-native inventory projection path:

```text
M5NetworkedInventoryShell
M5InventoryUiBridge
M4ItemGraphUiProjection
M4ItemCommandAdapter
M4InventoryTransientState
```

Therefore the shortest safe implementation is to compose this accepted M5 path
inside Earth MVP and remove the temporary text-only view.

The shell already reuses shared inventory presentation components, including:

```text
ContainerPanel
HotbarPanel
7-days-like interaction profile
cursor carry
transfer preview
quick transfer
world/mount/external projections
```

The full local `InventoryScreen` remains useful presentation evidence, but binding
it directly to network state would require a new controller-compatibility adapter.
That work is presentation polish, not required to prove V0-I1 canonical network
inventory convergence.

## 6. Validation requirements for V0-I1

Required before graphical acceptance:

```text
Godot parser PASS on exact modified Earth MVP
fake runtime attach PASS
inventory shell setup PASS
Tab visibility state PASS
movement suppression while UI open PASS
hotbar 1..8 network action PASS
invalid slot rejection PASS
selected hotbar drop uses canonical Item command PASS
git apply --check PASS for delivery patch
git diff --check PASS
```

Then human graphical check with real server + two clients:

```text
hotbar visible on both clients
Tab opens graphical inventory
items correspond to each client's canonical projection
drag/cursor interaction works
hotbar selection replicates through server state
drop updates world projection
closing Tab restores gameplay mouse/input
```

## 7. Construction after I1

Network smoothing remains deferred. Immediately after V0-I1 graphical PASS, next
runtime mutation is V0-I2 or V0-C1, not a network rewrite.

Construction route already present:

```text
MvpEarthOutpostAuthority
-> M3ConstructionReplicationBridge
-> M3GraphicalClientRuntime ConstructionReplica
-> EarthConstructionPresentation
```

Remaining work is user-facing placement/build glue and authoritative C22/C24
projection, not a new Construction protocol.

## 8. Definition of Done V0-S1

V0-S1 is accepted only when all are true:

```text
procedural Earth ready
2 clients in same world
bidirectional movement visible
canonical inventory/hotbar usable
world item/container loop usable
canonical outpost commit
same outpost on second client
matching construction collision
reconnect same live world
no duplicate canonical truth
focused/integrated runner PASS
full relevant regression PASS
30 minute soak PASS
```

Until then V0 remains an integration candidate, but every completed convergence
step stays enabled and becomes part of the regression floor for the next step.
