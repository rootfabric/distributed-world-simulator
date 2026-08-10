# G8.2 River Channel Incision — IMPLEMENTED CANDIDATE

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`
**Parent:** `G8.1 Valley Incision Baseline — ACCEPTED`

## Goal

G8.2 adds the actual river-channel cut inside the valley already produced by G8.1. It uses accepted G6 hydrology semantics projected through G7 and does not introduce a new river identity or geometry owner.

Inputs:

```text
geo/surface-height-m
geo/valley-influence
geo/river-distance-m
geo/river-width-m
```

`geo/river-distance-m` is the accepted distance to the G6 centerline. `geo/river-width-m` is the accepted full channel width.

## Composition

G8.2 first evaluates the accepted G8.1 valley generator on the same semantic bundle and profile, then preserves that exact valley component and adds only `river_channel_delta_m`.

```text
resolved_surface_height
    = source_surface_height
    + valley_delta
    + river_channel_delta
```

At G8.2:

```text
bank_delta              = 0
floodplain_delta        = 0
erosion_deposition_delta = 0
```

## River profile

```text
half_width_m        = river_width_m * 0.5
normalized_distance = river_distance_m / half_width_m
core_ratio          = 1.0 - river_edge_softness_ratio
```

Inside the core region the river reaches the profile maximum channel depth. Across the outer softness band a cubic smoothstep-like curve fades the channel weight from `1` to `0`. At and beyond `river_width_m / 2`, river incision is exactly zero.

```text
river_delta_m = -river_max_depth_m * channel_weight
```

The accepted profile therefore remains the tuning owner for river depth and edge softness; the semantic fields remain the spatial source of truth.

## Candidate properties

- centerline reaches `river_max_depth_m`;
- core region is full depth;
- outer edge fades monotonically;
- half-width and beyond produce no river incision;
- river component never raises the surface;
- river depth is profile-bounded;
- G8.1 valley component is preserved exactly;
- same semantic bundle checksum drives valley and river composition;
- output remains deterministic and binds the profile checksum;
- SurfaceCellKey, LOD, camera, representation, authority, interest, Matter, material ontology, persistence and network identity remain outside the contract.

## Acceptance

```powershell
.\RUN_G8_2_RIVER_CHANNEL_INCISION_TESTS.ps1 -GodotPath $Godot
.\RUN_G8_2_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Run focused first. If green, keep the exact same clean checkout and run full acceptance without fetch/reset. Only a full PASS unlocks `G8.3 Banks and Floodplain Shaping`.
