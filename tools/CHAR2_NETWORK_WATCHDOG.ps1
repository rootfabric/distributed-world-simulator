[CmdletBinding()]
param(
    # Health files produced by the instrumented CHAR2 run
    [string] $ClientHealth = "$env:APPDATA\Godot\app_userdata\Real Scale Procedural Moon\char2_client_health.jsonl",
    [string] $ServerHealth = "$env:APPDATA\Godot\app_userdata\Real Scale Procedural Moon\char2_server_health.jsonl",
    # Where the watchdog writes
    [string] $WatchLog = "C:\dwsv-char2-network-r1-run\network-watchdog.jsonl",
    [string] $ReportFile = "C:\dwsv-char2-network-r1-run\network-watchdog-report.txt",
    [int] $SampleIntervalSeconds = 15,
    # Degradation thresholds (tuned from the 2026-10-10 degraded-server capture:
    # ~18 sequence gaps/s per client on loopback, i.e. >1000 gaps/min)
    [int] $GapsPerMinuteWarn = 300,
    [int] $GapsPerMinuteDegraded = 600,
    [int] $SnapshotTickLagWarn = 3000,
    [double] $SnapshotAgeP95WarnMs = 100.0,
    [double] $ReplayedTicksP99Warn = 8.0,
    [switch] $NoAlertsOnStaleFiles
)

# CHAR2 network watchdog.
# Watches the instrumented client/server health dumps for the degradation
# signatures observed on 2026-10-10:
#   1. transport_unreliable_sequence_gaps climbing fast (lost/unordered
#      unreliable frames -> NX5 interpolation starvation -> jerky rollback).
#   2. client snapshot tick falling behind the server tick.
#   3. rising snapshot age / prediction replay bursts.
#   4. movement input rejections or join failures on a long-lived server.
# Every sample and every alert is appended to the JSONL watch log; the last
# state is summarized into the report file.

$ErrorActionPreference = 'Continue'

function Read-LastLines([string] $Path, [int] $Count) {
    if (-not (Test-Path $Path)) { return @() }
    return @(Get-Content $Path -Tail $Count -ErrorAction SilentlyContinue)
}

function Get-ClientState {
    $states = @{}
    $lines = Read-LastLines $ClientHealth 12
    foreach ($group in ($lines | ConvertFrom-Json -ErrorAction SilentlyContinue | Group-Object player)) {
        $last = $group.Group | Select-Object -Last 1
        if ($null -ne $last) { $states[[string]$last.player] = $last }
    }
    return $states
}

function Get-ServerState {
    $lines = Read-LastLines $ServerHealth 10
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $parsed = $lines[$i] | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $parsed -and [string]$parsed.event -eq 'SERVER_HEALTH') { return $parsed }
    }
    return $null
}

function Append-Watch([hashtable] $Entry) {
    $Entry['watchdog_time'] = (Get-Date).ToString('o')
    Add-Content -Path $WatchLog -Value (ConvertTo-Json -InputObject $Entry -Depth 6 -Compress)
}

$script:lastGaps = @{}
$script:lastSampleTime = $null
$script:degradedSince = $null
$script:alertsRaised = 0

Append-Watch @{ event = 'WATCHDOG_START'; thresholds = @{
    gaps_per_minute_warn = $GapsPerMinuteWarn; gaps_per_minute_degraded = $GapsPerMinuteDegraded
    snapshot_tick_lag_warn = $SnapshotTickLagWarn; snapshot_age_p95_warn_ms = $SnapshotAgeP95WarnMs
    replayed_ticks_p99_warn = $ReplayedTicksP99Warn } }

