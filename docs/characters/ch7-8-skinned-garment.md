# CH7.8 — Minimal skinned garment experiment

## Goal

Prove one real rigged outfit on the accepted CH7 semantic equipment architecture with the smallest possible increase in complexity.

This stage is intentionally **not** a full wardrobe system and **not** cloth simulation.

## Selected asset family

Use Quaternius **Modular Character Outfits - Fantasy**, Standard package, current v2.1-compatible download.

Why this family:

- authored by the same creator as Universal Base Characters;
- explicitly compatible with Universal Base Characters;
- humanoid rig and Universal Animation Library compatible;
- glTF/FBX are available in the Standard package;
- CC0;
- the Base Characters were updated with Head/Upperbody variants for this outfit family;
- v2.0 specifically improved modularity and clipping, and notes that Peasant_Male works with only the Base Character head;
- v2.1 fixed GLTF export/content issues for several outfits.

For the first prototype prefer **Peasant_Male** if present in the Standard archive. It is not a gameplay commitment; it is a compatibility probe.

## External asset location

Do not commit the downloaded 280 MB package into the feature branch.

Extract the Standard package under:

```text
assets/external/quaternius/modular_outfits_fantasy/
```

The probe deliberately scans recursively, so the archive's internal directory layout does not need to be renamed.

## Minimal presentation strategy

The first successful garment should be treated as a **skinned outfit assembly**, not arbitrary cloth layered over a complete visible naked/base body.

Initial semantic equipment profile:

```text
profile_id:       equipment.outfit.peasant_male.prototype
presentation_id:  wearable.outfit.peasant_male.prototype
preferred_anchor: body.root
occupied channels:
  body.torso.outer
  body.arms.outer
  body.legs.outer
```

It remains **one canonical equipment item** occupying multiple semantic channels.

### Body visibility

For the first prototype use coarse semantic replacement:

```text
body.region.torso
body.region.arms
body.region.legs
```

Prefer a compatible Base Character `Head`/`Upperbody` presentation variant if the downloaded files expose one. This is intentionally simpler and safer than per-triangle masking.

Do not introduce shader cut masks, mesh surgery, body morphs or runtime vertex editing in CH7.8.

## Rig strategy

The outfit may contain its own Skeleton3D. CH7.8 is allowed to keep that skeleton as a presentation object, but it must be driven from the already authoritative avatar presentation pose.

Target implementation order:

1. Probe actual Standard-package files and skeletons.
2. Choose one Peasant_Male-compatible scene with the highest normalized bone overlap with the accepted Universal Base Character rig.
3. Add a `SKINNED_GARMENT` presentation strategy without changing the equipment domain.
4. Build a normalized bone map from the avatar Skeleton3D to the garment Skeleton3D.
5. Copy pose only in presentation processing; no gameplay transforms, input, network state or Item Graph mutations.
6. Hide/replace coarse semantic body regions for this one outfit.
7. Refresh the accepted CH6 FP/TP/world-shadow composition after equip/unequip.

## Explicitly deferred

- cloth physics;
- skirts/capes with secondary simulation;
- arbitrary garments from unrelated skeletons;
- runtime retarget profile authoring UI;
- body shape morphing;
- automatic garment fitting;
- dozens of simultaneous clothing pieces;
- production ItemGraphEquipmentSource bridge;
- network/persistence integration.

## Acceptance ladder

### CH7.8-A — Asset probe

PASS when the external Standard pack is found and at least one rigged outfit scene reports strong normalized bone overlap with the accepted base rig.

### CH7.8-B — One skinned outfit

PASS when one outfit follows idle/walk/run/jump/crouch without independent animation authority.

### CH7.8-C — Body-region replacement

PASS when the outfit does not visibly fight the base torso/arms/legs and no gameplay body/collision changes are used to solve clipping.

### CH7.8-D — CH6 composition

PASS when FP/TP visibility and first-person shadow preservation continue to work after outfit equip/unequip.

### CH7.8-E — Lifecycle

PASS when repeated equip/unequip leaves one canonical item, no duplicate garment presentation and no orphan garment skeleton.

Only after this should the generic garment system be widened to a second outfit or more granular layered clothing.
