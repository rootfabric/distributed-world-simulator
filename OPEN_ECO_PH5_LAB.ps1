param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$GuiGodot = $GodotPath -replace '\.console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $GuiGodot -PathType Leaf)) { $GuiGodot = $GodotPath }
Write-Host "Opening ECO.PH5 render materialization lab"
Write-Host "Godot: $GuiGodot"
Write-Host "Scene: res://scenes/labs/ecology/eco_ph5_render_materialization_lab.tscn"
Write-Host "Controls: Q/E = environment; A/D or Left/Right = renderer profile; Up/Down = zoom"

$hadRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$previousRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    # This standalone research lab does not need the breakpoint_mcp TCP bridge.
    # Disable its fixed-port listener so an already-running editor/MCP session on
    # 127.0.0.1:9081 cannot contaminate graphical review with a port collision.
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GuiGodot --path $RootDir --editor-pid 0 res://scenes/labs/ecology/eco_ph5_render_materialization_lab.tscn
}
finally {
    if ($hadRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $previousRuntimeDisabled
    }
    else {
        Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}