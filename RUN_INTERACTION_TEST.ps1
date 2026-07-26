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
    throw "Double-precision Godot editor was not found. Update RUN_INTERACTION_TEST.ps1 with its path."
}

& $Godot `
    --headless `
    --path $ProjectRoot `
    --script res://tests/integration/test_first_person_interaction.gd

if ($LASTEXITCODE -ne 0) {
    throw "First-person interaction integration tests failed with exit code $LASTEXITCODE"
}
