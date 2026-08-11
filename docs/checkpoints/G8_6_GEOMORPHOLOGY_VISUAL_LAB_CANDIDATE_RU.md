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

## Guarded manual graphical gate

A dedicated manual runner was added after automated acceptance. It is harness-only and does not alter the accepted G8.6 runtime, scene, manifest or geomorphology algorithms.

Initial runner commit:

```text
3a0330a62f71bf0ec7a2379d722f03e28ca0ae6d
```

The final guard intentionally allows later control/manifest/validation **metadata** to move while fail-closing if executable G8.6 behavior or its focused acceptance harness moved after automated acceptance.

The runner refuses to open the graphical scene unless all of the following are true:

1. current branch is exactly `feature/g8-geomorphology`;
2. working tree is clean;
3. automated-tested head `a9ca1f8b723e4edc5ebff40db26e41283d464597` is an ancestor of the current checkout;
4. no executable G8.6 presentation/runtime file, G8.6 scene, geomorphology runtime, focused G8.6 acceptance test, or accepted G8.6 automated/focused runner changed after that head;
5. the focused G8.6 headless gate passes again on the current checkout.

Run from the G checkout:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git fetch origin --prune
git switch feature/g8-geomorphology
git pull --ff-only

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G8_6_MANUAL_GRAPHICAL_ACCEPTANCE.ps1 -GodotPath $Godot
```

The script deliberately does **not** mark G8.6 accepted when the window closes. Human graphical observation remains mandatory.

## Manual graphical observations

Confirm all five items:

1. `G` visibly switches source G3 ↔ resolved G8 geometry while HUD `Truth hash` remains unchanged.
2. `1..7` show resolved height, total deformation, valley, channel, bank, floodplain and erosion/deposition views.
3. `W/S` changes derived presentation LOD/mesh-grid through `33×17`, `17×9`, `9×5`, `5×3` while `Canonical samples=561` and `Truth hash` remain unchanged.
4. With `X`, the magenta PX/PZ seam crosses the resolved surface without a visible crack/discontinuity.
5. With `F`, the cyan canonical river overlay agrees with the visible channel/bank/floodplain structure.

Only user-observed graphical PASS moves G8.6 to `ACCEPTED`. After that, record G8.6 ACCEPTED and run G8 Full Acceptance. No automatic PR merge.
