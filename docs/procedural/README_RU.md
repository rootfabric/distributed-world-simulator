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
G6.4 ACCEPTED
G6 FULL ACCEPTANCE — BLOCKED BY SHARED MW10 BASELINE
```

G6.4 Fix4 is accepted from Windows Godot 4.7.1 double automated evidence, manual graphical observation and a clean post-cleanup `git diff --check`.

Accepted evidence:

```text
G6.4 contracts       PASS — 158 assertions
far_lod -> near_lod  1 -> 9
far_triangles        120 -> 4176
octaves              8
min_signal_km        4.688
manual observation   PASS_BY_USER_OBSERVATION
post-cleanup hygiene PASS
```

The lab remains derived presentation over accepted G2/G3/G6 semantics. LOD, SurfaceCellKey and renderer state do not own river identity. River valley carving remains deferred to G8 Geomorphology; layered geology remains G9.

Next gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

The full gate is currently blocked by the shared G5 baseline. PR #43 must integrate the accepted MW10 atomic-lock release fix into `feature/g5-world-feature-graph`, then G6 must be resynchronized and the same full gate rerun.

After a green full gate:

```text
G6 SOURCE_ACCEPTED
        -> G7 Semantic Field Fabric
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
