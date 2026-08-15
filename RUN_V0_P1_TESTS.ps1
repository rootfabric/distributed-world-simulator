[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}

$Tests = @(
    "res://tests/runtime/test_v0_p1_earth_wiring.gd",
    "res://tests/runtime/test_v0_p1_world_items_containers.gd",
    "res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd",
    "res://tests/runtime/test_v0_s1_mvp_launch_options.gd"
)

Write-Host "[V0-P1] Project: $ProjectRoot"
Write-Host "[V0-P1] Godot:   $GodotExe"

foreach ($Test in $Tests) {
    Write-Host ""
    Write-Host "=== $Test ==="
    & $GodotExe --headless --path $ProjectRoot --script $Test
    if ($LASTEXITCODE -ne 0) {
        throw "V0-P1 preflight failed: $Test (exit $LASTEXITCODE)"
    }
}

Write-Host ""
Write-Host "[V0-P1] All preflight tests passed."
