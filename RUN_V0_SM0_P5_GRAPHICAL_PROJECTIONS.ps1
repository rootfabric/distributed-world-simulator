[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    [switch]$Visual,
    [int]$VisualHoldSeconds = 8,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) { throw "Godot project.godot missing: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot 4.7.1 double console executable missing: $GodotExe" }
if ($Visual -and -not (Test-Path -LiteralPath $GodotGuiExe -PathType Leaf)) { throw "Godot 4.7.1 double GUI executable missing: $GodotGuiExe" }
if ($VisualHoldSeconds -lt 1 -or $VisualHoldSeconds -gt 300) { throw "VisualHoldSeconds must be 1..300." }

$GitHead = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) { throw "Unable to resolve exact git HEAD." }
$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P5.1 graphical projection gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")" }

Write-Host "[SM0-P5.1] Re-running inherited P5 authority/projection gate first..."
$P5Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P5_PROJECTIONS.ps1"
if (-not (Test-Path -LiteralPath $P5Runner -PathType Leaf)) { throw "Inherited P5 runner missing: $P5Runner" }
& $P5Runner -ProjectRoot $ProjectRoot -GodotExe $GodotExe -AllowDirty:$AllowDirty
if ($LASTEXITCODE -ne 0) { throw "Inherited SM0 P5 projection gate failed." }

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

$Ports = @(25980, 25981, 25990, 25991)
foreach ($Port in $Ports) {
    if (-not (Test-UdpPortAvailable $Port)) { throw "P5.1 graphical projection gate requires free UDP loopback port $Port." }
}

$Scripts = @(
    "res://scripts/runtime/seamless/sm0/sm0_p5_projection_view_contract.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_observer.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_process.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_host.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_host_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_p5_graphical_projections.gd"
)
foreach ($ScriptPath in $Scripts) {
    Write-Host "[SM0-P5.1] Compile check: $ScriptPath"
    & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
    if ($LASTEXITCODE -ne 0) { throw "P5.1 compile check failed: $ScriptPath" }
}

Write-Host "[SM0-P5.1] Running focused graphical projection regression..."
& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p5_graphical_projections.gd
if ($LASTEXITCODE -ne 0) { throw "SM0 P5.1 focused graphical projection regression failed." }
foreach ($Port in $Ports) {
    if (-not (Test-UdpPortAvailable $Port)) { throw "P5.1 focused regression did not release UDP port $Port." }
}

$RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$LogRoot = Join-Path ([IO.Path]::GetTempPath()) "dws-sm0-p5-1-$RunId"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$StopFile = Join-Path $LogRoot "stop.flag"
$LogServerA = Join-Path $LogRoot "server-a.log"
$LogServerB = Join-Path $LogRoot "server-b.log"
$LogObserverA = Join-Path $LogRoot "observer-a.log"
$LogObserverB = Join-Path $LogRoot "observer-b.log"
$Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

function Quote-Arg([string]$Value) { return '"' + $Value + '"' }

function Start-SM0Process {
    param(
        [string]$Label,
        [string]$Exe,
        [bool]$Headless,
        [string]$Script,
        [string]$LogFile,
        [string[]]$UserArgs
    )
    $Args = @()
    if ($Headless) { $Args += "--headless" }
    $Args += @(
        "--path", (Quote-Arg $ProjectRoot),
        "--log-file", (Quote-Arg $LogFile),
        "--script", $Script,
        "--"
    )
    $Args += $UserArgs
    $WindowStyle = if ($Headless) { "Hidden" } else { "Normal" }
    $PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        # Multi-process SM0 acceptance must not let every Godot process compete
        # for the breakpoint_mcp runtime bridge's single loopback TCP port 9081.
        # runtime_bridge.gd explicitly supports this environment escape hatch.
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process -FilePath $Exe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle $WindowStyle -PassThru
    }
    finally {
        if ($null -eq $PreviousBreakpointRuntimeDisabled) {
            Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
        }
        else {
            $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled
        }
    }
    Write-Host "[SM0-P5.1] $Label PID=$($Process.Id) log=$LogFile"
    return $Process
}

function Wait-LogMarker {
    param([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds, [string]$Label)
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue) { return }
            foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "setup_failed")) {
                if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "$Label contains fatal marker '$Fatal'. See $Path" }
            }
        }
        $Process.Refresh()
        if ($Process.HasExited) { throw "$Label exited code=$($Process.ExitCode) before '$Marker'. See $Path" }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for '$Marker' from $Label. See $Path"
}

