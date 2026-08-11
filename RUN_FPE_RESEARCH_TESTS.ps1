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
    @{
        Path = "res://tests/characters/test_first_person_embodiment_contract.gd"
        PassMarker = "FirstPersonEmbodiment contract: PASS"
    },
    @{
        Path = "res://tests/characters/test_first_person_embodiment_lab_load.gd"
        PassMarker = "FirstPersonEmbodiment graphical scene load: PASS"
    }
)

$FatalMarkers = @(
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "ERROR: Failed to load script"
)

$Failed = $false
foreach ($Test in $Tests) {
    $TestPath = [string]$Test.Path
    Write-Host "Running $TestPath" -ForegroundColor Cyan

    $OutputLines = [System.Collections.Generic.List[string]]::new()
    & $GodotPath --headless --path $Root --script $TestPath 2>&1 | ForEach-Object {
        $Line = [string]$_
        $OutputLines.Add($Line)
        Write-Host $Line
    }
    $ExitCode = $LASTEXITCODE
    $OutputText = $OutputLines -join "`n"

    $EngineError = $false
    foreach ($Marker in $FatalMarkers) {
        if ($OutputText.Contains($Marker)) {
            $EngineError = $true
            Write-Host "Detected fatal Godot marker: $Marker" -ForegroundColor Red
            break
        }
    }

    $PassMarkerSeen = $OutputText.Contains([string]$Test.PassMarker)
    if ($ExitCode -ne 0 -or $EngineError -or -not $PassMarkerSeen) {
        $Failed = $true
        Write-Host "FAIL: $TestPath (exit=$ExitCode, engine_error=$EngineError, pass_marker=$PassMarkerSeen)" -ForegroundColor Red
        break
    }

    Write-Host "PASS: $TestPath" -ForegroundColor Green
}

if ($Failed) {
    exit 1
}

Write-Host "FirstPersonEmbodiment focused tests: PASS" -ForegroundColor Green
exit 0
