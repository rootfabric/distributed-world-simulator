param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path $GodotPath)) {
    throw "Godot binary not found: $GodotPath"
}

Write-Host "G6.4 Casual Visual River Lab + G2 adaptive LOD + G3 diagnostic detail recipe"
Write-Host "Controls: A/D orbit, Q/E pitch, W/S zoom+refine/coarsen, Space auto-orbit, R reset"
Write-Host "Debug: 1 water, 2 centerline, 3 banks, 4 query probes, 5 seam markers, 6 LOD grid"
Write-Host "Watch refine: LOD grid shrinks while higher-frequency G3 macro detail becomes visible"
Write-Host "Standalone lab disables BreakpointRuntimeBridge to avoid 127.0.0.1:9081 collisions"
Write-Host "River valley carving is intentionally deferred to G8 Geomorphology"

$HadBreakpointDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$ExitCode = 0
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotPath --path $PSScriptRoot --scene "res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn"
    $ExitCode = $LASTEXITCODE
}
finally {
    if ($HadBreakpointDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled
    }
    else {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}

exit $ExitCode