param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedParentP45 = "c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419"
$ExpectedP45KernelBlob = "2a4083fb9d4b55f8c16421c4f3555c19a952711f"
$ExpectedP45TestBlob = "041e7e81588f59b54bac76d7cd9ad558d054b0de"
$ExpectedP45RunnerBlob = "b712fb2ac1bda03dffdbaff4eee435f60cf236d5"
$ExpectedP45ValidationBlob = "a02f1547c1beea5a49d500304b58ab8c763334ca"
$ExpectedKernelBlob = "5ce5aa88549c171eeda92b6d6f3202ff5c44c6b1"
$ExpectedUnitTestBlob = "9cde3960a37010a15d00c3d8c3c736943c59e7ba"
$ExpectedFixtureBlob = "dc55b886c057e2ccd8f454658b6be58d579642e1"
$ExpectedIntegrationTestBlob = "1924202c9ba98ccc5e867529fda1d328b9d746ce"
$ExpectedAggregate = "88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2"
$ExpectedSummary = "9b3270edcb178dcb681de63223c0d5f5c8c851d90856f94d660e76c125b4521f"
$ExpectedInterest = "875fce66118cc2810755549e3663d92575b4942e8a42dd00bd710c2acdc57864"
$GodotTimeoutSeconds = 600
$HeartbeatSeconds = 10

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH: expected=$ExpectedGodot actual=$version" }

$parentValidationPath = Join-Path $RootDir "validation/ecology/eco-p4-5-region-ownership-validation.json"
if (-not (Test-Path -LiteralPath $parentValidationPath -PathType Leaf)) { throw "P4.5 validation missing" }
$parentValidation = Get-Content -LiteralPath $parentValidationPath -Raw | ConvertFrom-Json
if (-not ([string]$parentValidation.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P4.5 parent is not ACCEPTED: status=$($parentValidation.status)"
}
if ([string]$parentValidation.acceptance_evidence.aggregate_hash -ne $ExpectedParentP45) {
    throw "P4.5 accepted aggregate mismatch"
}

function Assert-Blob([string]$Path, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object $Path).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to hash $Path" }
    if ($actual -ne $Expected) { throw "BLOB_MISMATCH: path=$Path expected=$Expected actual=$actual" }
}
Assert-Blob "scripts/ecology/production/ecology_region_ownership_v1.gd" $ExpectedP45KernelBlob
Assert-Blob "tests/ecology/production/eco_p4_5_region_ownership_acceptance.gd" $ExpectedP45TestBlob
Assert-Blob "RUN_ECO_P4_5_TESTS.ps1" $ExpectedP45RunnerBlob
Assert-Blob "validation/ecology/eco-p4-5-region-ownership-validation.json" $ExpectedP45ValidationBlob
Assert-Blob "scripts/ecology/production/ecology_client_read_model_v1.gd" $ExpectedKernelBlob
Assert-Blob "tests/ecology/production/eco_p4_6_client_read_model_acceptance.gd" $ExpectedUnitTestBlob
Assert-Blob "tests/ecology/production/support/eco_p4_fixture_v1.gd" $ExpectedFixtureBlob
Assert-Blob "tests/ecology/production/eco_p4_6_real_integration_acceptance.gd" $ExpectedIntegrationTestBlob

