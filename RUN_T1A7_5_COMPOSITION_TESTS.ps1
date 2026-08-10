param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
$PreviousBreakpointRuntimeDisabled = [Environment]::GetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "Process")
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
try {
    & (Join-Path $ProjectRoot "RUN_T1A7_4_SCALE_SOAK_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.4 accepted dependency focused regression failed: $LASTEXITCODE" }

    & $GodotPath --headless --path $ProjectRoot --script res://tests/construction/t1a7_5_composition_acceptance.gd
    if ($LASTEXITCODE -ne 0) { throw "T1A.7.5 recovery/interest/selective composition acceptance failed: $LASTEXITCODE" }

    Write-Host "T1A.7.5 composition focused gate passed."
}
finally {
    [Environment]::SetEnvironmentVariable(
        "BREAKPOINT_RUNTIME_DISABLED",
        $PreviousBreakpointRuntimeDisabled,
        "Process"
    )
}
