param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [switch]$FocusedOnly,
    [switch]$IncludeTwoClientProcess
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = (Resolve-Path $GodotPath).Path

function Invoke-PowerShellParseCheck {
    param([string]$Name, [string]$Path)
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $Tokens = $null
    $ParseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$Tokens,
        [ref]$ParseErrors
    ) | Out-Null
    if ($null -ne $ParseErrors -and @($ParseErrors).Count -gt 0) {
        $Messages = @($ParseErrors | ForEach-Object { $_.Message }) -join "; "
        throw "$Name emitted PowerShell parse errors: $Messages"
    }
    Write-Host "${Name}: PASS" -ForegroundColor Green
}

function Invoke-GodotCheck {
    param([string]$Name, [string[]]$Arguments)
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $PreviousErrorActionPreference = $ErrorActionPreference
    $PreviousBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $ErrorActionPreference = "Continue"
        $Output = @(& $Godot @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -eq $PreviousBreakpoint) {
            Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
        }
        else {
            $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpoint
        }
    }
    foreach ($Line in $Output) { Write-Host $Line }
    $Text = ($Output | ForEach-Object { $_.ToString() }) -join "`n"
    foreach ($Pattern in @("SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to load script")) {
        if ($Text.Contains($Pattern)) {
            throw "$Name emitted fatal Godot script diagnostics: $Pattern"
        }
    }
    if ($ExitCode -ne 0) {
        throw "$Name failed with exit code $ExitCode"
    }
    Write-Host "${Name}: PASS" -ForegroundColor Green
}

Write-Host "M7 FIX10 sequence-aware reconciliation validation" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

Invoke-PowerShellParseCheck -Name "M7 owner-authority diagnostic PowerShell parse" -Path (
    Join-Path $ProjectRoot "RUN_M7_OWNER_AUTHORITY_DIAGNOSTIC.ps1"
)

Invoke-GodotCheck -Name "FIX10 editor import/composition" -Arguments @(
    "--headless", "--editor", "--path", $ProjectRoot, "--quit"
)

Invoke-GodotCheck -Name "M7 owner-authoritative movement boundary" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_owner_movement_authority.gd"
)

Invoke-GodotCheck -Name "M7 owner-authority item drop + same-revision rollback" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_owner_authority_item_drop_projection.gd"
)

Invoke-GodotCheck -Name "FIX10 fix7b arrival-paced authority input playout" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix7b_arrival_playout.gd"
)

Invoke-GodotCheck -Name "FIX10 fix6 ACK phase semantics" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix6_ack_phase_semantics.gd"
)

Invoke-GodotCheck -Name "FIX10 fix8 owner ACK fast confirmation" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix8_owner_ack_fast_confirm.gd"
)

Invoke-GodotCheck -Name "FIX10 fix6 one-sequence-per-fixed-tick input latch" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix6_semantic_input_latch.gd"
)

Invoke-GodotCheck -Name "FIX10 fix6 semantic cadence + local presentation ownership" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix6_cadence_presentation.gd"
)

Invoke-GodotCheck -Name "FIX10 fix6 remote snapshot guard" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix6_remote_snapshot_guard.gd"
)

Invoke-GodotCheck -Name "FIX10 fix7 render-rate local presentation" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix10_fix7_render_presentation.gd"
)

Invoke-GodotCheck -Name "FIX10 fix5 composite ACK semantic identity" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix5.gd"
)

Invoke-GodotCheck -Name "FIX10 fix4 ACK timeline + MTU headroom" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix4.gd"
)

Invoke-GodotCheck -Name "FIX10 fix3 remote continuity + ACK fallback" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix3.gd"
)

Invoke-GodotCheck -Name "FIX10 fix2 MTU preflight contracts" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10_fix2.gd"
)

Invoke-GodotCheck -Name "FIX10 focused sequence-aware reconciliation" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_sequence_reconciliation_fix10.gd"
)

Invoke-GodotCheck -Name "FIX9 frame-budget regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_client_frame_budget_fix9.gd"
)

Invoke-GodotCheck -Name "FIX8 prediction-clock regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_prediction_clock_fix8.gd"
)

Invoke-GodotCheck -Name "NX4 prediction/reconciliation regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_nx4_client_prediction_reconciliation.gd"
)

if (-not $FocusedOnly) {
    Write-Host ""
    Write-Host "[FIX9 + FIX8 + FIX7 + FIX6 + FIX5 + accepted network/inventory baseline]" -ForegroundColor Cyan
    $Fix9Runner = Join-Path $ProjectRoot "VALIDATE_M7_CLIENT_FRAME_BUDGET_FIX9.ps1"
    if ($IncludeTwoClientProcess) {
        & $Fix9Runner -GodotPath $Godot -IncludeTwoClientProcess
    }
    else {
        & $Fix9Runner -GodotPath $Godot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "M7 FIX9/full accepted baseline failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "M7 FIX10 sequence-aware reconciliation validation passed." -ForegroundColor Green
if ($FocusedOnly) {
    Write-Host "FocusedOnly parse-checks the owner-authority diagnostic, validates OWNER_AUTHORITATIVE_VALIDATED movement plus server-authoritative item drop/same-revision prediction rollback, then the existing FIX10/FIX9/FIX8/NX4 regressions." -ForegroundColor Yellow
}
elseif (-not $IncludeTwoClientProcess) {
    Write-Host "Run with -IncludeTwoClientProcess before manual acceptance." -ForegroundColor Yellow
}
Write-Host "Final FIX10 server-predicted acceptance remains unchanged until owner-authority visual diagnostics are explicitly accepted." -ForegroundColor Yellow
Write-Host "Owner movement target: local transform is authored by the owning client, PLAYER_STATE is validated by the server and relayed through the existing remote snapshot/interpolation path; ownership/items/world authority remain server-side." -ForegroundColor Yellow
Write-Host "Item projection target: optimistic item presentation may change without changing authoritative revision; rejected predictions must reapply the same-revision canonical graph so ghost inventory ownership cannot survive rollback." -ForegroundColor Yellow
Write-Host "FIX10 fix8 target: exact or conservatively phase-equivalent authoritative ACKs confirm local owner prediction without rewind/replay or visible correction; real kinematic divergence keeps the authoritative correction path." -ForegroundColor Yellow
Write-Host "FIX10 fix7b target: client_tick is ACK identity/diagnostic metadata only; available movement input applies on the nearest server fixed tick; queue pressure recovery may never turn a dropped client_tick gap into artificial authority playout delay." -ForegroundColor Yellow
Write-Host "FIX10 fix7 target remains: local simulation stays deterministic 60 Hz while visible presentation updates every render frame." -ForegroundColor Yellow
Write-Host "FIX10 fix6 target remains: 30 Hz continuous semantic input with immediate responsiveness edges; monotonic semantic sequences; realtime movement snapshots are not suppressed merely because future input samples are pending; PREDICTION_ACK dispatch remains independent from canonical snapshot acceptance." -ForegroundColor Yellow
Write-Host "FIX10 fix5 target remains ack_mismatches=0 and sidecars_rejected=0." -ForegroundColor Yellow
Write-Host "FIX10 fix4 MTU target remains movement_snapshots_dropped_for_mtu=0 while max_unreliable_sent_bytes remains <=1350." -ForegroundColor Yellow
Write-Host "Remote presentation target: ~20 Hz movement snapshot cadence with no long moving HOLD/underrun streaks." -ForegroundColor Yellow
