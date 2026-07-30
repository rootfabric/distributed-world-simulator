param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportRoot = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportRoot "a2-networked-gameplay-audit-summary.json"
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

function Resolve-GodotExecutable {
    param([string]$RequestedPath)
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $Candidates += $RequestedPath }
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

$Godot = Resolve-GodotExecutable $GodotPath
$Tests = @(
    "res://tests/runtime/test_a2_networked_gameplay_architecture.gd",
    "res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd",
    "res://tests/runtime/test_h3_dedicated_multiplayer_processes.gd",
    "res://tests/runtime/test_h2_player_ownership_contracts.gd",
    "res://tests/runtime/test_h2_host_client_processes.gd",
    "res://tests/runtime/test_launch_options.gd",
    "res://tests/runtime/test_h0_listen_host_contracts.gd",
    "res://tests/runtime/test_h1_playable_listen_host_contracts.gd",
    "res://tests/runtime/test_h1_playable_listen_host_integration.gd",
    "res://tests/network/test_t1_multi_peer_transport_contracts.gd",
    "res://tests/network/test_t1_multi_peer_transport_processes.gd"
)
$Summary = [ordered]@{
    schema = "planet_simulator.a2_networked_gameplay_audit_summary.v1"
    checkpoint = "v16.9.4-architecture-a2-networked-gameplay"
    build_id = "a2-networked-gameplay-audit-freeze"
    decision = "FROZEN_WITH_GATES"
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
    [IO.File]::WriteAllText($ReportPath, $Json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-CheckedGodot {
    param([string]$Name,[string]$Target,[string[]]$Arguments)
    $LogPath = Join-Path $ReportRoot ("a2-{0}.log" -f $Name)
    $Started = [DateTime]::UtcNow
    & $Godot @Arguments 2>&1 | Tee-Object -FilePath $LogPath
    $ExitCode = $LASTEXITCODE
    $LogText = if (Test-Path $LogPath) { [IO.File]::ReadAllText($LogPath) } else { "" }
    if ($ExitCode -eq 0 -and $LogText -match ': FAIL(\s|\()') { $ExitCode = 1 }
    $Summary.steps += [ordered]@{
        name = $Name; target = $Target; exit_code = $ExitCode
        duration_seconds = [Math]::Round(([DateTime]::UtcNow - $Started).TotalSeconds, 3)
        passed = ($ExitCode -eq 0)
    }
    if ($ExitCode -ne 0) { Save-Summary; throw "$Name failed with exit code $ExitCode" }
    Write-Host "$Name`: PASS" -ForegroundColor Green
}

try {
    Write-Host "Godot: $Godot"
    Write-Host "Checkpoint: v16.9.4-architecture-a2-networked-gameplay"
    Invoke-CheckedGodot -Name "editor_import" -Target "res://" -Arguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit")
    foreach ($Test in $Tests) {
        Invoke-CheckedGodot -Name ([IO.Path]::GetFileNameWithoutExtension($Test)) -Target $Test -Arguments @("--headless", "--path", $ProjectRoot, "--script", $Test)
    }
    $Summary.passed = $true
    Save-Summary
    Write-Host "A2 networked gameplay architecture audit: PASS" -ForegroundColor Green
    Write-Host "Report: $ReportPath"
}
catch { $Summary.passed = $false; Save-Summary; throw }
