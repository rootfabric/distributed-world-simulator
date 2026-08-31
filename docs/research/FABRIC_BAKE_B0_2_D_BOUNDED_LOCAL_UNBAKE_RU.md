# FABRIC-BAKE B0.2-D — Bounded Local Unbake

**Status:** RESEARCH SLICE CLOSED / EXACT-HEAD DOUBLE PASS.  
**Branch:** `research/fabric-bake0-2-d-bounded-local-unbake-r1`.  
**Executable implementation HEAD:** `8da6ec6b7c2983b127f4c0607edeb9be900825c3`.  
**Executable TREE:** `285240dcc8a08a3a676897792659dfcad43bf410`.  
**Parent / B0.2-C evidence frontier:** `da90331f83e94ca71d8979304c084b072a082634`.  
Production acceptance is not claimed.

## Goal

B0.2-C can deterministically request refinement of a canonical structural region before a hidden certified bond capacity is crossed. B0.2-D consumes that request and performs a bounded derived representation transition:

```text
one 500-part BAKED aggregate
        ↓
C guard requests canonical region R
        ↓
reconstruct exact parent rigid state
        ↓
R becomes FULL
        +
unaffected connected residuals remain BAKED
        ↓
explicit FULL ↔ BAKED cut interfaces
        ↓
mass / linear momentum / angular momentum reconciliation
```

Construction / Matter remain canonical truth. No canonical part or bond is created, deleted, broken, or revised by D.

## Static local-unbake plan

The plan is content-bound to:

- source frontier hash;
- parent structural descriptor checksum;
- parent reconstruction mapping checksum;
- B0.2-C guard-field checksum;
- target canonical region;
- explicit maximum FULL-part bound;
- explicit minimum safe retained-component size;
- interface continuity tolerance;
- conservation tolerance;
- deterministic transition version.

The plan partitions every canonical part exactly once into either:

```text
FULL target region
or
one retained BAKED residual component
```

Every canonical bond is likewise accounted for exactly once as:

```text
target-internal
or
residual-internal
or
FULL ↔ BAKED cut bond
```

Overlap, omission, stale source identity, foreign descriptor/mapping/guard identity, or incomplete cut coverage fail closed.

## Boundedness rule

D does not silently grow the requested region.

If:

```text
target FULL part count > max_full_parts
```

the compiler returns:

```text
NO_SAFE_BOUNDED_LOCAL_UNBAKE_LIMIT
```

If removing the requested region leaves a residual connected component too small for the existing B0.2-A/B safe aggregate scope, the compiler returns:

```text
NO_SAFE_BOUNDED_LOCAL_UNBAKE_RESIDUAL_TOO_SMALL
```

instead of absorbing additional regions heuristically.

## Residual recompilation

Each retained connected component is recompiled from the original canonical parts and internal rigid bonds through the B0.2-A/B compiler. This produces a fresh derived descriptor/reconstruction mapping for that residual only.

Each cut bond produces an explicit derived cut interface:

```text
interface_id
bond_id
full_part_id
residual_part_id
residual_component_id
full_position_local
residual_anchor_id
point_from_parent_com
```

The residual synthetic anchor is located at the certified cut point carried by the B0.2-C guard topology.

## Runtime transition

Runtime does not trust a caller-provided statement that refinement was triggered. It re-evaluates the exact B0.2-C guard field.

R1 requires exactly one requested target region:

- safe guard state -> `STRUCTURAL_LOCAL_UNBAKE_GUARD_NOT_TRIGGERED`;
- request for another region -> `STRUCTURAL_LOCAL_UNBAKE_TARGET_NOT_REQUESTED`;
- unsupported multi-region transition -> fail closed.

The parent 13-DOF state is reconstructed to canonical FULL part states using B0.2-B. Only the requested region's part states are emitted as FULL. Every retained component is projected into its own 13-DOF reduced state and reconstructed again to audit continuity.

At each cut interface D checks position and velocity from both sides against the parent rigid state.

## Conservation reconciliation

The mixed representation is accepted only if:

```text
Σ mass(FULL target parts)
+ Σ mass(retained BAKED components)
= parent aggregate mass
```

and if combined linear and angular momentum equal the parent reduced state within deterministic tolerance.

Angular momentum of each residual aggregate is translated back to the original parent COM before reconciliation.

## Acceptance fixture

The existing 500-part / 25-region structural fixture is used.

B0.2-C requests:

```text
region/b0-2-012
```

The requested region contains 20 parts. Removing it from the canonical rigid chain leaves:

```text
20 FULL parts

240-part BAKED residual
240-part BAKED residual

2 cut interfaces
480 parts remain reduced
```

State representation:

```text
fully FULL:
500 × 13 = 6500 DOF

parent BAKED:
13 DOF

after bounded local unbake:
20 × 13 + 2 × 13 = 286 DOF

preserved reduction:
6500 / 286 = 22.727273x
```

Only 4% of canonical parts are expanded to FULL.

## Exact deterministic result

Both exact-head passes produced:

```text
B0.2-D Acceptance: PASS (609 assertions)

full=20
retained=480
components=2
interfaces=2

dof=6500->286
ratio=22.727273

mass_err=0.0
linear_err=0.00000000000023
angular_err=0.00000000000539

interface_pos=0.00000000000001
interface_vel=0.0

plan=
733cbe36eb3f98c72f893d83793ec6fe444899a32d7b7dc28d8cc991ac01ba8f
```

Reverse source ordering compiles to the same plan checksum.

## Fail-closed coverage

Acceptance covers, among other cases:

- guard has not triggered;
- guard requested a different region;
- bounded FULL-part limit exceeded;
- retained residual falls below safe aggregate minimum;
- canonical source mutation under stale parent descriptor;
- foreign guard binding;
- tampered ownership coverage;
- non-rigid source bond;
- stale source/descriptor/reconstruction bindings;
- guard topology mismatch.

## Exact verification

Pinned engine:

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Exact-source export:

```text
workflow run:
33365726226

artifact id:
9748204242

artifact name:
fabric-bake-b0-2-d-exact-source-8da6ec6b

artifact digest:
sha256:9f5dd67be50d79d7bcad6665781b5074117894da75f61a7c126b57e7ff1f660d

tracked archive SHA-256:
a15594210e395082b2186cb630e425535184f539115e470052cbc6914648f24d

tracked files:
5054
```

Two separate fresh archive extractions, each with a fresh Godot import, produced:

```text
B0.0 Acceptance       PASS (33)
B0.1 Acceptance       PASS (64)
B0.1 Playground       PASS
B0.2-A/B Acceptance   PASS (76)
B0.2-A/B Playground   PASS
B0.2-C Acceptance     PASS (118)
B0.2-C Playground     PASS
B0.2-D Acceptance     PASS (609)
B0.2-D Playground     PASS
```

Post-run byte audit for each fresh tree:

```text
checked=5054
missing=0
changed=0
```

Windows is `PASS_BY_POLICY / NON-GATING`.

## Non-claims

B0.2-D does not claim:

- canonical topology mutation;
- physical bond break/damage semantics;
- arbitrary multi-region simultaneous unbake;
- topology split/re-bake lifecycle completion;
- final B0.2 executable PhysicalBakeArtifact;
- B0.2 overall closure;
- production readiness.

## Next

```text
B0.2-E
TOPOLOGY SPLIT / RE-BAKE
```
