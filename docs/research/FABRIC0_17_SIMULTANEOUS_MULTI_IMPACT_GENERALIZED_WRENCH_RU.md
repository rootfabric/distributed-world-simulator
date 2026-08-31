# FABRIC0.17 — SIMULTANEOUS MULTI-IMPACT + GENERALIZED CONTACT WRENCH

## Статус

```text
FABRIC0.17
IN PROGRESS

0.17-A — SIMULTANEOUS IMPACT EVENT SET
IMPLEMENTED CANDIDATE / 77/77 PASS

0.17-B — COUPLED SIMULTANEOUS IMPACT SOLVE
IMPLEMENTED CANDIDATE / 63/63 PASS

0.17-C — GENERALIZED CONTACT WRENCH
IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
76/76 PASS
REMOTE BYTE IDENTITY PASS
NOT CLOSED
```

**Branch:** `research/fabric0-17-simultaneous-impact-event-set-r1`  
**Predecessor:** `FABRIC0.16 — GENERAL CONVEX MULTIPOINT MCP`  
**FABRIC0.16 closure HEAD:** `ae781ab78f2e0688641f6a332a131b3fb759994f`  
**FABRIC0.16 exact-tested executable:** `3307d553c1c3c79cd9c15a5c565af7fef3f0400c`  
**0.17-A executable HEAD:** `9139a213ccee64d3bf1bb95ea32170027421b3b3`.

FABRIC0.17 продолжает именно Physical Core. FABRIC-BAKE остаётся sibling research axis и может развиваться независимо.

## 1. Fundamental wall

FABRIC0.16 доказал отдельные general-convex contact events и unified graph topology mutation, но сознательно не заявил simultaneous multi-impact closure.

Новая стена:

```text
several independently localized impact candidates
                ↓
same physical instant / unresolved temporal neighborhood
                ↓
one deterministic event set
                ↓
one coupled post-impact solve
```

0.17-A атакует только первые три строки.

## 2. Checkpoint decomposition

```text
0.17-A
SIMULTANEOUS IMPACT EVENT SET

0.17-B
COUPLED SIMULTANEOUS IMPACT SOLVE

0.17-C
GENERALIZED CONTACT WRENCH
normal + tangential + rolling + torsional

0.17-D
UNIFIED MULTI-IMPACT WRENCH TRAJECTORY
+ refinement
+ momentum/energy
+ determinism
+ closure decision
```

Это разбиение специально не смешивает temporal identity события и physical jump solve.

## 3. 0.17-A semantics

Новый primitive:

`Fabric0SimultaneousImpactEventSetV1`.

Pipeline:

```text
body set
→ conservative swept candidate pairs
→ S2 contact-appearance root localization for every candidate
→ impact kinematics audit
→ canonical time/id ordering
→ earliest temporal cluster
→ deferred later impact roots
```

Contact appearance входит в impact set только если на локализованной границе:

```text
approach_speed > min_approach_speed
```

Approach speed вычисляется из full point velocity:

```text
v_point = v + omega × r
```

и oriented contact normal.

Таким образом простое появление contact relation без сближения не объявляется impact.

## 4. Что означает simultaneous

Запрещено определять simultaneity как:

```text
float_time_a == float_time_b
```

0.17-A использует локализованные root intervals:

```text
event_i =
[lo_i, hi_i]
+
reported midpoint time_i
```

События относятся к одному earliest event set, если distance их localization intervals от anchor interval не превосходит explicit `simultaneous_resolution`.

Результат означает: impacts are indistinguishable at the declared temporal resolution.

Это не математическое доказательство exact equality реальных корней.

Observable classification:

```text
INTERVAL_COINCIDENT
RESOLUTION_EQUIVALENT
```

и поля `root_tolerance`, `simultaneous_resolution`, `common_lo/common_hi`, `union_lo/union_hi`, `temporal_spread`, `uncertainty_span` делают numerical policy частью evidence.

## 5. Main falsifier

Пять одинаковых convex boxes:

```text
L ---> C <--- R

P ---> Q
```

