# G8.0 Geomorphology Contracts — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`
**Parent:** `G7 Semantic Field Fabric — ACCEPTED`

## Decision

`G8.0 Geomorphology Contracts` is **ACCEPTED**.

The checkpoint freezes a deterministic procedural deformation boundary before any concrete valley, river, bank, floodplain or erosion/deposition formula becomes part of the pipeline.

## Accepted composition

```text
resolved_surface_height_m
    = source_surface_height_m
    + valley_delta_m
    + river_channel_delta_m
    + bank_delta_m
    + floodplain_delta_m
    + erosion_deposition_delta_m
```

Valley and river-channel deltas are non-positive. Bank, floodplain and erosion/deposition deltas are signed and bounded by the selected geomorphology profile.

## Windows acceptance evidence

Tested head:

```text
7a34c5d58b5a766fd8f4da46073dfcea29673fe9
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Final gate:

```text
G7 parent ACCEPTED                 PASS
G8.0 contracts                     PASS
Geomorphology ownership boundary   PASS
MW10 cross-region Matter           PASS 51 assertions
MW10 lock release retry            PASS 12 assertions
RL0 representation contracts       PASS 92 assertions
RL1 Matter summary pyramid         PASS 245 assertions
RL2 Matter multiresolution meshing PASS 153 assertions
RL2 real asteroid multiresolution  PASS 44 assertions
RL3 representation-aware streaming PASS 175 assertions
RL3 representation processes       PASS 37 assertions
main_scene_cli_all                  6 PASS / 0 FAIL
world/core through NX4             PASS
lifecycle                           STOPPED
working tree                        CLEAN
G8.0 FULL ACCEPTANCE                PASS
```

## Ownership boundary

The accepted contract contains no `SurfaceCellKey`, LOD, authority/interest region identity, Matter revision, `MaterialDefinitionId`, network peer identity or persistence identity.

G8 owns procedural baseline shaping only. Player excavation and persistent terrain damage remain Matter-owned sparse authoritative mutations composed over procedural truth.

## Known non-blocking harness debt

The full regression emitted transient M5 `Parse JSON failed` messages while polling acceptance barrier files. The M5 scenario continued and all convergence assertions passed. This is classified as a test-harness polling read race, not a G8/runtime failure. A later harness cleanup should route M5 polling reads through the existing `AtomicJson.read_dictionary/read_value` helper.

## Next

`G8.1 Valley Incision Baseline`.
