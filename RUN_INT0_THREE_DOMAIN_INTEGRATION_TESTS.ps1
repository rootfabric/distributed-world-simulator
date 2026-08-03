param(
    [string]$GodotPath = "",
    [ValidateSet("focused", "full")]
    [string]$Profile = "full"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "int0-three-domain-integration-summary.json"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

$Candidates = @()
if ($GodotPath) { $Candidates += $GodotPath }
if ($env:GODOT_BIN) { $Candidates += $env:GODOT_BIN }
$Candidates += @(
    (Join-Path $ProjectRoot "tools\godot\godot.windows.editor.double.x86_64.console.exe"),
    (Join-Path $ProjectRoot "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $ProjectRoot "godot.windows.editor.double.x86_64.console.exe"),
    (Join-Path $ProjectRoot "godot.windows.editor.double.x86_64.exe"),
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
    throw "Godot executable not found. Set GODOT_BIN or pass -GodotPath with Godot 4.7.1 double."
}

$PowerShellExecutable = (Get-Process -Id $PID).Path
$env:GODOT_BIN = $GodotExecutable

$FocusedSuites = @(
    "RUN_INT0_RL3_MW10_COMPOSITION_TESTS.ps1",
    "RUN_NX6_PREDICTED_ITEM_INTERACTIONS_TESTS.ps1",
    "RUN_MW10_CROSS_REGION_MATTER_TRANSACTIONS_TESTS.ps1",
    "RUN_RL3_REPRESENTATION_AWARE_NETWORK_STREAMING_TESTS.ps1",
    "RUN_C24_PROXY_MESH_BACKEND_TESTS.ps1"
)

$FullSuites = @(
    "RUN_INT0_RL3_MW10_COMPOSITION_TESTS.ps1",
    "RUN_NX6_PREDICTED_ITEM_INTERACTIONS_TESTS.ps1",
    "RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.ps1",
    "RUN_MW8_MATTER_HANDOFF_TESTS.ps1",
    "RUN_MW9_DURABLE_HANDOFF_RECOVERY_TESTS.ps1",
    "RUN_MW9_RACE_STRESS_TESTS.ps1",
    "RUN_MW10_CROSS_REGION_MATTER_TRANSACTIONS_TESTS.ps1",
    "RUN_RL2_MATTER_MULTIRESOLUTION_MESHING_TESTS.ps1",
    "RUN_RL3_REPRESENTATION_AWARE_NETWORK_STREAMING_TESTS.ps1",
    "RUN_C2B_AUTHORITATIVE_ITEM_GRAPH_TESTS.ps1",
    "RUN_C9_DAMAGE_SPLIT_REPAIR_TESTS.ps1",
    "RUN_C22_COMPILED_PROXY_TESTS.ps1",
    "RUN_C23_PRODUCTION_HARDENING_TESTS.ps1",
    "RUN_C24_PROXY_MESH_BACKEND_TESTS.ps1",
    "RUN_NETWORK_CONTRACT_TESTS.ps1",
    "RUN_WORLD_REGRESSION_TESTS.ps1"
)

$SelectedSuites = if ($Profile -eq "focused") { $FocusedSuites } else { $FullSuites }
$Steps = [System.Collections.Generic.List[object]]::new()
$Passed = $false
$FailureMessage = ""
$StartedAt = [DateTime]::UtcNow

function Add-StepResult {
    param(
        [string]$Name,
        [string]$Target,
        [bool]$Succeeded,
        [double]$DurationSeconds,
        [int]$ExitCode,
        [string]$ErrorMessage = ""
    )
    $Steps.Add([ordered]@{
        name = $Name
        target = $Target
        passed = $Succeeded
        duration_seconds = [Math]::Round($DurationSeconds, 3)
        exit_code = $ExitCode
        error = $ErrorMessage
    })
}

function Invoke-GodotEditorImport {
    $Started = [DateTime]::UtcNow
    & $GodotExecutable --headless --editor --path $ProjectRoot --quit
    $Code = $LASTEXITCODE
    $Duration = ([DateTime]::UtcNow - $Started).TotalSeconds
    Add-StepResult -Name "editor_import" -Target "res://" -Succeeded ($Code -eq 0) -DurationSeconds $Duration -ExitCode $Code
    if ($Code -ne 0) {
        throw "INT0 editor import failed with exit code $Code."
    }
}

function Invoke-Suite {
    param([string]$RelativePath)

    $SuitePath = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $SuitePath -PathType Leaf)) {
        throw "Required INT0 suite is missing: $RelativePath"
    }

    $Arguments = @("-NoLogo", "-NoProfile")
    if ($env:OS -eq "Windows_NT") {
        $Arguments += @("-ExecutionPolicy", "Bypass")
    }
    $Arguments += @("-File", $SuitePath, "-GodotPath", $GodotExecutable)

    Write-Host "INT0 runner: $RelativePath" -ForegroundColor Cyan
    $Started = [DateTime]::UtcNow
    & $PowerShellExecutable @Arguments
    $Code = $LASTEXITCODE
    $Duration = ([DateTime]::UtcNow - $Started).TotalSeconds
    Add-StepResult -Name ([IO.Path]::GetFileNameWithoutExtension($RelativePath)) -Target $RelativePath -Succeeded ($Code -eq 0) -DurationSeconds $Duration -ExitCode $Code
    if ($Code -ne 0) {
        throw "INT0 suite failed: $RelativePath (exit $Code)"
    }
}

