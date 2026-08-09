param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
$PreviousBreakpointRuntimeDisabled = [Environment]::GetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "Process")
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
try {
    & $GodotPath --headless --editor --path $ProjectRoot --quit
    if ($LASTEXITCODE -ne 0) { throw "T1A.4 editor parse failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a3_item_graph_materialization_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.3 dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c5_capability_affordance_contracts.gd
    if ($LASTEXITCODE -ne 0) { throw "C5 capability/affordance dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c15_executable_utilities_contracts.gd
    if ($LASTEXITCODE -ne 0) { throw "C15 executable utility dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c2b_authoritative_item_graph_integration.gd
    if ($LASTEXITCODE -ne 0) { throw "C2B authoritative Item Graph dependency regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a4_interactive_fixture_binding_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.4 interactive fixture binding failed: $LASTEXITCODE" }

    Write-Host "T1A.4 interactive fixture binding focused gate passed."
}
finally {
    [Environment]::SetEnvironmentVariable(
        "BREAKPOINT_RUNTIME_DISABLED",
        $PreviousBreakpointRuntimeDisabled,
        "Process"
    )
}
