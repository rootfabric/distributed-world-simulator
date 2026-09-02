# FABRIC0.15 — MULTIBODY CONVEX COMPLEMENTARITY GRAPH

**Статус:** research-only successor к FABRIC0.14.  
**Parent research head:** `e4962f067722008ac90993ba648a6f9d2a84f9ec`.  
**Exact executable commit:** `a8ff0d7360b4bba0f1b3e164f8c040d73622b1ee`.

## 1. Главный falsification wall

FABRIC0.14 закрыл local rigid-body wall:

```text
full 6DOF body
+
anisotropic inertia
+
unilateral normal contact
+
Coulomb stick / slide / separation
+
explicit impacts
+
feature topology
+
energy / momentum audits
```

Но всё ещё оставался fundamental question:

> Что произойдёт, когда несколько **свободных 6DOF тел** одновременно делят одни и те же contact constraints, так что impulse одного contact меняет residual другого contact?

FABRIC0.15 переводит nonsmooth mechanics из local-contact формы в **coupled contact graph**.

Главный объект checkpoint:

```text
many rigid bodies
+
many simultaneous contacts
+
shared body velocities
+
projected complementarity iterations
+
dynamic island merge / split
```

---

## 2. Multibody state

Accepted stand содержит четыре dynamic bodies:

```text
A
B
C
D
```

Каждое body имеет:

```text
position       3
quaternion     4
linear v       3
angular omega  3
anisotropic inertia
```

Основной numerical state therefore содержит:

```text
4 × 13 = 52 components
```

FABRIC0.15 не возвращается к point-mass simplification.

---

## 3. Research convex geometry scope

Текущий minimal convex family:

- dynamic bodies represented by spheres/balls;
- analytic plane support;
- sphere-plane contact;
- sphere-sphere contact.

Это deliberately simple convex geometry, чтобы falsify **graph complementarity**, а не одновременно смешивать его с GJK/EPA implementation risk.

Следовательно:

> FABRIC0.15 доказывает coupled convex contact graph на sphere/plane family. Он не заявляет arbitrary convex polytope collision.

General convex support mapping / GJK / EPA остаются следующим wall.

---

## 4. Initial graph

Initial stable support stack:

```text
plane
  ↕
  A
  ↕
  B
  ↕
  C
```

Body D initially free.

Dynamic components:

```text
[A,B,C]
+
[D]
```

Contacts in the persistent stack:

```text
plane|A
A|B
B|C
```

D has 3D linear and angular velocity and falls onto C.

---

## 5. Coupled contact block

Each contact owns a projected impulse block:

```text
Pn  ∈ R
Pt  ∈ R²
```

with:

```text
Pn >= 0
```

and Coulomb disk:

```text
|Pt| <= mu * Pn
```

The contact-space solve applies impulses directly to shared body velocities.

Therefore solving one block changes the residual seen by neighboring blocks.

For example:

```text
B|C impulse
→ changes B and C velocities
→ changes A|B and C|D contact velocities
```

This is the key distinction between FABRIC0.15 and several independent local contact probes.

---

## 6. Projected block Gauss-Seidel

Research solver uses projected block Gauss-Seidel.

For every iteration and every contact block:

1. compute relative contact velocity;
2. solve/update normal impulse;
3. project normal impulse onto `Pn >= 0`;
4. recompute relative velocity;
5. solve a 2D tangent update;
6. project tangent impulse onto Coulomb disk;
7. apply the impulse delta immediately to involved bodies;
8. continue to next block using the updated shared state.

Canonical forward contact order is deterministic.

Accepted solver budget:

```text
32 iterations / contact solve
```

This is a research PGS backend, not a globally certified MCP/NCP solve.

---

## 7. Coupled normal-chain falsification

A dedicated analytic probe removes lateral complexity and applies one gravity impulse over:

```text
dt = 1/240 s
```

For masses in the A/B/C stack, expected normal impulses are:

```text
B|C:
mC g dt
=
0.0367875

A|B:
(mB + mC) g dt
=
0.08379375

plane|A:
(mA + mB + mC) g dt
=
0.12466875
```

Solved values:

```text
B|C
0.03678437280127

A|B
0.08378662693623

plane|A
0.12466162693623
```

Maximum normal-velocity violation:

```text
3.47466525e-6
```

Coulomb cone violation:

```text
0
```

This directly demonstrates load propagation through the coupled graph.

---

## 8. Mixed friction in one island

A separate probe deliberately creates different tangential requirements inside the same support island.

Solved modes:

```text
plane|A
stick

A|B
stick

B|C
slide
```

