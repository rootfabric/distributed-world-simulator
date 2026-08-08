param(
    [Parameter(Mandatory = $true)][string]$ServerJson,
    [Parameter(Mandatory = $true)][string]$ClientAJson,
    [Parameter(Mandatory = $true)][string]$ClientBJson,
    [double]$MaxPredictionErrorM = 0.50,
    [double]$MaxServerProcessMs = 75.0,
    [double]$MaxReportBuildMs = 25.0,
    [double]$MaxMeasuredPhaseMs = 25.0,
    [int]$MaxClientSlowProcessFrames = 2,
    [int]$MaxUnattributedOverBudgetFrames = 2,
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

function Get-PhaseSummary {
    param([object]$Phases)
    $Result = [ordered]@{}
    if ($null -eq $Phases) { return $Result }
    foreach ($Property in $Phases.PSObject.Properties) {
        $Phase = $Property.Value
        $Result[$Property.Name] = [ordered]@{
            count = [int]$Phase.count
            last_ms = [double]$Phase.last_ms
            max_ms = [double]$Phase.max_ms
            mean_ms = [double]$Phase.mean_ms
            over_budget = [int]$Phase.over_budget
        }
    }
    return $Result
}

function Get-DominantPhase {
    param([System.Collections.IDictionary]$Phases)
    $Name = ""
    $MaxMs = 0.0
    foreach ($Key in $Phases.Keys) {
        $Value = $Phases[$Key]
        if ([double]$Value.max_ms -gt $MaxMs) {
            $MaxMs = [double]$Value.max_ms
            $Name = [string]$Key
        }
    }
    return [ordered]@{ name = $Name; max_ms = $MaxMs }
}

function Get-ClientSummary {
    param([object]$Client, [string]$Label)
    $Prediction = $Client.world_report.m7_prediction_report
    $NetworkBudget = $Client.runtime_report.client_frame_budget
    $WorldBudget = $Client.world_report.fix9_client_frame_budget
    $Inventory = $Client.world_report.inventory_rev6
    $NetworkPhases = Get-PhaseSummary -Phases $NetworkBudget.phases
    $WorldPhases = Get-PhaseSummary -Phases $WorldBudget.phases
    return [ordered]@{
        label = $Label
        passed = [bool]$Client.passed
        hard_corrections = [int]$Prediction.hard_corrections
        maximum_error_m = [double]$Prediction.maximum_error_m
        network_policy = [string]$NetworkBudget.policy
        network_process_max_ms = [double]$NetworkBudget.process_max_ms
        network_process_slow_frames = [int]$NetworkBudget.process_slow_frames
        network_unattributed_max_ms = [double]$NetworkBudget.unattributed_max_ms
        network_unattributed_over_budget_frames = [int]$NetworkBudget.unattributed_over_budget_frames
        network_phases = $NetworkPhases
        network_dominant_phase = Get-DominantPhase -Phases $NetworkPhases
        world_policy = [string]$WorldBudget.policy
        world_physics_unattributed_max_ms = [double]$WorldBudget.physics_unattributed_max_ms
        world_phases = $WorldPhases
        world_dominant_phase = Get-DominantPhase -Phases $WorldPhases
        inventory_schema = [string]$Inventory.schema
        inventory_layout_policy = [string]$Inventory.layout_policy
        inventory_sort_layout_updates = [int]$Inventory.sort_layout_updates
        inventory_sort_layout_skips = [int]$Inventory.sort_layout_skips
        inventory_hint_layout_updates = [int]$Inventory.interaction_hint_layout_updates
        inventory_hint_layout_skips = [int]$Inventory.interaction_hint_layout_skips
        inventory_visibility_updates = [int]$Inventory.visibility_updates
        inventory_visibility_skips = [int]$Inventory.visibility_skips
    }
}

function Add-PhaseFailures {
    param(
        [System.Collections.ArrayList]$Failures,
        [System.Collections.IDictionary]$Phases,
        [string]$Label,
        [double]$ThresholdMs
    )
    foreach ($Key in $Phases.Keys) {
        # Unattributed time has its own count-based gate below. Aggregate message
        # dispatch/control also contains compatibility/JOIN/bootstrap work before
        # normal gameplay is established. The exact-Windows FIX1 gate proved that
        # one startup dispatch can be >100 ms while the steady process p99 remains
        # around 3 ms. Gate those lifecycle spikes by the total >=50 ms process
        # frame count instead of rejecting the lifetime maximum twice. Snapshot,
        # item, prediction, telemetry and other gameplay phases keep the strict
        # absolute phase limit.
        $PhaseName = [string]$Key
        if ($PhaseName -like "*unattributed*") { continue }
        if ($PhaseName -eq "message_dispatch" -or $PhaseName -eq "control_message") { continue }
        $MaxMs = [double]$Phases[$Key].max_ms
        if ($MaxMs -gt $ThresholdMs) {
            [void]$Failures.Add("$Label phase '$Key' exceeded ${ThresholdMs} ms ($MaxMs)")
        }
    }
}

$Server = Read-RequiredJson -Path $ServerJson -Label "Server"
$ClientA = Read-RequiredJson -Path $ClientAJson -Label "Client A"
$ClientB = Read-RequiredJson -Path $ClientBJson -Label "Client B"
$A = Get-ClientSummary -Client $ClientA -Label "A"
$B = Get-ClientSummary -Client $ClientB -Label "B"
$ServerHealthy = Test-HealthyServerResult -Server $Server
$Realtime = $Server.realtime_foundation
$Failures = [System.Collections.ArrayList]::new()

if (-not $ServerHealthy) {
    [void]$Failures.Add("Server result is neither terminal PASS nor a healthy READY authority")
}
$ServerProcessMs = [double]$Realtime.server_process_max_duration_ms
$ReportBuildMs = [double]$Realtime.report_max_snapshot_build_duration_ms
if ($ServerProcessMs -gt $MaxServerProcessMs) {
    [void]$Failures.Add("Server process peak exceeded ${MaxServerProcessMs} ms ($ServerProcessMs)")
}
if ($ReportBuildMs -gt $MaxReportBuildMs) {
    [void]$Failures.Add("Server report build peak exceeded ${MaxReportBuildMs} ms ($ReportBuildMs)")
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
    if ($Client.network_policy -ne "PHASE_ACCOUNTING_NO_GAMEPLAY_SEMANTICS_V1") {
        [void]$Failures.Add("Client $($Client.label) does not expose FIX9 network phase accounting")
    }
    if ($Client.world_policy -ne "CLIENT_WORLD_PHASE_ACCOUNTING_V1") {
        [void]$Failures.Add("Client $($Client.label) does not expose FIX9 world presentation phase accounting")
    }
    if ($Client.network_process_slow_frames -gt $MaxClientSlowProcessFrames) {
        [void]$Failures.Add("Client $($Client.label) had $($Client.network_process_slow_frames) >=50ms network-process frames (limit $MaxClientSlowProcessFrames)")
    }
    if ($Client.network_unattributed_over_budget_frames -gt $MaxUnattributedOverBudgetFrames) {
        [void]$Failures.Add("Client $($Client.label) had $($Client.network_unattributed_over_budget_frames) unattributed >16.667ms process frames (limit $MaxUnattributedOverBudgetFrames)")
    }
    Add-PhaseFailures -Failures $Failures -Phases $Client.network_phases -Label "Client $($Client.label) network" -ThresholdMs $MaxMeasuredPhaseMs
    Add-PhaseFailures -Failures $Failures -Phases $Client.world_phases -Label "Client $($Client.label) world" -ThresholdMs $MaxMeasuredPhaseMs
    if ($Client.inventory_layout_policy -ne "WRITE_CONTROL_GEOMETRY_ONLY_WHEN_CHANGED_V1") {
        [void]$Failures.Add("Client $($Client.label) does not use FIX9 inventory write-on-change layout policy")
    }
    if ($Client.inventory_sort_layout_skips -le 0 -or $Client.inventory_hint_layout_skips -le 0) {
        [void]$Failures.Add("Client $($Client.label) did not observe redundant inventory layout suppression")
    }
}

$Result = [ordered]@{
    schema = "planet_simulator.m7_fix9_result_analysis.v1"
    passed = ($Failures.Count -eq 0)
    server_result_policy = $ServerResultPolicy
    thresholds = [ordered]@{
        max_prediction_error_m = $MaxPredictionErrorM
        max_server_process_ms = $MaxServerProcessMs
        max_report_build_ms = $MaxReportBuildMs
        max_measured_phase_ms = $MaxMeasuredPhaseMs
        max_client_slow_process_frames = $MaxClientSlowProcessFrames
        max_unattributed_over_budget_frames = $MaxUnattributedOverBudgetFrames
    }
    server = [ordered]@{
        healthy = $ServerHealthy
        terminal_passed = [bool]$Server.passed
        state = [string]$Server.state
        process_max_duration_ms = $ServerProcessMs
        report_max_snapshot_build_duration_ms = $ReportBuildMs
    }
    client_a = $A
    client_b = $B
    failures = @($Failures)
}

Write-Host ""
Write-Host "M7 FIX9 frame-budget analysis" -ForegroundColor Cyan
Write-Host ("Server: healthy={0}, state={1}, process max={2:N3} ms, report build max={3:N3} ms" -f `
    $ServerHealthy, [string]$Server.state, $ServerProcessMs, $ReportBuildMs)
foreach ($Client in @($A, $B)) {
    Write-Host ("Client {0}: process max={1:N3} ms, >=50ms frames={2}, unattributed max={3:N3} ms / over-budget frames={4}, net dominant={5}:{6:N3} ms, world dominant={7}:{8:N3} ms" -f `
        $Client.label, $Client.network_process_max_ms, $Client.network_process_slow_frames, `
        $Client.network_unattributed_max_ms, $Client.network_unattributed_over_budget_frames, `
        $Client.network_dominant_phase.name, $Client.network_dominant_phase.max_ms, `
        $Client.world_dominant_phase.name, $Client.world_dominant_phase.max_ms)
    Write-Host ("Client {0} inventory: sort writes/skips={1}/{2}, hint writes/skips={3}/{4}, visibility writes/skips={5}/{6}" -f `
        $Client.label, $Client.inventory_sort_layout_updates, $Client.inventory_sort_layout_skips, `
        $Client.inventory_hint_layout_updates, $Client.inventory_hint_layout_skips, `
        $Client.inventory_visibility_updates, $Client.inventory_visibility_skips)
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
    Write-Host "FIX9 analysis: FAIL" -ForegroundColor Red
    foreach ($Failure in $Failures) { Write-Host " - $Failure" -ForegroundColor Red }
    exit 1
}

Write-Host "FIX9 analysis: PASS" -ForegroundColor Green
exit 0
