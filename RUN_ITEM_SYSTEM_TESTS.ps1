param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-ConsoleSibling {
    param([string]$ExecutablePath)

    $Resolved = (Resolve-Path $ExecutablePath).Path
    if ([IO.Path]::GetFileName($Resolved) -like "*.console.exe") {
        return $Resolved
    }

    $Directory = Split-Path -Parent $Resolved
    $BaseName = [IO.Path]::GetFileNameWithoutExtension($Resolved)
    $ConsoleSibling = Join-Path $Directory ($BaseName + ".console.exe")
    if (Test-Path $ConsoleSibling) {
        return (Resolve-Path $ConsoleSibling).Path
    }
    return $Resolved
}

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path $RequestedPath)) {
            throw "Godot executable not found: $RequestedPath"
        }
        return (Get-ConsoleSibling -ExecutablePath $RequestedPath)
    }

    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
        $Candidates += $env:GODOT_BIN
    }

    $Candidates += @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe",
        (Join-Path $ProjectRoot "godot.windows.editor.double.x86_64.console.exe"),
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.exe",
        (Join-Path $ProjectRoot "godot.windows.editor.double.x86_64.exe")
    )

    foreach ($CommandName in @(
        "godot.windows.editor.double.x86_64.console.exe",
        "godot.windows.editor.double.x86_64.exe"
    )) {
        $Command = Get-Command $CommandName -ErrorAction SilentlyContinue
        if ($null -ne $Command) {
            $Candidates += $Command.Source
        }
    }

    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Get-ConsoleSibling -ExecutablePath $Candidate)
        }
    }

    throw @"
Double-precision Godot was not found.
Run with an explicit path:
.\RUN_ITEM_SYSTEM_TESTS.ps1 -GodotPath "C:\full\path\godot.windows.editor.double.x86_64.console.exe"
"@
}

function Invoke-GodotCheck {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    & $Godot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
    Write-Host "${Name}: PASS" -ForegroundColor Green
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
if ([IO.Path]::GetFileName($Godot) -notlike "*.console.exe") {
    Write-Warning "Console Godot executable was not found. Diagnostic output may be unavailable: $Godot"
}

Write-Host "Godot: $Godot"
Write-Host "Project: $ProjectRoot"

Invoke-GodotCheck -Name "Project import and script parse" -Arguments @(
    "--headless",
    "--editor",
    "--path",
    $ProjectRoot,
    "--quit"
)

Invoke-GodotCheck -Name "Item domain invariants" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_domain.gd"
)

Invoke-GodotCheck -Name "Item identity and state store" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_identity_and_state_store.gd"
)

Invoke-GodotCheck -Name "Complete item graph persistence" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_graph_persistence.gd"
)

Invoke-GodotCheck -Name "Item operation ledger" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_operation_ledger.gd"
)

Invoke-GodotCheck -Name "Item gravity and recursive physical mass" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_physics_environment.gd"
)

Invoke-GodotCheck -Name "Player inventory and interaction matrix" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_player_inventory_flow.gd"
)

Invoke-GodotCheck -Name "Stack merge, split and quantity UI" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_stack_transfers.gd"
)

Invoke-GodotCheck -Name "Placeable fixtures and admin grants" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_placement_and_admin.gd"
)

Invoke-GodotCheck -Name "Item laboratory integration" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_lab_integration.gd"
)

Invoke-GodotCheck -Name "Inventory UI-I0 component architecture" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/ui/test_inventory_ui_i0_architecture.gd"
)

Write-Host ""
Write-Host "All item-system tests passed." -ForegroundColor Green
