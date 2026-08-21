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
$CrashProfile = "h2-target-crash-after-commit-persist-v1"
if ($Final) { $Handoffs = 6; if ($TimeoutSeconds -lt 180) { $TimeoutSeconds = 180 } }
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) { throw "SM0-H2.2 must run under C:\distributed-world-simulator. Current: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot double console executable not found: $GodotExe" }

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH22"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H22Alive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}
function Stop-H22 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $S = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($R in @($S.processes)) {
                if (Test-H22Alive ([int]$R.pid)) { Stop-Process -Id ([int]$R.pid) -Force -ErrorAction SilentlyContinue }
            }
        } catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}
if ($Stop) { Stop-H22; exit 0 }
if ($Restart) { Stop-H22 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "SM0-H2.2 requires a clean worktree:`n$($StatusBefore -join "`n")" }
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()

$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate pre-existing UID sidecars." }
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) { $UidBeforeSet[[string]$RelativeUid] = $true }

$BaseRunner = Join-Path $ProjectRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
$Preflight = @{ Handoffs = 2; Restart = $true; ProjectRoot = $ProjectRoot; GodotExe = $GodotExe; TimeoutSeconds = 120 }
if ($AllowDirty) { $Preflight.AllowDirty = $true }
Write-Host "[SM0-H2.2] Running healthy preflight before durable commit crash injection..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H2.2 healthy preflight failed." }

function Invoke-H22CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H2.2] Compile check: $ScriptPath"
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        $Code = $LASTEXITCODE
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($Code -ne 0) { throw "SM0-H2.2 compile check failed: $ScriptPath (exit $Code)" }
}
foreach ($ScriptPath in @(
    "res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd"
)) { Invoke-H22CompileCheck $ScriptPath }

function Test-H22PortFree([int]$Port) {
    $U = $null
    try {
        $U = [System.Net.Sockets.UdpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $U.Client.ExclusiveAddressUse = $true
        $U.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        return $true
    } catch { return $false } finally { if ($null -ne $U) { $U.Dispose() } }
}
function Wait-H22Ports([int[]]$Ports) {
    $D = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $D) {
        $Ok = $true
        foreach ($Port in $Ports) { if (-not (Test-H22PortFree $Port)) { $Ok = $false; break } }
        if ($Ok) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}
function Quote-H22([string]$Value) { return '"' + $Value + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
$RecoveryRoot = Join-Path $LogDir "recovery"
New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
$HarnessLog = Join-Path $LogDir "harness.log"
$ALog = Join-Path $LogDir "server-a.log"
$B1Log = Join-Path $LogDir "server-b-crashed.log"
$B2Log = Join-Path $LogDir "server-b-restarted.log"
$BLog = Join-Path $LogDir "server-b.log"
$CLog = Join-Path $LogDir "client.log"
$CResult = Join-Path $LogDir "client-result.json"
$StopFile = Join-Path $LogDir "stop.flag"
$SummaryPath = Join-Path $LogDir "h22-summary.json"
function Write-H22Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H22Godot([string]$Role, [string]$Log, [string[]]$UserArgs) {
    $Args = @("--headless", "--path", (Quote-H22 $ProjectRoot), "--log-file", (Quote-H22 $Log), "--script", "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd", "--") + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try { $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $P = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru }
    finally { if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } }
    Write-H22Log "$Role started PID=$($P.Id) log=$Log"
    return $P
}
function Start-H22Client([string[]]$UserArgs) {
    $Args = @("--headless", "--path", (Quote-H22 $ProjectRoot), "--log-file", (Quote-H22 $CLog), "--script", "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd", "--") + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try { $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $P = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru }
    finally { if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } }
    Write-H22Log "client started PID=$($P.Id) log=$CLog"
    return $P
}
function Wait-H22Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $D = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $D) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}
function Get-H22Events([string]$Path) {
    $Out = @()
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') { $Out += ($Matches[1] | ConvertFrom-Json) }
    }
    return @($Out)
}

$A = $null; $B1 = $null; $B2 = $null; $C = $null; $Exit = 1
try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H22PortFree $Port)) { throw "UDP port $Port is already in use." }
    }
    Write-H22Log "SM0-H2.2 start HEAD=$Head handoffs=$Handoffs profile=$CrashProfile"
    $A = Start-H22Godot "server-a" $ALog @(
        "--authority-id=authority/sm0/a","--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580","--control-port=24680","--peer-control-port=24681","--stop-file=$StopFile"
    )
    $B1 = Start-H22Godot "server-b-commit-crash-target" $B1Log @(
        "--authority-id=authority/sm0/b","--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581","--control-port=24681","--peer-control-port=24680","--stop-file=$StopFile",
        "--fault-profile=$CrashProfile","--recovery-dir=$RecoveryRoot"
    )
    $State = [ordered]@{
        schema="distributed_world_simulator.sm0_h22_launcher_state.v1"; project_root=$ProjectRoot; git_head=$Head;
        log_directory=$LogDir; recovery_directory=$RecoveryRoot;
        processes=@([ordered]@{role="server-a";pid=$A.Id},[ordered]@{role="server-b-commit-crash-target";pid=$B1.Id})
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H22Marker $ALog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A 20
    Wait-H22Marker $B1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B1 20
    Wait-H22Marker $B1Log '"event":"SM0_RECOVERY_ENABLED"' $B1 20
    Wait-H22Marker $B1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $B1 20

    $C = Start-H22Client @(
        "--server-host=127.0.0.1","--server-a-port=24580","--server-b-port=24581","--client-port=24780",
        "--handoffs=$Handoffs","--timeout-ms=$($TimeoutSeconds*1000)","--result-file=$CResult"
    )
    $State.processes += [ordered]@{role="client";pid=$C.Id}
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H22Marker $B1Log '"crash_point":"TARGET_AFTER_COMMIT_PERSIST_BEFORE_ACK"' $B1 30
    $E1BeforeCrash = @(Get-H22Events $B1Log)
    $CrashBeforeKill = @($E1BeforeCrash | Where-Object { $_.event -eq "SM0_H2_CRASH_POINT" -and $_.crash_point -eq "TARGET_AFTER_COMMIT_PERSIST_BEFORE_ACK" })
    if ($CrashBeforeKill.Count -ne 1) { throw "Expected one H2.2 crash point before kill, got $($CrashBeforeKill.Count)." }
    $CrashTransfer = [string]$CrashBeforeKill[0].transfer_id
    $CrashGeneration = [int]$CrashBeforeKill[0].recovery_generation
    $PersistBeforeKill = @($E1BeforeCrash | Where-Object { $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "TARGET_COMMITTED" -and [string]$_.transfer_id -eq $CrashTransfer })
    if ($PersistBeforeKill.Count -ne 1) { throw "Target commit was not durably persisted before crash marker." }
    if ([int]$PersistBeforeKill[0].generation -ne $CrashGeneration) { throw "Crash marker recovery generation does not match persisted generation." }
    if (@($E1BeforeCrash | Where-Object { $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -ne 1) { throw "Target commit decision missing before crash." }
    if (@($E1BeforeCrash | Where-Object { $_.event -eq "SM0_TARGET_ACTIVATED" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -ne 0) { throw "Target activated client before deterministic crash." }

    $SnapshotPath = Join-Path (Join-Path $RecoveryRoot "authority-b") ("recovery-{0:d8}.json" -f $CrashGeneration)
    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw "Persisted recovery snapshot is missing: $SnapshotPath" }
    $Snapshot = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
    if ($Snapshot.schema -ne "distributed_world_simulator.sm0_handoff_recovery_snapshot.v1" -or $Snapshot.phase -ne "TARGET_COMMITTED" -or [string]$Snapshot.transfer_id -ne $CrashTransfer) {
        throw "Persisted recovery snapshot does not describe the crash transfer."
    }

    $CrashPid = $B1.Id
    Write-H22Log "Durable commit crash point observed generation=$CrashGeneration transfer=$CrashTransfer; force-killing target PID=$CrashPid"
    Stop-Process -Id $CrashPid -Force -ErrorAction Stop
    try { $B1.WaitForExit(5000) } catch {}
    if (Test-H22Alive $CrashPid) { throw "Target PID=$CrashPid survived forced crash." }
    Wait-H22Ports @(24581,24681)

    $B2 = Start-H22Godot "server-b-recovered" $B2Log @(
        "--authority-id=authority/sm0/b","--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581","--control-port=24681","--peer-control-port=24680","--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot"
    )
    $State.processes += [ordered]@{role="server-b-recovered";pid=$B2.Id}
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    Wait-H22Marker $B2Log '"event":"SM0_RECOVERY_RESTORED"' $B2 20
    Wait-H22Marker $B2Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B2 20
    Write-H22Log "Restarted target restored durable commit; waiting for client/source convergence."

    $D = (Get-Date).AddSeconds($TimeoutSeconds + 10)
    while (-not $C.HasExited -and (Get-Date) -lt $D) {
        Start-Sleep -Milliseconds 50
        $C.Refresh(); $A.Refresh(); $B2.Refresh()
        if ($A.HasExited -or $B2.HasExited) { throw "Authority process exited after durable target restart." }
    }
    if (-not $C.HasExited) { throw "Client timed out after durable target restart." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($S in @($A,$B2)) {
        $D=(Get-Date).AddSeconds(10)
        while (-not $S.HasExited -and (Get-Date)-lt $D) { Start-Sleep -Milliseconds 50; $S.Refresh() }
        if (-not $S.HasExited) { Stop-Process -Id $S.Id -Force -ErrorAction SilentlyContinue }
    }

    @((Get-Content -LiteralPath $B1Log),(Get-Content -LiteralPath $B2Log)) | Set-Content -LiteralPath $BLog -Encoding UTF8
    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) { throw "Base SM0 convergence failed after durable commit crash/restart." }

    $EA = @(Get-H22Events $ALog); $E1 = @(Get-H22Events $B1Log); $E2 = @(Get-H22Events $B2Log)
    $Restored = @($E2 | Where-Object { $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "TARGET_COMMITTED" -and [string]$_.transfer_id -eq $CrashTransfer })
    if ($Restored.Count -ne 1 -or [int]$Restored[0].generation -ne $CrashGeneration) { throw "Restarted target did not restore exact committed generation." }
    if (@($E2 | Where-Object { $_.event -eq "SM0_RECOVERY_SESSION_REBOUND" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -lt 1) { throw "Recovered target did not rebind committed client session." }
    if (@($E2 | Where-Object { $_.event -eq "SM0_TARGET_ACTIVATED" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -lt 1) { throw "Recovered target did not activate crash transfer." }
    foreach ($EventName in @("SM0_SOURCE_RETIRED","SM0_SOURCE_TRANSFER_COMPLETE")) {
        if (@($EA | Where-Object { $_.event -eq $EventName -and [string]$_.transfer_id -eq $CrashTransfer }).Count -lt 1) { throw "Source missing $EventName for $CrashTransfer" }
    }
    if (@($EA + $E1 + $E2 | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) { throw "Invariant violation observed in H2.2 logs." }

    $R = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($R.result -ne "PASS" -or [int]$R.handoffs_completed -ne $Handoffs -or [int]$R.identity_changes -ne 0) { throw "Client durable recovery evidence failed." }

    [ordered]@{
        schema="distributed_world_simulator.sm0_h22_durable_commit_summary.v1"; result="PASS"; git_head=$Head;
        crash_point="TARGET_AFTER_COMMIT_PERSIST_BEFORE_ACK"; crash_transfer_id=$CrashTransfer; recovery_generation=$CrashGeneration;
        crashed_target_pid=$CrashPid; restarted_target_pid=$B2.Id; handoffs_completed=[int]$R.handoffs_completed;
        identity_changes=[int]$R.identity_changes; authority_epoch_end=[int]$R.authority_epoch_end;
        recovery_snapshot=$SnapshotPath; logs=$LogDir
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H2.2 durable target commit recovery: PASS" -ForegroundColor Green
    Write-Host "  crashed PID        : $CrashPid"
    Write-Host "  restarted PID      : $($B2.Id)"
    Write-Host "  recovered transfer : $CrashTransfer"
    Write-Host "  recovery generation: $CrashGeneration"
    Write-Host "  handoffs           : $Handoffs / $Handoffs"
    Write-Host "  identity changes   : 0"
    Write-Host "  snapshot           : $SnapshotPath"
    Write-Host "  logs               : $LogDir"
    Write-Host "  summary            : $SummaryPath"
    $Exit = 0
}
catch {
    Write-Error "SM0-H2.2 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $Exit = 1
}
finally {
    foreach ($P in @($C,$A,$B1,$B2)) {
        if ($null -ne $P) {
            try { $P.Refresh(); if (-not $P.HasExited) { Stop-Process -Id $P.Id -Force -ErrorAction SilentlyContinue } } catch {}
        }
    }
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    $UidAfter = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
    if ($LASTEXITCODE -eq 0) {
        foreach ($RelativeUid in $UidAfter) {
            $RelativeUidText = [string]$RelativeUid
            if (-not $UidBeforeSet.ContainsKey($RelativeUidText)) {
                $GeneratedPath = Join-Path $ProjectRoot $RelativeUidText
                if (Test-Path -LiteralPath $GeneratedPath -PathType Leaf) {
                    Remove-Item -LiteralPath $GeneratedPath -Force -ErrorAction SilentlyContinue
                    Write-Host "[SM0-H2.2] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H2.2 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
