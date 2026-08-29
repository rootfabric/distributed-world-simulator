[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    [int]$Handoffs = 2,
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
if ($Handoffs -lt 2 -or ($Handoffs % 2) -ne 0 -or $Handoffs -gt 20) { throw "P6 Handoffs must be an even value in 2..20." }
if ($VisualHoldSeconds -lt 1 -or $VisualHoldSeconds -gt 300) { throw "VisualHoldSeconds must be 1..300." }

$GitHead = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) { throw "Unable to resolve exact git HEAD." }
$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P6 projection pivot gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")" }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$PreviousP4Fast = $env:SM0_P4_FAST_HANDOFF
$env:BREAKPOINT_RUNTIME_DISABLED = "1"

try {
    Write-Host "[SM0-P6] Re-running inherited P5.1 graphical projection gate first..."
    $P51Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P5_GRAPHICAL_PROJECTIONS.ps1"
    if (-not (Test-Path -LiteralPath $P51Runner -PathType Leaf)) { throw "Inherited P5.1 runner missing: $P51Runner" }
    & $P51Runner -ProjectRoot $ProjectRoot -GodotExe $GodotExe -GodotGuiExe $GodotGuiExe -AllowDirty:$AllowDirty
    if ($LASTEXITCODE -ne 0) { throw "Inherited SM0 P5.1 graphical projection gate failed." }

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

    $Ports = @(24580, 24581, 24680, 24681, 24780, 26100, 26101, 26110)
    foreach ($Port in $Ports) {
        if (-not (Test-UdpPortAvailable $Port)) { throw "P6 projection pivot gate requires free UDP loopback port $Port." }
    }

    $Scripts = @(
        "res://scripts/runtime/seamless/sm0/sm0_p6_pivot_view_contract.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_server.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_server_process.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_observer.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_observer_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p6_projection_pivot.gd"
    )
    foreach ($ScriptPath in $Scripts) {
        Write-Host "[SM0-P6] Compile check: $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "P6 compile check failed: $ScriptPath" }
    }

    Write-Host "[SM0-P6] Running focused persistent-visual pivot regression..."
    $FocusedOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p6_projection_pivot.gd 2>&1)
    $FocusedOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "SM0 P6 focused projection/canonical pivot regression failed." }
    if (-not (($FocusedOutput -join "`n") -match 'SM0 P6 projection/canonical pivot: PASS \(30 assertions\)')) {
        throw "SM0 P6 focused regression did not emit the exact 30-assertion PASS marker."
    }
    foreach ($Port in $Ports) {
        if (-not (Test-UdpPortAvailable $Port)) { throw "P6 focused regression did not release UDP port $Port." }
    }

    $RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $LogRoot = Join-Path ([IO.Path]::GetTempPath()) "dws-sm0-p6-$RunId"
    $RecoveryRoot = Join-Path $LogRoot "recovery"
    New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
    $StopFile = Join-Path $LogRoot "stop.flag"
    $ResultFile = Join-Path $LogRoot "client-result.json"
    $LogServerA = Join-Path $LogRoot "server-a.log"
    $LogServerB = Join-Path $LogRoot "server-b.log"
    $LogObserverA = Join-Path $LogRoot "observer-a.log"
    $LogObserverB = Join-Path $LogRoot "observer-b.log"
    $LogClient = Join-Path $LogRoot "client.log"
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
        $Process = Start-Process -FilePath $Exe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle $WindowStyle -PassThru
        Write-Host "[SM0-P6] $Label PID=$($Process.Id) log=$LogFile"
        return $Process
    }

    function Wait-LogMarker {
        param([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds, [string]$Label)
        $Deadline = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $Deadline) {
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                if (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue) { return }
                foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "setup_failed", "SM0_INVARIANT_VIOLATION", "SM0_P6_VISUAL_IDENTITY_VIOLATION")) {
                    if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "$Label contains fatal marker '$Fatal'. See $Path" }
                }
            }
            $Process.Refresh()
            if ($Process.HasExited) { throw "$Label exited code=$($Process.ExitCode) before '$Marker'. See $Path" }
            Start-Sleep -Milliseconds 50
        }
        throw "Timeout waiting for '$Marker' from $Label. See $Path"
    }

    function Get-Sm0Events {
        param([string]$Path)
        $Events = @()
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Events }
        foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
            $Marker = "[SM0_EVENT] "
            $Index = $Line.IndexOf($Marker)
            if ($Index -lt 0) { continue }
            $Json = $Line.Substring($Index + $Marker.Length)
            try { $Events += ($Json | ConvertFrom-Json -ErrorAction Stop) } catch { }
        }
        return $Events
    }

    $env:SM0_P4_FAST_HANDOFF = "1"
    try {
        $ObserverExe = if ($Visual) { $GodotGuiExe } else { $GodotExe }
        $ObserverA = Start-SM0Process -Label "observer-a" -Exe $ObserverExe -Headless:(-not $Visual) `
            -Script "res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_observer_process.gd" -LogFile $LogObserverA -UserArgs @(
                "--viewer-authority-id=authority/sm0/a", "--listen-port=26100", "--stop-file=$StopFile"
            )
        $Processes.Add($ObserverA)
        $ObserverB = Start-SM0Process -Label "observer-b" -Exe $ObserverExe -Headless:(-not $Visual) `
            -Script "res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_observer_process.gd" -LogFile $LogObserverB -UserArgs @(
                "--viewer-authority-id=authority/sm0/b", "--listen-port=26101", "--stop-file=$StopFile"
            )
        $Processes.Add($ObserverB)
        Wait-LogMarker $LogObserverA '"event":"SM0_P6_OBSERVER_READY"' $ObserverA 15 "observer-a"
        Wait-LogMarker $LogObserverB '"event":"SM0_P6_OBSERVER_READY"' $ObserverB 15 "observer-b"

        $ServerA = Start-SM0Process -Label "server-a" -Exe $GodotExe -Headless:$true `
            -Script "res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_server_process.gd" -LogFile $LogServerA -UserArgs @(
                "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
                "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681",
                "--view-port=26100", "--recovery-dir=$RecoveryRoot", "--stop-file=$StopFile"
            )
        $Processes.Add($ServerA)
        $ServerB = Start-SM0Process -Label "server-b" -Exe $GodotExe -Headless:$true `
            -Script "res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_server_process.gd" -LogFile $LogServerB -UserArgs @(
                "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
                "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680",
                "--view-port=26101", "--recovery-dir=$RecoveryRoot", "--stop-file=$StopFile"
            )
        $Processes.Add($ServerB)

        Wait-LogMarker $LogServerA '"event":"SM0_P6_READY"' $ServerA 20 "server-a"
        Wait-LogMarker $LogServerB '"event":"SM0_P6_READY"' $ServerB 20 "server-b"
        Wait-LogMarker $LogServerA '"event":"SM0_AUTHORITY_PEER_SYNCED"' $ServerA 20 "server-a"
        Wait-LogMarker $LogServerB '"event":"SM0_AUTHORITY_PEER_SYNCED"' $ServerB 20 "server-b"

        $SettleSteps = if ($Visual) { 8 } else { 4 }
        $Client = Start-SM0Process -Label "client" -Exe $GodotExe -Headless:$true `
            -Script "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd" -LogFile $LogClient -UserArgs @(
                "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780",
                "--handoffs=$Handoffs", "--timeout-ms=90000", "--post-handoff-settle-steps=$SettleSteps",
                "--result-file=$ResultFile"
            )
        $Processes.Add($Client)

        if (-not $Client.WaitForExit(95000)) { throw "P6 automated handoff client timed out. See $LogClient" }
        if ($Client.ExitCode -ne 0) { throw "P6 automated handoff client exited code=$($Client.ExitCode). See $LogClient" }

        Wait-LogMarker $LogObserverA '"event":"SM0_P6_CANONICAL_TO_PROJECTION"' $ObserverA 15 "observer-a"
        Wait-LogMarker $LogObserverA '"event":"SM0_P6_PROJECTION_TO_CANONICAL"' $ObserverA 15 "observer-a"
        Wait-LogMarker $LogObserverB '"event":"SM0_P6_PROJECTION_TO_CANONICAL"' $ObserverB 15 "observer-b"
        Wait-LogMarker $LogObserverB '"event":"SM0_P6_CANONICAL_TO_PROJECTION"' $ObserverB 15 "observer-b"
        Wait-LogMarker $LogServerA '"event":"SM0_P4_FAST_COMMIT_ACCEPTED"' $ServerA 15 "server-a"
        Wait-LogMarker $LogServerB '"event":"SM0_P4_FAST_COMMIT_ACCEPTED"' $ServerB 15 "server-b"

        foreach ($ObserverPath in @($LogObserverA, $LogObserverB)) {
            $Events = @(Get-Sm0Events $ObserverPath)
            $VisualEvents = @($Events | Where-Object { $_.event -in @("SM0_P6_PLAYER_VISIBLE", "SM0_P6_PROJECTION_TO_CANONICAL", "SM0_P6_CANONICAL_TO_PROJECTION") })
            if ($VisualEvents.Count -lt 3) { throw "P6 observer lacks complete visible/pivot evidence: $ObserverPath" }
            $InstanceIds = @($VisualEvents | ForEach-Object { [string]$_.visual_instance_id } | Sort-Object -Unique)
            if ($InstanceIds.Count -ne 1 -or [string]::IsNullOrWhiteSpace($InstanceIds[0])) { throw "P6 observer respawned/replaced the visual entity: $ObserverPath ids=$($InstanceIds -join ',')" }
            foreach ($Event in $VisualEvents) {
                if ([string]$Event.player_entity_id -ne "player/a") { throw "P6 observer changed player_entity_id: $ObserverPath" }
                if ($Event.PSObject.Properties.Name -contains "command_channel" -and [bool]$Event.command_channel) { throw "P6 observer exposed a command channel: $ObserverPath" }
            }
        }

        foreach ($ServerPath in @($LogServerA, $LogServerB)) {
            $Events = @(Get-Sm0Events $ServerPath)
            if (@($Events | Where-Object { [int]$_.writer_count -gt 1 }).Count -gt 0) { throw "P6 server observed writer_count > 1: $ServerPath" }
            if (@($Events | Where-Object { $_.event -eq "SM0_P6_SERVER_ROLE_PIVOT" }).Count -lt 2) { throw "P6 server did not observe both stable role pivots: $ServerPath" }
        }

        $FastCommits = 0
        foreach ($ServerPath in @($LogServerA, $LogServerB)) {
            $FastCommits += @(Select-String -LiteralPath $ServerPath -SimpleMatch '"event":"SM0_P4_FAST_COMMIT_ACCEPTED"' -ErrorAction SilentlyContinue).Count
        }
        if ($FastCommits -lt $Handoffs) { throw "P6 expected at least $Handoffs P4 fast commits, observed $FastCommits." }
        if (-not (Select-String -LiteralPath $LogClient -SimpleMatch '"identity_changes":0' -Quiet -ErrorAction SilentlyContinue)) {
            throw "P6 client log does not prove identity_changes=0. See $LogClient"
        }

        if ($Visual) {
            Write-Host "[SM0-P6] Visual pivot proof completed $Handoffs handoffs. WHITE=canonical, GREEN=projection, YELLOW=handoff hold."
            Write-Host "[SM0-P6] Both windows retain one MeshInstance3D for player/a; color/role pivots without respawn. Holding for $VisualHoldSeconds seconds."
            Start-Sleep -Seconds $VisualHoldSeconds
        }

        New-Item -ItemType File -Force -Path $StopFile | Out-Null
        foreach ($Process in $Processes) {
            $Process.Refresh()
            if ($Process.HasExited) { continue }
            if (-not $Process.WaitForExit(10000)) { throw "P6 process PID=$($Process.Id) did not stop cleanly." }
            if ($Process.ExitCode -ne 0) { throw "P6 process PID=$($Process.Id) exited code=$($Process.ExitCode)." }
        }
    }
    finally {
        if (-not (Test-Path -LiteralPath $StopFile -PathType Leaf)) { New-Item -ItemType File -Force -Path $StopFile -ErrorAction SilentlyContinue | Out-Null }
        foreach ($Process in $Processes) {
            try { $Process.Refresh(); if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } } catch { }
        }
    }

    foreach ($Path in @($LogServerA, $LogServerB, $LogObserverA, $LogObserverB, $LogClient)) {
        foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "ERROR:", "SM0_INVARIANT_VIOLATION", "SM0_P6_VISUAL_IDENTITY_VIOLATION", "SM0_P6_PROJECTION_REJECTED")) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "P6 final log scan found '$Fatal' in $Path" }
        }
    }

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P6 gate" }
    if (-not $AllowDirty -and (($StatusAfter -join "`n") -ne ($StatusBefore -join "`n"))) { throw "P6 gate mutated the source worktree." }

    Write-Host ""
    Write-Host "SM0-P6 projection/canonical pivot during P4 handoff: PASS" -ForegroundColor Green
    Write-Host "  HEAD       : $GitHead"
    Write-Host "  handoffs   : $Handoffs P4_FAST"
    Write-Host "  observer A : canonical -> projection -> canonical on persistent player/a visual"
    Write-Host "  observer B : projection -> canonical -> projection on persistent player/a visual"
    Write-Host "  identity   : player/a stable / visual instance stable per observer"
    Write-Host "  observers  : writer_count=0 / command_channel=false"
    Write-Host "  P4 protocol: unchanged (subclass composition only)"
    Write-Host "  visual     : $Visual"
    Write-Host "  logs       : $LogRoot"
}
finally {
    if ($null -eq $PreviousBridgeDisabled) { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBridgeDisabled }
    if ($null -eq $PreviousP4Fast) { Remove-Item Env:SM0_P4_FAST_HANDOFF -ErrorAction SilentlyContinue } else { $env:SM0_P4_FAST_HANDOFF = $PreviousP4Fast }
}