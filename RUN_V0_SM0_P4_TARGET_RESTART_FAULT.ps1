[CmdletBinding()]
param(
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(20, 300)][int]$TimeoutSeconds = 90,
    [ValidateRange(3500, 15000)][int]$PostCrashHoldMs = 4000
)

$ErrorActionPreference = "Stop"
$CanonicalWorkspaceRoot = "C:\distributed-world-simulator"
$GameplayPorts = @(24580, 24581)
$ControlPorts = @(24680, 24681)
$ClientPort = 24780
$JoinProbePort = 24782
$LivePrewarmTtlMs = 3000

if ($PostCrashHoldMs -le $LivePrewarmTtlMs) {
    throw "PostCrashHoldMs must be greater than the P4 live PREWARM TTL ($LivePrewarmTtlMs ms)."
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith($CanonicalWorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0 Windows fault evidence must run below $CanonicalWorkspaceRoot. Current project: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project.godot missing: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot 4.7.1 double console executable missing: $GodotExe"
}

$GitHead = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) { throw "Unable to resolve exact git HEAD." }
$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "P4 restart fault gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")"
}

if ($Restart) {
    $StopRunner = Join-Path $ProjectRoot "RUN_V0_SM0_P4_ACCEPTANCE.ps1"
    if (Test-Path -LiteralPath $StopRunner -PathType Leaf) {
        & $StopRunner -Stop -ProjectRoot $ProjectRoot -GodotExe $GodotExe
    }
}

function Test-UdpPortAvailable {
    param([int]$Port)
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

foreach ($Port in @($GameplayPorts + $ControlPorts + @($ClientPort, $JoinProbePort))) {
    if (-not (Test-UdpPortAvailable $Port)) {
        throw "Required UDP port $Port is already in use. Rerun with -Restart after stopping the owning process."
    }
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$RunId = "{0}-{1}-{2}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), $PID, ([guid]::NewGuid().ToString("N").Substring(0, 8))
$LogDirectory = Join-Path $LocalAppData "DistributedWorldSimulator\SM0P4Fault\$RunId"
$RecoveryRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0P4Recovery\fault-$RunId"
New-Item -ItemType Directory -Force -Path $LogDirectory, $RecoveryRoot | Out-Null

$ServerAPreLog = Join-Path $LogDirectory "server-a.pre-restart.log"
$ServerAPostLog = Join-Path $LogDirectory "server-a.post-restart.log"
$ServerACombinedLog = Join-Path $LogDirectory "server-a.log"
$ServerBPreLog = Join-Path $LogDirectory "server-b.pre-restart.log"
$ServerBPostLog = Join-Path $LogDirectory "server-b.post-restart.log"
$ServerBCombinedLog = Join-Path $LogDirectory "server-b.log"
$ClientLog = Join-Path $LogDirectory "client.log"
$ClientResult = Join-Path $LogDirectory "client-result.json"
$JoinProbeLog = Join-Path $LogDirectory "restart-reconnect-probe.log"
$JoinProbeResult = Join-Path $LogDirectory "restart-reconnect-probe.json"
$HarnessLog = Join-Path $LogDirectory "harness.log"
$StopFile = Join-Path $LogDirectory "stop.flag"
$EvidencePath = Join-Path $LogDirectory "p4-target-restart-evidence.json"

function Write-Harness([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Quote-Arg([string]$Value) { return '"' + $Value + '"' }

function Start-Sm0Godot {
    param(
        [string]$Role,
        [string]$LogFile,
        [string]$ScriptPath,
        [string[]]$UserArgs
    )
    $Args = @(
        "--headless",
        "--path", (Quote-Arg $ProjectRoot),
        "--log-file", (Quote-Arg $LogFile),
        "--script", $ScriptPath,
        "--"
    ) + $UserArgs
    $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    Write-Harness "$Role started PID=$($Process.Id) log=$LogFile"
    return $Process
}

function Wait-LogMarker {
    param(
        [string]$Path,
        [string]$Marker,
        [System.Diagnostics.Process]$Process,
        [int]$Seconds,
        [string]$Label
    )
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue) { return }
            foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "SM0 server setup failed", "SM0 P4 fault server setup failed")) {
                if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) {
                    throw "$Label contains fatal marker '$Fatal'. See $Path"
                }
            }
        }
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "$Label exited code=$($Process.ExitCode) before marker '$Marker'. See $Path"
        }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for '$Marker' from $Label. See $Path"
}

