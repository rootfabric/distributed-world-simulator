param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
$GuiGodot = $GodotPath -replace '\.console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $GuiGodot -PathType Leaf)) { $GuiGodot = $GodotPath }
Write-Host "Opening ECO.PH5-S4 multiscale LOD / truth-invariance lab"
Write-Host "Godot: $GuiGodot"
Write-Host "Scene: res://scenes/labs/ecology/eco_ph5_s4_multiscale_lod_lab.tscn"
Write-Host "Controls: Q/E = contrasting PH2 environment; A/D or Left/Right = FULL / REDUCED / CANOPY / IMPOSTOR / POPULATION_ONLY"
Write-Host "Acceptance: morphology changes by environment, representation changes by tier, growth_graph_hash must remain fixed while cycling tiers for one environment; POPULATION_ONLY must show no individual plant geometry."
$previous = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GuiGodot --path $RootDir --editor-pid 0 res://scenes/labs/ecology/eco_ph5_s4_multiscale_lod_lab.tscn
}
finally {
    if ($null -eq $previous) { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $previous }
}
