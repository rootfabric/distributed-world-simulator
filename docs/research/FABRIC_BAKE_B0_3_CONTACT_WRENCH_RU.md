# FABRIC-BAKE B0.3 — CONTACT / WRENCH BAKE

**Статус:** **RESEARCH CHECKPOINT CLOSED / EXACT DOUBLE PASS / PROJECT CONTROL PASS / NOT PRODUCTION ACCEPTED**.

## 1. Frozen predecessors

```text
BRIDGE-1 closure:
82a44ac8f6e362456cb2f8c150145e73afb17157

FABRIC0.18 research closure:
b9f4a11cb7c31e47884d12eaad2985811e0b6563

FABRIC0.18 exact physical executable:
e079565b4b9cd0dae530ff5042f057ce8fa0d0cc
```

B0.3 не переносит canonical ownership из Construction / Matter и не делает FABRIC contact history канонической истиной.

## 2. Exact executable boundary

```text
branch:
research/fabric-bake0-3-contact-wrench-r1

HEAD:
acc72c1fb216bea56bc44547bc3e1eec7a37af08

TREE:
f8247e39494c00d2d065ed4c4b121e103f32ab0a

Project Control:
#1928
run id 33399124353
SUCCESS
```

## 3. Accepted reduction

Accepted initial domain:

```text
COPLANAR
UNIFORM CONTACT PARAMETERS
PERSISTENT WRENCH PATCH
SHARED NORMAL SUPPORT BUDGET
```

Reduction:

```text
441 manifold members
        ↓
convex support hull
        ↓
4 extreme generators

reduction ratio:
110.25x
```

The reduced model preserves the 6D boundary admissible wrench support function

```text
W = (Fx, Fy, Fz, Mx, My, Mz)
```

rather than preserving an arbitrary redundant pointwise lambda split.

For a linear support query over the accepted convex patch, interior contact points cannot exceed the support value attained by an extreme point. This is the exact initial B0.3 reduction claim.

## 4. Exact acceptance

Pinned engine:

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Focused result:

```text
B0.3 Contact/Wrench Bake:
319/319 PASS

Playground:
PASS

model:
95554e75f2dc485cfacdbe59c8a0d64c5c81f4878e041bc8c562a9e5e3f5662e

FULL-vs-BAKED max support error:
0

max support witness projection error:
1.4210854715202004e-14

max observed passive contact power:
-6.0351378875996975
```

Fresh deterministic passes reproduced the same acceptance summary and model identity.

## 5. Boundary behavior

B0.3 explicitly represents:

- normal support;
- friction force limits;
- tipping moments;
- rolling resistance moments;
- torsional resistance;
- 6D maximum-dissipation wrench;
- support loss;
- directional wrench capacity exit.

Falsifiers include:

```text
non-coplanar patch
→ NO_SAFE_BAKE

degenerate support polygon
→ NO_SAFE_BAKE

insufficient reduction
→ NO_SAFE_BAKE

invalid provenance / frame / model hash
→ FAIL CLOSED

support → 0
→ SUPPORT_TO_SEPARATION

directional demand > admissible support
→ WRENCH_CAPACITY_EXIT
→ refinement required
```

## 6. Transient contact truth boundary

The artifact explicitly rejects persistence of:

```text
internal lambda split
accepted generalized impulse
warm-start proposal
contact age
stick/slide/roll/spin history
```

Reconstruction policy:

```text
DISCARD_AND_REDERIVE_CONTACT_STATE
```

These values remain solver-assist / derived runtime state.

## 7. B0.0 / BRIDGE-1 lifecycle integration

`contact_wrench_bake_bridge_v1.gd` builds the contact model as the reduced-model descriptor of a normal B0.0 `PhysicalBakeArtifact`.

The binding carries:

- canonical source frontier;
- authority envelope;
- dependency set;
- physical graph hash/compiler version;
- physical boundary contract;
- validated domain;
- error/conservation envelopes;
- reconstruction descriptor;
- state mapping;
- bake policy.

Execution requires the parent BRIDGE-1 gate and the B0.3 artifact gate. B0.3 therefore does not create a parallel source revision, authority or stale-execution universe.

## 8. Exact bytes

```text
contact_wrench_bake_compiler_v1.gd
git blob 5dac75ea7473d595795eea98b4ad379d2b3a0928
sha256   31e8a1a44a3c260c14936b6641e2451f640e6aff5840566d87016bda180b1530

contact_wrench_bake_runtime_v1.gd
git blob 5d71baf606bf782cbe897ab686045daea584e53a
sha256   699e5d3c94da9c5c89c8c8bd62701ae16711aa5c913d5d94321c41a358aad008

contact_wrench_bake_bridge_v1.gd
git blob e6366a66f2e4e38f4883506ce3f128d26ca548f0
sha256   6cf975a351283170b7c1c31bcb49c9353eb8e2643a5182ee4f3feabba59461bf

fabric_bake_b0_3_acceptance.gd
git blob 663e6a800a6058e6b64d2bae2118306d1ac2ef42
sha256   0e0ef8fb73746437d11f100acc1c0c947dd8f96485540bab457c9b281f6140f9

fabric_bake_b0_3_playground.gd
git blob e305b06310f43926d03cb92088d25ec3359f895a
sha256   fe6918f2be443eb34bc1c1ba261b8ebd3d41f410f4a4b606467cfe7ef8051f60

RUN_FABRIC_BAKE_B0_3_TESTS.sh
git blob 527e73740aeea421c2ae5be3da0ef21061bf56f6
sha256   6ceed3acbb7ddf679d8745cc5894244f1ab37f3c447ae9e47aa6adada36814ec
```

Remote byte audit is 6/6 exact. The six imported FABRIC0.18 runtime predecessor blobs are also exact.

## 9. Non-claims

B0.3 does not claim:

- arbitrary non-coplanar pressure/contact reduction;
- pressure-distribution PDE or compliant/Hertz contact;
- persistence of internal contact reactions as truth;
- cross-authority mutable contact bake;
- production solver readiness;
- production acceptance.

The next roadmap stage after formal B0.3 closure is B0.4 Dynamic ROM and B0.5 Hybrid Bake research, converging later at BRIDGE-2.


## 10. Closure boundary

```text
exact executable HEAD:
acc72c1fb216bea56bc44547bc3e1eec7a37af08

exact executable TREE:
f8247e39494c00d2d065ed4c4b121e103f32ab0a

executable Project Control:
#1928
run id 33399124353
SUCCESS

evidence carrier:
c303b5c44621cae1dd073b12aef2de037fec8a74

evidence Project Control:
#1930
run id 33399573089
SUCCESS
```

Closure commits after the executable boundary change only documentation/validation evidence. Runtime and test bytes remain frozen at the exact executable HEAD.

Final qualification:

```text
FABRIC-BAKE B0.3
CONTACT / WRENCH BAKE

RESEARCH CHECKPOINT CLOSED
EXACT DOUBLE PASS
REMOTE BYTE AUDIT PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```
