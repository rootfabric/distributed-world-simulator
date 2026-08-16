param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis2-1-" + [Guid]::NewGuid().ToString("N"))

function Resolve-Godot {
    param([string]$ExplicitPath)
    $candidates = @()
    if ($ExplicitPath) { $candidates += $ExplicitPath }
    if ($env:GODOT4_BIN) { $candidates += $env:GODOT4_BIN }
    if ($env:GODOT_BIN) { $candidates += $env:GODOT_BIN }
    $candidates += @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        (Join-Path $RepoRoot "godot.windows.editor.double.x86_64.console.exe"),
        (Join-Path $RepoRoot "godot.windows.editor.double.x86_64.exe"),
        (Join-Path $RepoRoot "godot.linuxbsd.editor.double.x86_64"),
        (Join-Path $RepoRoot "godot.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $command = Get-Command godot4 -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "Godot executable not found. Pass -GodotPath or set GODOT4_BIN."
}

function ConvertTo-ProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-GodotProcess {
    param(
        [string[]]$Arguments,
        [string]$Label,
        [int]$TimeoutSeconds = 240,
        [string]$PassMarker = ""
    )

    Write-Host ">> $Label"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Godot
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) {
            throw "$Label failed to start Godot"
        }
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

        if ($process.ExitCode -ne 0) {
            throw "$Label failed with exit code $($process.ExitCode)"
        }
        if ($combined -match '(?m)^SCRIPT ERROR:' -or $combined -match '(?m)^ERROR:' -or $combined -match '(?i)Parse Error') {
            throw "$Label emitted Godot error output despite zero exit code"
        }
        if ($PassMarker -and $combined -notmatch $PassMarker) {
            throw "$Label PASS marker missing: $PassMarker"
        }
        return $combined
    }
    finally {
        $process.Dispose()
    }
}

$Godot = Resolve-Godot $GodotPath

try {
    Write-Host "=== ECO VIS2.1 Control vs Treatment isolated gate ==="
    Write-Host "repo_root=$RepoRoot"
    Write-Host "godot=$Godot"

    $versionOutput = Invoke-GodotProcess -Arguments @("--version") -Label "ECO VIS2.1 Godot version check"
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) {
        throw "ECO VIS2.1 requires exact Godot $ExpectedGodotVersion"
    }
    Write-Host "ECO.VIS2.1 exact Godot identity: PASS"

    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\research\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scenes\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "tests\research\ecology") -Force | Out-Null

    $projectConfig = @"
[application]
config/name="ECO VIS2.1 Isolated Gate"
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
        "scenes\labs\ecology\eco_vis1_8a_realtime_turnover_field.tscn",
        "scenes\labs\ecology\eco_vis1_8b_continuous_population_field.tscn",
        "scenes\labs\ecology\eco_vis1_9_evolution_observatory.tscn",
        "scenes\labs\ecology\eco_vis2_0_evolution_experiment_lab.tscn",
        "scenes\labs\ecology\eco_vis2_1_control_vs_treatment_lab.tscn",
        "tests\research\ecology\test_eco_vis1_8b_continuous_population_field.gd",
        "tests\research\ecology\test_eco_vis1_9_evolution_observatory.gd",
        "tests\research\ecology\test_eco_vis2_0_evolution_experiment_lab.gd",
        "tests\research\ecology\test_eco_vis2_1_control_branch_runner.gd",
        "tests\research\ecology\test_eco_vis2_1_treatment_branch_runner.gd",
        "tests\research\ecology\test_eco_vis2_1_comparison_model.gd",
        "tests\research\ecology\test_eco_vis2_1_control_vs_treatment_lab.gd"
    )

    foreach ($relative in $copies) {
        $source = Join-Path $RepoRoot $relative
        $target = Join-Path $TempRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "ECO VIS2.1 required isolated-gate file missing: $source"
        }
        $targetDir = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
    Write-Host "ECO.VIS2.1 isolated project dependency graph: PASS"

    Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--check-only", "--script", "res://tests/research/ecology/test_eco_vis2_1_control_vs_treatment_lab.gd") `
        -Label "ECO VIS2.1 parser preflight" `
        -TimeoutSeconds 240 | Out-Null
    Write-Host "ECO.VIS2.1 parser preflight: PASS"

    $controlOutput = Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis2_1_control_branch_runner.gd") `
        -Label "ECO VIS2.1 CONTROL runner regression" `
        -TimeoutSeconds 240 `
        -PassMarker 'ECO\.VIS2\.1-C control branch runner: PASS'
    Write-Host "ECO.VIS2.1 CONTROL runner gate: PASS"

    $treatmentOutput = Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis2_1_treatment_branch_runner.gd") `
        -Label "ECO VIS2.1 TREATMENT R1 runner regression" `
        -TimeoutSeconds 240 `
        -PassMarker 'ECO\.VIS2\.1-T treatment branch runner R1: PASS'
    Write-Host "ECO.VIS2.1 TREATMENT R1 runner gate: PASS"

    $comparatorOutput = Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis2_1_comparison_model.gd") `
        -Label "ECO VIS2.1 Comparator R1 regression" `
        -TimeoutSeconds 240 `
        -PassMarker 'ECO\.VIS2\.1 comparison model: PASS'
    Write-Host "ECO.VIS2.1 Comparator R1 gate: PASS"

    $vis18bOutput = Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis1_8b_continuous_population_field.gd") `
        -Label "ECO VIS1.8B regression smoke" `
        -TimeoutSeconds 240 `
        -PassMarker 'ECO\.VIS1\.8B headless scene smoke: PASS'
    Write-Host "ECO.VIS1.8B regression gate: PASS"

    $vis19Output = Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis1_9_evolution_observatory.gd") `
        -Label "ECO VIS1.9 regression smoke" `
        -TimeoutSeconds 240 `
        -PassMarker 'ECO\.VIS1\.9 headless scene smoke: PASS'
    Write-Host "ECO.VIS1.9 regression gate: PASS"

    $vis20Output = Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis2_0_evolution_experiment_lab.gd") `
        -Label "ECO VIS2.0 regression smoke" `
        -TimeoutSeconds 240 `
        -PassMarker 'ECO\.VIS2\.0 headless scene smoke: PASS'
    Write-Host "ECO.VIS2.0 regression gate: PASS"

    $vis21Output = Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis2_1_control_vs_treatment_lab.gd") `
        -Label "ECO VIS2.1 integrated rolling-cache long smoke" `
        -TimeoutSeconds 300 `
        -PassMarker 'ECO\.VIS2\.1 control-vs-treatment integration: PASS'
    Write-Host "ECO.VIS2.1 integrated boundedness/performance gate: PASS"

    Write-Host "`nECO VIS2.1 isolated gate: PASS (7 scripts + parser preflight)"
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