Истинные roots:

```text
C|L = 0.5
C|R = 0.5

P|Q = 0.5002
```

То есть два impact действительно simultaneous, третий физически очень близок, но позже.

### Coarse resolution

При `1e-3`:

```text
[C|L, C|R, P|Q]
```

Все три roots ещё неразличимы в текущем temporal uncertainty.

### Refinement

Начиная с `1e-5`:

```text
event set:
[C|L, C|R]

deferred:
[P|Q]
```

Reference `1e-11`:

```text
simultaneous event:
0.50000000000146

deferred P|Q:
0.50019999999931
```

Event-time errors относительно reference:

```text
1e-5 -> 1.5258774510584772e-6
1e-7 -> 1.192238407998758e-8
1e-9 -> 9.167711034763215e-11
```

Strictly decreasing.

## 6. Determinism

Canonical event-set signature:

```text
SIMULTANEOUS_IMPACT_SET[C|L,C|R]
```

Полный reverse input body order даёт те же pair_ids, signature, event time и deferred pair/time.

## 7. Fail-closed boundaries

0.17-A явно отвергает:

- меньше двух bodies;
- empty/duplicate body IDs;
- bad time interval;
- non-positive root tolerance;
- negative simultaneous resolution;
- bad iteration budget;
- bad pair budget;
- pair count above bounded budget;
- negative impact approach threshold;
- localization/impact-kinematics failure.

Если impact roots отсутствуют: `NO_IMPACT_EVENT`.

Pair enumeration остаётся bounded research implementation. По умолчанию `max_pairs = 4096`.

## 8. Exact validation

Engine: `Godot 4.7.1.stable.double.custom_build.a13da4feb`.

```text
0.17-A acceptance 77/77 PASS
0.17-A playground PASS
0.16 S3 regression 101/101 PASS
0.16 S2 regression 102/102 PASS
0.16 S1 regression 110/110 PASS
editor parse/compile CLEAN
remote byte identity 4/4 PASS
```

Exact files:

```text
event set
blob   593cd671c9144819199685eeb222df7b06399c76
sha256 4c4ecddb1675b65d52308490854bcd9334bce90291d215d8a98ba4c3950ca0d6

experiments
blob   a76d2e99165c69058e2d4da5a859a6cbc32f2bc0
sha256 276d5354ad2a090c31b9fc9b73d3500641618f3791f081c1bfbc3b644701051c

acceptance
blob   440ce7a1e1c48456d33a8d43aeb776a979afe02e
sha256 e1fc369b8342dc4a43b847c60a99aa7ed26d2813faf7ddcf1f1db94f38284da8

playground
blob   ecf16b7e6c87f50038357443d2fd0b82e4fc73c9
sha256 83bcb3365f0b3a450de38c0d9f5a14361d0af3a26937bf8b17cbba27dd6b0985
```

## 9. 0.17-A non-claims

0.17-A does **not** solve impact impulses.

Not claimed:

- coupled simultaneous post-impact velocity solve;
- restitution law across a multi-contact event set;
- unique/maximum-dissipation impact solution;
- same-time topology fixed point after impulses;
- rolling or torsional friction;
- exact mathematical equality of impact root times;
- transient appear+disappear detection when both macro-interval endpoints have the same contact state;
- production broadphase;
- sub-quadratic pair discovery;
- production acceptance.

Current event finder localizes bracketed appearance roots over an interval.

## 10. Next slice — 0.17-B

```text
SIMULTANEOUS_IMPACT_EVENT_SET
        ↓
materialize all event-set manifolds at one event boundary
        ↓
assemble one coupled impulse graph
        ↓
solve all normal impact impulses together
        ↓
optional restitution target
        ↓
audit pair-order independence
+ momentum conservation
+ energy/restitution ledger
+ complementarity
+ refinement
```

Critical requirement: sequentially applying pair impacts is not accepted as the 0.17-B reference semantics.

Construction remains canonical semantic owner. FABRIC0.17 remains research-only.


## 11. 0.17-B — Coupled Simultaneous Impact Solve

