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
    throw "C22 incremental editor import failed: $LASTEXITCODE"
}

$Tests = @(
    "res://tests/construction/test_c22_incremental_local_rebuild.gd",
    "res://tests/construction/test_c22_compiled_proxy_graphical.gd",
    "res://tests/construction/test_c24_proxy_mesh_backend_contracts.gd"
)

foreach ($Test in $Tests) {
    & $GodotPath --headless --path $ProjectRoot --script $Test
    if ($LASTEXITCODE -ne 0) {
        throw "C22 incremental focused test failed: $Test ($LASTEXITCODE)"
    }
}

Write-Host "C22 incremental local rebuild focused gate: PASS"
