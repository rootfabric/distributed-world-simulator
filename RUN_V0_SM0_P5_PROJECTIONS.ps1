[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

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
    throw "P5 projection gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")"
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

foreach ($Port in @(25880, 25881)) {
    if (-not (Test-UdpPortAvailable $Port)) {
        throw "P5 projection gate requires free UDP loopback port $Port."
    }
}

$Scripts = @(
    "res://scripts/runtime/seamless/sm0/sm0_p5_projection_contract.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_projection_store.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_projection_server_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_projection_server_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_p5_two_authority_projections.gd"
)

foreach ($ScriptPath in $Scripts) {
    Write-Host "[SM0-P5] Compile check: $ScriptPath"
    & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
    if ($LASTEXITCODE -ne 0) { throw "P5 compile check failed: $ScriptPath" }
}

Write-Host "[SM0-P5] Running focused two-authority read-only projection regression..."
& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p5_two_authority_projections.gd
if ($LASTEXITCODE -ne 0) { throw "SM0 P5 focused projection regression failed." }

foreach ($Port in @(25880, 25881)) {
    if (-not (Test-UdpPortAvailable $Port)) {
        throw "P5 focused regression did not release UDP port $Port."
    }
}

$RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$LogRoot = Join-Path ([IO.Path]::GetTempPath()) "dws-sm0-p5-$RunId"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$StopFile = Join-Path $LogRoot "stop.flag"
$LogA = Join-Path $LogRoot "server-a.log"
$LogB = Join-Path $LogRoot "server-b.log"
$Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

function Quote-Arg([string]$Value) { return '"' + $Value + '"' }

function Start-P5Server {
    param(
        [string]$Label,
        [string]$LogFile,
        [string[]]$UserArgs
    )
    $Args = @(
        "--headless",
        "--path", (Quote-Arg $ProjectRoot),
        "--log-file", (Quote-Arg $LogFile),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_p5_projection_server_process.gd",
        "--"
    ) + $UserArgs
    $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    Write-Host "[SM0-P5] $Label PID=$($Process.Id) log=$LogFile"
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
            foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "setup_failed")) {
                if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) {
                    throw "$Label contains fatal marker '$Fatal'. See $Path"
                }
            }
        }
        $Process.Refresh()
        if ($Process.HasExited) { throw "$Label exited code=$($Process.ExitCode) before '$Marker'. See $Path" }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for '$Marker' from $Label. See $Path"
}

try {
    $ServerA = Start-P5Server -Label "server-a" -LogFile $LogA -UserArgs @(
        "--authority-id=authority/sm0/a",
        "--zone-id=zone/earth/sm0/west",
        "--local-player-id=a",
        "--control-port=25880",
        "--peer-control-port=25881",
        "--stop-file=$StopFile"
    )
    $Processes.Add($ServerA)
    $ServerB = Start-P5Server -Label "server-b" -LogFile $LogB -UserArgs @(
        "--authority-id=authority/sm0/b",
        "--zone-id=zone/earth/sm0/east",
        "--local-player-id=b",
        "--control-port=25881",
        "--peer-control-port=25880",
        "--stop-file=$StopFile"
    )
    $Processes.Add($ServerB)

    Wait-LogMarker $LogA '"event":"SM0_P5_READY"' $ServerA 15 "server-a"
    Wait-LogMarker $LogB '"event":"SM0_P5_READY"' $ServerB 15 "server-b"
    Wait-LogMarker $LogA '"event":"SM0_P5_PROJECTION_ACCEPTED"' $ServerA 15 "server-a"
    Wait-LogMarker $LogB '"event":"SM0_P5_PROJECTION_ACCEPTED"' $ServerB 15 "server-b"

    foreach ($Path in @($LogA, $LogB)) {
        if (Select-String -LiteralPath $Path -SimpleMatch '"writer_count":2' -Quiet -ErrorAction SilentlyContinue) {
            throw "P5 multi-process evidence observed duplicate canonical writer count in $Path"
        }
    }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Process in $Processes) {
        if (-not $Process.WaitForExit(10000)) { throw "P5 server PID=$($Process.Id) did not stop cleanly." }
        if ($Process.ExitCode -ne 0) { throw "P5 server PID=$($Process.Id) exited code=$($Process.ExitCode)." }
    }
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
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed after P5 gate" }
if (-not $AllowDirty -and (($StatusAfter -join "`n") -ne ($StatusBefore -join "`n"))) {
    throw "P5 gate mutated the source worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")"
}

Write-Host ""
Write-Host "SM0-P5 two-authority read-only projections: PASS" -ForegroundColor Green
Write-Host "  HEAD       : $GitHead"
Write-Host "  canonical A: player/a on authority/sm0/a"
Write-Host "  canonical B: player/b on authority/sm0/b"
Write-Host "  projection : foreign player state only / read-only"
Write-Host "  mutation   : projection writes fail with SM0_P5_PROJECTION_READ_ONLY"
Write-Host "  processes  : A/B projection exchange verified across separate Godot processes"
Write-Host "  P4 protocol: unchanged"
Write-Host "  logs       : $LogRoot"