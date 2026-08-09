# T1A.2 M4 composition fix — Windows retest commands

Branch: `feature/t1a2-d0-authoritative-outpost-builder`

The T1A.2 focused gate is already PASS (186 assertions). The current blocker is the M4 final server-report read race fixed in `tests/runtime/test_m4_graphical_shared_gameplay_processes.gd`.

Run focused M4 first:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
& $Godot --headless --path . --script res://tests/runtime/test_m4_graphical_shared_gameplay_processes.gd
Write-Host "M4 EXIT: $LASTEXITCODE"
```

Expected:

```text
M4 graphical shared gameplay: 22 assertions, 0 failures
M4 EXIT: 0
```

Then run full regression:

```powershell
$env:GODOT_BIN = $Godot
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Expected final marker:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
```
