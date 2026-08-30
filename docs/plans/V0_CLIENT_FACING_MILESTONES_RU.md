# V0 — Client-Facing Milestones

**Status:** CANONICAL PRODUCT/TEST GOALS  
**Date:** 2026-08-30  
**Canonical base:** `f5bf92f1f3a3eed50d8e48c3a817a5d7db11039e`

## 1. Purpose

This document protects the client-visible goals of DWS from being lost inside foundation-level work.

The project is not considered product-complete merely because Authority, Matter, Item Graph or handoff contracts pass independently. The roadmap must periodically prove that a human can launch clients locally and see one coherent world.

## 2. Core client promise

The target experience is:

```text
2 graphical clients
+
2 or 3 server/Authority processes
+
one stable Gateway/client endpoint
+
continuous planetary surface
+
items distributed across authority regions
+
players can pick up / carry / drop items
+
players and items cross authority boundaries
+
no reconnect
+
no respawn
+
stable player identity
+
stable item identity
+
both clients converge on the same canonical world
```

Client-visible rule:

```text
ONE WORLD
ONE PLAYER IDENTITY
ONE ITEM IDENTITY
MULTIPLE TEMPORARY AUTHORITIES
```

Server process identity MUST NOT become permanent player/item/world identity.

## 3. Milestone C1 — PLANETARY SEAM VISUAL LAB

**Earliest target:** after P7.2 Bounded Planetary Matter Bubble.

Purpose: first locally observable planetary demo with live authority boundaries.

Topology:

```text
                    Gateway
                  /         \
             Client A      Client B

        Authority A  <-->  Authority B
              \              /
               continuous planet
```

Required visual properties:

- two graphical clients run locally;
- one continuous planetary surface is visible;
- Authority A and B are separate processes;
- clients cross A↔B without reconnect or respawn;
- optional authority debug overlay can show the seam;
- normal presentation hides the seam;
- static/world items may be placed in both regions using existing production paths;
- no test-owned item/authority semantics.

This milestone is a visual/product lab, not final cross-authority item acceptance.

## 4. Milestone C2 — TWO-CLIENT WORLD CONVERGENCE

**Target:** P7.5 / Test Ladder V3.

Required topology:

```text
Client A ─┐
          ├→ Gateway → active Authority → canonical world
Client B ─┘
```

Required proof:

- two graphical clients observe the same world revision;
- canonical Item Graph checksums converge;
- Matter/representation changes converge;
- neither client owns private canonical terrain/item truth;
- reconnect/resync behavior remains deterministic.

## 5. Milestone C3 — PLAYABLE SEAM + ITEMS

**Target:** P7.6 / Test Ladder V4.

This is the mandatory product milestone for the requested distributed-world experience.

Topology:

```text
                         Gateway
                      /           \
               Client A           Client B
                   │                 │
                   └──────┬──────────┘
                          │
                 canonical routing
                          │
             ┌────────────┴────────────┐
             ▼                         ▼
        Authority A               Authority B
          REGION A                  REGION B

       ● item 1                  ● item 2
       ● item 3                  ● item 4

════════════ continuous planet surface ════════════
```

Mandatory scenario:

```text
Client A picks up item in region A
→ item enters canonical Item Graph inventory
→ Client A crosses A→B
→ no reconnect
→ no respawn
→ same logical_player_id
→ same player_entity_id
→ same item_id
→ same equipment/carry relation
→ Client A drops item in region B
→ Client B sees the item
→ Client B picks it up
→ both clients converge
```

Required invariants:

```text
player_id before seam == player_id after seam
item_id before seam   == item_id after seam
Gateway endpoint      == unchanged
reconnect_count       == 0
respawn_count         == 0
canonical Item Graph  == single owner
authority route       == temporary
```

Item origin/placement region MUST NOT become permanent identity. Prefer:

```text
item/world/tool-001
spawn_origin_region = region/a
```

over identities such as:

```text
item/server-a/tool-001
```

## 6. Milestone C4 — THREE-AUTHORITY STATIC CHAIN

**Classification:** optional early scale-extension lab; later canonicalized under Static N-authority.

Topology:

```text
                    Gateway
             /        |        \
        Client A    routing    Client B
                     |
        ┌────────────┼────────────┐
        ▼            ▼            ▼
   Authority A  Authority B  Authority C

═══════ one continuous planetary surface ═══════
```

Scenario:

```text
Client A: A → B → C → B → A
Client B: C → B → A

items originate in A/B/C
players pick/carry/drop them across regions
item identity remains stable
```

This lab is allowed early only if it consumes existing generic authority/routing semantics and requires no A/B-specific foundation rewrite.

If the implementation reveals hard-coded two-authority assumptions, the lab reports the limitation and routes the required genericization to the owning authority/routing stage.

## 7. Milestone C5 — GRAPHICAL DIGGING IN SEAMLESS WORLD

**Target:** P7.7 / Test Ladder V5.

Required loop:

```text
2 graphical clients
→ equip tool
→ aim
→ dig
→ visible hole
→ canonical material yield
→ Item Graph inventory
→ second client sees same result
→ cross A↔B seam
→ continue digging
```

The player must experience the planet as one world even while ownership changes behind the scenes.

## 8. Final client acceptance

These milestones converge into:

```text
V0 PLAYABLE SEAMLESS PLANET
TYPE = COMPOSITION_ACCEPTANCE
```

Final minimum acceptance:

- two graphical clients;
- two Authority processes minimum;
- one stable Gateway endpoint;
- continuous planetary surface;
- items placed in multiple authority regions;
- pickup/carry/drop across seams;
- shared construction/outpost;
- graphical digging and material yield;
- two-client convergence;
- reconnect;
- server restart;
- persistent Matter and Item Graph state;
- no second canonical owner.

## 9. Local-observation requirement

Every client milestone from C1 onward must provide a locally runnable OBSERVE mode.

Recommended interface:

```text
Linux:
./RUN_V0_PLAYABLE_SEAMLESS_*.sh <godot-double> --observe

Windows:
.\RUN_V0_PLAYABLE_SEAMLESS_*.ps1 -GodotBin <godot-double> -Observe
```

The human must be able to see:

- Client A window;
- Client B window;
- authority/epoch debug HUD;
- world revision;
- Item Graph revision/checksum;
- currently held/equipped item;
- seam crossing without reconnect.

Human observation supplements deterministic assertions; it never replaces them.

## 10. Roadmap anchors

```text
P7.2  → C1 PLANETARY SEAM VISUAL LAB
P7.5  → C2 TWO-CLIENT WORLD CONVERGENCE
P7.6  → C3 PLAYABLE SEAM + ITEMS        MANDATORY
        C4 THREE-AUTHORITY STATIC CHAIN OPTIONAL LAB
P7.7  → C5 GRAPHICAL DIGGING
        ↓
V0 PLAYABLE SEAMLESS PLANET
```

These client goals are product anchors. Foundation work that does not advance or preserve them must not silently redefine the V0 success criterion.
