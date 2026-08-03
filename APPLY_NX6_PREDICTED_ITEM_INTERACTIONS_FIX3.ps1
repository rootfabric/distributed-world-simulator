param([string]$ProjectRoot = "")
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$Production = Join-Path $ProjectRoot "scripts/world/testing/playground_runtime.gd"
$Client = Join-Path $ProjectRoot "tools/runtime/m7_playable_network_client.gd"
if (-not (Test-Path $Production)) { throw "Missing production playground runtime: $Production" }
if (-not (Test-Path $Client)) { throw "Missing M7 process client: $Client" }
$ProductionSource = Get-Content -Raw -Path $Production
$ClientSource = Get-Content -Raw -Path $Client
if (-not $ProductionSource.Contains('_m7_item_bridge.stop("NX6_PLAYGROUND_UNLOAD")')) {
    throw "NX6 fix3 production cleanup is not present."
}
if ($ClientSource.Contains("nx6_lifecycle_safe_playground_runtime")) {
    throw "M7 process client still references the obsolete lifecycle wrapper."
}
foreach ($Relative in @(
    "scripts/world/testing/nx6_lifecycle_safe_playground_runtime.gd",
    "scripts/world/testing/nx6_lifecycle_safe_playground_runtime.gd.uid"
)) {
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $ProjectRoot $Relative)
}
Write-Host "NX6 fix3 applied: production playground cleanup active; obsolete fix2 wrapper removed." -ForegroundColor Green
