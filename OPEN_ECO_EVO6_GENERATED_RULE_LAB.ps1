param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempArtifact = Join-Path ([System.IO.Path]::GetTempPath()) ("evo6-r31-lab-{0}-{1}.json" -f $PID, [Guid]::NewGuid().ToString("N"))

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

$PreviousOutcomePath = $env:EVO6_GENERATED_OUTCOMES_PATH
try {
    & $PythonExe @PythonPrefix (Join-Path $RootDir "scripts\research\ecology\evo6_generated_outcomes_v1.py") --seed 20260823 --output $TempArtifact
    if ($LASTEXITCODE -ne 0) { throw "EVO6 outcome generation failed with exit code $LASTEXITCODE" }
    $env:EVO6_GENERATED_OUTCOMES_PATH = $TempArtifact
    & $GodotPath --path $RootDir "res://scenes/labs/ecology/eco_evo6_generated_rule_fly_lab.tscn"
    if ($LASTEXITCODE -ne 0) { throw "EVO6 generated-rule flyover exited with code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousOutcomePath) { Remove-Item Env:\EVO6_GENERATED_OUTCOMES_PATH -ErrorAction SilentlyContinue }
    else { $env:EVO6_GENERATED_OUTCOMES_PATH = $PreviousOutcomePath }
    Remove-Item -LiteralPath $TempArtifact -Force -ErrorAction SilentlyContinue
}
