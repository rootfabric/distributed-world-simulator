param(
    [Alias('GodotPath')]
    [string]$GodotBin = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedGodot = '4.7.1.stable.double.custom_build.a13da4feb'
$ExpectedBase = '7044c13e8cd9b036f318192ba0d62c6f3393fb60'
$ExpectedContractBlob = 'b076784f6b4016a0191e937c4e6ada1fe90c783b'
$ContractPath = 'config/ecology/eco-evo7-perf2-measurement-contract.v1.json'

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}

$ActualGodot = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($ActualGodot -ne $ExpectedGodot) {
    throw "ECO.EVO7 PERF2.2 BLOCKED: expected Godot '$ExpectedGodot', got '$ActualGodot'"
}

$Head = (& git -C $Root rev-parse HEAD).Trim()
$Tree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()

& git -C $Root merge-base --is-ancestor $ExpectedBase $Head
if ($LASTEXITCODE -ne 0) {
    throw "PERF2.2 BASE MISMATCH: accepted PERF2.1 control tip $ExpectedBase is not an ancestor"
}

$ContractBlob = (& git -C $Root rev-parse "HEAD:$ContractPath").Trim()
if ($ContractBlob -ne $ExpectedContractBlob) {
    throw "PERF2.2 CONTRACT DRIFT: expected $ExpectedContractBlob, got $ContractBlob"
}
& git -C $Root diff --quiet -- $ContractPath
if ($LASTEXITCODE -ne 0) {
    throw 'PERF2.2 CONTRACT WORKTREE DRIFT'
}

$ProtectedDiff = @(& git -C $Root diff --name-only "$ExpectedBase...$Head" -- 'scripts/ecology/shadow' 'scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd' 'scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd' 'scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd' 'scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd' 'scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd')
if ($ProtectedDiff.Count -gt 0) {
    $ProtectedDiff | ForEach-Object { Write-Host "PROTECTED_RUNTIME_CHANGE=$_" }
    throw 'PERF2.2 is derived measurement-only: accepted runtime/profilers must not change'
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
$env:BREAKPOINT_RUNTIME_DISABLED = '1'

Write-Host "PERF2.2 exact target HEAD=$Head"
Write-Host "PERF2.2 exact target TREE=$Tree"
Write-Host "PERF2.2 accepted predecessor=$ExpectedBase"
Write-Host "PERF2.2 Godot=$ActualGodot"
Write-Host "PERF2.2 frozen contract blob=$ContractBlob"
Write-Host "PERF2.2 host fingerprint=$HostFingerprint"
Write-Host 'PERF2.2 protected runtime diff=PASS'

$LogRoot = Join-Path $Root 'artifacts\perf22_gate_logs'
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

Write-Host 'PERF2.2 fresh import START'
& $GodotBin --headless --import --path $Root
if ($LASTEXITCODE -ne 0) {
    throw "PERF2.2 import failed: $LASTEXITCODE"
}
Write-Host 'PERF2.2 fresh import PASS'

$Tests = @(
    @{ Name = 'PERF1';   Script = 'res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd' },
    @{ Name = 'STREAM1'; Script = 'res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd' },
    @{ Name = 'PERF2.0'; Script = 'res://tests/ecology/eco_evo7_perf2_measurement_contract_acceptance.gd' },
    @{ Name = 'PERF2.1'; Script = 'res://tests/ecology/eco_evo7_perf21_generation_profiling_acceptance.gd' },
    @{ Name = 'PERF2.2'; Script = 'res://tests/ecology/eco_evo7_perf22_working_set_memory_acceptance.gd' }
)

foreach ($Entry in $Tests) {
    $Log = Join-Path $LogRoot (($Entry.Name -replace '\.','_') + '.log')
    Write-Host "PERF2.2 GATE START $($Entry.Name)"
    & $GodotBin --headless --path $Root --log-file $Log --script $Entry.Script
    if ($LASTEXITCODE -ne 0) {
        Write-Host "PERF2.2 GATE FAIL $($Entry.Name) log=$Log"
        exit $LASTEXITCODE
    }
    Write-Host "PERF2.2 GATE PASS $($Entry.Name)"
}

$ReportPath = Join-Path $Root 'artifacts\perf2\perf2-2-working-set-memory-r1.json'
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "PERF2.2 report missing: $ReportPath"
}
$Report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
if ($Report.schema -ne 'distributed_world_simulator.ecology.evo7_perf2_2.working_set_memory_report.v1') {
    throw "PERF2.2 report schema mismatch: $($Report.schema)"
}
if (@($Report.working_set_rows).Count -ne 4) { throw 'PERF2.2 report must contain 4 working-set rows' }
if (@($Report.memory_rows).Count -ne 4) { throw 'PERF2.2 report must contain 4 memory rows' }
if (@($Report.comparisons).Count -ne 3) { throw 'PERF2.2 report must contain 3 comparisons' }
$BadComparison = @($Report.comparisons | Where-Object {
    [int]$_.exact_pairs -ne 3 -or
    -not [bool]$_.working_set_bound_claim -or
    [bool]$_.memory_reduction_claim -or
    [bool]$_.optimization_claim
})
if ($BadComparison.Count -ne 0) { throw 'PERF2.2 report comparison policy mismatch' }

Write-Host "PERF2_2_WORKING_SET_ROWS=$(@($Report.working_set_rows).Count)"
Write-Host "PERF2_2_MEMORY_ROWS=$(@($Report.memory_rows).Count)"
Write-Host "PERF2_2_COMPARISONS=$(@($Report.comparisons).Count)"
Write-Host "PERF2_2_REPORT_HASH=$($Report.report_hash)"
foreach ($Comparison in @($Report.comparisons)) {
    $Line = "PERF2_2_PROFILE chunk={0} parent={1:N6} candidate={2:N6} proxy={3:N6} engine_static={4:N6}" -f [int]$Comparison.stream_chunk_size, [double]$Comparison.parent_record_reduction_factor_serial_over_stream, [double]$Comparison.candidate_record_reduction_factor_serial_over_stream, [double]$Comparison.record_proxy_reduction_factor_serial_over_stream, [double]$Comparison.engine_static_end_ratio_serial_over_stream
    Write-Host $Line
}

$FinalHead = (& git -C $Root rev-parse HEAD).Trim()
$FinalTree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()
if ($FinalHead -ne $Head) { throw "PERF2.2 HEAD moved during gate: $FinalHead != $Head" }
if ($FinalTree -ne $Tree) { throw "PERF2.2 TREE moved during gate: $FinalTree != $Tree" }

$Tracked = @(& git -C $Root status --porcelain --untracked-files=no)
if ($Tracked.Count -gt 0) {
    $Tracked | ForEach-Object { Write-Host $_ }
    throw 'PERF2.2 tracked worktree changed during gate'
}

Write-Host 'ECO.EVO7 PERF2.2 transitive working-set/memory R1 acceptance: PASS'
exit 0
