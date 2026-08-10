param(
    [Parameter(Mandatory=$false)]
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath or GODOT_BIN is required."
}

& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) {
    throw "TS0.2 editor import failed: $LASTEXITCODE"
}

$Tests = @(
    "res://tests/construction/test_c24_proxy_mesh_backend_contracts.gd",
    "res://tests/construction/ts0/ts0_100k_hierarchical_proxy_acceptance.gd"
)

foreach ($Test in $Tests) {
    & $GodotPath --headless --path $ProjectRoot --script $Test
    if ($LASTEXITCODE -ne 0) {
        throw "TS0.2 focused test failed: $Test ($LASTEXITCODE)"
    }
}
