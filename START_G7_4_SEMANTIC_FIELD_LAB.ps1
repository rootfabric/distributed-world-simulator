param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

Write-Host "G7.4 Semantic Field Lab - derived visualization over accepted G7 semantics"
Write-Host "1 surface height | 2 valley influence | 3 river distance | 4 river width | 5 fluid-surface distance"
Write-Host "F river centerline | W/S zoom | A/D yaw | Q/E pitch | Space auto-orbit | R reset"
Write-Host "Slope, curvature, drainage, continentalness, temperature and moisture remain vocabulary-only and are intentionally NOT faked."
Write-Host "Colors, camera and mesh density are presentation-only and excluded from canonical semantic checksums."

$HadBreakpointDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$ExitCode = 0
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotPath --path $PSScriptRoot --scene "res://scenes/labs/procedural/g7_4_semantic_field_lab.tscn"
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
