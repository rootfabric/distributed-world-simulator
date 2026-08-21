[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [ValidateRange(2, 1000)][int]$RequireHandoffs = 10,
    [ValidateRange(1, 10000)][int]$NetworkLatencyMs = 30,
    [ValidateRange(0, 5000)][int]$NetworkJitterMs = 5,
    [int]$NetworkSeed = 431,
    [string]$ProjectRoot = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGraphical = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$ErrorActionPreference = "Stop"
$Profile = "p31-controlled-latency-v1"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$SourceRunner = Join-Path $ProjectRoot "RUN_V0_SM0_GRAPHICAL_LAB.ps1"
if (-not (Test-Path -LiteralPath $SourceRunner -PathType Leaf)) {
    throw "SM0-P3.1 source graphical runner not found: $SourceRunner"
}
if ($NetworkJitterMs -gt $NetworkLatencyMs) {
    throw "SM0-P3.1 NetworkJitterMs cannot exceed NetworkLatencyMs."
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$LogsRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0GraphicalLab\logs"

if ($Stop) {
    & $SourceRunner -Stop -ProjectRoot $ProjectRoot -GodotConsole $GodotConsole -GodotGraphical $GodotGraphical
    exit $LASTEXITCODE
}

$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Head)) {
    throw "Unable to resolve exact SM0-P3.1 HEAD."
}

$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$VersionText = (& $GodotConsole --version | Select-Object -First 1).Trim()
if ($VersionText -ne $ExpectedVersion) {
    throw "Unexpected Godot version: $VersionText"
}

$BeforeDirs = @{}
if (Test-Path -LiteralPath $LogsRoot -PathType Container) {
    foreach ($Dir in Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue) {
        $BeforeDirs[$Dir.FullName] = $true
    }
}

$Invoke = @{
    RequireHandoffs = $RequireHandoffs
    NetworkProfile = $Profile
    NetworkLatencyMs = $NetworkLatencyMs
    NetworkJitterMs = $NetworkJitterMs
    NetworkSeed = $NetworkSeed
    ProjectRoot = $ProjectRoot
    GodotConsole = $GodotConsole
    GodotGraphical = $GodotGraphical
}
if ($Restart) { $Invoke.Restart = $true }
if ($AllowDirty) { $Invoke.AllowDirty = $true }

Write-Host "[SM0-P3.1] CONTROLLED WAN-like latency lab: healthy authority path, deterministic UDP egress delay, zero intentional loss/reorder." -ForegroundColor Green
Write-Host "[SM0-P3.1] Profile=$Profile one-way=${NetworkLatencyMs}ms jitter=+/-${NetworkJitterMs}ms seed=$NetworkSeed"
Write-Host "[SM0-P3.1] Cross the boundary at least $RequireHandoffs times, observe whether a hitch is perceptible, then close the Godot window."
& $SourceRunner @Invoke
$SourceExit = $LASTEXITCODE
if ($SourceExit -ne 0) {
    exit $SourceExit
}

$CandidateDirs = @()
if (Test-Path -LiteralPath $LogsRoot -PathType Container) {
    $CandidateDirs = @(
        Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not $BeforeDirs.ContainsKey($_.FullName) } |
            Sort-Object LastWriteTime -Descending
    )
}
if ($CandidateDirs.Count -eq 0) {
    $CandidateDirs = @(
        Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
}
if ($CandidateDirs.Count -eq 0) {
    throw "SM0-P3.1 could not locate the graphical log directory."
}

$LogDir = $CandidateDirs[0].FullName
$ClientLog = Join-Path $LogDir "graphical-client.log"
$ServerALog = Join-Path $LogDir "server-a.log"
$ServerBLog = Join-Path $LogDir "server-b.log"
foreach ($Path in @($ClientLog, $ServerALog, $ServerBLog)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "SM0-P3.1 required log missing: $Path"
    }
}

