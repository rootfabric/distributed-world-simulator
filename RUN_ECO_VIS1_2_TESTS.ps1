param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis1-2-" + [Guid]::NewGuid().ToString("N"))

function ConvertTo-ProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-GodotProcess {
    param(
        [string[]]$Arguments,
        [string]$Label
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GodotPath
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        throw "$Label failed to start Godot"
    }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $combined = ($stdout + [Environment]::NewLine + $stderr).Trim()
    if ($combined) {
        Write-Host $combined
    }
    if ($process.ExitCode -ne 0) {
        throw "$Label failed with exit code $($process.ExitCode)"
    }
    if ($combined -match '(?m)^SCRIPT ERROR:' -or $combined -match '(?m)^ERROR:') {
        throw "$Label emitted Godot error output despite zero exit code"
    }
    return $combined
}

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw "Godot executable not found: $GodotPath"
    }

    Write-Host "=== ECO VIS1.2 isolated headless gate ==="
    Write-Host "repo_root=$RepoRoot"
    Write-Host "godot=$GodotPath"

    $versionOutput = Invoke-GodotProcess -Arguments @("--version") -Label "ECO VIS1.2 Godot version check"
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) {
        throw "ECO VIS1.2 requires exact Godot $ExpectedGodotVersion"
    }
    Write-Host "ECO.VIS1.2 exact Godot identity: PASS"

    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scripts\research\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "scenes\labs\ecology") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TempRoot "tests\research\ecology") -Force | Out-Null

    $projectConfig = @"
[application]
config/name="ECO VIS1.2 Isolated Gate"

[display]
window/size/viewport_width=1440
window/size/viewport_height=900

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
        @("scripts\research\ecology\environment_sample_v1.gd", "scripts\research\ecology\environment_sample_v1.gd"),
        @("scripts\research\ecology\plant_resource_competition_v1.gd", "scripts\research\ecology\plant_resource_competition_v1.gd"),
        @("scripts\research\ecology\plant_density_carrying_capacity_v1.gd", "scripts\research\ecology\plant_density_carrying_capacity_v1.gd"),
        @("scripts\research\ecology\plant_spatial_dispersal_v1.gd", "scripts\research\ecology\plant_spatial_dispersal_v1.gd"),
        @("scripts\research\ecology\eco_obs1_spatial_snapshot_v1.gd", "scripts\research\ecology\eco_obs1_spatial_snapshot_v1.gd"),
        @("scripts\research\ecology\eco_obs1_spatial_demo_timeline_v1.gd", "scripts\research\ecology\eco_obs1_spatial_demo_timeline_v1.gd"),
        @("scenes\labs\ecology\eco_vis1_2_spatial_projection.tscn", "scenes\labs\ecology\eco_vis1_2_spatial_projection.tscn"),
        @("tests\research\ecology\test_eco_vis1_2_spatial_projection.gd", "tests\research\ecology\test_eco_vis1_2_spatial_projection.gd")
    )
    foreach ($pair in $copies) {
        $source = Join-Path $RepoRoot $pair[0]
        $target = Join-Path $TempRoot $pair[1]
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "ECO VIS1.2 required file missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
    Write-Host "ECO.VIS1.2 isolated project with canonical ecology dependencies: PASS"

    Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--check-only", "--script", "res://tests/research/ecology/test_eco_vis1_2_spatial_projection.gd") `
        -Label "ECO VIS1.2 parser preflight" | Out-Null
    Write-Host "ECO.VIS1.2 parser preflight: PASS"

    $smokeOutput = Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis1_2_spatial_projection.gd") `
        -Label "ECO VIS1.2 headless scene smoke"
    if ($smokeOutput -notmatch 'ECO\.VIS1\.2 headless scene smoke: PASS') {
        throw "ECO VIS1.2 PASS marker missing"
    }

    Write-Host "ECO.VIS1.2 automated gate: PASS"
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
