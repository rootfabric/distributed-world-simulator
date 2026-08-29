param(
    [string]$GodotPath = "",
    [int]$Runs = 10
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"

$Candidates = @()
if ($GodotPath) { $Candidates += $GodotPath }
if ($env:GODOT_BIN) { $Candidates += $env:GODOT_BIN }
foreach ($Name in @(
    "godot.windows.editor.double.x86_64.console.exe",
    "godot.windows.editor.double.x86_64.exe",
    "godot4",
    "godot"
)) {
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $Command) { $Candidates += $Command.Source }
}
$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$Godot = $Candidates |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -Unique |
    Select-Object -First 1

if ($null -eq $Godot) {
    throw "Exact double Godot not found. Set GODOT_BIN or pass -GodotPath."
}

$Godot = (Resolve-Path $Godot).Path
$ActualGodot = (& $Godot --version | Select-Object -First 1).Trim()
if ($ActualGodot -ne $ExpectedGodot) {
    throw "Godot mismatch. Expected $ExpectedGodot, got $ActualGodot"
}

$Head = (git -C $Root rev-parse HEAD).Trim()
$Tree = (git -C $Root rev-parse 'HEAD^{tree}').Trim()
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ResultRoot = Join-Path $Root "artifacts\test-results\m5-stability-$Stamp"
New-Item -ItemType Directory -Force -Path $ResultRoot | Out-Null

$Summary = [ordered]@{
    schema = "distributed_world_simulator.m5_graphical_stability.v1"
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    head_sha = $Head
    tree_sha = $Tree
    godot = $Godot
    godot_version = $ActualGodot
    requested_runs = $Runs
    completed_runs = 0
    passed_runs = 0
    failed_run = $null
    pipe_smoke = $null
    passed = $false
    runs = @()
}

$EnvNames = @(
    "HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA",
    "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
    "PLANET_SIMULATOR_INVENTORY_PROFILE",
    "BREAKPOINT_RUNTIME_DISABLED",
    "GODOT_SILENCE_ROOT_WARNING"
)

function Invoke-WithIsolatedProfile {
    param(
        [string]$ProfileRoot,
        [scriptblock]$Body
    )
    $Data = Join-Path $ProfileRoot "data"
    $Config = Join-Path $ProfileRoot "config"
    $Cache = Join-Path $ProfileRoot "cache"
    foreach ($Path in @($ProfileRoot, $Data, $Config, $Cache)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }

    $Saved = @{}
    foreach ($Name in $EnvNames) {
        $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    }

    try {
        $env:HOME = $ProfileRoot
        $env:USERPROFILE = $ProfileRoot
        $env:APPDATA = $Data
        $env:LOCALAPPDATA = $Data
        $env:XDG_DATA_HOME = $Data
        $env:XDG_CONFIG_HOME = $Config
        $env:XDG_CACHE_HOME = $Cache
        $env:PLANET_SIMULATOR_INVENTORY_PROFILE = "planet_default"
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $env:GODOT_SILENCE_ROOT_WARNING = "1"
        & $Body
    }
    finally {
        foreach ($Name in $EnvNames) {
            [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], "Process")
        }
    }
}

function Save-Summary {
    $Summary.finished_at_utc = [DateTime]::UtcNow.ToString("o")
    $Summary | ConvertTo-Json -Depth 8 |
        Set-Content -Path (Join-Path $ResultRoot "summary.json") -Encoding UTF8
}

Write-Host "M5 graphical stability gate" -ForegroundColor Cyan
Write-Host "HEAD:   $Head"
Write-Host "TREE:   $Tree"
Write-Host "Godot:  $ActualGodot"
Write-Host "Runs:   $Runs"
Write-Host "Output: $ResultRoot"

$PreflightProfile = Join-Path $ResultRoot "profile-preflight"
Invoke-WithIsolatedProfile $PreflightProfile {
    & $Godot --headless --editor --path $Root --quit
    if ($LASTEXITCODE -ne 0) {
        throw "M5 stability editor preflight failed"
    }
}
Write-Host "Editor import: PASS" -ForegroundColor Green

