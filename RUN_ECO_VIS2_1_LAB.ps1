param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedIdentity = "4.7.1.stable.double.custom_build.a13da4feb"

function Resolve-Godot {
    param([string]$ExplicitPath)
    $candidates = @()
    if ($ExplicitPath) { $candidates += $ExplicitPath }
    if ($env:GODOT4_BIN) { $candidates += $env:GODOT4_BIN }
    if ($env:GODOT_BIN) { $candidates += $env:GODOT_BIN }
    $candidates += @(
        (Join-Path $Root "godot.windows.editor.double.x86_64.exe"),
        (Join-Path $Root "godot.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $command = Get-Command godot4 -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "Godot executable not found. Pass -GodotPath or set GODOT4_BIN."
}

$Godot = Resolve-Godot $GodotPath
$Identity = (& $Godot --version 2>&1 | Select-Object -First 1).Trim()
if ($Identity -ne $ExpectedIdentity) {
    throw "Wrong Godot identity: '$Identity'; expected '$ExpectedIdentity'."
}

& $Godot --path $Root "res://scenes/labs/ecology/eco_vis2_1_control_vs_treatment_lab.tscn"
exit $LASTEXITCODE
