[CmdletBinding()]
param([string]$GodotBin = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
if (-not $GodotBin) { $GodotBin = 'C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe' }
if ((Get-FileHash -LiteralPath $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant() -ne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'EXACT_WINDOWS_DOUBLE_ENGINE_REQUIRED' }
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
$env:PLANET_SIMULATOR_INVENTORY_PROFILE = 'planet_default'
$taskOutput = Join-Path $PSScriptRoot ('artifacts/journal-main-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))
New-Item -ItemType Directory -Path $taskOutput -ErrorAction Stop | Out-Null
$taskSpecs = @(
  @{Name='import'; Args=@('--editor','--import','--quit'); Marker=''},
  @{Name='rollback'; Args=@('--script','res://tests/runtime/test_v0_mvp_6_prediction_rollback.gd'); Marker='MVP6 prediction rollback: PASS (77 assertions)'},
  @{Name='nx6'; Args=@('--script','res://tests/network/test_nx6_predicted_item_interactions.gd'); Marker='NX6 predicted item interactions: PASS (940 assertions)'},
  @{Name='bridge'; Args=@('--script','res://tests/network/test_nx6_predicted_item_interactions_integration.gd'); Marker='NX6 predicted item integration: PASS (66 assertions)'}
)
foreach ($taskSpec in $taskSpecs) {
  $taskLog = Join-Path $taskOutput ($taskSpec.Name + '.log')
  & $GodotBin --headless --path $PSScriptRoot @($taskSpec.Args) *> $taskLog
  $taskExit = $LASTEXITCODE
  $taskText = Get-Content -LiteralPath $taskLog -Raw
  if ($taskExit -ne 0 -or $taskText -match '(?m)^\s*(SCRIPT ERROR|ERROR):|Parse Error|Compile Error') { throw "GATE_FAILED:$($taskSpec.Name):$taskLog" }
  if ($taskSpec.Marker -and @($taskText.Split("`n") | Where-Object { $_.TrimEnd() -ceq $taskSpec.Marker }).Count -ne 1) { throw "EXACT_ASSERTIONS_REQUIRED:$($taskSpec.Name)" }
  Write-Output "PASS $($taskSpec.Name) $((Get-FileHash -LiteralPath $taskLog -Algorithm SHA256).Hash)"
}
