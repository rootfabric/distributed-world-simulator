[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p5-equipment-tools"
$ImportLog = Join-Path $ArtifactRoot "import.log"

if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}
if (-not (Test-Path -LiteralPath $ProjectFile)) {
    throw "Godot project file not found: $ProjectFile"
}

$ActualHead = (& git -C $ProjectRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $ActualHead -notmatch '^[0-9a-f]{40}$') {
    throw "Unable to resolve exact V0-P5 HEAD."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead)) {
    $NormalizedExpected = $ExpectedHead.Trim().ToLowerInvariant()
    if ($ActualHead -ne $NormalizedExpected) {
        throw "V0-P5 exact-head mismatch. Expected $NormalizedExpected, got $ActualHead"
    }
}
if (git -C $ProjectRoot status --porcelain) {
    throw "V0-P5 equipment/tools gate requires a clean tracked checkout."
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
        throw "V0-P5 gate mutated project.godot during $Stage."
    }
}

function Assert-LogClean {
    param([string]$Path, [string]$Stage)
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $Path -SimpleMatch $Pattern -Quiet) {
            Get-Content $Path -Tail 400 -ErrorAction SilentlyContinue
            throw "V0-P5 $Stage contains fatal parser/startup marker: $Pattern"
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
        throw "V0-P5 contract RED: $Name"
    }
    Assert-LogClean -Path $Log -Stage $Name
    Assert-ProjectStable -Stage $Name
    if (-not (Select-String -Path $Log -SimpleMatch $Summary -Quiet)) {
        Get-Content $Log -Tail 400 -ErrorAction SilentlyContinue
        throw "V0-P5 contract did not emit required PASS summary: $Name / $Summary"
    }
    Write-Host "[V0-P5] PASS: $Name" -ForegroundColor Green
}

Write-Host "[V0-P5] Project: $ProjectRoot"
Write-Host "[V0-P5] HEAD:    $ActualHead"
Write-Host "[V0-P5] Godot:   $GodotExe"

$HadBreakpointRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    & $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
    if ($LASTEXITCODE -ne 0) {
        Get-Content $ImportLog -Tail 400 -ErrorAction SilentlyContinue
        throw "V0-P5 import failed."
    }
    Assert-LogClean -Path $ImportLog -Stage "import"
    Assert-ProjectStable -Stage "import"

    Invoke-GodotContract -Name "p5-canonical-equipment" -Script "res://tests/runtime/test_v0_p5_canonical_equipment_relation.gd" -Summary "V0-P5 canonical equipment relation: 31 assertions, 0 failures"
    Invoke-GodotContract -Name "p5-live-mining-tool-gate" -Script "res://tests/runtime/test_v0_p5_mining_tool_gate.gd" -Summary "V0-P5 mining tool gate: 36 assertions, 0 failures"
    Invoke-GodotContract -Name "p5-two-client-reconnect" -Script "res://tests/runtime/test_v0_p5_two_client_replication_reconnect.gd" -Summary "V0-P5 two-client replication/reconnect: 47 assertions, 0 failures"

    Invoke-GodotContract -Name "p3-domain" -Script "res://tests/runtime/test_v0_p3_resource_mining_domain.gd" -Summary "V0-P3 resource/mining domain: 79 assertions, 0 failures"
    Invoke-GodotContract -Name "p3-aggregate-recovery" -Script "res://tests/runtime/test_v0_p3_resource_mining_aggregate_recovery.gd" -Summary "V0-P3 aggregate resource recovery: 33 assertions, 0 failures"
    Invoke-GodotContract -Name "p3-m6-resource-replay" -Script "res://tests/runtime/test_v0_p3_m6_resource_replay_outbox.gd" -Summary "V0-P3 M6 resource replay: 22 assertions, 0 failures"
    Invoke-GodotContract -Name "m4-canonical" -Script "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd" -Summary "M4 canonical shared gameplay contracts: 26 assertions, 0 failures"

    Invoke-GodotContract -Name "p4-exact-consume" -Script "res://tests/construction/test_v0_p4_real_resource_exact_consume_contract.gd" -Summary "V0-P4 exact-consume contract: PASS (12 assertions)"
    Invoke-GodotContract -Name "p4-allocator" -Script "res://tests/construction/test_v0_p4_deterministic_server_allocator.gd" -Summary "V0-P4 deterministic allocator: PASS (50 assertions)"
    Invoke-GodotContract -Name "p4-live-m4" -Script "res://tests/construction/test_v0_p4_live_m4_transaction_port.gd" -Summary "V0-P4 live M4 transaction port: PASS (70 assertions)"
    Invoke-GodotContract -Name "p4-authoritative-m4" -Script "res://tests/construction/test_v0_p4_live_m4_authoritative_transaction_port.gd" -Summary "V0-P4 authoritative live M4 transaction port: PASS (37 assertions)"
    Invoke-GodotContract -Name "p4-live-mvp" -Script "res://tests/runtime/test_v0_p4_live_mvp_composition_ordering.gd" -Summary "V0-P4 live MVP composition ordering: PASS (64 assertions)"

    Invoke-GodotContract -Name "p3-live-mining-reconnect" -Script "res://tests/runtime/test_v0_p3_live_resource_mining_convergence.gd" -Summary "V0-P3 live resource mining convergence: 43 assertions, 0 failures"
    Invoke-GodotContract -Name "p4-live-two-client-reconnect" -Script "res://tests/runtime/test_v0_p4_live_two_client_reconnect_convergence.gd" -Summary "V0-P4 live two-client reconnect convergence: 46 assertions, 0 failures"
}
finally {
    if ($HadBreakpointRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled
    }
    else {
        Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}

if (git -C $ProjectRoot status --porcelain) {
    git -C $ProjectRoot status --short
    throw "V0-P5 equipment/tools gate changed tracked checkout state."
}

Write-Host ""
Write-Host "V0-P5 EQUIPMENT/TOOLS FOCUSED GATE GREEN" -ForegroundColor Green
Write-Host "[V0-P5] EXACT HEAD GREEN: $ActualHead" -ForegroundColor Green
