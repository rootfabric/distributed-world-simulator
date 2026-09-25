param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$Python = "python"
)
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $GodotBin = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    throw "Pinned Godot executable not found: $GodotBin"
}
$Output = Join-Path $Root "artifacts\mvp3-native-process"
if (Test-Path -LiteralPath $Output) {
    throw "Preserve or move previous evidence first: $Output"
}
$PreviousUtf8 = $env:PYTHONUTF8
try {
    $env:PYTHONUTF8 = "1"
    & $Python (Join-Path $Root "tests\integration\test_v0_mvp3_native_process_roundtrip.py") --engine $GodotBin --output $Output
    if ($LASTEXITCODE -ne 0) {
        throw "MVP3 native process roundtrip failed; see $Output\manifest.json and logs"
    }
}
finally {
    if ($null -eq $PreviousUtf8) { Remove-Item Env:\PYTHONUTF8 -ErrorAction SilentlyContinue }
    else { $env:PYTHONUTF8 = $PreviousUtf8 }
}
Write-Host "MVP3 native A-B-A process subgate passed. Graphical MVP3 acceptance is not claimed."
