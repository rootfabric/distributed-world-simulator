# FABRIC.SYNC3 — POST-B0.4 / B0.5-P0 SYNCHRONIZATION REVIEW

## Status

```text
FABRIC.SYNC3
B0.4-D / B0.5-P0 INTERFACE SYNCHRONIZATION

REVIEW CLOSED
EXACT-HEAD CANONICAL DOUBLE PASS
PROJECT CONTROL PASS

B0.4 DYNAMIC ROM:
CLOSED / HUMAN ACCEPTED

B0.5-P0 HYBRID PREFLIGHT:
CLOSED

B0.5 EXECUTABLE HYBRID REDUCTION:
AUTHORIZED

BRIDGE-2 EXECUTABLE:
CONDITIONALLY AUTHORIZED AFTER B0.5-A CLOSES

FABRIC0.19:
NOT AUTHORIZED

PRODUCTION ACCEPTANCE:
NO
```

## 1. Exact reviewed subjects

```text
B0.4-D exact implementation:
6ffae6ee61fd1b7b33ad3da9de0d4f15b86a5aeb
TREE a20d545cfb9fc9d887230b8ee1abd2f5222841e5

B0.4 closure / human acceptance:
0e3fc0580ee50bc7bd25c96c11a293244b8850c9
TREE 13d37180697e0d00cca60307293a22f6bf0b766d

B0.5-P0 exact implementation/test:
8c2a7db2a10e721546540e97ef8d2876f3dd41b4
TREE 82d2819ac3c06ee34494d98eecf236a2664c052e

B0.5-P0 closure:
d280096e0b64c03ac613e586881e43c816f471f0
TREE 3c9abec167a2dc827996a08e37561d1f8fe72b5a

FABRIC0.18 closure:
b9f4a11cb7c31e47884d12eaad2985811e0b6563
```

SYNC-3 does not merge Physical Core history. FABRIC0.18 remains an explicit reviewed
dependency and its runtime-derived persistent contact state does not become canonical source.

## 2. Why SYNC-3 is required

SYNC-2 deliberately allowed B0.5-P0 to freeze contracts before the final B0.4 runtime
interface existed.

That worked as intended: P0 preserved the correct generic semantics, but its placeholder
resolved binding assumed:

```text
PHYSICAL_BAKE_ARTIFACT
state_mapping_checksum
reconstruction_descriptor_checksum
```

The closed B0.4-D executable boundary instead uses:

```text
DynamicRomExecutionArtifact
DynamicRomExecutionLifecycle
RomRuntimeCertificate
LAST_ACCEPTED_ROM_STATE_ONLY FULL handoff
C-norm bounded FULL -> ROM projection
```

The D artifact does not contain P0's placeholder `state_mapping_checksum` or
`reconstruction_descriptor_checksum`. Inventing synthetic hashes to satisfy the old
placeholder would be architecture fraud.

## 3. What remains valid from B0.5-P0

The following P0 contracts remain accepted without semantic change:

- physical mode identity derives from source/topology/active relations;
- device-specific MOTOR/GEARBOX/CLUTCH/VALVE kernel identities remain forbidden;
- FABRIC owns FLOW/JUMP physical event semantics;
- hybrid events remain EXACTLY_ONCE;
- reset does not seize canonical revision ownership;
- lazy cache remains derived-only;
- exact cache identity is required;
- nearest-mode reuse is forbidden;
- unknown/uncertifiable mode falls back FULL / NO_SAFE_BAKE.

P0 v1 remains immutable historical evidence and remains `PREFLIGHT_ONLY`.

## 4. SYNC-3 interface seam

SYNC-3 introduces:

`scripts/research/fabric_bake0/dynamic_rom_hybrid_interface_v1.gd`

It binds the actual closed B0.4-D interface:

```text
canonical source frontier
source binding checksum
physical topology / fabric graph
dependency fingerprint
PhysicalBoundaryContract
DynamicRomExecutionArtifact
ROM descriptor
reduced state schema
B0.4-B reduction binding
B0.4-C runtime certification
build generation
D lifecycle version
deterministic FULL-handoff contract
```

The handoff contract freezes:

```text
continuity_policy = LAST_ACCEPTED_ROM_STATE_ONLY
canonical_state_owner = PHYSICAL_SOURCE
rom_state_role = DERIVED_HANDOFF_ONLY
projection C-norm tolerance = B0.4-D frozen tolerance
```

Any rebuild generation or exact D artifact identity change changes the hybrid interface
identity. Canonical source/frontier changes are not cache-compatible.

## 5. B0.5 executable authorization

After SYNC-3 closes:

