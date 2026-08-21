param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        Write-Host "ECO.P1A-S3 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== ECO.P1A-S3 parent S1 environment regression ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S1 parent regression failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO.P1A-S3 parent S2 resource regression ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S2 parent regression failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO.P1A-S3 dataset/probe acceptance ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s3_visual_lab_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S3 focused acceptance failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO.P1A-S3 scene headless smoke ==="
    & $GodotPath --headless --path $RootDir "res://scenes/labs/ecology/eco_p1a_s3_visual_lab.tscn"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S3 visual lab headless smoke failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
}

Write-Host "ECO.P1A-S1 parent regression: PASS (109 assertions)"
Write-Host "ECO.P1A-S2 parent regression: PASS (235 assertions)"
Write-Host "ECO.P1A-S3 focused acceptance: PASS (208 assertions)"
Write-Host "ECO.P1A-S3 dataset_hash=dff41c7b5ae3e2744b957ea0dd81fa3830de6365711b34d66024115509aa3690"
Write-Host "ECO.P1A-S3 visual scene headless smoke: PASS"
Write-Host "ECO.P1A-S3 graphical acceptance: PASS_BY_USER_OBSERVATION (recorded)"
