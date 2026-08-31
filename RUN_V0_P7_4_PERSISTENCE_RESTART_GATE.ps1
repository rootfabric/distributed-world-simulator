[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GodotExe,
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArtifactRoot = Join-Path $Root "artifacts\runtime\v0-p7-4-persistence-restart"
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
    throw "P7_4_HEAD_MISMATCH actual=$Head expected=$ExpectedHead"
}
if (git -C $Root status --porcelain --untracked-files=no) { throw "P7.4 gate requires clean tracked checkout." }

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
        throw "P7.4 contract RED: $Name"
    }
    Assert-LogClean $Log
    if (-not (Select-String -Path $Log -SimpleMatch $Summary -Quiet)) {
        Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue
        throw "Missing PASS summary: $Summary"
    }
    Write-Host "[V0-P7.4] PASS $Name" -ForegroundColor Green
}

function Invoke-RestartPhase {
    param([string]$Phase)
    $Log = Join-Path $ArtifactRoot "p7-4-$Phase.log"
    $oldHome=$env:HOME; $oldData=$env:XDG_DATA_HOME; $oldConfig=$env:XDG_CONFIG_HOME; $oldCache=$env:XDG_CACHE_HOME; $oldAppData=$env:APPDATA; $oldLocal=$env:LOCALAPPDATA
    try {
        $env:HOME=$TestHome
        $env:XDG_DATA_HOME=(Join-Path $TestHome "data")
        $env:XDG_CONFIG_HOME=(Join-Path $TestHome "config")
        $env:XDG_CACHE_HOME=(Join-Path $TestHome "cache")
        $env:APPDATA=(Join-Path $TestHome "data")
        $env:LOCALAPPDATA=(Join-Path $TestHome "data")
        & $GodotExe --headless --path $Root --log-file $Log --script "res://tests/runtime/test_v0_p7_4_persistence_restart_composition.gd" -- "--phase=$Phase"
    } finally {
        $env:HOME=$oldHome; $env:XDG_DATA_HOME=$oldData; $env:XDG_CONFIG_HOME=$oldConfig; $env:XDG_CACHE_HOME=$oldCache; $env:APPDATA=$oldAppData; $env:LOCALAPPDATA=$oldLocal
    }
    if ($LASTEXITCODE -ne 0) { Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue; throw "P7.4 restart phase RED: $Phase" }
    Assert-LogClean $Log
    if (-not (Select-String -Path $Log -SimpleMatch "V0-P7.4 $Phase`: PASS" -Quiet)) {
        Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue
        throw "Missing P7.4 phase PASS: $Phase"
    }
    Write-Host "[V0-P7.4] PASS restart-$Phase" -ForegroundColor Green
}

$ImportLog = Join-Path $ArtifactRoot "import.log"
& $GodotExe --headless --editor --path $Root --log-file $ImportLog --import
if ($LASTEXITCODE -ne 0) { Get-Content $ImportLog -Tail 500; throw "P7.4 import failed" }
Assert-LogClean $ImportLog

Invoke-RestartPhase "seed"
Invoke-RestartPhase "recover-deliver"
Invoke-RestartPhase "recover-replay"
Invoke-Contract "p7-3-material-delivery" "res://tests/runtime/test_v0_p7_3_material_batch_to_item_graph.gd" "V0-P7.3 material batch to Item Graph: PASS (116 assertions, 0 failures)"
Invoke-Contract "p7-2-bubble" "res://tests/matter/product/test_v0_p7_2_lunar_matter_bubble.gd" "V0-P7.2 lunar Matter bubble: PASS (53 assertions, 0 failures)"
Invoke-Contract "p7-2-seam" "res://tests/runtime/test_v0_p7_2_lunar_surface_seam.gd" "V0-P7.2 lunar surface seam: PASS (50 assertions, 0 failures)"
Invoke-Contract "p7-1-authority" "res://tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd" "V0-P7.1 authority gate: PASS (83 assertions, 0 failures)"
Invoke-Contract "p7-1-tool-to-mw4" "res://tests/runtime/test_v0_p7_1_tool_to_mw4_adapter.gd" "V0-P7.1 Tool->MW4 integration: PASS (30 assertions, 0 failures)"
Invoke-Contract "p5-mining-tool" "res://tests/runtime/test_v0_p5_mining_tool_gate.gd" "V0-P5 mining tool gate: 36 assertions, 0 failures"
Invoke-Contract "p3-resource-domain" "res://tests/runtime/test_v0_p3_resource_mining_domain.gd" "V0-P3 resource/mining domain: 79 assertions, 0 failures"
Invoke-Contract "p3-aggregate-recovery" "res://tests/runtime/test_v0_p3_resource_mining_aggregate_recovery.gd" "V0-P3 aggregate resource recovery: 33 assertions, 0 failures"
Invoke-Contract "m6-recovery-contracts" "res://tests/runtime/test_m6_dedicated_recovery_contracts.gd" "M6 dedicated recovery contracts: 126 assertions, 0 failures"
Invoke-Contract "m6-recovery-processes" "res://tests/runtime/test_m6_dedicated_recovery_processes.gd" "M6 dedicated recovery processes: 128 assertions, 0 failures"
Invoke-Contract "mw4" "res://tests/matter/mutation/test_mw4_matter_mutations.gd" "MW4 matter mutations: PASS"
Invoke-Contract "mw5" "res://tests/matter/persistence/test_mw5_matter_persistence.gd" "MW5 matter persistence: PASS"
Invoke-Contract "mw6" "res://tests/matter/network/test_mw6_matter_network_replication.gd" "MW6 matter network authority: PASS"

if (git -C $Root status --porcelain --untracked-files=no) { git -C $Root status --short; throw "P7.4 gate changed tracked checkout." }
Write-Host "V0-P7.4 PERSISTENCE RESTART COMPOSITION GATE GREEN" -ForegroundColor Green
Write-Host "EXACT_HEAD=$Head"
Write-Host "GODOT=$Version"
