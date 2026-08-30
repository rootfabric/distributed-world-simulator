# V0 PLAYABLE SEAMLESS — Test Ladder

**Status:** CANONICAL TEST/COMPOSITION PLAN  
**Date:** 2026-08-30  
**Product train:** V0  
**Runtime mutation lease:** NOT OWNED BY THIS LANE  
**Current P7 state at plan creation:** P7.1 COMPLETE / P7.2 NEXT  
**Canonical main at plan creation:** `7055aef6c163099101588d5252d90ff77e089330`

## 1. Purpose

This lane creates locally runnable, observable acceptance tests that progressively compose the already accepted DWS product foundations into one playable seamless world.

The test lane is deliberately separate from the active P7 runtime implementation.

```text
P7
= runtime product integration

PLAYABLE SEAMLESS TEST LADDER
= test / composition / observation
```

It MUST NOT consume the pre-H0.3 runtime mutation worker and MUST NOT introduce production owners.

Primary human goal:

> A developer can start the test locally, see two graphical clients, watch the world state change, inspect authority handoff and item state, and receive deterministic PASS/FAIL evidence from the same run.

## 2. Hard boundary

The test lane may create:

```text
RUN_V0_PLAYABLE_SEAMLESS_*.sh
RUN_V0_PLAYABLE_SEAMLESS_*.ps1
tests/runtime/test_v0_playable_seamless_*.gd
tests/fixtures/v0_playable_seamless/**
docs/testing/**
artifacts/test-results/**
```

It MUST NOT implement missing product semantics inside fixtures.

Forbidden test-owned semantics:

```text
second Item Graph
second Matter truth
test-only authority protocol
test-only handoff semantics
test-only persistence owner
test-only replication protocol
test-only seam bridge
fake production adapter used only to make acceptance green
```

Rule:

```text
if the test needs a production capability that does not exist
→ report BLOCKED / NOT_YET_PROVEN
→ return the missing capability to the owning product stage
```

## 3. Existing accepted evidence to reuse

The first versions intentionally reuse accepted, already existing runtime paths.

### Seam / two graphical clients

```text
RUN_V0_SM1_GRAPHICAL.sh
tests/runtime/test_v0_sm1_graphical_handoff_processes.gd
```

Proves:

- Authority A + Authority B;
- Gateway;
- two graphical clients;
- stable client endpoint;
- A→B→A handoff;
- no reconnect/respawn for the handoff;
- monotonic authority epoch/world revision.

### Items / two graphical clients

```text
RUN_M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_TESTS.sh
RUN_M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_TESTS.ps1
tests/runtime/test_m5_graphical_multiplayer_acceptance.gd
```

Proves:

- two graphical clients;
- real canonical Item Graph;
- pickup/drop;
- inventory/hotbar;
- mount/detach;
- containers;
- reconnect;
- client Item Graph convergence.

### Item/Outpost + SM1 composition

```text
tests/runtime/test_v0_sm1_combined_carry_world_chain.gd
```

Proves composition of:

- Item Graph;
- Construction;
- P6 shared outpost;
- persistence owner;
- SM1 carrying/handoff/world continuity.

This is currently composition/headless evidence, not the final live graphical topology.

## 4. Test ladder

```text
V1  PLAYABLE SEAMLESS PRECHECK
    component convergence + local graphical observation
          ↓
V2  P7 MATERIAL PRODUCT PRECHECK
    add P7.1/P7.2 and, when available, P7.3 material→Item Graph evidence
          ↓
V3  SINGLE-TOPOLOGY TWO-CLIENT CONVERGENCE
    aligned with P7.5
          ↓
V4  SINGLE-TOPOLOGY SEAM + ITEMS + MATTER
    aligned with P7.6
          ↓
V5  GRAPHICAL DIGGING
    aligned with P7.7
          ↓
V0 PLAYABLE SEAMLESS PLANET
    COMPOSITION ACCEPTANCE
```

The ladder is monotonic: every later version preserves the earlier proof and adds one new live composition property.

## 4.1 Client-facing milestone anchors

The test ladder is also the execution/evidence carrier for the explicit client goals in
`docs/plans/V0_CLIENT_FACING_MILESTONES_RU.md`.

```text
P7.2 / V1-V2 → C1 PLANETARY SEAM VISUAL LAB
P7.5 / V3    → C2 TWO-CLIENT WORLD CONVERGENCE
P7.6 / V4    → C3 PLAYABLE SEAM + ITEMS
                two clients
                two authorities
                planet
                items on both sides
                pickup in A
                carry A→B
                drop in B
                second client picks it
                no reconnect/respawn
                stable player/item identity
P7.6+ lab    → C4 THREE-AUTHORITY STATIC CHAIN (optional)
P7.7 / V5    → C5 GRAPHICAL DIGGING
```

