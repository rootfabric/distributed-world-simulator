[CmdletBinding()]
param(
    [ValidateRange(1, 2)][int]$Chains = 1,
    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(90, 900)][int]$TimeoutSeconds = 420
)

$ErrorActionPreference = "Stop"
$FaultProfile = "h4-recovery-of-recovery-same-transfer-v1"
if ($Final) {
    $Chains = 2
    if ($TimeoutSeconds -lt 600) { $TimeoutSeconds = 600 }
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0-H4.3 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot double console executable not found: $GodotExe"
}

$ExpectedHandoffs = $Chains
$ExpectedOutages = $Chains * 3
$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH43"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H43Alive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Stop-H43 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($Record in @($State.processes)) {
                if (Test-H43Alive ([int]$Record.pid)) {
                    Stop-Process -Id ([int]$Record.pid) -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}

if ($Stop) { Stop-H43; exit 0 }
if ($Restart) { Stop-H43 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-H4.3 requires a clean worktree:`n$($StatusBefore -join "`n")"
}
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()

$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate pre-existing UID sidecars." }
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) { $UidBeforeSet[[string]$RelativeUid] = $true }

$BaseRunner = Join-Path $ProjectRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
$Preflight = @{
    Handoffs = 2
    Restart = $true
    ProjectRoot = $ProjectRoot
    GodotExe = $GodotExe
    TimeoutSeconds = 120
}
if ($AllowDirty) { $Preflight.AllowDirty = $true }
Write-Host "[SM0-H4.3] Running healthy preflight before recovery-of-recovery outages..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H4.3 healthy preflight failed." }

function Invoke-H43CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H4.3] Compile check: $ScriptPath"
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED
    $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        $Code = $LASTEXITCODE
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($Code -ne 0) { throw "SM0-H4.3 compile check failed: $ScriptPath (exit $Code)" }
}

foreach ($ScriptPath in @(
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_recovery.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_chain_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_target_prepare_recovery.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_source_retire_recovery.gd"
)) { Invoke-H43CompileCheck $ScriptPath }

function Invoke-H43Regression([string]$Label, [string]$ScriptPath) {
    Write-Host "[SM0-H4.3] Running $Label..."
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED
    $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe --headless --path $ProjectRoot --script $ScriptPath
        $Code = $LASTEXITCODE
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($Code -ne 0) { throw "SM0-H4.3 regression failed: $Label (exit $Code)" }
}

Invoke-H43Regression "transaction recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_target_prepare_recovery.gd"
Invoke-H43Regression "active-owner recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
Invoke-H43Regression "source-retire recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_source_retire_recovery.gd"

function Test-H43PortFree([int]$Port) {
    $Udp = $null
    try {
        $Udp = [System.Net.Sockets.UdpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $Udp.Client.ExclusiveAddressUse = $true
        $Udp.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        return $true
    }
    catch { return $false }
    finally { if ($null -ne $Udp) { $Udp.Dispose() } }
}

function Wait-H43Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $Deadline) {
        $AllFree = $true
        foreach ($Port in $Ports) {
            if (-not (Test-H43PortFree $Port)) { $AllFree = $false; break }
        }
        if ($AllFree) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}

function Quote-H43([string]$Value) { return '"' + $Value + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
$RecoveryRoot = Join-Path $LogDir "recovery"
New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
$HarnessLog = Join-Path $LogDir "harness.log"
$ALog = Join-Path $LogDir "server-a.log"
$BLog = Join-Path $LogDir "server-b.log"
$CLog = Join-Path $LogDir "client.log"
$CResult = Join-Path $LogDir "client-result.json"
$StopFile = Join-Path $LogDir "stop.flag"
$SummaryPath = Join-Path $LogDir "h43-summary.json"

function Write-H43Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H43Server([string]$AuthorityLetter, [string]$Role, [string]$Log) {
    if ($AuthorityLetter -eq "A") {
        $AuthorityId = "authority/sm0/a"; $ZoneId = "zone/earth/sm0/west"
        $GameplayPort = 24580; $ControlPort = 24680; $PeerControlPort = 24681
    }
    elseif ($AuthorityLetter -eq "B") {
        $AuthorityId = "authority/sm0/b"; $ZoneId = "zone/earth/sm0/east"
        $GameplayPort = 24581; $ControlPort = 24681; $PeerControlPort = 24680
    }
    else { throw "Unknown authority letter: $AuthorityLetter" }

    $UserArgs = @(
        "--authority-id=$AuthorityId", "--zone-id=$ZoneId",
        "--gameplay-port=$GameplayPort", "--control-port=$ControlPort", "--peer-control-port=$PeerControlPort",
        "--stop-file=$StopFile", "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot"
    )
    $Args = @(
        "--headless", "--path", (Quote-H43 $ProjectRoot),
        "--log-file", (Quote-H43 $Log),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd", "--"
    ) + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED
    $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    Write-H43Log "$Role started PID=$($Process.Id) log=$Log"
    return $Process
}

function Start-H43Client {
    $UserArgs = @(
        "--server-host=127.0.0.1", "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780",
        "--handoffs=$ExpectedHandoffs", "--timeout-ms=$($TimeoutSeconds*1000)", "--result-file=$CResult"
    )
    $Args = @(
        "--headless", "--path", (Quote-H43 $ProjectRoot),
        "--log-file", (Quote-H43 $CLog),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd", "--"
    ) + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED
    $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    Write-H43Log "client started PID=$($Process.Id) log=$CLog"
    return $Process
}

function Wait-H43Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}

