param([string]$GodotPath = "")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
$Candidates = @()
if ($GodotPath) { $Candidates += $GodotPath }
if ($env:GODOT_BIN) { $Candidates += $env:GODOT_BIN }
foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot.windows.editor.double.x86_64.exe", "godot4", "godot")) {
  $Command = Get-Command $Name -ErrorAction SilentlyContinue; if ($null -ne $Command) { $Candidates += $Command.Source }
}
$Godot = $Candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique | Select-Object -First 1
if ($null -eq $Godot) { throw "Set GODOT_BIN or -GodotPath" }
$Actual = (& $Godot --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) { throw "Godot mismatch expected=$Expected actual=$Actual" }
& $Godot --headless --editor --path $Root --quit
if ($LASTEXITCODE -ne 0) { throw "editor import failed" }
& $Godot --headless --path $Root --script res://tests/runtime/test_v0_sm1_manual_seamless_demo.gd
if ($LASTEXITCODE -ne 0) { throw "manual seamless demo test failed" }
$Head = git -C $Root rev-parse HEAD
Write-Host "SM1_MANUAL_SEAMLESS_DEMO_EXACT_HEAD_PASS head=$Head godot=$Actual" -ForegroundColor Green
