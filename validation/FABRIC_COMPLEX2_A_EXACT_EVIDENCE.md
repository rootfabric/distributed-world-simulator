# FABRIC COMPLEX2-A — Exact Modular Machine Evidence

**Verdict:** PASS / CHECKPOINT EXACT VERIFIED  
**COMPLEX2 overall:** OPEN  
**Branch:** `feature/fabric-complex2-modular-machine-r1`  
**PR:** #534

## Exact source identity

```text
HEAD  8d10a4e00b616c28e62cd16b4645342dc8256632
TREE  7ce37330e70f5082c7e5d1e6632e0b5982bbcaf4
```

Exact source carrier:

```text
workflow run 33864290741
artifact     9933326912
artifact digest
sha256:fd2901a506b285f0b7b9ff0569a30dd72afc976476f990b3690da8715c0dd028
```

The artifact bundle itself was SHA-256 verified before checkout and resolved to the exact HEAD/TREE above.

## Runtime

Attached canonical double build:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Execution was performed as the non-root `oai` user with isolated writable HOME/XDG paths.

## Exact acceptance

Two independent Godot processes executed:

```text
res://tests/research/fabric_bake0/fabric_bake_complex2_modular_machine_acceptance.gd
```

Both returned:

```text
FABRIC COMPLEX2 Modular Machine Acceptance: PASS (2115 assertions)
parts=2000
modules=25
movers=6
contacts=3
paths=2
second_event=accepted
mixed=FULL_REFERENCE
```

Both independent processes produced exactly the same deterministic experiment identity:

```text
COMPLEX2_EXPERIMENT_HASH=
7017c4acf32ff0f8e75165e1bd8a9c9c45e111ba767776f9ab8b486a52cae541
```

Therefore process-isolated replay determinism is established for this checkpoint.

## Visual parser smoke

```text
FABRIC COMPLEX2 Scene Smoke: PASS (3 assertions)
```

Scene:

```text
res://scenes/labs/fabric/complex2_modular_machine_lab.tscn
```

The visual layer remains a read-only observer and is not part of canonical machine ownership.

## Accepted composition

```text
canonical parts              2000
logical structural modules   25
parts per module             80
moving subsystems            6
active contact zones         3
functional paths             2
BRIDGE-2 execution regions   5
```

The five execution partitions remain exactly the closed BRIDGE-2 R1 set:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

The 25 modules are logical/canonical composition above those five owners; no fake extra representation authority was introduced.

## Accepted physical / causal sequence

### Normal mixed movement

Drive flows are applied to DYNAMIC_ROM and HYBRID_BAKE partitions. Every mixed step is compared against the FULL reference.

```text
max mixed/FULL state delta <= 1e-12
observed exact sequence max delta = 0
```

### Local contact

External contact flow enters only:

```text
region/complex2-contact
```

The contact state changes measurably and remains identical to FULL reference execution.

### First structural event — detachable module

```text
event/complex2-detach-module-24
support/complex2-23-24
```

Accepted result:

```text
module 24 -> singleton disconnected component
machine revision 100 -> 101
only HYBRID execution partition invalidated
stale mixed execution forbidden
HYBRID rebuild state handoff error = 0
```

The same support identity drives generic functional topology loss:

```text
wire/branch-a -> SUPPORT_TOPOLOGY_LOST
load A: ON -> OFF
load B: ON -> ON
```

This rejects a hidden machine-level shortcut such as `detached -> all loads off`.

### Stabilization + representation event

After rebuild and stable mixed/FULL evolution, one event atomically swaps:

```text
region/complex2-full    FULL        -> HYBRID_BAKE
region/complex2-hybrid  HYBRID_BAKE -> FULL
```

Accepted:

```text
representation event ledger entries = 1
max state handoff error = 0
five-kind representation set preserved
mixed/FULL equality preserved
```

### Second event against already reconfigured machine

```text
event/complex2-break-drive-support
support/complex2-10-11
```

Accepted result:

```text
machine revision 101 -> 102
second distinct event accepted exactly once
only DYNAMIC partition invalidated
stale execution forbidden
DYNAMIC rebuild state handoff error = 0
wire/branch-b -> SUPPORT_TOPOLOGY_LOST
load A: OFF
load B: ON -> OFF
mixed execution resumes
```

This is the key anti-single-shot falsifier for COMPLEX2-A.

## Regression qualification

This checkpoint does not modify the closed BRIDGE-2 core files. On this exact HEAD:

```text
Project Control                         SUCCESS
FABRIC-BAKE BRIDGE-2-A Portable Smoke  SUCCESS
FABRIC-BAKE Complex Labs Portable Smoke SUCCESS
FABRIC BRIDGE-2 Exact Source Carrier   SUCCESS
```

The previously closed exact BRIDGE-2 generic-machine regression remains the predecessor proof (`PASS 125 assertions`, max FULL delta 0). The focused COMPLEX2 runner intentionally does not re-run that legacy stateful test in-process; dedicated BRIDGE-2 workflows remain attached to the PR.

Self-hosted Linux-double jobs are still an external runner queue and are not represented as completed evidence.

## Checkpoint decision

```text
COMPLEX1B  CLOSED
    ↓
COMPLEX2-A Composition / Contact / Detach / Swap / Second Event
    ✅ EXACT VERIFIED
    ↓
COMPLEX2 remains OPEN
```

Next COMPLEX2 work must deepen the machine rather than merely add more module records:

1. compliant/spring response envelope;
2. stronger articulated/rotating subsystem interaction;
3. independent structural-support failure distinct from detachable endpoint;
4. settle → rebake → re-impact lifecycle;
5. scale/performance matrix at 500 / 1000 / 2000 canonical elements;
6. final COMPLEX2 closure review.
