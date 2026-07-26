$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe"
)

$Godot = $null
foreach ($Candidate in $Candidates) {
    if (Test-Path $Candidate) {
        $Godot = $Candidate
        break
    }
}

if ($null -eq $Godot) {
    throw "Double-precision Godot editor was not found. Update RUN_ATMOSPHERE_ARCHITECTURE_TEST.ps1 with its path."
}

& $Godot `
    --headless `
    --path $ProjectRoot `
    --script res://tests/unit/test_atmosphere_layer.gd

if ($LASTEXITCODE -ne 0) {
    throw "Atmosphere architecture tests failed with exit code $LASTEXITCODE"
}
