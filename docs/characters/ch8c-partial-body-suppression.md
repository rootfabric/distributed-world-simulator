# CH8C — Layered garment fit policy

## Goal

CH8B proved that `Male_Peasant.gltf` can be presented as three independent equipment visuals on the accepted 65-bone Quaternius rig:

- upper: `Male_Peasant_Body` + `Male_Peasant_Arms`;
- lower: `Male_Peasant_Legs`;
- feet: `Male_Peasant_Feet`.

CH8C solves visual overlap against the fused `SuperHero_Male` base body without moving `CharacterBody3D`, changing collision, mutating Item Graph, or adding mesh-specific state to networking.

## What graphical tuning proved

Five visual iterations established the limits and the accepted direction:

1. coarse whole-body clipping removed underwear/pelvis and knees;
2. protected fine regions preserved those boundaries but allowed skin to poke through trousers/footwear;
3. adding shin/foot clip regions removed skin where open garments must reveal it;
4. outward `BaseMaterial3D.grow` preserved skin topology but still could not guarantee that the garment shell stayed outside the more voluminous base leg in every pose;
5. topology-aware occlusion fixed the trousers, while the tall Peasant footwear still showed a small residual calf penetration near the upper boot shaft.

The fifth observation is important: the topology approach is correct, but different garment shapes need different **topology acceptance policies**. A torn trouser should be conservative around openings, while a tall boot may be more aggressive only near its upper shaft.

## Final CH8C policy

### Closed garment

A closed garment may use semantic body suppression where the covered area is unambiguous.

Current Peasant upper:

```text
wearable.layer.upper.peasant
    material body suppression -> body.region.torso.core
```

### Open/torn garment

Open trousers do not use spatial body bands and do not rely on surface grow.

```text
wearable.layer.lower.peasant
    material body suppression -> none
    topology occlusion -> Male_Peasant_Legs geometry
    coverage mode -> ROBUST
```

The base body remains present where the garment has no nearby surface: through actual holes and below real cuffs. Only base-body triangles close to actual garment geometry are removed from a temporary presentation mesh.

### Tall footwear

`Male_Peasant_Feet` visually behaves as a tall boot. Fix7 robust topology removed the foot/ankle penetration but left a small amount of calf geometry visible through the upper shaft.

Fix8 introduces an explicit `HIGH_BOOT` topology mode for this presentation only:

```text
wearable.layer.feet.peasant
    topology occlusion -> Male_Peasant_Feet geometry
    coverage mode      -> HIGH_BOOT
    threshold          -> 0.045 m
    boundary pad       -> 0.006 m
    upper Y guard      -> 0.012 m
    upper bias start   -> 52% of boot AABB height
```

`HIGH_BOOT` keeps the same real garment topology and proximity-grid model as `ROBUST`, but in the upper part of the boot it may remove a base-body triangle when one sampled point is covered instead of requiring two. This is intentionally scoped to the upper shaft/calf zone. Below that band it keeps the normal robust rule.

The upper Y guard is small and one-sided. It exists to cover deformation around the boot collar; it does not turn the mask into a global leg-height clip.

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
                -> PackedScene
                -> threshold / boundary pad
                -> coverage mode
                -> optional high-boot upper bias
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

For each active topology garment it:

1. instantiates the selective garment scene;
2. samples garment triangle vertices, edge midpoints and centroids in rig/model space;
3. stores those samples in a spatial grid;
4. examines triangles from the original fused base-body mesh;
5. applies the descriptor-specific triangle acceptance mode;
6. rejects matches outside the garment AABB except for configured small boundary guards;
7. rebuilds an `ArrayMesh` with the original vertex/bone/weight arrays and a filtered index array.

Consequences:

- a real hole in the trousers has no garment samples in its center, so skin can remain there;
- below the actual trouser cuff the garment AABB boundary prevents the mask from continuing down the leg;
- `HIGH_BOOT` can be more aggressive around the upper calf without changing trouser behavior;
- adding footwear unions the trouser and footwear topology masks;
- removing one item always rebuilds from the exact original body mesh, never incrementally from an already masked mesh.

Current prototype fit metadata:

```text
Male_Peasant_Legs
    mode             = ROBUST
    threshold        = 0.045 m
    boundary pad     = 0.006 m

Male_Peasant_Feet
    mode             = HIGH_BOOT
    threshold        = 0.045 m
    boundary pad     = 0.006 m
    upper Y guard    = 0.012 m
    upper bias start = 0.52
```

These are presentation-fit metadata and can be tuned without changing equipment semantics.

## Runtime lifecycle

`LayeredBodyTopologyOcclusionCoordinator` owns only presentation mesh substitution.

```text
no lower/feet
    SuperHero_Male.mesh = exact imported mesh

lower
    SuperHero_Male.mesh = derived mesh masked by ROBUST trouser topology

lower + feet
    SuperHero_Male.mesh = derived union of trouser + HIGH_BOOT footwear masks

feet only
    rebuild from original mesh using HIGH_BOOT footwear topology only

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

## Fix8 automated gates

The high-boot tuning must prove:

- `wearable.layer.lower.peasant` stays `ROBUST` at `0.045 m` with no high-boot upper padding;
- `wearable.layer.feet.peasant` resolves as `HIGH_BOOT` at `0.045 m`;
- footwear upper Y guard is exactly `0.012 m`;
- footwear upper bias starts inside, not outside, the real footwear AABB;
- feet-only removes some but not all body triangles;
- lower+feet removes more body triangles than lower-only;
- removing feet from the union deterministically restores the exact lower-only mask count;
- removing all lower garments restores exact original mesh identity;
- base material, gameplay `CharacterBody3D`, and capsule remain unchanged;
- graphical lab status exposes the high-boot mode so the Windows screenshot can be tied to exact fit metadata;
- the runner continues to reject any Godot `ERROR:` line.

## Graphical acceptance

Inspect `K`, `L+K`, then `U+L+K` in idle/walk/run/jump/crouch.

Required result:

- trousers retain the already-correct fix7 appearance;
- residual calf skin no longer penetrates the solid upper boot shaft;
- skin above the actual boot collar is not removed;
- intentionally open footwear areas retain skin rather than becoming holes;
- underwear/pelvis remains intact;
- helmet/backpack, FP/TP and shadow remain coherent.

If the calf still barely penetrates, tune only `FEET_TOPOLOGY_THRESHOLD_M`, `FEET_TOPOLOGY_UPPER_Y_PAD_M`, or `FEET_TOPOLOGY_UPPER_BIAS_FRACTION`. Do not change the trouser descriptor and do not return to global lower-leg Y clipping.