while ($true) {
    $now = Get-Date
    $server = Get-ServerState
    $clients = Get-ClientState

    $alerts = @()
    $summary = @()

    foreach ($p in @($clients.Keys | Sort-Object)) {
        $c = $clients[$p]
        if ($null -eq $c) { continue }
        $d = $c.details
        $tel = $d.telemetry
        $gaps = [int]($tel.counters.transport_unreliable_sequence_gaps)
        $key = "$($c.process_id)"
        $gapsRate = $null

        if ($script:lastSampleTime -ne $null -and $script:lastGaps.ContainsKey($key)) {
            $elapsedMin = (($now - $script:lastSampleTime).TotalMinutes)
            if ($elapsedMin -gt 0.0) {
                $gapsRate = [math]::Round(($gaps - $script:lastGaps[$key]) / $elapsedMin, 0)
            }
        }
        $script:lastGaps[$key] = $gaps

        $snapshotAgeP95 = [double]($tel.distributions.snapshot_age_ms.p95)
        $replayedP99 = [double]($tel.distributions.prediction_replayed_ticks.p99)
        $srvTick = 0
        if ($server -ne $null) { $srvTick = [int]($server.details.server_tick) }
        $tickLag = $null
        if ($srvTick -gt 0) { $tickLag = $srvTick - [int]($d.snapshot_server_tick) }

        $line = ("client {0} pid {1}: state={2} gaps={3} gaps/min={4} tick_lag={5} snap_age_p95={6}ms replay_p99={7} seq={8} pos=[{9}]" -f `
            $p, $c.process_id, $d.connection_state, $gaps, $gapsRate, ($(if ($null -ne $tickLag) { $tickLag } else { 'n/a' })), $snapshotAgeP95, $replayedP99, $d.input_sequence, (($d.own_position | ForEach-Object { [math]::Round($_) }) -join ','))
        $summary += $line

        if ($d.connection_state -ne 'CONNECTED') {
            $alerts += "client ${p}: connection_state=$($d.connection_state) last_error=$($d.last_error_code)"
        }
        if ($null -ne $gapsRate -and $gapsRate -ge $GapsPerMinuteDegraded) {
            $alerts += "client ${p}: DEGRADED unreliable sequence gaps ${gapsRate}/min (threshold $GapsPerMinuteDegraded)"
        } elseif ($null -ne $gapsRate -and $gapsRate -ge $GapsPerMinuteWarn) {
            $alerts += "client ${p}: WARN unreliable sequence gaps ${gapsRate}/min"
        }
        if ($srvTick -gt 0 -and $tickLag -ge $SnapshotTickLagWarn) {
            $alerts += "client ${p}: snapshot tick lag ${tickLag} ticks behind server"
        }
        if ($snapshotAgeP95 -ge $SnapshotAgeP95WarnMs) {
            $alerts += "client ${p}: snapshot age p95 ${snapshotAgeP95} ms"
        }
        if ($replayedP99 -ge $ReplayedTicksP99Warn) {
            $alerts += "client ${p}: prediction replay p99 ${replayedP99} ticks"
        }
        if ($d.reconcile_failures -gt 0) {
            $alerts += "client ${p}: reconcile_failures=$($d.reconcile_failures)"
        }
        if ($d.event -eq 'CLIENT_CONNECTION_FAILED') {
            $alerts += "client ${p}: CONNECTION FAILED ($($d.details.error_code))"
        }
    }
    $script:lastSampleTime = $now

    $srvLine = $null
    if ($server -ne $null) {
        $srvLine = ("server pid {0}: tick={1} moves={2} rejections={3} peers={4} err={5}" -f `
            $server.process_id, $server.details.server_tick, $server.details.moves, $server.details.rejections, $server.details.connected_peers, $server.details.last_error_code)
        if ([int]$server.details.rejections -gt 0) {
            $alerts += "server: movement rejections=$($server.details.rejections)"
        }
    } else {
        $srvLine = 'server: no health data'
    }

    $severity = 'OK'
    if ($alerts.Count -gt 0) {
        $severity = if ($alerts | Where-Object { $_ -match 'DEGRADED|CONNECTION FAILED' }) { 'DEGRADED' } else { 'WARN' }
        $script:alertsRaised += $alerts.Count
    }
    if ($severity -eq 'DEGRADED') {
        if ($script:degradedSince -eq $null) { $script:degradedSince = $now }
    } else {
        $script:degradedSince = $null
    }

    Append-Watch @{ event = 'SAMPLE'; severity = $severity; server = $srvLine; clients = $summary; alerts = $alerts }
    if ($alerts.Count -gt 0) {
        Append-Watch @{ event = 'ALERT'; severity = $severity; alerts = $alerts }
    }

    $report = @(
        "CHAR2 network watchdog - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "severity: $severity  degraded_since: $($script:degradedSince -as [string])  total_alerts: $($script:alertsRaised)",
        '',
        $srvLine
    ) + $summary
    if ($alerts.Count -gt 0) { $report += @('', 'ALERTS:') + $alerts }
    Set-Content -Path $ReportFile -Value $report -Encoding UTF8

    Start-Sleep -Seconds $SampleIntervalSeconds
}
