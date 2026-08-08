# CH7.8 — Minimal skinned garment experiment

## Goal

Prove one real rigged outfit on the accepted CH7 semantic equipment architecture with the smallest possible increase in complexity.

This stage is intentionally **not** a full wardrobe system and **not** cloth simulation.

## Selected asset

The real Windows asset probe selected:

```text
Male_Peasant.gltf
base bones:       65
garment bones:    65
matched bones:    65
base overlap:     1.0
garment overlap:  1.0
skinned meshes:   4
```

Therefore CH7.8 does not require arbitrary retargeting for this outfit.

External asset bytes remain outside Git.

## Canonical equipment model

The outfit remains one canonical equipment item even though its presentation contains multiple skinned mesh parts.

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

No garment mesh, Skeleton3D, material or shadow proxy becomes a second inventory/equipment identity.

## Skinned presentation strategy

`SKINNED_GARMENT` is presentation-only.

```text
avatar presentation Skeleton3D
        |
        | exact normalized 65-bone map
        v
Male_Peasant garment Skeleton3D
```

`SkinnedGarmentPoseBridge` copies presentation pose only. It does not move `CharacterBody3D`, own root-motion authority, read gameplay input, mutate Item Graph state or own network state.

## Actual Universal Base Character structure

The current Standard archive was inspected on Windows after URI normalization and a clean Godot reimport.

`Superhero_Male_FullBody.gltf` resolves to:

```text
Skeleton3D                         65 bones
├─ Eyebrows      skinned, 1 surface
├─ Eyes          skinned, 1 surface
└─ SuperHero_Male skinned, 1 surface
```

Observed material identities:

```text
Eyebrows       -> T_Hair_1_BaseColor.png
Eyes           -> T_Eye_Brown.png
SuperHero_Male -> T_Superhero_Male_Dark.png
```

Important consequence: the face/head and body are fused into the single `SuperHero_Male` mesh and its single material surface. Mesh-level or surface-level hiding cannot preserve the face.

The current Standard archive also did not expose a standalone Head/Upperbody character glTF in the inspected export. CH7.8 therefore does not depend on a separate head scene.

## CH7.8C fused-body suppression

The chosen minimal solution is a presentation-only **head clip material**.

While the outfit is equipped:

```text
original Skeleton3D           ACTIVE
Eyes                          VISIBLE
Eyebrows                      VISIBLE
SuperHero_Male mesh           VISIBLE, custom head-clip material
  fragments below neck plane  DISCARDED
  head fragments              VISIBLE
Male_Peasant                  VISIBLE, skinned
helmet/backpack               VISIBLE on original BoneAttachment3D anchors
```

On unequip, the original `material_override` is restored exactly.

There is no second head skeleton, no runtime vertex editing and no gameplay-body change.

### Clip plane

The clip plane is derived from the actual imported asset rather than a gameplay coordinate.

Primary rule:

```text
clip_local_y = Eyes AABB min Y - 0.20 m
```

For the inspected asset:

```text
Eyes min Y ~= 1.6836 m
clip Y     ~= 1.4836 m
```

Fallback for a compatible Quaternius rig without a separately named Eyes mesh:

```text
clip_local_y = body AABB min Y + body height * 0.82
```

This value belongs to rig presentation and never changes the gameplay capsule or canonical character transform.

## Generic suppression contract

The equipment presenter does not hard-code Quaternius.

`CharacterRigAdapter.resolve_body_region_suppression_targets()` maps semantic body regions to presentation targets.

Generic rigs use:

```text
VISIBILITY
```

which preserves the existing ref-counted hide/restore behavior.

The inspected Quaternius fused rig uses:

```text
MATERIAL_OVERRIDE
```

with one deduplicated target for all coarse semantic regions:

```text
body.region.torso
body.region.arms
body.region.legs
body.region.feet
        -> SuperHero_Male fused mesh
        -> one head-clip material target
```

The presenter reference-counts both target modes and restores the exact original state when the last owner disappears.

## CH6 first-person and shadow composition

The accepted CH6 `WORLD_PROXY` shadow implementation shares the source Mesh/Skin and copies `material_override` from the source, including during proxy synchronization. Therefore the same head clip presentation is expected to apply to the first-person shadow proxy without creating a second shadow-specific mask path.

The CH7.8 real lab continues to assert:

- garment meshes are recaptured into CH6 world presentation;
- garment meshes are recaptured into CH6 shadow proxy;
- first-person shadow proxy remains active;
- crouch keeps the accepted presentation-only `-0.35 m` ground compensation;
- gameplay `CharacterBody3D` position and capsule remain unchanged;
- helmet/backpack compose before or after outfit equip.

## Explicitly deferred

- cloth physics;
- capes/skirts with secondary simulation;
- generic unrelated-rig retargeting;
- body shape morphing;
- automatic arbitrary garment fitting;
- runtime vertex/triangle mesh surgery;
- production ItemGraphEquipmentSource bridge;
- network/persistence integration;
- high-volume optimization for hundreds of clipped characters.

For a high population of characters, a pre-generated head-only asset may later be preferable to fragment `discard`. CH7.8 first proves the semantic/presentation composition with one character before optimizing that representation.

## Acceptance ladder

### CH7.8-A — Asset probe — PASS

`Male_Peasant.gltf` selected with exact 65/65 bone overlap and four skinned meshes.

### CH7.8-B — One skinned outfit — PASS

Real Windows lab completed equip, motion, crouch, rigid composition and unequip with 37 assertions before body suppression was added.

### CH7.8-C1 — Generic body suppression — PASS

Synthetic body-region replacement/hide lifecycle passed 65 assertions.

### CH7.8-C2 — FullBody structure probe — PASS

Real Windows probe proved the 3-mesh / 3-surface layout and the fused `SuperHero_Male` head+body surface.

### CH7.8-C3 — Fused-body head clip — IMPLEMENTED, Windows rerun required

Pending gates prove:

- synthetic clip material contract;
- Quaternius semantic regions resolve only to the fused body mesh;
- one material suppression target is deduplicated across torso/arms/legs/feet;
- Eyes/Eyebrows remain visible;
- head clip survives motion, crouch and rigid-equipment composition;
- original material override is restored exactly on unequip.

### CH7.8-D — CH6 composition — rerun required with head clip

### CH7.8-E — lifecycle — rerun required with head clip

Only after the combined runner and graphical observation pass should the system widen to a second outfit or more granular layered clothing.