```text
B0.5-A EXECUTABLE HYBRID BAKE
AUTHORIZED
```

Mandatory B0.5-A entry rules:

1. consume `DynamicRomHybridInterfaceV1`; do not fabricate old P0 placeholder hashes;
2. use real B0.4-D execution artifacts per stable physical mode;
3. keep P0 mode signature semantics;
4. keep FABRIC FLOW/JUMP ownership;
5. compile/cache modes lazily by exact mode/interface identity;
6. unknown mode -> FULL / NO_SAFE_BAKE;
7. transition handoff must start from last accepted ROM state only;
8. destination mode may activate only after bounded FULL -> ROM handoff succeeds;
9. transition conservation/continuity must be measured explicitly;
10. no cache entry may become canonical state owner.

B0.5-A may introduce successor descriptor/transition schemas where required by the
actual D interface. It must not mutate the closed P0 v1 evidence in place.

## 6. BRIDGE-2 authorization

SYNC-3 does not authorize BRIDGE-2 to start immediately.

It establishes a conditional gate:

```text
B0.5-A CLOSED
+
one generic two-mode executable transition
+
exact B0.4-D interface consumption
+
FULL fallback / failed handoff evidence
+
exactly-one state/event ownership
        ↓
BRIDGE-2 EXECUTABLE AUTHORIZED
```

No additional Physical Core checkpoint is required merely to begin BRIDGE-2 after that gate.

## 7. FABRIC0.19 necessity test

The first B0.5 executable can be built from already accepted generic semantics:

```text
FLOW
JUMP
localized crossing guard
persistent contact/event ownership where applicable
B0.4-D mode-local ROM
FULL fallback
```

No missing physical primitive has been identified that makes the first generic hybrid
falsifier impossible.

Therefore:

```text
FABRIC0.18 remains frozen
FABRIC0.19 NOT AUTHORIZED
```

Unsupported future pressure/Hertz/non-coplanar/contact-PDE domains remain FULL /
NO_SAFE_BAKE until a concrete falsifier proves otherwise.

## 8. Focused acceptance

SYNC-3 acceptance must prove in one combined tree:

- B0.4-D focused acceptance still passes;
- exact closed B0.5-P0 contracts still pass;
- actual D artifact maps deterministically into the SYNC-3 hybrid interface;
- source/topology/boundary identity is compatible with P0 mode signatures;
- old P0 placeholder state-mapping/reconstruction fields are absent from D;
- no synthetic legacy hash is required;
- build generation changes interface identity;
- source revision changes interface identity;
- unknown mode fallback remains FULL;
- nearest cached mode reuse remains forbidden;
- FABRIC remains exactly-once event owner;
- canonical state owner remains PhysicalSource.

## 9. Decision

If focused exact double + Project Control pass:

```text
FABRIC.SYNC3
REVIEW CLOSED

B0.4:
CLOSED

B0.5-P0:
CLOSED

B0.5-A:
AUTHORIZED / NEXT EXECUTABLE

FABRIC0.19:
NOT AUTHORIZED

BRIDGE-2:
CONDITIONALLY AUTHORIZED AFTER B0.5-A CLOSED

NEXT:
B0.5-A EXECUTABLE HYBRID BAKE
```

This is a research architecture authorization, not production acceptance.


## 10. Closure evidence — 2026-09-03

```text
SYNC-3 implementation/test HEAD:
fb996d3692ea147749fc655636749d6db276a842

TREE:
34e5cf62efb44a6caae0136f1564c156b1b1520d

Project Control:
33643607663 SUCCESS

Exact Source Carrier:
33643607859 SUCCESS
artifact 9851825435

exact bundle SHA-256:
8332d10fbbb5ce3ff5f6184eada8dd4fc5b0d8eb2e78a628c4c189871f07f5f8

Portable Godot smoke:
33643607671 SUCCESS

canonical Linux double:
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

fresh import:
PASS / exit 0 / fatal markers 0

B0.4-D focused:
233/233 PASS

B0.5-P0 focused:
63/63 PASS

SYNC-3 focused:
66/66 PASS

SYNC-3 deterministic second run:
66/66 PASS

tracked status:
CLEAN

git diff --check:
PASS
```

Final qualification:

```text
FABRIC.SYNC3
POST-B0.4 / B0.5-P0 SYNCHRONIZATION REVIEW
CLOSED

B0.5-A EXECUTABLE HYBRID BAKE:
AUTHORIZED / NEXT

FABRIC0.19:
NOT AUTHORIZED

BRIDGE-2:
CONDITIONALLY AUTHORIZED AFTER B0.5-A CLOSED

NOT PRODUCTION ACCEPTED
```
