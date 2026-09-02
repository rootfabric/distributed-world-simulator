# FABRIC0.13 — UNIFIED ADAPTIVE 3D CONTACT GRAPH

**Статус:** research-only successor к FABRIC0.12.  
**Parent research head:** `fdcd3f5dc18a5f62a6335c954ddca794d0d79f21`.

## 1. Зачем понадобился FABRIC0.13

До этого FABRIC разделился на две сильные, но частично независимые линии.

### Persistent sparse contact graph

FABRIC0.9–0.11 дали:

```text
geometric contacts
→ persistent relation identities
→ contact islands
→ warm state
→ event-time island merge
→ sparse PCG
```

### Adaptive manifold semantics

FABRIC0.12 дал:

```text
adaptive error-controlled flow
→ several physical events per macro interval
→ same-time manifold fixed point
→ feature lineage
→ split/merge warm remap
→ actual Thread execution
→ refinement convergence
```

Но FABRIC0.12 был intentionally reduced orientation-aware corner DAE.

Главный falsification wall:

> Можно ли перенести adaptive multi-event / lineage / parallel semantics обратно в persistent sparse contact graph, не потеряв convergence, constraint solve и deterministic causal history?

FABRIC0.13 отвечает: **да на unified research stand**.

---

## 2. Unified stand

Мир содержит persistent support stack:

```text
B
↕ pair:A|B
A
↕ floor
```

и свободное body C:

- масса 1;
- начальная vertical position `2.8`;
- начальная vertical velocity `-3`;
- начальная orientation `theta=-0.25 rad`;
- angular velocity `+1`.

Body C имеет box half-extents:

```text
hx = 0.35
hy = 0.40
hz = 0.30
```

В `0.7 s` adaptive advance происходят:

1. impact C into persistent A/B support graph;
2. first rocking manifold transition;
3. reverse rocking manifold transition.

То есть один execution path объединяет:

```text
persistent graph
+
adaptive flow
+
impact-time graph merge
+
orientation-aware multipoint manifold
+
feature lineage
+
same-time topology fixed point
+
sparse PCG
+
actual parallel island audit
```

---

## 3. State model

Research state vector:

```text
[
  zA,
  zB,
  zC,
  theta,
  vA,
  vB,
  vC,
  omega
]
```

A/B remain support bodies in the demonstrated vertical contact chain.

C carries:

- vertical translation;
- rotational coordinate `theta`;
- angular velocity `omega`.

Orientation is exposed as normalized 3D quaternion:

```text
Quaternion(Vector3.RIGHT, theta)
```

Important scope:

> Quaternion representation exists, but the demonstrated motion excites one rotational axis only. FABRIC0.13 is not yet a general arbitrary-axis 6DOF rigid-body proof.

---

## 4. Contact graph before impact

Before C touches B:

```text
contacts:

floor|A
pair:A|B

island:

[A,B]

C = free
```

Persistent support reactions are already active.

At initial exact solve:

```text
floor|A = 19.62

pair:A|B = 9.81
```

These reactions are numerical state/hints associated with persistent relations.

---

## 5. Impact event

First event:

```text
t =
0.12770032218309
```

Appears:

`pair:B|C|edge:back_bottom`.

Graph mutation:

```text
[A,B]
    ↓
[A,B,C]
```

Old relations persist:

```text
floor|A
pair:A|B
```

Acceptance explicitly verifies that their pre-impact reaction values are retained across graph merge:

```text
floor|A = 19.62

pair:A|B = 9.81
```

The impact path therefore does not destroy numerical continuity of the already constrained support graph.

---

## 6. Orientation-aware multipoint feature manifold

For C, support contact feature depends on rocking orientation.

Negative side:

```text
edge:back_bottom
lineage = [BBL, BBR]
point_count = 2
```

At exact zero orientation:

```text
face:bottom
lineage = [BBL, BBR, BFL, BFR]
point_count = 4
```

Positive side:

```text
edge:front_bottom
lineage = [BFL, BFR]
point_count = 2
```

This creates a true multipoint feature topology transition:

```text
2-point edge
→
4-point face
→
2-point opposite edge
```

---

## 7. Same-time manifold fixed point

First rocking event:

```text
t =
0.15171711003539
```

Transitions:

