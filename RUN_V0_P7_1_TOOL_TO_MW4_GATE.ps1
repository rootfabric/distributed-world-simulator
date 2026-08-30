[CmdletBinding()]
param(
    [string]$GodotExe = "C:\\Godot\\godot\\bin\\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\\runtime\\v0-p7-1-tool-to-mw4"
$ImportLog = Join-Path $ArtifactRoot "import.log"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"

if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Exact Godot executable not found: $GodotExe" }
if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) { throw "Godot project file not found: $ProjectFile" }
$Version = (& $GodotExe --version 2>&1 | Select-Object -First 1).Trim()
if ($Version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH: actual=$Version expected=$ExpectedGodot" }
$ActualHead = (& git -C $ProjectRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $ActualHead -notmatch "^[0-9a-f]{40}$") { throw "Unable to resolve exact V0-P7.1 HEAD." }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead)) {
    $NormalizedExpected = $ExpectedHead.Trim().ToLowerInvariant()
    if ($ActualHead -ne $NormalizedExpected) { throw "V0-P7.1 exact-head mismatch. Expected $NormalizedExpected, got $ActualHead" }
}
if (git -C $ProjectRoot status --porcelain) { throw "V0-P7.1 gate requires a clean tracked checkout." }
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
$ProjectHashBefore = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
$FatalPatterns = @("SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to instantiate an autoload", "Resource file not found: res://", "Failed to load script")

function Assert-ProjectStable {
    param([string]$Stage)
    $After = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
    if ($After -ne $ProjectHashBefore) { & git -C $ProjectRoot diff -- project.godot; throw "V0-P7.1 gate mutated project.godot during $Stage." }
}

function Assert-LogClean {
    param([string]$Path, [string]$Stage)
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $Path -SimpleMatch $Pattern -Quiet) { Get-Content $Path -Tail 500 -ErrorAction SilentlyContinue; throw "V0-P7.1 $Stage contains fatal marker: $Pattern" }
    }
}

function Invoke-GodotContract {
    param([string]$Name, [string]$Script, [string]$Summary)
    $Log = Join-Path $ArtifactRoot ("$Name.log")
    & $GodotExe --headless --path $ProjectRoot --log-file $Log --script $Script
    if ($LASTEXITCODE -ne 0) { Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue; throw "V0-P7.1 contract RED: $Name" }
    Assert-LogClean -Path $Log -Stage $Name
    Assert-ProjectStable -Stage $Name
    if (-not (Select-String -Path $Log -SimpleMatch $Summary -Quiet)) { Get-Content $Log -Tail 500 -ErrorAction SilentlyContinue; throw "V0-P7.1 contract missing PASS summary: $Name / $Summary" }
    Write-Host "[V0-P7.1] PASS: $Name" -ForegroundColor Green
}

Write-Host "[V0-P7.1] Project: $ProjectRoot"
Write-Host "[V0-P7.1] HEAD:    $ActualHead"
Write-Host "[V0-P7.1] Godot:   $Version"
$HadBreakpointRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
    if ($LASTEXITCODE -ne 0) { Get-Content $ImportLog -Tail 500 -ErrorAction SilentlyContinue; throw "V0-P7.1 import failed." }
    Assert-LogClean -Path $ImportLog -Stage "import"
    Assert-ProjectStable -Stage "import"
    Invoke-GodotContract -Name "p7-1-authority-gate" -Script "res://tests/runtime/test_v0_p7_1_matter_command_authority_gate.gd" -Summary "V0-P7.1 authority gate: PASS"
    Invoke-GodotContract -Name "p7-1-real-tool-to-mw4" -Script "res://tests/runtime/test_v0_p7_1_tool_to_mw4_adapter.gd" -Summary "V0-P7.1 Tool->MW4 integration: PASS"
    Invoke-GodotContract -Name "p5-live-mining-tool-regression" -Script "res://tests/runtime/test_v0_p5_mining_tool_gate.gd" -Summary "V0-P5 mining tool gate: 36 assertions, 0 failures"
    Invoke-GodotContract -Name "mw6-authority-replication-regression" -Script "res://tests/matter/network/test_mw6_matter_network_replication.gd" -Summary "MW6 matter network authority: PASS"
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
if (git -C $ProjectRoot status --porcelain) { git -C $ProjectRoot status --short; throw "V0-P7.1 gate changed tracked checkout state." }
Write-Host ""
Write-Host "V0-P7.1 TOOL -> EXISTING MW4 FOCUSED GATE GREEN" -ForegroundColor Green
Write-Host "[V0-P7.1] EXACT HEAD GREEN: $ActualHead" -ForegroundColor Green