function Invoke-StaticChecks {
    $GitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $GitCommand) {
        throw "git is required for INT0 static checks."
    }

    $Started = [DateTime]::UtcNow
    & $GitCommand.Source -C $ProjectRoot diff --check
    $DiffCode = $LASTEXITCODE
    Add-StepResult -Name "git_diff_check" -Target "git diff --check" -Succeeded ($DiffCode -eq 0) -DurationSeconds (([DateTime]::UtcNow - $Started).TotalSeconds) -ExitCode $DiffCode
    if ($DiffCode -ne 0) {
        throw "git diff --check failed."
    }

    $Started = [DateTime]::UtcNow
    $ConflictOutput = & $GitCommand.Source -C $ProjectRoot grep -n -E '^(<<<<<<< |=======|>>>>>>> )' -- . ':!artifacts' 2>&1
    $ConflictCode = $LASTEXITCODE
    $NoConflicts = $ConflictCode -eq 1
    Add-StepResult -Name "conflict_marker_scan" -Target "git grep conflict markers" -Succeeded $NoConflicts -DurationSeconds (([DateTime]::UtcNow - $Started).TotalSeconds) -ExitCode $ConflictCode -ErrorMessage ($(if ($NoConflicts) { "" } else { [string]$ConflictOutput }))
    if (-not $NoConflicts) {
        throw "Conflict-marker scan failed."
    }

    $Started = [DateTime]::UtcNow
    $RemainingGodot = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "godot*" })
    Add-StepResult -Name "remaining_godot_processes" -Target "Get-Process godot*" -Succeeded ($RemainingGodot.Count -eq 0) -DurationSeconds (([DateTime]::UtcNow - $Started).TotalSeconds) -ExitCode ($(if ($RemainingGodot.Count -eq 0) { 0 } else { 1 })) -ErrorMessage ($(if ($RemainingGodot.Count -eq 0) { "" } else { ($RemainingGodot.ProcessName -join ", ") }))
    if ($RemainingGodot.Count -ne 0) {
        throw "Godot processes remain after INT0 runner: $($RemainingGodot.ProcessName -join ', ')"
    }
}

try {
    Write-Host "INT0 three-domain integration gate [$Profile]" -ForegroundColor Green
    Write-Host "Godot: $GodotExecutable"
    Invoke-GodotEditorImport
    foreach ($Suite in $SelectedSuites) {
        Invoke-Suite -RelativePath $Suite
    }
    Invoke-StaticChecks
    $Passed = $true
}
catch {
    $FailureMessage = $_.Exception.Message
    Write-Error $FailureMessage
}
finally {
    $Report = [ordered]@{
        schema = "distributed_world_simulator.int0_three_domain_summary.v1"
        checkpoint = "v18.0.0-integration-int0-three-domain-base"
        profile = $Profile
        passed = $Passed
        started_at_utc = $StartedAt.ToString("o")
        finished_at_utc = [DateTime]::UtcNow.ToString("o")
        godot = $GodotExecutable
        suite_count = $SelectedSuites.Count
        failure = $FailureMessage
        steps = $Steps
    }
    $Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReportPath -Encoding utf8
    Write-Host "INT0 report: $ReportPath"
}

if (-not $Passed) {
    exit 1
}

Write-Host "INT0 three-domain integration gate: PASS [$Profile]" -ForegroundColor Green
exit 0
