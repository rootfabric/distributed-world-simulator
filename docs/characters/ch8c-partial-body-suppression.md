# CH8C — Layered garment fit policy

## Goal

CH8B proved that `Male_Peasant.gltf` can be presented as three independent equipment visuals on the accepted 65-bone Quaternius rig:

- upper: `Male_Peasant_Body` + `Male_Peasant_Arms`;
- lower: `Male_Peasant_Legs`;
- feet: `Male_Peasant_Feet`.

The remaining problem is presentation fit against the fused `SuperHero_Male` base body. The canonical equipment domain is already correct; CH8C must solve overlap without moving `CharacterBody3D`, changing collision, mutating Item Graph, or adding mesh-specific state to networking.

## What the graphical tuning proved

Three visual iterations established the boundary of region clipping:

1. coarse whole-body regions removed underwear/pelvis and knee geometry;
2. protected fine regions preserved those boundaries but allowed base leg/foot geometry to poke through garments;
3. extending fine shin/foot clipping reduced poke-through but again removed skin that must remain visible below open cuffs and through open/torn garment topology.

The third observation is decisive: `Male_Peasant_Legs` and `Male_Peasant_Feet` are **open garments**. A body mask based only on spatial bands cannot know where the garment has holes/open edges. Making that mask more aggressive trades penetration for missing limbs.

Therefore fix6 introduces two explicit presentation policies.

## Policy A — closed garment: body suppression

Closed garments that completely cover an area may suppress the base body underneath.

Current Peasant upper uses this only for the safely enclosed shirt core:

```text
wearable.layer.upper.peasant
    body coverage -> body.region.torso.core
```

The base arms and underwear/pelvis remain visible. Coarse regions remain available for future EVA/full-body suits:

```text
body.region.torso
body.region.arms
body.region.legs
body.region.feet
```

## Policy B — open/torn garment: surface-fit overlay

Open trousers, sandals/boots with openings, sleeves with intentional skin gaps, and similar garments must keep the base body intact.

For current Peasant lower/feet:

```text
wearable.layer.lower.peasant
    body coverage -> none
    presentation fit -> outward garment grow 0.010 m

wearable.layer.feet.peasant
    body coverage -> none
    presentation fit -> outward garment grow 0.008 m
```

Only the wearable presentation shell moves outward. The base leg/foot is not clipped, so skin remains available through garment holes and below cuffs.

Godot `BaseMaterial3D` provides vertex grow: when enabled, vertices are displaced along their normals. CH8C uses that feature on **duplicated per-scene materials**, never on the imported/shared asset material.

## Surface-fit implementation

`GarmentSurfaceFitSceneFactory` takes an already selective `PackedScene` and a small grow distance.

It:

1. instantiates the selective scene;
2. visits all garment `MeshInstance3D` surfaces;
3. resolves each effective `BaseMaterial3D`;
4. duplicates the material locally;
5. enables vertex grow and applies the requested amount;
6. installs the duplicate as a surface/material override;
7. repacks a temporary presentation-only `PackedScene`.

The source glTF, source mesh resource, and imported/shared materials are not mutated.

Guard rails:

```text
grow > 0
max grow = 0.05 m
current lower = 0.010 m
current feet  = 0.008 m
```

These values are asset-fit metadata. They are intentionally not equipment channels or gameplay dimensions.

## Separation of responsibilities

```text
canonical equipment snapshot
        |
        +--> CharacterEquipmentPresenter
        |       -> independent skinned garment visuals
        |       -> fitted temporary lower/feet scenes
        |
        +--> WearableBodyCoverageCatalog
                -> only actual closed-body coverage
                |
                v
        LayeredBodySuppressionCoordinator
                -> torso.core for current upper
                -> no leg/foot clipping for current open garments
```

This keeps the invariant:

```text
canonical equipment != rig fit != rendered garment geometry
```

## Why not keep adding local clip volumes

Local boxes/cylinders can improve a closed garment, but they still cannot express arbitrary holes or torn boundaries without authored mask data. For the current trousers a volume large enough to remove every penetration also removes skin that must remain visible.

Surface-fit overlay is the lowest-complexity solution that respects the actual garment topology: the garment itself defines where cloth exists.

If grow is insufficient for some future asset, the next escalation is authored UV/vertex coverage or a precomputed garment-to-body mask, not wider Y bands.

## Compatibility

Fix6 does not modify accepted:

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

## Fix6 automated gates

The candidate must prove:

- surface-fit factory duplicates materials rather than mutating the selected source scene;
- lower visual uses grow `0.010 m`;
- feet visual uses grow `0.008 m`;
- lower alone contributes zero body suppression regions;
- feet alone contributes zero body suppression regions;
- lower+feet leave the exact original base-body `material_override` intact;
- upper+lower+feet has exactly `body.region.torso.core` active;
- toggling lower/feet while upper remains equipped does not rebuild the torso mask;
- removing upper restores the exact original base material while lower/feet remain equipped;
- gameplay body and capsule remain unchanged;
- the graphical lab lifecycle is clean with no Godot `ERROR:` lines;
- accepted CH7.8, CH8A and CH8B regression stays green.

## Fix6 graphical acceptance

Inspect `L`, `K`, and `L+K` in idle, walking, jumping and crouching.

Required result:

- trousers no longer show unacceptable leg poke-through;
- the leg remains visible below the actual trouser cuff and through intentional openings;
- footwear no longer shows unacceptable foot/ankle poke-through;
- open skin areas remain present instead of becoming holes;
- underwear/pelvis remains visible where intended;
- upper, helmet, backpack, FP/TP and shadow remain coherent.

If a small residual intersection remains, tune `LOWER_SURFACE_GROW_M` or `FEET_SURFACE_GROW_M` by millimeters. Do not reintroduce lower-leg body clipping for this open asset.
