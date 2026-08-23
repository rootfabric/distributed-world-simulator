param(
    [string]$GodotPath = $env:GODOT_BIN,
    [switch]$SkipBaseline
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"

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

if (-not $SkipBaseline) {
    Write-Host "=== ECO.EVO6 baseline regression ==="
    & (Join-Path $RootDir "RUN_ECO_EVO6_RULE_SELECTION_CONTINUATION.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) {
        throw "ECO.EVO6 baseline regression failed with exit code $LASTEXITCODE"
    }
}

Write-Host "=== ECO.EVO6-WATER rule pack + numeric predicates ==="
Invoke-PythonChecked -ArgsList @((Join-Path $RootDir "tests\research\ecology\test_evo5_rule_compiler.py"))
Invoke-PythonChecked -ArgsList @((Join-Path $RootDir "tests\research\ecology\test_evo6_water_rules.py"))

if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
    Write-Host "ECO.EVO6-WATER preflight: initializing Godot import/UID cache"
    & $GodotPath --headless --path $RootDir --import
    if ($LASTEXITCODE -ne 0) {
        throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE"
    }
}

$Tests = @(
    @{ Name = "water fitness math"; Script = "res://tests/research/ecology/eco_evo6_water_fitness_acceptance.gd" },
    @{ Name = "water-driven evolution causality"; Script = "res://tests/research/ecology/eco_evo6_water_evolution_acceptance.gd" }
)

foreach ($Test in $Tests) {
    Write-Host "=== ECO.EVO6-WATER $($Test.Name) ==="
    & $GodotPath --headless --path $RootDir --script $Test.Script
    if ($LASTEXITCODE -ne 0) {
        throw "$($Test.Name) failed with exit code $LASTEXITCODE"
    }
}

$PreviousVisualAutocap = $env:EVO6_WATER_LAB_AUTOCAP
try {
    Write-Host "=== ECO.EVO6-WATER visual observatory adapter ==="
    $env:EVO6_WATER_LAB_AUTOCAP = "1"
    & $GodotPath --headless --path $RootDir res://scenes/labs/ecology/eco_evo6_water_evolution_lab.tscn
    if ($LASTEXITCODE -ne 0) {
        throw "water visual observatory adapter failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($null -eq $PreviousVisualAutocap) {
        Remove-Item Env:\EVO6_WATER_LAB_AUTOCAP -ErrorAction SilentlyContinue
    }
    else {
        $env:EVO6_WATER_LAB_AUTOCAP = $PreviousVisualAutocap
    }
}

Write-Host "ECO.EVO6-WATER strong water rules + evolutionary divergence + visual adapter: PASS"
