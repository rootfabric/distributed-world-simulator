[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) { throw "Godot project.godot missing: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot 4.7.1 double console executable missing: $GodotExe" }

$GitHead = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) { throw "Unable to resolve exact git HEAD." }
$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P7 three-authority routing gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")" }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED = "1"

try {
    Write-Host "[SM0-P7] Re-running inherited P6 projection/canonical pivot gate first..."
    $P6Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P6_PROJECTION_PIVOT.ps1"
    if (-not (Test-Path -LiteralPath $P6Runner -PathType Leaf)) { throw "Inherited P6 runner missing: $P6Runner" }
    & $P6Runner -ProjectRoot $ProjectRoot -GodotExe $GodotExe -GodotGuiExe $GodotGuiExe -Handoffs 2 -AllowDirty:$AllowDirty
    if ($LASTEXITCODE -ne 0) { throw "Inherited SM0 P6 projection/canonical pivot gate failed." }

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

    $Ports = @(26200, 26201, 26202, 26210, 26211, 26212)
    foreach ($Port in $Ports) {
        if (-not (Test-UdpPortAvailable $Port)) { throw "P7 routing gate requires free UDP loopback port $Port." }
    }

    $Scripts = @(
        "res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p7_route_contract.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p7_router_node.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p7_router_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p7_three_authority_routing.gd"
    )
    foreach ($ScriptPath in $Scripts) {
        Write-Host "[SM0-P7] Compile check: $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "P7 compile check failed: $ScriptPath" }
    }

    Write-Host "[SM0-P7] Running focused three-authority routing regression..."
    $FocusedOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p7_three_authority_routing.gd 2>&1)
    $FocusedOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "SM0 P7 focused three-authority routing regression failed." }
    if (-not (($FocusedOutput -join "`n") -match 'SM0 P7 three-authority routing: PASS \(40 assertions\)')) {
        throw "SM0 P7 focused regression did not emit the exact 40-assertion PASS marker."
    }
    foreach ($Port in $Ports) {
        if (-not (Test-UdpPortAvailable $Port)) { throw "P7 focused regression did not release UDP port $Port." }
    }

    $RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $LogRoot = Join-Path ([IO.Path]::GetTempPath()) "dws-sm0-p7-$RunId"
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
    $StartFile = Join-Path $LogRoot "start.flag"
    $StopFile = Join-Path $LogRoot "stop.flag"
    $LogA = Join-Path $LogRoot "router-a.log"
    $LogB = Join-Path $LogRoot "router-b.log"
    $LogC = Join-Path $LogRoot "router-c.log"
    $Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

    function Quote-Arg([string]$Value) { return '"' + $Value + '"' }

    function Start-P7Router {
        param([string]$Label, [string]$LogFile, [string[]]$UserArgs)
        $Args = @(
            "--headless",
            "--path", (Quote-Arg $ProjectRoot),
            "--log-file", (Quote-Arg $LogFile),
            "--script", "res://scripts/runtime/seamless/sm0/sm0_p7_router_process.gd",
            "--"
        )
        $Args += $UserArgs
        $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
        Write-Host "[SM0-P7] $Label PID=$($Process.Id) log=$LogFile"
        return $Process
    }

    function Wait-LogMarker {
        param([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds, [string]$Label)
        $Deadline = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $Deadline) {
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                if (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue) { return }
                foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "setup_failed", "SM0_INVARIANT_VIOLATION")) {
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

    try {
        $RouterB = Start-P7Router -Label "router-b" -LogFile $LogB -UserArgs @(
            "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/central", "--listen-port=26201",
            "--neighbor-a-port=26200", "--neighbor-c-port=26202", "--start-file=$StartFile", "--stop-file=$StopFile"
        )
        $Processes.Add($RouterB)
        $RouterA = Start-P7Router -Label "router-a" -LogFile $LogA -UserArgs @(
            "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west", "--listen-port=26200",
            "--neighbor-b-port=26201", "--auto-probe-destination=authority/sm0/c", "--start-file=$StartFile", "--stop-file=$StopFile"
        )
        $Processes.Add($RouterA)
        $RouterC = Start-P7Router -Label "router-c" -LogFile $LogC -UserArgs @(
            "--authority-id=authority/sm0/c", "--zone-id=zone/earth/sm0/east", "--listen-port=26202",
            "--neighbor-b-port=26201", "--auto-probe-destination=authority/sm0/a", "--start-file=$StartFile", "--stop-file=$StopFile"
        )
        $Processes.Add($RouterC)

        Wait-LogMarker $LogA '"event":"SM0_P7_ROUTER_READY"' $RouterA 15 "router-a"
        Wait-LogMarker $LogB '"event":"SM0_P7_ROUTER_READY"' $RouterB 15 "router-b"
        Wait-LogMarker $LogC '"event":"SM0_P7_ROUTER_READY"' $RouterC 15 "router-c"
        New-Item -ItemType File -Force -Path $StartFile | Out-Null

        Wait-LogMarker $LogA '"event":"SM0_P7_ROUTE_DELIVERED"' $RouterA 15 "router-a"
        Wait-LogMarker $LogC '"event":"SM0_P7_ROUTE_DELIVERED"' $RouterC 15 "router-c"
        Wait-LogMarker $LogB '"event":"SM0_P7_ROUTE_FORWARDED"' $RouterB 15 "router-b"

        $EventsA = @(Get-Sm0Events $LogA)
        $EventsB = @(Get-Sm0Events $LogB)
        $EventsC = @(Get-Sm0Events $LogC)
        foreach ($Event in @($EventsA + $EventsB + $EventsC)) {
            if ([int]$Event.writer_count -ne 0) { throw "P7 routing-only process exposed writer_count != 0." }
            if ($Event.PSObject.Properties.Name -contains "command_channel" -and [bool]$Event.command_channel) { throw "P7 router exposed a command channel." }
            if ([string]$Event.event -eq "SM0_P7_ROUTE_REJECTED") { throw "P7 process-isolated route was rejected: $($Event.error_code)" }
        }

        $OriginAC = @($EventsA | Where-Object { $_.event -eq "SM0_P7_ROUTE_ORIGINATED" -and $_.destination_authority_id -eq "authority/sm0/c" }) | Select-Object -First 1
        $DeliverAC = @($EventsC | Where-Object { $_.event -eq "SM0_P7_ROUTE_DELIVERED" -and $_.source_authority_id -eq "authority/sm0/a" }) | Select-Object -First 1
        $OriginCA = @($EventsC | Where-Object { $_.event -eq "SM0_P7_ROUTE_ORIGINATED" -and $_.destination_authority_id -eq "authority/sm0/a" }) | Select-Object -First 1
        $DeliverCA = @($EventsA | Where-Object { $_.event -eq "SM0_P7_ROUTE_DELIVERED" -and $_.source_authority_id -eq "authority/sm0/c" }) | Select-Object -First 1
        if ($null -eq $OriginAC -or $null -eq $DeliverAC -or $null -eq $OriginCA -or $null -eq $DeliverCA) { throw "P7 missing end-to-end A<->C route evidence." }
        if (($OriginAC.route_path -join "|") -ne "authority/sm0/a|authority/sm0/b|authority/sm0/c") { throw "P7 A->C origin did not plan A-B-C." }
        if (($DeliverAC.route_path -join "|") -ne "authority/sm0/a|authority/sm0/b|authority/sm0/c") { throw "P7 A->C delivery did not preserve A-B-C." }
        if (($OriginCA.route_path -join "|") -ne "authority/sm0/c|authority/sm0/b|authority/sm0/a") { throw "P7 C->A origin did not plan C-B-A." }
        if (($DeliverCA.route_path -join "|") -ne "authority/sm0/c|authority/sm0/b|authority/sm0/a") { throw "P7 C->A delivery did not preserve C-B-A." }
        if ([string]$DeliverAC.player_entity_id -ne "player/a" -or [string]$DeliverCA.player_entity_id -ne "player/a") { throw "P7 route changed player/a identity." }

        $ForwardAC = @($EventsB | Where-Object { $_.event -eq "SM0_P7_ROUTE_FORWARDED" -and $_.source_authority_id -eq "authority/sm0/a" -and $_.destination_authority_id -eq "authority/sm0/c" -and $_.next_authority_id -eq "authority/sm0/c" })
        $ForwardCA = @($EventsB | Where-Object { $_.event -eq "SM0_P7_ROUTE_FORWARDED" -and $_.source_authority_id -eq "authority/sm0/c" -and $_.destination_authority_id -eq "authority/sm0/a" -and $_.next_authority_id -eq "authority/sm0/a" })
        if ($ForwardAC.Count -lt 1 -or $ForwardCA.Count -lt 1) { throw "P7 middle authority B did not forward both directions." }

        New-Item -ItemType File -Force -Path $StopFile | Out-Null
        foreach ($Process in $Processes) {
            if (-not $Process.WaitForExit(10000)) { throw "P7 router PID=$($Process.Id) did not stop after stop-file." }
            if ($Process.ExitCode -ne 0) { throw "P7 router PID=$($Process.Id) exited code=$($Process.ExitCode)." }
        }
    }
    finally {
        if (-not (Test-Path -LiteralPath $StopFile -PathType Leaf)) { New-Item -ItemType File -Force -Path $StopFile | Out-Null }
        foreach ($Process in $Processes) {
            try {
                $Process.Refresh()
                if (-not $Process.HasExited) {
                    if (-not $Process.WaitForExit(3000)) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue }
                }
            }
            catch { }
        }
    }

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P7 run." }
    if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
        throw "P7 routing gate changed the source worktree.`nBefore:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")"
    }

    Write-Host ""
    Write-Host "SM0-P7 three-authority routing substrate: PASS"
    Write-Host "  HEAD       : $GitHead"
    Write-Host "  topology   : authority/sm0/a <-> authority/sm0/b <-> authority/sm0/c"
    Write-Host "  A -> C     : routed A -> B -> C"
    Write-Host "  C -> A     : routed C -> B -> A"
    Write-Host "  authority B: transit only / writer_count=0"
    Write-Host "  identity   : player/a preserved"
    Write-Host "  routing    : canonical shortest path / no A<->C direct hop"
    Write-Host "  P4/P5/P6   : unchanged"
    Write-Host "  logs       : $LogRoot"
}
finally {
    if ($null -eq $PreviousBridgeDisabled) {
        Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBridgeDisabled
    }
}