C3 is mandatory for the V0 product definition. C4 is an optional early scale lab and must
not delay C3 or create new authority semantics.

---

# 5. V1 — PLAYABLE SEAMLESS PRECHECK

## 5.1 Goal

V1 must be implementable immediately and in parallel with P7 without changing P7 production code.

V1 answers:

1. Can the exact same repository HEAD launch and pass the accepted seam graphical scenario?
2. Can the same HEAD launch and pass the accepted two-client Item Graph graphical scenario?
3. Does the accepted SM1+Item/P6 composition chain still pass?
4. Can a human locally watch the graphical clients while the automated test also records deterministic evidence?

V1 DOES NOT yet claim:

```text
single live topology containing seam + Item Graph = proven
```

Its required classification is:

```text
component_convergence = PASS
single_live_topology = NOT_YET_PROVEN
```

## 5.2 Planned files

Primary runner:

```text
RUN_V0_PLAYABLE_SEAMLESS_PRECHECK.sh
RUN_V0_PLAYABLE_SEAMLESS_PRECHECK.ps1
```

Coordinator:

```text
tests/runtime/test_v0_playable_seamless_precheck.gd
```

Optional test-only observation helpers:

```text
tests/fixtures/v0_playable_seamless/
    observation_overlay.gd
    observation_control.gd
    report_support.gd
```

No production runtime file is required for V1.

## 5.3 Local execution modes

### AUTOMATED

Example target interface:

```bash
./RUN_V0_PLAYABLE_SEAMLESS_PRECHECK.sh /path/to/godot-double
```

or:

```powershell
.\RUN_V0_PLAYABLE_SEAMLESS_PRECHECK.ps1 -GodotBin C:\path\godot.exe
```

Behavior:

- runs all V1 gates;
- automatically drives clients;
- records logs/reports/screenshots;
- returns exit 0 only when all mandatory component gates pass.

### OBSERVE

Target interface:

```bash
./RUN_V0_PLAYABLE_SEAMLESS_PRECHECK.sh /path/to/godot-double --observe
```

and Windows equivalent:

```powershell
.\RUN_V0_PLAYABLE_SEAMLESS_PRECHECK.ps1 -GodotBin C:\path\godot.exe -Observe
```

Behavior:

- graphical clients MUST NOT run headless;
- windows remain visible long enough for human inspection;
- important milestones are held for a bounded observation interval;
- the same automated assertions still execute;
- human observation does not become canonical truth.

Optional controls:

```text
--observe-seconds <N>
--keep-open-on-fail
--capture-screenshots
--only seam
--only items
```

## 5.4 V1 visible scenes

V1 is intentionally two live scenes plus one composition gate.

### Scene A — Seam

Launch topology:

```text
Authority A
Authority B
Gateway
Graphical Client A
Graphical Client B
```

Human should be able to observe:

```text
Client A moves
→ approaches seam
→ Authority A → B
→ continues without reconnect/respawn
→ returns B → A

Client B remains connected and observes the same player/world progression
```

Required evidence:

- two graphical client processes;
- stable Gateway endpoint;
- logical player identity stable;
- authority route A→B→A;
- authority epoch monotonic;
- reconnect_count = 0 for seam crossing;
- respawn_count = 0 for seam crossing;
- world revision monotonic.

### Scene B — Items

Launch topology:

```text
Dedicated Server
Graphical Client A
Graphical Client B
```

Human should be able to observe:

```text
A picks item
→ inventory/hotbar
→ mount/detach
→ container transfer
→ drop/repick

B observes converged Item Graph state
```

Required evidence:

- real graphical display for A and B;
- canonical Item Graph revision/checksum non-empty;
- pickup accepted;
- deterministic contention/rejection where expected;
- container transfer accepted;
- mount/detach accepted;
- drop/repick accepted;
- A/B converge to the same final Item Graph checksum.

### Gate C — SM1 + Item/P6 composition

Run existing:

```text
test_v0_sm1_combined_carry_world_chain.gd
```

Required evidence:

- real Item Graph state included in carrying/world continuity;
- P6 shared outpost composition remains valid;
- handoff/world continuity keeps canonical identities;
- no test-owned state store.

## 5.5 Observation HUD

V1 MAY add a test-only overlay, injected only by the test harness.

Recommended fields:

```text
CLIENT A / CLIENT B
test phase
logical_player_id
player_entity_id
current authority
AuthorityEpoch
world revision
position
Item Graph revision
Item Graph checksum
selected hotbar slot
equipped item_id
last accepted operation
PASS / FAIL / WAITING
```

The overlay is presentation-only and is not allowed to affect gameplay or assertions.

## 5.6 Evidence artifacts

V1 produces one root:

