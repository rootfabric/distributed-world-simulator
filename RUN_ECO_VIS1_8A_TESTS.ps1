param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis1-8a-" + [Guid]::NewGuid().ToString("N"))

function ConvertTo-ProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-GodotProcess {
    param([string[]]$Arguments, [string]$Label, [int]$TimeoutSeconds = 180)
    Write-Host ">> $Label"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GodotPath
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw "$Label failed to start Godot" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { Write-Warning "$Label timed out and Kill() also reported: $($_.Exception.Message)" }
            $process.WaitForExit()
            $stdout = $stdoutTask.Result
            $stderr = $stderrTask.Result
            $combined = ($stdout + [Environment]::NewLine + $stderr).Trim()
            if ($combined) { Write-Host $combined }
            throw "$Label timed out after $TimeoutSeconds seconds"
        }
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $combined = ($stdout + [Environment]::NewLine + $stderr).Trim()
        if ($combined) { Write-Host $combined }
        if ($process.ExitCode -ne 0) { throw "$Label failed with exit code $($process.ExitCode)" }
        if ($combined -match '(?m)^SCRIPT ERROR:' -or $combined -match '(?m)^ERROR:') { throw "$Label emitted Godot error output despite zero exit code" }
        return $combined
    }
    finally { $process.Dispose() }
}

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable not found: $GodotPath" }
    Write-Host "=== ECO VIS1.8A isolated population turnover gate ==="
    Write-Host "repo_root=$RepoRoot"
    Write-Host "godot=$GodotPath"
    $versionOutput = Invoke-GodotProcess -Arguments @("--version") -Label "ECO VIS1.8A Godot version check"
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) { throw "ECO VIS1.8A requires exact Godot $ExpectedGodotVersion" }
    Write-Host "ECO.VIS1.8A exact Godot identity: PASS"

    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\research\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scenes\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "tests\research\ecology") -Force | Out-Null

    $projectConfig = @"
[application]
config/name="ECO VIS1.8A Isolated Gate"
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"@
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
        "scripts\labs\ecology\eco_vis1_8a_population_turnover_field.gd",
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
        "scenes\labs\ecology\eco_vis1_2_spatial_projection.tscn",
        "scenes\labs\ecology\eco_vis1_3_ph5_population_materialization.tscn",
        "scenes\labs\ecology\eco_vis1_4_population_visual_field.tscn",
        "scenes\labs\ecology\eco_vis1_5_environment_phenotype_field.tscn",
        "scenes\labs\ecology\eco_vis1_6_lineage_genome_field.tscn",
        "scenes\labs\ecology\eco_vis1_7_temporal_evolution_field.tscn",
        "scenes\labs\ecology\eco_vis1_8a_population_turnover_field.tscn",
        "tests\research\ecology\test_eco_vis1_2_spatial_projection.gd",
        "tests\research\ecology\test_eco_vis1_3_ph5_population_materialization.gd",
        "tests\research\ecology\test_eco_vis1_4_population_visual_field.gd",
        "tests\research\ecology\test_eco_vis1_5_environment_phenotype_field.gd",
        "tests\research\ecology\test_eco_vis1_6_lineage_genome_field.gd",
        "tests\research\ecology\test_eco_vis1_7_temporal_evolution_bridge.gd",
        "tests\research\ecology\test_eco_vis1_7_temporal_evolution_field.gd",
        "tests\research\ecology\test_eco_vis1_8a_turnover_bridge.gd",
        "tests\research\ecology\test_eco_vis1_8a_population_turnover_field.gd"
    )
    foreach ($relative in $copies) {
        $source = Join-Path $RepoRoot $relative
        $target = Join-Path $TempRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "ECO VIS1.8A required file missing: $source" }
        $targetDir = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
    Write-Host "ECO.VIS1.8A isolated project with VIS1.2-VIS1.7 + turnover/recruitment + canonical PH5/development dependencies: PASS"

    Invoke-GodotProcess -Arguments @("--headless", "--path", $TempRoot, "--check-only", "--script", "res://tests/research/ecology/test_eco_vis1_8a_turnover_bridge.gd") -Label "ECO VIS1.8A bridge parser preflight" | Out-Null
    Invoke-GodotProcess -Arguments @("--headless", "--path", $TempRoot, "--check-only", "--script", "res://tests/research/ecology/test_eco_vis1_8a_population_turnover_field.gd") -Label "ECO VIS1.8A field parser preflight" | Out-Null
    Write-Host "ECO.VIS1.8A parser preflight: PASS"

    $regressions = @(
        @("2", "spatial_projection"),
        @("3", "ph5_population_materialization"),
        @("4", "population_visual_field"),
        @("5", "environment_phenotype_field"),
        @("6", "lineage_genome_field")
    )
    foreach ($entry in $regressions) {
        $stage = $entry[0]
        $suffix = $entry[1]
        $testPath = "res://tests/research/ecology/test_eco_vis1_${stage}_${suffix}.gd"
        $output = Invoke-GodotProcess -Arguments @("--headless", "--path", $TempRoot, "--script", $testPath) -Label "ECO VIS1.$stage regression smoke"
        if ($output -notmatch ("ECO\.VIS1\." + $stage + " headless scene smoke: PASS")) { throw "ECO VIS1.$stage regression PASS marker missing" }
        Write-Host "ECO.VIS1.$stage regression gate: PASS"
    }

    $vis17BridgeOutput = Invoke-GodotProcess -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis1_7_temporal_evolution_bridge.gd") -Label "ECO VIS1.7 regression temporal bridge"
    if ($vis17BridgeOutput -notmatch 'ECO\.VIS1\.7 temporal bridge: PASS') { throw "ECO VIS1.7 temporal bridge regression marker missing" }
    $vis17FieldOutput = Invoke-GodotProcess -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis1_7_temporal_evolution_field.gd") -Label "ECO VIS1.7 regression field"
    if ($vis17FieldOutput -notmatch 'ECO\.VIS1\.7 headless scene smoke: PASS') { throw "ECO VIS1.7 field regression marker missing" }
    Write-Host "ECO.VIS1.7 regression gate: PASS"

    $bridgeOutput = Invoke-GodotProcess -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis1_8a_turnover_bridge.gd") -Label "ECO VIS1.8A turnover bridge"
    if ($bridgeOutput -notmatch 'ECO\.VIS1\.8A turnover bridge: PASS') { throw "ECO VIS1.8A turnover bridge PASS marker missing" }
    Write-Host "ECO.VIS1.8A turnover bridge gate: PASS"

    $fieldOutput = Invoke-GodotProcess -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis1_8a_population_turnover_field.gd") -Label "ECO VIS1.8A headless scene smoke"
    if ($fieldOutput -notmatch 'ECO\.VIS1\.8A headless scene smoke: PASS') { throw "ECO VIS1.8A scene PASS marker missing" }
    Write-Host "ECO.VIS1.8A automated gate: PASS"
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