**Exact-tested executable HEAD:** `6456ca4a5ce936c7b4c2b11906c696982a091e24`.

0.17-B принимает уже локализованный 0.17-A event set и выполняет один physical jump из immutable common pre-impact state.

Accepted pipeline:

```text
SIMULTANEOUS_IMPACT_EVENT_SET
        ↓
canonical body/member order
        ↓
advance every body to one event time
        ↓
immutable common pre-impact state
        ↓
materialize every event-set face manifold
        ↓
one coupled Delassus matrix
        ↓
one normal impact LCP
        ↓
apply solved impulses
        ↓
one post-impact state
```

Sequential pair mutation не используется как reference semantics.

### 11.1 Impact complementarity law

Для contact rows `i` используется:

```text
lambda >= 0

w =
J v+ + e J v- + epsilon lambda
>= 0

lambda ⟂ w

v+ =
v- + M^-1 J^T lambda
```

где:

- `e` — restitution coefficient, `0 <= e <= 1`;
- `epsilon = normal_regularization`;
- accepted research default `epsilon = 1e-9`;
- `J` содержит все manifold normal rows одного simultaneous event set.

RHS coupled LCP:

```text
q_i = (1 + e) * vn_before_i
```

Delassus matrix переиспользует проверенную 0.16 graph coupling semantics.

Regularization является observable numerical policy и не выдаётся за физическую compliance.

### 11.2 Exact-boundary manifold materialization

Все event members materialize на одном event time.

На zero-measure convex touch EPA может быть volumetrically degenerate. Как и в 0.16 S3, 0.17-B не вводит искусственное penetration epsilon.

Fallback:

```text
event normal
+
opposed support witnesses
+
bounded signed support gap
        ↓
zero-depth collision witness
        ↓
ordinary clipped persistent manifold builder
```

Accepted `max_boundary_gap = 5e-6`.

### 11.3 Symmetric simultaneous-impact falsifier

```text
L ---> C <--- R
```

Оба roots принадлежат одному event set около `t=0.5`.

Каждый face contact даёт 4 points:

```text
C|L = 4 rows
C|R = 4 rows
total = 8 coupled rows
```

Elastic `e=1`:

```text
event time = 0.50000000009313

pair impulse C|L = 3.999999999
pair impulse C|R = 3.999999999

pre:
L = +2
C =  0
R = -2

post:
L ≈ -2
C ≈  0
R ≈ +2
```

Energy:

```text
4.0
→ 3.999999996
```

The tiny loss is consistent with explicit `1e-9` regularization and remains observable.

Audits:

```text
max regularized complementarity ≈ 3.04e-15
max restitution error           ≈ 1.00e-9
linear momentum error            = 0
angular momentum error           = 0
```

### 11.4 Sequential-order falsifier

The deliberately rejected reference:

```text
solve C|L
mutate velocity
solve C|R
```

gives:

```text
forward order:
C=-2, L=0,  R=+2

reverse order:
C=+2, L=-2, R=0

max state delta = 4
```

Both sequential variants conserve total linear momentum. Therefore momentum conservation alone is insufficient evidence of correct simultaneous-impact semantics.

The accepted coupled solve differs strongly from both sequential outcomes and is exact-identical under:

- reversed caller body order;
- reversed event-member order.

### 11.5 Restitution on one coupled graph

Same graph, different `e`:

```text
e = 0.0
energy after ≈ 0

e = 0.5
energy 4 -> ≈ 1
ratio ≈ 0.25

e = 1.0
energy 4 -> ≈ 4
```

Thus restitution target participates in the single coupled LCP rather than pair-wise post-processing.

### 11.6 Off-center full-6DOF falsifier

A second stand intentionally makes both simultaneous contacts off-center and asymmetric.

Observed for `e=0.35`:

```text
8 manifold rows

pair impulses:
C|L = 2.32041018805662
C|R = 2.41419120032416
```

Post-state includes substantial angular velocity:

```text
C.w_z ≈ -1.47370162073111
L.w_z ≈ -1.47370162051047
R.w_z ≈ -1.47370162043639
```

Energy:

```text
4.5
→ 1.03020302603508
delta = -3.46979697396492
```

Audits:

```text
linear momentum error  = 0
angular momentum error = 0
max complementarity    ~ 3e-14
max restitution error  ~ 7.51e-10
```

Reverse body/member order again produces exact-identical signature/state.

This is evidence that simultaneous impulse coupling uses full 6DOF lever-arm dynamics rather than a one-dimensional center-velocity shortcut.

### 11.7 Refinement gate before physical jump

A coarse 0.17-A event set may still contain the near-later `P|Q` root.

0.17-B intentionally refuses to solve such a jump when:

```text
event_set.uncertainty_span
>
max_event_uncertainty
```

Fail-closed code:

`EVENT_SET_NOT_REFINED_ENOUGH`.

This prevents temporal uncertainty from silently becoming impact topology.

### 11.8 Exact validation

Exact runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

```text
0.17-B acceptance  63/63 PASS
0.17-B playground  PASS

0.17-A regression  77/77 PASS

0.16 S3 regression 101/101 PASS
0.16 S2 regression 102/102 PASS
0.16 S1 regression 110/110 PASS

editor parse/compile CLEAN
```

Remote exact preservation at B executable HEAD:

```text
0.17-B  4/4 exact
0.17-A  4/4 preserved
0.16 S3 3/3 preserved
0.16 S2 5/5 preserved
0.16 S1 8/8 preserved
```

0.17-B exact blobs:

```text
solver
01ab5dd2bd1ad0743562f4608827f8c1bfcbd4e5
sha256 2f87326e9815f2f6f0ae5d26413ec4c26f4664db6076bd04f13a6f8b2757ac8c

experiments
176e4af2b01e9efefc347bc20ffcafac2f3df2cd
sha256 6eb9a9c52087fc8e675b52cfef564a813dd21e50c60814d023ca5fa6b75bc348

acceptance
228d4b2d88b2b94762f58aaccbd5d6012f234932
sha256 8c1cf6fb2c8820719944dfb9dc4a89ea20c8c6a79bf42ee3aa30e8882b3fa0c3

playground
fc283ea79973553299bd464f1530d79ac06c83fc
sha256 898ecea5501d0ddf3f2cce5bed628f8e1c2e352e82ea863fc8ba153eafa3bd33
```

## 12. 0.17-B non-claims

0.17-B proves a bounded normal, frictionless, coupled restitution impact graph.

It does **not** claim:

- globally unique rigid multi-impact solution for arbitrary geometry;
- maximum-dissipation impact law;
- tangential impact friction;
- rolling or torsional impact friction;
- compliant finite-duration collision;
- same-time post-impact contact/topology fixed-point iteration;
- a universal monolithic Signorini-Coulomb impact MCP;
- production sparse impact backend;
- production acceptance;
- FABRIC0.17 closure.

The accepted solver is explicitly a regularized normal restitution LCP over the simultaneous multipoint event graph.

## 13. Next slice — 0.17-C

```text
FABRIC0.17-C
GENERALIZED CONTACT WRENCH

normal impulse
+
2D tangential impulse
+
rolling resistance moment
+
torsional friction moment
        ↓
one bounded admissible 6DOF contact wrench
```

The next falsification question is whether rotational resistance can be expressed as generic contact-wrench limits derived from manifold geometry and normal support, without introducing wheel/bearing/device-specific kernel classes.


## 14. 0.17-C — Generalized Contact Wrench

**Exact-tested executable HEAD:** `edc021230dadf62e9bf5ffb4c17cc5f2d0140ba0`.

0.17-C adds a generic patch-level friction wrench on top of an already resolved normal support budget.

The five generalized friction coordinates are:

```text
u =
[v_t1,
 v_t2,
 omega_roll_t1,
 omega_roll_t2,
 omega_spin_n]
```

and generalized impulse:

```text
z =
[P_t1,
 P_t2,
 M_roll_t1,
 M_roll_t2,
 M_torsion]
```

