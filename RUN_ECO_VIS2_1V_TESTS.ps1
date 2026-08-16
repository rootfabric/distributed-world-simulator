param(
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-eco-vis2-1v-" + [Guid]::NewGuid().ToString("N"))

$GodotShutdownLeakPatterns = @(
    '(?im)ObjectDB instance(?:s)?\s+(?:was|were)\s+leaked at exit',
    '(?im)^\s*(?:WARNING:|ERROR:)?\s*\d+\s+RID(?:s|\s+allocations)?\s+of\s+type\b[^\r\n]*\b(?:was|were)\s+leaked(?:\s+at\s+exit)?\.?\s*$',
    '(?im)^Leaked\b',
    '(?im)^Resource still in use:',
    '(?im)resources? still in use at exit',
    '(?im)^Orphan StringName:',
    '(?im)^StringName:\s+\d+\s+unclaimed string names at exit\.?$',
    '(?im)^WARNING:[^\r\n]*(?:\bleak(?:ed|s|ing)?\b|\bstill in use\b)[^\r\n]*$'
)

function ConvertTo-ProcessArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Test-GodotShutdownLeakOutput {
    param([string]$Output)
    foreach ($leakPattern in $script:GodotShutdownLeakPatterns) {
        if ($Output -match $leakPattern) {
            return $true
        }
    }
    return $false
}

function Assert-GodotShutdownLeakMatcherCoverage {
    $leakingFixtures = @(
        'WARNING: 1 ObjectDB instance was leaked at exit (run with `--verbose` for details).',
        'WARNING: 1 RID of type "CanvasItem" was leaked.',
        'WARNING: 2 RIDs of type "Texture" were leaked.',
        "ERROR: 3 RID allocations of type 'Example' were leaked at exit.",
        'WARNING: 1 framebuffer cache instance(s) still in use.',
        'WARNING: 1 uniform set cache instance(s) still in use.',
        'Leaked instance: Node:123',
        'Resource still in use: res://example.gd (GDScript)',
        'Orphan StringName: example (static: 0, total: 1)',
        'StringName: 1 unclaimed string names at exit.'
    )
    foreach ($fixture in $leakingFixtures) {
        if (-not (Test-GodotShutdownLeakOutput -Output $fixture)) {
            throw "ECO.VIS2.1-V shutdown leak matcher missed fixture: $fixture"
        }
    }

    $benignFixtures = @(
        'ECO.VIS2.1-V Treatment realtime LOD: PASS (25 assertions)',
        'WARNING: Started the engine as `root`/superuser. This is a security risk.'
    )
    foreach ($fixture in $benignFixtures) {
        if (Test-GodotShutdownLeakOutput -Output $fixture) {
            throw "ECO.VIS2.1-V shutdown leak matcher false-positive fixture: $fixture"
        }
    }

    Write-Host "ECO.VIS2.1-V shutdown leak matcher coverage: PASS"
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
            try { $process.Kill() } catch { Write-Warning "$Label timed out and Kill() reported: $($_.Exception.Message)" }
            $process.WaitForExit()
            $combined = (($stdoutTask.Result) + [Environment]::NewLine + ($stderrTask.Result)).Trim()
            if ($combined) { Write-Host $combined }
            throw "$Label timed out after $TimeoutSeconds seconds"
        }
        $process.WaitForExit()
        $combined = (($stdoutTask.Result) + [Environment]::NewLine + ($stderrTask.Result)).Trim()
        if ($combined) { Write-Host $combined }
        if ($process.ExitCode -ne 0) { throw "$Label failed with exit code $($process.ExitCode)" }
        if ($combined -match '(?m)^SCRIPT ERROR:' -or $combined -match '(?m)^ERROR:' -or $combined -match '(?i)Parse Error') {
            throw "$Label emitted Godot error output despite zero exit code"
        }

        # Godot can report shutdown ownership/resource/RID leaks as WARNING while
        # still returning exit code 0. Keep this check independent of --verbose so
        # a future harness change cannot silently turn a leaking smoke green again.
        if (Test-GodotShutdownLeakOutput -Output $combined) {
            throw "$Label emitted Godot shutdown leak diagnostics despite zero exit code"
        }

        if ($PassMarker -and $combined -notmatch $PassMarker) { throw "$Label PASS marker missing: $PassMarker" }
        return $combined
    }
    finally { $process.Dispose() }
}

try {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable not found: $GodotPath" }
    Write-Host "=== ECO VIS2.1-V Treatment Realtime LOD gate ==="
    Write-Host "repo_root=$RepoRoot"
    Write-Host "godot=$GodotPath"

    Assert-GodotShutdownLeakMatcherCoverage

    $versionOutput = Invoke-GodotProcess -Arguments @("--version") -Label "ECO VIS2.1-V Godot version check"
    if ($versionOutput -notmatch [Regex]::Escape($ExpectedGodotVersion)) { throw "ECO VIS2.1-V requires exact Godot $ExpectedGodotVersion" }
    Write-Host "ECO.VIS2.1-V exact Godot identity: PASS"

    $vis21Runner = Join-Path $RepoRoot "RUN_ECO_VIS2_1_TESTS.ps1"
    if (-not (Test-Path -LiteralPath $vis21Runner -PathType Leaf)) { throw "Validated VIS2.1 runner missing: $vis21Runner" }
    Write-Host ">> ECO VIS2.1 validated causal/boundedness regression gate"
    & $vis21Runner -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "VIS2.1 regression runner failed with exit code $LASTEXITCODE" }
    Write-Host "ECO.VIS2.1 validated regression gate: PASS"

    $projectConfig = @"
[application]
config/name="ECO VIS2.1-V Treatment Realtime LOD Isolated Gate"
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
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

    $testRelative = "tests\research\ecology\test_eco_vis2_1v_treatment_realtime_lod_lab.gd"
    $testSource = Join-Path $RepoRoot $testRelative
    $testTarget = Join-Path $TempRoot $testRelative
    if (-not (Test-Path -LiteralPath $testSource -PathType Leaf)) { throw "VIS2.1-V test missing: $testSource" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $testTarget) -Force | Out-Null
    Copy-Item -LiteralPath $testSource -Destination $testTarget -Force
    Write-Host "ECO.VIS2.1-V isolated ecology dependency graph: PASS"

    Invoke-GodotProcess `
        -Arguments @("--headless", "--path", $TempRoot, "--check-only", "--script", "res://tests/research/ecology/test_eco_vis2_1v_treatment_realtime_lod_lab.gd") `
        -Label "ECO VIS2.1-V parser preflight" `
        -TimeoutSeconds 240 | Out-Null
    Write-Host "ECO.VIS2.1-V parser preflight: PASS"

    Write-Host "ECO.VIS2.1-V shutdown leak gate: STRICT (ObjectDB + RID + resources + StringName + verbose smoke)"
    $output = Invoke-GodotProcess `
        -Arguments @("--verbose", "--headless", "--path", $TempRoot, "--script", "res://tests/research/ecology/test_eco_vis2_1v_treatment_realtime_lod_lab.gd") `
        -Label "ECO VIS2.1-V Treatment realtime LOD smoke" `
        -TimeoutSeconds 300 `
        -PassMarker 'ECO\.VIS2\.1-V Treatment realtime LOD: PASS'
    Write-Host "ECO.VIS2.1-V automated gate: PASS"
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
