param(
    [Parameter(Mandatory=$false)]
    [string]$GodotPath = $env:GODOT_BIN,
    [ValidateSet("CUBE_10K", "PYRAMID_10K")]
    [string]$Profile = "CUBE_10K",
    [ValidateSet("NEAR", "MID", "FAR")]
    [string]$Mode = "FAR"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath or GODOT_BIN is required."
}

& $GodotPath --path $ProjectRoot "res://scenes/labs/construction/ts0_large_structural_visual_lab.tscn" -- "--ts0-profile=$Profile" "--ts0-mode=$Mode"
if ($LASTEXITCODE -ne 0) {
    throw "TS0.1 graphical lab exited with code $LASTEXITCODE"
}
