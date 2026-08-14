$ErrorActionPreference = "Stop"

$ExpectedBase = "6c4931f9c44db374b4eb3ab08b51fe1268dce569"
$PatchBranch = "origin/agent/v0-s1-mvp-tab-spawn-spectator"
$ExpectedPatchSha256 = "F9A3600C33339A0217786A0D234FBC10305C2CB1C468CE04BA9BD124C9C9043E"
$PatchParts = @(
    "patches/v0-s1-mvp-tab-spawn-spectator.patch.part1",
    "patches/v0-s1-mvp-tab-spawn-spectator.patch.part2",
    "patches/v0-s1-mvp-tab-spawn-spectator.patch.part3",
    "patches/v0-s1-mvp-tab-spawn-spectator.patch.part4"
)

function Read-GitBlobBytes([string]$ObjectSpec) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "git"
    $startInfo.Arguments = "cat-file blob $ObjectSpec"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to start git cat-file for $ObjectSpec"
    }

    $memory = New-Object System.IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "git cat-file failed for ${ObjectSpec}: $stderr"
        }
        return $memory.ToArray()
    }
    finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

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

Write-Host "Fetching corrected text patch..."
git fetch origin agent/v0-s1-mvp-tab-spawn-spectator
if ($LASTEXITCODE -ne 0) {
    throw "git fetch failed."
}

$tempPatch = Join-Path ([System.IO.Path]::GetTempPath()) "v0-s1-mvp-tab-spawn-spectator.patch"
try {
    if (Test-Path $tempPatch) {
        Remove-Item -Force $tempPatch
    }

    $output = [System.IO.File]::Create($tempPatch)
    try {
        foreach ($partPath in $PatchParts) {
            $objectSpec = "${PatchBranch}:$partPath"
            Write-Host "Reading $partPath"
            $bytes = Read-GitBlobBytes $objectSpec
            $output.Write($bytes, 0, $bytes.Length)
        }
    }
    finally {
        $output.Dispose()
    }

    $actualPatchSha256 = (Get-FileHash $tempPatch -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualPatchSha256 -ne $ExpectedPatchSha256) {
        throw "Patch SHA256 mismatch: $actualPatchSha256. Expected: $ExpectedPatchSha256. No changes were applied."
    }

    Write-Host "Patch SHA256 verified: $actualPatchSha256"
    Write-Host "Checking patch applicability..."
    git apply --check -- $tempPatch
    if ($LASTEXITCODE -ne 0) {
        throw "git apply --check failed. No changes were applied."
    }

    Write-Host "Applying patch..."
    git apply -- $tempPatch
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
    if (Test-Path $tempPatch) {
        Remove-Item -Force $tempPatch
    }
}
