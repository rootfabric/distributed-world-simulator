[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",

    [ValidateRange(120, 10000)]
    [int]$SoakIterations = 120,

    [ValidateRange(180, 900)]
    [int]$TimeoutSeconds = 240,

    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$CanonicalHandoffs = 20

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "project.godot missing: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot 4.7.1 double console executable missing: $GodotExe"
}

$ActualGodot = ((& $GodotExe --version) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualGodot -ne $ExpectedGodot) {
    throw "Unexpected Godot '$ActualGodot'; expected '$ExpectedGodot'."
}

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0 FINAL requires a clean worktree:`n$($StatusBefore -join "`n")"
}

$HeadBefore = ((& git -C $ProjectRoot rev-parse HEAD) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($HeadBefore)) {
    throw "Unable to resolve git HEAD."
}

$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ':(glob)**/*.uid')
$UidBeforeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($Uid in $UidBefore) { [void]$UidBeforeSet.Add([string]$Uid) }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED = "1"

$RunId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0,8))
$LogRoot = Join-Path $ProjectRoot "artifacts\runtime\sm0-final-$RunId"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Remove-NewUidFiles {
    $After = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ':(glob)**/*.uid')
    foreach ($Uid in $After) {
        if (-not $UidBeforeSet.Contains([string]$Uid)) {
            Remove-Item -LiteralPath (Join-Path $ProjectRoot $Uid) -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-FinalCompileCheck {
    param([string]$ScriptPath)

    Write-Host "[SM0-FINAL] Compile check: $ScriptPath"
    & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "SM0 FINAL compile check failed: $ScriptPath"
    }
}

function Invoke-FinalFocusedTest {
    param(
        [string]$ScriptPath,
        [string]$PassPattern,
        [string]$LogName,
        [string]$Label
    )

    Write-Host "[SM0-FINAL] Running $Label..."
    $Output = @(& $GodotExe --headless --path $ProjectRoot --script $ScriptPath 2>&1)
    $ExitCode = $LASTEXITCODE
    $Output | Tee-Object -FilePath (Join-Path $LogRoot $LogName) | ForEach-Object { Write-Host $_ }
    if ($ExitCode -ne 0 -or -not (($Output -join "`n") -match $PassPattern)) {
        throw "SM0 FINAL focused gate failed: $Label"
    }
}

function Invoke-ChildPowerShellGate {
    param(
        [string]$RunnerPath,
        [string[]]$Arguments,
        [string]$LogName,
        [string]$PassPattern,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $RunnerPath -PathType Leaf)) {
        throw "$Label runner missing: $RunnerPath"
    }

    Write-Host "[SM0-FINAL] Running $Label..."
    $CommandArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $RunnerPath) + $Arguments
    $Output = @(& powershell.exe @CommandArgs 2>&1)
    $ExitCode = $LASTEXITCODE
    $Output | Tee-Object -FilePath (Join-Path $LogRoot $LogName) | ForEach-Object { Write-Host $_ }

    if ($ExitCode -ne 0) {
        throw "$Label exited with code $ExitCode."
    }
    if (-not (($Output -join "`n") -match $PassPattern)) {
        throw "$Label did not emit its required PASS marker."
    }
    return @($Output)
}

function Get-FreshBaselineSummary {
    param([datetime]$NotOlderThan)

    $LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
    $AcceptanceRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0Seamless\logs"
    if (-not (Test-Path -LiteralPath $AcceptanceRoot -PathType Container)) {
        throw "Canonical SM0 acceptance log root missing after baseline gate: $AcceptanceRoot"
    }

    $Candidates = @(
        Get-ChildItem -LiteralPath $AcceptanceRoot -Filter "summary.json" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $NotOlderThan.AddSeconds(-2) } |
            Sort-Object LastWriteTime -Descending
    )
    if ($Candidates.Count -lt 1) {
        throw "Fresh canonical SM0 summary.json was not produced."
    }
    return $Candidates[0]
}

