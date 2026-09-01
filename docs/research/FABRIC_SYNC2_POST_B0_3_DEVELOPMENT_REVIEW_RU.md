# FABRIC.SYNC2 — POST-B0.3 PHYSICAL / REDUCTION DEVELOPMENT REVIEW

## Status

```text
FABRIC.SYNC2
POST-B0.3 PHYSICAL / REDUCTION DEVELOPMENT REVIEW

DECISION:
B0.4 DYNAMIC ROM — EXECUTABLE RESEARCH AUTHORIZED
B0.5 HYBRID BAKE — CONTRACT / PREFLIGHT AUTHORIZED
FABRIC0.19 — NOT AUTHORIZED
BRIDGE-2 EXECUTABLE — NOT YET AUTHORIZED

RUNTIME CHANGES IN SYNC-2:
NONE

PRODUCTION ACCEPTANCE:
NO
```

## 1. Review base and evidence

Formal branch base:

```text
FABRIC-BAKE B0.3 closure
9575a63d6aeb4c455f8beade7588505e600c12d6

B0.3 exact executable
acc72c1fb216bea56bc44547bc3e1eec7a37af08
```

Reviewed Physical Core:

```text
FABRIC0.18 closure
b9f4a11cb7c31e47884d12eaad2985811e0b6563

FABRIC0.18 exact physics
e079565b4b9cd0dae530ff5042f057ce8fa0d0cc
```

Reviewed bake lifecycle:

```text
BRIDGE-1 closure
82a44ac8f6e362456cb2f8c150145e73afb17157

BRIDGE-1 exact executable
e128cf9d49f84691b8a5428c97ab7acd53b92d90

B0.2 final executable
91a2f79bf6738efefa342589c44e4a0f0a6960d6
```

Additional tangible/falsification evidence from the parallel CONSTRUCT0 line:

```text
CONSTRUCT0 exact implementation/test subject
afcd564b631a2f48283dfefef17f4d6542f558a3

CONSTRUCT0 closure/evidence
1b1e237a4dfd3706d5375023d7832f5dc42687d1

exact chain
325/325 PASS
```

CONSTRUCT0 is not made an ancestor of this review. It is evidence that the closed
Physical Core + BRIDGE-1 + B0.2/B0.3 stack can already support:

- FULL ↔ BAKED representation forcing;
- canonical invalidation/rebuild;
- bounded local unbake;
- topology split;
- deterministic component re-bake;
- generic HINGE/SLIDER/AXLE/SPRING/BREAKABLE toy compositions;

without a new Physical Core successor.

## 2. Closed claim matrix

| Capability | Closed evidence | Review result |
|---|---|---|
| general convex multipoint contact | FABRIC0.16 | sufficient for current bake boundary |
| persistent generalized contact/wrench state | FABRIC0.18 | sufficient |
| localized stick/slide/roll/spin/support transitions | FABRIC0.18 | sufficient |
| structural exact/rigid reduction | B0.1/B0.2 | sufficient |
| refinement guard field | B0.2-C | sufficient |
| bounded local unbake | B0.2-D | sufficient |
| topology split / deterministic re-bake | B0.2-E | sufficient |
| canonical source lifecycle / reconstruction | BRIDGE-1 | sufficient |
| coplanar contact/wrench reduction | B0.3 | sufficient |
| tangible FULL/BAKED lifecycle | CONSTRUCT0 | sufficient |

No closed claim above contains general dynamic-state model order reduction.

No closed claim above contains hybrid-mode reduction/lazy-mode caching.

These are now the dominant reduction walls.

## 3. Open wall matrix

### Wall A — dynamic state count

A structurally baked subsystem may still contain hundreds or thousands of dynamic
storage/feedback states.

Examples:

```text
elastic/modal state
electrical storage
thermal storage
coupled electromechanical state
distributed passive feedback
controller-like physical feedback
```

Current structural/contact reduction does not solve:

```text
FULL dynamic state x ∈ R^N
N = O(10^2 ... 10^3)

→

small reduced dynamic state z ∈ R^r
r = O(10)
```

This is the strongest immediate scalability wall.

