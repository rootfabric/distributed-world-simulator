[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p3-resource-mining-domain"
$ImportLog = Join-Path $ArtifactRoot "import.log"
$PrepLog = Join-Path $ArtifactRoot "preparation.log"
$DomainLog = Join-Path $ArtifactRoot "domain.log"
$AggregateLog = Join-Path $ArtifactRoot "aggregate-recovery.log"

if (-not (Test-Path -LiteralPath $GodotExe)) { throw "Godot executable not found: $GodotExe" }
if (-not (Test-Path -LiteralPath $ProjectFile)) { throw "Godot project file not found: $ProjectFile" }

$ActualHead = (& git -C $ProjectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualHead -notmatch '^[0-9a-fA-F]{40}$') { throw "Unable to resolve exact V0-P3 domain HEAD." }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $ActualHead.ToLowerInvariant() -ne $ExpectedHead.Trim().ToLowerInvariant()) {
    throw "V0-P3 domain exact-head mismatch. Expected $ExpectedHead, got $ActualHead"
}
if (git -C $ProjectRoot status --porcelain) { throw "V0-P3 domain gate requires a clean tracked checkout." }

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
$ProjectHashBefore = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
$FatalPatterns = @(
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "Failed to instantiate an autoload",
    "Resource file not found: res://",
    "Failed to load script"
)

function Assert-ProjectStable {
    param([string]$Stage)
    $After = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
    if ($After -ne $ProjectHashBefore) {
        & git -C $ProjectRoot diff -- project.godot
        throw "V0-P3 domain gate mutated project.godot during $Stage."
    }
}

function Assert-LogClean {
    param([string]$Path, [string]$Stage)
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $Path -SimpleMatch $Pattern -Quiet) {
            Get-Content $Path -Tail 260 -ErrorAction SilentlyContinue
            throw "V0-P3 domain $Stage contains fatal marker: $Pattern"
        }
    }
}

function Invoke-GodotTest {
    param([string]$Script, [string]$Log, [string]$RequiredMarker)
    & $GodotExe --headless --path $ProjectRoot --log-file $Log --script $Script
    if ($LASTEXITCODE -ne 0) {
        Get-Content $Log -Tail 300 -ErrorAction SilentlyContinue
        throw "V0-P3 domain test failed: $Script"
    }
    Assert-LogClean -Path $Log -Stage $Script
    Assert-ProjectStable -Stage $Script
    if (-not (Select-String -Path $Log -SimpleMatch $RequiredMarker -Quiet)) {
        Get-Content $Log -Tail 300 -ErrorAction SilentlyContinue
        throw "V0-P3 domain test did not emit required marker: $RequiredMarker"
    }
    if (-not (Select-String -Path $Log -SimpleMatch "0 failures" -Quiet)) {
        Get-Content $Log -Tail 300 -ErrorAction SilentlyContinue
        throw "V0-P3 domain test did not finish with zero failures: $Script"
    }
}

Write-Host "[V0-P3 domain] Project: $ProjectRoot"
Write-Host "[V0-P3 domain] HEAD:    $ActualHead"
Write-Host "[V0-P3 domain] Godot:   $GodotExe"

& $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
if ($LASTEXITCODE -ne 0) {
    Get-Content $ImportLog -Tail 260 -ErrorAction SilentlyContinue
    throw "V0-P3 domain import failed."
}
Assert-LogClean -Path $ImportLog -Stage "import"
Assert-ProjectStable -Stage "import"

Invoke-GodotTest -Script "res://tests/runtime/test_v0_p3_resource_mining_preparation.gd" -Log $PrepLog -RequiredMarker "V0-P3 resource/mining preparation:"
Invoke-GodotTest -Script "res://tests/runtime/test_v0_p3_resource_mining_domain.gd" -Log $DomainLog -RequiredMarker "V0-P3 resource/mining domain:"
Invoke-GodotTest -Script "res://tests/runtime/test_v0_p3_resource_mining_aggregate_recovery.gd" -Log $AggregateLog -RequiredMarker "V0-P3 aggregate resource recovery:"

if (git -C $ProjectRoot status --porcelain) {
    git -C $ProjectRoot status --short
    throw "V0-P3 domain gate changed tracked checkout state."
}

Write-Host ""
Write-Host "V0-P3 RESOURCE/MINING DOMAIN + AGGREGATE RECOVERY GREEN" -ForegroundColor Green
Write-Host "[V0-P3 domain] EXACT HEAD GREEN: $ActualHead" -ForegroundColor Green
