# FABRIC.SYNC4 — POST-B0.5-A / BRIDGE-2 AUTHORIZATION REVIEW

## Status

```text
FABRIC.SYNC4
POST-B0.5-A SYNCHRONIZATION REVIEW

B0.5-A EXECUTABLE HYBRID:
CLOSED

BRIDGE-2 EXECUTABLE RESEARCH:
AUTHORIZED

FABRIC0.19:
NOT AUTHORIZED

NOT PRODUCTION ACCEPTED
```

## Predecessor

Canonical runtime evidence remains the B0.5-A exact subject:

```text
exact implementation/test HEAD:
d819fffa0dc86cc09cda0000f20c310aec23c799

TREE:
c92c1ff22c683ba348ac8596d2e6b3212a381b57

B0.5-P0:
63/63 PASS

B0.5-A:
67/67 PASS

closure chain:
PASS / exit 0

Project Control:
33708036538 SUCCESS
```

The review branch begins from the later docs-only B0.5-A tip:

```text
2115dc0d26f77ce43a9a8efef1d339efd87fa2cd
```

Project Control for that tip is also SUCCESS.

## What changed since SYNC-3

SYNC-3 blocked executable BRIDGE-2 because a real B0.4-backed hybrid mode transition
had not yet been demonstrated.

B0.5-A now proves:

- two generic modes backed by common B0.4 PhysicalBakeArtifact;
- FLOW executed through B0.4 runtime certification;
- FABRIC-owned localized physical JUMP;
- exactly-once event consumption;
- A ReconstructionDescriptor → FULL handoff → B StateMapping;
- lazy mode-B executable wrapper/cache;
- exact deterministic cache replay;
- stale/unknown fail-closed behavior;
- B0.4 refinement authority preserved after transition.

That removes the final SYNC-3 entry blocker.

## Common representation substrate

The representations needed by BRIDGE-2 are no longer unrelated runtime systems.

### STRUCTURAL_BAKE

BRIDGE-1 structural lifecycle emits common:

```text
PhysicalBakeArtifact
ReconstructionDescriptor
StateMapping
ValidatedDomain
ErrorEnvelope
ConservationEnvelope
RefinementGuard[]
BakeExecutionGate
```

It already proves source mutation → invalidation → stale rejection →
reconstruction/rebuild/full fallback.

### CONTACT_BAKE

B0.3 contact-wrench bridge also emits common PhysicalBakeArtifact via
FabricBakeFoundationCompilerV1 and uses the same BakeExecutionGate.

Persistent contact history remains transient solver assist and is re-derived after
reconstruction.

### DYNAMIC_ROM

B0.4-D emits common PhysicalBakeArtifact with real StateMapping and
ReconstructionDescriptor and has exact FULL↔ROM handoff.

### HYBRID_BAKE

B0.5-A does not invent another physical artifact class.

It wraps B0.4 PhysicalBakeArtifact modes and consumes FABRIC-owned physical events.

### FULL

FULL is the deterministic fallback/reference physical representation.

It is never canonical world truth; canonical Construction/Matter/PhysicalSource
remains authoritative.

## Decision: BRIDGE-2

There is now enough evidence to start executable research.

```text
BRIDGE-2 MIXED REPRESENTATION EXECUTION
EXECUTABLE RESEARCH AUTHORIZED
```

This is an authorization to build and falsify a bounded mixed subject, not a claim
that BRIDGE-2 is already implemented or closed.

Canonical branch:

`research/fabric-bridge2-mixed-representation-r1`

## Frozen entry contract

R1 representation kinds:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

Rules:

```text
canonical owner:
PHYSICAL_SOURCE

representation role:
DERIVED_EXECUTION_ONLY

region ownership:
EXPLICIT_NON_OVERLAPPING_REGION_OWNERSHIP

cross-region interface:
PHYSICAL_BOUNDARY_CONTRACT_EFFORT_FLOW_ONLY

physical event owner:
FABRIC_PHYSICAL_EVENT

canonical revision policy:
EXTERNAL_AUTHORITY_ONLY

unknown representation:
FULL_OR_NO_SAFE_BAKE
```