For sliding `B|C`:

```text
Pn =
0.03678437280127

|Pt| =
0.01250668675243
```

and:

```text
|Pt| = mu * Pn
```

within acceptance tolerance.

Thus one coupled graph can simultaneously contain stick and slide blocks.

Mode is solved per relation, not selected by a device class.

---

## 9. Dynamic island merge

Free D approaches the top of the existing support stack.

New relation:

`C|D`.

Accepted main run:

```text
dt =
0.001

merge time =
0.18299031095859
```

Appearing contact:

```text
mode =
stick

normal impulse =
0.59227588215158

tangent impulse =
(
 -0.00467806420921,
 -0.03987303859427
)
```

Graph mutation:

```text
[A,B,C] + [D]
        ↓
[A,B,C,D]
```

The new body joins an already constrained contact graph instead of creating an isolated local solve.

---

## 10. Why the final merge scenario is vertical

Early falsification prototypes used D as a lateral incoming body.

That produced many events, but also physically displaced A sideways and naturally destroyed A-B-C support contacts.

The solver was not necessarily wrong; the geometry made it impossible to isolate graph merge/hold semantics.

The final stand instead lets D fall vertically onto C with modest tangential velocity/rotation.

Gravity then naturally maintains compressive support.

This is a research-design lesson:

> A falsification scenario should isolate the architecture property under test. Extra dramatic events are not automatically stronger evidence.

---

## 11. Timestep-dependent hold finding

An earlier candidate appeared to hold the newly created contact at coarse timesteps but separated almost immediately under refinement.

That means:

```text
merge -> hold
```

was not physically robust.

The checkpoint was not accepted in that form.

The scenario and event handling were changed until the contact remained physically compressive under the finer reference.

This is another application of the FABRIC refinement rule:

> A topology narrative that disappears under timestep refinement is not accepted physical evidence.

---

## 12. New-contact penetration / Baumgarte finding

Another intermediate implementation detected a new contact only after discrete penetration.

At finer step:

```text
penetration
→ Baumgarte bias
→ positive separating velocity
→ just-created contact disappears
```

This created a timestep-dependent contact lifetime.

The accepted semantics separates configuration localization from physical impulse.

---

## 13. Configuration-only contact localization

When a new relation is detected with negative gap:

```text
gap < 0
```

the configuration is first moved to:

```text
gap = 0
```

without changing velocity.

For body-body contact, the positional correction is distributed by inverse mass.

This operation is explicitly classified as:

```text
event localization correction
```

not a physical impulse.

It records:

```text
projection_distance
projection_energy_delta
```

Accepted `dt=0.001` run:

```text
projection distance =
1.911595595e-5

projection energy delta =
0
```

Important contrast with FABRIC0.14:

```text
FABRIC0.14:
velocity projection changed momentum
→ hidden physical impulse
→ had to become explicit jump

FABRIC0.15:
configuration correction changes no momentum
→ numerical event localization
```

No claim is made that projection distance decreases monotonically under the current fixed-step refinement family.

---

## 14. Hold after merge

After C|D appears, gravity keeps the contact compressive.

The accepted causal graph remains:

```text
[A,B,C,D]
```

until the explicit source transition.

This was checked across the accepted refinement family instead of relying on a coarse-step artifact.

---

## 15. Explicit source change

At:

```text
t =
0.32
```

the research stand changes an external source acting on D:

```text
drive:D

old force =
(0,0,0)

new force =
(0,0,12)
```

This source event is exact and intentionally external.

The purpose is to test whether the coupled unilateral graph correctly releases a relation after the loading changes.

---

## 16. Complementarity separation

After the source transition, C|D reaches:

```text
normal impulse ~ 0
+
separating normal velocity > 0
```

The active set therefore removes C|D.

Event:

```text
CONTACT_DISAPPEAR

reason =
COMPLEMENTARITY_SEPARATION

time =
0.32
```

The graph becomes:

```text
[A,B,C,D]
        ↓
[A,B,C] + [D]
```

This demonstrates island split from unilateral active-set semantics.

The split trigger is not a fixed arbitrary gap timeout.

---

## 17. Fixed-step refinement

FABRIC0.15 currently uses fixed-step refinement, not an adaptive error-controlled integrator.

Reference:

```text
dt =
0.0005
```

Reference merge time:

```text
0.18321697505484
```

Split remains exactly:

```text
0.32
```

because it is tied to the exact source event and complementarity release.

Tested steps:

```text
0.004
0.002
0.001
```

---

## 18. Merge-time convergence

Maximum merge-time error against reference:

