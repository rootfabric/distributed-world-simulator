param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $Global:PSNativeCommandUseErrorActionPreference = $false
}

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 PERF2.CONV BLOCKED: expected Godot '$Expected', got '$Actual'"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$PreviousGodotBin = $env:GODOT_BIN
$PreviousTargetHead = $env:ECO_PERF2_CONV_TARGET_HEAD
$PreviousTargetTree = $env:ECO_PERF2_CONV_TARGET_TREE
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $env:GODOT_BIN = $GodotPath
    $LocalHead = (git -C $RootDir rev-parse HEAD).Trim()
    $LocalTree = (git -C $RootDir rev-parse "HEAD^{tree}").Trim()
    $TargetHead = if ([string]::IsNullOrWhiteSpace($PreviousTargetHead)) { $LocalHead } else { $PreviousTargetHead }
    $TargetTree = if ([string]::IsNullOrWhiteSpace($PreviousTargetTree)) { $LocalTree } else { $PreviousTargetTree }
    if ($TargetTree -ne $LocalTree) {
        throw "PERF2.CONV BLOCKED: target TREE $TargetTree != local TREE $LocalTree"
    }
    if ($TargetHead -notmatch '^[0-9a-f]{40}

    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== PERF2.4 prerequisite transitive gate ==="
    & (Join-Path $RootDir "RUN_ECO_EVO7_PERF2_4_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "PERF2.4 prerequisite gate failed" }

    Write-Host "=== VIS4.9 prerequisite transitive gate ==="
    & (Join-Path $RootDir "RUN_ECO_EVO7_VIS4_9_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "VIS4.9 prerequisite gate failed" }

    Write-Host "=== PERF2.CONV integrated STREAM1 + VIS4 gate ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_perf2_conv_stream1_vis4_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "PERF2.CONV focused acceptance failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    if ($null -eq $PreviousGodotBin) { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue } else { $env:GODOT_BIN = $PreviousGodotBin }
    if ($null -eq $PreviousTargetHead) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_HEAD -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_HEAD = $PreviousTargetHead }
    if ($null -eq $PreviousTargetTree) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_TREE -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_TREE = $PreviousTargetTree }
}

Write-Host "ECO.EVO7 PERF2.CONV STREAM1 + VIS4 candidate: PASS"
 -or $TargetTree -notmatch '^[0-9a-f]{40}

    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== PERF2.4 prerequisite transitive gate ==="
    & (Join-Path $RootDir "RUN_ECO_EVO7_PERF2_4_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "PERF2.4 prerequisite gate failed" }

    Write-Host "=== VIS4.9 prerequisite transitive gate ==="
    & (Join-Path $RootDir "RUN_ECO_EVO7_VIS4_9_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "VIS4.9 prerequisite gate failed" }

    Write-Host "=== PERF2.CONV integrated STREAM1 + VIS4 gate ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_perf2_conv_stream1_vis4_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "PERF2.CONV focused acceptance failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    if ($null -eq $PreviousGodotBin) { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue } else { $env:GODOT_BIN = $PreviousGodotBin }
    if ($null -eq $PreviousTargetHead) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_HEAD -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_HEAD = $PreviousTargetHead }
    if ($null -eq $PreviousTargetTree) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_TREE -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_TREE = $PreviousTargetTree }
}

Write-Host "ECO.EVO7 PERF2.CONV STREAM1 + VIS4 candidate: PASS"
) {
        throw "PERF2.CONV BLOCKED: invalid target HEAD/TREE identity"
    }
    $env:ECO_PERF2_CONV_TARGET_HEAD = $TargetHead
    $env:ECO_PERF2_CONV_TARGET_TREE = $TargetTree
    Write-Host "PERF2.CONV local HEAD=$LocalHead"
    Write-Host "PERF2.CONV target HEAD=$TargetHead"
    Write-Host "PERF2.CONV target TREE=$TargetTree"

    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== PERF2.4 prerequisite transitive gate ==="
    & (Join-Path $RootDir "RUN_ECO_EVO7_PERF2_4_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "PERF2.4 prerequisite gate failed" }

    Write-Host "=== VIS4.9 prerequisite transitive gate ==="
    & (Join-Path $RootDir "RUN_ECO_EVO7_VIS4_9_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "VIS4.9 prerequisite gate failed" }

    Write-Host "=== PERF2.CONV integrated STREAM1 + VIS4 gate ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_perf2_conv_stream1_vis4_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "PERF2.CONV focused acceptance failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    if ($null -eq $PreviousGodotBin) { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue } else { $env:GODOT_BIN = $PreviousGodotBin }
    if ($null -eq $PreviousTargetHead) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_HEAD -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_HEAD = $PreviousTargetHead }
    if ($null -eq $PreviousTargetTree) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_TREE -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_TREE = $PreviousTargetTree }
}

Write-Host "ECO.EVO7 PERF2.CONV STREAM1 + VIS4 candidate: PASS"
