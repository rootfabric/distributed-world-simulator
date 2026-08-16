param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis1-8b-lab-" + [Guid]::NewGuid().ToString("N"))

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable not found: $GodotPath" }
    $versionOutput = (& $GodotPath --version 2>&1 | Out-String).Trim()
    Write-Host $versionOutput
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) { throw "ECO VIS1.8B requires exact Godot $ExpectedGodotVersion" }

    $projectConfig = @"
[application]
config/name="ECO VIS1.8B Continuous Population Evolution"
run/main_scene="res://scenes/labs/ecology/eco_vis1_8b_continuous_population_field.tscn"
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1440
window/size/window_height_override=900
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"@
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $TempRoot "project.godot") -Value $projectConfig -Encoding UTF8

    $copies = @(
        "scripts\labs\ecology\eco_vis1_0_visual_proving_ground.gd",
        "scripts\labs\ecology\eco_environment_provider.gd",
        "scripts\labs\ecology\lab_environment_provider.gd",
        "scripts\labs\ecology\eco_vis1_1_environment_proving_ground.gd",
        "scripts\labs\ecology\eco_vis1_2_spatial_projection.gd",
        "scripts\labs\ecology\eco_vis1_3_ph5_population_materialization.gd",
        "scripts\labs\ecology\eco_vis1_4_population_visual_field.gd",
        "scripts\labs\ecology\eco_vis1_5_environment_phenotype_bridge.gd",
        "scripts\labs\ecology\eco_vis1_5_environment_phenotype_field.gd",
        "scripts\labs\ecology\eco_vis1_6_lineage_genome_bridge.gd",
        "scripts\labs\ecology\eco_vis1_6_lineage_genome_field.gd",
        "scripts\labs\ecology\eco_vis1_7_temporal_evolution_bridge.gd",
        "scripts\labs\ecology\eco_vis1_7_temporal_evolution_field.gd",
        "scripts\labs\ecology\eco_vis1_8a_turnover_bridge.gd",
        "scripts\labs\ecology\eco_vis1_8a_realtime_turnover_model.gd",
        "scripts\labs\ecology\eco_vis1_8a_realtime_proxy_renderer.gd",
        "scripts\labs\ecology\eco_vis1_8a_realtime_turnover_field.gd",
        "scripts\labs\ecology\eco_vis1_8b_continuous_turnover_model.gd",
        "scripts\labs\ecology\eco_vis1_8b_continuous_population_field.gd",
        "scripts\research\ecology\environment_sample_v1.gd",
        "scripts\research\ecology\plant_resource_competition_v1.gd",
        "scripts\research\ecology\plant_density_carrying_capacity_v1.gd",
        "scripts\research\ecology\plant_spatial_dispersal_v1.gd",
        "scripts\research\ecology\eco_obs1_spatial_snapshot_v1.gd",
        "scripts\research\ecology\eco_obs1_spatial_demo_timeline_v1.gd",
        "scripts\research\ecology\plant_genome_v1.gd",
        "scripts\research\ecology\plant_lineage_record_v1.gd",
        "scripts\research\ecology\plant_mutation_lineage_kernel_v1.gd",
        "scripts\research\ecology\plant_development_traits_v1.gd",
        "scripts\research\ecology\plant_development_contract_v1.gd",
        "scripts\research\ecology\plant_development_plasticity_profile_v1.gd",
        "scripts\research\ecology\plant_growth_graph_skeleton_v1.gd",
        "scripts\research\ecology\plant_environment_coupled_development_v1.gd",
        "scripts\research\ecology\plant_environment_coupled_development_probes_v1.gd",
        "scripts\research\ecology\plant_renderer_profile_v1.gd",
        "scripts\research\ecology\plant_render_description_v1.gd",
        "scripts\research\ecology\plant_render_description_probes_v1.gd",
        "scripts\research\ecology\plant_3d_materializer_v1.gd",
        "scenes\labs\ecology\eco_vis1_8b_continuous_population_field.tscn"
    )
    foreach ($relative in $copies) {
        $source = Join-Path $RepoRoot $relative
        $target = Join-Path $TempRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "ECO VIS1.8B required file missing: $source" }
        $targetDir = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    Write-Host "=== ECO VIS1.8B Continuous Population Evolution ==="
    Write-Host "validated_base=VIS1.8A-R1 e62bdc057ffc62a1a5e18772921e51b946e514b0"
    Write-Host "G12_limit=REMOVED; realtime turnover can continue to long-running generations"
    Write-Host "rolling_rewind_cache=32 turnover generations + founder G0"
    Write-Host "compact_history=64 generation summaries"
    Write-Host "generation0=detailed PH5 baseline; generation>0=realtime proxy presentation"
    Write-Host "whole-field PH5 rebuild during turnover=DISABLED"
    Write-Host "HUD tracks reps births deaths mean_fitness unique_genomes alpha/beta composition and recent history"
    Write-Host "R resets rolling timeline to deterministic founder G0"
    Write-Host "canonical_population_truth=OFF canonical_timeline_truth=OFF"
    Write-Host "controls=WASD move | Q/E down/up | Shift boost | mouse look | Esc release/capture | Home reset | Left/Right generation | Space play/pause | R restart G0 | F1-F5 diagnostics"
    Write-Host "Close the Godot window to return to PowerShell."

    $process = Start-Process -FilePath $GodotPath -ArgumentList @("--path", $TempRoot, "res://scenes/labs/ecology/eco_vis1_8b_continuous_population_field.tscn") -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "ECO VIS1.8B graphical lab exited with code $($process.ExitCode)" }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
