[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Plan,
    [switch]$Resume,
    [switch]$Drive,
    [switch]$Close,
    [switch]$CloseRole,
    [switch]$CloseMission,
    [switch]$Overview,
    [switch]$CheckConsistency,
    [switch]$Candidate,
    [string]$Execution,
    [string]$Checkpoint,
    [switch]$Execute,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$UnexpectedArguments
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$selectedModes = @($Status, $Plan, $Resume, $Drive, $Close, $CloseRole, $CloseMission, $Overview, $CheckConsistency) | Where-Object { $_ }
$exitCodes = '"INVALID_INVOCATION":2,"CONTRACT_OR_DEPENDENCY_INVALID":3,"GIT_STATE_INVALID":4,"EXECUTION_STATE_INVALID":5,"INTERNAL_ERROR":6,"ROLE_EXIT_FORBIDDEN":7,"MISSION_EXIT_FORBIDDEN":8'
if ($Execute -or $UnexpectedArguments.Count -gt 0 -or $selectedModes.Count -ne 1) {
    Write-Output ("{`"schema`":`"distributed_world_simulator.control_development_output.v1`",`"command`":`"UNKNOWN`",`"ok`":false,`"error`":{`"code`":`"INVALID_INVOCATION`",`"detail`":`"EXACTLY_ONE_CONTROL_MODE_REQUIRED_INCLUDING_OVERVIEW_OR_CHECKCONSISTENCY; EXECUTE_IS_FORBIDDEN`"},`"exit_codes`":{$exitCodes}}")
    exit 2
}

$mode = if ($Overview) {
    'overview'
} elseif ($CheckConsistency) {
    'check-consistency'
} elseif ($Status) {
    'status'
} elseif ($Plan) {
    'plan'
} elseif ($Resume) {
    'resume'
} elseif ($Drive) {
    'drive'
} elseif ($CloseRole) {
    'close-role'
} else {
    # -Close is intentionally a mission close gate: the user-visible session is the checkpoint mission.
    'close-mission'
}

$previousPythonPath = $env:PYTHONPATH
$previousPythonUtf8 = $env:PYTHONUTF8
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $env:PYTHONUTF8 = '1'
    Write-Host "[CONTROL][CONTRACT_LOAD] loading control contracts; overview defaults to canonical main"
    if ($Overview -or $CheckConsistency) {
        Write-Host "[CONTROL][PROJECT_OVERVIEW] reading goals, lanes and pinned evidence without selecting an execution"
    } else {
    Write-Host "[CONTROL][EXECUTION_SELECT] resolving current checkpoint execution from machine policy"
    Write-Host "[CONTROL][STATE_BUILD] reducing append-only execution ledger"
    Write-Host "[CONTROL][MISSION] binding the user session to one checkpoint mission"
    }
    if ($Plan) { Write-Host "[CONTROL][PLAN] deriving the next bounded checkpoint action" }
    if ($Resume) { Write-Host "[CONTROL][RESUME] reconstructing Git-only checkpoint-session state" }
    if ($Drive) { Write-Host "[CONTROL][DRIVE] continuing across routine role boundaries until a mission terminal" }
    if ($CloseRole) { Write-Host "[CONTROL][CLOSE_ROLE] checking whether the current isolated role may end" }
    if ($Close -or $CloseMission) { Write-Host "[CONTROL][CLOSE_MISSION] authorizing user-session exit only at checkpoint acceptance, human decision, or proven hard block" }

    $harnessPythonPath = Join-Path $repoRoot 'scripts'
    $pathSeparator = [System.IO.Path]::PathSeparator
    $env:PYTHONPATH = if ($previousPythonPath) { "$harnessPythonPath$pathSeparator$previousPythonPath" } else { $harnessPythonPath }
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) {
        $missingPythonCommand = $mode.Replace('-', '_').ToUpperInvariant()
        Write-Output ("{`"schema`":`"distributed_world_simulator.control_development_output.v1`",`"command`":`"$missingPythonCommand`",`"ok`":false,`"error`":{`"code`":`"CONTRACT_OR_DEPENDENCY_INVALID`",`"detail`":`"PYTHON_3_REQUIRED`"},`"exit_codes`":{$exitCodes}}")
        exit 3
    }

    $arguments = @('-m', 'harness.cli', $mode, '--root', $repoRoot)
    if ($Execution) { $arguments += @('--execution', $Execution) }
    if ($Checkpoint) { $arguments += @('--checkpoint', $Checkpoint) }
    if ($Candidate) { $arguments += '--candidate' }
    & $pythonCommand.Source @arguments
    exit $LASTEXITCODE
}
finally {
    $env:PYTHONPATH = $previousPythonPath
    $env:PYTHONUTF8 = $previousPythonUtf8
}
