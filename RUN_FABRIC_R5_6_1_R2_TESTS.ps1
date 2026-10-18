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
if (!$EvidenceDir) { $EvidenceDir = Join-Path $Root ('artifacts/r56-r2-'+[guid]::NewGuid().ToString('N')) }
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
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $GodotBin
    $start.WorkingDirectory = $Root
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $Utf8
    $start.StandardErrorEncoding = $Utf8
    $common = @('--headless','--path',$Root)
    if ($Name -eq 'bridge4-regression') { $common = @('--headless','--quit-after','2','--path',$Root) }
    foreach ($arg in ($common + $Args)) { $start.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (!$process.Start()) { throw "START_FAILED:$Name" }
        $o = $process.StandardOutput.ReadToEndAsync()
        $e = $process.StandardError.ReadToEndAsync()
        # 100k exact snapshot validation can take longer on a Windows host.
        if (!$process.WaitForExit(1800000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "TIMEOUT:$Name"
        }
        $text = $o.GetAwaiter().GetResult() + $e.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $Out "$Name.log"), $text, $Utf8)
        if ($process.ExitCode -ne 0 -or $text -match $Fatal) { throw "FAILED:$Name" }
        Write-Host "$Name=PASS"
    } finally { $process.Dispose() }
}
Identity 'identity-before.txt'
if (Test-Path '.godot') { Remove-Item '.godot' -Force -Recurse }
RunGodot 'import' @('--editor','--import')
$Tests = 'res://tests/research/fabric_bake0'
RunGodot 'parse-r2' @('--check-only','--script',"$Tests/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd")
RunGodot 'parse-scale' @('--check-only','--script',"$Tests/fabric_r5_6_1_r2_dynamic_index_scale.gd")
RunGodot 'parse-numeric' @('--check-only','--script',"$Tests/fabric_r5_6_1_r2_numeric_conditioning_acceptance.gd")
RunGodot 'parse-r1' @('--check-only','--script',"$Tests/fabric_r5_6_1_canonical_delta_acceptance.gd")
RunGodot 'parse-r1-narrow' @('--check-only','--script',"$Tests/fabric_r5_6_1_r1_source_admission_acceptance.gd")
1..3 | ForEach-Object { RunGodot "r2-acceptance-$_" @('--script',"$Tests/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd") }
RunGodot 'r2-scale' @('--script',"$Tests/fabric_r5_6_1_r2_dynamic_index_scale.gd")
RunGodot 'r2-numeric' @('--script',"$Tests/fabric_r5_6_1_r2_numeric_conditioning_acceptance.gd")
RunGodot 'r1-acceptance' @('--script',"$Tests/fabric_r5_6_1_canonical_delta_acceptance.gd")
RunGodot 'r1-narrow-admission' @('--script',"$Tests/fabric_r5_6_1_r1_source_admission_acceptance.gd")
RunGodot 'bridge4-regression' @('--script','res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd')
Identity 'identity-after.txt'
& $PythonBin 'scripts/research/fabric_bake0/collect_r5_6_1_r2_evidence.py' '--root' $Out '--expected-head' $ExpectedHead '--expected-tree' $ExpectedTree
if ($LASTEXITCODE -ne 0) { throw 'R56_R2_STRICT_COLLECTOR_FAILED' }
& $PythonBin 'scripts/research/fabric_bake0/test_r5_6_1_r2_evidence_collector.py' '--root' $Out
if ($LASTEXITCODE -ne 0) { throw 'R56_R2_TAMPER_MATRIX_FAILED' }
$items = @(Get-ChildItem $Out -File | Where-Object { $_.Name -ne 'SHA256SUMS' } | Sort-Object Name)
$hashes = $items | ForEach-Object { "$( (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() )  $($_.Name)" }
[IO.File]::WriteAllLines((Join-Path $Out 'SHA256SUMS'), @($hashes), $Utf8)
Write-Host 'FABRIC_R56_R2_EXACT=PASS'
Write-Host "EVIDENCE_DIR=$Out"