function Get-H43Events([string]$Path) {
    $Events = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Events }
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') { $Events += ($Matches[1] | ConvertFrom-Json) }
    }
    return $Events
}

function Get-H43Crossings {
    return @(Get-H43Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
}

function Wait-H43CrossingCount([int]$Expected, [System.Diagnostics.Process]$Client, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Count = @(Get-H43Crossings).Count
        if ($Count -ge $Expected) { return }
        $Client.Refresh()
        if ($Client.HasExited -and $Count -lt $Expected) { throw "Client exited before crossing count $Expected; observed $Count." }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for crossing count $Expected."
}

function Get-H43Snapshot([string]$AuthorityLeaf, [int]$Generation) {
    $Path = Join-Path (Join-Path $RecoveryRoot $AuthorityLeaf) ("recovery-{0:d8}.json" -f $Generation)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Recovery snapshot is missing: $Path" }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Save-H43State([System.Diagnostics.Process]$A, [System.Diagnostics.Process]$B, [System.Diagnostics.Process]$Client) {
    $Processes = @()
    if ($null -ne $A) { $Processes += [ordered]@{ role = "server-a"; pid = $A.Id } }
    if ($null -ne $B) { $Processes += [ordered]@{ role = "server-b"; pid = $B.Id } }
    if ($null -ne $Client) { $Processes += [ordered]@{ role = "client"; pid = $Client.Id } }
    [ordered]@{
        schema = "distributed_world_simulator.sm0_h43_launcher_state.v1"
        project_root = $ProjectRoot
        git_head = $Head
        log_directory = $LogDir
        recovery_directory = $RecoveryRoot
        processes = $Processes
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Stop-H43AuthorityPair(
    [System.Diagnostics.Process]$AProcess,
    [System.Diagnostics.Process]$BProcess,
    [System.Diagnostics.Process]$Client,
    [int]$Chain,
    [string]$Stage
) {
    $OldAPid = $AProcess.Id
    $OldBPid = $BProcess.Id
    $FirstKillMs = [Environment]::TickCount64
    Stop-Process -Id $AProcess.Id -Force -ErrorAction Stop
    $SecondKillMs = [Environment]::TickCount64
    Stop-Process -Id $BProcess.Id -Force -ErrorAction Stop
    $Gap = [Math]::Abs([long]$SecondKillMs - [long]$FirstKillMs)
    if ($Gap -gt 500) { throw "Chain $Chain stage $Stage kill request gap exceeded 500 ms: $Gap" }
    try { $null = $AProcess.WaitForExit(5000) } catch {}
    try { $null = $BProcess.WaitForExit(5000) } catch {}
    if ((Test-H43Alive $OldAPid) -or (Test-H43Alive $OldBPid)) { throw "Chain $Chain stage $Stage at least one authority survived total outage." }
    $Client.Refresh()
    if ($Client.HasExited) { throw "Chain $Chain stage $Stage client exited during zero-authority interval." }
    Wait-H43Ports @(24580,24581,24680,24681)
    return [ordered]@{ old_a_pid = $OldAPid; old_b_pid = $OldBPid; gap_ms = $Gap }
}

function Start-H43RecoveredPair([int]$Segment, [string]$TargetLetter, [string]$StageLabel) {
    $NewALog = Join-Path $LogDir ("server-a-segment{0:d2}.log" -f $Segment)
    $NewBLog = Join-Path $LogDir ("server-b-segment{0:d2}.log" -f $Segment)
    if ($TargetLetter -eq "A") {
        $NewA = Start-H43Server "A" "server-a-$StageLabel-target" $NewALog
        $NewB = Start-H43Server "B" "server-b-$StageLabel-source" $NewBLog
    }
    else {
        $NewB = Start-H43Server "B" "server-b-$StageLabel-target" $NewBLog
        $NewA = Start-H43Server "A" "server-a-$StageLabel-source" $NewALog
    }
    return [ordered]@{ a = $NewA; b = $NewB; a_log = $NewALog; b_log = $NewBLog }
}

$A = $null; $B = $null; $C = $null; $Exit = 1
$ASegmentLogs = [System.Collections.Generic.List[string]]::new()
$BSegmentLogs = [System.Collections.Generic.List[string]]::new()
$ChainEvidence = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H43PortFree $Port)) { throw "UDP port $Port is already in use." }
    }

    Write-H43Log "SM0-H4.3 start HEAD=$Head chains=$Chains outages=$ExpectedOutages profile=$FaultProfile stages=PREPARED,COMMITTED,ACTIVE"

    $CurrentALog = Join-Path $LogDir "server-a-segment00.log"
    $CurrentBLog = Join-Path $LogDir "server-b-segment00.log"
    $A = Start-H43Server "A" "server-a-initial" $CurrentALog
    $B = Start-H43Server "B" "server-b-initial" $CurrentBLog
    $ASegmentLogs.Add($CurrentALog)
    $BSegmentLogs.Add($CurrentBLog)
    Save-H43State $A $B $null

    Wait-H43Marker $CurrentALog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A 20
    Wait-H43Marker $CurrentBLog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B 20
    Wait-H43Marker $CurrentALog '"event":"SM0_RECOVERY_ENABLED"' $A 20
    Wait-H43Marker $CurrentBLog '"event":"SM0_RECOVERY_ENABLED"' $B 20
    Wait-H43Marker $CurrentALog '"event":"SM0_H43_PROFILE_ENABLED"' $A 20
    Wait-H43Marker $CurrentBLog '"event":"SM0_H43_PROFILE_ENABLED"' $B 20

    $C = Start-H43Client
    $ClientPid = $C.Id
    Save-H43State $A $B $C
    $Segment = 0
    $SeenTransfers = @{}

    for ($Chain = 1; $Chain -le $Chains; $Chain++) {
        $TargetLetter = if (($Chain % 2) -eq 1) { "B" } else { "A" }
        $SourceLetter = if ($TargetLetter -eq "B") { "A" } else { "B" }
        $TargetAuthorityId = if ($TargetLetter -eq "B") { "authority/sm0/b" } else { "authority/sm0/a" }
        $SourceAuthorityId = if ($SourceLetter -eq "A") { "authority/sm0/a" } else { "authority/sm0/b" }
        $TargetLeaf = if ($TargetLetter -eq "A") { "authority-a" } else { "authority-b" }
        $SourceLeaf = if ($SourceLetter -eq "A") { "authority-a" } else { "authority-b" }
        $TargetEpoch = $Chain + 1

        $TargetProcess = if ($TargetLetter -eq "A") { $A } else { $B }
        $SourceProcess = if ($SourceLetter -eq "A") { $A } else { $B }
        $TargetLog = if ($TargetLetter -eq "A") { $CurrentALog } else { $CurrentBLog }
        $SourceLog = if ($SourceLetter -eq "A") { $CurrentALog } else { $CurrentBLog }

        # ------------------------------------------------------------
        # Stage 1: exact T is retired at source and prepared at target,
        # while both COMMIT and redirect remain suppressed.
        # ------------------------------------------------------------
        Wait-H43Marker $SourceLog '"event":"SM0_H43_CRASH_POINT","severity":"INFO"' $SourceProcess 50
        Wait-H43Marker $SourceLog '"stage":"PREPARED"' $SourceProcess 20
        Wait-H43Marker $SourceLog '"message_type":"PLAYER_HANDOFF_COMMIT"' $SourceProcess 20
        Wait-H43Marker $SourceLog '"message_type":"HANDOFF_REDIRECT"' $SourceProcess 20
        Wait-H43Marker $TargetLog '"event":"SM0_TARGET_PREPARED_DURABLE"' $TargetProcess 20

        $SourceEvents = @(Get-H43Events $SourceLog)
        $TargetEvents = @(Get-H43Events $TargetLog)
        $PreparedCrashEvents = @($SourceEvents | Where-Object { $_.event -eq "SM0_H43_CRASH_POINT" -and [string]$_.stage -eq "PREPARED" })
        if ($PreparedCrashEvents.Count -lt 1) { throw "Chain $Chain PREPARED crash evidence missing." }
        $PreparedCrash = $PreparedCrashEvents[-1]
        $TransferId = [string]$PreparedCrash.transfer_id
        if ([string]::IsNullOrWhiteSpace($TransferId)) { throw "Chain $Chain PREPARED transfer id is empty." }
        if ($SeenTransfers.ContainsKey($TransferId)) { throw "Chain $Chain reused prior transfer id $TransferId." }
        $SeenTransfers[$TransferId] = $true

        if (@(Get-H43Crossings).Count -ne ($Chain - 1)) { throw "Chain $Chain crossed before PREPARED outage." }
        $PreparedSuppressedCommit = @($SourceEvents | Where-Object { $_.event -eq "SM0_H43_SEND_SUPPRESSED" -and $_.stage -eq "PREPARED" -and $_.message_type -eq "PLAYER_HANDOFF_COMMIT" -and [string]$_.transfer_id -eq $TransferId })
        $PreparedSuppressedRedirect = @($SourceEvents | Where-Object { $_.event -eq "SM0_H43_SEND_SUPPRESSED" -and $_.stage -eq "PREPARED" -and $_.message_type -eq "HANDOFF_REDIRECT" -and [string]$_.transfer_id -eq $TransferId })
        if ($PreparedSuppressedCommit.Count -ne 1 -or $PreparedSuppressedRedirect.Count -ne 1) { throw "Chain $Chain PREPARED suppression evidence is not exact-one." }
        if (@($TargetEvents | Where-Object { $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId }).Count -ne 0) { throw "Chain $Chain target committed before PREPARED outage." }

        $PreparedDurable = @($TargetEvents | Where-Object { $_.event -eq "SM0_TARGET_PREPARED_DURABLE" -and [string]$_.transfer_id -eq $TransferId })
        if ($PreparedDurable.Count -ne 1) { throw "Chain $Chain TARGET_PREPARED durability evidence missing." }
        $PreparedGeneration = [int]$PreparedDurable[0].generation
        $SourceRetired = @($SourceEvents | Where-Object { $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "SOURCE_RETIRED" -and [string]$_.transfer_id -eq $TransferId })
        if ($SourceRetired.Count -ne 1) { throw "Chain $Chain SOURCE_RETIRED durability evidence missing." }
        $SourceGeneration = [int]$SourceRetired[0].generation

        $PreparedSnapshot = Get-H43Snapshot $TargetLeaf $PreparedGeneration
        $SourceSnapshot = Get-H43Snapshot $SourceLeaf $SourceGeneration
        if ([string]$PreparedSnapshot.phase -ne "TARGET_PREPARED" -or [string]$PreparedSnapshot.transfer_id -ne $TransferId) { throw "Chain $Chain TARGET_PREPARED snapshot mismatch." }
        if ([string]$PreparedSnapshot.directory.owner_authority_id -ne $SourceAuthorityId) { throw "Chain $Chain prepared target directory must still name source." }
        if ($null -eq $PreparedSnapshot.prepared_transfers.PSObject.Properties[$TransferId]) { throw "Chain $Chain prepared snapshot lost T." }
        if ([string]$SourceSnapshot.phase -ne "SOURCE_RETIRED" -or [string]$SourceSnapshot.transfer_id -ne $TransferId) { throw "Chain $Chain SOURCE_RETIRED snapshot mismatch." }
        if ([string]$SourceSnapshot.directory.owner_authority_id -ne $TargetAuthorityId -or [int]$SourceSnapshot.directory.authority_epoch -ne $TargetEpoch) { throw "Chain $Chain source durable directory mismatch." }

        $KilledPrepared = Stop-H43AuthorityPair $A $B $C $Chain "PREPARED"
        Save-H43State $null $null $C
        Write-H43Log "Chain ${Chain}/${Chains} outage 1/3 PREPARED transfer=$TransferId target=$TargetLetter TARGET_PREPARED gen=$PreparedGeneration source=$SourceLetter SOURCE_RETIRED gen=$SourceGeneration oldA=$($KilledPrepared.old_a_pid) oldB=$($KilledPrepared.old_b_pid) gap=$($KilledPrepared.gap_ms)ms client=$ClientPid alive."

        $Segment++
        $Pair = Start-H43RecoveredPair $Segment $TargetLetter "chain$Chain-prepared-recovery"
        $A = $Pair.a; $B = $Pair.b; $CurrentALog = $Pair.a_log; $CurrentBLog = $Pair.b_log
        $ASegmentLogs.Add($CurrentALog); $BSegmentLogs.Add($CurrentBLog)
        Save-H43State $A $B $C
        $TargetProcess = if ($TargetLetter -eq "A") { $A } else { $B }
        $SourceProcess = if ($SourceLetter -eq "A") { $A } else { $B }
        $TargetLog = if ($TargetLetter -eq "A") { $CurrentALog } else { $CurrentBLog }
        $SourceLog = if ($SourceLetter -eq "A") { $CurrentALog } else { $CurrentBLog }
        Wait-H43Marker $TargetLog '"event":"SM0_RECOVERY_TARGET_PREPARED_PENDING"' $TargetProcess 25
        Wait-H43Marker $SourceLog '"event":"SM0_RECOVERY_SOURCE_IMMEDIATE_RESUME"' $SourceProcess 25

        # ------------------------------------------------------------
        # Stage 2: recovery of same T advances target to TARGET_COMMITTED,
        # then successful COMMITTED ACK is held before another total outage.
        # ------------------------------------------------------------
        Wait-H43Marker $TargetLog '"event":"SM0_H43_CRASH_POINT","severity":"INFO"' $TargetProcess 35
        Wait-H43Marker $TargetLog '"stage":"COMMITTED"' $TargetProcess 20
        Wait-H43Marker $TargetLog '"message_type":"PLAYER_HANDOFF_COMMITTED"' $TargetProcess 20
        $Stage2TargetEvents = @(Get-H43Events $TargetLog)
        $Stage2SourceEvents = @(Get-H43Events $SourceLog)
        $CommittedCrash = @($Stage2TargetEvents | Where-Object { $_.event -eq "SM0_H43_CRASH_POINT" -and $_.stage -eq "COMMITTED" -and [string]$_.transfer_id -eq $TransferId })
        if ($CommittedCrash.Count -ne 1) { throw "Chain $Chain COMMITTED crash evidence missing or duplicated." }
        $CommittedGeneration = [int]$CommittedCrash[0].recovery_generation
        if ($CommittedGeneration -le $PreparedGeneration) { throw "Chain $Chain target generation did not advance PREPARED -> COMMITTED." }
        $Stage2Suppressed = @($Stage2TargetEvents | Where-Object { $_.event -eq "SM0_H43_SEND_SUPPRESSED" -and $_.stage -eq "COMMITTED" -and $_.message_type -eq "PLAYER_HANDOFF_COMMITTED" -and [string]$_.transfer_id -eq $TransferId })
        if ($Stage2Suppressed.Count -ne 1) { throw "Chain $Chain COMMITTED suppression evidence is not exact-one." }
        $FreshCommits = @($Stage2TargetEvents | Where-Object { $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId })
        if ($FreshCommits.Count -ne 1) { throw "Chain $Chain expected exactly one canonical target commit while recovering PREPARED." }
        if (@(Get-H43Crossings).Count -ne ($Chain - 1)) { throw "Chain $Chain crossed before COMMITTED outage." }

        $CommittedSnapshot = Get-H43Snapshot $TargetLeaf $CommittedGeneration
        if ([string]$CommittedSnapshot.phase -ne "TARGET_COMMITTED" -or [string]$CommittedSnapshot.transfer_id -ne $TransferId) { throw "Chain $Chain TARGET_COMMITTED snapshot mismatch." }
        if ([string]$CommittedSnapshot.directory.owner_authority_id -ne $TargetAuthorityId -or [int]$CommittedSnapshot.directory.authority_epoch -ne $TargetEpoch) { throw "Chain $Chain TARGET_COMMITTED directory mismatch." }
        if ($null -eq $CommittedSnapshot.committed_transfers.PSObject.Properties[$TransferId]) { throw "Chain $Chain TARGET_COMMITTED snapshot lost T." }
        $RestoredSourceStage2 = @($Stage2SourceEvents | Where-Object { $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "SOURCE_RETIRED" -and [int]$_.generation -eq $SourceGeneration -and [string]$_.transfer_id -eq $TransferId })
        if ($RestoredSourceStage2.Count -ne 1 -or [int]$RestoredSourceStage2[0].writer_count -ne 0) { throw "Chain $Chain source did not restore exact retired non-writer state at Stage 2." }

        $KilledCommitted = Stop-H43AuthorityPair $A $B $C $Chain "COMMITTED"
        Save-H43State $null $null $C
        Write-H43Log "Chain ${Chain}/${Chains} outage 2/3 COMMITTED same-transfer=$TransferId target=$TargetLetter TARGET_COMMITTED gen=$CommittedGeneration source=$SourceLetter SOURCE_RETIRED gen=$SourceGeneration oldA=$($KilledCommitted.old_a_pid) oldB=$($KilledCommitted.old_b_pid) gap=$($KilledCommitted.gap_ms)ms client=$ClientPid alive."

        $Segment++
        $Pair = Start-H43RecoveredPair $Segment $TargetLetter "chain$Chain-committed-recovery"
        $A = $Pair.a; $B = $Pair.b; $CurrentALog = $Pair.a_log; $CurrentBLog = $Pair.b_log
        $ASegmentLogs.Add($CurrentALog); $BSegmentLogs.Add($CurrentBLog)
        Save-H43State $A $B $C
        $TargetProcess = if ($TargetLetter -eq "A") { $A } else { $B }
        $SourceProcess = if ($SourceLetter -eq "A") { $A } else { $B }
        $TargetLog = if ($TargetLetter -eq "A") { $CurrentALog } else { $CurrentBLog }
        $SourceLog = if ($SourceLetter -eq "A") { $CurrentALog } else { $CurrentBLog }
        Wait-H43Marker $TargetLog '"phase":"TARGET_COMMITTED"' $TargetProcess 25
        Wait-H43Marker $SourceLog '"event":"SM0_RECOVERY_SOURCE_IMMEDIATE_RESUME"' $SourceProcess 25

        # ------------------------------------------------------------
        # Stage 3: recovery of the same committed T reaches ACTIVE_OWNER,
        # persists before ACTIVATE_ACK, then both authorities die once more.
        # ------------------------------------------------------------
        Wait-H43Marker $TargetLog '"event":"SM0_H43_CRASH_POINT","severity":"INFO"' $TargetProcess 45
        Wait-H43Marker $TargetLog '"stage":"ACTIVE"' $TargetProcess 20
        Wait-H43Marker $TargetLog '"message_type":"ACTIVATE_ACK"' $TargetProcess 20
        $Stage3TargetEvents = @(Get-H43Events $TargetLog)
        $Stage3SourceEvents = @(Get-H43Events $SourceLog)
        $ActiveCrash = @($Stage3TargetEvents | Where-Object { $_.event -eq "SM0_H43_CRASH_POINT" -and $_.stage -eq "ACTIVE" -and [string]$_.transfer_id -eq $TransferId })
        if ($ActiveCrash.Count -ne 1) { throw "Chain $Chain ACTIVE crash evidence missing or duplicated." }
        $ActiveGeneration = [int]$ActiveCrash[0].recovery_generation
        if ($ActiveGeneration -le $CommittedGeneration) { throw "Chain $Chain target generation did not advance COMMITTED -> ACTIVE_OWNER." }
        $Stage3Suppressed = @($Stage3TargetEvents | Where-Object { $_.event -eq "SM0_H43_SEND_SUPPRESSED" -and $_.stage -eq "ACTIVE" -and $_.message_type -eq "ACTIVATE_ACK" -and [string]$_.transfer_id -eq $TransferId })
        if ($Stage3Suppressed.Count -ne 1) { throw "Chain $Chain ACTIVE suppression evidence is not exact-one." }
        if (@($Stage3TargetEvents | Where-Object { $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId }).Count -ne 0) { throw "Chain $Chain duplicate canonical target commit occurred while restoring TARGET_COMMITTED." }
        if (@($Stage3TargetEvents | Where-Object { $_.event -eq "SM0_TARGET_ACTIVATED" -and [string]$_.transfer_id -eq $TransferId }).Count -lt 1) { throw "Chain $Chain target activation evidence missing." }
        if (@(Get-H43Crossings).Count -ne ($Chain - 1)) { throw "Chain $Chain crossed before ACTIVE outage." }

        $ActiveSnapshot = Get-H43Snapshot $TargetLeaf $ActiveGeneration
        if ([string]$ActiveSnapshot.phase -ne "ACTIVE_OWNER" -or -not [string]::IsNullOrEmpty([string]$ActiveSnapshot.transfer_id)) { throw "Chain $Chain ACTIVE_OWNER snapshot mismatch." }
        if ([string]$ActiveSnapshot.directory.owner_authority_id -ne $TargetAuthorityId -or [int]$ActiveSnapshot.directory.authority_epoch -ne $TargetEpoch) { throw "Chain $Chain ACTIVE_OWNER directory mismatch." }
        if ($null -eq $ActiveSnapshot.committed_transfers.PSObject.Properties[$TransferId]) { throw "Chain $Chain ACTIVE_OWNER snapshot lost committed T metadata." }
        $RestoredSourceStage3 = @($Stage3SourceEvents | Where-Object { $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "SOURCE_RETIRED" -and [int]$_.generation -eq $SourceGeneration -and [string]$_.transfer_id -eq $TransferId })
        if ($RestoredSourceStage3.Count -ne 1 -or [int]$RestoredSourceStage3[0].writer_count -ne 0) { throw "Chain $Chain source did not restore exact retired non-writer state at Stage 3." }
        if ((Select-String -LiteralPath $TargetLog,$SourceLog -SimpleMatch "SM0_COMMIT_WITHOUT_PREPARE" -Quiet -ErrorAction SilentlyContinue)) { throw "Chain $Chain hit SM0_COMMIT_WITHOUT_PREPARE before ACTIVE outage." }

        $KilledActive = Stop-H43AuthorityPair $A $B $C $Chain "ACTIVE"
        Save-H43State $null $null $C
        Write-H43Log "Chain ${Chain}/${Chains} outage 3/3 ACTIVE same-transfer=$TransferId target=$TargetLetter ACTIVE_OWNER gen=$ActiveGeneration source=$SourceLetter SOURCE_RETIRED gen=$SourceGeneration oldA=$($KilledActive.old_a_pid) oldB=$($KilledActive.old_b_pid) gap=$($KilledActive.gap_ms)ms client=$ClientPid alive."

        # Terminal recovery of this T: no more fault. Same client must finish one
        # and only one crossing before the next chain may begin.
        $Segment++
        $Pair = Start-H43RecoveredPair $Segment $TargetLetter "chain$Chain-active-recovery"
        $A = $Pair.a; $B = $Pair.b; $CurrentALog = $Pair.a_log; $CurrentBLog = $Pair.b_log
        $ASegmentLogs.Add($CurrentALog); $BSegmentLogs.Add($CurrentBLog)
        Save-H43State $A $B $C
        $TargetProcess = if ($TargetLetter -eq "A") { $A } else { $B }
        $SourceProcess = if ($SourceLetter -eq "A") { $A } else { $B }
        $TargetLog = if ($TargetLetter -eq "A") { $CurrentALog } else { $CurrentBLog }
        $SourceLog = if ($SourceLetter -eq "A") { $CurrentALog } else { $CurrentBLog }
        Wait-H43Marker $TargetLog '"event":"SM0_RECOVERY_ACTIVE_OWNER_PENDING"' $TargetProcess 25
        Wait-H43Marker $SourceLog '"event":"SM0_RECOVERY_SOURCE_IMMEDIATE_RESUME"' $SourceProcess 25
        Wait-H43Marker $TargetLog '"event":"SM0_RECOVERY_SESSION_REBOUND"' $TargetProcess 50
        Wait-H43CrossingCount $Chain $C 60

        $TerminalTargetEvents = @(Get-H43Events $TargetLog)
        $TerminalSourceEvents = @(Get-H43Events $SourceLog)
        $RestoredActive = @($TerminalTargetEvents | Where-Object { $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $ActiveGeneration })
        if ($RestoredActive.Count -ne 1) { throw "Chain $Chain terminal target did not restore exact ACTIVE_OWNER generation." }
        $RestoredSourceTerminal = @($TerminalSourceEvents | Where-Object { $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "SOURCE_RETIRED" -and [int]$_.generation -eq $SourceGeneration -and [string]$_.transfer_id -eq $TransferId })
        if ($RestoredSourceTerminal.Count -ne 1 -or [int]$RestoredSourceTerminal[0].writer_count -ne 0) { throw "Chain $Chain terminal source restore mismatch." }
        if (@($TerminalTargetEvents | Where-Object { $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId }).Count -ne 0) { throw "Chain $Chain terminal recovery duplicated canonical target commit/import." }
        if (@($TerminalTargetEvents | Where-Object { $_.event -eq "SM0_H43_CRASH_POINT" }).Count -ne 0) { throw "Chain $Chain terminal ACTIVE_OWNER recovery faulted again." }
        if ((Select-String -LiteralPath $TargetLog,$SourceLog -SimpleMatch "SM0_COMMIT_WITHOUT_PREPARE" -Quiet -ErrorAction SilentlyContinue)) { throw "Chain $Chain terminal recovery hit SM0_COMMIT_WITHOUT_PREPARE." }

        $CrossingsNow = @(Get-H43Crossings)
        if ($CrossingsNow.Count -ne $Chain) { throw "Chain $Chain crossing count advanced by more than one: $($CrossingsNow.Count)." }
        $Crossing = $CrossingsNow[$Chain - 1]
        if ([int]$Crossing.handoff_index -ne $Chain) { throw "Chain $Chain crossing index mismatch." }
        if ([string]$Crossing.transfer_id -ne $TransferId) { throw "Chain $Chain crossing did not complete the same transfer." }
        if ([string]$Crossing.authority_id -ne $TargetAuthorityId) { throw "Chain $Chain crossing target authority mismatch." }
        if ([int]$Crossing.directory.authority_epoch -ne $TargetEpoch) { throw "Chain $Chain directory epoch mismatch." }

        $ChainEvidence.Add([ordered]@{
            chain = $Chain
            transfer_id = $TransferId
            source_authority_id = $SourceAuthorityId
            target_authority_id = $TargetAuthorityId
            source_retired_generation = $SourceGeneration
            target_prepared_generation = $PreparedGeneration
            target_committed_generation = $CommittedGeneration
            target_active_generation = $ActiveGeneration
            prepared_outage = $KilledPrepared
            committed_outage = $KilledCommitted
            active_outage = $KilledActive
            directory_epoch = [int]$Crossing.directory.authority_epoch
        })
        Write-H43Log "Chain ${Chain}/${Chains} recovered same transfer=$TransferId through PREPARED->$PreparedGeneration COMMITTED->$CommittedGeneration ACTIVE->$ActiveGeneration; crossing #$Chain completed exactly once on target=$TargetLetter."
    }

    $Deadline = (Get-Date).AddSeconds(20)
    while (-not $C.HasExited -and (Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 50; $C.Refresh() }
    if (-not $C.HasExited) { throw "Client did not exit after completing all H4.3 handoffs." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($A,$B)) {
        $StopDeadline = (Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date) -lt $StopDeadline) { Start-Sleep -Milliseconds 50; $Server.Refresh() }
        if (-not $Server.HasExited) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
    }

    $ACombined = [System.Collections.Generic.List[string]]::new()
    foreach ($Path in $ASegmentLogs) { if (Test-Path -LiteralPath $Path) { foreach ($Line in Get-Content -LiteralPath $Path) { $ACombined.Add($Line) } } }
    $ACombined | Set-Content -LiteralPath $ALog -Encoding UTF8
    $BCombined = [System.Collections.Generic.List[string]]::new()
    foreach ($Path in $BSegmentLogs) { if (Test-Path -LiteralPath $Path) { foreach ($Line in Get-Content -LiteralPath $Path) { $BCombined.Add($Line) } } }
    $BCombined | Set-Content -LiteralPath $BLog -Encoding UTF8

    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $ExpectedHandoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) { throw "Base SM0 convergence failed after H4.3 recovery-of-recovery outages." }

    $AllEvents = @(Get-H43Events $ALog) + @(Get-H43Events $BLog)
    if (@($AllEvents | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) { throw "Invariant violation observed in H4.3 authority logs." }
    if ((Select-String -LiteralPath $ALog,$BLog -SimpleMatch "SM0_COMMIT_WITHOUT_PREPARE" -Quiet -ErrorAction SilentlyContinue)) { throw "SM0_COMMIT_WITHOUT_PREPARE observed in combined H4.3 logs." }

    $Result = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne $ExpectedHandoffs -or [int]$Result.identity_changes -ne 0) { throw "Client H4.3 evidence failed." }
    $Crossings = @(Get-H43Crossings)
    if ($Crossings.Count -ne $ExpectedHandoffs) { throw "H4.3 crossing event count mismatch." }
    for ($Index = 0; $Index -lt $Crossings.Count; $Index++) {
        $ExpectedIndex = $Index + 1
        $ExpectedTarget = if (($ExpectedIndex % 2) -eq 1) { "authority/sm0/b" } else { "authority/sm0/a" }
        if ([int]$Crossings[$Index].handoff_index -ne $ExpectedIndex) { throw "Non-contiguous H4.3 crossing index at $ExpectedIndex." }
        if ([string]$Crossings[$Index].authority_id -ne $ExpectedTarget) { throw "H4.3 target alternation mismatch at crossing $ExpectedIndex." }
        if ([int]$Crossings[$Index].directory.authority_epoch -ne ($ExpectedIndex + 1)) { throw "H4.3 directory epoch mismatch at crossing $ExpectedIndex." }
    }
    $ExpectedEpoch = $ExpectedHandoffs + 1
    if ([int]$Result.authority_epoch_end -ne $ExpectedEpoch) { throw "Final directory epoch mismatch: expected $ExpectedEpoch got $($Result.authority_epoch_end)" }

    [ordered]@{
        schema = "distributed_world_simulator.sm0_h43_recovery_of_recovery_summary.v1"
        result = "PASS"
        git_head = $Head
        fault_profile = $FaultProfile
        client_pid = $ClientPid
        chains_completed = $ChainEvidence.Count
        outages_completed = $ExpectedOutages
        handoffs_completed = [int]$Result.handoffs_completed
        final_directory_epoch = [int]$Result.authority_epoch_end
        identity_changes = [int]$Result.identity_changes
        chains = $ChainEvidence.ToArray()
        logs = $LogDir
    } | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H4.3 recovery-of-recovery same-transfer campaign: PASS" -ForegroundColor Green
    Write-Host "  same client PID       : $ClientPid"
    Write-Host "  chains                : $($ChainEvidence.Count) / $Chains"
    Write-Host "  outages               : $ExpectedOutages / $ExpectedOutages"
    Write-Host "  stages per transfer   : PREPARED, COMMITTED, ACTIVE"
    Write-Host "  target sequence       : B,A alternating"
    Write-Host "  handoffs              : $ExpectedHandoffs / $ExpectedHandoffs"
    Write-Host "  final directory epoch : $($Result.authority_epoch_end)"
    Write-Host "  identity changes      : 0"
    Write-Host "  logs                  : $LogDir"
    Write-Host "  summary               : $SummaryPath"
    $Exit = 0
}
catch {
    Write-Error "SM0-H4.3 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $Exit = 1
}
finally {
    foreach ($Process in @($C,$A,$B)) {
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
                    Write-Host "[SM0-H4.3] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H4.3 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
