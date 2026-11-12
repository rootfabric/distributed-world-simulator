# Seamless transfer testing suite (r1)
# Run from the repository root: .\RUN_SEAMLESS_TRANSFER_SUITE.ps1
# Requires Godot 4.7.1.stable.double.custom_build.a13da4feb at $env:GODOT_BIN
# (default C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe).

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"

if (-not (Test-Path $GodotBin)) {
    Write-Output "SEAMLESS_SUITE_GODOT_NOT_FOUND: $GodotBin"
    exit 2
}
$ActualVersion = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($ActualVersion -ne $ExpectedVersion) {
    Write-Output "SEAMLESS_SUITE_GODOT_VERSION_MISMATCH: expected=$ExpectedVersion actual=$ActualVersion"
    exit 3
}
$TestedHead = git -C $Root rev-parse HEAD
if (-not $TestedHead) {
    Write-Output "SEAMLESS_SUITE_GIT_HEAD_UNAVAILABLE"
    exit 4
}
Write-Output "SEAMLESS_SUITE_GODOT_VERSION=$ActualVersion"
Write-Output "SEAMLESS_SUITE_TESTED_HEAD=$TestedHead"

$env:BREAKPOINT_RUNTIME_DISABLED = "1"
$LogDir = Join-Path $Root "artifacts\test-results\seamless-suite"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Tests = @(
    "res://tests/runtime/test_v0_sm1_world_mutations_around_handoff.gd",
    "res://tests/runtime/test_v0_sm1_graphical_handoff_processes.gd",
    "res://tests/runtime/test_seamless_transfer_items_grids_stress.gd",
    "res://tests/runtime/test_seamless_transfer_process_metrics.gd"
)

$Failed = 0
foreach ($Test in $Tests) {
    $Name = (Split-Path $Test -Leaf) -replace "\.gd$", ""
    Write-Output "=== $Name ==="
    & $GodotBin --headless --path $Root --script $Test *> (Join-Path $LogDir "$Name.log")
    if ($LASTEXITCODE -ne 0) {
        Write-Output "SEAMLESS_SUITE_TEST_FAILED: $Name (exit $LASTEXITCODE)"
        Get-Content (Join-Path $LogDir "$Name.log") -Tail 15
        $Failed += 1
    }
}

if ($Failed -gt 0) {
    Write-Output "SEAMLESS_SUITE_FAIL head=$TestedHead godot=$ActualVersion failed=$Failed"
    exit 1
}
Write-Output "SEAMLESS_SUITE_PASS head=$TestedHead godot=$ActualVersion"
exit 0
