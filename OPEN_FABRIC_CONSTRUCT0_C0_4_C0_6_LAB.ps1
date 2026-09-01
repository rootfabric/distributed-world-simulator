param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/fabric-construct0-c0-4-c0-6-lifecycle-r1"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) {
    throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch"
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}
$GuiGodot = $GodotPath -replace '\.console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $GuiGodot -PathType Leaf)) {
    $GuiGodot = $GodotPath
}

Write-Host "Opening CONSTRUCT0 C0.4-C0.6 Physical Lifecycle Lab"
Write-Host "C0.4 FULL/BAKED | C0.5 mutation/rebuild | C0.6 local-unbake/split/re-bake"
Write-Host "Godot: $GuiGodot"

$hadRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$previousRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GuiGodot --path $RootDir --editor-pid 0 res://scenes/labs/fabric_construct0_c0_4_c0_6_lab.tscn
}
finally {
    if ($hadRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $previousRuntimeDisabled }
    else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
