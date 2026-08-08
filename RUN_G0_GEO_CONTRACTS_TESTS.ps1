$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
    $Candidates += $env:GODOT_BIN
}
$Candidates += @(
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$GodotExecutable = $Candidates |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -Unique |
    Select-Object -First 1

if ($null -eq $GodotExecutable) {
    throw "Godot executable not found. Set GODOT_BIN to the Godot 4.7.1 double-precision console/editor binary."
}

& $GodotExecutable `
    --headless `
    --path $RootDir `
    --script "res://tests/procedural/contracts/g0_geo_contracts_acceptance.gd"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
