# FABRIC0.16 — progress / recovery note

## Recovery boundary

```text
branch:
research/fabric0-compositional-world-fabric-r1

predecessor frontier:
962b9c1bbf7f04c7853f1fb0e36480cf54f3250d

FABRIC0.15:
CLOSED

FABRIC0.16:
RESEARCH CANDIDATE CLOSED
```

## Completed S1

```text
S1 GENERAL CONVEX MANIFOLD + GRAPH LCP

support-mapped convex polytopes       ✅
GJK intersection                      ✅
EPA penetration                       ✅
clipped 1..4 point manifold           ✅
persistent manifold point IDs         ✅
research sweep-and-prune broadphase   ✅
graph-wide normal active-set LCP      ✅
coupled Coulomb friction fixed point  ✅
canonical reverse input-order replay  ✅
linear/angular momentum audit         ✅
exact Linux double acceptance         ✅ 110/110
playground                             ✅ PASS
editor parse/compile scan              ✅ CLEAN
```

## Important findings fixed during S1

1. Redundant face rows can make an unregularized/generalized Jacobian singular. Current normal LCP exposes `normal_regularization=1e-9`.
2. Compact GDScript `if ...: ...; ...` caused a hidden pivot bug. New S1 runtime scope uses explicit control blocks.
3. One-pass tangential friction can reopen solved normal constraints. Current solver iterates normal LCP and friction cones to a fixed point.
4. Contact impulse lever arms use a common manifold point; geometry witnesses remain separate. This preserves internal angular momentum under numerical penetration.

## Not closed yet

```text
adaptive event localization     🔵 NEXT
same-world parallel islands     🔵 NEXT
refinement across events        🔵 NEXT
final FABRIC0.16 closure        ⛔ not claimed
```

Next bounded slice:

```text
FABRIC0.16 S2
ADAPTIVE CONVEX CONTACT EVENTS + SAME-WORLD PARALLEL ISLANDS
```

Primary design/evidence:

```text
docs/research/FABRIC0_16_GENERAL_CONVEX_MULTIPOINT_MCP_RU.md
validation/fabric0-compositional-world-fabric-v16-s1-validation.json
```


## Completed S2

```text
S2 ADAPTIVE CONVEX EVENTS + SAME-WORLD PARALLEL ISLANDS

accepted executable head:
92588ac05a7fa5b3cedd64bb567436e82e3a0a0e

motion candidate envelope                 ✅
GJK/EPA contact appearance localization  ✅
GJK/EPA separation localization          ✅
zero-measure exact-touch boundary repair ✅
persistent 4-point manifold post-event   ✅
root-localized stick -> slide             ✅
same-world deterministic island split    ✅
actual Godot Thread island solves         ✅
parallel == sequential reference          ✅ exact
reverse spawn determinism                 ✅ exact
transactional failure                     ✅
thread lifecycle hardening                ✅
exact Linux double acceptance             ✅ 102/102
S1 regression                             ✅ 110/110
remote S2 byte identity                   ✅ 5/5
S1 predecessor blob preservation          ✅ 8/8
editor parse/compile                      ✅ CLEAN
```

Important exact-touch rule discovered in S2:

```text
GJK boundary + EPA volume degeneracy
!= collision failure inside a bracketed zero-measure event search
```

The boundary is represented by support gap = 0 and remains fail-closed outside the event-localization context.

Reference events:

```text
appear    0.50000000001455
disappear 0.10000000004657
stick->slide 0.15798543221899
```

Next:

```text
FABRIC0.16 S3
UNIFIED EVENT-DRIVEN CONVEX TRAJECTORY + REFINEMENT
```

FABRIC0.16 remains IN PROGRESS / NOT CLOSED.


## FABRIC0.16 CLOSURE

```text
exact-tested S3 executable head:
3307d553c1c3c79cd9c15a5c565af7fef3f0400c

FABRIC0.16:
RESEARCH CANDIDATE CLOSED
```

Closure chain:

```text
S1  GENERAL CONVEX MANIFOLD + GRAPH LCP
    110/110 PASS

S2  ADAPTIVE CONVEX EVENTS + SAME-WORLD PARALLEL ISLANDS
    102/102 PASS

S3  UNIFIED EVENT-DRIVEN CONVEX TRAJECTORY
    101/101 PASS
```

S3 proves in one trajectory:

```text
2 islands -> 1 -> 2
8 rows -> 12 -> 8
2 threads -> 1 -> 2
localized appear -> graph merge -> source release -> localized disappear -> graph split
```

Refinement against `1e-11` reference is strictly decreasing for both complete rigid-body state and event times.

Energy/momentum:

```text
energy residual = 0
linear momentum error = 0
angular momentum error = 0
```

Exact remote preservation:

```text
S3 3/3 PASS
S2 5/5 PRESERVED
S1 8/8 PRESERVED
FABRIC0.15 7/7 PRESERVED
```

Project Control run `33350916275`: SUCCESS.

The checkpoint is closed only as a **research candidate**. Production promotion and the explicit non-claims in the design note remain open.
