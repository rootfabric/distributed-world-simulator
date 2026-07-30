param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportRoot = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportRoot "m2-dedicated-graphical-client-summary.json"
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

function Resolve-Godot {
    param([string]$Requested)

    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) { $Candidates += $Requested }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
    $Candidates += @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot4", "godot")) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $Command) { $Candidates += $Command.Source }
    }
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Resolve-Path $Candidate).Path
        }
    }
    throw "Double-precision Godot was not found. Set GODOT_BIN or pass -GodotPath."
}

$Godot = Resolve-Godot -Requested $GodotPath
$Tests = @(
    "res://tests/runtime/test_launch_options.gd",
    "res://tests/runtime/test_h0_listen_host_contracts.gd",
    "res://tests/runtime/test_h1_playable_listen_host_contracts.gd",
    "res://tests/runtime/test_h1_playable_listen_host_integration.gd",
    "res://tests/runtime/test_h2_player_ownership_contracts.gd",
    "res://tests/runtime/test_h2_host_client_processes.gd",
    "res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd",
    "res://tests/runtime/test_h3_dedicated_multiplayer_processes.gd",
    "res://tests/runtime/test_m1_networked_gameplay_contracts.gd",
    "res://tests/runtime/test_m1_unified_networked_gameplay_service.gd",
    "res://tests/runtime/test_m2_graphical_client_contracts.gd",
    "res://tests/runtime/test_m2_dedicated_graphical_processes.gd",
    "res://tests/network/test_t1_multi_peer_transport_contracts.gd",
    "res://tests/network/test_t1_multi_peer_transport_processes.gd",
    "res://tests/runtime/test_a2_networked_gameplay_architecture.gd",
    "res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd"
)

$Summary = [ordered]@{
    schema = "planet_simulator.m2_dedicated_graphical_client_summary.v1"
    checkpoint = "v16.10.1-runtime-m2-dedicated-graphical-client"
    build_id = "m2-dedicated-graphical-client"
    decision = "DEDICATED_PLUS_ONE_GRAPHICAL_CLIENT"
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    finished_at_utc = $null
    godot = $Godot
    project_root = $ProjectRoot
    declared_test_count = $Tests.Count
    passed = $false
    steps = @()
}

function Save-Summary {
    $Summary.finished_at_utc = [DateTime]::UtcNow.ToString("o")
    $Json = $Summary | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText(
        $ReportPath,
        $Json + [Environment]::NewLine,
        (New-Object Text.UTF8Encoding($false))
    )
}

function Run-Step {
    param(
        [string]$Name,
        [string]$Target,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $Started = [DateTime]::UtcNow
    $Captured = @()
    $LogPath = Join-Path $ReportRoot "m2-$Name.log"
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    $RawExitCode = 1

    try {
        # Godot may emit expected diagnostics on stderr even when it exits with
        # code 0. Capture those diagnostics without converting NativeCommandError
        # into a terminating PowerShell exception.
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        & $Godot @Arguments 2>&1 |
            Tee-Object -Variable Captured |
            Tee-Object -FilePath $LogPath |
            ForEach-Object { Write-Host $_ }
        $RawExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
        }
    }

    $OutputText = ($Captured | Out-String)
    $HasFailureMarker = $OutputText -match '(?m): FAIL(?:\s|\()'
    $ExitCode = if ($RawExitCode -ne 0) { $RawExitCode } elseif ($HasFailureMarker) { 1 } else { 0 }
    $Summary.steps += [ordered]@{
        name = $Name
        target = $Target
        exit_code = $ExitCode
        duration_seconds = [Math]::Round(([DateTime]::UtcNow - $Started).TotalSeconds, 3)
        passed = ($ExitCode -eq 0)
        log_path = $LogPath
    }
    Save-Summary

    if ($ExitCode -ne 0) {
        throw "$Name failed with exit code $ExitCode"
    }
    Write-Host "${Name}: PASS" -ForegroundColor Green
}

try {
    Write-Host "Godot: $Godot"
    Write-Host "Project: $ProjectRoot"
    Write-Host "Checkpoint: v16.10.1-runtime-m2-dedicated-graphical-client"

    Run-Step `
        -Name "editor_import" `
        -Target "res://" `
        -Arguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit")

    foreach ($Test in $Tests) {
        Run-Step `
            -Name ([IO.Path]::GetFileNameWithoutExtension($Test)) `
            -Target $Test `
            -Arguments @("--headless", "--path", $ProjectRoot, "--script", $Test)
    }

    $Summary.passed = $true
    Save-Summary
    Write-Host ""
    Write-Host "M2 dedicated graphical client: PASS" -ForegroundColor Green
    Write-Host "Report: $ReportPath"
}
catch {
    $Summary.passed = $false
    Save-Summary
    Write-Host $_ -ForegroundColor Red
    exit 1
}
