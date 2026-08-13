param(
    [Parameter(Mandatory=$true)][string]$ProfileId,
    [string]$ArchivePath = "",
    [string]$GodotPath = "",
    [string]$SourceGlb = "",
    [switch]$OpenDownloadPage
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$ProfileDir = Join-Path $Root "config\characters\hand-assets"

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

function Find-ProfileArchive {
    param(
        [object]$ProfileObject,
        [string]$RequestedPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath) -and (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $SearchDirs = [System.Collections.Generic.List[string]]::new()
    $UserProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    foreach ($Dir in @(
        (Join-Path $UserProfile "Downloads"),
        (Join-Path $UserProfile "OneDrive\Downloads")
    )) {
        if ((Test-Path -LiteralPath $Dir -PathType Container) -and -not $SearchDirs.Contains($Dir)) {
            $SearchDirs.Add($Dir)
        }
    }

    $ExpectedArchive = [string]$ProfileObject.asset.expected_archive
    if (-not [string]::IsNullOrWhiteSpace($ExpectedArchive)) {
        foreach ($Dir in $SearchDirs) {
            $Exact = Join-Path $Dir $ExpectedArchive
            if (Test-Path -LiteralPath $Exact -PathType Leaf) {
                Write-Host "Auto-discovered expected archive: $Exact" -ForegroundColor Cyan
                return (Resolve-Path -LiteralPath $Exact).Path
            }
        }
    }

    $Tokens = @([string]$ProfileObject.profile_id -split '[-_]' | Where-Object { $_.Length -ge 4 })
    $Candidates = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($Dir in $SearchDirs) {
        Get-ChildItem -LiteralPath $Dir -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object {
            $NameLower = $_.Name.ToLowerInvariant()
            $Matched = $false
            foreach ($Token in $Tokens) {
                if ($NameLower.Contains($Token.ToLowerInvariant())) {
                    $Matched = $true
                    break
                }
            }
            if ($Matched) {
                $Candidates.Add($_)
            }
        }
    }

    $Unique = @($Candidates | Sort-Object FullName -Unique)
    if ($Unique.Count -eq 1) {
        Write-Host "Auto-discovered matching archive: $($Unique[0].FullName)" -ForegroundColor Cyan
        return $Unique[0].FullName
    }
    if ($Unique.Count -gt 1) {
        Write-Host "Multiple matching ZIP archives found:" -ForegroundColor Yellow
        $Unique | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor Yellow }
        throw "Pass -ArchivePath with the exact ZIP to import."
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        Write-Host "Requested archive was not found: $RequestedPath" -ForegroundColor Yellow
    }
    $Locations = if ($SearchDirs.Count -gt 0) { $SearchDirs -join "; " } else { "<no standard Downloads directory found>" }
    $DownloadPage = [string]$ProfileObject.asset.download_page_url
    if ([string]::IsNullOrWhiteSpace($DownloadPage)) {
        $DownloadPage = [string]$ProfileObject.license.source_url
    }
    if (-not [string]::IsNullOrWhiteSpace($DownloadPage)) {
        Write-Host "Asset download page: $DownloadPage" -ForegroundColor Cyan
        if ($OpenDownloadPage) {
            Write-Host "Opening the asset download page in the default browser..." -ForegroundColor Cyan
            Start-Process $DownloadPage
        } else {
            Write-Host "Tip: rerun with -OpenDownloadPage to open it automatically." -ForegroundColor DarkGray
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedArchive)) {
        Write-Host "Expected downloaded file: $ExpectedArchive" -ForegroundColor Cyan
    }
    throw "No ZIP archive for profile '$ProfileId' was found. The importer does not bypass interactive vendor download pages. Download the asset first, then rerun this command. Searched: $Locations"
}

$ArchivePath = Find-ProfileArchive -ProfileObject $Profile -RequestedPath $ArchivePath
if ([IO.Path]::GetExtension($ArchivePath).ToLowerInvariant() -ne ".zip") {
    throw "The generic importer currently supports ZIP archives. Extract other archive types manually, then run INSPECT_FPE_HAND_ASSET.ps1 on the GLB."
}

$ScenePath = [string]$Profile.asset.scene_path
if ([string]::IsNullOrWhiteSpace($ScenePath) -or -not $ScenePath.StartsWith("res://")) {
    throw "Profile $ProfileId has no valid res:// asset.scene_path."
}
$RelativeTarget = $ScenePath.Substring("res://".Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
$TargetPath = Join-Path $Root $RelativeTarget
$TargetDir = Split-Path -Parent $TargetPath

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

# Rebuild the dedicated profile payload so stale vendor files from a previous
# import cannot trigger unrelated importers (for example Blender .blend import
# in a headless environment). Keep only the selected GLB plus non-3D support
# files from the selected GLB directory, preserving texture subdirectories.
if (Test-Path -LiteralPath $TargetDir) {
    Remove-Item -LiteralPath $TargetDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

$ChosenDir = Split-Path -Parent $Chosen.FullName
$Excluded3DExtensions = @(".blend", ".fbx", ".obj", ".gltf", ".glb")
Get-ChildItem -LiteralPath $ChosenDir -File -Recurse | ForEach-Object {
    if ($_.FullName -eq $Chosen.FullName) {
        return
    }
    if ($Excluded3DExtensions -contains $_.Extension.ToLowerInvariant()) {
        return
    }
    $Relative = $_.FullName.Substring($ChosenDir.Length).TrimStart('\', '/')
    $Destination = Join-Path $TargetDir $Relative
    $DestinationDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $DestinationDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    }
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Force
}
Copy-Item -LiteralPath $Chosen.FullName -Destination $TargetPath -Force

Write-Host "Imported hand asset profile: $ProfileId" -ForegroundColor Green
Write-Host "Profile: $ProfileFile"
Write-Host "Archive: $ArchivePath"
Write-Host "Source GLB: $($Chosen.FullName)"
Write-Host "Stable Godot scene path: $ScenePath" -ForegroundColor Cyan
Write-Host "Staged payload intentionally excludes alternate .blend/.fbx/.obj sources." -ForegroundColor DarkGray

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
