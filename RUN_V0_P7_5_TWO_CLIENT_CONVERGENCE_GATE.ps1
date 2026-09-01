[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GodotExe,
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArtifactRoot = Join-Path $Root "artifacts\runtime\v0-p7-5-two-client-convergence"
$TestHome = Join-Path $ArtifactRoot "user-home"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TestHome
New-Item -ItemType Directory -Force -Path (Join-Path $TestHome "data") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $TestHome "config") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $TestHome "cache") | Out-Null

if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Exact Godot executable not found: $GodotExe" }
$Version = (& $GodotExe --version 2>&1 | Select-Object -First 1).Trim()
if ($Version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH actual=$Version expected=$ExpectedGodot" }
$Head = (& git -C $Root rev-parse HEAD).Trim().ToLowerInvariant()
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $Head -ne $ExpectedHead.Trim().ToLowerInvariant()) {
    throw "P7_5_HEAD_MISMATCH actual=$Head expected=$ExpectedHead"
}
if (git -C $Root status --porcelain --untracked-files=no) { throw "P7.5 gate requires clean tracked checkout." }

function Assert-LogClean {
    param([string]$Path)
    foreach ($Pattern in @("SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to instantiate an autoload", "Failed to load script")) {
        if (Select-String -Path $Path -SimpleMatch $Pattern -Quiet) {
            Get-Content $Path -Tail 500 -ErrorAction SilentlyContinue
            throw "Fatal Godot marker: $Pattern"
        }
    }
}

function Invoke-Contract {
    param([string]$Name, [string]$Script, [string]$Summary)
    $Log = Join-Path $ArtifactRoot "$Name.log"
    & $GodotExe --headless --path $Root --log-file $Log --script $Script
    if ($LASTEXITCODE -ne 0) {
        Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue
        throw "P7.5 contract RED: $Name"
    }
    Assert-LogClean $Log
    if (-not (Select-String -Path $Log -SimpleMatch $Summary -Quiet)) {
        Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue
        throw "Missing PASS summary: $Summary"
    }
    Write-Host "[V0-P7.5] PASS $Name" -ForegroundColor Green
}

function Invoke-RestartPhase {
    param([string]$Phase)
    $Log = Join-Path $ArtifactRoot "p7-4-$Phase.log"
    $oldHome=$env:HOME
    $oldData=$env:XDG_DATA_HOME
    $oldConfig=$env:XDG_CONFIG_HOME
    $oldCache=$env:XDG_CACHE_HOME
    $oldAppData=$env:APPDATA
    $oldLocal=$env:LOCALAPPDATA
    try {
        $env:HOME=$TestHome
        $env:XDG_DATA_HOME=(Join-Path $TestHome "data")
        $env:XDG_CONFIG_HOME=(Join-Path $TestHome "config")
        $env:XDG_CACHE_HOME=(Join-Path $TestHome "cache")
        $env:APPDATA=(Join-Path $TestHome "data")
        $env:LOCALAPPDATA=(Join-Path $TestHome "data")
        & $GodotExe --headless --path $Root --log-file $Log --script "res://tests/runtime/test_v0_p7_4_persistence_restart_composition.gd" -- "--phase=$Phase"
    } finally {
        $env:HOME=$oldHome
        $env:XDG_DATA_HOME=$oldData
        $env:XDG_CONFIG_HOME=$oldConfig
        $env:XDG_CACHE_HOME=$oldCache
        $env:APPDATA=$oldAppData
        $env:LOCALAPPDATA=$oldLocal
    }
    if ($LASTEXITCODE -ne 0) {
        Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue
        throw "P7.4 restart phase RED inside P7.5 gate: $Phase"
    }
    Assert-LogClean $Log
    $ExpectedPhaseSummary = "V0-P7.4 $($Phase): PASS"
    if (-not (Select-String -Path $Log -SimpleMatch $ExpectedPhaseSummary -Quiet)) {
        Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue
        throw "Missing P7.4 phase PASS: $Phase"
    }
    Write-Host "[V0-P7.5] PASS p7-4-$Phase" -ForegroundColor Green
}

$ImportLog = Join-Path $ArtifactRoot "import.log"
& $GodotExe --headless --editor --path $Root --log-file $ImportLog --import
if ($LASTEXITCODE -ne 0) {
    Get-Content $ImportLog -Tail 500 -ErrorAction SilentlyContinue
    throw "P7.5 import failed"
}
Assert-LogClean $ImportLog

Invoke-Contract "p7-5-two-client" "res://tests/runtime/test_v0_p7_5_two_client_convergence.gd" "V0-P7.5 two-client convergence: PASS ("
Invoke-Contract "m7-aggregate-replica" "res://tests/runtime/test_m7_item_graph_replica_aggregate_compatibility.gd" "M7 aggregate replica compatibility: PASS ("
Invoke-RestartPhase "seed"
Invoke-RestartPhase "recover-deliver"
Invoke-RestartPhase "recover-replay"
Invoke-Contract "p7-3-material-delivery" "res://tests/runtime/test_v0_p7_3_material_batch_to_item_graph.gd" "V0-P7.3 material batch to Item Graph: PASS (116 assertions, 0 failures)"
Invoke-Contract "p7-2-bubble" "res://tests/matter/product/test_v0_p7_2_lunar_matter_bubble.gd" "V0-P7.2 lunar Matter bubble: PASS (53 assertions, 0 failures)"
Invoke-Contract "p7-2-seam" "res://tests/runtime/test_v0_p7_2_lunar_surface_seam.gd" "V0-P7.2 lunar surface seam: PASS (50 assertions, 0 failures)"
Invoke-Contract "p7-1-authority" "res://tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd" "V0-P7.1 authority gate: PASS (83 assertions, 0 failures)"
Invoke-Contract "p7-1-tool-to-mw4" "res://tests/runtime/test_v0_p7_1_tool_to_mw4_adapter.gd" "V0-P7.1 Tool->MW4 integration: PASS (30 assertions, 0 failures)"
Invoke-Contract "p5-two-client" "res://tests/runtime/test_v0_p5_two_client_replication_reconnect.gd" "V0-P5 two-client replication/reconnect:"
Invoke-Contract "p5-mining-tool" "res://tests/runtime/test_v0_p5_mining_tool_gate.gd" "V0-P5 mining tool gate: 36 assertions, 0 failures"
Invoke-Contract "mw6" "res://tests/matter/network/test_mw6_matter_network_replication.gd" "MW6 matter network authority: PASS"
Invoke-Contract "mw7" "res://tests/matter/interest/test_mw7_matter_interest_replication.gd" "MW7 matter interest replication: PASS"
Invoke-Contract "rl2" "res://tests/representation/test_rl2_matter_multiresolution_meshing.gd" "RL2 Matter multiresolution meshing: PASS"
Invoke-Contract "rl3" "res://tests/representation/test_rl3_representation_aware_network_streaming.gd" "RL3 representation-aware network streaming: PASS"

if (git -C $Root status --porcelain --untracked-files=no) {
    git -C $Root status --short
    throw "P7.5 gate changed tracked checkout."
}
Write-Host "V0-P7.5 TWO CLIENT CONVERGENCE GATE GREEN" -ForegroundColor Green
Write-Host "EXACT_HEAD=$Head"
Write-Host "GODOT=$Version"
