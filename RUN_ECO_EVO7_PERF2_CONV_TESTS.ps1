param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $Global:PSNativeCommandUseErrorActionPreference = $false
}

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$Perf24Head = "840cfcea62ef7192b510235f915b849829654c6c"
$Perf24Tree = "967d674c0ba2349db949193969f16f91553761ea"
$Perf24AcceptedControlHead = "ab115385e81375b224eb397cf6a9de071bd4e79e"
$Perf24ReportHash = "16d3407abef3d3ff30cbe4293cb1278e1b18845b0b5332589587d543b134853b"
$Perf24AcceptanceCheckpoint = "docs/checkpoints/2026-09-04_ECO_EVO7_PERF2_4_R12_ACCEPTED_RU.md"
$Vis49Head = "ab44617d8961add81a6c9f245c99d0b68eaeab52"
$Vis49Tree = "9d543a3db4f54a676e9f25152785c36a72c56a30"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$ActualGodot = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($ActualGodot -ne $ExpectedGodot) {
    throw "ECO.EVO7 PERF2.CONV BLOCKED: expected Godot '$ExpectedGodot', got '$ActualGodot'"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$PreviousGodotBin = $env:GODOT_BIN
$PreviousGodotDoubleBin = $env:GODOT_DOUBLE_BIN
$PreviousTargetHead = $env:ECO_PERF2_CONV_TARGET_HEAD
$PreviousTargetTree = $env:ECO_PERF2_CONV_TARGET_TREE

$LocalHead = (git -C $RootDir rev-parse HEAD).Trim()
$LocalTree = (git -C $RootDir rev-parse "HEAD^{tree}").Trim()
$TargetHead = if ([string]::IsNullOrWhiteSpace($PreviousTargetHead)) { $LocalHead } else { $PreviousTargetHead }
$TargetTree = if ([string]::IsNullOrWhiteSpace($PreviousTargetTree)) { $LocalTree } else { $PreviousTargetTree }

if ($TargetHead -ne $LocalHead) {
    throw "PERF2.CONV BLOCKED: target HEAD $TargetHead != local HEAD $LocalHead"
}
if ($TargetTree -ne $LocalTree) {
    throw "PERF2.CONV BLOCKED: target TREE $TargetTree != local TREE $LocalTree"
}
if ($TargetHead -notmatch '^[0-9a-f]{40}$' -or $TargetTree -notmatch '^[0-9a-f]{40}$') {
    throw "PERF2.CONV BLOCKED: invalid target HEAD/TREE identity"
}

foreach ($Pair in @(@($Perf24Head, $Perf24Tree), @($Vis49Head, $Vis49Tree))) {
    $Sha = $Pair[0]
    $ExpectedTree = $Pair[1]
    & git -C $RootDir cat-file -e "$Sha^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "PERF2.CONV BLOCKED: prerequisite commit missing: $Sha" }
    $ActualTree = (& git -C $RootDir rev-parse "$Sha^{tree}").Trim()
    if ($ActualTree -ne $ExpectedTree) {
        throw "PERF2.CONV BLOCKED: prerequisite TREE mismatch for $Sha"
    }
}

try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $env:GODOT_BIN = $GodotPath
    $env:GODOT_DOUBLE_BIN = $GodotPath
    $env:ECO_PERF2_CONV_TARGET_HEAD = $TargetHead
    $env:ECO_PERF2_CONV_TARGET_TREE = $TargetTree

    Write-Host "PERF2.CONV exact HEAD=$TargetHead"
    Write-Host "PERF2.CONV exact TREE=$TargetTree"
    Write-Host "PERF2.CONV Godot=$ActualGodot"
    Write-Host "PERF2.CONV PERF2.4 prerequisite=$Perf24Head / $Perf24Tree"
    Write-Host "PERF2.CONV VIS4.9 prerequisite=$Vis49Head / $Vis49Tree"

    Write-Host "=== immutable prerequisite provenance ==="
    & git -C $RootDir merge-base --is-ancestor $Perf24Head $TargetHead
    if ($LASTEXITCODE -ne 0) { throw "PERF2.CONV BLOCKED: accepted PERF2.4 runtime is not an ancestor" }
    & git -C $RootDir merge-base --is-ancestor $Perf24AcceptedControlHead $TargetHead
    if ($LASTEXITCODE -ne 0) { throw "PERF2.CONV BLOCKED: PERF2.4 acceptance control tip is not an ancestor" }
    & git -C $RootDir merge-base --is-ancestor $Vis49Head $TargetHead
    if ($LASTEXITCODE -ne 0) { throw "PERF2.CONV BLOCKED: tested VIS4.9 prerequisite is not an ancestor" }

    $AcceptancePath = Join-Path $RootDir $Perf24AcceptanceCheckpoint
    if (-not (Test-Path -LiteralPath $AcceptancePath -PathType Leaf)) { throw "PERF2.CONV BLOCKED: PERF2.4 acceptance checkpoint missing" }
    $AcceptanceText = Get-Content -Raw -LiteralPath $AcceptancePath
    foreach ($Token in @($Perf24Head, $Perf24Tree, $Perf24ReportHash)) {
        if (-not $AcceptanceText.Contains($Token)) { throw "PERF2.CONV BLOCKED: PERF2.4 acceptance checkpoint missing token $Token" }
    }
    Write-Host "PERF2.CONV PERF2.4 immutable accepted prerequisite: PASS"
    Write-Host "PERF2.CONV VIS4.9 immutable tested prerequisite: PASS"
    Write-Host "PERF2.CONV prerequisite rerun policy=NO_RERUN_ACCEPTED_IMMUTABLE_EVIDENCE"

    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== PERF2.CONV integrated STREAM1 + VIS4 gate ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_perf2_conv_stream1_vis4_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "PERF2.CONV focused acceptance failed with exit code $LASTEXITCODE" }

    $FinalHead = (git -C $RootDir rev-parse HEAD).Trim()
    $FinalTree = (git -C $RootDir rev-parse "HEAD^{tree}").Trim()
    if ($FinalHead -ne $TargetHead -or $FinalTree -ne $TargetTree) {
        throw "PERF2.CONV BLOCKED: subject moved during gate"
    }
    $TrackedStatus = (& git -C $RootDir status --porcelain --untracked-files=no)
    if ($TrackedStatus) {
        throw "PERF2.CONV BLOCKED: tracked worktree changed during gate"
    }

    Write-Host "PERF2.CONV final HEAD=$FinalHead"
    Write-Host "PERF2.CONV final TREE=$FinalTree"
    Write-Host "PERF2.CONV tracked worktree clean=YES"
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    if ($null -eq $PreviousGodotBin) { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue } else { $env:GODOT_BIN = $PreviousGodotBin }
    if ($null -eq $PreviousGodotDoubleBin) { Remove-Item Env:\GODOT_DOUBLE_BIN -ErrorAction SilentlyContinue } else { $env:GODOT_DOUBLE_BIN = $PreviousGodotDoubleBin }
    if ($null -eq $PreviousTargetHead) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_HEAD -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_HEAD = $PreviousTargetHead }
    if ($null -eq $PreviousTargetTree) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_TREE -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_TREE = $PreviousTargetTree }
}

Write-Host "ECO.EVO7 PERF2.CONV STREAM1 + VIS4 candidate: PASS"
