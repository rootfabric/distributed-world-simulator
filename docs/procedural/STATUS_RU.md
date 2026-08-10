# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g7-semantic-field-fabric`
**Architecture revision:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`

```text
G6 Hydrology / Fluid Surface            SOURCE_ACCEPTED
G7.0 Semantic Field Contracts           ACCEPTED
G7.1 Upstream Semantic Field Adapters   ACCEPTED
G7.2 Composition / Provenance            ACCEPTED
G7.3 Cross-Cell / Cross-LOD Invariance  ACCEPTED
G7.4 Semantic Field Lab                 FIX2 FOCUSED PASS / FULL PENDING
```

## Operational frontier

Fast-moving project state is owned by main PC0 registry. Legacy `GLOBAL-P0 active_frontiers` remains advisory.

```text
registry generation: 5
program: G
stage: G7.4 Semantic Field Lab
stage_status: FIX2_FOCUSED_PASS_FULL_REGRESSION_PENDING
health: YELLOW
```

## G7.3 accepted baseline

```text
G7.3 Cross-Cell / Cross-LOD Invariance: PASS (122 assertions)
G7.3 FULL ACCEPTANCE: PASS
World/core regression: PASS
main_scene_cli_all: 6 PASS / 0 FAIL
Working tree: CLEAN
```

Accepted tested head:

```text
910899a906e684d6793cd74ba898d68c457a37b4
```

## G7.4

G7.4 remains a derived visual/debug layer over accepted semantic samples. It visualizes only real adapter-backed fields:

```text
geo/surface-height-m
geo/valley-influence
geo/river-distance-m
geo/river-width-m
geo/fluid-surface-distance-m
```

The six vocabulary-only fields remain explicitly not faked.

### Fix1

Windows PowerShell launcher/runners are ASCII-only and AST-parse checked before runtime.

### Fix2 — shared M5 convergence

The first full G7.4 world regression exposed a shared M5 final-barrier handoff deadlock. Fix2 makes later peer states monotonic evidence for earlier convergence barriers when frozen player/item checksums match.

Focused Windows verification now passes:

```text
PASS: A reconnect graphical acceptance completed
PASS: B graphical acceptance completed
PASS: final clients passed
M5 graphical multiplayer acceptance: 92 assertions, 0 failures
```

Tested runtime/focused head:

```text
866187c437f0dbc14bf5d8d0f0f9fb25ab106f17
```

Remaining blockers:

```text
G7_4_FULL_WORLD_REGRESSION_PENDING
G7_4_MANUAL_GRAPHICAL_ACCEPTANCE_PENDING
```

## Next

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_4_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

After automated PASS:

```powershell
.\START_G7_4_SEMANTIC_FIELD_LAB.ps1 -GodotPath $Godot
```

Then manual graphical observation can close G7.4 before G7 Full Acceptance.
