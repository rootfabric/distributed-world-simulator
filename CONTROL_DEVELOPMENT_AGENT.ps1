[CmdletBinding()]
param(
    [switch]$Drive,
    [switch]$Resume,
    [switch]$Yield,
    [ValidateSet('ADAPTIVE', 'BOUNDED_DEEP_REASONING', 'LONG_HORIZON_CONTINUOUS')]
    [string]$Profile = 'ADAPTIVE',
    [switch]$ExternalPending,
    [string]$ExternalRef,
    [string]$Execution,
    [string]$Checkpoint
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$selectedModes = @($Drive, $Resume, $Yield) | Where-Object { $_ }
if ($selectedModes.Count -ne 1) {
    Write-Output '{"schema":"distributed_world_simulator.agent_execution_decision.v1","command":"UNKNOWN","ok":false,"error":{"code":"INVALID_INVOCATION","detail":"EXACTLY_ONE_OF_DRIVE_RESUME_YIELD_REQUIRED"}}'
    exit 2
}
if ($ExternalRef -and -not $ExternalPending) {
    Write-Output '{"schema":"distributed_world_simulator.agent_execution_decision.v1","command":"UNKNOWN","ok":false,"error":{"code":"INVALID_INVOCATION","detail":"EXTERNAL_REF_REQUIRES_EXTERNAL_PENDING"}}'
    exit 2
}

$mode = if ($Drive) {
    'drive'
} elseif ($Resume) {
    'resume'
} else {
    'yield'
}

$previousPythonPath = $env:PYTHONPATH
$previousPythonUtf8 = $env:PYTHONUTF8
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $env:PYTHONUTF8 = '1'
    $harnessPythonPath = Join-Path $repoRoot 'scripts'
    $env:PYTHONPATH = if ($previousPythonPath) { "$harnessPythonPath;$previousPythonPath" } else { $harnessPythonPath }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) {
        Write-Output '{"schema":"distributed_world_simulator.agent_execution_decision.v1","command":"UNKNOWN","ok":false,"error":{"code":"DEPENDENCY_INVALID","detail":"PYTHON_3_REQUIRED"}}'
        exit 3
    }

    $arguments = @(
        '-m',
        'harness.agent_execution_policy',
        $mode,
        '--root',
        $repoRoot,
        '--profile',
        $Profile
    )
    if ($Execution) { $arguments += @('--execution', $Execution) }
    if ($Checkpoint) { $arguments += @('--checkpoint', $Checkpoint) }
    if ($ExternalPending) { $arguments += '--external-pending' }
    if ($ExternalRef) { $arguments += @('--external-ref', $ExternalRef) }

    & $pythonCommand.Source @arguments
    exit $LASTEXITCODE
}
finally {
    $env:PYTHONPATH = $previousPythonPath
    $env:PYTHONUTF8 = $previousPythonUtf8
}