No wheel, bearing, tire or device class appears in the kernel.

### 14.1 Admissible wrench limits

For resolved normal impulse `Pn` and geometry-derived patch radius `R_eff`:

```text
||Pt|| <= mu_t * Pn

||Mroll|| <= mu_r * Pn * R_eff

|Mtorsion| <= mu_tau * Pn * R_eff
```

`R_eff` is currently:

> maximum planar distance from the clipped manifold centroid to a manifold point.

On the 4-point box face probe:

```text
R_eff = 0.70710678118655
```

The coefficients are dimensionless research material parameters.

### 14.2 Maximum-dissipation solve

0.17-C constructs the real 5x5 generalized effective matrix `K` by applying unit generalized impulses through the full rigid-body inertia/lever-arm dynamics.

The accepted bounded problem minimizes post-impulse kinetic energy increment:

```text
Delta T(z)
=
u^T z
+
1/2 z^T K z
```

over the product admissible set:

```text
tangent disk
x
rolling disk
x
torsion interval
```

using deterministic projected gradient.

This is a bounded maximum-dissipation research solve for the fixed normal support budget.

Observed matrix symmetry error on the acceptance fixture:

```text
0
```

### 14.3 Important normal-support boundary

`Pn` is **not applied by 0.17-C**.

It is assumed to have already been resolved by the normal contact solve and is used only as the friction-wrench capacity budget.

Therefore output distinguishes:

```text
applied_wrench_impulse
=
tangential force impulse
+
rolling/torsional moment impulse
```

from:

```text
admissible_resultant_wrench_impulse
=
normal support budget
+
applied friction wrench
```

This prevents double-applying normal support.

Normal/friction/wrench recoupling remains an integration wall for 0.17-D.

### 14.4 Stick falsifier

With large admissible limits:

```text
modes:
tangent = stick
rolling = stick
torsion = stick
```

Five generalized relative velocities after solve are all below approximately:

```text
6.4e-12
```

Projected iteration residual:

```text
9.774542286677956e-13
```

Energy:

```text
Delta KE = -0.00747350907499
```

The impulse-work prediction equals measured rigid-body kinetic-energy change within double precision.

### 14.5 Saturated slide / roll / spin falsifier

Normal support budget:

```text
Pn = 2
```

Limits:

```text
tangent = 0.5
rolling = 0.11313708498985
torsion = 0.07071067811865
```

All three channels saturate independently:

```text
tangent mode = slide
rolling mode = roll
torsion mode = spin
```

Solved generalized impulse:

```text
[-0.48801695881371,
 -0.10880922713731,
  0.09671521640430,
  0.05870406217520,
 -0.07071067811865]
```

Applied friction wrench:

```text
force =
(0,
 -0.10880922713731,
  0.48801695881371)

moment =
(-0.07071067811865,
  0.05870406217520,
 -0.09671521640430)
```

Energy:

```text
Delta KE = -3.31742638415729

energy ledger error
= 2.220446049250313e-15
```

Linear and angular momentum errors:

```text
0
0
```

### 14.6 Independent channel falsifiers

Pure rotational resistance:

```text
mu_tangent = 0

applied tangent force = 0
applied rolling/torsional moment != 0

Delta KE = -1.003651515657
```

This proves rolling/torsional channels are not encoded as hidden point force.

Pure tangent friction:

```text
mu_rolling = 0
mu_torsion = 0

applied tangent force != 0
explicit contact moment = 0

Delta KE = -1.723184248210
```

Thus point friction and contact moments are independently controllable generalized coordinates.

Zero normal support:

```text
Pn = 0
→ all three limits = 0
→ generalized impulse = 0
→ state unchanged
→ Delta KE = 0
```

### 14.7 Determinism and conservation

Reversing:

- caller body array order;
- requested pair order `A|B <-> B|A`;

produces exact-identical canonical signature/state.

All acceptance probes preserve total internal:

```text
linear momentum
angular momentum about world origin
```

at double-precision exact/roundoff scale.

