param(
    [Parameter(Mandatory = $true)][string]$ServerJson,
    [Parameter(Mandatory = $true)][string]$ClientAJson,
    [Parameter(Mandatory = $true)][string]$ClientBJson,
    [int]$MinStressDurationMs = 300000,
    [int]$MaxPhaseMismatchReconciliations = 5,
    [int]$MaxTransitionHistoryMisses = 5,
    [int]$MaxHoldDeltaTicks = 1,
    [double]$MaxTransitionDeltaErrorM = 0.01,
    [double]$MaxVelocityDeltaErrorM = 0.01,
    [double]$MaxSameClockAuthorityErrorM = 0.50,
    [double]$MinPhaseMatchDominanceRatio = 4.0,
    [int]$MaxServerTransitionMetadataIncomplete = 5,
    [string]$OutputJson = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseAnalyzer = Join-Path $ProjectRoot "ANALYZE_M7_FIX10_RESULTS.ps1"
$ExpectedSemanticBaselinePolicy = "PRE_POST_TRANSITION_PHASE_AWARE_AUTHORITY_SNAPSHOT_V1"
$ExpectedTransitionPolicy = "PRE_POST_INPUT_TRANSITION_WITH_HOLD_TICKS_V1"
$ExpectedWirePolicy = "COMPACT_TRANSITION_ARRAY_V2"

function Read-RequiredJson {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label JSON not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-PredictionReport {
    param([object]$Client)
    $Prediction = $Client.world_report.m7_prediction_report
    if ($null -eq $Prediction -and $null -ne $Client.runtime_report.client_prediction) {
        $Prediction = $Client.runtime_report.client_prediction.runtime
    }
    return $Prediction
}

function Get-Fix6ClientSummary {
    param([object]$Client, [string]$Label)
    $Prediction = Get-PredictionReport -Client $Client
    $Details = $Client.details
    return [ordered]@{
        label = $Label
        state = [string]$Client.state
        passed = [bool]$Client.passed
        normal_prediction_only = [bool]$Details.normal_prediction_only
        prediction_sync_enabled_for_entire_stress = [bool]$Details.prediction_sync_enabled_for_entire_stress
        stress_duration_ms = [int]$Details.stress_duration_ms
        requested_stress_duration_ms = [int]$Details.requested_stress_duration_ms
        waypoints_completed = [int]$Details.waypoints_completed
        item_actions = [int]$Details.item_actions
        final_state_sync_enabled = [bool]$Client.world_report.m7_state_sync_enabled
        ticks_predicted = [int]$Prediction.ticks_predicted
        semantic_baseline_policy = [string]$Prediction.fix10_fix6_semantic_baseline_policy
        transition_policy = [string]$Prediction.fix10_fix6_transition_policy
        phase_mismatch_authority_reconciliations = [int]$Prediction.fix10_fix6_phase_mismatch_authority_reconciliations
        phase_matched_ack_reconciliations = [int]$Prediction.fix10_fix6_phase_matched_ack_reconciliations
        transition_history_misses = [int]$Prediction.fix10_fix6_transition_history_misses
        transition_metadata_acks = [int]$Prediction.fix10_fix6_transition_metadata_acks
        max_server_hold_ticks = [int]$Prediction.fix10_fix6_max_server_hold_ticks
        max_client_hold_ticks = [int]$Prediction.fix10_fix6_max_client_hold_ticks
        max_hold_delta_ticks = [int]$Prediction.fix10_fix6_max_hold_delta_ticks
        max_raw_phase_baseline_offset_m = [double]$Prediction.fix10_fix6_max_raw_phase_baseline_offset_m
        max_pre_state_offset_m = [double]$Prediction.fix10_fix6_max_pre_state_offset_m
        max_transition_delta_error_m = [double]$Prediction.fix10_fix6_max_transition_delta_error_m
        max_velocity_delta_error_m = [double]$Prediction.fix10_fix6_max_velocity_delta_error_m
        max_same_clock_authority_error_m = [double]$Prediction.fix10_fix6_max_same_clock_authority_error_m
        last_ack_phase_mismatch = [bool]$Prediction.fix10_fix6_last_ack_phase_mismatch
        last_transition_diagnostics = $Prediction.fix10_fix6_last_transition_diagnostics
    }
}

if (-not (Test-Path -LiteralPath $BaseAnalyzer -PathType Leaf)) {
    throw "Base FIX10 analyzer not found: $BaseAnalyzer"
}

Write-Host "M7 FIX10 fix6 semantic baseline acceptance analysis" -ForegroundColor Cyan
Write-Host ""
Write-Host "[Existing FIX10/FIX4-FIX5 acceptance thresholds]" -ForegroundColor Cyan

$BaseArguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $BaseAnalyzer,
    "-ServerJson", $ServerJson,
    "-ClientAJson", $ClientAJson,
    "-ClientBJson", $ClientBJson
)
& powershell.exe @BaseArguments
$BaseExitCode = $LASTEXITCODE

$Server = Read-RequiredJson -Path $ServerJson -Label "Server"
$ClientA = Read-RequiredJson -Path $ClientAJson -Label "Client A"
$ClientB = Read-RequiredJson -Path $ClientBJson -Label "Client B"
$A = Get-Fix6ClientSummary -Client $ClientA -Label "A"
$B = Get-Fix6ClientSummary -Client $ClientB -Label "B"
$ServerFoundation = $Server.realtime_foundation
$ServerAck = $Server.fix10_prediction_ack
$Failures = [System.Collections.ArrayList]::new()

if ($BaseExitCode -ne 0) {
    [void]$Failures.Add("Existing FIX10 acceptance analyzer failed")
}

# Steady FIX7 READY reports are intentionally lightweight. FIX10 fix6 mirrors
# transition diagnostics into realtime_foundation there; terminal/full reports
# also expose the detailed fix10_prediction_ack object. Accept either shape.
$ServerWirePolicy = [string]$ServerFoundation.fix10_fix6_ack_wire_policy
if ([string]::IsNullOrWhiteSpace($ServerWirePolicy) -and $null -ne $ServerAck) {
    $ServerWirePolicy = [string]$ServerAck.fix6_wire_policy
}
$ServerTransitionPolicy = [string]$ServerFoundation.fix10_fix6_transition_policy
if ([string]::IsNullOrWhiteSpace($ServerTransitionPolicy) -and $null -ne $ServerAck) {
    $ServerTransitionPolicy = [string]$ServerAck.fix6_transition_policy
}
$ServerTransitionCaptures = [int]$ServerFoundation.fix10_fix6_transition_captures
if ($ServerTransitionCaptures -eq 0 -and $null -ne $ServerAck) {
    $ServerTransitionCaptures = [int]$ServerAck.fix6_transition_captures
}
$ServerTransitionIncomplete = [int]$ServerFoundation.fix10_fix6_transition_metadata_incomplete
if ($ServerTransitionIncomplete -eq 0 -and $null -ne $ServerAck) {
    $ServerTransitionIncomplete = [int]$ServerAck.fix6_transition_metadata_incomplete
}
$ServerMaxHoldTicks = [int]$ServerFoundation.fix10_fix6_max_server_hold_ticks
if ($ServerMaxHoldTicks -eq 0 -and $null -ne $ServerAck) {
    $ServerMaxHoldTicks = [int]$ServerAck.fix6_max_server_hold_ticks
}
$ServerMaxTransitionDisplacementM = [double]$ServerFoundation.fix10_fix6_max_transition_displacement_m
if ($ServerMaxTransitionDisplacementM -eq 0.0 -and $null -ne $ServerAck) {
    $ServerMaxTransitionDisplacementM = [double]$ServerAck.fix6_max_transition_displacement_m
}

if ($ServerWirePolicy -ne $ExpectedWirePolicy) {
    [void]$Failures.Add("Server FIX6 ACK wire policy is '$ServerWirePolicy', expected '$ExpectedWirePolicy'")
}
if ($ServerTransitionPolicy -ne $ExpectedTransitionPolicy) {
    [void]$Failures.Add("Server FIX6 transition policy is '$ServerTransitionPolicy', expected '$ExpectedTransitionPolicy'")
}
if ($ServerTransitionCaptures -le 0) {
    [void]$Failures.Add("Server captured no FIX6 transition metadata")
}
if ($ServerTransitionIncomplete -gt $MaxServerTransitionMetadataIncomplete) {
    [void]$Failures.Add("Server incomplete FIX6 transition metadata exceeded $MaxServerTransitionMetadataIncomplete ($ServerTransitionIncomplete)")
}

foreach ($Client in @($A, $B)) {
    if (-not $Client.normal_prediction_only) {
        [void]$Failures.Add("Client $($Client.label) result is not eligible for FIX6 acceptance: normal_prediction_only is false/missing")
    }
    if (-not $Client.prediction_sync_enabled_for_entire_stress -or -not $Client.final_state_sync_enabled) {
        [void]$Failures.Add("Client $($Client.label) disabled M7 prediction sync during the acceptance run")
    }
    if ($Client.stress_duration_ms -lt $MinStressDurationMs) {
        [void]$Failures.Add("Client $($Client.label) stress duration is below ${MinStressDurationMs} ms ($($Client.stress_duration_ms))")
    }
    if ($Client.item_actions -le 0) {
        [void]$Failures.Add("Client $($Client.label) executed no item actions during the stress run")
    }
    if ($Client.waypoints_completed -le 10) {
        [void]$Failures.Add("Client $($Client.label) completed too few movement waypoints ($($Client.waypoints_completed))")
    }
    if ($Client.semantic_baseline_policy -ne $ExpectedSemanticBaselinePolicy) {
        [void]$Failures.Add("Client $($Client.label) FIX6 semantic baseline policy missing/drifted")
    }
    if ($Client.transition_policy -ne $ExpectedTransitionPolicy) {
        [void]$Failures.Add("Client $($Client.label) FIX6 transition policy missing/drifted")
    }
    if ($Client.transition_metadata_acks -le 0) {
        [void]$Failures.Add("Client $($Client.label) received no FIX6 transition metadata ACKs")
    }
    if ($Client.phase_matched_ack_reconciliations -le 0) {
        [void]$Failures.Add("Client $($Client.label) had no phase-matched ACK reconciliations")
    }
    if ($Client.phase_mismatch_authority_reconciliations -gt $MaxPhaseMismatchReconciliations) {
        [void]$Failures.Add("Client $($Client.label) phase mismatches exceeded $MaxPhaseMismatchReconciliations ($($Client.phase_mismatch_authority_reconciliations))")
    }
    if ($Client.transition_history_misses -gt $MaxTransitionHistoryMisses) {
        [void]$Failures.Add("Client $($Client.label) FIX6 transition history misses exceeded $MaxTransitionHistoryMisses ($($Client.transition_history_misses))")
    }
    if ($Client.max_hold_delta_ticks -gt $MaxHoldDeltaTicks) {
        [void]$Failures.Add("Client $($Client.label) semantic hold delta exceeded $MaxHoldDeltaTicks tick(s) ($($Client.max_hold_delta_ticks))")
    }
    if ($Client.max_transition_delta_error_m -gt $MaxTransitionDeltaErrorM) {
        [void]$Failures.Add("Client $($Client.label) transition delta error exceeded ${MaxTransitionDeltaErrorM} m ($($Client.max_transition_delta_error_m))")
    }
    if ($Client.max_velocity_delta_error_m -gt $MaxVelocityDeltaErrorM) {
        [void]$Failures.Add("Client $($Client.label) transition velocity delta error exceeded $MaxVelocityDeltaErrorM ($($Client.max_velocity_delta_error_m))")
    }
    if ($Client.max_same_clock_authority_error_m -gt $MaxSameClockAuthorityErrorM) {
        [void]$Failures.Add("Client $($Client.label) same-clock authority error exceeded ${MaxSameClockAuthorityErrorM} m ($($Client.max_same_clock_authority_error_m))")
    }
    if ($Client.phase_mismatch_authority_reconciliations -gt 0) {
        $Dominance = [double]$Client.phase_matched_ack_reconciliations / [double]$Client.phase_mismatch_authority_reconciliations
        if ($Dominance -lt $MinPhaseMatchDominanceRatio) {
            [void]$Failures.Add("Client $($Client.label) phase-matched ACKs do not dominate mismatches by ${MinPhaseMatchDominanceRatio}x ($([Math]::Round($Dominance, 3))x)")
        }
    }
}

$Result = [ordered]@{
    schema = "planet_simulator.m7_fix10_fix6_result_analysis.v1"
    passed = ($Failures.Count -eq 0)
    base_fix10_analysis_passed = ($BaseExitCode -eq 0)
    thresholds = [ordered]@{
        min_stress_duration_ms = $MinStressDurationMs
        max_phase_mismatch_reconciliations = $MaxPhaseMismatchReconciliations
        max_transition_history_misses = $MaxTransitionHistoryMisses
        max_hold_delta_ticks = $MaxHoldDeltaTicks
        max_transition_delta_error_m = $MaxTransitionDeltaErrorM
        max_velocity_delta_error_m = $MaxVelocityDeltaErrorM
        max_same_clock_authority_error_m = $MaxSameClockAuthorityErrorM
        min_phase_match_dominance_ratio = $MinPhaseMatchDominanceRatio
        max_server_transition_metadata_incomplete = $MaxServerTransitionMetadataIncomplete
    }
    server_fix6 = [ordered]@{
        wire_policy = $ServerWirePolicy
        transition_policy = $ServerTransitionPolicy
        transition_captures = $ServerTransitionCaptures
        transition_metadata_incomplete = $ServerTransitionIncomplete
        max_server_hold_ticks = $ServerMaxHoldTicks
        max_transition_displacement_m = $ServerMaxTransitionDisplacementM
    }
    client_a = $A
    client_b = $B
    failures = @($Failures)
}

Write-Host ""
Write-Host "[FIX10 fix6 semantic phase/transition thresholds]" -ForegroundColor Cyan
Write-Host ("Server: wire={0}, transitions={1}, incomplete={2}, max hold={3}" -f `
    $ServerWirePolicy, $ServerTransitionCaptures, $ServerTransitionIncomplete, $ServerMaxHoldTicks)
foreach ($Client in @($A, $B)) {
    Write-Host ("Client {0}: duration={1:N1}s, ticks={2}, phase matched/mismatch={3}/{4}, history misses={5}, hold delta={6}, transition error={7:N6}m, same-clock error={8:N6}m, raw phase offset={9:N6}m, items={10}, waypoints={11}" -f `
        $Client.label, ($Client.stress_duration_ms / 1000.0), $Client.ticks_predicted, `
        $Client.phase_matched_ack_reconciliations, $Client.phase_mismatch_authority_reconciliations, `
        $Client.transition_history_misses, $Client.max_hold_delta_ticks, `
        $Client.max_transition_delta_error_m, $Client.max_same_clock_authority_error_m, `
        $Client.max_raw_phase_baseline_offset_m, $Client.item_actions, $Client.waypoints_completed)
}

if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputJson)
    $OutputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    }
    $Result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Result JSON: $OutputPath"
}

if ($Failures.Count -gt 0) {
    Write-Host "FIX10 fix6 semantic baseline analysis: FAIL" -ForegroundColor Red
    foreach ($Failure in $Failures) {
        Write-Host " - $Failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "FIX10 fix6 semantic baseline analysis: PASS" -ForegroundColor Green
exit 0
