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

The asset probe selected **Male_Peasant.gltf** from the Godot-Unreal glTF export. The real Windows probe measured 65 base bones, 65 garment bones, 65 matched bones, overlap 1.0/1.0 and four skinned garment meshes. Arbitrary retargeting is therefore not required for this prototype.

## External asset location

Do not commit the downloaded package into the feature branch.

Extract the Standard package under:

```text
assets/external/quaternius/modular_outfits_fantasy/
```

The Base Characters and Universal Animation Library remain under their existing external roots.

## Canonical equipment model

The first outfit remains **one canonical equipment item** even though its presentation contains multiple skinned mesh parts.

```text
profile_id:       equipment.outfit.peasant_male.prototype
presentation_id:  wearable.outfit.peasant_male
preferred_anchor: body.root
occupied channels:
  body.torso.outer
  body.arms.outer
  body.legs.outer
  body.feet
```

No garment mesh, Skeleton3D or head proxy becomes a second inventory/equipment identity.

## Skinned presentation strategy

`SKINNED_GARMENT` is a presentation strategy in `CharacterEquipmentPresenter`.

The garment keeps its own presentation Skeleton3D and is driven from the already authoritative avatar presentation pose through `SkinnedGarmentPoseBridge`:

```text
avatar presentation Skeleton3D
        |
        | normalized bone map
        v
Male_Peasant garment Skeleton3D
```

For the selected asset the map is exact 65/65. Position, rotation and scale are copied in presentation processing only.

The bridge:

- does not move the gameplay body;
- does not read input;
- does not own network state;
- does not apply root-motion authority;
- does not mutate Item Graph state.

## Coarse body replacement

The Universal Base Character may expose torso, arms, legs and head through one coarse full-body skinned mesh. CH7.8 deliberately does **not** introduce per-triangle masking or runtime mesh surgery to solve that.

Instead the presentation uses this composition while the outfit is equipped:

```text
original full-body MeshInstance3D(s)  -> hidden only
original Skeleton3D                  -> remains alive and authoritative for presentation pose
BoneAttachment3D helmet/backpack     -> remains alive
compatible Base Character Head scene -> visible, pose-driven
Male_Peasant outfit                   -> visible, pose-driven
```

The accepted base mesh nodes are hidden individually, not their `QuaterniusModel` parent. This preserves Skeleton3D and rigid equipment attachments.

Semantic body regions used by the outfit:

```text
body.region.torso
body.region.arms
body.region.legs
body.region.feet
```

For this coarse imported rig those semantic regions intentionally resolve to the same underlying full-body geometry set. `CharacterEquipmentPresenter` deduplicates the geometry and maintains reference-counted hide state so overlapping semantic regions cannot corrupt visibility restoration.

The original `visible` value of every body geometry node is restored exactly on unequip. A node that was already hidden before equip remains hidden afterward.

## Head variant resolution

The laboratory resolves the compatible head scene at runtime from the already selected base model. It first tries the direct sibling naming convention:

```text
*_FullBody.gltf -> *_Head.gltf
```

If that exact sibling is absent, it recursively scores Base Character head candidates, preferring the same character family, gender, export directory and glTF format.

The selected head scene is then passed through the same pose bridge. Its bone-overlap guard must pass before body hiding is applied.

This keeps the production equipment presenter independent from Quaternius file names.

## CH6 composition

Equip/unequip still uses the accepted `EquipmentAwareFirstPersonAdapter.refresh_presentation_visuals()` path.

After a presentation change CH6 recaptures dynamic visuals and rebuilds its world-shadow proxy. The expected result is:

- third person: head + outfit + rigid equipment are visible;
- first person: own world presentation obeys the existing camera-layer policy;
- first-person character/equipment shadow remains available;
- crouch keeps the accepted presentation-only `-0.35 m` ground correction;
- gameplay CharacterBody3D and capsule are unchanged.

## Explicitly deferred

- cloth physics;
- skirts/capes with secondary simulation;
- arbitrary garments from unrelated skeletons;
- runtime retarget profile authoring UI;
- body shape morphing;
- automatic garment fitting;
- shader cut masks;
- runtime vertex or triangle editing;
- dozens of simultaneous clothing pieces;
- production ItemGraphEquipmentSource bridge;
- network/persistence integration.

## Acceptance ladder

### CH7.8-A — Asset probe — PASS

Real Windows probe selected `Male_Peasant.gltf` with exact 65/65 bone overlap and four skinned meshes.

### CH7.8-B — One skinned outfit — focused PASS

The real asset laboratory completed equip, two process frames, locomotion pose copy and crouch composition with 37 assertions after parser fixes.

### CH7.8-C — Body-region replacement — IMPLEMENTED, rerun required

Synthetic acceptance now checks semantic region expansion, deduplication, reference-counted hiding, optional pose-driven replacement, idempotency and exact visibility restoration.

The real lab now requires a compatible Base Character head, hides the coarse full-body geometry while equipped and restores it after unequip.

### CH7.8-D — CH6 composition — focused PASS before body replacement; rerun required with replacement

The prior real lab proved FP/world-shadow capture and rigid helmet/backpack coexistence. The same checks remain in place and will be repeated with body replacement active.

### CH7.8-E — Lifecycle — focused PASS before body replacement; rerun required with replacement

The prior real lab proved canonical equip/unequip and no registered garment visual after removal. The new synthetic gate additionally stresses body hide/restore lifecycle.

Only after the combined runner and graphical observation pass should the generic garment system be widened to a second outfit or more granular layered clothing.
