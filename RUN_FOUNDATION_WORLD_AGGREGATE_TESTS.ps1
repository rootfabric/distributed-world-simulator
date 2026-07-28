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
if ($null -eq $Python) { throw "Python 3 is required for the process-level server boundary test." }

Write-Host "Godot: $Godot"
Write-Host "Project: $ProjectRoot"
Write-Host "Checkpoint: v16.7.0-repository-r3.1-authoritative-recovery"

Invoke-Step -Name "Editor import and parse" -Action {
    & $Godot --headless --editor --path $ProjectRoot --quit
}
Invoke-Step -Name "World entity aggregate and lifecycle" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/entities/test_world_entity_aggregate.gd"
}
Invoke-Step -Name "World entity store failure paths" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/entities/test_world_entity_store_failures.gd"
}
Invoke-Step -Name "Legacy WORLD relation migration" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/items/test_world_item_aggregate_migration.gd"
}
Invoke-Step -Name "Complete item graph persistence" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/items/test_item_graph_persistence.gd"
}
Invoke-Step -Name "Player WORLD item flow" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/items/test_player_inventory_flow.gd"
}
Invoke-Step -Name "Placement aggregate integration" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/items/test_item_placement_and_admin.gd"
}
Invoke-Step -Name "Simulation kernel and persistence boundary" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/runtime/test_simulation_kernel_boundary.gd"
}
Invoke-Step -Name "Authority revision semantics" -Action {
    & $Godot --headless --path $ProjectRoot --script "res://tests/entities/test_authority_revision_semantics.gd"
}
Invoke-Step -Name "Simulation-server kernel boundary" -Action {
    & $Python.Source (Join-Path $ProjectRoot "tests/process/test_simulation_server_lifecycle.py") --godot $Godot --project $ProjectRoot
}

Write-Host ""
Write-Host "Foundation world-aggregate profile passed." -ForegroundColor Green
