param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot 4.7.1 double executable is required via -GodotPath or GODOT_BIN."
}
& $GodotPath --path $Root --rendering-method gl_compatibility res://scenes/labs/character/character_presentation_lab.tscn
exit $LASTEXITCODE
