param(
    [Parameter(Mandatory = $true)][string]$ServerLog,
    [Parameter(Mandatory = $true)][string]$ClientALog,
    [Parameter(Mandatory = $true)][string]$ClientBLog,
    [int]$MaxAcceptableLiveLeadTicks = 12,
    [int]$MaxAcceptablePendingInputs = 20,
    [double]$MaxAcceptableServerProcessMs = 75.0,
    [double]$MaxAcceptableReportBuildMs = 25.0,
    [double]$MaxAcceptablePeerTelemetryMs = 20.0,
    [double]$MaxAcceptablePredictionErrorM = 0.75,
    [int]$MaxAcceptableTransientStallFrames = 10,
    [int]$MaxAcceptableHistoryMissResets = 12,
    [string]$OutputJson = ""
)

$ErrorActionPreference = "Stop"

function Resolve-RequiredPath {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label log not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Read-M7Events {
    param([string]$Path, [string]$Prefix)
    $Events = @()
    foreach ($Line in Get-Content -LiteralPath $Path) {
        $Text = $Line.ToString()
        $Index = $Text.IndexOf($Prefix, [System.StringComparison]::Ordinal)
        if ($Index -lt 0) { continue }
        $Json = $Text.Substring($Index + $Prefix.Length).Trim()
        if ([string]::IsNullOrWhiteSpace($Json)) { continue }
        try {
            $Value = $Json | ConvertFrom-Json
            if ($null -ne $Value) { $Events += $Value }
        }
        catch {
            # Console output can end with a truncated JSON line after Ctrl+C.
        }
    }
    return @($Events)
}

function Get-MaxNumber {
    param([object[]]$Values, [double]$Default = 0.0)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $Default }
    return [double](($Values | Measure-Object -Maximum).Maximum)
}

function Get-LastValue {
    param([object[]]$Events, [string]$Field, [double]$Default = 0.0)
    if ($null -eq $Events -or $Events.Count -eq 0) { return $Default }
    $Value = $Events[-1].details.$Field
    if ($null -eq $Value) { return $Default }
    return [double]$Value
}

