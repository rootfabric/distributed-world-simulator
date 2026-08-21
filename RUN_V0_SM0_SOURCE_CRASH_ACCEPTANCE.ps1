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
$CrashProfile = "h2-source-crash-after-retire-persist-v1"
if ($Final) { $Handoffs = 6; if ($TimeoutSeconds -lt 180) { $TimeoutSeconds = 180 } }
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) { throw "SM0-H2.3 must run under C:\distributed-world-simulator. Current: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot double console executable not found: $GodotExe" }

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH23"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H23Alive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}
function Stop-H23 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $S = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($R in @($S.processes)) {
                if (Test-H23Alive ([int]$R.pid)) { Stop-Process -Id ([int]$R.pid) -Force -ErrorAction SilentlyContinue }
            }
        } catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}
if ($Stop) { Stop-H23; exit 0 }
if ($Restart) { Stop-H23 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "SM0-H2.3 requires a clean worktree:`n$($StatusBefore -join "`n")" }
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()

$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate pre-existing UID sidecars." }
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) { $UidBeforeSet[[string]$RelativeUid] = $true }

$BaseRunner = Join-Path $ProjectRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
$Preflight = @{ Handoffs = 2; Restart = $true; ProjectRoot = $ProjectRoot; GodotExe = $GodotExe; TimeoutSeconds = 120 }
if ($AllowDirty) { $Preflight.AllowDirty = $true }
Write-Host "[SM0-H2.3] Running healthy preflight before durable source-retire crash injection..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H2.3 healthy preflight failed." }

function Invoke-H23CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H2.3] Compile check: $ScriptPath"
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        $Code = $LASTEXITCODE
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($Code -ne 0) { throw "SM0-H2.3 compile check failed: $ScriptPath (exit $Code)" }
}
foreach ($ScriptPath in @(
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_source_retire_recovery.gd"
)) { Invoke-H23CompileCheck $ScriptPath }

Write-Host "[SM0-H2.3] Running source-retire durable restore regression..."
$OldRegression = $env:BREAKPOINT_RUNTIME_DISABLED; $HadRegression = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotExe --headless --path $ProjectRoot --script "res://tests/runtime/seamless/sm0/test_sm0_source_retire_recovery.gd"
    $RegressionCode = $LASTEXITCODE
}
finally {
    if ($HadRegression) { $env:BREAKPOINT_RUNTIME_DISABLED = $OldRegression } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
if ($RegressionCode -ne 0) { throw "SM0-H2.3 source-retire recovery regression failed (exit $RegressionCode)." }

function Test-H23PortFree([int]$Port) {
    $U = $null
    try {
        $U = [System.Net.Sockets.UdpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $U.Client.ExclusiveAddressUse = $true
        $U.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        return $true
    } catch { return $false } finally { if ($null -ne $U) { $U.Dispose() } }
}
function Wait-H23Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $Deadline) {
        $Ok = $true
        foreach ($Port in $Ports) { if (-not (Test-H23PortFree $Port)) { $Ok = $false; break } }
        if ($Ok) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}
function Quote-H23([string]$Value) { return '"' + $Value + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
$RecoveryRoot = Join-Path $LogDir "recovery"
New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
$HarnessLog = Join-Path $LogDir "harness.log"
$A1Log = Join-Path $LogDir "server-a-crashed.log"
$A2Log = Join-Path $LogDir "server-a-restarted.log"
$ALog = Join-Path $LogDir "server-a.log"
$BLog = Join-Path $LogDir "server-b.log"
$CLog = Join-Path $LogDir "client.log"
$CResult = Join-Path $LogDir "client-result.json"
$StopFile = Join-Path $LogDir "stop.flag"
$SummaryPath = Join-Path $LogDir "h23-summary.json"
function Write-H23Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H23Godot([string]$Role, [string]$Log, [string[]]$UserArgs) {
    $Args = @("--headless", "--path", (Quote-H23 $ProjectRoot), "--log-file", (Quote-H23 $Log), "--script", "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd", "--") + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try { $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru }
    finally { if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } }
    Write-H23Log "$Role started PID=$($Process.Id) log=$Log"
    return $Process
}
function Start-H23Client([string[]]$UserArgs) {
    $Args = @("--headless", "--path", (Quote-H23 $ProjectRoot), "--log-file", (Quote-H23 $CLog), "--script", "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd", "--") + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try { $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru }
    finally { if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } }
    Write-H23Log "client started PID=$($Process.Id) log=$CLog"
    return $Process
}
function Wait-H23Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}
function Get-H23Events([string]$Path) {
    $Out = @()
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') { $Out += ($Matches[1] | ConvertFrom-Json) }
    }
    return @($Out)
}

$A1 = $null; $A2 = $null; $B = $null; $C = $null; $Exit = 1
try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H23PortFree $Port)) { throw "UDP port $Port is already in use." }
    }
    Write-H23Log "SM0-H2.3 start HEAD=$Head handoffs=$Handoffs profile=$CrashProfile"
    $A1 = Start-H23Godot "server-a-retire-crash-source" $A1Log @(
        "--authority-id=authority/sm0/a","--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580","--control-port=24680","--peer-control-port=24681","--stop-file=$StopFile",
        "--fault-profile=$CrashProfile","--recovery-dir=$RecoveryRoot"
    )
    $B = Start-H23Godot "server-b" $BLog @(
        "--authority-id=authority/sm0/b","--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581","--control-port=24681","--peer-control-port=24680","--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot"
    )
    $State = [ordered]@{
        schema="distributed_world_simulator.sm0_h23_launcher_state.v1"; project_root=$ProjectRoot; git_head=$Head;
        log_directory=$LogDir; recovery_directory=$RecoveryRoot;
        processes=@([ordered]@{role="server-a-retire-crash-source";pid=$A1.Id},[ordered]@{role="server-b";pid=$B.Id})
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H23Marker $A1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A1 20
    Wait-H23Marker $BLog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B 20
    Wait-H23Marker $A1Log '"event":"SM0_RECOVERY_ENABLED"' $A1 20
    Wait-H23Marker $BLog '"event":"SM0_RECOVERY_ENABLED"' $B 20
    Wait-H23Marker $A1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $A1 20

    $C = Start-H23Client @(
        "--server-host=127.0.0.1","--server-a-port=24580","--server-b-port=24581","--client-port=24780",
        "--handoffs=$Handoffs","--timeout-ms=$($TimeoutSeconds*1000)","--result-file=$CResult"
    )
    $State.processes += [ordered]@{role="client";pid=$C.Id}
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H23Marker $A1Log '"crash_point":"SOURCE_AFTER_RETIRE_PERSIST_BEFORE_COMMIT"' $A1 30
    $A1BeforeCrash = @(Get-H23Events $A1Log)
    $BBeforeCrash = @(Get-H23Events $BLog)
    $Crash = @($A1BeforeCrash | Where-Object { $_.event -eq "SM0_H2_CRASH_POINT" -and $_.crash_point -eq "SOURCE_AFTER_RETIRE_PERSIST_BEFORE_COMMIT" })
    if ($Crash.Count -ne 1) { throw "Expected one H2.3 crash point before kill, got $($Crash.Count)." }
    $CrashTransfer = [string]$Crash[0].transfer_id
    $CrashGeneration = [int]$Crash[0].recovery_generation
    $Persisted = @($A1BeforeCrash | Where-Object { $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "SOURCE_RETIRED" -and [string]$_.transfer_id -eq $CrashTransfer })
    if ($Persisted.Count -ne 1 -or [int]$Persisted[0].generation -ne $CrashGeneration) { throw "Source retirement was not durably persisted at crash generation." }
    if (@($A1BeforeCrash | Where-Object { $_.event -eq "SM0_SOURCE_RETIRED" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -ne 1) { throw "Source retirement event missing before crash." }
    foreach ($MessageType in @("PLAYER_HANDOFF_COMMIT","HANDOFF_REDIRECT")) {
        if (@($A1BeforeCrash | Where-Object { $_.event -eq "SM0_H2_SOURCE_SEND_SUPPRESSED" -and $_.message_type -eq $MessageType -and [string]$_.transfer_id -eq $CrashTransfer }).Count -ne 1) { throw "Expected deterministic suppression for $MessageType before source crash." }
    }
    if (@($BBeforeCrash | Where-Object { $_.event -eq "SM0_HANDOFF_PREPARED" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -lt 1) { throw "Target did not prepare crash transfer before source retirement." }
    if (@($BBeforeCrash | Where-Object { $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -ne 0) { throw "Target committed before deterministic source crash; COMMIT suppression failed." }
    if (@($A1BeforeCrash | Where-Object { $_.event -eq "SM0_SOURCE_TRANSFER_COMPLETE" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -ne 0) { throw "Source transfer completed before deterministic crash." }

    $SnapshotPath = Join-Path (Join-Path $RecoveryRoot "authority-a") ("recovery-{0:d8}.json" -f $CrashGeneration)
    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw "Persisted source recovery snapshot is missing: $SnapshotPath" }
    $Snapshot = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
    if ($Snapshot.schema -ne "distributed_world_simulator.sm0_handoff_recovery_snapshot.v1" -or $Snapshot.phase -ne "SOURCE_RETIRED" -or [string]$Snapshot.transfer_id -ne $CrashTransfer) { throw "Persisted source snapshot does not describe the crash transfer." }
    if ([string]$Snapshot.source_transfer.transfer_id -ne $CrashTransfer -or [string]$Snapshot.source_transfer.stage -ne "COMMIT_SENT") { throw "Persisted source transfer tracking is incomplete." }
    if ([string]$Snapshot.directory.owner_authority_id -ne "authority/sm0/b") { throw "Persisted retired source directory does not point to target." }
    $DurablePlayers = @($Snapshot.gameplay_state.players.players)
    $DurablePlayer = @($DurablePlayers | Where-Object { [string]$_.logical_player_id -eq "a" })
    if ($DurablePlayer.Count -ne 1 -or [bool]$DurablePlayer[0].connected -or -not [string]::IsNullOrEmpty([string]$DurablePlayer[0].transport_session_id)) { throw "Persisted canonical source player is not durably retired." }

    $CrashPid = $A1.Id
    Write-H23Log "Durable source-retire crash point observed generation=$CrashGeneration transfer=$CrashTransfer; force-killing source PID=$CrashPid"
    Stop-Process -Id $CrashPid -Force -ErrorAction Stop
    try { $A1.WaitForExit(5000) } catch {}
    if (Test-H23Alive $CrashPid) { throw "Source PID=$CrashPid survived forced crash." }
    Wait-H23Ports @(24580,24680)

    $A2 = Start-H23Godot "server-a-recovered" $A2Log @(
        "--authority-id=authority/sm0/a","--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580","--control-port=24680","--peer-control-port=24681","--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot"
    )
    if ($A2.Id -eq $CrashPid) { throw "Recovered source unexpectedly reused crashed PID." }
    $State.processes += [ordered]@{role="server-a-recovered";pid=$A2.Id}
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    Wait-H23Marker $A2Log '"event":"SM0_RECOVERY_RESTORED"' $A2 20
    Wait-H23Marker $A2Log '"event":"SM0_RECOVERY_SOURCE_TRANSFER_RESUMED"' $A2 20
    Wait-H23Marker $A2Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A2 20
    Write-H23Log "Restarted source restored retired transfer and resumed COMMIT/redirect; waiting for convergence."

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds + 10)
    while (-not $C.HasExited -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 50
        $C.Refresh(); $A2.Refresh(); $B.Refresh()
        if ($A2.HasExited -or $B.HasExited) { throw "Authority process exited after durable source restart." }
    }
    if (-not $C.HasExited) { throw "Client timed out after durable source restart." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($ServerProcess in @($A2,$B)) {
        $Deadline=(Get-Date).AddSeconds(10)
        while (-not $ServerProcess.HasExited -and (Get-Date)-lt $Deadline) { Start-Sleep -Milliseconds 50; $ServerProcess.Refresh() }
        if (-not $ServerProcess.HasExited) { Stop-Process -Id $ServerProcess.Id -Force -ErrorAction SilentlyContinue }
    }

    @((Get-Content -LiteralPath $A1Log),(Get-Content -LiteralPath $A2Log)) | Set-Content -LiteralPath $ALog -Encoding UTF8
    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) { throw "Base SM0 convergence failed after durable source crash/restart." }

    $E1 = @(Get-H23Events $A1Log); $E2 = @(Get-H23Events $A2Log); $EB = @(Get-H23Events $BLog)
    $Restored = @($E2 | Where-Object { $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "SOURCE_RETIRED" -and [string]$_.transfer_id -eq $CrashTransfer })
    if ($Restored.Count -ne 1 -or [int]$Restored[0].generation -ne $CrashGeneration) { throw "Restarted source did not restore exact SOURCE_RETIRED generation." }
    if ([int]$Restored[0].writer_count -ne 0) { throw "Recovered retired source became a writer during restore." }
    $Resumed = @($E2 | Where-Object { $_.event -eq "SM0_RECOVERY_SOURCE_TRANSFER_RESUMED" -and [string]$_.transfer_id -eq $CrashTransfer })
    if ($Resumed.Count -ne 1 -or [int]$Resumed[0].writer_count -ne 0) { throw "Recovered source transfer did not resume as non-writer." }
    if (@($E2 | Where-Object { $_.event -eq "SM0_SOURCE_TRANSFER_COMPLETE" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -lt 1) { throw "Recovered source did not finish transfer tracking." }
    if (@($EB | Where-Object { $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -lt 1) { throw "Target did not commit recovered source transfer." }
    if (@($EB | Where-Object { $_.event -eq "SM0_TARGET_ACTIVATED" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -lt 1) { throw "Target did not activate recovered source transfer." }
    if (@($E2 | Where-Object { $_.event -eq "SM0_RECOVERY_SESSION_REBOUND" -and [string]$_.transfer_id -eq $CrashTransfer }).Count -ne 0) { throw "Retired source incorrectly rebound player session." }
    if (@($E1 + $E2 + $EB | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) { throw "Invariant violation observed in H2.3 logs." }

    $Result = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne $Handoffs -or [int]$Result.identity_changes -ne 0) { throw "Client source recovery evidence failed." }

    [ordered]@{
        schema="distributed_world_simulator.sm0_h23_durable_source_summary.v1"; result="PASS"; git_head=$Head;
        crash_point="SOURCE_AFTER_RETIRE_PERSIST_BEFORE_COMMIT"; crash_transfer_id=$CrashTransfer; recovery_generation=$CrashGeneration;
        crashed_source_pid=$CrashPid; restarted_source_pid=$A2.Id; handoffs_completed=[int]$Result.handoffs_completed;
        identity_changes=[int]$Result.identity_changes; authority_epoch_end=[int]$Result.authority_epoch_end;
        recovery_snapshot=$SnapshotPath; logs=$LogDir
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H2.3 durable source retirement recovery: PASS" -ForegroundColor Green
    Write-Host "  crashed PID        : $CrashPid"
    Write-Host "  restarted PID      : $($A2.Id)"
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
    Write-Error "SM0-H2.3 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $Exit = 1
}
finally {
    foreach ($Process in @($C,$A1,$A2,$B)) {
        if ($null -ne $Process) {
            try { $Process.Refresh(); if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } } catch {}
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
                    Write-Host "[SM0-H2.3] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H2.3 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
