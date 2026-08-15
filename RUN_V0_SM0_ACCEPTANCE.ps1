[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$Handoffs = 4,

    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,

    [string]$ProjectRoot = "",

    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",

    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

$CanonicalWorkspaceRoot = "C:\distributed-world-simulator"
$CanonicalCentralCheckout = "C:\distributed-world-simulator\distributed-world-simulator"
$ClientPort = 24780

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

if (-not $ProjectRoot.StartsWith($CanonicalWorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0 Windows tests must run from the canonical workspace root $CanonicalWorkspaceRoot. Current project: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project.godot not found under: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot 4.7.1 double console executable not found: $GodotExe"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$LauncherRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0Seamless"
$StatePath = Join-Path $LauncherRoot "session.json"
$LogsRoot = Join-Path $LauncherRoot "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-ProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -lt 1) { return $false }
    try {
        Get-Process -Id $ProcessId -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}

function Stop-Sm0Session {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        Write-Host "[SM0] No managed session is recorded."
        return
    }
    try { $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
    catch {
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
        Write-Warning "[SM0] Removed unreadable session state."
        return
    }
    foreach ($Record in @($State.processes)) {
        $Pid = [int]$Record.pid
        if (Test-ProcessAlive $Pid) {
            Write-Host "[SM0] Stopping $($Record.role) (PID $Pid)..."
            Stop-Process -Id $Pid -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    Write-Host "[SM0] Managed session stopped."
}

if ($Stop) {
    Stop-Sm0Session
    exit 0
}

if ($Restart) {
    Stop-Sm0Session
}
elseif (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    try {
        $Existing = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        $Live = @($Existing.processes | Where-Object { Test-ProcessAlive ([int]$_.pid) })
        if ($Live.Count -gt 0) {
            throw "An SM0 session is already running. Use -Restart or -Stop."
        }
    }
    catch {
        if ($_.Exception.Message -like "An SM0 session is already running*") { throw }
    }
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
}

if ($Final) { $Handoffs = 20 }
if ($Final -and $TimeoutSeconds -lt 180) { $TimeoutSeconds = 180 }

$GitHead = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) { throw "Unable to resolve git HEAD for $ProjectRoot" }
$GitStatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($GitStatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0 acceptance requires a clean worktree. Current changes:`n$($GitStatusBefore -join "`n")"
}

$SessionId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDirectory = Join-Path $LogsRoot $SessionId
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$StopFile = Join-Path $LogDirectory "stop.flag"
$ContractLog = Join-Path $LogDirectory "contracts.log"
$ServerALog = Join-Path $LogDirectory "server-a.log"
$ServerBLog = Join-Path $LogDirectory "server-b.log"
$ClientLog = Join-Path $LogDirectory "client.log"
$ClientResult = Join-Path $LogDirectory "client-result.json"
$HarnessLog = Join-Path $LogDirectory "harness.log"

function Write-Harness {
    param([string]$Message)
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Quote-Arg {
    param([string]$Value)
    return '"' + $Value + '"'
}

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

    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process `
            -FilePath $GodotExe `
            -ArgumentList $Args `
            -WorkingDirectory $ProjectRoot `
            -WindowStyle Hidden `
            -PassThru
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    Write-Harness "$Role started PID=$($Process.Id) log=$LogFile"
    return $Process
}

function Wait-LogMarker {
    param(
        [string]$Path,
        [string]$Marker,
        [System.Diagnostics.Process]$Process,
        [int]$Seconds
    )
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process PID=$($Process.Id) exited before marker '$Marker'. Log: $Path"
        }
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue) {
                return
            }
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Timeout waiting for '$Marker'. Log: $Path"
}

Write-Harness "SM0 acceptance start"
Write-Harness "workspace root: $CanonicalWorkspaceRoot"
Write-Harness "central checkout: $CanonicalCentralCheckout"
Write-Harness "project root: $ProjectRoot"
Write-Harness "git HEAD: $GitHead"
Write-Harness "Godot: $GodotExe"
Write-Harness "handoffs: $Handoffs"
Write-Harness "stable client UDP port: $ClientPort"

$Processes = @()
$ServerA = $null
$ServerB = $null
$Client = $null
$ExitCode = 1

try {
    Write-Harness "Running SM0 contract tests..."
    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe `
            --headless `
            --path $ProjectRoot `
            --log-file $ContractLog `
            --script res://tests/runtime/seamless/sm0/test_sm0_contracts.gd
        $ContractExit = $LASTEXITCODE
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($ContractExit -ne 0) {
        throw "SM0 contract tests failed with exit code $ContractExit. Log: $ContractLog"
    }

    $ServerA = Start-Sm0Godot `
        -Role "server-a" `
        -LogFile $ServerALog `
        -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd" `
        -UserArgs @(
            "--authority-id=authority/sm0/a",
            "--zone-id=zone/earth/sm0/west",
            "--gameplay-port=24580",
            "--control-port=24680",
            "--peer-control-port=24681",
            "--stop-file=$StopFile"
        )
    $Processes += [ordered]@{ role = "server-a"; pid = $ServerA.Id; log = $ServerALog }

    $ServerB = Start-Sm0Godot `
        -Role "server-b" `
        -LogFile $ServerBLog `
        -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd" `
        -UserArgs @(
            "--authority-id=authority/sm0/b",
            "--zone-id=zone/earth/sm0/east",
            "--gameplay-port=24581",
            "--control-port=24681",
            "--peer-control-port=24680",
            "--stop-file=$StopFile"
        )
    $Processes += [ordered]@{ role = "server-b"; pid = $ServerB.Id; log = $ServerBLog }

    $State = [ordered]@{
        schema = "distributed_world_simulator.sm0_launcher_state.v1"
        project_root = $ProjectRoot
        git_head = $GitHead
        log_directory = $LogDirectory
        processes = @($Processes)
    }
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-LogMarker -Path $ServerALog -Marker '"event":"SM0_SERVER_READY"' -Process $ServerA -Seconds 15
    Wait-LogMarker -Path $ServerBLog -Marker '"event":"SM0_SERVER_READY"' -Process $ServerB -Seconds 15
    Wait-LogMarker -Path $ServerALog -Marker '"event":"SM0_AUTHORITY_PEER_SYNCED"' -Process $ServerA -Seconds 15
    Wait-LogMarker -Path $ServerBLog -Marker '"event":"SM0_AUTHORITY_PEER_SYNCED"' -Process $ServerB -Seconds 15
    Wait-LogMarker -Path $ServerALog -Marker '"event":"SM0_DIRECTORY_READY"' -Process $ServerA -Seconds 15
    Wait-LogMarker -Path $ServerBLog -Marker '"event":"SM0_DIRECTORY_READY"' -Process $ServerB -Seconds 15
    Write-Harness "Both authority servers are synchronized."

    $ClientTimeoutMs = $TimeoutSeconds * 1000
    $Client = Start-Sm0Godot `
        -Role "client-driver" `
        -LogFile $ClientLog `
        -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd" `
        -UserArgs @(
            "--server-host=127.0.0.1",
            "--server-a-port=24580",
            "--server-b-port=24581",
            "--client-port=$ClientPort",
            "--handoffs=$Handoffs",
            "--timeout-ms=$ClientTimeoutMs",
            "--result-file=$ClientResult"
        )
    $Processes += [ordered]@{ role = "client-driver"; pid = $Client.Id; log = $ClientLog }
    $State.processes = @($Processes)
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds + 10)
    while (-not $Client.HasExited -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 100
        $Client.Refresh()
        $ServerA.Refresh()
        $ServerB.Refresh()
        if ($ServerA.HasExited) { throw "Server A exited unexpectedly. Log: $ServerALog" }
        if ($ServerB.HasExited) { throw "Server B exited unexpectedly. Log: $ServerBLog" }
    }
    if (-not $Client.HasExited) {
        throw "SM0 client timed out. Log: $ClientLog"
    }
    Write-Harness "Client driver exited code=$($Client.ExitCode)"

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($ServerA, $ServerB)) {
        $ServerDeadline = (Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date) -lt $ServerDeadline) {
            Start-Sleep -Milliseconds 100
            $Server.Refresh()
        }
        if (-not $Server.HasExited) {
            Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue
            Write-Harness "Server PID=$($Server.Id) required forced stop after stop-file timeout."
        }
    }

    $Analyzer = Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1"
    & $Analyzer -LogDirectory $LogDirectory -ExpectedHandoffs $Handoffs
    $AnalyzeExit = $LASTEXITCODE
    if ($Client.ExitCode -ne 0) { throw "SM0 client reported failure. See $ClientLog" }
    if ($AnalyzeExit -ne 0) { throw "SM0 log analysis failed. See $LogDirectory\summary.json" }

    $GitStatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after SM0 acceptance" }
    if (-not $AllowDirty) {
        if (($GitStatusAfter -join "`n") -ne ($GitStatusBefore -join "`n")) {
            throw "SM0 acceptance mutated the tracked worktree. Before:`n$($GitStatusBefore -join "`n")`nAfter:`n$($GitStatusAfter -join "`n")"
        }
    }

    Write-Harness "SM0 acceptance PASS"
    $ExitCode = 0
}
catch {
    Write-Harness "SM0 acceptance FAIL: $($_.Exception.Message)"
    Write-Error $_ -ErrorAction Continue
}
finally {
    if (-not (Test-Path -LiteralPath $StopFile -PathType Leaf)) {
        New-Item -ItemType File -Force -Path $StopFile -ErrorAction SilentlyContinue | Out-Null
    }
    foreach ($Record in @($Processes)) {
        $Pid = [int]$Record.pid
        if (Test-ProcessAlive $Pid) {
            Stop-Process -Id $Pid -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
}

$ResultText = if ($ExitCode -eq 0) { "PASS" } else { "FAIL" }
$ResultColor = if ($ExitCode -eq 0) { "Green" } else { "Red" }
Write-Host ""
Write-Host "[SM0] Result : $ResultText" -ForegroundColor $ResultColor
Write-Host "[SM0] HEAD   : $GitHead"
Write-Host "[SM0] Root   : $ProjectRoot"
Write-Host "[SM0] Logs   : $LogDirectory"
Write-Host "[SM0] Summary: $(Join-Path $LogDirectory 'summary.json')"

exit $ExitCode
