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
.\ITEM_SYSTEM_LAB.ps1 -GodotPath "C:\full\path\godot.windows.editor.double.x86_64.exe"
"@
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath

Write-Host "Launching item laboratory" -ForegroundColor Green
Write-Host "Godot: $Godot"
Write-Host "Project: $ProjectRoot"

& $Godot --path $ProjectRoot "res://scenes/items/item_system_lab.tscn"

if ($LASTEXITCODE -ne 0) {
    throw "Item laboratory exited with code $LASTEXITCODE"
}
