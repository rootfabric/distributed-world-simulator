$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$GodotBin = if ($env:GODOT_BIN) {
    $env:GODOT_BIN
}
else {
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"

if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    throw "Godot binary not found: $GodotBin"
}

$ActualVersion = (& $GodotBin --version 2>&1 | Select-Object -First 1).Trim()
if ($ActualVersion -ne $ExpectedVersion) {
    throw "GODOT_IDENTITY_MISMATCH: actual=$ActualVersion expected=$ExpectedVersion"
}

function Invoke-GodotScript {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    & $GodotBin --headless --path $RepoRoot --script $ScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Godot script failed: $ScriptPath exit=$LASTEXITCODE"
    }
}

Invoke-GodotScript "res://tests/research/fabric_bake0/fabric_bake_b0_0_acceptance.gd"
Invoke-GodotScript "res://tests/research/fabric_bake0/fabric_bake_b0_1_acceptance.gd"
Invoke-GodotScript "res://tests/research/fabric_bake0/fabric_bake_b0_1_playground.gd"
