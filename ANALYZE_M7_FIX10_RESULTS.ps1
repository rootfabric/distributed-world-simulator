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
$ExpectedFix3AckFallbackPolicy = "SEPARATE_TELEMETRY_CHANNEL_WHEN_SNAPSHOT_ACK_OMITTED_V1"
$ExpectedFix3RemotePolicy = "EXACT_SNAPSHOT_CONTEXT_PRESENTATION_CONTINUITY_V1"

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
    $Omitted = [int]$Foundation.fix10_ack_omitted_for_mtu
    if ($Omitted -eq 0 -and $null -ne $Detailed) { $Omitted = [int]$Detailed.ack_omitted_for_mtu }
    $FallbackPolicy = [string]$Foundation.fix10_fix3_ack_fallback_policy
    if ([string]::IsNullOrWhiteSpace($FallbackPolicy) -and $null -ne $Detailed) {
        $FallbackPolicy = [string]$Detailed.fix3_ack_fallback_policy
    }
    $StandaloneAttempts = [int]$Foundation.fix10_fix3_standalone_ack_attempts
    if ($StandaloneAttempts -eq 0 -and $null -ne $Detailed) { $StandaloneAttempts = [int]$Detailed.fix3_standalone_ack_attempts }
    $StandaloneSent = [int]$Foundation.fix10_fix3_standalone_ack_sent
    if ($StandaloneSent -eq 0 -and $null -ne $Detailed) { $StandaloneSent = [int]$Detailed.fix3_standalone_ack_sent }
    $StandaloneFailures = [int]$Foundation.fix10_fix3_standalone_ack_failures
    if ($StandaloneFailures -eq 0 -and $null -ne $Detailed) { $StandaloneFailures = [int]$Detailed.fix3_standalone_ack_failures }
    $MaxStandaloneBytes = [int]$Foundation.fix10_fix3_max_standalone_ack_bytes
    if ($MaxStandaloneBytes -eq 0 -and $null -ne $Detailed) { $MaxStandaloneBytes = [int]$Detailed.fix3_max_standalone_ack_bytes }
    return [ordered]@{
        policy = $Policy
        captures = $Captures
        capture_mismatches = $Mismatches
        snapshots_with_ack = $WithAck
        max_input_apply_lag_ticks = $MaxLag
        ack_omitted_for_mtu = $Omitted
        fix3_ack_fallback_policy = $FallbackPolicy
        fix3_standalone_ack_attempts = $StandaloneAttempts
        fix3_standalone_ack_sent = $StandaloneSent
        fix3_standalone_ack_failures = $StandaloneFailures
        fix3_max_standalone_ack_bytes = $MaxStandaloneBytes
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
    $RemoteTransport = $Client.runtime_report.fix10_fix3_remote_presentation_transport
    $Remote = $Client.world_report.fix10_fix3_remote_continuity
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
        ack_fallback_policy = [string]$Transport.ack_fallback_policy
        sidecars_received = [int]$Transport.sidecars_received
        sidecars_registered = [int]$Transport.sidecars_registered
        sidecars_rejected = [int]$Transport.sidecars_rejected
        standalone_ack_received = [int]$Transport.standalone_ack_received
        standalone_ack_registered = [int]$Transport.standalone_ack_registered
        standalone_ack_rejected = [int]$Transport.standalone_ack_rejected
        sidecar_last_error_code = [string]$Transport.last_error_code
        process_max_ms = [double]$Budget.process_max_ms
        slow_process_frames = [int]$Budget.process_slow_frames
        unattributed_max_ms = [double]$Budget.unattributed_max_ms
        unattributed_over_budget_frames = [int]$Budget.unattributed_over_budget_frames
        remote_transport_policy = [string]$RemoteTransport.policy
        same_revision_semantic_conflicts = [int]$RemoteTransport.same_revision_semantic_conflicts
        last_same_revision_conflict = $RemoteTransport.last_same_revision_conflict
        remote_policy = [string]$Remote.policy
        remote_signal_connected = [bool]$Remote.signal_connected
        remote_count = [int]$Remote.remote_count
        remote_apply_failures = [int]$Remote.apply_failures
        remote_same_clock_conflicts = [int]$Remote.same_clock_conflicts
        remote_moving_buffer_underruns = [int]$Remote.moving_buffer_underruns
        remote_moving_hold_samples = [int]$Remote.moving_hold_samples
        remote_max_moving_hold_streak = [int]$Remote.max_moving_hold_streak
        remote_max_snapshot_gap_ticks = [int]$Remote.max_snapshot_gap_ticks
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
if ($ServerAck.fix3_ack_fallback_policy -ne $ExpectedFix3AckFallbackPolicy) {
    [void]$Failures.Add("Server does not expose FIX10 fix3 standalone ACK fallback policy")
}
if ($ServerAck.fix3_standalone_ack_failures -gt 0) {
    [void]$Failures.Add("Server failed to emit $($ServerAck.fix3_standalone_ack_failures) FIX10 fix3 standalone ACK packets")
}
if ($ServerAck.ack_omitted_for_mtu -gt 0) {
    if ($ServerAck.fix3_standalone_ack_attempts -le 0 -or $ServerAck.fix3_standalone_ack_sent -le 0) {
        [void]$Failures.Add("Server omitted snapshot ACKs for MTU but emitted no FIX10 fix3 standalone ACK fallback")
    }
    if ($ServerAck.fix3_standalone_ack_sent -lt $ServerAck.ack_omitted_for_mtu) {
        [void]$Failures.Add("Server standalone ACK coverage is below MTU omission count ($($ServerAck.fix3_standalone_ack_sent)/$($ServerAck.ack_omitted_for_mtu))")
    }
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
    if ($Client.ack_fallback_policy -ne $ExpectedFix3AckFallbackPolicy) {
        [void]$Failures.Add("Client $($Client.label) does not expose FIX10 fix3 standalone ACK fallback policy")
    }
    if ($Client.sidecars_received -le 0 -or $Client.sidecars_registered -le 0) {
        [void]$Failures.Add("Client $($Client.label) did not receive/register FIX10 acknowledgement sidecars")
    }
    if ($Client.sidecars_rejected -gt 0 -or $Client.standalone_ack_rejected -gt 0 -or -not [string]::IsNullOrWhiteSpace($Client.sidecar_last_error_code)) {
        [void]$Failures.Add("Client $($Client.label) rejected FIX10 acknowledgement metadata (sidecars=$($Client.sidecars_rejected), standalone=$($Client.standalone_ack_rejected), '$($Client.sidecar_last_error_code)')")
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
    if ($Client.remote_policy -ne $ExpectedFix3RemotePolicy) {
        [void]$Failures.Add("Client $($Client.label) does not expose FIX10 fix3 remote continuity policy")
    }
    if ($Client.remote_count -gt 0 -and -not $Client.remote_signal_connected) {
        [void]$Failures.Add("Client $($Client.label) has remote players but FIX10 fix3 wire-presentation signal is not connected")
    }
    if ($Client.remote_apply_failures -gt 0 -or $Client.remote_same_clock_conflicts -gt 0) {
        [void]$Failures.Add("Client $($Client.label) remote presentation had apply/same-clock failures ($($Client.remote_apply_failures)/$($Client.remote_same_clock_conflicts))")
    }
    if ($Client.remote_moving_buffer_underruns -gt 0 -or $Client.remote_moving_hold_samples -gt 0) {
        [void]$Failures.Add("Client $($Client.label) remote moving presentation exhausted its interpolation buffer (underruns=$($Client.remote_moving_buffer_underruns), holds=$($Client.remote_moving_hold_samples), max streak=$($Client.remote_max_moving_hold_streak))")
    }
    if ($Client.same_revision_semantic_conflicts -gt 0) {
        [void]$Failures.Add("Client $($Client.label) still observed $($Client.same_revision_semantic_conflicts) canonical same-revision semantic conflicts; inspect last_same_revision_conflict")
    }
}

$Result = [ordered]@{
    schema = "planet_simulator.m7_fix10_fix3_result_analysis.v1"
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
Write-Host "M7 FIX10 fix3 sequence/presentation continuity analysis" -ForegroundColor Cyan
Write-Host ("Server: healthy={0}, state={1}, process max={2:N3} ms, report build max={3:N3} ms, ack captures={4}, snapshot ACKs={5}, MTU omissions={6}, standalone ACK={7}/{8}, fallback failures={9}" -f `
    $ServerHealthy, [string]$Server.state, $ServerProcessMs, $ReportBuildMs, `
    $ServerAck.captures, $ServerAck.snapshots_with_ack, $ServerAck.ack_omitted_for_mtu, `
    $ServerAck.fix3_standalone_ack_sent, $ServerAck.fix3_standalone_ack_attempts, $ServerAck.fix3_standalone_ack_failures)
foreach ($Client in @($A, $B)) {
    Write-Host ("Client {0}: corrections={1} ({2:N3}/1000), hard={3}, max error={4:N4} m, ack reconcile={5}, standalone ACK={6}/{7}, ack misses={8}, remote underruns/holds={9}/{10}, same-revision conflicts={11}" -f `
        $Client.label, $Client.corrections, $Client.corrections_per_1000_prediction_ticks, `
        $Client.hard_corrections, $Client.maximum_error_m, $Client.ack_reconciliations, `
        $Client.standalone_ack_received, $Client.standalone_ack_registered, $Client.ack_history_misses, `
        $Client.remote_moving_buffer_underruns, $Client.remote_moving_hold_samples, $Client.same_revision_semantic_conflicts)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputJson)
    $OutputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    }
    $Result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Result JSON: $OutputPath"
}

if ($Failures.Count -gt 0) {
    Write-Host "FIX10 fix3 analysis: FAIL" -ForegroundColor Red
    foreach ($Failure in $Failures) { Write-Host " - $Failure" -ForegroundColor Red }
    exit 1
}

Write-Host "FIX10 fix3 analysis: PASS" -ForegroundColor Green
exit 0
