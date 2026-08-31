[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GodotExe,
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArtifactRoot = Join-Path $Root "artifacts\runtime\v0-p7-2-lunar-matter-bubble"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Exact Godot executable not found: $GodotExe" }
$Version = (& $GodotExe --version 2>&1 | Select-Object -First 1).Trim()
if ($Version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH actual=$Version expected=$ExpectedGodot" }
$Head = (& git -C $Root rev-parse HEAD).Trim().ToLowerInvariant()
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $Head -ne $ExpectedHead.Trim().ToLowerInvariant()) {
    throw "P7_2_HEAD_MISMATCH actual=$Head expected=$ExpectedHead"
}
if (git -C $Root status --porcelain --untracked-files=no) { throw "P7.2 gate requires clean tracked checkout." }

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
        throw "P7.2 contract RED: $Name"
    }
    Assert-LogClean $Log
    if (-not (Select-String -Path $Log -SimpleMatch $Summary -Quiet)) {
        Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue
        throw "Missing PASS summary: $Summary"
    }
    Write-Host "[V0-P7.2] PASS $Name" -ForegroundColor Green
}

$ImportLog = Join-Path $ArtifactRoot "import.log"
& $GodotExe --headless --editor --path $Root --log-file $ImportLog --import
if ($LASTEXITCODE -ne 0) { Get-Content $ImportLog -Tail 500; throw "P7.2 import failed" }
Assert-LogClean $ImportLog

Invoke-Contract "p7-2-bubble" "res://tests/matter/product/test_v0_p7_2_lunar_matter_bubble.gd" "V0-P7.2 lunar Matter bubble: PASS"
Invoke-Contract "p7-2-seam" "res://tests/runtime/test_v0_p7_2_lunar_surface_seam.gd" "V0-P7.2 lunar surface seam: PASS"
Invoke-Contract "p7-1-authority" "res://tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd" "V0-P7.1 authority gate: PASS"
Invoke-Contract "p7-1-tool-to-mw4" "res://tests/runtime/test_v0_p7_1_tool_to_mw4_adapter.gd" "V0-P7.1 Tool->MW4 integration: PASS"
Invoke-Contract "mw4" "res://tests/matter/mutation/test_mw4_matter_mutations.gd" "MW4 matter mutations: PASS"
Invoke-Contract "mw5" "res://tests/matter/persistence/test_mw5_matter_persistence.gd" "MW5 matter persistence: PASS"
Invoke-Contract "mw6" "res://tests/matter/network/test_mw6_matter_network_replication.gd" "MW6 matter network authority: PASS"

if (git -C $Root status --porcelain --untracked-files=no) { git -C $Root status --short; throw "P7.2 gate changed tracked checkout." }
Write-Host "V0-P7.2 BOUNDED LUNAR MATTER BUBBLE GATE GREEN" -ForegroundColor Green
Write-Host "EXACT_HEAD=$Head"
Write-Host "GODOT=$Version"
