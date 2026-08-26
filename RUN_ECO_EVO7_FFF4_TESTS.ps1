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
    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF31_CAUSALITY_REPAIR.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "FFF3.1 causality repair chain failed with exit code $LASTEXITCODE" }
}
& $GodotPath --headless --path $RootDir --script res://tests/research/ecology/eco_evo7_fff4_water_soil_acceptance.gd
if ($LASTEXITCODE -ne 0) { throw "FFF4 water+soil acceptance failed with exit code $LASTEXITCODE" }
Write-Host "ECO.EVO7 FFF4 Water + Soil Texture Feedback candidate: PASS"
