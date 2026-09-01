# FABRIC CONSTRUCT0 C0.4–C0.6 — Exact Verification and Closure

## Qualification

```text
C0.4 FULL ↔ BAKED PHYSICAL REPRESENTATION
CLOSED

C0.5 MUTATION / INVALIDATION / REBUILD
CLOSED

C0.6 LOCAL UNBAKE / TOPOLOGY SPLIT
CLOSED

CONSTRUCT0
RESEARCH / TANGIBLE CHECKPOINT CLOSED
EXACT DOUBLE PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

## Subject

```text
branch:
feature/fabric-construct0-c0-4-c0-6-lifecycle-r1

exact implementation/test HEAD:
afcd564b631a2f48283dfefef17f4d6542f558a3

TREE:
36064f8ad9f09e86cb242f4202f2e068044b6a2b

accepted predecessor:
d0eb147b435e85d12ce6db31111b37d62c0359bd
(CONSTRUCT0.PLAY1 closure/evidence)
```

Fresh verifier source was reconstructed from an exact Git bundle produced by the repository source-carrier workflow.

```text
bundle SHA-256:
84d119c649828a1b572aa25f7dd496dea45fd7ab3c32bf81551162dc7e9715f3

source carrier:
run 33507346997
SUCCESS

artifact:
9800137406
```

## Godot identity

```text
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

archive SHA-256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

Fresh detached verifier identity:

```text
HEAD:
afcd564b631a2f48283dfefef17f4d6542f558a3

TREE:
36064f8ad9f09e86cb242f4202f2e068044b6a2b

branch:
<detached-head>

tracked status:
clean
```

## Import

```text
Godot import:
PASS
exit 0

CONSTRUCT0 SCRIPT ERROR / failed-load markers:
0
```

Known historical ECO scene parse diagnostics remain present and non-fatal. They are outside the CONSTRUCT0 claim.

## Acceptance

```text
C0.1 SEE THE MODEL:
58 / 58 PASS

C0.2 SEE FABRIC MOVE IT:
33 / 33 PASS

C0.3 BUILD IT:
30 / 30 PASS

PLAY1 PHYSICAL TOYBOX:
111 / 111 PASS

C0.4 FULL ↔ BAKED:
26 / 26 PASS

C0.5 MUTATION / INVALIDATION / REBUILD:
23 / 23 PASS

C0.6 LOCAL UNBAKE / TOPOLOGY SPLIT:
44 / 44 PASS

TOTAL:
325 / 325 PASS

runner:
RUN_FABRIC_CONSTRUCT0_C0_6_TESTS.sh

chain exit:
0

fatal script markers in chain:
0
```

## C0.4 — FULL ↔ BAKED PHYSICAL REPRESENTATION

The Godot lifecycle lab consumes the exact 500-part BRIDGE-1 verification subject and calls the already closed physical-source lifecycle implementation.

Implemented modes:

```text
AUTO
FORCE FULL
FORCE BAKED
```

Verified behavior:

```text
canonical part count:
500

FULL complexity:
6500 DOF

BAKED complexity:
13 DOF

reduction:
500x

AUTO:
selects certified BAKED representation

FORCE FULL:
exact 500-part reconstruction

FORCE BAKED:
executes the existing PhysicalBakeArtifact

boundary anchor mismatch:
<= 1e-9
```

Representation switches do not mutate the canonical source frontier.

The UI also exposes:
- PhysicalBakeArtifact identity;
- build generation;
- refinement guard margin;
- current representation;
- FULL/current DOF;
- reduction ratio.

An explicit fail-closed unsupported-representation probe is visible as:

```text
NO_SAFE_BOUNDED_LOCAL_UNBAKE_LIMIT
→ NO_SAFE_BAKE
→ FAIL_CLOSED_OR_FULL
```

No silent approximation is introduced.

## C0.5 — MUTATION / INVALIDATION / REBUILD

The lab calls the closed BRIDGE-1 `rebuild_same_topology` lifecycle.

Verified sequence:

