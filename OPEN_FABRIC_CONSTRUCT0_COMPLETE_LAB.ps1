param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/fabric-construct0-c0-4-c0-6-lifecycle-r1"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($currentBranch -ne $ExpectedBranch) {
    throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch"
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$GuiGodot = $GodotPath -replace '\.console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $GuiGodot -PathType Leaf)) { $GuiGodot = $GodotPath }

$hadRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$previousRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GuiGodot --path $RootDir --editor-pid 0 res://scenes/labs/fabric_construct0_complete_lab.tscn
}
finally {
    if ($hadRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $previousRuntimeDisabled }
    else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
