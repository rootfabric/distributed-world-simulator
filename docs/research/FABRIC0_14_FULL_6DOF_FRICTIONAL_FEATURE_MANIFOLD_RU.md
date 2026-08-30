# FABRIC0.14 — FULL 6DOF FRICTIONAL FEATURE MANIFOLD

**Статус:** research-only successor к FABRIC0.13.  
**Parent research head:** `1b4be82a4b092acbddcc4445444104c079293f91`.  
**Exact-tested implementation head before documentation:** `afe5e417d9787e082fecce8a635001f363417a48`.

## 1. Главный falsification wall

FABRIC0.13 впервые объединил:

```text
persistent contact graph
+
adaptive multi-event manifold
+
orientation-sensitive reaction
+
sparse/parallel numerical execution
```

Но physical state оставался reduced:

- one-axis rotational trajectory in the accepted stand;
- no full 3-axis angular velocity/inertia tensor evolution;
- no unified Coulomb stick/slide law in the adaptive successor;
- no explicit unilateral separation branch in that same path;
- feature transitions still lacked a full rigid-body frictional impulse audit.

FABRIC0.14 attacks exactly these remaining physical simplifications.

Research question:

> Может ли один successor одновременно поддерживать free 3DOF translation + free 3DOF rotation, quaternion/inertia tensor dynamics, unilateral normal contact, Coulomb stick/slide/separation, persistent feature lineage, adaptive feature events and explicit momentum/energy accounting — без hidden projection impulses и без device-specific behavior?

Focused exact-double evidence answers **yes for the demonstrated rigid-box/plane research family**.

---

## 2. Full rigid-body state

State vector is 13-dimensional:

```text
position      = 3
quaternion    = 4
linear v      = 3
angular omega = 3
------------------
total         = 13
```

Packing:

```text
[
  px, py, pz,
  qx, qy, qz, qw,
  vx, vy, vz,
  wx, wy, wz
]
```

The body uses anisotropic body-frame inertia:

```text
I_body =
(0.19, 0.31, 0.43)
```

so rotational dynamics cannot collapse into one scalar inertia.

---

## 3. Quaternion + inertia tensor dynamics

World angular momentum:

```text
L =
I_world * omega
```

where application of `I_world` is implemented by transforming the vector into body space, multiplying by diagonal `I_body`, then rotating back into world space.

Angular acceleration:

```text
alpha =
I_world^-1 (
    torque
    -
    omega x (I_world * omega)
)
```

Quaternion differential equation:

```text
q_dot =
0.5 * Omega(omega) * q
```

Each numerical state is normalized before becoming accepted physical state.

This is the first FABRIC checkpoint that explicitly evolves all three components of angular velocity under anisotropic inertia.

---

## 4. Coordinate-system contract

FABRIC0.14 research world is **Z-up**.

Plane normal:

```text
n_world =
(0,0,1)
```

In Godot this is:

`Vector3.BACK`.

### Falsification finding

The first prototype accidentally used:

`Vector3.UP`

which in Godot is:

```text
(0,1,0)
```

That mismatch produced impossible support geometry and artificial energy gain.

Geometry/energy invariants exposed the bug immediately.

The correction is architectural, not cosmetic:

> Coordinate convention must be executable input to physical laws. It cannot remain an implicit convention in the developer's head.

---

## 5. Effective contact mass

For contact point offset `r`, the contact-space velocity response to impulse is assembled into a 3x3 effective mass matrix:

```text
W =
J M^-1 J^T
```

The implementation computes the response to basis impulses in X/Y/Z contact directions.

This makes translational and rotational impulse response coexist in one local contact law.

---

## 6. Unilateral normal semantics

Contact normal law obeys the research contract:

```text
gap >= 0
normal >= 0
gap * normal = 0
```

For active support state, accepted runs maintain approximately zero gap and positive normal force.

If maintaining contact would require tensile normal force:

```text
required normal < 0
```

the solver returns:

```text
active = false
mode   = separated
normal = 0
```

Executable separation probe:

```text
signed required normal =
-4.3165743280206
```

and:

```text
active = false
normal = 0
```

Thus the plane cannot pull the body toward itself.

---

## 7. Coulomb stick / slide law

### Stick candidate

The full 3D contact-space force required to cancel free contact acceleration is solved first.

If:

```text
normal > 0

and

|F_t| <= mu * F_n

and

tangential contact speed ~ 0
```

the mode is:

`stick`.

Executable stick probe:

```text
force =
(
 4.94533979338218,
 4.74453306530079,
12.2798501384264
)

cone ratio =
0.46507393858269
```

### Slide

Otherwise tangential direction opposes tangential velocity and:

```text
|F_t| =
mu * F_n
```

