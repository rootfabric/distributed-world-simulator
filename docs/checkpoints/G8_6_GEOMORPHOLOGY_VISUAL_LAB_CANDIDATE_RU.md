# G8.6 — Geomorphology Visual Lab — automated accepted / manual pending

**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Project Control:** `PC0-2026-08-10-R1`  
**Branch:** `feature/g8-geomorphology`

## Parent

`G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance — ACCEPTED`

Tested head:

```text
6cc0c2b5ff1bc21a5b488a8492ef8cce28fa4736
```

## Purpose

G8.6 is a derived presentation lab over accepted G3+G5+G6 semantic truth and accepted G8.4 geomorphology deformation. It does not make camera, mesh density, cube face, LOD or presentation geometry canonical truth.

The lab renders a local `440 m × 1600 m` corridor around a real accepted G6 river crossing of the PX/PZ cube-sphere seam using a canonical source grid `33×17 = 561` samples.

## FIX history

The first exact-Windows run exposed only a JSON numeric Array type-sensitivity bug in the acceptance harness. FIX1 corrected the harness without changing runtime.

The second exact-Windows run passed contracts but the headless lab found `river_channel_delta_m` zero throughout the corridor. The cause was presentation-only: the original lab forced the corridor onto `Fixture.RADIUS_M` while the accepted G6 river centerline carried real radial elevation. FIX2 therefore preserves the upstream G6 centerline radius and derives the local seam frame there. Accepted G8.1–G8.5 runtime and formulas remain unchanged.

## Automated acceptance

Exact automated acceptance checkout:

```text
a9ca1f8b723e4edc5ebff40db26e41283d464597
```

Engine:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Final evidence:

```text
G8.6 AUTOMATED ACCEPTANCE: PASS
G8.5 parent ACCEPTED: PASS
G8.6 headless local corridor lab: PASS
Derived presentation LOD / truth separation: PASS
PX/PZ seam diagnostic corridor: PASS
World/core regression: PASS
Working tree: CLEAN
MANUAL GRAPHICAL ACCEPTANCE: REQUIRED
```

Visible regression counts from the supplied Windows run include:

```text
MW10 cross-region Matter processes          PASS 51
MW10 lock release retry                     PASS 12
RL0 representation contracts                PASS 92
RL1 matter summary pyramid                  PASS 245
RL2 Matter multiresolution meshing          PASS 153
RL2 real asteroid multiresolution           PASS 44
RL3 representation-aware streaming          PASS 175
RL3 representation streaming processes      PASS 37
main_scene_cli_all                           6 PASS / 0 FAIL
lifecycle                                    STOPPED
NX4 final world/core marker                  PASS
```

G8.6 is therefore `AUTOMATED_ACCEPTED_MANUAL_PENDING`.

## Manual graphical gate

Launch on the same automated-tested checkout if it is still clean. Do not fetch/reset merely for the manual observation.

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
& $Godot --path . res://scenes/labs/procedural/g8_6_geomorphology_visual_lab.tscn
```

Confirm:

1. `G` visibly switches source G3 ↔ resolved G8 geometry while HUD `Truth hash` remains unchanged.
2. `1..7` show resolved height, total deformation, valley, channel, bank, floodplain and erosion/deposition views.
3. `W/S` changes derived presentation LOD/mesh-grid while `Canonical samples=561` and `Truth hash` remain unchanged.
4. With `X`, the magenta PX/PZ seam crosses the resolved surface without a visible crack/discontinuity.
5. With `F`, the cyan canonical river overlay agrees with the visible channel/bank/floodplain structure.

Only user-observed graphical PASS moves G8.6 to `ACCEPTED`. After that, run G8 Full Acceptance. No automatic PR merge.
