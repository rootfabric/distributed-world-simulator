# FABRIC-BAKE B0.5 — HYBRID BAKE / LAZY MODES — P0 Preflight Contract R1

## Qualification

```text
B0.5 HYBRID MODE BAKE + LAZY MODE COMPILATION

P0 CONTRACT / PREFLIGHT:
CLOSED / EXACT DOUBLE PASS / PROJECT CONTROL PASS

EXECUTABLE HYBRID REDUCTION:
STILL NOT AUTHORIZED

PRODUCTION ACCEPTANCE:
NO
```

Authorized P0 branch:

`research/fabric-bake0-5-hybrid-bake-preflight-r1`

## 1. Why P0 starts in parallel with B0.4

B0.4 will freeze a Dynamic ROM artifact interface.

Hybrid reduction will later need to bind:

- one reduced model per stable physical mode;
- mode-specific validity domains;
- transition guards;
- reset maps;
- source topology;
- exactly-once events.

P0 starts now so B0.4 does not accidentally create a mode-local ROM format that
cannot participate in hybrid transitions.

P0 may not implement a private ROM to bypass B0.4.

## 2. Existing FABRIC semantics are authoritative

B0.5 must consume the already existing generic semantics:

```text
FLOW
JUMP
TOPOLOGY TRANSACTION
complementarity
hybrid DAE
```

B0.5 does not invent a second hybrid state machine.

FABRIC remains the physical execution semantics; BAKE derives reduced artifacts.

## 3. Generic physical mode identity

Mode identity derives from physical state/topology, never device names.

A `HybridModeSignature` must bind at least:

- canonical source frontier hash;
- physical topology hash;
- active relation set/signature;
- complementarity/active-set signature where relevant;
- boundary contract hash;
- dependency/compiler versions.

Presentation order must not change mode identity.

Forbidden mode identity:

```text
MOTOR_ON
GEARBOX_SECOND_GEAR
CLUTCH_ENGAGED
VALVE_OPEN
```

unless those labels are purely UI aliases outside the kernel.

Kernel identity must remain generic physical relations/active constraints.

## 4. P0 contract set

P0 is authorized to define/validate the following generic contracts.

### 4.1 HybridModeSignature

Purpose:
deterministic identity of a mode-local physical regime.

### 4.2 HybridBakeModeDescriptor

Must bind:

- mode signature;
- source frontier;
- topology;
- boundary contract;
- mode-local validated domain;
- reduced artifact reference/interface;
- build generation;
- cache identity.

During P0, the B0.4 artifact reference may be an explicit unresolved interface
placeholder. It may not be replaced by a private device-specific reduced model.

### 4.3 HybridTransitionDescriptor

Must bind:

- transition ID;
- from/to mode signatures;
- localized guard;
- crossing direction;
- priority/order;
- reset/handoff map;
- optional topology transaction;
- conservation/error accounting;
- source revision/event ownership policy.

### 4.4 LazyModeCacheEntry

Must bind:

- deterministic cache key;
- exact mode signature;
- source/dependency versions;
- reduced artifact reference;
- validity state;
- stale/invalidation state.

The cache is derived state, never canonical truth.

## 5. Lazy compilation rule

Do not enumerate an exponential active-set space.

Required policy:

```text
mode encountered
      ↓
signature lookup
      │
      ├─ valid cached artifact
      │      ↓
      │    execute
      │
      └─ missing/stale
             ↓
       compile / validate
             │
             ├─ certifiable → cache derived artifact
             └─ unknown/unsafe → FULL / NO_SAFE_BAKE
```

No speculative `2^N` precompile requirement is allowed into the closure gate.

## 6. Transition ownership

A physical event has exactly one owner.

P0 must make it impossible for:

- FULL and BAKED mode layers to both commit the same JUMP;
- a cached mode artifact to replay an already committed topology transaction;
- a reset map to silently advance canonical source revision;
- a cache hit to resurrect a stale pre-mutation mode.

Canonical topology/source revision remains Construction/authority-owned where already
defined.

Derived mode/cache state follows canonical invalidation.

## 7. Reset / state handoff contract

For a transition:

```text
mode A reduced state
      ↓
localized guard
      ↓
physical JUMP / topology event
      ↓
reset/handoff
      ↓
mode B state
```

P0 must define the fields needed to verify:

- boundary continuity/discontinuity exactly where physics requires it;
- conservation/error envelope;
- no duplicate/lost state;
- compatibility with B0.4 projection/reconstruction;
- deterministic replay.

P0 does not need to solve the reduction numerically yet.

## 8. Unknown mode policy

If the encountered physical mode is absent, stale or uncertifiable:

```text
FULL
or
NO_SAFE_BAKE
```

The system must not:

- guess a nearest cached mode;
- reuse an artifact from a different active set;
- silently widen a ValidatedDomain;
- fabricate a reset map.

## 9. P0 preflight evidence

P0 should use existing generic hybrid fixtures to prove contract fit, including
FLOW/JUMP/topology examples already present in FABRIC.

The CONSTRUCT0 CATAPULT may be used as an additional tangible test vector because it
already demonstrates:

```text
HINGE
+ SPRING_DAMPER
+ BREAKABLE
+ localized latched → released transition
```

but it must not define a Catapult-specific kernel contract.

## 10. P0 acceptance gate

P0 may close only when:

- all P0 contract schemas validate fail-closed;
- identical physical mode inputs produce identical signatures/cache keys;
- input/presentation order invariance passes;
- changed source frontier/topology/dependency invalidates cache entries;
- unknown mode produces FULL / NO_SAFE_BAKE;
- transition descriptor has explicit exactly-once event ownership;
- reset/handoff contract references B0.4-compatible state mapping/reconstruction;
- no device-specific mode/solver class is introduced;
- no runtime claims are made for unresolved B0.4 artifact placeholders;
- Project Control passes.

P0 is primarily contract/validation work; a full Godot physics campaign is not
required unless P0 adds executable runtime code.

## 11. Unlock for executable B0.5

Executable hybrid reduction remains blocked until all are true:

1. B0.4 has a stable executable Dynamic ROM PhysicalBakeArtifact interface;
2. B0.4 projection/reconstruction/state mapping is frozen enough for mode handoff;
3. B0.4 runtime error/refinement semantics are available mode-locally;
4. P0 contract/preflight is CLOSED;
5. a generic two-mode falsifier is selected.

Recommended first executable falsifier after unlock:

```text
two stable passive modes
+
one localized FLOW → JUMP transition
+
deterministic reset
+
lazy compile/cache of the second mode
+
FULL fallback for an unknown third mode
```

No device semantics are required.

## 12. BRIDGE-2 relationship

P0 does not authorize BRIDGE-2 execution.

BRIDGE-2 may consume B0.5 only after a later review verifies that B0.5 mode artifacts
actually consume the B0.4 interface.

## 13. FABRIC0.19 relationship

P0 has no FABRIC0.19 dependency.

If a later executable hybrid falsifier cannot be expressed using FABRIC0.18's
generic physical semantics, that exact failure becomes evidence for a successor
review.

Until then:

```text
FABRIC0.19
NOT AUTHORIZED
```

## 14. Authorization decision

```text
B0.5 P0
CLOSED

branch:
research/fabric-bake0-5-hybrid-bake-preflight-r1

predecessor:
closed FABRIC.SYNC2 decision boundary

B0.5 executable:
NOT AUTHORIZED

dependency:
stable B0.4 mode-local Dynamic ROM artifact interface
```


## 15. P0 exact closure — 2026-09-01

```text
predecessor:
FABRIC.SYNC2 closure
be419fb695221917df0f6026ed335e1355f72840

exact implementation/test HEAD:
8c2a7db2a10e721546540e97ef8d2876f3dd41b4

TREE:
82d2819ac3c06ee34494d98eecf236a2664c052e

acceptance:
63/63 PASS

Project Control:
33516591870 SUCCESS

source carrier:
33516591916 SUCCESS

bundle SHA-256:
eaa70c0a808fd6d69a87ce9de8cf8b3f64424a3ab43a8d2891eae0426016f975
```

Implemented contracts:

```text
HybridModeSignature
HybridBakeModeDescriptor
HybridTransitionDescriptor
LazyModeCacheEntry
HybridBakePreflight
```

Verified properties:

- exact physical-mode identity is deterministic and presentation-order invariant;
- source-frontier/topology/dependency/B0.4-interface changes invalidate derived cache state;
- physical event ownership is exactly once and remains FABRIC-owned;
- reset/handoff cannot advance canonical source revision;
- unresolved B0.4 interface is PRELIGHT_ONLY and cannot claim runtime hashes/execution;
- unknown modes fall back to FULL / NO_SAFE_BAKE;
- nearest cached active-set reuse is forbidden;
- device-specific MOTOR/GEARBOX/CLUTCH/VALVE kernel identities are rejected;
- existing FABRIC FLOW/JUMP semantics remain authoritative.

Final qualification:

```text
B0.5-P0
RESEARCH CONTRACT/PREFLIGHT CHECKPOINT CLOSED
EXACT DOUBLE PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED

B0.5 EXECUTABLE HYBRID REDUCTION:
BLOCKED
```

Executable B0.5 still requires the stable executable B0.4 mode-local Dynamic ROM
PhysicalBakeArtifact interface and a new synchronization/authorization review.
