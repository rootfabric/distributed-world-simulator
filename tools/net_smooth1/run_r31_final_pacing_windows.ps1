# NET-SMOOTH1 R31 final server pacing: Windows independent exact 3x120s A/B.
# This script NEVER merges, kills foreign processes, modifies source or relabels FAIL.
# Requires standalone B3 Job Guard from PR #820, real Session1 GPU desktop.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Product,
    [Parameter(Mandatory=$true)][string]$GuardTools,
    [Parameter(Mandatory=$true)][string]$Evidence,
    [Parameter(Mandatory=$true)][string]$ExpectedHead,
    [Parameter(Mandatory=$true)][string]$ExpectedTree,
    [ValidateSet(90,120)][int]$CandidateCap=120,
    [string]$Godot='C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$CanonicalGuard='b4cbf565764cea16eb81cc163824b2a237e2cb8a'
$CanonicalGodotSHA='3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
$CanonicalVersion='4.7.1.stable.double.custom_build.a13da4feb'
$Python=(Get-Command python -ErrorAction Stop).Source
$Product=(Resolve-Path -LiteralPath $Product).Path
$GuardTools=(Resolve-Path -LiteralPath $GuardTools).Path
if ((git -C $Product rev-parse HEAD).Trim() -ne $ExpectedHead) { throw 'PRODUCT_HEAD_MISMATCH' }
if ((git -C $Product rev-parse 'HEAD^{tree}').Trim() -ne $ExpectedTree) { throw 'PRODUCT_TREE_MISMATCH' }
if (git -C $Product status --porcelain --untracked-files=no) { throw 'PRODUCT_TRACKED_DIRTY' }
if ((git -C $GuardTools rev-parse HEAD).Trim() -ne $CanonicalGuard) { throw 'JOB_GUARD_HEAD_MISMATCH' }
if ((git -C $GuardTools status --porcelain --untracked-files=no)) { throw 'JOB_GUARD_TRACKED_DIRTY' }
if (-not (Test-Path -LiteralPath $Godot)) { throw 'PINNED_GODOT_MISSING' }
if ((Get-FileHash -LiteralPath $Godot -Algorithm SHA256).Hash.ToLowerInvariant() -ne $CanonicalGodotSHA) { throw 'PINNED_GODOT_HASH_MISMATCH' }
if ((& $Godot --version | Out-String).Trim() -ne $CanonicalVersion) { throw 'PINNED_GODOT_VERSION_MISMATCH' }
if ((Get-Process -Id $PID).SessionId -eq 0) { throw 'INTERACTIVE_SESSION_REQUIRED' }
$GPU=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion)
if (-not @($GPU | Where-Object { $_.Name -match 'NVIDIA.*RTX' }).Count) { throw 'RTX_HARDWARE_RENDER_UNVERIFIED' }
if (Test-Path -LiteralPath $Evidence) { throw 'EVIDENCE_PATH_MUST_BE_NEW' }
New-Item -ItemType Directory -Path $Evidence -Force | Out-Null
$Log=Join-Path $Evidence 'host-identity.json'
[ordered]@{
  product_head=$ExpectedHead;product_tree=$ExpectedTree
  guard_head=$CanonicalGuard; godot_sha256=$CanonicalGodotSHA
  version=$CanonicalVersion; session_id=(Get-Process -Id $PID).SessionId
  gpu=$GPU; started=(Get-Date).ToString('o')
  godot_main_executable='NOT_INFERRED_SEPARATELY' # Executor must record trusted real main EXE hash
} | ConvertTo-Json -Depth 7 | Set-Content -Path $Log -Encoding UTF8
$ImportLog=Join-Path $Evidence 'cold-import.log'
& $Godot --headless --editor --path $Product --import --quit *> $ImportLog
if ($LASTEXITCODE -ne 0 -or (Select-String -Path $ImportLog -Pattern 'SCRIPT ERROR:|Parse Error:|Compile Error:' -Quiet)) {
    throw 'COLD_IMPORT_FAIL'
}
$Common=@(
'--mode','gui','--scenario','r31-reconnect-roundtrip','--duration','120','--warmup','20','--profile','LOCAL',
'--r3c-async-admission','--r3c2-avatar-prewarm','--r3c2-server-phased',
'--r3c3-staged-earth','--r3c21-frame-paced-presentation',
'--r3c4-periodic-frame-pacing','--r3c4r2-worker-envelope',
'--r3c4r31-replay-projection','--r3c4r31b-durable-attribution',
'--r31bp1-durable-chunks','--r31p22-loop-attribution',
'--r31p23r2-flush-attribution','--r31p23r21-single-pass-compact',
'--r31p23r22-attested-compact'
)
$Sequence=@(
@{label='p1-cap60';cap=60},
@{label='p1-candidate';cap=$CandidateCap},
@{label='p2-candidate';cap=$CandidateCap},
@{label='p2-cap60';cap=60},
@{label='p3-cap60';cap=60},
@{label='p3-candidate';cap=$CandidateCap}
)
$Status=@()
$CanonicalRawAssets=$null
foreach ($Arm in $Sequence) {
    $ArmFolder=Join-Path $Evidence $Arm.label
    New-Item -ItemType Directory -Path $ArmFolder -Force | Out-Null
    $ProcFile=Join-Path $ArmFolder 'host-processes.json'
    @(Get-CimInstance Win32_Process |
        Where-Object {$_.Name -match 'godot|node|python|chrome'} |
        Select-Object ProcessId,ParentProcessId,Name,CommandLine
    ) | ConvertTo-Json -Depth 5 | Set-Content -Path $ProcFile -Encoding UTF8
    $Load=@()
    for ($n=0; $n -lt 20; $n++) {
        $Load+= [int]((Get-CimInstance Win32_Processor |
          Measure-Object -Property LoadPercentage -Average).Average)
        Start-Sleep -Seconds 1
    }
    [ordered]@{samples=$Load; mean=(($Load | Measure-Object -Average).Average)} |
      ConvertTo-Json | Set-Content -Path (Join-Path $ArmFolder 'host-cpu.json')
    $Run=Join-Path $ArmFolder 'run'
    $Receipt=Join-Path $ArmFolder 'job_receipt.json'
    # Guard accepts a command after --; PERF_FAIL exit 1 is retained, never suppressed.
    $CommandArgs=@(
        '--receipt',$Receipt,'--cwd',$Product,'--deadline','1800','--',
        $Python,(Join-Path $Product 'tools\net_smooth1\run_net_smooth1.py'),
        '--godot',$Godot,'--output',$Run,'--skip-import',
        '--server-max-fps',[string]$Arm.cap
    ) + $Common
    & $Python (Join-Path $GuardTools 'tools\net_smooth1\run_r31_job_guard.py') @CommandArgs
    $Exit=$LASTEXITCODE
    $ManifestPath=Join-Path $Run 'manifest.json'
    $ReportPath=Join-Path $Run 'report.json'
    if (-not (Test-Path -LiteralPath $ManifestPath) -or -not (Test-Path -LiteralPath $ReportPath) -or -not (Test-Path -LiteralPath $Receipt)) {
        throw "MISSING_RAW_EVIDENCE:$($Arm.label)"
    }
    $Manifest=Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $Report=Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    $Guard=Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json
    $Clean=$Guard.job_cleanup.acceptance
    $RawAssets=[int]$Manifest.identity.asset_count
    if ($RawAssets -ne 123) { throw "ASSET_COUNT_NOT_123:$($Arm.label):$RawAssets" }
    $Hash=[string]$Manifest.identity.asset_manifest_sha256
    if ($null -eq $CanonicalRawAssets) { $CanonicalRawAssets=$Hash }
    if ($Hash -ne $CanonicalRawAssets) { throw "ASSET_MANIFEST_DRIFT:$($Arm.label)" }
    if ($Manifest.identity.head -ne $ExpectedHead -or $Manifest.identity.tree -ne $ExpectedTree) { throw "RUN_HEAD_TREE_MISMATCH:$($Arm.label)" }
    if ($Clean -ne 'CLEAN_JOB_EMPTY') { throw "JOB_NOT_CLEAN:$($Arm.label):$Clean" }
    foreach ($Role in @('server','a','b')) {
        foreach ($File in @('trace.jsonl','measure.end.ack','runtime.log')) {
            if (-not (Test-Path (Join-Path $Run "$Role\$File"))) { throw "MISSING_ROLE_EVIDENCE:$($Arm.label):$Role/$File" }
        }
    }
    if ($Report.verdict -eq 'INCONCLUSIVE' -or $Report.infrastructure.Count -gt 0) {
        throw "INCONCLUSIVE_OR_INFRASTRUCTURE_FAIL:$($Arm.label)"
    }
    $Status += [ordered]@{
        arm=$Arm.label;cap=$Arm.cap;runner_exit=$Exit;original_verdict=$Report.verdict;
        guard_cleanup=$Clean;run_id=$Manifest.run_id;asset_manifest_sha256=$Hash
    }
    $Status | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $Evidence 'arm-status.json') -Encoding UTF8
    Write-Host ("$($Arm.label) cap=$($Arm.cap) original=$($Report.verdict) guard_exit=$Exit cleanup=$Clean")
}
$Pairs=@(
    @((Join-Path $Evidence 'p1-cap60\run'),(Join-Path $Evidence 'p1-candidate\run')),
    @((Join-Path $Evidence 'p2-cap60\run'),(Join-Path $Evidence 'p2-candidate\run')),
    @((Join-Path $Evidence 'p3-cap60\run'),(Join-Path $Evidence 'p3-candidate\run'))
)
$Args=@()
foreach ($Pair in $Pairs) { $Args+=@('--pair',$Pair[0],$Pair[1]) }
$Args+=@('--output',(Join-Path $Evidence 'pacing-comparison.json'))
& $Python (Join-Path $Product 'tools\net_smooth1\compare_r31_server_pacing.py') @Args
if ($LASTEXITCODE -ne 0) { throw 'STRICT_PACING_COMPARATOR_FAIL' }
$Hashes=@(Get-ChildItem -LiteralPath $Evidence -Recurse -File |
  Where-Object {$_.Name -ne 'sha256-inventory.json'} |
  Sort-Object FullName |
  ForEach-Object {
    [ordered]@{relative=$_.FullName.Substring($Evidence.Length).TrimStart('\');sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
  })
$Hashes | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $Evidence 'sha256-inventory.json') -Encoding UTF8
Write-Host 'DIAGNOSTIC COMPLETE — individual report.json PASS/FAIL preserved; NOT RELEASE ACCEPTANCE.'
