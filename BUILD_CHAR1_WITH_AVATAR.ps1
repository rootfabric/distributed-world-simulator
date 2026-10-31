[CmdletBinding()]
param(
    [string] $GodotConsole = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe',
    [string] $AssetSource = '',
    [string] $OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$head = (& git -C $repo rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $head.Length -ne 40) {
    throw 'CHAR1_GIT_HEAD_NOT_RESOLVED'
}
$tree = (& git -C $repo rev-parse 'HEAD^{tree}' | Out-String).Trim()
$sourceTree = (& git -C $repo status --porcelain --untracked-files=no | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($sourceTree)) {
    throw 'CHAR1_TRACKED_WORKTREE_DIRTY: commit or restore tracked changes first'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repo 'artifacts\char1-with-avatar'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$destination = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path (
    'CHAR1_REALISTIC_WITH_AVATAR_{0}_Windows.zip' -f $head.Substring(0,8)
)
if (Test-Path -LiteralPath $destination) {
    throw ('CHAR1_RELEASE_EXISTS: {0} (do not overwrite a previous release)' -f $destination)
}
$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    throw 'CHAR1_PYTHON_NOT_FOUND: install Python 3.10+ or use Windows GitHub Actions'
}
$argsList = @(
    'tools/char1/build_bundled_windows_avatar.py',
    '--repo', $repo,
    '--expected-head', $head,
    '--godot-console', $GodotConsole,
    '--output', $destination
)
if (-not [string]::IsNullOrWhiteSpace($AssetSource)) {
    $argsList += @('--assets-root', $AssetSource)
}
$log = Join-Path $OutputDirectory ('char1-bundle-{0}.log' -f $head.Substring(0,8))
Write-Host ('Building CHAR1 standalone preview with real Quaternius and bundled Godot: {0}' -f $head) -ForegroundColor Cyan
$previousErrorActionPreference = $ErrorActionPreference
$nativePreference = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
$nativeOld = if ($null -ne $nativePreference) { $nativePreference.Value } else { $null }
$exitCode = 1
try {
    # PS 5.1 treats benign native stderr as NativeCommandError.
    $ErrorActionPreference = 'Continue'
    if ($null -ne $nativePreference) {
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
    }
    & $python.Source @argsList 2>&1 | Tee-Object -FilePath $log
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
    if ($null -ne $nativePreference) {
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $nativeOld
    }
}
if ($null -eq $exitCode -or $exitCode -ne 0) {
    throw ('CHAR1_WITH_AVATAR_BUILD_FAILED: ExitCode={0}, log={1}' -f $exitCode,$log)
}
if (-not (Test-Path -LiteralPath $destination)) {
    throw 'CHAR1_WITH_AVATAR_ZIP_NOT_CREATED'
}
$hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host 'CHAR1 WITH REAL AVATAR: BUILD PASS' -ForegroundColor Green
Write-Host ('HEAD: {0}' -f $head)
Write-Host ('TREE: {0}' -f $tree)
Write-Host ('ZIP: {0}' -f $destination)
Write-Host ('ZIP SHA256: {0}' -f $hash)
Write-Host 'Extract ZIP to a writable folder and launch START_CHAR1.cmd.'
