param([string]$GodotPath = "")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath is required" }
$ImportHome = Join-Path $Root "artifacts/test-results/m4-import-$PID"
$ImportData = Join-Path $ImportHome "data"; $ImportConfig = Join-Path $ImportHome "config"; $ImportCache = Join-Path $ImportHome "cache"
New-Item -ItemType Directory -Force -Path $ImportData,$ImportConfig,$ImportCache | Out-Null
$env:HOME=$ImportHome; $env:APPDATA=$ImportData; $env:LOCALAPPDATA=$ImportData; $env:XDG_DATA_HOME=$ImportData; $env:XDG_CONFIG_HOME=$ImportConfig; $env:XDG_CACHE_HOME=$ImportCache
$oldImportPreference=$ErrorActionPreference; $importNative=$null
try {
 if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $importNative=$PSNativeCommandUseErrorActionPreference; $PSNativeCommandUseErrorActionPreference=$false }
 $ErrorActionPreference="Continue"; $importOutput=& $GodotPath --headless --editor --path $Root --quit 2>&1; $importCode=$LASTEXITCODE; $importOutput | ForEach-Object { Write-Host $_ }
} finally { $ErrorActionPreference=$oldImportPreference; if ($null -ne $importNative) { $PSNativeCommandUseErrorActionPreference=$importNative } }
if ($importCode -ne 0 -or (($importOutput -join "`n") -match "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:)")) { throw "M4 editor import failed" }
$Tests = @(
 "res://tests/runtime/test_m1_networked_gameplay_contracts.gd",
 "res://tests/runtime/test_m1_unified_networked_gameplay_service.gd",
 "res://tests/runtime/test_m2_graphical_client_contracts.gd",
 "res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd",
 "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd",
 "res://tests/runtime/test_m4_graphical_shared_gameplay_processes.gd",
 "res://tests/network/test_t1_multi_peer_transport_contracts.gd",
 "res://tests/runtime/test_a2_networked_gameplay_architecture.gd",
 "res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd"
)
$Profile = Join-Path $Root "artifacts/test-results/m4-profile-$PID"
New-Item -ItemType Directory -Force -Path $Profile | Out-Null
foreach ($Test in $Tests) {
 $Name = [IO.Path]::GetFileNameWithoutExtension($Test); $TestHome = Join-Path $Profile $Name
 $Data = Join-Path $TestHome "data"; $Config = Join-Path $TestHome "config"; $Cache = Join-Path $TestHome "cache"
 New-Item -ItemType Directory -Force -Path $Data,$Config,$Cache | Out-Null
 $old = $ErrorActionPreference; $native = $null
 try {
  $env:HOME=$TestHome; $env:APPDATA=$Data; $env:LOCALAPPDATA=$Data; $env:XDG_DATA_HOME=$Data; $env:XDG_CONFIG_HOME=$Config; $env:XDG_CACHE_HOME=$Cache
  if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $native=$PSNativeCommandUseErrorActionPreference; $PSNativeCommandUseErrorActionPreference=$false }
  $ErrorActionPreference="Continue"; $output=& $GodotPath --headless --path $Root --script $Test 2>&1; $code=$LASTEXITCODE; $output | ForEach-Object { Write-Host $_ }
 } finally { $ErrorActionPreference=$old; if ($null -ne $native) { $PSNativeCommandUseErrorActionPreference=$native } }
 if ($code -ne 0 -or (($output -join "`n") -match "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:)")) { throw "M4 test failed: $Test" }
}
Write-Host "M4 canonical shared gameplay: PASS ($($Tests.Count)/$($Tests.Count))"
