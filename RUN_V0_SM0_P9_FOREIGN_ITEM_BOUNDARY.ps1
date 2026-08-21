[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) { throw "project.godot missing: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot 4.7.1 double console executable missing: $GodotExe" }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P9 gate requires a clean worktree:`n$($StatusBefore -join "`n")" }
$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ':(glob)**/*.uid')
$UidBeforeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($Uid in $UidBefore) { [void]$UidBeforeSet.Add([string]$Uid) }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
$Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0,8))
$LogRoot = Join-Path $ProjectRoot "artifacts\runtime\sm0-p9-$RunId"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Remove-NewUidFiles {
    $After = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ':(glob)**/*.uid')
    foreach ($Uid in $After) {
        if (-not $UidBeforeSet.Contains([string]$Uid)) {
            Remove-Item -LiteralPath (Join-Path $ProjectRoot $Uid) -Force -ErrorAction SilentlyContinue
        }
    }
}

function Quote-Arg([string]$Value) { return '"' + $Value + '"' }

function Start-P9Authority {
    param([string]$AuthorityId, [int]$Port, [string]$LogFile, [string]$StdoutFile)
    $Args = @(
        "--headless",
        "--path", (Quote-Arg $ProjectRoot),
        "--log-file", (Quote-Arg $LogFile),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_process.gd",
        "--",
        "--authority-id=$AuthorityId",
        "--listen-port=$Port"
    )
    $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -RedirectStandardOutput $StdoutFile -RedirectStandardError ($StdoutFile + ".err") -PassThru
    $Processes.Add($Process)
    return $Process
}

function Wait-LogMarker {
    param([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [string]$Label, [int]$Seconds = 15)
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue) { return }
            foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "SM0_INVARIANT_VIOLATION")) {
                if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "$($Label) contains fatal marker '$Fatal'. See $Path" }
            }
        }
        $Process.Refresh()
        if ($Process.HasExited) { throw "$($Label) exited code=$($Process.ExitCode) before '$Marker'. See $Path" }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for '$Marker' from $Label. See $Path"
}

function Assert-P9AuthorityExitedCleanly {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$LogFile,
        [string]$Label
    )

    if (-not $Process.WaitForExit(5000)) {
        throw "P9 authority process $($Label) PID=$($Process.Id) did not shut down."
    }

    try { $Process.Refresh() } catch {}

    # Windows PowerShell 5.1 can occasionally leave ExitCode unavailable on a
    # Start-Process -PassThru object after redirected child shutdown. Prefer the
    # OS exit code when it is exposed, but do not turn a successful Godot exit
    # into a false RED solely because PowerShell returned $null.
    $ExitCode = $null
    try {
        $ExitCodeProperty = $Process.PSObject.Properties["ExitCode"]
        if ($null -ne $ExitCodeProperty) {
            $ExitCode = $ExitCodeProperty.Value
        }
    }
    catch {
        $ExitCode = $null
    }

    if ($null -ne $ExitCode) {
        if ([int]$ExitCode -ne 0) {
            throw "P9 authority process $($Label) PID=$($Process.Id) exited code=$ExitCode."
        }
        return
    }

    # The authority process emits this structured event immediately before
    # quit(_exit_code). Requiring both process termination above and an explicit
    # exit_code=0 marker keeps the fallback fail-closed.
    $ExitLines = @()
    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        $ExitLines = @(
            Select-String -LiteralPath $LogFile -SimpleMatch '"event":"SM0_P9_PROCESS_EXIT"' -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Line }
        )
    }
    if ($ExitLines.Count -lt 1) {
        throw "P9 authority process $($Label) PID=$($Process.Id) terminated, but PowerShell exposed no ExitCode and SM0_P9_PROCESS_EXIT is missing. See $LogFile"
    }

    $CleanStructuredExit = $false
    foreach ($Line in $ExitLines) {
        if ($Line -match '"exit_code"\s*:\s*0(?:\s*[,}])') {
            $CleanStructuredExit = $true
            break
        }
    }
    if (-not $CleanStructuredExit) {
        throw "P9 authority process $($Label) PID=$($Process.Id) terminated without a structured exit_code=0. See $LogFile"
    }

    Write-Host "[SM0-P9] $($Label) PID=$($Process.Id): PowerShell ExitCode unavailable; verified SM0_P9_PROCESS_EXIT exit_code=0."
}

