# FPE portable hand asset workflow

This research layer keeps item authority, grip logic and canonical first-person poses independent from the concrete hand mesh/rig asset.

## Profile registry

Drop JSON profiles into:

`res://config/characters/hand-assets/`

The registry scans that directory. A profile records:

- stable `profile_id` and display name;
- provider backend;
- external scene path;
- hand layout (`PER_HAND_SINGLE_SCENE`, `PAIRED_SEPARATE_MESHES`, `PAIRED_SINGLE_MESH`, `BOTH_COMPATIBLE`, `AUTO_INSPECT`);
- mesh node selection, optionally per hand;
- named source-to-canonical bone map;
- rest-space policy and future bind-pose calibration;
- presentation offset/rotation/scale;
- source URL and license metadata.

Adding another hand should normally require a new JSON profile plus the asset files, not a new gameplay or grip implementation.

## First external probe: WRAD ARMS

Profile id: `wrad-arms-cc0`

Expected local asset path:

`res://assets/external/fpe_hands/wrad_arms/wrad_arms.glb`

Download `WRAD_ARMS.zip` from the author page, extract the GLB and copy/rename it to the path above. Keep any referenced textures beside the GLB.

The WRAD profile intentionally starts with `INSPECT_REQUIRED` and an empty bone map. We must not invent source bone names or claim rest-space compatibility before importing the real file.

Run:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\INSPECT_FPE_HAND_ASSET.ps1 `
    -GodotPath $Godot `
    -Scene "res://assets/external/fpe_hands/wrad_arms/wrad_arms.glb"
```

The runner prints `FPE_HAND_ASSET_INSPECTION_JSON:` containing:

- skinned mesh paths;
- Skeleton3D paths and bone names;
- Skin bind names;
- weighted surface counts;
- animation libraries;
- left/right naming clues;
- mesh bounds.

Use that inspection to fill `selection`, `hand_layout`, `retarget.bone_map` and, if necessary, presentation calibration.

## Runtime selection

Existing direct S7/S8 routes remain supported. Portable profiles are selected independently:

```powershell
.\PLAY_FPE_RESEARCH.ps1 -GodotPath $Godot -ResetState -HandAssetProfile "s9-rounded-internal"
```

A profile can also be referenced directly by `res://...json` path.

Only one provider selection may be active at a time:

- `-HandVisualScene` (legacy S7 BoneAttachment route), or
- `-SkinnedHandScene` (legacy S8 named-Skin route), or
- `-HandAssetProfile` (portable profile route).

## Fail-closed rules

External profiles do not weaken authority and do not own Item Graph, network state or gameplay transforms.

A skinned profile fails closed when:

- its asset file is missing;
- no weighted skinned mesh is selected;
- Skin bind names are absent;
- a source bind cannot map to the canonical FPE hand skeleton;
- rest space is still `INSPECT_REQUIRED`;
- the asset is a single inseparable paired-hand mesh that needs a dedicated paired-viewmodel adapter.

The last case is explicit because some FPS arm packs contain both arms in one weighted mesh. The inspector/profile layer records that layout instead of silently duplicating both arms into each canonical hand.
