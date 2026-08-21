param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedP46ValidationBlob = "d2bcd0342c882ef9c2c161ddef949c2ea0d0e8fc"
$ExpectedP46KernelBlob = "5ce5aa88549c171eeda92b6d6f3202ff5c44c6b1"
$ExpectedP46FixtureBlob = "dc55b886c057e2ccd8f454658b6be58d579642e1"
$ExpectedP46IntegrationBlob = "1924202c9ba98ccc5e867529fda1d328b9d746ce"
$ExpectedP46RunnerBlob = "bd65dd9df5b964f0c930814e97c160520033adc2"
$ExpectedP46UnitAggregate = "88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2"
$ExpectedP46IntegrationHash = "f8191c46658f345e54c85c61b29059939bbf9c7decda2892b9ef62e733a27bdf"
$ExpectedSoakTestBlob = "49821079787479212feb78a10a4703bc52ba89b3"
$ExpectedRegions = 8
$ExpectedCycles = 12
$ExpectedHandoffs = 4
$ExpectedEcologyGenerationSteps = 8
$ExpectedSaveLoads = 12
$ExpectedClientUpdates = 12
$ExpectedInterestProjections = 14
$ExpectedRestarts = 3
$MaxRemainingDueSteps = 1
$GodotTimeoutSeconds = 600
$HeartbeatSeconds = 10
$GodotProjectRoot = $null

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH: expected=$ExpectedGodot actual=$version" }

function Assert-Blob([string]$Path, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object $Path).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to hash $Path" }
    if ($actual -ne $Expected) { throw "BLOB_MISMATCH: path=$Path expected=$Expected actual=$actual" }
}

function New-IsolatedGodotProject() {
    $projectRoot = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        ("dws-eco-p47-project-{0}" -f [Guid]::NewGuid().ToString("N"))
    )
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

    foreach ($name in @("scripts", "tests")) {
        $target = Join-Path $RootDir $name
        if (-not (Test-Path -LiteralPath $target -PathType Container)) {
            throw "Required ECO resource directory missing: $target"
        }
        $link = Join-Path $projectRoot $name
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        if (-not (Test-Path -LiteralPath $link -PathType Container)) {
            throw "Unable to create ECO isolated project junction: $link -> $target"
        }
    }

    $projectConfig = @'
config_version=5

[application]
config/name="DWS ECO P4.7 Isolated Test"
config/features=PackedStringArray("4.7", "Double Precision")

[debug]
gdscript/warnings/treat_warnings_as_errors=false
'@
    Set-Content -LiteralPath (Join-Path $projectRoot "project.godot") -Value $projectConfig -Encoding ASCII
    return $projectRoot
}

