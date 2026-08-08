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
G6.4 FIX4 MANUAL GRAPHICAL PASS
G6 FULL ACCEPTANCE IMPLEMENTED CANDIDATE
```

Current branch documentation head after runtime-environment verification:

```text
e7576bde3cbb91d327966ce7b095f326c6cae35e
```

G6 Full Acceptance is currently blocked by the shared MW10 baseline, not by the hydrology code. PR #43 must first land in `feature/g5-world-feature-graph`; G6 must then be resynchronized and `RUN_G6_FULL_ACCEPTANCE.ps1` rerun.

Project-provided Linux double Godot has been independently verified in the assistant runtime:

```text
4.7.1.stable.double.custom_build.a13da4feb
headless GDScript smoke: PASS
```

The assistant container still lacks a full repository checkout, so project-level Godot suites were not run there. Windows remains the final G6 full-acceptance runtime environment after the shared-baseline resync.

Run locally:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
