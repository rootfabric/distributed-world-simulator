param([string]$GodotPath = $env:GODOT_BIN, [switch]$SkipBaseline)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
if (-not $SkipBaseline) {
    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF4_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "FFF4 dependency failed with exit code $LASTEXITCODE" }
}
& $GodotPath --headless --path $RootDir --script res://tests/research/ecology/eco_evo7_fff5_soil_memory_acceptance.gd
if ($LASTEXITCODE -ne 0) { throw "FFF5 soil-memory acceptance failed with exit code $LASTEXITCODE" }
Write-Host "ECO.EVO7 FFF5 Litter / Soil Memory candidate: PASS"