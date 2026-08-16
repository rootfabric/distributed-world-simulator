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
$SourceRunner = Join-Path $ProjectRoot "RUN_V0_SM0_CONTROLLED_NETWORK_LATENCY_LAB.ps1"
if (-not (Test-Path -LiteralPath $SourceRunner -PathType Leaf)) {
    throw "SM0-P3.1 FINAL matrix source runner not found: $SourceRunner"
}

$HostExecutable = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($HostExecutable) -or -not (Test-Path -LiteralPath $HostExecutable -PathType Leaf)) {
    throw "SM0-P3.1 FINAL matrix cannot resolve the current PowerShell executable."
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$LogsRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0GraphicalLab\logs"
$MatrixRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0GraphicalLab\matrix"

if ($Stop) {
    $StopArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $SourceRunner,
        "-Stop",
        "-ProjectRoot", $ProjectRoot,
        "-GodotConsole", $GodotConsole,
        "-GodotGraphical", $GodotGraphical
    )
    & $HostExecutable @StopArgs
    exit $LASTEXITCODE
}

$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Head)) {
    throw "Unable to resolve exact SM0-P3.1 FINAL matrix HEAD."
}

$Profiles = @(
    [pscustomobject]@{ Label = "WAN-10"; LatencyMs = 10; JitterMs = 2; Seed = 431 },
    [pscustomobject]@{ Label = "WAN-20"; LatencyMs = 20; JitterMs = 3; Seed = 431 },
    [pscustomobject]@{ Label = "WAN-30"; LatencyMs = 30; JitterMs = 5; Seed = 431 },
    [pscustomobject]@{ Label = "WAN-45"; LatencyMs = 45; JitterMs = 7; Seed = 431 }
)

function Get-Sm0ExistingLogDirectories {
    $Paths = @{}
    if (Test-Path -LiteralPath $LogsRoot -PathType Container) {
        foreach ($Dir in Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue) {
            $Paths[$Dir.FullName] = $true
        }
    }
    return $Paths
}

function Get-Sm0NewControlledSummary([hashtable]$BeforeDirs) {
    if (-not (Test-Path -LiteralPath $LogsRoot -PathType Container)) {
        throw "SM0-P3.1 FINAL matrix logs root was not created: $LogsRoot"
    }

    $Candidates = @(
        Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not $BeforeDirs.ContainsKey($_.FullName) } |
            Sort-Object LastWriteTime -Descending
    )
    foreach ($Dir in $Candidates) {
        $SummaryPath = Join-Path $Dir.FullName "controlled-network-latency-summary.json"
        if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
            return $SummaryPath
        }
    }

    throw "SM0-P3.1 FINAL matrix could not locate the new controlled-network-latency-summary.json."
}

