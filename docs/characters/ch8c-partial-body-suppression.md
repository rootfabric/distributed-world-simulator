# CH8C — Protected base-body suppression for layered garments

## Problem

CH8B proved that `Male_Peasant.gltf` can be presented as three independent canonical equipment items:

- upper: `Male_Peasant_Body` + `Male_Peasant_Arms`;
- lower: `Male_Peasant_Legs`;
- feet: `Male_Peasant_Feet`.

The accepted base character is different: `SuperHero_Male` contains head, torso, arms, legs and feet in one skinned `MeshInstance3D` and one material surface. The CH7.8 whole-body head clip is correct for a closed full outfit, but is too coarse for open layered garments.

The first CH8C graphical observation exposed exactly this problem:

- equipping the upper garment removed the visible underwear/pelvis area;
- equipping the lower garment removed the knee band;
- the coarse mask therefore created holes at garment boundaries even though the garment meshes themselves were correct.

## Policy: suppress cores, preserve open boundaries

CH8C fix4 uses a hybrid presentation rule.

We do **not** disable body suppression globally: an inner body surface can still poke through tight garments during animation. Instead, layered garments suppress only the body volume safely inside the garment and leave open boundaries rendered underneath.

For the current Peasant parts:

```text
upper
    canonical channels: body.torso.outer + body.arms.outer
    garment meshes: Body + Arms
    body suppression: body.region.torso.core only
    preserved base: arms, pelvis/underwear, legs, feet

lower
    canonical channel: body.legs.outer
    garment mesh: Legs
    body suppression: body.region.thighs.core only
    preserved base: pelvis/underwear, knees, lower legs, feet

feet
    canonical channel: body.feet
    garment mesh: Feet
    body suppression: none (overlay-only)
    preserved base: complete foot/ankle extremity
```

This distinction is presentation-only. Canonical occupancy remains `torso.outer / arms.outer / legs.outer / feet`; it does not learn about `torso.core`, `thighs.core`, shaders or Quaternius geometry.

## Coarse vs fine coverage regions

The original coarse semantic regions remain available:

```text
body.region.torso
body.region.arms
body.region.legs
body.region.feet
```

They are still useful for closed/full-body garments such as an EVA suit.

Layered Quaternius presentation adds two finer regions:

```text
body.region.torso.core
body.region.thighs.core
```

`QuaterniusLayeredBodySuppressionAdapter` supports both sets. This avoids weakening the meaning of the old coarse regions.

## Separation of responsibilities

```text
canonical equipment snapshot
        |
        +--> CharacterEquipmentPresenter
        |       -> upper/lower/feet skinned garment visuals
        |
        +--> WearableBodyCoverageCatalog
                -> presentation-only coverage metadata
                |
                v
        LayeredBodySuppressionCoordinator
                -> union fine/coarse coverage
                -> one composite material
```

The canonical domain still contains only item IDs, profiles, anchors and occupied equipment channels. It does not contain mesh names, clip thresholds, shaders or Quaternius knowledge.

## Aggregate coordinator

`LayeredBodySuppressionCoordinator` consumes the complete equipment snapshot, gathers all registered presentation coverage, sorts/deduplicates the semantic regions and asks the rig for one composite suppression result.

It is snapshot-driven rather than event/ref-count driven. Therefore an atomic canonical replacement goes directly from the old aggregate region set to the new aggregate region set without intermediate partial presentation states.

Unrelated items such as a helmet do not rebuild the material when the aggregate coverage set is unchanged.

An overlay-only garment is allowed to have an empty coverage set. Equipping such an item changes canonical/presentation state but does not modify the base-body material.

When no equipped garment contributes body coverage, the exact original `material_override` is restored even if overlay-only garments remain equipped.

## Quaternius protected material

`QuaterniusRegionClip` keeps the existing coarse masks for closed garments and adds protected fine masks for layered garments.

For the current `SuperHero_Male` AABB, the fine thresholds are derived from the body dimensions:

```text
torso.core min      = min_y + height * 0.56
torso.core max      = min_y + height * 0.86
torso.core half-x   = width  * 0.20

thighs.core min     = min_y + height * 0.39
thighs.core max     = min_y + height * 0.56
thighs.core half-x  = width  * 0.16
```

With the observed real asset this is roughly:

```text
torso core  ~1.01 .. 1.55 m
thigh core  ~0.70 .. 1.01 m
```

The intent is explicit:

- below the torso core remains the underwear/pelvis boundary;
- below the thigh core remains the knee/lower-leg boundary;
- base arms are not removed for the Peasant upper;
- base feet are not removed for the current Peasant feet item.

The shader still uses opaque fragment `discard`; it does not write alpha and does not modify vertices/triangles or imported asset bytes.

## Compatibility

CH7.8 full-outfit `MATERIAL_OVERRIDE` head-clip path remains unchanged.

CH8C does not modify the accepted `CharacterEquipmentPresenter`, `WearablePresentationCatalog` or `SkinnedGarmentPoseBridge` contracts. The aggregate coordinator runs beside the presenter.

The CH6 shadow proxy continues to synchronize source `material_override` through the existing path.

## CH8C fix4 acceptance gates

Automated:

- upper enables `torso.core` only;
- upper does not enable coarse torso/arms/legs/feet suppression;
- torso-core lower boundary preserves a pelvis/underwear band;
- unrelated helmet leaves aggregate material identity unchanged;
- lower adds `thighs.core` only;
- thigh-core lower boundary preserves knee/lower-leg geometry;
- feet is overlay-only and does not rebuild the aggregate body material;
- upper+lower+feet produces exactly two active fine coverage regions;
- removing upper+lower restores the exact original material even while feet remains equipped;
- Eyes and Eyebrows remain visible;
- gameplay `CharacterBody3D` and capsule remain unchanged;
- graphical lab U/L/K lifecycle passes headlessly with no Godot `ERROR:` lines;
- accepted CH7.8, CH8A and CH8B regression remains green.

Graphical:

- U: shirt appears without removing underwear/pelvis or arms;
- L: lower garment appears without removing knees/lower legs;
- K: feet part layers without removing the base extremity;
- U+L+K has no unacceptable body poke-through through the central garment surfaces;
- head remains visible;
- movement, jump, crouch, FP/TP, helmet/backpack and shadow remain coherent.

## Future refinement

Fine geometric cores are still a prototype fit strategy. Different garments may require different coverage metadata.

If body poke-through remains visible after protected cores, the next refinement should be authored vertex/UV masks or per-garment coverage volumes. That refinement remains presentation metadata and must not change canonical equipment semantics, Item Graph or network protocol.
