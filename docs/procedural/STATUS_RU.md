# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           ACCEPTED
G5 + MW10 shared baseline              ACCEPTED / INTEGRATED
G6 Full Acceptance                     FIX2 IMPLEMENTED CANDIDATE
```

G6.4 Windows evidence remains accepted:

```text
G6.4 contracts                         PASS — 158
adaptive macro surface                 PASS
far -> near LOD                        1 -> 9
far -> near triangles                  120 -> 4176
manual graphical observation           PASS_BY_USER_OBSERVATION
```

The first G6 full-gate attempt progressed through G6.4 and MW10 retry `12/12`, then stopped at world regression coverage because the new MW10 retry test was not declared in `RUN_WORLD_REGRESSION_TESTS.ps1`. Fix1 added that declaration in shared G5 and synchronized it into G6.

The next preflight found one generated untracked Godot sidecar:

```text
tests/matter/transactions/test_mw10_lock_release_retry.gd.uid
```

Fix2 tracks that UID in shared G5 using project-provided Godot-generated value:

```text
uid://yush8dg03nlf
```

After the current G5→G6 lineage sync, rerun only:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

If it reaches `G6 FULL ACCEPTANCE: PASS`, record G6 SOURCE_ACCEPTED and proceed to G7 Semantic Field Fabric.
