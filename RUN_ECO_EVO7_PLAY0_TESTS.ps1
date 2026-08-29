param(
    [string]$GodotBin = $env:GODOT_BIN
)
$ErrorActionPreference = 'Stop'
# Godot prints benign diagnostics to stderr; keep native stderr from aborting
# the runner under PowerShell 7.4+ policy.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $Global:PSNativeCommandUseErrorActionPreference = $false
}
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $DefaultDouble = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
    if (Test-Path $DefaultDouble) {
        $GodotBin = $DefaultDouble
    }
}
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 PLAY0 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
$ErrorActionPreference = 'Continue'
& $GodotBin --headless --path $Root --script 'res://tests/ecology/eco_evo7_play0_live_planet_playground_acceptance.gd' 2>$null
exit $LASTEXITCODE