### Wall B — hybrid mode count

Existing FABRIC already has FLOW/JUMP/topology/complementarity/hybrid DAE semantics,
but FABRIC-BAKE does not yet own a reduced, cacheable, validity-bounded mode artifact.

The danger is exponential active-set precompilation.

This is the second wall and should be attacked at contract level now.

### Wall C — unsupported contact physics

FABRIC0.18/B0.3 still do not claim:

- pressure-resolved contact PDE;
- compliant/Hertz contact;
- lubrication/wear/thermal friction;
- arbitrary non-coplanar contact bake;
- arbitrary multi-dynamic-body persistent-contact graphs.

These are real non-claims, but they do not currently block B0.4 or B0.5 preflight.

Unsupported contact domains already have a legal architecture path:

```text
FULL
or
NO_SAFE_BAKE
```

A non-claim is not by itself evidence that a new Physical Core checkpoint is needed.

## 4. FABRIC0.19 necessity test

A new Physical Core checkpoint may only be authorized when all are true:

1. a named downstream executable acceptance/falsifier needs a physical primitive;
2. that primitive cannot be represented by FABRIC0.18 semantics;
3. keeping the case FULL / NO_SAFE_BAKE would make the declared downstream
   acceptance impossible rather than merely less optimized;
4. the missing capability belongs in generic Physical Core rather than BAKE,
   Construction, scheduling or a device-specific layer;
5. the successor has an independently testable physical correctness boundary.

Current result:

```text
B0.4 first executable subject:
does not require FABRIC0.19

B0.5 contract/preflight:
does not require FABRIC0.19

CONSTRUCT0 lifecycle:
already passed without FABRIC0.19

FABRIC0.19:
NOT AUTHORIZED
```

Pressure/Hertz/non-coplanar extensions remain future candidates only if a concrete
accepted machine/falsifier proves FULL fallback is insufficient.

## 5. B0.4 decision

```text
B0.4
DYNAMIC STATE REDUCTION / ROM

AUTHORIZATION:
EXECUTABLE RESEARCH AUTHORIZED

priority:
PRIMARY NEXT EXECUTABLE
```

Initial B0.4 scope is deliberately narrower than arbitrary nonlinear ROM.

First executable target:

```text
stable passive mode-local dynamic subsystem
with generic physical boundary ports

FULL:
>= 512 dynamic states

REDUCED:
<= 24 dynamic states

target state-count reduction:
>= 20x
```

The first subject must be generic state/port physics, not a Motor/Gearbox/etc class.

Required architecture:

```text
canonical source binding
        ↓
PhysicalBoundaryContract
        ↓
mode-local FULL dynamic model
        ↓
exact/static elimination where possible
        ↓
structure/passivity-preserving ROM
        ↓
PhysicalBakeArtifact
        ├─ ValidatedDomain
        ├─ ErrorEnvelope
        ├─ RuntimeErrorEstimator
        ├─ RefinementGuard
        ├─ ReconstructionDescriptor
        └─ StateMapping
```

Required correctness emphasis:

```text
boundary behavior
+ conservative error certificate
+ passivity / no invented energy
+ deterministic artifact identity
+ safe reconstruction/refinement
```

not merely average regression quality.

The detailed authorization contract is frozen in:

`docs/research/FABRIC_BAKE_B0_4_DYNAMIC_ROM_AUTHORIZATION_RU.md`.

Authorized branch name:

`research/fabric-bake0-4-dynamic-rom-r1`.

It must fork from the closed SYNC-2 decision boundary, not directly from an
unreviewed experimental runtime branch.

## 6. B0.5 decision

```text
B0.5
HYBRID MODE BAKE + LAZY MODE COMPILATION

AUTHORIZATION:
CONTRACT / PREFLIGHT AUTHORIZED

EXECUTABLE HYBRID REDUCTION:
NOT YET AUTHORIZED
```

P0 may implement only generic contracts/preflight for:

- physical mode identity;
- source/topology/active-relation binding;
- reduced-mode descriptor;
- validity region;
- localized transition guard;
- reset/handoff descriptor;
- exactly-once event ownership;
- deterministic lazy-mode cache key;
- cache invalidation;
- FULL / NO_SAFE_BAKE fallback.

