param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "s0-spatial-substrate-summary.json"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

function Resolve-GodotExecutable {
    param([string]$RequestedPath)
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $Candidates += $RequestedPath }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
    $Candidates += @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot4", "godot")) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $Command) { $Candidates += $Command.Source }
    }
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Resolve-Path $Candidate).Path
        }
    }
    throw "Double-precision Godot was not found. Set GODOT_BIN or pass -GodotPath."
}

function Write-JsonFileAtomically {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 8,
        [int]$MaxReplaceAttempts = 20,
        [int]$RetryDelayMs = 25
    )

    $Directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $Directory = (Get-Location).Path
    }
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null

    $FileName = [IO.Path]::GetFileName($Path)
    $Suffix = "$PID.$([Guid]::NewGuid().ToString('N'))"
    $TemporaryPath = Join-Path $Directory ".$FileName.$Suffix.tmp"
    $BackupPath = Join-Path $Directory ".$FileName.$Suffix.bak"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $BackupCreated = $false

    try {
        $Json = $Value | ConvertTo-Json -Depth $Depth
        if ([string]::IsNullOrWhiteSpace($Json)) {
            throw "JSON serialization produced an empty summary"
        }
        $Payload = $Json + [Environment]::NewLine
        $Bytes = $Utf8NoBom.GetBytes($Payload)
        if ($Bytes.Length -le 0) {
            throw "JSON serialization produced a zero-byte summary"
        }

        $Stream = [IO.File]::Open(
            $TemporaryPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        try {
            $Stream.Write($Bytes, 0, $Bytes.Length)
            $Stream.Flush($true)
        }
        finally {
            $Stream.Dispose()
        }

        $TemporaryInfo = Get-Item -LiteralPath $TemporaryPath -ErrorAction Stop
        if ($TemporaryInfo.Length -le 0) {
            throw "Temporary summary is zero bytes: $TemporaryPath"
        }
        $TemporaryText = [IO.File]::ReadAllText($TemporaryPath, $Utf8NoBom)
        $null = $TemporaryText | ConvertFrom-Json -ErrorAction Stop

        $Replaced = $false
        for ($Attempt = 1; $Attempt -le $MaxReplaceAttempts; $Attempt++) {
            try {
                if ([IO.File]::Exists($Path)) {
                    if ([IO.File]::Exists($BackupPath)) {
                        [IO.File]::Delete($BackupPath)
                    }
                    [IO.File]::Replace($TemporaryPath, $Path, $BackupPath, $true)
                    $BackupCreated = [IO.File]::Exists($BackupPath)
                }
                else {
                    [IO.File]::Move($TemporaryPath, $Path)
                }
                $Replaced = $true
                break
            }
            catch {
                if ($Attempt -ge $MaxReplaceAttempts) {
                    throw
                }
                Start-Sleep -Milliseconds $RetryDelayMs
            }
        }
        if (-not $Replaced) {
            throw "Atomic summary replacement did not complete: $Path"
        }

        $FinalInfo = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($FinalInfo.Length -le 0) {
            throw "Final summary is zero bytes after atomic replacement: $Path"
        }
        $FinalText = [IO.File]::ReadAllText($Path, $Utf8NoBom)
        $null = $FinalText | ConvertFrom-Json -ErrorAction Stop

        if ($BackupCreated -and [IO.File]::Exists($BackupPath)) {
            [IO.File]::Delete($BackupPath)
            $BackupCreated = $false
        }
    }
    catch {
        if ($BackupCreated -and [IO.File]::Exists($BackupPath)) {
            try {
                if ([IO.File]::Exists($Path)) {
                    [IO.File]::Delete($Path)
                }
                [IO.File]::Move($BackupPath, $Path)
                $BackupCreated = $false
            }
            catch {
                Write-Warning "Failed to restore previous summary from $BackupPath"
            }
        }
        throw
    }
    finally {
        foreach ($CleanupPath in @($TemporaryPath, $BackupPath)) {
            if ([IO.File]::Exists($CleanupPath)) {
                try {
                    [IO.File]::Delete($CleanupPath)
                }
                catch {
                    Write-Warning "Failed to remove temporary summary file: $CleanupPath"
                }
            }
        }
    }
}


$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
$Tests = @(
    "res://tests/simulation/test_s0_spatial_substrate_contracts.gd",
    "res://tests/simulation/test_s0_spatial_substrate_integration.gd"
)
$Summary = [ordered]@{
    schema = "planet_simulator.s0_spatial_substrate_runner_summary.v1"
    checkpoint = "v16.9.0-simulation-s1-distributed-compute-fix1"
    build_id = "s1-distributed-compute-contracts-fix1"
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    finished_at_utc = $null
    godot = $Godot
    project_root = $ProjectRoot
    passed = $false
    steps = @()
}

function Save-Summary {
    $Summary.finished_at_utc = [DateTime]::UtcNow.ToString("o")
    Write-JsonFileAtomically -Value $Summary -Path $ReportPath
}

function Invoke-CheckedGodot {
    param([string]$Name, [string[]]$Arguments, [string]$Target)
    Write-Host ""; Write-Host "[$Name]" -ForegroundColor Cyan
    $Started = [DateTime]::UtcNow
    $Captured = @()
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false }
        & $Godot @Arguments 2>&1 | Tee-Object -Variable Captured | ForEach-Object { Write-Host $_ }
        $RawExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference }
    }
    $OutputText = ($Captured | Out-String)
    $HasFailureMarker = $OutputText -match '(?m): FAIL(?:\s|\()'
    $ExitCode = if ($RawExitCode -ne 0) { $RawExitCode } elseif ($HasFailureMarker) { 1 } else { 0 }
    $Summary.steps += [ordered]@{
        name = $Name
        target = $Target
        exit_code = $ExitCode
        duration_seconds = [Math]::Round(([DateTime]::UtcNow - $Started).TotalSeconds, 3)
        passed = ($ExitCode -eq 0)
    }
    Save-Summary
    if ($ExitCode -ne 0) { throw "$Name failed with exit code $ExitCode" }
}

try {
    Write-Host "Godot: $Godot"
    Write-Host "Checkpoint: v16.9.0-simulation-s1-distributed-compute-fix1"
    Invoke-CheckedGodot -Name "editor_import_parse" -Arguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit") -Target "res://"
    foreach ($Test in $Tests) {
        Invoke-CheckedGodot -Name ([IO.Path]::GetFileNameWithoutExtension($Test)) -Arguments @("--headless", "--path", $ProjectRoot, "--script", $Test) -Target $Test
    }
    $Summary.passed = $true
    Save-Summary
    Write-Host "S0 spatial substrate tests passed." -ForegroundColor Green
    Write-Host "Report: $ReportPath"
}
catch {
    $Summary.passed = $false
    Save-Summary
    Write-Host $_ -ForegroundColor Red
    exit 1
}
