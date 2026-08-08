param(
    [Parameter(Mandatory = $true)][string]$ServerLog,
    [Parameter(Mandatory = $true)][string]$ClientALog,
    [Parameter(Mandatory = $true)][string]$ClientBLog,
    [int]$MaxAcceptableLeadTicks = 20,
    [int]$MaxAcceptablePendingInputs = 20,
    [double]$MaxAcceptableServerProcessMs = 100.0,
    [double]$MaxAcceptableReportBuildMs = 50.0,
    [double]$MaxAcceptablePeerTelemetryMs = 20.0,
    [double]$MaxAcceptablePredictionErrorM = 1.25,
    [int]$MaxAcceptableTransientStallFrames = 10,
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
        $JsonStart = $Index + $Prefix.Length
        $Json = $Text.Substring($JsonStart).Trim()
        if ([string]::IsNullOrWhiteSpace($Json)) { continue }
        try {
            $Value = $Json | ConvertFrom-Json
            if ($null -ne $Value) { $Events += $Value }
        }
        catch {
            # Ignore non-JSON/truncated console lines; the summary below requires
            # at least one valid health event from every process.
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
    $LeadValues = @($Prediction | ForEach-Object { [double]$_.details.lead_ticks })
    $HardValues = @($Prediction | ForEach-Object { [double]$_.details.hard_corrections })
    $ErrorValues = @($Prediction | ForEach-Object { [double]$_.details.maximum_error_m })
    $HighLeadSamples = @($Prediction | Where-Object { [int]$_.details.lead_ticks -gt $MaxAcceptableLeadTicks }).Count
    $InputQueueFull = @(Select-String -LiteralPath $Path -SimpleMatch "INPUT_QUEUE_FULL" -ErrorAction SilentlyContinue).Count
    $SameRevisionMutation = @(Select-String -LiteralPath $Path -SimpleMatch "MULTIPLAYER_SAME_REVISION_MUTATION" -ErrorAction SilentlyContinue).Count
    return [ordered]@{
        label = $Label
        prediction_health_samples = $Prediction.Count
        client_health_samples = $Health.Count
        max_lead_ticks = [int](Get-MaxNumber -Values $LeadValues)
        high_lead_samples = [int]$HighLeadSamples
        max_hard_corrections = [int](Get-MaxNumber -Values $HardValues)
        maximum_prediction_error_m = [double](Get-MaxNumber -Values $ErrorValues)
        final_history_miss_resets = [int](Get-LastValue -Events $Prediction -Field "history_miss_resets")
        final_history_size = [int](Get-LastValue -Events $Prediction -Field "history_size")
        input_queue_full_occurrences = [int]$InputQueueFull
        same_revision_mutation_occurrences = [int]$SameRevisionMutation
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
    if ($Client.max_lead_ticks -gt $MaxAcceptableLeadTicks) {
        $Failures += "Client $($Client.label) prediction lead exceeded $MaxAcceptableLeadTicks ticks (observed $($Client.max_lead_ticks))"
    }
    if ($Client.max_hard_corrections -gt 0) {
        $Failures += "Client $($Client.label) used hard reconciliation corrections ($($Client.max_hard_corrections))"
    }
    if ($Client.maximum_prediction_error_m -gt $MaxAcceptablePredictionErrorM) {
        $Failures += "Client $($Client.label) prediction error exceeded ${MaxAcceptablePredictionErrorM} m (observed $([math]::Round($Client.maximum_prediction_error_m, 4)) m)"
    }
    if ($Client.same_revision_mutation_occurrences -gt 0) {
        $Failures += "Client $($Client.label) reported MULTIPLAYER_SAME_REVISION_MUTATION"
    }
}

$Result = [ordered]@{
    schema = "planet_simulator.m7_fix6_stress_analysis.v1"
    passed = ($Failures.Count -eq 0)
    thresholds = [ordered]@{
        max_lead_ticks = $MaxAcceptableLeadTicks
        max_pending_inputs = $MaxAcceptablePendingInputs
        max_server_process_ms = $MaxAcceptableServerProcessMs
        max_report_build_ms = $MaxAcceptableReportBuildMs
        max_peer_telemetry_ms = $MaxAcceptablePeerTelemetryMs
        max_prediction_error_m = $MaxAcceptablePredictionErrorM
        max_transient_stall_frames = $MaxAcceptableTransientStallFrames
    }
    server = $ServerSummary
    client_a = $ClientA
    client_b = $ClientB
    failures = @($Failures)
}

Write-Host ""
Write-Host "M7 FIX6 stress analysis" -ForegroundColor Cyan
Write-Host ("Server: pending max={0}, process max={1:N3} ms, report build max={2:N3} ms, peer telemetry max={3:N3} ms, transient stalls={4}" -f `
    $ServerSummary.reported_max_pending_inputs, $ServerSummary.max_server_process_duration_ms, $ServerSummary.max_report_snapshot_build_duration_ms, $ServerSummary.max_peer_telemetry_duration_ms, $ServerSummary.final_transient_stall_frames)
Write-Host ("Client A: lead max={0} ticks, hard corrections={1}, prediction error max={2:N4} m" -f `
    $ClientA.max_lead_ticks, $ClientA.max_hard_corrections, $ClientA.maximum_prediction_error_m)
Write-Host ("Client B: lead max={0} ticks, hard corrections={1}, prediction error max={2:N4} m" -f `
    $ClientB.max_lead_ticks, $ClientB.max_hard_corrections, $ClientB.maximum_prediction_error_m)

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
    Write-Host "FIX6 stress acceptance: FAIL" -ForegroundColor Red
    foreach ($Failure in $Failures) { Write-Host " - $Failure" -ForegroundColor Red }
    exit 1
}

Write-Host "FIX6 stress acceptance: PASS" -ForegroundColor Green
exit 0
