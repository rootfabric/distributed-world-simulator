$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif ($env:GODOT_DOUBLE_BIN) { $env:GODOT_DOUBLE_BIN } else { "godot" }
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 LS3.6 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
& $GodotBin --path $Root "res://scenes/labs/ecology/eco_evo7_ls36_rule_workbench_lab.tscn"
exit $LASTEXITCODE
