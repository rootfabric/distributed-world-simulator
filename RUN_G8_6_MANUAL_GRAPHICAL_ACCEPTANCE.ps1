param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/g8-geomorphology"
$AutomatedTestedHead = "a9ca1f8b723e4edc5ebff40db26e41283d464597"
$Scene = "res://scenes/labs/procedural/g8_6_geomorphology_visual_lab.tscn"

function Get-GitText {
    param([string[]]$GitArgs)
    $output = & git -C $RootDir @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git command failed: git -C `"$RootDir`" $($GitArgs -join ' ')"
    }
    return (($output | Out-String).Trim())
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git executable not found in PATH."
}

$CurrentBranch = Get-GitText @("rev-parse", "--abbrev-ref", "HEAD")
$CurrentHead = Get-GitText @("rev-parse", "HEAD")
if ($CurrentBranch -ne $ExpectedBranch) {
    throw "G8.6 manual gate must run from '$ExpectedBranch'; current branch is '$CurrentBranch'."
}

$WorktreeStatus = Get-GitText @("status", "--porcelain=v1")
if (-not [string]::IsNullOrWhiteSpace($WorktreeStatus)) {
    throw "Working tree is not clean. Commit/stash local changes before the G8.6 manual gate.`n$WorktreeStatus"
}

& git -C $RootDir merge-base --is-ancestor $AutomatedTestedHead $CurrentHead
if ($LASTEXITCODE -ne 0) {
    throw "Automated-tested G8.6 head $AutomatedTestedHead is not an ancestor of current head $CurrentHead. Re-run automated acceptance before graphical acceptance."
}

# Post-acceptance control/manifest/validation metadata is allowed to move.
# The manual gate must fail closed only if executable G8.6 presentation/runtime
# or its focused acceptance harness changed after the automated-tested head.
$ExecutableGuardPaths = @(
    "scripts/labs/procedural/g8_6_geomorphology_visual_lab.gd",
    "scripts/labs/procedural/g8_6_geomorphology_visual_lab_fix2.gd",
    "scenes/labs/procedural/g8_6_geomorphology_visual_lab.tscn",
    "scripts/simulation/procedural/geomorphology",
    "tests/procedural/geomorphology/g8_6_geomorphology_visual_lab_acceptance.gd",
    "RUN_G8_6_GEOMORPHOLOGY_VISUAL_LAB_TESTS.ps1",
    "RUN_G8_6_AUTOMATED_ACCEPTANCE.ps1"
)
$ExecutableDrift = & git -C $RootDir diff --name-only "$AutomatedTestedHead..$CurrentHead" -- @ExecutableGuardPaths
if ($LASTEXITCODE -ne 0) {
    throw "Unable to check G8.6 executable drift."
}
$ExecutableDriftText = (($ExecutableDrift | Out-String).Trim())
if (-not [string]::IsNullOrWhiteSpace($ExecutableDriftText)) {
    throw "G8.6 executable presentation/runtime or focused acceptance harness changed after automated acceptance. Re-run automated acceptance first.`n$ExecutableDriftText"
}

$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) { $Candidates += $GodotPath }
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
$Candidates += @(
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)
$GodotExecutable = $Candidates | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf)
} | Select-Object -Unique | Select-Object -First 1
if ($null -eq $GodotExecutable) {
    throw "Godot executable not found. Pass -GodotPath or set GODOT_BIN."
}

Write-Host "=== G8.6 MANUAL GRAPHICAL ACCEPTANCE PREFLIGHT ==="
Write-Host "branch              : $CurrentBranch"
Write-Host "current head        : $CurrentHead"
Write-Host "automated tested    : $AutomatedTestedHead"
Write-Host "executable drift    : NONE"
Write-Host "working tree        : CLEAN"
Write-Host "Godot               : $GodotExecutable"
Write-Host ""

$FocusedRunner = Join-Path $RootDir "RUN_G8_6_GEOMORPHOLOGY_VISUAL_LAB_TESTS.ps1"
if (-not (Test-Path -LiteralPath $FocusedRunner -PathType Leaf)) {
    throw "Focused G8.6 runner missing: $FocusedRunner"
}

Write-Host "=== G8.6 FOCUSED AUTOMATED RECHECK ==="
& $FocusedRunner -GodotPath $GodotExecutable

Write-Host ""
Write-Host "=== G8.6 GRAPHICAL CHECKLIST ==="
Write-Host "1. Press G: SOURCE G3 <-> RESOLVED G8 must visibly change geometry; Truth hash must stay identical."
Write-Host "2. Press 1..7: resolved / total / valley / channel / bank / floodplain / erosion-deposition views must all be readable."
Write-Host "3. Hold W/S: Presentation LOD must move through mesh grids 33x17, 17x9, 9x5, 5x3; Canonical samples=561 and Truth hash must stay unchanged."
Write-Host "4. Press X: magenta PX/PZ seam must cross the resolved surface without a visible crack/discontinuity."
Write-Host "5. Press F: cyan canonical river overlay must align with channel/bank/floodplain shaping."
Write-Host "Controls: A/D yaw, Q/E pitch, Space auto-orbit, R reset."
Write-Host ""
Write-Host "Closing the window does NOT automatically accept G8.6. Record PASS only after observing all five checks."
Write-Host ""

$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotExecutable --path $RootDir $Scene
    if ($LASTEXITCODE -ne 0) {
        throw "G8.6 graphical lab exited with code $LASTEXITCODE."
    }
}
finally {
    if ($HadBreakpointRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled
    }
    else {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "G8.6 graphical lab closed. USER OBSERVATION REQUIRED: report PASS only if all five checklist items were visibly satisfied."
