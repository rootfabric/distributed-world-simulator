param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/fabric-construct0-tangible-sandbox-r1"
$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) {
    throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch"
}

$trackedStatus = (& git -C $RootDir status --short --untracked-files=no)
if ($LASTEXITCODE -ne 0) { throw "Unable to read Git status" }
if (-not [string]::IsNullOrWhiteSpace(($trackedStatus -join ""))) {
    throw "DIRTY_TRACKED_WORKTREE"
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$actualVersion = ((& $GodotPath --version) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to execute Godot: $GodotPath" }
if ($actualVersion -ne $ExpectedVersion) {
    throw "Unexpected Godot version: $actualVersion expected $ExpectedVersion"
}

$head = (& git -C $RootDir rev-parse HEAD).Trim()
$tree = (& git -C $RootDir rev-parse "HEAD^{tree}").Trim()
Write-Host "FABRIC CONSTRUCT0 C0.1-C0.3 EXACT WINDOWS VERIFICATION"
Write-Host "branch: $currentBranch"
Write-Host "HEAD:   $head"
Write-Host "TREE:   $tree"
Write-Host "Godot:  $actualVersion"

$hadRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$previousRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    & $GodotPath --headless --path $RootDir --import
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed: exit $LASTEXITCODE" }

    foreach ($script in @(
        "res://tests/research/fabric_construct0/fabric_construct0_c0_1_acceptance.gd",
        "res://tests/research/fabric_construct0/fabric_construct0_c0_2_acceptance.gd",
        "res://tests/research/fabric_construct0/fabric_construct0_c0_3_acceptance.gd"
    )) {
        Write-Host "RUN $script"
        & $GodotPath --headless --path $RootDir --script $script
        if ($LASTEXITCODE -ne 0) {
            throw "Acceptance failed: $script exit $LASTEXITCODE"
        }
    }
}
finally {
    if ($hadRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $previousRuntimeDisabled
    }
    else {
        Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}

Write-Host "FABRIC CONSTRUCT0 C0.1-C0.3: PASS"
