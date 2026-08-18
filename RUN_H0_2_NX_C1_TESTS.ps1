[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Tests = @(
    'tests/network/test_nx_owner_movement_authority.gd',
    'tests/network/test_nx_render_physics_separation.gd',
    'tests/network/test_nx_owner_item_projection_rollback.gd',
    'tests/network/test_nx_client_tick_robustness.gd',
    'tests/network/test_nx6_predicted_item_interactions.gd'
)

Write-Host "[H0.2][NX.C1] Godot: $GodotPath"
foreach ($TestPath in $Tests) {
    Write-Host "[H0.2][NX.C1] RUN $TestPath"
    & $GodotPath --headless --path $Root --script "res://$TestPath"
    if ($LASTEXITCODE -ne 0) {
        throw "H0.2 NX.C1 test failed: $TestPath (exit $LASTEXITCODE)"
    }
}
Write-Host "[H0.2][NX.C1] focused suite PASS ($($Tests.Count) scripts)"
