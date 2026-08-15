param(
    [string]$SourceRepo = "C:\distributed-world-simulator\distributed-world-simulator",
    [string]$ValidationRepo = "C:\distributed-world-simulator\eco-validation-workspace",
    [ValidateSet("current", "accepted", "full", "p4.4", "p4.5", "p4.6", "p4.7", "p4.8")]
    [string]$Suite = "current",
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$Branch = "feature/eco-evolutionary-ecology"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}

# Windows PowerShell 5.1 can surface native stderr as NativeCommandError when
# $ErrorActionPreference is Stop, even if the native process exits with code 0.
# Git writes normal progress messages (for example "From https://...") to stderr.
# Run Git with Continue locally, capture both streams, and decide success strictly
# from the native exit code.
function Invoke-NativeGit([string[]]$Arguments) {
    $previousErrorActionPreference = $ErrorActionPreference
    $rawOutput = @()
    $exitCode = -1
    try {
        $ErrorActionPreference = "Continue"
        $rawOutput = @(& git @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $output = @($rawOutput | ForEach-Object { $_.ToString() })
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code ${exitCode}:`n$($output -join [Environment]::NewLine)"
    }
    return $output
}

function Invoke-Git([string]$Repo, [string[]]$Arguments) {
    $gitArguments = @("-C", $Repo) + $Arguments
    return @(Invoke-NativeGit -Arguments $gitArguments)
}

if (-not (Test-Path -LiteralPath $SourceRepo -PathType Container)) {
    throw "Source repository directory not found: $SourceRepo"
}
$sourceRoot = (Invoke-Git $SourceRepo @("rev-parse", "--show-toplevel") | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($sourceRoot)) {
    throw "SourceRepo is not a Git checkout: $SourceRepo"
}

Write-Host "=== ECO isolated validation workspace bootstrap ==="
Write-Host "source_repo=$sourceRoot"
Write-Host "validation_repo=$ValidationRepo"
Write-Host "branch=$Branch"
Write-Host "suite=$Suite"

$null = Invoke-Git $sourceRoot @("fetch", "origin", $Branch)
$originUrl = (Invoke-Git $sourceRoot @("remote", "get-url", "origin") | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($originUrl)) {
    throw "Unable to resolve origin URL from source repository"
}

if (-not (Test-Path -LiteralPath $ValidationRepo -PathType Container)) {
    $parent = Split-Path -Parent $ValidationRepo
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Write-Host "Creating dedicated validation clone..."
    $cloneOutput = Invoke-NativeGit -Arguments @(
        "clone",
        "--branch", $Branch,
        "--single-branch",
        $originUrl,
        $ValidationRepo
    )
    if ($cloneOutput.Count -gt 0) {
        $cloneOutput | ForEach-Object { Write-Host $_ }
    }
}

$validationRoot = (Invoke-Git $ValidationRepo @("rev-parse", "--show-toplevel") | Select-Object -First 1).Trim()
$validationOrigin = (Invoke-Git $validationRoot @("remote", "get-url", "origin") | Select-Object -First 1).Trim()
if ($validationOrigin -ne $originUrl) {
    throw "Validation workspace origin mismatch: expected=$originUrl actual=$validationOrigin"
}

$dirty = Invoke-Git $validationRoot @("status", "--porcelain")
if ($dirty.Count -gt 0) {
    throw "Validation workspace is dirty. Refusing destructive synchronization: $validationRoot"
}

$null = Invoke-Git $validationRoot @("fetch", "origin", $Branch)
$currentBranch = (Invoke-Git $validationRoot @("branch", "--show-current") | Select-Object -First 1).Trim()
if ($currentBranch -ne $Branch) {
    $null = Invoke-Git $validationRoot @("switch", $Branch)
}

$localHead = (Invoke-Git $validationRoot @("rev-parse", "HEAD") | Select-Object -First 1).Trim()
$remoteHead = (Invoke-Git $validationRoot @("rev-parse", "origin/$Branch") | Select-Object -First 1).Trim()
if ($localHead -ne $remoteHead) {
    Write-Host "Synchronizing validation workspace: $localHead -> $remoteHead"
    $null = Invoke-Git $validationRoot @("reset", "--hard", "origin/$Branch")
}

$finalHead = (Invoke-Git $validationRoot @("rev-parse", "HEAD") | Select-Object -First 1).Trim()
if ($finalHead -ne $remoteHead) {
    throw "Validation workspace failed to reach exact remote head: local=$finalHead remote=$remoteHead"
}

$workflow = Join-Path $validationRoot "RUN_ECO_TEST_WORKFLOW.ps1"
if (-not (Test-Path -LiteralPath $workflow -PathType Leaf)) {
    throw "Repository-local ECO workflow missing at exact remote head: $workflow"
}

Write-Host "validation_head=$finalHead"
Write-Host "Validation workspace synchronized exactly; source checkout was not modified."
Write-Host ""

& $workflow -Suite $Suite -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    throw "ECO repository-local workflow failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "ECO isolated validation workspace: PASS"
Write-Host "validation_head=$finalHead"
