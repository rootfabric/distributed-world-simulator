param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
$PreviousBreakpointRuntimeDisabled = [Environment]::GetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "Process")
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
try {
    & $GodotPath --headless --editor --path $ProjectRoot --quit
    if ($LASTEXITCODE -ne 0) { throw "T1A.3 editor parse failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a2_d0_authoritative_outpost_builder_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.2 dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c2b_authoritative_item_graph_integration.gd
    if ($LASTEXITCODE -ne 0) { throw "C2B authoritative Item Graph integration regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/simulation/test_m0_aggregate_transaction_integration.gd
    if ($LASTEXITCODE -ne 0) { throw "M0 transaction foundation regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a3_item_graph_materialization_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.3 Item Graph materialization failed: $LASTEXITCODE" }

    Write-Host "T1A.3 Item Graph materialization focused gate passed."
}
finally {
    [Environment]::SetEnvironmentVariable(
        "BREAKPOINT_RUNTIME_DISABLED",
        $PreviousBreakpointRuntimeDisabled,
        "Process"
    )
}