```text
0.004
1.5902247457270924e-3

0.002
6.811752040176144e-4

0.001
2.2666409624433337e-4
```

Strictly decreasing.

---

## 19. Full 52D state convergence

Maximum component error across all four body states:

```text
0.004
4.257633804026106e-3

0.002
1.8033092993312572e-3

0.001
7.327864068812362e-4
```

Strictly decreasing.

This is whole-graph state convergence, not merely one contact residual.

---

## 20. Energy-ledger refinement

The research ledger contains:

- mechanical energy delta;
- external source work;
- contact kinetic dissipation;
- contact kinetic gain if any;
- configuration-localization energy delta.

Residual:

```text
|delta_E
 - external_work
 - (-contact_dissipation + contact_gain)
 - projection_energy_delta|
```

Accepted refinement residuals:

```text
0.004
0.1863040594936023

0.002
0.09295272462256121

0.001
0.047009019436045296
```

Strictly decreasing.

This is first-order research evidence, not a structure-preserving production integrator.

---

## 21. Main dt=0.001 trajectory

Duration:

```text
0.4 s
```

Contact work:

```text
contact solves =
403

PGS iterations =
12896
```

Constraint audits:

```text
max normal velocity violation =
1.634842214e-4

max cone violation =
0

max penetration =
4.72630019e-6
```

Energy quantities:

```text
contact dissipation =
0.65570895032957

contact gain =
0

external work =
1.13448578288811

projection energy delta =
0

energy delta =
0.52578585199459

ledger residual =
0.04700901943605
```

Main physical state hash:

`68e18b6a9a16b574aaf0b6ca30b3cf5160ea9a69ba8919df11f1b04fda92d29c`.

---

## 22. Internal pair momentum audit

Every body-body impulse is internal to the dynamic system.

The implementation measures total momentum before/after pair impulse application.

Accepted maxima:

```text
internal linear momentum error =
0

internal angular momentum error =
0
```

Plane-body impulses are classified as external and are not incorrectly included in the internal-pair conservation claim.

---

## 23. PGS contact-order robustness

Projected Gauss-Seidel is order-sensitive at finite iteration count.

The checkpoint therefore does **not** claim exact contact-order independence.

A forward/reverse block-order probe after 32 iterations gives:

```text
max delta linear velocity =
1.8593214664426525e-6

max delta angular velocity =
2.1323642847629e-7
```

The important current claim is:

```text
same solved modes
+
small finite-iteration state difference
```

not bit-exact equality.

A future globally converged MCP/NCP solver should strengthen this boundary.

---

## 24. Dynamic stick / slide evidence

The main contact graph records mode transitions.

Accepted history includes:

- slide states;
- later slide -> stick transitions;
- newly appearing C|D contact in stick mode.

Thus the graph contains dynamic friction-state evolution, although the checkpoint does not yet localize stick/slide transitions with the same root-finding rigor as contact appearance/separation.

---

## 25. Actual Thread audit

Two actual Godot Threads execute independent contact graph snapshots.

Canonical joined hash:

`49e8c7b2fa0e1177f0e19d36ee85c4e22239ad95556c2c0a7c909d24fb47b34b`.

Reversing thread spawn order yields the exact same canonical hash.

The audit does not mutate the original physical world hash.

This remains snapshot-level parallel evidence, not a production same-world contact scheduler.

---

## 26. Deterministic replay

A fresh main `dt=0.001` run reproduces:

- exact state hash;
- exact event JSON;
- exact graph-event JSON.

Physical hash:

`68e18b6a9a16b574aaf0b6ca30b3cf5160ea9a69ba8919df11f1b04fda92d29c`.

---

## 27. Exact runtime validation

Exact Godot:

`4.7.1.stable.double.custom_build.a13da4feb`.

FABRIC0.15 focused acceptance:

```text
PASS
103/103 assertions
```

Playground:

`FABRIC0_15_MULTIBODY_CONVEX_COMPLEMENTARITY_GRAPH_PLAYGROUND_PASS`.

Editor parse/compile/SCRIPT scan:

`CLEAN`.

---

## 28. Real predecessor regression

On the same exact-double engine:

```text
FABRIC0.14 Full 6DOF Frictional Feature Manifold Acceptance:
PASS
156/156
```

All seven FABRIC0.14 executable blobs remain unchanged.

Therefore FABRIC0.15 has both:

```text
predecessor runtime PASS
+
predecessor byte preservation PASS
```

---

## 29. Exact executable byte identity

SHA-256:

```text
model
329fe422a519c87cd43b2c43e30eb911e66069593f9334e9ead4400b59e5e320

complementarity
437baa63df7cd8472721d0225f6784cb7403d8ffd2ca1f48e3298dfc7e5fcfde

driver
170ea1f66534f83c92f5ee4b654f9ffeaf61e45017b3652af215555269932679

facade
3ee576134e840faac0eca17301369f28e5ec3c3248da3c99b3ea380ca80657ab

experiments
413f05f1cd734a23def05da6c5808347b03a710e0e6033bc4615190e59f9b689

acceptance
6203f521fdbc448acb4f5a0d9cdb0a970c34360cf0718ca09217bb6516ce687d

playground
4c2591a3ebd86169c7b44c4d295e5eae3c0a5cffd3da9c1a71e10bbd9cc5d9f5
```

Git blobs:

```text
model
ef5b08656e6b747b62edbf973fddd2dfb3cece70

complementarity
e9a731afefa0d86254ab8fec3b1bcfb0482192c3

driver
7bcd1402ace822ee29f30d9f10c0b192c0c2abaf

facade
60b4ca92c856d6b6aa63b185c25a5ff5aaa62bcd

experiments
7a5d8a7a94311a5d613b495c1976c8f4f15a23c1

acceptance
5dd08bff21449615113f5890b795ca7420adc302

playground
db94890564626ea0921e2bf5f73e49053c83a1a6
```

All seven GitHub branch blobs were re-fetched after commit and verified exact-equal to local `git hash-object`.

---

## 30. What FABRIC0.15 proves

The checkpoint demonstrates:

- four simultaneously dynamic 6DOF bodies;
- a 52-component whole-system physical state;
- an existing three-body support contact graph;
- a free body merging into that graph;
- projected normal complementarity over shared body velocities;
- projected 2D Coulomb tangent blocks;
- simultaneous stick and slide contacts in one coupled island;
- analytic load propagation through a coupled normal chain;
- a newly appearing body-body contact with normal+tangent impulse;
- island merge `[A,B,C]+[D] -> [A,B,C,D]`;
- contact hold under compressive loading;
- source-driven complementarity separation;
- island split `[A,B,C,D] -> [A,B,C]+[D]`;
- configuration-only gap localization without momentum change;
- fixed-step convergence of merge time, full 52D state and energy ledger;
- exact internal body-body linear/angular momentum audit in the demonstrated impulse application;
- small finite-iteration forward/reverse PGS order difference with same modes;
- dynamic friction mode history;
- deterministic replay;
- actual two-thread snapshot solve with canonical join;
- exact remote/local byte identity for all seven successor files;
- real FABRIC0.14 runtime regression.

---

## 31. What FABRIC0.15 does NOT prove

Open walls:

- arbitrary convex polytope collision;
- GJK/EPA;
- mesh collision;
- true multipoint face contact manifold;
- graph-wide globally converged MCP/NCP solve;
- exact contact-order independence;
- block-sparse/CSR production backend;
- adaptive error-controlled time integration;
- exact simultaneous multi-impact localization;
- autonomous stick/slide event localization with root finding;
- fully autonomous split family without an explicit source change in the main accepted trajectory;
- rolling friction;
- torsional friction;
- production broadphase;
- production same-world thread pool/work stealing;
- Construction/authority/persistence/replication integration;
- full materialized DWS regression.

---

## 32. Next falsification wall

### FABRIC0.16 — GENERAL CONVEX MULTIPOINT MCP

Target:

```text
arbitrary convex support mapping
+
GJK / EPA
+
persistent multipoint manifold
+
normal complementarity over manifold points
+
coupled tangent cones
+
globally converged MCP/NCP or semismooth solve
+
adaptive contact/separation/stick-slide localization
+
same-world parallel islands
+
broadphase
+
refinement / momentum / energy evidence
```

The critical step is no longer “more bodies”.

It is replacing the deliberately simple sphere contact family and finite-iteration PGS with a general convex multipoint nonsmooth solve.

---

## 33. Architectural conclusion

FABRIC0.15 changes the research object from:

```text
one rigid body + local contact law
```

to:

```text
persistent multibody contact graph
+
shared 6DOF state
+
graph-coupled complementarity blocks
+
dynamic connected components
+
causal merge/split history
```

The current physics grammar now spans:

```text
Construction semantic truth
        ↓
physical bodies / relations
        ↓
contact graph
        ↓
coupled nonsmooth solve
        ↓
active-set topology mutation
        ↓
island merge / split
        ↓
canonical causal history
```

Construction remains canonical semantic owner.

FABRIC remains a research physical execution substrate, not a second world-truth authority.