It must reuse existing FABRIC semantics:

```text
FLOW
JUMP
TOPOLOGY TRANSACTION
complementarity
hybrid DAE
```

Forbidden kernel shortcuts:

```text
Motor
Gearbox
Clutch
Valve
device-specific mode classes
```

The detailed P0 contract is frozen in:

`docs/research/FABRIC_BAKE_B0_5_HYBRID_BAKE_PREFLIGHT_RU.md`.

Authorized branch name:

`research/fabric-bake0-5-hybrid-bake-preflight-r1`.

B0.5 executable reduction is unlocked only after B0.4 exposes a stable
mode-local Dynamic ROM artifact interface.

## 7. B0.4 / B0.5 ordering

The tracks are intentionally asymmetric:

```text
                    SYNC-2
                       │
          ┌────────────┴────────────┐
          │                         │
          ▼                         ▼
   B0.4 EXECUTABLE            B0.5 P0 CONTRACT
     PRIMARY TRACK               PARALLEL
          │                         │
          │                 no executable ROM claim
          │                         │
          ▼                         │
   B0.4 interface stable            │
          │                         │
          └────────────┬────────────┘
                       ▼
               B0.5 executable
               authorization review
```

B0.5 is allowed to prevent B0.4 from accidentally freezing an artifact shape that
cannot participate in hybrid transitions, but B0.5 may not invent a private ROM.

## 8. BRIDGE-2 entry contract

```text
BRIDGE-2 EXECUTABLE
NOT AUTHORIZED BY SYNC-2
```

Design/preflight discussion is allowed, but executable mixed-graph work requires:

1. B0.3 remains closed;
2. B0.4 is CLOSED with an executable Dynamic ROM PhysicalBakeArtifact;
3. B0.4 demonstrates boundary compatibility and deterministic state handoff;
4. B0.5 P0 contract/preflight is CLOSED;
5. at least one generic B0.5 mode-local transition candidate consumes the B0.4
   artifact interface rather than a private reduction format;
6. mixed ownership for FULL / CONTACT_BAKE / DYNAMIC_ROM / HYBRID_BAKE is explicit;
7. no authority crossing is hidden.

Target representation ladder:

```text
FULL
 ↕
STRUCTURAL / CONTACT BAKE
 ↕
DYNAMIC ROM
 ↕
HYBRID BAKE
 ↕
FULL
```

BRIDGE-2 must preserve:

- effort/flow dimensions and sign/frame conventions;
- power/conservation/error accounting;
- event ordering;
- exactly-one state ownership;
- canonical source binding;
- deterministic replay;
- fail-closed stale artifacts.

## 9. Next synchronization point

Next formal synchronization is required:

```text
after:
B0.4 CLOSED
+
B0.5 P0 CLOSED

before:
BRIDGE-2 executable authorization
```

That review decides whether:

- B0.5 executable scope is mature enough;
- a concrete B0.4/B0.5 falsifier finally requires FABRIC0.19;
- BRIDGE-2 may become executable.

## 10. Final SYNC-2 decision

```text
FABRIC.SYNC2

PHYSICAL CORE:
FABRIC0.18 remains frozen
FABRIC0.19 NOT AUTHORIZED

PRIMARY NEXT EXECUTABLE:
B0.4 DYNAMIC ROM

PARALLEL AUTHORIZED WORK:
B0.5 HYBRID BAKE CONTRACT / PREFLIGHT P0

B0.5 EXECUTABLE:
BLOCKED ON STABLE B0.4 MODE-LOCAL ROM INTERFACE

B0.3:
NO IMMEDIATE DOMAIN EXPANSION
FULL / NO_SAFE_BAKE remains legal outside accepted domain

BRIDGE-2 EXECUTABLE:
BLOCKED

NEXT SYNC:
B0.4 CLOSED + B0.5 P0 CLOSED
```

This is an architecture/research authorization. It does not change runtime behavior
and does not promote any FABRIC/B0.x checkpoint to production acceptance.