try {
    Write-Host "[SM0-P9] HEAD : $((& git -C $ProjectRoot rev-parse HEAD).Trim())"
    Write-Host "[SM0-P9] Logs : $LogRoot"
    $Scripts = @(
        "res://scripts/runtime/seamless/sm0/sm0_p9_foreign_item_boundary_contract.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_node.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p9_boundary_coordinator.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p9_foreign_item_boundary.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p9_process_boundary.gd"
    )
    foreach ($ScriptPath in $Scripts) {
        Write-Host "[SM0-P9] Compile check: $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "P9 compile check failed: $ScriptPath" }
    }

    Write-Host "[SM0-P9] Running inherited P8 regression..."
    $P8Output = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p8_moving_nested_island.gd 2>&1)
    $P8Output | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or -not (($P8Output -join "`n") -match 'SM0 P8 moving nested authority island: PASS \(96 assertions\)')) { throw "Inherited P8 regression failed." }

    Write-Host "[SM0-P9] Running focused boundary regression..."
    $P9Output = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p9_foreign_item_boundary.gd 2>&1)
    $P9Output | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or -not (($P9Output -join "`n") -match 'SM0 P9 foreign item boundary: PASS \(103 assertions\)')) { throw "P9 focused regression failed." }

    $LogA = Join-Path $LogRoot "world-a.log"
    $LogC = Join-Path $LogRoot "world-c.log"
    $LogShip = Join-Path $LogRoot "ship.log"
    $StdA = Join-Path $LogRoot "world-a.stdout.log"
    $StdC = Join-Path $LogRoot "world-c.stdout.log"
    $StdShip = Join-Path $LogRoot "ship.stdout.log"

    $A = Start-P9Authority "authority/sm0/a" 26820 $LogA $StdA
    $C = Start-P9Authority "authority/sm0/c" 26822 $LogC $StdC
    $Ship = Start-P9Authority "authority/island/ship/01" 26823 $LogShip $StdShip

    Wait-LogMarker $LogA '"event":"SM0_P9_PROCESS_READY"' $A "world A"
    Wait-LogMarker $LogC '"event":"SM0_P9_PROCESS_READY"' $C "world C"
    Wait-LogMarker $LogShip '"event":"SM0_P9_PROCESS_READY"' $Ship "ship"
    Write-Host "[SM0-P9] Process PIDs A=$($A.Id) C=$($C.Id) ship=$($Ship.Id)"
    if ($A.Id -eq $C.Id -or $A.Id -eq $Ship.Id -or $C.Id -eq $Ship.Id) { throw "P9 authority processes are not distinct." }

    $ScenarioLog = Join-Path $LogRoot "scenario.log"
    $ScenarioOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p9_process_boundary.gd 2>&1)
    $ScenarioOutput | Tee-Object -FilePath $ScenarioLog | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or -not (($ScenarioOutput -join "`n") -match 'SM0 P9 process-isolated boundary: PASS \(55 assertions\)')) { throw "P9 process-isolated boundary scenario failed." }

    Assert-P9AuthorityExitedCleanly $A $LogA "world A"
    Assert-P9AuthorityExitedCleanly $C $LogC "world C"
    Assert-P9AuthorityExitedCleanly $Ship $LogShip "ship"
    $Processes.Clear()

    foreach ($Path in @($LogA,$LogC,$LogShip,$ScenarioLog)) {
        foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "SM0_INVARIANT_VIOLATION")) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "Fatal marker '$Fatal' in $Path" }
        }
    }
    if (-not (Select-String -LiteralPath $LogA -SimpleMatch '"event":"SM0_P9_TRANSFER_SOURCE_RETIRED"' -Quiet)) { throw "A did not retire imported item." }
    if (-not (Select-String -LiteralPath $LogShip -SimpleMatch '"event":"SM0_P9_TRANSFER_TARGET_COMMITTED"' -Quiet)) { throw "Ship did not activate imported item." }
    if (-not (Select-String -LiteralPath $LogShip -SimpleMatch '"event":"SM0_P9_TRANSFER_SOURCE_RETIRED"' -Quiet)) { throw "Ship did not retire exported item." }
    if (-not (Select-String -LiteralPath $LogC -SimpleMatch '"event":"SM0_P9_TRANSFER_TARGET_COMMITTED"' -Quiet)) { throw "C did not activate exported item." }
    if (-not (Select-String -LiteralPath $LogC -SimpleMatch '"event":"SM0_P9_TRANSFER_SOURCE_ROLLED_BACK"' -Quiet)) { throw "C rollback evidence missing." }
    if (-not (Select-String -LiteralPath $LogShip -SimpleMatch '"event":"SM0_P9_TRANSFER_TARGET_ABORTED"' -Quiet)) { throw "Ship target-abort evidence missing." }

    Remove-NewUidFiles
    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P9 gate" }
    if (-not $AllowDirty -and ($StatusAfter -join "`n") -ne ($StatusBefore -join "`n")) { throw "P9 gate modified the source worktree:`n$($StatusAfter -join "`n")" }

    Write-Host ""
    Write-Host "SM0-P9 foreign item/interactions boundary: PASS"
    Write-Host "  focused   : P9 103 assertions"
    Write-Host "  process   : P9 55 assertions / 3 distinct Godot authority processes"
    Write-Host "  inherited : P8 96 assertions"
    Write-Host "  authority : direct foreign mutation forbidden; interaction routed to current owner"
    Write-Host "  transfer  : WORLD -> SHIP -> current WORLD owner, stable item id"
    Write-Host "  safety    : source frozen during PREPARE; exact replay idempotent; failure replay deterministic"
    Write-Host "  rollback  : target commit failure restores source and aborts target shadow"
    Write-Host "  logs      : $LogRoot"
}
finally {
    foreach ($Process in @($Processes)) {
        try { if (-not $Process.HasExited) { $Process.Kill() } } catch {}
    }
    Remove-NewUidFiles
    if ($null -eq $PreviousBridgeDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBridgeDisabled }
}
