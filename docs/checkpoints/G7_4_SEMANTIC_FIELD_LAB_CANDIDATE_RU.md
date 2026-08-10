# G7.4 Semantic Field Lab — FIX2 FOCUSED PASS / FULL ACCEPTANCE PENDING

**Global architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g7-semantic-field-fabric`
**Parent:** `G7.3 ACCEPTED @ 1a2808a2e03c565c9a52fc467c51398d43fcf3e9`

## Current state

```text
G7.4 Semantic Field Lab
stage: FIX2_FOCUSED_PASS_FULL_REGRESSION_PENDING
PC0 G health: YELLOW
```

G7.4 is a derived graphical lab over accepted semantic truth. Rendering, camera, mesh density and color remain outside canonical world identity.

Visualized adapter-backed fields:

```text
geo/surface-height-m
geo/valley-influence
geo/river-distance-m
geo/river-width-m
geo/fluid-surface-distance-m
```

Vocabulary-only fields remain explicitly not faked:

```text
geo/slope
geo/curvature
geo/drainage-potential
geo/continentalness
geo/temperature-baseline
geo/moisture-baseline
```

## Fix1 — Windows PowerShell launcher

The initial launcher contained a Unicode em dash. Legacy Windows PowerShell could decode UTF-8-without-BOM through an ANSI codepage into smart-quote bytes and parse field legend text as PowerShell expressions.

Fix1 keeps G7.4 PowerShell launchers/runners ASCII-only and makes the full gate AST-parse them before runtime. No world semantics changed.

## Fix2 — shared M5 final convergence

The first full G7.4 run reached shared world regression and exposed an inherited M5 barrier handoff deadlock:

```text
A2: WAIT_CONVERGENCE_PEER timeout
B : WAIT_FINAL_CONVERGENCE_PEER timeout

both leave_result.success = true
server joins = 3
server leaves = 3
server connected_peer_count = 0
```

All canonical final-state assertions still passed. Root cause was monotonic barrier progress: a faster peer could publish `FINAL_CONVERGENCE_LOCKED` before the slower peer observed the earlier `CONVERGENCE_LOCKED` report.

Fix2 accepts later peer states as proof of already-crossed earlier barriers only when frozen player/item checksums match:

```text
READY_TO_CONVERGE
  < CONVERGENCE_LOCKED
  < FINAL_CONVERGENCE_LOCKED
  < COMPLETE
```

No timeout was increased and no assertion was weakened.

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

## PC0

Main-owned registry generation 5 now declares:

```text
G stage_status = FIX2_FOCUSED_PASS_FULL_REGRESSION_PENDING
G health       = YELLOW
```

Remaining blockers:

```text
G7_4_FULL_WORLD_REGRESSION_PENDING
G7_4_MANUAL_GRAPHICAL_ACCEPTANCE_PENDING
```

Therefore full G7.4 acceptance may resume, but G7.4 is not accepted yet.

## Next automated gate

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_4_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Expected final marker:

```text
G7.4 AUTOMATED ACCEPTANCE: PASS
Architecture revision: GLOBAL-P0-2026-08-10-R2
Project Control revision: PC0-2026-08-10-R1
PC0 operational G frontier: PASS
PC0 G health is not RED: PASS
G7.3 ACCEPTED ancestor: PASS
G7.4 visual-lab scope: PASS
Five adapter-backed semantic fields: PASS
Six vocabulary-only fields not faked: PASS
World/core regression: PASS
Working tree: CLEAN
MANUAL GRAPHICAL OBSERVATION: REQUIRED before G7.4 ACCEPTED
```

After automated PASS, run `START_G7_4_SEMANTIC_FIELD_LAB.ps1` and complete the manual graphical checks before marking G7.4 accepted.
