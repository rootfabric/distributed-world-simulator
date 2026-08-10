param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
$PreviousBreakpointRuntimeDisabled = [Environment]::GetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "Process")
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
try {
    & $GodotPath --headless --editor --path $ProjectRoot --quit
    if ($LASTEXITCODE -ne 0) { throw "T1A.5 transactional effects editor parse failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/c5b_affordance_runtime_contracts.gd
    if ($LASTEXITCODE -ne 0) { throw "C5B runtime contracts failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a5_interactive_runtime_execution_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.5 runtime dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a5_transactional_runtime_effects_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.5 transactional runtime effects acceptance failed: $LASTEXITCODE" }

    Write-Host "T1A.5 transactional runtime effects focused gate passed."
}
finally {
    [Environment]::SetEnvironmentVariable(
        "BREAKPOINT_RUNTIME_DISABLED",
        $PreviousBreakpointRuntimeDisabled,
        "Process"
    )
}
