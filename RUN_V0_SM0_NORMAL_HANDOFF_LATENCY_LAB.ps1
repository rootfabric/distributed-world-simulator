[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [ValidateRange(2, 1000)][int]$RequireHandoffs = 10,
    [string]$ProjectRoot = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGraphical = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$SourceRunner = Join-Path $ProjectRoot "RUN_V0_SM0_GRAPHICAL_LAB.ps1"
if (-not (Test-Path -LiteralPath $SourceRunner -PathType Leaf)) {
    throw "SM0 normal handoff source graphical runner not found: $SourceRunner"
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
    throw "Unable to resolve exact SM0 normal handoff HEAD."
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
    ProjectRoot = $ProjectRoot
    GodotConsole = $GodotConsole
    GodotGraphical = $GodotGraphical
}
if ($Restart) { $Invoke.Restart = $true }
if ($AllowDirty) { $Invoke.AllowDirty = $true }

Write-Host "[SM0-P3] NORMAL healthy handoff latency lab: no fault profile, no authority kills, no recovery holds." -ForegroundColor Green
Write-Host "[SM0-P3] Cross the boundary at least $RequireHandoffs times, then close the Godot window."
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
    # A timestamp collision is extremely unlikely, but use the newest directory
    # as a deterministic fallback if the source runner reused a name.
    $CandidateDirs = @(
        Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
}
if ($CandidateDirs.Count -eq 0) {
    throw "SM0-P3 could not locate the graphical log directory."
}

$LogDir = $CandidateDirs[0].FullName
$ClientLog = Join-Path $LogDir "graphical-client.log"
if (-not (Test-Path -LiteralPath $ClientLog -PathType Leaf)) {
    throw "SM0-P3 graphical client log missing: $ClientLog"
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
        throw "SM0-P3 invalid latency event JSON in $ClientLog : $Line"
    }
    $Samples.Add($Event)
}

if ($Samples.Count -lt $RequireHandoffs) {
    throw "SM0-P3 expected at least $RequireHandoffs measured handoffs, found $($Samples.Count)."
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
$PreviousTarget = ""

Write-Host ""
Write-Host "[SM0-P3] Per-handoff client-observed latency:" -ForegroundColor Cyan
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

    if ($Transfer.Length -eq 0) { throw "SM0-P3 handoff #$Index has empty transfer id." }
    if ($Source -eq $Target -or $Source -notin @("authority/sm0/a", "authority/sm0/b") -or $Target -notin @("authority/sm0/a", "authority/sm0/b")) {
        throw "SM0-P3 handoff #$Index has invalid route $Source -> $Target."
    }
    if (-not [string]::IsNullOrWhiteSpace($PreviousTarget) -and $Source -ne $PreviousTarget) {
        throw "SM0-P3 handoff #$Index route is not continuous: previous target=$PreviousTarget source=$Source."
    }
    if ($IdentityChanges -ne 0 -or $PlayerId -ne "player/a") {
        throw "SM0-P3 identity invariant failed at handoff #${Index}: player=$PlayerId identity_changes=$IdentityChanges."
    }
    if ($Total -lt 0 -or $Redirect -lt 0 -or $Activate -lt 0 -or [Math]::Abs(($Redirect + $Activate) - $Total) -gt 2.0) {
        throw "SM0-P3 latency accounting failed at handoff #${Index}: total=$Total redirect=$Redirect activate=$Activate."
    }
    if ([Math]::Abs($Speed - 0.25) -gt 0.001) {
        throw "SM0-P3 handoff #$Index changed canonical movement step magnitude: speed=$Speed."
    }

    $Totals.Add($Total)
    $ToRedirect.Add($Redirect)
    $ToActivate.Add($Activate)
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
}

$SummaryPath = Join-Path $LogDir "normal-handoff-latency-summary.json"
$Summary = [ordered]@{
    schema = "distributed_world_simulator.sm0_normal_handoff_latency_summary.v1"
    git_head = $Head
    godot_version = $VersionText
    measurement = "client accepted boundary MOVE_ACK -> HANDOFF_REDIRECT -> ACTIVATE_ACK"
    fault_profile = "none"
    authority_process_restarts = 0
    artificial_recovery_holds = 0
    statistics = $Stats
    samples = @($Samples)
    client_log = $ClientLog
}
$Summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

Write-Host ""
Write-Host "SM0-P3 normal healthy handoff latency measurement: PASS" -ForegroundColor Green
Write-Host "  samples : $($Stats.sample_count)"
Write-Host ("  total   : min={0:N0} ms  p50={1:N0} ms  p95={2:N0} ms  max={3:N0} ms  avg={4:N1} ms" -f $Stats.min_ms, $Stats.p50_ms, $Stats.p95_ms, $Stats.max_ms, $Stats.average_ms)
Write-Host ("  phases  : trigger->redirect p50={0:N0} ms p95={1:N0} ms | redirect->activate p50={2:N0} ms p95={3:N0} ms" -f $Stats.trigger_to_redirect_p50_ms, $Stats.trigger_to_redirect_p95_ms, $Stats.redirect_to_activate_p50_ms, $Stats.redirect_to_activate_p95_ms)
Write-Host "  HEAD    : $Head"
Write-Host "  Godot   : $VersionText"
Write-Host "  logs    : $LogDir"
Write-Host "  summary : $SummaryPath"
exit 0