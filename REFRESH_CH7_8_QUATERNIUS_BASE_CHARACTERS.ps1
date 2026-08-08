param(
    [string]$GodotPath = "",
    [string]$ArchivePath = "",
    [switch]$OpenDownloadPage
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$AssetRoot = Join-Path $Root "assets\external\quaternius\base_characters"
$DownloadPage = "https://quaternius.itch.io/universal-base-characters/purchase"
$ProbeScript = "res://tests/characters/probe_ch7_8_quaternius_base_variants.gd"

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
                $_.Name -match '(?i)universal.*base.*characters' -and
                $_.Name -match '(?i)standard'
            } |
            Sort-Object LastWriteTime -Descending
    )
    if ($Matches.Count -gt 0) {
        return $Matches[0].FullName
    }
    return ""
}

function Assert-UpdatedArchive([string]$Archive) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $VariantEntries = @(
            $Zip.Entries |
                Where-Object {
                    $_.FullName -match '(?i)(head|upperbody)' -and
                    $_.FullName -match '(?i)\.(gltf|glb|fbx)$'
                }
        )
        if ($VariantEntries.Count -eq 0) {
            throw "The selected Base Characters ZIP contains no Head/Upperbody model variants. Download the current Standard pack from Quaternius before continuing."
        }
        Write-Host "CH7.8 updated base archive preflight: PASS ($($VariantEntries.Count) Head/Upperbody model entries)" -ForegroundColor Green
        foreach ($Entry in ($VariantEntries | Select-Object -First 12)) {
            Write-Host "  $($Entry.FullName)" -ForegroundColor DarkGray
        }
    }
    finally {
        $Zip.Dispose()
    }
}

function Install-Archive([string]$Archive, [string]$Destination) {
    Assert-UpdatedArchive $Archive
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Write-Host "CH7.8 overlaying current Universal Base Characters Standard pack:" -ForegroundColor Cyan
    Write-Host "  $Archive"
    Write-Host "to:" -ForegroundColor Cyan
    Write-Host "  $Destination"
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
}

function Invoke-VariantProbe([string]$Godot) {
    Write-Host ""
    Write-Host "[base_variant_probe]" -ForegroundColor Cyan
    & $Godot @(
        "--headless", "--path", $Root,
        "--script", $ProbeScript
    )
    return $LASTEXITCODE
}

$Godot = Resolve-Godot $GodotPath
Write-Host "Godot: $Godot"
Write-Host "CH7.8 base character asset root: $AssetRoot"

$ResolvedArchive = Find-StandardArchive $ArchivePath
if (-not [string]::IsNullOrWhiteSpace($ResolvedArchive)) {
    Install-Archive $ResolvedArchive $AssetRoot

    Write-Host ""
    Write-Host "[editor_import]" -ForegroundColor Cyan
    & $Godot @(
        "--headless", "--editor", "--quit",
        "--path", $Root
    )
    if ($LASTEXITCODE -ne 0) {
        throw "CH7.8 Base Characters editor import failed with exit code $LASTEXITCODE"
    }

    $ProbeExit = Invoke-VariantProbe $Godot
    if ($ProbeExit -ne 0) {
        throw "CH7.8 Base Characters variant probe failed after refresh with exit code $ProbeExit"
    }
    Write-Host ""
    Write-Host "CH7.8 Universal Base Characters refresh + variant probe: PASS" -ForegroundColor Green
    exit 0
}

$CurrentProbeExit = Invoke-VariantProbe $Godot
if ($CurrentProbeExit -eq 0) {
    Write-Host ""
    Write-Host "Installed Base Characters pack already contains a compatible Head variant." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "Installed Universal Base Characters pack is missing the compatible Head variant required by CH7.8C." -ForegroundColor Yellow
Write-Host "Quaternius added Head/Upperbody variants specifically for the Modular Character Outfits update." -ForegroundColor Yellow
Write-Host "Download the current free Standard archive:" -ForegroundColor Yellow
Write-Host "  $DownloadPage" -ForegroundColor Cyan
Write-Host ""
Write-Host "After download, run this same command again. The newest Standard ZIP in Downloads will be validated before extraction." -ForegroundColor Yellow
Write-Host "Optional explicit archive usage:" -ForegroundColor DarkGray
Write-Host '  .\REFRESH_CH7_8_QUATERNIUS_BASE_CHARACTERS.ps1 -GodotPath $Godot -ArchivePath "C:\Users\root\Downloads\Universal Base Characters[Standard].zip"' -ForegroundColor DarkGray
if ($OpenDownloadPage) {
    Start-Process $DownloadPage
}
exit 3