```text
pair:B|C|edge:back_bottom
→
pair:B|C|face:bottom
→
pair:B|C|edge:front_bottom
```

Second rocking event:

```text
t =
0.58519759521384
```

Transitions:

```text
pair:B|C|edge:front_bottom
→
pair:B|C|face:bottom
→
pair:B|C|edge:back_bottom
```

Each physical event reports:

```text
iterations = 3
topology_mutations = 2
fixed_point = true
```

So the unified graph now performs multi-mutation same-time topology transactions inside adaptive flow.

---

## 8. Feature-lineage warm remap

Warm force and impulse are remapped through feature ancestry.

First rocking event:

```text
force:
3.19540765718406
→
3.19540765718406

impulse:
2.79582739473921
→
2.79582739473921
```

Second rocking event:

```text
force:
6.37715467034077
→
6.37715467034077

impulse:
2.30680300608927
→
2.30680300608927
```

The exact contact relation string changes.

Continuity instead follows geometric lineage:

```text
edge ancestry
→ face ancestry
→ opposite edge ancestry
```

This is the 0.12 lineage principle integrated into a persistent contact graph.

---

## 9. Contact acceleration constraint

For each active constraint:

```text
A =
J M^-1 J^T
```

and:

```text
A lambda =
rhs
```

Then:

```text
qdd =
a_free
+
M^-1 J^T lambda
```

For rocking C contact row:

```text
J =
[0, -1, +1, dr/dtheta]
```

Thus reaction couples B translation, C translation and C rotation.

Curvature acceleration term:

```text
gamma =
d2r/dtheta2 * omega^2
```

is included in the acceleration constraint.

Therefore rotation participates directly in physical contact equations.

---

## 10. Constraint stabilization

Current research successor uses position/velocity stabilization in acceleration RHS:

```text
400 * gap
+
40 * constraint_velocity
```

This is numerical policy.

It is not a new semantic world law.

The checkpoint proves the integrated architecture with this policy, not universal optimal stabilization.

---

## 11. Sparse PCG in adaptive trajectory

Effective constraint matrix remains sparse research dictionaries.

PCG is used both for:

- reaction acceleration solve;
- velocity projection during topology jump.

Main `1e-9` run:

```text
PCG calls       = 38
PCG iterations  = 95

pattern hits     = 36
pattern misses   = 2
```

Maximum tested constraint residual:

```text
~ 1e-14
```

Acceptance bound:

`<= 2e-14`.

---

## 12. Pattern cache survives adaptive flow

Pattern cache is keyed by sparse structural pattern.

During main adaptive run:

```text
misses = 2
hits   = 36
```

The graph crosses multiple physical events and feature IDs.

Numerical structural reuse remains separate from physical relation identity.

---

## 13. Final support reactions

At the end of the main `1e-9` run:

```text
floor|A =
26.5710523718944

pair:A|B =
16.7610523718944

pair:B|C|edge:back_bottom =
6.95105237189441
```

Minimum observed demonstrated contact force remains:

`> 2.9`.

This research path therefore does not rely on a negative normal-force artifact in the accepted trajectory.

---

## 14. Adaptive convergence on the unified graph

This is the critical FABRIC0.13 gate.

An ultra run:

`tol = 1e-12`

is used as high-accuracy numerical reference.

Compared runs:

```text
1e-7
1e-9
1e-11
```

Maximum error across all three event times:

```text
1e-7:
8.034517395838492e-8

1e-9:
3.1108455811335034e-9

1e-11:
5.63820101717738e-11
```

Strictly decreasing:

```text
8.03e-8
↓
3.11e-9
↓
5.64e-11
```

---

## 15. Final-state convergence

Maximum state-vector error against the `1e-12` reference:

```text
1e-7:
6.4536567821738e-7

1e-9:
2.6241198575194247e-8

1e-11:
4.793412056169899e-10
```

Again strictly decreasing.

This is stronger than checking event timestamps alone.

The unified physical state itself converges under numerical refinement.

---

## 16. Main 1e-9 state

At `t=0.7`:

```text
[
  0.5,
  1.5,
  2.31500523792666,
 -0.03806559230923,
  0,
  0,
 -0.03391269895384,
  0.08733783833833
]
```

Contacts:

```text
floor|A
pair:A|B
pair:B|C|edge:back_bottom
```

Free support gap audit:

