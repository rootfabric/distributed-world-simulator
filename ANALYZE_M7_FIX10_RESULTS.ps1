param(
    [Parameter(Mandatory = $true)][string]$ServerJson,
    [Parameter(Mandatory = $true)][string]$ClientAJson,
    [Parameter(Mandatory = $true)][string]$ClientBJson,
    [double]$MaxCorrectionsPer1000PredictionTicks = 5.0,
    [double]$MaxPresentReplayErrorM = 0.35,
    [double]$MaxPredictionErrorM = 0.50,
    [int]$MaxAckHistoryMisses = 5,
    [int]$MaxClientSlowProcessFrames = 2,
    [double]$MaxServerProcessMs = 75.0,
    [double]$MaxReportBuildMs = 25.0,
    [string]$OutputJson = ""
)

$ErrorActionPreference = "Stop"
$ServerResultPolicy = "TERMINAL_PASS_OR_READY_HEALTHY_V1"
$ExpectedAckPolicy = "SERVER_ECHOED_POST_INPUT_BASELINE_V1"
$ExpectedReconciliationPolicy = "ACK_BASELINE_REPLAY_LOCAL_TIMELINE_V1"

function Read-RequiredJson {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label JSON not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Test-HealthyServerResult {
    param([object]$Server)
    if ([bool]$Server.passed) { return $true }
    if ([string]$Server.state -ne "READY") { return $false }
    if (-not [bool]$Server.configured) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$Server.last_error_code)) { return $false }
    if ([int]$Server.rejections -gt 0) { return $false }
    if ($null -ne $Server.fixed_tick_simulation -and [int]$Server.fixed_tick_simulation.failures -gt 0) {
        return $false
    }
    return $true
}

function Get-ServerAckSummary {
    param([object]$Server)
    $Foundation = $Server.realtime_foundation
    $Detailed = $Server.fix10_prediction_ack
    $Policy = [string]$Foundation.fix10_prediction_ack_policy
    if ([string]::IsNullOrWhiteSpace($Policy) -and $null -ne $Detailed) {
        $Policy = [string]$Detailed.policy
    }
    $Captures = [int]$Foundation.fix10_prediction_ack_captures
    if ($Captures -eq 0 -and $null -ne $Detailed) { $Captures = [int]$Detailed.captures }
    $Mismatches = [int]$Foundation.fix10_prediction_ack_capture_mismatches
    if ($Mismatches -eq 0 -and $null -ne $Detailed) { $Mismatches = [int]$Detailed.capture_mismatches }
    $WithAck = [int]$Foundation.fix10_snapshots_with_prediction_ack
    if ($WithAck -eq 0 -and $null -ne $Detailed) { $WithAck = [int]$Detailed.snapshots_with_ack }
    $MaxLag = [int]$Foundation.fix10_max_input_apply_lag_ticks
    if ($MaxLag -eq 0 -and $null -ne $Detailed) { $MaxLag = [int]$Detailed.max_input_apply_lag_ticks }
    return [ordered]@{
        policy = $Policy
        captures = $Captures
        capture_mismatches = $Mismatches
        snapshots_with_ack = $WithAck
        max_input_apply_lag_ticks = $MaxLag
    }
}

function Get-ClientSummary {
    param([object]$Client, [string]$Label)
    $Prediction = $Client.world_report.m7_prediction_report
    if ($null -eq $Prediction -and $null -ne $Client.runtime_report.client_prediction) {
        $Prediction = $Client.runtime_report.client_prediction.runtime
    }
    $Transport = $Client.runtime_report.fix10_prediction_ack_transport
    $Budget = $Client.runtime_report.client_frame_budget
    return [ordered]@{
        label = $Label
        passed = [bool]$Client.passed
        state = [string]$Client.state
        hard_corrections = [int]$Prediction.hard_corrections
        corrections = [int]$Prediction.corrections
        ticks_predicted = [int]$Prediction.ticks_predicted
        corrections_per_1000_prediction_ticks = [double]$Prediction.fix10_corrections_per_1000_prediction_ticks
        maximum_error_m = [double]$Prediction.maximum_error_m
        visual_offset_m = [double]$Prediction.visual_offset_m
        ack_policy = [string]$Prediction.fix10_prediction_ack_policy
        reconciliation_policy = [string]$Prediction.fix10_reconciliation_policy
        ack_reconciliations = [int]$Prediction.fix10_ack_reconciliations
        ack_replays = [int]$Prediction.fix10_ack_replays
        ack_replayed_ticks = [int]$Prediction.fix10_ack_replayed_ticks
        ack_history_misses = [int]$Prediction.fix10_ack_history_misses
        ack_mismatches = [int]$Prediction.fix10_ack_mismatches
        ack_registration_rejections = [int]$Prediction.fix10_ack_registration_rejections
        max_ack_baseline_error_m = [double]$Prediction.fix10_max_ack_baseline_error_m
        max_present_replay_error_m = [double]$Prediction.fix10_max_present_replay_error_m
        last_reconciliation_mode = [string]$Prediction.fix10_last_reconciliation_mode
        sidecar_policy = [string]$Transport.policy
        sidecars_received = [int]$Transport.sidecars_received
        sidecars_registered = [int]$Transport.sidecars_registered
        sidecars_rejected = [int]$Transport.sidecars_rejected
        sidecar_last_error_code = [string]$Transport.last_error_code
        process_max_ms = [double]$Budget.process_max_ms
        slow_process_frames = [int]$Budget.process_slow_frames
        unattributed_max_ms = [double]$Budget.unattributed_max_ms
        unattributed_over_budget_frames = [int]$Budget.unattributed_over_budget_frames
    }
}

