# CH8C fix9 — Profile-driven garment vertex inflation

## Why fix9 exists

Fix7 established topology-aware base-body occlusion and fixed the main trouser overlap. Fix8 added a local `HIGH_BOOT` topology policy for the upper boot shaft. Graphical motion testing then exposed the remaining failure mode: even when the rest-pose topology mask is reasonable, the skinned base body and skinned garment can separate differently during animation because their meshes and skin weights are not identical. A body surface can therefore move back through a garment surface after the character starts moving.

The correct response is not to delete more body geometry globally. Fix9 adds a small **separation reserve to the garment itself** while keeping topology occlusion as the second line of defense.

## Architecture

```text
Male_Peasant.gltf
      |
      v
SelectiveGarmentSceneFactory
      |
      v
GarmentVertexInflationSceneFactory
      |  profile-driven rest-vertex offset along normals
      v
inflated temporary PackedScene
      |
      +--> WearablePresentationCatalog / SKINNED_GARMENT
      |      -> normal CH7.8 pose bridge / 65-bone skinning
      |
      +--> WearableBodyTopologyCatalog
             -> topology mask is derived from the same rendered shell
```

The ordering matters: topology sampling receives the same inflated scene that the presenter uses, so presentation geometry and body occlusion do not drift into two independent definitions.

## What the inflation factory changes

For each selected garment `ArrayMesh`:

1. read every triangle surface and its vertex normals;
2. find the local Y range of the garment part;
3. normalize every vertex height to `t = 0..1`;
4. sample a piecewise-linear fit profile;
5. replace only the rest vertex position with `vertex + normal * offset`;
6. preserve normals, indices, materials, bone indices, weights, UVs and all other source arrays;
7. repack a temporary scene without mutating the imported glTF or the selective source scene.

The mesh is not scaled as a whole. A waist, cuff or sole can remain almost unchanged while knees, calves or the upper boot shaft receive more clearance.

## Initial Peasant profiles

### `Male_Peasant_Legs`

```text
t=0.00  +1.5 mm   lower cuff
 t=0.18  +4.0 mm
 t=0.45  +6.0 mm   main knee/calf separation reserve
 t=0.72  +5.0 mm
 t=1.00  +1.5 mm   waist / upper attachment
```

### `Male_Peasant_Feet`

```text
t=0.00  +1.5 mm   sole/lower foot
 t=0.35  +2.5 mm
 t=0.65  +4.5 mm
 t=1.00  +7.0 mm   upper boot shaft
```

These are intentionally small millimetre-level offsets. If graphical testing shows visible floating or an inflated silhouette, tune the profile rather than changing canonical equipment or scaling the complete `MeshInstance3D`.

## Composition with topology occlusion

Fix9 does not replace fix7/fix8 topology masking.

```text
lower garment
    vertex inflation profile
    + ROBUST topology occlusion

feet garment
    vertex inflation profile
    + HIGH_BOOT topology occlusion
```

This division of responsibilities is intentional:

- vertex inflation reduces skin/cloth intersections under animation;
- topology occlusion hides body triangles that should never be visible under solid cloth;
- genuine holes and open garment boundaries can still reveal skin;
- neither system owns gameplay state.

## Invariants

Fix9 must not change:

- canonical equipment entries or channels;
- Item Graph;
- network protocol;
- persistence;
- `CharacterBody3D` transform;
- capsule/collision;
- imported Quaternius asset bytes;
- accepted `CharacterEquipmentPresenter` contract;
- accepted `SkinnedGarmentPoseBridge` contract.

The inflation factory is presentation-only and operates only when creating temporary wearable scenes.

## Automated gates

`test_ch8c_quaternius_vertex_inflation.gd` uses the real `Male_Peasant.gltf` and must prove for both `Legs` and `Feet`:

- the selective source mesh is an `ArrayMesh`;
- vertex count remains unchanged;
- normals remain unchanged;
- triangle indices remain unchanged;
- bone arrays remain unchanged;
- weight arrays remain unchanged;
- each moved vertex follows its source normal;
- displacement follows the configured height profile;
- the selective source scene is not mutated;
- configured and observed inflation maxima are reported separately.

The graphical lab gate additionally requires both inflation profiles to be registered while topology masking and all gameplay invariants remain green.

## Graphical acceptance

Inspect `L`, `K`, `L+K`, then move, turn, crouch and jump.

Required result:

- the already-correct trouser silhouette stays intact;
- body skin does not reappear through trouser cloth after animation begins;
- calf skin does not reappear through solid boot shafts;
- intended trouser/footwear openings still show skin;
- skin above real cuffs/collars remains present;
- garment does not look visibly ballooned or detached;
- underwear/pelvis remains intact;
- FP/TP, shadow, helmet and backpack remain coherent.

If residual penetration is small, tune only the corresponding millimetre profile points. Do not return to global lower-leg clipping and do not scale the whole wearable node.