function Assert-BaselineSummary {
    param([string]$Path)

    try {
        $Summary = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Canonical SM0 summary is invalid JSON: $Path"
    }

    if ([string]$Summary.schema -ne "distributed_world_simulator.sm0_acceptance_summary.v1") {
        throw "Unexpected canonical SM0 summary schema: $($Summary.schema)"
    }
    if ([string]$Summary.result -ne "PASS") {
        throw "Canonical SM0 summary result is not PASS."
    }
    if ([int]$Summary.expected_handoffs -ne $CanonicalHandoffs -or [int]$Summary.handoffs_completed -ne $CanonicalHandoffs) {
        throw "Canonical SM0 final handoff count mismatch: $($Summary.handoffs_completed) / $($Summary.expected_handoffs)"
    }
    if ([int]$Summary.player_identity_changes -ne 0) {
        throw "Canonical SM0 final changed player identity $($Summary.player_identity_changes) times."
    }
    if ([int]$Summary.invariant_violation_count -ne 0) {
        throw "Canonical SM0 final observed invariant violations."
    }
    if ([int]$Summary.unexpected_error_count -ne 0) {
        throw "Canonical SM0 final observed unexpected errors."
    }
    if ([int]$Summary.authority_epoch_start -ne 1 -or [int]$Summary.authority_epoch_end -ne (1 + $CanonicalHandoffs)) {
        throw "Canonical SM0 final authority epoch mismatch: $($Summary.authority_epoch_start) -> $($Summary.authority_epoch_end)"
    }

    return $Summary
}

