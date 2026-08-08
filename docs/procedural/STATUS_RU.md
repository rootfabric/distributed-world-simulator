# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           FIX4 MANUAL PASS / AUTOMATED RERUN IN FULL GATE
G6 Full Acceptance                     IMPLEMENTED CANDIDATE — BLOCKED BY SHARED MW10 BASELINE
```

G6.4 Fix4 manual evidence is recorded: observer refinement from about `LOD 6 @ 812.7 km` to `LOD 10 @ 42.2 km`, with subtle higher-frequency macro irregularities becoming visible while the river and canonical IDs remain stable. The remaining Fix4 automated rerun is intentionally folded into `RUN_G6_FULL_ACCEPTANCE.ps1`.

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

Current blocker: PR #43 (`MW10: integrate atomic lock release into shared G5 baseline`) is still open and not merged. By design G6 does not privately copy that fix. After #43 lands in G5, resynchronize G6 and rerun the same full gate.

Assistant-side runtime execution was attempted, but the available container has neither a Godot binary nor a local repository checkout, and network clone/download is unavailable. No assistant-side Godot PASS is claimed.

After G6 Full Acceptance: `G7 Semantic Field Fabric`.
