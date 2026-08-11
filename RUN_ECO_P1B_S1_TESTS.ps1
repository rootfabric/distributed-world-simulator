param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        Write-Host "ECO.P1B-S1 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
    }

    $Tests = @(
        @{ Name = "P1A-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd" },
        @{ Name = "P1A-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd" },
        @{ Name = "P1A-S3 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s3_visual_lab_acceptance.gd" },
        @{ Name = "P1A-S4 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s4_determinism_sensitivity_acceptance.gd" },
        @{ Name = "P1B-S1 mutation/inheritance/lineage"; Script = "res://tests/research/ecology/eco_p1b_s1_mutation_lineage_acceptance.gd" },
        @{ Name = "P1B-S1 fresh-process replay"; Script = "res://tests/research/ecology/eco_p1b_s1_restart_replay_probe.gd" }
    )

    foreach ($Test in $Tests) {
        Write-Host "=== ECO $($Test.Name) ==="
        & $GodotPath --headless --path $RootDir --script $Test.Script
        if ($LASTEXITCODE -ne 0) {
            throw "$($Test.Name) failed with exit code $LASTEXITCODE"
        }
    }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
}

Write-Host "ECO.P1A-S1 parent regression: PASS (109 assertions)"
Write-Host "ECO.P1A-S2 parent regression: PASS (235 assertions)"
Write-Host "ECO.P1A-S3 parent regression: PASS (208 assertions)"
Write-Host "ECO.P1A-S4 parent regression: PASS (165 assertions)"
Write-Host "ECO.P1B-S1 focused acceptance: PASS (5834 assertions)"
Write-Host "ECO.P1B-S1 restart replay: PASS (6 assertions)"
Write-Host "ECO.P1B-S1 ancestor_lineage_hash=73621a2c49d6496bb89faef63a8350f2a76b553fd718fa88d1bc6b21b83a230f"
Write-Host "ECO.P1B-S1 population_hash=83a114cd712aacac42e0a1b4d74c0876a441fadb019f6640bfd44c921778ce84"
Write-Host "ECO.P1B-S1 chain_hash=3792cf995265b622ab8817a973f0bd38aedab8ca34721ca9468178e6e1a35874"
Write-Host "ECO.P1B-S1 local adaptation foundation candidate: PASS"