try {
    Write-Host "[SM0-FINAL] Godot          : $ActualGodot"
    Write-Host "[SM0-FINAL] HEAD           : $HeadBefore"
    Write-Host "[SM0-FINAL] Handoffs       : $CanonicalHandoffs"
    Write-Host "[SM0-FINAL] Soak iterations: $SoakIterations"
    Write-Host "[SM0-FINAL] Logs           : $LogRoot"

    $ReferenceScripts = @(
        "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_node.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p8_1_visual_reference_frame.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p8_1_1_stationary_passenger.gd"
    )
    foreach ($ScriptPath in $ReferenceScripts) {
        Invoke-FinalCompileCheck -ScriptPath $ScriptPath
    }

    Invoke-FinalFocusedTest `
        -ScriptPath "res://tests/runtime/seamless/sm0/test_sm0_p8_1_visual_reference_frame.gd" `
        -PassPattern 'SM0 P8\.1 visual reference-frame repair: PASS \(33 assertions\)' `
        -LogName "p8-1-reference-frame.log" `
        -Label "P8.1 reference-frame continuity"

    Invoke-FinalFocusedTest `
        -ScriptPath "res://tests/runtime/seamless/sm0/test_sm0_p8_1_1_stationary_passenger.gd" `
        -PassPattern 'SM0 P8\.1\.1 stationary passenger: PASS \(14 assertions\)' `
        -LogName "p8-1-1-stationary-passenger.log" `
        -Label "P8.1.1 stationary passenger continuity"

    $BaselineStarted = Get-Date
    $BaselineRunner = Join-Path $ProjectRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
    $BaselineArgs = @(
        "-Final",
        "-Restart",
        "-ProjectRoot", $ProjectRoot,
        "-GodotExe", $GodotExe,
        "-TimeoutSeconds", ([string]$TimeoutSeconds)
    )
    if ($AllowDirty) { $BaselineArgs += "-AllowDirty" }

    $BaselineOutput = Invoke-ChildPowerShellGate `
        -RunnerPath $BaselineRunner `
        -Arguments $BaselineArgs `
        -LogName "canonical-20-handoff.log" `
        -PassPattern 'SM0 log analysis:\s+PASS' `
        -Label "canonical 20-handoff acceptance"

    if (-not (($BaselineOutput -join "`n") -match 'handoffs\s*:\s*20\s*/\s*20')) {
        throw "Canonical 20-handoff acceptance did not report 20 / 20."
    }

    $FreshSummaryFile = Get-FreshBaselineSummary -NotOlderThan $BaselineStarted
    $BaselineSummary = Assert-BaselineSummary -Path $FreshSummaryFile.FullName
    Copy-Item -LiteralPath $FreshSummaryFile.FullName -Destination (Join-Path $LogRoot "canonical-summary.json") -Force

    $P11Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P11_FAULT_MATRIX.ps1"
    $P11Args = @(
        "-ProjectRoot", $ProjectRoot,
        "-GodotExe", $GodotExe,
        "-Iterations", ([string]$SoakIterations)
    )
    if ($AllowDirty) { $P11Args += "-AllowDirty" }

    $P11Output = Invoke-ChildPowerShellGate `
        -RunnerPath $P11Runner `
        -Arguments $P11Args `
        -LogName "p11-integrated.log" `
        -PassPattern 'SM0-P11 deterministic fault matrix \+ simultaneous-crossing soak:\s+PASS' `
        -Label "P11 deterministic fault matrix + process-isolated soak"

    $P11Text = $P11Output -join "`n"
    if ($P11Text -notmatch 'SM0 P11 deterministic fault matrix: PASS \(68 assertions\)') {
        throw "Integrated P11 output is missing deterministic 68-assertion PASS."
    }
    $ExpectedSoakPattern = "SM0 P11 process-isolated simultaneous crossings \+ soak: PASS \($SoakIterations iterations / [0-9]+ assertions\)"
    if ($P11Text -notmatch $ExpectedSoakPattern) {
        throw "Integrated P11 output is missing the requested $SoakIterations-iteration process soak PASS."
    }
    if ($P11Text -notmatch 'full P10 gate PASS') {
        throw "Integrated P11 output did not prove inherited P10/P9/P8 closure."
    }

    Remove-NewUidFiles

    $HeadAfter = ((& git -C $ProjectRoot rev-parse HEAD) | Select-Object -First 1).Trim()
    if ($LASTEXITCODE -ne 0 -or $HeadAfter -ne $HeadBefore) {
        throw "SM0 FINAL changed or moved HEAD: $HeadBefore -> $HeadAfter"
    }

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after SM0 FINAL" }
    if (-not $AllowDirty -and (($StatusAfter -join "`n") -ne ($StatusBefore -join "`n"))) {
        throw "SM0 FINAL modified the source worktree:`n$($StatusAfter -join "`n")"
    }

    $FinalSummary = [ordered]@{
        schema = "distributed_world_simulator.sm0_final_acceptance_summary.v1"
        result = "PASS"
        git_head = $HeadBefore
        godot_version = $ActualGodot
        canonical_handoffs = $CanonicalHandoffs
        canonical_handoffs_completed = [int]$BaselineSummary.handoffs_completed
        authority_epoch_start = [int]$BaselineSummary.authority_epoch_start
        authority_epoch_end = [int]$BaselineSummary.authority_epoch_end
        player_identity_changes = [int]$BaselineSummary.player_identity_changes
        invariant_violation_count = [int]$BaselineSummary.invariant_violation_count
        unexpected_error_count = [int]$BaselineSummary.unexpected_error_count
        p8_1_reference_frame_assertions = 33
        p8_1_1_stationary_passenger_assertions = 14
        p11_fault_matrix_assertions = 68
        p11_process_soak_iterations = $SoakIterations
        inherited_p8_p9_p10_gate = "PASS"
        canonical_summary_source = $FreshSummaryFile.FullName
        evidence_directory = $LogRoot
    }
    $FinalSummaryPath = Join-Path $LogRoot "summary.json"
    $FinalSummary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $FinalSummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0 FINAL integrated closure / canonical acceptance: PASS"
    Write-Host "  HEAD        : $HeadBefore"
    Write-Host "  canonical   : 20 / 20 A<->B handoffs; stable player identity; epoch 1 -> 21"
    Write-Host "  reference   : P8.1 33 + P8.1.1 14 assertions"
    Write-Host "  world/item  : inherited P9 full foreign-item boundary gate PASS"
    Write-Host "  view/LOD    : inherited P10 multi-authority composition gate PASS"
    Write-Host "  fault       : P11 deterministic 68 assertions"
    Write-Host "  soak        : 3 authority processes / $SoakIterations simultaneous-crossing iterations"
    Write-Host "  invariant   : zero split-brain / zero identity changes / zero unexpected errors"
    Write-Host "  summary     : $FinalSummaryPath"
    Write-Host "  logs        : $LogRoot"
}
finally {
    Remove-NewUidFiles
    if ($null -eq $PreviousBridgeDisabled) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBridgeDisabled
    }
}
