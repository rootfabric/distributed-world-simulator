[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LogDirectory
)

$ErrorActionPreference = "Stop"
$LogDirectory = [IO.Path]::GetFullPath($LogDirectory)
$ServerLogs = @(
    [pscustomobject]@{ Role = "server-a"; Path = (Join-Path $LogDirectory "server-a.log") },
    [pscustomobject]@{ Role = "server-b"; Path = (Join-Path $LogDirectory "server-b.log") }
)

$Events = [System.Collections.Generic.List[object]]::new()
$HardeningReady = @{}
foreach ($Server in $ServerLogs) {
    if (-not (Test-Path -LiteralPath $Server.Path -PathType Leaf)) {
        throw "SM0-P4 global writer audit missing $($Server.Role) log: $($Server.Path)"
    }
    foreach ($Line in Get-Content -LiteralPath $Server.Path -ErrorAction Stop) {
        if (-not $Line.Contains("[SM0_EVENT]")) { continue }
        $Brace = $Line.IndexOf('{')
        if ($Brace -lt 0) { continue }
        try { $Event = $Line.Substring($Brace) | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        if ([string]$Event.event -eq "SM0_P4_HARDENING_READY") {
            $HardeningReady[$Server.Role] = $true
        }
        if ($null -eq $Event.writer_count) { continue }
        if ($null -eq $Event.wall_time_unix_usec) {
            throw "SM0-P4 $($Server.Role) event '$($Event.event)' lacks wall_time_unix_usec; aggregate writer ordering is not provable."
        }
        $Events.Add([pscustomobject][ordered]@{
            role = $Server.Role
            authority_id = [string]$Event.authority_id
            event = [string]$Event.event
            wall_time_unix_usec = [Int64]$Event.wall_time_unix_usec
            process_event_sequence = [Int64]$Event.process_event_sequence
            writer_count = [int]$Event.writer_count
            process_incarnation_id = [string]$Event.process_incarnation_id
        })
    }
}

foreach ($Role in @("server-a", "server-b")) {
    if (-not $HardeningReady.ContainsKey($Role)) {
        throw "SM0-P4 aggregate writer audit requires SM0_P4_HARDENING_READY from $Role."
    }
}
if ($Events.Count -lt 2) {
    throw "SM0-P4 aggregate writer audit has insufficient structured server events."
}

# All servers are child processes on the same Windows host, so wall clock is a
# shared ordering domain. If events have the exact same microsecond timestamp,
# apply writer retirement (0) before activation (1); this avoids declaring an
# overlap when the protocol's retire-before-activate edge lands in one clock bin.
$Ordered = @($Events | Sort-Object `
    @{ Expression = "wall_time_unix_usec"; Ascending = $true }, `
    @{ Expression = "writer_count"; Ascending = $true }, `
    @{ Expression = "role"; Ascending = $true }, `
    @{ Expression = "process_event_sequence"; Ascending = $true })

$State = @{ "server-a" = 0; "server-b" = 0 }
$Incarnation = @{ "server-a" = ""; "server-b" = "" }
$MaxAggregate = 0
$Overlap = $null
$Transitions = [System.Collections.Generic.List[object]]::new()
foreach ($Event in $Ordered) {
    if ($Event.writer_count -lt 0 -or $Event.writer_count -gt 1) {
        throw "SM0-P4 invalid local writer_count=$($Event.writer_count) in $($Event.role) event $($Event.event)."
    }
    $PreviousIncarnation = [string]$Incarnation[$Event.role]
    if (-not [string]::IsNullOrWhiteSpace($Event.process_incarnation_id) -and $PreviousIncarnation -ne $Event.process_incarnation_id) {
        # A restarted process has no right to inherit an inferred live writer
        # merely because the old process's last log event had writer_count=1.
        # The first event from the new incarnation supplies its actual state.
        $Incarnation[$Event.role] = $Event.process_incarnation_id
    }
    $State[$Event.role] = [int]$Event.writer_count
    $Aggregate = [int]$State["server-a"] + [int]$State["server-b"]
    if ($Aggregate -gt $MaxAggregate) { $MaxAggregate = $Aggregate }
    if ($Transitions.Count -eq 0 -or [int]$Transitions[$Transitions.Count - 1].aggregate_writer_count -ne $Aggregate) {
        $Transitions.Add([pscustomobject][ordered]@{
            wall_time_unix_usec = [Int64]$Event.wall_time_unix_usec
            role = $Event.role
            event = $Event.event
            server_a_writer_count = [int]$State["server-a"]
            server_b_writer_count = [int]$State["server-b"]
            aggregate_writer_count = $Aggregate
        })
    }
    if ($Aggregate -gt 1) {
        $Overlap = [pscustomobject][ordered]@{
            wall_time_unix_usec = [Int64]$Event.wall_time_unix_usec
            triggering_role = $Event.role
            triggering_event = $Event.event
            server_a_writer_count = [int]$State["server-a"]
            server_b_writer_count = [int]$State["server-b"]
        }
        break
    }
}

$Result = if ($null -eq $Overlap) { "PASS" } else { "FAIL" }
$SummaryPath = Join-Path $LogDirectory "p4-global-writer-audit.json"
$Summary = [ordered]@{
    schema = "distributed_world_simulator.sm0_p4_global_writer_audit.v1"
    result = $Result
    event_count = $Events.Count
    max_aggregate_writer_count = $MaxAggregate
    overlap = $Overlap
    transitions = @($Transitions)
    server_a_log = $ServerLogs[0].Path
    server_b_log = $ServerLogs[1].Path
}
$Summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

if ($null -ne $Overlap) {
    Write-Host "SM0-P4 aggregate single-writer audit: FAIL" -ForegroundColor Red
    Write-Host "  A+B writers: $($Overlap.server_a_writer_count)+$($Overlap.server_b_writer_count)"
    Write-Host "  event      : $($Overlap.triggering_role) / $($Overlap.triggering_event)"
    Write-Host "  summary    : $SummaryPath"
    exit 1
}

Write-Host "SM0-P4 aggregate single-writer audit: PASS" -ForegroundColor Green
Write-Host "  events     : $($Events.Count)"
Write-Host "  max A+B    : $MaxAggregate"
Write-Host "  summary    : $SummaryPath"
exit 0
