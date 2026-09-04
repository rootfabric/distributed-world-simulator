param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    Write-Error "ECO.EVO7 LS4.1 BLOCKED: expected Godot '$Expected', got '$Actual'"
    exit 2
}

& $GodotPath --headless --path $Root --script res://tests/ecology/eco_evo7_ls4_scope_contract_acceptance.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $GodotPath --headless --path $Root --script res://tests/ecology/eco_evo7_ls41_multi_species_acceptance.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $GodotPath --headless --path $Root --script res://tests/ecology/eco_evo7_ls41_vis1_acceptance.gd
exit $LASTEXITCODE