function Invoke-GodotTimed([string]$Label, [string]$ScriptPath, [bool]$CheckOnly = $false) {
    Write-Host "=== $Label ==="
    $process = $null
    $stopwatch = $null
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
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $nextHeartbeat = $HeartbeatSeconds
        while (-not $process.WaitForExit(1000)) {
            $elapsed = [int][Math]::Floor($stopwatch.Elapsed.TotalSeconds)
            if ($elapsed -ge $nextHeartbeat) {
                Write-Host ("... {0} still running ({1}s elapsed)" -f $Label, $elapsed)
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
    }
}

Write-Host "=== ECO P4.5 accepted parent identity ==="
Write-Host "ECO.P4.5 accepted parent identity: PASS"
Write-Host "ECO.P4.5 accepted aggregate=$ExpectedParentP45"

$null = Invoke-GodotTimed "ECO P4.6 unit parser/preload preflight" "res://tests/ecology/production/eco_p4_6_client_read_model_acceptance.gd" $true
$null = Invoke-GodotTimed "ECO P4.6 real integration parser/preload preflight" "res://tests/ecology/production/eco_p4_6_real_integration_acceptance.gd" $true

$runA = Invoke-GodotTimed "ECO P4.6 interest/read model unit A" "res://tests/ecology/production/eco_p4_6_client_read_model_acceptance.gd"
$runB = Invoke-GodotTimed "ECO P4.6 interest/read model unit fresh process B" "res://tests/ecology/production/eco_p4_6_client_read_model_acceptance.gd"
if ($runA -ne $runB) { throw "P4.6 unit fresh-process logs are not byte-identical" }
$aggregate = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$summary = [regex]::Match($runA, 'summary_hash=([0-9a-f]{64})')
$interest = [regex]::Match($runA, 'interest_hash=([0-9a-f]{64})')
$parent = [regex]::Match($runA, 'parent_p4_5=([0-9a-f]{64})')
foreach ($match in @($aggregate,$summary,$interest,$parent)) { if (-not $match.Success) { throw "Unable to parse P4.6 unit output" } }
if ($aggregate.Groups[1].Value -ne $ExpectedAggregate) { throw "P4.6 unit aggregate mismatch" }
if ($summary.Groups[1].Value -ne $ExpectedSummary) { throw "P4.6 unit summary hash mismatch" }
if ($interest.Groups[1].Value -ne $ExpectedInterest) { throw "P4.6 unit interest hash mismatch" }
if ($parent.Groups[1].Value -ne $ExpectedParentP45) { throw "P4.6 unit parent P4.5 mismatch" }

$integrationA = Invoke-GodotTimed "ECO P4.6 real P4.5 integration A" "res://tests/ecology/production/eco_p4_6_real_integration_acceptance.gd"
$integrationB = Invoke-GodotTimed "ECO P4.6 real P4.5 integration fresh process B" "res://tests/ecology/production/eco_p4_6_real_integration_acceptance.gd"
if ($integrationA -ne $integrationB) { throw "P4.6 real integration fresh-process logs are not byte-identical" }
$integrationHash = [regex]::Match($integrationA, 'integration_hash=([0-9a-f]{64})')
$sourceSummary = [regex]::Match($integrationA, 'source_summary_hash=([0-9a-f]{64})')
$targetSummary = [regex]::Match($integrationA, 'target_summary_hash=([0-9a-f]{64})')
$integrationInterest = [regex]::Match($integrationA, 'interest_hash=([0-9a-f]{64})')
$futureSummary = [regex]::Match($integrationA, 'future_summary_hash=([0-9a-f]{64})')
$restartOwnership = [regex]::Match($integrationA, 'restart_ownership_hash=([0-9a-f]{64})')
$integrationParent = [regex]::Match($integrationA, 'parent_p4_5=([0-9a-f]{64})')
foreach ($match in @($integrationHash,$sourceSummary,$targetSummary,$integrationInterest,$futureSummary,$restartOwnership,$integrationParent)) { if (-not $match.Success) { throw "Unable to parse P4.6 real integration output" } }
if ($integrationParent.Groups[1].Value -ne $ExpectedParentP45) { throw "P4.6 real integration parent mismatch" }

Write-Host "ECO.P4.5 accepted parent identity: PASS"
Write-Host "ECO.P4.6 unit fresh-process determinism: PASS"
Write-Host "ECO.P4.6 unit aggregate_hash=$($aggregate.Groups[1].Value)"
Write-Host "ECO.P4.6 unit summary_hash=$($summary.Groups[1].Value)"
Write-Host "ECO.P4.6 unit interest_hash=$($interest.Groups[1].Value)"
Write-Host "ECO.P4.6 real integration fresh-process determinism: PASS"
Write-Host "ECO.P4.6 integration_hash=$($integrationHash.Groups[1].Value)"
Write-Host "ECO.P4.6 source_summary_hash=$($sourceSummary.Groups[1].Value)"
Write-Host "ECO.P4.6 target_summary_hash=$($targetSummary.Groups[1].Value)"
Write-Host "ECO.P4.6 integration_interest_hash=$($integrationInterest.Groups[1].Value)"
Write-Host "ECO.P4.6 future_summary_hash=$($futureSummary.Groups[1].Value)"
Write-Host "ECO.P4.6 restart_ownership_hash=$($restartOwnership.Groups[1].Value)"
Write-Host "ECO.P4.6 parent_p4_5=$($integrationParent.Groups[1].Value)"
Write-Host "ECO.P4.6 candidate automated gates: PASS"
