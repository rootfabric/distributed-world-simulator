# NET-SMOOTH1 #815: guarded 6-arm Windows GUI SAFETY campaign (NOT performance acceptance).
# No merges, no kill of foreign processes, no retries hidden, no norm waiver.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Product,
  [Parameter(Mandatory=$true)][string]$GuardTools,
  [Parameter(Mandatory=$true)][string]$Evidence,
  [Parameter(Mandatory=$true)][string]$ExpectedHead,
  [Parameter(Mandatory=$true)][string]$ExpectedTree,
  [string]$Godot='C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$GodotSHA='3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
$GuardSHA='b4cbf565764cea16eb81cc163824b2a237e2cb8a'
$RawAssetSHA='d0abf6650b2de9293e720c11981354ec403d7032adbc5f5b0c042655d2ce427d'
$Python=(Get-Command python -ErrorAction Stop).Source
$Product=(Resolve-Path -LiteralPath $Product).Path
$GuardTools=(Resolve-Path -LiteralPath $GuardTools).Path
if ((git -C $Product rev-parse HEAD).Trim() -ne $ExpectedHead) { throw 'PRODUCT_HEAD_MISMATCH' }
if ((git -C $Product rev-parse 'HEAD^{tree}').Trim() -ne $ExpectedTree) { throw 'PRODUCT_TREE_MISMATCH' }
if ((git -C $GuardTools rev-parse HEAD).Trim() -ne $GuardSHA) { throw 'B3_GUARD_HEAD_MISMATCH' }
if (git -C $Product status --porcelain --untracked-files=no) { throw 'TRACKED_DIRTY_PRODUCT' }
if (git -C $GuardTools status --porcelain --untracked-files=no) { throw 'TRACKED_DIRTY_GUARD' }
if (-not (Test-Path $Godot)) { throw 'PINNED_GODOT_NOT_FOUND' }
if ((Get-FileHash $Godot -Algorithm SHA256).Hash.ToLowerInvariant() -ne $GodotSHA) { throw 'GODOT_SHA_MISMATCH' }
if ((& $Godot --version | Out-String).Trim() -ne '4.7.1.stable.double.custom_build.a13da4feb') { throw 'GODOT_VERSION_MISMATCH' }
if ((Get-Process -Id $PID).SessionId -eq 0) { throw 'INTERACTIVE_SESSION_REQUIRED' }
$GPU=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion)
if (@($GPU | Where-Object {$_.Name -match 'NVIDIA.*RTX'}).Count -eq 0) { throw 'GPU_HARDWARE_NOT_VERIFIED' }
if (Test-Path -LiteralPath $Evidence) { throw 'EVIDENCE_ROOT_ALREADY_EXISTS' }
New-Item -ItemType Directory -Path $Evidence -Force | Out-Null
$MainExe=Join-Path (Split-Path $Godot -Parent) 'godot.windows.editor.double.x86_64.exe'
$MainHash=(Get-FileHash $MainExe -Algorithm SHA256).Hash.ToLowerInvariant()
[ordered]@{ product_head=$ExpectedHead; product_tree=$ExpectedTree; guard_head=$GuardSHA; godot_wrapper_sha256=$GodotSHA; main_exe_sha256=$MainHash; session=(Get-Process -Id $PID).SessionId; gpu=$GPU } | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $Evidence 'identity.json') -Encoding UTF8
$ImportLog=Join-Path $Evidence 'cold-import.log'
& $Godot --headless --editor --path $Product --import --quit *> $ImportLog
if ($LASTEXITCODE -ne 0 -or (Select-String $ImportLog -Pattern 'SCRIPT ERROR:|Parse Error:|Compile Error:' -Quiet)) { throw 'GODOT_COLD_IMPORT_FAIL' }
$Common=@(
 '--mode','gui','--scenario','r31-reconnect-roundtrip','--duration','120','--warmup','20','--profile','LOCAL',
 '--r3c-async-admission','--r3c2-avatar-prewarm','--r3c2-server-phased',
 '--r3c3-staged-earth','--r3c21-frame-paced-presentation',
 '--r3c4-periodic-frame-pacing','--r3c4r2-worker-envelope',
 '--r3c4r31-replay-projection','--r3c4r31b-durable-attribution',
 '--r31bp1-durable-chunks','--r31p22-loop-attribution',
 '--r31p23r2-flush-attribution','--r31p23r21-single-pass-compact',
 '--r31p23r22-attested-compact','--r31-815-wire-forensics'
)
$Arms=@(
 @{name='p1-60-control';cap=60;guard=$false},
 @{name='p1-120-control';cap=120;guard=$false},
 @{name='p2-120-protected';cap=120;guard=$true},
 @{name='p2-60-control';cap=60;guard=$false},
 @{name='p3-120-protected';cap=120;guard=$true},
 @{name='p3-120-control';cap=120;guard=$false}
)
$List=@()
foreach ($Arm in $Arms) {
  $Folder=Join-Path $Evidence $Arm.name
  New-Item -ItemType Directory -Path $Folder -Force | Out-Null
  @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'godot|python|chrome|node' } | Select-Object ProcessId,ParentProcessId,Name,CommandLine) | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Folder 'host-processes-preflight.json')
  $Run=Join-Path $Folder 'run'
  $Receipt=Join-Path $Folder 'job_receipt.json'
  $Cmd=@('--receipt',$Receipt,'--cwd',$Product,'--deadline','1800','--',
         $Python,(Join-Path $Product 'tools\net_smooth1\run_net_smooth1.py'),
         '--godot',$Godot,'--output',$Run,'--skip-import','--server-max-fps',
         [string]$Arm.cap) + $Common
  if ($Arm.guard) { $Cmd+=@('--r31-815-outbound-guard') }
  & $Python (Join-Path $GuardTools 'tools\net_smooth1\run_r31_job_guard.py') @Cmd
  $OriginalExit=$LASTEXITCODE
  $ManifestP=Join-Path $Run 'manifest.json'
  $ReportP=Join-Path $Run 'report.json'
  if (-not (Test-Path $ManifestP) -or -not (Test-Path $ReportP) -or -not (Test-Path $Receipt)) { throw "RAW_EVIDENCE_MISSING:$($Arm.name)" }
  $Manifest=Get-Content $ManifestP -Raw | ConvertFrom-Json
  $Report=Get-Content $ReportP -Raw | ConvertFrom-Json
  $GuardReceipt=Get-Content $Receipt -Raw | ConvertFrom-Json
  if ($Manifest.identity.head -ne $ExpectedHead -or $Manifest.identity.tree -ne $ExpectedTree) { throw "RUN_IDENTITY_DRIFT:$($Arm.name)" }
  if ([int]$Manifest.identity.asset_count -ne 123 -or $Manifest.identity.asset_manifest_sha256 -ne $RawAssetSHA) { throw "QUATERNIUS_RAW_ASSET_DRIFT:$($Arm.name)" }
  if ($GuardReceipt.job_cleanup.acceptance -ne 'CLEAN_JOB_EMPTY') { throw "UNSAFE_PROCESS_CLEANUP:$($Arm.name)" }
  if ([bool]$Manifest.r31_815_outbound_guard -ne [bool]$Arm.guard) { throw "UNATTESTED_GUARD_FLAG:$($Arm.name)" }
  $Forensic=Join-Path $Folder 'wire-fingerprints.json'
  & $Python (Join-Path $Product 'tools\net_smooth1\analyze_r31_815_wire_fingerprints.py') $Run --output $Forensic
  if ($LASTEXITCODE -ne 0) { throw "FORENSIC_TRACE_MISSING_OR_INVALID:$($Arm.name)" }
  $EvidenceResult=Get-Content $Forensic -Raw | ConvertFrom-Json
  $List += [ordered]@{arm=$Arm.name;server_fps=$Arm.cap;guard_enabled=$Arm.guard;original_exit=$OriginalExit;original_verdict=$Report.verdict;rx_decode_rejects=$EvidenceResult.actual_decode_reject_count;outbound_guard_rejects=$EvidenceResult.outbound_guard_reject_count;run_id=$Manifest.run_id;cleanup='CLEAN_JOB_EMPTY'}
  $List | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Evidence 'attempt-results.json') -Encoding UTF8
  Write-Host "ARM $($Arm.name): original=$($Report.verdict) RX=$($EvidenceResult.actual_decode_reject_count) intercepted=$($EvidenceResult.outbound_guard_reject_count)"
}
# Preserve every raw trace/manifest/report under a SHA256 inventory.
@(Get-ChildItem -LiteralPath $Evidence -Recurse -File | Where-Object {$_.Name -ne 'sha256-inventory.json'} | Sort-Object FullName | ForEach-Object {[ordered]@{path=$_.FullName.Substring($Evidence.Length).TrimStart('\');sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}) | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Evidence 'sha256-inventory.json') -Encoding UTF8
Write-Host 'SAFETY_DIAGNOSTIC_ONLY. Original PERF_FAIL and #815 OPEN remain unchanged.'
