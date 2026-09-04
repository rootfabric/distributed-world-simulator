param(
    [Alias('GodotPath')]
    [string]$GodotBin = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedGodot = '4.7.1.stable.double.custom_build.a13da4feb'
$ExpectedBase = '07bffc0e7f30bac4479f1b7e53dee3fee3a818f6'
$ExpectedContractBlob = 'b076784f6b4016a0191e937c4e6ada1fe90c783b'
$ContractPath = 'config/ecology/eco-evo7-perf2-measurement-contract.v1.json'

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}

$ActualGodot = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($ActualGodot -ne $ExpectedGodot) {
    throw "ECO.EVO7 PERF2.1 BLOCKED: expected Godot '$ExpectedGodot', got '$ActualGodot'"
}

$Head = (& git -C $Root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve exact PERF2.1 HEAD' }
$Tree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve exact PERF2.1 TREE' }

& git -C $Root merge-base --is-ancestor $ExpectedBase $Head
if ($LASTEXITCODE -ne 0) {
    throw "PERF2.1 BASE MISMATCH: expected accepted PERF2.0 control base $ExpectedBase to be ancestor of $Head"
}

$ContractBlob = (& git -C $Root rev-parse "HEAD:$ContractPath").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve accepted PERF2.0 contract blob' }
if ($ContractBlob -ne $ExpectedContractBlob) {
    throw "PERF2.1 CONTRACT DRIFT: expected blob $ExpectedContractBlob, got $ContractBlob"
}
& git -C $Root diff --quiet -- $ContractPath
if ($LASTEXITCODE -ne 0) {
    throw 'PERF2.1 CONTRACT WORKTREE DRIFT: accepted contract has local modifications'
}

$ProtectedDiff = @(& git -C $Root diff --name-only "$ExpectedBase...$Head" -- 'scripts/ecology/shadow' 'scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd' 'scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd' 'scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd' 'scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd')
if ($LASTEXITCODE -ne 0) { throw 'Unable to evaluate PERF2.1 protected runtime diff' }
if ($ProtectedDiff.Count -gt 0) {
    $ProtectedDiff | ForEach-Object { Write-Host "PROTECTED_RUNTIME_CHANGE=$_" }
    throw 'PERF2.1 is measurement-only: accepted ecology/STREAM1/PERF2.0 runtime must not change'
}

$HostDescriptor = @(
    'windows',
    [Environment]::OSVersion.VersionString,
    [string]$env:PROCESSOR_ARCHITECTURE,
    [string]$env:PROCESSOR_IDENTIFIER,
    [Environment]::ProcessorCount.ToString(),
    "powershell-$($PSVersionTable.PSVersion.ToString())"
) -join '|'
$Sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $HostBytes = [System.Text.Encoding]::UTF8.GetBytes($HostDescriptor)
    $HostHashBytes = $Sha256.ComputeHash($HostBytes)
}
finally {
    $Sha256.Dispose()
}
$HostFingerprint = -join ($HostHashBytes | ForEach-Object { $_.ToString('x2') })

$env:ECO_PERF2_TARGET_HEAD = $Head
$env:ECO_PERF2_TARGET_TREE = $Tree
$env:ECO_PERF2_HOST_FINGERPRINT = $HostFingerprint

Write-Host "PERF2.1 exact target HEAD=$Head"
Write-Host "PERF2.1 exact target TREE=$Tree"
Write-Host "PERF2.1 accepted base=$ExpectedBase"
Write-Host "PERF2.1 Godot=$ActualGodot"
Write-Host "PERF2.1 frozen contract blob=$ContractBlob"
Write-Host "PERF2.1 host fingerprint=$HostFingerprint"
Write-Host 'PERF2.1 protected runtime diff=PASS'

$LogRoot = Join-Path $Root 'artifacts\perf21_gate_logs'
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$Tests = @(
    @{ Name = 'PERF1';   Script = 'res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd' },
    @{ Name = 'STREAM1'; Script = 'res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd' },
    @{ Name = 'PERF2.0'; Script = 'res://tests/ecology/eco_evo7_perf2_measurement_contract_acceptance.gd' },
    @{ Name = 'PERF2.1'; Script = 'res://tests/ecology/eco_evo7_perf21_generation_profiling_acceptance.gd' }
)

foreach ($Entry in $Tests) {
    $Log = Join-Path $LogRoot (($Entry.Name -replace '\.','_') + '.log')
    Write-Host "PERF2.1 GATE START $($Entry.Name)"
    & $GodotBin --headless --path $Root --log-file $Log --script $Entry.Script
    if ($LASTEXITCODE -ne 0) {
        Write-Host "PERF2.1 GATE FAIL $($Entry.Name) log=$Log"
        exit $LASTEXITCODE
    }
    Write-Host "PERF2.1 GATE PASS $($Entry.Name)"
}

$ReportPath = Join-Path $Root 'artifacts\perf2\perf2-1-generation-profile-r2.json'
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "PERF2.1 report missing: $ReportPath"
}
$Report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
if ($Report.schema -ne 'distributed_world_simulator.ecology.evo7_perf2.measurement_report.v1') {
    throw "PERF2.1 report schema mismatch: $($Report.schema)"
}
if ($Report.profile_schema -ne 'distributed_world_simulator.ecology.evo7_perf2_1.generation_profile.v2') {
    throw "PERF2.1 profile schema mismatch: $($Report.profile_schema)"
}
if (@($Report.samples).Count -ne 12) { throw 'PERF2.1 report must contain 12 samples' }
if (@($Report.summaries).Count -ne 32) { throw 'PERF2.1 report must contain 32 summaries' }
if (@($Report.comparisons).Count -ne 3) { throw 'PERF2.1 report must contain 3 chunk comparisons' }
$BadComparison = @($Report.comparisons | Where-Object { [int]$_.exact_pairs -ne 3 -or [bool]$_.optimization_claim })
if ($BadComparison.Count -ne 0) { throw 'PERF2.1 report comparison parity/claim policy mismatch' }

Write-Host "PERF2_1_REPORT_SAMPLES=$(@($Report.samples).Count)"
Write-Host "PERF2_1_REPORT_SUMMARIES=$(@($Report.summaries).Count)"
Write-Host "PERF2_1_REPORT_COMPARISONS=$(@($Report.comparisons).Count)"
Write-Host "PERF2_1_REPORT_HASH=$($Report.report_hash)"
foreach ($Comparison in @($Report.comparisons)) {
    Write-Host ("PERF2_1_RATIO chunk={0} wall={1:N6} generation={2:N6}" -f [int]$Comparison.stream_chunk_size, [double]$Comparison.observed_wall_ratio_serial_over_stream, [double]$Comparison.observed_generation_ratio_serial_over_stream)
}

$FinalHead = (& git -C $Root rev-parse HEAD).Trim()
$FinalTree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()
if ($FinalHead -ne $Head) { throw "PERF2.1 HEAD moved during gate: $FinalHead != $Head" }
if ($FinalTree -ne $Tree) { throw "PERF2.1 TREE moved during gate: $FinalTree != $Tree" }
$Tracked = @(& git -C $Root status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) { throw 'Unable to read final PERF2.1 git status' }
if ($Tracked.Count -gt 0) {
    $Tracked | ForEach-Object { Write-Host $_ }
    throw 'PERF2.1 tracked worktree changed during gate'
}

Write-Host 'ECO.EVO7 PERF2.1 transitive generation-profiling R2 acceptance: PASS'
exit 0
