# CH8C — Layered garment fit policy

## Goal

CH8B proved that `Male_Peasant.gltf` can be presented as three independent equipment visuals on the accepted 65-bone Quaternius rig:

- upper: `Male_Peasant_Body` + `Male_Peasant_Arms`;
- lower: `Male_Peasant_Legs`;
- feet: `Male_Peasant_Feet`.

CH8C solves visual overlap against the fused `SuperHero_Male` base body without moving `CharacterBody3D`, changing collision, mutating Item Graph, or adding mesh-specific state to networking.

## What graphical tuning proved

Four visual iterations established the limits of the simple approaches:

1. coarse whole-body clipping removed underwear/pelvis and knees;
2. protected fine regions preserved those boundaries but allowed skin to poke through trousers/footwear;
3. adding shin/foot clip regions removed skin where open garments must reveal it;
4. outward `BaseMaterial3D.grow` preserved skin topology but still could not guarantee that the garment shell stayed outside the more voluminous base leg in every pose.

The fourth observation is decisive: open/torn garments need **topology-aware body occlusion**. Their own triangles must define where base-body geometry may be hidden.

## Final CH8C policy

### Closed garment

A closed garment may use semantic body suppression where the covered area is unambiguous.

Current Peasant upper:

```text
wearable.layer.upper.peasant
    material body suppression -> body.region.torso.core
```

### Open/torn garment

Open trousers/footwear do not use spatial body bands and do not rely on surface grow.

Current Peasant lower/feet:

```text
wearable.layer.lower.peasant
    material body suppression -> none
    topology occlusion -> Male_Peasant_Legs geometry

wearable.layer.feet.peasant
    material body suppression -> none
    topology occlusion -> Male_Peasant_Feet geometry
```

The base body remains present where the garment has no nearby surface: through actual holes and below real cuffs. Only base-body triangles close to actual garment geometry are removed from a temporary presentation mesh.

## Topology-aware architecture

```text
canonical equipment snapshot
        |
        +--> CharacterEquipmentPresenter
        |       -> unchanged skinned garment visuals
        |
        +--> WearableBodyCoverageCatalog
        |       -> closed-region material suppression
        |
        +--> WearableBodyTopologyCatalog
                -> open-garment PackedScene + fit threshold
                |
                v
        LayeredBodyTopologyOcclusionCoordinator
                -> aggregate equipped topology descriptors
                -> GarmentTopologyOcclusionBuilder
                -> temporary derived SuperHero_Male ArrayMesh
```

This keeps the invariant:

```text
canonical equipment != body-fit metadata != presentation geometry
```

## GarmentTopologyOcclusionBuilder

The builder works once per equipment topology state, not per frame.

For each active open garment it:

1. instantiates the selective garment scene;
2. samples garment triangle vertices, edge midpoints and centroids in rig/model space;
3. stores those samples in a spatial grid;
4. examines triangles from the original fused base-body mesh;
5. removes a base-body triangle only when its centroid or enough edge/vertex samples are close to actual garment samples;
6. rejects matches outside the garment AABB except for a very small boundary pad;
7. rebuilds an `ArrayMesh` with the original vertex/bone/weight arrays and a filtered index array.

Consequences:

- a real hole in the trousers has no garment samples in its center, so skin can remain there;
- below the actual trouser cuff the garment AABB boundary prevents the mask from continuing down the leg;
- adding footwear unions the trouser and footwear topology masks;
- removing one item always rebuilds from the exact original body mesh, never incrementally from an already masked mesh.

Current prototype fit thresholds:

```text
Male_Peasant_Legs: threshold = 0.045 m
Male_Peasant_Feet: threshold = 0.035 m
boundary pad:                 0.006 m
```

These are presentation-fit metadata and can be tuned without changing equipment semantics.

## Runtime lifecycle

`LayeredBodyTopologyOcclusionCoordinator` owns only presentation mesh substitution.

```text
no lower/feet
    SuperHero_Male.mesh = exact imported mesh

lower
    SuperHero_Male.mesh = derived mesh masked by trouser topology

lower + feet
    SuperHero_Male.mesh = derived union mask

feet only
    rebuild from original mesh using footwear topology only

none again
    restore exact imported mesh resource identity
```

The existing `LayeredBodySuppressionCoordinator` remains independent and handles the upper `torso.core` material clip.

## Compatibility

CH8C topology occlusion does not modify accepted:

- `CharacterEquipmentPresenter`;
- `WearablePresentationCatalog`;
- `SkinnedGarmentPoseBridge`;
- CH7.8 full-outfit head-clip path;
- CH8A canonical layered-equipment semantics;
- CH8B selective real-part semantics.

It does not change:

- Item Graph;
- network protocol;
- persistence;
- gameplay body/capsule;
- imported Quaternius asset bytes.

The derived mesh preserves source vertices, bones and weights and changes only presentation triangle indices.

## Why surface grow is no longer the accepted path

`BaseMaterial3D.grow` remains a useful general rendering tool, but graphical observation proved that a fixed outward offset cannot guarantee separation from this specific base-body shape across all regions/poses. Increasing grow further would visibly inflate the garment while still not encoding where real openings are.

Therefore fix6 surface-fit is retained only as an experimental utility and is not part of the CH8C acceptance runner.

## Automated gates

The CH8C topology candidate must prove:

- lower-only applies a derived base-body mesh and removes some but not all body triangles;
- the base-body material remains unchanged for lower/feet;
- the derived mesh preserves source bone/weight array sizes;
- lower+feet creates an aggregate topology mask;
- feet-only recomposes from the original body mesh;
- removing all open garments restores exact original mesh identity;
- upper-only keeps original mesh topology and uses only `body.region.torso.core` material suppression;
- gameplay `CharacterBody3D` and capsule remain unchanged;
- graphical lab lifecycle reports topology state and completes without Godot `ERROR:` lines;
- accepted CH7.8, CH8A and CH8B regression remains green.

## Graphical acceptance

Inspect `L`, `K`, `L+K`, then `U+L+K` in idle/walk/run/jump/crouch.

Required result:

- trousers no longer show unacceptable base-leg poke-through on cloth surfaces;
- skin remains visible through intended garment openings;
- leg remains below the real trouser cuff;
- footwear does not show unacceptable base-foot penetration;
- open footwear areas still contain skin instead of holes;
- underwear/pelvis remains intact;
- helmet/backpack, FP/TP and shadow remain coherent.

If the topology result is correct but an edge is slightly too aggressive or too permissive, tune only the per-garment proximity threshold/boundary pad. Do not return to global lower-leg Y clipping.
