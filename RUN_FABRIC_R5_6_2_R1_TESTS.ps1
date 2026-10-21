[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$GodotBin,
    [Parameter(Mandatory)][string]$ExpectedHead,
    [Parameter(Mandatory)][string]$ExpectedTree,
    [string]$EvidenceDir = '',
    [string]$PythonBin = 'python'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'POWERSHELL_7_REQUIRED' }
$Root = $PSScriptRoot
Set-Location $Root
$GodotBin = (Resolve-Path $GodotBin).Path
$Utf8 = [Text.UTF8Encoding]::new($false)
$Fatal = 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:'
if (!$EvidenceDir) { $EvidenceDir = Join-Path $Root ('artifacts/r562-r1-'+[guid]::NewGuid().ToString('N')) }
$Out = [IO.Path]::GetFullPath($EvidenceDir)
if (Test-Path $Out) {
    if (@(Get-ChildItem $Out -Force).Count -gt 0) { throw 'EVIDENCE_DIR_NOT_EMPTY' }
} else { New-Item -ItemType Directory -Path $Out -Force | Out-Null }
$env:GODOT_SILENCE_ROOT_WARNING = '1'
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
function GitText([string[]]$Arguments) {
    $rows = & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'GIT_COMMAND_FAILED' }
    return (($rows -join "`n").Trim())
}
function Identity([string]$Name) {
    if (GitText @('status','--porcelain=v1','--untracked-files=no')) { throw 'TRACKED_TREE_DIRTY' }
    $head = GitText @('rev-parse','HEAD')
    $tree = GitText @('rev-parse','HEAD^{tree}')
    if ($head -cne $ExpectedHead -or $tree -cne $ExpectedTree) { throw 'FROZEN_PRODUCT_DRIFT' }
    $version = ((& $GodotBin --version) -join "`n").Trim()
    $sha = (Get-FileHash $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($version -cne '4.7.1.stable.double.custom_build.a13da4feb') { throw 'GODOT_VERSION_MISMATCH' }
    if ($sha -cne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'GODOT_SHA_MISMATCH' }
    [IO.File]::WriteAllLines((Join-Path $Out $Name), @(
        "HEAD=$head", "TREE=$tree", "GODOT_VERSION=$version", "GODOT_SHA256=$sha"
    ), $Utf8)
}
function RunGodot([string]$Name, [string[]]$Args) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $GodotBin
    $info.WorkingDirectory = $Root
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $Utf8
    $info.StandardErrorEncoding = $Utf8
    foreach ($arg in (@('--headless','--path',$Root) + $Args)) { $info.ArgumentList.Add($arg) }
    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $info
    try {
        if (!$proc.Start()) { throw "START_FAILED:$Name" }
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        if (!$proc.WaitForExit(1800000)) {
            $proc.Kill($true)
            $proc.WaitForExit()
            throw "TIMEOUT:$Name"
        }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $Out "$Name.log"), $output, $Utf8)
        if ($proc.ExitCode -ne 0 -or $output -match $Fatal) { throw "FAILED:$Name" }
        Write-Host "$Name=PASS"
    } finally { $proc.Dispose() }
}
# Godot normally stores user:// under the real user's roaming APPDATA.
# These changes apply ONLY to spawned test/editor processes, never the
# production game profile. Always restore the caller's environment.
$SavedUserEnv = @{}
foreach ($variable in @('APPDATA','LOCALAPPDATA')) {
    $SavedUserEnv[$variable] = [Environment]::GetEnvironmentVariable($variable, 'Process')
}
try {
    $UserRoot = Join-Path $Out 'isolated-user'
    $Roaming = Join-Path $UserRoot 'Roaming'
    $Local = Join-Path $UserRoot 'Local'
    New-Item -ItemType Directory -Force -Path $Roaming,$Local | Out-Null
    $env:APPDATA = $Roaming
    $env:LOCALAPPDATA = $Local

    Identity 'identity-before.txt'
    if (Test-Path '.godot') { Remove-Item '.godot' -Force -Recurse }
    # Recovery mode avoids activating editor plugins/tool scripts before the
    # global GDScript class cache exists. BOTH phases remain strict: no error
    # filtering, no ignored import failures, same project/Godot binary.
    RunGodot 'import-recovery' @('--editor','--import','--recovery-mode')
    RunGodot 'import' @('--editor','--import')
    $T = 'res://tests/research/fabric_bake0'
    RunGodot 'parse-lifecycle' @('--check-only','--script',"$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
    1..3 | ForEach-Object { RunGodot "lifecycle-$_" @('--script',"$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd") }
    RunGodot 'r2-regression' @('--script',"$T/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd")
    RunGodot 'com-recovery-regression' @('--script',"$T/fabric_r5_6_1_r2_com_recovery_acceptance.gd")
    RunGodot 'r1-regression' @('--script',"$T/fabric_r5_6_1_canonical_delta_acceptance.gd")
    RunGodot 'bridge4-regression' @('--quit-after','2','--script','res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd')
    Identity 'identity-after.txt'
    & $PythonBin 'scripts/research/fabric_bake0/collect_r5_6_2_r1_evidence.py' '--root' $Out '--expected-head' $ExpectedHead '--expected-tree' $ExpectedTree '--platform' 'windows'
    if ($LASTEXITCODE -ne 0) { throw 'R562_R1_STRICT_COLLECTOR_FAILED' }
    $files = @(Get-ChildItem $Out -File | Where-Object { $_.Name -ne 'SHA256SUMS' } | Sort-Object Name)
    $hashes = $files | ForEach-Object { "$( (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() )  $($_.Name)" }
    [IO.File]::WriteAllLines((Join-Path $Out 'SHA256SUMS'), @($hashes), $Utf8)
    Write-Host 'FABRIC_R562_R1_WINDOWS_EXACT=PASS'
    Write-Host "EVIDENCE_DIR=$Out"
} finally {
    foreach ($variable in @('APPDATA','LOCALAPPDATA')) {
        [Environment]::SetEnvironmentVariable($variable,$SavedUserEnv[$variable],'Process')
    }
}
