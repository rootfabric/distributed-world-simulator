$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe"
)
$Godot = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -eq $Godot) {
    throw "Double-precision Godot was not found. Update RUN_ITEM_SYSTEM_TESTS.ps1 with its path."
}
& $Godot --headless --path $ProjectRoot --script res://tests/items/test_item_domain.gd
if ($LASTEXITCODE -ne 0) {
    throw "Item system tests failed with exit code $LASTEXITCODE"
}
