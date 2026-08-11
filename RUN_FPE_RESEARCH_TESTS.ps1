param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $Candidates = @(
        $env:GODOT_BIN,
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            $GodotPath = (Resolve-Path $Candidate).Path
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path $GodotPath)) {
    throw "Godot executable not found. Pass -GodotPath or set GODOT_BIN."
}

$Tests = @(
    "res://tests/characters/test_first_person_embodiment_contract.gd"
)

$Failed = $false
foreach ($Test in $Tests) {
    Write-Host "Running $Test" -ForegroundColor Cyan
    & $GodotPath --headless --path $Root --script $Test
    if ($LASTEXITCODE -ne 0) {
        $Failed = $true
        Write-Host "FAIL: $Test" -ForegroundColor Red
        break
    }
}

if ($Failed) {
    exit 1
}

Write-Host "FirstPersonEmbodiment focused tests: PASS" -ForegroundColor Green
exit 0
