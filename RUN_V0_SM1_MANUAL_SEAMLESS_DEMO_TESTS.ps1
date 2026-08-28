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

$ProfileRoot = Join-Path $Root ("artifacts/test-results/sm1-manual-demo-test-profile-{0}" -f $PID)
$DataRoot = Join-Path $ProfileRoot "data"
$ConfigRoot = Join-Path $ProfileRoot "config"
$CacheRoot = Join-Path $ProfileRoot "cache"
foreach ($Path in @($ProfileRoot, $DataRoot, $ConfigRoot, $CacheRoot)) {
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

$Names = @(
  "HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA",
  "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
  "PLANET_SIMULATOR_INVENTORY_PROFILE", "GODOT_SILENCE_ROOT_WARNING"
)
$Saved = @{}
foreach ($Name in $Names) {
  $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

try {
  $env:HOME = $ProfileRoot
  $env:USERPROFILE = $ProfileRoot
  $env:APPDATA = $DataRoot
  $env:LOCALAPPDATA = $DataRoot
  $env:XDG_DATA_HOME = $DataRoot
  $env:XDG_CONFIG_HOME = $ConfigRoot
  $env:XDG_CACHE_HOME = $CacheRoot
  $env:PLANET_SIMULATOR_INVENTORY_PROFILE = "planet_default"
  $env:GODOT_SILENCE_ROOT_WARNING = "1"

  & $Godot --headless --editor --path $Root --quit
  if ($LASTEXITCODE -ne 0) { throw "editor import failed" }

  & $Godot --headless --path $Root --script res://tests/runtime/test_v0_sm1_manual_seamless_demo.gd
  if ($LASTEXITCODE -ne 0) { throw "manual seamless demo test failed" }

  $Head = git -C $Root rev-parse HEAD
  Write-Host "SM1_MANUAL_SEAMLESS_DEMO_EXACT_HEAD_PASS head=$Head godot=$Actual profile=$ProfileRoot" -ForegroundColor Green
}
finally {
  foreach ($Name in $Names) {
    [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], "Process")
  }
}
