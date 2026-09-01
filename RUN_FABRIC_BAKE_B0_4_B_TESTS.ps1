param(
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$ExpectedHead = ""
)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "research/fabric-bake0-4-dynamic-rom-r1"
$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
$head = (& git -C $RootDir rev-parse HEAD).Trim()
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead)) {
    if ($head -ne $ExpectedHead) { throw "WRONG_HEAD: expected $ExpectedHead actual $head" }
}
elseif ($currentBranch -ne $ExpectedBranch) {
    throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch"
}
$trackedStatus = (& git -C $RootDir status --short --untracked-files=no)
if (-not [string]::IsNullOrWhiteSpace(($trackedStatus -join ""))) { throw "DIRTY_TRACKED_WORKTREE" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$actualVersion = ((& $GodotPath --version) | Select-Object -First 1).Trim()
if ($actualVersion -ne $ExpectedVersion) { throw "Unexpected Godot version: $actualVersion expected $ExpectedVersion" }

Write-Host "FABRIC-BAKE B0.4-B EXACT WINDOWS VERIFICATION"
Write-Host "branch: $currentBranch"
Write-Host "HEAD:   $head"
Write-Host "TREE:   $((& git -C $RootDir rev-parse 'HEAD^{tree}').Trim())"
Write-Host "Godot:  $actualVersion"

$hadRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$previousRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $importOutput = @(& $GodotPath --headless --editor --path $RootDir --import 2>&1)
    $importExit = $LASTEXITCODE
    $importOutput | ForEach-Object { Write-Host $_ }
    if ($importExit -ne 0) { throw "Godot import failed: exit $importExit" }

    foreach ($script in @(
        "res://tests/research/fabric_bake0/fabric_bake_b0_4_a_acceptance.gd",
        "res://tests/research/fabric_bake0/fabric_bake_b0_4_b_acceptance.gd",
        "res://tests/research/fabric_bake0/fabric_bake_b0_4_b_playground.gd"
    )) {
        Write-Host "RUN $script"
        $output = @(& $GodotPath --headless --path $RootDir --script $script 2>&1)
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if ($exitCode -ne 0) { throw "Acceptance failed: $script exit $exitCode" }
        if (($output -join "`n") -match "SCRIPT ERROR:|ERROR: Failed to load script") {
            throw "Acceptance emitted fatal script marker: $script"
        }
    }
}
finally {
    if ($hadRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $previousRuntimeDisabled }
    else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
Write-Host "FABRIC-BAKE B0.4-B: PASS"
