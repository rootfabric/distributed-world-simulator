[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p4-live-two-client-reconnect"
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
    throw "V0-P4 live reconnect gate requires a clean tracked checkout."
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
        throw "V0-P4 live reconnect gate mutated project.godot during $Stage."
    }
}

function Assert-LogClean {
    param([string]$Path, [string]$Stage)
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $Path -SimpleMatch $Pattern -Quiet) {
            Get-Content $Path -Tail 400 -ErrorAction SilentlyContinue
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
        Get-Content $Log -Tail 400 -ErrorAction SilentlyContinue
        throw "V0-P4 contract RED: $Name"
    }
    Assert-LogClean -Path $Log -Stage $Name
    Assert-ProjectStable -Stage $Name
    if (-not (Select-String -Path $Log -SimpleMatch $Summary -Quiet)) {
        Get-Content $Log -Tail 400 -ErrorAction SilentlyContinue
        throw "V0-P4 contract did not emit required PASS summary: $Name / $Summary"
    }
    Write-Host "[V0-P4 reconnect] PASS: $Name" -ForegroundColor Green
}

Write-Host "[V0-P4 reconnect] Project: $ProjectRoot"
Write-Host "[V0-P4 reconnect] HEAD:    $ActualHead"
Write-Host "[V0-P4 reconnect] Godot:   $GodotExe"

& $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
if ($LASTEXITCODE -ne 0) {
    Get-Content $ImportLog -Tail 400 -ErrorAction SilentlyContinue
    throw "V0-P4 import failed."
}
Assert-LogClean -Path $ImportLog -Stage "import"
Assert-ProjectStable -Stage "import"

Invoke-GodotContract -Name "p4-6-two-client-reconnect" -Script "res://tests/runtime/test_v0_p4_live_two_client_reconnect_convergence.gd" -Summary "V0-P4 live two-client reconnect convergence: 46 assertions, 0 failures"
Invoke-GodotContract -Name "p4-5-post-commit-publication" -Script "res://tests/runtime/test_v0_p4_post_commit_publication_fallback.gd" -Summary "V0-P4 post-commit publication/fallback: PASS (54 assertions)"
Invoke-GodotContract -Name "p4-4-live-mvp-composition" -Script "res://tests/runtime/test_v0_p4_live_mvp_composition_ordering.gd" -Summary "V0-P4 live MVP composition ordering: PASS (62 assertions)"
Invoke-GodotContract -Name "p4-3-live-m4" -Script "res://tests/construction/test_v0_p4_live_m4_transaction_port.gd" -Summary "V0-P4 live M4 transaction port: PASS (70 assertions)"
Invoke-GodotContract -Name "p4-3-authoritative-m0" -Script "res://tests/construction/test_v0_p4_live_m4_authoritative_transaction_port.gd" -Summary "V0-P4 authoritative live M4 transaction port: PASS (37 assertions)"
Invoke-GodotContract -Name "p4-2-allocator" -Script "res://tests/construction/test_v0_p4_deterministic_server_allocator.gd" -Summary "V0-P4 deterministic allocator: PASS (50 assertions)"
Invoke-GodotContract -Name "p4-1-exact-consume" -Script "res://tests/construction/test_v0_p4_real_resource_exact_consume_contract.gd" -Summary "V0-P4 exact-consume contract: PASS (12 assertions)"
Invoke-GodotContract -Name "p3-live-mining-reconnect" -Script "res://tests/runtime/test_v0_p3_live_resource_mining_convergence.gd" -Summary "V0-P3 live resource mining convergence: 43 assertions, 0 failures"
Invoke-GodotContract -Name "m4-canonical" -Script "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd" -Summary "M4 canonical shared gameplay contracts: 26 assertions, 0 failures"
Invoke-GodotContract -Name "mvp-m3-construction-bridge" -Script "res://tests/runtime/test_mvp_m3_construction_replication_bridge.gd" -Summary "MVP M3 construction replication bridge: PASS (25 assertions)"
Invoke-GodotContract -Name "v0-c1-client-adapter" -Script "res://tests/runtime/test_v0_c1_mvp_outpost_client_adapter.gd" -Summary "V0-C1 MVP outpost client adapter: PASS (12 assertions)"

if (git -C $ProjectRoot status --porcelain) {
    git -C $ProjectRoot status --short
    throw "V0-P4 live reconnect gate changed tracked checkout state."
}

Write-Host ""
Write-Host "V0-P4 live two-client/reconnect convergence GREEN on exact HEAD $ActualHead" -ForegroundColor Green