Accepted sliding probes produce:

`cone ratio = 1.0`.

So stick and slide are two solved states of one generic friction law, not separate engine devices.

---

## 8. Impact impulse law

For incoming contact:

```text
v_n < 0
```

the successor first attempts a sticking impulse in contact space.

If the stick candidate violates the Coulomb cone, it falls back to sliding impulse on the cone boundary.

Impulse application changes:

- linear momentum by `P`;
- angular momentum about COM by `r x P`.

The acceptance explicitly audits both.

---

## 9. Oblique free-flight impact

Main impact experiment begins from arbitrary orientation, nonzero 3D linear velocity and nonzero 3D angular velocity.

First impact time:

```text
0.16920086866594
```

Contact feature:

`plane|C|v:---`.

Solved impact:

```text
mode =
stick

impulse =
(
-0.38652781487918,
 2.99430127860919,
 8.6621395387905
)

cone ratio =
0.82986926603547
```

Momentum audits:

```text
linear momentum error  = 0
angular momentum error = 0
```

Kinetic energy change:

```text
-25.073057544238
```

This makes the impact a fully explicit causal jump.

---

## 10. Persistent convex feature hierarchy

For a box against a plane, support geometry is derived from:

```text
n_body =
q^-1 * n_world
```

The sign of each component selects supporting local coordinates.

Classification:

```text
no zero components
→ vertex

one zero component
→ edge

two zero components
→ face
```

### Vertex

```text
point_count = 1
```

### Edge

```text
point_count = 2
```

### Face

```text
point_count = 4
```

Executable face probe:

```text
type =
face

lineage =
[
  v:++-,
  v:+--,
  v:-+-,
  v:---
]

local point =
(0,0,-0.25)
```

This is a geometry-derived lineage hierarchy:

```text
vertex
↕
edge
↕
face
```

---

## 11. Dynamic feature fixed points

Accepted sliding run uses duration:

`0.315 s`.

Two physical feature events occur.

### Event 1

```text
t =
0.25850330043665

plane|C|v:---
→
plane|C|edge:0:v:+--:v:---
→
plane|C|v:+--
```

### Event 2

```text
t =
0.31322331523056

plane|C|v:+--
→
plane|C|edge:1:v:++-:v:+--
→
plane|C|v:++-
```

Each event:

```text
iterations = 3
topology_mutations = 2
fixed_point = true

point counts =
1 -> 2 -> 1
```

Thus 0.12/0.13 same-time topology fixed-point semantics survive inside full frictional rigid-body evolution.

---

## 12. Hidden-projection impulse finding

During initial FABRIC0.14 integration, the energy ledger showed:

```text
-delta_E
!=
continuous friction loss
```

with a roughly constant discrepancy:

`~0.1224`.

Crucially, the discrepancy **did not decrease under refinement**.

Therefore it was not normal integration truncation.

Root cause:

At a feature switch:

```text
old vertex
→
edge
→
new vertex
```

the implementation silently projected the new support point's normal velocity to the new constraint.

That projection was physically equivalent to an impulse, but no impulse existed in causal history.

This violated the FABRIC rule:

```text
physical jump
must be explicit
```

---

## 13. Explicit feature-transition impulse

FABRIC0.14 removes the hidden projection.

At each feature topology transition:

1. lineage remaps old numerical warm state;
2. the new support feature is compiled;
3. contact velocity at that feature is measured;
4. a real frictional unilateral impulse is solved;
5. linear/angular momentum audits are recorded;
6. kinetic energy change is recorded;
7. only then is the state projected onto the new active constraint.

First sliding transition:

```text
impulse =
(
-0.31924747565365,
 0.33309207021759,
 1.53792529060373
)

mode = slide

kinetic loss =
2.38784108026821
```

Second:

```text
impulse =
(
-0.27757117602471,
 0.21178194248111,
 1.16379336138726
)

kinetic loss =
1.67546501980837
```

Both have:

```text
linear momentum audit error  = 0
angular momentum audit error = 0
cone ratio                    = 1
```

This is one of the most important findings of the checkpoint.

---

## 14. Energy ledger

The accepted energy accounting is:

```text
-delta_E
=
continuous Coulomb friction dissipation
+
discrete impact / feature-transition losses
+
numerical closure residual
```

For main `1e-9` sliding run:

```text
continuous friction dissipation =
1.2019943422435

discrete feature-event losses =
4.06330610007658

energy delta =
-5.26530042753262

closure residual =
1.4787455704379227e-8
```

The missing energy from the hidden projection is gone.

---

## 15. Energy-closure convergence

Against the `1e-12` reference family:

```text
tol      closure residual

1e-7     3.8286514048024856e-7

1e-9     1.4787455704379227e-8

1e-11    3.3513192221334975e-10
```

