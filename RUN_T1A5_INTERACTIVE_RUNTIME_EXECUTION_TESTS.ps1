param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
$PreviousBreakpointRuntimeDisabled = [Environment]::GetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "Process")
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
try {
    & $GodotPath --headless --editor --path $ProjectRoot --quit
    if ($LASTEXITCODE -ne 0) { throw "T1A.5 editor parse failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a4_interactive_fixture_binding_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.4 dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/c5b_affordance_runtime_contracts.gd
    if ($LASTEXITCODE -ne 0) { throw "C5B affordance runtime contracts failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c15_executable_utilities_contracts.gd
    if ($LASTEXITCODE -ne 0) { throw "C15 executable utility dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a5_interactive_runtime_execution_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.5 interactive runtime execution failed: $LASTEXITCODE" }

    Write-Host "T1A.5 interactive runtime execution focused gate passed."
}
finally {
    [Environment]::SetEnvironmentVariable(
        "BREAKPOINT_RUNTIME_DISABLED",
        $PreviousBreakpointRuntimeDisabled,
        "Process"
    )
}
