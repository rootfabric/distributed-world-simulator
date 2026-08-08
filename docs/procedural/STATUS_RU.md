# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           FIX4 RUNTIME+MANUAL PASS — HYGIENE RERUN ONLY
G6 Full Acceptance                     IMPLEMENTED CANDIDATE — BLOCKED BY SHARED MW10 BASELINE
```

G6.4 Fix4 now has both required runtime evidence paths on Windows Godot 4.7.1 double:

```text
manual graphical observation            PASS_BY_USER_OBSERVATION
automated dependency chain through G6.3 PASS
G6.4 contracts                           PASS (158 assertions)
adaptive macro surface                   PASS
far -> near LOD                           1 -> 9
far -> near triangles                     120 -> 4176
detail recipe                             octaves=8, min_signal_km=4.688
visual lab runtime marker                 PASS
```

The successful automated Fix4 run was performed on `7cb3c69bbca276c815b27563fa494ac35b078779`. The only remaining G6.4 formality is repository hygiene: the same run exposed old trailing whitespace in markdown files. Those lines have now been cleaned without changing G6 runtime code; rerun `git diff --check origin/feature/g5-world-feature-graph...HEAD` to close that formality.

Full gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

The full gate requires:

```text
GLOBAL config == main == G5
current G5 is ancestor of G6
accepted MW10 atomic-lock blobs exist in G5 and G6
G6.0-G6.4 focused chain PASS
MW10 lock-release retry PASS
RUN_WORLD_REGRESSION_TESTS.ps1 PASS
clean worktree + git diff --check
```

The first Windows G6 full-gate attempt behaved exactly as designed: GLOBAL preflight passed and the runner stopped at the shared MW10 baseline because G5 still contains repository blob `ec596493...` instead of accepted blob `a25b7d8c...`. PR #43 remains the blocker; G6 must not privately copy that fix.

Assistant-side engine verification is also available using the project-provided Linux Godot 4.7.1 double build: version/binary checks and a real headless GDScript smoke passed. A full assistant-side project gate is not claimed because the execution container still has no repository checkout.

After PR #43 lands in G5: resynchronize G6, run `RUN_G6_FULL_ACCEPTANCE.ps1`, record `G6.4 ACCEPTED` / `G6 SOURCE_ACCEPTED`, then start `G7 Semantic Field Fabric`.
