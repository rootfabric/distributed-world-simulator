param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath is required. Pass -GodotPath or set GODOT_BIN."
}
if (-not (Test-Path $GodotPath)) {
    throw "Godot binary not found: $GodotPath"
}

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
$HadBreakpointDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:GODOT_BIN = $GodotPath
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== G6.3 accepted dependency gate ==="
    & "$PSScriptRoot\RUN_G6_3_RUNTIME_WATER_QUERY_TESTS.ps1"
    if (-not $?) {
        throw "G6.3 accepted dependency gate failed"
    }

    Write-Host "=== G6.4 source / P0 / adaptive representation contract gate ==="
    & $GodotPath --headless --path $PSScriptRoot --script res://tests/procedural/hydrology/g6_4_casual_visual_river_lab_acceptance.gd
    if ($LASTEXITCODE -ne 0) {
        throw "G6.4 visual river lab contract gate failed"
    }

    Write-Host "=== G6.4 headless scene + river LOD + G3 detail-recipe smoke ==="
    $SceneOutput = & $GodotPath --headless --path $PSScriptRoot --scene "res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn" --quit-after 2 2>&1
    $SceneExitCode = $LASTEXITCODE
    $SceneText = ($SceneOutput | Out-String)
    $SceneOutput | ForEach-Object { Write-Host $_ }

    if ($SceneExitCode -ne 0) {
        throw "G6.4 visual river lab headless smoke failed with exit code $SceneExitCode"
    }
    if ($SceneText -match "SCRIPT ERROR|Parse Error|Failed to load script") {
        throw "G6.4 visual river lab headless smoke reported a script parse/load error"
    }
    if ($SceneText -notmatch "G6\.4 Adaptive Macro Surface: PASS") {
        throw "G6.4 adaptive macro surface did not emit the required PASS marker"
    }
    if ($SceneText -notmatch "far_triangles=\d+ near_triangles=\d+") {
        throw "G6.4 adaptive macro surface marker did not expose far/near geometry detail"
    }
    if ($SceneText -notmatch "octaves=8") {
        throw "G6.4 fix4 marker did not expose the eight-octave diagnostic G3 recipe"
    }
    if ($SceneText -notmatch "min_signal_km=4\.688") {
        throw "G6.4 fix4 marker did not expose the expected ~4.7 km minimum source wavelength"
    }
    if ($SceneText -notmatch "G6\.4 Casual Visual River Lab: PASS") {
        throw "G6.4 visual river lab did not emit the required PASS runtime marker"
    }
    if ($SceneText -notmatch "max_lod=\d+") {
        throw "G6.4 visual river lab PASS marker did not expose active max LOD"
    }
    if ($SceneText -notmatch "river_lod=\d+\.\.\d+") {
        throw "G6.4 visual river lab PASS marker did not expose river representation LOD range"
    }

    Write-Host "G6.4 Casual Visual River Lab fix4 automated gate passed."
    Write-Host "Headless proof covers adaptive G2 selection, river sampling, real G3 triangle refinement, and an 8-octave diagnostic detail recipe."
    Write-Host "BreakpointRuntimeBridge is disabled for this standalone gate to avoid port 9081 collisions."
    Write-Host "Manual graphical detail observation is still required before G6.4 acceptance."
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
    if ($HadBreakpointDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}

exit 0