function Get-ClientSummary {
    param([string]$Path, [string]$Label)

    $Events = Read-M7Events -Path $Path -Prefix "[m7_client] "
    $Prediction = @($Events | Where-Object { $_.event -eq "PREDICTION_HEALTH" })
    $Health = @($Events | Where-Object { $_.event -eq "CLIENT_HEALTH" })

    # FIX6 treated every trailing prediction sample as live. During manual Ctrl+C
    # shutdown a graphical client can keep predicting for a few seconds after the
    # authoritative feed has stopped. That produced values such as 247 lead ticks
    # even though authoritative_tick, messages_received and snapshot_updates had
    # all frozen. Detect a trailing health suffix with no receive/snapshot progress
    # and exclude prediction samples after the first health sample of that suffix.
    $TailStartTimeMs = $null
    $StationaryHealthSamples = 0
    if ($Health.Count -ge 2) {
        $FinalMessages = [int]$Health[-1].details.messages_received
        $FinalSnapshots = [int]$Health[-1].details.snapshot_updates
        $SuffixStart = $Health.Count - 1
        for ($Index = $Health.Count - 2; $Index -ge 0; $Index--) {
            if (
                [int]$Health[$Index].details.messages_received -eq $FinalMessages -and
                [int]$Health[$Index].details.snapshot_updates -eq $FinalSnapshots
            ) {
                $SuffixStart = $Index
            }
            else {
                break
            }
        }
        $StationaryHealthSamples = $Health.Count - $SuffixStart
        if ($StationaryHealthSamples -ge 2) {
            $TailStartTimeMs = [int64]$Health[$SuffixStart].time_msec
        }
    }

    $LivePrediction = @($Prediction)
    $TailPrediction = @()
    if ($null -ne $TailStartTimeMs) {
        $LivePrediction = @($Prediction | Where-Object { [int64]$_.time_msec -le $TailStartTimeMs })
        $TailPrediction = @($Prediction | Where-Object { [int64]$_.time_msec -gt $TailStartTimeMs })
        if ($LivePrediction.Count -eq 0) {
            $LivePrediction = @($Prediction)
            $TailPrediction = @()
            $TailStartTimeMs = $null
            $StationaryHealthSamples = 0
        }
    }

    $RawLeadValues = @($Prediction | ForEach-Object { [double]$_.details.lead_ticks })
    $LiveLeadValues = @($LivePrediction | ForEach-Object { [double]$_.details.lead_ticks })
    $TailLeadValues = @($TailPrediction | ForEach-Object { [double]$_.details.lead_ticks })
    $HardValues = @($LivePrediction | ForEach-Object { [double]$_.details.hard_corrections })
    $ErrorValues = @($LivePrediction | ForEach-Object { [double]$_.details.maximum_error_m })
    $HistoryMissValues = @($LivePrediction | ForEach-Object { [double]$_.details.history_miss_resets })
    $HighLiveLeadSamples = @($LivePrediction | Where-Object { [int]$_.details.lead_ticks -gt $MaxAcceptableLiveLeadTicks }).Count
    $InputQueueFull = @(Select-String -LiteralPath $Path -SimpleMatch "INPUT_QUEUE_FULL" -ErrorAction SilentlyContinue).Count
    $SameRevisionMutation = @(Select-String -LiteralPath $Path -SimpleMatch "MULTIPLAYER_SAME_REVISION_MUTATION" -ErrorAction SilentlyContinue).Count
    $CameraInterpolationWarnings = @(Select-String -LiteralPath $Path -SimpleMatch "Interpolated Camera3D triggered from outside physics process" -ErrorAction SilentlyContinue).Count

    return [ordered]@{
        label = $Label
        prediction_health_samples = $Prediction.Count
        live_prediction_health_samples = $LivePrediction.Count
        ignored_tail_prediction_samples = $TailPrediction.Count
        trailing_stationary_health_samples = $StationaryHealthSamples
        tail_start_time_msec = $(if ($null -eq $TailStartTimeMs) { 0 } else { [int64]$TailStartTimeMs })
        max_raw_lead_ticks = [int](Get-MaxNumber -Values $RawLeadValues)
        max_live_lead_ticks = [int](Get-MaxNumber -Values $LiveLeadValues)
        tail_max_lead_ticks = [int](Get-MaxNumber -Values $TailLeadValues)
        high_live_lead_samples = [int]$HighLiveLeadSamples
        max_hard_corrections = [int](Get-MaxNumber -Values $HardValues)
        maximum_live_prediction_error_m = [double](Get-MaxNumber -Values $ErrorValues)
        max_live_history_miss_resets = [int](Get-MaxNumber -Values $HistoryMissValues)
        final_live_history_size = [int](Get-LastValue -Events $LivePrediction -Field "history_size")
        input_queue_full_occurrences = [int]$InputQueueFull
        same_revision_mutation_occurrences = [int]$SameRevisionMutation
        camera_interpolation_warning_occurrences = [int]$CameraInterpolationWarnings
    }
}

$ServerLog = Resolve-RequiredPath -Path $ServerLog -Label "Server"
$ClientALog = Resolve-RequiredPath -Path $ClientALog -Label "Client A"
$ClientBLog = Resolve-RequiredPath -Path $ClientBLog -Label "Client B"

$ServerEvents = Read-M7Events -Path $ServerLog -Prefix "[m7_server] "
$ServerHealth = @($ServerEvents | Where-Object { $_.event -eq "SERVER_HEALTH" })
$ServerQueueFull = @(Select-String -LiteralPath $ServerLog -SimpleMatch "INPUT_QUEUE_FULL" -ErrorAction SilentlyContinue).Count
$PersistenceFatal = @(Select-String -LiteralPath $ServerLog -SimpleMatch "PERSISTENCE_FATAL" -ErrorAction SilentlyContinue).Count

