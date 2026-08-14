param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedP46KernelBlob = "5ce5aa88549c171eeda92b6d6f3202ff5c44c6b1"
$ExpectedP46FixtureBlob = "dc55b886c057e2ccd8f454658b6be58d579642e1"
$ExpectedP46IntegrationBlob = "1924202c9ba98ccc5e867529fda1d328b9d746ce"
$ExpectedP46RunnerBlob = "2a903df63715d6f383ec2f4d4b58ead55af121ae"
$ExpectedSoakTestBlob = "2a996a58a72d3f9d6e8a81851d8a8e0abaa3ffd2"
$ExpectedParentP45 = "c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419"
$GodotTimeoutSeconds = 600

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH: expected=$ExpectedGodot actual=$version" }

$p46ValidationPath = Join-Path $RootDir "validation/ecology/eco-p4-6-client-read-model-validation.json"
if (-not (Test-Path -LiteralPath $p46ValidationPath -PathType Leaf)) { throw "P4.6 validation missing" }
$p46Validation = Get-Content -LiteralPath $p46ValidationPath -Raw | ConvertFrom-Json
$p46Status = [string]$p46Validation.status
if (-not ($p46Status.StartsWith("CANDIDATE", [System.StringComparison]::Ordinal) -or $p46Status.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal))) {
    throw "P4.6 is not a valid pre-acceptance parent: status=$p46Status"
}
if ([string]$p46Validation.parent.expected_aggregate_hash -ne $ExpectedParentP45 -and [string]$p46Validation.parent.accepted_aggregate_hash -ne $ExpectedParentP45) {
    throw "P4.6 parent P4.5 aggregate mismatch"
}

function Assert-Blob([string]$Path, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object $Path).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to hash $Path" }
    if ($actual -ne $Expected) { throw "BLOB_MISMATCH: path=$Path expected=$Expected actual=$actual" }
}
Assert-Blob "scripts/ecology/production/ecology_client_read_model_v1.gd" $ExpectedP46KernelBlob
Assert-Blob "tests/ecology/production/support/eco_p4_fixture_v1.gd" $ExpectedP46FixtureBlob
Assert-Blob "tests/ecology/production/eco_p4_6_real_integration_acceptance.gd" $ExpectedP46IntegrationBlob
Assert-Blob "RUN_ECO_P4_6_TESTS.ps1" $ExpectedP46RunnerBlob
Assert-Blob "tests/ecology/production/eco_p4_7_production_integration_soak.gd" $ExpectedSoakTestBlob

function Invoke-GodotTimed([string]$Label, [string]$ScriptPath, [bool]$CheckOnly = $false) {
    Write-Host "=== $Label ==="
    $process = $null
    try {
        $argumentText = "--headless --path `"$RootDir`""
        if ($CheckOnly) { $argumentText += " --check-only" }
        $argumentText += " --script `"$ScriptPath`""
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $GodotPath
        $startInfo.Arguments = $argumentText
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw "$Label failed to start Godot" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($GodotTimeoutSeconds * 1000)) {
            try { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null } catch { }
            try { $process.WaitForExit() } catch { }
            throw "$Label timed out after $GodotTimeoutSeconds seconds; Godot process tree terminated"
        }
        $process.WaitForExit()
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
        if ($null -ne $process) { $process.Dispose() }
    }
}

$null = Invoke-GodotTimed "ECO P4.7 accelerated soak parser/preload preflight" "res://tests/ecology/production/eco_p4_7_production_integration_soak.gd" $true
$runA = Invoke-GodotTimed "ECO P4.7 accelerated production soak A" "res://tests/ecology/production/eco_p4_7_production_integration_soak.gd"
$runB = Invoke-GodotTimed "ECO P4.7 accelerated production soak fresh process B" "res://tests/ecology/production/eco_p4_7_production_integration_soak.gd"
if ($runA -ne $runB) { throw "P4.7 soak fresh-process logs are not byte-identical" }

$soak = [regex]::Match($runA, 'soak_hash=([0-9a-f]{64})')
$interest = [regex]::Match($runA, 'final_interest_hash=([0-9a-f]{64})')
$handoffs = [regex]::Match($runA, 'handoff_count=([0-9]+)')
$saves = [regex]::Match($runA, 'save_load_count=([0-9]+)')
$updates = [regex]::Match($runA, 'client_update_count=([0-9]+)')
$projections = [regex]::Match($runA, 'interest_projection_count=([0-9]+)')
$debt = [regex]::Match($runA, 'max_remaining_due_steps=([0-9]+)')
$regions = [regex]::Match($runA, 'region_count=([0-9]+)')
$cycles = [regex]::Match($runA, 'cycles=([0-9]+)')
foreach ($match in @($soak,$interest,$handoffs,$saves,$updates,$projections,$debt,$regions,$cycles)) { if (-not $match.Success) { throw "Unable to parse P4.7 soak output" } }
if ([int]$regions.Groups[1].Value -ne 8) { throw "P4.7 region count mismatch" }
if ([int]$cycles.Groups[1].Value -ne 12) { throw "P4.7 cycle count mismatch" }
if ([int]$saves.Groups[1].Value -ne 96) { throw "P4.7 save/load count mismatch" }
if ([int]$updates.Groups[1].Value -ne 96) { throw "P4.7 client update count mismatch" }
if ([int]$projections.Groups[1].Value -ne 12) { throw "P4.7 interest projection count mismatch" }
if ([int]$debt.Groups[1].Value -gt 8) { throw "P4.7 catch-up debt exceeded bound" }

Write-Host "ECO.P4.7 accelerated production soak fresh-process determinism: PASS"
Write-Host "ECO.P4.7 soak_hash=$($soak.Groups[1].Value)"
Write-Host "ECO.P4.7 final_interest_hash=$($interest.Groups[1].Value)"
Write-Host "ECO.P4.7 handoff_count=$($handoffs.Groups[1].Value)"
Write-Host "ECO.P4.7 save_load_count=$($saves.Groups[1].Value)"
Write-Host "ECO.P4.7 client_update_count=$($updates.Groups[1].Value)"
Write-Host "ECO.P4.7 interest_projection_count=$($projections.Groups[1].Value)"
Write-Host "ECO.P4.7 max_remaining_due_steps=$($debt.Groups[1].Value)"
Write-Host "ECO.P4.7 PRE-ACCEPTANCE automated gates: PASS"
