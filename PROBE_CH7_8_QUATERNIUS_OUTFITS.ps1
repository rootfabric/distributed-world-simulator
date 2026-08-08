param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Resolve-Godot([string]$Requested) {
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
    throw "Godot 4.7.1 double was not found. Pass -GodotPath or set GODOT_BIN."
}

$Godot = Resolve-Godot $GodotPath
$AssetRoot = Join-Path $Root "assets\external\quaternius\modular_outfits_fantasy"

Write-Host "Godot: $Godot"
Write-Host "CH7.8 outfit asset root: $AssetRoot"
if (-not (Test-Path $AssetRoot)) {
    Write-Host ""
    Write-Host "Asset root is missing." -ForegroundColor Yellow
    Write-Host "Download Quaternius 'Modular Character Outfits - Fantasy' [Standard] and extract it under:" -ForegroundColor Yellow
    Write-Host "  $AssetRoot" -ForegroundColor Cyan
    exit 2
}

Write-Host ""
Write-Host "[editor_import]" -ForegroundColor Cyan
& $Godot @(
    "--headless", "--editor", "--quit",
    "--path", $Root
)
if ($LASTEXITCODE -ne 0) {
    throw "CH7.8 editor import failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "[outfit_compatibility_probe]" -ForegroundColor Cyan
& $Godot @(
    "--headless", "--path", $Root,
    "--script", "res://tests/characters/probe_ch7_8_quaternius_outfit_assets.gd"
)
if ($LASTEXITCODE -ne 0) {
    throw "CH7.8 outfit compatibility probe failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "CH7.8 Quaternius outfit compatibility probe: PASS" -ForegroundColor Green
exit 0
