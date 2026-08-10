param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
$PreviousBreakpointRuntimeDisabled = [Environment]::GetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "Process")
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
try {
    & $GodotPath --headless --editor --path $ProjectRoot --quit
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.2 editor parse failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a4_interactive_fixture_binding_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.4 dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/c5b_affordance_runtime_contracts.gd
    if ($LASTEXITCODE -ne 0) { throw "C5B dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a5_interactive_runtime_execution_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.5 dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a5_transactional_runtime_effects_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.5 transactional dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a7_runtime_recovery_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.1 recovery regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/network/test_nx0_observability_baseline.gd
    if ($LASTEXITCODE -ne 0) { throw "NX0 dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd
    if ($LASTEXITCODE -ne 0) { throw "M3 dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/c5c_runtime_replication_contracts.gd
    if ($LASTEXITCODE -ne 0) { throw "C5C dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a6_runtime_presentation_multiplayer_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.6 default snapshot semantics regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a7_2_runtime_interest_binding_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.2 interest binding acceptance failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a7_2_late_interest_reconnect_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.2 late-interest/reconnect acceptance failed: $LASTEXITCODE" }

    Write-Host "T1A.7.2 late-interest baseline + reconnect focused gate passed."
}
finally {
    [Environment]::SetEnvironmentVariable(
        "BREAKPOINT_RUNTIME_DISABLED",
        $PreviousBreakpointRuntimeDisabled,
        "Process"
    )
}