function Remove-IsolatedGodotProject([string]$ProjectRoot) {
    if ([string]::IsNullOrWhiteSpace($ProjectRoot) -or -not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        return
    }
    foreach ($name in @("scripts", "tests")) {
        $link = Join-Path $ProjectRoot $name
        if (Test-Path -LiteralPath $link) {
            try { & cmd.exe /c rmdir `"$link`" 2>&1 | Out-Null } catch { }
        }
    }
    try { Remove-Item -LiteralPath $ProjectRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

Assert-Blob "validation/ecology/eco-p4-6-client-read-model-validation.json" $ExpectedP46ValidationBlob
Assert-Blob "scripts/ecology/production/ecology_client_read_model_v1.gd" $ExpectedP46KernelBlob
Assert-Blob "tests/ecology/production/support/eco_p4_fixture_v1.gd" $ExpectedP46FixtureBlob
Assert-Blob "tests/ecology/production/eco_p4_6_real_integration_acceptance.gd" $ExpectedP46IntegrationBlob
Assert-Blob "RUN_ECO_P4_6_TESTS.ps1" $ExpectedP46RunnerBlob
Assert-Blob "tests/ecology/production/eco_p4_7_production_integration_soak.gd" $ExpectedSoakTestBlob

$p46ValidationPath = Join-Path $RootDir "validation/ecology/eco-p4-6-client-read-model-validation.json"
$p46Validation = Get-Content -LiteralPath $p46ValidationPath -Raw | ConvertFrom-Json
if (-not ([string]$p46Validation.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P4.6 parent is not ACCEPTED: status=$($p46Validation.status)"
}
if ([string]$p46Validation.acceptance_evidence.unit.aggregate_hash -ne $ExpectedP46UnitAggregate) {
    throw "P4.6 accepted unit aggregate mismatch"
}
if ([string]$p46Validation.acceptance_evidence.real_integration.integration_hash -ne $ExpectedP46IntegrationHash) {
    throw "P4.6 accepted real integration hash mismatch"
}

function Invoke-GodotTimed([string]$Label, [string]$ScriptPath, [bool]$CheckOnly = $false) {
    Write-Host "=== $Label ==="
    if ([string]::IsNullOrWhiteSpace($GodotProjectRoot) -or -not (Test-Path -LiteralPath $GodotProjectRoot -PathType Container)) {
        throw "Isolated Godot test project is unavailable"
    }
    $process = $null
    $stopwatch = $null
    $progressPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        ("dws-eco-p47-{0}.txt" -f [Guid]::NewGuid().ToString("N"))
    )
    try {
        Set-Content -LiteralPath $progressPath -Value "starting" -Encoding ASCII
        $argumentText = "--headless --path `"$GodotProjectRoot`""
        if ($CheckOnly) { $argumentText += " --check-only" }
        $argumentText += " --script `"$ScriptPath`""
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $GodotPath
        $startInfo.Arguments = $argumentText
        $startInfo.WorkingDirectory = $GodotProjectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables["ECO_P4_7_PROGRESS_FILE"] = $progressPath
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw "$Label failed to start Godot" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $nextHeartbeat = $HeartbeatSeconds
        while (-not $process.WaitForExit(1000)) {
            $elapsed = [int][Math]::Floor($stopwatch.Elapsed.TotalSeconds)
            if ($elapsed -ge $nextHeartbeat) {
                $phase = ""
                try {
                    if (Test-Path -LiteralPath $progressPath -PathType Leaf) {
                        $phase = (Get-Content -LiteralPath $progressPath -Raw -ErrorAction Stop).Trim()
                    }
                }
                catch { }
                if ([string]::IsNullOrWhiteSpace($phase)) {
                    Write-Host ("... {0} still running ({1}s elapsed)" -f $Label, $elapsed)
                }
                else {
                    Write-Host ("... {0} still running ({1}s elapsed) phase={2}" -f $Label, $elapsed, $phase)
                }
                $nextHeartbeat += $HeartbeatSeconds
            }
            if ($stopwatch.Elapsed.TotalSeconds -ge $GodotTimeoutSeconds) {
                try { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null } catch { }
                try { $process.WaitForExit() } catch { }
                throw "$Label timed out after $GodotTimeoutSeconds seconds; Godot process tree terminated"
            }
        }
        $process.WaitForExit()
        $stopwatch.Stop()
        $stdoutText = [string]$stdoutTask.Result
        $stderrText = [string]$stderrTask.Result
        if (-not [string]::IsNullOrEmpty($stdoutText)) { Write-Host $stdoutText.TrimEnd() }
        if (-not [string]::IsNullOrEmpty($stderrText)) { Write-Host $stderrText.TrimEnd() }
        $joined = ($stdoutText + $stderrText).Trim()
        $exitCode = [int]$process.ExitCode
        if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
        if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
        return $joined
    }
    finally {
        if ($null -ne $stopwatch -and $stopwatch.IsRunning) { $stopwatch.Stop() }
        if ($null -ne $process) { $process.Dispose() }
        try { Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue } catch { }
    }
}

Write-Host "=== ECO P4.6 accepted parent identity ==="
Write-Host "ECO.P4.6 accepted parent identity: PASS"
Write-Host "ECO.P4.6 accepted unit aggregate=$ExpectedP46UnitAggregate"
Write-Host "ECO.P4.6 accepted integration hash=$ExpectedP46IntegrationHash"

$GodotProjectRoot = New-IsolatedGodotProject
Write-Host "ECO.P4.7 isolated headless Godot project: PASS"
Write-Host "ECO.P4.7 isolated project has no gameplay/MCP autoloads"
try {
    $null = Invoke-GodotTimed "ECO P4.7 bounded rotating soak parser/preload preflight" "res://tests/ecology/production/eco_p4_7_production_integration_soak.gd" $true
    $runA = Invoke-GodotTimed "ECO P4.7 bounded rotating production soak A" "res://tests/ecology/production/eco_p4_7_production_integration_soak.gd"
    $runB = Invoke-GodotTimed "ECO P4.7 bounded rotating production soak fresh process B" "res://tests/ecology/production/eco_p4_7_production_integration_soak.gd"
    if ($runA -ne $runB) { throw "P4.7 soak fresh-process logs are not byte-identical" }
    if ($runA -notmatch 'ECO\.P4\.7 Bounded Rotating Production Integration Soak: PASS') { throw "P4.7 bounded rotating soak did not report PASS" }

    $soak = [regex]::Match($runA, 'soak_hash=([0-9a-f]{64})')
    $interest = [regex]::Match($runA, 'final_interest_hash=([0-9a-f]{64})')
    $handoffs = [regex]::Match($runA, 'handoff_count=([0-9]+)')
    $ecologySteps = [regex]::Match($runA, 'ecology_generation_steps=([0-9]+)')
    $saves = [regex]::Match($runA, 'save_load_count=([0-9]+)')
    $updates = [regex]::Match($runA, 'client_update_count=([0-9]+)')
    $projections = [regex]::Match($runA, 'interest_projection_count=([0-9]+)')
    $restarts = [regex]::Match($runA, 'restart_count=([0-9]+)')
    $debt = [regex]::Match($runA, 'max_remaining_due_steps=([0-9]+)')
    $regions = [regex]::Match($runA, 'region_count=([0-9]+)')
    $cycles = [regex]::Match($runA, 'cycles=([0-9]+)')
    foreach ($match in @($soak,$interest,$handoffs,$ecologySteps,$saves,$updates,$projections,$restarts,$debt,$regions,$cycles)) {
        if (-not $match.Success) { throw "Unable to parse P4.7 bounded rotating soak output" }
    }
    if ([int]$regions.Groups[1].Value -ne $ExpectedRegions) { throw "P4.7 region count mismatch" }
    if ([int]$cycles.Groups[1].Value -ne $ExpectedCycles) { throw "P4.7 cycle count mismatch" }
    if ([int]$handoffs.Groups[1].Value -ne $ExpectedHandoffs) { throw "P4.7 handoff count mismatch" }
    if ([int]$ecologySteps.Groups[1].Value -ne $ExpectedEcologyGenerationSteps) { throw "P4.7 deep ecology generation count mismatch" }
    if ([int]$saves.Groups[1].Value -ne $ExpectedSaveLoads) { throw "P4.7 save/load count mismatch" }
    if ([int]$updates.Groups[1].Value -ne $ExpectedClientUpdates) { throw "P4.7 client update count mismatch" }
    if ([int]$projections.Groups[1].Value -ne $ExpectedInterestProjections) { throw "P4.7 interest projection count mismatch" }
    if ([int]$restarts.Groups[1].Value -ne $ExpectedRestarts) { throw "P4.7 restart count mismatch" }
    if ([int]$debt.Groups[1].Value -gt $MaxRemainingDueSteps) { throw "P4.7 catch-up debt exceeded bound" }

    Write-Host "ECO.P4.6 accepted parent identity: PASS"
    Write-Host "ECO.P4.7 bounded rotating production soak fresh-process determinism: PASS"
    Write-Host "ECO.P4.7 soak_hash=$($soak.Groups[1].Value)"
    Write-Host "ECO.P4.7 final_interest_hash=$($interest.Groups[1].Value)"
    Write-Host "ECO.P4.7 handoff_count=$($handoffs.Groups[1].Value)"
    Write-Host "ECO.P4.7 ecology_generation_steps=$($ecologySteps.Groups[1].Value)"
    Write-Host "ECO.P4.7 save_load_count=$($saves.Groups[1].Value)"
    Write-Host "ECO.P4.7 client_update_count=$($updates.Groups[1].Value)"
    Write-Host "ECO.P4.7 interest_projection_count=$($projections.Groups[1].Value)"
    Write-Host "ECO.P4.7 restart_count=$($restarts.Groups[1].Value)"
    Write-Host "ECO.P4.7 max_remaining_due_steps=$($debt.Groups[1].Value)"
    Write-Host "ECO.P4.7 canonical automated gates: PASS"
}
finally {
    Remove-IsolatedGodotProject $GodotProjectRoot
}
