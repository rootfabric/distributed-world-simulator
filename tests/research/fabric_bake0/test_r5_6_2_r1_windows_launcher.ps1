[CmdletBinding()]param(
    [string]$RunnerPath = (Join-Path $PSScriptRoot '../../../RUN_FABRIC_R5_6_2_R1_TESTS.ps1'),
    [string]$LegacyRunnerPath = '',
    [string]$PythonBin = 'python',
    [string]$EvidenceDir = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RunnerPath = (Resolve-Path $RunnerPath).Path
if (!$EvidenceDir) {
    $EvidenceDir = Join-Path (Split-Path $RunnerPath) ('artifacts/launcher-contract-'+[guid]::NewGuid().ToString('N'))
}
$EvidenceDir = [IO.Path]::GetFullPath($EvidenceDir)
if ((Test-Path $EvidenceDir) -and @(Get-ChildItem $EvidenceDir -Force).Count) { throw 'TEST_EVIDENCE_NOT_EMPTY' }
New-Item -ItemType Directory -Force $EvidenceDir | Out-Null
$Root = Join-Path $EvidenceDir 'project with spaces Кириллица'
New-Item -ItemType Directory -Force $Root | Out-Null
$GodotBin = (Get-Command $PythonBin -CommandType Application | Select-Object -First 1).Source
$Utf8 = [Text.UTF8Encoding]::new($false)
$Fatal = 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:'
$script:Checks = 0
$script:CaseResults = @()
$script:ProbePython = @'
import json, os, sys, time
print('ARGV_PROBE=' + json.dumps(sys.argv[1:], ensure_ascii=False), flush=True)
mode = os.environ.get('FABRIC_R562_LAUNCHER_TEST_MODE', '')
if mode == 'timeout':
    print('TIMEOUT_STDOUT_SENTINEL', flush=True)
    print('TIMEOUT_STDERR_SENTINEL', file=sys.stderr, flush=True)
    time.sleep(30)
if mode == 'fatal':
    print('SCRIPT ERROR: TEST_SENTINEL', file=sys.stderr, flush=True)
if mode == 'gameplay':
    print('terrain_streaming_summary state=ACTIVE reason=spectator_predictive_stream', flush=True)
if mode == 'nonzero':
    sys.exit(7)
'@
function Check([bool]$Condition,[string]$Label) {
    $script:Checks++
    if (!$Condition) { throw "LAUNCHER_ASSERTION_FAILED:$Label" }
}
function Load-Launcher([string]$Path) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'RUNNER_PARSE_ERROR' }
    $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'RunGodot'},$false)
    if ($null -eq $node) { throw 'LAUNCHER_FUNCTION_MISSING' }
    $code = $node.Extent.Text
    $boundary = '$proc.StartInfo = $info'
    if (!$code.Contains($boundary)) { throw 'PROCESS_ADAPTER_BOUNDARY_MISSING' }
    # Extract the REAL checked-in function, never dot-source the full runner.
    # Only adapt its native executable boundary to Python instead of Godot.
    # No change to parameter binding, stage validation, original argv builder,
    # wait/kill logic, logging or outcome evaluation. Python echoes native argv.
    return $code.Replace($boundary, $boundary + @'

    $proc.StartInfo.ArgumentList.Insert(0, $script:ProbePython)
    $proc.StartInfo.ArgumentList.Insert(0, '-c')
'@)
}
function New-Case([string]$Label) {
    $path = Join-Path $EvidenceDir $Label
    New-Item -ItemType Directory -Force $path | Out-Null
    return $path
}
function Echo-Arguments([string]$Path) {
    $lines = @(Get-Content $Path -Encoding utf8 | Where-Object { $_.StartsWith('ARGV_PROBE=') })
    Check ($lines.Count -eq 1) 'exactly one child argv witness'
    return ,@($lines[0].Substring('ARGV_PROBE='.Length) | ConvertFrom-Json)
}
function Same-Array($Left,$Right) {
    return (ConvertTo-Json -InputObject @($Left) -Compress) -ceq (ConvertTo-Json -InputObject @($Right) -Compress)
}
$previousMode = [Environment]::GetEnvironmentVariable('FABRIC_R562_LAUNCHER_TEST_MODE','Process')
$previousEncoding = [Environment]::GetEnvironmentVariable('PYTHONIOENCODING','Process')
try {
    $env:PYTHONIOENCODING = 'utf-8'
    $env:FABRIC_R562_LAUNCHER_TEST_MODE = ''
    if ($LegacyRunnerPath) {
        Invoke-Expression (Load-Launcher (Resolve-Path $LegacyRunnerPath).Path)
        $Out = New-Case 'legacy-red'
        RunGodot 'import-recovery' @('--editor','--import','--recovery-mode')
        $legacyActual = Echo-Arguments (Join-Path $Out 'import-recovery.log')
        Check (Same-Array $legacyActual @('--headless','--path',$Root)) 'legacy exact function loses all gate flags'
        $script:CaseResults += 'LEGACY_RED_REPRODUCED'
    }
    Invoke-Expression (Load-Launcher $RunnerPath)
    $T = 'res://tests/research/fabric_bake0'
    $cases = [ordered]@{
        'import-recovery' = @('--editor','--import','--recovery-mode')
        'import' = @('--editor','--import')
        'parse-lifecycle' = @('--check-only','--script',"$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
        'lifecycle-1' = @('--script',"$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
        'lifecycle-2' = @('--script',"$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
        'lifecycle-3' = @('--script',"$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
        'r2-regression' = @('--script',"$T/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd")
        'com-recovery-regression' = @('--script',"$T/fabric_r5_6_1_r2_com_recovery_acceptance.gd")
        'r1-regression' = @('--script',"$T/fabric_r5_6_1_canonical_delta_acceptance.gd")
        'bridge4-regression' = @('--quit-after','2','--script','res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd')
    }
    foreach ($stage in $cases.Keys) {
        $Out = New-Case $stage
        RunGodot -Name $stage -GateArgs $cases[$stage]
        $actual = Echo-Arguments (Join-Path $Out "$stage.log")
        $expected = @('--headless','--path',$Root) + $cases[$stage]
        Check (Same-Array $actual $expected) "$stage native argv including spaces and Unicode"
        $command = Get-Content (Join-Path $Out "$stage.argv.json") -Raw | ConvertFrom-Json
        Check (Same-Array $command.argv $expected) "$stage launch audit matches native child"
        $outcome = Get-Content (Join-Path $Out "$stage.process.json") -Raw | ConvertFrom-Json
        Check ($outcome.verdict -ceq 'PASS' -and $outcome.exit_code -eq 0 -and !$outcome.timed_out) "$stage clean process receipt"
        $script:CaseResults += "ARGV_PASS:$stage"
    }
    $invalid = @(
        @{Name='import'; GateArgs=@('--editor')},
        @{Name='import-recovery'; GateArgs=@('--editor','--import')},
        @{Name='import'; GateArgs=@('--editor','--import','--')},
        @{Name='lifecycle-1'; GateArgs=@('--script','res://main.gd')},
        @{Name='parse-lifecycle'; GateArgs=@('--check-only')},
        @{Name='import'; GateArgs=@()},
        @{Name='unknown'; GateArgs=@('--editor','--import')}
    )
    for ($i=0; $i -lt $invalid.Count; $i++) {
        $Out = New-Case "invalid-$i"
        $call = $invalid[$i]
        $rejected = $false
        try { RunGodot @call } catch { $rejected = $true }
        Check $rejected "invalid-$i rejected before native start"
        Check (@(Get-ChildItem $Out -Force).Count -eq 0) "invalid-$i produces no child artifact"
        $script:CaseResults += "FAIL_CLOSED:$i"
    }
    foreach ($mode in @('nonzero','fatal','gameplay','timeout')) {
        $env:FABRIC_R562_LAUNCHER_TEST_MODE = $mode
        $Out = New-Case "fault-$mode"
        $failure = ''
        $deadline = if ($mode -eq 'timeout') { 1 } else { 10 }
        try { RunGodot -Name 'import' -GateArgs @('--editor','--import') -TimeoutSeconds $deadline }
        catch { $failure = $_.Exception.Message }
        $wanted = if ($mode -eq 'timeout') { 'TIMEOUT:import' } elseif ($mode -eq 'gameplay') { 'IMPORT_GAMEPLAY_SIDE_EFFECT:import' } else { 'FAILED:import' }
        Check ($failure -ceq $wanted) "$mode exact rejection ($failure)"
        Check (Test-Path (Join-Path $Out 'import.argv.json')) "$mode argv preserved"
        $receipt = Get-Content (Join-Path $Out 'import.process.json') -Raw | ConvertFrom-Json
        Check ($receipt.verdict -cne 'PASS') "$mode never false PASS"
        Check (Test-Path (Join-Path $Out 'import.log')) "$mode combined raw output preserved"
        if ($mode -eq 'timeout') {
            Check $receipt.timed_out 'timeout receipt true'
            Check ((Get-Content (Join-Path $Out 'import.stdout.log') -Raw) -match 'TIMEOUT_STDOUT_SENTINEL') 'timeout stdout retained'
            Check ((Get-Content (Join-Path $Out 'import.stderr.log') -Raw) -match 'TIMEOUT_STDERR_SENTINEL') 'timeout stderr retained'
        }
        $script:CaseResults += "PROCESS_FAULT:$mode"
    }
    $report = [ordered]@{
        schema='fabric.r562.windows_launcher_contract.v1';checks=$script:Checks;failures=@()
        cases=$script:CaseResults;powershell=$PSVersionTable.PSVersion.ToString()
        os=[Environment]::OSVersion.VersionString;godot_launched=$false
        runner_sha256=(Get-FileHash $RunnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    [IO.File]::WriteAllText((Join-Path $EvidenceDir 'launcher-result.json'),
        (ConvertTo-Json -InputObject $report -Depth 6), $Utf8)
    Write-Host "FABRIC_R562_WINDOWS_LAUNCHER_CONTRACT=PASS checks=$script:Checks"
} finally {
    [Environment]::SetEnvironmentVariable('FABRIC_R562_LAUNCHER_TEST_MODE',$previousMode,'Process')
    [Environment]::SetEnvironmentVariable('PYTHONIOENCODING',$previousEncoding,'Process')
}
