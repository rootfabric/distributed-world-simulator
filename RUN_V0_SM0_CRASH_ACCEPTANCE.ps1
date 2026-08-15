[CmdletBinding()]
param(
    [ValidateRange(2, 100)][int]$Handoffs = 2,
    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(30, 600)][int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$CrashProfile = "h2-target-crash-before-prepared-v1"
if ($Final) { $Handoffs = 6; if ($TimeoutSeconds -lt 180) { $TimeoutSeconds = 180 } }
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) { throw "SM0-H2 must run under C:\distributed-world-simulator. Current: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot double console executable not found: $GodotExe" }

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH2"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Alive([int]$PidValue) { try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true } catch { return $false } }
function Stop-H2 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $S = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($R in @($S.processes)) { if (Alive ([int]$R.pid)) { Stop-Process -Id ([int]$R.pid) -Force -ErrorAction SilentlyContinue } }
        } catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}
if ($Stop) { Stop-H2; exit 0 }
if ($Restart) { Stop-H2 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "SM0-H2 requires a clean worktree:`n$($StatusBefore -join "`n")" }
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()

# Reuse the already-hardened base runner as compile/cold-import/contract/healthy-path preflight.
$BaseRunner = Join-Path $ProjectRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
$Preflight = @{ Handoffs = 2; Restart = $true; ProjectRoot = $ProjectRoot; GodotExe = $GodotExe; TimeoutSeconds = 120 }
if ($AllowDirty) { $Preflight.AllowDirty = $true }
Write-Host "[SM0-H2] Running healthy preflight before process-crash injection..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H2 healthy preflight failed." }

function Port-Free([int]$Port) {
    $U = $null
    try {
        $U = [System.Net.Sockets.UdpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $U.Client.ExclusiveAddressUse = $true
        $U.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        return $true
    } catch { return $false } finally { if ($null -ne $U) { $U.Dispose() } }
}
function Wait-Ports([int[]]$Ports) {
    $D = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $D) {
        $Ok = $true
        foreach ($P in $Ports) { if (-not (Port-Free $P)) { $Ok = $false; break } }
        if ($Ok) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}
function Q([string]$V) { return '"' + $V + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$HarnessLog = Join-Path $LogDir "harness.log"
$ALog = Join-Path $LogDir "server-a.log"
$B1Log = Join-Path $LogDir "server-b-crashed.log"
$B2Log = Join-Path $LogDir "server-b-restarted.log"
$BLog = Join-Path $LogDir "server-b.log"
$CLog = Join-Path $LogDir "client.log"
$CResult = Join-Path $LogDir "client-result.json"
$StopFile = Join-Path $LogDir "stop.flag"
$SummaryPath = Join-Path $LogDir "h2-summary.json"
function Write-H2Log([string]$M) { $L = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $M; Write-Host $L; Add-Content -LiteralPath $HarnessLog -Value $L -Encoding UTF8 }

function Start-Godot([string]$Role, [string]$Log, [string[]]$UserArgs) {
    $Args = @("--headless", "--path", (Q $ProjectRoot), "--log-file", (Q $Log), "--script", "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd", "--") + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try { $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $P = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru }
    finally { if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } }
    Write-H2Log "$Role started PID=$($P.Id) log=$Log"
    return $P
}
function Start-Client([string[]]$UserArgs) {
    $Args = @("--headless", "--path", (Q $ProjectRoot), "--log-file", (Q $CLog), "--script", "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd", "--") + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try { $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $P = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru }
    finally { if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } }
    Write-H2Log "client started PID=$($P.Id) log=$CLog"
    return $P
}
function Wait-Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$P, [int]$Seconds) {
    $D = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $D) {
        $P.Refresh(); if ($P.HasExited) { throw "PID=$($P.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}
function Events([string]$Path) {
    $Out = @()
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') { $Out += ($Matches[1] | ConvertFrom-Json) }
    }
    return @($Out)
}

$A = $null; $B1 = $null; $B2 = $null; $C = $null; $Exit = 1
try {
    foreach ($P in @(24580,24581,24680,24681,24780)) { if (-not (Port-Free $P)) { throw "UDP port $P is already in use." } }
    Write-H2Log "SM0-H2.1 start HEAD=$Head handoffs=$Handoffs profile=$CrashProfile"
    $A = Start-Godot "server-a" $ALog @("--authority-id=authority/sm0/a","--zone-id=zone/earth/sm0/west","--gameplay-port=24580","--control-port=24680","--peer-control-port=24681","--stop-file=$StopFile")
    $B1 = Start-Godot "server-b-crash-target" $B1Log @("--authority-id=authority/sm0/b","--zone-id=zone/earth/sm0/east","--gameplay-port=24581","--control-port=24681","--peer-control-port=24680","--stop-file=$StopFile","--fault-profile=$CrashProfile")
    $State = [ordered]@{ schema="distributed_world_simulator.sm0_h2_launcher_state.v1"; project_root=$ProjectRoot; git_head=$Head; log_directory=$LogDir; processes=@([ordered]@{role="server-a";pid=$A.Id},[ordered]@{role="server-b-crash-target";pid=$B1.Id}) }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-Marker $ALog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A 20
    Wait-Marker $B1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B1 20
    Wait-Marker $B1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $B1 20

    $C = Start-Client @("--server-host=127.0.0.1","--server-a-port=24580","--server-b-port=24581","--client-port=24780","--handoffs=$Handoffs","--timeout-ms=$($TimeoutSeconds*1000)","--result-file=$CResult")
    $State.processes += [ordered]@{role="client";pid=$C.Id}; $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    $D = (Get-Date).AddSeconds(30); $Seen = $false
    while ((Get-Date) -lt $D) {
        $A.Refresh(); $B1.Refresh(); $C.Refresh()
        if ($A.HasExited -or $B1.HasExited -or $C.HasExited) { throw "A process exited before deterministic crash point." }
        if ((Test-Path $B1Log) -and (Select-String -LiteralPath $B1Log -SimpleMatch '"event":"SM0_H2_CRASH_POINT"' -Quiet)) { $Seen = $true; break }
        Start-Sleep -Milliseconds 25
    }
    if (-not $Seen) { throw "H2 crash point was not observed." }

    $CrashPid = $B1.Id; Write-H2Log "Crash point observed; force-killing target PID=$CrashPid"
    Stop-Process -Id $CrashPid -Force -ErrorAction Stop
    try { $B1.WaitForExit(5000) } catch {}
    if (Alive $CrashPid) { throw "Target PID=$CrashPid survived forced crash." }
    Wait-Ports @(24581,24681)

    $B2 = Start-Godot "server-b-restarted" $B2Log @("--authority-id=authority/sm0/b","--zone-id=zone/earth/sm0/east","--gameplay-port=24581","--control-port=24681","--peer-control-port=24680","--stop-file=$StopFile")
    $State.processes += [ordered]@{role="server-b-restarted";pid=$B2.Id}; $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    Wait-Marker $B2Log '"event":"SM0_SERVER_READY"' $B2 20
    Wait-Marker $B2Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B2 20
    Write-H2Log "Restarted target synchronized; waiting for convergence."

    $D = (Get-Date).AddSeconds($TimeoutSeconds + 10)
    while (-not $C.HasExited -and (Get-Date) -lt $D) {
        Start-Sleep -Milliseconds 50; $C.Refresh(); $A.Refresh(); $B2.Refresh()
        if ($A.HasExited -or $B2.HasExited) { throw "Authority process exited after target restart." }
    }
    if (-not $C.HasExited) { throw "Client timed out after target restart." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($S in @($A,$B2)) { $D=(Get-Date).AddSeconds(10); while (-not $S.HasExited -and (Get-Date)-lt $D) { Start-Sleep -Milliseconds 50; $S.Refresh() }; if (-not $S.HasExited) { Stop-Process -Id $S.Id -Force -ErrorAction SilentlyContinue } }

    @((Get-Content -LiteralPath $B1Log),(Get-Content -LiteralPath $B2Log)) | Set-Content -LiteralPath $BLog -Encoding UTF8
    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) { throw "Base SM0 convergence failed after crash/restart." }

    $EA = @(Events $ALog); $E1 = @(Events $B1Log); $E2 = @(Events $B2Log)
    $Crash = @($E1 | Where-Object { $_.event -eq "SM0_H2_CRASH_POINT" -and $_.crash_point -eq "TARGET_BEFORE_PREPARED_ACK" })
    if ($Crash.Count -ne 1) { throw "Expected one crash event, got $($Crash.Count)." }
    $T = [string]$Crash[0].transfer_id
    if (@($E1 | Where-Object { $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $T }).Count -ne 0) { throw "Target committed before crash." }
    foreach ($N in @("SM0_HANDOFF_PREPARED","SM0_TARGET_AUTHORITY_COMMITTED","SM0_TARGET_ACTIVATED")) { if (@($E2 | Where-Object { $_.event -eq $N -and [string]$_.transfer_id -eq $T }).Count -lt 1) { throw "Restarted target missing $N for $T" } }
    foreach ($N in @("SM0_SOURCE_FROZEN","SM0_SOURCE_TRANSFER_COMPLETE")) { if (@($EA | Where-Object { $_.event -eq $N -and [string]$_.transfer_id -eq $T }).Count -lt 1) { throw "Source missing $N for $T" } }
    $R = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($R.result -ne "PASS" -or [int]$R.handoffs_completed -ne $Handoffs -or [int]$R.identity_changes -ne 0) { throw "Client recovery evidence failed." }

    [ordered]@{schema="distributed_world_simulator.sm0_h2_target_restart_summary.v1";result="PASS";git_head=$Head;crash_point="TARGET_BEFORE_PREPARED_ACK";crash_transfer_id=$T;crashed_target_pid=$CrashPid;restarted_target_pid=$B2.Id;handoffs_completed=[int]$R.handoffs_completed;identity_changes=[int]$R.identity_changes;authority_epoch_end=[int]$R.authority_epoch_end;logs=$LogDir} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
    Write-Host ""; Write-Host "SM0-H2.1 target crash/restart analysis: PASS" -ForegroundColor Green
    Write-Host "  crashed PID       : $CrashPid"; Write-Host "  restarted PID     : $($B2.Id)"; Write-Host "  recovered transfer: $T"; Write-Host "  handoffs          : $Handoffs / $Handoffs"; Write-Host "  identity changes  : 0"; Write-Host "  logs              : $LogDir"; Write-Host "  summary           : $SummaryPath"
    $Exit = 0
}
catch { Write-Error "SM0-H2.1 FAIL: $($_.Exception.Message)" -ErrorAction Continue; $Exit = 1 }
finally {
    foreach ($P in @($C,$A,$B1,$B2)) { if ($null -ne $P) { try { $P.Refresh(); if (-not $P.HasExited) { Stop-Process -Id $P.Id -Force -ErrorAction SilentlyContinue } } catch {} } }
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
}
$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) { Write-Error "SM0-H2 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue; exit 1 }
exit $Exit