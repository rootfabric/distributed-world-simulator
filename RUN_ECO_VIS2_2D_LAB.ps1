param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis2-2d-lab-" + [Guid]::NewGuid().ToString("N"))

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable not found: $GodotPath" }
    $versionOutput = (& $GodotPath --version 2>&1 | Out-String).Trim()
    Write-Host $versionOutput
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) { throw "ECO VIS2.2-D requires exact Godot $ExpectedGodotVersion" }

    $projectConfig = @"
[application]
config/name="ECO VIS2.2-D Integrated Replicated Observatory"
run/main_scene="res://scenes/labs/ecology/eco_vis2_2_integrated_observatory_lab.tscn"
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

    Write-Host "=== ECO VIS2.2-D Integrated Replicated Observatory ==="
    Write-Host "replicates=default 8 paired Control/Treatment trajectories"
    Write-Host "visible_world=exactly one selected Treatment realtime LOD population"
    Write-Host "data_only=all Controls + all nonselected Treatments"
    Write-Host "observatory=aggregate mean/range/consensus + selected replicate"
    Write-Host "selection=[ / ] presentation-only; aggregate/root/generation must remain unchanged"
    Write-Host "fork=F | next=Right | play/pause=Space | restart=R"
    Write-Host "treatment=2 drought | 3 flood | 4 nutrient | 5 shade | -/+ intensity"
    Write-Host "progressive_PH5=OFF after replicated fork | whole-field PH5 rebuild=DISABLED"
    Write-Host "launch_mode=ISOLATED_NO_REPOSITORY_AUTOLOADS"
    Write-Host "Close the Godot window to return to PowerShell."

    $process = Start-Process -FilePath $GodotPath -ArgumentList @("--path", $TempRoot, "res://scenes/labs/ecology/eco_vis2_2_integrated_observatory_lab.tscn") -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "ECO VIS2.2-D graphical lab exited with code $($process.ExitCode)" }
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
