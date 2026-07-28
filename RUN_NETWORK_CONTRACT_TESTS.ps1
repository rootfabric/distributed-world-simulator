param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "network-contract-summary.json"
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
    "res://tests/runtime/test_launch_options.gd",
    "res://tests/network/test_network_contracts.gd",
    "res://tests/network/test_loopback_command_transport.gd",
    "res://tests/network/test_network_transport_boundary.gd",
    "res://tests/network/test_n0_extended_contracts.gd",
    "res://tests/network/test_n0_contract_mutation_matrix.gd",
    "res://tests/network/test_n0_golden_fixtures.gd",
    "res://tests/network/test_loopback_replication_transport.gd",
    "res://tests/network/test_n0_review_regressions.gd",
    "res://tests/network/test_handoff_state_machine.gd",
    "res://tests/network/test_handoff_transition_matrix.gd",
    "res://tests/entities/test_authority_revision_semantics.gd",
    "res://tests/runtime/test_kernel_ports.gd"
)

$Summary = [ordered]@{
    schema = "planet_simulator.network_contract_summary.v1"
    checkpoint = "v16.4.2-network-transport-boundary"
    build_id = "n1-transport-lifecycle-boundary"
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
    $Summary | ConvertTo-Json -Depth 8 | Set-Content -Path $ReportPath -Encoding UTF8
}

function Invoke-CheckedProcess {
    param(
        [string]$Name,
        [string]$Kind,
        [string[]]$Arguments,
        [string]$Target
    )
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $Started = [DateTime]::UtcNow
    & $Godot @Arguments
    $ExitCode = $LASTEXITCODE
    $Duration = ([DateTime]::UtcNow - $Started).TotalSeconds
    $Summary.steps += [ordered]@{
        name = $Name
        kind = $Kind
        target = $Target
        exit_code = $ExitCode
        duration_seconds = [Math]::Round($Duration, 3)
        passed = ($ExitCode -eq 0)
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
    Write-Host "Checkpoint: v16.4.2-network-transport-boundary"

    Invoke-CheckedProcess `
        -Name "editor_import_parse" `
        -Kind "editor" `
        -Arguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit") `
        -Target "res://"

    foreach ($Test in $Tests) {
        Invoke-CheckedProcess `
            -Name ([IO.Path]::GetFileNameWithoutExtension($Test)) `
            -Kind "headless_script" `
            -Arguments @("--headless", "--path", $ProjectRoot, "--script", $Test) `
            -Target $Test
    }

    $Summary.passed = $true
    Save-Summary
    Write-Host ""
    Write-Host "Foundation/N0 contract tests passed." -ForegroundColor Green
    Write-Host "Report: $ReportPath"
}
catch {
    $Summary.passed = $false
    Save-Summary
    Write-Host $_ -ForegroundColor Red
    exit 1
}
