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
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P7.1 canonical handoff gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")" }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED = "1"

try {
    Write-Host "[SM0-P7.1] Re-running inherited P7 routing substrate gate first..."
    $P7Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P7_THREE_AUTHORITY_ROUTING.ps1"
    if (-not (Test-Path -LiteralPath $P7Runner -PathType Leaf)) { throw "Inherited P7 runner missing: $P7Runner" }
    & $P7Runner -ProjectRoot $ProjectRoot -GodotExe $GodotExe -GodotGuiExe $GodotGuiExe -AllowDirty:$AllowDirty
    if ($LASTEXITCODE -ne 0) { throw "Inherited SM0 P7 routing substrate gate failed." }

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

    $Ports = @(26310, 26311, 26312, 26320, 26321, 26322)
    foreach ($Port in $Ports) {
        if (-not (Test-UdpPortAvailable $Port)) { throw "P7.1 canonical handoff gate requires free UDP loopback port $Port." }
    }

    $Scripts = @(
        "res://scripts/runtime/seamless/sm0/sm0_p7_1_transfer_contract.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p7_1_canonical_handoff_node.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p7_1_canonical_handoff_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p7_1_canonical_handoff.gd"
    )
    foreach ($ScriptPath in $Scripts) {
        Write-Host "[SM0-P7.1] Compile check: $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "P7.1 compile check failed: $ScriptPath" }
    }

    Write-Host "[SM0-P7.1] Running focused routed canonical handoff regression..."
    $FocusedOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p7_1_canonical_handoff.gd 2>&1)
    $FocusedOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "SM0 P7.1 focused routed canonical handoff regression failed." }
    if (-not (($FocusedOutput -join "`n") -match 'SM0 P7.1 routed canonical handoff: PASS \(53 assertions\)')) {
        throw "SM0 P7.1 focused regression did not emit the exact 53-assertion PASS marker."
    }
    foreach ($Port in $Ports) {
        if (-not (Test-UdpPortAvailable $Port)) { throw "P7.1 focused regression did not release UDP port $Port." }
    }

    $RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $LogRoot = Join-Path ([IO.Path]::GetTempPath()) "dws-sm0-p7-1-$RunId"
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
    $StartFile = Join-Path $LogRoot "start.flag"
    $StopFile = Join-Path $LogRoot "stop.flag"
    $LogA = Join-Path $LogRoot "authority-a.log"
    $LogB = Join-Path $LogRoot "transit-b.log"
    $LogC = Join-Path $LogRoot "authority-c.log"
    $Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

    function Quote-Arg([string]$Value) { return '"' + $Value + '"' }

    function Start-SM0Process {
        param([string]$Label, [string]$LogFile, [string[]]$UserArgs)
        $Args = @(
            "--headless",
            "--path", (Quote-Arg $ProjectRoot),
            "--log-file", (Quote-Arg $LogFile),
            "--script", "res://scripts/runtime/seamless/sm0/sm0_p7_1_canonical_handoff_process.gd",
            "--"
        )
        $Args += $UserArgs
        $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
        Write-Host "[SM0-P7.1] $Label PID=$($Process.Id) log=$LogFile"
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

    try {
        $B = Start-SM0Process -Label "transit-b" -LogFile $LogB -UserArgs @(
            "--authority-id=authority/sm0/b", "--listen-port=26321",
            "--neighbor-a-port=26320", "--neighbor-c-port=26322", "--stop-file=$StopFile"
        )
        $Processes.Add($B)
        $A = Start-SM0Process -Label "authority-a" -LogFile $LogA -UserArgs @(
            "--authority-id=authority/sm0/a", "--listen-port=26320", "--neighbor-b-port=26321",
            "--start-file=$StartFile", "--stop-file=$StopFile", "--auto-start-target=authority/sm0/c"
        )
        $Processes.Add($A)
        $C = Start-SM0Process -Label "authority-c" -LogFile $LogC -UserArgs @(
            "--authority-id=authority/sm0/c", "--listen-port=26322", "--neighbor-b-port=26321",
            "--stop-file=$StopFile", "--auto-return-target=authority/sm0/a"
        )
        $Processes.Add($C)

        Wait-LogMarker $LogA '"event":"SM0_P7_1_READY"' $A 15 "authority-a"
        Wait-LogMarker $LogB '"event":"SM0_P7_1_READY"' $B 15 "transit-b"
        Wait-LogMarker $LogC '"event":"SM0_P7_1_READY"' $C 15 "authority-c"
        New-Item -ItemType File -Force -Path $StartFile | Out-Null

        Wait-LogMarker $LogA '"event":"SM0_P7_1_SOURCE_RETIRED"' $A 20 "authority-a"
        Wait-LogMarker $LogC '"event":"SM0_P7_1_TARGET_COMMITTED"' $C 20 "authority-c"
        Wait-LogMarker $LogA '"event":"SM0_P7_1_TRANSFER_COMPLETED"' $A 20 "authority-a"
        Wait-LogMarker $LogC '"event":"SM0_P7_1_SOURCE_RETIRED"' $C 20 "authority-c"
        Wait-LogMarker $LogA '"event":"SM0_P7_1_TARGET_COMMITTED"' $A 20 "authority-a"
        Wait-LogMarker $LogC '"event":"SM0_P7_1_TRANSFER_COMPLETED"' $C 20 "authority-c"

        $BForwards = @(Select-String -LiteralPath $LogB -SimpleMatch '"event":"SM0_P7_1_ROUTE_FORWARDED"' -ErrorAction Stop).Count
        if ($BForwards -lt 8) { throw "Transit B forwarded only $BForwards phases; expected at least 8 for A->C->A." }
        if (Select-String -LiteralPath $LogB -Pattern '"writer_count":[1-9]' -Quiet -ErrorAction Stop) { throw "Transit B became a gameplay writer. See $LogB" }
        if (Select-String -LiteralPath $LogB -SimpleMatch '"authority_present":true' -Quiet -ErrorAction Stop) { throw "Transit B instantiated gameplay authority. See $LogB" }
        if (-not (Select-String -LiteralPath $LogC -SimpleMatch '"player_entity_id":"player/a"' -Quiet -ErrorAction Stop)) { throw "C target commit did not preserve player/a identity." }
        if (-not (Select-String -LiteralPath $LogA -SimpleMatch '"authority_epoch":3' -Quiet -ErrorAction Stop)) { throw "A did not finish round trip at authority epoch 3." }
        if (-not (Select-String -LiteralPath $LogA -Pattern '"event":"SM0_P7_1_TARGET_COMMITTED".*"writer_count":1' -Quiet -ErrorAction Stop)) { throw "A did not finish as canonical writer." }
        if (-not (Select-String -LiteralPath $LogC -Pattern '"event":"SM0_P7_1_SOURCE_RETIRED".*"writer_count":0' -Quiet -ErrorAction Stop)) { throw "C source was not retired before return commit." }
    }
    finally {
        New-Item -ItemType File -Force -Path $StopFile | Out-Null
        foreach ($Process in $Processes) {
            try {
                if (-not $Process.HasExited) { $null = $Process.WaitForExit(10000) }
                if (-not $Process.HasExited) { $Process.Kill() }
            }
            catch { }
        }
    }

    foreach ($Pair in @(@("authority-a", $A, $LogA), @("transit-b", $B, $LogB), @("authority-c", $C, $LogC))) {
        $Label = [string]$Pair[0]
        $Process = [System.Diagnostics.Process]$Pair[1]
        $Path = [string]$Pair[2]
        $Process.Refresh()
        if (-not $Process.HasExited) { throw "$Label did not stop after stop-file. See $Path" }
        if ($Process.ExitCode -ne 0) { throw "$Label exited code=$($Process.ExitCode). See $Path" }
        foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "ERROR:", "SM0_INVARIANT_VIOLATION")) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "P7.1 final log scan found '$Fatal' in $Path" }
        }
    }

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P7.1 gate." }
    if (-not $AllowDirty -and ($StatusAfter -join "`n") -ne ($StatusBefore -join "`n")) { throw "P7.1 gate modified the source worktree." }

    Write-Host ""
    Write-Host "SM0-P7.1 routed canonical handoff: PASS"
    Write-Host "  HEAD       : $GitHead"
    Write-Host "  topology   : authority/sm0/a <-> transit authority/sm0/b <-> authority/sm0/c"
    Write-Host "  ownership  : A -> C -> A / epochs 1 -> 2 -> 3"
    Write-Host "  transit B  : routing only / no MultiplayerGameplayAuthority / writer_count=0"
    Write-Host "  identity   : player/a preserved through both canonical imports"
    Write-Host "  protocol   : PREPARE -> PREPARED -> source leave -> COMMIT(retire proof) -> COMMITTED"
    Write-Host "  P4/P5/P6/P7: unchanged"
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