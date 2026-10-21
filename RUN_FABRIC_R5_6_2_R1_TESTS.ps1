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
function RunGodot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$GateArgs,
        [ValidateRange(1, 1800)][int]$TimeoutSeconds = 1800
    )
    # $Args is an automatic PowerShell variable, NOT a safe parameter name.
    # Freeze an independent stage contract so missing flags cannot launch main.tscn.
    $Tests = 'res://tests/research/fabric_bake0'
    $ExpectedGates = @{
        'import-recovery' = @('--editor','--import','--recovery-mode')
        'import' = @('--editor','--import')
        'parse-lifecycle' = @('--check-only','--script',"$Tests/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
        'lifecycle-1' = @('--script',"$Tests/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
        'lifecycle-2' = @('--script',"$Tests/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
        'lifecycle-3' = @('--script',"$Tests/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
        'r2-regression' = @('--script',"$Tests/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd")
        'com-recovery-regression' = @('--script',"$Tests/fabric_r5_6_1_r2_com_recovery_acceptance.gd")
        'r1-regression' = @('--script',"$Tests/fabric_r5_6_1_canonical_delta_acceptance.gd")
        'bridge4-regression' = @('--quit-after','2','--script','res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd')
    }
    if (!$ExpectedGates.ContainsKey($Name)) { throw "UNKNOWN_GODOT_STAGE:$Name" }
    $expected = $ExpectedGates[$Name]
    if ($GateArgs.Count -ne $expected.Count) { throw "GODOT_STAGE_ARGV_MISMATCH:$Name" }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        if ($GateArgs[$index] -cne $expected[$index]) { throw "GODOT_STAGE_ARGV_MISMATCH:$Name" }
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $GodotBin
    $info.WorkingDirectory = $Root
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $Utf8
    $info.StandardErrorEncoding = $Utf8
    foreach ($argument in (@('--headless','--path',$Root) + $GateArgs)) {
        $info.ArgumentList.Add($argument)
    }
    # Audit the vector actually submitted to ProcessStartInfo, before Start.
    $launch = [ordered]@{
        schema = 'fabric.r562.windows_launch.v1'; stage = $Name
        executable = $info.FileName; working_directory = $info.WorkingDirectory
        argv = @($info.ArgumentList); timeout_seconds = $TimeoutSeconds
    }
    [IO.File]::WriteAllText((Join-Path $Out "$Name.argv.json"),
        (ConvertTo-Json -InputObject $launch -Depth 5), $Utf8)
    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $info
    $result = [ordered]@{
        schema = 'fabric.r562.windows_process.v1'; stage = $Name
        started = $false; exit_code = $null; timed_out = $false
        gameplay_detected = $false; verdict = 'START_FAILED'
    }
    try {
        if (!$proc.Start()) { throw "START_FAILED:$Name" }
        $result.started = $true
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        $result.timed_out = !$proc.WaitForExit($TimeoutSeconds * 1000)
        if ($result.timed_out) {
            if (!$proc.HasExited) { $proc.Kill($true) }
            $proc.WaitForExit()
        }
        # Drain and persist BOTH streams before raising timeout/failure.
        # The old runner threw before saving them on a 30-minute timeout.
        $stdoutText = $stdout.GetAwaiter().GetResult()
        $stderrText = $stderr.GetAwaiter().GetResult()
        $output = $stdoutText + $stderrText
        [IO.File]::WriteAllText((Join-Path $Out "$Name.stdout.log"), $stdoutText, $Utf8)
        [IO.File]::WriteAllText((Join-Path $Out "$Name.stderr.log"), $stderrText, $Utf8)
        [IO.File]::WriteAllText((Join-Path $Out "$Name.log"), $output, $Utf8)
        $result.exit_code = $proc.ExitCode
        $result.gameplay_detected = $Name -in @('import-recovery','import') -and
            $output -match '(?i)listen-host|user://worlds/|terrain_streaming_summary|spectator_predictive_stream'
        if ($result.timed_out) { $result.verdict = 'TIMEOUT'; throw "TIMEOUT:$Name" }
        if ($result.gameplay_detected) {
            $result.verdict = 'IMPORT_GAMEPLAY_SIDE_EFFECT'; throw "IMPORT_GAMEPLAY_SIDE_EFFECT:$Name"
        }
        if ($proc.ExitCode -ne 0 -or $output -match $Fatal) {
            $result.verdict = 'FAILED'; throw "FAILED:$Name"
        }
        $result.verdict = 'PASS'
        Write-Host "$Name=PASS"
    } finally {
        [IO.File]::WriteAllText((Join-Path $Out "$Name.process.json"),
            (ConvertTo-Json -InputObject $result -Depth 5), $Utf8)
        $proc.Dispose()
    }
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
    RunGodot -Name 'import-recovery' -GateArgs @('--editor','--import','--recovery-mode')
    RunGodot -Name 'import' -GateArgs @('--editor','--import')
    foreach ($stage in @('import-recovery','import')) {
        $text = [IO.File]::ReadAllText((Join-Path $Out "$stage.log"),$Utf8)
        if ($text -match '(?i)listen-host|user://worlds/|terrain_streaming_summary|spectator_predictive_stream') { throw "IMPORT_GAMEPLAY_SIDE_EFFECT:$stage" }
    }
    if (@(Get-ChildItem -Path $UserRoot -Directory -Recurse -ErrorAction Stop |
        Where-Object { $_.Name -ceq 'worlds' }).Count -ne 0) {
        throw 'IMPORT_OPENED_GAME_WORLD'
    }
    $T = 'res://tests/research/fabric_bake0'
    RunGodot -Name 'parse-lifecycle' -GateArgs @('--check-only','--script',"$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd")
    1..3 | ForEach-Object { RunGodot -Name "lifecycle-$_" -GateArgs @('--script',"$T/fabric_r5_6_2_r1_lifecycle_acceptance.gd") }
    RunGodot -Name 'r2-regression' -GateArgs @('--script',"$T/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd")
    RunGodot -Name 'com-recovery-regression' -GateArgs @('--script',"$T/fabric_r5_6_1_r2_com_recovery_acceptance.gd")
    RunGodot -Name 'r1-regression' -GateArgs @('--script',"$T/fabric_r5_6_1_canonical_delta_acceptance.gd")
    RunGodot -Name 'bridge4-regression' -GateArgs @('--quit-after','2','--script','res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd')
    Identity 'identity-after.txt'
    $ReceiptCount = @(Get-ChildItem -Path $UserRoot -Recurse -File -Filter 'fabric_r562_r1_*.bin').Count
    if ($ReceiptCount -ne 42) { throw "USERDATA_SANDBOX_RECEIPTS_MISSING:$ReceiptCount" }
    [IO.File]::WriteAllLines((Join-Path $Out 'isolation.txt'), @(
        "RECEIPTS_IN_SANDBOX=$ReceiptCount", 'LIVE_WORLD_LOGS=0'
    ), $Utf8)
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
