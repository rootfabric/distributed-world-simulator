[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p4-live-m4-transaction-port"
$ImportLog = Join-Path $ArtifactRoot "import.log"

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
    throw "V0-P4 live-M4 transaction gate requires a clean tracked checkout."
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
        throw "V0-P4 live-M4 transaction gate mutated project.godot during $Stage."
    }
}

function Assert-LogClean {
    param([string]$Path, [string]$Stage)
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $Path -SimpleMatch $Pattern -Quiet) {
            Get-Content $Path -Tail 220 -ErrorAction SilentlyContinue
            throw "V0-P4 $Stage contains fatal parser/startup marker: $Pattern"
        }
    }
}

function Invoke-GodotContract {
    param(
        [string]$Name,
        [string]$Script,
        [string]$Summary
    )
    $Log = Join-Path $ArtifactRoot ("$Name.log")
    & $GodotExe --headless --path $ProjectRoot --log-file $Log --script $Script
    if ($LASTEXITCODE -ne 0) {
        Get-Content $Log -Tail 260 -ErrorAction SilentlyContinue
        throw "V0-P4 contract RED: $Name"
    }
    Assert-LogClean -Path $Log -Stage $Name
    Assert-ProjectStable -Stage $Name
    if (-not [string]::IsNullOrWhiteSpace($Summary) -and -not (Select-String -Path $Log -SimpleMatch $Summary -Quiet)) {
        Get-Content $Log -Tail 260 -ErrorAction SilentlyContinue
        throw "V0-P4 contract did not emit required PASS summary: $Name / $Summary"
    }
    Write-Host "[V0-P4 live-M4] PASS: $Name" -ForegroundColor Green
}

Write-Host "[V0-P4 live-M4] Project: $ProjectRoot"
Write-Host "[V0-P4 live-M4] HEAD:    $ActualHead"
Write-Host "[V0-P4 live-M4] Godot:   $GodotExe"

& $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
if ($LASTEXITCODE -ne 0) {
    Get-Content $ImportLog -Tail 220 -ErrorAction SilentlyContinue
    throw "V0-P4 import failed."
}
Assert-LogClean -Path $ImportLog -Stage "import"
Assert-ProjectStable -Stage "import"

Invoke-GodotContract -Name "p4-3-live-m4" -Script "res://tests/construction/test_v0_p4_live_m4_transaction_port.gd" -Summary "V0-P4 live M4 transaction port: PASS (70 assertions)"
Invoke-GodotContract -Name "p4-2-allocator" -Script "res://tests/construction/test_v0_p4_deterministic_server_allocator.gd" -Summary "V0-P4 deterministic allocator: PASS (50 assertions)"
Invoke-GodotContract -Name "p4-1-exact-consume" -Script "res://tests/construction/test_v0_p4_real_resource_exact_consume_contract.gd" -Summary "V0-P4 exact-consume contract: PASS (12 assertions)"
Invoke-GodotContract -Name "m4-canonical" -Script "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd" -Summary "M4 canonical shared gameplay contracts: 26 assertions, 0 failures"
Invoke-GodotContract -Name "p3-mining" -Script "res://tests/runtime/test_v0_p3_resource_mining_domain.gd" -Summary "V0-P3 resource/mining domain: 79 assertions, 0 failures"
Invoke-GodotContract -Name "c3-build-plan" -Script "res://tests/construction/test_c3_build_plan_contracts.gd" -Summary "C3 BuildPlan contracts: PASS (80 assertions)"

if (git -C $ProjectRoot status --porcelain) {
    git -C $ProjectRoot status --short
    throw "V0-P4 live-M4 transaction gate changed tracked checkout state."
}

Write-Host ""
Write-Host "V0-P4 live M4 single-owner transaction port GREEN on exact HEAD $ActualHead" -ForegroundColor Green
