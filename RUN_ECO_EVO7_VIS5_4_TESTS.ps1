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
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}
$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 VIS5.4 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$PreviousGodotBin = $env:GODOT_BIN
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $env:GODOT_BIN = $GodotPath
    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }
    Write-Host "=== ECO VIS5.3 closed predecessor regression ==="
    & (Join-Path $RootDir "RUN_ECO_EVO7_VIS5_3_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "VIS5.3 predecessor regression failed" }
    Write-Host "=== ECO VIS5.4 composition LOD / streaming focused acceptance ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_vis5_4_composition_lod_streaming_gate_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "VIS5.4 focused acceptance failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    if ($null -eq $PreviousGodotBin) { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue } else { $env:GODOT_BIN = $PreviousGodotBin }
}
Write-Host "ECO.EVO7 VIS5.4 Composition LOD / Streaming Local Gate candidate: PASS"
