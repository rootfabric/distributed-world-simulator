param(
    [Parameter(Mandatory = $true)][string]$ServerJson,
    [Parameter(Mandatory = $true)][string]$ClientAJson,
    [Parameter(Mandatory = $true)][string]$ClientBJson,
    [double]$MaxPredictionErrorM = 0.50,
    [double]$MaxVisualOffsetM = 0.500001,
    [double]$MaxServerProcessMs = 75.0,
    [double]$MaxReportBuildMs = 25.0,
    [string]$OutputJson = ""
)

$ErrorActionPreference = "Stop"

$ServerResultPolicy = "TERMINAL_PASS_OR_READY_HEALTHY_V1"

function Read-RequiredJson {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label JSON not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Test-HealthyServerResult {
    param([object]$Server)

    # A dedicated authority is intentionally long-lived. The playable harness can
    # capture server.json while the authority is still in READY and only terminate
    # it after both clients have completed. In that valid case `passed` is false
    # because the server never entered a terminal COMPLETE state. Do not turn that
    # lifecycle detail into a false FIX8 failure. A non-terminal READY report is
    # accepted only when the authority is configured and has no runtime rejection,
    # fixed-tick failure, or explicit error code.
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

function Get-RemoteSummary {
    param([object]$Client)
    $Presenters = $Client.world_report.remote_presenters
    $Count = 0
    $Underruns = 0
    $MovingHolds = 0
    $MovingExtrapolation = 0
    $MaxGap = 0
    $MaxHoldStreak = 0
    if ($null -ne $Presenters) {
        foreach ($Property in $Presenters.PSObject.Properties) {
            $Report = $Property.Value
            $Count += 1
            $Underruns += [int]$Report.fix8_moving_buffer_underruns
            $MovingHolds += [int]$Report.fix8_moving_hold_samples
            $MovingExtrapolation += [int]$Report.fix8_moving_extrapolation_samples
            $MaxGap = [math]::Max($MaxGap, [int]$Report.fix8_max_snapshot_gap_ticks)
            $MaxHoldStreak = [math]::Max($MaxHoldStreak, [int]$Report.fix8_max_moving_hold_streak)
        }
    }
    return [ordered]@{
        presenter_count = $Count
        moving_buffer_underruns = $Underruns
        moving_hold_samples = $MovingHolds
        moving_extrapolation_samples = $MovingExtrapolation
        max_snapshot_gap_ticks = $MaxGap
        max_moving_hold_streak = $MaxHoldStreak
    }
}

function Get-ClientSummary {
    param([object]$Client, [string]$Label)
    $Prediction = $Client.world_report.m7_prediction_report
    $Remote = Get-RemoteSummary -Client $Client
    return [ordered]@{
        label = $Label
        passed = [bool]$Client.passed
        prediction_tick = [int]$Prediction.prediction_tick
        authoritative_tick = [int]$Prediction.last_authoritative_tick
        current_input_sequence = [int]$Prediction.current_input_sequence
        authoritative_input_sequence = [int]$Prediction.last_authoritative_sequence
        reconciliations = [int]$Prediction.reconciliations
        corrections = [int]$Prediction.corrections
        hard_corrections = [int]$Prediction.hard_corrections
        maximum_error_m = [double]$Prediction.maximum_error_m
        visual_offset_m = [double]$Prediction.visual_offset_m
        max_bounded_visual_offset_m = [double]$Prediction.max_bounded_visual_offset_m
        max_raw_visual_offset_m = [double]$Prediction.max_raw_visual_offset_m
        clock_alignment_events = [int]$Prediction.clock_alignment_events
        clock_alignment_ticks = [int]$Prediction.clock_alignment_ticks
        clock_only_alignment_events = [int]$Prediction.clock_only_alignment_events
        sequence_mismatch_alignment_skips = [int]$Prediction.sequence_mismatch_alignment_skips
        large_gap_alignment_skips = [int]$Prediction.large_gap_alignment_skips
        replay_failures = [int]$Prediction.replay_failures
        history_miss_resets = [int]$Prediction.history_miss_resets
        clock_alignment_policy = [string]$Prediction.clock_alignment_policy
        correction_policy = [string]$Prediction.correction_policy
        remote = $Remote
    }
}

$Server = Read-RequiredJson -Path $ServerJson -Label "Server"
$ClientA = Read-RequiredJson -Path $ClientAJson -Label "Client A"
$ClientB = Read-RequiredJson -Path $ClientBJson -Label "Client B"

$A = Get-ClientSummary -Client $ClientA -Label "A"
$B = Get-ClientSummary -Client $ClientB -Label "B"
$Realtime = $Server.realtime_foundation
$ServerHealthy = Test-HealthyServerResult -Server $Server

$Failures = @()
if (-not $ServerHealthy) {
    $Failures += "Server result is neither terminal PASS nor a healthy READY authority"
}
foreach ($Client in @($A, $B)) {
    if (-not $Client.passed) { $Failures += "Client $($Client.label) result is not passed" }
    if ($Client.clock_alignment_policy -ne "SEQUENCE_MATCHED_FUTURE_TICK_PREALIGN_V1") {
        $Failures += "Client $($Client.label) does not report FIX8 clock alignment policy"
    }
    if ($Client.correction_policy -ne "BOUNDED_CONTINUITY_OFFSET_RATE_LIMITED_DECAY_V1") {
        $Failures += "Client $($Client.label) does not report FIX8 correction policy"
    }
    if ($Client.hard_corrections -gt 0) {
        $Failures += "Client $($Client.label) used hard corrections ($($Client.hard_corrections))"
    }
    if ($Client.replay_failures -gt 0) {
        $Failures += "Client $($Client.label) reported replay failures ($($Client.replay_failures))"
    }
    if ($Client.maximum_error_m -gt $MaxPredictionErrorM) {
        $Failures += "Client $($Client.label) prediction error exceeded ${MaxPredictionErrorM} m ($($Client.maximum_error_m))"
    }
    if ($Client.visual_offset_m -gt $MaxVisualOffsetM) {
        $Failures += "Client $($Client.label) final visual offset exceeded ${MaxVisualOffsetM} m ($($Client.visual_offset_m))"
    }
    if ($Client.max_bounded_visual_offset_m -gt $MaxVisualOffsetM) {
        $Failures += "Client $($Client.label) bounded visual offset exceeded ${MaxVisualOffsetM} m ($($Client.max_bounded_visual_offset_m))"
    }
}

$ServerProcessMs = [double]$Realtime.server_process_max_duration_ms
$ReportBuildMs = [double]$Realtime.report_max_snapshot_build_duration_ms
if ($ServerProcessMs -gt $MaxServerProcessMs) {
    $Failures += "Server process peak exceeded ${MaxServerProcessMs} ms ($ServerProcessMs)"
}
if ($ReportBuildMs -gt $MaxReportBuildMs) {
    $Failures += "Server report build peak exceeded ${MaxReportBuildMs} ms ($ReportBuildMs)"
}

$RemoteUnderruns = [int]$A.remote.moving_buffer_underruns + [int]$B.remote.moving_buffer_underruns
$RemoteFollowupRequired = $RemoteUnderruns -gt 0

$Result = [ordered]@{
    schema = "planet_simulator.m7_fix8_result_analysis.v1"
    passed = ($Failures.Count -eq 0)
    server_result_policy = $ServerResultPolicy
    thresholds = [ordered]@{
        max_prediction_error_m = $MaxPredictionErrorM
        max_visual_offset_m = $MaxVisualOffsetM
        max_server_process_ms = $MaxServerProcessMs
        max_report_build_ms = $MaxReportBuildMs
    }
    server = [ordered]@{
        healthy = $ServerHealthy
        terminal_passed = [bool]$Server.passed
        state = [string]$Server.state
        process_max_duration_ms = $ServerProcessMs
        report_max_snapshot_build_duration_ms = $ReportBuildMs
        slow_process_frames = [int]$Realtime.slow_process_frames
        transient_stall_frames = [int]$Realtime.transient_stall_frames
        scheduler_pending_catch_up_ticks = [int]$Realtime.scheduler_pending_catch_up_ticks
    }
    client_a = $A
    client_b = $B
    remote_followup_required = $RemoteFollowupRequired
    remote_followup_reason = $(if ($RemoteFollowupRequired) { "MOVING_REMOTE_BUFFER_UNDERRUN_OBSERVED" } else { "" })
    failures = @($Failures)
}

Write-Host ""
Write-Host "M7 FIX8 result analysis" -ForegroundColor Cyan
Write-Host ("Server: healthy={0}, state={1}, terminal_pass={2}, process max={3:N3} ms, report build max={4:N3} ms" -f `
    $ServerHealthy, [string]$Server.state, [bool]$Server.passed, $ServerProcessMs, $ReportBuildMs)
foreach ($Client in @($A, $B)) {
    Write-Host ("Client {0}: corrections={1}, hard={2}, max error={3:N4} m, visual now/max bounded={4:N4}/{5:N4} m, clock align={6} events/{7} ticks, remote moving underruns={8}" -f `
        $Client.label, $Client.corrections, $Client.hard_corrections, $Client.maximum_error_m, $Client.visual_offset_m, $Client.max_bounded_visual_offset_m, $Client.clock_alignment_events, $Client.clock_alignment_ticks, $Client.remote.moving_buffer_underruns)
}

if ($RemoteFollowupRequired) {
    Write-Host "Remote moving-buffer underrun observed: local FIX8 can still pass, but remote playout tuning remains measurable follow-up work." -ForegroundColor Yellow
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputPath = [System.IO.Path]::GetFullPath($OutputJson)
    $OutputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    }
    $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Result JSON: $OutputPath"
}

if ($Failures.Count -gt 0) {
    Write-Host "FIX8 analysis: FAIL" -ForegroundColor Red
    foreach ($Failure in $Failures) { Write-Host " - $Failure" -ForegroundColor Red }
    exit 1
}

Write-Host "FIX8 analysis: PASS" -ForegroundColor Green
exit 0
