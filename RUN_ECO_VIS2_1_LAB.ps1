param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis2-1-lab-" + [Guid]::NewGuid().ToString("N"))
$Scene = "res://scenes/labs/ecology/eco_vis2_1_control_vs_treatment_lab.tscn"

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw "Godot executable not found: $GodotPath"
    }

    $versionOutput = (& $GodotPath --version 2>&1 | Out-String).Trim()
    Write-Host $versionOutput
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) {
        throw "ECO VIS2.1 requires exact Godot $ExpectedGodotVersion"
    }

    $projectConfig = @"
[application]
config/name="ECO VIS2.1 Control vs Treatment Lab"
run/main_scene="$Scene"

[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1440
window/size/window_height_override=900
window/stretch/mode="canvas_items"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"@

    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $TempRoot "project.godot") -Value $projectConfig -Encoding UTF8

    # Keep the graphical lab isolated from the repository-level autoloads/editor
    # plugins. This is the same dependency boundary used by the validated VIS2.1
    # automated gate, but without copying test scripts.
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
        "scripts\labs\ecology\eco_vis1_9_observatory_model.gd",
        "scripts\labs\ecology\eco_vis1_9_observatory_panel.gd",
        "scripts\labs\ecology\eco_vis1_9_evolution_observatory.gd",
        "scripts\labs\ecology\eco_vis2_0_experiment_model.gd",
        "scripts\labs\ecology\eco_vis2_0_experiment_panel.gd",
        "scripts\labs\ecology\eco_vis2_0_evolution_experiment_lab.gd",
        "scripts\labs\ecology\eco_vis2_1_branch_trace_contract.gd",
        "scripts\labs\ecology\eco_vis2_1_control_branch_runner.gd",
        "scripts\labs\ecology\eco_vis2_1_treatment_branch_runner.gd",
        "scripts\labs\ecology\eco_vis2_1_comparison_model.gd",
        "scripts\labs\ecology\eco_vis2_1_comparison_panel.gd",
        "scripts\labs\ecology\eco_vis2_1_trace_adapter.gd",
        "scripts\labs\ecology\eco_vis2_1_control_vs_treatment_lab.gd",
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
        "scenes\labs\ecology\eco_vis2_0_evolution_experiment_lab.tscn",
        "scenes\labs\ecology\eco_vis2_1_control_vs_treatment_lab.tscn"
    )

    foreach ($relative in $copies) {
        $source = Join-Path $RepoRoot $relative
        $target = Join-Path $TempRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "ECO VIS2.1 graphical lab dependency missing: $source"
        }
        $targetDir = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    Write-Host "=== ECO VIS2.1 Control vs Treatment Lab ==="
    Write-Host "launch_mode=ISOLATED_NO_REPOSITORY_AUTOLOADS"
    Write-Host "fork=F at current BASELINE generation"
    Write-Host "control=BASELINE data-only"
    Write-Host "treatment=2 DROUGHT | 3 FLOOD | 4 NUTRIENT_PULSE | 5 SHADE | -/+ intensity"
    Write-Host "paired=Space play/pause | Left/Right cached rewind/advance | R restart common fork"
    Write-Host "comparison=CONTROL / TREATMENT / DELTA; VIS1.9 and VIS2.0 panels are inherited pre-fork/source diagnostics"
    Write-Host "Close the Godot window to return to PowerShell."

    & $GodotPath --path $TempRoot $Scene
    if ($LASTEXITCODE -ne 0) {
        throw "ECO VIS2.1 graphical lab exited with code $LASTEXITCODE"
    }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
