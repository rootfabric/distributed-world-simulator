param([string]$GodotPath = $env:GODOT_BIN, [switch]$SkipBaseline)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
    & $GodotPath --headless --path $RootDir --import
    if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
}
if (-not $SkipBaseline) {
    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF3_BASELINE_CLOSURE.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "FFF3 immutable baseline regression failed with exit code $LASTEXITCODE" }
}
Write-Host "=== ECO.EVO7 FFF3.1 counterfactual identity repair ==="
& $GodotPath --headless --path $RootDir --script res://tests/research/ecology/eco_evo7_fff31_counterfactual_identity_acceptance.gd
if ($LASTEXITCODE -ne 0) { throw "FFF3.1 counterfactual identity acceptance failed with exit code $LASTEXITCODE" }
Write-Host "ECO.EVO7 FFF3.1 Causality Repair candidate: PASS"