$Server = Read-RequiredJson -Path $ServerJson -Label "Server"
$ClientA = Read-RequiredJson -Path $ClientAJson -Label "Client A"
$ClientB = Read-RequiredJson -Path $ClientBJson -Label "Client B"
$ServerHealthy = Test-HealthyServerResult -Server $Server
$ServerAck = Get-ServerAckSummary -Server $Server
$A = Get-ClientSummary -Client $ClientA -Label "A"
$B = Get-ClientSummary -Client $ClientB -Label "B"
$Realtime = $Server.realtime_foundation
$ServerProcessMs = [double]$Realtime.server_process_max_duration_ms
$ReportBuildMs = [double]$Realtime.report_max_snapshot_build_duration_ms
$Failures = [System.Collections.ArrayList]::new()

if (-not $ServerHealthy) {
    [void]$Failures.Add("Server result is neither terminal PASS nor a healthy READY authority")
}
if ($ServerProcessMs -gt $MaxServerProcessMs) {
    [void]$Failures.Add("Server process peak exceeded ${MaxServerProcessMs} ms ($ServerProcessMs)")
}
if ($ReportBuildMs -gt $MaxReportBuildMs) {
    [void]$Failures.Add("Server report build peak exceeded ${MaxReportBuildMs} ms ($ReportBuildMs)")
}
if ($ServerAck.policy -ne $ExpectedAckPolicy) {
    [void]$Failures.Add("Server does not expose FIX10 prediction ack policy")
}
if ($ServerAck.captures -le 0) {
    [void]$Failures.Add("Server captured no post-input prediction acknowledgement baselines")
}
if ($ServerAck.snapshots_with_ack -le 0) {
    [void]$Failures.Add("Server published no snapshots with FIX10 acknowledgement sidecars")
}
if ($ServerAck.capture_mismatches -gt 0) {
    [void]$Failures.Add("Server had FIX10 acknowledgement capture mismatches ($($ServerAck.capture_mismatches))")
}

