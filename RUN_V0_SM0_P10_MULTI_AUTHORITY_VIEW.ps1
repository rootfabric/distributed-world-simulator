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
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ActualGodot = ((& $GodotExe --version) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualGodot -ne $ExpectedGodot) { throw "Unexpected Godot '$ActualGodot'; expected '$ExpectedGodot'." }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P10 gate requires a clean worktree:`n$($StatusBefore -join "`n")" }
$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ':(glob)**/*.uid')
$UidBeforeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($Uid in $UidBefore) { [void]$UidBeforeSet.Add([string]$Uid) }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
$Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0,8))
$LogRoot = Join-Path $ProjectRoot "artifacts\runtime\sm0-p10-$RunId"
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

function Start-P10Source {
    param(
        [string]$AuthorityId,
        [string]$SourceRole,
        [int]$Port,
        [string]$LogFile,
        [string]$StdoutFile
    )
    $Args = @(
        "--headless",
        "--path", (Quote-Arg $ProjectRoot),
        "--log-file", (Quote-Arg $LogFile),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_p10_projection_source_process.gd",
        "--",
        "--authority-id=$AuthorityId",
        "--source-role=$SourceRole",
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
        if ($Process.HasExited) { throw "$($Label) exited before '$Marker'. See $Path" }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for '$Marker' from $($Label). See $Path"
}

function Assert-P10SourceExitedCleanly {
    param([System.Diagnostics.Process]$Process, [string]$LogFile, [string]$Label)
    if (-not $Process.WaitForExit(5000)) { throw "P10 source $($Label) PID=$($Process.Id) did not shut down." }
    try { $Process.Refresh() } catch {}
    $ExitCode = $null
    try {
        $ExitCodeProperty = $Process.PSObject.Properties["ExitCode"]
        if ($null -ne $ExitCodeProperty) { $ExitCode = $ExitCodeProperty.Value }
    }
    catch { $ExitCode = $null }
    if ($null -ne $ExitCode) {
        if ([int]$ExitCode -ne 0) { throw "P10 source $($Label) PID=$($Process.Id) exited code=$ExitCode." }
        return
    }
    $ExitLines = @()
    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        $ExitLines = @(Select-String -LiteralPath $LogFile -SimpleMatch '"event":"SM0_P10_SOURCE_EXIT"' -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
    }
    if ($ExitLines.Count -lt 1) { throw "P10 source $($Label) PID=$($Process.Id) terminated, but PowerShell exposed no ExitCode and SM0_P10_SOURCE_EXIT is missing. See $LogFile" }
    $CleanStructuredExit = $false
    foreach ($Line in $ExitLines) {
        if ($Line -match '"exit_code"\s*:\s*0(?:\s*[,}])') { $CleanStructuredExit = $true; break }
    }
    if (-not $CleanStructuredExit) { throw "P10 source $($Label) PID=$($Process.Id) terminated without structured exit_code=0. See $LogFile" }
    Write-Host "[SM0-P10] $($Label) PID=$($Process.Id): PowerShell ExitCode unavailable; verified SM0_P10_SOURCE_EXIT exit_code=0."
}

try {
    $Head = ((& git -C $ProjectRoot rev-parse HEAD) | Select-Object -First 1).Trim()
    Write-Host "[SM0-P10] Godot: $ActualGodot"
    Write-Host "[SM0-P10] HEAD : $Head"
    Write-Host "[SM0-P10] Logs : $LogRoot"

    Write-Host "[SM0-P10] Running inherited P9 full boundary gate..."
    $P9Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P9_FOREIGN_ITEM_BOUNDARY.ps1"
    if (-not (Test-Path -LiteralPath $P9Runner -PathType Leaf)) { throw "Inherited P9 runner missing: $P9Runner" }
    $P9Output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $P9Runner -ProjectRoot $ProjectRoot -GodotExe $GodotExe 2>&1)
    $P9ExitCode = $LASTEXITCODE
    $P9Output | Tee-Object -FilePath (Join-Path $LogRoot "inherited-p9.log") | ForEach-Object { Write-Host $_ }
    if ($P9ExitCode -ne 0 -or -not (($P9Output -join "`n") -match 'SM0-P9 foreign item/interactions boundary: PASS')) { throw "Inherited P9 full gate failed." }

    $Scripts = @(
        "res://scripts/runtime/seamless/sm0/sm0_p10_view_contract.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p10_multi_authority_view_composer.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p10_projection_source_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p10_multi_authority_view.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p10_process_composition.gd"
    )
    foreach ($ScriptPath in $Scripts) {
        Write-Host "[SM0-P10] Compile check: $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "P10 compile check failed: $ScriptPath" }
    }

    Write-Host "[SM0-P10] Running focused multi-authority composition regression..."
    $FocusedOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p10_multi_authority_view.gd 2>&1)
    $FocusedOutput | Tee-Object -FilePath (Join-Path $LogRoot "focused.log") | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or -not (($FocusedOutput -join "`n") -match 'SM0 P10 multi-authority view \+ LOD: PASS \(91 assertions\)')) { throw "P10 focused regression failed." }

    $LogA = Join-Path $LogRoot "source-a.log"
    $LogB = Join-Path $LogRoot "source-b.log"
    $LogC = Join-Path $LogRoot "source-c.log"
    $A = Start-P10Source "authority/sm0/a" "FOREIGN" 26920 $LogA (Join-Path $LogRoot "source-a.stdout.log")
    $B = Start-P10Source "authority/sm0/b" "LOCAL" 26921 $LogB (Join-Path $LogRoot "source-b.stdout.log")
    $C = Start-P10Source "authority/sm0/c" "FOREIGN" 26922 $LogC (Join-Path $LogRoot "source-c.stdout.log")
    Wait-LogMarker $LogA '"event":"SM0_P10_SOURCE_READY"' $A "source A"
    Wait-LogMarker $LogB '"event":"SM0_P10_SOURCE_READY"' $B "source B"
    Wait-LogMarker $LogC '"event":"SM0_P10_SOURCE_READY"' $C "source C"
    Write-Host "[SM0-P10] Source PIDs A=$($A.Id) B=$($B.Id) C=$($C.Id)"
    if ($A.Id -eq $B.Id -or $A.Id -eq $C.Id -or $B.Id -eq $C.Id) { throw "P10 projection source processes are not distinct." }

    $ScenarioLog = Join-Path $LogRoot "scenario.log"
    $ScenarioOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p10_process_composition.gd 2>&1)
    $ScenarioOutput | Tee-Object -FilePath $ScenarioLog | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or -not (($ScenarioOutput -join "`n") -match 'SM0 P10 process-isolated composition: PASS \(52 assertions\)')) { throw "P10 process-isolated composition failed." }

    Assert-P10SourceExitedCleanly $A $LogA "source A"
    Assert-P10SourceExitedCleanly $B $LogB "source B"
    Assert-P10SourceExitedCleanly $C $LogC "source C"
    $Processes.Clear()

    foreach ($Path in @($LogA,$LogB,$LogC,$ScenarioLog)) {
        foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "SM0_INVARIANT_VIOLATION")) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "Fatal marker '$Fatal' in $Path" }
        }
    }
    foreach ($Path in @($LogA,$LogB,$LogC)) {
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_P10_SOURCE_READY"' -Quiet)) { throw "P10 source ready evidence missing: $Path" }
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_P10_SOURCE_SNAPSHOT_SENT"' -Quiet)) { throw "P10 source snapshot evidence missing: $Path" }
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_P10_SOURCE_EXIT"' -Quiet)) { throw "P10 source exit evidence missing: $Path" }
    }

    Remove-NewUidFiles
    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P10 gate" }
    if (-not $AllowDirty -and ($StatusAfter -join "`n") -ne ($StatusBefore -join "`n")) { throw "P10 gate modified the source worktree:`n$($StatusAfter -join "`n")" }

    Write-Host ""
    Write-Host "SM0-P10 multi-authority view + representation LOD: PASS"
    Write-Host "  focused    : P10 91 assertions"
    Write-Host "  process    : P10 52 assertions / 3 distinct projection-source processes"
    Write-Host "  inherited  : full P9 gate PASS (including P8 96 / P9 103 / P9 process 55)"
    Write-Host "  composition: LOCAL B + FOREIGN A/C -> one presentation view"
    Write-Host "  fencing    : per-source epoch / sequence / checksum fail-closed"
    Write-Host "  LOD        : distance + priority + bandwidth coarse/fine selection"
    Write-Host "  progressive: fine representation upgrade + content cache reuse"
    Write-Host "  dropout    : source A loss removes A dynamic state only; cached coarse A degrades read-only"
    Write-Host "  safety     : presentation artifacts cannot become canonical state"
    Write-Host "  logs       : $LogRoot"
}
finally {
    foreach ($Process in @($Processes)) {
        try { if (-not $Process.HasExited) { $Process.Kill() } } catch {}
    }
    Remove-NewUidFiles
    if ($null -eq $PreviousBridgeDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBridgeDisabled }
}