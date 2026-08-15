param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis1-1-lab-" + [Guid]::NewGuid().ToString("N"))

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw "Godot executable not found: $GodotPath"
    }

    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\research\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scenes\labs\ecology") -Force | Out-Null

    $projectConfig = @"
[application]
config/name="ECO VIS1.1 Causal Environment Proving Ground"
run/main_scene="res://scenes/labs/ecology/eco_vis1_1_environment_proving_ground.tscn"

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

    $copies = @(
        @("scripts\labs\ecology\eco_vis1_0_visual_proving_ground.gd", "scripts\labs\ecology\eco_vis1_0_visual_proving_ground.gd"),
        @("scripts\labs\ecology\eco_environment_provider.gd", "scripts\labs\ecology\eco_environment_provider.gd"),
        @("scripts\labs\ecology\lab_environment_provider.gd", "scripts\labs\ecology\lab_environment_provider.gd"),
        @("scripts\labs\ecology\eco_vis1_1_environment_proving_ground.gd", "scripts\labs\ecology\eco_vis1_1_environment_proving_ground.gd"),
        @("scripts\research\ecology\environment_sample_v1.gd", "scripts\research\ecology\environment_sample_v1.gd"),
        @("scenes\labs\ecology\eco_vis1_1_environment_proving_ground.tscn", "scenes\labs\ecology\eco_vis1_1_environment_proving_ground.tscn")
    )
    foreach ($pair in $copies) {
        $source = Join-Path $RepoRoot $pair[0]
        $target = Join-Path $TempRoot $pair[1]
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "ECO VIS1.1 required file missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    Write-Host "=== ECO VIS1.1 Causal Environment Proving Ground ==="
    Write-Host "polygon=500x500m seed=73191"
    Write-Host "terrain colors=moisture + nutrients + flood influence"
    Write-Host "blue ribbon=water gradient axis"
    Write-Host "controls=WASD move | Q/E down/up | Shift boost | mouse look | Esc release/capture | Home reset"
    Write-Host "Close the Godot window to return to PowerShell."

    $process = Start-Process `
        -FilePath $GodotPath `
        -ArgumentList @("--path", $TempRoot, "res://scenes/labs/ecology/eco_vis1_1_environment_proving_ground.tscn") `
        -PassThru `
        -Wait

    if ($process.ExitCode -ne 0) {
        throw "ECO VIS1.1 graphical lab exited with code $($process.ExitCode)"
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
