param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis2-1v-lab-" + [Guid]::NewGuid().ToString("N"))

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable not found: $GodotPath" }
    $versionOutput = (& $GodotPath --version 2>&1 | Out-String).Trim()
    Write-Host $versionOutput
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) { throw "ECO VIS2.1-V requires exact Godot $ExpectedGodotVersion" }

    $projectConfig = @"
[application]
config/name="ECO VIS2.1-V Treatment Realtime LOD"
run/main_scene="res://scenes/labs/ecology/eco_vis2_1v_treatment_realtime_lod_lab.tscn"
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

    foreach ($relativeDir in @("scripts\labs\ecology", "scripts\research\ecology", "scenes\labs\ecology")) {
        $sourceDir = Join-Path $RepoRoot $relativeDir
        $targetDir = Join-Path $TempRoot $relativeDir
        if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { throw "Required ecology directory missing: $sourceDir" }
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetDir) -Force | Out-Null
        Copy-Item -LiteralPath $sourceDir -Destination $targetDir -Recurse -Force
    }

    Write-Host "=== ECO VIS2.1-V Treatment Realtime LOD ==="
    Write-Host "validated_base=VIS2.1 Windows-runtime-validated causal candidate"
    Write-Host "rendering=CONTROL data-only; TREATMENT is the only visible world"
    Write-Host "lod=near detailed realtime proxy <=110m | mid canopy 75..240m | far lightweight canopy >=190m"
    Write-Host "birth_death_animation=retained across realtime LOD tiers"
    Write-Host "progressive_PH5=OFF after fork | whole-field PH5 rebuild=DISABLED"
    Write-Host "source_VIS2.0_panel=hidden after fork to avoid confusing BASELINE source with Treatment"
    Write-Host "launch_mode=ISOLATED_NO_REPOSITORY_AUTOLOADS"
    Write-Host "Close the Godot window to return to PowerShell."

    $process = Start-Process -FilePath $GodotPath -ArgumentList @("--path", $TempRoot, "res://scenes/labs/ecology/eco_vis2_1v_treatment_realtime_lod_lab.tscn") -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "ECO VIS2.1-V graphical lab exited with code $($process.ExitCode)" }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