try {
    $ObserverExe = if ($Visual) { $GodotGuiExe } else { $GodotExe }
    $ObserverA = Start-SM0Process -Label "observer-a" -Exe $ObserverExe -Headless:(-not $Visual) `
        -Script "res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_process.gd" -LogFile $LogObserverA -UserArgs @(
            "--viewer-authority-id=authority/sm0/a", "--listen-port=25990", "--stop-file=$StopFile"
        )
    $Processes.Add($ObserverA)
    $ObserverB = Start-SM0Process -Label "observer-b" -Exe $ObserverExe -Headless:(-not $Visual) `
        -Script "res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_process.gd" -LogFile $LogObserverB -UserArgs @(
            "--viewer-authority-id=authority/sm0/b", "--listen-port=25991", "--stop-file=$StopFile"
        )
    $Processes.Add($ObserverB)

    Wait-LogMarker $LogObserverA '"event":"SM0_P5_GRAPHICAL_VIEW_READY"' $ObserverA 15 "observer-a"
    Wait-LogMarker $LogObserverB '"event":"SM0_P5_GRAPHICAL_VIEW_READY"' $ObserverB 15 "observer-b"

    $ServerA = Start-SM0Process -Label "server-a" -Exe $GodotExe -Headless:$true `
        -Script "res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_host_process.gd" -LogFile $LogServerA -UserArgs @(
            "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west", "--local-player-id=a",
            "--control-port=25980", "--peer-control-port=25981", "--view-port=25990", "--stop-file=$StopFile",
            "--demo-motion=true"
        )
    $Processes.Add($ServerA)
    $ServerB = Start-SM0Process -Label "server-b" -Exe $GodotExe -Headless:$true `
        -Script "res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_host_process.gd" -LogFile $LogServerB -UserArgs @(
            "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east", "--local-player-id=b",
            "--control-port=25981", "--peer-control-port=25980", "--view-port=25991", "--stop-file=$StopFile",
            "--demo-motion=true"
        )
    $Processes.Add($ServerB)

    Wait-LogMarker $LogServerA '"event":"SM0_P5_PROJECTION_ACCEPTED"' $ServerA 15 "server-a"
    Wait-LogMarker $LogServerB '"event":"SM0_P5_PROJECTION_ACCEPTED"' $ServerB 15 "server-b"
    Wait-LogMarker $LogObserverA '"event":"SM0_P5_GRAPHICAL_LOCAL_VISIBLE"' $ObserverA 15 "observer-a"
    Wait-LogMarker $LogObserverB '"event":"SM0_P5_GRAPHICAL_LOCAL_VISIBLE"' $ObserverB 15 "observer-b"
    Wait-LogMarker $LogObserverA '"event":"SM0_P5_GRAPHICAL_REMOTE_VISIBLE"' $ObserverA 15 "observer-a"
    Wait-LogMarker $LogObserverB '"event":"SM0_P5_GRAPHICAL_REMOTE_VISIBLE"' $ObserverB 15 "observer-b"
    Wait-LogMarker $LogServerA '"event":"SM0_P5_GRAPHICAL_DEMO_MOVED"' $ServerA 15 "server-a"
    Wait-LogMarker $LogServerB '"event":"SM0_P5_GRAPHICAL_DEMO_MOVED"' $ServerB 15 "server-b"
    Wait-LogMarker $LogObserverA '"event":"SM0_P5_GRAPHICAL_LOCAL_MOVED"' $ObserverA 15 "observer-a"
    Wait-LogMarker $LogObserverA '"event":"SM0_P5_GRAPHICAL_REMOTE_MOVED"' $ObserverA 15 "observer-a"
    Wait-LogMarker $LogObserverB '"event":"SM0_P5_GRAPHICAL_LOCAL_MOVED"' $ObserverB 15 "observer-b"
    Wait-LogMarker $LogObserverB '"event":"SM0_P5_GRAPHICAL_REMOTE_MOVED"' $ObserverB 15 "observer-b"

    if (-not (Select-String -LiteralPath $LogObserverA -SimpleMatch '"logical_player_id":"b"' -Quiet)) { throw "Observer A did not render remote player b." }
    if (-not (Select-String -LiteralPath $LogObserverB -SimpleMatch '"logical_player_id":"a"' -Quiet)) { throw "Observer B did not render remote player a." }
    foreach ($Path in @($LogObserverA, $LogObserverB)) {
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"writer_count":0' -Quiet)) { throw "Graphical observer must remain writer_count=0: $Path" }
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"command_channel":false' -Quiet)) { throw "Graphical observer must prove command_channel=false: $Path" }
    }
    foreach ($Path in @($LogServerA, $LogServerB)) {
        if (Select-String -LiteralPath $Path -SimpleMatch '"writer_count":2' -Quiet -ErrorAction SilentlyContinue) { throw "P5.1 observed duplicate canonical writer count: $Path" }
    }

    if ($Visual) {
        Write-Host "[SM0-P5.1] Visual proof is live for $VisualHoldSeconds seconds: WHITE=local derived view, GREEN=remote read-only projection; canonical hosts move automatically."
        Write-Host "[SM0-P5.1] The graphical observer windows remain read-only by design; keyboard input is not a command channel in P5.1."
        Start-Sleep -Seconds $VisualHoldSeconds
    }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Process in $Processes) {
        if (-not $Process.WaitForExit(10000)) { throw "P5.1 process PID=$($Process.Id) did not stop cleanly." }
        if ($Process.ExitCode -ne 0) { throw "P5.1 process PID=$($Process.Id) exited code=$($Process.ExitCode)." }
    }
}
finally {
    if (-not (Test-Path -LiteralPath $StopFile -PathType Leaf)) { New-Item -ItemType File -Force -Path $StopFile -ErrorAction SilentlyContinue | Out-Null }
    foreach ($Process in $Processes) {
        try { $Process.Refresh(); if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } } catch { }
    }
}

foreach ($Path in @($LogServerA, $LogServerB, $LogObserverA, $LogObserverB)) {
    foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "ERROR:")) {
        if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "P5.1 final log scan found '$Fatal' in $Path" }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed after P5.1 gate" }
if (-not $AllowDirty -and (($StatusAfter -join "`n") -ne ($StatusBefore -join "`n"))) { throw "P5.1 gate mutated the source worktree." }

Write-Host ""
Write-Host "SM0-P5.1 graphical cross-authority projections: PASS" -ForegroundColor Green
Write-Host "  HEAD       : $GitHead"
Write-Host "  observer A : local player/a + remote read-only player/b"
Write-Host "  observer B : local player/b + remote read-only player/a"
Write-Host "  observers  : writer_count=0 / command_channel=false"
Write-Host "  motion     : canonical A/B auto-motion observed locally and through remote projections"
Write-Host "  servers    : one canonical writer each"
Write-Host "  P4 handoff : unchanged"
Write-Host "  P6 pivot   : NOT implemented"
Write-Host "  visual     : $Visual"
Write-Host "  logs       : $LogRoot"
