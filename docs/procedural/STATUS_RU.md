# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           ACCEPTED
G6 Full Acceptance                     BLOCKED BY SHARED MW10 BASELINE — EXPECTED
```

G6.4 Fix4 is complete on Windows Godot 4.7.1 double:

```text
manual graphical observation            PASS_BY_USER_OBSERVATION
automated dependency chain through G6.3 PASS
G6.4 contracts                           PASS (158 assertions)
adaptive macro surface                   PASS
far -> near LOD                           1 -> 9
far -> near triangles                     120 -> 4176
detail recipe                             octaves=8, min_signal_km=4.688
visual lab runtime marker                 PASS
post-cleanup git diff --check             PASS
working tree                              CLEAN
```

The successful automated Fix4 run was performed on `7cb3c69bbca276c815b27563fa494ac35b078779`. Later changes were documentation/validation-only hygiene and acceptance records; G6 runtime code did not change.

Full gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

The first Windows G6 full-gate attempt behaved exactly as designed: GLOBAL preflight passed and the runner stopped at the shared MW10 baseline because G5 still contains repository blob `ec596493...` instead of accepted blob `a25b7d8c...`.

PR #43 remains the only shared-baseline blocker. G6 must not privately copy that Matter fix.

Assistant-side engine verification is also available using the project-provided Linux Godot 4.7.1 double build: version/binary checks and a real headless GDScript smoke passed. A full assistant-side project gate is not claimed because the execution container still has no repository checkout.

Required sequence:

```text
PR #43 -> G5 shared baseline
        -> resynchronize G6
        -> RUN_G6_FULL_ACCEPTANCE.ps1
        -> G6 SOURCE_ACCEPTED
        -> G7 Semantic Field Fabric
```
