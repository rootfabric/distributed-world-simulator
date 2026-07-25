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
    throw "Double-precision Godot editor was not found. Update RUN_ENTITY_INTEGRATION_TEST.ps1 with its path."
}

& $Godot `
    --headless `
    --path $ProjectRoot `
    --script res://tests/integration/test_entity_registry_migration.gd

if ($LASTEXITCODE -ne 0) {
    throw "Entity registry integration tests failed with exit code $LASTEXITCODE"
}
