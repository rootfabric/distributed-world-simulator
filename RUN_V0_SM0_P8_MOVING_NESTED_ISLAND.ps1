[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    [switch]$Visual,
    [int]$VisualHoldSeconds = 15,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) { throw "Godot project.godot missing: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot 4.7.1 double console executable missing: $GodotExe" }
if ($Visual -and -not (Test-Path -LiteralPath $GodotGuiExe -PathType Leaf)) { throw "Godot 4.7.1 double GUI executable missing: $GodotGuiExe" }
if ($VisualHoldSeconds -lt 0) { throw "VisualHoldSeconds must be >= 0." }

$GitHead = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) { throw "Unable to resolve exact git HEAD." }
$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P8 moving nested-island gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")" }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED = "1"

try {
    Write-Host "[SM0-P8] Re-running inherited P7.1 routed canonical handoff gate first..."
    $P71Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P7_1_CANONICAL_HANDOFF.ps1"
    if (-not (Test-Path -LiteralPath $P71Runner -PathType Leaf)) { throw "Inherited P7.1 runner missing: $P71Runner" }
    & $P71Runner -ProjectRoot $ProjectRoot -GodotExe $GodotExe -GodotGuiExe $GodotGuiExe -AllowDirty:$AllowDirty
    if ($LASTEXITCODE -ne 0) { throw "Inherited SM0 P7.1 routed canonical handoff gate failed." }

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

    $Ports = @(26410, 26411, 26412, 26413, 26414, 26420, 26421, 26422, 26423, 26424)
    foreach ($Port in $Ports) {
        if (-not (Test-UdpPortAvailable $Port)) { throw "P8 moving nested-island gate requires free UDP loopback port $Port." }
    }

    $Scripts = @(
        "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_contract.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_node.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_node.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_process.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p8_moving_nested_island.gd"
    )
    foreach ($ScriptPath in $Scripts) {
        Write-Host "[SM0-P8] Compile check: $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "P8 compile check failed: $ScriptPath" }
    }

    Write-Host "[SM0-P8] Running focused moving nested-authority regression..."
    $FocusedOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p8_moving_nested_island.gd 2>&1)
    $FocusedOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "SM0 P8 focused moving nested-authority regression failed." }
    if (-not (($FocusedOutput -join "`n") -match 'SM0 P8 moving nested authority island: PASS \(96 assertions\)')) {
        throw "SM0 P8 focused regression did not emit the exact 96-assertion PASS marker."
    }
    foreach ($Port in $Ports) {
        if (-not (Test-UdpPortAvailable $Port)) { throw "P8 focused regression did not release UDP port $Port." }
    }

    $RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $LogRoot = Join-Path ([IO.Path]::GetTempPath()) "dws-sm0-p8-$RunId"
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
    $StartFile = Join-Path $LogRoot "start.flag"
    $StopFile = Join-Path $LogRoot "stop.flag"
    $LogObserver = Join-Path $LogRoot "observer.log"
    $LogNested = Join-Path $LogRoot "nested-ship-authority.log"
    $LogA = Join-Path $LogRoot "outer-a.log"
    $LogB = Join-Path $LogRoot "transit-b.log"
    $LogC = Join-Path $LogRoot "outer-c.log"
    $Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

    function Quote-Arg([string]$Value) { return '"' + $Value + '"' }

    function Start-P8Process {
        param(
            [string]$Label,
            [string]$LogFile,
            [string]$ScriptPath,
            [string[]]$UserArgs,
            [switch]$UseGui
        )
        $Executable = if ($UseGui) { $GodotGuiExe } else { $GodotExe }
        $Args = @()
        if (-not $UseGui) { $Args += "--headless" }
        $Args += @(
            "--path", (Quote-Arg $ProjectRoot),
            "--log-file", (Quote-Arg $LogFile),
            "--script", $ScriptPath,
            "--"
        )
        $Args += $UserArgs
        $StartParams = @{
            FilePath = $Executable
            ArgumentList = $Args
            WorkingDirectory = $ProjectRoot
            PassThru = $true
        }
        if (-not $UseGui) { $StartParams.WindowStyle = "Hidden" }
        $Process = Start-Process @StartParams
        Write-Host "[SM0-P8] $Label PID=$($Process.Id) log=$LogFile"
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
            try { $Events += ($Line.Substring($Index + $Marker.Length) | ConvertFrom-Json -ErrorAction Stop) } catch { }
        }
        return $Events
    }

    try {
        $Observer = Start-P8Process -Label "observer" -LogFile $LogObserver -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer_process.gd" -UseGui:$Visual -UserArgs @(
            "--listen-port=26424", "--stop-file=$StopFile"
        )
        $Processes.Add($Observer)
        $Nested = Start-P8Process -Label "nested-ship-authority" -LogFile $LogNested -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_process.gd" -UserArgs @(
            "--anchor-port=26423", "--view-port=26424", "--stop-file=$StopFile"
        )
        $Processes.Add($Nested)
        $B = Start-P8Process -Label "transit-b" -LogFile $LogB -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd" -UserArgs @(
            "--authority-id=authority/sm0/b", "--listen-port=26421", "--neighbor-a-port=26420", "--neighbor-c-port=26422", "--stop-file=$StopFile"
        )
        $Processes.Add($B)
        $C = Start-P8Process -Label "outer-c" -LogFile $LogC -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd" -UserArgs @(
            "--authority-id=authority/sm0/c", "--listen-port=26422", "--neighbor-b-port=26421", "--anchor-port=26423",
            "--initial-writer=false", "--auto-return-target=authority/sm0/a", "--stop-file=$StopFile"
        )
        $Processes.Add($C)
        $A = Start-P8Process -Label "outer-a" -LogFile $LogA -ScriptPath "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd" -UserArgs @(
            "--authority-id=authority/sm0/a", "--listen-port=26420", "--neighbor-b-port=26421", "--anchor-port=26423",
            "--initial-writer=true", "--initial-x=-1.0", "--velocity-x=0.8", "--velocity-z=0.1", "--angular-velocity-yaw=0.2",
            "--auto-start-target=authority/sm0/c", "--start-file=$StartFile", "--stop-file=$StopFile"
        )
        $Processes.Add($A)

        Wait-LogMarker $LogObserver '"event":"SM0_P8_VISUAL_READY"' $Observer 15 "observer"
        Wait-LogMarker $LogNested '"event":"SM0_P8_NESTED_READY"' $Nested 15 "nested-ship-authority"
        Wait-LogMarker $LogA '"event":"SM0_P8_OUTER_READY"' $A 15 "outer-a"
        Wait-LogMarker $LogB '"event":"SM0_P8_OUTER_READY"' $B 15 "transit-b"
        Wait-LogMarker $LogC '"event":"SM0_P8_OUTER_READY"' $C 15 "outer-c"
        Wait-LogMarker $LogNested '"event":"SM0_P8_ANCHOR_ACCEPTED"' $Nested 15 "nested-ship-authority"

        New-Item -ItemType File -Force -Path $StartFile | Out-Null
        Wait-LogMarker $LogA '"event":"SM0_P8_SOURCE_RETIRED"' $A 20 "outer-a"
        Wait-LogMarker $LogC '"event":"SM0_P8_TARGET_COMMITTED"' $C 20 "outer-c"
        Wait-LogMarker $LogA '"event":"SM0_P8_TRANSFER_COMPLETED"' $A 20 "outer-a"
        Wait-LogMarker $LogC '"event":"SM0_P8_SOURCE_RETIRED"' $C 20 "outer-c"
        Wait-LogMarker $LogA '"event":"SM0_P8_TARGET_COMMITTED"' $A 20 "outer-a"
        Wait-LogMarker $LogC '"event":"SM0_P8_TRANSFER_COMPLETED"' $C 20 "outer-c"

        $OwnerDeadline = (Get-Date).AddSeconds(10)
        do {
            $NestedEvents = @(Get-Sm0Events $LogNested)
            $ObserverEvents = @(Get-Sm0Events $LogObserver)
            $NestedOwnerChanges = @($NestedEvents | Where-Object { $_.event -eq "SM0_P8_OUTER_OWNER_CHANGED" })
            $ObserverOwnerChanges = @($ObserverEvents | Where-Object { $_.event -eq "SM0_P8_VISUAL_OUTER_OWNER_CHANGED" })
            if ($NestedOwnerChanges.Count -ge 2 -and $ObserverOwnerChanges.Count -ge 2) { break }
            Start-Sleep -Milliseconds 50
        } while ((Get-Date) -lt $OwnerDeadline)
        if ($NestedOwnerChanges.Count -lt 2 -or $ObserverOwnerChanges.Count -lt 2) { throw "P8 nested/visual observers did not see both A->C and C->A outer-owner pivots." }

        $EventsA = @(Get-Sm0Events $LogA)
        $EventsB = @(Get-Sm0Events $LogB)
        $EventsC = @(Get-Sm0Events $LogC)
        $NestedEvents = @(Get-Sm0Events $LogNested)
        $ObserverEvents = @(Get-Sm0Events $LogObserver)

        if (@($EventsB | Where-Object { [int]$_.writer_count -ne 0 }).Count -gt 0) { throw "P8 transit B exposed writer_count != 0." }
        if (@($EventsB | Where-Object { $_.event -eq "SM0_P8_ROUTE_REJECTED" }).Count -gt 0) { throw "P8 transit B rejected a process-isolated route." }
        $BForwards = @($EventsB | Where-Object { $_.event -eq "SM0_P8_ROUTE_FORWARDED" })
        if ($BForwards.Count -lt 8) { throw "P8 transit B forwarded only $($BForwards.Count) phases; expected at least 8." }

        $SourceRetiredA = @($EventsA | Where-Object { $_.event -eq "SM0_P8_SOURCE_RETIRED" }) | Select-Object -First 1
        $SourceRetiredC = @($EventsC | Where-Object { $_.event -eq "SM0_P8_SOURCE_RETIRED" }) | Select-Object -First 1
        if ($null -eq $SourceRetiredA -or $null -eq $SourceRetiredC) { throw "P8 missing source-retirement evidence." }
        if ([int]$SourceRetiredA.commit_tick -le [int]$SourceRetiredA.reservation_tick) { throw "P8 A ship motion did not continue between PREPARE reservation and commit boundary." }
        if ([int]$SourceRetiredC.commit_tick -le [int]$SourceRetiredC.reservation_tick) { throw "P8 C ship motion did not continue between PREPARE reservation and commit boundary." }

        $CommitC = @($EventsC | Where-Object { $_.event -eq "SM0_P8_TARGET_COMMITTED" -and [int]$_.outer_authority_epoch -eq 2 }) | Select-Object -First 1
        $CommitA = @($EventsA | Where-Object { $_.event -eq "SM0_P8_TARGET_COMMITTED" -and [int]$_.outer_authority_epoch -eq 3 }) | Select-Object -First 1
        if ($null -eq $CommitC -or $null -eq $CommitA) { throw "P8 missing A->C->A target commits at epochs 2 and 3." }
        foreach ($Commit in @($CommitC, $CommitA)) {
            if ([string]$Commit.island_id -ne "island/ship/01" -or [string]$Commit.island_entity_id -ne "ship/01") { throw "P8 target commit changed moving-island identity." }
            if ([string]$Commit.inner_authority_unchanged -ne "authority/island/ship/01") { throw "P8 target commit changed nested authority identity." }
            if ([math]::Abs([double]$Commit.linear_velocity.x) -le 0.000001) { throw "P8 target commit lost nonzero linear velocity." }
            if ([math]::Abs([double]$Commit.angular_velocity_yaw) -le 0.000001) { throw "P8 target commit lost nonzero angular velocity." }
        }

        if (@($NestedEvents | Where-Object { $_.event -eq "SM0_P8_ANCHOR_REJECTED" }).Count -gt 0) { throw "P8 nested authority rejected a process-isolated canonical anchor." }
        if (@($NestedEvents | Where-Object { [int]$_.writer_count -ne 1 }).Count -gt 0) { throw "P8 nested authority lost its single player writer." }
        $NestedChanges = @($NestedEvents | Where-Object { $_.event -eq "SM0_P8_OUTER_OWNER_CHANGED" })
        if ($NestedChanges.Count -lt 2) { throw "P8 nested authority did not observe two outer-owner changes." }
        foreach ($Change in $NestedChanges) {
            if ([string]$Change.island_authority_id -ne "authority/island/ship/01" -or [int]$Change.inner_authority_epoch -ne 1 -or [string]$Change.player_entity_id -ne "player/a") {
                throw "P8 outer-owner pivot mutated nested authority/player identity."
            }
        }
        $NestedFrames = @($NestedEvents | Where-Object { $_.event -eq "SM0_P8_NESTED_FRAME" })
        if ($NestedFrames.Count -lt 4) { throw "P8 nested authority produced too few frames." }
        $FirstInput = [int]($NestedFrames | Select-Object -First 1).player_input_sequence
        $LastInput = [int]($NestedFrames | Select-Object -Last 1).player_input_sequence
        if ($LastInput -le $FirstInput) { throw "P8 nested player local input sequence did not continue while outer ownership moved." }

        if (@($ObserverEvents | Where-Object { [int]$_.writer_count -ne 0 }).Count -gt 0) { throw "P8 observer exposed writer_count != 0." }
        if (@($ObserverEvents | Where-Object { $_.PSObject.Properties.Name -contains "command_channel" -and [bool]$_.command_channel }).Count -gt 0) { throw "P8 observer exposed a command channel." }
        if (@($ObserverEvents | Where-Object { $_.event -eq "SM0_P8_VISUAL_REJECTED" }).Count -gt 0) { throw "P8 process-isolated visual stream was rejected." }
        $VisualFrames = @($ObserverEvents | Where-Object { $_.event -eq "SM0_P8_VISUAL_FRAME" })
        if ($VisualFrames.Count -lt 3) { throw "P8 observer produced too few visual frames." }
        $ShipVisualIds = @($VisualFrames | ForEach-Object { [string]$_.ship_visual_instance_id } | Sort-Object -Unique)
        $PlayerVisualIds = @($VisualFrames | ForEach-Object { [string]$_.player_visual_instance_id } | Sort-Object -Unique)
        if ($ShipVisualIds.Count -ne 1 -or $PlayerVisualIds.Count -ne 1) { throw "P8 ship/player visual instance changed during outer ownership pivots." }
        if (@($ObserverEvents | Where-Object { $_.event -eq "SM0_P8_VISUAL_OUTER_OWNER_CHANGED" }).Count -lt 2) { throw "P8 observer did not render both outer-owner pivots." }

        if ($Visual -and $VisualHoldSeconds -gt 0) {
            Write-Host "[SM0-P8] Visual proof holding for $VisualHoldSeconds s. WHITE ship=A owner, GREEN ship=C owner, YELLOW player=nested authority."
            Start-Sleep -Seconds $VisualHoldSeconds
        }

        New-Item -ItemType File -Force -Path $StopFile | Out-Null
        foreach ($Process in $Processes) {
            if (-not $Process.WaitForExit(10000)) { throw "P8 process PID=$($Process.Id) did not stop after stop-file." }
            if ($Process.ExitCode -ne 0) { throw "P8 process PID=$($Process.Id) exited code=$($Process.ExitCode)." }
        }
    }
    finally {
        if (-not (Test-Path -LiteralPath $StopFile -PathType Leaf)) { New-Item -ItemType File -Force -Path $StopFile | Out-Null }
        foreach ($Process in $Processes) {
            try {
                $Process.Refresh()
                if (-not $Process.HasExited) {
                    $null = $Process.WaitForExit(3000)
                    $Process.Refresh()
                    if (-not $Process.HasExited) { $Process.Kill() }
                }
            }
            catch { }
        }
    }

    foreach ($Path in @($LogObserver, $LogNested, $LogA, $LogB, $LogC)) {
        foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "SM0_INVARIANT_VIOLATION")) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "P8 final log scan found '$Fatal' in $Path" }
        }
    }

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P8 gate." }
    if (-not $AllowDirty -and ($StatusAfter -join "`n") -ne ($StatusBefore -join "`n")) { throw "P8 gate modified the source worktree." }

    Write-Host ""
    Write-Host "SM0-P8 moving nested authority island: PASS"
    Write-Host "  HEAD       : $GitHead"
    Write-Host "  outer      : Ship-01 A -> C -> A through transit B / epochs 1 -> 2 -> 3"
    Write-Host "  motion     : source keeps integrating through PREPARE; nonzero linear + angular velocity preserved"
    Write-Host "  nested     : authority/island/ship/01 stays epoch 1 and keeps canonical player/a writer"
    Write-Host "  player     : ship-local movement continues during both outer handoffs"
    Write-Host "  transit B  : routing only / writer_count=0"
    Write-Host "  visual     : persistent ship + persistent nested player / no respawn"
    Write-Host "  P4-P7.1    : unchanged"
    Write-Host "  visual mode: $([bool]$Visual)"
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