$ServerSummary = [ordered]@{
    health_samples = $ServerHealth.Count
    max_pending_inputs = [int](Get-MaxNumber -Values @($ServerHealth | ForEach-Object { [double]$_.details.pending_inputs }))
    reported_max_pending_inputs = [int](Get-MaxNumber -Values @($ServerHealth | ForEach-Object { [double]$_.details.max_pending_inputs }))
    max_scheduler_backlog_ticks = [int](Get-MaxNumber -Values @($ServerHealth | ForEach-Object { [double]$_.details.max_scheduler_backlog_ticks }))
    final_scheduler_backlog_ticks = [int](Get-LastValue -Events $ServerHealth -Field "scheduler_backlog_ticks")
    final_transient_stall_frames = [int](Get-LastValue -Events $ServerHealth -Field "transient_stall_frames")
    final_movement_snapshot_recovery_suppressions = [int](Get-LastValue -Events $ServerHealth -Field "movement_snapshot_recovery_suppressions")
    max_server_process_duration_ms = [double](Get-MaxNumber -Values @($ServerHealth | ForEach-Object { [double]$_.details.server_process_max_duration_ms }))
    max_report_snapshot_build_duration_ms = [double](Get-MaxNumber -Values @($ServerHealth | ForEach-Object { [double]$_.details.report_max_snapshot_build_duration_ms }))
    max_peer_telemetry_duration_ms = [double](Get-MaxNumber -Values @($ServerHealth | ForEach-Object { [double]$_.details.peer_telemetry_max_duration_ms }))
    final_slow_process_frames = [int](Get-LastValue -Events $ServerHealth -Field "slow_process_frames")
    final_report_requests_coalesced = [int](Get-LastValue -Events $ServerHealth -Field "report_requests_coalesced")
    input_queue_full_occurrences = [int]$ServerQueueFull
    persistence_fatal_occurrences = [int]$PersistenceFatal
}

$ClientA = Get-ClientSummary -Path $ClientALog -Label "A"
$ClientB = Get-ClientSummary -Path $ClientBLog -Label "B"

$Failures = @()
if ($ServerSummary.health_samples -lt 1) { $Failures += "No SERVER_HEALTH samples parsed" }
if ($ClientA.prediction_health_samples -lt 1) { $Failures += "No PREDICTION_HEALTH samples parsed for client A" }
if ($ClientB.prediction_health_samples -lt 1) { $Failures += "No PREDICTION_HEALTH samples parsed for client B" }
if ($ServerSummary.input_queue_full_occurrences -gt 0 -or $ClientA.input_queue_full_occurrences -gt 0 -or $ClientB.input_queue_full_occurrences -gt 0) {
    $Failures += "INPUT_QUEUE_FULL observed"
}
if ($ServerSummary.persistence_fatal_occurrences -gt 0) { $Failures += "PERSISTENCE_FATAL observed" }
if ($ServerSummary.reported_max_pending_inputs -gt $MaxAcceptablePendingInputs) {
    $Failures += "Server pending inputs exceeded $MaxAcceptablePendingInputs (observed $($ServerSummary.reported_max_pending_inputs))"
}
if ($ServerSummary.final_scheduler_backlog_ticks -ne 0) {
    $Failures += "Scheduler backlog did not return to zero (final $($ServerSummary.final_scheduler_backlog_ticks))"
}
if ($ServerSummary.final_transient_stall_frames -gt $MaxAcceptableTransientStallFrames) {
    $Failures += "Transient stall frames exceeded $MaxAcceptableTransientStallFrames (observed $($ServerSummary.final_transient_stall_frames))"
}
if ($ServerSummary.max_server_process_duration_ms -gt $MaxAcceptableServerProcessMs) {
    $Failures += "Server process peak exceeded ${MaxAcceptableServerProcessMs} ms (observed $([math]::Round($ServerSummary.max_server_process_duration_ms, 3)) ms)"
}
if ($ServerSummary.max_report_snapshot_build_duration_ms -gt $MaxAcceptableReportBuildMs) {
    $Failures += "Report snapshot build peak exceeded ${MaxAcceptableReportBuildMs} ms (observed $([math]::Round($ServerSummary.max_report_snapshot_build_duration_ms, 3)) ms)"
}
if ($ServerSummary.max_peer_telemetry_duration_ms -gt $MaxAcceptablePeerTelemetryMs) {
    $Failures += "Peer telemetry peak exceeded ${MaxAcceptablePeerTelemetryMs} ms (observed $([math]::Round($ServerSummary.max_peer_telemetry_duration_ms, 3)) ms)"
}

