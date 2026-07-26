param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path $RequestedPath)) {
            throw "Godot executable not found: $RequestedPath"
        }
        return (Resolve-Path $RequestedPath).Path
    }

    $Candidates = @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.exe",
        (Join-Path $ProjectRoot "godot.windows.editor.double.x86_64.exe")
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate) {
            return (Resolve-Path $Candidate).Path
        }
    }

    $Command = Get-Command "godot.windows.editor.double.x86_64.exe" -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }

    throw @"
Double-precision Godot was not found.
Run with an explicit path:
.\RUN_ITEM_SYSTEM_TESTS.ps1 -GodotPath "C:\full\path\godot.windows.editor.double.x86_64.exe"
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

Invoke-GodotCheck -Name "Item laboratory integration" -Arguments @(
    "--headless",
    "--path",
    $ProjectRoot,
    "--script",
    "res://tests/items/test_item_lab_integration.gd"
)

Write-Host ""
Write-Host "All item-system tests passed." -ForegroundColor Green
