param(
    [Parameter(Mandatory=$false)]
    [string]$GodotPath = $env:GODOT_BIN,
    [ValidateSet("CUBE_100K", "PYRAMID_100K")]
    [string]$Profile = "CUBE_100K",
    [ValidateSet("NEAR", "MID", "FAR")]
    [string]$Mode = "FAR"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath or GODOT_BIN is required."
}

& $GodotPath --path $ProjectRoot "res://scenes/labs/construction/ts0_100k_hierarchical_visual_lab.tscn" -- "--ts0-profile=$Profile" "--ts0-mode=$Mode"
if ($LASTEXITCODE -ne 0) {
    throw "TS0.2 100k graphical lab exited with code $LASTEXITCODE"
}