foreach ($Path in @($ClientLog, $ServerALog, $ServerBLog)) {
    if (-not (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_NET_PROFILE_ENABLED"' -Quiet -ErrorAction SilentlyContinue)) {
        throw "SM0-P3.1 profile marker missing: $Path"
    }
    if (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_INVARIANT_VIOLATION"' -Quiet -ErrorAction SilentlyContinue) {
        throw "SM0-P3.1 invariant violation found: $Path"
    }
}

$ClientDelayCount = @(Select-String -LiteralPath $ClientLog -SimpleMatch '"event":"SM0_NET_DELAY_SCHEDULED"' -ErrorAction SilentlyContinue).Count
$ServerADelayCount = @(Select-String -LiteralPath $ServerALog -SimpleMatch '"event":"SM0_NET_DELAY_SCHEDULED"' -ErrorAction SilentlyContinue).Count
$ServerBDelayCount = @(Select-String -LiteralPath $ServerBLog -SimpleMatch '"event":"SM0_NET_DELAY_SCHEDULED"' -ErrorAction SilentlyContinue).Count
if ($ClientDelayCount -lt 1 -or $ServerADelayCount -lt 1 -or $ServerBDelayCount -lt 1) {
    throw "SM0-P3.1 missing handoff delay evidence: client=$ClientDelayCount A=$ServerADelayCount B=$ServerBDelayCount"
}

$Samples = [System.Collections.Generic.List[object]]::new()
foreach ($Line in Get-Content -LiteralPath $ClientLog -ErrorAction Stop) {
    if (-not $Line.Contains('"event":"SM0_CLIENT_HANDOFF_LATENCY_MEASURED"')) { continue }
    $Brace = $Line.IndexOf('{')
    if ($Brace -lt 0) { continue }
    try {
        $Event = $Line.Substring($Brace) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "SM0-P3.1 invalid latency event JSON in $ClientLog : $Line"
    }
    $Samples.Add($Event)
}

if ($Samples.Count -lt $RequireHandoffs) {
    throw "SM0-P3.1 expected at least $RequireHandoffs measured handoffs, found $($Samples.Count)."
}

function Get-Sm0NearestRank([double[]]$Values, [double]$Percentile) {
    if ($Values.Count -eq 0) { return 0.0 }
    $Sorted = @($Values | Sort-Object)
    $Rank = [Math]::Ceiling($Percentile * $Sorted.Count)
    $Index = [Math]::Max(0, [Math]::Min($Sorted.Count - 1, $Rank - 1))
    return [double]$Sorted[$Index]
}

$Totals = [System.Collections.Generic.List[double]]::new()
$ToRedirect = [System.Collections.Generic.List[double]]::new()
$ToActivate = [System.Collections.Generic.List[double]]::new()
$AToB = [System.Collections.Generic.List[double]]::new()
$BToA = [System.Collections.Generic.List[double]]::new()
$PreviousTarget = ""

Write-Host ""
Write-Host "[SM0-P3.1] Per-handoff client-observed latency under controlled network delay:" -ForegroundColor Cyan
foreach ($Sample in $Samples) {
    $Index = [int]$Sample.handoff_index
    $Transfer = [string]$Sample.transfer_id
    $Source = [string]$Sample.source_authority_id
    $Target = [string]$Sample.target_authority_id
    $Total = [double]$Sample.total_ms
    $Redirect = [double]$Sample.trigger_to_redirect_ms
    $Activate = [double]$Sample.redirect_to_activate_ms
    $IdentityChanges = [int]$Sample.identity_changes
    $PlayerId = [string]$Sample.player_entity_id
    $Velocity = $Sample.velocity
    $Vx = [double]$Velocity.x
    $Vz = [double]$Velocity.z
    $Speed = [Math]::Sqrt($Vx * $Vx + $Vz * $Vz)

    if ($Transfer.Length -eq 0) { throw "SM0-P3.1 handoff #$Index has empty transfer id." }
    if ($Source -eq $Target -or $Source -notin @("authority/sm0/a", "authority/sm0/b") -or $Target -notin @("authority/sm0/a", "authority/sm0/b")) {
        throw "SM0-P3.1 handoff #$Index has invalid route $Source -> $Target."
    }
    if (-not [string]::IsNullOrWhiteSpace($PreviousTarget) -and $Source -ne $PreviousTarget) {
        throw "SM0-P3.1 handoff #$Index route is not continuous: previous target=$PreviousTarget source=$Source."
    }
    if ($IdentityChanges -ne 0 -or $PlayerId -ne "player/a") {
        throw "SM0-P3.1 identity invariant failed at handoff #${Index}: player=$PlayerId identity_changes=$IdentityChanges."
    }
    if ($Total -lt 0 -or $Redirect -lt 0 -or $Activate -lt 0 -or [Math]::Abs(($Redirect + $Activate) - $Total) -gt 2.0) {
        throw "SM0-P3.1 latency accounting failed at handoff #${Index}: total=$Total redirect=$Redirect activate=$Activate."
    }
    if ([Math]::Abs($Speed - 0.25) -gt 0.001) {
        throw "SM0-P3.1 handoff #$Index changed canonical movement step magnitude: speed=$Speed."
    }

    $Totals.Add($Total)
    $ToRedirect.Add($Redirect)
    $ToActivate.Add($Activate)
    if ($Source -eq "authority/sm0/a") { $AToB.Add($Total) } else { $BToA.Add($Total) }
    $PreviousTarget = $Target
    Write-Host ("  #{0,2} {1} -> {2}  total={3,6:N0} ms  trigger->redirect={4,6:N0} ms  redirect->activate={5,5:N0} ms  |v|={6:N2}" -f $Index, $Source.Split('/')[-1].ToUpperInvariant(), $Target.Split('/')[-1].ToUpperInvariant(), $Total, $Redirect, $Activate, $Speed)
}

$TotalArray = [double[]]$Totals.ToArray()
$RedirectArray = [double[]]$ToRedirect.ToArray()
$ActivateArray = [double[]]$ToActivate.ToArray()
$Average = ($TotalArray | Measure-Object -Average).Average
$Stats = [ordered]@{
    sample_count = $Samples.Count
    min_ms = [double]($TotalArray | Measure-Object -Minimum).Minimum
    p50_ms = Get-Sm0NearestRank $TotalArray 0.50
    p95_ms = Get-Sm0NearestRank $TotalArray 0.95
    max_ms = [double]($TotalArray | Measure-Object -Maximum).Maximum
    average_ms = [double]$Average
    trigger_to_redirect_p50_ms = Get-Sm0NearestRank $RedirectArray 0.50
    trigger_to_redirect_p95_ms = Get-Sm0NearestRank $RedirectArray 0.95
    redirect_to_activate_p50_ms = Get-Sm0NearestRank $ActivateArray 0.50
    redirect_to_activate_p95_ms = Get-Sm0NearestRank $ActivateArray 0.95
    a_to_b_p50_ms = if ($AToB.Count -gt 0) { Get-Sm0NearestRank ([double[]]$AToB.ToArray()) 0.50 } else { 0.0 }
    b_to_a_p50_ms = if ($BToA.Count -gt 0) { Get-Sm0NearestRank ([double[]]$BToA.ToArray()) 0.50 } else { 0.0 }
}

$SummaryPath = Join-Path $LogDir "controlled-network-latency-summary.json"
$Summary = [ordered]@{
    schema = "distributed_world_simulator.sm0_controlled_network_latency_summary.v1"
    git_head = $Head
    godot_version = $VersionText
    measurement = "client accepted boundary MOVE_ACK -> HANDOFF_REDIRECT -> ACTIVATE_ACK"
    network_profile = [ordered]@{
        id = $Profile
        one_way_latency_ms = $NetworkLatencyMs
        jitter_ms = $NetworkJitterMs
        seed = $NetworkSeed
        intentional_loss_percent = 0
        intentional_duplicate_percent = 0
        intentional_reorder_percent = 0
        shaped_egress = @("authority-a", "authority-b", "graphical-client")
    }
    authority_process_restarts = 0
    artificial_recovery_holds = 0
    delay_evidence = [ordered]@{
        client_scheduled = $ClientDelayCount
        authority_a_scheduled = $ServerADelayCount
        authority_b_scheduled = $ServerBDelayCount
    }
    statistics = $Stats
    samples = @($Samples)
    client_log = $ClientLog
    server_a_log = $ServerALog
    server_b_log = $ServerBLog
}
$Summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

Write-Host ""
Write-Host "SM0-P3.1 controlled network handoff latency measurement: PASS" -ForegroundColor Green
Write-Host "  profile : $Profile one-way=${NetworkLatencyMs}ms jitter=+/-${NetworkJitterMs}ms seed=$NetworkSeed loss=0 reorder=0"
Write-Host "  samples : $($Stats.sample_count)"
Write-Host ("  total   : min={0:N0} ms  p50={1:N0} ms  p95={2:N0} ms  max={3:N0} ms  avg={4:N1} ms" -f $Stats.min_ms, $Stats.p50_ms, $Stats.p95_ms, $Stats.max_ms, $Stats.average_ms)
Write-Host ("  phases  : trigger->redirect p50={0:N0} ms p95={1:N0} ms | redirect->activate p50={2:N0} ms p95={3:N0} ms" -f $Stats.trigger_to_redirect_p50_ms, $Stats.trigger_to_redirect_p95_ms, $Stats.redirect_to_activate_p50_ms, $Stats.redirect_to_activate_p95_ms)
Write-Host ("  dirs    : A->B p50={0:N0} ms | B->A p50={1:N0} ms" -f $Stats.a_to_b_p50_ms, $Stats.b_to_a_p50_ms)
Write-Host "  shaping : client=$ClientDelayCount authority-A=$ServerADelayCount authority-B=$ServerBDelayCount handoff messages scheduled"
Write-Host "  HEAD    : $Head"
Write-Host "  Godot   : $VersionText"
Write-Host "  logs    : $LogDir"
Write-Host "  summary : $SummaryPath"
exit 0
