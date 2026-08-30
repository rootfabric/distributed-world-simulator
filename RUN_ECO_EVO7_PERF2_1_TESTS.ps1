param(
    [Alias('GodotPath')]
    [string]$GodotBin = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedGodot = '4.7.1.stable.double.custom_build.a13da4feb'
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

$ContractBlob = (& git -C $Root rev-parse "HEAD:$ContractPath").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve accepted PERF2.0 contract blob' }
if ($ContractBlob -ne $ExpectedContractBlob) {
    throw "PERF2.1 CONTRACT DRIFT: expected blob $ExpectedContractBlob, got $ContractBlob"
}
& git -C $Root diff --quiet -- $ContractPath
if ($LASTEXITCODE -ne 0) {
    throw 'PERF2.1 CONTRACT WORKTREE DRIFT: accepted contract has local modifications'
}

$Machine = [string]$env:COMPUTERNAME
if ([string]::IsNullOrWhiteSpace($Machine)) { $Machine = '<unknown-machine>' }
$HostFingerprint = "$Machine|$([Environment]::OSVersion.VersionString)|powershell-$($PSVersionTable.PSVersion)"

$env:ECO_PERF2_TARGET_HEAD = $Head
$env:ECO_PERF2_TARGET_TREE = $Tree
$env:ECO_PERF2_HOST_FINGERPRINT = $HostFingerprint

Write-Host "PERF2.1 exact target HEAD=$Head"
Write-Host "PERF2.1 exact target TREE=$Tree"
Write-Host "PERF2.1 Godot=$ActualGodot"
Write-Host "PERF2.1 frozen contract blob=$ContractBlob"
Write-Host "PERF2.1 host fingerprint=$HostFingerprint"

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

$FinalHead = (& git -C $Root rev-parse HEAD).Trim()
$FinalTree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()
if ($FinalHead -ne $Head) { throw "PERF2.1 HEAD moved during gate: $FinalHead != $Head" }
if ($FinalTree -ne $Tree) { throw "PERF2.1 TREE moved during gate: $FinalTree != $Tree" }

Write-Host 'ECO.EVO7 PERF2.1 transitive generation-profiling acceptance: PASS'
exit 0
