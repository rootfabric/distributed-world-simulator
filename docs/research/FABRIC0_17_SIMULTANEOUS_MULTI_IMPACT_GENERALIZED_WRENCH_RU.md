# FABRIC0.17 — SIMULTANEOUS MULTI-IMPACT + GENERALIZED CONTACT WRENCH

## Статус

```text
FABRIC0.17
IN PROGRESS

0.17-A — SIMULTANEOUS IMPACT EVENT SET
IMPLEMENTED CANDIDATE / 77/77 PASS

0.17-B — COUPLED SIMULTANEOUS IMPACT SOLVE
IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
63/63 PASS
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
