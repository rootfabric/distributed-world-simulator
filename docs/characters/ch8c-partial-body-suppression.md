# CH8C — Protected base-body suppression for layered garments

## Problem

CH8B proved that `Male_Peasant.gltf` can be presented as three independent canonical equipment items:

- upper: `Male_Peasant_Body` + `Male_Peasant_Arms`;
- lower: `Male_Peasant_Legs`;
- feet: `Male_Peasant_Feet`.

The accepted base character is different: `SuperHero_Male` contains head, torso, arms, legs and feet in one skinned `MeshInstance3D` and one material surface. A full-body head clip works for a closed outfit, but open modular garments require finer coverage.

The graphical tuning history established two opposite failure modes:

1. coarse coverage removed underwear/pelvis and knees;
2. the first protected-overlay policy preserved those boundaries, but left base shins/feet visibly poking through trousers and boots.

CH8C fix5 keeps the protected-boundary idea and adds fine lower-leg/foot cores instead of returning to coarse whole-leg suppression.

## Current Peasant coverage policy

```text
upper
    canonical channels: body.torso.outer + body.arms.outer
    garment meshes: Body + Arms
    body suppression: body.region.torso.core
    preserved: base arms, pelvis/underwear, legs, feet

lower
    canonical channel: body.legs.outer
    garment mesh: Legs
    body suppression:
        body.region.thighs.core
        body.region.shins.core
    preserved: pelvis/underwear and an explicit knee band

feet
    canonical channel: body.feet
    garment mesh: Feet
    body suppression:
        body.region.feet.core
    preserved: coarse body semantics; only the enclosed ankle/foot core is removed
```

This is presentation metadata only. Canonical equipment still knows only item/profile/channel semantics; it does not know Quaternius mesh names, shader thresholds or fine clip regions.

## Coarse and fine body regions

Coarse regions remain available for closed garments such as EVA/full-body suits:

```text
body.region.torso
body.region.arms
body.region.legs
body.region.feet
```

The layered Quaternius adapter adds fine regions:

```text
body.region.torso.core
body.region.thighs.core
body.region.shins.core
body.region.feet.core
```

The old meanings are not weakened. A different wearable can choose coarse or fine coverage independently through `WearableBodyCoverageCatalog`.

## Aggregate architecture

```text
canonical equipment snapshot
        |
        +--> CharacterEquipmentPresenter
        |       -> independent skinned garment visuals
        |
        +--> WearableBodyCoverageCatalog
                -> rig-specific presentation coverage
                |
                v
        LayeredBodySuppressionCoordinator
                -> union/sort coverage
                -> one composite base-body material
```

The coordinator is snapshot-driven. Atomic canonical replacement therefore yields one final aggregate material rather than a sequence of intermediate masks.

When no equipped item contributes body coverage, the exact original `material_override` is restored.

## Quaternius fine-region material

`QuaterniusRegionClip` uses rest/model coordinates from the fused base mesh and opaque fragment `discard`. It does not write alpha, modify vertices/triangles, collision, gameplay body or imported asset bytes.

For the current base-body AABB, fix5 uses:

```text
torso.core min      = min_y + height * 0.56
torso.core max      = min_y + height * 0.86
torso.core half-x   = width  * 0.20

thighs.core min     = min_y + height * 0.39
thighs.core max     = min_y + height * 0.56
thighs.core half-x  = width  * 0.16

shins.core min      = min_y + height * 0.24
shins.core max      = min_y + height * 0.33
shins.core half-x   = width  * 0.14

feet.core max       = min_y + height * 0.25
feet.core half-x    = width  * 0.14
```

The real modular-part probe measured approximately:

```text
Male_Peasant_Legs  y = 0.403 .. 1.054 m
Male_Peasant_Feet  y = -0.004 .. 0.448 m
```

So the fine cuts intentionally follow the actual garment overlap.

### Protected knee band

The knee remains visible because there is an explicit gap between:

```text
shins.core max
        < knee band <
thighs.core min
```

For the current base proportions that gap is roughly 0.59 .. 0.70 m. This avoids the earlier failure where a coarse `legs` clip removed the knee completely.

### Boot/shin seam

`feet.core` reaches slightly into the lower boundary of `shins.core`. This overlap is intentional: it prevents a narrow strip of base geometry from leaking through between trousers and the foot/boot mesh.

## Compatibility

CH7.8 full-outfit head-clip behavior remains unchanged.

CH8C fix5 does not modify accepted `CharacterEquipmentPresenter`, `WearablePresentationCatalog` or `SkinnedGarmentPoseBridge` contracts. It does not alter canonical equipment, Item Graph, collision or network protocol.

The CH6 first-person shadow proxy continues to synchronize the source `material_override` through the existing path.

## CH8C fix5 acceptance gates

Automated:

- `upper` uses `torso.core` and never coarse arm/leg/feet suppression;
- `lower` uses exactly `thighs.core + shins.core`;
- the knee band between shin and thigh cuts remains non-zero;
- `feet` contributes `feet.core` rather than coarse `feet`;
- foot and shin cores overlap enough to avoid a vertical seam;
- removing lower leaves only foot coverage when boots remain;
- removing the final covered item restores the exact original material;
- graphical lab reports four fine regions for U+L+K;
- gameplay `CharacterBody3D` and capsule remain unchanged;
- the full runner rejects any Godot `ERROR:` line;
- accepted CH7.8, CH8A and CH8B regressions remain green.

Graphical:

- underwear/pelvis remains visible where the upper/lower garments are open;
- the deliberate knee opening remains visible;
- base shin geometry no longer pokes through the trousers;
- base ankle/foot geometry no longer pokes through the foot/boot mesh;
- U+L+K remains coherent in idle/walk/run/jump/crouch;
- helmet/backpack, FP/TP and shadow remain coherent.

## Future refinement

These rest-coordinate cores are still prototype fit metadata. If a garment needs holes or silhouettes that cannot be represented by a few geometric bands, the next step is authored vertex/UV coverage masks or per-garment generated coverage data. That remains presentation-only and must not leak into canonical Item Graph or networking semantics.
