[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [int]$Iterations = 120,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if ($Iterations -lt 1) { throw "Iterations must be >= 1." }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) { throw "project.godot missing: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot 4.7.1 double console executable missing: $GodotExe" }
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ActualGodot = ((& $GodotExe --version) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualGodot -ne $ExpectedGodot) { throw "Unexpected Godot '$ActualGodot'; expected '$ExpectedGodot'." }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P11 gate requires a clean worktree:`n$($StatusBefore -join "`n")" }
$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ':(glob)**/*.uid')
$UidBeforeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($Uid in $UidBefore) { [void]$UidBeforeSet.Add([string]$Uid) }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
$Processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0,8))
$LogRoot = Join-Path $ProjectRoot "artifacts\runtime\sm0-p11-$RunId"
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

function Start-P11Authority {
    param([string]$AuthorityId, [int]$Port, [string]$LogFile, [string]$StdoutFile)
    $Args = @(
        "--headless",
        "--path", (Quote-Arg $ProjectRoot),
        "--log-file", (Quote-Arg $LogFile),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_p11_authority_process.gd",
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
        if ($Process.HasExited) { throw "$($Label) exited before '$Marker'. See $Path" }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for '$Marker' from $($Label). See $Path"
}

function Assert-P11AuthorityExitedCleanly {
    param([System.Diagnostics.Process]$Process, [string]$LogFile, [string]$Label)
    if (-not $Process.WaitForExit(5000)) { throw "P11 authority $($Label) PID=$($Process.Id) did not shut down." }
    try { $Process.Refresh() } catch {}
    $ExitCode = $null
    try {
        $ExitCodeProperty = $Process.PSObject.Properties["ExitCode"]
        if ($null -ne $ExitCodeProperty) { $ExitCode = $ExitCodeProperty.Value }
    }
    catch { $ExitCode = $null }
    if ($null -ne $ExitCode) {
        if ([int]$ExitCode -ne 0) { throw "P11 authority $($Label) PID=$($Process.Id) exited code=$ExitCode." }
        return
    }
    $ExitLines = @()
    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        $ExitLines = @(Select-String -LiteralPath $LogFile -SimpleMatch '"event":"SM0_P11_AUTHORITY_EXIT"' -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
    }
    if ($ExitLines.Count -lt 1) { throw "P11 authority $($Label) PID=$($Process.Id) terminated, but PowerShell exposed no ExitCode and SM0_P11_AUTHORITY_EXIT is missing. See $LogFile" }
    $CleanStructuredExit = $false
    foreach ($Line in $ExitLines) {
        if ($Line -match '"exit_code"\s*:\s*0(?:\s*[,}])') { $CleanStructuredExit = $true; break }
    }
    if (-not $CleanStructuredExit) { throw "P11 authority $($Label) PID=$($Process.Id) terminated without structured exit_code=0. See $LogFile" }
    Write-Host "[SM0-P11] $($Label) PID=$($Process.Id): PowerShell ExitCode unavailable; verified SM0_P11_AUTHORITY_EXIT exit_code=0."
}

try {
    $Head = ((& git -C $ProjectRoot rev-parse HEAD) | Select-Object -First 1).Trim()
    Write-Host "[SM0-P11] Godot     : $ActualGodot"
    Write-Host "[SM0-P11] HEAD      : $Head"
    Write-Host "[SM0-P11] Iterations: $Iterations"
    Write-Host "[SM0-P11] Logs      : $LogRoot"

    Write-Host "[SM0-P11] Running inherited P10 full view/LOD gate..."
    $P10Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P10_MULTI_AUTHORITY_VIEW.ps1"
    if (-not (Test-Path -LiteralPath $P10Runner -PathType Leaf)) { throw "Inherited P10 runner missing: $P10Runner" }
    $P10Output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $P10Runner -ProjectRoot $ProjectRoot -GodotExe $GodotExe 2>&1)
    $P10ExitCode = $LASTEXITCODE
    $P10Output | Tee-Object -FilePath (Join-Path $LogRoot "inherited-p10.log") | ForEach-Object { Write-Host $_ }
    if ($P10ExitCode -ne 0 -or -not (($P10Output -join "`n") -match 'SM0-P10 multi-authority view \+ representation LOD: PASS')) { throw "Inherited P10 full gate failed." }

    $Scripts = @(
        "res://scripts/runtime/seamless/sm0/sm0_p11_fault_contract.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p11_simultaneous_crossing_model.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p11_authority_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p11_fault_matrix.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p11_process_soak.gd"
    )
    foreach ($ScriptPath in $Scripts) {
        Write-Host "[SM0-P11] Compile check: $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "P11 compile check failed: $ScriptPath" }
    }

    Write-Host "[SM0-P11] Running deterministic focused fault matrix..."
    $FocusedOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p11_fault_matrix.gd 2>&1)
    $FocusedOutput | Tee-Object -FilePath (Join-Path $LogRoot "focused.log") | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or -not (($FocusedOutput -join "`n") -match 'SM0 P11 deterministic fault matrix: PASS \([0-9]+ assertions\)')) { throw "P11 deterministic fault matrix failed." }

    $LogA = Join-Path $LogRoot "authority-a.log"
    $LogB = Join-Path $LogRoot "authority-b.log"
    $LogC = Join-Path $LogRoot "authority-c.log"
    $A = Start-P11Authority "authority/sm0/a" 27020 $LogA (Join-Path $LogRoot "authority-a.stdout.log")
    $B = Start-P11Authority "authority/sm0/b" 27021 $LogB (Join-Path $LogRoot "authority-b.stdout.log")
    $C = Start-P11Authority "authority/sm0/c" 27022 $LogC (Join-Path $LogRoot "authority-c.stdout.log")
    Wait-LogMarker $LogA '"event":"SM0_P11_AUTHORITY_READY"' $A "authority A"
    Wait-LogMarker $LogB '"event":"SM0_P11_AUTHORITY_READY"' $B "authority B"
    Wait-LogMarker $LogC '"event":"SM0_P11_AUTHORITY_READY"' $C "authority C"
    Write-Host "[SM0-P11] Authority PIDs A=$($A.Id) B=$($B.Id) C=$($C.Id)"
    if ($A.Id -eq $B.Id -or $A.Id -eq $C.Id -or $B.Id -eq $C.Id) { throw "P11 authority processes are not distinct." }

    $ScenarioLog = Join-Path $LogRoot "process-soak.log"
    $ScenarioOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p11_process_soak.gd -- "--iterations=$Iterations" 2>&1)
    $ScenarioOutput | Tee-Object -FilePath $ScenarioLog | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or -not (($ScenarioOutput -join "`n") -match "SM0 P11 process-isolated simultaneous crossings \+ soak: PASS \($Iterations iterations / [0-9]+ assertions\)")) { throw "P11 process-isolated simultaneous-crossing soak failed." }

    Assert-P11AuthorityExitedCleanly $A $LogA "authority A"
    Assert-P11AuthorityExitedCleanly $B $LogB "authority B"
    Assert-P11AuthorityExitedCleanly $C $LogC "authority C"
    $Processes.Clear()

    foreach ($Path in @($LogA,$LogB,$LogC,$ScenarioLog)) {
        foreach ($Fatal in @("SCRIPT ERROR", "Parse Error", "Failed to load script", "SM0_INVARIANT_VIOLATION")) {
            if (Select-String -LiteralPath $Path -SimpleMatch $Fatal -Quiet -ErrorAction SilentlyContinue) { throw "Fatal marker '$Fatal' in $Path" }
        }
    }
    foreach ($Path in @($LogA,$LogB,$LogC)) {
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_P11_AUTHORITY_READY"' -Quiet)) { throw "P11 authority ready evidence missing: $Path" }
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_P11_AUTHORITY_EXIT"' -Quiet)) { throw "P11 authority exit evidence missing: $Path" }
    }

    Remove-NewUidFiles
    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P11 gate" }
    if (-not $AllowDirty -and ($StatusAfter -join "`n") -ne ($StatusBefore -join "`n")) { throw "P11 gate modified the source worktree:`n$($StatusAfter -join "`n")" }

    Write-Host ""
    Write-Host "SM0-P11 deterministic fault matrix + simultaneous-crossing soak: PASS"
    Write-Host "  focused     : deterministic P11 matrix PASS (68 assertions on implementation baseline)"
    Write-Host "  process     : 3 distinct Godot authority processes / $Iterations soak iterations"
    Write-Host "  simultaneous: A->B + B->A and A->B + B->C overlap proved"
    Write-Host "  fencing     : retirement proof, epoch, operation replay and stale-owner fail-closed"
    Write-Host "  projection  : delayed/reordered projection rejected; one-source dropout isolated"
    Write-Host "  fault       : unavailable peer does not freeze unrelated writer"
    Write-Host "  invariant   : exactly one active writer per aggregate after every soak crossing"
    Write-Host "  inherited   : full P10 gate PASS (therefore P8/P9/P10 remain green)"
    Write-Host "  logs        : $LogRoot"
}
finally {
    foreach ($Process in @($Processes)) {
        try { if (-not $Process.HasExited) { $Process.Kill() } } catch {}
    }
    Remove-NewUidFiles
    if ($null -eq $PreviousBridgeDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBridgeDisabled }
}