### 14.8 Exact validation

Exact runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

```text
0.17-C acceptance   76/76 PASS
0.17-C playground   PASS

0.17-B regression   63/63 PASS
0.17-A regression   77/77 PASS

0.16 S3 regression 101/101 PASS
0.16 S2 regression 102/102 PASS
0.16 S1 regression 110/110 PASS

editor parse/compile CLEAN
```

Remote executable bytes:

```text
0.17-C 4/4 exact
0.17-B preserved
0.17-A preserved
0.16 S3 predecessor preserved
```

Exact C blobs:

```text
runtime
b910db82df3d46528ba2a65c38e9292cbf6d73c6
sha256 a1e815fd0a7adc6cad334913a4b55ab3e60a5373eb3b5f5924c84e8c496316cf

experiments
af80403d36010e347b6061afed65e885a42014e1
sha256 4cb6bc0de6c20d4351b2c53198e3f9a62e9485add2b7ecbd17b6456ea3b9067a

acceptance
b1ff38e5d8d6c12edc8deae7cfb11dcf1f90b1b4
sha256 9394583de5498ab4340c96342197c2ffb520189e7a194193bdf17e24ed4c789a

playground
f90df6b4075e8d607bdbc6b8ebc768157f9a8aa6
sha256 dc21c9a329d555d2e4f51710b35835c7eadace07675571dc2691ffa2770be5ce
```

## 15. 0.17-C non-claims

0.17-C does **not** claim:

- normal support and generalized friction solved in one coupled MCP;
- exact pressure-distribution contact wrench cone;
- center-of-pressure/tipping support polygon solve;
- coupled ellipsoidal force/moment friction law;
- rolling resistance derived from deformation/material microphysics;
- frictional simultaneous impact;
- sustained contact trajectory with mode events;
- globally certified maximum-dissipation Signorini-Coulomb wrench solve;
- production acceptance;
- FABRIC0.17 closure.

The current admissible set is an explicit product of tangent disk, rolling disk and torsion interval.

## 16. Next slice — 0.17-D

```text
FABRIC0.17-D
UNIFIED MULTI-IMPACT WRENCH TRAJECTORY

0.17-A event-set localization
+
0.17-B coupled impact jump
+
0.17-C generalized sustained-contact wrench
        ↓
same-time event fixed point
        ↓
post-impact persistent manifold
        ↓
wrench mode evolution
        ↓
separation / topology mutation
        ↓
refinement
+
momentum / energy
+
deterministic replay
```

0.17-D is the closure-decision slice. It must show that temporal event identity, coupled normal impact and generalized rotational/tangential contact behavior coexist in one trajectory rather than only in isolated probes.

## 17. 0.17-D — Unified Multi-Impact Wrench Trajectory

**Exact-tested executable HEAD:** `643b4bdc5d33756819869c3faacc1dccf1251a1f`  
**TREE:** `3d531be386502c34ad7c30da8a00c5df8f152906`.

Current bounded status: `IMPLEMENTED CANDIDATE / EXACT LINUX DOUBLE PASS / 157/157 PASS / REMOTE BYTE IDENTITY 6/6 PASS / PROJECT CONTROL RECHECK / FABRIC0.17 NOT CLOSED`.

### 17.1 Integration finding: one-pass B → C is invalid

A naive coupled-normal-impact followed once by generalized wrench reopens the normal restitution/complementarity law through shared rigid-body coupling. Measured reopened residuals were `0.3411080670192037` and `0.3373959971736645` for the two event groups.

D therefore introduces `Fabric0ImpactWrenchFixedPointV1`. Every outer iteration starts from the same immutable pre-impact state, applies the current normal impulses, solves the graph-wide generalized wrench, measures the full-post normal law, then re-solves the normal LCP with the wrench cross-bias. Stopping is based on the physical full-post normal residual, not only on small `lambda/z` change.

Accepted residual limit is `5e-10`. Reference accepted residuals are `4.4365353630363876e-10` and `2.2960234509547496e-10`.

### 17.2 Graph-wide generalized wrench

