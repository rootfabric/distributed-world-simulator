param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [switch]$FocusedOnly,
    [switch]$IncludeTwoClientProcess
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = (Resolve-Path $GodotPath).Path

function Invoke-GodotCheck {
    param([string]$Name, [string[]]$Arguments)
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $PreviousErrorActionPreference = $ErrorActionPreference
    $PreviousBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $ErrorActionPreference = "Continue"
        $Output = @(& $Godot @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -eq $PreviousBreakpoint) {
            Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
        }
        else {
            $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpoint
        }
    }
    foreach ($Line in $Output) { Write-Host $Line }
    $Text = ($Output | ForEach-Object { $_.ToString() }) -join "`n"
    foreach ($Pattern in @("SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to load script")) {
        if ($Text.Contains($Pattern)) {
            throw "$Name emitted fatal Godot script diagnostics: $Pattern"
        }
    }
    if ($ExitCode -ne 0) {
        throw "$Name failed with exit code $ExitCode"
    }
    Write-Host "${Name}: PASS" -ForegroundColor Green
}

Write-Host "M7 FIX10 sequence-aware reconciliation validation" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

Invoke-GodotCheck -Name "FIX10 editor import/composition" -Arguments @(
    "--headless", "--editor", "--path", $ProjectRoot, "--quit"
)

Invoke-GodotCheck -Name "FIX10 fix6 semantic baseline + replay correctness" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix6.gd"
)

Invoke-GodotCheck -Name "FIX10 fix6 one-sequence-per-fixed-tick input latch" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix6_semantic_input_latch.gd"
)

Invoke-GodotCheck -Name "FIX10 fix6 semantic cadence + local presentation ownership" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix6_cadence_presentation.gd"
)

Invoke-GodotCheck -Name "FIX10 fix5 composite ACK semantic identity" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix5.gd"
)

Invoke-GodotCheck -Name "FIX10 fix4 ACK timeline + MTU headroom" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix4.gd"
)

Invoke-GodotCheck -Name "FIX10 fix3 remote continuity + ACK fallback" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix3.gd"
)

Invoke-GodotCheck -Name "FIX10 fix2 MTU preflight contracts" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix2.gd"
)

Invoke-GodotCheck -Name "FIX10 focused sequence-aware reconciliation" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10.gd"
)

Invoke-GodotCheck -Name "FIX9 frame-budget regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_client_frame_budget_fix9.gd"
)

Invoke-GodotCheck -Name "FIX8 prediction-clock regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_prediction_clock_fix8.gd"
)

Invoke-GodotCheck -Name "NX4 prediction/reconciliation regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_nx4_client_prediction_reconciliation.gd"
)

if (-not $FocusedOnly) {
    Write-Host ""
    Write-Host "[FIX9 + FIX8 + FIX7 + FIX6 + FIX5 + accepted network/inventory baseline]" -ForegroundColor Cyan
    $Fix9Runner = Join-Path $ProjectRoot "VALIDATE_M7_CLIENT_FRAME_BUDGET_FIX9.ps1"
    if ($IncludeTwoClientProcess) {
        & $Fix9Runner -GodotPath $Godot -IncludeTwoClientProcess
    }
    else {
        & $Fix9Runner -GodotPath $Godot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "M7 FIX9/full accepted baseline failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "M7 FIX10 sequence-aware reconciliation validation passed." -ForegroundColor Green
if ($FocusedOnly) {
    Write-Host "FocusedOnly validates FIX10 fix6 semantic scheduling, monotonic latching, 30 Hz continuous input cadence, single-writer local presentation, transition-aware ACK baselines and ACK dispatch, then fix5/fix4/fix3/fix2 plus FIX10/FIX9/FIX8/NX4 regressions." -ForegroundColor Yellow
}
elseif (-not $IncludeTwoClientProcess) {
    Write-Host "Run with -IncludeTwoClientProcess before manual acceptance." -ForegroundColor Yellow
}
Write-Host "Final FIX10 acceptance still requires a >=5 minute two-client LOCAL prediction-only movement/item stress run and ANALYZE_M7_FIX10_FIX6_RESULTS.ps1 PASS." -ForegroundColor Yellow
Write-Host "FIX10 fix6 target: 30 Hz continuous semantic input with immediate responsiveness edges; one monotonic semantic input sequence per client fixed tick; single-writer local render presentation; semantic server scheduling preserves client_tick spacing; phase-only ACK offsets do not enter direct baseline correction; PREDICTION_ACK never reports UNKNOWN_M3_SERVER_MESSAGE; snapshot ACK registration survives canonical same-revision conflicts." -ForegroundColor Yellow
Write-Host "FIX10 fix5 target remains ack_mismatches=0 and sidecars_rejected=0." -ForegroundColor Yellow
Write-Host "FIX10 fix4 MTU target remains movement_snapshots_dropped_for_mtu=0 while max_unreliable_sent_bytes remains <=1350." -ForegroundColor Yellow
Write-Host "Remote presentation fix3 remains unchanged; continue watching moving HOLD/underrun telemetry during the long run." -ForegroundColor Yellow
