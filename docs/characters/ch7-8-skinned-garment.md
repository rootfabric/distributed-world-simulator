# CH7.8 — Minimal skinned garment experiment

## Goal

Prove one real rigged outfit on the accepted CH7 semantic equipment architecture with the smallest possible increase in complexity.

This stage is intentionally **not** a full wardrobe system and **not** cloth simulation.

## Final status

```text
checkpoint: CH7.8 skinned garment + fused-body head clip
decision:   ACCEPTED
```

Automated Windows acceptance passed the complete CH6, CH7 and CH7.8 composition, including the real Quaternius `Male_Peasant.gltf` asset. The graphical lab was then accepted by user observation with no reported visual defects.

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
Skeleton3D                          65 bones
├─ Eyebrows       skinned, 1 surface
├─ Eyes           skinned, 1 surface
└─ SuperHero_Male skinned, 1 surface
```

Observed material identities:

```text
Eyebrows       -> T_Hair_1_BaseColor.png
Eyes           -> T_Eye_Brown.png
SuperHero_Male -> T_Superhero_Male_Dark.png
```

Important consequence: the face/head and body are fused into the single `SuperHero_Male` mesh and its single material surface. Mesh-level or surface-level hiding cannot preserve the face.

The inspected current Standard archive also did not expose a standalone Head/Upperbody character glTF. CH7.8 therefore does not depend on a separate head scene.

## CH7.8C fused-body suppression

The accepted minimal solution is a presentation-only **head clip material**.

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

For the accepted asset:

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

The accepted CH6 `WORLD_PROXY` shadow implementation shares the source Mesh/Skin and copies `material_override` from the source, including during proxy synchronization. The same head clip therefore propagates through the accepted first-person shadow path without a second shadow-specific mask system.

The accepted real lab proves:

- garment meshes are recaptured into CH6 world presentation;
- garment meshes are recaptured into CH6 shadow proxy;
- first-person shadow proxy remains active;
- crouch keeps the accepted presentation-only `-0.35 m` ground compensation;
- gameplay `CharacterBody3D` position and capsule remain unchanged;
- helmet/backpack compose before or after outfit equip;
- material suppression restores exactly on outfit removal.

## Acceptance evidence

### CH7.8-A — Asset probe — PASS

`Male_Peasant.gltf` selected with exact 65/65 bone overlap and four skinned meshes.

### CH7.8-B — One skinned outfit — PASS

Real Windows lab completed equip, motion, crouch, rigid composition and unequip with 37 assertions before fused-body suppression was added.

### CH7.8-C1 — Generic body suppression — PASS

Synthetic body-region replacement/hide lifecycle passed 65 assertions.

### CH7.8-C2 — FullBody structure probe — PASS

Real Windows probe proved the 3-mesh / 3-surface layout and fused `SuperHero_Male` head+body surface.

### CH7.8-C3 — Fused-body head clip — PASS

Focused material contract passed 19 assertions. Real rigid-first suppression order passed 49 assertions.

### CH7.8-D — CH6 composition — PASS

Accepted CH6 regression remained green and the real garment lab passed with first-person/world-shadow composition active.

### CH7.8-E — Lifecycle — PASS

The final real Quaternius garment laboratory passed 67 assertions including equip, pose composition, crouch, rigid equipment coexistence, fused-body suppression, exact restore and unchanged gameplay body/capsule.

### Combined runner — PASS

```text
CH7.8 Skinned Garment + fused-body head clip candidate runner: PASS
```

### Graphical observation — PASS_BY_USER_OBSERVATION

The graphical laboratory launched successfully with `MATERIAL_OVERRIDE`, `clip_y=1.4836`, and the user reported that everything looked normal. No graphical defect was reported.

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

For a high population of characters, a pre-generated head-only asset may later be preferable to fragment `discard`. CH7.8 proves the semantic/presentation composition first; representation optimization can remain rig-specific.

## Next expansion

The accepted mechanism can now widen without changing the equipment domain:

1. add a second real outfit to prove the strategy is not asset-specific;
2. split presentation into layered upper/lower/feet garments using existing semantic channels;
3. add armor/EVA presentation profiles on the same slots and conflict rules;
4. only after the presentation layer is stable, connect the already planned production `ItemGraphEquipmentSource` and network/persistence bridge.