function Wait-LogMarkerAllowExit {
    param(
        [string]$Path,
        [string]$Marker,
        [System.Diagnostics.Process]$Process,
        [int]$Seconds,
        [string]$Label
    )
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue) { return }
            foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "SM0 server setup failed", "SM0 P4 fault server setup failed")) {
                if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) {
                    throw "$Label contains fatal marker '$Fatal'. See $Path"
                }
            }
        }
        $Process.Refresh()
        if ($Process.HasExited) {
            # The fault process may finish immediately after it flushes the marker.
            Start-Sleep -Milliseconds 50
            if (Test-Path -LiteralPath $Path -PathType Leaf -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
            throw "$Label exited before emitting required marker '$Marker'. See $Path"
        }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for '$Marker' from $Label. See $Path"
}

function Wait-ProcessExit {
    param([System.Diagnostics.Process]$Process, [int]$Seconds, [string]$Label)
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "$Label did not exit within $Seconds seconds."
}

function Wait-PortAvailable {
    param([int]$Port, [int]$Seconds)
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        if (Test-UdpPortAvailable $Port) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "UDP port $Port was not released after process restart."
}

function Assert-ProcessAlive {
    param([System.Diagnostics.Process]$Process, [string]$Label)
    $Process.Refresh()
    if ($Process.HasExited) { throw "$Label exited unexpectedly with code=$($Process.ExitCode)." }
}

$HadP4 = Test-Path Env:SM0_P4_FAST_HANDOFF
$PreviousP4 = $env:SM0_P4_FAST_HANDOFF
$HadRecovery = Test-Path Env:SM0_P4_RECOVERY_DIR
$PreviousRecovery = $env:SM0_P4_RECOVERY_DIR
$HadBreakpoint = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
$Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$ServerAPre = $null
$ServerAPost = $null
$ServerBPre = $null
$ServerBPost = $null
$Client = $null
$JoinProbe = $null
$ExitCode = 1