foreach ($Client in @($A, $B)) {
    if (-not $Client.passed) {
        [void]$Failures.Add("Client $($Client.label) result is not passed")
    }
    if ($Client.hard_corrections -gt 0) {
        [void]$Failures.Add("Client $($Client.label) used hard corrections ($($Client.hard_corrections))")
    }
    if ($Client.maximum_error_m -gt $MaxPredictionErrorM) {
        [void]$Failures.Add("Client $($Client.label) prediction error exceeded ${MaxPredictionErrorM} m ($($Client.maximum_error_m))")
    }
    if ($Client.ack_policy -ne $ExpectedAckPolicy) {
        [void]$Failures.Add("Client $($Client.label) does not expose FIX10 acknowledgement policy")
    }
    if ($Client.reconciliation_policy -ne $ExpectedReconciliationPolicy) {
        [void]$Failures.Add("Client $($Client.label) does not expose FIX10 reconciliation policy")
    }
    if ($Client.sidecar_policy -ne $ExpectedAckPolicy) {
        [void]$Failures.Add("Client $($Client.label) transport does not expose FIX10 sidecar policy")
    }
    if ($Client.sidecars_received -le 0 -or $Client.sidecars_registered -le 0) {
        [void]$Failures.Add("Client $($Client.label) did not receive/register FIX10 acknowledgement sidecars")
    }
    if ($Client.sidecars_rejected -gt 0 -or -not [string]::IsNullOrWhiteSpace($Client.sidecar_last_error_code)) {
        [void]$Failures.Add("Client $($Client.label) rejected FIX10 acknowledgement sidecars ($($Client.sidecars_rejected), '$($Client.sidecar_last_error_code)')")
    }
    if ($Client.ack_reconciliations -le 0) {
        [void]$Failures.Add("Client $($Client.label) never used sequence-aware acknowledgement reconciliation")
    }
    if ($Client.ack_mismatches -gt 0 -or $Client.ack_registration_rejections -gt 0) {
        [void]$Failures.Add("Client $($Client.label) had FIX10 ack mismatches/rejections ($($Client.ack_mismatches)/$($Client.ack_registration_rejections))")
    }
    if ($Client.ack_history_misses -gt $MaxAckHistoryMisses) {
        [void]$Failures.Add("Client $($Client.label) FIX10 ack history misses exceeded $MaxAckHistoryMisses ($($Client.ack_history_misses))")
    }
    if ($Client.max_present_replay_error_m -gt $MaxPresentReplayErrorM) {
        [void]$Failures.Add("Client $($Client.label) present replay error exceeded ${MaxPresentReplayErrorM} m ($($Client.max_present_replay_error_m))")
    }
    if ($Client.corrections_per_1000_prediction_ticks -gt $MaxCorrectionsPer1000PredictionTicks) {
        [void]$Failures.Add("Client $($Client.label) correction density exceeded $MaxCorrectionsPer1000PredictionTicks/1000 ticks ($($Client.corrections_per_1000_prediction_ticks))")
    }
    if ($Client.slow_process_frames -gt $MaxClientSlowProcessFrames) {
        [void]$Failures.Add("Client $($Client.label) had $($Client.slow_process_frames) >=50ms network-process frames (limit $MaxClientSlowProcessFrames)")
    }
}

$Result = [ordered]@{
    schema = "planet_simulator.m7_fix10_result_analysis.v1"
    passed = ($Failures.Count -eq 0)
    server_result_policy = $ServerResultPolicy
    thresholds = [ordered]@{
        max_corrections_per_1000_prediction_ticks = $MaxCorrectionsPer1000PredictionTicks
        max_present_replay_error_m = $MaxPresentReplayErrorM
        max_prediction_error_m = $MaxPredictionErrorM
        max_ack_history_misses = $MaxAckHistoryMisses
        max_client_slow_process_frames = $MaxClientSlowProcessFrames
        max_server_process_ms = $MaxServerProcessMs
        max_report_build_ms = $MaxReportBuildMs
    }
    server = [ordered]@{
        healthy = $ServerHealthy
        terminal_passed = [bool]$Server.passed
        state = [string]$Server.state
        process_max_duration_ms = $ServerProcessMs
        report_max_snapshot_build_duration_ms = $ReportBuildMs
        prediction_ack = $ServerAck
    }
    client_a = $A
    client_b = $B
    failures = @($Failures)
}

Write-Host ""
Write-Host "M7 FIX10 sequence-aware reconciliation analysis" -ForegroundColor Cyan
Write-Host ("Server: healthy={0}, state={1}, process max={2:N3} ms, report build max={3:N3} ms, ack captures={4}, ack snapshots={5}, capture mismatches={6}, max input apply lag={7} ticks" -f `
    $ServerHealthy, [string]$Server.state, $ServerProcessMs, $ReportBuildMs, `
    $ServerAck.captures, $ServerAck.snapshots_with_ack, $ServerAck.capture_mismatches, $ServerAck.max_input_apply_lag_ticks)
foreach ($Client in @($A, $B)) {
    Write-Host ("Client {0}: corrections={1} ({2:N3}/1000 predicted ticks), hard={3}, max error={4:N4} m, ack reconciles/replays={5}/{6}, ack replay ticks={7}, ack misses={8}, present replay max={9:N4} m, sidecars={10}/{11} registered" -f `
        $Client.label, $Client.corrections, $Client.corrections_per_1000_prediction_ticks, `
        $Client.hard_corrections, $Client.maximum_error_m, $Client.ack_reconciliations, `
        $Client.ack_replays, $Client.ack_replayed_ticks, $Client.ack_history_misses, `
        $Client.max_present_replay_error_m, $Client.sidecars_received, $Client.sidecars_registered)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputPath = [System.IO.Path]::GetFullPath($OutputJson)
    $OutputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    }
    $Result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Result JSON: $OutputPath"
}

if ($Failures.Count -gt 0) {
    Write-Host "FIX10 analysis: FAIL" -ForegroundColor Red
    foreach ($Failure in $Failures) { Write-Host " - $Failure" -ForegroundColor Red }
    exit 1
}

Write-Host "FIX10 analysis: PASS" -ForegroundColor Green
exit 0