```text
artifacts/test-results/v0-playable-seamless-precheck-<run-id>/
```

Required contents:

```text
summary.json
seam/
    authority-a.json
    authority-b.json
    gateway.json
    client-a.json
    client-b.json
    *.log
items/
    server.json
    client-a.json
    client-b.json
    *.log
composition/
    result.json
screenshots/
    seam-before.png
    seam-after-a-to-b.png
    items-equipped.png
    items-container.png
```

Screenshots are evidence for observation only. Machine acceptance is based on exact runtime reports/assertions.

## 5.7 V1 summary contract

Minimum planned summary:

```json
{
  "schema": "distributed_world_simulator.v0_playable_seamless_precheck.v1",
  "passed": true,
  "godot": "4.7.1.stable.double.custom_build.a13da4feb",
  "exact_head": "<sha>",
  "component_convergence": "PASS",
  "single_live_topology": "NOT_YET_PROVEN",
  "seam_graphical": {
    "passed": true,
    "two_clients": true,
    "route": ["authority/a", "authority/b", "authority/a"],
    "reconnect_during_handoff": false
  },
  "items_graphical": {
    "passed": true,
    "two_clients": true,
    "item_graph_converged": true
  },
  "sm1_item_outpost_composition": {
    "passed": true
  }
}
```

## 5.8 V1 acceptance

V1 is PASS only when:

```text
exact double Godot                        PASS
same exact repository HEAD               PASS
SM1 graphical seam                       PASS
M5 graphical Item Graph                  PASS
SM1 + Item/P6 combined composition       PASS
two graphical clients actually visible  PASS
reports are non-empty and exact          PASS
no production source modified by V1      PASS
single_live_topology classified honestly NOT_YET_PROVEN
```

V1 MUST FAIL if one component test passes only by replacing an existing production owner with fixture logic.

---

# 6. V2 — P7 material product precheck

V2 is enabled incrementally as P7 capabilities become accepted.

After P7.1/P7.2:

```text
equipped tool
→ accepted authorization gate
→ existing MW4 mutation
→ bounded planetary Matter bubble
```

After P7.3:

```text
MatterMaterialBatch
→ canonical Item Graph
```

V2 adds mass/accounting evidence but still does not claim final two-client seam composition unless that topology is real.

# 7. V3 — Single-topology two-client convergence

Aligned with P7.5.

Required topology:

```text
Client A ─┐
          ├→ Gateway / active Authority → Matter
Client B ─┘
```

Required sequence:

```text
A equips tool
→ A mutates Matter
→ canonical commit
→ representation invalidation
→ material state
→ A and B converge
```

V3 changes:

```text
single_live_topology = PROVEN_FOR_TWO_CLIENT_CONVERGENCE
```

# 8. V4 — Single-topology seam + items + Matter

Aligned with P7.6.

Required scenario:

```text
A carries/equips canonical tool
→ A crosses Authority A→B
→ no reconnect
→ no respawn
→ same logical_player_id
→ same player_entity_id
→ same item_id/equipment relation
→ mutation under B
→ Client B sees same canonical result
```

For a mutation wholly owned by B:

```text
ordinary MW4 + SM1/MW8/MW9
```

For one mutation spanning A+B:

```text
MW10
```

The test MUST prove these are distinct cases.

# 9. V5 — Graphical digging

Aligned with P7.7.

Required visible loop:

```text
equip
→ aim
→ click
→ visible hole
→ canonical material yield
→ Item Graph inventory
→ second client sees same result
→ seamless handoff
→ continue digging
```

# 10. Final promotion

The test ladder becomes the principal runtime evidence for:

```text
V0 PLAYABLE SEAMLESS PLANET
TYPE = COMPOSITION ACCEPTANCE
```

Final acceptance later adds:

- reconnect;
- server restart;
- persistent hole;
- persistent Item Graph/material accounting;
- construction/shared outpost after the mutation;
- A↔B operation continuity.

## 11. Scheduling

This lane is allowed to proceed in parallel with P7 because it is test/composition-only.

```text
P7 runtime lane
    owns the one runtime mutation worker

Playable Seamless Test Ladder
    owns no runtime mutation lease
    may prepare/run tests in parallel
```

If a test change requires production runtime modification, that change is no longer part of the test lane and must be routed to the relevant P7/SM1/P5/P6 owner.

## 12. Immediate next test work

```text
NOW
  implement V1 runners (.sh + .ps1)
  implement V1 coordinator
  add AUTOMATED mode
  add OBSERVE mode
  reuse existing accepted seam/items/composition tests
  produce one summary.json
  capture bounded screenshots
  prove zero production-source diff

IN PARALLEL
  continue P7.2 runtime work

LATER
  promote V1 → V2/V3/V4/V5 at the corresponding P7 gates
```
