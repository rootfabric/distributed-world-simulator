param(
    [string]$GodotPath = "",
    [string]$ArchivePath = "",
    [switch]$OpenDownloadPage
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$DownloadPage = "https://quaternius.itch.io/universal-base-characters/purchase"
$MeshProbe = "res://tests/characters/probe_ch7_8_quaternius_fullbody_mesh_structure.gd"

function Resolve-Godot([string]$Requested) {
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) { $Candidates += $Requested }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
    $Candidates += "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Resolve-Path $Candidate).Path
        }
    }
    throw "Godot 4.7.1 double was not found. Pass -GodotPath or set GODOT_BIN."
}

function Find-Archive([string]$Requested) {
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if (-not (Test-Path -LiteralPath $Requested -PathType Leaf)) { throw "ArchivePath does not exist: $Requested" }
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    $Downloads = Join-Path $HOME "Downloads"
    if (-not (Test-Path $Downloads -PathType Container)) { return "" }
    $Match = Get-ChildItem -LiteralPath $Downloads -File -Filter "*.zip" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)universal.*base.*characters' -and $_.Name -match '(?i)standard' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    return $(if ($null -ne $Match) { $Match.FullName } else { "" })
}

function Get-TrueVariantEntries([string]$Archive) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        return @($Zip.Entries | Where-Object {
            $_.Name -match '(?i)(^|[_\-.])(head|upperbody)([_\-.]|$)' -and
            $_.Name -match '(?i)\.(gltf|glb|fbx)$' -and
            $_.FullName -notmatch '(?i)/Hairstyles/'
        } | ForEach-Object { $_.FullName })
    }
    finally { $Zip.Dispose() }
}

$Godot = Resolve-Godot $GodotPath
$Archive = Find-Archive $ArchivePath
Write-Host "Godot: $Godot"

if (-not [string]::IsNullOrWhiteSpace($Archive)) {
    $Variants = @(Get-TrueVariantEntries $Archive)
    if ($Variants.Count -gt 0) {
        Write-Host "CH7.8 base archive: true exported Head/Upperbody variants=$($Variants.Count)" -ForegroundColor Green
        foreach ($Entry in ($Variants | Select-Object -First 12)) { Write-Host "  $Entry" }
    }
    else {
        Write-Host "CH7.8 base archive: NO standalone Head/Upperbody character exports" -ForegroundColor Yellow
        Write-Host "  $Archive"
        Write-Host "Previous preflight was a false positive: 'Rigged to Head Bone' is a hairstyle directory, not a Head character variant." -ForegroundColor Yellow
    }
}
else {
    Write-Host "CH7.8 base archive: no Standard ZIP found in Downloads" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "The current CH7.8 path no longer asks you to re-download the same Standard archive." -ForegroundColor Cyan
Write-Host "Run the FullBody structure probe instead:" -ForegroundColor Cyan
Write-Host "  & `$Godot --headless --path . --script $MeshProbe"
Write-Host ""
Write-Host "Official page, for reference only: $DownloadPage" -ForegroundColor DarkGray
if ($OpenDownloadPage) {
    Write-Host "OpenDownloadPage is intentionally non-operative in this diagnostic revision; the current Standard ZIP has already been inspected." -ForegroundColor DarkGray
}
exit 4
