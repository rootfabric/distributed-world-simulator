[CmdletBinding()]
param(
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(20, 300)][int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"
$CanonicalWorkspaceRoot = "C:\distributed-world-simulator"
$GameplayPorts = @(24580, 24581)
$ControlPorts = @(24680, 24681)
$ClientPort = 24780

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

foreach ($Port in @($GameplayPorts + $ControlPorts + @($ClientPort))) {
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

$ImportLog = Join-Path $LogDirectory "import.log"
$ServerALog = Join-Path $LogDirectory "server-a.log"
$ServerBPreLog = Join-Path $LogDirectory "server-b.pre-restart.log"
$ServerBPostLog = Join-Path $LogDirectory "server-b.post-restart.log"
$ServerBCombinedLog = Join-Path $LogDirectory "server-b.log"
$ClientLog = Join-Path $LogDirectory "client.log"
$ClientResult = Join-Path $LogDirectory "client-result.json"
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
        [string]$Label,
        [switch]$AllowExitAfterMarker
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
        if ($Process.HasExited -and -not $AllowExitAfterMarker) {
            throw "$Label exited code=$($Process.ExitCode) before marker '$Marker'. See $Path"
        }
        if ($Process.HasExited -and $AllowExitAfterMarker) {
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
    throw "UDP port $Port was not released after target crash."
}

$HadP4 = Test-Path Env:SM0_P4_FAST_HANDOFF
$PreviousP4 = $env:SM0_P4_FAST_HANDOFF
$HadRecovery = Test-Path Env:SM0_P4_RECOVERY_DIR
$PreviousRecovery = $env:SM0_P4_RECOVERY_DIR
$HadBreakpoint = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
$Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$ServerA = $null
$ServerBPre = $null
$ServerBPost = $null
$Client = $null
$ExitCode = 1

try {
    $env:SM0_P4_FAST_HANDOFF = "1"
    $env:SM0_P4_RECOVERY_DIR = $RecoveryRoot
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Harness "P4 target-restart fault gate start HEAD=$GitHead"
    Write-Harness "recovery root=$RecoveryRoot"
    Write-Harness "Importing Godot metadata."
    & $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed. See $ImportLog" }

    foreach ($ScriptPath in @(
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_fault.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_process_p4_fault.gd",
        "res://tests/runtime/seamless/sm0/sm0_p4_hardening_test_server.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p4_hardening.gd"
    )) {
        Write-Harness "Compile check $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "Compile check failed: $ScriptPath" }
    }
    & $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p4_hardening.gd
    if ($LASTEXITCODE -ne 0) { throw "P4 hardening focused tests failed." }

    & (Join-Path $ProjectRoot "TEST_V0_SM0_P4_GLOBAL_WRITER_ANALYZER.ps1") -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw "Aggregate writer analyzer self-test failed." }

    $ServerA = Start-Sm0Godot -Role "server-a" -LogFile $ServerALog -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd" -UserArgs @(
        "--authority-id=authority/sm0/a",
        "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580",
        "--control-port=24680",
        "--peer-control-port=24681",
        "--stop-file=$StopFile"
    )
    $Processes.Add($ServerA)

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

    Wait-LogMarker $ServerALog '"event":"SM0_P4_HARDENING_READY"' $ServerA 20 "server-a"
    Wait-LogMarker $ServerBPreLog '"event":"SM0_P4_HARDENING_READY"' $ServerBPre 20 "server-b-fault"
    Wait-LogMarker $ServerALog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $ServerA 20 "server-a"
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

    Wait-LogMarker $ServerBPreLog '"event":"SM0_P4_FAULT_TARGET_EXIT_AFTER_PREWARM_ACK"' $ServerBPre 20 "server-b-fault" -AllowExitAfterMarker
    Wait-ProcessExit $ServerBPre 10 "server-b-fault"
    if ($ServerBPre.ExitCode -ne 86) {
        throw "Fault target exited with code $($ServerBPre.ExitCode); expected 86."
    }
    Write-Harness "Target B crashed after durable PREWARM ACK as required."

    # This is the decisive ordering guard. Do not restart B until A has already
    # crossed the boundary, frozen/retired its writer, and committed the new
    # directory. Otherwise the run could pass through the safe pre-retirement
    # incarnation fallback and would not exercise the mandatory fault window.
    Wait-LogMarker $ServerALog '"event":"SM0_SOURCE_RETIRED"' $ServerA 10 "server-a"
    Wait-LogMarker $ServerALog '"event":"SM0_P4_FAST_HANDOFF_BEGIN"' $ServerA 10 "server-a"
    Write-Harness "Source A is retired; restart now exercises PREWARMED -> restart -> FAST_COMMIT recovery."

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
    Wait-LogMarker $ServerBPostLog '"event":"SM0_P4_FAST_COMMIT_ACCEPTED"' $ServerBPost 20 "server-b-restarted"
    Write-Harness "Restarted target restored reservation and accepted FAST_COMMIT."

    $ClientDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $ClientDeadline) {
        $Client.Refresh()
        if ($Client.HasExited) { break }
        $ServerA.Refresh()
        $ServerBPost.Refresh()
        if ($ServerA.HasExited) { throw "Server A exited unexpectedly during recovery." }
        if ($ServerBPost.HasExited) { throw "Restarted Server B exited unexpectedly during recovery." }
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

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($ServerA, $ServerBPost)) {
        if ($null -eq $Server) { continue }
        $Deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $Deadline) {
            $Server.Refresh()
            if ($Server.HasExited) { break }
            Start-Sleep -Milliseconds 50
        }
    }

    @(
        Get-Content -LiteralPath $ServerBPreLog -ErrorAction Stop
        Get-Content -LiteralPath $ServerBPostLog -ErrorAction Stop
    ) | Set-Content -LiteralPath $ServerBCombinedLog -Encoding UTF8

    foreach ($Forbidden in @(
        "SM0_P4_FAST_COMMIT_WITHOUT_PREWARM",
        "SM0_P4_JOIN_REQUIRES_COMMITTED_ACTIVATION"
    )) {
        if (Select-String -LiteralPath $ServerBCombinedLog -SimpleMatch $Forbidden -Quiet -ErrorAction SilentlyContinue) {
            throw "Recovered target emitted forbidden fault marker '$Forbidden'."
        }
    }

    $Analyzer = Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1"
    & $Analyzer -LogDirectory $LogDirectory -ExpectedHandoffs 1
    if ($LASTEXITCODE -ne 0) { throw "Base SM0 analyzer failed after target restart recovery." }
    $Summary = Get-Content -LiteralPath (Join-Path $LogDirectory "summary.json") -Raw | ConvertFrom-Json
    if ([int]$Summary.p4_fast_handoffs -ne 1 -or [int]$Summary.legacy_handoffs -ne 0) {
        throw "Fault run escaped to legacy path instead of recovering P4 FAST: fast=$($Summary.p4_fast_handoffs) legacy=$($Summary.legacy_handoffs)"
    }

    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_P4_GLOBAL_WRITERS.ps1") -LogDirectory $LogDirectory
    if ($LASTEXITCODE -ne 0) { throw "Aggregate A+B writer audit failed after target restart recovery." }
    $WriterAudit = Get-Content -LiteralPath (Join-Path $LogDirectory "p4-global-writer-audit.json") -Raw | ConvertFrom-Json
    if ([int]$WriterAudit.max_aggregate_writer_count -gt 1) {
        throw "Aggregate writer overlap detected after recovery."
    }

    $Evidence = [ordered]@{
        schema = "distributed_world_simulator.sm0_p4_target_restart_fault_evidence.v1"
        result = "PASS"
        git_head = $GitHead
        fault = "PREWARMED -> target process exit -> source retired -> target restart -> FAST_COMMIT"
        expected_fault_exit_code = 86
        handoffs_completed = 1
        p4_fast_handoffs = 1
        legacy_handoffs = 0
        identity_changes = [int]$Result.identity_changes
        max_aggregate_writer_count = [int]$WriterAudit.max_aggregate_writer_count
        target_reservation_restored = $true
        fast_commit_without_prewarm_seen = $false
        recovery_root = $RecoveryRoot
        server_a_log = $ServerALog
        server_b_pre_restart_log = $ServerBPreLog
        server_b_post_restart_log = $ServerBPostLog
        client_log = $ClientLog
    }
    $Evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P4 fault gate" }
    if (-not $AllowDirty -and (($StatusAfter -join "`n") -ne ($StatusBefore -join "`n"))) {
        throw "P4 fault gate mutated the source worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")"
    }

    Write-Harness "P4 target-restart fault gate PASS."
    $ExitCode = 0
}
catch {
    Write-Harness "P4 target-restart fault gate FAIL: $($_.Exception.Message)"
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
    Write-Host "SM0-P4 target restart fault gate: PASS" -ForegroundColor Green
    Write-Host "  HEAD     : $GitHead"
    Write-Host "  fault    : PREWARMED -> target exit -> SOURCE_RETIRED -> target restart -> FAST_COMMIT"
    Write-Host "  P4 fast  : 1"
    Write-Host "  legacy   : 0"
    Write-Host "  A+B max  : 1"
    Write-Host "  evidence : $EvidencePath"
}
else {
    Write-Host "SM0-P4 target restart fault gate: FAIL" -ForegroundColor Red
    Write-Host "  HEAD : $GitHead"
    Write-Host "  logs : $LogDirectory"
}
exit $ExitCode
