param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis1-5-lab-" + [Guid]::NewGuid().ToString("N"))

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw "Godot executable not found: $GodotPath"
    }

    $versionOutput = (& $GodotPath --version 2>&1 | Out-String).Trim()
    Write-Host $versionOutput
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) {
        throw "ECO VIS1.5 requires exact Godot $ExpectedGodotVersion"
    }

    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\research\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scenes\labs\ecology") -Force | Out-Null

    $projectConfig = @"
[application]
config/name="ECO VIS1.5 Environment-Coupled Phenotype Field"
run/main_scene="res://scenes/labs/ecology/eco_vis1_5_environment_phenotype_field.tscn"

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
        @("scripts\labs\ecology\eco_vis1_4_population_visual_field.gd", "scripts\labs\ecology\eco_vis1_4_population_visual_field.gd"),
        @("scripts\labs\ecology\eco_vis1_5_environment_phenotype_bridge.gd", "scripts\labs\ecology\eco_vis1_5_environment_phenotype_bridge.gd"),
        @("scripts\labs\ecology\eco_vis1_5_environment_phenotype_field.gd", "scripts\labs\ecology\eco_vis1_5_environment_phenotype_field.gd"),
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
        @("scenes\labs\ecology\eco_vis1_5_environment_phenotype_field.tscn", "scenes\labs\ecology\eco_vis1_5_environment_phenotype_field.tscn")
    )

    foreach ($pair in $copies) {
        $source = Join-Path $RepoRoot $pair[0]
        $target = Join-Path $TempRoot $pair[1]
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "ECO VIS1.5 required file missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    Write-Host "=== ECO VIS1.5 Environment-Coupled Phenotype Field ==="
    Write-Host "polygon=500x500m environment_seed=73191"
    Write-Host "ecology_source=canonical VIS1.2 spatial snapshot, read-only"
    Write-Host "population_field=VIS1.4 representative density + clustered placement + LOD"
    Write-Host "phenotype=actual local EnvironmentSample -> EnvironmentCoupledDevelopment -> GrowthGraph -> PH5"
    Write-Host "lab_genome=shared baseline context only; NOT canonical alpha/beta genome truth"
    Write-Host "canned_exemplars=OFF (no alpha:SUN / beta:SHADE morphology selection)"
    Write-Host "controls=WASD move | Q/E down/up | Shift boost | mouse look | Esc release/capture | Home reset | F1-F5 diagnostics/visibility"
    Write-Host "Close the Godot window to return to PowerShell."

    $process = Start-Process `
        -FilePath $GodotPath `
        -ArgumentList @("--path", $TempRoot, "res://scenes/labs/ecology/eco_vis1_5_environment_phenotype_field.tscn") `
        -PassThru `
        -Wait

    if ($process.ExitCode -ne 0) {
        throw "ECO VIS1.5 graphical lab exited with code $($process.ExitCode)"
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