$PipeSmokeProfile = Join-Path $ResultRoot "profile-pipe-smoke"
$PipeSmokeLog = Join-Path $ResultRoot "pipe-smoke.log"
$PipeSmokeCaptured = @()
$PipeSmokeExitCode = 0
Invoke-WithIsolatedProfile $PipeSmokeProfile {
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        & $Godot --headless --path $Root --script res://tests/runtime/test_m5_graphical_multiplayer_acceptance.gd -- --m5-pipe-smoke-only 2>&1 |
            Tee-Object -Variable PipeSmokeCaptured |
            Tee-Object -FilePath $PipeSmokeLog |
            ForEach-Object { Write-Host $_ }
        $script:PipeSmokeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
        }
    }
}
$PipeSmokeText = ($PipeSmokeCaptured | Out-String)
$PipeSmokeMarker = $PipeSmokeText -match 'M5_CHILD_PIPE_OBSERVABILITY_PASS'
$Summary.pipe_smoke = [ordered]@{
    exit_code = $PipeSmokeExitCode
    pass_marker = $PipeSmokeMarker
    log = $PipeSmokeLog
    profile = $PipeSmokeProfile
}
Save-Summary
if ($PipeSmokeExitCode -ne 0 -or -not $PipeSmokeMarker) {
    Write-Host "M5_CHILD_PIPE_OBSERVABILITY_GATE_FAIL exit=$PipeSmokeExitCode" -ForegroundColor Red
    Write-Host "Pipe smoke log: $PipeSmokeLog"
    exit $(if ($PipeSmokeExitCode -ne 0) { $PipeSmokeExitCode } else { 1 })
}
Write-Host "M5_CHILD_PIPE_OBSERVABILITY_GATE_PASS" -ForegroundColor Green

for ($Run = 1; $Run -le $Runs; $Run++) {
    $RunLabel = "{0:D2}" -f $Run
    $ProfileRoot = Join-Path $ResultRoot "profile-run-$RunLabel"
    $LogPath = Join-Path $ResultRoot "run-$RunLabel.log"

    Write-Host ""
    Write-Host "=== M5 stability run $Run/$Runs ===" -ForegroundColor Yellow

    $Started = [DateTime]::UtcNow
    $Captured = @()
    $ExitCode = 0

    Invoke-WithIsolatedProfile $ProfileRoot {
        $PreviousErrorActionPreference = $ErrorActionPreference
        $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
        $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
        try {
            $ErrorActionPreference = "Continue"
            if ($null -ne $NativePreference) {
                Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
            }
            & $Godot --headless --path $Root --script res://tests/runtime/test_m5_graphical_multiplayer_acceptance.gd 2>&1 |
                Tee-Object -Variable Captured |
                Tee-Object -FilePath $LogPath |
                ForEach-Object { Write-Host $_ }
            $script:ExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $PreviousErrorActionPreference
            if ($null -ne $NativePreference) {
                Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
            }
        }
    }

    $OutputText = ($Captured | Out-String)
    $FailureMarker = $OutputText -cmatch '(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)'
    $EffectiveExit = if ($ExitCode -ne 0) { $ExitCode } elseif ($FailureMarker) { 1 } else { 0 }
    $Duration = ([DateTime]::UtcNow - $Started).TotalSeconds

    $RunRecord = [ordered]@{
        run = $Run
        exit_code = $EffectiveExit
        raw_exit_code = $ExitCode
        duration_seconds = [Math]::Round($Duration, 3)
        failure_marker = $FailureMarker
        log = $LogPath
        profile = $ProfileRoot
        passed = ($EffectiveExit -eq 0)
    }
    $Summary.runs += $RunRecord
    $Summary.completed_runs = $Run

    if ($EffectiveExit -ne 0) {
        $Summary.failed_run = $RunRecord
        Save-Summary
        Write-Host ""
        Write-Host "M5_GRAPHICAL_STABILITY_FAIL run=$Run exit=$EffectiveExit" -ForegroundColor Red
        Write-Host "First failure preserved: $LogPath"
        exit $EffectiveExit
    }

    $Summary.passed_runs = $Run
    Save-Summary
    Write-Host "M5 stability run ${Run}: PASS" -ForegroundColor Green
}

$Summary.passed = $true
Save-Summary

Write-Host ""
Write-Host "M5_GRAPHICAL_STABILITY_PASS $Runs/$Runs" -ForegroundColor Green
Write-Host "summary=$(Join-Path $ResultRoot 'summary.json')"
