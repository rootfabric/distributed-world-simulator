# V0-C2A Earth-fixed Construction Anchor — delivery

## Primary delivery branch

`agent/v0-s1-inventory-convergence`

The C2A work was prepared from the exact previous delivery head:

`ab6e79b83cc94977fcf55ecd863467f4ddc37ad1`

A temporary preparation branch also exists:

`agent/v0-c2a-earth-fixed-construction-anchor`

Use the primary delivery branch for local patch retrieval.

## Patch

`patches/v0-c2a-earth-fixed-construction-anchor.patch`

The patch is intentionally based on the current local C2 state **after** `v0-c2-earth-construction-observer-frame.patch` was applied. It replaces that observer-owned transform semantics rather than stacking another offset correction on top of it.

## What changes

- `scripts/app/earth_app.gd`
  - caches a stable Earth-fixed outpost surface anchor;
  - projects it against `EarthWorld.get_render_origin()` every frame;
  - uses `EarthWorld.basis` for current reference-frame conversion;
  - reports anchor and render-update diagnostics.
- `scripts/app/earth_construction_presentation.gd`
  - removes observer planar position / eye height as construct placement truth;
  - accepts only a derived render transform;
  - keeps Construction authority external/server-owned.
- `scripts/app/earth_surface_render_projector.gd`
  - pure presentation-only Earth-fixed -> floating-origin transform helper.
- `tests/runtime/test_v0_c2a_earth_surface_render_projector.gd`
  - covers walking, jump, spectator translation, frame conversion and anchor immutability.

The MVP foundation bbox is `0.5 m` high, so its root center is placed `0.25 m` above the sampled terrain surface. This makes the bottom face sit on the support surface instead of using player eye height.

## Automated evidence

Exact engine used:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Focused invariant test:

```text
V0-C2A Earth surface render projector: PASS (10 assertions)
```

Construction presentation parse/setup check:

```text
C2A presentation parse/setup: PASS
```

Patch reconstruction checks:

```text
PATCH_APPLY_CHECK=PASS
git diff --check = PASS
```

## Apply on the current local MVP stack

PowerShell:

```powershell
cd C:\distributed-world-simulator
git fetch origin
git restore --source=origin/agent/v0-s1-inventory-convergence --worktree -- patches/v0-c2a-earth-fixed-construction-anchor.patch
git apply --check .\patches\v0-c2a-earth-fixed-construction-anchor.patch
git apply .\patches\v0-c2a-earth-fixed-construction-anchor.patch
git diff --check
Remove-Item .\patches\v0-c2a-earth-fixed-construction-anchor.patch -Force
```

Do not stage/delete unrelated `.uid` files.

## Run focused automated test

```powershell
cd C:\distributed-world-simulator
$GODOT = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
& $GODOT --headless --path "C:\distributed-world-simulator" --script res://tests/runtime/test_v0_c2a_earth_surface_render_projector.gd
```

Expected:

```text
V0-C2A Earth surface render projector: PASS (10 assertions)
```

## Parse/preflight

```powershell
& "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" --headless --path "C:\distributed-world-simulator" --editor --quit-after 1
```

## Runtime acceptance

Start the same dedicated server + clients A/B used by the V0-S1 MVP.

Check in this order:

1. Build foundation and complete the outpost.
2. Walk 10 m, 30 m, then at least 50 m away and back.
3. Jump several times next to the foundation.
4. Enable detached spectator and move ~100 m away.
5. Move spectator ~1 km away if terrain remains in local LOD range.
6. Return to the player.
7. Repeat from client B while client A stays near the outpost.

PASS criteria:

```text
foundation remains seated on terrain
building never follows player eye height
building never follows spectator
terrain and building recede together
returning restores the same world location
A and B agree on the outpost location
construction checksum/revision do not change from observer movement
```

Useful report fields:

```text
construction_surface_anchor_ready
construction_surface_anchor_world
construction_render_transform_updates
construction_presentation.spatial_authority = EXTERNAL_EARTH_FIXED_ANCHOR
construction_presentation.derived_render_origin
```

## Architecture follow-up

This checkpoint deliberately does **not** introduce persistent coordinates into `ConstructSnapshot`.

Current fixed MVP anchor:

```text
canonical M3 planar outpost position
-> deterministic procedural Earth surface point
-> cached Earth-fixed Transform3D
```

Target promotion when world-item spatial convergence lands:

```text
root Item
-> WORLD(entity_id)
-> WorldEntity
-> SpatialRef(frame_id = earth.fixed)
-> same presentation projector
```

No C22/C24 or Construction topology rewrite should be required for that promotion.
