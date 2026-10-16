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
if (!$EvidenceDir) { $EvidenceDir = Join-Path $Root ('artifacts/r56-' + [guid]::NewGuid().ToString('N')) }
$Out = [IO.Path]::GetFullPath($EvidenceDir)
if (Test-Path $Out) {
    if (@(Get-ChildItem $Out -Force).Count -gt 0) { throw 'EVIDENCE_DIR_NOT_EMPTY' }
} else { New-Item -ItemType Directory -Path $Out -Force | Out-Null }
$env:GODOT_SILENCE_ROOT_WARNING = '1'
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
$Utf8 = [Text.UTF8Encoding]::new($false)
$Fatal = 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:'
function GitText([string[]]$Arguments) {
    $rows = & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'GIT_COMMAND_FAILED' }
    return (($rows -join "`n").Trim())
}
function Identity([string]$Filename) {
    if (GitText @('status','--porcelain=v1','--untracked-files=no')) { throw 'TRACKED_TREE_DIRTY' }
    $head = GitText @('rev-parse','HEAD')
    $tree = GitText @('rev-parse','HEAD^{tree}')
    if ($head -cne $ExpectedHead -or $tree -cne $ExpectedTree) { throw 'PRODUCT_IDENTITY_MISMATCH' }
    $version = ((& $GodotBin --version) -join "`n").Trim()
    $sha = (Get-FileHash $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($version -cne '4.7.1.stable.double.custom_build.a13da4feb') { throw 'GODOT_VERSION_MISMATCH' }
    if ($sha -cne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'GODOT_SHA_MISMATCH' }
    [IO.File]::WriteAllLines((Join-Path $Out $Filename), @(
        "HEAD=$head", "TREE=$tree", "GODOT_VERSION=$version", "GODOT_SHA256=$sha"
    ), $Utf8)
}
function RunGodot([string]$Name, [string[]]$Arguments) {
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
    foreach ($arg in ($common + $Arguments)) { $start.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (!$process.Start()) { throw "START_FAILED:$Name" }
        $o = $process.StandardOutput.ReadToEndAsync()
        $e = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(600000)) {
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
$sample = 'res://tests/research/fabric_bake0/fabric_r5_6_1_canonical_delta_acceptance.gd'
RunGodot 'parse' @('--check-only','--script',$sample)
1..3 | ForEach-Object { RunGodot "sample-$_" @('--script',$sample) }
RunGodot 'bridge4-regression' @('--script','res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd')
Identity 'identity-after.txt'
& $PythonBin 'scripts/research/fabric_bake0/collect_r5_6_1_evidence.py' '--root' $Out '--expected-head' $ExpectedHead '--expected-tree' $ExpectedTree
if ($LASTEXITCODE -ne 0) { throw 'R56_STRICT_COLLECTOR_FAILED' }
$items = @(Get-ChildItem $Out -File | Where-Object { $_.Name -ne 'SHA256SUMS' } | Sort-Object Name)
$hashes = $items | ForEach-Object { "$( (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() )  $($_.Name)" }
[IO.File]::WriteAllLines((Join-Path $Out 'SHA256SUMS'), @($hashes), $Utf8)
Write-Host 'R5_6_1_EXACT=PASS'
Write-Host "EVIDENCE_DIR=$Out"
