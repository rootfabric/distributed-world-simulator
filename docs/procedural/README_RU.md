# Universal World Generation Fabric — entrypoint

Current implementation branch:

```text
feature/g6-hydrology-fluid-surface-v0
```

Current state:

```text
G6.0 ACCEPTED
G6.1 ACCEPTED
G6.2 ACCEPTED
G6.3 ACCEPTED
G6.4 FIX4 MANUAL GRAPHICAL PASS / AUTOMATED RERUN FOLDED INTO FULL GATE
G6 FULL ACCEPTANCE IMPLEMENTED CANDIDATE — SHARED BASELINE BLOCKED
```

G6.4 manual observation confirmed observer-driven refinement to LOD 10 with subtle higher-frequency diagnostic G3 detail while the river presentation and canonical IDs remain stable.

The next executable checkpoint is now:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

The runner first performs repository/synchronization checks, then reruns G6.4 Fix4 (which includes G6.0-G6.3), executes the MW10 atomic-lock retry fault injection, and finally runs the full world/core regression.

Current intentional blocker: PR #43 with the independently accepted MW10 atomic-lock fix has not yet been integrated into `feature/g5-world-feature-graph`. Full acceptance therefore requires this order:

```text
PR #43 -> G5 shared baseline
        ↓
resync G6 on updated G5
        ↓
RUN_G6_FULL_ACCEPTANCE.ps1
        ↓
G6 SOURCE_ACCEPTED
        ↓
G7 Semantic Field Fabric
```

Do not copy the MW10 fix privately into G6; shared baseline ownership stays with G5/integration.

Global revision: `GLOBAL-P0-2026-08-08-R1`.
