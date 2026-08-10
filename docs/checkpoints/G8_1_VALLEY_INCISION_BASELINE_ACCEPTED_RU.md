# G8.1 Valley Incision Baseline — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`
**Parent:** `G8.0 Geomorphology Contracts — ACCEPTED`

## Decision

G8.1 is **ACCEPTED**.

Exact Windows full acceptance passed on:

```text
42940c0b7f16b2ccf3704d7e603691415b1360cf
```

with Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Final gate evidence:

```text
G8.0 parent ACCEPTED                 PASS
G8.1 valley incision baseline        PASS
Geomorphology ownership boundary     PASS
RL3 representation-aware streaming   PASS 175 assertions
RL3 representation processes         PASS 37 assertions
main_scene_cli_all                    6 PASS / 0 FAIL
world/core regression through NX4    PASS
lifecycle                             STOPPED
working tree                          CLEAN
G8.1 FULL ACCEPTANCE                  PASS
```

The first Windows attempt on `5de8716fc5b2893e00d31f109b73d0974891aca9` stopped before the G8.1 runtime test because the inherited G8.0 regression encoded stale pre-acceptance manifest expectations. FIX1 corrected only the parent regression harness and its full-acceptance allowlist; the valley runtime/formula did not change.

## Accepted formula

```text
valley_delta_m = -valley_max_depth_m * pow(valley_influence, valley_exponent)
```

Inputs:

```text
geo/surface-height-m
geo/valley-influence
```

Accepted properties:

- influence `0` produces no incision;
- influence `1` reaches the profile maximum valley depth;
- incision is monotonic with influence;
- valley deformation never raises the surface;
- deformation is profile-bounded and deterministic;
- river/channel, bank, floodplain and erosion/deposition components remain zero at this stage;
- output binds the source semantic bundle checksum and geomorphology profile checksum;
- body-fixed position is preserved;
- no SurfaceCellKey, LOD, authority, interest, Matter mutation, material ontology, persistence or network ownership is introduced.

## Next

`G8.2 River Channel Incision` may now compose a river-channel component on top of the accepted valley deformation using accepted `geo/river-distance-m` and `geo/river-width-m` semantics.
