param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$Output = ""
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($GodotBin)) { throw 'Set GODOT_BIN to the project-pinned double-precision Godot executable.' }
$Engine = (Resolve-Path -LiteralPath $GodotBin).Path
if ([string]::IsNullOrWhiteSpace($Output)) { $Output = Join-Path $PSScriptRoot ("artifacts/mvp5-visible-launch-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
# This launches an observable automated native-input scenario, not a manual
# keyboard acceptance gate. The runner owns and cleans up exactly its children.
Push-Location $PSScriptRoot
$PreviousBridgeSetting = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = '1'
    & $Engine --headless --path $PSScriptRoot --editor --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    & python tests/integration/test_v0_mvp_5_graphical_material.py --engine $Engine --output $Output
    if ($LASTEXITCODE -ne 0) { throw 'MVP5 graphical material validation failed. Inspect the preserved output directory.' }
} finally {
    $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBridgeSetting
    Pop-Location
}
