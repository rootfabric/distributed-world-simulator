param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if ($GodotPath) {
    $Candidates += $GodotPath
}
if ($env:GODOT_BIN) {
    $Candidates += $env:GODOT_BIN
}
$Candidates += @(
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.console.exe"),
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.console.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$GodotExecutable = $null
foreach ($Candidate in $Candidates) {
    if ($Candidate -and (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        $GodotExecutable = (Resolve-Path -LiteralPath $Candidate).Path
        break
    }
}

if (-not $GodotExecutable) {
    throw "Godot executable not found. Set GODOT_BIN or pass -GodotPath with the Godot 4.7.1 double-precision console/editor binary."
}

& $GodotExecutable `
    --headless `
    --path $RootDir `
    --script "res://tests/matter/presentation/test_mw3_local_meshing.gd"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
