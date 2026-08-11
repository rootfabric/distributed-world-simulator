[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Plan,
    [switch]$Resume,
    [switch]$Execute,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$UnexpectedArguments
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$executionPath = 'config/control/harness/executions/E2026-08-11-H0-0-R2'
$selectedModes = @($Status, $Plan, $Resume) | Where-Object { $_ }
if ($Execute -or $UnexpectedArguments.Count -gt 0 -or $selectedModes.Count -ne 1) {
    Write-Output '{"schema":"distributed_world_simulator.control_development_output.v1","command":"UNKNOWN","ok":false,"error":{"code":"INVALID_INVOCATION","detail":"EXACTLY_ONE_OF_STATUS_PLAN_RESUME_REQUIRED; EXECUTE_IS_FORBIDDEN"},"exit_codes":{"INVALID_INVOCATION":2,"CONTRACT_OR_DEPENDENCY_INVALID":3,"GIT_STATE_INVALID":4,"EXECUTION_STATE_INVALID":5,"INTERNAL_ERROR":6}}'
    exit 2
}
$mode = if ($Status) { 'status' } elseif ($Plan) { 'plan' } else { 'resume' }
$previousPythonPath = $env:PYTHONPATH
$previousPythonUtf8 = $env:PYTHONUTF8
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $env:PYTHONUTF8 = '1'
    Write-Host "[CONTROL][CONTRACT_LOAD] loading canonical contracts"
    Write-Host "[CONTROL][STATE_BUILD] reducing append-only execution ledger"
    Write-Host "[CONTROL][EPOCH_CHECK] validating epoch against canonical main"
    if ($Plan) { Write-Host "[CONTROL][PLAN] applying H0.0 pilot override" }
    if ($Resume) { Write-Host "[CONTROL][RESUME] reconstructing Git-only recovery state" }
    $harnessPythonPath = Join-Path $repoRoot 'scripts'
    $env:PYTHONPATH = if ($previousPythonPath) { "$harnessPythonPath;$previousPythonPath" } else { $harnessPythonPath }
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) {
        $missingPythonCommand = $mode.ToUpperInvariant()
        Write-Output ("{`"schema`":`"distributed_world_simulator.control_development_output.v1`",`"command`":`"$missingPythonCommand`",`"ok`":false,`"error`":{`"code`":`"CONTRACT_OR_DEPENDENCY_INVALID`",`"detail`":`"PYTHON_3_REQUIRED`"},`"exit_codes`":{`"INVALID_INVOCATION`":2,`"CONTRACT_OR_DEPENDENCY_INVALID`":3,`"GIT_STATE_INVALID`":4,`"EXECUTION_STATE_INVALID`":5,`"INTERNAL_ERROR`":6}}")
        exit 3
    }
    & $pythonCommand.Source -m harness.cli $mode --root $repoRoot --execution $executionPath
    $pythonExitCode = $LASTEXITCODE
    exit $pythonExitCode
}
finally {
    $env:PYTHONPATH = $previousPythonPath
    $env:PYTHONUTF8 = $previousPythonUtf8
}
