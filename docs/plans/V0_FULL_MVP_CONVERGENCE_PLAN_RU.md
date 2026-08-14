# V0 Full MVP Convergence Plan

**Date:** 2026-08-14  
**Status:** ACTIVE PRODUCT CONVERGENCE  
**Current product line:** `feature/v0-s1-networked-planetary-outpost-mvp`

## 1. Current proven composition

The current V0 runtime already has a useful integrated base:

```text
procedural Earth surface
+ dedicated server
+ 2 graphical clients
+ NX4 local prediction
+ NX5 remote snapshot interpolation code path
+ shared Earth floating/render frame
+ stable local/remote player projection
+ canonical M4 Item Graph inventory/hotbar
+ canonical 3-stage Construction outpost
+ C22/C24 construction mesh projection
+ Earth-fixed construction presentation anchor
```

The next work must increase the playable loop without creating duplicate Item,
Construction, Terrain, Character or Network truth.

## 2. Immediate non-blocking presentation step — V0-P1

### V0-P1 Earth Surface Presentation Polish

Presentation-only local terrain material:

```text
existing procedural vertex color
+ deterministic macro variation (~35 m)
+ deterministic detail variation (~5 m)
+ rare weak dry tint
+ high roughness
```

Must NOT change:

```text
terrain height
terrain collision
biome/rule pipeline
world coordinates
network state
save state
```

This is deliberately disposable presentation. The global/orbital LOD remains on
the current cheap StandardMaterial path.

## 3. Next gameplay convergence — V0-I2S

### V0-I2S Spatial World Items / Containers

The current inventory proves canonical Item Graph transfers. The next product
step is to bring the already-existing world interaction surfaces into the same
Earth spatial presentation model.

Target:

```text
canonical Item WORLD relation
        ↓
world entity / spatial presentation
        ↓
shared Earth render projector
        ↓
visible item or container on terrain
        ↓
raycast / E
        ↓
canonical item.pickup / container interaction
        ↓
second client observes the same result
```

Reuse candidates already present in repository history:

```text
feature/m7-world-item-consistency-fix5
feature/n1-remote-item-command
existing world_interactable/raycast/highlight surfaces
existing M5 Item Graph UI bridge
```

For every world item use the same spatial principle already proven by
Construction and remote players:

```text
canonical world position != Node3D position
Node3D transform = projection(canonical spatial state, current Earth render frame)
```

## 4. Resource gameplay — V0-C3

### V0-C3 Item Graph ↔ Construction Resources

Replace the MVP-only Construction resource fixture with a boundary to the
canonical gameplay Item Graph.

First complete loop:

```text
find/pick material
→ material appears in backpack
→ build foundation
→ server validates requirement
→ Item mutation consumes material
→ Construction mutation advances stage
→ A/B converge on both domains
```

Reuse existing Construction economy/logistics work where its contracts are
compatible (`feature/c20-logistics-construction-economy`) rather than embedding a
second resource ledger in V0.

V0 must not invent cross-domain atomicity. If the existing boundary cannot
provide correctness, escalate the exact requirement to the canonical transaction
owner instead of hiding it in the UI.

## 5. Network quality gate — V0-N2

### Current finding

Do NOT re-import NX5 wholesale. The V0 tree already contains the same
`remote_snapshot_interpolator.gd` and `remote_player_presenter.gd` blobs as
`feature/nx5-remote-snapshot-interpolation`.

Current server fixed tick is 60 Hz and movement snapshot interval is 3 ticks,
therefore the intended remote snapshot cadence is ~20 Hz. The NX5 default
interpolation delay is 6 ticks (~100 ms).

Therefore visible remote jitter is an integration-quality defect, not evidence
that the V0 accidentally uses a pre-NX5 presenter.

### V0-N2 task

Before reconnect/soak, perform one bounded network presentation pass:

```text
measure actual received snapshot interval/jitter
measure interpolation mode distribution
measure render_tick progression
measure extrapolation/hold/buffering counts
compare server published snapshots vs client received snapshots
verify no Earth render-frame recenter introduces presentation discontinuity
```

Then fix only the proven layer. Candidate adjustments are allowed only after
measurement, for example interpolation clock or presentation smoothing. Do not
change authority, fixed-tick simulation or protocol merely to improve appearance.

### NX6

NX6 is useful next, but for a different purpose: its accepted branch adds
predicted item interaction journal/pump and M7 item-command integration on top of
NX5. Bring those ideas/components into V0-I2S where compatible; do not treat NX6
as a replacement remote-character interpolation stack.

## 6. Reconnect gate — V0-R1

Scenario:

```text
A + B join
A/B move
item picked up/transferred/dropped
outpost changes
B disconnects
A continues playing
B reconnects
same live world
same Item Graph truth
same Construction truth
same world-item spatial state
```

No hidden client-private reconstruction is allowed.

## 7. Final V0 acceptance — V0-A1

One launcher/runner exercises:

```text
boot dedicated server
2 clients join
movement + remote presentation
inventory/hotbar
world item pickup/drop
external container transfer
construct foundation/walls/roof using real inventory materials
second-client convergence
spectator spatial invariants
reconnect
30 minute soak
```

Acceptance additionally requires:

```text
no growing reliable/control backlog
no growing prediction history beyond bounded policy
no repeated disconnect loop
no spatial object following spectator by mistake
no duplicate Item/Construction authority
```

## 8. What stays after the global V0 baseline

Only after the above scenario is stable do we resume larger vertical slices.
Priority order:

```text
1. CH9 equipment/presentation convergence
2. construction editing UX from C16 where useful
3. mutable terrain/digging canonical integration
4. landed ship as world entity + cargo/container
5. movable ship / docking / flight
6. bots/agents on the same server authority model
7. space/handoff and larger distributed simulation work
```

The ship should reuse the same hierarchy rather than introduce a new spatial
model:

```text
ship root world entity / SpatialRef
+ Construction-local structure
+ Item Graph cargo/interior containers
+ derived presentation
```

## 9. Shortest path from today

```text
V0-P1  terrain visual polish              small, now
  ↓
V0-I2S spatial world items + containers   product loop
  ↓
V0-C3  real materials consumed by build   product loop
  ↓
V0-N2  measured remote presentation fix   quality gate
  ↓
V0-R1  reconnect same live world           resilience gate
  ↓
V0-A1  integrated runner + 30m soak        product acceptance
  ↓
GLOBAL V0 PRODUCT BASELINE
```

This keeps network quality visible but avoids blocking useful gameplay convergence
on speculative networking changes.