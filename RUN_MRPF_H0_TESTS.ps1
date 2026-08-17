param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"
if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "MRPF-H0 Godot executable not found: $GodotExe"
}
$ActualVersion = (& $GodotExe --version).Trim()
if ($ActualVersion -ne $ExpectedVersion) {
    throw "MRPF-H0 Godot version mismatch: expected $ExpectedVersion, got $ActualVersion"
}
& $GodotExe --headless --path $ProjectRoot --script "res://tests/runtime/seamless/mrpf/test_mrpf_h0_hierarchical_projection.gd"
exit $LASTEXITCODE
