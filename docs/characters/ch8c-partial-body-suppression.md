# CH8C — Partial base-body suppression for layered garments

## Problem

CH8B proved that `Male_Peasant.gltf` can be presented as three independent canonical equipment items:

- upper: `Male_Peasant_Body` + `Male_Peasant_Arms`;
- lower: `Male_Peasant_Legs`;
- feet: `Male_Peasant_Feet`.

The accepted base character is different: `SuperHero_Male` contains head, torso, arms, legs and feet in one skinned `MeshInstance3D` and one material surface. The CH7.8 whole-body head clip is correct for a full outfit, but cannot represent independent upper/lower/feet coverage.

## Separation of responsibilities

CH8C keeps three independent layers:

```text
canonical equipment snapshot
        |
        +--> CharacterEquipmentPresenter
        |       -> upper/lower/feet skinned garment visuals
        |
        +--> LayeredBodySuppressionCoordinator
                -> union presentation coverage
                -> one composite base-body material
```

The canonical domain still contains only item IDs, profiles, anchors and occupied equipment channels. It does not contain mesh names, clip thresholds, shaders or Quaternius knowledge.

## Coverage catalog

`WearableBodyCoverageCatalog` is presentation metadata keyed by `presentation_id + rig_profile_id`.

For the current real asset:

```text
wearable.layer.upper.peasant
    -> body.region.torso
    -> body.region.arms

wearable.layer.lower.peasant
    -> body.region.legs

wearable.layer.feet.peasant
    -> body.region.feet
```

Coverage is intentionally separate from canonical equipment occupancy. A jacket can occupy `body.torso.outer` while its concrete presentation may cover more or less of a particular rig.

## Aggregate coordinator

`LayeredBodySuppressionCoordinator` consumes a complete equipment snapshot, gathers all registered presentation coverage, sorts/deduplicates the semantic regions and asks the rig for one composite suppression result.

It is snapshot-driven rather than event/ref-count driven. Therefore an atomic canonical replacement goes directly from the old aggregate region set to the new aggregate region set without intermediate partial presentation states.

Unrelated items such as a helmet do not rebuild the material when the aggregate coverage set is unchanged.

When the last covered garment disappears, the exact original `material_override` is restored.

## Quaternius implementation

`QuaterniusLayeredBodySuppressionAdapter` maps the aggregate semantic region set to one `QuaterniusRegionClip` material on `SuperHero_Male`.

The material uses opaque fragment `discard`; it does not write alpha and does not modify vertices/triangles or the imported asset bytes.

The current thresholds are derived from the real base-body AABB using fractions chosen to match the observed modular-part bounds:

```text
feet max       = min_y + height * 0.30
legs max       = min_y + height * 0.60
torso min      = min_y + height * 0.49
torso max      = min_y + height * 0.87
arms min       = min_y + height * 0.73
arms max       = min_y + height * 0.88
torso half-x   = width * 0.22
arms inner-x   = width * 0.17
```

These are presentation fit parameters, not gameplay dimensions. Their graphical quality must be inspected and can be tuned without changing the equipment domain, gameplay body or network protocol.

## Compatibility

CH7.8 `MATERIAL_OVERRIDE` suppression remains unchanged and is still used for the accepted full `Male_Peasant` outfit/head-clip experiment.

CH8C does not modify the accepted `CharacterEquipmentPresenter`, `WearablePresentationCatalog` or `SkinnedGarmentPoseBridge` contracts. The aggregate coordinator runs beside the presenter.

The accepted CH6 shadow proxy synchronizes the source `material_override`, so the aggregate region clip follows the existing first-person shadow path.

## CH8C acceptance gates

Automated:

- upper alone enables torso+arms only;
- an unrelated helmet leaves the same material instance intact;
- lower adds/removes legs independently;
- feet adds/removes feet independently;
- upper+lower+feet produces four active semantic regions on one fused-body material;
- Eyes and Eyebrows remain visible;
- final garment removal restores exact original `material_override`;
- gameplay `CharacterBody3D` and capsule remain unchanged;
- graphical lab scene completes U/L/K lifecycle headlessly;
- accepted CH7.8, CH8A and CH8B runners remain green.

Graphical:

- U: upper garment covers torso/arms with no unacceptable base-body bleed;
- L: lower garment independently covers legs;
- K: feet garment independently covers feet;
- combinations do not remove the head;
- waist, shoulder, wrist/hand and boot boundaries are acceptable;
- movement, jump, crouch, FP/TP, helmet/backpack and shadow remain coherent.

## Deferred

- authored vertex masks or UV masks;
- per-garment custom suppression volumes;
- body morph fitting;
- cloth physics;
- production Item Graph equipment source;
- replication/persistence;
- performance optimization for large crowds.

If the coarse geometric mask is visually insufficient, CH8D should introduce authored presentation masks or generated per-rig mask metadata without changing canonical equipment semantics.
