# V0 — Reviewed Preimplementation Package

**Status:** `V0_PREIMPLEMENTATION_PACKAGE_READY_WITH_REVIEW_CORRECTIONS`  
**Lane:** preparation only; no V0 runtime branch or implementation  
**Owner:** V0 composition consumer only  

## 1. Core invariant

V0 composes canonical owners and does not create a second truth.

Forbidden:

```text
V0Terrain
V0Inventory
V0NetworkState
V0Scheduler
V0Persistence
V0Authority
V0MaterialRegistry
```

H0.3 is the **development Work-Order scheduler/control layer** and never participates in the game boot graph. V0 runtime uses existing production lifecycle/runtime entry points.

Verified production boot seam on current baseline:

```text
project.godot
  → run/main_scene = res://main.tscn
main.tscn
  → scripts/app/simulator_app.gd
```

## 2. Reviewed inventory conclusions

The preparation session correctly identified major existing seams:

- world/terrain baseline includes `scripts/world/terrain/procedural_moon_terrain.gd`;
- player/controller baseline exists under `scripts/actors/...`;
- Item/Container runtime services exist under `scripts/runtime/networked_gameplay/services/`;
- canonical item/network composition roots exist in current networked gameplay runtime;
- C22 is derived Construction presentation and must not own Construction truth;
- CH9 equipment/recovery surfaces exist on the CH branch but are not present on current `main`;
- network baseline exists on current main, but V0-S3 must wait for the bounded NX capability to become `MAIN_INTEGRATED`;
- persistence remains subsystem-owned; V0 never introduces its own save/recovery truth.

All exact component paths/statuses must be reread against fresh current main before real V0 Work Orders are materialized.

## 3. Critical correction: no V0 waterfall

The preparation session proposed an over-constrained `V0.0` entry requiring GEO/T/C22/CH/NX/MAT integration together. That is rejected.

Correct model:

```text
H0.3 accepted
      │
      ├────────→ V0.0 composition/capability freeze
      │                ↓
      │              V0-S0 boot/smoke
      │
      ├─ GEO-min + usable player + Construction/C22 → V0-S1
      │
      ├─ ITEM-min (+ equipment only when available/required) → V0-S2
      │
      └─ NX MAIN_INTEGRATED → NET-min → V0-S3
                                      ↓
                                    V0-S4
                                      ↓
                                    V0-S5
```

`V0.0` freezes owners, exact component references, scenario contracts and **per-scenario capability gates**. It does not require every later capability to already be integrated.

## 4. Scenario gates

### V0.0 / V0-S0

Requires H0.3 acceptance plus a minimal composition/runtime lifecycle set sufficient to boot through the existing production runtime.

Does **not** require in advance:

```text
NX MAIN_INTEGRATED
CH9 equipment integration
MAT0
G9-G13
NX7-NX9
```

H0.3 does not run game workers. It only enables controlled development Work Orders.

### V0-S1 — world slice

Required capabilities:

```text
usable current/accepted GEO terrain/surface seam
production player/controller/presenter sufficient for walking
real Construction truth/fixture
C22 MAIN_INTEGRATED presentation for the outpost
coordinate/collision coherence
```

`MAT0` is **not a mandatory S1 gate** unless this concrete S1 scenario requires canonical material semantics. Basic walkable terrain + outpost composition must not wait for geology/material ontology work.

CH9 equipment is not an S1 blocker.

### V0-S2 — item roundtrip

Core gate:

```text
ITEM-min over canonical Item Graph/container/pickup/drop/transfer path
```

Equipment is a capability extension, not a universal blocker. If CH equipment is integrated and required by the selected scenario, add equip/unequip. Otherwise S2 may prove carry/transfer/drop roundtrip without inventing V0 equipment truth.

WT0 is not required for the basic roundtrip. WT becomes relevant for mining, salvage and other cross-domain transactions.

### V0-S3 — network composition

Hard gate:

```text
NX SOURCE_ACCEPTED
→ explicit NX integration/merge gate
→ post-NX PC0
→ NX MAIN_INTEGRATED
→ NET-min
→ V0-S3
```

Legacy network branches/evidence do not authorize V0-S3 directly.

NX7/NX8/NX9 are not automatically required for the first two-client player/item scenario unless that scenario explicitly depends on their semantics.

### V0-S4 / S5

Recovery and final black-box acceptance remain cross-cutting composition proofs. Persistence truth remains with subsystem owners. Failure is routed first to the canonical owner; only a proven cross-owner wiring defect belongs to V0.

## 5. GEO-min reviewed boundary

GEO-min is a read/projection adapter over canonical world facts, not a new generator or world service.

May expose:

```text
body/world identity
surface position/normal
spawn pose facts
collision-ready representation reference
world-coordinate identity/path
representation/LOD observation
facts needed by Construction-owned placement validation
```

Forbidden:

```text
private terrain truth
private coordinates
private LOD policy
MAT substitute
G9 substitute
V0-owned Construction placement mutation
```

## 6. ITEM-min reviewed boundary

ITEM-min is a thin command/result facade over existing canonical Item/container routes:

```text
open/close container
read canonical contents
pickup/drop
transfer
equip/unequip only when integrated/required
identity/revision verification
reopen/recovery smoke
```

No V0-local inventory or optimistic state becomes canonical truth.

## 7. NET-min reviewed boundary

NET-min is design-only until NX is main-integrated. It may project:

```text
connection/session lifecycle observation
local vs authoritative role observation
authoritative player state
remote presentation state
authoritative item result
rejection/rollback observation
network telemetry
```

It owns none of these truths.

## 8. Exact component inventory policy

Before each real V0 Work Order, resolve every component to:

```text
exact current-main path/ref
canonical owner
SOURCE_ACCEPTED state
MAIN_INTEGRATED state
required V0 scenario
adapter needed yes/no
blocking dependency
```

Do not treat "file exists on main" as equivalent to `MAIN_INTEGRATED` for a newer accepted frontier. Conversely, do not block a scenario merely because a deeper frontier is not integrated when the scenario can legally consume an existing canonical baseline.

## 9. Scenario acceptance outline

```text
V0.0  capability/owner/component freeze
V0-S0 production boot + controlled shutdown
V0-S1 terrain + player + real Construction outpost + C22
V0-S2 canonical item/container roundtrip; equipment when applicable
V0-S3 authoritative server + two clients + shared item
V0-S4 restart/recovery without duplicate truth
V0-S5 black-box operator acceptance from clean checkout
```

Each scenario must define operator flow, automated assertions, telemetry/evidence, failure-owner routing and checkpoint identity.

## 10. Current preparation verdict

```text
V0_PREIMPLEMENTATION_PACKAGE_READY_WITH_REVIEW_CORRECTIONS
runtime_authorized = false
v0_runtime_branch_created = false
private_v0_truth_allowed = false
```

The package is sufficient to avoid another foundation discussion after H0.3. Real allowed paths, base SHA, adapter implementation and integration ordering are materialized from fresh current control state through H0.3 rather than being frozen now.