Strictly decreasing.

This means the energy ledger is now consistent with the actual hybrid dynamics to numerical accuracy.

---

## 16. Event-time convergence

Sliding feature-event max error against `1e-12` reference:

```text
1e-7:
6.510981837015706e-8

1e-9:
1.5766716265908087e-9

1e-11:
3.3262503862374615e-11
```

Strictly decreasing.

---

## 17. Full 13D state convergence

Maximum final state-component error:

```text
1e-7:
5.464352880735213e-7

1e-9:
1.2631674595198206e-8

1e-11:
2.586177383356869e-10
```

Strictly decreasing.

Therefore FABRIC0.14 acceptance simultaneously requires convergence of:

```text
event times
+
13D physical state
+
energy ledger
```

---

## 18. Main sliding run evidence

At `tol=1e-9`:

```text
accepted steps =
24

rejected steps =
1

contact force calls =
22

slide force calls =
22

stick force calls =
0

min normal force >
5.0

max cone ratio =
1.0

max support gap <=
1e-13

max quaternion normalization error <=
1e-14
```

Physical state hash:

`2b52dc944cdc4a48152265db3e456c629bfb5f66969850563e39ec188147efe7`.

---

## 19. Torque-free full 3-axis invariant audit

Separate experiment disables gravity and external force/torque.

Initial angular velocity:

```text
(
 1.1,
-0.9,
 1.4
)
```

After `0.6 s`:

```text
omega =
(
 0.64777572651907,
-0.36223547345886,
 1.87243783476517
)
```

All three rotational components remain live.

Invariant drifts:

```text
linear momentum drift =
0

world angular momentum drift =
9.733960482902654e-10

rotational energy drift =
1.7629e-10
```

Quaternion remains normalized.

Torque-free state hash:

`e57d66d29b7de53757f5b4ba2d0d2a26f3c2a342086a63aebc93726b40666a99`.

This is the direct evidence that 0.14 is more than one-axis quaternion representation.

---

## 20. Actual parallel contact audit

Two real Godot Threads solve independent contact snapshots.

Canonical hash:

`526844a8ca0629969477f2942853b3e7b9617b391e39fc54147d30d38852773c`.

Reverse thread spawn order produces the exact same hash.

Main result:

```text
mode =
slide

force =
(
-1.70130933446569,
 0.19586342431757,
 5.70848874000184
)

cone ratio =
1
```

Side result:

```text
(
 2.4830692348853,
-2.13104100828383,
 7.79083441814543
)
```

Parallel audit does not mutate physical world hash.

---

## 21. Deterministic replay

Fresh `1e-9` sliding run reproduces:

- exact event JSON;
- exact physical state hash.

Main state hash:

`2b52dc944cdc4a48152265db3e456c629bfb5f66969850563e39ec188147efe7`.

---

## 22. Fail-closed contracts

Invalid adaptive tolerance:

`BAD_ADAPTIVE_OPTIONS`.

Negative friction coefficient:

`BAD_FRICTION_COEFFICIENT`.

Nonpositive mass:

`BAD_MASS`.

Nonpositive inertia component:

`BAD_INERTIA`.

Degenerate contact effective-mass solve also has fail-closed singular/bad-denominator paths.

---

## 23. Exact validation

Exact runtime was re-extracted again from the original user-provided Godot archive:

`4.7.1.stable.double.custom_build.a13da4feb`.

Focused acceptance:

`156/156 PASS`.

Acceptance line:

```text
FABRIC0.14 Full 6DOF Frictional Feature Manifold Acceptance:
PASS (156 assertions)
```

Playground:

`FABRIC0_14_FULL_6DOF_FRICTIONAL_FEATURE_MANIFOLD_PLAYGROUND_PASS`.

Editor parse/compile/SCRIPT scan:

`CLEAN`.

---

## 24. Real predecessor regression

Unlike several previous isolated successors, the FABRIC0.14 lab materializes the FABRIC0.13 runtime suite.

On the same exact-double Godot:

```text
FABRIC0.13 Unified Adaptive 3D Contact Graph Acceptance:
PASS (95 assertions)
```

All seven FABRIC0.13 executable blobs also remain unchanged against v13 evidence.

Therefore v14 can honestly claim both:

```text
predecessor runtime regression PASS
+
predecessor executable bytes preserved
```

---

## 25. Exact executable SHA-256

