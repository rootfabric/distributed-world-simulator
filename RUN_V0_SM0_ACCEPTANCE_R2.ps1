[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$Handoffs = 4,

    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,

    [string]$ProjectRoot = "",

    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",

    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

$InnerRunner = Join-Path $PSScriptRoot "RUN_V0_SM0_ACCEPTANCE_R1.ps1"
if (-not (Test-Path -LiteralPath $InnerRunner -PathType Leaf)) {
    throw "SM0 R1 runner is missing: $InnerRunner"
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

if ($Stop) {
    & $InnerRunner -Stop -ProjectRoot $ProjectRoot -GodotExe $GodotExe
    exit $LASTEXITCODE
}

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) {
    throw "git status failed for $ProjectRoot"
}
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0 acceptance requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")"
}

$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
if ($LASTEXITCODE -ne 0) {
    throw "Unable to enumerate pre-existing untracked UID sidecars."
}
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) {
    $UidBeforeSet[[string]$RelativeUid] = $true
}

function Invoke-Sm0CompileCheck {
    param([string]$ScriptPath)

    Write-Host "[SM0] Compile check: $ScriptPath"
    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe `
            --headless `
            --path $ProjectRoot `
            --check-only `
            --script $ScriptPath
        $CompileExit = $LASTEXITCODE
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($CompileExit -ne 0) {
        throw "SM0 compile check failed: $ScriptPath (exit $CompileExit)"
    }
}

function Invoke-Sm0ScriptTest {
    param([string]$ScriptPath, [string]$Label)

    Write-Host "[SM0] Running $Label..."
    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe `
            --headless `
            --path $ProjectRoot `
            --script $ScriptPath
        $TestExit = $LASTEXITCODE
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($TestExit -ne 0) {
        throw "SM0 $Label failed: $ScriptPath (exit $TestExit)"
    }
}

$Forward = @{
    Handoffs = $Handoffs
    ProjectRoot = $ProjectRoot
    GodotExe = $GodotExe
    TimeoutSeconds = $TimeoutSeconds
    AllowDirty = $true
}
if ($Final) { $Forward["Final"] = $true }
if ($Restart) { $Forward["Restart"] = $true }

$InnerExit = 1
try {
    $CompileScripts = @(
        "res://scripts/runtime/networked_gameplay/multiplayer_gameplay_authority_service.gd",
        "res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd",
        "res://scripts/runtime/seamless/sm0/sm0_contracts.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_v2.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_hardened.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_network_delay.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
        "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd",
        "res://scripts/runtime/seamless/sm0/sm0_automated_client_node_p4_hardened.gd",
        "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd",
        "res://scripts/runtime/seamless/sm0/sm0_manual_client_node.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_handoff_import.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p4_hardening.gd"
    )
    foreach ($CompileScript in $CompileScripts) {
        Invoke-Sm0CompileCheck -ScriptPath $CompileScript
    }
    Write-Host "[SM0] Compile-smoke PASS ($($CompileScripts.Count) scripts)."

    Invoke-Sm0ScriptTest `
        -ScriptPath "res://tests/runtime/seamless/sm0/test_sm0_handoff_import.gd" `
        -Label "handoff motion import regression"

    Invoke-Sm0ScriptTest `
        -ScriptPath "res://tests/runtime/seamless/sm0/test_sm0_p4_hardening.gd" `
        -Label "P4 hardening replay/fence regression"

    & $InnerRunner @Forward
    $InnerExit = $LASTEXITCODE
}
finally {
    $UidAfter = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
    if ($LASTEXITCODE -eq 0) {
        foreach ($RelativeUid in $UidAfter) {
            $RelativeUidText = [string]$RelativeUid
            if (-not $UidBeforeSet.ContainsKey($RelativeUidText)) {
                $GeneratedPath = Join-Path $ProjectRoot $RelativeUidText
                if (Test-Path -LiteralPath $GeneratedPath -PathType Leaf) {
                    Remove-Item -LiteralPath $GeneratedPath -Force -ErrorAction SilentlyContinue
                    Write-Host "[SM0] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) {
    throw "git status failed after SM0 acceptance"
}

$BeforeText = $StatusBefore -join "`n"
$AfterText = $StatusAfter -join "`n"
if ($BeforeText -ne $AfterText) {
    Write-Error "SM0 acceptance changed the source worktree. Before:`n$BeforeText`nAfter:`n$AfterText" -ErrorAction Continue
    exit 1
}

exit $InnerExit
