$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe"
)

$Godot = $Candidates |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if ($null -eq $Godot) {
    throw "Double-precision Godot editor was not found."
}

foreach ($TestScript in @(
    "res://tests/integration/test_unified_planetary_runtime.gd",
    "res://tests/integration/test_unified_runtime_boot.gd"
)) {
    & $Godot `
        --headless `
        --path $ProjectRoot `
        --script $TestScript

    if ($LASTEXITCODE -ne 0) {
        throw "Unified planetary runtime test failed: $TestScript"
    }
}