```text
canonical mass/property revision
        ↓
RepresentationInvalidation
        ↓
BakeInvalidation
        ↓
old PhysicalBakeArtifact
STALE / execution forbidden
        ↓
exact 500-part kinematic reconstruction
        ↓
contact state
DISCARD_AND_REDERIVE
        ↓
fresh compile / projection
        ↓
new PhysicalBakeArtifact
build_generation + 1
        ↓
fresh execution gate PASS
```

Required facts verified:
- stale rejection code is `STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN`;
- 500 full part states are reconstructed;
- old and new artifact identities differ;
- build generation increments exactly once;
- reconstruction/re-projection handoff error is within the BRIDGE-1 continuity tolerance;
- previous persistent contact impulse is not accepted as canonical truth;
- explicit FULL fallback remains available when requested.

## C0.6 — LOCAL UNBAKE / TOPOLOGY SPLIT

### B0.2-D bounded local unbake

The lab directly executes the closed B0.2-D compiler/runtime on the exact structural verification subject.

Verified:

```text
canonical parts:
500

locally FULL:
20 parts

retained reduced:
480 parts

retained reduced components:
2

cut interfaces:
2

FULL baseline:
6500 DOF

mixed before topology event:
286 DOF

preserved reduction:
> 22.7x

unbaked fraction:
4%
```

Mass, linear momentum, angular momentum, interface position and interface velocity continuity all remain within the frozen B0.2-D tolerances.

The transition explicitly reports:

```text
next required stage:
B0.2-E_TOPOLOGY_SPLIT_REBAKE
```

### B0.2-E topology split / re-bake

The lab then executes the closed B0.2-E compiler/runtime at the exact topology event.

Verified:

```text
bond break event:
APPLIED exactly once

split components:
2

invalidated predecessor reduced pieces:
3

new executable PhysicalBakeArtifacts:
2

FULL baseline:
6500 DOF

mixed before event:
286 DOF

rebaked:
26 DOF

post-split reduction:
250x
```

Mass, linear momentum, angular momentum and state handoff remain within the frozen B0.2-E tolerances.

The new component artifacts pass their own execution gates.

## Integrated Godot entrypoint

A single CONSTRUCT0 entrypoint now exists:

```text
res://scenes/labs/fabric_construct0_complete_lab.tscn
```

Launcher:

```text
OPEN_FABRIC_CONSTRUCT0_COMPLETE_LAB.ps1
```

It integrates three already verified views:

```text
C0.1-C0.3
SEE / MOVE / BUILD
        ↓
PLAY1
PHYSICAL TOYBOX
        ↓
C0.4-C0.6
FULL / BAKE / REBUILD / SPLIT
```

This satisfies the frozen CONSTRUCT0 end-to-end tangible path:

```text
build compound object
→ inspect canonical Construction
→ run/view physical behavior
→ compare FULL / BAKED
→ mutate canonical source
→ invalidate/reconstruct/rebuild
→ trigger bounded local unbake
→ break topology
→ split
→ deterministic component re-bake
```

Godot remains interaction/presentation only.

## Architectural non-claims

CONSTRUCT0 does not claim:
- production physics acceptance;
- production adaptive fidelity scheduling;
- dynamic ROM;
- hybrid bake;
- arbitrary non-coplanar contact bake;
- device-specific motor/gearbox physics;
- networked collaborative construction;
- BRIDGE-2 mixed-world production integration.

## Project Control

Exact implementation/test subject:

```text
run:
33507347220

conclusion:
SUCCESS
```

## Verdict

```text
VERIFIED
```

C0.4, C0.5, C0.6 and CONSTRUCT0 may be qualified CLOSED as research/tangible checkpoints.

## Next

The tangible CONSTRUCT0 line is complete. The next architecture decision returns to the post-B0.3 synchronization roadmap:

```text
CONSTRUCT0 ✅ CLOSED
        ↓
FABRIC SYNC-2 decision
        ↓
B0.4 Dynamic ROM
+ B0.5 Hybrid Bake contract/preflight
        ↓
BRIDGE-2
```
