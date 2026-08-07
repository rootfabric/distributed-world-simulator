param(
    [string]$DownloadsPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DownloadsPath)) {
    $DownloadsPath = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads"
}
if (-not (Test-Path $DownloadsPath)) {
    throw "Downloads folder not found: $DownloadsPath"
}

$ZipFiles = Get-ChildItem -Path $DownloadsPath -File -Filter "*.zip"
$BaseZip = $ZipFiles |
    Where-Object { $_.Name -like "Universal Base Characters*Standard*.zip" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$AnimationZip = $ZipFiles |
    Where-Object { $_.Name -like "Universal Animation Library*Standard*.zip" -and $_.Name -notlike "*Library 2*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $BaseZip) {
    throw "Universal Base Characters[Standard].zip was not found in $DownloadsPath"
}
if ($null -eq $AnimationZip) {
    throw "Universal Animation Library[Standard].zip was not found in $DownloadsPath"
}

$ExternalRoot = Join-Path $Root "assets/external/quaternius"
$BaseTarget = Join-Path $ExternalRoot "base_characters"
$AnimationTarget = Join-Path $ExternalRoot "animation_library"

foreach ($Target in @($BaseTarget, $AnimationTarget)) {
    if (Test-Path $Target) {
        Remove-Item -Path $Target -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

Write-Host "Installing Quaternius CC0 assets..." -ForegroundColor Cyan
Write-Host "Base characters: $($BaseZip.FullName)"
Write-Host "Animations:      $($AnimationZip.FullName)"
Expand-Archive -LiteralPath $BaseZip.FullName -DestinationPath $BaseTarget -Force
Expand-Archive -LiteralPath $AnimationZip.FullName -DestinationPath $AnimationTarget -Force

$BaseScenes = Get-ChildItem -Path $BaseTarget -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @(".glb", ".gltf", ".fbx") }
$AnimationScenes = Get-ChildItem -Path $AnimationTarget -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in @(".glb", ".gltf", ".fbx") }

if ($BaseScenes.Count -lt 1) {
    throw "No GLB/glTF/FBX character scene was found after extraction."
}
if ($AnimationScenes.Count -lt 1) {
    throw "No GLB/glTF/FBX animation scene was found after extraction."
}

$ExcludePath = Join-Path $Root ".git/info/exclude"
if (Test-Path (Split-Path -Parent $ExcludePath)) {
    $Existing = if (Test-Path $ExcludePath) { Get-Content $ExcludePath } else { @() }
    $Entries = @(
        "/assets/external/quaternius/base_characters/",
        "/assets/external/quaternius/animation_library/"
    )
    foreach ($Entry in $Entries) {
        if ($Existing -notcontains $Entry) {
            Add-Content -Path $ExcludePath -Value $Entry -Encoding UTF8
        }
    }
}

Write-Host ""
Write-Host "Quaternius assets installed." -ForegroundColor Green
Write-Host "Character source files: $($BaseScenes.Count)"
Write-Host "Animation source files: $($AnimationScenes.Count)"
Write-Host "The assets stay local and are excluded through .git/info/exclude."
Write-Host "Run .\RUN_CH4_QUATERNIUS_CHARACTER_TESTS.ps1 next."
