# Run only in a dedicated clean exact-subject checkout. Does not manage runners.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotBin,
    [Parameter(Mandatory)][string]$ExpectedHead,
    [Parameter(Mandatory)][string]$ExpectedTree,
    [string]$ExpectedHash = '',
    [string]$EvidenceDir = '',
    [string]$PythonBin = 'python'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 required' }
$Root = $PSScriptRoot
Set-Location -LiteralPath $Root
$GodotBin = (Resolve-Path -LiteralPath $GodotBin).Path
if (-not $EvidenceDir) { $EvidenceDir = Join-Path $Root ('artifacts/t16-' + [guid]::NewGuid().ToString('N')) }
$Out = [IO.Path]::GetFullPath($EvidenceDir)
if (Test-Path -LiteralPath $Out) {
    if (@(Get-ChildItem -LiteralPath $Out -Force).Count) { throw 'Evidence directory must be empty' }
} else { New-Item -ItemType Directory -Path $Out -Force | Out-Null }
$env:GODOT_SILENCE_ROOT_WARNING = '1'
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
$Utf8 = [Text.UTF8Encoding]::new($false)
$Fatal = 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:'
function GitText([string[]]$Arguments) {
    $text = & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('Git failed: ' + ($Arguments -join ' ')) }
    return (($text -join "`n").Trim())
}
function Write-Identity([string]$Name) {
    if (GitText @('status', '--porcelain=v1', '--untracked-files=no')) { throw 'TRACKED_TREE_DIRTY' }
    $head = GitText @('rev-parse', 'HEAD')
    $tree = GitText @('rev-parse', 'HEAD^{tree}')
    if ($head -cne $ExpectedHead -or $tree -cne $ExpectedTree) { throw 'SUBJECT_IDENTITY_MISMATCH' }
    $version = ((& $GodotBin --version) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0) { throw 'GODOT_VERSION_FAILED' }
    $sha = (Get-FileHash -LiteralPath $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($version -cne '4.7.1.stable.double.custom_build.a13da4feb') { throw 'GODOT_VERSION_MISMATCH' }
    if ($sha -cne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'GODOT_SHA_MISMATCH' }
    [IO.File]::WriteAllLines((Join-Path $Out $Name), @("HEAD=$head", "TREE=$tree", "GODOT_VERSION=$version", "GODOT_SHA256=$sha"), $Utf8)
}
function Run-Engine([string]$Name, [string[]]$Arguments) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $GodotBin
    $info.WorkingDirectory = $Root
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $Utf8
    $info.StandardErrorEncoding = $Utf8
    foreach ($arg in (@('--headless', '--path', $Root) + $Arguments)) { $info.ArgumentList.Add($arg) }
    $p = [Diagnostics.Process]::new()
    $p.StartInfo = $info
    try {
        if (-not $p.Start()) { throw "START_FAILED:$Name" }
        $stdout = $p.StandardOutput.ReadToEndAsync()
        $stderr = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(300000)) {
            $p.Kill($true) # only the process tree this invocation created
            $p.WaitForExit()
            [IO.File]::WriteAllText((Join-Path $Out "$Name.log"), $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult(), $Utf8)
            throw "ENGINE_TIMEOUT:$Name"
        }
        $text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $Out "$Name.log"), $text, $Utf8)
        if ($p.ExitCode -ne 0 -or $text -match $Fatal) { throw "ENGINE_FAILED:$Name" }
        Write-Host "$Name=PASS"
    } finally { $p.Dispose() }
}
Write-Identity 'identity-before.txt'
$cache = Join-Path $Root '.godot'
if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force }
Run-Engine 'import' @('--editor', '--import')
$script = 'res://tests/research/fabric_bake0/fabric_r5_2_t16_no_safe_bake_acceptance.gd'
Run-Engine 'parse' @('--check-only', '--script', $script)
foreach ($i in 1..3) { Run-Engine "sample-$i" @('--script', $script) }
$regressions = [ordered]@{
    't15' = 'fabric_r5_2_t15_local_damage_acceptance.gd'
    't14' = 'fabric_r5_2_t14_observation_refinement_acceptance.gd'
    't13-5' = 'fabric_r5_2_t13_5_shared_families_acceptance.gd'
    't13' = 'fabric_r5_2_t13_shared_instances_acceptance.gd'
    't12' = 'fabric_r5_2_t12_ship_acceptance.gd'
}
foreach ($name in $regressions.Keys) { Run-Engine "$name-regression" @('--script', ('res://tests/research/fabric_bake0/' + $regressions[$name])) }
& $PythonBin -m unittest discover -s tests/research/fabric_bake0 -p test_t16_evidence.py -v *> (Join-Path $Out 'python-tests.log')
if ($LASTEXITCODE -ne 0) { throw 'PYTHON_TESTS_FAILED' }
Write-Identity 'identity-after.txt'
$collectorArgs = @('scripts/research/fabric_bake0/collect_r5_2_t16_evidence.py', '--root', $Out)
if ($ExpectedHash) { $collectorArgs += @('--expected-hash', $ExpectedHash) }
& $PythonBin @collectorArgs
if ($LASTEXITCODE -ne 0) { throw 'T16_EVIDENCE_FAILED' }
Write-Host "EVIDENCE_DIR=$Out"
