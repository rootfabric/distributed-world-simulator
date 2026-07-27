param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-GodotExecutable {
    param([string]$RequestedPath)
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $Candidates += $RequestedPath }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
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
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Resolve-Path $Candidate).Path
        }
    }
    throw "Double-precision Godot was not found. Set GODOT_BIN or pass -GodotPath."
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
    Write-Host "${Name}: PASS" -ForegroundColor Green
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
$Python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $Python) { $Python = Get-Command python3 -ErrorAction SilentlyContinue }
if ($null -eq $Python) { throw "Python 3 is required for the process lifecycle test." }

Write-Host "Godot: $Godot"
Write-Host "Project: $ProjectRoot"

Invoke-Step -Name "Editor import and parse" -Action {
    & $Godot --headless --editor --path $ProjectRoot --quit
}
Invoke-Step -Name "Lifecycle coordinator contracts" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/runtime/test_lifecycle_coordinator.gd"
}
Invoke-Step -Name "Simulator shutdown failure paths" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/runtime/test_simulator_shutdown_failures.gd"
}
Invoke-Step -Name "World switch during terrain generation" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/runtime/test_world_switch_during_generation.gd"
}
Invoke-Step -Name "Unified runtime boot and exit" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/integration/test_unified_runtime_boot.gd"
}
Invoke-Step -Name "World boot matrix and exit" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/runtime/test_world_boot_matrix.gd"
}
Invoke-Step -Name "Simulation-server process lifecycle" -Action {
    & $Python.Source (Join-Path $ProjectRoot "tests/process/test_simulation_server_lifecycle.py") `
        --godot $Godot `
        --project $ProjectRoot
}

Write-Host ""
Write-Host "Foundation lifecycle part 2 tests passed." -ForegroundColor Green