State transitions between representation kinds require explicit reconstruction/full
handoff/projection. A representation is not allowed to directly copy private solver
state into another representation.

## First executable falsifier

```text
MIXED_GENERIC_MACHINE_R1
```

One canonical PhysicalSource frontier is partitioned into explicit regions:

```text
region A → STRUCTURAL_BAKE
region B → FULL
region C → CONTACT_BAKE
region D → DYNAMIC_ROM
region E → HYBRID_BAKE
```

The first subject must demonstrate:

1. all five regions refer to one canonical source frontier;
2. each physical state degree has one explicit representation owner;
3. cross-region coupling only through declared PhysicalBoundaryContract ports;
4. stable FLOW with simultaneous mixed execution;
5. at least one FABRIC-owned event that changes required representation;
6. reconstruction/project handoff without duplicate physical state ownership;
7. canonical mutation invalidates every affected derived artifact/cache before reuse;
8. unaffected regions remain executable;
9. stale artifacts cannot execute;
10. deterministic mixed replay;
11. FULL reference produces the same causally meaningful outcome within declared envelopes;
12. unknown or uncertifiable region falls back FULL / NO_SAFE_BAKE.

The first R1 need not be a polished world demo; it is an architecture falsifier.

COMPLEX1B / powered breakable structure becomes the first visually meaningful
downstream mixed-system lab once the bridge path exists.

## Invalidation ordering

BRIDGE-2 must preserve:

```text
canonical source mutation
        ↓
RepresentationInvalidation
        ↓
BakeInvalidation / cache invalidation
        ↓
affected artifacts STALE
        ↓
execution forbidden
        ↓
reconstruct/refine/FULL
        ↓
fresh compile/rebuild
        ↓
execution may resume
```

No representation may continue for one extra step after its relevant canonical
dependency became stale.

## Refinement ordering

If any active reduced representation reaches its certified guard:

```text
representation-local guard
        ↓
REFINE / RECONSTRUCT / FULL
        ↓
only then continue cross-region execution
```

Hybrid orchestration cannot suppress B0.4 or structural/contact refinement.

## FABRIC0.19 re-evaluation

Result:

```text
FABRIC0.19
NOT AUTHORIZED
```

No current executable failure demonstrates a missing generic Physical Core
primitive.

Every operation required by the BRIDGE-2 R1 falsifier is expressible with existing
FABRIC0.18 semantics:

- FLOW;
- effort/flow coupling;
- localized JUMP;
- exactly-once physical event ownership;
- topology transaction;
- persistent contact state;
- support loss/separation;
- mode transition;
- reconstruction/refinement lifecycle.

The current missing work is representation orchestration, not core physical
semantics.

## What would authorize FABRIC0.19

A future proposal requires a concrete executable failure satisfying all of:

1. the subject uses already-closed generic Construction/FABRIC primitives;
2. the failure remains under FULL reference execution, not only reduced execution;
3. it cannot be expressed using FABRIC0.18 FLOW/JUMP/topology/contact semantics;
4. it is not merely a performance/scaling problem;
5. it is not a missing B0.x compiler/bridge/cache/invalidation feature;
6. the missing concept can be stated as a generic physical primitive or law;
7. a minimal falsifier exists.

Only then may SYNC authorize FABRIC0.19.

## BRIDGE-2 closure gate

Authorization does not equal closure.

BRIDGE-2 closes only after exact double verification proves:

- five-kind mixed representation registry;
- explicit region ownership;
- no overlapping solver authority;
- one canonical PhysicalSource frontier;
- common boundary coupling;
- mixed FLOW;
- physical event handoff;
- local refinement/reconstruction;
- exact invalidation fan-out;
- stale rejection;
- deterministic replay;
- FULL-vs-mixed causal equivalence;
- Project Control;
- fresh exact source carrier.

## Verdict

```text
FABRIC.SYNC4
CLOSED when control/evidence passes

BRIDGE-2 EXECUTABLE RESEARCH
AUTHORIZED

FABRIC0.19
NOT AUTHORIZED

next:
BRIDGE-2 MIXED REPRESENTATION R1
```
