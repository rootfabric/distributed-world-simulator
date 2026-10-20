# Read-only exact Windows acceptance launcher for NET-SMOOTH1 R3C.4 R2.
# Execute this file OUTSIDE the pinned #787 worktree; no source edits or merges.
# Expected exit: 0 = GUI perf gates pass only; 1 = PERF_FAIL;
# 2 = INCONCLUSIVE; 3 = FUNCTIONAL_FAIL. Never auto-merge.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepoPath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [string]$GodotPath = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$ExpectedHead = 'f64fed2430f1292773d1561f881e5c8a4cc89075'
$ExpectedTree = '01731ee75418c58c2f2d2e16fb39d29b9a167def'
$ExpectedParent = 'ced03db64eae3adaab270044574c0f8b96c590c6'
$ExpectedVersion = '4.7.1.stable.double.custom_build.a13da4feb'
$ExpectedHash = '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
$Python = (Get-Command python -ErrorAction Stop).Source
$Runner = Join-Path $RepoPath 'tools\net_smooth1\run_net_smooth1.py'
$Analyzer = Join-Path $RepoPath 'tools\net_smooth1\analyze_net_smooth1.py'
$Comparator = Join-Path $PSScriptRoot 'compare_r3c4r2_gui_evidence.py'

function Assert-Equal([string]$Actual, [string]$Expected, [string]$Label) {
    if ($Actual -cne $Expected) { throw "$Label mismatch: actual='$Actual' expected='$Expected'" }
}
function Invoke-Native([string]$Label, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
    Write-Host "== $Label ==" -ForegroundColor Cyan
    & $Python @Arguments
    $rc = $LASTEXITCODE
    if ($rc -notin $Allowed) { throw "$Label failed with code $rc" }
    return $rc
}
if ((Test-Path -LiteralPath $OutputRoot)) {
    throw "OutputRoot already exists; preserve immutable evidence: $OutputRoot"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "GODOT_EXE_NOT_FOUND: $GodotPath"
}
Assert-Equal ((& git -C $RepoPath rev-parse HEAD).Trim()) $ExpectedHead 'HEAD'
Assert-Equal ((& git -C $RepoPath rev-parse 'HEAD^{tree}').Trim()) $ExpectedTree 'TREE'
& git -C $RepoPath merge-base --is-ancestor $ExpectedParent HEAD
if ($LASTEXITCODE -ne 0) { throw 'R1_ANCESTRY_MISMATCH' }
$tracked = (& git -C $RepoPath status --porcelain --untracked-files=no | Out-String).Trim()
if ($tracked) { throw "TRACKED_WORKTREE_DIRTY: $tracked" }
Assert-Equal ((& $GodotPath --version | Out-String).Trim()) $ExpectedVersion 'GODOT_VERSION'
Assert-Equal (Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant() $ExpectedHash 'GODOT_SHA256'
$assets = Join-Path $RepoPath 'assets\external\quaternius'
if (-not (Test-Path -LiteralPath $assets -PathType Container)) { throw 'QUATERNIUS_ASSETS_MISSING' }
$assetCount = @(Get-ChildItem -LiteralPath $assets -Recurse -File |
    Where-Object { $_.Extension -notin @('.import', '.uid') }).Count
if ($assetCount -lt 220) { throw "QUATERNIUS_INCOMPLETE: only $assetCount asset files" }
if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) { throw "RUNNER_NOT_FOUND: $Runner" }
if (-not (Test-Path -LiteralPath $Analyzer -PathType Leaf)) { throw "ANALYZER_NOT_FOUND: $Analyzer" }
if (-not (Test-Path -LiteralPath $Comparator -PathType Leaf)) { throw "COMPARATOR_NOT_FOUND: $Comparator" }

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$Identity = [ordered]@{
    head = $ExpectedHead
    tree = $ExpectedTree
    parent = $ExpectedParent
    godot_version = $ExpectedVersion
    godot_sha256 = $ExpectedHash
    quaternius_asset_count = $assetCount
    machine = $env:COMPUTERNAME
    pwsh = $PSVersionTable.PSVersion.ToString()
    python = (& $Python --version | Out-String).Trim()
    utc = (Get-Date).ToUniversalTime().ToString('o')
}
$Identity | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputRoot 'identity.json') -Encoding utf8

