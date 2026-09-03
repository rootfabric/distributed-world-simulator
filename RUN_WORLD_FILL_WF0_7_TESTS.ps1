param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "world-fill-wf0-7-summary.json"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

function Resolve-GodotExecutable {
    param([string]$RequestedPath)
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $Candidates += $RequestedPath }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
    $Candidates += @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot4", "godot")) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $Command) { $Candidates += $Command.Source }
    }
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Resolve-Path $Candidate).Path
        }
    }
    throw "Double-precision Godot was not found. Set GODOT_BIN or pass -GodotPath."
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
$Summary = [ordered]@{
    schema = "world_fill.wf0_7_runner_summary.v1"
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    finished_at_utc = $null
    godot = $Godot
    godot_version = $null
    project_root = $ProjectRoot
    passed = $false
    steps = @()
}

function Save-Summary {
    $Summary.finished_at_utc = [DateTime]::UtcNow.ToString("o")
    $TemporaryPath = "$ReportPath.$PID.tmp"
    $Summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $TemporaryPath -Encoding UTF8
    Move-Item -LiteralPath $TemporaryPath -Destination $ReportPath -Force
}

function Invoke-CheckedGodot {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$RequireMarker = ""
    )
    Write-Host ""; Write-Host "[$Name]" -ForegroundColor Cyan
    $Started = [DateTime]::UtcNow
    $Captured = @()
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false }
        & $Godot @Arguments 2>&1 | Tee-Object -Variable Captured | ForEach-Object { Write-Host $_ }
        $RawExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference }
    }
    $OutputText = ($Captured | Out-String)
    $HasFailureMarker = $OutputText -match '(?m): FAIL(?:\s|\()'
    $HasScriptError = $OutputText -match 'SCRIPT ERROR'
    $ExitCode = if ($RawExitCode -ne 0) { $RawExitCode } elseif ($HasFailureMarker -or $HasScriptError) { 1 } else { 0 }
    if ($ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($RequireMarker)) {
        if (-not $OutputText.Contains($RequireMarker)) {
            Write-Host "Required marker missing: $RequireMarker" -ForegroundColor Red
            $ExitCode = 1
        }
    }
    $Summary.steps += [ordered]@{
        name = $Name
        exit_code = $ExitCode
        duration_seconds = [Math]::Round(([DateTime]::UtcNow - $Started).TotalSeconds, 3)
        passed = ($ExitCode -eq 0)
    }
    Save-Summary
    if ($ExitCode -ne 0) { throw "$Name failed with exit code $ExitCode" }
}

try {
    Write-Host "Godot: $Godot"
    $Summary.godot_version = (& $Godot --version 2>&1 | Out-String).Trim()
    Write-Host "Godot version: $($Summary.godot_version)"

    Invoke-CheckedGodot -Name "editor_import_parse" -Arguments @(
        "--headless", "--editor", "--path", $ProjectRoot, "--quit"
    )

    Invoke-CheckedGodot -Name "wf0_1_dressing_contract" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/world_fill/test_wf0_1_dressing_contract.gd"
    )

    Invoke-CheckedGodot -Name "wf0_2_prop_scatter" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/world_fill/test_wf0_2_prop_scatter.gd"
    )

    Invoke-CheckedGodot -Name "wf0_3_scar_layer" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/world_fill/test_wf0_3_scar_layer.gd"
    )
    Invoke-CheckedGodot -Name "wf0_4_atmosphere" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/world_fill/test_wf0_4_atmosphere.gd"
    )
    Invoke-CheckedGodot -Name "wf0_5_event_feedback" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/world_fill/test_wf0_5_event_feedback.gd"
    )
    Invoke-CheckedGodot -Name "wf0_6_poi_kit" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/world_fill/test_wf0_6_poi_kit.gd"
    )
    Invoke-CheckedGodot -Name "wf0_7_playground_composition" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/world_fill/test_wf0_7_playground.gd"
    )

    Invoke-CheckedGodot -Name "digging_playground_headless" -Arguments @(
        "--headless", "--path", $ProjectRoot, "--quit-after", "10",
        "res://scenes/labs/world_fill/digging_playground.tscn"
    ) -RequireMarker "WORLD_FILL_DIGGING_PLAYGROUND_READY"
    Invoke-CheckedGodot -Name "world_fill_demo_headless" -Arguments @(
        "--headless", "--path", $ProjectRoot, "--quit-after", "10",
        "res://scenes/labs/world_fill/world_fill_demo.tscn"
    ) -RequireMarker "WORLD_FILL_DEMO_READY"

    $Summary.passed = $true
    Save-Summary
    Write-Host "WORLD FILL WF0.7 tests passed." -ForegroundColor Green
    Write-Host "Report: $ReportPath"
}
catch {
    $Summary.passed = $false
    Save-Summary
    Write-Host $_ -ForegroundColor Red
    exit 1
}






