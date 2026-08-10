param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
$HadBreakpointDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:GODOT_BIN = $GodotPath
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== G7.4 editor import / parse ==="
    & $GodotPath --headless --editor --path $RootDir --quit
    if ($LASTEXITCODE -ne 0) {
        throw "G7.4 headless editor import failed"
    }

    foreach ($TestScript in @(
        "res://tests/procedural/semantic_fields/g7_0_semantic_field_contracts_acceptance.gd",
        "res://tests/procedural/semantic_fields/g7_1_upstream_semantic_field_adapters_acceptance.gd",
        "res://tests/procedural/semantic_fields/g7_2_composition_provenance_acceptance.gd",
        "res://tests/procedural/semantic_fields/g7_3_cross_cell_cross_lod_invariance_acceptance.gd",
        "res://tests/procedural/semantic_fields/g7_4_semantic_field_lab_acceptance.gd"
    )) {
        Write-Host "Running $TestScript"
        & $GodotPath --headless --path $RootDir --script $TestScript
        if ($LASTEXITCODE -ne 0) {
            throw "G7.4 focused semantic regression failed: $TestScript"
        }
    }

    Write-Host "=== G7.4 headless semantic field lab smoke ==="
    $SceneOutput = & $GodotPath --headless --path $RootDir --scene "res://scenes/labs/procedural/g7_4_semantic_field_lab.tscn" --quit-after 20 2>&1
    $SceneExitCode = $LASTEXITCODE
    $SceneText = ($SceneOutput | Out-String)
    $SceneOutput | ForEach-Object { Write-Host $_ }

    if ($SceneExitCode -ne 0) {
        throw "G7.4 semantic field lab headless smoke failed with exit code $SceneExitCode"
    }
    if ($SceneText -match "SCRIPT ERROR|Parse Error|Failed to load script") {
        throw "G7.4 semantic field lab headless smoke reported a script parse/load error"
    }
    if ($SceneText -notmatch "G7\.4 Semantic Field Lab: PASS") {
        throw "G7.4 semantic field lab did not emit the required PASS marker"
    }
    if ($SceneText -notmatch "samples=561") {
        throw "G7.4 semantic field lab did not emit the expected 561 semantic samples"
    }
    if ($SceneText -notmatch "fields=5") {
        throw "G7.4 semantic field lab did not expose exactly five adapter-backed fields"
    }
    if ($SceneText -notmatch "vocabulary_only=6") {
        throw "G7.4 semantic field lab did not preserve six vocabulary-only fields as unavailable"
    }
    if ($SceneText -notmatch "faces=.*PX" -or $SceneText -notmatch "faces=.*PZ") {
        throw "G7.4 semantic field lab did not prove PX/PZ semantic sampling coverage"
    }

    Write-Host "G7.4 Semantic Field Lab focused gate passed."
    Write-Host "The lab renders only adapter-backed semantic truth; vocabulary-only fields remain explicitly unavailable."
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
    if ($HadBreakpointDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}

exit 0
