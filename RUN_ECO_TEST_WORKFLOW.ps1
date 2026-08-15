param(
    [ValidateSet("current", "accepted", "full", "p4.4", "p4.5", "p4.6", "p4.7", "p4.8")]
    [string]$Suite = "current",
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$gitRoot = (& git -C $ScriptRoot rev-parse --show-toplevel 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) {
    throw "RUN_ECO_TEST_WORKFLOW.ps1 must live inside a Git checkout"
}

$scriptFull = [System.IO.Path]::GetFullPath($ScriptRoot).TrimEnd('\', '/')
$gitFull = [System.IO.Path]::GetFullPath($gitRoot).TrimEnd('\', '/')
if (-not [string]::Equals($scriptFull, $gitFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Workflow entrypoint must be at repository root: script_root=$scriptFull git_root=$gitFull"
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}

$definitions = [ordered]@{
    "p4.4" = @{ Path = "RUN_ECO_P4_4_TESTS.ps1"; NeedsGodot = $true }
    "p4.5" = @{ Path = "RUN_ECO_P4_5_TESTS.ps1"; NeedsGodot = $true }
    "p4.6" = @{ Path = "RUN_ECO_P4_6_TESTS.ps1"; NeedsGodot = $true }
    "p4.7" = @{ Path = "RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1"; NeedsGodot = $true }
    "p4.8" = @{ Path = "RUN_ECO_P4_8_PREACCEPTANCE_TESTS.ps1"; NeedsGodot = $false }
}

$suites = @{
    "current"  = @("p4.7", "p4.8")
    "accepted" = @("p4.4", "p4.5", "p4.6")
    "full"     = @("p4.4", "p4.5", "p4.6", "p4.7", "p4.8")
    "p4.4"     = @("p4.4")
    "p4.5"     = @("p4.5")
    "p4.6"     = @("p4.6")
    "p4.7"     = @("p4.7")
    "p4.8"     = @("p4.8")
}

$selected = @($suites[$Suite])
$needsGodot = $false
foreach ($stage in $selected) {
    if ([bool]$definitions[$stage].NeedsGodot) {
        $needsGodot = $true
        break
    }
}

if ($needsGodot -and -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$branch = (& git -C $gitFull branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current branch" }
$head = (& git -C $gitFull rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current HEAD" }
$status = & git -C $gitFull status --porcelain
if ($LASTEXITCODE -ne 0) { throw "Unable to read Git status" }

Write-Host "=== ECO repository-local test workflow ==="
Write-Host "repo_root=$gitFull"
Write-Host "branch=$branch"
Write-Host "head=$head"
Write-Host "suite=$Suite"
Write-Host "stages=$($selected -join ',')"
if ($needsGodot) { Write-Host "godot=$GodotPath" }
if ($status) {
    Write-Host "WARNING: working tree is not clean; tests still run against current files"
}

Push-Location $gitFull
try {
    foreach ($stage in $selected) {
        $entry = $definitions[$stage]
        $runner = Join-Path $gitFull ([string]$entry.Path)
        if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
            throw "Workflow stage runner missing: stage=$stage path=$runner"
        }

        Write-Host ""
        Write-Host "================================================================"
        Write-Host "ECO WORKFLOW STAGE $stage"
        Write-Host "runner=$($entry.Path)"
        Write-Host "================================================================"

        if ([bool]$entry.NeedsGodot) {
            & $runner -GodotPath $GodotPath
        }
        else {
            & $runner
        }

        if ($LASTEXITCODE -ne 0) {
            throw "ECO workflow stage failed: stage=$stage exit_code=$LASTEXITCODE"
        }
        Write-Host "ECO WORKFLOW STAGE $stage: PASS"
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "ECO repository-local test workflow: PASS"
Write-Host "suite=$Suite"
Write-Host "head=$head"
