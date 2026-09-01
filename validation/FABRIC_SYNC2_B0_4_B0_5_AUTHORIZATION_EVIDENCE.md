# FABRIC.SYNC2 — B0.4 / B0.5 Authorization Evidence

## Decision subject

```text
branch:
research/fabric-sync2-post-b0-3-development-review-r1

base:
9575a63d6aeb4c455f8beade7588505e600c12d6
FABRIC-BAKE B0.3 closure

decision HEAD:
4a8fdfc8e25ded698d3e682f2499ff60ca82ab83

decision TREE:
b23affe8d7078b24776208ad4846cbdf7293a731
```

## Decision delta

The decision subject is documentation/validation-only.

Changed paths relative to the B0.3 closure:

```text
docs/research/FABRIC_BAKE_B0_4_DYNAMIC_ROM_AUTHORIZATION_RU.md
docs/research/FABRIC_BAKE_B0_5_HYBRID_BAKE_PREFLIGHT_RU.md
docs/research/FABRIC_BAKE_ROADMAP_RU.md
docs/research/FABRIC_SYNC2_POST_B0_3_DEVELOPMENT_REVIEW_RU.md
validation/fabric_sync2_authorization.v1.json
```

No Physical Core, FABRIC-BAKE runtime, Construction runtime, Godot lab runtime or
acceptance test byte is changed by the SYNC-2 decision subject.

## Reviewed evidence

```text
FABRIC0.18 closure:
b9f4a11cb7c31e47884d12eaad2985811e0b6563

FABRIC0.18 exact physics:
e079565b4b9cd0dae530ff5042f057ce8fa0d0cc

B0.2 final executable:
91a2f79bf6738efefa342589c44e4a0f0a6960d6

BRIDGE-1 closure:
82a44ac8f6e362456cb2f8c150145e73afb17157

BRIDGE-1 exact executable:
e128cf9d49f84691b8a5428c97ab7acd53b92d90

B0.3 closure:
9575a63d6aeb4c455f8beade7588505e600c12d6

B0.3 exact executable:
acc72c1fb216bea56bc44547bc3e1eec7a37af08

CONSTRUCT0 exact subject:
afcd564b631a2f48283dfefef17f4d6542f558a3

CONSTRUCT0 closure/evidence:
1b1e237a4dfd3706d5375023d7832f5dc42687d1

CONSTRUCT0 exact acceptance:
325/325 PASS
```

CONSTRUCT0 is considered parallel falsification/tangible evidence and is not made an
ancestor of the SYNC-2 branch.

## Authorized work

### B0.4

```text
B0.4 DYNAMIC STATE REDUCTION / ROM

authorization:
EXECUTABLE RESEARCH AUTHORIZED

branch:
research/fabric-bake0-4-dynamic-rom-r1

priority:
PRIMARY NEXT EXECUTABLE

initial reference target:
FULL >= 512 dynamic states
REDUCED <= 24 dynamic states
state reduction >= 20x
relative boundary response error <= 1e-3
```

Required:
- existing PhysicalBakeArtifact architecture;
- generic physical boundary ports;
- ValidatedDomain;
- ErrorEnvelope;
- RuntimeErrorEstimator;
- RefinementGuard;
- ReconstructionDescriptor;
- StateMapping;
- passivity / no invented energy;
- deterministic artifact identity;
- FULL / NO_SAFE_BAKE fail-closed path.

### B0.5

```text
B0.5 HYBRID MODE BAKE + LAZY MODE COMPILATION

authorization:
P0 CONTRACT / PREFLIGHT AUTHORIZED

branch:
research/fabric-bake0-5-hybrid-bake-preflight-r1

executable hybrid reduction:
NOT AUTHORIZED
```

P0 is limited to generic mode/signature/cache/transition/reset/invalidation/fallback
contracts over existing FABRIC FLOW/JUMP/TOPOLOGY TRANSACTION/complementarity/hybrid
DAE semantics.

B0.5 executable work remains blocked until B0.4 exposes a stable mode-local Dynamic
ROM PhysicalBakeArtifact interface.

## Explicit non-authorizations

```text
FABRIC0.19:
NOT AUTHORIZED

BRIDGE-2 executable:
NOT AUTHORIZED

B0.3 domain expansion:
NOT AUTHORIZED BY SYNC-2
```

Unsupported physical/reduction domains retain the legal:

```text
FULL
or
NO_SAFE_BAKE
```

path.

## Project Control

Decision subject:

```text
run:
33512470596

conclusion:
SUCCESS
```

## Verdict

```text
FABRIC.SYNC2
DECISION VERIFIED

B0.4 EXECUTABLE RESEARCH AUTHORIZED
B0.5 P0 CONTRACT/PREFLIGHT AUTHORIZED
FABRIC0.19 NOT AUTHORIZED
BRIDGE-2 EXECUTABLE NOT AUTHORIZED
NOT PRODUCTION ACCEPTED
```

## Next

The next implementation branches are now allowed to fork from the closed SYNC-2
decision boundary:

```text
research/fabric-bake0-4-dynamic-rom-r1
research/fabric-bake0-5-hybrid-bake-preflight-r1
```

The next mandatory synchronization is after B0.4 CLOSED + B0.5 P0 CLOSED and before
BRIDGE-2 executable authorization.
