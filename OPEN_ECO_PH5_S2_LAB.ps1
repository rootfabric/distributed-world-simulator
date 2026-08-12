param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
$GuiGodot = $GodotPath -replace '\.console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $GuiGodot -PathType Leaf)) { $GuiGodot = $GodotPath }
Write-Host "Opening ECO.PH5-S2 real 3D plant materialization lab"
Write-Host "Godot: $GuiGodot"
Write-Host "Scene: res://scenes/labs/ecology/eco_ph5_s2_3d_materialization_lab.tscn"
Write-Host "Controls: Q/E = environment; A/D or Left/Right = BRANCH_TUBES / BRANCH_LEAF_INSTANCED / FULL_PROCEDURAL"
$previous = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GuiGodot --path $RootDir --editor-pid 0 res://scenes/labs/ecology/eco_ph5_s2_3d_materialization_lab.tscn
}
finally {
    if ($null -eq $previous) { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $previous }
}
