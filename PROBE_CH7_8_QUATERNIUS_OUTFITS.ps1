param(
    [string]$GodotPath = "",
    [string]$ArchivePath = "",
    [string]$AssetSourcePath = "",
    [switch]$OpenDownloadPage
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$DownloadPage = "https://quaternius.itch.io/modular-character-outfits-fantasy/purchase"

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

function Find-StandardArchive([string]$Requested) {
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if (-not (Test-Path -LiteralPath $Requested -PathType Leaf)) {
            throw "ArchivePath does not exist: $Requested"
        }
        return (Resolve-Path -LiteralPath $Requested).Path
    }

    $Downloads = Join-Path $HOME "Downloads"
    if (-not (Test-Path $Downloads -PathType Container)) {
        return ""
    }

    $Matches = @(
        Get-ChildItem -LiteralPath $Downloads -File -Filter "*.zip" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '(?i)modular.*character.*outfits.*fantasy' -and
                $_.Name -match '(?i)standard'
            } |
            Sort-Object LastWriteTime -Descending
    )

    if ($Matches.Count -gt 0) {
        return $Matches[0].FullName
    }
    return ""
}

function Install-AssetDirectory([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "AssetSourcePath does not exist: $Source"
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
}

function Install-AssetArchive([string]$Archive, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Write-Host "CH7.8 extracting archive:" -ForegroundColor Cyan
    Write-Host "  $Archive"
    Write-Host "to:" -ForegroundColor Cyan
    Write-Host "  $Destination"
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
}

$Godot = Resolve-Godot $GodotPath
$AssetRoot = Join-Path $Root "assets\external\quaternius\modular_outfits_fantasy"

Write-Host "Godot: $Godot"
Write-Host "CH7.8 outfit asset root: $AssetRoot"

if (-not (Test-Path $AssetRoot -PathType Container)) {
    if (-not [string]::IsNullOrWhiteSpace($AssetSourcePath)) {
        Install-AssetDirectory $AssetSourcePath $AssetRoot
    }
    else {
        $ResolvedArchive = Find-StandardArchive $ArchivePath
        if (-not [string]::IsNullOrWhiteSpace($ResolvedArchive)) {
            Install-AssetArchive $ResolvedArchive $AssetRoot
        }
    }
}

if (-not (Test-Path $AssetRoot -PathType Container)) {
    Write-Host ""
    Write-Host "Asset root is missing and no Standard ZIP was found automatically in Downloads." -ForegroundColor Yellow
    Write-Host "Download the free Quaternius 'Modular Character Outfits - Fantasy[Standard].zip'." -ForegroundColor Yellow
    Write-Host "Download page:" -ForegroundColor Yellow
    Write-Host "  $DownloadPage" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "After the ZIP appears in your Downloads folder, run this same command again." -ForegroundColor Yellow
    Write-Host "The launcher will discover and extract it automatically." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Optional explicit archive usage:" -ForegroundColor DarkGray
    Write-Host '  .\PROBE_CH7_8_QUATERNIUS_OUTFITS.ps1 -GodotPath $Godot -ArchivePath "C:\path\Modular Character Outfits - Fantasy[Standard].zip"' -ForegroundColor DarkGray
    if ($OpenDownloadPage) {
        Start-Process $DownloadPage
    }
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
