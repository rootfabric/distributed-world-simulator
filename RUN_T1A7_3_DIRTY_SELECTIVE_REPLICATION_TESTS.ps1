param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
$PreviousBreakpointRuntimeDisabled = [Environment]::GetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "Process")
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
try {
    & (Join-Path $ProjectRoot "RUN_T1A7_2_LATE_INTEREST_RECONNECT_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.2 accepted dependency focused regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a7_3_dirty_selective_replication_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.3 dirty selective planner acceptance failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a7_3_selective_replication_process_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.3 selective M3 process acceptance failed: $LASTEXITCODE" }

    Write-Host "T1A.7.3 dirty/selective runtime replication focused gate passed."
}
finally {
    [Environment]::SetEnvironmentVariable(
        "BREAKPOINT_RUNTIME_DISABLED",
        $PreviousBreakpointRuntimeDisabled,
        "Process"
    )
}
