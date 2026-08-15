param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis1-0-lab-" + [Guid]::NewGuid().ToString("N"))

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw "Godot executable not found: $GodotPath"
    }

    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scenes\labs\ecology") -Force | Out-Null

    $projectConfig = @"
[application]
config/name="ECO VIS1.0 Visual Proving Ground"
run/main_scene="res://scenes/labs/ecology/eco_vis1_0_visual_proving_ground.tscn"

[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1440
window/size/window_height_override=900

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"@
    Set-Content -LiteralPath (Join-Path $TempRoot "project.godot") -Value $projectConfig -Encoding UTF8

    Copy-Item `
        -LiteralPath (Join-Path $RepoRoot "scripts\labs\ecology\eco_vis1_0_visual_proving_ground.gd") `
        -Destination (Join-Path $TempRoot "scripts\labs\ecology\eco_vis1_0_visual_proving_ground.gd") `
        -Force
    Copy-Item `
        -LiteralPath (Join-Path $RepoRoot "scenes\labs\ecology\eco_vis1_0_visual_proving_ground.tscn") `
        -Destination (Join-Path $TempRoot "scenes\labs\ecology\eco_vis1_0_visual_proving_ground.tscn") `
        -Force

    Write-Host "=== ECO VIS1.0 Visual Proving Ground ==="
    Write-Host "polygon=500x500m"
    Write-Host "controls=WASD move | Q/E down/up | Shift boost | mouse look | Esc release/capture | Home reset"
    Write-Host "Close the Godot window to return to PowerShell."

    $process = Start-Process `
        -FilePath $GodotPath `
        -ArgumentList @("--path", $TempRoot, "res://scenes/labs/ecology/eco_vis1_0_visual_proving_ground.tscn") `
        -PassThru `
        -Wait

    if ($process.ExitCode -ne 0) {
        throw "ECO VIS1.0 graphical lab exited with code $($process.ExitCode)"
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