`<= 1e-12`.

---

## 17. Quaternion audit

Final quaternion:

```text
length =
1.0

x =
-0.01903164707883

y =
0

z =
0

w =
0.99981888180283
```

Normalization acceptance:

`|length-1| <= 1e-14`.

Again:

> This proves orientation representation and contact coupling for the tested one-axis rotational trajectory, not general free rigid-body quaternion integration.

---

## 18. Multiple events restart the adaptive flow

One adaptive call:

`duration = 0.7`.

Causal sequence:

```text
adaptive free/constrained flow
↓
impact event
↓
velocity projection
↓
graph merge
↓
reaction refresh
↓
adaptive constrained flow
↓
manifold fixed point #1
↓
reaction refresh
↓
adaptive constrained flow
↓
manifold fixed point #2
↓
remaining adaptive flow
```

No stale pre-event candidate end state is reused after topology mutation.

---

## 19. Real parallel island audit

After main run, a parallel snapshot solves:

### Main island

```text
[A,B,C]
```

### Independent side island

```text
[D,E]
```

Actual Godot Threads:

`2`.

Main sparse solution:

```text
[
  26.5710523718944,
  16.7610523718944,
   6.95105237189441
]
```

Independent side solution:

```text
[
  19.62,
   9.81
]
```

---

## 20. Reverse thread-spawn invariance

Forward and reverse thread spawn order produce exact canonical hash:

`6ef3fd35474a179a7bf02675d5bde9ecb457f235fdb7cc70f017a69757f92757`.

Physical world hash is unchanged by the parallel audit.

Therefore thread work is observation/numerical execution, not a hidden mutation of canonical physical state.

---

## 21. Derived sleep/wake remains noncanonical

As in 0.12:

- first two quiet updates: awake;
- third quiet update: sleeping;
- motion: wake.

Sleep tracker does not alter world hash.

Thus:

```text
sleep/wake
=
derived computational scheduling state
```

not physical ownership.

---

## 22. Deterministic replay

A fresh `1e-9` run reproduces:

- all three event timestamps;
- exact event records JSON;
- final physical state hash.

State hash:

`f486303b7f133d28148d63362ad368d82e946132f2a12f9c164ae5edc2819483`.

---

## 23. Exact validation

Runtime re-extracted from the user-provided archive:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Focused acceptance:

`95/95 PASS`.

Exact acceptance line:

```text
FABRIC0.13 Unified Adaptive 3D Contact Graph Acceptance:
PASS (95 assertions)
```

Main observed event times:

```text
0.127700322183
0.151717110035
0.585197595214
```

Adaptive work:

```text
37 accepted
1 rejected
```

Playground:

`FABRIC0_13_UNIFIED_ADAPTIVE_3D_CONTACT_GRAPH_PLAYGROUND_PASS`.

Editor parse/compile/SCRIPT scan:

`CLEAN`.

---

## 24. Exact executable byte identity

SHA-256:

```text
facade
4e37dd9896c4324e4644f3e85a6dd7c015e895f64b92881d8cec436931094857

model
0c24947e7c70ba8ad23923ac523add979903403eddc5a962745339feab9ff0d8

driver
f3bc5e0a67463b1e55f608fb47c59942894c58b7d2662aa3a4d256df91809c5b

sparse
2f171d768dc2d9ee6b20f64eaddd19ea413c964a42cfe7ea102d836b813e2226

experiments
98ff85f065fa639941f271768fb2e36b311dcc8d2bf5d6fa3c7cae93fe8c48f3

acceptance
2543f7e5c6c038706ae7fdb58253f14cd7c750fc075c453b0af615d96ae6e4ce

playground
636cab2c46564dbefe0598f326a298330f657b91c5e679096c7d70cae0e2096b
```

Git blobs:

```text
facade
2f7e7b393ffc931f69e8f79c9cf156714acf2d04

model
c5c0650b29a732b37539ca1f789e5d72d251592a

driver
6b0b73f8418fc428b866433173c987ab8d2965c8

sparse
cb7f9c86993cecab44b7ac7dbb09f1114eb01f58

experiments
dcf7be2eb80a35f84f81fdde4c384f6a2fc5d028

acceptance
6334a9cb5fc4eff6be1b55da0a288e81ef675ef8

playground
c783dbbc4c6b9b0d319e3431fb69131eecaadf05
```

