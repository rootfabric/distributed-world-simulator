param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) { $Candidates += $GodotPath }
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
$Candidates += @(
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)
$GodotExecutable = $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique | Select-Object -First 1
if ($null -eq $GodotExecutable) { throw "Godot executable not found. Set -GodotPath or GODOT_BIN to the Godot 4.7.1 double-precision console/editor binary." }

$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    Write-Host "=== G8.0 editor import / parse ==="
    & $GodotExecutable --headless --editor --path $RootDir --quit
    if ($LASTEXITCODE -ne 0) { throw "G8.0 headless editor import failed" }

    Write-Host "=== G8.0 Geomorphology Contracts ==="
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/geomorphology/g8_0_geomorphology_contracts_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G8.0 geomorphology contracts acceptance failed" }

    Write-Host "G8.0 Geomorphology Contracts focused gate passed."
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
