param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/fabric-construct0-tangible-sandbox-r1"

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

Write-Host "Opening FABRIC CONSTRUCT0 tangible sandbox"
Write-Host "Branch: $ExpectedBranch"
Write-Host "Godot: $GuiGodot"
Write-Host "Scene: res://scenes/labs/fabric_construct0_lab.tscn"
Write-Host "Tabs: SEE THE MODEL / SEE FABRIC MOVE IT / BUILD IT"
Write-Host "C0.1: canonical Construction + real B0.3 reduction."
Write-Host "C0.2: closed FABRIC0.18 trajectory playback."
Write-Host "C0.3: canonical Block/Plate/Beam editor with move/rotate/bond/break."

$hadRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$previousRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GuiGodot --path $RootDir --editor-pid 0 res://scenes/labs/fabric_construct0_lab.tscn
}
finally {
    if ($hadRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $previousRuntimeDisabled
    }
    else {
        Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}
