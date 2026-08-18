$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$GodotExe = if ($env:GODOT_EXE) {
    $env:GODOT_EXE
} else {
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}

if (-not (Test-Path $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}

$Previous = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/mrpf/test_mrpf_h1_space_earth_process.gd -- --graphical-client=true --phase-hold-ms=1500
    if ($LASTEXITCODE -ne 0) {
        throw "MRPF-H1 graphical stand failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($null -eq $Previous) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    } else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $Previous
    }
}