`Fabric0GeneralizedContactWrenchGraphV1` assembles all 5DOF patch coordinates of one simultaneous event set in one shared-body effective matrix. The reference cross-patch coupling is approximately `3.33333333333333` for the first event and `3.44827586206897` for the second, so the acceptance stand is not block-diagonal.

### 17.3 Unified two-event trajectory

The six-body trajectory contains two causally ordered simultaneous groups: first `[C|L,C|R]` near `0.5`, then `[P|Q,Q|S]` near `0.5002`. Each group materializes two four-point manifolds, therefore eight normal rows, and executes a recoupled normal-impact + generalized-wrench jump.

At `1e-11` localization the reference event times are `0.50000000000255` and `0.50020000000273`. Maximum tangential impulses are approximately `0.328386` and `0.341175`; explicit rolling/torsional moment impulse magnitude is nonzero (about `0.004823` and `0.007338`). The torsional channel is supported by C but is not itself active in this D trajectory.

Both impacts separate immediately after restitution (`persistent_after=false`), so this trajectory does not claim finite-duration persistent-contact wrench-mode evolution.

At coarse `1e-3`, A aliases both physical instants into `[C|L,C|R,P|Q,Q|S]`; D fails closed with `EVENT_SET_NOT_REFINED_ENOUGH_FOR_TRAJECTORY` before executing any jump.

### 17.4 Refinement, conservation, determinism

Whole-state error against the `1e-11` reference strictly decreases: `7.492319276325432e-6 → 5.04126098643809e-8 → 5.950968606782681e-10` for `1e-5,1e-7,1e-9`.

Maximum event-time error strictly decreases: `2.8655978531189064e-6 → 1.9476065094004014e-8 → 2.1209412004452588e-10`.

Reference energy is `9.66625 → 2.07687223207214`; whole-trajectory energy-ledger error is `1.7763568394002505e-15`. Linear and angular momentum errors are zero.

Same-tolerance replay, reverse caller body order, and reverse event-member order produce exact-identical state, event times and signature.

### 17.5 Exact gate

Exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

`D 157/157`, `C 76/76`, `B 63/63`, `A 77/77`, `0.16 S3 101/101`, `S2 102/102`, `S1 110/110`; editor parse/compile `CLEAN`.

Remote executable boundary: D `6/6 exact`; C/B/A and 0.16 S3 predecessor bytes preserved.

Exact D blobs: graph `b309a9d47bfec9128206fb6d93a54f8fbdea6cd6`; fixed-point `438722f3af3db2284e15ff707380ebb2730dc831`; trajectory `3afa66115c59a1d8e88ff289d91eed3cbd584319`; experiments `3bb52758b02a22709335f5554491ee7a77a09651`; acceptance `f5565a183e869524ed607f83006566d805a3b1b0`; playground `2f45649b09ffa66843957cec604b3f4e59d7fd75`.

### 17.6 Project Control external blocker record

First Project Control on exact D executable HEAD: run `#1836`, id `33357807534`, `FAILURE` at `architecture and ownership passport compatibility regression`.

The D delta from the previously successful C evidence HEAD is exactly six added FABRIC research/test files. It changes no G/ECO/Matter/control-registry file. The failing harness tests instead report repository-wide RED passport/dependency drift in `G` and `ECO`, including Matter generation/query/storage paths. This is recorded as `EXTERNAL_CROSS_REF_CONTROL_DRIFT` and the same exact D HEAD is being rechecked.

Until Project Control is green, or an explicit project-policy external-blocker exception exists, FABRIC0.17 is not declared CLOSED.

## 18. D non-claims and closure boundary

D does not claim finite-duration persistent-contact wrench-mode evolution, torsional activation in the D trajectory, exact pressure-distribution wrench cone, globally unique arbitrary rigid multi-impact solution, universal monolithic Signorini-Coulomb impact+wrench MCP, production sparse backend, or production acceptance.

The bounded A+B+C+D physical target is executable and exact-tested; final research-candidate closure remains gated by repository control.
