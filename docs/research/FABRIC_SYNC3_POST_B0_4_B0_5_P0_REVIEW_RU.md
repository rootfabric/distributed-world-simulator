# FABRIC.SYNC3 — POST-B0.4 + B0.5-P0 DEVELOPMENT REVIEW

## Status

```text
FABRIC.SYNC3

B0.4 DYNAMIC ROM:
CLOSED

B0.5-P0 HYBRID CONTRACT/PREFLIGHT:
CLOSED

B0.5-A EXECUTABLE HYBRID BAKE:
AUTHORIZED

FABRIC0.19:
NOT AUTHORIZED

BRIDGE-2 EXECUTABLE:
NOT AUTHORIZED

BRIDGE-2 DESIGN/PREFLIGHT:
ALLOWED

NOT PRODUCTION ACCEPTED
```

## Integration boundary

SYNC-3 is a two-parent integration boundary:

```text
parent 1:
B0.4 closure
1e8324407f60b4536bf9497e0a7c8a6874ae93ca

parent 2:
B0.5-P0 closure
d280096e0b64c03ac613e586881e43c816f471f0

integration commit:
91132efab20579fa2e64dc2fb9e0dc074c66179e

TREE:
fd745f5e0c6d37db6b468c8695361af43d891245
```

The P0 contract/test bytes are brought into the B0.4 closure tree without semantic
modification. The roadmap conflict is resolved in favor of the newer B0.4 closure
and then updated by this review.

## Evidence

### B0.4

```text
exact implementation/test HEAD:
e33ac10ac94d8b70f1387d442a3ae9d3801bb08a

A:
609/609 PASS

B:
83/83 PASS

C:
1533/1533 PASS

D:
287/287 PASS

full closure regression:
PASS / exit 0

Project Control exact subject:
33696130121 SUCCESS

closure/evidence Project Control:
33704064789 SUCCESS
```

B0.4 now exposes the missing executable mode-local Dynamic ROM interface through
the common PhysicalBakeArtifact architecture, including real StateMapping and
ReconstructionDescriptor.

### B0.5-P0

```text
exact implementation/test HEAD:
8c2a7db2a10e721546540e97ef8d2876f3dd41b4

closure:
d280096e0b64c03ac613e586881e43c816f471f0

acceptance:
63/63 PASS
```

P0 already freezes deterministic mode identity, transition/event ownership,
lazy-cache identity/invalidation, unknown-mode fail-closed behavior and the B0.4
state-handoff interface.

## B0.5-A decision

The SYNC-2 blocker is now removed:

```text
stable executable B0.4 mode-local ROM interface
✅ AVAILABLE

B0.5-P0
✅ CLOSED
```

Therefore:

```text
B0.5-A EXECUTABLE HYBRID BAKE
EXECUTABLE RESEARCH AUTHORIZED
```

Authorized branch:

`research/fabric-bake0-5-a-executable-hybrid-r1`

## First executable falsifier

The first executable subject is generic, not device-specific:

```text
stable passive mode A
using B0.4 PhysicalBakeArtifact
        │
        │ FLOW
        ▼
localized generic guard
        │
        │ JUMP exactly once
        ▼
reset / handoff
through B0.4 StateMapping + ReconstructionDescriptor
        │
        ▼
stable passive mode B
        │
        ├─ exact HybridModeSignature
        ├─ lazy compile on first encounter
        └─ derived cache hit on replay

unknown mode C
        ↓
FULL or NO_SAFE_BAKE
```

Required properties:

- both A and B use the common B0.4 Dynamic ROM PhysicalBakeArtifact interface;
- no private hybrid ROM object;
- FABRIC remains owner of FLOW/JUMP/topology semantics;
- one physical event has exactly one owner;
- reset/handoff does not advance canonical source revision;
- lazy cache is derived-only;
- stale source/topology/dependency/B0.4-interface cache entries are rejected;
- no nearest-mode reuse;
- unknown mode falls back FULL / NO_SAFE_BAKE;
- deterministic replay and lazy-cache identity;
- boundary/error/passivity constraints remain certified mode-locally;
- B0.4 runtime refinement remains authoritative inside each mode.

## FABRIC0.19 necessity

Current result:

```text
FABRIC0.19
NOT AUTHORIZED
```

Reason:

The selected B0.5-A falsifier can be expressed with existing FABRIC0.18 generic
FLOW/JUMP/hybrid-DAE/topology semantics plus the now-closed B0.4 artifact interface.

A future FABRIC0.19 proposal still requires a concrete executable failure proving a
missing generic Physical Core primitive, not merely an optimization opportunity.

## BRIDGE-2 decision

```text
BRIDGE-2 EXECUTABLE:
NOT AUTHORIZED

BRIDGE-2 DESIGN/PREFLIGHT:
ALLOWED
```

B0.4 + B0.5-P0 are necessary but not sufficient for executable mixed-world
integration.

Executable BRIDGE-2 requires:

1. B0.5-A CLOSED;
2. at least one actual lazy-compiled mode-B artifact consuming the B0.4 interface;
3. exact mode transition/state handoff evidence;
4. explicit ownership for FULL / STRUCTURAL_BAKE / CONTACT_BAKE / DYNAMIC_ROM /
   HYBRID_BAKE;
5. common invalidation/refinement ordering;
6. deterministic mixed replay;
7. no hidden authority crossing.

## Next checkpoint

```text
B0.5-A CLOSED
        ↓
FABRIC synchronization / BRIDGE-2 authorization review
        ↓
BRIDGE-2 executable?
FABRIC0.19 necessity?
```

## Final decision

```text
FABRIC.SYNC3
AUTHORIZED

B0.5-A EXECUTABLE HYBRID BAKE:
AUTHORIZED

FABRIC0.19:
NOT AUTHORIZED

BRIDGE-2 EXECUTABLE:
BLOCKED

NOT PRODUCTION ACCEPTED
```
