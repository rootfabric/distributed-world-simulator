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

function Invoke-Git([string]$Repo, [string[]]$Arguments) {
    $output = & git -C $Repo @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git -C `"$Repo`" $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
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
    $cloneOutput = & git clone --branch $Branch --single-branch $originUrl $ValidationRepo 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create validation clone:`n$($cloneOutput -join [Environment]::NewLine)"
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
