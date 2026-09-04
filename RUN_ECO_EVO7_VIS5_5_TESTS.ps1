param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $Global:PSNativeCommandUseErrorActionPreference = $false
}
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) { throw "ECO.EVO7 VIS5.5 BLOCKED: expected Godot '$Expected', got '$Actual'" }
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }
    $Scripts = @(
        "res://tests/ecology/eco_evo7_vis5_0_terrain_ecosystem_composition_contract_acceptance.gd",
        "res://tests/ecology/eco_evo7_vis5_1_terrain_surface_frame_adapter_acceptance.gd",
        "res://tests/ecology/eco_evo7_vis5_2_noncanonical_ground_cover_bridge_acceptance.gd",
        "res://tests/ecology/eco_evo7_vis5_3_mixed_strata_composition_lab_acceptance.gd",
        "res://tests/ecology/eco_evo7_vis5_4_composition_lod_streaming_gate_acceptance.gd",
        "res://tests/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff_acceptance.gd"
    )
    foreach ($Script in $Scripts) {
        Write-Host "=== $Script ==="
        & $GodotPath --headless --path $RootDir --script $Script
        if ($LASTEXITCODE -ne 0) { throw "VIS5 line acceptance failed for $Script with exit code $LASTEXITCODE" }
    }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
}
Write-Host "ECO.EVO7 VIS5.5 Visual Evidence / Integrated PLAY1 Handoff candidate: PASS"
