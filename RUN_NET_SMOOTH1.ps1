[CmdletBinding()]
param(
    [ValidateSet('focused','headless','gui')][string] $Mode = 'focused',
    [string] $GodotConsole = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe',
    [string] $OutputDirectory = '',
    [double] $DurationSeconds = 120,
    [double] $WarmupSeconds = 20,
    [double] $StartupTimeoutSeconds = 240,
    [string] $AssetSource = '',
    [ValidateSet('async','sync')][string] $CheckpointMode = 'async',
    [string] $NetworkProfile = 'LOCAL',
    [ValidateSet('local','seam-stress','r31-reconnect-roundtrip')][string] $Scenario = 'local',
    [ValidateSet('','server','a','b')][string] $InjectStallRole = '',
    [int] $InjectStallMs = 250,
    [switch] $IncludeProcessTests,
    [switch] $SkipImport
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if (-not (Test-Path -LiteralPath $GodotConsole -PathType Leaf)) {
    throw "Canonical double Godot not found: $GodotConsole"
}
$python = Get-Command python -ErrorAction Stop
if ($AssetSource) {
    # Copy only into the external, ignored asset directory of this worktree.
    # Reject accidental replacement; use a fresh worktree for another provider.
    $source = (Resolve-Path -LiteralPath $AssetSource).Path
    $destination = Join-Path $repo 'assets\external\quaternius'
    if (Test-Path -LiteralPath $destination) {
        throw "Asset destination exists: $destination. Re-run without -AssetSource or use a fresh worktree."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse
}
$argsList = @(
    (Join-Path $repo 'tools\net_smooth1\run_net_smooth1.py'),
    '--godot', $GodotConsole, '--mode', $Mode,
    '--duration', [string]$DurationSeconds, '--warmup', [string]$WarmupSeconds,
    '--startup-timeout', [string]$StartupTimeoutSeconds,
    '--checkpoint-mode', $CheckpointMode, '--profile', $NetworkProfile, '--scenario', $Scenario
)
if ($OutputDirectory) { $argsList += @('--output', $OutputDirectory) }
if ($IncludeProcessTests) { $argsList += '--include-process-tests' }
if ($SkipImport) { $argsList += '--skip-import' }
if ($InjectStallRole) { $argsList += @('--inject-stall-role', $InjectStallRole, '--inject-stall-ms', [string]$InjectStallMs) }
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
& $python.Source @argsList
$code = $LASTEXITCODE
if ($null -eq $code) { throw 'NET_SMOOTH1_NO_EXIT_CODE' }
# 0=PASS scoped evidence; 1=detected failure; 2=inconclusive harness/evidence.
# Never turn an intentional fault-injection FAIL into a normal green run.
exit $code
