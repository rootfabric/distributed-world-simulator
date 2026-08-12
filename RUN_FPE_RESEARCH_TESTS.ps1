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

$FatalMarkers = @(
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "ERROR: Failed to load script"
)

function Invoke-GodotCaptured {
    param(
        [string[]]$Arguments
    )

    $OutputLines = [System.Collections.Generic.List[string]]::new()
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    $ExitCode = 1
    try {
        # Windows PowerShell can surface native stderr as ErrorRecord objects.
        # Keep them in the captured stream instead of letting $ErrorActionPreference=Stop
        # abort before we can apply the explicit Godot fatal-marker policy below.
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        & $GodotPath @Arguments 2>&1 | ForEach-Object {
            $Line = [string]$_
            $OutputLines.Add($Line)
            Write-Host $Line
        }
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
        }
    }

    return @{
        ExitCode = $ExitCode
        OutputText = ($OutputLines -join "`n")
    }
}

function Get-FatalGodotMarker {
    param(
        [string]$OutputText
    )
    foreach ($Marker in $FatalMarkers) {
        if ($OutputText.Contains($Marker)) {
            return $Marker
        }
    }
    return ""
}

# FPE is commonly exercised from worktrees that switch between long-lived
# research/control branches. Godot resolves class_name dependencies through
# .godot/global_script_class_cache.cfg. Refresh that cache before loading CH9.6
# so a stale cache cannot make accepted classes appear missing.
Write-Host "Refreshing Godot global script class cache" -ForegroundColor Cyan
$Preflight = Invoke-GodotCaptured -Arguments @(
    "--headless",
    "--editor",
    "--path", $Root,
    "--quit"
)
$PreflightFatal = Get-FatalGodotMarker -OutputText ([string]$Preflight.OutputText)
if ([int]$Preflight.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($PreflightFatal)) {
    Write-Host "FAIL: Godot class-cache preflight (exit=$($Preflight.ExitCode), fatal_marker=$PreflightFatal)" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Godot class-cache preflight" -ForegroundColor Green

$Tests = @(
    @{
        Path = "res://tests/characters/test_first_person_embodiment_contract.gd"
        PassMarker = "FirstPersonEmbodiment contract: PASS"
    },
    @{
        Path = "res://tests/characters/test_first_person_hotbar_network_adapter.gd"
        PassMarker = "FirstPerson hotbar nonblocking adapter: PASS"
    },
    @{
        Path = "res://tests/characters/test_first_person_embodiment_lab_load.gd"
        PassMarker = "FirstPersonEmbodiment graphical scene load: PASS"
    }
)

foreach ($Test in $Tests) {
    $TestPath = [string]$Test.Path
    Write-Host "Running $TestPath" -ForegroundColor Cyan

    $Run = Invoke-GodotCaptured -Arguments @(
        "--headless",
        "--path", $Root,
        "--script", $TestPath
    )
    $EngineFatal = Get-FatalGodotMarker -OutputText ([string]$Run.OutputText)
    $PassMarkerSeen = ([string]$Run.OutputText).Contains([string]$Test.PassMarker)

    if ([int]$Run.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($EngineFatal) -or -not $PassMarkerSeen) {
        Write-Host "FAIL: $TestPath (exit=$($Run.ExitCode), fatal_marker=$EngineFatal, pass_marker=$PassMarkerSeen)" -ForegroundColor Red
        exit 1
    }

    Write-Host "PASS: $TestPath" -ForegroundColor Green
}

Write-Host "FirstPersonEmbodiment focused tests: PASS" -ForegroundColor Green
exit 0