foreach ($Client in @($ClientA, $ClientB)) {
    if ($Client.max_live_lead_ticks -gt $MaxAcceptableLiveLeadTicks) {
        $Failures += "Client $($Client.label) LIVE prediction lead exceeded $MaxAcceptableLiveLeadTicks ticks (observed $($Client.max_live_lead_ticks); raw $($Client.max_raw_lead_ticks); ignored tail samples $($Client.ignored_tail_prediction_samples))"
    }
    if ($Client.max_hard_corrections -gt 0) {
        $Failures += "Client $($Client.label) used hard reconciliation corrections ($($Client.max_hard_corrections))"
    }
    if ($Client.maximum_live_prediction_error_m -gt $MaxAcceptablePredictionErrorM) {
        $Failures += "Client $($Client.label) live prediction error exceeded ${MaxAcceptablePredictionErrorM} m (observed $([math]::Round($Client.maximum_live_prediction_error_m, 4)) m)"
    }
    if ($Client.max_live_history_miss_resets -gt $MaxAcceptableHistoryMissResets) {
        $Failures += "Client $($Client.label) live history-miss resets exceeded $MaxAcceptableHistoryMissResets (observed $($Client.max_live_history_miss_resets))"
    }
    if ($Client.same_revision_mutation_occurrences -gt 0) {
        $Failures += "Client $($Client.label) reported MULTIPLAYER_SAME_REVISION_MUTATION"
    }
    if ($Client.camera_interpolation_warning_occurrences -gt 0) {
        $Failures += "Client $($Client.label) reported Camera3D physics-interpolation warnings"
    }
}

$Result = [ordered]@{
    schema = "planet_simulator.m7_fix7_stress_analysis.v1"
    passed = ($Failures.Count -eq 0)
    tail_policy = "EXCLUDE_TRAILING_CLIENT_HEALTH_SUFFIX_WITH_FROZEN_MESSAGES_AND_SNAPSHOTS_V1"
    thresholds = [ordered]@{
        max_live_lead_ticks = $MaxAcceptableLiveLeadTicks
        max_pending_inputs = $MaxAcceptablePendingInputs
        max_server_process_ms = $MaxAcceptableServerProcessMs
        max_report_build_ms = $MaxAcceptableReportBuildMs
        max_peer_telemetry_ms = $MaxAcceptablePeerTelemetryMs
        max_live_prediction_error_m = $MaxAcceptablePredictionErrorM
        max_transient_stall_frames = $MaxAcceptableTransientStallFrames
        max_live_history_miss_resets = $MaxAcceptableHistoryMissResets
    }
    server = $ServerSummary
    client_a = $ClientA
    client_b = $ClientB
    failures = @($Failures)
}

Write-Host ""
Write-Host "M7 FIX7 stress analysis" -ForegroundColor Cyan
Write-Host ("Server: pending max={0}, process max={1:N3} ms, report build max={2:N3} ms, peer telemetry max={3:N3} ms, transient stalls={4}" -f `
    $ServerSummary.reported_max_pending_inputs, $ServerSummary.max_server_process_duration_ms, $ServerSummary.max_report_snapshot_build_duration_ms, $ServerSummary.max_peer_telemetry_duration_ms, $ServerSummary.final_transient_stall_frames)
Write-Host ("Client A: live/raw lead={0}/{1} ticks, ignored tail={2}, hard corrections={3}, live error max={4:N4} m" -f `
    $ClientA.max_live_lead_ticks, $ClientA.max_raw_lead_ticks, $ClientA.ignored_tail_prediction_samples, $ClientA.max_hard_corrections, $ClientA.maximum_live_prediction_error_m)
Write-Host ("Client B: live/raw lead={0}/{1} ticks, ignored tail={2}, hard corrections={3}, live error max={4:N4} m" -f `
    $ClientB.max_live_lead_ticks, $ClientB.max_raw_lead_ticks, $ClientB.ignored_tail_prediction_samples, $ClientB.max_hard_corrections, $ClientB.maximum_live_prediction_error_m)

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputPath = [System.IO.Path]::GetFullPath($OutputJson)
    $OutputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    }
    $Result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Analysis JSON: $OutputPath"
}

if ($Failures.Count -gt 0) {
    Write-Host "FIX7 stress acceptance: FAIL" -ForegroundColor Red
    foreach ($Failure in $Failures) { Write-Host " - $Failure" -ForegroundColor Red }
    exit 1
}

Write-Host "FIX7 stress acceptance: PASS" -ForegroundColor Green
exit 0
