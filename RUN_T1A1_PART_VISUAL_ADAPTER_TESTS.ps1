param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
$PreviousBreakpointRuntimeDisabled = [Environment]::GetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "Process")
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
try {
    & $GodotPath --headless --editor --path $ProjectRoot --quit
    if ($LASTEXITCODE -ne 0) { throw "T1A.1 editor parse failed: $LASTEXITCODE" }
    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_t1a0_complex_construct_demo_baseline.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.0 dependency regression failed: $LASTEXITCODE" }
    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_t1a1_part_visual_adapter.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.1 part visual adapter failed: $LASTEXITCODE" }
    Write-Host "T1A.1 part visual adapter passed."
}
finally {
    [Environment]::SetEnvironmentVariable(
        "BREAKPOINT_RUNTIME_DISABLED",
        $PreviousBreakpointRuntimeDisabled,
        "Process"
    )
}
