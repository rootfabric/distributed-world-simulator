param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
$TempArtifact = Join-Path ([System.IO.Path]::GetTempPath()) ("evo6-r31-{0}-{1}.json" -f $PID, [Guid]::NewGuid().ToString("N"))

$PythonExe = $null
$PythonPrefix = @()
if (Get-Command py -ErrorAction SilentlyContinue) {
    $PythonExe = (Get-Command py).Source
    $PythonPrefix = @("-3")
}
elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $PythonExe = (Get-Command python).Source
}
else {
    throw "Python 3 not found (expected py -3 or python)"
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

function Invoke-PythonChecked {
    param([string[]]$ArgsList)
    & $PythonExe @PythonPrefix @ArgsList
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code $LASTEXITCODE`: $($ArgsList -join ' ')"
    }
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$PreviousOutcomePath = $env:EVO6_GENERATED_OUTCOMES_PATH
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== ECO.EVO6 R3.1 generated outcomes ==="
    Invoke-PythonChecked -ArgsList @((Join-Path $RootDir "tests\research\ecology\test_evo6_generated_outcomes.py"))
    Invoke-PythonChecked -ArgsList @(
        (Join-Path $RootDir "scripts\research\ecology\evo6_generated_outcomes_v1.py"),
        "--seed", "20260823",
        "--output", $TempArtifact
    )
    if (-not (Test-Path -LiteralPath $TempArtifact -PathType Leaf)) {
        throw "EVO6 generated outcome artifact was not produced"
    }
    $env:EVO6_GENERATED_OUTCOMES_PATH = $TempArtifact

    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        Write-Host "ECO.EVO6 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
    }

    $Tests = @(
        @{ Name = "P1B-S2 parent selection regression"; Script = "res://tests/research/ecology/eco_p1b_s2_spatial_selection_acceptance.gd" },
        @{ Name = "EVO6 R3.1 generated visual adapter"; Script = "res://tests/research/ecology/eco_evo6_r31_visual_adapter_acceptance.gd" },
        @{ Name = "EVO6 H1-H3 generated-rule selection bridge"; Script = "res://tests/research/ecology/eco_evo6_rule_selection_bridge_acceptance.gd" }
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
    if ($null -eq $PreviousOutcomePath) { Remove-Item Env:\EVO6_GENERATED_OUTCOMES_PATH -ErrorAction SilentlyContinue }
    else { $env:EVO6_GENERATED_OUTCOMES_PATH = $PreviousOutcomePath }
    Remove-Item -LiteralPath $TempArtifact -Force -ErrorAction SilentlyContinue
}

Write-Host "ECO.EVO6 R3.1 exact artifact digest: c2c49218cc04dffaf8b036b0b2986672559ff8884e4be54d2149b61ba45f0f67"
Write-Host "ECO.EVO6 selection surface digest: e3fbaee778ba54708057e623fb6e515b7de6e7eedd20248d2a3daad45d3fb6de"
Write-Host "ECO.EVO6 rule-language -> P1B selection/mutation continuation: PASS"