All seven GitHub branch blobs were verified exact-equal to local `git hash-object`.

Two large files initially differed by one trailing newline during persistence. The branch was corrected and accepted only after exact blob identity passed.

---

## 25. Predecessor preservation

FABRIC0.12 runtime suite was not materialized in the current FABRIC0.13 lab, so a new 0.12 runtime rerun is not claimed.

However all four FABRIC0.12 executable blobs remain unchanged against v12 evidence:

```text
solver
d88c5e3a30284985e6bf66328921280fafe6990f

experiments
fb4fa7a9bad103ec61ca466ede56a5713eb3139b

acceptance
59ab0eb3acb8b9cef668716e730ff859bdb05208

playground
16d535693a7f54d3d8de17f453c38f33b8605491
```

---

## 26. What FABRIC0.13 proves

FABRIC0.13 demonstrates, in one research execution path:

- persistent A/B support relations before a new impact;
- adaptive impact event localization;
- same-time graph merge `[A,B] -> [A,B,C]`;
- preservation of old persistent reaction state through merge;
- orientation-coupled contact Jacobian;
- multipoint contact-feature topology `edge -> face -> opposite edge`;
- two manifold fixed-point events after impact;
- lineage-based warm force/impulse continuity;
- sparse PCG inside the adaptive constrained trajectory;
- sparse pattern-cache reuse across adaptive steps;
- very small tested constraint residual;
- event-time convergence under tolerance refinement;
- final physical-state convergence under refinement;
- normalized quaternion orientation representation;
- deterministic event replay;
- real two-thread independent island solve;
- reverse thread-spawn canonical invariance;
- derived sleep/wake outside physical world hash;
- exact local/GitHub byte identity for all seven executable checkpoint files.

---

## 27. What FABRIC0.13 does NOT prove

The following remain open:

- arbitrary 6DOF rigid-body motion;
- three-axis angular velocity evolution;
- full world/body inertia tensor dynamics;
- general quaternion differential integration;
- arbitrary convex/mesh collision manifold;
- production robust feature matching under floating geometry noise;
- tangential Coulomb cone integrated into this adaptive multipoint successor;
- general unilateral contact separation/complementarity on every row;
- arbitrary simultaneous multi-body impacts;
- general MCP/NCP multi-event fixed point;
- arbitrary contact graph split after separation;
- conservative remap for every dual/numerical quantity type;
- CSR/CSC sparse backend;
- production thread pool/work stealing;
- production sleep/wake;
- broadphase;
- production Construction/authority/persistence/replication integration;
- full materialized DWS regression.

A/B support coordinates are also partially algebraically projected in this research stand. This is useful for isolating unified event/manifold semantics, but it is not a full free 6DOF rigid-body world.

---

## 28. Next falsification wall

### FABRIC0.14 — FULL 6DOF FRICTIONAL FEATURE MANIFOLD

Next checkpoint should now remove the biggest remaining physical simplifications:

```text
full translational 3DOF
+
full rotational 3DOF
+
quaternion differential update
+
body/world inertia tensor
+
normal unilateral complementarity
+
tangential Coulomb cones
+
persistent convex feature manifold
+
adaptive multi-event fixed point
+
feature lineage
+
sparse parallel islands
```

Critical experiment:

```text
persistent multi-body support
+
freely tumbling convex body
+
oblique impact
+
sliding / sticking friction
+
several contact features appearing/disappearing
+
island merge/split

with:

refinement convergence
+
energy/momentum/reaction audits
+
lineage warm remap
+
parallel-order invariance
```

---

## 29. Architectural conclusion

FABRIC0.13 is the first checkpoint where the two previously separate research lines actually meet:

```text
persistent physical relation graph
+
adaptive hybrid event time
+
multipoint feature lineage
+
sparse numerical execution
+
parallel deterministic boundary
```

The durable form is now:

```text
semantic Construction truth
        ↓
persistent FABRIC physical relation graph
        ↓
adaptive constrained flow
        ↓
event-time topology transaction
        ↓
feature-lineage manifold fixed point
        ↓
sparse parallel numerical solve
        ↓
causal physical history
```

Construction remains canonical semantic owner.

FABRIC remains a research physical execution substrate, not a second source of semantic truth.
