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
IN PROGRESS
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
