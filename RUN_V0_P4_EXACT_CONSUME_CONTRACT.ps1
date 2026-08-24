[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p4-exact-consume"
$ImportLog = Join-Path $ArtifactRoot "import.log"
$TestLog = Join-Path $ArtifactRoot "exact-consume.log"
$ExpectedSummaryPrefix = "V0-P4 exact-consume contract: PASS ("

if (-not (Test-Path -LiteralPath $GodotExe)) { throw "Godot executable not found: $GodotExe" }
if (-not (Test-Path -LiteralPath $ProjectFile)) { throw "Godot project file not found: $ProjectFile" }

$ActualHead = (& git -C $ProjectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualHead -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Unable to resolve exact V0-P4 HEAD."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $ActualHead.ToLowerInvariant() -ne $ExpectedHead.Trim().ToLowerInvariant()) {
    throw "V0-P4 exact-head mismatch. Expected $ExpectedHead, got $ActualHead"
}
if (git -C $ProjectRoot status --porcelain) {
    throw "V0-P4 focused gate requires a clean tracked checkout."
}

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
        throw "V0-P4 exact-consume gate mutated project.godot during $Stage."
    }
}

function Assert-LogClean {
    param([string]$Path, [string]$Stage)
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $Path -SimpleMatch $Pattern -Quiet) {
            Get-Content $Path -Tail 180 -ErrorAction SilentlyContinue
            throw "V0-P4 $Stage contains fatal parser/startup marker: $Pattern"
        }
    }
}

Write-Host "[V0-P4 exact-consume] Project: $ProjectRoot"
Write-Host "[V0-P4 exact-consume] HEAD:    $ActualHead"
Write-Host "[V0-P4 exact-consume] Godot:   $GodotExe"

& $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
if ($LASTEXITCODE -ne 0) {
    Get-Content $ImportLog -Tail 180 -ErrorAction SilentlyContinue
    throw "V0-P4 import failed."
}
Assert-LogClean -Path $ImportLog -Stage "import"
Assert-ProjectStable -Stage "import"

& $GodotExe --headless --path $ProjectRoot --log-file $TestLog --script res://tests/construction/test_v0_p4_real_resource_exact_consume_contract.gd
if ($LASTEXITCODE -ne 0) {
    Get-Content $TestLog -Tail 220 -ErrorAction SilentlyContinue
    throw "V0-P4 exact-consume contract is RED. This is expected before the P4.1 production repair, and must become GREEN on the implementation candidate."
}
Assert-LogClean -Path $TestLog -Stage "contract test"
Assert-ProjectStable -Stage "contract test"

if (-not (Select-String -Path $TestLog -SimpleMatch $ExpectedSummaryPrefix -Quiet)) {
    Get-Content $TestLog -Tail 220 -ErrorAction SilentlyContinue
    throw "V0-P4 exact-consume contract did not emit the required PASS summary."
}

if (git -C $ProjectRoot status --porcelain) {
    git -C $ProjectRoot status --short
    throw "V0-P4 exact-consume gate changed tracked checkout state."
}

Write-Host ""
Write-Host "V0-P4 exact-consume contract GREEN on exact HEAD $ActualHead" -ForegroundColor Green
