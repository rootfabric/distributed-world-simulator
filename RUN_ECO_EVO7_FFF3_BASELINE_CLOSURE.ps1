param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

function Invoke-Stage {
    param([string]$Name, [scriptblock]$Command)
    Write-Host "=== $Name ==="
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
}

Invoke-Stage "ECO.EVO6 generated-rule selection regression" {
    & (Join-Path $RootDir "RUN_ECO_EVO6_RULE_SELECTION_CONTINUATION.ps1") -GodotPath $GodotPath
}
Invoke-Stage "ECO.EVO6-WATER regression" {
    & (Join-Path $RootDir "RUN_ECO_EVO6_WATER_SELECTION.ps1") -SkipBaseline -GodotPath $GodotPath
}
Invoke-Stage "ECO.EVO7 FFF0" {
    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF0_TESTS.ps1") -GodotPath $GodotPath
}
Invoke-Stage "ECO.EVO7 FFF1" {
    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF1_TESTS.ps1") -GodotPath $GodotPath
}
Invoke-Stage "ECO.EVO7 FFF2" {
    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF2_TESTS.ps1") -GodotPath $GodotPath
}
Invoke-Stage "ECO.EVO7 FFF3" {
    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF3_TESTS.ps1") -GodotPath $GodotPath
}
Invoke-Stage "ECO.EVO7 multiseed robustness" {
    & $GodotPath --headless --path $RootDir --script res://tests/research/ecology/eco_evo7_multiseed_robustness_acceptance.gd
}

Write-Host "ECO.EVO7 FFF3 immutable baseline closure regression: PASS"