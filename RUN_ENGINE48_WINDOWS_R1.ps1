# ENGINE48 Windows R1 gate runner.
# Strict fail-closed verification of the locally-built Godot 4.8 beta1 double
# binary against the exact migration HEAD. The canonical 4.7.1 runners are not
# modified and remain the product baseline.
param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [string]$ExpectedVersion = "4.8.beta1.double.custom_build.4d10419ca"
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out = Join-Path $Root "artifacts\engine48\windows\r1"
New-Item -ItemType Directory -Force $Out | Out-Null
$Godot = (Resolve-Path $GodotPath).Path

# This pinned machine binary was independently checked for Windows R1.
$ExpectedSha256 = 'f53f90f686a4eb05df076692c1b67a9e3d12d7c6c981cf86f1015d1ec36a2636'
$sha = (Get-FileHash -LiteralPath $Godot -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne $ExpectedSha256) { throw "ENGINE48_SHA_MISMATCH:$sha" }
$ver = (& $Godot --version | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $ver -ne $ExpectedVersion) { throw "ENGINE48_VERSION_MISMATCH:$ver" }
if ((git -C $Root status --porcelain --untracked-files=no)) { throw 'TRACKED_DIRTY' }

[ordered]@{
    schema = "distributed_world_simulator.engine48_windows_gate.v1"
    head = (git -C $Root rev-parse HEAD).Trim()
    tree = (git -C $Root rev-parse 'HEAD^{tree}').Trim()
    godot_version = $ver
    godot_console_sha256 = $sha
} | ConvertTo-Json | Set-Content (Join-Path $Out "gate-preflight.json") -Encoding UTF8

$tests = @(
    'tests/network/test_v0_live2_enet_rollover.gd',
    'tests/runtime/test_v0_live2_human_gameplay_bridge.gd',
    'tests/network/test_nx2_physical_channel_processes.gd',
    'tests/runtime/test_v0_user1_first_usable_slice.gd',
    'tests/runtime/test_v0_user1_product_seam_bridge.gd',
    'tests/runtime/test_v0_p4_live_two_client_reconnect_convergence.gd',
    'tests/runtime/test_m6_dedicated_recovery_processes.gd',
    'tests/runtime/test_v0_ux0_product_shell.gd',
    'tests/runtime/test_v0_mvp_6_native_item_handoff.gd',
    'tests/runtime/test_v0_mvp_6_native_carry_prerequisite.gd',
    'tests/runtime/test_launch_options.gd'
)
$failed = @()
foreach ($t in $tests) {
    $log = Join-Path $Out ("headless-" + (Split-Path -Leaf $t) + ".log")
    & $Godot --headless --path $Root --script "res://$t" *> $log
    if ($LASTEXITCODE -ne 0) { $failed += $t; Write-Host "FAIL $t" -ForegroundColor Red }
    else { Write-Host "PASS $t" -ForegroundColor Green }
}
if ($failed.Count -gt 0) { throw "ENGINE48_MATRIX_FAILED: $($failed -join ', ')" }
Write-Host "ENGINE48_WINDOWS_R1 gate: headless matrix PASS" -ForegroundColor Green
