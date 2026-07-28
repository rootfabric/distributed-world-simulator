param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "n1-enet-snapshot-runner-summary.json"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

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

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
$Tests = @(
    "res://tests/network/test_n1_enet_snapshot_contracts.gd",
    "res://tests/network/test_n1_enet_snapshot_processes.gd"
)
$Summary = [ordered]@{
    schema = "planet_simulator.n1_enet_snapshot_runner_summary.v1"
    checkpoint = "v16.5.0-network-n1-snapshot"
    build_id = "n1-enet-handshake-initial-snapshot"
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    finished_at_utc = $null
    godot = $Godot
    project_root = $ProjectRoot
    passed = $false
    steps = @()
}

function Save-Summary {
    $Summary.finished_at_utc = [DateTime]::UtcNow.ToString("o")
    $Summary | ConvertTo-Json -Depth 8 | Set-Content -Path $ReportPath -Encoding UTF8
}

function Invoke-CheckedProcess {
    param([string]$Name, [string[]]$Arguments, [string]$Target)
    Write-Host "Running $Name" -ForegroundColor Cyan
    $Started = [DateTime]::UtcNow
    & $Godot @Arguments
    $ExitCode = $LASTEXITCODE
    $Summary.steps += [ordered]@{
        name = $Name
        target = $Target
        exit_code = $ExitCode
        duration_seconds = [Math]::Round(([DateTime]::UtcNow - $Started).TotalSeconds, 3)
        passed = ($ExitCode -eq 0)
    }
    Save-Summary
    if ($ExitCode -ne 0) { throw "$Name failed with exit code $ExitCode" }
}

try {
    Write-Host "Godot: $Godot"
    Write-Host "Checkpoint: v16.5.0-network-n1-snapshot"
    Invoke-CheckedProcess -Name "editor_import_parse" -Arguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit") -Target "res://"
    foreach ($Test in $Tests) {
        Invoke-CheckedProcess -Name ([IO.Path]::GetFileNameWithoutExtension($Test)) -Arguments @("--headless", "--path", $ProjectRoot, "--script", $Test) -Target $Test
    }
    $Summary.passed = $true
    Save-Summary
    Write-Host "N1.1 ENet snapshot tests passed." -ForegroundColor Green
    Write-Host "Report: $ReportPath"
}
catch {
    $Summary.passed = $false
    Save-Summary
    Write-Host $_ -ForegroundColor Red
    exit 1
}