```text
contact
79cc324b9a7def6cb90ace97799085e158d134dabde2b30443e2386a4e63ae33

model
2d2144615f340111e516a5246a67a294a0868f206bb7a48487f4354dc840f7a8

driver
2a320ea36d498391a8260509a4a222850052a7ea2b7b48352a01efd2a795ecfb

facade
84136c5568a4a51a68f04ed10949db3eb8b8efa6bea36d570578cd9112391532

experiments
2a90b64bbd0824b7c04b67b3b613406abcb3f0f5f50d8942638433cb5a117321

acceptance
5376947be3ee00c7b9122d7b9cdcb212dcd55a0c0910aa5f6ca92abe9cde2faa

playground
fd8c6ec319807837862a7f9f8c9915b1b74ad205a4e4425c921bc485979ad253
```

---

## 26. Exact Git blob identity

Local `git hash-object`:

```text
contact
08e247d97f5fd261f8dfc6facda028ebca2727b3

model
c766a915a02b8269024ddd93e9a4fb1f9f210bd1

driver
6a8c2417b44b25d82038e7bdc3ca2c1ae5616eba

facade
ce2d2270af508e2fabe5ede2ccfdf884e7c6f6fb

experiments
c914866af52b6dc595a076fb7c24cf30701d03fd

acceptance
97a27b68358aab2c6bfb9dc091786dd3524839b7

playground
97355e398262fbaad6d883e21fd69f80c9e4477a
```

All seven GitHub branch blobs were re-fetched and verified exact-equal.

Remote byte identity:

`7/7 PASS`.

---

## 27. What FABRIC0.14 proves

The checkpoint demonstrates:

- a 13-component rigid-body state with 3D translation, quaternion and 3D angular velocity;
- anisotropic body inertia and gyroscopic rigid-body dynamics;
- torque-free three-axis angular-momentum and rotational-energy invariant audit;
- geometry-derived box support features from orientation;
- vertex, edge and face feature classification and lineage;
- unilateral normal separation branch;
- Coulomb stick branch;
- Coulomb sliding branch on the cone boundary;
- oblique free-flight impact with explicit linear/angular momentum audit;
- adaptive sliding trajectory with two feature topology fixed points;
- explicit feature-transition impulses rather than hidden velocity projection;
- continuous friction dissipation + discrete jump-loss energy ledger;
- convergence of event time, full physical state and energy closure;
- deterministic replay;
- actual two-thread contact snapshot solve with reverse-order invariance;
- exact remote/local byte identity for all seven executable successor files;
- real FABRIC0.13 runtime regression on the same exact-double Godot.

---

## 28. What FABRIC0.14 does NOT prove

Important open walls:

- multiple simultaneously free interacting 6DOF bodies;
- a coupled multipoint normal complementarity solve over all face points;
- dynamic accepted trajectory that remains on a full face manifold;
- arbitrary convex/GJK/EPA/mesh contact geometry;
- localized dynamic separation event;
- localized dynamic stick-to-slide / slide-to-stick event;
- coupled multi-contact Coulomb friction cones;
- restitution family beyond the current research default;
- rolling friction;
- torsional friction;
- arbitrary simultaneous impacts;
- production broadphase;
- production block-sparse/CSR solver;
- production thread pool/work stealing;
- distributed Construction/authority/persistence/network integration;
- full DWS materialized regression.

The current box/plane feature family is an analytically convenient convex research geometry, not a generic collision engine.

---

## 29. Next falsification wall

### FABRIC0.15 — MULTIBODY CONVEX COMPLEMENTARITY GRAPH

Next checkpoint should move from one free body against a plane to several free interacting rigid bodies and a coupled nonsmooth graph.

Target:

```text
multiple free 6DOF rigid bodies
+
convex feature generation
+
simultaneous normal complementarity
+
coupled tangential friction cones
+
dynamic separation
+
stick/slide mode events
+
island merge and split
+
adaptive multi-event fixed point
+
block sparse parallel solve
+
momentum / energy / refinement evidence
```

Critical experiment:

```text
several freely moving convex bodies
+
oblique multi-contact collision
+
one body sticks
+
one contact slides
+
another contact separates
+
island merges then splits

while:

event times converge
+
13N state converges
+
momentum jump audits close
+
dissipation ledger closes
+
feature lineage remains causal
+
parallel order remains canonical
```

---

## 30. Architectural conclusion

FABRIC0.14 changes the research picture from:

```text
contact graph with partial rotational mechanics
```

to:

```text
full rigid-body local dynamics
+
nonsmooth frictional contact law
+
feature-topology hybrid events
+
explicit jump energetics
```

The most important lesson is not simply “6DOF works”.

It is:

> Hybrid physical transitions must never hide impulses inside numerical projection. If refinement reveals a non-convergent energy discrepancy, the architecture must search for missing physical semantics before reducing solver tolerances.

Construction remains canonical semantic owner.

FABRIC remains a research physical execution substrate and does not become a second source of world truth.
