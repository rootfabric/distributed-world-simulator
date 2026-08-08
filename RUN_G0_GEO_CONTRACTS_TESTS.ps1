$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
    $Candidates += $env:GODOT_BIN
}
$Candidates += @(
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$GodotExecutable = $Candidates |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -Unique |
    Select-Object -First 1

if ($null -eq $GodotExecutable) {
    throw "Godot executable not found. Set GODOT_BIN to the Godot 4.7.1 double-precision console/editor binary."
}

$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED

try {
    # Headless contract tests never need the live MCP runtime socket. Disabling it
    # prevents false 127.0.0.1:9081 collisions when a regression harness starts
    # multiple Godot processes in parallel.
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    # A fresh git worktree has no .godot UID cache yet. Import once before the
    # standalone script so UID-backed autoloads resolve cleanly on first launch.
    & $GodotExecutable `
        --headless `
        --editor `
        --path $RootDir `
        --quit

    if ($LASTEXITCODE -ne 0) {
        throw "G0 headless editor import failed with exit code $LASTEXITCODE"
    }

    & $GodotExecutable `
        --headless `
        --path $RootDir `
        --script "res://tests/procedural/contracts/g0_geo_contracts_acceptance.gd"

    if ($LASTEXITCODE -ne 0) {
        throw "G0 Geo contracts acceptance failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($HadBreakpointRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled
    }
    else {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}
