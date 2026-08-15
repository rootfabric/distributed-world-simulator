param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis1-3-lab-" + [Guid]::NewGuid().ToString("N"))

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw "Godot executable not found: $GodotPath"
    }

    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\research\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scenes\labs\ecology") -Force | Out-Null

    $projectConfig = @"
[application]
config/name="ECO VIS1.3 PH5 Population Materialization"
run/main_scene="res://scenes/labs/ecology/eco_vis1_3_ph5_population_materialization.tscn"

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
        @("scripts\labs\ecology\eco_vis1_2_spatial_projection.gd", "scripts\labs\ecology\eco_vis1_2_spatial_projection.gd"),
        @("scripts\labs\ecology\eco_vis1_3_ph5_population_materialization.gd", "scripts\labs\ecology\eco_vis1_3_ph5_population_materialization.gd"),
        @("scripts\research\ecology\environment_sample_v1.gd", "scripts\research\ecology\environment_sample_v1.gd"),
        @("scripts\research\ecology\plant_resource_competition_v1.gd", "scripts\research\ecology\plant_resource_competition_v1.gd"),
        @("scripts\research\ecology\plant_density_carrying_capacity_v1.gd", "scripts\research\ecology\plant_density_carrying_capacity_v1.gd"),
        @("scripts\research\ecology\plant_spatial_dispersal_v1.gd", "scripts\research\ecology\plant_spatial_dispersal_v1.gd"),
        @("scripts\research\ecology\eco_obs1_spatial_snapshot_v1.gd", "scripts\research\ecology\eco_obs1_spatial_snapshot_v1.gd"),
        @("scripts\research\ecology\eco_obs1_spatial_demo_timeline_v1.gd", "scripts\research\ecology\eco_obs1_spatial_demo_timeline_v1.gd"),
        @("scripts\research\ecology\plant_genome_v1.gd", "scripts\research\ecology\plant_genome_v1.gd"),
        @("scripts\research\ecology\plant_development_traits_v1.gd", "scripts\research\ecology\plant_development_traits_v1.gd"),
        @("scripts\research\ecology\plant_development_contract_v1.gd", "scripts\research\ecology\plant_development_contract_v1.gd"),
        @("scripts\research\ecology\plant_development_plasticity_profile_v1.gd", "scripts\research\ecology\plant_development_plasticity_profile_v1.gd"),
        @("scripts\research\ecology\plant_growth_graph_skeleton_v1.gd", "scripts\research\ecology\plant_growth_graph_skeleton_v1.gd"),
        @("scripts\research\ecology\plant_environment_coupled_development_v1.gd", "scripts\research\ecology\plant_environment_coupled_development_v1.gd"),
        @("scripts\research\ecology\plant_environment_coupled_development_probes_v1.gd", "scripts\research\ecology\plant_environment_coupled_development_probes_v1.gd"),
        @("scripts\research\ecology\plant_renderer_profile_v1.gd", "scripts\research\ecology\plant_renderer_profile_v1.gd"),
        @("scripts\research\ecology\plant_render_description_v1.gd", "scripts\research\ecology\plant_render_description_v1.gd"),
        @("scripts\research\ecology\plant_render_description_probes_v1.gd", "scripts\research\ecology\plant_render_description_probes_v1.gd"),
        @("scripts\research\ecology\plant_3d_materializer_v1.gd", "scripts\research\ecology\plant_3d_materializer_v1.gd"),
        @("scenes\labs\ecology\eco_vis1_3_ph5_population_materialization.tscn", "scenes\labs\ecology\eco_vis1_3_ph5_population_materialization.tscn")
    )

    foreach ($pair in $copies) {
        $source = Join-Path $RepoRoot $pair[0]
        $target = Join-Path $TempRoot $pair[1]
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "ECO VIS1.3 required file missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    Write-Host "=== ECO VIS1.3 PH5 Population Materialization ==="
    Write-Host "polygon=500x500m environment_seed=73191"
    Write-Host "ecology_source=canonical VIS1.2 / ECO OBS1 spatial demo timeline, frame=5"
    Write-Host "geometry=existing PH5 RenderDescription -> Plant3DMaterializer"
    Write-Host "profile=BRANCH_LEAF_INSTANCED"
    Write-Host "presentation_exemplars=alpha:SUN beta:SHADE (NOT ecology/genome truth)"
    Write-Host "biomass_usage=visual count and scale only"
    Write-Host "patch discs/labels/links remain derived diagnostics"
    Write-Host "canonical ecology snapshot is read-only"
    Write-Host "controls=WASD move | Q/E down/up | Shift boost | mouse look | Esc release/capture | Home reset"
    Write-Host "Close the Godot window to return to PowerShell."

    $process = Start-Process `
        -FilePath $GodotPath `
        -ArgumentList @("--path", $TempRoot, "res://scenes/labs/ecology/eco_vis1_3_ph5_population_materialization.tscn") `
        -PassThru `
        -Wait

    if ($process.ExitCode -ne 0) {
        throw "ECO VIS1.3 graphical lab exited with code $($process.ExitCode)"
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
