$ErrorActionPreference = "Stop"

$ExpectedBase = "6c4931f9c44db374b4eb3ab08b51fe1268dce569"
$PatchBranch = "origin/agent/v0-s1-mvp-tab-spawn-spectator"
$PatchRepoPath = "patches/v0-s1-mvp-tab-spawn-spectator.patch.gz"
$ExpectedPatchSha256 = "F9A3600C33339A0217786A0D234FBC10305C2CB1C468CE04BA9BD124C9C9043E"

$repoRoot = (git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "Not inside a Git repository."
}
Set-Location $repoRoot

$currentHead = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve current HEAD."
}
if ($currentHead -ne $ExpectedBase) {
    throw "Unexpected HEAD: $currentHead. Expected exact base: $ExpectedBase. No changes were applied."
}

Write-Host "Fetching patch branch..."
git fetch origin agent/v0-s1-mvp-tab-spawn-spectator
if ($LASTEXITCODE -ne 0) {
    throw "git fetch failed."
}

$localGz = Join-Path $repoRoot $PatchRepoPath
$localPatch = Join-Path ([System.IO.Path]::GetTempPath()) "v0-s1-mvp-tab-spawn-spectator.patch"

try {
    if (Test-Path $localGz) {
        Remove-Item -Force $localGz
    }
    if (Test-Path $localPatch) {
        Remove-Item -Force $localPatch
    }

    Write-Host "Restoring exact binary blob from Git..."
    git restore --source=$PatchBranch --worktree -- $PatchRepoPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $localGz)) {
        throw "Unable to restore $PatchRepoPath from $PatchBranch."
    }

    $inputStream = [System.IO.File]::OpenRead($localGz)
    try {
        $gzipStream = [System.IO.Compression.GZipStream]::new(
            $inputStream,
            [System.IO.Compression.CompressionMode]::Decompress
        )
        try {
            $outputStream = [System.IO.File]::Create($localPatch)
            try {
                $gzipStream.CopyTo($outputStream)
            }
            finally {
                $outputStream.Dispose()
            }
        }
        finally {
            $gzipStream.Dispose()
        }
    }
    finally {
        $inputStream.Dispose()
    }

    $actualPatchSha256 = (Get-FileHash $localPatch -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualPatchSha256 -ne $ExpectedPatchSha256) {
        throw "Patch SHA256 mismatch: $actualPatchSha256. Expected: $ExpectedPatchSha256. No changes were applied."
    }

    Write-Host "Patch SHA256 verified: $actualPatchSha256"
    Write-Host "Checking patch applicability..."
    git apply --check -- $localPatch
    if ($LASTEXITCODE -ne 0) {
        throw "git apply --check failed. No changes were applied."
    }

    Write-Host "Applying patch..."
    git apply -- $localPatch
    if ($LASTEXITCODE -ne 0) {
        throw "git apply failed."
    }

    Write-Host "Checking resulting diff..."
    git diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed after applying the patch."
    }

    Write-Host ""
    Write-Host "Patch applied successfully."
    git diff --stat
    git status --short
}
finally {
    if (Test-Path $localGz) {
        Remove-Item -Force $localGz
    }
    if (Test-Path $localPatch) {
        Remove-Item -Force $localPatch
    }
}
