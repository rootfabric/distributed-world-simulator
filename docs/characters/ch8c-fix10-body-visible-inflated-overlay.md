# CH8C fix10 — Body-visible inflated overlay

## Motivation

Graphical tuning of the Peasant layered garments showed that body-occlusion masks can solve penetration but may also remove real body geometry above cuffs/collars. The user-requested fix10 experiment therefore changes the default layered fit policy:

```text
base body = always intact
wearable  = slightly larger temporary skinned shell
```

No imported asset, gameplay body, Item Graph state, or network state is changed.

## Default policy

`QuaterniusLayeredEquipmentLab.body_fit_policy` now defaults to:

```text
BODY_VISIBLE_INFLATED_OVERLAY
```

For this policy:

- `SuperHero_Male.mesh` stays the exact imported resource;
- `SuperHero_Male.material_override` stays the exact original resource;
- `LayeredBodySuppressionCoordinator` has zero active regions;
- `LayeredBodyTopologyOcclusionCoordinator` has zero active presentations;
- removed body triangles = 0;
- only wearable presentation meshes are changed.

The previous `TOPOLOGY_OCCLUSION` path remains available as an explicit fallback for closed armor/EVA or future garments where removing covered body geometry is desirable.

## Clothing-only surfaces

The Quaternius `Male_Peasant_Arms` mesh contains both:

```text
MI_Peasant
MI_Regular_Male
```

When the real base body stays visible, rendering the embedded `MI_Regular_Male` skin would duplicate skin geometry. Therefore `GarmentVertexInflationSceneFactory` accepts an optional material allowlist.

The fix10 default passes:

```text
["MI_Peasant"]
```

so wearable scenes contain/inflate only actual clothing surfaces. The base character supplies all skin.

## Inflation profiles

Offsets are rest-mesh offsets along each source normal before normal skinning.

```text
upper
  4 mm -> 7 mm -> 8 mm -> 4 mm

lower
  6 mm -> 10 mm -> 14 mm -> 12 mm -> 6 mm

feet
  5 mm -> 8 mm -> 12 mm -> 16 mm
```

These values are intentionally presentation-only tuning metadata. They can be reduced if garments visibly float or increased locally if small penetration remains during animation.

## Why not node scale

Whole-node scale moves cuffs, belts and boots away from their attachment relationships and changes all axes from the node origin. Vertex inflation instead changes local shell thickness while preserving:

- skeleton binding;
- bone indices;
- weights;
- indices;
- UV/material arrays;
- canonical equipment semantics.

## Fallback preservation

Tests for topology occlusion and HIGH_BOOT coverage explicitly set:

```text
body_fit_policy = TOPOLOGY_OCCLUSION
```

before the lab enters the tree. Thus fix10 does not delete the previous machinery; it only changes the default graphical experiment.

## Acceptance

Automated default-policy gates must prove for U/L/K and all combinations:

- body mesh resource identity never changes;
- body material resource identity never changes;
- no material suppression regions become active;
- no topology descriptor becomes active;
- no body triangle is removed;
- upper/lower/feet all have inflation reports;
- upper filters at least the embedded non-clothing skin surface;
- only `MI_Peasant` is selected for wearable inflation;
- CharacterBody3D and capsule stay unchanged.

Graphical acceptance must inspect idle, walk, run, turn, jump and crouch. Required behavior:

- no body part is cut away above boots or trouser openings;
- skin does not penetrate solid cloth/boot surfaces during motion;
- intentional holes reveal the intact base body;
- garments do not look excessively ballooned;
- FP/TP and shadows remain coherent.
