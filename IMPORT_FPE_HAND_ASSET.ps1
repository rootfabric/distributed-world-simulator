param(
    [Parameter(Mandatory=$true)][string]$ProfileId,
    [Parameter(Mandatory=$true)][string]$ArchivePath,
    [string]$GodotPath = "",
    [string]$SourceGlb = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$ProfileDir = Join-Path $Root "config\characters\hand-assets"

if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "Archive not found: $ArchivePath"
}
if ([IO.Path]::GetExtension($ArchivePath).ToLowerInvariant() -ne ".zip") {
    throw "The generic importer currently supports ZIP archives. Extract other archive types manually, then run INSPECT_FPE_HAND_ASSET.ps1 on the GLB."
}

$ProfileFile = $null
$Profile = $null
Get-ChildItem -LiteralPath $ProfileDir -Filter *.json -File | ForEach-Object {
    $Candidate = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    if ([string]$Candidate.profile_id -eq $ProfileId) {
        $ProfileFile = $_.FullName
        $Profile = $Candidate
    }
}
if ($null -eq $Profile -or [string]::IsNullOrWhiteSpace($ProfileFile)) {
    throw "Hand asset profile id not found: $ProfileId"
}

$ScenePath = [string]$Profile.asset.scene_path
if ([string]::IsNullOrWhiteSpace($ScenePath) -or -not $ScenePath.StartsWith("res://")) {
    throw "Profile $ProfileId has no valid res:// asset.scene_path."
}
$RelativeTarget = $ScenePath.Substring("res://".Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
$TargetPath = Join-Path $Root $RelativeTarget
$TargetDir = Split-Path -Parent $TargetPath
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

$TempRoot = Join-Path $Root "artifacts\fpe_hand_import\$ProfileId"
if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $TempRoot -Force

$Glbs = @(Get-ChildItem -LiteralPath $TempRoot -Filter *.glb -File -Recurse)
if ($Glbs.Count -eq 0) {
    throw "No .glb file found inside $ArchivePath"
}
$Chosen = $null
if (-not [string]::IsNullOrWhiteSpace($SourceGlb)) {
    $Chosen = $Glbs | Where-Object { $_.Name -eq $SourceGlb -or $_.FullName.EndsWith($SourceGlb, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($null -eq $Chosen) {
        throw "Requested GLB '$SourceGlb' was not found. Available: $($Glbs.Name -join ', ')"
    }
} elseif ($Glbs.Count -eq 1) {
    $Chosen = $Glbs[0]
} else {
    Write-Host "Multiple GLB files found:" -ForegroundColor Yellow
    $Glbs | ForEach-Object { Write-Host "  $($_.FullName.Substring($TempRoot.Length + 1))" -ForegroundColor Yellow }
    throw "Rerun with -SourceGlb '<file name or relative suffix>' to select the hand model."
}

# Keep the extracted payload beside the canonical target so external textures or
# auxiliary files remain available. The selected GLB is additionally copied to
# the profile's stable scene_path, decoupling runtime profiles from vendor names.
Get-ChildItem -LiteralPath $TempRoot | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $TargetDir -Recurse -Force
}
Copy-Item -LiteralPath $Chosen.FullName -Destination $TargetPath -Force

Write-Host "Imported hand asset profile: $ProfileId" -ForegroundColor Green
Write-Host "Profile: $ProfileFile"
Write-Host "Source GLB: $($Chosen.FullName)"
Write-Host "Stable Godot scene path: $ScenePath" -ForegroundColor Cyan

$Inspector = Join-Path $Root "INSPECT_FPE_HAND_ASSET.ps1"
$InspectorArgs = @{
    Scene = $ScenePath
}
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
    $InspectorArgs.GodotPath = $GodotPath
}
& $Inspector @InspectorArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