try {
    $env:SM0_P4_FAST_HANDOFF = "1"
    $env:SM0_P4_RECOVERY_DIR = $RecoveryRoot
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Harness "P4 closure fault gate start HEAD=$GitHead"
    Write-Harness "recovery root=$RecoveryRoot"
    Write-Harness "live prewarm ttl=$LivePrewarmTtlMs ms; post-crash hold=$PostCrashHoldMs ms"
    Write-Harness "Skipping editor import; this fault gate is script-only and validates every participating script with --check-only."

    foreach ($ScriptPath in @(
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_hardened.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_fault.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_process_p4_fault.gd",
        "res://scripts/runtime/seamless/sm0/sm0_automated_client_node_p4_hardened.gd",
        "res://tests/runtime/seamless/sm0/sm0_p4_hardening_test_server.gd",
        "res://tests/runtime/seamless/sm0/sm0_p4_hardening_test_client.gd",
        "res://tests/runtime/seamless/sm0/sm0_p4_durable_proof_test_server.gd",
        "res://tests/runtime/seamless/sm0/sm0_p4_join_probe_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p4_hardening.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p4_durable_proof_recovery.gd"
    )) {
        Write-Harness "Compile check $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "Compile check failed: $ScriptPath" }
    }
    & $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p4_hardening.gd
    if ($LASTEXITCODE -ne 0) { throw "P4 hardening focused tests failed." }
    & $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p4_durable_proof_recovery.gd
    if ($LASTEXITCODE -ne 0) { throw "P4 durable proof recovery focused tests failed." }

    & (Join-Path $ProjectRoot "TEST_V0_SM0_P4_GLOBAL_WRITER_ANALYZER.ps1") -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw "Aggregate writer analyzer self-test failed." }

    $ServerAPre = Start-Sm0Godot -Role "server-a" -LogFile $ServerAPreLog -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd" -UserArgs @(
        "--authority-id=authority/sm0/a",
        "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580",
        "--control-port=24680",
        "--peer-control-port=24681",
        "--stop-file=$StopFile"
    )
    $Processes.Add($ServerAPre)

    $ServerBPre = Start-Sm0Godot -Role "server-b-fault" -LogFile $ServerBPreLog -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_authority_server_process_p4_fault.gd" -UserArgs @(
        "--authority-id=authority/sm0/b",
        "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581",
        "--control-port=24681",
        "--peer-control-port=24680",
        "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot",
        "--p4-fault-profile=target-exit-after-prewarm-ack-v1"
    )
    $Processes.Add($ServerBPre)

    Wait-LogMarker $ServerAPreLog '"event":"SM0_P4_HARDENING_READY"' $ServerAPre 20 "server-a"
    Wait-LogMarker $ServerBPreLog '"event":"SM0_P4_HARDENING_READY"' $ServerBPre 20 "server-b-fault"
    Wait-LogMarker $ServerAPreLog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $ServerAPre 20 "server-a"
    Wait-LogMarker $ServerBPreLog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $ServerBPre 20 "server-b-fault"
    Write-Harness "Initial authorities synchronized."

    $Client = Start-Sm0Godot -Role "client" -LogFile $ClientLog -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd" -UserArgs @(
        "--server-host=127.0.0.1",
        "--server-a-port=24580",
        "--server-b-port=24581",
        "--client-port=$ClientPort",
        "--handoffs=1",
        "--timeout-ms=$($TimeoutSeconds * 1000)",
        "--result-file=$ClientResult"
    )
    $Processes.Add($Client)

    Wait-LogMarkerAllowExit $ServerBPreLog '"event":"SM0_P4_FAULT_TARGET_EXIT_AFTER_PREWARM_ACK"' $ServerBPre 20 "server-b-fault"
    Wait-ProcessExit $ServerBPre 10 "server-b-fault"
    if ($ServerBPre.ExitCode -ne 86) {
        throw "Fault target exited with code $($ServerBPre.ExitCode); expected 86."
    }
    Write-Harness "Target B crashed after durable PREWARM ACK as required."

    # Decisive ordering guard: B remains down until A has crossed, frozen and
    # retired its writer. This prevents the test from escaping through the safe
    # pre-retirement incarnation fallback.
    Wait-LogMarker $ServerAPreLog '"event":"SM0_SOURCE_RETIRED"' $ServerAPre 10 "server-a"
    Wait-LogMarker $ServerAPreLog '"event":"SM0_P4_FAST_HANDOFF_BEGIN"' $ServerAPre 10 "server-a"
    Write-Harness "Source A is retired. Keeping B down beyond the $LivePrewarmTtlMs ms live PREWARM TTL."

    # The target must stay physically down longer than the live reservation TTL.
    # If the restart later succeeds without SM0_P4_PREWARM_REHYDRATED_FROM_DURABLE_PROOF,
    # this harness must fail: restoring a still-live reservation is not sufficient
    # evidence for the durable-proof closure.
    Start-Sleep -Milliseconds $PostCrashHoldMs
    Assert-ProcessAlive $ServerAPre "server-a-during-post-crash-hold"
    $ServerBPre.Refresh()
    if (-not $ServerBPre.HasExited) {
        throw "Fault target B unexpectedly became alive during post-crash TTL hold."
    }
    Write-Harness "Post-crash hold complete ($PostCrashHoldMs ms > $LivePrewarmTtlMs ms TTL); restarting B now requires durable proof rehydration."

    Wait-PortAvailable 24581 5
    Wait-PortAvailable 24681 5
    $ServerBPost = Start-Sm0Godot -Role "server-b-restarted" -LogFile $ServerBPostLog -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd" -UserArgs @(
        "--authority-id=authority/sm0/b",
        "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581",
        "--control-port=24681",
        "--peer-control-port=24680",
        "--stop-file=$StopFile"
    )
    $Processes.Add($ServerBPost)

    Wait-LogMarker $ServerBPostLog '"event":"SM0_P4_STATE_RESTORED"' $ServerBPost 20 "server-b-restarted"
    Wait-LogMarker $ServerBPostLog '"event":"SM0_P4_PREWARM_PROOFS_RESTORED"' $ServerBPost 20 "server-b-restarted"
    Wait-LogMarker $ServerBPostLog '"event":"SM0_P4_PREWARM_REHYDRATED_FROM_DURABLE_PROOF"' $ServerBPost 20 "server-b-restarted"
    Wait-LogMarker $ServerBPostLog '"event":"SM0_P4_FAST_COMMIT_ACCEPTED"' $ServerBPost 20 "server-b-restarted"
    Write-Harness "Restarted target restored durable proof, rehydrated an expired live reservation and accepted FAST_COMMIT."

    $ClientDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $ClientDeadline) {
        $Client.Refresh()
        if ($Client.HasExited) { break }
        Assert-ProcessAlive $ServerAPre "server-a"
        Assert-ProcessAlive $ServerBPost "server-b-restarted"
        Start-Sleep -Milliseconds 50
    }
    $Client.Refresh()
    if (-not $Client.HasExited) { throw "Client did not finish after target restart recovery." }
    if ($Client.ExitCode -ne 0) { throw "Client failed after target restart recovery. See $ClientLog" }

    if (-not (Test-Path -LiteralPath $ClientResult -PathType Leaf)) { throw "Client result missing: $ClientResult" }
    $Result = Get-Content -LiteralPath $ClientResult -Raw | ConvertFrom-Json
    if ([string]$Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne 1 -or [int]$Result.identity_changes -ne 0) {
        throw "Recovered client result invalid: $($Result | ConvertTo-Json -Compress)"
    }

    # Physical restart + reconnect probe. B is now the canonical writer. Kill A
    # only, restart it from the same recovery root and immediately send a fresh
    # CLIENT_JOIN to A. A must never manufacture writer truth from stale
    # bootstrap/recovery state. The completed-fast tombstone must also suppress
    # resurrection of A's old SOURCE_RETIRED pending transfer.
    Write-Harness "Restarting retired A to exercise stale-authority reconnect admission."
    Stop-Process -Id $ServerAPre.Id -Force -ErrorAction Stop
    Wait-ProcessExit $ServerAPre 10 "server-a-pre-restart"
    Wait-PortAvailable 24580 5
    Wait-PortAvailable 24680 5
    Assert-ProcessAlive $ServerBPost "server-b-owner-before-reconnect-probe"

    $ServerAPost = Start-Sm0Godot -Role "server-a-restarted" -LogFile $ServerAPostLog -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd" -UserArgs @(
        "--authority-id=authority/sm0/a",
        "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580",
        "--control-port=24680",
        "--peer-control-port=24681",
        "--stop-file=$StopFile"
    )
    $Processes.Add($ServerAPost)
    Wait-LogMarker $ServerAPostLog '"event":"SM0_P4_HARDENING_READY"' $ServerAPost 20 "server-a-restarted"
    Wait-LogMarker $ServerAPostLog '"event":"SM0_P4_RECOVERY_COMPLETED_SOURCE_TOMBSTONE_APPLIED"' $ServerAPost 20 "server-a-restarted"

    $JoinProbe = Start-Sm0Godot -Role "restart-reconnect-probe" -LogFile $JoinProbeLog -ScriptPath "res://tests/runtime/seamless/sm0/sm0_p4_join_probe_process.gd" -UserArgs @(
        "--server-host=127.0.0.1",
        "--server-port=24580",
        "--client-port=$JoinProbePort",
        "--timeout-ms=5000",
        "--result-file=$JoinProbeResult"
    )
    $Processes.Add($JoinProbe)
    Wait-ProcessExit $JoinProbe 10 "restart-reconnect-probe"
    if ($JoinProbe.ExitCode -ne 0) {
        throw "Restart reconnect probe failed. See $JoinProbeLog"
    }
    if (-not (Test-Path -LiteralPath $JoinProbeResult -PathType Leaf)) {
        throw "Restart reconnect probe result missing: $JoinProbeResult"
    }
    $ProbeResult = Get-Content -LiteralPath $JoinProbeResult -Raw | ConvertFrom-Json
    if ([string]$ProbeResult.result -ne "PASS") {
        throw "Restart reconnect probe did not PASS: $($ProbeResult | ConvertTo-Json -Compress)"
    }
    if ([string]$ProbeResult.result_code -notin @("SM0_P4_JOIN_REQUIRES_PEER_SYNC", "SM0_AUTHORITY_NOT_ACTIVE")) {
        throw "Restart reconnect probe used an unexpected rejection: $($ProbeResult.result_code)"
    }
    if (Select-String -LiteralPath $ServerAPostLog -SimpleMatch '"event":"SM0_CLIENT_JOINED"' -Quiet -ErrorAction SilentlyContinue) {
        throw "Restarted stale authority A accepted CLIENT_JOIN during reconnect probe."
    }
    Assert-ProcessAlive $ServerBPost "server-b-owner-after-reconnect-probe"
    Write-Harness "Restart reconnect probe PASS: stale A did not accept JOIN; result=$($ProbeResult.result_code)."

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($ServerAPost, $ServerBPost)) {
        if ($null -eq $Server) { continue }
        $Deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $Deadline) {
            $Server.Refresh()
            if ($Server.HasExited) { break }
            Start-Sleep -Milliseconds 50
        }
    }

    @(
        Get-Content -LiteralPath $ServerAPreLog -ErrorAction Stop
        Get-Content -LiteralPath $ServerAPostLog -ErrorAction Stop
    ) | Set-Content -LiteralPath $ServerACombinedLog -Encoding UTF8
    @(
        Get-Content -LiteralPath $ServerBPreLog -ErrorAction Stop
        Get-Content -LiteralPath $ServerBPostLog -ErrorAction Stop
    ) | Set-Content -LiteralPath $ServerBCombinedLog -Encoding UTF8

    foreach ($Forbidden in @(
        "SM0_P4_FAST_COMMIT_WITHOUT_PREWARM",
        "SM0_P4_RESTART_RECONNECT_JOIN_UNEXPECTEDLY_ACCEPTED"
    )) {
        foreach ($Path in @($ServerACombinedLog, $ServerBCombinedLog, $JoinProbeLog)) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Forbidden -Quiet -ErrorAction SilentlyContinue) {
                throw "Fault evidence emitted forbidden marker '$Forbidden' in $Path."
            }
        }
    }

    foreach ($RequiredProofMarker in @(
        '"event":"SM0_P4_PREWARM_PROOFS_RESTORED"',
        '"event":"SM0_P4_PREWARM_REHYDRATED_FROM_DURABLE_PROOF"'
    )) {
        if (-not (Select-String -LiteralPath $ServerBPostLog -SimpleMatch $RequiredProofMarker -Quiet -ErrorAction SilentlyContinue)) {
            throw "Target restart did not exercise required durable-proof marker: $RequiredProofMarker"
        }
    }

    $Analyzer = Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1"
    & $Analyzer -LogDirectory $LogDirectory -ExpectedHandoffs 1
    if ($LASTEXITCODE -ne 0) { throw "Base SM0 analyzer failed after target restart/reconnect recovery." }
    $Summary = Get-Content -LiteralPath (Join-Path $LogDirectory "summary.json") -Raw | ConvertFrom-Json
    if ([int]$Summary.p4_fast_handoffs -ne 1 -or [int]$Summary.legacy_handoffs -ne 0) {
        throw "Fault run escaped to legacy path instead of recovering P4 FAST: fast=$($Summary.p4_fast_handoffs) legacy=$($Summary.legacy_handoffs)"
    }

    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_P4_GLOBAL_WRITERS.ps1") -LogDirectory $LogDirectory
    if ($LASTEXITCODE -ne 0) { throw "Aggregate A+B writer audit failed after target restart/reconnect recovery." }
    $WriterAudit = Get-Content -LiteralPath (Join-Path $LogDirectory "p4-global-writer-audit.json") -Raw | ConvertFrom-Json
    if ([int]$WriterAudit.max_aggregate_writer_count -gt 1) {
        throw "Aggregate writer overlap detected after recovery."
    }

    $Evidence = [ordered]@{
        schema = "distributed_world_simulator.sm0_p4_closure_fault_evidence.v2"
        result = "PASS"
        git_head = $GitHead
        target_restart_fault = "PREWARMED -> target process exit -> SOURCE_RETIRED -> hold beyond live TTL -> target restart -> durable proof rehydrate -> FAST_COMMIT"
        restart_reconnect_fault = "completed fast handoff -> retired source restart -> immediate CLIENT_JOIN probe"
        expected_fault_exit_code = 86
        live_prewarm_ttl_ms = $LivePrewarmTtlMs
        post_crash_hold_ms = $PostCrashHoldMs
        handoffs_completed = 1
        p4_fast_handoffs = 1
        legacy_handoffs = 0
        identity_changes = [int]$Result.identity_changes
        max_aggregate_writer_count = [int]$WriterAudit.max_aggregate_writer_count
        target_live_reservation_restored = $false
        target_durable_proof_restored = $true
        target_reservation_rehydrated_from_proof = $true
        source_completion_tombstone_applied = $true
        restart_reconnect_probe = "PASS"
        restart_reconnect_result_code = [string]$ProbeResult.result_code
        fast_commit_without_prewarm_seen = $false
        recovery_root = $RecoveryRoot
        server_a_pre_restart_log = $ServerAPreLog
        server_a_post_restart_log = $ServerAPostLog
        server_b_pre_restart_log = $ServerBPreLog
        server_b_post_restart_log = $ServerBPostLog
        client_log = $ClientLog
        reconnect_probe_log = $JoinProbeLog
    }
    $Evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P4 fault gate" }
    if (-not $AllowDirty -and (($StatusAfter -join "`n") -ne ($StatusBefore -join "`n"))) {
        throw "P4 fault gate mutated the source worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")"
    }

    Write-Harness "P4 closure fault gate PASS."
    $ExitCode = 0
}
catch {
    Write-Harness "P4 closure fault gate FAIL: $($_.Exception.Message)"
    Write-Error $_ -ErrorAction Continue
}
finally {
    if (-not (Test-Path -LiteralPath $StopFile -PathType Leaf)) {
        New-Item -ItemType File -Force -Path $StopFile -ErrorAction SilentlyContinue | Out-Null
    }
    foreach ($Process in $Processes) {
        try {
            $Process.Refresh()
            if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue }
        }
        catch { }
    }
    if ($HadP4) { $env:SM0_P4_FAST_HANDOFF = $PreviousP4 } else { Remove-Item Env:SM0_P4_FAST_HANDOFF -ErrorAction SilentlyContinue }
    if ($HadRecovery) { $env:SM0_P4_RECOVERY_DIR = $PreviousRecovery } else { Remove-Item Env:SM0_P4_RECOVERY_DIR -ErrorAction SilentlyContinue }
    if ($HadBreakpoint) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpoint } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}

Write-Host ""
if ($ExitCode -eq 0) {
    Write-Host "SM0-P4 closure fault gate: PASS" -ForegroundColor Green
    Write-Host "  HEAD       : $GitHead"
    Write-Host "  target     : PREWARMED -> exit -> SOURCE_RETIRED -> hold > TTL -> proof rehydrate -> FAST_COMMIT"
    Write-Host "  hold       : $PostCrashHoldMs ms (live TTL $LivePrewarmTtlMs ms)"
    Write-Host "  reconnect  : retired A restart -> fresh JOIN rejected"
    Write-Host "  P4 fast    : 1"
    Write-Host "  legacy     : 0"
    Write-Host "  A+B max    : 1"
    Write-Host "  evidence   : $EvidencePath"
}
else {
    Write-Host "SM0-P4 closure fault gate: FAIL" -ForegroundColor Red
    Write-Host "  HEAD : $GitHead"
    Write-Host "  logs : $LogDirectory"
}
exit $ExitCode
