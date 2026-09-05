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
    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF5_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "FFF5 dependency chain failed with exit code $LASTEXITCODE" }
}

Write-Host "=== ECO.EVO7 FFF6 visual first-frame regression ==="
& $GodotPath --headless --path $RootDir --script res://tests/ecology/eco_evo7_fff6_visual_first_frame_acceptance.gd
if ($LASTEXITCODE -ne 0) { throw "FFF6 visual first-frame regression failed with exit code $LASTEXITCODE" }

Write-Host "=== ECO.EVO7 FFF6 100-cycle succession acceptance ==="
& $GodotPath --headless --path $RootDir --script res://tests/research/ecology/eco_evo7_fff6_succession_acceptance.gd
if ($LASTEXITCODE -ne 0) { throw "FFF6 succession acceptance failed with exit code $LASTEXITCODE" }

$PreviousAutocap = $env:EVO7_FFF6_LAB_AUTOCAP
try {
    Write-Host "=== ECO.EVO7 FFF6 visual observatory adapter ==="
    $env:EVO7_FFF6_LAB_AUTOCAP = "1"
    & $GodotPath --headless --path $RootDir res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn
    if ($LASTEXITCODE -ne 0) { throw "FFF6 visual observatory adapter failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousAutocap) { Remove-Item Env:\EVO7_FFF6_LAB_AUTOCAP -ErrorAction SilentlyContinue }
    else { $env:EVO7_FFF6_LAB_AUTOCAP = $PreviousAutocap }
}
Write-Host "ECO.EVO7 FFF6 Closed Community / Succession candidate: PASS"
