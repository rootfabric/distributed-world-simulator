param(
    [string]$GodotBin = $env:GODOT_BIN
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Scene = 'res://scenes/labs/ecology/eco_evo7_play0_live_planet_playground.tscn'

# Locate / accept the exact Windows DOUBLE build of Godot.
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $Candidates = @(
        'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe',
        "$Root\..\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate) {
            $GodotBin = $Candidate
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotBin) -or -not (Test-Path $GodotBin)) {
    throw 'ECO.EVO7 PLAY0 BLOCKED: pass -GodotBin or set GODOT_BIN with the exact double Godot 4.7.1 executable.'
}
$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 PLAY0 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
Write-Host "ECO.EVO7 PLAY0 launching exact DOUBLE Godot $Actual"
Write-Host "ECO.EVO7 PLAY0 launching explicit scene: $Scene"
& $GodotBin --path $Root --resolution 1600x900 --scene $Scene
exit $LASTEXITCODE