$CommonFlags = @(
    '--r3c-async-admission',
    '--r3c2-avatar-prewarm',
    '--r3c2-server-phased',
    '--r3c3-staged-earth',
    '--r3c21-frame-paced-presentation',
    '--r3c4-periodic-frame-pacing'
)
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
$env:GODOT_SILENCE_ROOT_WARNING = '1'
Push-Location $RepoPath
try {
    $FocusedArgs = @($Runner, '--godot', $GodotPath, '--mode', 'focused',
        '--output', (Join-Path $OutputRoot 'focused'))
    [void](Invoke-Native 'focused-native' $FocusedArgs)
    [void](Invoke-Native 'r2-source-contract' @(
        '-m', 'unittest', 'discover', '-s', 'tests/tools',
        '-p', 'test_net_smooth1_r3c4_r2_worker_envelope_source.py', '-v'
    ))
    $NativeLog = Join-Path $OutputRoot 'r2-native.log'
    & $GodotPath --headless --path $RepoPath --script 'res://tests/runtime/test_net_smooth1_r3c4_r2_worker_envelope.gd' *> $NativeLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $NativeLog -Pattern 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:' -Quiet)) {
        Get-Content -LiteralPath $NativeLog -Tail 100
        throw 'R2_NATIVE_FALSIFIER_FAIL'
    }

    # Run alternating pairs: OFF/ON, ON/OFF, OFF/ON. All arms same pinned HEAD.
    # Exit=1 on performance regression is EXPECTED and must not truncate batch.
    for ($pair = 1; $pair -le 3; $pair++) {
        $arms = if ($pair -eq 2) { @('on','off') } else { @('off','on') }
        foreach ($arm in $arms) {
            $name = "gui-$arm-$pair"
            $RunArgs = @($Runner, '--godot', $GodotPath, '--mode', 'gui',
                '--scenario', 'r31-reconnect-roundtrip', '--duration', '120',
                '--warmup', '20', '--profile', 'LOCAL',
                '--output', (Join-Path $OutputRoot $name)) + $CommonFlags
            if ($arm -eq 'on') { $RunArgs += '--r3c4r2-worker-envelope' }
            $rc = Invoke-Native $name $RunArgs @(0, 1)
            $Dir = Join-Path $OutputRoot $name
            if (-not (Test-Path -LiteralPath (Join-Path $Dir 'manifest.json'))) {
                throw "MANIFEST_MISSING: $name"
            }
            $m = Get-Content (Join-Path $Dir 'manifest.json') -Raw | ConvertFrom-Json
            if ($m.completed -ne $true -or @($m.errors).Count -gt 0) {
                throw "GUI_RUN_INCONCLUSIVE: $name manifest completed/errors invalid"
            }
            # Independently re-evaluate with unmodified repository analyzer.
            [void](Invoke-Native "reanalyze-$name" @($Analyzer, $Dir) @(0,1))
            Write-Host "$name analyzer exit: $rc"
        }
    }

    # Fault-injected ITEM canary; its frame thresholds can fail under injected delay.
    for ($i = 1; $i -le 3; $i++) {
        $name = "slow-item-on-$i"
        $RunArgs = @($Runner, '--godot', $GodotPath, '--mode', 'gui',
            '--scenario', 'r3-slow-item', '--slow-item-writer-ms', '1800',
            '--duration', '120', '--warmup', '20', '--profile', 'LOCAL',
            '--output', (Join-Path $OutputRoot $name),
            '--r3c4r2-worker-envelope') + $CommonFlags
        [void](Invoke-Native $name $RunArgs @(0,1))
        $m = Get-Content (Join-Path (Join-Path $OutputRoot $name) 'manifest.json') -Raw | ConvertFrom-Json
        if ($m.completed -ne $true -or @($m.errors).Count -gt 0 -or $m.r3c4r2_worker_envelope -ne $true) {
            throw "SLOW_ITEM_INCONCLUSIVE: $name"
        }
        $DurableFile = Join-Path (Join-Path $OutputRoot $name) 'durable-commands.json'
        if (-not (Test-Path -LiteralPath $DurableFile -PathType Leaf)) {
            throw "SLOW_ITEM_DURABLE_EVIDENCE_MISSING: $name"
        }
        $Durable = Get-Content -LiteralPath $DurableFile -Raw | ConvertFrom-Json
        if ($Durable.committed_durable_count -lt 24 -or
            @($Durable.command_types).Count -lt 2 -or
            $Durable.duplicate_replay_idempotent -ne $true) {
            throw "SLOW_ITEM_DURABLE_WORKLOAD_FAIL: $name"
        }
    }

    $rc = Invoke-Native 'compare-six-gui-runs' @($Comparator, '--root', $OutputRoot) @(0,1,2,3)
    $Status = @('GUI_PERF_GATE_PASS_ONLY', 'PERF_FAIL', 'INCONCLUSIVE', 'FUNCTIONAL_FAIL')[$rc]
    Write-Host "$Status / NO_MERGE — evidence: $OutputRoot"
    $Final = (& git -C $RepoPath status --porcelain --untracked-files=no | Out-String).Trim()
    if ($Final) { throw "POSTTEST_TRACKED_DIRTY: $Final" }

    $shaList = Get-ChildItem -LiteralPath $OutputRoot -Recurse -File |
        Where-Object { $_.Name -ne 'sha256.json' } |
        ForEach-Object {
            [ordered]@{
                file = $_.FullName.Substring($OutputRoot.Length).TrimStart('\')
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    @($shaList) | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputRoot 'sha256.json') -Encoding utf8
    exit $rc
} finally {
    Pop-Location
}