$Results = [System.Collections.Generic.List[object]]::new()
$ProfileNumber = 0
foreach ($Profile in $Profiles) {
    $ProfileNumber += 1
    $BeforeDirs = Get-Sm0ExistingLogDirectories
    $LatencyMs = [int]$Profile.LatencyMs
    $JitterMs = [int]$Profile.JitterMs
    $Seed = [int]$Profile.Seed
    $Label = [string]$Profile.Label

    Write-Host ""
    Write-Host ("[SM0-P3.1 FINAL] Profile {0}/{1}: {2} one-way={3}ms jitter=+/-{4}ms seed={5}" -f $ProfileNumber, $Profiles.Count, $Label, $LatencyMs, $JitterMs, $Seed) -ForegroundColor Cyan
    Write-Host "[SM0-P3.1 FINAL] Cross the boundary at least $RequireHandoffs times, observe the boundary hitch, then close the Godot window."
    Write-Host "[SM0-P3.1 FINAL] The next profile starts automatically after the current child runner completes."

    $ChildArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $SourceRunner,
        "-RequireHandoffs", [string]$RequireHandoffs,
        "-NetworkLatencyMs", [string]$LatencyMs,
        "-NetworkJitterMs", [string]$JitterMs,
        "-NetworkSeed", [string]$Seed,
        "-ProjectRoot", $ProjectRoot,
        "-GodotConsole", $GodotConsole,
        "-GodotGraphical", $GodotGraphical
    )
    if ($Restart) { $ChildArgs += "-Restart" }
    if ($AllowDirty) { $ChildArgs += "-AllowDirty" }

    & $HostExecutable @ChildArgs
    $ChildExit = $LASTEXITCODE
    if ($ChildExit -ne 0) {
        throw "SM0-P3.1 FINAL matrix profile $Label failed with exit code $ChildExit."
    }

    $SummaryPath = Get-Sm0NewControlledSummary $BeforeDirs
    $Summary = Get-Content -LiteralPath $SummaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$Summary.schema -ne "distributed_world_simulator.sm0_controlled_network_latency_summary.v1") {
        throw "SM0-P3.1 FINAL matrix profile $Label produced an unexpected summary schema: $($Summary.schema)"
    }
    if ([string]$Summary.git_head -ne $Head) {
        throw "SM0-P3.1 FINAL matrix profile $Label HEAD mismatch: expected=$Head actual=$($Summary.git_head)"
    }
    if ([int]$Summary.network_profile.one_way_latency_ms -ne $LatencyMs -or [int]$Summary.network_profile.jitter_ms -ne $JitterMs -or [int]$Summary.network_profile.seed -ne $Seed) {
        throw "SM0-P3.1 FINAL matrix profile $Label network profile mismatch in child summary."
    }
    if ([int]$Summary.statistics.sample_count -lt $RequireHandoffs) {
        throw "SM0-P3.1 FINAL matrix profile $Label has insufficient samples: $($Summary.statistics.sample_count)."
    }

    $ConfiguredRttMs = $LatencyMs * 2
    $P50 = [double]$Summary.statistics.p50_ms
    $P95 = [double]$Summary.statistics.p95_ms
    $Ratio = if ($ConfiguredRttMs -gt 0) { [Math]::Round($P50 / $ConfiguredRttMs, 3) } else { 0.0 }
    $PreviousP50 = if ($Results.Count -gt 0) { [double]$Results[$Results.Count - 1].p50_ms } else { $null }
    $DeltaP50 = if ($null -ne $PreviousP50) { [Math]::Round($P50 - $PreviousP50, 1) } else { $null }

    $Results.Add([pscustomobject][ordered]@{
        label = $Label
        one_way_latency_ms = $LatencyMs
        jitter_ms = $JitterMs
        seed = $Seed
        configured_rtt_ms = $ConfiguredRttMs
        sample_count = [int]$Summary.statistics.sample_count
        min_ms = [double]$Summary.statistics.min_ms
        p50_ms = $P50
        p95_ms = $P95
        max_ms = [double]$Summary.statistics.max_ms
        average_ms = [double]$Summary.statistics.average_ms
        trigger_to_redirect_p50_ms = [double]$Summary.statistics.trigger_to_redirect_p50_ms
        redirect_to_activate_p50_ms = [double]$Summary.statistics.redirect_to_activate_p50_ms
        a_to_b_p50_ms = [double]$Summary.statistics.a_to_b_p50_ms
        b_to_a_p50_ms = [double]$Summary.statistics.b_to_a_p50_ms
        p50_to_configured_rtt_ratio = $Ratio
        p50_delta_from_previous_profile_ms = $DeltaP50
        child_summary = $SummaryPath
        child_log_directory = Split-Path -Parent $SummaryPath
    })
}

New-Item -ItemType Directory -Path $MatrixRoot -Force | Out-Null
$MatrixId = Get-Date -Format "yyyyMMdd-HHmmss"
$MatrixDir = Join-Path $MatrixRoot $MatrixId
New-Item -ItemType Directory -Path $MatrixDir -Force | Out-Null
$MatrixSummaryPath = Join-Path $MatrixDir "controlled-network-latency-matrix-summary.json"

$MatrixSummary = [ordered]@{
    schema = "distributed_world_simulator.sm0_controlled_network_latency_matrix_summary.v1"
    git_head = $Head
    matrix_id = $MatrixId
    matrix_status = "OBJECTIVE_INVARIANTS_PASS_SUBJECTIVE_THRESHOLD_PENDING_OPERATOR_REPORT"
    require_handoffs_per_profile = $RequireHandoffs
    profile_count = $Profiles.Count
    profile_order = @($Profiles | ForEach-Object { $_.Label })
    subjective_gate = [ordered]@{
        measured_by_runner = $false
        instruction = "Report the first profile where the authority-boundary hitch becomes perceptible. Objective PASS does not claim seamless subjective motion."
    }
    profiles = @($Results)
}
$MatrixSummary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $MatrixSummaryPath -Encoding UTF8

Write-Host ""
Write-Host "SM0-P3.1 FINAL controlled WAN latency matrix: OBJECTIVE PASS" -ForegroundColor Green
Write-Host "  HEAD    : $Head"
Write-Host "  samples : $RequireHandoffs handoffs/profile x $($Profiles.Count) profiles"
foreach ($Result in $Results) {
    Write-Host ("  {0,-6}: one-way={1,2}ms RTT={2,3}ms jitter=+/-{3,2}ms | p50={4,6:N0}ms p95={5,6:N0}ms | phases={6:N0}+{7:N0}ms | A->B={8:N0} B->A={9:N0}ms" -f $Result.label, $Result.one_way_latency_ms, $Result.configured_rtt_ms, $Result.jitter_ms, $Result.p50_ms, $Result.p95_ms, $Result.trigger_to_redirect_p50_ms, $Result.redirect_to_activate_p50_ms, $Result.a_to_b_p50_ms, $Result.b_to_a_p50_ms)
}
Write-Host "  summary : $MatrixSummaryPath"
Write-Host ""
Write-Host "Operator observation still required: report the FIRST profile where the boundary transition becomes perceptible." -ForegroundColor Yellow
Write-Host "Objective PASS means authority/identity/latency-accounting invariants held for every profile; it does not mean the transition was visually seamless."
exit 0
