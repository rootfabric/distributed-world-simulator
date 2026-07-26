$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe"
)
$Godot = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -eq $Godot) {
    throw "Double-precision Godot was not found. Update ITEM_SYSTEM_LAB.ps1 with its path."
}
& $Godot --path $ProjectRoot --editor res://scenes/items/item_system_lab.tscn
