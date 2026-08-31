# FABRIC-BAKE B0.2-E — Topology Split / Re-bake

**Status:** RESEARCH SLICE CLOSED / EXACT-HEAD DOUBLE PASS.  
**Branch:** `research/fabric-bake0-2-e-topology-split-rebake-r1`.  
**Executable implementation HEAD:** `91a2f79bf6738efefa342589c44e4a0f0a6960d6`.  
**Executable TREE:** `610288ea119e9f7508f711ce5b0468b272a9b489`.  
**Parent / B0.2-D docs frontier:** `762ef5d4b3094d021b3f9f956b3d0cf049a2a38c`.  
Production acceptance is not claimed.

## Goal

B0.2-E closes the structural aggregate lifecycle after B0.2-C guard refinement and
B0.2-D bounded local unbake:

```text
canonical rigid structure
→ aggregate bake
→ guard-triggered bounded local FULL region
→ canonical topology event
→ stale reduced pieces invalidated
→ graph split
→ surviving connected components recompiled
→ fresh executable BAKE_READY artifacts
→ exact state / ownership handoff
```

The topology event belongs to the canonical Construction/Matter source. E does not
invent a parallel topology truth.

## Exact-once topology transaction

R1 accepts an explicit canonical `BOND_BREAK` revision for a bond that is already
inside the FULL region produced by D.

The transaction binds:

- pre-event source frontier;
- post-event source frontier;
- D local-unbake plan;
- topology event identity;
- broken canonical bond identity;
- complete pre/post canonical part inventory;
- complete pre/post canonical bond inventory;
- invalidated reduced piece identities;
- derived post-split component identities;
- re-baked artifact identities;
- deterministic transition version.

The same event cannot be committed twice. Replay or duplicate mutation ownership is
rejected fail-closed.

## Invalidation rule

On accepted topology revision, E invalidates every old reduced representation whose
source coverage is no longer valid:

```text
old parent aggregate
+ D residual aggregate #1
+ D residual aggregate #2
→ STALE / invalidated
```

No stale reduced descriptor is allowed to remain executable after the canonical bond
revision.

## Split and re-bake

After removing `bond/b0-2-0257`, the canonical 500-part chain splits into two connected
rigid components:

```text
component A: 257 parts
component B: 243 parts
```

Each eligible component is independently rebuilt through the existing B0.2 pipeline:

```text
canonical component
→ A/B structural aggregate + reconstruction mapping
→ C refinement guard field
→ B0.0 PhysicalBakeArtifact
→ BAKE_READY
```

This produces two fresh executable artifacts on the post-event frontier.

## State handoff and conservation

The parent state is reconstructed to all canonical part states before topology split.
Each new component derives its reduced state from exactly the parts it owns.

The runtime audits:

- complete exactly-once ownership of all 500 canonical parts;
- no part duplication across components;
- no lost part state;
- exact pose/velocity handoff to every part;
- total mass;
- linear momentum;
- angular momentum translated to a common frame.

## Acceptance result

The canonical 500-part fixture gives:

```text
split components:
[243, 257]

invalidated old reduced pieces:
3

new executable BAKE_READY artifacts:
2

state DOF:
6500 fully FULL
→ 286 B0.2-D mixed
→ 26 post-split re-baked

post-split reduction:
250.000000x
```

Exact deterministic errors:

```text
mass_err=0.0
linear_err=0.00000000000017
angular_err=0.00000000001475
state_err=0.00000000000002
```

Exact identities:

```text
event:
2265ae95b31918ea728015c8ffdcc39076c0928834a9e041927f09f7d78e6287

transaction:
e9c42a971c1f562ccb156743245611ce5f837337f473452715f412422640063a
```

## Fail-closed coverage

Acceptance covers at least:

- event replay / duplicate event ownership;
- stale pre-event source frontier;
- incorrect post-event source revision;
- undeclared part inventory change;
- undeclared second bond mutation;
- wrong broken bond;
- event outside the D FULL region;
- invalid D plan binding;
- component ownership overlap or omission;
- component below safe re-bake size;
- failed A/B recompile;
- failed guard/artifact construction;
- stale artifact execution.

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
33370961820

artifact id:
9750024058

artifact:
fabric-bake-b0-2-e-exact-source-91a2f79b

artifact digest:
sha256:b26d0f49c6a5e0235c5d8e235c274ee201437154158fe78f23646426b69872c4

tracked archive SHA-256:
d700bd6212913693c4d48e02db08a0fa7bde46013642ee5b75f479aaa19c07fc

tracked files:
5064
```

Two independent fresh filesystem extractions, each with a fresh import, produced:

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
B0.2-E Acceptance     PASS (2580)
B0.2-E Playground     PASS
```

Both E summary lines were byte-identical.

Post-run tracked-byte audit in both trees:

```text
checked=5064
missing=0
changed=0
```

Windows remains `PASS_BY_POLICY / NON-GATING`.

## Scope / non-claims

B0.2-E and B0.2 overall close only the current certified R1 structural domain.

They do not claim:

- production readiness;
- arbitrary cyclic/redundant guard load inference;
- arbitrary simultaneous multi-region unbake;
- generic fracture/damage constitutive physics;
- contact/wrench bake;
- distributed cross-authority bake.

## Result

```text
B0.2-E:
RESEARCH SLICE CLOSED
EXACT-HEAD DOUBLE PASS

B0.2:
RESEARCH CHECKPOINT CLOSED

next roadmap gate:
BRIDGE-1 — Physical source lifecycle + bake reconstruction
```
