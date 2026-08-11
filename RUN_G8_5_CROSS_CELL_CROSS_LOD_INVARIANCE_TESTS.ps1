param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) { $Candidates += $GodotPath }
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
$Candidates += @(
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)
$GodotExecutable = $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique | Select-Object -First 1
if ($null -eq $GodotExecutable) { throw "Godot executable not found. Pass -GodotPath or set GODOT_BIN." }

$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== G8.5 editor import / parse ==="
    & $GodotExecutable --headless --editor --path $RootDir --quit
    if ($LASTEXITCODE -ne 0) { throw "G8.5 headless editor import failed" }

    Write-Host "=== G7.3 accepted semantic representation invariance ==="
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/semantic_fields/g7_3_cross_cell_cross_lod_invariance_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G7.3 semantic invariance regression failed" }

    foreach ($Stage in @(
        @{ Name = "G8.0 accepted contracts"; Script = "res://tests/procedural/geomorphology/g8_0_geomorphology_contracts_acceptance.gd" },
        @{ Name = "G8.1 accepted valley"; Script = "res://tests/procedural/geomorphology/g8_1_valley_incision_acceptance.gd" },
        @{ Name = "G8.2 accepted river channel"; Script = "res://tests/procedural/geomorphology/g8_2_river_channel_incision_acceptance.gd" },
        @{ Name = "G8.3 accepted banks/floodplain"; Script = "res://tests/procedural/geomorphology/g8_3_banks_floodplain_acceptance.gd" },
        @{ Name = "G8.4 accepted erosion/deposition"; Script = "res://tests/procedural/geomorphology/g8_4_erosion_deposition_acceptance.gd" }
    )) {
        Write-Host "=== $($Stage.Name) regression ==="
        & $GodotExecutable --headless --path $RootDir --script $Stage.Script
        if ($LASTEXITCODE -ne 0) { throw "$($Stage.Name) regression failed" }
    }

    Write-Host "=== G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance ==="
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/geomorphology/g8_5_cross_cell_cross_lod_invariance_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G8.5 geomorphology invariance acceptance failed" }

    Write-Host "G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance focused gate passed."
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
